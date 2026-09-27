--!strict
-- Noise: seeded integer hashing and value noise for SkyWeather (exact 32-bit arithmetic, so
-- Lune and Roblox agree bit for bit).
--
--   Noise.seed(v)                 -- number or string -> uint32
--   Noise.hash(seed, a, b?, c?)   -- integers -> uint32
--   Noise.u(seed, a, b?, c?)      -- integers -> [0, 1)
--   Noise.value3(seed, x, y, z)   -- continuous value noise in [0, 1] (smoothstep-faded lattice)

local Noise = {}

local TWO32 = 4294967296

local function imul(a: number, b: number): number
	local alo = bit32.band(a, 0xFFFF)
	local ahi = bit32.rshift(a, 16)
	return (((ahi * b) % 65536) * 65536 + alo * b) % TWO32
end

local function fmix32(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = imul(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = imul(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

local function u32(v: number): number
	return math.floor(v) % TWO32
end

-- seed(v) -> uint32: numbers pass through (mod 2^32); strings hash with FNV-1a.
function Noise.seed(v: any): number
	if type(v) == "number" then
		return u32(math.abs(v))
	end
	local s = tostring(v)
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = imul(h, 16777619)
	end
	return h
end

-- hash(seed, a, b, c) -> uint32 over integers (floats are floored; negatives wrap).
function Noise.hash(seed: number, a: number, b: number?, c: number?): number
	local h = fmix32(bit32.bxor(u32(seed), 0x9E3779B9))
	h = fmix32(bit32.bxor(h, u32(a)))
	h = fmix32(bit32.bxor((h + 0x7F4A7C15) % TWO32, u32(b or 0)))
	h = fmix32(bit32.bxor((h + 0x94D049BB) % TWO32, u32(c or 0)))
	return h
end

function Noise.u(seed: number, a: number, b: number?, c: number?): number
	return Noise.hash(seed, a, b, c) / TWO32
end

local function fade(t: number): number
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- value3(seed, x, y, z) -> [0, 1]: trilinear value noise on the integer lattice with a
-- smoothstep fade, continuous everywhere (C1).
function Noise.value3(seed: number, x: number, y: number, z: number): number
	local x0, y0, z0 = math.floor(x), math.floor(y), math.floor(z)
	local fx, fy, fz = fade(x - x0), fade(y - y0), fade(z - z0)
	local function v(i: number, j: number, k: number): number
		return Noise.u(seed, x0 + i, y0 + j, z0 + k)
	end
	local a = lerp(lerp(v(0, 0, 0), v(1, 0, 0), fx), lerp(v(0, 1, 0), v(1, 1, 0), fx), fy)
	local b = lerp(lerp(v(0, 0, 1), v(1, 0, 1), fx), lerp(v(0, 1, 1), v(1, 1, 1), fx), fy)
	return lerp(a, b, fz)
end

return Noise
