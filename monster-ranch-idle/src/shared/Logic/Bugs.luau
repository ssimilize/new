--[[
	Logic/Bugs (update 3.13 · Wild things): pure rules of the Bug Catching Meadow (Config/Bugs),
	shared by Systems/Bugs (the authoritative replay) and the Bugs screen (the same path, drawn).

	  Bugs.Seed(userId, day, n, secret) -> seed        one swing's seed
	  Bugs.Night(now) -> boolean                       the Weather night phase (WeatherRoll.Phase)
	  Bugs.Available(def, season?, night?) -> boolean  out right now
	  Bugs.Weights(lure?) -> { number }                per rarity
	  Bugs.RarityChances(lure?) -> { [rarity]: p }     sums to 1
	  Bugs.Roll(seed, season?, night?, lure?) -> bugDef
	  Bugs.Path(seed, rarity) -> Path                  { delay, duration, twist, freq, bob, phase, total }
	  Bugs.X(path, t) -> x                             where the bug is across the field at t
	  Bugs.Y(path, t) -> y                             its wobble, 0..1 (looks only)
	  Bugs.InNet(path, t) -> boolean
	  Bugs.Window(path) -> (enter, leave)              the times it is inside the net (x rises, so one span)
	  Bugs.Hit(path, t) -> boolean                     t inside the window ± Grace
	  Bugs.Value(bugId) -> seconds                     sell price in seconds of ranch income
	  Bugs.Species(log) -> number                      kinds caught (profile.Bugs.log)

	The bug's progress p = (t - delay) / duration runs 0..1; x = Enter + (Exit - Enter) × (p +
	twist × sin(2π·freq·p) / (2π·freq)). With twist < 1 the bug never flies backwards, it only darts
	and dawdles, so the net window is a single span.
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)
local WeatherRoll = require(script.Parent.WeatherRoll)

local Cfg = Config.Bugs

local Bugs = {}

local TAU = 2 * math.pi

local function round(x: number, places: number): number
	local m = 10 ^ places
	return math.floor(x * m + 0.5) / m
end

function Bugs.Seed(userId: number, day: number, n: number, secret: number): number
	return Rng.seed("bugs", userId, day, n, secret)
end

function Bugs.Night(now: number): boolean
	local night = WeatherRoll.Phase(now)
	return night == true
end

function Bugs.Available(def, season: string?, night: boolean?): boolean
	if not def then
		return false
	end
	if def.season ~= nil and def.season ~= season then
		return false
	end
	if def.night and not night then
		return false
	end
	return true
end

function Bugs.Weights(lure: boolean?): { number }
	local list = {}
	for i, r in Cfg.Rarities do
		list[i] = if lure then r.lure else r.weight
	end
	return list
end

function Bugs.RarityChances(lure: boolean?): { number }
	local list = Bugs.Weights(lure)
	local total = 0
	for _, w in list do
		total += w
	end
	local out = {}
	for i, w in list do
		out[i] = w / total
	end
	return out
end

function Bugs.Roll(seed: number, season: string?, night: boolean?, lure: boolean?)
	local rng = Rng.new(Rng.seed("bug_roll", seed))
	local rarity = rng:Weighted(Bugs.Weights(lure))
	local pool = {}
	for _, b in Cfg.List do
		if b.rarity == rarity and Bugs.Available(b, season, night) then
			table.insert(pool, b)
		end
	end
	return rng:Pick(pool)
end

function Bugs.Path(seed: number, rarity: number)
	local r = Cfg.Rarities[rarity] or Cfg.Rarities[1]
	local rng = Rng.new(Rng.seed("bug_path", seed))
	local delay = round(rng:Float(Cfg.Delay[1], Cfg.Delay[2]), 3)
	local duration = round(rng:Float(r.duration[1], r.duration[2]), 3)
	return {
		delay = delay,
		duration = duration,
		twist = round(rng:Float(r.twist[1], r.twist[2]), 3),
		freq = round(rng:Float(Cfg.Freq[1], Cfg.Freq[2]), 3),
		bob = round(rng:Float(Cfg.Bob[1], Cfg.Bob[2]), 3),
		phase = round(rng:Next(), 3),
		total = round(delay + duration, 3),
	}
end

local function progress(path, t: number): number
	local span = if path.duration > 0 then path.duration else 1
	return math.clamp((t - path.delay) / span, 0, 1)
end

function Bugs.X(path, t: number): number
	local p = progress(path, t)
	local f = math.max(0.1, path.freq)
	local x = p + math.clamp(path.twist, 0, 0.95) * math.sin(TAU * f * p) / (TAU * f)
	return Cfg.Enter + (Cfg.Exit - Cfg.Enter) * x
end

function Bugs.Y(path, t: number): number
	local p = progress(path, t)
	return math.clamp(0.5 + path.bob * math.sin(TAU * (path.freq * 1.5 * p + path.phase)), 0.05, 0.95)
end

function Bugs.InNet(path, t: number): boolean
	return math.abs(Bugs.X(path, t) - Cfg.NetCenter) <= Cfg.NetHalf
end

function Bugs.Window(path): (number, number)
	local enter, leave = nil, nil
	local step = Cfg.SampleStep
	local n = math.ceil(path.total / step) + 1
	for i = 0, n do
		local t = i * step
		if Bugs.InNet(path, t) then
			enter = enter or t
			leave = t
		elseif enter then
			break
		end
	end
	return round(enter or -1, 3), round(leave or -1, 3)
end

function Bugs.Hit(path, t: number): boolean
	if type(t) ~= "number" or t ~= t then
		return false
	end
	local enter, leave = Bugs.Window(path)
	if enter < 0 then
		return false
	end
	return t >= enter - Cfg.Grace and t <= leave + Cfg.Grace
end

function Bugs.Value(bugId: string): number
	local def = Cfg.ById[bugId]
	return if def then def.coins else 0
end

function Bugs.Species(log): number
	local n = 0
	if type(log) == "table" then
		for id, count in log do
			if Cfg.ById[id] and (tonumber(count) or 0) > 0 then
				n += 1
			end
		end
	end
	return n
end

return Bugs
