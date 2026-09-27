--!strict
-- Lamplighter kinds, flicker profiles and window masks, as data (the practicals kit, LT2 step 2).
--
-- A kind is how one sort of practical light looks and behaves:
--   kelvin      colour temperature (K); `colour` (hex "#RRGGBB") wins when set
--   brightness  Light.Brightness at full level;  range  Light.Range in studs
--   light       "point" | "spot" | "surface" (the sink picks the Instance class); angle for spot/surface
--   flicker     a profile id in FLICKERS (nil or "steady" = none)
--   decal       ground pool diameter in studs (0 = this kind never gets a decal); decalAlpha 0..1
--   shadows     may this kind cast shadows when the shadow budget allows
--   switch      "night" (on by the lamp schedule or the lamplighter's route), "always" (a forge
--               that never goes out), "windows" (lit panes follow occupancy and the window schedule)
--   lamplighter true when the lamplighter's route lights it (Life's lamplighter role)
--   weight      priority multiplier in the weighted solver (default 1)
--   on / off    optional per-kind switch-on / switch-off hour ranges (else rules.lamps.on / .off)
--   emissive    glow strength of the fixture's own lit material at full level (0..1)
--
-- Every value here can be overridden per game in rules.kinds[kindId] (fields merge).

local Kinds = {}

Kinds.KINDS = {
	lantern = {
		kelvin = 2400,
		brightness = 1.2,
		range = 12,
		light = "point",
		flicker = "lantern",
		decal = 10,
		decalAlpha = 0.55,
		shadows = false,
		switch = "night",
		lamplighter = true,
		emissive = 0.9,
	},
	torch = {
		kelvin = 1900,
		brightness = 1.6,
		range = 14,
		light = "point",
		flicker = "torch",
		decal = 12,
		decalAlpha = 0.6,
		shadows = true,
		switch = "night",
		lamplighter = true,
		emissive = 1,
	},
	brazier = {
		kelvin = 1800,
		brightness = 2,
		range = 18,
		light = "point",
		flicker = "fire",
		decal = 16,
		decalAlpha = 0.65,
		shadows = true,
		switch = "night",
		lamplighter = false,
		emissive = 1,
	},
	lamppost = {
		kelvin = 2700,
		brightness = 1.4,
		range = 16,
		light = "point",
		flicker = "steady",
		decal = 14,
		decalAlpha = 0.5,
		shadows = true,
		switch = "night",
		lamplighter = true,
		emissive = 0.95,
	},
	window = {
		kelvin = 2300,
		brightness = 0.8,
		range = 10,
		light = "surface",
		angle = 70,
		flicker = "breathe",
		decal = 8,
		decalAlpha = 0.4,
		shadows = false,
		switch = "windows",
		lamplighter = false,
		emissive = 0.85,
	},
	forge = {
		kelvin = 1600,
		brightness = 2.2,
		range = 20,
		light = "point",
		flicker = "forge",
		decal = 18,
		decalAlpha = 0.7,
		shadows = false,
		switch = "always",
		lamplighter = false,
		emissive = 1,
	},
}

-- Flicker profiles. value(t) = 1 + amount * n ("centered") or 1 - amount * (n * 0.5 + 0.5)
-- ("down"), n = sum of weight * sin(t * rate * freq + seed * phase + offset) over `terms`
-- ({freq, weight, phase, offset?}). Optional `gust = {every, chance, depth, length}`: in each
-- `every`-second bucket, with chance `chance` (seeded per fixture and bucket), one dip of
-- `depth` lasting `length` seconds. Pure in (seed, t): every client sees the same flame.
Kinds.FLICKERS = {
	steady = { amount = 0 },
	lantern = {
		amount = 0.08,
		rate = 2.3,
		mode = "centered",
		terms = { { 1, 0.5, 1 }, { 2.71, 0.3, 1.7 }, { 6.13, 0.2, 3.1 } },
		gust = { every = 6, chance = 0.2, depth = 0.25, length = 0.4 },
	},
	torch = {
		amount = 0.22,
		rate = 6,
		mode = "centered",
		terms = { { 1, 0.45, 1 }, { 2.31, 0.35, 2.3 }, { 4.97, 0.2, 3.7 } },
		gust = { every = 2.5, chance = 0.3, depth = 0.35, length = 0.25 },
	},
	fire = {
		amount = 0.28,
		rate = 5,
		mode = "centered",
		terms = { { 1, 0.5, 1 }, { 2.13, 0.3, 1.9 }, { 5.3, 0.2, 0 } },
		gust = { every = 3, chance = 0.25, depth = 0.3, length = 0.35 },
	},
	forge = {
		amount = 0.15,
		rate = 1.3,
		mode = "centered",
		terms = { { 1, 0.7, 1 }, { 3.7, 0.3, 2.2 } },
	},
	-- Guildhall BuildingLife Logic.flicker: 1 - amount * (n * 0.5 + 0.5), s = seed * 17.3,
	-- n = sin(t r + s) 0.5 + sin(t r 2.37 + s 1.7) 0.3 + sin(t r 5.11 + s 3.1) 0.2.
	breathe = {
		amount = 0.18,
		rate = 3.1,
		mode = "down",
		terms = { { 1, 0.5, 17.3 }, { 2.37, 0.3, 17.3 * 1.7 }, { 5.11, 0.2, 17.3 * 3.1 } },
	},
	-- Monster Ranch Lamplight campfires: 1 + f * (sin(c 11 + s) 0.5 + sin(c 23.7 + s 3) 0.3
	-- + sin(c 5.3) 0.2), c the controller clock, s the source seed.
	ranch = {
		amount = 0.25,
		rate = 1,
		mode = "centered",
		terms = { { 11, 0.5, 1 }, { 23.7, 0.3, 3 }, { 5.3, 0.2, 0 } },
	},
}

-- Window masks: which panes of a building kind's facade glow. Coordinates are pixels on a
-- `size = {w, h}` canvas (the PIL generator draws the emissive texture at that size); each
-- pane is `{id, x, y, w, h, bars?}` with `bars` = "cross" | "vertical" | "none" (mullions).
Kinds.MASKS = {
	cottage = {
		size = { 256, 256 },
		panes = {
			{ id = "g1", x = 36, y = 150, w = 56, h = 64, bars = "cross" },
			{ id = "g2", x = 164, y = 150, w = 56, h = 64, bars = "cross" },
			{ id = "u1", x = 100, y = 48, w = 56, h = 56, bars = "cross" },
		},
	},
	shop = {
		size = { 256, 256 },
		panes = {
			{ id = "front", x = 28, y = 140, w = 120, h = 80, bars = "vertical" },
			{ id = "u1", x = 40, y = 40, w = 48, h = 56, bars = "cross" },
			{ id = "u2", x = 168, y = 40, w = 48, h = 56, bars = "cross" },
		},
	},
	hall = {
		size = { 256, 256 },
		panes = {
			{ id = "g1", x = 20, y = 150, w = 44, h = 70, bars = "vertical" },
			{ id = "g2", x = 192, y = 150, w = 44, h = 70, bars = "vertical" },
			{ id = "u1", x = 20, y = 50, w = 44, h = 60, bars = "cross" },
			{ id = "u2", x = 106, y = 30, w = 44, h = 80, bars = "vertical" },
			{ id = "u3", x = 192, y = 50, w = 44, h = 60, bars = "cross" },
		},
	},
	tower = {
		size = { 128, 256 },
		panes = {
			{ id = "f1", x = 44, y = 184, w = 40, h = 48, bars = "cross" },
			{ id = "f2", x = 44, y = 110, w = 40, h = 48, bars = "cross" },
			{ id = "f3", x = 44, y = 36, w = 40, h = 48, bars = "cross" },
		},
	},
}

-- Colour temperature (K) -> r, g, b in 0..255 (Tanner Helland's fit, 1000..40000 K). The PIL
-- generator in foundry/tools/lamplighter/draw.py carries the same formula; a spec checks both.
function Kinds.kelvin(k: number): (number, number, number)
	local t = math.clamp(k, 1000, 40000) / 100
	local r, g, b
	if t <= 66 then
		r = 255
		g = 99.4708025861 * math.log(t) - 161.1195681661
	else
		r = 329.698727446 * (t - 60) ^ -0.1332047592
		g = 288.1221695283 * (t - 60) ^ -0.0755148492
	end
	if t >= 66 then
		b = 255
	elseif t <= 19 then
		b = 0
	else
		b = 138.5177312231 * math.log(t - 10) - 305.0447927307
	end
	return math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255)
end

-- mix(h) -> uint32: the murmur3 finaliser over a hash. Almanac.hash is plain FNV-1a, whose
-- values for ids that differ only in the last character sit close together; every per-fixture
-- draw here goes through this avalanche first (unit = mix(hash(...)) / 2^32).
local TWO32 = 4294967296
local function imul(a: number, b: number): number
	local alo = bit32.band(a, 0xFFFF)
	local ahi = bit32.rshift(a, 16)
	return (((ahi * b) % 65536) * 65536 + alo * b) % TWO32
end
function Kinds.mix(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = imul(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = imul(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

-- "#RRGGBB" -> r, g, b 0..255, or nil for a malformed string.
function Kinds.hex(s: string): (number?, number?, number?)
	local h = string.match(s, "^#?(%x%x%x%x%x%x)$")
	if not h then
		return nil, nil, nil
	end
	return tonumber(string.sub(h, 1, 2), 16), tonumber(string.sub(h, 3, 4), 16), tonumber(string.sub(h, 5, 6), 16)
end

return Kinds
