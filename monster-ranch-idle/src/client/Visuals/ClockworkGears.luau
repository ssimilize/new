--[[
	ClockworkGears (R2-CLOCKWORK): turns every gear Visuals/ClockworkBuild made (the landmark
	tower's and the area's), like ReefLife sways kelp. Cheap and streaming-safe: a plain CFrame
	pivot on a handful of Model instances, and a gear whose Parent has gone (streamed out,
	destroyed) is dropped from the list instead of erroring.

	  ClockworkGears.Build(root: Instance) -> state    finds every descendant Model with a non-zero
	                                                    `Gear` attribute (degrees a second) and
	                                                    records its starting pivot
	  ClockworkGears.Step(state, dt)                    turns each one another `speed * dt` degrees
	                                                    about its own Y axis
	  ClockworkGears.Count(state) -> number             tests: how many gears are turning
]]

local ClockworkGears = {}

function ClockworkGears.Build(root: Instance)
	local gears = {}
	for _, inst in root:GetDescendants() do
		if inst:IsA("Model") then
			local speed = inst:GetAttribute("Gear")
			if type(speed) == "number" and speed ~= 0 and inst.PrimaryPart then
				table.insert(gears, { model = inst, base = inst:GetPivot(), speed = speed, angle = 0 })
			end
		end
	end
	return { gears = gears }
end

function ClockworkGears.Step(state, dt: number)
	if not state then
		return
	end
	local i = 1
	while i <= #state.gears do
		local g = state.gears[i]
		if not g.model.Parent then
			table.remove(state.gears, i)
		else
			g.angle += math.rad(g.speed) * dt
			g.model:PivotTo(g.base * CFrame.Angles(0, g.angle, 0))
			i += 1
		end
	end
end

function ClockworkGears.Count(state): number
	return if state then #state.gears else 0
end

return ClockworkGears
