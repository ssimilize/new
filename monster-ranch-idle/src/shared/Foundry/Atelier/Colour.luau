--!strict
-- Colour helpers for Atelier: hex parsing, HSV shifts of lock colours, and a perceptual-ish
-- distance (for the crowd check). Pure; the same numbers under Lune and in Roblox.

local Colour = {}

function Colour.parse(hex: string): (number, number, number)
	local r, g, b = string.match(hex, "^#(%x%x)(%x%x)(%x%x)$")
	if not r then
		error(`Atelier.Colour: '{tostring(hex)}' is not #rrggbb`, 2)
	end
	return (tonumber(r, 16) :: number), (tonumber(g, 16) :: number), (tonumber(b, 16) :: number)
end

function Colour.isHex(v: any): boolean
	return type(v) == "string" and string.match(v, "^#%x%x%x%x%x%x$") ~= nil
end

local function clamp01(x: number): number
	return math.max(0, math.min(1, x))
end

function Colour.toHex(r: number, g: number, b: number): string
	local function c(v: number): number
		return math.floor(math.max(0, math.min(255, v)) + 0.5)
	end
	return string.format("#%02X%02X%02X", c(r), c(g), c(b))
end

-- rgb 0..1 -> h 0..1, s, v (the colorsys formulas)
local function rgbToHsv(r: number, g: number, b: number): (number, number, number)
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local v = mx
	if mx == mn then
		return 0, 0, v
	end
	local s = (mx - mn) / mx
	local rc, gc, bc = (mx - r) / (mx - mn), (mx - g) / (mx - mn), (mx - b) / (mx - mn)
	local h
	if r == mx then
		h = bc - gc
	elseif g == mx then
		h = 2 + rc - bc
	else
		h = 4 + gc - rc
	end
	return (h / 6) % 1, s, v
end

local function hsvToRgb(h: number, s: number, v: number): (number, number, number)
	if s == 0 then
		return v, v, v
	end
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	i = i % 6
	if i == 0 then
		return v, t, p
	elseif i == 1 then
		return q, v, p
	elseif i == 2 then
		return p, v, t
	elseif i == 3 then
		return p, q, v
	elseif i == 4 then
		return t, p, v
	end
	return v, p, q
end

-- A colour with its HSV value and saturation scaled (clamped), like the Bench's shade_of.
function Colour.shade(hex: string, value: number?, sat: number?): string
	local r, g, b = Colour.parse(hex)
	local h, s, v = rgbToHsv(r / 255, g / 255, b / 255)
	local r2, g2, b2 = hsvToRgb(h, clamp01(s * (sat or 1)), clamp01(v * (value or 1)))
	return Colour.toHex(r2 * 255, g2 * 255, b2 * 255)
end

-- Redmean RGB distance scaled to 0..1 (0 same, 1 black vs white).
function Colour.distance(a: string, b: string): number
	local r1, g1, b1 = Colour.parse(a)
	local r2, g2, b2 = Colour.parse(b)
	local rm = (r1 + r2) / 2
	local dr, dg, db = r1 - r2, g1 - g2, b1 - b2
	local d = math.sqrt((2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db)
	return math.min(1, d / 764.8339663572415)
end

return Colour
