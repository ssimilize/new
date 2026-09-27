--[[
	R2-LOWQ: low-poly meshes for Low graphics and crowd-capped fights (tools/blender/lowpoly.py's
	output, MeshMonsterAssets.<form>.lowMesh). MonsterModel.Build picks the low mesh when Quality is
	Low or opts.crowded is true and the form has one, falls back to the full mesh when it does not,
	loads each variant once per form, and the 2D battle view (Parts/BattleReplay, Components/MonsterIcon)
	already shows the monster's portrait instead of a procedural shape - proved here rather than the
	old-phone shape fallback the packet went looking for (MonsterModel.luau; MeshMonster.Has), which
	turned out not to exist: nothing before this change read Quality at all, so a Low or crowded player
	got the very same full mesh as everyone once a form's mesh+texture ids were set, and only a form
	still missing them ever showed MonsterModel's placeholder - the same for every quality level.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Appearance = t.Shared("Logic.Appearance")
	local Vector3 = t.Roblox.Vector3

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function expectClean(c)
		local problems = c:Problems()
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	-- A meshSource that counts calls per (form, cheap) so "one load per form [and variant]" is provable.
	local function countingClient(h, p)
		local c = ClientHarness.new(h, p, { noBoot = true })
		local MeshMonster = c:require(c.clientFolder.Visuals.MeshMonster)
		local calls = {}
		MeshMonster.SetMeshSource(function(form, cheap)
			local key = form .. ":" .. tostring(cheap == true)
			calls[key] = (calls[key] or 0) + 1
			local part = c.Instance.new("MeshPart")
			part.Size = Vector3.new(1, 1, 1)
			return part
		end)
		c:Boot()
		return c, MeshMonster, calls
	end

	-- Any form whose rig module is present and whose ids are set (meshForms in MeshMonsterClient.spec
	-- picks by rig shape; here any one is enough). `skip` avoids MeshMonster's own Data cache: once a
	-- form has been built, its lowMesh id is cached from the first read, so a fallback case needs a
	-- form of its own, not the same one with MeshMonsterAssets edited back to "".
	local function pickForm(MeshMonster, skip: { [string]: boolean }?)
		for _, line in Config.Species.Lines do
			for stage = 1, 3 do
				local ok, ap = pcall(Appearance.Preview, line.id, stage)
				if ok and MeshMonster.Has(ap.form) and not (skip and skip[ap.form]) then
					return ap.form, line.id, stage
				end
			end
		end
		error("no mesh-monster form found to test with")
	end

	describe("R2-LOWQ: MonsterModel.Build picks the low-poly mesh", function()
		it("builds the low mesh on Low graphics when the form has one, and falls back when it does not", function()
			local h = TestKernel.new({ systems = allSystems() })
			local c, MeshMonster, calls = countingClient(h, h:Join())
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local Assets = c:require(c.clientFolder.Visuals.MeshMonsterAssets)
			local Quality = c:require(c.clientFolder.Visuals.Quality)
			local formA, lineA, stageA = pickForm(MeshMonster)
			local formB, lineB, stageB = pickForm(MeshMonster, { [formA] = true })
			Assets[formA].lowMesh = "rbxassetid://9999999"
			Assets[formB].lowMesh = "" -- every published form has a low mesh now: take formB's away

			Quality.SetAuto(1)
			expect(Quality.IsLow()).toBe(true)
			local apA, apB = Appearance.Preview(lineA, stageA), Appearance.Preview(lineB, stageB)
			local lowModel = MonsterModel.Build(apA)
			expect(lowModel:GetAttribute("LowPoly")).toBe(true)
			expect(calls[formA .. ":true"]).toBe(1)
			expect(calls[formA .. ":false"]).toBe(nil) -- the full mesh was never asked for

			Quality.SetAuto(3)
			expect(Quality.IsLow()).toBe(false)
			local highModel = MonsterModel.Build(apA)
			expect(highModel:GetAttribute("LowPoly")).toBe(false)
			expect(calls[formA .. ":false"]).toBe(1)

			-- formB has no lowMesh id: today's behaviour (the full mesh), even on Low / crowded.
			-- meshSource's second argument is which variant was actually built, so the fallback shows
			-- up as ":false" (full) even though `cheap` (Low + crowded) was asked for.
			Quality.SetAuto(1)
			local fallback = MonsterModel.Build(apB, { crowded = true })
			expect(fallback:GetAttribute("LowPoly")).toBe(false)
			expect(calls[formB .. ":false"]).toBe(1) -- asked cheap, built full: the fallback ran
			expect(calls[formB .. ":true"]).toBe(nil)
			expect(fallback:FindFirstChild("Mesh") ~= nil).toBe(true)

			lowModel:Destroy()
			highModel:Destroy()
			fallback:Destroy()
			expectClean(c)
		end)

		it("loads each variant once per form and clones it for every monster", function()
			local h = TestKernel.new({ systems = allSystems() })
			local c, MeshMonster, calls = countingClient(h, h:Join())
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local Assets = c:require(c.clientFolder.Visuals.MeshMonsterAssets)
			local form, line, stage = pickForm(MeshMonster)
			Assets[form].lowMesh = "rbxassetid://9999998"
			local ap = Appearance.Preview(line, stage)

			local models = {}
			for _ = 1, 5 do
				table.insert(models, MonsterModel.Build(ap, { crowded = true }))
			end
			table.insert(models, MonsterModel.Build(ap)) -- Quality is High by default: the full mesh
			expect(calls[form .. ":true"]).toBe(1)
			expect(calls[form .. ":false"]).toBe(1)
			for i = 1, 5 do
				expect(models[i]:FindFirstChild("Mesh") ~= nil).toBe(true)
			end
			for _, m in models do
				m:Destroy()
			end
			expectClean(c)
		end)

		it("keeps the same rig on the low mesh: bones, clips and Follow are unaffected", function()
			local h = TestKernel.new({ systems = allSystems() })
			local c, MeshMonster = countingClient(h, h:Join())
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local Assets = c:require(c.clientFolder.Visuals.MeshMonsterAssets)
			local Quality = c:require(c.clientFolder.Visuals.Quality)
			local form, line, stage = pickForm(MeshMonster)
			Assets[form].lowMesh = "rbxassetid://9999997"
			Quality.SetAuto(1)
			local model = MonsterModel.Build(Appearance.Preview(line, stage))
			expect(model:GetAttribute("LowPoly")).toBe(true)
			expect(MeshMonster.HasClip(model, "idle")).toBe(true)
			MeshMonster.Pose(model, "idle", 0.1, true)
			expect(MeshMonster.BoneCFrame(model, "root") ~= nil).toBe(true) -- every rig has one
			model:Destroy()
			expectClean(c)
		end)
		it("draws the full mesh, not the placeholder, when a low mesh fails to load", function()
			local h = TestKernel.new({ systems = allSystems() })
			local c = ClientHarness.new(h, h:Join(), { noBoot = true })
			local MeshMonster = c:require(c.clientFolder.Visuals.MeshMonster)
			local calls = {}
			MeshMonster.SetMeshSource(function(form, cheap)
				local key = form .. ":" .. tostring(cheap == true)
				calls[key] = (calls[key] or 0) + 1
				if cheap then
					error("asset is not approved for the requester") -- a live server refusing the burner's mesh
				end
				local part = c.Instance.new("MeshPart")
				part.Size = Vector3.new(1, 1, 1)
				return part
			end)
			c:Boot()
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local Assets = c:require(c.clientFolder.Visuals.MeshMonsterAssets)
			local form, line, stage = pickForm(MeshMonster)
			Assets[form].lowMesh = "rbxassetid://9999996"
			local ap = Appearance.Preview(line, stage)

			local first = MonsterModel.Build(ap, { crowded = true })
			expect(first:FindFirstChild("Mesh") ~= nil).toBe(true)
			expect(first:GetAttribute("LowPoly")).toBe(false)
			local second = MonsterModel.Build(ap, { crowded = true })
			expect(second:FindFirstChild("Mesh") ~= nil).toBe(true)
			expect(calls[form .. ":true"]).toBe(1) -- tried once, then dropped for the session
			expect(calls[form .. ":false"]).toBe(1)
			first:Destroy()
			second:Destroy()
			expectClean(c)
		end)
	end)

	describe("R2-LOWQ: the 2D battle view draws portraits, not shapes", function()
		it("shows the uploaded portrait for a form that has one, on Low quality, instead of the procedural blob", function()
			local h = TestKernel.new({ systems = allSystems() })
			local c = ClientHarness.new(h, h:Join())
			c:Advance(1)
			local Quality = c:require(c.clientFolder.Visuals.Quality)
			local MonsterIcon = c:require(c.clientFolder.UI.Components.MonsterIcon)
			local Sheet = c:require(c.clientFolder.UI.Art.Sheet)
			Quality.SetAuto(1)
			expect(Quality.IsLow()).toBe(true)

			-- buzzbee has an uploaded portrait cell (UI/Art/Portraits): a real, already-shipped case.
			local form = "buzzbee"
			expect(Sheet.has(Sheet.Portraits, form)).toBe(true)
			local ap = { form = form, elements = { "spark" }, archetype = "bug", stage = 1, variant = 0, muts = {} }
			local icon = MonsterIcon.new(ap, 80)
			local art = icon:FindFirstChild("Portrait")
			expect(art ~= nil and art:IsA("ImageLabel")).toBe(true)

			-- A form with no portrait cell falls back to the procedural shape, on the same Low level:
			-- the choice is the sheet's, not the quality's (nothing in this file changes that).
			local noArt = { form = "zzz-not-a-real-form", elements = { "sprout" }, archetype = "blob", stage = 1, variant = 0, muts = {} }
			local blobIcon = MonsterIcon.new(noArt, 80)
			expect(blobIcon:FindFirstChild("Portrait")).toBeNil()
			expectClean(c)
		end)
	end)
end
