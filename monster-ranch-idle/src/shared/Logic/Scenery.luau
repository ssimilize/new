--[[
	Scenery: where the world's decoration stands (trees, rocks, bushes, flowers, grass) and how
	the perimeter wall is cut into segments. Pure and seeded (Config.World.Scenery.seed), so every
	server builds the same map and Scenery.spec can prove that nothing blocks a plot, a path, the
	plaza or a building. World/Scenery (server) turns the lists into MeshParts.

	Scenery.layout(Config, mode?) -> { Item }   Item = { kind, x, z, yaw, size }
	    `size` is the target of the mesh's largest dimension, in studs.
	Scenery.wall(World) -> { Segment }          Segment = { kind = "wall"|"pillar", x, z, yaw, length }
	Scenery.keepOut(Config, mode?) -> { Zone }  Zone = circle { x, z, r } or box { x, z, hx, hz, yaw }
	Scenery.blocked(zones, x, z, pad) -> boolean

	Keep-out zones: the Market Square disc, every hub building, every plot (with its gate and
	path), the egg-hunt spots, and Config.World.Scenery.keepOut for areas saved for future features.
	Inside the wall, kinds scatter in groups; `outside` kinds form a forest band beyond the wall
	so the edge of the map reads as woods rather than a drop.
]]

local Rng = require(script.Parent.Rng)

local Scenery = {}

export type Zone = { x: number, z: number, r: number?, hx: number?, hz: number?, yaw: number? }
export type Item = { kind: string, x: number, z: number, yaw: number, size: number }

local function circle(x: number, z: number, r: number): Zone
	return { x = x, z = z, r = r }
end

-- A box of half extents hx, hz turned by `yaw` radians (same sense as CFrame.Angles(0, yaw, 0)).
local function box(x: number, z: number, hx: number, hz: number, yaw: number): Zone
	return { x = x, z = z, hx = hx, hz = hz, yaw = yaw }
end

-- World position of a plot-local point (Build.plotFrame: yaw = facing - 90 degrees).
local function plotPoint(plot, lx: number, lz: number): (number, number)
	local yaw = math.rad((plot.facing or 0) - 90)
	local c, s = math.cos(yaw), math.sin(yaw)
	return plot.center[1] + lx * c + lz * s, plot.center[3] - lx * s + lz * c
end

function Scenery.keepOut(Config, mode: string?): { Zone }
	local World = Config.World
	local zones = {}
	if mode == "hub" then
		local Hub = Config.TradingHub.World
		table.insert(zones, circle(0, 0, Hub.plazaRadius + 4))
		for _, def in Hub.buildings do
			table.insert(zones, circle(def.position[1], def.position[3], math.max(def.size[1], def.size[3]) * 0.75))
		end
	else
		table.insert(zones, circle(0, 0, World.HubRadius + 2))
		for _, def in World.Hub do
			table.insert(zones, circle(def.position[1], def.position[3], math.max(def.size[1], def.size[3]) * 0.75))
		end
		local sx, sz = World.PlotSize[1], World.PlotSize[2]
		for _, plot in World.Plots do
			local yaw = math.rad((plot.facing or 0) - 90)
			table.insert(zones, box(plot.center[1], plot.center[3], sx / 2, sz / 2, yaw))
			-- The path (12 wide, Build.buildPath) from the plot's front edge to the plaza.
			local fx, fz = plotPoint(plot, sx / 2, 0)
			local length = math.sqrt(fx * fx + fz * fz)
			if length > World.HubRadius then
				local ux, uz = fx / length, fz / length
				local from, to = World.HubRadius - 2, length + 3
				local mid = (from + to) / 2
				table.insert(zones, box(ux * mid, uz * mid, 6, (to - from) / 2, math.atan2(ux, uz)))
			end
		end
		for _, spot in Config.EggHunt.Spots do
			table.insert(zones, circle(spot[1], spot[3], 4))
		end
	end
	for _, zone in World.Scenery.keepOut do
		if zone.size then
			table.insert(zones, box(zone.center[1], zone.center[2], zone.size[1] / 2, zone.size[2] / 2, 0))
		else
			table.insert(zones, circle(zone.center[1], zone.center[2], zone.radius))
		end
	end
	return zones
end

-- True if a disc of radius `pad` at (x, z) touches any zone.
function Scenery.blocked(zones: { Zone }, x: number, z: number, pad: number): boolean
	for _, zone in zones do
		local dx, dz = x - zone.x, z - zone.z
		if zone.r then
			local reach = zone.r + pad
			if dx * dx + dz * dz < reach * reach then
				return true
			end
		else
			-- Into the box's frame: the inverse of the yaw rotation.
			local c, s = math.cos(zone.yaw :: number), math.sin(zone.yaw :: number)
			local lx, lz = dx * c - dz * s, dx * s + dz * c
			if math.abs(lx) < (zone.hx :: number) + pad and math.abs(lz) < (zone.hz :: number) + pad then
				return true
			end
		end
	end
	return false
end

-- A coarse grid of the solid items placed so far, so a new tree does not grow into a boulder.
local CELL = 32

local function cellKey(x: number, z: number): number
	return math.floor(x / CELL) * 100003 + math.floor(z / CELL)
end

local function crowded(grid, x: number, z: number, r: number): boolean
	local cx, cz = math.floor(x / CELL), math.floor(z / CELL)
	for i = cx - 1, cx + 1 do
		for j = cz - 1, cz + 1 do
			for _, other in grid[i * 100003 + j] or {} do
				local reach = r + other.r
				local dx, dz = x - other.x, z - other.z
				if dx * dx + dz * dz < reach * reach then
					return true
				end
			end
		end
	end
	return false
end

local function remember(grid, x: number, z: number, r: number)
	local key = cellKey(x, z)
	grid[key] = grid[key] or {}
	table.insert(grid[key], { x = x, z = z, r = r })
end

-- Footprint radius of an item: `footprint` x its size (trees spread about as wide as tall).
local function radiusOf(kind, size: number): number
	return size * (kind.footprint or 0.4)
end

function Scenery.layout(Config, mode: string?): { Item }
	local World = Config.World
	local S = World.Scenery
	local rng = Rng.new(Rng.seed(S.seed, mode or "ranch"))
	local zones = Scenery.keepOut(Config, mode)
	local inner = World.Boundary.half - S.wallClearance
	local grid = {}
	local items: { Item } = {}

	local function try(kind, x: number, z: number): boolean
		local size = rng:Float(kind.size[1], kind.size[2])
		local r = radiusOf(kind, size)
		if math.abs(x) > inner - r or math.abs(z) > inner - r then
			return false
		end
		if Scenery.blocked(zones, x, z, r + S.margin) then
			return false
		end
		-- Every kind keeps out of solid items; only solid kinds reserve room of their own.
		if crowded(grid, x, z, if kind.solid then r else r * 0.3) then
			return false
		end
		if kind.solid then
			remember(grid, x, z, r)
		end
		table.insert(items, { kind = kind.id, x = x, z = z, yaw = rng:Float(0, math.pi * 2), size = size })
		return true
	end

	for _, kind in S.kinds do
		local placed, attempts = 0, 0
		local group = kind.group or { 1, 1 }
		while placed < kind.count and attempts < kind.count * 30 do
			attempts += 1
			local cx, cz = rng:Float(-inner, inner), rng:Float(-inner, inner)
			for _ = 1, rng:Int(group[1], group[2]) do
				if placed >= kind.count then
					break
				end
				local spread = kind.spread or 0
				local a, d = rng:Float(0, math.pi * 2), spread * math.sqrt(rng:Next())
				if try(kind, cx + math.cos(a) * d, cz + math.sin(a) * d) then
					placed += 1
				end
			end
		end
	end

	-- The forest band beyond the wall: walk each side and drop trees at a random depth.
	local band = S.outside
	if band then
		local half = World.Boundary.half
		local reach = half + band.depth[2]
		local s = -reach
		while s < reach do
			for side = 1, 4 do
				local depth = half + rng:Float(band.depth[1], band.depth[2])
				local along = s + rng:Float(-band.step * 0.3, band.step * 0.3)
				local x, z
				if side == 1 then
					x, z = along, -depth
				elseif side == 2 then
					x, z = along, depth
				elseif side == 3 then
					x, z = -depth, along
				else
					x, z = depth, along
				end
				local kindId = band.kinds[rng:Int(1, #band.kinds)]
				local yaw = rng:Float(0, math.pi * 2)
				table.insert(items, { kind = kindId, x = x, z = z, yaw = yaw, size = rng:Float(band.size[1], band.size[2]) })
			end
			s += band.step
		end
	end
	return items
end

-- The perimeter wall as segments of Config.World.Boundary.segment studs with a pillar every
-- `pillarEvery` segments and at each corner. Each side runs corner to corner.
function Scenery.wall(World)
	local B = World.Boundary
	local half = B.half
	local count = math.max(1, math.round(half * 2 / B.segment))
	local length = half * 2 / count
	local list = {}
	local sides = {
		{ x = 0, z = -half, dx = 1, dz = 0, yaw = 0 },
		{ x = 0, z = half, dx = 1, dz = 0, yaw = 0 },
		{ x = -half, z = 0, dx = 0, dz = 1, yaw = math.pi / 2 },
		{ x = half, z = 0, dx = 0, dz = 1, yaw = math.pi / 2 },
	}
	for sideIndex, side in sides do
		for i = 0, count - 1 do
			local t = -half + (i + 0.5) * length
			table.insert(list, { kind = "wall", x = side.x + side.dx * t, z = side.z + side.dz * t, yaw = side.yaw, length = length })
		end
		-- Pillars on the joints; the first two sides also take the four corners.
		for i = 0, count do
			local corner = i == 0 or i == count
			if (i % B.pillarEvery == 0 or corner) and not (corner and sideIndex > 2) then
				local t = -half + i * length
				table.insert(list, { kind = "pillar", x = side.x + side.dx * t, z = side.z + side.dz * t, yaw = side.yaw, length = 0 })
			end
		end
	end
	return list
end

return Scenery
