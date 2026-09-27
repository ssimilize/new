--[[
	Wake: a cheap "is the camera anywhere near this?" gate for client scenery that animates every
	frame (Controllers/ClockworkCanyon's gears, Controllers/DeepReef's and Controllers/Abyss's
	life). Far scenery stops writing CFrames and its bubble emitters pause; its clock keeps
	running, so it wakes up where it would have been. The distance is re-read every CHECK
	seconds, not every frame.

	  Wake.new(center: Vector3, radius: number) -> gate   awake while the camera is within
	                                                      radius + MARGIN studs of center
	  Wake.Step(gate, dt) -> (awake: boolean, changed: boolean)
]]

local Wake = {}

Wake.CHECK = 0.5 -- seconds between distance checks
Wake.MARGIN = 200 -- studs past a place's own radius where it still animates

function Wake.new(center: Vector3, radius: number)
	-- acc starts full so the first Step decides at once instead of animating for CHECK seconds
	return { center = center, range = radius + Wake.MARGIN, acc = Wake.CHECK, awake = true }
end

function Wake.Step(gate, dt: number): (boolean, boolean)
	gate.acc += dt
	if gate.acc < Wake.CHECK then
		return gate.awake, false
	end
	gate.acc = 0
	local camera = workspace.CurrentCamera
	local awake = camera == nil or (camera.CFrame.Position - gate.center).Magnitude <= gate.range
	local changed = awake ~= gate.awake
	gate.awake = awake
	return awake, changed
end

return Wake
