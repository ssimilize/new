--[[
	SceneryIndex: the scenery items by kind, for the ambience controllers (Lamplight, SceneryMotion,
	Critters). World/Scenery (server) parents one finished Folder Workspace.World.Scenery of parts
	named by kind; this indexes it once when it arrives (and again if it is replaced), so nobody
	walks ~2,100 parts on a timer.

		SceneryIndex.Start()                   idempotent: waits for Workspace.World in a thread
		SceneryIndex.Get(kind) -> { BasePart }  the items of a kind (empty until the folder arrives)
		SceneryIndex.Points(kind) -> { Vector3 } their positions (same order; parts are anchored)
		SceneryIndex.Version() -> number        bumps every time the index is rebuilt
		SceneryIndex.Index(folder)              index a folder now (tests)
]]

local SceneryIndex = {}

local byKind: { [string]: { BasePart } } = {}
local points: { [string]: { Vector3 } } = {}
local version = 0
local started = false
local EMPTY = table.freeze({})

function SceneryIndex.Index(folder: Instance)
	table.clear(byKind)
	table.clear(points)
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			local list = byKind[child.Name]
			if not list then
				list = {}
				byKind[child.Name] = list
				points[child.Name] = {}
			end
			table.insert(list, child)
			table.insert(points[child.Name], child.Position)
		end
	end
	version += 1
end

function SceneryIndex.Get(kind: string): { BasePart }
	return byKind[kind] or EMPTY :: any
end

function SceneryIndex.Points(kind: string): { Vector3 }
	return points[kind] or EMPTY :: any
end

function SceneryIndex.Version(): number
	return version
end

function SceneryIndex.Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local world = workspace:WaitForChild("World", 120)
		if not world then
			return
		end
		local function consider(child: Instance)
			if child.Name == "Scenery" and child:IsA("Folder") then
				SceneryIndex.Index(child)
			end
		end
		world.ChildAdded:Connect(consider)
		local existing = world:FindFirstChild("Scenery")
		if existing then
			consider(existing)
		end
	end)
end

return SceneryIndex
