--[[
	World/Dress: swaps placeholder buildings for their Meshy models (BuildingMeshes) once the world
	is in the Workspace. A building is several pieces (BuildingMeshes has why); each piece's mesh is
	built once (ctx.Services.CreateMeshPart, which yields) and cloned for every copy: the barn stands
	on every plot.

	The model is scaled to fit the placeholder's footprint (Body's X and Z, so the plot layout that
	LevelSeventy.spec proves still holds), stands on Body's floor and faces the same way (front -Z).
	The placeholder parts stay, invisible and not colliding: clients anchor the Open prompt on Door
	and the name billboard hangs off Body. A Sign's lettering is switched off; the models carry
	their own sign shapes. Without the adapter (the Lune mock) or when a mesh fails to load, the
	placeholder simply stays, whole: a building is dressed only if all its pieces loaded.
]]

local Dress = {}

-- Building id -> the models to dress: hub buildings by their HubId, every plot's Barn, and the
-- Sky Gate on the landing isle (Sky/Gate, "skyGate").
local function targets(world: Instance): { [string]: { Instance } }
	local list = {}
	local function add(id, model)
		list[id] = list[id] or {}
		table.insert(list[id], model)
	end
	local hub = world:FindFirstChild("Hub")
	local buildings = hub and hub:FindFirstChild("Buildings")
	if buildings then
		for _, model in buildings:GetChildren() do
			local id = model:GetAttribute("HubId")
			if type(id) == "string" then
				add(id, model)
			end
		end
	end
	local sky = world:FindFirstChild("Sky")
	local gate = sky and sky:FindFirstChild("Gate")
	if gate then
		add("skyGate", gate)
	end
	local plots = world:FindFirstChild("Plots")
	if plots then
		for _, plot in plots:GetChildren() do
			local barn = plot:FindFirstChild("Barn")
			if barn then
				add("barn", barn)
			end
		end
	end
	return list
end

local function vector(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function dress(model: Instance, data, templates: { MeshPart }): boolean
	local body = model:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		return false
	end
	local size = vector(data.size)
	local scale = math.min(body.Size.X / size.X, body.Size.Z / size.Z)
	local floor = body.Position.Y - body.Size.Y / 2
	local centre = body.CFrame.Rotation + Vector3.new(body.Position.X, floor + size.Y * scale / 2, body.Position.Z)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide = false
			d.CastShadow = false
		elseif d:IsA("SurfaceGui") then
			d.Enabled = false
		end
	end
	for i, piece in data.parts do
		local part = templates[i]:Clone()
		part.Name = "Mesh" .. i
		part.Size = templates[i].Size * scale
		part.CFrame = centre * CFrame.new(vector(piece.offset) * scale)
		part.Parent = model
	end
	-- The name billboard sits above the placeholder's box; a model can be taller than its box (the
	-- Showtime Stage's is 6 studs, its model ~15), so lift the label clear of the model's top.
	local clearance = floor + size.Y * scale + 3 - body.Position.Y
	for _, gui in body:GetChildren() do
		if gui:IsA("BillboardGui") and gui.StudsOffset.Y < clearance then
			gui.StudsOffset = Vector3.new(gui.StudsOffset.X, clearance, gui.StudsOffset.Z)
		end
	end
	return true
end

-- Returns how many models were dressed.
function Dress.world(world: Instance, meshes, createMeshPart: (string) -> MeshPart?, log: (string, ...any) -> ()): number
	local dressed = 0
	for id, models in targets(world) do
		local data = meshes[id]
		if data then
			local templates, missing = {}, nil
			for i, piece in data.parts do
				local template = createMeshPart(piece.mesh)
				if not template then
					missing = piece.mesh
					break
				end
				template.TextureID = piece.texture
				template.Anchored = true
				template.CanTouch = false
				templates[i] = template
			end
			if missing then
				log("no mesh for %s (%s): its placeholder stays", id, missing)
			else
				for _, model in models do
					if dress(model, data, templates) then
						dressed += 1
					end
				end
			end
			for _, template in templates do
				template:Destroy()
			end
		end
	end
	return dressed
end

return Dress
