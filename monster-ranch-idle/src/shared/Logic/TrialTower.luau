--[[
	Logic/TrialTower (update 3.12 · Honey & stars): the Trial Tower's pure rules (Config/TrialTower).

	TrialTower.IsBoss(floor) -> boolean
	TrialTower.Region(floor) -> regionId        the region band the floor is fought in
	TrialTower.Power(floor) -> number           one enemy's power on that floor (a boss: × BossMult)
	TrialTower.Enemies(week, floor) -> { enemy record }
	    the same for everyone that week: a seeded stage of the floor's region (a boss floor: one of
	    its bosses), each record's statMult set so its power is Power(floor)
	TrialTower.Preview(week, floor) -> { boss, region, list = { { name, line, form, lv, rarity, boss } } }
	TrialTower.FightSeed(userId, week, floor, n) -> number   n = fights so far (the server's count)
	TrialTower.Fight(members, week, floor, seed) -> BattleReplay   (Logic/BattleSim, boss flag on boss floors)
	TrialTower.Milestone(floor) -> { Reward }?  nil unless floor is a milestone
	TrialTower.NextMilestone(best) -> number    the next milestone floor above `best`
	TrialTower.RecordReward(floor) -> { Reward }?  nil unless floor is a record floor
]]

local Config = require(script.Parent.Parent.Config)
local BattleSim = require(script.Parent.BattleSim)
local Formulas = require(script.Parent.Formulas)
local Rng = require(script.Parent.Rng)

local Cfg = Config.TrialTower
local Regions = Config.Regions

local TrialTower = {}

function TrialTower.IsBoss(floor: number): boolean
	return floor % Cfg.BossEvery == 0
end

function TrialTower.Region(floor: number): string
	local index = math.clamp(math.ceil(floor / Cfg.RegionFloors), 1, #Regions.List)
	return Regions.List[index].id
end

function TrialTower.Power(floor: number): number
	return Cfg.BasePower * Cfg.Growth ^ (math.max(1, floor) - 1)
end

local function bossStages(region): { number }
	local list = {}
	for stage in region.bosses or {} do
		table.insert(list, stage)
	end
	table.sort(list)
	return list
end

-- A non-boss stage of the region, seeded.
local function waveStage(rng, region): number
	local stages = Regions.Stages(region.id)
	for _ = 1, 20 do
		local stage = rng:Int(1, stages)
		if not (region.bosses and region.bosses[stage]) then
			return stage
		end
	end
	return 1
end

function TrialTower.Enemies(week: number, floor: number)
	local regionId = TrialTower.Region(floor)
	local region = Regions.ById[regionId]
	local rng = Rng.new(Rng.seed("tower", week, floor))
	local seed = rng:Int(1, 2147483646)
	local enemies
	local target = TrialTower.Power(floor)
	local bosses = bossStages(region)
	if TrialTower.IsBoss(floor) and #bosses > 0 then
		enemies = BattleSim.BuildEnemies(regionId, rng:Pick(bosses), seed)
		target *= Cfg.BossMult
	else
		enemies = BattleSim.BuildEnemies(regionId, waveStage(rng, region), seed)
	end
	for _, record in enemies do
		local base = math.max(1, Formulas.MonsterPower(record))
		record.statMult = target / base
	end
	return enemies
end

function TrialTower.Preview(week: number, floor: number)
	local list = {}
	local boss = false
	for _, record in TrialTower.Enemies(week, floor) do
		boss = boss or record.boss == true
		local name = record.name
		if name == nil or name == "" then
			local entry = Config.Species.FormById[record.form]
			name = if entry then entry.form.name else record.form
		end
		table.insert(list, {
			name = name,
			line = record.line,
			form = record.form,
			lv = record.lv,
			rarity = record.rarity,
			boss = record.boss == true,
		})
	end
	return { boss = boss, region = TrialTower.Region(floor), list = list }
end

function TrialTower.FightSeed(userId: number, week: number, floor: number, n: number): number
	return Rng.seed("tower_fight", userId, week, floor, n) % 2147483646 + 1
end

function TrialTower.Fight(members, week: number, floor: number, seed: number)
	local enemies = TrialTower.Enemies(week, floor)
	return BattleSim.Simulate(members, enemies, seed, { boss = TrialTower.IsBoss(floor) })
end

function TrialTower.Milestone(floor: number)
	if floor <= 0 or floor % Cfg.MilestoneEvery ~= 0 then
		return nil
	end
	local steps = floor // Cfg.MilestoneEvery
	local items = {
		{ kind = "coins", seconds = Cfg.MilestoneSeconds * steps, amount = 0 },
		{ kind = "stardust", amount = Cfg.MilestoneDust * steps },
	}
	local gems = Cfg.MilestoneGems[floor]
	if gems then
		table.insert(items, { kind = "gems", amount = gems })
	end
	return items
end

function TrialTower.NextMilestone(best: number): number
	return (best // Cfg.MilestoneEvery + 1) * Cfg.MilestoneEvery
end

function TrialTower.RecordReward(floor: number)
	if floor <= 0 or floor % Cfg.RecordEvery ~= 0 then
		return nil
	end
	return { { kind = "gems", amount = Cfg.RecordGems } }
end

return TrialTower
