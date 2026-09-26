--[[
	Expeditions (S4): stage battles, timed expeditions and co-op Caravans.

	Save section (profile.Expeditions):
	  cleared = { [regionId] = highestStage }
	  slots   = { [1..4] = { state = "idle"|"running", region = string|false, stage, squad = { id },
	                         startedAt, endsAt, duration, seed, caravan = string|false } }  -- always 4
	  squad   = { id }                   -- the default squad (stage fights and the Stampede)
	Session (session.Expeditions): { slotCount, squadSize, caravan = CaravanLobby|false }
	Global  (global.Expeditions):  { caravans = { [caravanId] = CaravanLobby } }  (see Caravans.luau)

	Actions: Expeditions.SetSquad, Fight, Start, Claim, ClaimAll, Recall,
	         OpenCaravan, JoinCaravan, LeaveCaravan, LaunchCaravan.

	Public API (other systems):
	  Expeditions:GetSquad(player) -> { id }          -- default squad (existing monsters only)
	  Expeditions:SquadPower(player) -> number         -- Σ Formulas.MonsterPower of the default squad
	  Expeditions:Cleared(player, regionId) -> stage   -- highest cleared stage (0 = none)
	  Expeditions:SlotCount(player) -> number
	  Expeditions:SquadSize(player) -> number
	  Expeditions:LootBonus(player, ids) -> pct        -- loot bonus a squad would get right now
	  Expeditions:RegisterLootModifier(key, fn(player) -> pct)
	  Expeditions:ResetForRebirth(player) -> boolean  -- clears region progress (Rebirth)

	Rules:
	  • Stage fights: region unlocked, stage ≤ cleared + 1, whole squad free. Simulated by
	    Logic/BattleSim from a server seed; the client only replays. The `stageRetry` ad
	    (only right after losing that stage) gives +20% stats. First clears pay
	    Regions.FirstClearReward and Ranch XP; re-wins pay nothing (no farming).
	  • Timed expeditions farm a cleared stage. Loot comes from Logic/Loot and is rolled
	    from the slot's saved seed at claim time, so offline runs simply finish on their own.
	    Loot bonus = Lucky Paw traits (≤ Regions.LuckyPawMax members) + Treasure Nose passives
	    + registered modifiers (+ Caravan bonus). Squad members are busy ("expedition").
	  • Recall ends a run early: loot for the time spent, no duration bonus, no caravan bonus.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local BattleSim = require(Shared.Logic.BattleSim)
local Loot = require(Shared.Logic.Loot)
local Format = require(Shared.Logic.Format)
local Caravans = require(script.Caravans)

local Expeditions = {
	Name = "Expeditions",
	Dependencies = { "Currency", "Progression", "Rewards", "Monsters" },
	OptionalDependencies = { "Monetization", "Weather" },
}

local SLOT_COUNT = 4
local BUSY_TAG = "expedition"
local NOTIFY_EVERY = 5

local function newSlot()
	return {
		state = "idle",
		region = false,
		stage = 0,
		squad = {},
		startedAt = 0,
		endsAt = 0,
		duration = 0,
		seed = 0,
		caravan = false,
	}
end

Expeditions.Profile = {
	Version = 1,
	Default = function()
		local slots = {}
		for i = 1, SLOT_COUNT do
			slots[i] = newSlot()
		end
		return { cleared = {}, slots = slots, squad = {} }
	end,
}

local ctx
local Config, Regions
local Progression, Rewards, Monsters

local lootModifiers = {} -- [key] = fn(player) -> pct
local lastLoss = {} -- [player] = "region:stage" of the last lost fight (for the retry ad)
local notified = {} -- [player] = { [slot] = true } finished runs already announced

-- Helpers -------------------------------------------------------------------------------

local function section(player)
	return ctx:Section(player)
end

local function optional(name: string)
	return ctx:GetSystem(name)
end

local function slotsOf(player)
	local s = section(player)
	for i = 1, SLOT_COUNT do
		if type(s.slots[i]) ~= "table" then
			s.slots[i] = newSlot()
		end
	end
	return s.slots
end

local function hasPass(player, key: string): boolean
	local Monetization = optional("Monetization")
	if not Monetization then
		return false
	end
	local ok, owned = pcall(Monetization.HasPass, Monetization, player, key)
	return ok and owned == true
end

local function isNight(): boolean
	local Weather = optional("Weather")
	if not Weather or not Weather.IsNight then
		return false
	end
	local ok, night = pcall(Weather.IsNight, Weather)
	return ok and night == true
end

local function requireRegion(player, regionId: string)
	local region = Regions.ById[regionId]
	if not region then
		ctx:Fail("That region doesn't exist")
	end
	if not Regions.IsOpen(region, ctx:Now()) then
		ctx:Fail(string.format("%s opens on %s", region.name, Format.date(region.opensAt)))
	end
	if not Progression:IsUnlocked(player, region.unlock) then
		ctx:Fail(string.format("%s unlocks at Ranch Level %d", region.name, Progression:UnlockLevel(region.unlock)))
	end
	return region
end

-- A stage must exist in the region, and deeper bands (Coral Depths) have their own unlock.
local function requireStage(player, regionId: string, stage: number)
	if stage > Regions.Stages(regionId) then
		ctx:Fail("That stage doesn't exist")
	end
	local band = Regions.Band(regionId, stage)
	if band.depths and not Progression:IsUnlocked(player, band.unlock) then
		ctx:Fail(string.format("%s unlocks at Ranch Level %d", band.name, Progression:UnlockLevel(band.unlock)))
	end
end

-- Checks a squad the client sent: size, duplicates, ownership, busy. Returns (records?, why?).
local function checkSquad(player, ids: { string }): ({ any }?, string?)
	local size = Expeditions:SquadSize(player)
	if #ids == 0 then
		return nil, "Pick a squad first"
	end
	if #ids > size then
		return nil, string.format("A squad has at most %d monsters", size)
	end
	local seen = {}
	local records = {}
	for _, id in ids do
		if seen[id] then
			return nil, "Each monster can only be picked once"
		end
		seen[id] = true
		local m, why = Monsters:Available(player, id)
		if not m then
			return nil, why
		end
		table.insert(records, m)
	end
	return records, nil
end

local function mustSquad(player, ids: { string })
	local records, why = checkSquad(player, ids)
	if not records then
		ctx:Fail(why or "That squad can't go")
	end
	return records
end

local function powerOf(player, ids: { string }): number
	local total = 0
	for _, id in ids do
		local m = Monsters:Get(player, id)
		if m then
			total += Formulas.MonsterPower(m)
		end
	end
	return total
end

local function refreshSession(player)
	local session = ctx:Session(player)
	if not session or not section(player) then
		return
	end
	session.slotCount = Expeditions:SlotCount(player)
	session.squadSize = Expeditions:SquadSize(player)
	if session.caravan == nil then
		session.caravan = false
	end
	ctx:DirtySession(player)
end

local function setSessionCaravan(player, lobby)
	local session = ctx:Session(player)
	if session then
		session.caravan = lobby or false
		ctx:DirtySession(player, "caravan")
	end
end

local function remaining(seconds: number): string
	return Format.duration(math.max(1, math.ceil(seconds)))
end

-- Public API ----------------------------------------------------------------------------

function Expeditions:RegisterLootModifier(key: string, fn)
	lootModifiers[key] = fn
end

function Expeditions:GetSquad(player): { string }
	local s = section(player)
	if not s then
		return {}
	end
	local out = {}
	for _, id in s.squad do
		if Monsters:Get(player, id) then
			table.insert(out, id)
		end
	end
	return out
end

function Expeditions:SquadPower(player): number
	return powerOf(player, Expeditions:GetSquad(player))
end

function Expeditions:Cleared(player, regionId: string): number
	local s = section(player)
	return s and s.cleared[regionId] or 0
end

-- Rebirth: forget every cleared stage (first clears pay again) and drop squad members
-- that no longer exist. Callers make sure no slot is running first.
function Expeditions:ResetForRebirth(player): boolean
	local s = section(player)
	if not s then
		return false
	end
	s.cleared = {}
	s.squad = Expeditions:GetSquad(player)
	ctx:Dirty(player, "cleared")
	ctx:Dirty(player, "squad")
	return true
end

function Expeditions:SlotCount(player): number
	local n = 0
	for _, key in Regions.Slots.unlocks do
		if Progression:IsUnlocked(player, key) then
			n += 1
		end
	end
	if hasPass(player, "explorer") then
		n += Regions.Slots.passSlots
	end
	return math.min(n, Regions.Slots.max, SLOT_COUNT)
end

function Expeditions:SquadSize(player): number
	local cfg = Regions.SquadSize
	local size = cfg.base
	for _, step in cfg.steps do
		if Progression:IsUnlocked(player, step.unlock) then
			size = math.max(size, step.size)
		end
	end
	return size
end

function Expeditions:LootBonus(player, ids: { string }): number
	local paws = {}
	local passives = 0
	for _, id in ids do
		local m = Monsters:Get(player, id)
		if m then
			local pct = Config.Traits.Sum(Formulas.ActiveTraits(m), "lootPct")
			if pct > 0 then
				table.insert(paws, pct)
			end
			local def = Config.Species.ById[m.line]
			local passive = def and Config.Species.Passives[def.passive]
			if def and def.passive == "lucky" and passive then
				passives += passive.value
			end
		end
	end
	table.sort(paws, function(a, b)
		return a > b
	end)
	local total = passives
	for i = 1, math.min(#paws, Regions.LuckyPawMax or 3) do
		total += paws[i]
	end
	for key, fn in lootModifiers do
		local ok, value = pcall(fn, player)
		if ok and type(value) == "number" and value == value then
			total += value
		elseif not ok then
			warn(string.format("[Expeditions] loot modifier %s failed: %s", key, tostring(value)))
		end
	end
	return math.max(0, total)
end

-- Expedition runs -------------------------------------------------------------------------

local function startRun(player, index: number, regionId: string, stage: number, duration: number, ids: { string }, caravan: string?)
	local slots = slotsOf(player)
	for _, id in ids do
		Monsters:SetBusy(player, id, BUSY_TAG)
	end
	local now = ctx:Now()
	slots[index] = {
		state = "running",
		region = regionId,
		stage = stage,
		squad = table.clone(ids),
		startedAt = now,
		endsAt = now + duration,
		duration = duration,
		seed = ctx.Rng:Int(1, 2147483646),
		caravan = caravan or false,
	}
	ctx:Dirty(player, "slots")
	if notified[player] then
		notified[player][index] = nil
	end
	ctx.Bus:Publish("ExpeditionStarted", player, { slot = index, duration = duration })
	ctx.Analytics.Custom(player, "expedition_start", duration, { region = regionId, stage = tostring(stage) })
	return now + duration
end

-- Ends a run and returns its loot (not granted yet) and the seconds it counted for.
local function endRun(player, index: number, partial: boolean)
	local slots = slotsOf(player)
	local slot = slots[index]
	local seconds = slot.duration
	if partial then
		seconds = math.clamp(ctx:Now() - slot.startedAt, 0, slot.duration)
	end
	local pct = Expeditions:LootBonus(player, slot.squad)
	if slot.caravan and not partial then
		pct += Regions.Caravan.lootBonus
	end
	local loot = Loot.ExpeditionLoot(slot.region, slot.stage, seconds, { lootPct = pct, seed = slot.seed, partial = partial })
	if slot.caravan and not partial then
		for _, item in Regions.Caravan.chest do
			table.insert(loot, table.clone(item))
		end
	end
	for _, id in slot.squad do
		local m = Monsters:Get(player, id)
		if m and m.busy == BUSY_TAG then
			Monsters:SetBusy(player, id, false)
		end
	end
	slots[index] = newSlot()
	ctx:Dirty(player, "slots")
	if notified[player] then
		notified[player][index] = nil
	end
	return loot, seconds
end

local function payXP(player, seconds: number, reason: string)
	local amount = math.floor(Config.Unlocks.XP.expeditionPerMinute * seconds / 60)
	if amount > 0 then
		ctx.Bus:Publish("RanchXP", player, { amount = amount, reason = reason })
	end
end

local function claimSlots(player, indices: { number })
	local lists = {}
	local total = 0
	for _, index in indices do
		local slot = slotsOf(player)[index]
		local duration, region, stage, squad = slot.duration, slot.region, slot.stage, table.clone(slot.squad)
		local loot, seconds = endRun(player, index, false)
		table.insert(lists, loot)
		total += seconds
		-- region, stage, squad and loot: glow-up X writes a postcard from them.
		ctx.Bus:Publish(
			"ExpeditionClaimed",
			player,
			{ slot = index, duration = duration, region = region, stage = stage, squad = squad, loot = loot }
		)
		ctx.Analytics.Custom(player, "expedition_claim", duration, nil)
	end
	local granted = Rewards:Grant(player, Loot.Merge(lists), "expedition")
	payXP(player, total, "expedition")
	return granted
end

-- Lifecycle -----------------------------------------------------------------------------------

function Expeditions.Init(context)
	ctx = context
	Config = ctx.Config
	Regions = Config.Regions
	-- Module state is reset here (not at require time) so every kernel starts clean.
	-- Providers register in Start(), which always runs after every Init.
	lootModifiers = {}
	lastLoss = {}
	notified = {}
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")
	Monsters = ctx:GetSystem("Monsters")

	Caravans.Init(ctx, {
		checkSquad = checkSquad,
		powerOf = powerOf,
		slotsOf = slotsOf,
		startRun = startRun,
		requireRegion = requireRegion,
		setSessionCaravan = setSessionCaravan,
		getSquad = function(player)
			return Expeditions:GetSquad(player)
		end,
		slotCount = function(player)
			return Expeditions:SlotCount(player)
		end,
		cleared = function(player, regionId)
			return Expeditions:Cleared(player, regionId)
		end,
		progression = Progression,
	})

	ctx.Net:Handle("Expeditions.SetSquad", function(player, payload)
		local size = Expeditions:SquadSize(player)
		if #payload.ids > size then
			ctx:Fail(string.format("A squad has at most %d monsters", size))
		end
		local seen = {}
		for _, id in payload.ids do
			if seen[id] then
				ctx:Fail("Each monster can only be picked once")
			end
			seen[id] = true
			if not Monsters:Get(player, id) then
				ctx:Fail("That monster doesn't exist")
			end
		end
		section(player).squad = table.clone(payload.ids)
		ctx:Dirty(player, "squad")
		return nil
	end)

	ctx.Net:Handle("Expeditions.Fight", function(player, payload)
		local s = section(player)
		local region = requireRegion(player, payload.region)
		local stage = payload.stage
		requireStage(player, payload.region, stage)
		local cleared = Expeditions:Cleared(player, payload.region)
		if stage > cleared + 1 then
			ctx:Fail(string.format("Clear stage %d first", cleared + 1))
		end
		local ids = Expeditions:GetSquad(player)
		if #ids == 0 then
			ctx:Fail("Pick a squad first")
		end
		local key = payload.region .. ":" .. tostring(stage)
		local statBonus = 0
		if payload.retry then
			if lastLoss[player] ~= key then
				ctx:Fail("You can only retry a stage you just lost")
			end
			local Monetization = optional("Monetization")
			if not Monetization then
				ctx:Fail("Retries aren't available right now")
			end
			lastLoss[player] = nil
			if not Monetization:WatchAd(player, "stageRetry") then
				ctx:Fail("Watch the whole ad to get the retry boost")
			end
			statBonus = Config.Monetization.Ads.stageRetry.statBonus or 0.2
		end
		-- Validate after the ad: it yields, and the squad may have changed meanwhile.
		local members = mustSquad(player, ids)

		local seed = ctx.Rng:Int(1, 2147483646)
		local isBoss = BattleSim.IsBossStage(payload.region, stage)
		local enemies = BattleSim.BuildEnemies(payload.region, stage, seed)
		local replay = BattleSim.Simulate(members, enemies, seed, { night = isNight(), boss = isBoss, statBonus = statBonus })

		local rewards = {}
		if replay.win then
			lastLoss[player] = nil
			local first = stage > cleared
			if first then
				s.cleared[payload.region] = stage
				ctx:Dirty(player, "cleared", payload.region)
				local g = Regions.GlobalIndex(payload.region, stage)
				local items = Regions.FirstClearReward(g, isBoss)
				local boss = region.bosses and region.bosses[stage]
				for _, item in (boss and boss.firstClear) or {} do
					table.insert(items, table.clone(item))
				end
				rewards = Rewards:Grant(player, items, "stage_clear", { silent = true })
				ctx.Bus:Publish("RanchXP", player, { amount = Config.Unlocks.XP.stageClearBase + stage, reason = "stage_clear" })
			end
			ctx.Bus:Publish("StageCleared", player, { region = payload.region, stage = stage, first = first, squad = table.clone(ids) })
			ctx.Analytics.Custom(player, "stage_clear", stage, { region = region.id, first = tostring(first) })
		else
			lastLoss[player] = key
		end
		return { win = replay.win, replay = replay, rewards = rewards }
	end)

	ctx.Net:Handle("Expeditions.Start", function(player, payload)
		Progression:Require(player, "expeditions")
		local index = payload.slot
		if index > Expeditions:SlotCount(player) then
			ctx:Fail("That expedition slot is locked")
		end
		local slot = slotsOf(player)[index]
		if slot.state ~= "idle" then
			ctx:Fail("That slot is already exploring")
		end
		if Caravans.IsReserved(player, index) then
			ctx:Fail("That slot is saved for your caravan")
		end
		requireRegion(player, payload.region)
		requireStage(player, payload.region, payload.stage)
		local cleared = Expeditions:Cleared(player, payload.region)
		if payload.stage > cleared and payload.stage ~= 1 then
			ctx:Fail("Clear this stage before exploring it")
		end
		local duration = tonumber(payload.duration)
		if not duration or Regions.DurationBonus[duration] == nil then
			ctx:Fail("Pick a valid duration")
		end
		mustSquad(player, payload.squad)
		local endsAt = startRun(player, index, payload.region, payload.stage, duration :: number, payload.squad, nil)
		return { endsAt = endsAt }
	end)

	ctx.Net:Handle("Expeditions.Claim", function(player, payload)
		local slot = slotsOf(player)[payload.slot]
		if slot.state ~= "running" then
			ctx:Fail("Nothing to claim in that slot")
		end
		local left = slot.endsAt - ctx:Now()
		if left > 0 then
			ctx:Fail(string.format("Still exploring: back in %s", remaining(left)))
		end
		return { rewards = claimSlots(player, { payload.slot }) }
	end)

	ctx.Net:Handle("Expeditions.ClaimAll", function(player)
		local ready = {}
		local now = ctx:Now()
		for i, slot in slotsOf(player) do
			if slot.state == "running" and slot.endsAt <= now then
				table.insert(ready, i)
			end
		end
		if #ready == 0 then
			ctx:Fail("No expeditions are back yet")
		end
		return { rewards = claimSlots(player, ready) }
	end)

	ctx.Net:Handle("Expeditions.Recall", function(player, payload)
		local slot = slotsOf(player)[payload.slot]
		if slot.state ~= "running" then
			ctx:Fail("That slot isn't exploring")
		end
		if slot.endsAt <= ctx:Now() then
			-- Already back: a recall is just a full claim.
			return { rewards = claimSlots(player, { payload.slot }) }
		end
		local loot, seconds = endRun(player, payload.slot, true)
		local granted = Rewards:Grant(player, loot, "expedition_recall")
		payXP(player, seconds, "expedition")
		return { rewards = granted }
	end)

	ctx.Net:Handle("Expeditions.OpenCaravan", Caravans.Open)
	ctx.Net:Handle("Expeditions.JoinCaravan", Caravans.Join)
	ctx.Net:Handle("Expeditions.LeaveCaravan", Caravans.Leave)
	ctx.Net:Handle("Expeditions.LaunchCaravan", Caravans.Launch)

	ctx.Bus:Subscribe("LevelUp", function(player)
		if ctx:IsReady(player) then
			refreshSession(player)
		end
	end)
	ctx.Bus:Subscribe("PassesChanged", function(player)
		if ctx:IsReady(player) then
			refreshSession(player)
		end
	end)
	ctx.Bus:Subscribe("MonsterRemoved", function(player, detail)
		local s = section(player)
		if not s then
			return
		end
		local index = table.find(s.squad, detail.id)
		if index then
			table.remove(s.squad, index)
			ctx:Dirty(player, "squad")
		end
	end)

	ctx:Every(1, function()
		Caravans.Tick(ctx:Now())
	end)

	-- Tell online players when a run comes back.
	ctx:Every(NOTIFY_EVERY, function()
		local now = ctx:Now()
		for _, player in ctx:Players() do
			local seen = notified[player]
			if seen and section(player) then
				for i, slot in slotsOf(player) do
					if slot.state == "running" and slot.endsAt <= now and not seen[i] then
						seen[i] = true
						ctx:Notify(player, "An expedition is back! Claim its loot.", "success")
					end
				end
			end
		end
	end)
end

function Expeditions.PlayerAdded(player, info)
	notified[player] = {}
	local s = section(player)
	if not s then
		return
	end
	local slots = slotsOf(player)

	-- Busy tags are saved on the monsters; make them agree with the running slots.
	local onRun = {}
	for _, slot in slots do
		if slot.state == "running" then
			for _, id in slot.squad do
				onRun[id] = true
				local m = Monsters:Get(player, id)
				if m and not m.busy then
					Monsters:SetBusy(player, id, BUSY_TAG)
				end
			end
		end
	end
	for id, m in Monsters:All(player) do
		if m.busy == BUSY_TAG and not onRun[id] then
			Monsters:SetBusy(player, id, false)
		end
	end
	local squad = {}
	for _, id in s.squad do
		if Monsters:Get(player, id) then
			table.insert(squad, id)
		end
	end
	s.squad = squad

	-- Runs that came back while the player was away.
	local now = ctx:Now()
	local lastSeen = if info then info.lastSeen or 0 else 0
	local done = 0
	for i, slot in slots do
		if slot.state == "running" and slot.endsAt <= now then
			notified[player][i] = true
			if slot.endsAt > lastSeen then
				done += 1
			end
		end
	end
	if done > 0 then
		ctx.Bus:Publish("WelcomeItem", player, {
			kind = "expedition",
			text = if done == 1 then "1 expedition finished" else string.format("%d expeditions finished", done),
			icon = "expedition",
		})
	end

	local session = ctx:Session(player)
	session.caravan = false
	refreshSession(player)
end

function Expeditions.PlayerRemoving(player)
	Caravans.PlayerRemoving(player)
	lastLoss[player] = nil
	notified[player] = nil
end

return Expeditions
