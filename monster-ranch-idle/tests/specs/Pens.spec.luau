--[[
	Glow-up R · pens that grow: Logic/Pens (fence tiers, upgrade props, theme looks, habitats, crop
	stages, part budgets) as units; Plots replicating pen upgrades and the Feed Garden; and the real
	client (ClientHarness) dressing pens and the garden, rebuilding only on change, for the owner
	and for a visitor.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Pens")
	local Enum, CFrame = t.Roblox.Enum, t.Roblox.CFrame
	local P = Config.Pens
	local Economy = Config.Economy

	local SHAPES = { block = true, ball = true, cyl = true, wedge = true }
	local TOKENS = { fence = true, ground = true, element = true, accent = true }

	local function monsters(...)
		local list = {}
		for _, elements in { ... } do
			table.insert(list, { id = tostring(#list + 1), appearance = { elements = elements } })
		end
		return list
	end

	local function validMaterial(name: string): boolean
		local ok, value = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		return ok and value ~= nil
	end

	describe("Pens · rules", function()
		it("picks the fence tier from the jar tier: wood, timber, stone, crystal", function()
			local ids = {}
			for tier = 0, #Economy.JarTiers + 1 do
				table.insert(ids, (Logic.Fence(Config, tier)).id)
			end
			expect(table.concat(ids, ",")).toBe("wood,wood,timber,stone,crystal,crystal")
			expect((Logic.Fence(Config, nil)).id).toBe("wood")
		end)

		it("adds one visible prop at every capacity step, ending with food, water, shelter and bed", function()
			for cap = Economy.Pens.startCapacity, Economy.Pens.maxCapacity do
				expect(#Logic.Upgrades(Config, cap)).toBe(cap - Economy.Pens.startCapacity + 1)
			end
			local spots = {}
			for _, e in Logic.Upgrades(Config, Economy.Pens.maxCapacity) do
				spots[P.Props[e.id].spot] = true
			end
			expect(spots.food and spots.water and spots.shelter and spots.bed).toBe(true)
		end)

		it("gives every pen theme a look with one or two signature props, and every element a habitat", function()
			local missing = {}
			for _, theme in Config.Decor.PenThemes do
				local look = P.Themes[theme.id]
				if not look or #look.props < 1 or #look.props > 2 then
					table.insert(missing, "theme " .. theme.id)
				else
					for _, id in look.props do
						if not P.Props[id] then
							table.insert(missing, "prop " .. id)
						end
					end
				end
			end
			for _, element in Config.Elements.List do
				local id = P.Habitats[element.id]
				if not id or not P.Props[id] or not P.Props[id].spot then
					table.insert(missing, "habitat " .. element.id)
				end
			end
			expect(table.concat(missing, "; ")).toBe("")
			local look, id = Logic.Theme(Config, "a_player_designed_theme")
			expect(id).toBe(P.DefaultTheme)
			expect(look).toBe(P.Themes[P.DefaultTheme])
		end)

		it("finds the dominant element: majority, hybrids count for both, ties in element order", function()
			expect(Logic.Dominant(Config, monsters({ "tide" }, { "tide" }, { "ember" }))).toBe("tide")
			expect(Logic.Dominant(Config, monsters({ "ember", "tide" }, { "tide" }))).toBe("tide")
			expect(Logic.Dominant(Config, monsters({ "tide" }, { "ember" }))).toBe(Config.Elements.List[1].id)
			expect(Logic.Dominant(Config, monsters({ "tide" }, { "ember" }, { "spark" }))).toBe(nil)
			expect(Logic.Dominant(Config, {})).toBe(nil)
			expect(Logic.Dominant(Config, "garbage")).toBe(nil)
			expect(Logic.Dominant(Config, { { id = "x" }, false })).toBe(nil)
		end)

		it("keeps every prop valid: shapes, materials, colours, an anchor that is never dropped, a mesh slot", function()
			local bad = {}
			local function checkPiece(where, piece)
				if not SHAPES[piece.shape] then
					table.insert(bad, where .. " shape")
				end
				if not validMaterial(piece.mat) then
					table.insert(bad, where .. " material " .. tostring(piece.mat))
				end
				local c = piece.color
				if not TOKENS[c] and not (type(c) == "string" and string.match(c, "^#%x%x%x%x%x%x$")) then
					table.insert(bad, where .. " colour " .. tostring(c))
				end
			end
			for id, prop in P.Props do
				if prop.mesh ~= "" or prop.texture ~= "" then
					table.insert(bad, id .. " ships a mesh id")
				end
				if prop.pieces[1].small then
					table.insert(bad, id .. " anchor is small")
				end
				for i, piece in prop.pieces do
					checkPiece(id .. "#" .. i, piece)
				end
			end
			for _, fence in P.Fences do
				if fence.cap then
					checkPiece("cap " .. fence.id, fence.cap)
				end
				for _, style in { fence.rail, fence.post } do
					if not validMaterial(style.mat) then
						table.insert(bad, fence.id .. " material " .. style.mat)
					end
				end
			end
			for id, look in P.Themes do
				for _, name in { look.floor, look.rail } do
					if name and not validMaterial(name) then
						table.insert(bad, id .. " material " .. name)
					end
				end
			end
			expect(table.concat(bad, "; ")).toBe("")
		end)

		it("keeps every prop inside the pen's rails and every garden bed inside the garden", function()
			local hx = Config.World.PenSize[1] / 2 - 0.5
			local hz = Config.World.PenSize[2] / 2 - 0.5
			local out = {}
			local function check(id, spot)
				for i, piece in P.Props[id].pieces do
					local x, z = spot[1] + piece.at[1], spot[2] + piece.at[3]
					local sx, sz = piece.size[1] / 2, piece.size[3] / 2
					if math.abs(x) + sx > hx or math.abs(z) + sz > hz then
						table.insert(out, string.format("%s#%d at (%.1f, %.1f)", id, i, x, z))
					end
				end
			end
			for _, up in P.Upgrades do
				check(up.id, up.at)
			end
			for _, look in P.Themes do
				for i, id in look.props do
					check(id, P.ThemeSpots[i])
				end
			end
			for _, id in P.Habitats do
				check(id, P.HabitatSpot)
			end
			expect(table.concat(out, "; ")).toBe("")
			local G = P.Garden
			local maxPlots = Economy.Garden.plots[#Economy.Garden.plots]
			local rows = math.ceil(maxPlots / G.columns)
			local w = (G.columns - 1) * G.spacing[1] + G.bed[1] + G.glow.pad * 2
			local d = (rows - 1) * G.spacing[2] + G.bed[3] + G.glow.pad * 2
			expect(w <= Config.World.GardenSize[1]).toBe(true)
			expect(d <= Config.World.GardenSize[2]).toBe(true)
		end)

		it("stays within the part budget for every theme, tier, capacity, habitat and detail", function()
			local worst = { full = 0, lite = 0, far = 0 }
			local elements = { false }
			for _, e in Config.Elements.List do
				table.insert(elements, e.id)
			end
			for _, theme in Config.Decor.PenThemes do
				for jar = 1, #Economy.JarTiers do
					for cap = Economy.Pens.startCapacity, Economy.Pens.maxCapacity do
						for _, element in elements do
							local pen = {
								theme = theme.id,
								jarTier = jar,
								capacity = cap,
								monsters = if element then monsters({ element }) else {},
							}
							for detail in worst do
								worst[detail] = math.max(worst[detail], Logic.PartCount(Config, Logic.Plan(Config, pen, detail)))
							end
						end
					end
				end
			end
			expect(worst.full <= P.Budget.full).toBe(true)
			expect(worst.lite <= P.Budget.lite).toBe(true)
			expect(worst.far <= P.Budget.far).toBe(true)
			expect(worst.far < worst.full).toBe(true)
		end)

		it("changes only the key of the group that has to be rebuilt", function()
			local base = { theme = "wood", jarTier = 1, capacity = 6, monsters = monsters({ "tide" }) }
			local a = Logic.Plan(Config, base, "full")
			local function diff(change)
				local pen = table.clone(base)
				for k, v in change do
					pen[k] = v
				end
				local b = Logic.Plan(Config, pen, "full")
				local changed = {}
				for _, group in { "fence", "props", "habitat" } do
					if a.keys[group] ~= b.keys[group] then
						table.insert(changed, group)
					end
				end
				return table.concat(changed, ",")
			end
			expect(diff({ capacity = 7 })).toBe("props")
			expect(diff({ jarTier = 3 })).toBe("fence")
			expect(diff({ theme = "candy" })).toBe("fence,props")
			expect(diff({ monsters = monsters({ "ember" }) })).toBe("habitat")
			expect(diff({ monsters = monsters({ "tide" }, { "tide" }) })).toBe("")
		end)

		it("grows crops through seeds, sprouts and grown to ready, and keys the garden by stage", function()
			local grow = Economy.Garden.growSeconds
			local now = 10000
			expect(Logic.CropStage(Config, { flavor = false, readyAt = 0 }, now)).toBe(0)
			expect(Logic.CropStage(Config, { flavor = "sweet", readyAt = now + grow }, now)).toBe(1)
			expect(Logic.CropStage(Config, { flavor = "sweet", readyAt = now + grow * 0.5 }, now)).toBe(2)
			expect(Logic.CropStage(Config, { flavor = "sweet", readyAt = now + grow * 0.2 }, now)).toBe(3)
			expect(Logic.CropStage(Config, { flavor = "sweet", readyAt = now }, now)).toBe(4)
			local garden = { tier = 1, plots = { { flavor = "sweet", readyAt = now + grow }, { flavor = false, readyAt = 0 } } }
			local k1 = Logic.GardenKey(Config, garden, now, "full")
			expect(Logic.GardenKey(Config, garden, now + 5, "full")).toBe(k1)
			expect(Logic.GardenKey(Config, garden, now + grow, "full") ~= k1).toBe(true)
			expect(Logic.GardenKey(Config, garden, now, "far") ~= k1).toBe(true)
			expect(Logic.GardenKey(Config, false, now, "full")).toBe("none")
		end)
	end)

	describe("Pens · replication", function()
		it("publishes each pen's capacity and jar tier and the Feed Garden on the plot", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Ranch", "Plots" } })
			local p = h:Join()
			local plot = h.kernel.State:GlobalRoot("Plots")[1]
			expect(plot.pens[1].capacity).toBe(Economy.Pens.startCapacity)
			expect(plot.pens[1].jarTier).toBe(1)
			expect(#plot.garden.plots).toBe(Economy.Garden.plots[1])
			expect(plot.garden.plots[1].flavor).toBe(false)
			h:System("Currency"):Add(p, "coins", 1e9, "test")
			h:Call(p, "Ranch.Upgrade", { target = "capacity", pen = 1 })
			h:Advance(3)
			expect(h.kernel.State:GlobalRoot("Plots")[1].pens[1].capacity).toBe(Economy.Pens.startCapacity + 1)
			h:Leave(p)
			expect(h.kernel.State:GlobalRoot("Plots")[1].garden).toBe(false)
		end)
	end)

	describe("Pens · client", function()
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

		local function levelTo(h, p, level: number)
			local s = h:Section(p, "Progression")
			local need = -s.xp
			for l = s.level, level - 1 do
				need += Config.Unlocks.XPToNext(l)
			end
			h:System("Progression"):AddXP(p, need, "test")
		end

		local function penOf(c, plotIndex: number, pen: number)
			return c.world.workspace.World.Plots:FindFirstChild("Plot" .. plotIndex).Pens:FindFirstChild("Pen" .. pen)
		end

		local function dressParts(model)
			local list = {}
			local dress = model and model:FindFirstChild("Dress")
			for _, d in if dress then dress:GetDescendants() else {} do
				if d:IsA("BasePart") then
					table.insert(list, d)
				end
			end
			return list
		end

		local function spotsOf(parts)
			local spots = {}
			for _, part in parts do
				local spot = part:GetAttribute("PenSpot")
				if spot then
					spots[spot] = part
				end
			end
			return spots
		end

		local function setPen(h, p, c, fields)
			local pen = h:Section(p, "Ranch").pens[1]
			for k, v in fields do
				pen[k] = v
			end
			h:System("Plots"):Refresh(p)
			c:Advance(3)
		end

		it("dresses the owner's pen as it grows, inside its floor, within budget, rebuilding only on change", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join(9301, "Owner")
			local c = ClientHarness.new(h, p)
			local PensController = c:require(c.clientFolder.Controllers.Pens)
			local index = h:System("Plots"):GetPlot(p)
			local model = penOf(c, index, 1)
			c:Advance(1)

			-- Fresh pen: wood fence, hay nest (bed), the wood theme's sunflowers.
			local dress = model:FindFirstChild("Dress")
			expect(dress ~= nil).toBe(true)
			expect(dress:GetAttribute("FenceTier")).toBe("wood")
			expect(dress:GetAttribute("Theme")).toBe("wood")
			expect(model.RailN.Material.Name).toBe("WoodPlanks")
			expect(model.Floor.Material.Name).toBe("Grass")
			expect(dress:FindFirstChild("hay_nest") ~= nil).toBe(true)
			expect(dress:FindFirstChild("sunflowers") ~= nil).toBe(true)
			expect(dress:FindFirstChild("trough")).toBe(nil)

			-- Bought through the real action: the trough appears (props group only).
			local before = PensController.Stats().builds
			h:System("Currency"):Add(p, "coins", 1e9, "test")
			local ok = c:Request("Ranch.Upgrade", { target = "capacity", pen = 1 })
			expect(ok).toBe(true)
			c:Advance(3)
			expect(dress:FindFirstChild("trough") ~= nil).toBe(true)
			expect(dress.trough:GetAttribute("PenSpot")).toBe("food")
			expect(PensController.Stats().builds).toBe(before + 1)

			-- Nothing visible changed: no rebuild.
			local steady = PensController.Stats().builds
			h:System("Plots"):Refresh(p)
			c:Advance(5)
			expect(PensController.Stats().builds).toBe(steady)

			-- Several levels and themes.
			local budget = P.Budget.full
			for _, case in
				{
					{ jarTier = 2, capacity = 8, theme = "candy", fence = "timber" },
					{ jarTier = 3, capacity = 9, theme = "lantern_garden", fence = "stone" },
					{ jarTier = 4, capacity = 10, theme = "haunted_hollow", fence = "crystal" },
				}
			do
				setPen(h, p, c, { jarTier = case.jarTier, capacity = case.capacity, theme = case.theme })
				expect(dress:GetAttribute("FenceTier")).toBe(case.fence)
				expect(dress:GetAttribute("Theme")).toBe(case.theme)
				local parts = dressParts(model)
				expect(#parts <= budget).toBe(true)
				for _, id in P.Themes[case.theme].props do
					expect(dress:FindFirstChild(id) ~= nil).toBe(true)
				end
			end
			expect(model.RailN.Material.Name).toBe("Glass")
			expect(model.Floor.Material.Name).toBe("Mud")
			expect(#model.Dress:GetChildren() > 0).toBe(true)
			local caps = 0
			for _, part in dressParts(model) do
				if string.sub(part.Name, 1, 4) == "Cap_" then
					caps += 1
				end
			end
			expect(caps).toBe(4)

			-- Every spot at max capacity, each inside the pen floor.
			local spots = spotsOf(dressParts(model))
			for _, kind in { "food", "water", "shelter", "bed" } do
				expect(spots[kind] ~= nil).toBe(true)
			end
			local floor = model.Floor
			for _, part in dressParts(model) do
				if part:GetAttribute("PenSpot") then
					local lp = floor.CFrame:PointToObjectSpace(part.Position)
					expect(math.abs(lp.X) <= floor.Size.X / 2 and math.abs(lp.Z) <= floor.Size.Z / 2).toBe(true)
				end
			end
			expectClean(c)
		end)

		it("shows a habitat for the pen's dominant element", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join(9302, "Keeper")
			local c = ClientHarness.new(h, p)
			local Monsters = h:System("Monsters")
			Monsters:Create(p, { line = "cindlet", rarity = 1, traits = { 3, 4 }, hidden = 5, variant = 0 }, "hatch", true)
			c:Advance(3)
			local index = h:System("Plots"):GetPlot(p)
			local pen = c:Store("global.Plots")[index].pens[1]
			local element = Logic.Dominant(Config, pen.monsters)
			expect(element ~= nil).toBe(true)
			local dress = penOf(c, index, 1).Dress
			expect(dress:GetAttribute("Habitat")).toBe(element)
			local anchor = dress:FindFirstChild(P.Habitats[element])
			expect(anchor ~= nil).toBe(true)
			expect(anchor:GetAttribute("Habitat")).toBe(element)
			expect(anchor:GetAttribute("PenSpot")).toBe(P.Props[P.Habitats[element]].spot)
			expectClean(c)
		end)

		it("grows the Feed Garden's crops with its state and glows when ready; harvest still works", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join(9303, "Gardener")
			local c = ClientHarness.new(h, p)
			levelTo(h, p, 5)
			c:Advance(2)
			local PensController = c:require(c.clientFolder.Controllers.Pens)
			local index = h:System("Plots"):GetPlot(p)
			local garden = c.world.workspace.World.Plots:FindFirstChild("Plot" .. index):FindFirstChild("Garden")
			expect(garden ~= nil).toBe(true)
			expect(garden:FindFirstChild("GardenFrame") ~= nil).toBe(true)
			expect(garden.Bed1:GetAttribute("CropStage")).toBe(0)
			expect(garden:FindFirstChild("Bed" .. (Economy.Garden.plots[1] + 1))).toBe(nil)

			expect(c:Request("Ranch.Plant", { plot = 1, flavor = "sweet" })).toBe(true)
			c:Advance(1)
			expect(garden.Bed1:GetAttribute("CropStage")).toBe(1)
			expect(garden.Bed1:GetAttribute("Flavor")).toBe("sweet")
			expect(garden:FindFirstChild("Crop1_1") ~= nil).toBe(true)
			expect(garden:FindFirstChild("Ready1")).toBe(nil)

			-- Nearly grown, then ready: stages move on the controller's timer alone.
			local builds = PensController.Stats().gardenBuilds
			c:Advance(4)
			expect(PensController.Stats().gardenBuilds).toBe(builds)
			h:Section(p, "Ranch").garden.plots[1].readyAt = h.adapters.Clock.Unix() + 3
			h.kernel.State:Dirty(p, { "profile", "Ranch", "garden" })
			c:Advance(1)
			expect(garden.Bed1:GetAttribute("CropStage")).toBe(3)
			c:Advance(5)
			expect(garden.Bed1:GetAttribute("CropStage")).toBe(4)
			expect(garden:FindFirstChild("Ready1") ~= nil).toBe(true)
			expect(garden:FindFirstChild("Fruit1_1") ~= nil).toBe(true)
			local parts = 0
			for _, d in garden:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
				end
			end
			expect(parts <= P.Budget.garden).toBe(true)

			expect(c:Request("Ranch.Harvest", { plot = 1 })).toBe(true)
			c:Advance(1)
			expect(garden.Bed1:GetAttribute("CropStage")).toBe(0)
			expect(garden:FindFirstChild("Ready1")).toBe(nil)
			expectClean(c)
		end)

		it("shows the owner's upgrades to a visitor, lighter at a distance and in low graphics", function()
			local h = TestKernel.new({ systems = allSystems() })
			local owner = h:Join(9304, "Owner")
			local visitor = h:Join(9305, "Visitor")
			local co = ClientHarness.new(h, owner)
			local cv = ClientHarness.new(h, visitor)
			local index = h:System("Plots"):GetPlot(owner)
			local pen = h:Section(owner, "Ranch").pens[1]
			pen.capacity, pen.jarTier, pen.theme = 10, 3, "blossom_glade"
			h:System("Plots"):Refresh(owner)
			co:Advance(3)

			-- The visitor's camera starts far from every plot: hero props only.
			local model = penOf(cv, index, 1)
			local dress = model.Dress
			expect(dress:GetAttribute("FenceTier")).toBe("stone")
			expect(dress:FindFirstChild("pond") ~= nil).toBe(true)
			expect(dress:FindFirstChild("blossom_tree")).toBe(nil)
			expect(#dressParts(model) <= P.Budget.far).toBe(true)
			local far = #dressParts(model)

			-- Walk up to the plot: full detail on the next check.
			local c = Config.World.Plots[index].center
			cv.world.workspace.CurrentCamera.CFrame = CFrame.new(c[1], 30, c[3] + 20)
			cv:Advance(P.CheckSeconds + 0.5)
			expect(dress:FindFirstChild("blossom_tree") ~= nil).toBe(true)
			expect(#dressParts(model) > far).toBe(true)
			expect(#dressParts(model) <= P.Budget.full).toBe(true)

			-- Low graphics: back to far detail for other players' pens.
			expect(cv:Request("Settings.Set", { key = "lowGraphics", value = true })).toBe(true)
			cv:Advance(1)
			expect(dress:FindFirstChild("blossom_tree")).toBe(nil)
			expect(#dressParts(model) <= P.Budget.far).toBe(true)

			-- The owner leaves: the pen goes back to the plain locked look, nothing left behind.
			h:Leave(owner)
			cv:Advance(1)
			expect(model:FindFirstChild("Dress")).toBe(nil)
			expect(model.RailN.Material.Name).toBe("SmoothPlastic")
			expectClean(cv)
			expectClean(co)
		end)
	end)
end
