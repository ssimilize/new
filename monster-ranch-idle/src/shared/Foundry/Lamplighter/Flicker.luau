--!strict
-- Deterministic flicker: a pure function of (profile, fixture seed, t), so every client sees the
-- same flame at the same world time. Profiles are data (Kinds.FLICKERS, rules.flickers).

local Almanac = require("../Almanac/Almanac")
local Kinds = require("./Kinds")

local Flicker = {}

local TWO32 = 4294967296

-- value(profile, seed, key, t) -> brightness multiplier (>= 0). `seed` is the fixture's numeric
-- phase seed, `key` its stable string (id) for the seeded gust draws.
function Flicker.value(profile: any, seed: number, key: string, t: number): number
	if profile == nil or (profile.amount or 0) == 0 then
		return 1
	end
	local rate = profile.rate or 1
	local n = 0
	for _, term in profile.terms or {} do
		n += term[2] * math.sin(t * rate * term[1] + seed * term[3] + (term[4] or 0))
	end
	local v
	if profile.mode == "down" then
		v = 1 - profile.amount * (n * 0.5 + 0.5)
	else
		v = 1 + profile.amount * n
	end
	local g = profile.gust
	if g then
		local bucket = math.floor(t / g.every)
		local u = Kinds.mix(Almanac.hash(key, "gust", bucket)) / TWO32
		if u < g.chance then
			local half = g.length / 2
			local span = math.max(0, g.every - g.length)
			local centre = bucket * g.every + half + span * (Kinds.mix(Almanac.hash(key, "gustAt", bucket)) / TWO32)
			local d = math.abs(t - centre)
			if d < half then
				v *= 1 - g.depth * (1 - d / half)
			end
		end
	end
	return math.max(0, v)
end

-- problems(id, profile) -> { string } for rules validation.
function Flicker.problems(id: string, p: any): { string }
	local out = {}
	if type(p) ~= "table" then
		return { `flickers.{id} must be a table` }
	end
	if type(p.amount) ~= "number" or p.amount < 0 or p.amount > 1 then
		table.insert(out, `flickers.{id}.amount must be a number in [0, 1]`)
	end
	if p.mode ~= nil and p.mode ~= "centered" and p.mode ~= "down" then
		table.insert(out, `flickers.{id}.mode must be "centered" or "down"`)
	end
	if (p.amount or 0) > 0 then
		if type(p.rate) ~= "number" or p.rate <= 0 then
			table.insert(out, `flickers.{id}.rate must be a positive number`)
		end
		if type(p.terms) ~= "table" or #p.terms == 0 then
			table.insert(out, `flickers.{id}.terms must list \{freq, weight, phase}`)
		else
			local w = 0
			for i, term in p.terms do
				if type(term) ~= "table" or type(term[1]) ~= "number" or type(term[2]) ~= "number" or type(term[3]) ~= "number" then
					table.insert(out, `flickers.{id}.terms[{i}] must be \{freq, weight, phase}`)
				else
					w += math.abs(term[2])
				end
			end
			if w > 1 + 1e-9 then
				table.insert(out, `flickers.{id}.terms weights sum to {w} (> 1: the flame could go negative)`)
			end
		end
	end
	local g = p.gust
	if g ~= nil then
		if type(g) ~= "table" or type(g.every) ~= "number" or g.every <= 0 or type(g.chance) ~= "number"
			or type(g.depth) ~= "number" or g.depth < 0 or g.depth > 1 or type(g.length) ~= "number" or g.length <= 0
			or g.length > g.every then
			table.insert(out, `flickers.{id}.gust must be \{every > 0, chance, depth 0..1, 0 < length <= every}`)
		end
	end
	return out
end

return Flicker
