--[[
	3D monsters in the real client (ClientHarness): taps reach them, accessories hang off their rig
	and follow the pose, and Golden / Rainbow / Shadow textures come from MonsterLooks. The Lune mock
	has no CreateMeshPartAsync, so MeshMonster.SetMeshSource hands out a plain MeshPart; everything
	else (rig modules, bones, clips, attachments) is the real code path.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local RobloxMock = require("../runtime/RobloxMock")
	local Config = t.Shared("Config")
	local Appearance = t.Shared("Logic.Appearance")
	local Enum, Vector2, Vector3, CFrame = t.Roblox.Enum, t.Roblox.Vector2, t.Roblox.Vector3, t.Roblox.CFrame

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function expectClean(c, allow)
		local problems = c:Problems(allow)
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	-- Makes a client's monsters 3D wherever the form has a rig and published ids.
	local function sourced(c)
		local MeshMonster = c:require(c.clientFolder.Visuals.MeshMonster)
		MeshMonster.SetMeshSource(function()
			local part = c.Instance.new("MeshPart")
			part.Size = Vector3.new(1, 1, 1)
			return part
		end)
		return MeshMonster
	end

	local function meshClient(h, p)
		local c = ClientHarness.new(h, p, { noBoot = true })
		local MeshMonster = sourced(c)
		c:Boot()
		return c, MeshMonster
	end

	local function boneNames(c, form: string): { [string]: boolean }
		local rig = c:require(c.clientFolder.Visuals.MeshMonsters:FindFirstChild(form))
		local names = {}
		for _, bone in rig.bones do
			names[bone.name] = true
		end
		return names
	end

	-- A (line, stage, form) per rig shape: a head and a spine, a blob ("top") and a bug (no head).
	local function meshForms(c, MeshMonster)
		local found = {}
		for _, line in Config.Species.Lines do
			for stage = 1, 3 do
				local ok, ap = pcall(Appearance.Preview, line.id, stage)
				if ok and MeshMonster.Has(ap.form) then
					local names = boneNames(c, ap.form)
					local kind = if names.head
							and names.hips
							and names.chest
						then "spine"
						elseif names.top then "blob"
						elseif not names.head then "bug"
						else nil
					if kind and not found[kind] then
						found[kind] = { line = line.id, stage = stage, form = ap.form }
					end
				end
			end
		end
		return found
	end

	local function findModel(c, form: string)
		for _, d in c:Descendants(c.world.game:GetService("Workspace")) do
			if d:IsA("Model") and d:GetAttribute("Skinned") == true and d:GetAttribute("Form") == form then
				return d
			end
		end
		return nil
	end

	local function tap(c, part)
		c.world.raycastResult = { Instance = part, Position = part.Position }
		local uis = c.world.game:GetService("UserInputService")
		-- One touch is one InputObject from began to ended, as on a device.
		local input = RobloxMock.newInput(c.world, {
			UserInputType = Enum.UserInputType.Touch,
			UserInputState = Enum.UserInputState.Begin,
			Position = Vector3.new(200, 150, 0),
		})
		RobloxMock.fire(uis, "InputBegan", input, false)
		c.world.sched:runDeferred()
		RobloxMock.rawSet(input, "UserInputState", Enum.UserInputState.End)
		RobloxMock.fire(uis, "InputEnded", input, false)
		c.world.sched:runDeferred()
		c:Settle()
		c.world.raycastResult = nil
	end

	local function near(a: CFrame, b: CFrame): boolean
		return (a.Position - b.Position).Magnitude < 1e-3 and (a.LookVector - b.LookVector).Magnitude < 1e-3
	end

	local function luminance(pixels, i: number): number
		local o = (i - 1) * 4
		return 0.299 * buffer.readu8(pixels, o) + 0.587 * buffer.readu8(pixels, o + 1) + 0.114 * buffer.readu8(pixels, o + 2)
	end

	local function pixelBuffer(list)
		local pixels = buffer.create(#list * 4)
		for i, p in list do
			for j = 1, 4 do
				buffer.writeu8(pixels, (i - 1) * 4 + j - 1, p[j])
			end
		end
		return pixels
	end

	describe("3D monsters: taps", function()
		it("gives a 3D monster a hit box that a tap reaches (care for the owner, a pet for a visitor)", function()
			local h = TestKernel.new({ systems = allSystems() })
			local owner = h:Join(9101, "Owner")
			local visitor = h:Join(9102, "Visitor")
			local probe = ClientHarness.new(h, owner, { noBoot = true })
			local forms = meshForms(probe, sourced(probe))
			expect(forms.spine ~= nil).toBe(true)
			local pick = forms.spine
			local m = h:System("Monsters"):Create(owner, { line = pick.line, stage = pick.stage, rarity = 2 }, "test", true)
			h:Call(owner, "Ranch.Assign", { id = m.id, pen = 1 })
			h:Advance(Config.Social.PlotRefreshSeconds + 1)

			local mine = meshClient(h, owner)
			local theirs = meshClient(h, visitor)
			mine:Advance(2)
			local form = h:System("Monsters"):Appearance(owner, m.id).form
			local model = findModel(mine, form)
			expect(model ~= nil).toBe(true)
			local hit = model:FindFirstChild("Hit")
			expect(hit ~= nil and hit:IsA("BasePart")).toBe(true)
			expect(hit.CanQuery).toBe(true)
			expect(hit.Transparency).toBe(1)
			expect(model:FindFirstChild("Body")).toBeNil()
			expect(hit.Size.Y).toBeNear(model:GetAttribute("Height"), 0.01)

			tap(mine, hit)
			expect(mine.kernel.Router:IsOpen("Care")).toBe(true) -- glow-up Q: an own tap opens the care menu

			local other = findModel(theirs, form)
			expect(other ~= nil).toBe(true)
			theirs.requests = {}
			tap(theirs, other:FindFirstChild("Hit"))
			expect(table.find(theirs.requests, "Social.Pet") ~= nil).toBe(true)
			expectClean(mine)
			expectClean(theirs, { "Social.Pet" })
		end)
	end)

	describe("3D monsters: accessories", function()
		it("hangs every accessory on a spine rig, a blob and a bug, anchored to a bone", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c, MeshMonster = meshClient(h, p)
			c:Advance(1)
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local forms = meshForms(c, MeshMonster)
			local built = 0
			for kind, pick in forms do
				for _, acc in Config.Accessories.List do
					local ap = Appearance.Preview(pick.line, pick.stage)
					ap.acc = { [acc.slot] = acc.id }
					local model = MonsterModel.Build(ap)
					expect({ kind, acc.id, model:GetAttribute("Skinned") }).toEqual({ kind, acc.id, true })
					expect({ kind, acc.id, model:FindFirstChild("Acc_" .. acc.slot) ~= nil }).toEqual({ kind, acc.id, true })
					local anchor = model:FindFirstChild("AccAnchor_" .. acc.slot)
					local weld = anchor and anchor:FindFirstChildOfClass("Weld")
					expect({ kind, acc.id, weld ~= nil and weld.Part0 == model.PrimaryPart }).toEqual({ kind, acc.id, true })
					-- Placed at the rest pose, so an unanimated preview (Wardrobe, statues) wears it in place.
					expect(near(anchor.CFrame, model.PrimaryPart.CFrame * weld.C0)).toBe(true)
					model:Destroy()
					built += 1
				end
			end
			expect(built).toBe(3 * #Config.Accessories.List)
			expectClean(c)
		end)

		it("keeps accessories on the posed bones, through the animator's clip loop", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c, MeshMonster = meshClient(h, p)
			c:Advance(1)
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local MonsterAnimator = c:require(c.clientFolder.Visuals.MonsterAnimator)
			local pick = meshForms(c, MeshMonster).spine
			local head, back
			for _, acc in Config.Accessories.List do
				if acc.slot == "head" then
					head = head or acc.id
				elseif acc.slot == "back" then
					back = back or acc.id
				end
			end
			local ap = Appearance.Preview(pick.line, pick.stage)
			ap.acc = { head = head, back = back }
			local model = MonsterModel.Build(ap)
			local weld = model:FindFirstChild("AccAnchor_head"):FindFirstChildOfClass("Weld")
			local rest = weld.C0
			local restHead = MeshMonster.BoneCFrame(model, "head")
			expect(restHead ~= nil).toBe(true)
			local offset = restHead:Inverse() * rest

			-- The hop clip lifts the body: the hat goes up with the head bone, frame by frame.
			local lift = 0
			for i = 0, 20 do
				MeshMonster.Pose(model, "hop", i / 30, false)
				expect(MeshMonster.Follow(model)).toBe(true)
				expect(near(weld.C0, MeshMonster.BoneCFrame(model, "head") * offset)).toBe(true)
				lift = math.max(lift, weld.C0.Position.Y - rest.Position.Y)
			end
			expect(lift).toBeGreaterThan(0.02)

			-- The animator poses and then moves the accessories in the same step.
			MeshMonster.Pose(model, "idle", 0, true)
			MeshMonster.Follow(model)
			local camera = c.world.game:GetService("Workspace").CurrentCamera
			model.Parent = c.world.game:GetService("Workspace")
			local anim = MonsterAnimator.new(model)
			anim:SetBase(camera.CFrame * CFrame.new(0, 0, -12))
			anim:Play("happy")
			local moved = 0
			for _ = 1, 8 do
				c:Advance(0.05)
				moved = math.max(moved, (weld.C0.Position - rest.Position).Magnitude)
				expect(near(weld.C0, MeshMonster.BoneCFrame(model, "head") * offset)).toBe(true)
			end
			expect(moved).toBeGreaterThan(0.02)
			-- A skinned monster has no Body to squash or hue-cycle.
			local mesh = model:FindFirstChild("Mesh")
			local color = mesh.Color
			anim:Destroy()
			expect(mesh.Color).toEqual(color)
			model:Destroy()
			expectClean(c)
		end)

		it("rebuilds the ranch model when a monster puts an accessory on", function()
			local h = TestKernel.new({ systems = allSystems() })
			local owner = h:Join(9201, "Owner")
			local probe = ClientHarness.new(h, owner, { noBoot = true })
			local pick = meshForms(probe, sourced(probe)).spine
			local M = h:System("Monsters")
			local m = M:Create(owner, { line = pick.line, stage = pick.stage, rarity = 2 }, "test", true)
			h:Call(owner, "Ranch.Assign", { id = m.id, pen = 1 })
			h:Advance(Config.Social.PlotRefreshSeconds + 1)
			local c = meshClient(h, owner)
			c:Advance(2)
			local form = M:Appearance(owner, m.id).form
			local before = findModel(c, form)
			expect(before ~= nil).toBe(true)
			expect(before:FindFirstChild("Acc_neck")).toBeNil()
			local neck
			for _, acc in Config.Accessories.List do
				if acc.slot == "neck" then
					neck = neck or acc.id
				end
			end
			M:SetAccessory(owner, m.id, "neck", neck)
			c:Advance(Config.Social.PlotRefreshSeconds + 1)
			local after = findModel(c, form)
			expect(after ~= nil and after:FindFirstChild("Acc_neck") ~= nil).toBe(true)
			expectClean(c)
		end)
	end)

	describe("3D monsters: Golden, Rainbow and Shadow textures", function()
		local SAMPLES = {
			{ 20, 20, 20, 255 },
			{ 90, 60, 40, 200 },
			{ 128, 128, 128, 17 },
			{ 200, 120, 220, 255 },
			{ 40, 200, 90, 128 },
			{ 250, 250, 250, 0 },
		}

		it("recolours pixels: gold keeps the shading order, shadow is darker and purple, alpha stays", function()
			local h = TestKernel.new({ systems = { "Currency" } })
			local c = ClientHarness.new(h, h:Join(), { noBoot = true })
			local Looks = c:require(c.clientFolder.Visuals.MonsterLooks)
			local source = pixelBuffer(SAMPLES)

			local gold = pixelBuffer(SAMPLES)
			Looks.Recolor("golden", gold, #SAMPLES, 1)
			for i = 1, #SAMPLES do
				expect(buffer.readu8(gold, (i - 1) * 4 + 3)).toBe(SAMPLES[i][4])
				local r, g, b = buffer.readu8(gold, (i - 1) * 4), buffer.readu8(gold, (i - 1) * 4 + 1), buffer.readu8(gold, (i - 1) * 4 + 2)
				expect(r >= g and g >= b).toBe(true) -- warm: red over green over blue
				for j = 1, #SAMPLES do
					if luminance(source, i) < luminance(source, j) then
						expect(luminance(gold, i) < luminance(gold, j)).toBe(true)
					end
				end
			end

			local shadow = pixelBuffer(SAMPLES)
			Looks.Recolor("shadow", shadow, #SAMPLES, 1)
			for i = 1, #SAMPLES do
				expect(buffer.readu8(shadow, (i - 1) * 4 + 3)).toBe(SAMPLES[i][4])
				local r, g, b =
					buffer.readu8(shadow, (i - 1) * 4), buffer.readu8(shadow, (i - 1) * 4 + 1), buffer.readu8(shadow, (i - 1) * 4 + 2)
				expect(b > r and r > g).toBe(true)
				if luminance(source, i) > 40 then
					expect(luminance(shadow, i) < luminance(source, i)).toBe(true)
				end
			end

			-- Rainbow: one grey across a row turns into several hues; alpha stays.
			local row = {}
			for i = 1, 8 do
				row[i] = { 150, 150, 150, i * 20 }
			end
			local rainbow = pixelBuffer(row)
			Looks.Recolor("rainbow", rainbow, 8, 1)
			local seen, distinct = {}, 0
			for i = 1, 8 do
				expect(buffer.readu8(rainbow, (i - 1) * 4 + 3)).toBe(i * 20)
				local key = buffer.readu8(rainbow, (i - 1) * 4)
					.. ","
					.. buffer.readu8(rainbow, (i - 1) * 4 + 1)
					.. ","
					.. buffer.readu8(rainbow, (i - 1) * 4 + 2)
				if not seen[key] then
					seen[key] = true
					distinct += 1
				end
			end
			expect(distinct >= 5).toBe(true)

			expect(Looks.For({ variant = 1 })).toBe("golden")
			expect(Looks.For({ variant = 2, muts = { "shadow" } })).toBe("rainbow")
			expect(Looks.For({ variant = 1, muts = { "shadow" } })).toBe("shadow")
			expect(Looks.For({ variant = 0, muts = {} })).toBeNil()
		end)

		it("draws one image per form and look, shares it, and drops the least recently used", function()
			local h = TestKernel.new({ systems = { "Currency" } })
			local c = ClientHarness.new(h, h:Join(), { noBoot = true })
			local Looks = c:require(c.clientFolder.Visuals.MonsterLooks)
			local created, bound = {}, {}
			Looks.SetBackend({
				create = function(textureId)
					local image = { Size = Vector2.new(4, 3), texture = textureId, destroyed = false, written = nil }
					function image:ReadPixelsBuffer(_, size)
						local pixels = buffer.create(size.X * size.Y * 4)
						buffer.fill(pixels, 0, 100)
						return pixels
					end
					function image:WritePixelsBuffer(_, _, pixels)
						self.written = pixels
					end
					function image:Destroy()
						self.destroyed = true
					end
					table.insert(created, image)
					return image
				end,
				bind = function(mesh, image)
					bound[mesh] = image
				end,
				unbind = function(mesh, textureId)
					bound[mesh] = textureId
				end,
			})
			local a, b = {}, {}
			c.world:Run(function()
				Looks.Apply(a, "fox", "golden", "rbxassetid://11")
				Looks.Apply(b, "fox", "golden", "rbxassetid://11")
			end)
			c:Advance(0.1)
			expect(#created).toBe(1)
			expect(bound[a]).toBe(created[1])
			expect(bound[b]).toBe(created[1])
			expect(buffer.readu8(created[1].written, 0) ~= 100).toBe(true) -- recoloured
			expect(buffer.readu8(created[1].written, 3)).toBe(100) -- alpha untouched

			local meshes = { a }
			c.world:Run(function()
				for i = 2, 8 do
					meshes[i] = {}
					Looks.Apply(meshes[i], "form" .. i, "shadow", "rbxassetid://" .. i)
				end
			end)
			c:Advance(0.1)
			expect(Looks.Count()).toBe(8)
			c.world:Run(function()
				Looks.Apply({}, "fox", "golden", "rbxassetid://11") -- touch: now the most recent
				Looks.Apply({}, "form9", "rainbow", "rbxassetid://9")
			end)
			c:Advance(0.1)
			expect(Looks.Count()).toBe(8)
			expect(created[1].destroyed).toBe(false)
			expect(created[2].destroyed).toBe(true) -- form2 was the least recently used
			expect(bound[meshes[2]]).toBe("rbxassetid://2") -- its monster got the normal texture back
			expect(bound[a]).toBe(created[1])
			expectClean(c)
		end)

		it("keeps the normal texture and warns once when the image API is missing", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c, MeshMonster = meshClient(h, p)
			c:Advance(1)
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local Looks = c:require(c.clientFolder.Visuals.MonsterLooks)
			local pick = meshForms(c, MeshMonster).spine
			local golden = MonsterModel.Build(Appearance.Preview(pick.line, pick.stage, nil, 1, 1))
			local rainbow = MonsterModel.Build(Appearance.Preview(pick.line, pick.stage, nil, 1, 2))
			local plain = MonsterModel.Build(Appearance.Preview(pick.line, pick.stage))
			local statue = MonsterModel.Build(Appearance.Preview(pick.line, pick.stage), { vfx = false, look = "golden" })
			c:Advance(0.5)
			expect(golden:GetAttribute("Look")).toBe("golden")
			expect(golden:GetAttribute("Rainbow")).toBe(false)
			expect(rainbow:GetAttribute("Look")).toBe("rainbow")
			expect(rainbow:GetAttribute("Rainbow")).toBe(true)
			expect(statue:GetAttribute("Look")).toBe("golden")
			expect(plain:GetAttribute("Look")).toBeNil()
			expect(golden:FindFirstChild("Mesh").TextureID).toBe(plain:FindFirstChild("Mesh").TextureID)
			expect(Looks.Count()).toBe(0)
			local warns = 0
			for _, w in c.world.warnings do
				if string.find(w, "MonsterLooks", 1, true) then
					warns += 1
				end
			end
			expect(warns).toBe(1)
			expectClean(c, { "MonsterLooks" })
		end)
	end)
end
