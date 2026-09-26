--[[
	Logic/Ambience: the pure rules behind the ambience layers (Config/Ambience), shared by the Sky,
	Lamplight, SceneryMotion and Critters controllers and unit-tested in Ambience.spec.

		Ambience.Ramp(x, from, to) -> 0..1                smoothstep of x between from and to
		Ambience.Night(clock, on, off) -> 0..1            0 by day .. 1 at night; on = { from, to } dusk
		                                                   hours (0 -> 1), off = { from, to } dawn (1 -> 0)
		Ambience.GoldenHour(clock, cfg) -> 0..1           the warm-tint weight (cfg = Config.Ambience.GoldenHour)
		Ambience.Clouds(cfg, weatherId, night) -> cover, density, r, g, b
		Ambience.SunRays(cfg, weatherId, night) -> intensity
		Ambience.Enabled(layers, name, override) -> boolean   override (the Lighting attribute) wins
		Ambience.Cap(entry, low) -> number                entry.max, or entry.maxLow with lowGraphics
		Ambience.Nearest(points, x, z, radius, max) -> { index }   nearest first, flat (X/Z) distance
		Ambience.Scared(bird, player, speed, cfg) -> boolean  a running player is within cfg.scare
		Ambience.Sway(t, seed, angle, speed) -> ax, az    radians, a slow two-frequency rock

	Positions are anything with X and Z fields (a Vector3 or a plain table), so this stays pure.
]]

local Ambience = {}

function Ambience.Ramp(x: number, from: number, to: number): number
	if to == from then
		return if x >= to then 1 else 0
	end
	local p = math.clamp((x - from) / (to - from), 0, 1)
	return p * p * (3 - 2 * p)
end

function Ambience.Night(clock: number, on: { number }, off: { number }): number
	local c = clock % 24
	if c >= off[1] and c <= off[2] then
		return 1 - Ambience.Ramp(c, off[1], off[2])
	elseif c >= on[1] and c <= on[2] then
		return Ambience.Ramp(c, on[1], on[2])
	elseif c > off[2] and c < on[1] then
		return 0
	end
	return 1
end

local function bump(c: number, w): number
	if c <= w.from or c >= w.to then
		return 0
	elseif c <= w.peak then
		return Ambience.Ramp(c, w.from, w.peak)
	end
	return 1 - Ambience.Ramp(c, w.peak, w.to)
end

function Ambience.GoldenHour(clock: number, cfg): number
	local c = clock % 24
	return math.max(bump(c, cfg.dusk), bump(c, cfg.dawn))
end

local function hexToRgb(hex: string): (number, number, number)
	local s = string.gsub(hex, "#", "")
	local r = tonumber(string.sub(s, 1, 2), 16) or 255
	local g = tonumber(string.sub(s, 3, 4), 16) or 255
	local b = tonumber(string.sub(s, 5, 6), 16) or 255
	return r / 255, g / 255, b / 255
end
Ambience.HexToRgb = hexToRgb

function Ambience.Clouds(cfg, weatherId: string?, night: number): (number, number, number, number, number)
	local look = cfg.byWeather[weatherId or "clear"] or cfg.byWeather.clear
	local r, g, b = hexToRgb(look.color)
	local shade = 1 - (1 - (cfg.nightShade or 1)) * math.clamp(night, 0, 1)
	return look.cover, look.density, r * shade, g * shade, b * shade
end

function Ambience.SunRays(cfg, weatherId: string?, night: number): number
	local value = cfg.byWeather[weatherId or ""]
	if value == nil then
		value = cfg.default
	end
	return value * (1 - math.clamp(night, 0, 1))
end

function Ambience.Enabled(layers, name: string, override: any): boolean
	if type(override) == "boolean" then
		return override
	end
	return layers[name] ~= false
end

function Ambience.Cap(entry, low: boolean): number
	if low then
		return entry.maxLow or 0
	end
	return entry.max or 0
end

function Ambience.Nearest(points: { any }, x: number, z: number, radius: number, max: number): { number }
	local found = {}
	if max <= 0 then
		return found
	end
	local r2 = radius * radius
	local dist = {}
	for i, p in points do
		local dx, dz = p.X - x, p.Z - z
		local d2 = dx * dx + dz * dz
		if d2 <= r2 then
			table.insert(found, i)
			dist[i] = d2
		end
	end
	table.sort(found, function(a, b)
		return dist[a] < dist[b]
	end)
	for i = #found, max + 1, -1 do
		found[i] = nil
	end
	return found
end

function Ambience.Scared(bird, player, speed: number, cfg): boolean
	if speed < cfg.scareSpeed then
		return false
	end
	local dx, dz = bird.X - player.X, bird.Z - player.Z
	return dx * dx + dz * dz <= cfg.scare * cfg.scare
end

function Ambience.Sway(t: number, seed: number, angle: number, speed: number): (number, number)
	local a = math.rad(angle)
	local w = speed * math.pi * 2
	local ax = math.sin(t * w + seed) * 0.7 + math.sin(t * w * 2.3 + seed * 1.7) * 0.3
	local az = math.sin(t * w * 0.8 + seed * 2.1) * 0.6 + math.sin(t * w * 1.9 + seed * 0.4) * 0.4
	return ax * a, az * a
end

return Ambience
