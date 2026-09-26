--[[
	StoreKit (C2): nil-safe readers over ctx.Store, shared by the HUD and the C2 screens,
	plus two helpers every screen uses:

	  StoreKit.watch(store, { paths }, fn) -> { Start(), Stop() }
	      Coalesces Store observers into one deferred `fn()` per frame. Start on open,
	      Stop on close, so hidden screens never do work and observers never leak.
	  StoreKit.request(ctx, action, payload) -> ok, data
	      ctx.Net:RequestOnce + an error toast on failure (double taps are ignored silently).

	Every reader tolerates missing state: the systems behind a screen may not be plugged in.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Jar = require(ReplicatedStorage.Shared.Logic.Jar)

local StoreKit = {}

local function asTable(v): { [any]: any }
	return if type(v) == "table" then v else {}
end
StoreKit.asTable = asTable

function StoreKit.num(store, path: string, default: number?): number
	local v = store:Get(path)
	return if type(v) == "number" then v else (default or 0)
end

function StoreKit.tbl(store, path: string): { [any]: any }
	return asTable(store:Get(path))
end

function StoreKit.day(now: number): number
	return math.floor(now / 86400)
end

-- Progression ----------------------------------------------------------------------

function StoreKit.level(store): number
	return math.max(1, StoreKit.num(store, "profile.Progression.level", 1))
end

function StoreKit.unlockLevel(key: string): number
	return Config.Unlocks.Features[key] or 1
end

function StoreKit.isUnlocked(store, key: string): boolean
	return StoreKit.level(store) >= StoreKit.unlockLevel(key)
end

function StoreKit.lockText(key: string): string
	return string.format("Unlocks at Ranch Level %d", StoreKit.unlockLevel(key))
end

-- Currency -------------------------------------------------------------------------

-- key: coins | gems | treats | stardust | ribbons | friendship | food.<flavor> | token.<event>
function StoreKit.balance(store, key: string): number
	local cur = StoreKit.tbl(store, "profile.Currency")
	local head, tail = string.match(key, "^(%w+)%.(.+)$")
	if head == "food" then
		return tonumber(asTable(cur.food)[tail]) or 0
	elseif head == "token" then
		return tonumber(asTable(cur.tokens)[tail]) or 0
	end
	return tonumber(cur[key]) or 0
end

function StoreKit.foodTotal(store): number
	local total = 0
	for _, id in Config.Food.Ids do
		total += StoreKit.balance(store, "food." .. id)
	end
	return total
end

-- The running seasonal event's id (Config.Events calendar on the server clock), or nil.
function StoreKit.activeEvent(): string?
	return Config.Events.ActiveId(workspace:GetServerTimeNow())
end

-- Currency key for one entry of a price table ({ coins = n }, { token = n }, …).
function StoreKit.costKey(key: string, eventId: string?): string
	if key == "token" then
		return "token." .. tostring(eventId or StoreKit.activeEvent() or "")
	end
	return key
end

function StoreKit.iconFor(key: string): string
	local head = string.match(key, "^(%w+)") or key
	local map = {
		coins = "coin",
		gems = "gem",
		treats = "treat",
		stardust = "stardust",
		ribbons = "ribbon",
		friendship = "friendship",
		token = "token",
		food = "food",
		xp = "xp",
	}
	return map[head] or "coin"
end

function StoreKit.canAfford(store, cost: { [string]: number }?, eventId: string?): boolean
	for key, amount in asTable(cost) do
		if StoreKit.balance(store, StoreKit.costKey(key, eventId)) < amount then
			return false
		end
	end
	return true
end

-- How many times `cost` fits into the player's balances.
function StoreKit.affordCount(store, cost: { [string]: number }?, eventId: string?): number
	local best = math.huge
	for key, amount in asTable(cost) do
		if amount > 0 then
			best = math.min(best, math.floor(StoreKit.balance(store, StoreKit.costKey(key, eventId)) / amount))
		end
	end
	return if best == math.huge then 0 else best
end

-- Monetization -----------------------------------------------------------------------

function StoreKit.hasPass(store, key: string): boolean
	return asTable(StoreKit.tbl(store, "session.Monetization").passes)[key] == true
end

function StoreKit.adsLeft(store, placement: string, now: number): number
	local def = Config.Monetization.Ads[placement]
	if not def or not Config.Flags.RewardedAds then
		return 0
	end
	local ads = StoreKit.tbl(store, "profile.Monetization.ads")
	local used = 0
	if ads.day == StoreKit.day(now) then
		used = tonumber(asTable(ads.counts)[placement]) or 0
	end
	return math.max(0, def.cap - used)
end

-- Ranch ------------------------------------------------------------------------------

function StoreKit.pens(store): { any }
	return StoreKit.tbl(store, "profile.Ranch.pens")
end

-- Live jar for one pen, using the same rule as the server (Logic/Jar.Value): coins already
-- in the jar are never lost when the pen's rate drops.
function StoreKit.jar(store, pen: number, now: number): (number, number, number)
	local p = StoreKit.pens(store)[pen]
	if type(p) ~= "table" then
		return 0, 0, 0
	end
	local ranch = StoreKit.tbl(store, "session.Ranch")
	local rate = tonumber(asTable(ranch.rates)[pen]) or 0
	local capSeconds = tonumber(asTable(ranch.caps)[pen])
	if not capSeconds then
		local tier = Config.Economy.JarTiers[math.max(1, tonumber(p.jarTier) or 1)]
		capSeconds = if tier then tier.seconds else 3600
	end
	local full = rate * capSeconds
	local jar = tonumber(p.jar) or 0
	local jarAt = tonumber(p.jarAt) or now
	local value = Jar.Value(jar, rate, jarAt, now, capSeconds)
	return math.max(0, value), math.max(full, jar), rate
end

function StoreKit.jarTotal(store, now: number): number
	local total = 0
	for i in ipairs(StoreKit.pens(store)) do
		total += (StoreKit.jar(store, i, now))
	end
	return total
end

-- Monsters ---------------------------------------------------------------------------

function StoreKit.monsters(store): { [string]: any }
	return StoreKit.tbl(store, "profile.Monsters.list")
end

function StoreKit.monster(store, id: string?): any
	if not id then
		return nil
	end
	local m = StoreKit.monsters(store)[id]
	return if type(m) == "table" and m.line and Config.Species.ById[m.line] then m else nil
end

-- Eggs -------------------------------------------------------------------------------

function StoreKit.slotCount(store): number
	return math.clamp(StoreKit.num(store, "session.Eggs.slotCount", 1), 1, Config.Economy.Incubators.maxSlots)
end

function StoreKit.readyEggs(store, now: number): number
	local n = 0
	local slots = StoreKit.tbl(store, "profile.Eggs.slots")
	for i = 1, StoreKit.slotCount(store) do
		local s = slots[i]
		if type(s) == "table" and s.type and (tonumber(s.endsAt) or math.huge) <= now then
			n += 1
		end
	end
	return n
end

-- Expeditions & quests (HUD badges) ---------------------------------------------------

function StoreKit.finishedExpeditions(store, now: number): number
	local n = 0
	for _, s in ipairs(StoreKit.tbl(store, "profile.Expeditions.slots")) do
		if type(s) == "table" and s.state == "running" and (tonumber(s.endsAt) or math.huge) <= now then
			n += 1
		end
	end
	return n
end

local dailyById, achievementById
function StoreKit.claimableQuests(store): number
	if not dailyById then
		dailyById, achievementById = {}, {}
		for _, q in Config.Quests.DailyPool or {} do
			dailyById[q.id] = q
		end
		for _, q in Config.Quests.Achievements or {} do
			achievementById[q.id] = q
		end
	end
	local n = 0
	local quests = StoreKit.tbl(store, "profile.Quests")
	for _, entry in ipairs(asTable(asTable(quests.daily).list)) do
		local def = type(entry) == "table" and dailyById[entry.id]
		if def and not entry.claimed and (tonumber(entry.progress) or 0) >= (def.target or 1) then
			n += 1
		end
	end
	for id, entry in asTable(quests.achievements) do
		local def = achievementById[id]
		if def and type(entry) == "table" and not entry.claimed and (tonumber(entry.progress) or 0) >= (def.target or 1) then
			n += 1
		end
	end
	return n
end

-- Helpers ----------------------------------------------------------------------------

function StoreKit.watch(store, paths: { string }, fn: () -> ())
	local conns = {}
	local active, queued = false, false
	local function schedule()
		if queued or not active then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			if active then
				local ok, err = xpcall(fn, debug.traceback)
				if not ok then
					warn("[StoreKit.watch] " .. tostring(err))
				end
			end
		end)
	end
	return {
		Start = function()
			if active then
				return
			end
			active = true
			for _, path in paths do
				table.insert(conns, store:Observe(path, schedule))
			end
			schedule()
		end,
		Stop = function()
			active = false
			for _, conn in conns do
				conn:Disconnect()
			end
			table.clear(conns)
		end,
		Refresh = schedule,
	}
end

-- Kernel error codes as player-facing text (anything else is already a message).
local ERROR_TEXT = {
	NotAvailable = "Not available yet",
	UnknownAction = "Not available yet",
	TooFast = "Slow down a little and try again",
	BadRequest = "Something went wrong. Try again",
}

function StoreKit.errorText(err: any): string
	return ERROR_TEXT[err] or tostring(err or "Something went wrong")
end

function StoreKit.request(ctx, action: string, payload: any?): (boolean, any)
	local ok, res = ctx.Net:RequestOnce(action, payload)
	if not ok and res ~= "Busy" then
		ctx:Toast(StoreKit.errorText(res), "error")
	elseif ok and string.find(action, ".Buy", 1, true) then
		ctx:Sound("Purchase") -- Shop.BuyEgg, Shop.BuyFood, Accessories.Buy, …
	end
	return ok, res
end

-- Cuts text to at most maxBytes bytes (the server's limit) on a UTF-8 character boundary,
-- so an emoji or accented letter is never split in half.
function StoreKit.clip(text: string, maxBytes: number): string
	if #text <= maxBytes then
		return text
	end
	local cut = 0
	local ok = pcall(function()
		for pos in utf8.codes(text) do
			local nextPos = utf8.offset(text, 2, pos) or #text + 1
			if nextPos - 1 > maxBytes then
				break
			end
			cut = nextPos - 1
		end
	end)
	return string.sub(text, 1, if ok then cut else maxBytes)
end

return StoreKit
