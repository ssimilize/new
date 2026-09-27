--[[
	Bounties (update 3.9 · Family and fortune): the pure rules of Expedition Bounties
	(Config/Bounties). Roblox-free; used by Systems/Expeditions and tested in Bounties.spec.

	Bounty = { region, stage, name, line, seed, done }

	  Bounties.Draw(userId, week, eligible, clearedOf) -> { Bounty }
	      up to Config.Bounties.Count bounties from ("bounty", userId, week). eligible(region) says
	      whether a region is unlocked and open; clearedOf(regionId) is its furthest cleared stage.
	      Regions with nothing cleared are skipped; distinct regions come first; a region gives a
	      second bounty (on another stage) only when there are fewer eligible regions than Count.
	  Bounties.Stages(regionId, cleared) -> { stage }   the non-boss stages a bounty may sit on
	  Bounties.Find(list, regionId, stage) -> (index?, Bounty?)   the undone bounty on that stage
	  Bounties.Monster(bounty) -> enemy record   the wanted monster (statMult, name, aura, bounty)
	  Bounties.Inject(enemies, bounty?, regionId, stage) -> enemies   a new list with the bounty
	      in the front slot when it matches that stage and is not done; else the same list
	  Bounties.Egg(regionId) -> eggId?             the region's first egg (Regions eggs[1])
	  Bounties.EggChance(lootBonus) -> number      min(EggChanceMax, EggChance × (1 + lootBonus))
	  Bounties.RollEgg(bounty, lootBonus) -> boolean   deterministic from the bounty's seed
	  Bounties.Rewards(bounty, lootBonus) -> { Reward }  Config reward (+ the egg when rolled)
]]

local Shared = script.Parent.Parent
local Config = require(Shared.Config)
local Rng = require(script.Parent.Rng)
local BattleSim = require(script.Parent.BattleSim)
local Appearance = require(script.Parent.Appearance)

local Cfg = Config.Bounties
local Regions = Config.Regions
local Species = Config.Species

local Bounties = {}

function Bounties.Stages(regionId: string, cleared: number): { number }
	local region = Regions.ById[regionId]
	local list = {}
	if not region or cleared < 1 then
		return list
	end
	local last = math.min(cleared, Regions.Stages(regionId))
	for stage = math.max(1, last - Cfg.Window + 1), last do
		if not BattleSim.IsBossStage(regionId, stage) then
			table.insert(list, stage)
		end
	end
	return list
end

function Bounties.Draw(userId: number, week: number, eligible: (any) -> boolean, clearedOf: (string) -> number)
	local rng = Rng.new(Rng.seed("bounty", userId, week))
	local pools = {}
	local order = {}
	for _, region in Regions.List do
		if eligible(region) then
			local stages = Bounties.Stages(region.id, clearedOf(region.id))
			if #stages > 0 then
				pools[region.id] = stages
				table.insert(order, region.id)
			end
		end
	end
	rng:Shuffle(order)
	local names = table.clone(Cfg.Names)
	local list = {}
	while #list < Cfg.Count do
		local added = false
		for _, regionId in order do
			local pool = pools[regionId]
			if #list < Cfg.Count and #pool > 0 then
				local stage = table.remove(pool, rng:Int(1, #pool))
				local lines = Regions.Band(regionId, stage).enemyLines
				local name = table.remove(names, rng:Int(1, #names))
				local title = rng:Pick(Cfg.Titles)
				table.insert(list, {
					region = regionId,
					stage = stage,
					name = string.format(title.format, name),
					line = rng:Pick(lines),
					seed = rng:Int(1, 2147483646),
					done = false,
				})
				added = true
			end
		end
		if not added then
			break
		end
	end
	return list
end

function Bounties.Find(list, regionId: string, stage: number)
	for i, b in if type(list) == "table" then list else {} do
		if type(b) == "table" and b.region == regionId and b.stage == stage and not b.done then
			return i, b
		end
	end
	return nil, nil
end

function Bounties.Monster(bounty)
	local level, rarity = BattleSim.StageScaling(bounty.region, bounty.stage)
	local adults = Species.ById[bounty.line].forms[3]
	local form = Rng.new(Rng.seed("bounty_form", bounty.seed)):Pick(adults).id
	local record = BattleSim.EnemyRecord(bounty.line, level, rarity, form)
	record.statMult = Cfg.StatMult
	record.name = bounty.name
	record.bounty = true
	local look = Appearance.Of(record)
	look.aura = Cfg.Aura
	record.look = look
	return record
end

function Bounties.Inject(enemies, bounty, regionId: string, stage: number)
	if type(bounty) ~= "table" or bounty.done or bounty.region ~= regionId or bounty.stage ~= stage then
		return enemies
	end
	if not Species.ById[bounty.line] or BattleSim.IsBossStage(regionId, stage) then
		return enemies
	end
	local out = table.clone(enemies)
	out[1] = Bounties.Monster(bounty)
	return out
end

function Bounties.Egg(regionId: string): string?
	local region = Regions.ById[regionId]
	local first = region and region.eggs and region.eggs[1]
	return first and first.egg
end

function Bounties.EggChance(lootBonus: number): number
	return math.min(Cfg.EggChanceMax, Cfg.EggChance * (1 + math.max(0, lootBonus or 0)))
end

function Bounties.RollEgg(bounty, lootBonus: number): boolean
	return Rng.new(Rng.seed("bounty_egg", bounty.seed)):Float(0, 1) < Bounties.EggChance(lootBonus)
end

function Bounties.Rewards(bounty, lootBonus: number)
	local items = {}
	for _, item in Cfg.Reward do
		table.insert(items, table.clone(item))
	end
	local egg = Bounties.Egg(bounty.region)
	if egg and Bounties.RollEgg(bounty, lootBonus) then
		table.insert(items, { kind = "egg", id = egg, amount = 1 })
	end
	return items
end

return Bounties
