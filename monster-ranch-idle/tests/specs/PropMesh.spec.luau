--[[
	PropMesh + Config/PropMeshes: generated prop meshes swapped in for part-built props (decor
	pieces, the Deep Reef's props, battle stage props). The harness cannot load meshes, so a source
	hands in a MeshPart of known size and the fit, the hiding and the keep lists are checked.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local PropMeshes = t.Shared("Config.PropMeshes")
	local Tuning = t.Shared("Config.BattleStage")
	local Vector3, CFrame = t.Roblox.Vector3, t.Roblox.CFrame

	local function client()
		local h = TestKernel.new({ systems = { "Currency", "Progression", "Settings" } })
		local p = h:Join()
		local c = ClientHarness.new(h, p)
		c:Advance(0.5)
		return c
	end

	-- A PropMesh with a fake source that makes MeshParts of `size` and counts the loads.
	local function withSource(c, size)
		local PropMesh = c:require(c.clientFolder.Visuals.PropMesh)
		local loads = { n = 0 }
		PropMesh.SetSource(function(_entry)
			loads.n += 1
			local m = c.Instance.new("MeshPart")
			m.Size = size
			return m
		end)
		return PropMesh, loads
	end

	local function part(c, name: string, size, cf, parent)
		local p = c.Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Parent = parent
		return p
	end

	describe("PropMesh", function()
		it("fits the mesh over the parts it replaces, turned to their long side, and hides them", function()
			local c = client()
			local PropMesh, loads = withSource(c, Vector3.new(2, 4, 1))
			local model = c.Instance.new("Model")
			model.Parent = c.world.workspace
			-- The parts' box: x 4, y 0..6, z -4..4 (long side along z).
			local a = part(c, "A", Vector3.new(4, 2, 8), CFrame.new(0, 1, 0), model)
			local b = part(c, "B", Vector3.new(2, 6, 2), CFrame.new(0, 3, 3), model)
			local entry = { mesh = "rbxassetid://1", texture = "rbxassetid://2" }

			PropMesh.Replace(entry, { a, b }, CFrame.new(), model)
			expect(model:FindFirstChild("PropMesh")).toBeNil() -- deferred until the model is built
			c:Advance(0.1)
			local mesh = model:FindFirstChild("PropMesh")
			expect(mesh ~= nil).toBe(true)
			-- The mesh's long side (x) lay across the box's (z): turned, then its largest side (4)
			-- scaled to the box's largest (8), standing on the box's bottom.
			expect(math.abs(mesh.Size.Y - 8) < 1e-3).toBe(true)
			expect(math.abs(mesh.Size.X - 4) < 1e-3).toBe(true)
			expect(math.abs(mesh.Position.Y - 4) < 1e-3).toBe(true)
			expect(mesh.TextureID).toBe("rbxassetid://2")
			expect(mesh.CanCollide).toBe(false)
			expect(a.Transparency).toBe(1)
			expect(b.Transparency).toBe(1)
			expect(a.CanCollide).toBe(false)

			-- One load per asset: the next prop clones the template.
			local other = c.Instance.new("Model")
			other.Parent = c.world.workspace
			PropMesh.Replace(entry, { part(c, "C", Vector3.new(2, 2, 2), CFrame.new(10, 1, 0), other) }, CFrame.new(), other)
			c:Advance(0.1)
			expect(other:FindFirstChild("PropMesh") ~= nil).toBe(true)
			expect(loads.n).toBe(1)

			-- A model destroyed before its mesh lands gets nothing.
			local gone = c.Instance.new("Model")
			gone.Parent = c.world.workspace
			PropMesh.Replace(entry, { part(c, "D", Vector3.new(2, 2, 2), CFrame.new(20, 1, 0), gone) }, CFrame.new(), gone)
			gone.Parent = nil
			c:Advance(0.1)
			expect(gone:FindFirstChild("PropMesh")).toBeNil()
			PropMesh.SetSource(nil)
		end)

		it("changes nothing where meshes cannot load", function()
			local c = client()
			local PropMesh = c:require(c.clientFolder.Visuals.PropMesh)
			expect(PropMesh.Available()).toBe(false)
			local model = c.Instance.new("Model")
			model.Parent = c.world.workspace
			local a = part(c, "A", Vector3.new(2, 2, 2), CFrame.new(0, 1, 0), model)
			PropMesh.Replace(PropMeshes.decor.garden_fountain, { a }, CFrame.new(), model)
			c:Advance(0.1)
			expect(model:FindFirstChild("PropMesh")).toBeNil()
			expect(a.Transparency).toBe(0)
		end)
	end)

	describe("Config/PropMeshes", function()
		it("names real decor pieces, reef props and battle prop kinds, with ids", function()
			local function ok(entry)
				return type(entry.mesh) == "string"
					and entry.mesh:match("^rbxassetid://%d+$") ~= nil
					and type(entry.texture) == "string"
					and entry.texture:match("^rbxassetid://%d+$") ~= nil
			end
			for id, entry in PropMeshes.decor do
				expect(Config.Decor.ById[id] ~= nil).toBe(true)
				expect(ok(entry)).toBe(true)
			end
			for key, entry in PropMeshes.reef do
				expect(Config.DeepReef.Props[key] ~= nil).toBe(true)
				expect(ok(entry)).toBe(true)
			end
			local kinds = {}
			for _, theme in Tuning.themes do
				for _, prop in theme.props or {} do
					kinds[prop.kind] = true
				end
			end
			for kind, entry in PropMeshes.battle do
				expect(kinds[kind]).toBe(true)
				expect(ok(entry)).toBe(true)
			end
		end)
	end)

	describe("the builders", function()
		it("swaps the Garden Fountain's pieces for its mesh", function()
			local c = client()
			local PropMesh = withSource(c, Vector3.new(6, 5, 6))
			local DecorModel = c:require(c.clientFolder.Visuals.DecorModel)
			local model = DecorModel.Build(Config.Decor.ById.garden_fountain, CFrame.new(0, 0, 0), "full", c.world.workspace)
			c:Advance(0.1)
			expect(model:FindFirstChild("PropMesh") ~= nil).toBe(true)
			for _, child in model:GetChildren() do
				if child:IsA("BasePart") and child.Name ~= "PropMesh" then
					expect(child.Transparency).toBe(1)
				end
			end
			PropMesh.SetSource(nil)
		end)

		it("swaps only the parts a reef mesh stands for (the pier, not the pad; the bell, not its rope)", function()
			local c = client()
			local PropMesh = withSource(c, Vector3.new(6, 2, 18))
			local ReefBuild = c:require(c.clientFolder.Visuals.ReefBuild)
			local dock = ReefBuild.Dock(c.world.workspace)
			c:Advance(0.1)
			expect(dock:FindFirstChild("PropMesh") ~= nil).toBe(true)
			expect(dock:FindFirstChild("Plank1").Transparency).toBe(1)
			expect(dock:FindFirstChild("DivePad").Transparency < 1).toBe(true)
			expect(dock:FindFirstChild("Pool").Transparency < 1).toBe(true)
			local area = ReefBuild.Area(c.world.workspace, true)
			c:Advance(0.1)
			local bell = area:FindFirstChild("SurfaceBell")
			expect(bell:FindFirstChild("Bell").Transparency).toBe(1)
			expect(bell:FindFirstChild("Rope").Transparency < 1).toBe(true)
			expect(bell:FindFirstChild("ReturnPad").Transparency < 1).toBe(true)
			expect(area:FindFirstChild("Gate"):FindFirstChild("Portal").Transparency < 1).toBe(true)
			PropMesh.SetSource(nil)
		end)
	end)
end
