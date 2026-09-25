--[[
	Arena: pure rules of the PvP arena (Config/Arena), shared by the Arena system and the
	Arena screen.

	Arena.Snapshot(m) -> Fighter          -- what a defense team stores: { line, form, look }
	Arena.Normalize(fighter) -> record    -- the BattleSim record every fighter uses
	Arena.Fight(attack, defense, seed) -> BattleReplay   -- attack/defense = { Fighter }
	Arena.Expected(a, b) -> 0..1          -- Elo win chance of rating a against b
	Arena.Delta(a, b, won) -> points      -- rating change for `a`
	Arena.Tier(rating) -> tier def
	Arena.Bot(rating, seed) -> { key, name, rating, team = { Fighter }, bot = true }
]]

local Config = require(script.Parent.Parent.Config)
local Appearance = require(script.Parent.Appearance)
local BattleSim = require(script.Parent.BattleSim)
local Rng = require(script.Parent.Rng)

local Cfg = Config.Arena
local Species = Config.Species

local Arena = {}

function Arena.Snapshot(m)
	return { line = m.line, form = m.form, look = Appearance.Of(m) }
end

function Arena.Normalize(fighter)
	local def = Species.ById[fighter.line]
	assert(def, "unknown line " .. tostring(fighter.line))
	local form = Species.Form(fighter.line, 3, fighter.form)
	return {
		line = fighter.line,
		stage = 3,
		form = form.id,
		rarity = Cfg.Normal.rarity,
		variant = 0,
		muts = {},
		traits = {},
		hidden = 0,
		weight = def.weight,
		lv = Cfg.Normal.lv,
		stars = Cfg.Normal.stars,
		mood = 100,
		name = "",
		look = fighter.look,
	}
end

function Arena.Fight(attack, defense, seed: number)
	local a, d = {}, {}
	for _, f in attack do
		table.insert(a, Arena.Normalize(f))
	end
	for _, f in defense do
		table.insert(d, Arena.Normalize(f))
	end
	return BattleSim.Simulate(a, d, seed, { maxTurns = Cfg.MaxTurns })
end

function Arena.Expected(a: number, b: number): number
	return 1 / (1 + 10 ^ ((b - a) / 400))
end

function Arena.Delta(a: number, b: number, won: boolean): number
	local score = if won then 1 else 0
	return math.floor(Cfg.K * (score - Arena.Expected(a, b)) + 0.5)
end

function Arena.Tier(rating: number)
	local best = Cfg.Tiers[1]
	for _, tier in Cfg.Tiers do
		if rating >= tier.min then
			best = tier
		end
	end
	return best
end

-- Adult lines a bot can field (no event or raid-only lines).
local botLines = nil
local function botPool()
	if not botLines then
		botLines = {}
		for _, line in Species.Lines do
			if not line.event and not line.raid then
				table.insert(botLines, line.id)
			end
		end
		table.sort(botLines)
	end
	return botLines
end

function Arena.Bot(rating: number, seed: number)
	local rng = Rng.new(seed)
	local pool = botPool()
	local team = {}
	local used = {}
	while #team < Cfg.TeamSize do
		local line = pool[rng:Int(1, #pool)]
		if not used[line] then
			used[line] = true
			local adults = Species.ById[line].forms[3]
			local form = adults[rng:Int(1, #adults)].id
			table.insert(team, { line = line, form = form, look = Appearance.Preview(line, 3, form, Cfg.Normal.rarity) })
		end
	end
	return {
		key = "bot:" .. tostring(seed),
		name = Cfg.BotNames[rng:Int(1, #Cfg.BotNames)],
		rating = math.max(Cfg.MinRating, math.floor(rating + rng:Int(-60, 60))),
		team = team,
		bot = true,
	}
end

return Arena
