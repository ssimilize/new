--[[
	Trade (S5): player-to-player trading of monsters and eggs on the same server.

	Flow:
	  Trade.Request { target }       → target gets Trade.Incoming; expires after requestTimeout
	  Trade.Respond { from, accept } → accept opens the trade window for both
	  Trade.SetOffer { items }       → replaces your offer (monsters get busy "trade")
	  Trade.SetReady { ready }       → both press Ready…
	  Trade.Confirm                  → …then both Confirm: a countdown starts, then the trade runs
	  Trade.Cancel                   → cancels a request, declines an incoming one or closes the trade
	Any offer change (or a change to an offered monster) resets both sides' ready/confirm and
	stops the countdown. Leaving the server cancels everything.

	Gates (Config.Social.Trade): Flags.Trading, unlock "trading" for both players, total playtime
	≥ minPlaySeconds for both (ctx:Meta(p).playSeconds + this session), one trade at a time.

	Execution is one synchronous server transaction: every item is re-validated, both sides'
	monster capacity and egg caps are checked, then items are removed from both profiles and
	inserted into the other (Monsters:Remove/Insert, Eggs:Remove/Insert). If a removal fails,
	everything already removed goes back to its owner. Both profiles are saved right away.

	Save section (profile.Trade): { log }   -- private; newest first, ≤ maxLogEntries, ≤ logDays old
	  log entry = { t, partner, partnerName, gave = { Summary }, got = { Summary } }

	Session (session.Trade):
	  { status = "none"|"outgoing"|"incoming"|"open"|"countdown", partner = { userId, name }|false,
	    mine = TradeSide, theirs = TradeSide, endsAt }
	  TradeSide = { items = { { kind, id, appearance = Appearance|false, egg = eggType|false } }, ready, confirmed }

	Bus: publishes TradeCompleted { partner } and RanchXP for both players; fires Trade.Completed.
	Eggs is optional; it is expected to expose Get/Remove/Insert/Count (and optionally
	IsIncubating(player, id)) as documented in ARCHITECTURE.md.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Appearance = require(Shared.Logic.Appearance)
local Formulas = require(Shared.Logic.Formulas)

local Trade = {
	Name = "Trade",
	Dependencies = { "Monsters", "Progression" },
	OptionalDependencies = { "Eggs" },
}

Trade.Profile = {
	Version = 1,
	Default = function()
		return { log = {} }
	end,
	Private = { "log" },
}

local ctx
local Config
local Monsters, Progression

local requests = {} -- [fromPlayer] = request { from, to, expiresAt, timer }
local incoming = {} -- [toPlayer] = request
local trades = {} -- [player] = trade { a, b, sides = { [player] = Side }, status, endsAt, timer, token }
local joinedAt = {} -- [player] = unix seconds

-- Monster fields whose change alters what the partner agreed to.
local VALUE_FIELDS = {
	line = true,
	stage = true,
	form = true,
	rarity = true,
	variant = true,
	muts = true,
	traits = true,
	hidden = true,
	weight = true,
	lv = true,
	stars = true,
	name = true,
	locked = true,
}

-- Helpers ----------------------------------------------------------------------------------

local function rules()
	return Config.Social.Trade
end

local function displayName(player): string
	return player.DisplayName or player.Name
end

local function playSeconds(player): number
	local meta = ctx:Meta(player)
	local now = ctx:Now()
	return (meta and meta.playSeconds or 0) + math.max(0, now - (joinedAt[player] or now))
end

local function isTrading(player): boolean
	return trades[player] ~= nil or requests[player] ~= nil or incoming[player] ~= nil
end

local function partnerOf(trade, player)
	return if trade.a == player then trade.b else trade.a
end

local function eggsSystem()
	return ctx:GetSystem("Eggs")
end

local function eggIncubating(Eggs, player, id: string): boolean
	if type(Eggs.IsIncubating) == "function" then
		return Eggs:IsIncubating(player, id) == true
	end
	return false
end

local function emptySide()
	return { items = {}, ready = false, confirmed = false }
end

local function itemView(owner, item)
	if item.kind == "monster" then
		return { kind = "monster", id = item.id, appearance = Monsters:Appearance(owner, item.id) or false, egg = false }
	end
	local Eggs = eggsSystem()
	local record = Eggs and Eggs:Get(owner, item.id)
	return { kind = "egg", id = item.id, appearance = false, egg = record and record.type or false }
end

local function sideView(owner, side)
	local items = {}
	for i, item in side.items do
		items[i] = itemView(owner, item)
	end
	return { items = items, ready = side.ready, confirmed = side.confirmed }
end

local function writeSession(player, status: string, partner, mine, theirs, endsAt: number?)
	local sess = ctx:Session(player)
	if not sess then
		return
	end
	sess.status = status
	sess.partner = if partner then { userId = partner.UserId, name = displayName(partner) } else false
	sess.mine = mine or emptySide()
	sess.theirs = theirs or emptySide()
	sess.endsAt = endsAt or 0
	ctx:DirtySession(player)
end

local function clearSession(player)
	writeSession(player, "none", nil, nil, nil, 0)
end

local function syncTrade(trade)
	for _, player in { trade.a, trade.b } do
		local other = partnerOf(trade, player)
		writeSession(
			player,
			trade.status,
			other,
			sideView(player, trade.sides[player]),
			sideView(other, trade.sides[other]),
			trade.endsAt
		)
	end
end

local function stopCountdown(trade)
	if trade.timer then
		trade.timer.Cancel()
		trade.timer = nil
	end
	trade.token += 1
	trade.status = "open"
	trade.endsAt = 0
end

-- Any change to either offer: both sides must look again.
local function resetReadiness(trade)
	for _, side in trade.sides do
		side.ready = false
		side.confirmed = false
	end
	stopCountdown(trade)
end

local function freeOffer(player, side)
	for _, item in side.items do
		if item.kind == "monster" then
			local m = Monsters:Get(player, item.id)
			if m and m.busy == "trade" then
				Monsters:SetBusy(player, item.id, false)
			end
		end
	end
end

local function dropRequest(req)
	if req.timer then
		req.timer.Cancel()
	end
	if requests[req.from] == req then
		requests[req.from] = nil
		clearSession(req.from)
	end
	if incoming[req.to] == req then
		incoming[req.to] = nil
		clearSession(req.to)
	end
end

local function closeTrade(trade)
	stopCountdown(trade)
	for _, player in { trade.a, trade.b } do
		freeOffer(player, trade.sides[player])
		if trades[player] == trade then
			trades[player] = nil
		end
		clearSession(player)
	end
end

local function mustTrade(player)
	local trade = trades[player]
	if not trade then
		ctx:Fail("You're not in a trade")
	end
	return trade
end

-- Execution ---------------------------------------------------------------------------------

local function summarize(kind: string, id: string, record)
	if kind == "monster" then
		return {
			kind = "monster",
			id = id,
			line = record.line,
			rarity = record.rarity,
			variant = record.variant or 0,
			muts = table.clone(record.muts or {}),
			weight = record.weight,
			lv = record.lv or 1,
			stars = record.stars or 1,
			gen = record.gen or 0,
		}
	end
	return { kind = "egg", id = id, type = record.type }
end

local function writeLog(player, partner, gave, got)
	local s = ctx:Section(player)
	if not s then
		return
	end
	local now = ctx:Now()
	table.insert(s.log, 1, { t = now, partner = partner.UserId, partnerName = partner.Name, gave = gave, got = got })
	local oldest = now - rules().logDays * 86400
	for i = #s.log, 1, -1 do
		if i > rules().maxLogEntries or s.log[i].t < oldest then
			table.remove(s.log, i)
		end
	end
end

-- Returns an error message if the item can no longer be traded.
local function stillValid(player, item): string?
	if item.kind == "monster" then
		local m = Monsters:Get(player, item.id)
		if not m or m.busy ~= "trade" or m.locked then
			return "An item in the trade changed. Check both offers again."
		end
		return nil
	end
	local Eggs = eggsSystem()
	if not Eggs or not Eggs:Get(player, item.id) or eggIncubating(Eggs, player, item.id) then
		return "An egg in the trade is no longer available. Check both offers again."
	end
	return nil
end

local function counts(side): (number, number)
	local monsters, eggs = 0, 0
	for _, item in side.items do
		if item.kind == "monster" then
			monsters += 1
		else
			eggs += 1
		end
	end
	return monsters, eggs
end

-- Returns (message for this player, message for the partner) if the player can't take the items.
local function capacityProblem(player, mine, theirs): (string?, string?)
	local givenM, givenE = counts(mine)
	local recvM, recvE = counts(theirs)
	if recvM > givenM and Monsters:Count(player) - givenM + recvM > Monsters:Capacity(player) then
		return "Your ranch is full. Make room before trading.", displayName(player) .. "'s ranch is full"
	end
	if recvE > givenE then
		local Eggs = eggsSystem()
		if Eggs and Eggs:Count(player) - givenE + recvE > Config.Economy.MaxEggs then
			return "You're carrying too many eggs. Hatch some first.", displayName(player) .. " can't carry more eggs"
		end
	end
	return nil, nil
end

local function execute(trade)
	local a, b = trade.a, trade.b
	if not ctx:IsReady(a) or not ctx:IsReady(b) then
		closeTrade(trade)
		return
	end
	local function halt(messages)
		resetReadiness(trade)
		syncTrade(trade)
		for player, text in messages do
			ctx:Notify(player, text, "error")
		end
	end

	-- 1. Re-validate every item.
	for _, player in { a, b } do
		for _, item in trade.sides[player].items do
			local why = stillValid(player, item)
			if why then
				halt({ [a] = why, [b] = why })
				return
			end
		end
	end
	-- 2. Room on both sides.
	for _, player in { a, b } do
		local other = partnerOf(trade, player)
		local mineMsg, theirMsg = capacityProblem(player, trade.sides[player], trade.sides[other])
		if mineMsg then
			halt({ [player] = mineMsg, [other] = theirMsg })
			return
		end
	end

	-- 3. Take everything out of both profiles.
	local Eggs = eggsSystem()
	local removed = { [a] = {}, [b] = {} }
	local failed = false
	for _, player in { a, b } do
		for _, item in trade.sides[player].items do
			local record
			if item.kind == "monster" then
				Monsters:SetBusy(player, item.id, false)
				record = Monsters:Remove(player, item.id, "trade")
			elseif Eggs then
				record = Eggs:Remove(player, item.id)
			end
			if not record then
				failed = true
				break
			end
			table.insert(removed[player], { kind = item.kind, id = item.id, record = record })
		end
		if failed then
			break
		end
	end
	if failed then
		-- Put back what was already taken; nothing changes hands.
		for player, list in removed do
			for _, entry in list do
				if entry.kind == "monster" then
					Monsters:Insert(player, entry.record, "trade")
				elseif Eggs then
					Eggs:Insert(player, entry.record, "trade")
				end
			end
		end
		warn("[Trade] a removal failed during execution; trade rolled back")
		closeTrade(trade)
		for _, player in { a, b } do
			ctx:Notify(player, "The trade couldn't be completed. Nothing was exchanged.", "error")
		end
		return
	end

	-- 4. Give everything to the other side.
	local received = { [a] = {}, [b] = {} }
	local gave = { [a] = {}, [b] = {} }
	local got = { [a] = {}, [b] = {} }
	for _, player in { a, b } do
		local other = partnerOf(trade, player)
		for _, entry in removed[player] do
			table.insert(gave[player], summarize(entry.kind, entry.id, entry.record))
			if entry.kind == "monster" then
				local record = Monsters:Insert(other, entry.record, "trade")
				table.insert(received[other], { kind = "monster", appearance = Appearance.Of(record), egg = false })
				table.insert(got[other], summarize("monster", record.id, record))
			else
				local newId = Eggs:Insert(other, entry.record, "trade")
				table.insert(received[other], { kind = "egg", appearance = false, egg = entry.record.type })
				table.insert(got[other], summarize("egg", newId or entry.id, entry.record))
			end
		end
	end

	-- 5. Close, log, save and announce.
	trades[a], trades[b] = nil, nil
	stopCountdown(trade)
	for _, player in { a, b } do
		local other = partnerOf(trade, player)
		writeLog(player, other, gave[player], got[player])
		clearSession(player)
		ctx:RequestSave(player)
		ctx.Bus:Publish("TradeCompleted", player, { partner = other.UserId })
		ctx.Bus:Publish("RanchXP", player, { amount = Config.Unlocks.XP.trade, reason = "trade" })
		ctx.Net:Fire(player, "Trade.Completed", { received = received[player] })
		ctx.Analytics.Custom(player, "TradeDone", #gave[player] + #got[player], {})
	end
end

-- Actions -----------------------------------------------------------------------------------

local function request(player, payload)
	if not Config.Flags.Trading then
		ctx:Fail("Trading is turned off right now")
	end
	if payload.target == player.UserId then
		ctx:Fail("You can't trade with yourself")
	end
	local target = ctx:PlayerByUserId(payload.target)
	if not target then
		ctx:Fail("That player isn't on this server")
	end
	local unlock = rules().unlock
	if not Progression:IsUnlocked(player, unlock) then
		ctx:Fail(string.format("Trading unlocks at Ranch Level %d", Progression:UnlockLevel(unlock)))
	end
	if not Progression:IsUnlocked(target, unlock) then
		ctx:Fail(displayName(target) .. " hasn't unlocked trading yet")
	end
	local left = rules().minPlaySeconds - playSeconds(player)
	if left > 0 then
		ctx:Fail(string.format("You can trade after %d more minutes of play", math.ceil(left / 60)))
	end
	if playSeconds(target) < rules().minPlaySeconds then
		ctx:Fail(displayName(target) .. " can't trade yet (not enough playtime)")
	end
	if isTrading(player) then
		ctx:Fail("Finish your current trade first")
	end
	if isTrading(target) then
		ctx:Fail(displayName(target) .. " is busy trading")
	end

	local timeout = rules().requestTimeout
	local req = { from = player, to = target, expiresAt = ctx:Now() + timeout }
	requests[player] = req
	incoming[target] = req
	req.timer = ctx:After(timeout, function()
		if requests[player] == req then
			req.timer = nil
			dropRequest(req)
			if ctx:IsReady(player) then
				ctx:Notify(player, displayName(target) .. " didn't answer your trade request", "info")
			end
		end
	end)
	writeSession(player, "outgoing", target, nil, nil, req.expiresAt)
	writeSession(target, "incoming", player, nil, nil, req.expiresAt)
	ctx.Net:Fire(target, "Trade.Incoming", { from = player.UserId, name = displayName(player) })
	return nil
end

local function respond(player, payload)
	local req = incoming[player]
	if not req or req.from.UserId ~= payload.from then
		ctx:Fail("That trade request has expired")
	end
	dropRequest(req)
	local from = req.from
	if not payload.accept then
		ctx:Notify(from, displayName(player) .. " declined your trade request", "info")
		return nil
	end
	if not ctx:IsReady(from) or isTrading(from) then
		ctx:Fail("That player is no longer available")
	end
	local trade = {
		a = from,
		b = player,
		sides = { [from] = emptySide(), [player] = emptySide() },
		status = "open",
		endsAt = 0,
		token = 0,
	}
	trades[from] = trade
	trades[player] = trade
	syncTrade(trade)
	return nil
end

local function setOffer(player, payload)
	local trade = mustTrade(player)
	local side = trade.sides[player]
	if #payload.items > rules().maxItems then
		ctx:Fail(string.format("You can offer up to %d items", rules().maxItems))
	end
	local offered = {} -- monster ids currently in this player's offer
	for _, item in side.items do
		if item.kind == "monster" then
			offered[item.id] = true
		end
	end

	local seen, items = {}, {}
	for _, item in payload.items do
		local key = item.kind .. ":" .. item.id
		if seen[key] then
			ctx:Fail("That item is already in your offer")
		end
		seen[key] = true
		if item.kind == "monster" then
			local m = Monsters:Get(player, item.id)
			if not m then
				ctx:Fail("That monster doesn't exist")
			end
			if m.locked then
				ctx:Fail(Formulas.DisplayName(m) .. " is locked. Unlock it to trade it.")
			end
			if m.busy and not (m.busy == "trade" and offered[item.id]) then
				ctx:Fail(Formulas.DisplayName(m) .. " is busy")
			end
		else
			local Eggs = eggsSystem()
			if not Eggs then
				ctx:Fail("Eggs can't be traded right now")
			end
			if not Eggs:Get(player, item.id) then
				ctx:Fail("That egg doesn't exist")
			end
			if eggIncubating(Eggs, player, item.id) then
				ctx:Fail("That egg is in an incubator")
			end
		end
		table.insert(items, { kind = item.kind, id = item.id })
	end

	for id in offered do
		if not seen["monster:" .. id] then
			local m = Monsters:Get(player, id)
			if m and m.busy == "trade" then
				Monsters:SetBusy(player, id, false)
			end
		end
	end
	side.items = items -- set before tagging so MonsterChanged sees the new offer
	for _, item in items do
		if item.kind == "monster" and not offered[item.id] then
			Monsters:SetBusy(player, item.id, "trade")
		end
	end
	resetReadiness(trade)
	syncTrade(trade)
	return nil
end

local function setReady(player, payload)
	local trade = mustTrade(player)
	local side = trade.sides[player]
	if payload.ready then
		side.ready = true
	else
		side.ready = false
		for _, s in trade.sides do
			s.confirmed = false
		end
		stopCountdown(trade)
	end
	syncTrade(trade)
	return nil
end

local function confirm(player)
	local trade = mustTrade(player)
	local mine, theirs = trade.sides[player], trade.sides[partnerOf(trade, player)]
	if not (mine.ready and theirs.ready) then
		ctx:Fail("Both players need to be Ready first")
	end
	if #mine.items + #theirs.items == 0 then
		ctx:Fail("Add something to the trade first")
	end
	if trade.status == "countdown" then
		return nil
	end
	mine.confirmed = true
	if theirs.confirmed then
		local seconds = rules().countdownSeconds
		trade.token += 1
		local token = trade.token
		trade.status = "countdown"
		trade.endsAt = ctx:Now() + seconds
		trade.timer = ctx:After(seconds, function()
			if trades[trade.a] == trade and trade.status == "countdown" and trade.token == token then
				trade.timer = nil
				execute(trade)
			end
		end)
	end
	syncTrade(trade)
	return nil
end

local function cancel(player)
	local trade = trades[player]
	if trade then
		local other = partnerOf(trade, player)
		closeTrade(trade)
		ctx:Notify(other, displayName(player) .. " cancelled the trade", "info")
		return nil
	end
	local req = requests[player]
	if req then
		dropRequest(req)
		ctx:Notify(req.to, displayName(player) .. " cancelled the trade request", "info")
		return nil
	end
	req = incoming[player]
	if req then
		dropRequest(req)
		ctx:Notify(req.from, displayName(player) .. " declined your trade request", "info")
		return nil
	end
	return ctx:Fail("You're not trading")
end

-- Reacts to changes on offered monsters (anti bait-and-switch: renaming, locking, …).
local function onMonsterChanged(player, detail)
	local trade = trades[player]
	if not trade then
		return
	end
	local offered = false
	for _, item in trade.sides[player].items do
		if item.kind == "monster" and item.id == detail.id then
			offered = true
			break
		end
	end
	if not offered then
		return
	end
	local relevant = detail.fields == nil
	for _, field in detail.fields or {} do
		if VALUE_FIELDS[field] then
			relevant = true
			break
		end
	end
	if relevant then
		resetReadiness(trade)
		syncTrade(trade)
	end
end

-- Lifecycle -------------------------------------------------------------------------------------

function Trade.Init(context)
	ctx = context
	Config = ctx.Config
	Monsters = ctx:GetSystem("Monsters")
	Progression = ctx:GetSystem("Progression")
	-- Fresh module state (tests boot many kernels in one process).
	table.clear(requests)
	table.clear(incoming)
	table.clear(trades)
	table.clear(joinedAt)

	ctx.Net:Handle("Trade.Request", request)
	ctx.Net:Handle("Trade.Respond", respond)
	ctx.Net:Handle("Trade.SetOffer", setOffer)
	ctx.Net:Handle("Trade.SetReady", setReady)
	ctx.Net:Handle("Trade.Confirm", confirm)
	ctx.Net:Handle("Trade.Cancel", cancel)

	ctx.Bus:Subscribe("MonsterChanged", onMonsterChanged)
end

function Trade.PlayerAdded(player, _info)
	joinedAt[player] = ctx:Now()
	-- A trade never survives a rejoin; clear tags left behind by a crash mid-trade.
	for id, m in Monsters:All(player) do
		if m.busy == "trade" then
			Monsters:SetBusy(player, id, false)
		end
	end
	clearSession(player)
end

function Trade.PlayerRemoving(player)
	local trade = trades[player]
	if trade then
		local other = partnerOf(trade, player)
		closeTrade(trade)
		if ctx:IsReady(other) then
			ctx:Notify(other, displayName(player) .. " left, so the trade was cancelled", "info")
		end
	end
	local req = requests[player] or incoming[player]
	if req then
		dropRequest(req)
		local other = if req.from == player then req.to else req.from
		if ctx:IsReady(other) then
			ctx:Notify(other, displayName(player) .. " left the server", "info")
		end
	end
	-- Both directions may exist only transiently; clear any leftovers.
	if incoming[player] then
		dropRequest(incoming[player])
	end
	joinedAt[player] = nil
end

return Trade
