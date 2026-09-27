--!strict
-- Vec: three-component vector maths on plain tables { x, y, z } (no Roblox datatypes, so the
-- package runs in Lune; the game converts with Vector3.new(v.x, v.y, v.z) / CFrame.lookAt).

export type Vec3 = { x: number, y: number, z: number }

local Vec = {}

function Vec.new(x: number, y: number, z: number): Vec3
	return { x = x, y = y, z = z }
end

local function finiteNumber(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
Vec.finiteNumber = finiteNumber

-- Accepts { x, y, z } or { 1, 2, 3 }; nil when it is neither (or not finite).
function Vec.of(v: any): Vec3?
	if type(v) ~= "table" then
		return nil
	end
	local x, y, z = v.x, v.y, v.z
	if x == nil and y == nil and z == nil then
		x, y, z = v[1], v[2], v[3]
	end
	if finiteNumber(x) and finiteNumber(y) and finiteNumber(z) then
		return { x = x, y = y, z = z }
	end
	return nil
end

function Vec.isVec(v: any): boolean
	return type(v) == "table" and finiteNumber(v.x) and finiteNumber(v.y) and finiteNumber(v.z)
end

function Vec.add(a: Vec3, b: Vec3): Vec3
	return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end

function Vec.sub(a: Vec3, b: Vec3): Vec3
	return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

function Vec.scale(a: Vec3, k: number): Vec3
	return { x = a.x * k, y = a.y * k, z = a.z * k }
end

function Vec.dot(a: Vec3, b: Vec3): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

function Vec.cross(a: Vec3, b: Vec3): Vec3
	return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
end

function Vec.length(a: Vec3): number
	return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
end

function Vec.dist(a: Vec3, b: Vec3): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Unit vector; the zero vector stays zero.
function Vec.norm(a: Vec3): Vec3
	local l = Vec.length(a)
	if l < 1e-12 then
		return { x = 0, y = 0, z = 0 }
	end
	return { x = a.x / l, y = a.y / l, z = a.z / l }
end

function Vec.lerp(a: Vec3, b: Vec3, t: number): Vec3
	return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t }
end

-- Rotate around +Y by `deg` degrees (yaw), the same handedness as the orbit convention:
-- yaw 0 puts a camera on the +Z side of its subject, yaw 90 on the +X side.
function Vec.yaw(a: Vec3, deg: number): Vec3
	local r = math.rad(deg)
	local s, c = math.sin(r), math.cos(r)
	return { x = a.x * c + a.z * s, y = a.y, z = -a.x * s + a.z * c }
end

function Vec.array(a: Vec3): { number }
	return { a.x, a.y, a.z }
end

return Vec
