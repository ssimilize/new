--[[
	PROTOTYPE monster lab for Studio (not part of the game). Two jobs:

	MonsterLab.capture() -> JSON
		Reads Workspace.MonsterGen (generate_monsters.luau's output: every part published, tagged
		MeshAsset / TextureAsset) into the MonsterLibrary table: per form its archetype, whether it
		hovers, and each part's name, mesh, texture, size and CFrame relative to the body.
		write_monster_library.py turns the JSON into MonsterLibrary.luau.

	MonsterLab.show(options?) -> stop()
		Rebuilds every monster in MonsterLibrary FROM ITS ASSETS (CreateMeshPartAsync, as a game
		would), lines them up in Workspace.MonsterLab, rigs each with Animator and plays it: blinks,
		ear twitches, tail wags, wing flaps, chatter, breathing; every third one walks a small circle.
		options: { walkers = 3 (every Nth walks), spacing = 12, perRow = 8, origin = Vector3 }

	The modules sit in ServerStorage.PetGeneticsLab next to this one.
]]

local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")

local here = script.Parent
local Animator = require(here.Animator)

local MonsterLab = {}

local function isBody(name: string): boolean
	return string.lower((string.gsub(name, "[^%a]", ""))) == "bodygeom" or string.lower(name) == "body"
end

function MonsterLab.capture(): string
	local library = {}
	for _, model in workspace.MonsterGen:GetChildren() do
		local body
		for _, p in model:GetDescendants() do
			if p:IsA("MeshPart") and isBody(p.Name) then
				body = p
			end
		end
		if body then
			local entry = {
				archetype = model:GetAttribute("Archetype"),
				hover = model:GetAttribute("Hover") == true,
				line = model:GetAttribute("Line"),
				parts = {},
			}
			local complete = true
			for _, p in model:GetDescendants() do
				if p:IsA("MeshPart") then
					local mesh, texture = p:GetAttribute("MeshAsset"), p:GetAttribute("TextureAsset")
					complete = complete and mesh ~= nil and texture ~= nil
					local rel = body.CFrame:ToObjectSpace(p.CFrame)
					table.insert(entry.parts, {
						name = string.gsub(string.gsub(p.Name, "_geom$", ""), "[^%a ]", ""),
						mesh = mesh,
						texture = texture,
						size = { p.Size.X, p.Size.Y, p.Size.Z },
						cframe = { rel:GetComponents() },
					})
				end
			end
			if complete then
				library[model.Name] = entry
			end
		end
	end
	return HttpService:JSONEncode(library)
end

local cache: { [string]: MeshPart } = {}

local function meshPart(mesh: string): MeshPart
	local template = cache[mesh]
	if not template then
		template = AssetService:CreateMeshPartAsync(Content.fromUri(mesh))
		cache[mesh] = template
	end
	return template:Clone()
end

-- One monster from its library entry, body at `at` facing -Z, standing on the ground.
function MonsterLab.build(form: string, entry, at: Vector3): Model
	local model = Instance.new("Model")
	model.Name = form
	local bodyCf = CFrame.new(at)
	local parts = {}
	for _, p in entry.parts do
		local part = meshPart(p.mesh)
		part.Name = p.name
		part.TextureID = p.texture
		part.Anchored = true
		part.CanCollide = false
		part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
		part.CFrame = bodyCf * CFrame.new(table.unpack(p.cframe))
		part.Parent = model
		table.insert(parts, part)
		if string.lower(p.name) == "body" then
			model.PrimaryPart = part
		end
	end
	local box, extent = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, at.Y + extent.Y / 2 - box.Position.Y, 0))
	model:SetAttribute("Archetype", entry.archetype)
	return model
end

function MonsterLab.show(options: any?): () -> ()
	options = options or {}
	local Library = require(here.MonsterLibrary)
	local old = workspace:FindFirstChild("MonsterLab")
	if old then
		old:Destroy()
	end
	if _G.MonsterLabStop then
		pcall(_G.MonsterLabStop)
	end
	local folder = Instance.new("Folder")
	folder.Name = "MonsterLab"
	folder.Parent = workspace
	local spacing, perRow = options.spacing or 12, options.perRow or 8
	local origin = options.origin or Vector3.new(0, 0, -120)
	local forms = {}
	for form in Library do
		table.insert(forms, form)
	end
	table.sort(forms, function(a, b)
		return (Library[a].line or 0) < (Library[b].line or 0)
	end)
	local rigs = {}
	for i, form in forms do
		local entry = Library[form]
		local col, row = (i - 1) % perRow, (i - 1) // perRow
		local at = origin + Vector3.new(col * spacing, 0, row * spacing)
		local model = MonsterLab.build(form, entry, at)
		model.Parent = folder
		local walker = not entry.hover and i % (options.walkers or 3) == 0
		local path
		if walker then
			-- A small circle in its own cell, facing along the way it walks.
			local centre, radius, speed = at, spacing * 0.22, 0.55
			local y = model.PrimaryPart.Position.Y
			path = function(t: number): CFrame
				local a = t * speed + i
				local pos = Vector3.new(centre.X + math.cos(a) * radius, y, centre.Z + math.sin(a) * radius)
				local ahead = Vector3.new(-math.sin(a), 0, math.cos(a))
				return CFrame.lookAt(pos, pos + ahead)
			end
		end
		local rig = Animator.rig(model, { hover = entry.hover, seed = i * 7919, path = path })
		rig:setWalking(walker)
		table.insert(rigs, rig)
	end
	local stop = Animator.run(rigs)
	_G.MonsterLabStop = stop
	_G.MonsterLabRigs = rigs
	return stop
end

-- Lines the generated models up in a tight grid, each turned so its face (the side its `eyes` part
-- is on: the generator faces monsters any way it likes) looks toward -Z, then animates them.
-- Stop the animation first: this moves the models' rest poses. Returns stop().
function MonsterLab.arrangeLive(options: any?): () -> ()
	options = options or {}
	if _G.MonsterLabStop then
		pcall(_G.MonsterLabStop)
		_G.MonsterLabStop = nil
	end
	local spacing, perRow = options.spacing or 7, options.perRow or 8
	local origin = options.origin or Vector3.new(0, 0, 300)
	local models = workspace.MonsterGen:GetChildren()
	table.sort(models, function(a, b)
		return (a:GetAttribute("Line") or 0) < (b:GetAttribute("Line") or 0)
	end)
	for i, model in models do
		local body, eyes
		for _, p in model:GetDescendants() do
			if p:IsA("MeshPart") then
				local n = string.lower(p.Name)
				if isBody(p.Name) then
					body = p
				elseif string.find(n, "eye", 1, true) then
					eyes = p
				end
			end
		end
		if body then
			local yaw = 0
			if eyes then
				local d = eyes.Position - body.Position
				if Vector2.new(d.X, d.Z).Magnitude > 0.05 then
					-- Turn so that d points at -Z.
					yaw = math.atan2(d.X, d.Z) - math.pi
				end
			end
			local col, row = (i - 1) % perRow, (i - 1) // perRow
			local at = origin + Vector3.new(col * spacing, 0, row * spacing)
			local centre = model:GetBoundingBox().Position
			local turned = CFrame.new(centre) * CFrame.Angles(0, -yaw, 0) * CFrame.new(-centre)
			model:PivotTo(turned * model:GetPivot())
			local box, extent = model:GetBoundingBox()
			model:PivotTo(model:GetPivot() + (Vector3.new(at.X, extent.Y / 2, at.Z) - box.Position))
		end
	end
	return MonsterLab.animateLive(options)
end

-- Animates the freshly generated models where they stand (Workspace.MonsterGen), before their
-- parts are published: the quickest look. Returns stop().
function MonsterLab.animateLive(options: any?): () -> ()
	options = options or {}
	if _G.MonsterLabStop then
		pcall(_G.MonsterLabStop)
	end
	local rigs = {}
	for i, model in workspace.MonsterGen:GetChildren() do
		for _, p in model:GetDescendants() do
			if p:IsA("MeshPart") and isBody(p.Name) then
				model.PrimaryPart = p
			end
		end
		if model.PrimaryPart then
			local hover = model:GetAttribute("Hover") == true
			local walker = not hover and i % (options.walkers or 3) == 0
			local path
			if walker then
				local centre = model.PrimaryPart.Position
				local radius, speed = 2.6, 0.55
				path = function(t: number): CFrame
					local a = t * speed + i
					local pos = Vector3.new(centre.X + math.cos(a) * radius, centre.Y, centre.Z + math.sin(a) * radius)
					local ahead = Vector3.new(-math.sin(a), 0, math.cos(a))
					return CFrame.lookAt(pos, pos + ahead)
				end
			end
			local rig = Animator.rig(model, { hover = hover, seed = i * 7919, path = path })
			rig:setWalking(walker)
			table.insert(rigs, rig)
		end
	end
	local stop = Animator.run(rigs)
	_G.MonsterLabStop = stop
	_G.MonsterLabRigs = rigs
	return stop
end

return MonsterLab
