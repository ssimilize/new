--[[
	Rng: a small deterministic random number generator (mulberry32) plus string hashing.

	Roblox's `Random` is not available in Lune tests and is not guaranteed identical
	across engine versions, so every roll that must be reproducible (battle replays,
	global shop restocks, breeding previews) uses this module with an explicit seed.

		local rng = Rng.new(12345)
		rng:Next()              -- [0, 1)
		rng:Int(1, 6)           -- inclusive
		rng:Chance(0.25)
		rng:Weighted({ 75, 22, 3 })  -- returns index
]]

local Rng = {}
Rng.__index = Rng

local band, bor, bxor, rshift, lshift = bit32.band, bit32.bor, bit32.bxor, bit32.rshift, bit32.lshift
local TWO32 = 4294967296

-- 32-bit integer multiply (wraps), exact in doubles by splitting into 16-bit halves.
local function imul(a: number, b: number): number
	local ah, al = rshift(a, 16), band(a, 0xFFFF)
	local bh, bl = rshift(b, 16), band(b, 0xFFFF)
	local high = band(ah * bl + al * bh, 0xFFFF)
	return band(al * bl + lshift(high, 16), 0xFFFFFFFF)
end
Rng.imul = imul

-- FNV-1a 32-bit hash of a string.
function Rng.hash(str: string): number
	local h = 2166136261
	for i = 1, #str do
		h = bxor(h, string.byte(str, i))
		h = imul(h, 16777619)
	end
	return h
end

-- Combines several values (numbers or strings) into one 32-bit seed.
function Rng.seed(...: any): number
	local parts = table.pack(...)
	local text = {}
	for i = 1, parts.n do
		text[i] = tostring(parts[i])
	end
	return Rng.hash(table.concat(text, "|"))
end

function Rng.new(seed: number?)
	local s = seed or math.floor((os.clock() * 1e6) % TWO32)
	return setmetatable({ _state = band(math.floor(s) % TWO32, 0xFFFFFFFF) }, Rng)
end

function Rng:State(): number
	return self._state
end

-- Float in [0, 1).
function Rng:Next(): number
	local t = band(self._state + 0x6D2B79F5, 0xFFFFFFFF)
	self._state = t
	t = imul(bxor(t, rshift(t, 15)), bor(t, 1))
	t = bxor(t, band(t + imul(bxor(t, rshift(t, 7)), bor(t, 61)), 0xFFFFFFFF))
	return bxor(t, rshift(t, 14)) / TWO32
end

-- Integer in [min, max] inclusive.
function Rng:Int(min: number, max: number): number
	if max < min then
		min, max = max, min
	end
	return min + math.floor(self:Next() * (max - min + 1))
end

function Rng:Float(min: number, max: number): number
	return min + self:Next() * (max - min)
end

function Rng:Chance(p: number): boolean
	return self:Next() < p
end

function Rng:Pick<T>(list: { T }): T
	return list[self:Int(1, #list)]
end

-- Weighted pick over an array of weights; returns the chosen index. Zero weights are skipped.
function Rng:Weighted(weights: { number }): number
	local total = 0
	for _, w in weights do
		total += math.max(w, 0)
	end
	if total <= 0 then
		return 1
	end
	local roll = self:Next() * total
	local acc = 0
	local last = 1
	for i, w in weights do
		if w > 0 then
			acc += w
			last = i
			if roll < acc then
				return i
			end
		end
	end
	return last
end

-- Weighted pick over a list of entries using `entry[weightKey]`; returns the entry.
function Rng:WeightedBy<T>(entries: { T }, weightKey: string): T
	local weights = {}
	for i, e in entries do
		weights[i] = (e :: any)[weightKey] or 0
	end
	return entries[self:Weighted(weights)]
end

function Rng:Shuffle<T>(list: { T }): { T }
	for i = #list, 2, -1 do
		local j = self:Int(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return Rng
