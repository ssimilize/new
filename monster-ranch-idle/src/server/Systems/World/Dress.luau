--[[
	World/Dress: swaps placeholder buildings for their Meshy models (BuildingMeshes) once the world
	is in the Workspace. Each mesh is built once (ctx.Services.CreateMeshPart, which yields) and
	cloned for every copy: the barn stands on every plot.

	The model is scaled to fit the placeholder's footprint (Body's X and Z, so the plot layout that
	LevelSeventy.spec proves still holds), stands on Body's floor and faces the same way (front -Z).
	The placeholder parts stay, invisible and not colliding: clients anchor the Open prompt on Door
	and the name billboard hangs off Body. A Sign's lettering is switched off; the models carry
	their own sign shapes. Without the adapter (the Lune mock) or when a mesh fails to load, the
	placeholder simply stays.
]]

local Dress = {}

-- Building id -> the models to dress: hub buildings by their HubId, and every plot's Barn.
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

local function dress(model: Instance, template: MeshPart): boolean
	local body = model:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		return false
	end
	local native = template.Size
	local scale = math.min(body.Size.X / native.X, body.Size.Z / native.Z)
	local part = template:Clone()
	part.Name = "Mesh"
	part.Size = native * scale
	local floor = body.Position.Y - body.Size.Y / 2
	part.CFrame = body.CFrame.Rotation + Vector3.new(body.Position.X, floor + part.Size.Y / 2, body.Position.Z)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide = false
			d.CastShadow = false
		elseif d:IsA("SurfaceGui") then
			d.Enabled = false
		end
	end
	part.Parent = model
	return true
end

-- Returns how many models were dressed.
function Dress.world(world: Instance, meshes, createMeshPart: (string) -> MeshPart?, log: (string, ...any) -> ()): number
	local dressed = 0
	for id, models in targets(world) do
		local data = meshes[id]
		if data then
			local template = createMeshPart(data.mesh)
			if template then
				template.TextureID = data.texture
				template.Anchored = true
				template.CanTouch = false
				for _, model in models do
					if dress(model, template) then
						dressed += 1
					end
				end
				template:Destroy()
			else
				log("no mesh for %s (%s): its placeholder stays", id, data.mesh)
			end
		end
	end
	return dressed
end

return Dress
