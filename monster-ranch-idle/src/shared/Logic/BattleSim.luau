--[[
	BattleSim: the deterministic auto-battle used by stage fights (Expeditions.Fight).

	Pure and Roblox-free. The same (allies, enemies, seed, opts) always produces the same
	BattleReplay, so the server simulates once and the client only draws the result.

	BattleSim.Simulate(allies, enemies, seed, opts?) -> BattleReplay (ARCHITECTURE.md §7)
	  allies / enemies: monster records (≤ 4 allies, ≤ 5 enemies). Extra optional fields:
	    statMult = n   multiplies HP/ATK/DEF/SPD (enemy bosses, see BuildEnemies)
	    hpMult = n     multiplies HP only (raid bosses: long fights that don't one-shot)
	    boss = true    drawn as a boss by the client
	    look = Appearance  drawn instead of the record's own look (Arena's normalized fighters)
	  opts = {
	    night = boolean?,      -- Night Owl traits (nightAtkPct) add ATK
	    boss = boolean?,       -- boss fight: Boss Brawler traits (bossDmgPct) add ally damage
	    statBonus = number?,   -- ally stat bonus (0.2 = +20%, the stage-retry ad)
	    maxTurns = number?,    -- defaults to Config.Regions.MaxTurns
	    maxAllies = number?,   -- defaults to BattleSim.MaxAllies (Raids field up to 8)
	  }
	BattleSim.BuildEnemies(regionId, stage, seed) -> { enemy records }
	BattleSim.RecommendedPower(regionId, stage) -> number (comparable with squad power)

	Rules (GDD "Battle rules"):
	  • A turn is one round: every living unit acts once, fastest SPD first.
	  • Each unit's third action is its Special (Species.Skills); the others are basic hits.
	  • The front living unit of a side draws 50% of attacks, the rest share the other 50%.
	    A taunting unit draws every attack.
	  • dmg = ATK × power × elementMult × 100 / (100 + DEF) × rand(0.9, 1.1); crits ×1.5.
	  • Shields absorb damage first; Thorns reflect a share of damage taken; Regrowth heals
	    at the start of the unit's action; a stunned unit skips its next action.
	  • All enemies fainted = win. All allies fainted or MaxTurns reached = loss.
	  • The event log is capped at MaxEvents; the simulation still runs to the end and
	    `truncated = true` tells the client to jump to the result.
]]

local Config = require(script.Parent.Parent.Config)
local Formulas = require(script.Parent.Formulas)
local Appearance = require(script.Parent.Appearance)
local Rng = require(script.Parent.Rng)

local Species = Config.Species
local Elements = Config.Elements
local Traits = Config.Traits
local Regions = Config.Regions
local Economy = Config.Economy

local BattleSim = {}

BattleSim.MaxEvents = 400
BattleSim.SpecialCharge = 3 -- every 3rd action is the Special
BattleSim.BaseCrit = 0.05
BattleSim.CritMult = 1.5
BattleSim.FrontShare = 0.5
BattleSim.MaxShieldPct = 0.5 -- shields stack up to 50% of max HP
BattleSim.MaxAllies = 4
BattleSim.MaxEnemies = 5

local Skills = Species.Skills
local Passives = Species.Passives

-- Units -------------------------------------------------------------------------------

local function round(x: number): number
	return math.floor(x + 0.5)
end

local function buildUnit(m, side: string, slot: number, opts)
	local def = Species.ById[m.line]
	local stats = Formulas.Stats(m)
	local mult = (m.statMult or 1) * (if side == "ally" then 1 + (opts.statBonus or 0) else 1)
	local traits = Formulas.ActiveTraits(m)
	local atkMult = 1
	if opts.night then
		atkMult += Traits.Sum(traits, "nightAtkPct")
	end
	local passive = def.passive
	local maxHp = math.max(1, round(stats.hp * mult * (m.hpMult or 1)))
	return {
		key = (if side == "ally" then "a" else "e") .. tostring(slot),
		side = side,
		slot = slot,
		name = Formulas.DisplayName(m),
		appearance = m.look or Appearance.Of(m),
		boss = m.boss == true,
		elements = def.elements,
		special = def.special,
		passive = passive,
		maxHp = maxHp,
		hp = maxHp,
		atk = math.max(1, stats.atk * mult * atkMult),
		def = math.max(0, stats.def * mult),
		spd = math.max(1, stats.spd * mult),
		crit = BattleSim.BaseCrit + (if passive == "crit" then Passives.crit.value else 0),
		guard = if passive == "guard" then Passives.guard.value else 0,
		thorns = if passive == "thorns" then Passives.thorns.value else 0,
		regen = if passive == "regen" then Passives.regen.value else 0,
		dmgBonus = if side == "ally" and opts.boss then Traits.Sum(traits, "bossDmgPct") else 0,
		charge = 0,
		shield = 0,
		stunned = false,
		taunt = 0,
		defUp = 0,
	}
end

-- Squad-wide passives (Tailwind, Rally) stack across the side.
local function applySquadPassives(units)
	local haste, rally = 0, 0
	for _, u in units do
		if u.passive == "haste" then
			haste += Passives.haste.value
		elseif u.passive == "rally" then
			rally += Passives.rally.value
		end
	end
	for _, u in units do
		u.spd *= 1 + haste
		u.atk *= 1 + rally
	end
end

-- Simulation ----------------------------------------------------------------------------

function BattleSim.Simulate(allies, enemies, seed: number, options)
	local opts = options or {}
	local rng = Rng.new(seed)
	local maxTurns = opts.maxTurns or Regions.MaxTurns

	local sides = { ally = {}, enemy = {} }
	local units = {}
	for i, m in allies do
		if i > (opts.maxAllies or BattleSim.MaxAllies) then
			break
		end
		table.insert(sides.ally, buildUnit(m, "ally", i, opts))
	end
	for i, m in enemies do
		if i > BattleSim.MaxEnemies then
			break
		end
		table.insert(sides.enemy, buildUnit(m, "enemy", i, opts))
	end
	applySquadPassives(sides.ally)
	applySquadPassives(sides.enemy)
	for _, u in sides.ally do
		table.insert(units, u)
	end
	for _, u in sides.enemy do
		table.insert(units, u)
	end

	local events = {}
	local truncated = false
	local turn = 0

	local function log(actor, target, kind: string, amount: number, hp: number, mult: number?, skill: string?)
		if #events >= BattleSim.MaxEvents then
			truncated = true
			return
		end
		table.insert(events, {
			turn = turn,
			actor = actor.key,
			target = if target then target.key else false,
			kind = kind,
			amount = amount,
			hp = hp,
			mult = if mult and mult ~= 1 then mult else nil,
			skill = skill,
		})
	end

	local function living(side: string)
		local list = {}
		for _, u in sides[side] do
			if u.hp > 0 then
				table.insert(list, u)
			end
		end
		return list
	end

	local function opposite(side: string): string
		return if side == "ally" then "enemy" else "ally"
	end

	local function pickTarget(attacker)
		local list = living(opposite(attacker.side))
		if #list == 0 then
			return nil
		end
		for _, u in list do
			if u.taunt > 0 then
				return u
			end
		end
		if #list == 1 or rng:Chance(BattleSim.FrontShare) then
			return list[1]
		end
		return list[rng:Int(2, #list)]
	end

	local function healUnit(target, amount: number): number
		local healed = math.min(target.maxHp - target.hp, math.max(0, math.floor(amount)))
		target.hp += healed
		return healed
	end

	-- Deals one hit. Returns the damage dealt (0 if the target was already down).
	local function strike(attacker, target, power: number, kindOverride: string?, skill: string?): number
		if target.hp <= 0 or attacker.hp <= 0 then
			return 0
		end
		local mult = Elements.MultiplierMulti(attacker.elements, target.elements)
		local defense = target.def * (1 + (if target.taunt > 0 then target.defUp else 0))
		local raw = attacker.atk * power * mult * 100 / (100 + defense) * rng:Float(0.9, 1.1)
		local crit = rng:Chance(attacker.crit)
		if crit then
			raw *= BattleSim.CritMult
		end
		raw *= (1 - target.guard) * (1 + attacker.dmgBonus)
		local amount = math.max(1, round(raw))
		local absorbed = math.min(target.shield, amount)
		target.shield -= absorbed
		target.hp = math.max(0, target.hp - (amount - absorbed))
		local kind = kindOverride or (if crit then "crit" else "hit")
		log(attacker, target, kind, amount, target.hp, mult, skill)
		if target.hp == 0 then
			log(attacker, target, "faint", 0, 0)
		end
		if target.thorns > 0 and attacker.hp > 0 then
			local reflected = math.max(1, math.floor(amount * target.thorns))
			attacker.hp = math.max(0, attacker.hp - reflected)
			log(target, attacker, "reflect", reflected, attacker.hp)
			if attacker.hp == 0 then
				log(target, attacker, "faint", 0, 0)
			end
		end
		return amount
	end

	local function useSpecial(unit)
		local id = unit.special
		local skill = Skills[id]
		if not skill then
			local target = pickTarget(unit)
			if target then
				strike(unit, target, 1)
			end
			return
		end
		if id == "blast" then
			for _, target in living(opposite(unit.side)) do
				strike(unit, target, skill.power, "special", id)
			end
		elseif id == "heal" then
			log(unit, false, "special", 0, unit.hp, nil, id)
			for _, ally in living(unit.side) do
				local healed = healUnit(ally, ally.maxHp * skill.heal)
				if healed > 0 then
					log(unit, ally, "heal", healed, ally.hp)
				end
			end
		elseif id == "shield" then
			log(unit, false, "special", 0, unit.hp, nil, id)
			for _, ally in living(unit.side) do
				local cap = math.floor(ally.maxHp * BattleSim.MaxShieldPct)
				local add = math.min(math.floor(ally.maxHp * skill.shield), math.max(0, cap - ally.shield))
				ally.shield += add
				log(unit, ally, "shield", add, ally.hp)
			end
		elseif id == "taunt" then
			-- Ticks down at the start of the taunter's own actions.
			unit.taunt = skill.turns or 2
			unit.defUp = skill.defUp or 0
			log(unit, unit, "special", 0, unit.hp, nil, id)
		else
			-- Single-target damage specials: strike, drain, stun.
			local target = pickTarget(unit)
			if not target then
				return
			end
			local dealt = strike(unit, target, skill.power or 1, "special", id)
			if skill.lifesteal and dealt > 0 and unit.hp > 0 then
				local healed = healUnit(unit, dealt * skill.lifesteal)
				if healed > 0 then
					log(unit, unit, "heal", healed, unit.hp)
				end
			end
			if skill.stunChance and target.hp > 0 and rng:Chance(skill.stunChance) then
				target.stunned = true
				log(unit, target, "stun", 0, target.hp)
			end
		end
	end

	local function act(unit)
		if unit.taunt > 0 then
			unit.taunt -= 1
		end
		if unit.regen > 0 then
			local healed = healUnit(unit, unit.maxHp * unit.regen)
			if healed > 0 then
				log(unit, false, "regen", healed, unit.hp)
			end
		end
		if unit.stunned then
			unit.stunned = false
			log(unit, false, "stunned", 0, unit.hp)
			return
		end
		unit.charge += 1
		if unit.charge >= BattleSim.SpecialCharge then
			unit.charge = 0
			useSpecial(unit)
		else
			local target = pickTarget(unit)
			if target then
				strike(unit, target, 1)
			end
		end
	end

	local order = table.clone(units)
	table.sort(order, function(a, b)
		if a.spd ~= b.spd then
			return a.spd > b.spd
		end
		if a.side ~= b.side then
			return a.side == "ally"
		end
		return a.slot < b.slot
	end)

	local finished = #sides.ally == 0 or #sides.enemy == 0
	local win = #sides.ally > 0 and #sides.enemy == 0
	while not finished and turn < maxTurns do
		turn += 1
		for _, unit in order do
			if unit.hp > 0 then
				act(unit)
				if #living("enemy") == 0 then
					win, finished = true, true
					break
				elseif #living("ally") == 0 then
					win, finished = false, true
					break
				end
			end
		end
	end

	local unitViews = {}
	for _, u in units do
		table.insert(unitViews, {
			key = u.key,
			side = u.side,
			slot = u.slot,
			name = u.name,
			appearance = u.appearance,
			maxHp = u.maxHp,
			boss = u.boss,
		})
	end

	return {
		win = win,
		turns = turn,
		seed = seed,
		units = unitViews,
		events = events,
		truncated = if truncated then true else nil,
	}
end

-- Enemy waves ----------------------------------------------------------------------------

-- Life stage an enemy of this level is drawn at (Baby up to the Baby level cap, and so on).
local function lifeStageFor(level: number): number
	for s = 1, 2 do
		local cap = Economy.Stages[s].levelCap
		if cap and level <= cap then
			return s
		end
	end
	return 3
end

-- Level and rarity for a stage, interpolated across its band's ranges (Regions.Band).
function BattleSim.StageScaling(regionId: string, stage: number): (number, number)
	local band = Regions.Band(regionId, stage)
	local t = if band.last > band.first then (stage - band.first) / (band.last - band.first) else 0
	t = math.clamp(t, 0, 1)
	local level = round(band.levels[1] + (band.levels[2] - band.levels[1]) * t)
	local lo, hi = band.rarity[1], band.rarity[2]
	local rarity = math.clamp(lo + math.floor(t * (hi - lo + 1)), lo, hi)
	return level, rarity
end

local function enemyRecord(lineId: string, level: number, rarity: number, formId: string?, stageOverride: number?)
	local def = Species.ById[lineId]
	local lifeStage = stageOverride or lifeStageFor(level)
	local form
	if lifeStage == 3 then
		form = Species.Form(lineId, 3, formId).id
	else
		form = def.forms[lifeStage].id
	end
	return {
		line = lineId,
		stage = lifeStage,
		form = form,
		rarity = rarity,
		variant = 0,
		muts = {},
		traits = {},
		hidden = 0,
		weight = def.weight,
		lv = level,
		stars = 1,
		mood = Economy.Mood.start,
		name = "",
		boss = false,
		statMult = 1,
	}
end

-- The boss is drawn in its adult form but scaled from the stats a regular enemy of that
-- level would have, so boss stages stay in line with the stages around them.
local function bossRecord(boss, level: number, rarity: number)
	local record = enemyRecord(boss.line, level, rarity, boss.form, 3)
	local regular = Economy.Stages[lifeStageFor(level)].statMult
	record.statMult = Regions.BossStatMult * regular / Economy.Stages[3].statMult
	record.boss = true
	record.name = boss.name
	return record
end

function BattleSim.IsBossStage(regionId: string, stage: number): boolean
	local region = Regions.ById[regionId]
	return region ~= nil and region.bosses ~= nil and region.bosses[stage] ~= nil
end

function BattleSim.BuildEnemies(regionId: string, stage: number, seed: number)
	local region = Regions.ById[regionId]
	assert(region, "unknown region " .. tostring(regionId))
	local level, rarity = BattleSim.StageScaling(regionId, stage)
	local boss = region.bosses and region.bosses[stage]
	if boss then
		return { bossRecord(boss, level, rarity) }
	end
	local rng = Rng.new(Rng.seed("wave", regionId, stage, seed))
	local lines = Regions.Band(regionId, stage).enemyLines
	local wave = {}
	for _ = 1, Regions.WaveSize do
		local lineId = rng:Pick(lines)
		local adults = Species.ById[lineId].forms[3]
		local record = enemyRecord(lineId, level, rarity, rng:Pick(adults).id)
		table.insert(wave, record)
	end
	return wave
end

local function scaledPower(record): number
	local stats = Formulas.Stats(record)
	local mult = record.statMult or 1
	return Formulas.Power({ hp = stats.hp * mult, atk = stats.atk * mult, def = stats.def * mult, spd = stats.spd * mult })
end

-- Expected enemy power of a stage (the wave's average, independent of the seed).
function BattleSim.RecommendedPower(regionId: string, stage: number): number
	local region = Regions.ById[regionId]
	assert(region, "unknown region " .. tostring(regionId))
	local level, rarity = BattleSim.StageScaling(regionId, stage)
	local boss = region.bosses and region.bosses[stage]
	if boss then
		return scaledPower(bossRecord(boss, level, rarity))
	end
	local total = 0
	local lines = Regions.Band(regionId, stage).enemyLines
	for _, lineId in lines do
		total += scaledPower(enemyRecord(lineId, level, rarity, nil))
	end
	return math.floor(total / #lines * Regions.WaveSize + 0.5)
end

return BattleSim
