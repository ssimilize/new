--[[
	PhotoRig: the pure maths of photo mode's free camera (plain numbers, no Roblox types), used by
	the client PhotoMode controller and unit-tested in Lune.

	A rig orbits a focus point. The focus is an offset (x, y, z) from the spot photo mode began at,
	kept within Camera.radius horizontally and minHeight..maxHeight vertically. The eye sits
	`distance` studs from the focus in the direction given by yaw (around +Y, 0 = the eye on +Z,
	looking towards -Z) and pitch (elevation above the focus). There is no roll.

	  PhotoRig.new(limits, yaw?, pitch?, distance?) -> rig        limits = Config.Photo.Camera
	  PhotoRig.FromOffset(limits, dx, dy, dz) -> rig              from an eye offset (the camera
	                                                               the player had) around the focus
	  PhotoRig.Orbit(rig, limits, dYaw, dPitch)                   degrees; pitch is clamped
	  PhotoRig.Zoom(rig, limits, factor)                          distance *= factor, clamped
	  PhotoRig.Pan(rig, limits, right, up, forward)               studs, relative to the view
	                                                               (forward is flattened)
	  PhotoRig.Eye(rig) -> dx, dy, dz                             eye offset from the focus
	  PhotoRig.Basis(rig) -> rx, rz, fx, fz                       flat right and forward vectors
	  PhotoRig.Cycle(count, index, step, allowed?) -> index       next allowed index, wrapping
	  PhotoRig.IsTap(movedPixels, seconds) -> boolean             a tap, not a drag
	  PhotoRig.FocusRadius(depth, distance) -> number             DepthOfField in-focus radius
	  PhotoRig.Deadzone(value, zone) -> number                    rescaled stick value
]]

local PhotoRig = {}

PhotoRig.TAP_PIXELS = 12
PhotoRig.TAP_SECONDS = 0.35

local rad, sin, cos, clamp, sqrt, atan2, deg = math.rad, math.sin, math.cos, math.clamp, math.sqrt, math.atan2, math.deg

local function wrapYaw(yaw: number): number
	yaw = yaw % 360
	return if yaw > 180 then yaw - 360 else yaw
end

function PhotoRig.new(limits, yaw: number?, pitch: number?, distance: number?)
	local rig = {
		yaw = wrapYaw(yaw or 0),
		pitch = clamp(pitch or 20, limits.minPitch, limits.maxPitch),
		distance = clamp(distance or limits.startDistance, limits.minDistance, limits.maxDistance),
		x = 0,
		y = 0,
		z = 0,
	}
	return rig
end

function PhotoRig.FromOffset(limits, dx: number, dy: number, dz: number)
	local length = sqrt(dx * dx + dy * dy + dz * dz)
	if length < 1e-3 then
		return PhotoRig.new(limits)
	end
	local yaw = deg(atan2(dx, dz))
	local pitch = deg(math.asin(clamp(dy / length, -1, 1)))
	return PhotoRig.new(limits, yaw, pitch, length)
end

function PhotoRig.Orbit(rig, limits, dYaw: number, dPitch: number)
	rig.yaw = wrapYaw(rig.yaw + dYaw)
	rig.pitch = clamp(rig.pitch + dPitch, limits.minPitch, limits.maxPitch)
end

function PhotoRig.Zoom(rig, limits, factor: number)
	if factor ~= factor or factor <= 0 then
		return
	end
	rig.distance = clamp(rig.distance * factor, limits.minDistance, limits.maxDistance)
end

function PhotoRig.Basis(rig): (number, number, number, number)
	local yaw = rad(rig.yaw)
	-- right = (cos, 0, -sin), forward (flattened, away from the eye) = (-sin, 0, -cos)
	return cos(yaw), -sin(yaw), -sin(yaw), -cos(yaw)
end

function PhotoRig.Pan(rig, limits, right: number, up: number, forward: number)
	local rx, rz, fx, fz = PhotoRig.Basis(rig)
	local x = rig.x + rx * right + fx * forward
	local z = rig.z + rz * right + fz * forward
	local flat = sqrt(x * x + z * z)
	if flat > limits.radius then
		x, z = x / flat * limits.radius, z / flat * limits.radius
	end
	rig.x, rig.z = x, z
	rig.y = clamp(rig.y + up, limits.minHeight, limits.maxHeight)
end

function PhotoRig.Eye(rig): (number, number, number)
	local yaw, pitch = rad(rig.yaw), rad(rig.pitch)
	local flat = cos(pitch) * rig.distance
	return sin(yaw) * flat, sin(pitch) * rig.distance, cos(yaw) * flat
end

function PhotoRig.Cycle(count: number, index: number, step: number, allowed: ((number) -> boolean)?): number
	if count <= 0 then
		return index
	end
	local i = index
	for _ = 1, count do
		i = ((i - 1 + step) % count) + 1
		if not allowed or allowed(i) then
			return i
		end
	end
	return index
end

function PhotoRig.IsTap(movedPixels: number, seconds: number): boolean
	return movedPixels <= PhotoRig.TAP_PIXELS and seconds <= PhotoRig.TAP_SECONDS
end

function PhotoRig.FocusRadius(depth, distance: number): number
	return clamp(distance * depth.radiusShare, depth.minRadius, depth.maxRadius)
end

function PhotoRig.Deadzone(value: number, zone: number): number
	local a = math.abs(value)
	if a <= zone then
		return 0
	end
	return math.sign(value) * math.min(1, (a - zone) / (1 - zone))
end

return PhotoRig
