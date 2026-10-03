--[[
	Logic/TreasureMaps (update 3.13 · Wild things): the Treasure Maps' pure rules (Config/TreasureMaps).

	TreasureMaps.DropSeed(userId, source, n) -> number        n = drop rolls so far (the server's count)
	TreasureMaps.Drops(source, seed) -> number               pieces a drop roll gives (0 or more)
	TreasureMaps.MapSeed(userId, n) -> number                n = maps made so far
	TreasureMaps.Roll(open, seed) -> { region, stage }?      the X: one of `open` = { { region, cleared } }
	                                                         (sorted by region order); nil when empty
	TreasureMaps.Guardian(map) -> { enemy record }           the guardian wave of a map
	                                                         ({ region, stage, seed }), scaled to its power
	TreasureMaps.GuardianPower(map) -> number                the wave's total power (the preview)
	TreasureMaps.Preview(map) -> { region, power, list = { { name, line, form, power } } }
	TreasureMaps.FightSeed(userId, mapId, n) -> number       n = digs so far
	TreasureMaps.Fight(members, map, seed) -> BattleReplay   (Logic/BattleSim, boss flag)
	TreasureMaps.Egg(regionId, stage) -> eggId               the region's egg at that stage
	TreasureMaps.Chest(map) -> { Reward }                    the chest a win opens (seeded by the map)
	TreasureMaps.ChestPreview(map) -> { Reward }             the sure part (coins, gems, egg)
]]

local Config = require(script.Parent.Parent.Config)
local BattleSim = require(script.Parent.BattleSim)
local Formulas = require(script.Parent.Formulas)
local Rng = require(script.Parent.Rng)

local Cfg = Config.TreasureMaps
local Regions = Config.Regions

local TreasureMaps = {}

function TreasureMaps.DropSeed(userId: number, source: string, n: number): number
	return Rng.seed("treasure_drop", userId, source, n) % 2147483646 + 1
end

function TreasureMaps.Drops(source: string, seed: number): number
	if source == "bounty" then
		return Cfg.BountyPieces
	end
	local chance = Cfg.Drops[source]
	if not chance or chance <= 0 then
		return 0
	end
	return if Rng.new(seed):Chance(chance) then 1 else 0
end

function TreasureMaps.MapSeed(userId: number, n: number): number
	return Rng.seed("treasure_map", userId, n) % 2147483646 + 1
end

function TreasureMaps.Roll(open, seed: number)
	if #open == 0 then
		return nil
	end
	local rng = Rng.new(seed)
	local pick = open[rng:Int(1, #open)]
	local top = math.min(pick.cleared, Regions.Stages(pick.region))
	local stage = rng:Int(math.max(1, top - Cfg.StageSpread), math.max(1, top))
	return { region = pick.region, stage = stage }
end

function TreasureMaps.Guardian(map)
	local seed = Rng.seed("treasure_guardian", map.region, map.stage, map.seed) % 2147483646 + 1
	local enemies = BattleSim.BuildEnemies(map.region, map.stage, seed)
	local target = BattleSim.RecommendedPower(map.region, map.stage) * Cfg.GuardianMult / math.max(1, #enemies)
	for _, record in enemies do
		local base = math.max(1, Formulas.MonsterPower(record))
		record.statMult = target / base
	end
	return enemies
end

local function powerOf(record): number
	return math.floor(Formulas.MonsterPower(record) * (record.statMult or 1) + 0.5)
end

function TreasureMaps.GuardianPower(map): number
	local total = 0
	for _, record in TreasureMaps.Guardian(map) do
		total += powerOf(record)
	end
	return total
end

function TreasureMaps.Preview(map)
	local list = {}
	local total = 0
	for _, record in TreasureMaps.Guardian(map) do
		local name = record.name
		if name == nil or name == "" then
			local entry = Config.Species.FormById[record.form]
			name = if entry then entry.form.name else record.form
		end
		local power = powerOf(record)
		total += power
		table.insert(list, { name = name, line = record.line, form = record.form, power = power })
	end
	return { region = map.region, power = total, list = list }
end

function TreasureMaps.FightSeed(userId: number, mapId: number, n: number): number
	return Rng.seed("treasure_fight", userId, mapId, n) % 2147483646 + 1
end

function TreasureMaps.Fight(members, map, seed: number)
	return BattleSim.Simulate(members, TreasureMaps.Guardian(map), seed, { boss = true })
end

function TreasureMaps.Egg(regionId: string, stage: number): string
	local region = Regions.ById[regionId]
	local egg = "meadow"
	for _, entry in (region and region.eggs) or {} do
		if entry.egg ~= "royal" and (entry.fromStage or 1) <= stage then
			egg = entry.egg
		end
	end
	return egg
end

function TreasureMaps.ChestPreview(map)
	local region = Regions.ById[map.region]
	local steps = math.max(0, ((region and region.order) or 1) - 1)
	return {
		{ kind = "coins", seconds = Cfg.ChestSeconds + Cfg.ChestSecondsPerRegion * steps, amount = 0 },
		{ kind = "gems", amount = Cfg.ChestGems + Cfg.ChestGemsPerRegion * steps },
		{ kind = "egg", id = TreasureMaps.Egg(map.region, map.stage), amount = 1 },
	}
end

function TreasureMaps.Chest(map)
	local items = TreasureMaps.ChestPreview(map)
	local rng = Rng.new(Rng.seed("treasure_chest", map.region, map.stage, map.seed))
	if rng:Chance(Cfg.DecorChance) then
		table.insert(items, { kind = "decor", id = rng:Pick(Cfg.Decor), amount = 1 })
	end
	return items
end

return TreasureMaps
