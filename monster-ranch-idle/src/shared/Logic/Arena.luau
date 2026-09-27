--[[
	Arena: pure rules of the PvP arena (Config/Arena), shared by the Arena system and the
	Arena screen.

	Arena.Snapshot(m) -> Fighter          -- what a defense team stores: { line, form, look }
	Arena.Normalize(fighter, featured?) -> record   -- the BattleSim record every fighter uses;
	                                      -- featured = { [lineId] = true } (3.8) adds FeaturedBoost
	Arena.Fight(attack, defense, seed, season?) -> BattleReplay   -- attack/defense = { Fighter };
	                                      -- season (3.8) boosts that season's featured lines, both sides
	Arena.Expected(a, b) -> 0..1          -- Elo win chance of rating a against b
	Arena.Delta(a, b, won) -> points      -- rating change for `a`
	Arena.Tier(rating) -> tier def
	Arena.Bot(rating, seed) -> { key, name, rating, team = { Fighter }, bot = true }
	Arena.SeasonAt(now) -> number        -- 3.8: the season running at `now` (0 before season 1)
	Arena.SeasonStartsAt(season), Arena.SeasonEndsAt(season) -> unix time
	Arena.Featured(season) -> { lineId }  -- 3.8: the season's featured lines (none for season 0)
	Arena.FeaturedSet(season) -> { [lineId] = true }
	Arena.SoftReset(rating) -> number     -- one season's reset: ResetFraction back to StartRating
	Arena.Reseason(record, season) -> boolean   -- brings a stored record into `season` (in place)
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

function Arena.Normalize(fighter, featured: { [string]: boolean }?)
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
		statMult = if featured and featured[fighter.line] then 1 + Cfg.Season.FeaturedBoost else nil,
	}
end

function Arena.Fight(attack, defense, seed: number, season: number?)
	local featured = Arena.FeaturedSet(season or 0)
	local a, d = {}, {}
	for _, f in attack do
		table.insert(a, Arena.Normalize(f, featured))
	end
	for _, f in defense do
		table.insert(d, Arena.Normalize(f, featured))
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

-- Seasons (3.8) ---------------------------------------------------------------------------

function Arena.SeasonAt(now: number): number
	local week = Config.Leaderboards.Week(now) - Cfg.Season.AnchorWeek
	if week < 0 then
		return 0
	end
	return week // Cfg.Season.Weeks + 1
end

function Arena.SeasonStartsAt(season: number): number
	local week = Cfg.Season.AnchorWeek + (season - 1) * Cfg.Season.Weeks
	return Config.Leaderboards.WeekEndsAt(week - 1)
end

function Arena.SeasonEndsAt(season: number): number
	return Arena.SeasonStartsAt(season + 1)
end

-- The season's featured lines: `Featured` distinct lines from the bot pool (adult lines, no
-- event or raid lines), seeded by the season number alone, so every server agrees.
local featuredCache = {}
function Arena.Featured(season: number): { string }
	if season <= 0 then
		return {}
	end
	if not featuredCache[season] then
		local rng = Rng.new(Rng.seed("arena_featured", season))
		local pool = table.clone(botPool())
		local list = {}
		while #list < math.min(Cfg.Season.Featured, #pool) do
			table.insert(list, table.remove(pool, rng:Int(1, #pool)))
		end
		featuredCache[season] = list
	end
	return table.clone(featuredCache[season])
end

function Arena.FeaturedSet(season: number): { [string]: boolean }
	local set = {}
	for _, line in Arena.Featured(season) do
		set[line] = true
	end
	return set
end

function Arena.SoftReset(rating: number): number
	local start = Cfg.StartRating
	local moved = start + (rating - start) * (1 - Cfg.Season.ResetFraction)
	return math.max(Cfg.MinRating, math.floor(moved + 0.5))
end

-- A record last touched in an older season takes one soft reset per season it missed (a record
-- from before season 1 counts as season 0). Returns true when it changed.
function Arena.Reseason(record, season: number): boolean
	local from = tonumber(record.season) or 0
	if from >= season then
		return false
	end
	local rating = tonumber(record.rating) or Cfg.StartRating
	for _ = 1, math.min(season - from, 20) do
		rating = Arena.SoftReset(rating)
	end
	record.rating = rating
	record.season = season
	return true
end

return Arena
