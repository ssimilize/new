--[[
	Market (update 1.3 · Market Day, ARCHITECTURE §8): asynchronous listings across every
	server. Rules and tuning are in Config.Market; pure listing rules in Listing.luau.

	Escrow: listing takes the monster or egg out of the seller's profile (Monsters:Remove /
	Eggs:Remove) and stores it inside the listing record (Services.Market.Create). If Create
	fails the item goes straight back. A listing only leaves "open" inside
	Services.Market.Update (atomic), so exactly one buyer can win it across all servers.

	Buy:     checks → Currency:Charge → Update(open → sold). A lost race or a failed Update
	         refunds. The winner gets the item (Monsters:Insert / Eggs:Insert); the seller gets
	         Config.Market.Proceeds(price, club) through their mailbox.
	Cancel / expiry: Update(open → cancelled | expired) by the seller's server; the item comes
	         back to the profile when there is room, otherwise through the mailbox.
	Mail:    collected on join (PlayerReady) and every MailSyncSeconds: coins are added
	         ("market_sale"), items inserted when they fit; the rest goes back to the mailbox
	         and shows in session.Market.mail. Fires Market.MailCollected when anything arrived.
	Outbox:  mail that could not be sent (MailAdd failed) is kept in the sender's profile
	         (private `outbox`, saved with it) and retried on every sync: proceeds are never
	         dropped. Tasks for players who already left wait in memory.

	Market.Buy also needs the "market" unlock (alts below Ranch Level 10 can't move coins).
	Browse results are cached per query for BrowseCacheSeconds (cleared by this server's own
	listings, sales and cancels); expired listings are filtered at read time.

	Save section (profile.Market):
	  listings = { listingId }                          -- this player's open listings
	  stats    = { sold, bought, earned, spent }
	  seq      = number                                 -- private: listing id counter
	  outbox   = { { kind = "mail", userId, entry } | { kind = "void", listing, seller } }  -- private
	Session (session.Market): { mail = { coins, items = { { kind, key, reason, item = ItemView } } } }

	Actions: Market.List, Cancel, Buy, Browse, Mine, Collect. Event: Market.MailCollected.
	Bus: publishes MarketListed, MarketBought (buyer) and MarketSold (nil, buyer's server).
	Public API: Market:Sync(player) -> summary? (tests / shutdown), Market:Flush().
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
	Version = 1,
	Default = function()
		return { listings = {}, stats = { sold = 0, bought = 0, earned = 0, spent = 0 }, seq = 0, outbox = {} }
	end,
	Private = { "seq", "outbox" },
}

local BUSY = "The market is busy. Try again"

local ctx
local Config, Cfg
local Currency, Progression, Monsters

local known = {} -- [player] = { [listingId] = expiresAt } open listings this server has read
local syncing = {} -- [player] = true while a sync runs
local orphans = {} -- outbox tasks whose sender already left
local cache = {} -- [query] = { at, list } browse results
local tokens = 0

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

local function knownOf(player)
	local list = known[player]
	if not list then
		list = {}
		known[player] = list
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

-- Outbox -------------------------------------------------------------------------------------

local function queue(owner, task)
	local s = owner and section(owner)
	if s then
		table.insert(s.outbox, task)
	else
		table.insert(orphans, task)
	end
end

local function runTask(task): boolean
	if task.kind == "mail" then
		return call("MailAdd", task.userId, task.entry) == true
	elseif task.kind == "void" then
		local t = now()
		return call("Update", task.listing, function(current)
			return Listing.Void(current, task.seller, t)
		end) == true
	end
	warn("[Market] dropping unknown outbox task " .. tostring(task.kind))
	return true
end

-- Runs queued tasks in order; stops at the first failure (the market is probably down).
local function flush(list): boolean
	while #list > 0 do
		if not runTask(list[1]) then
			return false
		end
		table.remove(list, 1)
	end
	return true
end

-- Sends mail to `userId`, or keeps it in `owner`'s outbox when the mailbox can't be reached.
local function mail(owner, userId: number, entry)
	if call("MailAdd", userId, entry) ~= true then
		queue(owner, { kind = "mail", userId = userId, entry = entry })
		return false
	end
	return true
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

-- Returns a closed listing's item: to the profile if it fits, otherwise to the mailbox.
local function returnItem(player, listing): string?
	if roomFor(player, listing.kind) then
		local id = give(player, listing.kind, listing.item)
		if id then
			return id
		end
	end
	mail(player, listing.seller, {
		kind = "item",
		itemKind = listing.kind,
		item = listing.item,
		listing = listing.id,
		reason = listing.state,
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
-- the ones that are no longer open (a sale's coins arrive by mail). Returns the open ones and
-- whether every read worked.
local function review(player, onlyUnknown: boolean)
	local s = section(player)
	local seen = knownOf(player)
	local open, allOk = {}, true
	if not s then
		return open, false
	end
	for _, id in table.clone(s.listings) do
		if not (onlyUnknown and seen[id]) then
			local ok, listing = call("Get", id)
			if not ok then
				allOk = false
			elseif type(listing) == "table" and listing.state == "open" then
				seen[id] = listing.expiresAt
				table.insert(open, listing)
			else
				forget(player, id)
			end
		end
	end
	return open, allOk
end

-- Closes one of the player's open listings. Returns (closed listing) or (nil, "busy" | "unchanged").
local function close(player, id: string, reason: string)
	local token = newToken(player)
	local t = now()
	local ok, result = call("Update", id, function(current)
		return Listing.Close(current, player.UserId, t, token, reason)
	end)
	if ok ~= true then
		-- The write may have landed before the failure was reported: our token tells.
		local got, current = call("Get", id)
		if got == true and type(current) == "table" and current.token == token then
			result = current
		else
			return nil, "busy"
		end
	end
	if type(result) ~= "table" or result.token ~= token then
		return nil, "unchanged"
	end
	forget(player, id)
	invalidate()
	return result, nil
end

-- Expires the player's listings whose time is up. Returns { { kind, id } } put back.
local function expireDue(player)
	local items = {}
	local t = now()
	for id, expiresAt in table.clone(knownOf(player)) do
		if expiresAt <= t then
			local closed, why = close(player, id, "expired")
			if closed then
				local newId = returnItem(player, closed)
				if newId then
					table.insert(items, { kind = closed.kind, id = newId })
				end
			elseif why == "unchanged" then
				-- Sold or closed elsewhere: read it again on the next sync.
				knownOf(player)[id] = nil
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
	ctx:RequestSave(player)
end

-- One pass for one player: outbox, unknown listings, expiry, then the mailbox.
local function syncNow(player)
	local s = section(player)
	flush(s.outbox)
	review(player, true)
	local items = expireDue(player)
	local returned = #items
	local coins, sold, left = 0, {}, {}

	local ok, entries = call("MailTake", player.UserId)
	local mailOk = ok == true and type(entries) == "table"
	if mailOk then
		for _, entry in entries do
			if type(entry) ~= "table" then
				continue
			end
			if entry.kind == "coins" then
				local amount = math.max(0, math.floor(tonumber(entry.amount) or 0))
				if entry.refund then
					Currency:Add(player, "coins", amount, "market_refund")
				else
					Currency:Add(player, "coins", amount, "market_sale")
					s.stats.sold += 1
					s.stats.earned += amount
					ctx:Dirty(player, "stats")
					table.insert(sold, { key = entry.key, price = entry.price, proceeds = amount })
				end
				coins += amount
				if type(entry.listing) == "string" then
					forget(player, entry.listing)
				end
			elseif entry.kind == "item" and type(entry.item) == "table" and roomFor(player, entry.itemKind) then
				local newId = give(player, entry.itemKind, entry.item)
				if newId then
					table.insert(items, { kind = entry.itemKind, id = newId })
					if entry.reason ~= "bought" then
						returned += 1
					end
				else
					table.insert(left, entry)
				end
			else
				table.insert(left, entry) -- no room (or unknown): back into the mailbox
			end
		end
		for _, entry in left do
			mail(player, player.UserId, entry)
		end
		setMailView(player, left)
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

function Market:Flush()
	flush(orphans)
	for _, player in ctx:Players() do
		Market:Sync(player)
	end
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
	if call("Create", listing) ~= true then
		give(player, payload.kind, record)
		-- If the write landed after all, close it without returning the item a second time.
		queue(player, { kind = "void", listing = listing.id, seller = player.UserId })
		ctx:Fail(BUSY)
	end

	table.insert(s.listings, listing.id)
	ctx:Dirty(player, "listings")
	knownOf(player)[listing.id] = listing.expiresAt
	invalidate()
	ctx.Bus:Publish("MarketListed", player, { listing = listing.id, key = listing.key, price = listing.price, club = isClub(listing) })
	ctx:RequestSave(player)
	ctx.Analytics.Custom(player, "MarketListed", listing.price, { kind = listing.kind, key = listing.key })
	return { listing = Listing.View(listing, player.UserId) }
end

local function cancel(player, payload)
	local s = section(player)
	local id = payload.listing
	if not table.find(s.listings, id) then
		ctx:Fail("That isn't one of your listings")
	end
	local closed, why = close(player, id, "cancelled")
	if why == "busy" then
		ctx:Fail(BUSY)
	end
	if not closed then
		local ok, current = call("Get", id)
		if ok ~= true then
			ctx:Fail(BUSY)
		end
		if type(current) ~= "table" or current.state ~= "open" then
			forget(player, id)
		end
		if type(current) == "table" and current.state == "sold" then
			syncLater(player) -- the coins may already be waiting
			ctx:Fail("That listing already sold")
		end
		ctx:Fail("That listing is no longer open")
	end
	local newId = returnItem(player, closed :: any)
	ctx:RequestSave(player)
	if not newId then
		syncLater(player) -- shows it in session.Market.mail
	end
	return { returned = newId ~= nil }
end

local function buy(player, payload)
	Progression:Require(player, Cfg.Unlock)
	local id = payload.listing
	local ok, listing = call("Get", id)
	if ok ~= true then
		ctx:Fail(BUSY)
	end
	if type(listing) ~= "table" then
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

	-- Pay first, then try to win the listing; anything but a win refunds.
	local price = listing.price
	Currency:Charge(player, { coins = price }, "market_buy")
	local token = newToken(player)
	local buyer = { userId = player.UserId, name = displayName(player) }
	local t = now()
	local done, sold = call("Update", id, function(current)
		return Listing.Sell(current, buyer, price, t, token)
	end)
	if done ~= true then
		local got, current = call("Get", id)
		if got == true and type(current) == "table" and current.token == token then
			done, sold = true, current
		end
	end
	if done ~= true or type(sold) ~= "table" or sold.token ~= token or sold.state ~= "sold" then
		if section(player) then
			Currency:Add(player, "coins", price, "market_refund")
		else
			mail(nil, player.UserId, { kind = "coins", amount = price, listing = id, key = listing.key, price = price, refund = true })
		end
		invalidate()
		ctx:Fail(if done == true then "Someone else just bought that" else BUSY)
	end

	-- Won: the item to the buyer, the proceeds to the seller's mailbox.
	local newId = give(player, sold.kind, sold.item)
	if not newId then
		mail(player, player.UserId, { kind = "item", itemKind = sold.kind, item = sold.item, listing = id, reason = "bought" })
	end
	local club = isClub(sold)
	local proceeds = Cfg.Proceeds(price, club)
	mail(player, sold.seller, { kind = "coins", amount = proceeds, listing = id, key = sold.key, price = price })

	local s = section(player)
	if s then
		s.stats.bought += 1
		s.stats.spent += price
		ctx:Dirty(player, "stats")
	end
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
	ctx:RequestSave(player)
	ctx.Analytics.Custom(player, "MarketBought", price, { kind = sold.kind, key = sold.key })
	local seller = ctx:PlayerByUserId(sold.seller)
	if seller then
		syncLater(seller) -- pay a seller on this server right away
	end
	return { kind = sold.kind, id = newId or "" }
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
	table.clear(orphans)
	table.clear(cache)

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
	known[player] = nil
	syncing[player] = nil
end

return Market
