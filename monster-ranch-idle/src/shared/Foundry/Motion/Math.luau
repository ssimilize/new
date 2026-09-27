--!strict
-- Math: the small rotation kit Motion needs without Roblox types (so it runs the same in Lune
-- and in a game): 3x3 matrices as flat row-major arrays, unit quaternions as { x, y, z, w }.
--
-- Euler convention = Roblox CFrame.Angles(rx, ry, rz) = Rx * Ry * Rz (radians inside, the
-- public helpers take DEGREES because clip poses are in degrees).

local M = {}

export type Mat = { number } -- 9 numbers, row major
export type Vec = { number } -- { x, y, z }
export type Quat = { x: number, y: number, z: number, w: number }

M.IDENTITY = table.freeze({ 1, 0, 0, 0, 1, 0, 0, 0, 1 })

function M.mul(a: Mat, b: Mat): Mat
	local o = table.create(9, 0)
	for r = 0, 2 do
		for c = 0, 2 do
			o[r * 3 + c + 1] = a[r * 3 + 1] * b[c + 1] + a[r * 3 + 2] * b[c + 4] + a[r * 3 + 3] * b[c + 7]
		end
	end
	return o
end

function M.apply(m: Mat, v: Vec): Vec
	return {
		m[1] * v[1] + m[2] * v[2] + m[3] * v[3],
		m[4] * v[1] + m[5] * v[2] + m[6] * v[3],
		m[7] * v[1] + m[8] * v[2] + m[9] * v[3],
	}
end

-- anglesDeg(rx, ry, rz) -> Rx * Ry * Rz (CFrame.Angles order).
function M.anglesDeg(rx: number, ry: number, rz: number): Mat
	local a, b, c = math.rad(rx), math.rad(ry), math.rad(rz)
	local ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
	local X = { 1, 0, 0, 0, ca, -sa, 0, sa, ca }
	local Y = { cb, 0, sb, 0, 1, 0, -sb, 0, cb }
	local Z = { cc, -sc, 0, sc, cc, 0, 0, 0, 1 }
	return M.mul(M.mul(X, Y), Z)
end

function M.fromQuat(q: Quat): Mat
	local x, y, z, w = q.x, q.y, q.z, q.w
	local n = math.sqrt(x * x + y * y + z * z + w * w)
	if n < 1e-12 then
		return table.clone(M.IDENTITY) :: any
	end
	x, y, z, w = x / n, y / n, z / n, w / n
	return {
		1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
		2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
		2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y),
	}
end

-- slerp(a, b, w): the shortest arc from a to b (Roblox CFrame:Lerp does the same).
function M.slerp(a: Quat, b: Quat, w: number): Quat
	local bx, by, bz, bw = b.x, b.y, b.z, b.w
	local d = a.x * bx + a.y * by + a.z * bz + a.w * bw
	if d < 0 then
		d, bx, by, bz, bw = -d, -bx, -by, -bz, -bw
	end
	local k0, k1
	if d > 0.9995 then
		k0, k1 = 1 - w, w
	else
		local th = math.acos(math.min(d, 1))
		local s = math.sin(th)
		k0, k1 = math.sin((1 - w) * th) / s, math.sin(w * th) / s
	end
	local x, y, z, ww = a.x * k0 + bx * k1, a.y * k0 + by * k1, a.z * k0 + bz * k1, a.w * k0 + bw * k1
	local n = math.sqrt(x * x + y * y + z * z + ww * ww)
	if n < 1e-12 then
		return { x = 0, y = 0, z = 0, w = 1 }
	end
	return { x = x / n, y = y / n, z = z / n, w = ww / n }
end

function M.clamp(v: number, lo: number, hi: number): number
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

-- hash01(seed, n) -> [0, 1): a stateless integer hash (the same on every client), so a
-- procedural layer can ask "the n-th blink of character `seed`" without keeping state.
function M.hash01(seed: number, n: number): number
	local h = bit32.bxor(math.floor(seed) % 4294967296, 0x9E3779B9)
	h = bit32.bxor(h, (math.floor(n) * 0x85EBCA6B) % 4294967296)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = (bit32.band(h, 0xFFFF) * 0x7FEB352D + bit32.rshift(h, 16) * 0x352D0000) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 15))
	h = (bit32.band(h, 0xFFFF) * 0x846CA68B + bit32.rshift(h, 16) * 0xA68B0000) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

return M
