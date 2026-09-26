-- Logic/Scenery (pure): the scatter of trees, rocks and grass and the perimeter wall segments.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local Scenery = t.Shared("Logic.Scenery")
	local Config = t.Shared("Config")
	local World = Config.World

	-- Plot-local coordinates of a world point (inverse of Build.plotFrame's yaw = facing - 90).
	local function plotLocal(plot, x: number, z: number): (number, number)
		local yaw = math.rad((plot.facing or 0) - 90)
		local dx, dz = x - plot.center[1], z - plot.center[3]
		return dx * math.cos(yaw) - dz * math.sin(yaw), dx * math.sin(yaw) + dz * math.cos(yaw)
	end

	local function inside(item): boolean
		return math.abs(item.x) < World.Boundary.half and math.abs(item.z) < World.Boundary.half
	end

	describe("Scenery · layout", function()
		local items = Scenery.layout(Config)

		it("is the same on every server", function()
			local again = Scenery.layout(Config)
			expect(#again).toBe(#items)
			local same = true
			for i, item in items do
				local other = again[i]
				if other.kind ~= item.kind or other.x ~= item.x or other.z ~= item.z or other.size ~= item.size then
					same = false
				end
			end
			expect(same).toBe(true)
		end)

		it("places every kind close to its count", function()
			local counts = {}
			for _, item in items do
				if inside(item) then
					counts[item.kind] = (counts[item.kind] or 0) + 1
				end
			end
			local short = {}
			for _, kind in World.Scenery.kinds do
				local n = counts[kind.id] or 0
				if n < kind.count * 0.9 or n > kind.count then
					table.insert(short, string.format("%s %d/%d", kind.id, n, kind.count))
				end
			end
			expect(table.concat(short, "; ")).toBe("")
		end)

		it("keeps clear of the plaza, the plots, the paths, the buildings and the wall", function()
			local problems = {}
			local hx, hz = World.PlotSize[1] / 2, World.PlotSize[2] / 2
			for _, item in items do
				if inside(item) then
					local where = string.format("%s at (%.0f, %.0f)", item.kind, item.x, item.z)
					if math.sqrt(item.x * item.x + item.z * item.z) < World.HubRadius + 2 then
						table.insert(problems, where .. " is on the plaza")
					end
					for _, plot in World.Plots do
						local lx, lz = plotLocal(plot, item.x, item.z)
						if math.abs(lx) < hx and math.abs(lz) < hz then
							table.insert(problems, where .. " is on plot " .. plot.id)
						end
					end
					for _, def in World.Hub do
						local dx, dz = item.x - def.position[1], item.z - def.position[3]
						if math.abs(dx) < def.size[1] / 2 + 2 and math.abs(dz) < def.size[3] / 2 + 2 then
							table.insert(problems, where .. " is in " .. def.id)
						end
					end
					local limit = World.Boundary.half - World.Scenery.wallClearance
					if math.abs(item.x) > limit or math.abs(item.z) > limit then
						table.insert(problems, where .. " is against the wall")
					end
				end
			end
			-- The path from each plot's gate to the plaza: a 12-stud strip on the line between them.
			for _, plot in World.Plots do
				local yaw = math.rad((plot.facing or 0) - 90)
				local gx = plot.center[1] + hx * math.cos(yaw)
				local gz = plot.center[3] - hx * math.sin(yaw)
				local length = math.sqrt(gx * gx + gz * gz)
				for _, item in items do
					local along = (item.x * gx + item.z * gz) / length
					local across = math.abs(item.x * gz - item.z * gx) / length
					if along > World.HubRadius and along < length and across < 6 then
						local where = string.format("%s at (%.0f, %.0f)", item.kind, item.x, item.z)
						table.insert(problems, where .. " is on the path to plot " .. plot.id)
					end
				end
			end
			for _, spot in Config.EggHunt.Spots do
				for _, item in items do
					local dx, dz = item.x - spot[1], item.z - spot[3]
					if dx * dx + dz * dz < 16 then
						table.insert(problems, item.kind .. " covers an egg-hunt spot")
					end
				end
			end
			expect(table.concat(problems, "; ")).toBe("")
		end)

		it("keeps the woods outside the wall and on the ground", function()
			local problems = {}
			local outside = 0
			for _, item in items do
				if not inside(item) then
					outside += 1
					local reach = math.max(math.abs(item.x), math.abs(item.z))
					if reach < World.Boundary.half + World.Scenery.outside.depth[1] - 1 then
						table.insert(problems, "tree against the wall")
					end
					if reach > World.GroundSize[1] / 2 - 10 then
						table.insert(problems, "tree off the ground")
					end
				end
			end
			expect(outside > 100).toBe(true)
			expect(table.concat(problems, "; ")).toBe("")
		end)

		it("leaves a future-feature zone empty", function()
			local copy = table.clone(Config)
			copy.World = table.clone(World)
			copy.World.Scenery = table.clone(World.Scenery)
			copy.World.Scenery.keepOut = { { center = { 500, 500 }, radius = 120 } }
			local zoned = Scenery.layout(copy)
			local hits = 0
			for _, item in zoned do
				local dx, dz = item.x - 500, item.z - 500
				if dx * dx + dz * dz < 120 * 120 then
					hits += 1
				end
			end
			expect(hits).toBe(0)
		end)

		it("keeps the Trading Hub plaza clear on the hub place", function()
			local hub = Scenery.layout(Config, "hub")
			local r = Config.TradingHub.World.plazaRadius
			local hits = 0
			for _, item in hub do
				if item.x * item.x + item.z * item.z < r * r then
					hits += 1
				end
			end
			expect(#hub > 500).toBe(true)
			expect(hits).toBe(0)
		end)
	end)

	describe("Scenery · wall", function()
		it("closes every side, corner to corner, with a pillar on each corner", function()
			local segments = Scenery.wall(World)
			local half = World.Boundary.half
			local lengthBySide = { n = 0, s = 0, w = 0, e = 0 }
			local corners = {}
			for _, seg in segments do
				if seg.kind == "wall" then
					local side = if seg.z == -half then "n" elseif seg.z == half then "s" elseif seg.x == -half then "w" else "e"
					lengthBySide[side] += seg.length
				elseif math.abs(seg.x) == half and math.abs(seg.z) == half then
					local key = seg.x .. "," .. seg.z
					corners[key] = (corners[key] or 0) + 1
				end
			end
			for side, length in lengthBySide do
				expect(side .. " " .. math.round(length)).toBe(side .. " " .. half * 2)
			end
			local n = 0
			for _, c in corners do
				n += 1
				expect(c).toBe(1)
			end
			expect(n).toBe(4)
		end)
	end)
end
