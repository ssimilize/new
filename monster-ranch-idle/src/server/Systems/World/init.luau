--[[
	World (C1): builds the static, server-side world geometry from Config.World under
	Workspace.World (ground, paths, plaza and fountain, six hub buildings, six ranch plots
	with pens, fences, incubator pads, barns and gates, the SpawnLocation, and the perimeter wall
	with its invisible barrier). On the Trading Hub place (update 3.0) it builds the hub layout
	(Config.TradingHub.World) instead. Then, as their meshes load, the Meshy buildings replace
	their placeholders (Dress.luau) and the scenery goes down (Scenery.luau: trees, rocks,
	bushes, flowers, grass, and the stone wall meshes).

	This is the one system allowed to create Roblox Instances; it reaches the Workspace only
	through ctx.Services.Workspace. It has no profile, no actions and no public methods.
	Clients render everything dynamic (monsters, eggs, jars, weather) on top of it; see
	Build.luau for the instance layout and the attributes clients rely on.
	Tested in Studio only (no Lune spec: Instances are not available there).
]]

local Build = require(script.Build)
local BuildingMeshes = require(script.BuildingMeshes)
local Dress = require(script.Dress)
local Scenery = require(script.Scenery)
local SceneryMeshes = require(script.SceneryMeshes)

local World = {
	Name = "World",
	Dependencies = {},
}

local ctx

function World.Init(context)
	ctx = context
	local workspace = ctx.Services.Workspace
	if not workspace then
		ctx:Log("no Workspace adapter; world not built")
		return
	end
	local old = workspace:FindFirstChild("World")
	if old then
		old:Destroy()
	end
	-- Studio's Baseplate template (docs/LOCAL_SETUP.md) puts its top at y = 0, the same height as
	-- Ground's, and the two flicker; the world brings its own ground, so the baseplate goes.
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local mode = ctx.Config.TradingHub.Mode(ctx.Services.PlaceId, ctx.Services.PlaceMode)
	local folder, parts = Build.world(ctx.Config, mode)
	-- Parent last so clients receive the finished tree in one replication step.
	folder.Parent = workspace
	ctx:Log("built %d parts", parts)
	-- The Meshy buildings take over from their placeholders as their meshes load (Dress.luau).
	local createMeshPart = ctx.Services.CreateMeshPart
	if createMeshPart then
		ctx.Services.Spawn(function()
			local dressed = Dress.world(folder, BuildingMeshes, createMeshPart, function(...)
				ctx:Log(...)
			end)
			ctx:Log("dressed %d buildings", dressed)
		end)
		-- Trees, rocks, flowers, grass and the stone wall meshes (Scenery.luau), alongside the buildings.
		ctx.Services.Spawn(function()
			local placed = Scenery.world(folder, ctx.Config, mode, SceneryMeshes, createMeshPart, function(...)
				ctx:Log(...)
			end)
			ctx:Log("placed %d scenery items", placed)
		end)
	end
end

return World
