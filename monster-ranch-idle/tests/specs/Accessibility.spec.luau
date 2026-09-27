--[[
	Accessibility (R2-A11Y): three Settings toggles, saved server-side and applied live (no
	rejoin) -
	  · colorBlind: Widgets.RarityChip / ElementChip and MonsterIcon.card add a letter / glyph
	    next to the colour (Config.Rarities.mark, Config.Elements.glyph, Theme.ColorBlind).
	  · textSize ("normal" / "large"): Theme.TextScale, rescaled live on every already-built
	    screen too (Theme.RescaleText via the Broadcasts controller); still fits a 568×320 phone.
	  · reducedMotion: UI/Anim.enabled and CameraDirector:ReducedMotion(), independently of
	    Low graphics.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")

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
		local problems = c:Problems({ "Infinite yield possible" })
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	local function boot()
		local h = TestKernel.new({ systems = allSystems() })
		local p = h:Join()
		local c = ClientHarness.new(h, p)
		c:Advance(1)
		return h, p, c
	end

	describe("Settings: colour-blind, text size and reduced motion", function()
		it("keeps the stock palette for everyone and swaps the clashing colours only in colour-blind mode", function()
			local _h, _p, c = boot()
			local Theme = c:require(c.clientFolder.UI.Theme)
			local function hexOf(color): string
				return string.format("#%02X%02X%02X", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
			end
			expect(Config.Rarities.List[4].color).toBe("#A259E0")
			expect(Config.Elements.ById.stone.color).toBe("#A68B70")
			expect(Config.Elements.ById.light.color).toBe("#F2C94C")
			Theme.ColorBlind = false
			expect(hexOf(Theme.Rarity(4))).toBe("#A259E0")
			expect(hexOf(Theme.Element("light"))).toBe("#F2C94C")
			Theme.ColorBlind = true
			expect(hexOf(Theme.Rarity(4))).toBe(Config.Rarities.List[4].cbColor)
			expect(hexOf(Theme.Element("stone"))).toBe(Config.Elements.ById.stone.cbColor)
			expect(hexOf(Theme.Element("light"))).toBe(Config.Elements.ById.light.cbColor)
			expect(hexOf(Theme.Element("ember"))).toBe(Config.Elements.ById.ember.color) -- no override
			Theme.ColorBlind = false
		end)

		it("defaults every one off, saves each, and survives a rejoin", function()
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			expect(h:Section(player, "Settings").colorBlind).toBe(false)
			expect(h:Section(player, "Settings").textSize).toBe("normal")
			expect(h:Section(player, "Settings").reducedMotion).toBe(false)

			local c = ClientHarness.new(h, player)
			c:Advance(1)
			expect(c:Request("Settings.Set", { key = "colorBlind", value = true })).toBe(true)
			expect(c:Request("Settings.SetTextSize", { textSize = "large" })).toBe(true)
			expect(c:Request("Settings.Set", { key = "reducedMotion", value = true })).toBe(true)
			c:Advance(0.5)
			expect(c:Store("profile.Settings").colorBlind).toBe(true)
			expect(c:Store("profile.Settings").textSize).toBe("large")
			expect(c:Store("profile.Settings").reducedMotion).toBe(true)

			h:Leave(player)
			local again = h:Join(player.UserId, player.Name)
			expect(h:Section(again, "Settings").colorBlind).toBe(true)
			expect(h:Section(again, "Settings").textSize).toBe("large")
			expect(h:Section(again, "Settings").reducedMotion).toBe(true)
			local c2 = ClientHarness.new(h, again)
			c2:Advance(1)
			expect(c2:Store("profile.Settings").colorBlind).toBe(true)
			expectClean(c2)
		end)

		it("rejects a bad textSize and a bad Settings.Set key", function()
			local _, _, c = boot()
			expect(c:Request("Settings.SetTextSize", { textSize = "huge" })).toBe(false)
			expect(c:Request("Settings.Set", { key = "notAThing", value = true })).toBe(false)
			expectClean(c)
		end)
	end)

	describe("Colour-blind mode: rarity marks and element glyphs on a real screen", function()
		local function withMonster(rarity: number)
			local h, player, c = boot()
			local line = Config.Species.Lines[1] -- cindlet: ember
			local record = h:System("Monsters")
				:Create(player, { line = line.id, rarity = rarity, stage = 3, form = line.forms[3][1].id }, "test", true)
			h:Step()
			return h, player, c, record
		end

		it("adds the rarity letter and the element glyph to MonsterDetail once colour-blind mode is on", function()
			local _, _, c, record = withMonster(3) -- Rare -> mark "R"
			local root = c:Open("MonsterDetail", { id = record.id })
			c:Advance(0.5)
			expect(table.find(c:Texts(root), "R")).toBe(nil)
			expect(table.find(c:Texts(root), Config.Elements.ById.ember.glyph)).toBe(nil)
			c:Close("MonsterDetail")

			expect(c:Request("Settings.Set", { key = "colorBlind", value = true })).toBe(true)
			c:Advance(0.5)
			root = c:Open("MonsterDetail", { id = record.id })
			c:Advance(0.5)
			expect(table.find(c:Texts(root), "R") ~= nil).toBe(true)
			expect(table.find(c:Texts(root), Config.Elements.ById.ember.glyph) ~= nil).toBe(true)
			expectClean(c)
		end)
	end)

	describe("Text size: large text scales live and keeps the phone fit", function()
		it("resizes an already-open screen's text live, without reopening it", function()
			local _, _, c = boot()
			local root = c:Open("Settings")
			c:Advance(0.5)
			local label
			for _, d in c:Descendants(root) do
				if d:IsA("TextLabel") and d.Text == "Music" then
					label = d
					break
				end
			end
			expect(label ~= nil).toBe(true)
			local before = label.TextSize
			expect(c:Request("Settings.SetTextSize", { textSize = "large" })).toBe(true)
			c:Advance(0.3)
			expect(label.TextSize).toBe(before * 1.15)
			expectClean(c)
		end)

		it("fits a 568×320 phone with large text on the main screens", function()
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			local viewport = t.Roblox.Vector2.new(568, 320)
			local c = ClientHarness.new(h, player, { viewport = viewport })
			c:Advance(1)
			expect(c:Request("Settings.SetTextSize", { textSize = "large" })).toBe(true)
			c:Advance(0.5)
			local overflow = {}
			for _, name in { "Settings", "Ranch", "Monsters" } do
				local root = c:Open(name)
				c:Advance(0.5)
				for _, gui in { root, table.unpack(root:GetChildren()) } do
					if gui:IsA("GuiObject") and gui.Visible then
						local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
						if pos.X < -1 or pos.Y < -1 or pos.X + size.X > viewport.X + 1 or pos.Y + size.Y > viewport.Y + 1 then
							table.insert(
								overflow,
								string.format("%s/%s at (%d,%d) size %dx%d", name, gui.Name, pos.X, pos.Y, size.X, size.Y)
							)
						end
					end
				end
				c:Close(name)
			end
			expectClean(c)
			if #overflow > 0 then
				error("off-screen on 568x320 with large text:\n  " .. table.concat(overflow, "\n  "))
			end
		end)
	end)

	describe("Reduced motion: stops camera shake/kicks independently of Low graphics", function()
		it("keeps a huge reward's FOV kick off once Settings.reducedMotion is on", function()
			local _, _, c = boot()
			local kit = c.kernel:GetController("Celebrate")
			local camera = c.world.workspace.CurrentCamera
			local fov = camera.FieldOfView
			expect(c:Store("profile.Settings").lowGraphics).toBe(false)
			expect(c:Request("Settings.Set", { key = "reducedMotion", value = true })).toBe(true)
			c:Advance(0.3)
			local Anim = c:require(c.clientFolder.UI.Anim)
			expect(Anim.enabled).toBe(false)
			for _ = 1, 4 do
				kit:Reward({ { kind = "coins", amount = 1e9 }, { kind = "gems", amount = 1000 } })
			end
			c:Advance(0.5)
			expect(camera.FieldOfView).toBe(fov) -- no kick with reduced motion, even though graphics stayed High
			expectClean(c)
		end)

		it("feeds CameraDirector:ReducedMotion(), independently of Low graphics", function()
			local _, _, c = boot()
			local director = c.kernel:GetController("CameraDirector")
			expect(director:ReducedMotion()).toBe(false)
			expect(c:Request("Settings.Set", { key = "reducedMotion", value = true })).toBe(true)
			c:Advance(0.3)
			expect(director:ReducedMotion()).toBe(true)
			expect(c:Store("profile.Settings").lowGraphics).toBe(false) -- Low graphics itself never turned on
			expectClean(c)
		end)
	end)
end
