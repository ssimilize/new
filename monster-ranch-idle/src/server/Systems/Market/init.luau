--[[
	Market (update 1.3 · Market Day, ARCHITECTURE §8): asynchronous listings across every
	server. Rules and tuning are in Config.Market; pure listing rules in Listing.luau.

	Nothing is ever duplicated or lost, even when a server dies or a DataStore write lands
	but reports failure. Every cross-server step follows the same pattern:
	  1. record the intent as a task in the player's own profile (private `outbox`) and
	     ctx:SaveNow — the saved profile now says what is about to happen;
	  2. do the external write (Services.Market);
	  3. resolve: apply the result and drop the task in one profile change. When the write's
	     outcome is unknown, a fresh read (an Update whose transform writes nothing) decides;
	     when even that fails the task stays saved and is resolved on the next sync, on any
	     server, after a crash or a rejoin.

	Tasks: list   { listing, itemKind, item }          escrowed item until Create is confirmed
	       settle { listing, token, price, key }       coins charged until the sale is confirmed
	       close  { listing, token, reason }           cancel / expiry until confirmed
	       mail   { userId, entry }                    a MailAdd to retry
	A listing only leaves "open" inside Services.Market.Update (atomic, with a per-request
	token), so exactly one buyer wins across all servers.

	Mail is two-phase and deduplicated: every entry has a deterministic id ("sale:<listing>",
	"bought:<listing>", "return:<listing>"); MailAdd skips ids it has seen, and collection is
	MailPeek → apply + remember the ids (`mailSeen`) + SaveNow → MailAck. Entries that don't
	fit (full ranch) stay in the mailbox and show in session.Market.mail.

	Market.Buy also needs the "market" unlock (alts below Ranch Level 10 can't move coins),
	and one purchase per player at a time. Browse results are cached per query for
	BrowseCacheSeconds; expired listings are filtered at read time.

	Save section (profile.Market), version 2:
	  listings = { listingId }                          -- this player's open listings
	  stats    = { sold, bought, earned, spent }
	  seq      = number                                 -- private: listing id counter
	  outbox   = { task }                               -- private: see above
	  mailSeen = { mailId }                             -- private: applied, maybe not yet acked
	Session (session.Market): { mail = { coins, items = { { kind, key, reason, item = ItemView } } } }

	Actions: Market.List, Cancel, Buy, Browse, Mine, Collect. Event: Market.MailCollected.
	Bus: publishes MarketListed, MarketBought (buyer) and MarketSold (nil, buyer's server).
	Public API: Market:Sync(player) -> summary? (tests / shutdown), Market:Flush().

	Other systems' mail (glow-up L: gifts, invite rewards) rides the same mailbox:
	  Market:RegisterMail(kind, fn(player, entry) -> boolean)   -- in Start(); true = done (acked)
	  Market:Send(owner, userId, entry) -> boolean                -- saved outbox task first, then MailAdd
	An entry of a registered kind is handed to its handler on collection; false leaves it in the
	mailbox for the next sync (e.g. no room). Entry ids must be deterministic, like the market's.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local Listing = require(script.Listing)

local Market = {
	Name = "Market",
	Dependencies = { "Currency", "Progression", "Monsters" },
	OptionalDependencies = { "Eggs", "Clubs" },
}

Market.Profile = {
	Version = 2,
	Default = function()
		return { listings = {}, stats = { sold = 0, bought = 0, earned = 0, spent = 0 }, seq = 0, outbox = {}, mailSeen = {} }
	end,
	Migrate = function(section, fromVersion)
		if fromVersion < 2 then
			section.mailSeen = section.mailSeen or {}
			local kept = {}
			for _, task in section.outbox or {} do
				if task.kind == "mail" then
					table.insert(kept, task)
				end
			end
			section.outbox = kept
		end
		return section
	end,
	Private = { "seq", "outbox", "mailSeen" },
}

local BUSY = "The market is busy. Try again"

local ctx
local Config, Cfg
local Currency, Progression, Monsters

local known = {} -- [player] = { [listingId] = expiresAt } open listings this server has read
local syncing = {} -- [player] = true while a sync runs
local buying = {} -- [player] = true while a purchase runs (one at a time)
local flushing = false
local cache = {} -- [query] = { at, list } browse results
local tokens = 0
local MAIL_SEEN_MAX = 200
local mailHandlers = {} -- [entry.kind] = fn(player, entry) -> boolean (other systems' mail)

-- Helpers -----------------------------------------------------------------------------------

local function displayName(player): string
	return player.DisplayName or player.Name
end

local function now(): number
	return ctx:Now()
end

local function section(player)
	return ctx:Section(player)
end

-- Listings this server has read for the player. Players who already left get a throwaway
-- table, so a request still yielding for them can't keep them in memory.
local function knownOf(player)
	local list = known[player]
	if not list then
		list = {}
		if ctx:IsReady(player) then
			known[player] = list
		end
	end
	return list
end

local function eggsSystem()
	return ctx:GetSystem("Eggs")
end

local function clubOf(player): string?
	local Clubs = ctx:GetSystem("Clubs")
	return if Clubs then Clubs:ClubOf(player) else nil
end

local function isClub(listing): boolean
	return listing.club ~= false and listing.club ~= nil
end

local function newToken(player): string
	tokens += 1
	return string.format("%s:%d:%d", tostring(ctx.Services.JobId), player.UserId, tokens)
end

-- Calls Services.Market[method]; a missing adapter or an error counts as a failure.
local function call(method: string, ...): (any, any)
	local svc = ctx.Services.Market
	if not svc or type(svc[method]) ~= "function" then
		return false, nil
	end
	local ok, a, b = pcall(svc[method], ...)
	if not ok then
		warn("[Market] " .. method .. " errored: " .. tostring(a))
		return false, nil
	end
	return a, b
end

local function invalidate()
	table.clear(cache)
end

-- Outbox and mail --------------------------------------------------------------------------

local function addTask(player, task)
	table.insert(section(player).outbox, task)
end

local function removeTask(player, task)
	local s = section(player)
	local i = s and table.find(s.outbox, task)
	if i then
		table.remove(s.outbox, i)
	end
end

-- Sends mail, or keeps it in `owner`'s saved outbox to retry. Entries carry an `id`, so a
-- retry after a write that landed anyway is skipped by the mailbox.
local function mail(owner, userId: number, entry)
	if call("MailAdd", userId, entry) ~= true then
		if owner and section(owner) then
			addTask(owner, { kind = "mail", userId = userId, entry = entry })
		else
			warn("[Market] could not mail " .. tostring(entry.id) .. "; nobody to keep it")
		end
		return false
	end
	return true
end

-- Reads the latest record without writing (UpdateAsync is never cached, GetAsync can be).
local function fresh(id: string): (boolean, any)
	local seen = nil
	local ok = call("Update", id, function(current)
		seen = current
		return nil
	end)
	return ok == true, seen
end

-- Items --------------------------------------------------------------------------------------

local function roomFor(player, kind: string): boolean
	if not section(player) then
		return false
	end
	if kind == "monster" then
		return Monsters:Count(player) < Monsters:Capacity(player)
	end
	local Eggs = eggsSystem()
	return Eggs ~= nil and Eggs:Room(player) > 0
end

-- Puts an item record into the player's profile; returns its new id.
local function give(player, kind: string, record): string?
	if not section(player) then
		return nil
	end
	if kind == "monster" then
		local m = Monsters:Insert(player, record, "market")
		return m and m.id
	end
	local Eggs = eggsSystem()
	return Eggs and Eggs:Insert(player, record, "market")
end

-- Gives an item back to its seller: into the profile if it fits, otherwise by mail.
local function returnItem(player, kind: string, record, listingId: string, reason: string): string?
	if roomFor(player, kind) then
		local id = give(player, kind, record)
		if id then
			return id
		end
	end
	mail(player, player.UserId, {
		id = "return:" .. listingId,
		kind = "item",
		itemKind = kind,
		item = record,
		listing = listingId,
		reason = reason,
	})
	return nil
end

-- Listings of a seller ---------------------------------------------------------------------

local function forget(player, id: string)
	local s = section(player)
	if s then
		local i = table.find(s.listings, id)
		if i then
			table.remove(s.listings, i)
			ctx:Dirty(player, "listings")
		end
	end
	knownOf(player)[id] = nil
end

-- Re-reads the player's listings (all, or only those this server hasn't read yet) and drops
-- the ones that are no longer open (a sale's coins arrive by mail; cancels and expiries are
-- settled by their `close` task). Returns the open ones and whether every read worked.
local function review(player, onlyUnknown: boolean)
	local s = section(player)
	local seen = knownOf(player)
	local open, allOk = {}, true
	if not s then
		return open, false
	end
	local pendingList = {}
	for _, task in s.outbox do
		if task.kind == "list" then
			pendingList[task.listing] = true
		end
	end
	for _, id in table.clone(s.listings) do
		if not (onlyUnknown and seen[id]) and not pendingList[id] then
			local ok, listing = call("Get", id)
			if not ok then
				allOk = false
			elseif type(listing) == "table" and listing.state == "open" then
				seen[id] = listing.expiresAt
				table.insert(open, listing)
			elseif listing ~= nil then
				forget(player, id)
			end
		end
	end
	return open, allOk
end

-- Resolvers ------------------------------------------------------------------------------------
-- Each returns a status, or nil when the market can't be read (the task stays saved).

-- A listing whose Create is in doubt: "listed" (it exists) or "returned" (item back).
local function resolveList(player, task): string?
	local ok, current = fresh(task.listing)
	if not ok then
		return nil
	end
	if current == nil then
		local wrote = call("Update", task.listing, function(c)
			return Listing.Tombstone(c, task.listing, player.UserId, now())
		end)
		if wrote ~= true then
			return nil
		end
		ok, current = fresh(task.listing)
		if not ok then
			return nil
		end
	end
	if type(current) == "table" and current.state == "void" then
		returnItem(player, task.itemKind, task.item, task.listing, "cancelled")
		forget(player, task.listing)
		return "returned"
	end
	if type(current) == "table" and current.state == "open" then
		knownOf(player)[task.listing] = current.expiresAt
	end
	return "listed" -- it exists; its own sale / close flow takes it from here
end

local function deliver(player, sold, price: number)
	local id = sold.id
	local newId = if roomFor(player, sold.kind) then give(player, sold.kind, sold.item) else nil
	if not newId then
		mail(
			player,
			player.UserId,
			{ id = "bought:" .. id, kind = "item", itemKind = sold.kind, item = sold.item, listing = id, reason = "bought" }
		)
	end
	local club = isClub(sold)
	local proceeds = Cfg.Proceeds(price, club)
	local name = if type(sold.view) == "table" then sold.view.name else nil
	mail(
		player,
		sold.seller,
		{ id = "sale:" .. id, kind = "coins", amount = proceeds, listing = id, key = sold.key, price = price, name = name }
	)
	local s = section(player)
	s.stats.bought += 1
	s.stats.spent += price
	ctx:Dirty(player, "stats")
	invalidate()
	ctx.Bus:Publish("MarketBought", player, { listing = id, key = sold.key, kind = sold.kind, price = price, club = club })
	ctx.Bus:Publish("MarketSold", nil, {
		listing = id,
		key = sold.key,
		kind = sold.kind,
		price = price,
		proceeds = proceeds,
		buyer = player.UserId,
		seller = sold.seller,
		club = club,
	})
	ctx.Analytics.Custom(player, "MarketBought", price, { kind = sold.kind, key = sold.key })
	local seller = ctx:PlayerByUserId(sold.seller)
	if seller then
		ctx.Services.Spawn(function()
			Market:Sync(seller) -- pay a seller on this server right away
		end)
	end
	return newId
end

-- A purchase whose Update is in doubt: "bought" (item delivered) or "refunded".
local function resolveSettle(player, task): (string?, string?)
	local ok, current = fresh(task.listing)
	if not ok then
		return nil
	end
	if type(current) == "table" and current.state == "sold" and current.token == task.token then
		return "bought", deliver(player, current, task.price)
	end
	Currency:Add(player, "coins", task.price, "market_refund")
	return "refunded"
end

-- A cancel / expiry whose Update is in doubt: "closed" (item back) or "unchanged".
local function resolveClose(player, task): (string?, string?)
	local ok, current = fresh(task.listing)
	if not ok then
		return nil
	end
	if type(current) == "table" and current.token == task.token and current.state ~= "open" and current.state ~= "sold" then
		local newId = returnItem(player, current.kind, current.item, task.listing, current.state)
		forget(player, task.listing)
		invalidate()
		return "closed", newId
	end
	if current == nil or current.state ~= "open" then
		forget(player, task.listing)
	end
	return "unchanged"
end

local function resolve(player, task): boolean
	if task.kind == "mail" then
		return call("MailAdd", task.userId, task.entry) == true
	elseif task.kind == "list" then
		return resolveList(player, task) ~= nil
	elseif task.kind == "settle" then
		return resolveSettle(player, task) ~= nil
	elseif task.kind == "close" then
		return resolveClose(player, task) ~= nil
	end
	warn("[Market] dropping unknown task " .. tostring(task.kind))
	return true
end

-- Runs the player's saved tasks in order; stops at the first one the market can't settle.
local function flushTasks(player): boolean
	local s = section(player)
	if not s then
		return false
	end
	local changed = false
	while #s.outbox > 0 do
		local task = s.outbox[1]
		if not resolve(player, task) then
			break
		end
		if not section(player) then
			return false -- left while resolving; the saved copy still has the task
		end
		removeTask(player, task)
		changed = true
	end
	if changed then
		ctx:SaveNow(player)
	end
	return #s.outbox == 0
end

-- Closes one of the player's open listings. Returns ("closed", listing, newItemId),
-- ("unchanged") when it is not open any more, or ("busy") when the market can't settle it.
local function closeListing(player, id: string, reason: string)
	local task = { kind = "close", listing = id, token = newToken(player), reason = reason }
	addTask(player, task)
	if not ctx:SaveNow(player) then
		removeTask(player, task)
		return "busy"
	end
	local t = now()
	local ok, result = call("Update", id, function(current)
		return Listing.Close(current, player.UserId, t, task.token, reason)
	end)
	if not section(player) then
		return "busy"
	end
	if ok == true then
		removeTask(player, task)
		if type(result) == "table" and result.token == task.token then
			local newId = returnItem(player, result.kind, result.item, id, result.state)
			forget(player, id)
			invalidate()
			ctx:SaveNow(player)
			return "closed", result, newId
		end
		return "unchanged"
	end
	local status, newId = resolveClose(player, task)
	if status == nil or not section(player) then
		return "busy" -- stays saved; the next sync settles it
	end
	removeTask(player, task)
	ctx:SaveNow(player)
	return status, nil, newId
end

-- Expires the player's listings whose time is up. Returns { { kind, id } } put back.
local function expireDue(player)
	local items = {}
	local t = now()
	for id, expiresAt in table.clone(knownOf(player)) do
		if expiresAt <= t and section(player) then
			local status, closed, newId = closeListing(player, id, "expired")
			if status == "closed" and newId then
				table.insert(items, { kind = if closed then closed.kind else "monster", id = newId })
			elseif status == "unchanged" then
				knownOf(player)[id] = nil -- sold or closed elsewhere: read it again next sync
			end
		end
	end
	return items
end

-- Mail ---------------------------------------------------------------------------------------

local function setMailView(player, entries)
	local sess = ctx:Session(player)
	if not sess then
		return
	end
	local coins, items = 0, {}
	for _, entry in entries do
		if entry.kind == "coins" then
			coins += tonumber(entry.amount) or 0
		elseif entry.kind == "item" and type(entry.item) == "table" then
			local ok, view = pcall(Listing.ItemView, entry.itemKind, entry.item)
			table.insert(items, {
				kind = entry.itemKind,
				key = Cfg.ItemKey(entry.itemKind, entry.item),
				reason = entry.reason or "",
				item = if ok then view else false,
			})
		end
	end
	sess.mail = { coins = coins, items = items }
	ctx:DirtySession(player, "mail")
end

local function report(player, coins: number, items, sold, returned: number)
	if coins <= 0 and #items == 0 and #sold == 0 then
		return
	end
	ctx.Net:Fire(player, "Market.MailCollected", { coins = coins, items = items, sold = sold, returned = returned })
end

local function rememberMail(s, id: string)
	table.insert(s.mailSeen, id)
	while #s.mailSeen > MAIL_SEEN_MAX do
		table.remove(s.mailSeen, 1)
	end
end

-- One pass for one player: saved tasks, unknown listings, expiry, then the mailbox.
local function syncNow(player)
	flushTasks(player)
	review(player, true)
	local items = expireDue(player)
	local returned = #items
	local coins, sold, left, ack = 0, {}, {}, {}

	local ok, entries = call("MailPeek", player.UserId)
	local s = section(player)
	local mailOk = ok == true and type(entries) == "table" and s ~= nil
	if mailOk then
		for _, entry in entries do
			if type(entry) ~= "table" then
				continue
			end
			local id = entry.id
			if id ~= nil and table.find(s.mailSeen, id) then
				table.insert(ack, id) -- applied before; the ack was lost
				continue
			end
			local applied = false
			if entry.kind == "coins" then
				local amount = math.max(0, math.floor(tonumber(entry.amount) or 0))
				if entry.refund then
					Currency:Add(player, "coins", amount, "market_refund")
				else
					Currency:Add(player, "coins", amount, "market_sale")
					s.stats.sold += 1
					s.stats.earned += amount
					ctx:Dirty(player, "stats")
					table.insert(sold, { key = entry.key, price = entry.price, proceeds = amount, name = entry.name })
				end
				coins += amount
				if type(entry.listing) == "string" then
					forget(player, entry.listing)
				end
				applied = true
			elseif type(entry.kind) == "string" and mailHandlers[entry.kind] then
				local ran, done = pcall(mailHandlers[entry.kind], player, entry)
				if not ran then
					warn("[Market] mail handler " .. entry.kind .. " errored: " .. tostring(done))
				end
				applied = ran and done == true and section(player) ~= nil
			elseif entry.kind == "item" and type(entry.item) == "table" and roomFor(player, entry.itemKind) then
				local newId = give(player, entry.itemKind, entry.item)
				if newId then
					table.insert(items, { kind = entry.itemKind, id = newId })
					if entry.reason ~= "bought" then
						returned += 1
					end
					applied = true
				end
			end
			if applied then
				if id ~= nil then
					rememberMail(s, id)
					table.insert(ack, id)
				end
			else
				table.insert(left, entry) -- no room: it stays in the mailbox
			end
		end
		setMailView(player, left)
		if #ack > 0 and ctx:SaveNow(player) then
			call("MailAck", player.UserId, ack)
		end
	end
	report(player, coins, items, sold, returned)
	return { mailOk = mailOk, coins = coins, items = items, sold = sold, left = #left }
end

function Market:Sync(player)
	if syncing[player] or not section(player) then
		return nil
	end
	syncing[player] = true
	local ok, result = pcall(syncNow, player)
	syncing[player] = nil
	if not ok then
		warn("[Market] sync failed: " .. tostring(result))
		return nil
	end
	return result
end

function Market:RegisterMail(kind: string, fn)
	assert(type(kind) == "string" and type(fn) == "function", "[Market] RegisterMail(kind, fn)")
	assert(kind ~= "coins" and kind ~= "item", "[Market] coins and item mail are the market's own")
	mailHandlers[kind] = fn
end

-- Sends mail on behalf of another system with the market's failure safety: the task is saved in
-- `owner`'s outbox before the write, so a crash can only repeat it (the id dedups), never lose it.
-- Returns true when it was delivered now; false means it waits in the outbox for the next sync.
function Market:Send(owner, userId: number, entry): boolean
	assert(type(entry) == "table" and entry.id ~= nil, "[Market] Send needs an entry with an id")
	if not owner or not section(owner) then
		return call("MailAdd", userId, entry) == true
	end
	local task = { kind = "mail", userId = userId, entry = entry }
	addTask(owner, task)
	if not ctx:SaveNow(owner) then
		return false -- saved with the next save and retried by the next sync
	end
	if call("MailAdd", userId, entry) ~= true then
		return false
	end
	removeTask(owner, task)
	return true
end

function Market:Flush()
	if flushing then
		return
	end
	flushing = true
	for _, player in ctx:Players() do
		Market:Sync(player)
	end
	flushing = false
end

local function syncLater(player)
	ctx.Services.Spawn(function()
		Market:Sync(player)
	end)
end

-- Actions ------------------------------------------------------------------------------------

local function list(player, payload)
	Progression:Require(player, Cfg.Unlock)
	local s = section(player)
	if #s.listings >= Cfg.MaxListings then
		review(player, false) -- some may have sold or closed since
		if #s.listings >= Cfg.MaxListings then
			ctx:Fail(string.format("You can have up to %d listings at a time", Cfg.MaxListings))
		end
	end
	local clubId = false
	if payload.club then
		clubId = clubOf(player) or false
		if not clubId then
			ctx:Fail("Join a club to post on its trading post")
		end
	end

	-- Escrow: the item leaves the profile before the listing exists anywhere.
	local record
	if payload.kind == "monster" then
		local m = Monsters:Get(player, payload.id)
		if not m then
			ctx:Fail("That monster doesn't exist")
		end
		if m.locked then
			ctx:Fail(Formulas.DisplayName(m) .. " is locked. Unlock it to sell it.")
		end
		if m.busy then
			ctx:Fail(Formulas.DisplayName(m) .. " is busy")
		end
		record = Monsters:Remove(player, payload.id, "market")
		if not record then
			ctx:Fail(Formulas.DisplayName(m) .. " is busy")
		end
	else
		local Eggs = eggsSystem()
		if not Eggs then
			ctx:Fail("Eggs can't be sold right now")
		end
		if not Eggs:Get(player, payload.id) then
			ctx:Fail("Only eggs in storage can be sold")
		end
		record = Eggs:Remove(player, payload.id)
		if not record then
			ctx:Fail("Only eggs in storage can be sold")
		end
	end

	s.seq += 1
	local t = now()
	local listing = Listing.New({
		id = Listing.Id(player.UserId, t, s.seq),
		seller = player.UserId,
		sellerName = displayName(player),
		kind = payload.kind,
		item = record,
		price = payload.price,
		now = t,
		club = clubId,
	})
	-- 1. Intent: the saved profile holds the item in a `list` task until Create is settled.
	local task = { kind = "list", listing = listing.id, itemKind = payload.kind, item = record }
	addTask(player, task)
	table.insert(s.listings, listing.id)
	ctx:Dirty(player, "listings")
	if not ctx:SaveNow(player) then
		removeTask(player, task)
		forget(player, listing.id)
		give(player, payload.kind, record)
		ctx:Fail(BUSY)
	end
	-- 2. The external write.
	local created = call("Create", listing) == true
	if not section(player) then
		ctx:Fail(BUSY) -- left mid-request: the saved task settles it on their next join
	end
	-- 3. Settle.
	if not created then
		local status = resolveList(player, task)
		if status == nil then
			ctx:Fail("The market is busy. Your item is safe and will be listed or returned shortly")
		end
		removeTask(player, task)
		ctx:SaveNow(player)
		if status == "returned" then
			ctx:Fail(BUSY)
		end
	else
		removeTask(player, task)
		ctx:RequestSave(player)
	end
	knownOf(player)[listing.id] = listing.expiresAt
	invalidate()
	ctx.Bus:Publish("MarketListed", player, { listing = listing.id, key = listing.key, price = listing.price, club = isClub(listing) })
	ctx.Analytics.Custom(player, "MarketListed", listing.price, { kind = listing.kind, key = listing.key })
	return { listing = Listing.View(listing, player.UserId) }
end

local function cancel(player, payload)
	local s = section(player)
	local id = payload.listing
	if not table.find(s.listings, id) then
		ctx:Fail("That isn't one of your listings")
	end
	for _, task in s.outbox do
		if task.listing == id then
			ctx:Fail("That listing is still being settled. Try again in a moment")
		end
	end
	local status, _, newId = closeListing(player, id, "cancelled")
	if status == "busy" then
		ctx:Fail(BUSY)
	end
	if status == "unchanged" then
		local ok, current = call("Get", id)
		if ok == true and type(current) == "table" and current.state == "sold" then
			forget(player, id)
			syncLater(player) -- the coins may already be waiting
			ctx:Fail("That listing already sold")
		end
		if ok == true and (current == nil or current.state ~= "open") then
			forget(player, id)
		end
		ctx:Fail("That listing is no longer open")
	end
	if not newId then
		syncLater(player) -- shows it in session.Market.mail
	end
	return { returned = newId ~= nil }
end

local function buyNow(player, payload)
	Progression:Require(player, Cfg.Unlock)
	local id = payload.listing
	local ok, listing = call("Get", id)
	if ok ~= true then
		ctx:Fail(BUSY)
	end
	if not section(player) then
		ctx:Fail(BUSY)
	end
	if type(listing) ~= "table" or listing.state == "void" then
		ctx:Fail("That listing is gone")
	end
	if listing.seller == player.UserId then
		ctx:Fail("You can't buy your own listing")
	end
	if listing.state == "sold" then
		ctx:Fail("Someone already bought that")
	end
	if listing.state ~= "open" then
		ctx:Fail("That listing is no longer open")
	end
	if listing.expiresAt <= now() then
		ctx:Fail("That listing has expired")
	end
	if listing.price ~= payload.price then
		ctx:Fail("The price changed. Check the listing again")
	end
	if isClub(listing) and clubOf(player) ~= listing.club then
		ctx:Fail("Only members of that club can buy this")
	end
	if listing.kind == "monster" then
		if Monsters:Count(player) >= Monsters:Capacity(player) then
			ctx:Fail("Your ranch is full. Make room first")
		end
	else
		local Eggs = eggsSystem()
		if not Eggs then
			ctx:Fail("Eggs can't be bought right now")
		end
		if Eggs:Room(player) <= 0 then
			ctx:Fail("You're carrying too many eggs. Hatch some first")
		end
	end

	-- 1. Intent: pay, and save a `settle` task holding the charge until the sale is settled.
	local price = listing.price
	Currency:Charge(player, { coins = price }, "market_buy")
	local task = { kind = "settle", listing = id, token = newToken(player), price = price, key = listing.key }
	addTask(player, task)
	if not ctx:SaveNow(player) then
		removeTask(player, task)
		Currency:Add(player, "coins", price, "market_refund")
		ctx:Fail(BUSY)
	end
	-- 2. The external write: exactly one buyer can win.
	local buyer = { userId = player.UserId, name = displayName(player) }
	local t = now()
	local done, sold = call("Update", id, function(current)
		return Listing.Sell(current, buyer, price, t, task.token)
	end)
	if not section(player) then
		ctx:Fail(BUSY) -- left mid-request: the saved task settles it on their next join
	end
	-- 3. Settle.
	if done == true then
		removeTask(player, task)
		if type(sold) == "table" and sold.token == task.token and sold.state == "sold" then
			local newId = deliver(player, sold, price)
			ctx:SaveNow(player)
			return { kind = sold.kind, id = newId or "" }
		end
		Currency:Add(player, "coins", price, "market_refund")
		ctx:RequestSave(player)
		invalidate()
		ctx:Fail("Someone else just bought that")
	end
	local status, newId = resolveSettle(player, task)
	if status == nil or not section(player) then
		ctx:Fail("The market is busy. Your purchase will be confirmed or refunded shortly")
	end
	removeTask(player, task)
	ctx:SaveNow(player)
	if status == "refunded" then
		invalidate()
		ctx:Fail("Someone else just bought that")
	end
	return { kind = listing.kind, id = newId or "" }
end

local function buy(player, payload)
	if buying[player] then
		ctx:Fail("Finish your last purchase first")
	end
	buying[player] = true
	local ok, result = pcall(buyNow, player, payload)
	buying[player] = nil
	if not ok then
		error(result, 0)
	end
	return result
end

-- Raw open listings for a query, cached for BrowseCacheSeconds.
local function query(scope: string, kind: string?, key: string?, sort: string)
	local cacheKey = table.concat({ scope, kind or "*", key or "*", sort }, "|")
	local hit = cache[cacheKey]
	if hit and now() - hit.at < Cfg.BrowseCacheSeconds then
		return hit.list
	end
	local ok, result = call("Browse", { scope = scope, kind = kind, key = key, sort = sort })
	if ok ~= true or type(result) ~= "table" then
		ctx:Fail(BUSY)
	end
	cache[cacheKey] = { at = now(), list = result }
	return result
end

local function browse(player, payload)
	local scope = "all"
	if payload.club then
		scope = clubOf(player) or ctx:Fail("You're not in a club")
	end
	local sort = payload.sort or "price"
	local found = Listing.Filter(query(scope, payload.kind, payload.key, sort), now(), payload.kind, payload.key)
	Listing.Sort(found, sort)
	local page = payload.page or 1
	local slice, more = Listing.Page(found, page, Cfg.PageSize)
	local views = {}
	for i, listing in slice do
		views[i] = Listing.View(listing, player.UserId)
	end
	return { listings = views, page = page, more = more }
end

local function mine(player)
	local items = expireDue(player)
	report(player, 0, items, {}, #items)
	local open, allOk = review(player, false)
	if not allOk then
		ctx:Fail(BUSY)
	end
	Listing.Sort(open, "new")
	local views = {}
	for i, listing in open do
		views[i] = Listing.View(listing, player.UserId)
	end
	return { listings = views }
end

local function collect(player)
	if syncing[player] then
		ctx:Fail("Already collecting. Try again in a moment")
	end
	local result = Market:Sync(player)
	if not result or not result.mailOk then
		ctx:Fail(BUSY)
	end
	return { coins = result.coins, items = result.items, left = result.left }
end

-- Lifecycle ----------------------------------------------------------------------------------

function Market.Init(context)
	ctx = context
	Config = ctx.Config
	Cfg = Config.Market
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	-- Fresh module state (tests boot many kernels in one process).
	table.clear(known)
	table.clear(syncing)
	table.clear(buying)
	table.clear(cache)
	table.clear(mailHandlers)
	flushing = false

	ctx.Net:Handle("Market.List", list)
	ctx.Net:Handle("Market.Cancel", cancel)
	ctx.Net:Handle("Market.Buy", buy)
	ctx.Net:Handle("Market.Browse", browse)
	ctx.Net:Handle("Market.Mine", mine)
	ctx.Net:Handle("Market.Collect", collect)

	-- After the snapshot, so the client sees Market.MailCollected from the join sync.
	ctx.Bus:Subscribe("PlayerReady", function(player)
		syncLater(player)
	end)
end

function Market.Start()
	ctx:Every(Cfg.MailSyncSeconds, function()
		ctx.Services.Spawn(function()
			Market:Flush()
		end)
	end)
end

function Market.PlayerAdded(player, _info)
	known[player] = {}
	setMailView(player, {})
end

function Market.PlayerRemoving(player)
	-- One best-effort pass over mail meant for others (e.g. a seller's proceeds) before the
	-- profile is released; anything left stays saved and is retried when the player returns.
	local s = section(player)
	if s then
		for _, task in table.clone(s.outbox) do
			if task.kind == "mail" and call("MailAdd", task.userId, task.entry) == true then
				removeTask(player, task)
			end
		end
	end
	known[player] = nil
	syncing[player] = nil
	buying[player] = nil
end

return Market
