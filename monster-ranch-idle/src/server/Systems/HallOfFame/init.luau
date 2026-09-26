--[[
	HallOfFame (S6): prestige layer 1. Retiring an Adult at its level cap turns it into a
	statue, adds a permanent Legacy coin bonus to its element(s) (capped per element) and pays
	Stardust + Star Shards. Stardust buys permanent upgrades that other systems read through the
	providers registered in Start().

	Save section (profile.HallOfFame):
	  entries    = { { appearance, retiredAt, rarity, element } }   -- newest first, ≤ Config.MaxEntries
	  legacy     = { [element] = pct }                              -- fraction (0.05 = +5%), ≤ LegacyCapPerElement
	  upgrades   = { [upgradeId] = level }
	  starShards = number

	Providers (registered in Start with systems that are plugged in; absent ones are skipped):
	  Ranch:RegisterRateModifier("legacy", fn(player, elements) -> highest legacy among elements)
	  Ranch:RegisterJarBonus("jar_cap", fn(player) -> seconds)
	  Eggs:RegisterSpeedProvider("incubator_speed", fn(player) -> fraction)
	  Monsters:RegisterMoodFloorProvider(fn(player) -> mood floor)
	  Boss:RegisterDamageModifier("boss_power", fn(player) -> fraction)
	  Breeding:RegisterBreedsPerDayBonus("daily_breed", fn(player) -> breeds)
	  Expeditions:RegisterLootModifier("expedition_loot", fn(player) -> fraction)

	Public API (other systems):
	  HallOfFame:GetLegacy(player, element) -> pct
	  HallOfFame:UpgradeLevel(player, upgradeId) -> number
	  HallOfFame:UpgradeEffect(player, upgradeId, effectKey) -> number   -- level × effect (0 when not bought)
	  HallOfFame:Statues(player) -> { Appearance }                       -- newest Config.MaxStatues
	  HallOfFame:RetiredCount(player) -> number
	  HallOfFame:StarShards(player) -> number
	  HallOfFame:SpendStarShards(player, amount, reason) -> boolean      -- 3.3: the Mastery shop
	  HallOfFame:AddStarShards(player, amount, reason)                   -- 3.3: Mastery rewards
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local Appearance = require(Shared.Logic.Appearance)

local HallOfFame = {
	Name = "HallOfFame",
	Dependencies = { "Currency", "Progression", "Monsters" },
	OptionalDependencies = { "Ranch", "Eggs", "Boss", "Breeding", "Expeditions" },
}

HallOfFame.Profile = {
	Version = 1,
	Default = function()
		return { entries = {}, legacy = {}, upgrades = {}, starShards = 0 }
	end,
}

local DEFAULT_MAX_ENTRIES = 100

local ctx
local Config -- Config.HallOfFame
local Currency, Progression, Monsters

-- Legacy percentages are sums of small fractions; round so caps compare exactly.
local function round4(x: number): number
	return math.floor(x * 10000 + 0.5) / 10000
end

local function mustSection(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

-- Public API ---------------------------------------------------------------------------

function HallOfFame:GetLegacy(player, element: string): number
	local s = ctx:Section(player)
	return s and s.legacy[element] or 0
end

function HallOfFame:UpgradeLevel(player, upgradeId: string): number
	local s = ctx:Section(player)
	return s and s.upgrades[upgradeId] or 0
end

function HallOfFame:UpgradeEffect(player, upgradeId: string, effectKey: string): number
	local def = Config.UpgradeById[upgradeId]
	local per = def and def.effect[effectKey]
	if type(per) ~= "number" then
		return 0
	end
	return HallOfFame:UpgradeLevel(player, upgradeId) * per
end

-- Every monster this player has retired (statues shown are capped at MaxStatues).
function HallOfFame:RetiredCount(player): number
	local s = ctx:Section(player)
	return if s then #s.entries else 0
end

function HallOfFame:Statues(player)
	local s = ctx:Section(player)
	local list = {}
	if not s then
		return list
	end
	for i = 1, math.min(Config.MaxStatues, #s.entries) do
		list[i] = s.entries[i].appearance
	end
	return list
end

function HallOfFame:StarShards(player): number
	local s = ctx:Section(player)
	return s and s.starShards or 0
end

function HallOfFame:SpendStarShards(player, amount: number, reason: string): boolean
	local s = ctx:Section(player)
	if not s or type(amount) ~= "number" or amount ~= amount or amount < 0 or (s.starShards or 0) < amount then
		return false
	end
	s.starShards -= amount
	ctx:Dirty(player, "starShards")
	ctx.Analytics.Custom(player, "StarShardsSpent", amount, { reason = reason })
	return true
end

function HallOfFame:AddStarShards(player, amount: number, reason: string)
	local s = ctx:Section(player)
	if not s or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	s.starShards = (s.starShards or 0) + math.floor(amount)
	ctx:Dirty(player, "starShards")
	ctx.Analytics.Custom(player, "StarShardsEarned", amount, { reason = reason })
end

-- Retire -------------------------------------------------------------------------------

local function checkRetirable(player, m)
	if not m then
		ctx:Fail("That monster doesn't exist")
	end
	local name = Formulas.DisplayName(m)
	if m.stage < 3 then
		ctx:Fail("Only Adults can retire")
	end
	local cap = Formulas.LevelCap(m)
	if (m.lv or 1) < cap then
		ctx:Fail(string.format("Reach level %d to retire %s", cap, name))
	end
	if m.busy then
		ctx:Fail(name .. " is busy")
	end
	if m.locked then
		ctx:Fail(name .. " is locked. Unlock it first")
	end
	if Monsters:Count(player) <= 1 then
		ctx:Fail("You need to keep at least one monster")
	end
end

local function addLegacy(player, s, elements: { string }, pct: number): number
	local best = 0
	for _, element in elements do
		local before = s.legacy[element] or 0
		local after = round4(math.min(Config.LegacyCapPerElement, before + pct))
		if after > before then
			s.legacy[element] = after
			ctx:Dirty(player, "legacy", element)
			best = math.max(best, round4(after - before))
		end
	end
	return best
end

local function retire(player, id: string)
	local s = mustSection(player)
	Progression:Require(player, Config.Unlock)
	local m = Monsters:Get(player, id)
	checkRetirable(player, m)

	local rarity = ctx.Config.Rarities.List[m.rarity]
	local elements = table.clone(Formulas.Elements(m))
	local appearance = Monsters:Appearance(player, id) or Appearance.Of(m)
	if not Monsters:Remove(player, id, "retire") then
		ctx:Fail("That monster can't retire right now")
	end

	table.insert(s.entries, 1, {
		appearance = appearance,
		retiredAt = ctx:Now(),
		rarity = m.rarity,
		element = elements[1],
	})
	local maxEntries = Config.MaxEntries or DEFAULT_MAX_ENTRIES
	while #s.entries > maxEntries do
		table.remove(s.entries)
	end
	ctx:Dirty(player, "entries")

	local gained = addLegacy(player, s, elements, rarity.legacyPct)
	local stardust = rarity.stardust
	Currency:Add(player, "stardust", stardust, "retire")
	local shards = Config.StarShardsPerRetire[m.rarity] or 0
	if shards > 0 then
		s.starShards += shards
		ctx:Dirty(player, "starShards")
	end

	ctx.Bus:Publish("Retired", player, { rarity = m.rarity, element = elements[1] })
	ctx.Bus:Publish("RanchXP", player, { amount = ctx.Config.Unlocks.XP.retire, reason = "retire" })
	ctx.Bus:Publish("RateModifiersChanged", player, {})
	ctx.Net:Fire(player, "HallOfFame.Retired", { appearance = appearance, stardust = stardust })
	ctx.Analytics.Custom(player, "Retired", m.rarity, { line = m.line })
	ctx:RequestSave(player)
	return { stardust = stardust, legacy = gained, starShards = shards }
end

-- Providers ----------------------------------------------------------------------------

local function registerProviders()
	local function legacyFor(player, elements)
		local best = 0
		for _, element in elements or {} do
			best = math.max(best, HallOfFame:GetLegacy(player, element))
		end
		return best
	end

	local Ranch = ctx:GetSystem("Ranch")
	if Ranch then
		Ranch:RegisterRateModifier("legacy", legacyFor)
		Ranch:RegisterJarBonus("jar_cap", function(player)
			return HallOfFame:UpgradeEffect(player, "jar_cap", "jarCapSeconds")
		end)
	end

	local Eggs = ctx:GetSystem("Eggs")
	if Eggs then
		Eggs:RegisterSpeedProvider("incubator_speed", function(player)
			return HallOfFame:UpgradeEffect(player, "incubator_speed", "hatchSpeed")
		end)
	end

	Monsters:RegisterMoodFloorProvider(function(player)
		-- A floor, not a stacking bonus: any level gives the configured floor.
		local def = Config.UpgradeById.mood_floor
		if def and HallOfFame:UpgradeLevel(player, "mood_floor") > 0 then
			return def.effect.moodFloor
		end
		return 0
	end)

	local Boss = ctx:GetSystem("Boss")
	if Boss then
		Boss:RegisterDamageModifier("boss_power", function(player)
			return HallOfFame:UpgradeEffect(player, "boss_power", "bossDmgPct")
		end)
	end

	local Breeding = ctx:GetSystem("Breeding")
	if Breeding then
		Breeding:RegisterBreedsPerDayBonus("daily_breed", function(player)
			return HallOfFame:UpgradeEffect(player, "daily_breed", "breedsPerDay")
		end)
	end

	local Expeditions = ctx:GetSystem("Expeditions")
	if Expeditions then
		Expeditions:RegisterLootModifier("expedition_loot", function(player)
			return HallOfFame:UpgradeEffect(player, "expedition_loot", "lootPct")
		end)
	end
end

-- Lifecycle ----------------------------------------------------------------------------

function HallOfFame.Init(context)
	ctx = context
	Config = ctx.Config.HallOfFame
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")

	ctx.Net:Handle("HallOfFame.Retire", function(player, payload)
		return retire(player, payload.id)
	end)

	ctx.Net:Handle("HallOfFame.BuyUpgrade", function(player, payload)
		local s = mustSection(player)
		Progression:Require(player, Config.Unlock)
		local def = Config.UpgradeById[payload.upgrade]
		if not def then
			ctx:Fail("That upgrade doesn't exist")
		end
		local level = s.upgrades[def.id] or 0
		if level >= def.maxLevel then
			ctx:Fail(def.name .. " is already maxed")
		end
		Currency:Charge(player, { stardust = def.cost[level + 1] }, "hof_upgrade")
		s.upgrades[def.id] = level + 1
		ctx:Dirty(player, "upgrades", def.id)
		ctx.Bus:Publish("RateModifiersChanged", player, {})
		ctx.Analytics.Custom(player, "HallUpgrade", level + 1, { upgrade = def.id })
		return { level = level + 1 }
	end)
end

function HallOfFame.Start()
	registerProviders()
end

return HallOfFame
