--[[
	EggModel: the eggs' contract on the placeholder path (the Lune mock has no CreateMeshPartAsync,
	and no ids are published yet) and on the mesh path (EggModel.SetMeshLoader stands in for
	AssetService), the crack stages, the READY glow, and the EggAssets data (tools/blender/eggs.py).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Presets = t.Shared("Config.Vfx")
	local SpriteIds = t.Shared("Config.VfxSprites")

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function boot()
		local h = TestKernel.new({ systems = allSystems() })
		local p = h:Join()
		local c = ClientHarness.new(h, p)
		c:Advance(1)
		local EggModel = c:require(c.clientFolder.Visuals.EggModel)
		local Assets = c:require(c.clientFolder.Visuals.EggAssets)
		local Vfx = c:require(c.clientFolder.Visuals.Vfx)
		return c, EggModel, Assets, Vfx
	end

	local function expectClean(c)
		local problems = c:Problems()
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	local function count(root, className: string): number
		local n = 0
		for _, d in root:GetDescendants() do
			if d:IsA(className) then
				n += 1
			end
		end
		return n
	end

	local function near(a, b): boolean
		return (a - b).Magnitude < 1e-4
	end

	local function expectContract(c, model, eggType: string, size: number, anchored: boolean)
		local V3 = c.globals.Vector3
		expect(model:IsA("Model")).toBe(true)
		local root = model.PrimaryPart
		expect(root ~= nil).toBe(true)
		expect(root.Name).toBe("Root")
		expect(root.Anchored).toBe(anchored)
		expect(near(root.Size, V3.new(size, size * 1.3, size))).toBe(true)
		expect(model:GetAttribute("EggType")).toBe(eggType)
		expect(model:GetAttribute("CrackStage")).toBe(0)
		expect(count(model, "Sparkles") + count(model, "Fire")).toBe(0) -- the old decorations are gone
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= root then
				expect(d.Anchored).toBe(false) -- everything else rides on Root's welds
			end
		end
	end

	-- Every id filled with a fake one, and a loader that makes a MeshPart per uri (counted).
	local function publishAll(c, EggModel, Assets)
		local saved = {
			meshes = table.clone(Assets.meshes),
			textures = table.clone(Assets.textures),
			ornaments = {},
			cracks = table.clone(Assets.cracks),
			painted = Assets.painted,
		}
		local n = 100
		local function nextId(): string
			n += 1
			return "rbxassetid://" .. n
		end
		Assets.meshes.shell = nextId()
		Assets.meshes.gem = nextId()
		for id in Assets.textures do
			Assets.textures[id] = nextId()
		end
		for id, orn in Assets.ornaments do
			saved.ornaments[id] = table.clone(orn)
			orn.mesh = nextId()
			orn.texture = "rbxassetid://99"
		end
		for i = 1, 3 do
			Assets.cracks[i] = nextId()
		end
		Assets.painted = nextId()
		local calls = {}
		EggModel.SetMeshLoader(function(uri: string)
			calls[uri] = (calls[uri] or 0) + 1
			local part = c.Instance.new("MeshPart")
			local egg = uri == Assets.meshes.shell or uri == Assets.meshes.gem
			part.Size = if egg then c.globals.Vector3.new(1, 1.3, 1) else c.globals.Vector3.new(0.3, 0.2, 0.3)
			return part
		end)
		local function restore()
			EggModel.SetMeshLoader(nil)
			for k, v in saved.meshes do
				Assets.meshes[k] = v
			end
			for k, v in saved.textures do
				Assets.textures[k] = v
			end
			for k, v in saved.ornaments do
				Assets.ornaments[k].mesh, Assets.ornaments[k].texture = v.mesh, v.texture
			end
			for i = 1, 3 do
				Assets.cracks[i] = saved.cracks[i]
			end
			Assets.painted = saved.painted
		end
		return calls, restore
	end

	describe("EggAssets", function()
		it("lists every egg in Config.Eggs, and its ids are empty or asset ids", function()
			local c, _, Assets = boot()
			local function isId(v)
				return v == "" or string.match(v, "^rbxassetid://%d+$") ~= nil
			end
			for _, def in Config.Eggs.List do
				expect({ def.id, type(Assets.textures[def.id]) }).toEqual({ def.id, "string" })
			end
			for id, v in Assets.textures do
				expect({ id, Config.Eggs.ById[id] ~= nil, isId(v) }).toEqual({ id, true, true })
			end
			expect(isId(Assets.meshes.shell) and isId(Assets.meshes.gem)).toBe(true)
			for id, shape in Assets.shapes do
				expect({ id, Config.Eggs.ById[id] ~= nil, Assets.meshes[shape] ~= nil }).toEqual({ id, true, true })
			end
			expect(Assets.shapes.crystal).toBe("gem")
			for id, orn in Assets.ornaments do
				expect({ id, Config.Eggs.ById[id] ~= nil, isId(orn.mesh), isId(orn.texture) }).toEqual({ id, true, true, true })
				expect(#orn.offset).toBe(3)
				for _, x in orn.offset do
					expect(type(x) == "number" and math.abs(x) < 1).toBe(true)
				end
			end
			expect(#Assets.cracks).toBe(3)
			for _, v in Assets.cracks do
				expect(isId(v)).toBe(true)
			end
			expect(isId(Assets.painted)).toBe(true)
			expectClean(c)
		end)
	end)

	describe("EggModel placeholder", function()
		it("builds every egg to the contract without published ids", function()
			local c, EggModel = boot()
			for _, def in Config.Eggs.List do
				expect(EggModel.Has(def.id)).toBe(false)
				local model = EggModel.Build(def.id)
				expectContract(c, model, def.id, 2, true)
				expect(model.Name).toBe(def.name)
				expect(count(model, "MeshPart")).toBe(0)
				expect(model:FindFirstChild("Spot1") ~= nil).toBe(true)
			end
			expectContract(c, EggModel.Build("royal", { anchored = false, size = 3 }), "royal", 3, false)
			expectContract(c, EggModel.Build("starter"), "starter", 2, true) -- not a shop egg: still an egg
			local tint = c.globals.Color3.new(1, 0, 0)
			local hunt = EggModel.Build("bloom", { size = 2.2, tint = tint })
			expectContract(c, hunt, "bloom", 2.2, true)
			expect(hunt.PrimaryPart.Color).toBe(tint)
			expectClean(c)
		end)

		it("stays the placeholder while ids are empty, even where meshes can load", function()
			local c, EggModel = boot()
			local called = 0
			EggModel.SetMeshLoader(function()
				called += 1
				return c.Instance.new("MeshPart")
			end)
			local model = EggModel.Build("meadow")
			EggModel.SetMeshLoader(nil)
			expectContract(c, model, "meadow", 2, true)
			expect(count(model, "MeshPart")).toBe(0)
			expect(called).toBe(0)
			expectClean(c)
		end)

		it("cracks in three stages and clamps the stage", function()
			local c, EggModel = boot()
			local model = EggModel.Build("meadow")
			local sizes = {}
			for stage = 1, 3 do
				EggModel.SetCrack(model, stage)
				expect(model:GetAttribute("CrackStage")).toBe(stage)
				local crack = model:FindFirstChild("Crack")
				expect(crack ~= nil).toBe(true)
				sizes[stage] = #crack:GetChildren()
				for _, bar in crack:GetChildren() do
					expect(bar.Anchored).toBe(false)
				end
			end
			expect(sizes[1] < sizes[2] and sizes[2] < sizes[3]).toBe(true)
			EggModel.SetCrack(model, 0)
			expect(model:FindFirstChild("Crack")).toBe(nil)
			expect(model:GetAttribute("CrackStage")).toBe(0)
			EggModel.SetCrack(model, 9)
			expect(model:GetAttribute("CrackStage")).toBe(3)
			EggModel.SetCrack(model, -2)
			expect(model:GetAttribute("CrackStage")).toBe(0)
			expectClean(c)
		end)
	end)

	describe("EggModel mesh", function()
		it("builds every egg from the shared mesh, its texture and its ornament, one load per mesh", function()
			local c, EggModel, Assets = boot()
			local calls, restore = publishAll(c, EggModel, Assets)
			for round = 1, 2 do
				for _, def in Config.Eggs.List do
					expect(EggModel.Has(def.id)).toBe(true)
					local model = EggModel.Build(def.id, { size = 2.5, anchored = round == 1 })
					expectContract(c, model, def.id, 2.5, round == 1)
					local root = model.PrimaryPart
					expect(root:IsA("MeshPart")).toBe(true)
					expect(root.TextureID).toBe(Assets.textures[def.id])
					expect(model:FindFirstChild("Spot1")).toBe(nil)
					local orn = model:FindFirstChild("Ornament")
					expect({ def.id, orn ~= nil }).toEqual({ def.id, Assets.ornaments[def.id] ~= nil })
					if orn then
						expect(orn.TextureID).toBe(Assets.ornaments[def.id].texture)
						expect(near(orn.Size, c.globals.Vector3.new(0.75, 0.5, 0.75))).toBe(true)
						local weld = orn:FindFirstChildOfClass("WeldConstraint")
						expect(weld ~= nil and weld.Part0 == root).toBe(true)
					end
				end
			end
			expect(calls[Assets.meshes.shell]).toBe(1)
			expect(calls[Assets.meshes.gem]).toBe(1) -- the Crystal Egg
			for _, orn in Assets.ornaments do
				expect(calls[orn.mesh]).toBe(1)
			end
			-- The hunt's painted egg: a plain shell in the colour, the white paint over it.
			local tint = c.globals.Color3.new(0, 1, 0)
			local hunt = EggModel.Build("bloom", { size = 2.2, tint = tint })
			expectContract(c, hunt, "bloom", 2.2, true)
			expect(hunt.PrimaryPart.TextureID).toBe("")
			expect(hunt.PrimaryPart.Color).toBe(tint)
			expect(hunt:FindFirstChild("Paint").TextureID).toBe(Assets.painted)
			expect(hunt:FindFirstChild("Ornament")).toBe(nil)
			restore()
			expectClean(c)
		end)

		it("overlays the crack image on the egg's own mesh, one stage at a time", function()
			local c, EggModel, Assets = boot()
			local _, restore = publishAll(c, EggModel, Assets)
			for _, eggType in { "meadow", "crystal" } do
				local model = EggModel.Build(eggType)
				local root = model.PrimaryPart
				for stage = 1, 3 do
					EggModel.SetCrack(model, stage)
					local crack = model:FindFirstChild("Crack")
					expect(crack:IsA("MeshPart")).toBe(true)
					expect(crack.TextureID).toBe(Assets.cracks[stage])
					expect(near(crack.Size, root.Size * 1.03)).toBe(true)
					local n = 0
					for _, child in model:GetChildren() do
						if child.Name == "Crack" then
							n += 1
						end
					end
					expect(n).toBe(1)
				end
				EggModel.SetCrack(model, 0)
				expect(model:FindFirstChild("Crack")).toBe(nil)
			end
			restore()
			expectClean(c)
		end)

		it("falls back to the placeholder when a mesh cannot load", function()
			local c, EggModel, Assets = boot()
			local _, restore = publishAll(c, EggModel, Assets)
			EggModel.SetMeshLoader(function()
				error("HTTP 403")
			end)
			local model = EggModel.Build("royal")
			expectContract(c, model, "royal", 2, true)
			expect(count(model, "MeshPart")).toBe(0)
			restore()
		end)
	end)

	describe("EggModel effects", function()
		it("sparkles with the game's particles, glows when ready, and stays bare in a viewport", function()
			local c, EggModel, _, Vfx = boot()
			local starUploaded = type(SpriteIds.star) == "table" and SpriteIds.star.grey ~= ""
			local royal = EggModel.Build("royal")
			local plain = EggModel.Build("meadow")
			expect(Presets.Eggs.meadow).toBe(nil)
			expect(Vfx.Count(plain)).toBe(0)
			if starUploaded then
				expect(Vfx.Count(royal)).toBe(#Presets.Eggs.royal)
			end
			expect(Vfx.Count(EggModel.Build("royal", { vfx = false }))).toBe(0)

			EggModel.SetReady(plain, true)
			expect(plain:GetAttribute("Ready")).toBe(true)
			expect(plain.PrimaryPart:FindFirstChild("ReadyGlow") ~= nil).toBe(true)
			if starUploaded then
				expect(Vfx.Count(plain) > 0).toBe(true)
			end
			EggModel.SetReady(plain, true) -- twice is still one glow
			local lights = 0
			for _, d in plain.PrimaryPart:GetChildren() do
				if d.Name == "ReadyGlow" then
					lights += 1
				end
			end
			expect(lights).toBe(1)
			EggModel.SetReady(plain, false)
			expect(plain:GetAttribute("Ready")).toBe(false)
			expect(plain.PrimaryPart:FindFirstChild("ReadyGlow")).toBe(nil)
			expect(Vfx.Count(plain)).toBe(0)

			local bare = EggModel.Build("royal", { vfx = false })
			EggModel.SetReady(bare, true)
			expect(Vfx.Count(bare)).toBe(0)
			expectClean(c)
		end)

		it("keeps every egg effect inside a small particle budget", function()
			for id, specs in Presets.Eggs do
				expect({ id, Config.Eggs.ById[id] ~= nil }).toEqual({ id, true })
				local live = 0
				for _, spec in specs do
					live += (spec.rate or 0) * spec.lifetime[2]
				end
				expect({ id, live <= 5 }).toEqual({ id, true })
			end
		end)
	end)
end
