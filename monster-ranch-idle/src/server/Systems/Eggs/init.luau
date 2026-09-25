--[[
	Eggs (S3): the egg inventory, the five incubator slots, hatching and the starter egg.

	Save section (profile.Eggs):
	  list    = { [eggId] = { type, source, t } }       -- eggId = "e<n>"; eggs waiting in storage
	  slots   = { [1..5] = { egg = eggId|false, type = eggType|"starter"|false, startedAt, endsAt } }  -- always 5
	            (Version 2, update 3.2: Migrate appends the 5th empty slot to 4-slot saves)
	  nextId  = number
	  pity    = { starlit, royal }                       -- Starlit pity / Royal lucky meter counters
	  hatched = number                                   -- lifetime hatches
	Session (session.Eggs): { slotCount, speed }         -- usable slots 1..5; hatch-time reduction

	An egg leaves `list` when it is placed in an incubator (the slot keeps its id), so eggs
	that are incubating can never be traded or counted as storage. Timers are fixed at
	placement: `endsAt = now + hatchSeconds × (1 − speed)`. Eggs that finish while the
	player is offline wait in their slot; the Welcome Back screen lists them.

	The starter egg lets the player choose its line: Eggs.Hatch { slot, starter = lineId }
	with a line from Config.Eggs.Starter.lines (random when omitted). Eggs.HatchAll skips
	the starter so the choice is never made for the player.

	Public API (other systems):
	  Eggs:Add(player, eggType, source, amount?) -> { eggId }   -- grants never drop eggs (no cap)
	  Eggs:Insert(player, record, source) -> eggId               -- trade receive (new id)
	  Eggs:Remove(player, eggId) -> record?                      -- storage eggs only
	  Eggs:Get(player, eggId) -> record?
	  Eggs:Count(player) -> number                               -- eggs in storage
	  Eggs:Room(player) -> number                                -- storage left under Economy.MaxEggs
	  Eggs:SlotCount(player) -> 1..5
	  Eggs:Speed(player) -> fraction                             -- summed providers, capped
	  Eggs:RefreshSpeed(player)                                  -- call after a provider's input changes
	  Eggs:RegisterSpeedProvider(key, fn(player) -> fraction)    -- 0.1 = 10% faster
	  Eggs:PublicSlots(player) -> { { type, endsAt } }           -- filled slots (Plots view)

	Player-initiated gains (Shop.BuyEgg, Shop.ClaimFreeEgg) check Room; Trade should too.
	Queries Monetization:HasPass(player, "extraIncubator" | "luckyHatcher") and
	Monetization:WatchAd(player, "hatchRush") when Monetization is plugged in.
	Publishes EggAdded, EggHatched, RanchXP, PlotChanged, WelcomeItem; fires Eggs.Hatched.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local EggRoll = require(Shared.Logic.EggRoll)

local Eggs = {
	Name = "Eggs",
	Dependencies = { "Monsters", "Progression" },
	OptionalDependencies = { "Monetization" },
}

-- Saved slots: always this many (4 earned by level + 1 from the Extra Incubator pass).
local SLOTS = 5

local function emptySlot()
	return { egg = false, type = false, startedAt = 0, endsAt = 0 }
end

Eggs.Profile = {
	Version = 2,
	Default = function()
		local slots = {}
		for i = 1, SLOTS do
			slots[i] = emptySlot()
		end
		return { list = {}, slots = slots, nextId = 1, pity = { starlit = 0, royal = 0 }, hatched = 0 }
	end,
	Migrate = function(section, fromVersion)
		-- v2 (update 3.2): incubator 4 at Ranch Level 62 makes 5 slots with the pass. Old saves
		-- keep slots 1..4 exactly as they were (eggs and timers) and gain an empty 5th.
		if fromVersion < 2 and type(section.slots) == "table" then
			for i = #section.slots + 1, SLOTS do
				section.slots[i] = emptySlot()
			end
		end
		return section
	end,
}

local ctx
local Config
local Monsters, Progression

local speedProviders = {} -- [key] = fn(player) -> fraction
local rushing = {} -- [player] = true while a Hatch Rush ad is showing

-- Helpers ------------------------------------------------------------------------------

local function section(player)
	return ctx:Section(player)
end

local function monetization()
	return ctx:GetSystem("Monetization")
end

local function hasPass(player, key: string): boolean
	local M = monetization()
	if not M then
		return false
	end
	local ok, result = pcall(M.HasPass, M, player, key)
	return ok and result == true
end

local function hatchSeconds(eggType: string): number
	if eggType == "starter" then
		return Config.Eggs.Starter.hatchSeconds
	end
	return Config.Eggs.ById[eggType].hatchSeconds
end

local function isReady(slot, now: number): boolean
	return slot.type ~= false and now >= slot.endsAt
end

-- Keeps exactly SLOTS well-formed entries (old saves, hand-edited data).
local function normalizeSlots(s)
	for i = 1, SLOTS do
		local slot = s.slots[i]
		if type(slot) ~= "table" then
			s.slots[i] = emptySlot()
		else
			slot.egg = slot.egg or false
			slot.type = slot.type or false
			slot.startedAt = slot.startedAt or 0
			slot.endsAt = slot.endsAt or 0
		end
	end
	for i = #s.slots, SLOTS + 1, -1 do
		s.slots[i] = nil
	end
end

local function computeSlotCount(player): number
	local inc = Config.Economy.Incubators
	local earned = 0
	for _, key in inc.slotUnlocks do
		if Progression:IsUnlocked(player, key) then
			earned += 1
		end
	end
	local count = math.max(inc.baseSlots, earned)
	if hasPass(player, "extraIncubator") then
		count += inc.passSlots
	end
	return math.clamp(count, 1, math.min(inc.maxSlots, SLOTS))
end

local function refreshSession(player)
	local session = ctx:Session(player)
	if not session or not section(player) then
		return
	end
	local slotCount = computeSlotCount(player)
	local speed = Eggs:Speed(player)
	if session.slotCount ~= slotCount or session.speed ~= speed then
		session.slotCount = slotCount
		session.speed = speed
		ctx:DirtySession(player)
	end
end

local function watchAd(player, placement: string)
	local M = monetization()
	if not M or not Config.Flags.RewardedAds then
		ctx:Fail("Ads aren't available")
	end
	if M.CanWatchAd then
		local ok, why = M:CanWatchAd(player, placement)
		if not ok then
			ctx:Fail(why or "Ads aren't available")
		end
	elseif M.AdsLeft and M:AdsLeft(player, placement) <= 0 then
		ctx:Fail("No more ads today. Come back tomorrow!")
	end
	if not M:WatchAd(player, placement) then
		ctx:Fail("The ad didn't finish")
	end
end

local function slotArg(player, index: number)
	if index > SLOTS then
		ctx:Fail("That incubator is locked")
	end
	return section(player).slots[index]
end

local function newEggId(s): string
	local id = "e" .. tostring(s.nextId)
	s.nextId += 1
	return id
end

-- Public API ------------------------------------------------------------------------------

function Eggs:RegisterSpeedProvider(key: string, fn)
	speedProviders[key] = fn
end

function Eggs:Speed(player): number
	local total = 0
	for _, provider in speedProviders do
		local ok, value = pcall(provider, player)
		if ok and type(value) == "number" and value == value then
			total += value
		end
	end
	return math.clamp(total, 0, Config.Economy.IncubatorSpeedCap)
end

function Eggs:RefreshSpeed(player)
	refreshSession(player)
end

function Eggs:SlotCount(player): number
	if not section(player) then
		return Config.Economy.Incubators.baseSlots
	end
	return computeSlotCount(player)
end

function Eggs:Get(player, id: string)
	local s = section(player)
	return s and s.list[id]
end

function Eggs:Count(player): number
	local s = section(player)
	if not s then
		return 0
	end
	local n = 0
	for _ in s.list do
		n += 1
	end
	return n
end

function Eggs:Room(player): number
	return math.max(0, Config.Economy.MaxEggs - Eggs:Count(player))
end

local function store(player, record, source: string): string
	local s = section(player)
	local id = newEggId(s)
	s.list[id] = record
	ctx:Dirty(player, "list", id)
	ctx:Dirty(player, "nextId")
	ctx.Bus:Publish("EggAdded", player, { id = id, type = record.type, source = source })
	return id
end

function Eggs:Add(player, eggType: string, source: string, amount: number?): { string }
	local ids = {}
	if not section(player) then
		return ids
	end
	if not Config.Eggs.ById[eggType] then
		warn("[Eggs] Add: unknown egg type " .. tostring(eggType))
		return ids
	end
	for _ = 1, math.max(1, math.floor(amount or 1)) do
		table.insert(ids, store(player, { type = eggType, source = source, t = ctx:Now() }, source))
	end
	return ids
end

function Eggs:Insert(player, record, source: string): string?
	if not section(player) or type(record) ~= "table" or not Config.Eggs.ById[record.type] then
		return nil
	end
	return store(player, { type = record.type, source = source, t = ctx:Now() }, source)
end

function Eggs:Remove(player, id: string)
	local s = section(player)
	local record = s and s.list[id]
	if not record then
		return nil
	end
	s.list[id] = nil
	ctx:Dirty(player, "list", id)
	return record
end

function Eggs:PublicSlots(player): { { type: string, endsAt: number } }
	local out = {}
	local s = section(player)
	if not s then
		return out
	end
	for _, slot in s.slots do
		if slot.type then
			table.insert(out, { type = slot.type, endsAt = slot.endsAt })
		end
	end
	return out
end

-- Placing & hatching ----------------------------------------------------------------------

local function place(player, index: number, eggId: string): number
	local s = section(player)
	local record = s.list[eggId]
	local now = ctx:Now()
	local seconds = hatchSeconds(record.type) * (1 - Eggs:Speed(player))
	local slot = s.slots[index]
	slot.egg = eggId
	slot.type = record.type
	slot.startedAt = now
	slot.endsAt = now + math.max(1, math.floor(seconds + 0.5))
	s.list[eggId] = nil
	ctx:Dirty(player, "list", eggId)
	ctx:Dirty(player, "slots")
	return slot.endsAt
end

-- "Best" = the most valuable egg first (highest shop order), oldest first within a type.
local function bestEggs(s): { string }
	local ids = {}
	for id in s.list do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local ra, rb = s.list[a], s.list[b]
		local oa = (Config.Eggs.ById[ra.type] or { order = 0 }).order
		local ob = (Config.Eggs.ById[rb.type] or { order = 0 }).order
		if oa ~= ob then
			return oa > ob
		end
		if ra.t ~= rb.t then
			return ra.t < rb.t
		end
		return (tonumber(string.sub(a, 2)) or 0) < (tonumber(string.sub(b, 2)) or 0)
	end)
	return ids
end

-- Hatches one ready slot. Returns the monster, or nil and the reason (nothing is changed
-- on failure, so a full ranch never burns pity or the egg).
local function hatch(player, index: number, starterLine: string?)
	local s = section(player)
	local slot = s.slots[index]
	local eggType = slot.type
	local lucky = hasPass(player, "luckyHatcher")
	local spec, result, source
	if eggType == "starter" then
		spec = EggRoll.starter(ctx.Rng, { lucky = lucky, line = starterLine })
		source = "starter"
	else
		local def = Config.Eggs.ById[eggType]
		if not def then
			return nil, "That egg can't hatch"
		end
		spec, result = EggRoll.roll(ctx.Rng, def, { lucky = lucky, pity = s.pity })
		source = "hatch"
	end

	local monster, err = Monsters:Create(player, spec, source)
	if not monster then
		return nil, err or "Couldn't hatch that egg"
	end

	if result then
		s.pity = result.pity
		ctx:Dirty(player, "pity")
	end
	s.slots[index] = emptySlot()
	s.hatched = (s.hatched or 0) + 1
	ctx:Dirty(player, "slots")
	ctx:Dirty(player, "hatched")

	ctx.Net:Fire(player, "Eggs.Hatched", { slot = index, monster = monster, egg = eggType })
	ctx.Bus:Publish("EggHatched", player, { id = monster.id, egg = eggType, rarity = monster.rarity, variant = monster.variant })
	ctx.Bus:Publish("RanchXP", player, { amount = Config.Rarities.List[monster.rarity].xp, reason = "hatch" })
	ctx.Analytics.Custom(player, "EggHatched", monster.rarity, { egg = eggType, variant = tostring(monster.variant) })
	return monster, nil
end

-- Lifecycle ----------------------------------------------------------------------------

function Eggs.Init(context)
	ctx = context
	Config = ctx.Config
	Monsters = ctx:GetSystem("Monsters")
	Progression = ctx:GetSystem("Progression")

	ctx.Net:Handle("Eggs.Place", function(player, payload)
		local s = section(player)
		local slot = slotArg(player, payload.slot)
		if payload.slot > computeSlotCount(player) then
			ctx:Fail("That incubator is locked")
		end
		if slot.type then
			ctx:Fail("That incubator is busy")
		end
		if not s.list[payload.egg] then
			ctx:Fail("That egg doesn't exist")
		end
		local endsAt = place(player, payload.slot, payload.egg)
		ctx.Bus:Publish("PlotChanged", player, {})
		return { endsAt = endsAt }
	end)

	ctx.Net:Handle("Eggs.PlaceAuto", function(player)
		local s = section(player)
		local usable = computeSlotCount(player)
		local free = {}
		for i = 1, usable do
			if not s.slots[i].type then
				table.insert(free, i)
			end
		end
		if #free == 0 then
			ctx:Fail("Every incubator is busy")
		end
		local ids = bestEggs(s)
		if #ids == 0 then
			ctx:Fail("You don't have any eggs. Buy some in the Egg Shop!")
		end
		local placed = 0
		for i, index in free do
			local id = ids[i]
			if not id then
				break
			end
			place(player, index, id)
			placed += 1
		end
		ctx.Bus:Publish("PlotChanged", player, {})
		return { placed = placed }
	end)

	ctx.Net:Handle("Eggs.Hatch", function(player, payload)
		local slot = slotArg(player, payload.slot)
		if not slot.type then
			ctx:Fail("That incubator is empty")
		end
		if not isReady(slot, ctx:Now()) then
			ctx:Fail("That egg isn't ready yet")
		end
		if payload.starter ~= nil and slot.type ~= "starter" then
			ctx:Fail("Only the starter egg lets you choose")
		end
		local monster, err = hatch(player, payload.slot, payload.starter)
		if not monster then
			ctx:Fail(err :: string)
		end
		ctx.Bus:Publish("PlotChanged", player, {})
		return { monster = monster }
	end)

	ctx.Net:Handle("Eggs.HatchAll", function(player)
		local s = section(player)
		local now = ctx:Now()
		local monsters = {}
		local anyReady = false
		local starterReady = false
		local failure
		for index = 1, SLOTS do
			if isReady(s.slots[index], now) and s.slots[index].type == "starter" then
				starterReady = true
			elseif isReady(s.slots[index], now) then
				anyReady = true
				local monster, err = hatch(player, index)
				if not monster then
					failure = err
					break
				end
				table.insert(monsters, monster)
			end
		end
		if not anyReady then
			ctx:Fail(if starterReady then "Tap your starter egg to choose your first monster" else "No eggs are ready yet")
		end
		if #monsters == 0 then
			ctx:Fail(failure :: string)
		end
		if failure then
			ctx:Notify(player, failure, "error")
		end
		ctx.Bus:Publish("PlotChanged", player, {})
		return { monsters = monsters }
	end)

	ctx.Net:Handle("Eggs.HatchRush", function(player, payload)
		local slot = slotArg(player, payload.slot)
		if not slot.type then
			ctx:Fail("That incubator is empty")
		end
		if isReady(slot, ctx:Now()) then
			ctx:Fail("That egg is ready to hatch")
		end
		if rushing[player] then
			ctx:Fail("An ad is already playing")
		end
		local eggId, eggType, endsAt = slot.egg, slot.type, slot.endsAt
		rushing[player] = true
		local ok, err = pcall(watchAd, player, "hatchRush")
		rushing[player] = nil
		if not ok then
			error(err, 0) -- re-raise the player-facing failure
		end
		-- The ad yields: make sure the same egg is still incubating before shortening it.
		local s = section(player)
		local current = s and s.slots[payload.slot]
		if not current or current.egg ~= eggId or current.type ~= eggType or current.endsAt ~= endsAt then
			ctx:Fail("That egg has already hatched")
		end
		current.endsAt = math.max(ctx:Now(), current.endsAt - Config.Monetization.Ads.hatchRush.seconds)
		ctx:Dirty(player, "slots")
		ctx.Bus:Publish("PlotChanged", player, {})
		return { endsAt = current.endsAt }
	end)

	ctx.Bus:Subscribe("LevelUp", function(player)
		refreshSession(player)
	end)
	ctx.Bus:Subscribe("PassesChanged", function(player)
		refreshSession(player)
	end)
	ctx.Bus:Subscribe("WeatherChanged", function()
		for _, player in ctx:Players() do
			refreshSession(player)
		end
	end)

	-- Speed providers can depend on anything (weather, upgrades): keep the session current.
	ctx:Every(10, function()
		for _, player in ctx:Players() do
			refreshSession(player)
		end
	end)
end

function Eggs.PlayerAdded(player, info)
	local s = section(player)
	normalizeSlots(s)
	local now = ctx:Now()

	if info.firstJoin and not s.slots[1].type and (s.hatched or 0) == 0 then
		s.slots[1] = {
			egg = false,
			type = "starter",
			startedAt = now,
			endsAt = now + Config.Eggs.Starter.hatchSeconds,
		}
		ctx:Dirty(player, "slots")
	elseif not info.firstJoin then
		local ready = 0
		for _, slot in s.slots do
			if isReady(slot, now) then
				ready += 1
			end
		end
		if ready > 0 then
			ctx.Bus:Publish("WelcomeItem", player, {
				kind = "eggs",
				text = if ready == 1 then "1 egg ready to hatch" else string.format("%d eggs ready to hatch", ready),
			})
		end
	end

	local session = ctx:Session(player)
	session.slotCount = computeSlotCount(player)
	session.speed = Eggs:Speed(player)
	ctx:DirtySession(player)
end

function Eggs.PlayerRemoving(player)
	rushing[player] = nil
end

return Eggs
