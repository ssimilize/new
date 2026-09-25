--[[
	GamepadClient (update 3.2): controller support played through the real client
	(ClientHarness). The harness stands in for the engine's pad handling: c:UseGamepad(on)
	plugs a pad in (or goes back to touch), c:Press(key) runs a key through
	ContextActionService, GUI navigation (A presses the selection, the D-pad moves it) and
	UserInputService, c:Stick(x, y) moves the left stick, c:Selected() reads the cursor.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local RobloxMock = require("../runtime/RobloxMock")
	local Config = t.Shared("Config")
	local Enum = t.Roblox.Enum

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
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function boot(options)
		local h = TestKernel.new({ systems = allSystems(), startTime = options and options.startTime })
		local p = h:Join()
		local c = ClientHarness.new(h, p)
		c:Advance(1)
		return h, p, c
	end

	-- A max-level player with currencies and one monster per species line.
	local function veteran(h, p)
		h:System("Progression"):AddXP(p, 1e9, "test")
		local currency = h:System("Currency")
		for key, amount in { coins = 1e9, gems = 1e5, stardust = 1e5, treats = 1e4, friendship = 1e4 } do
			currency:Add(p, key, amount, "test")
		end
		local ids = {}
		for i, line in Config.Species.Lines do
			local stage = (i % 3) + 1
			local spec = { line = line.id, rarity = line.rarity or 2, stage = stage }
			if stage == 3 then
				spec.form = line.forms[3][1].id
			end
			table.insert(ids, h:System("Monsters"):Create(p, spec, "test", true).id)
		end
		h:Step()
		return ids
	end

	local function guiService(c)
		return c.world.game:GetService("GuiService")
	end

	local function describeGui(gui): string
		return if gui then gui:GetFullName() else "nothing"
	end

	-- The cursor is on a shown, selectable button inside root that something listens to.
	local function expectCursorIn(c, root, label: string)
		local selected = c:Selected()
		local ok = selected ~= nil
			and selected:IsDescendantOf(root)
			and selected:IsA("GuiButton")
			and selected.Selectable
			and c:IsShown(selected)
			and RobloxMock.hasConnections(selected, "Activated")
		if not ok then
			error(string.format("%s: the cursor is on %s", label, describeGui(selected)), 2)
		end
	end

	local function legendText(c): string?
		local legend = c.kernel.UI.Overlay:FindFirstChild("GamepadLegend")
		return if legend and legend.Visible then legend.Keys.Text else nil
	end

	-- Moves the cursor with the D-pad until it rests on target (proves it can be reached).
	local function navigateTo(c, target)
		for _ = 1, 80 do
			if c:Selected() == target then
				return
			end
			c:Press("DPadDown")
		end
		error("could not reach " .. describeGui(target) .. " with the D-pad; stuck on " .. describeGui(c:Selected()), 2)
	end

	local function scopeProps(root)
		return {
			root.SelectionGroup,
			root.SelectionBehaviorUp,
			root.SelectionBehaviorDown,
			root.SelectionBehaviorLeft,
			root.SelectionBehaviorRight,
		}
	end

	describe("Gamepad client", function()
		it("stays dormant with touch: no selection, cursor, bindings or scope changes", function()
			local _, _, c = boot()
			local gs = guiService(c)
			local nav, auto = gs.GuiNavigationEnabled, gs.AutoSelectGuiEnabled
			local root = c:Open("Monsters")
			c:Advance(0.5)
			local before = scopeProps(root)
			c:Close("Monsters")
			c:Open("Monsters")
			c:Advance(0.5)
			expect(c:Selected()).toBe(nil)
			expect(c.playerGui.SelectionImageObject).toBe(nil)
			expect(next(c.world.input.actions)).toBe(nil)
			expect(scopeProps(root)).toEqual(before)
			expect(root.SelectionGroup).toBe(false)
			expect(gs.GuiNavigationEnabled).toBe(nav)
			expect(gs.AutoSelectGuiEnabled).toBe(auto)
			expect(legendText(c)).toBe(nil)
			c:Close("Monsters")
			expect(c.kernel.Router:Current()).toBe(nil)
			expectClean(c)
		end)

		it("opens Monsters with Y, keeps the cursor inside, and B closes it and hands selection back", function()
			local _, _, c = boot()
			c:UseGamepad(true)
			expect(legendText(c)).toBe("Ⓨ Monsters")
			expect(c:Selected()).toBe(nil) -- walking: A still jumps
			expect(c.playerGui.SelectionImageObject ~= nil).toBe(true)

			-- The player browsed the HUD with the engine's Select button and rests on Shop.
			local shop = c.kernel.UI.Hud:FindFirstChild("Shop", true)
			guiService(c).SelectedObject = shop
			c:Press("ButtonY")
			expect(c.kernel.Router:Current()).toBe("Monsters")
			local root = c:Screen("Monsters")
			expectCursorIn(c, root, "Monsters")
			expect(root.SelectionGroup).toBe(true)
			expect(root.SelectionBehaviorDown).toBe(Enum.SelectionBehavior.Stop)
			expect(legendText(c) ~= "Ⓨ Monsters").toBe(true)
			-- Y does nothing more while a screen is open.
			c:Press("ButtonY")
			expect(c.kernel.Router:Current()).toBe("Monsters")

			c:Press("ButtonB")
			expect(c.kernel.Router:Current()).toBe(nil)
			expect(c:Selected()).toBe(shop)
			expect(root.SelectionGroup).toBe(false)
			expect(legendText(c)).toBe("Ⓨ Monsters")

			-- From no selection, back to no selection.
			guiService(c).SelectedObject = nil
			c:Press("ButtonY")
			expectCursorIn(c, root, "Monsters again")
			c:Press("ButtonB")
			expect(c:Selected()).toBe(nil)
			-- B with nothing open is not sunk: no action claims it.
			c:Press("ButtonB")
			expect(c.kernel.Router:Current()).toBe(nil)
			expectClean(c)
		end)

		it("puts the cursor on a shown, live control inside every screen", function()
			local h, p, c = boot()
			local ids = veteran(h, p)
			c:Advance(1)
			c:UseGamepad(true)
			local manifest = c:require(c.clientFolder.Manifest)
			for _, name in manifest.Screens do
				local params = if name == "MonsterDetail" then { id = ids[3] } else nil
				local root = c:Open(name, params)
				c:Advance(0.5)
				expect(root ~= nil).toBe(true)
				expectCursorIn(c, root, name)
				c:Press("ButtonB")
				c:Advance(0.3)
				if c.kernel.Router:IsOpen(name) then
					error(name .. " did not close with B")
				end
				local problems = c:Problems()
				if #problems > 0 then
					error(name .. ":\n" .. table.concat(problems, "\n\n"))
				end
			end
		end)

		it("keeps D-pad movement inside the open screen", function()
			local h, p, c = boot()
			veteran(h, p)
			c:Advance(1)
			c:UseGamepad(true)
			-- Every value the selection takes, including between frames: the per-frame focus
			-- repair must not be what keeps the cursor in (the SelectionGroup scope must).
			local gs = guiService(c)
			local seen = {}
			gs:GetPropertyChangedSignal("SelectedObject"):Connect(function()
				table.insert(seen, gs.SelectedObject)
			end)
			for _, name in { "Store", "Quests", "EggShop" } do
				local root = c:Open(name)
				c:Advance(0.5)
				table.clear(seen)
				local visited = {}
				for _, key in { "DPadDown", "DPadRight", "DPadUp", "DPadLeft" } do
					for i = 1, 40 do
						c:Press(key)
						for _, gui in seen do
							if not (gui and gui:IsDescendantOf(root)) then
								error(string.format("%s: %s #%d left the screen for %s", name, key, i, describeGui(gui)))
							end
							visited[gui] = true
						end
						table.clear(seen)
					end
				end
				local count = 0
				for _ in visited do
					count += 1
				end
				expect(count > 3).toBe(true) -- the cursor really moved
				c:Close(name)
			end
			expectClean(c)
		end)

		it("changes tabs with LB and RB", function()
			local h, p, c = boot()
			veteran(h, p)
			c:Advance(1)
			c:UseGamepad(true)
			local Widgets = c:require(c.clientFolder.UI.Components.Widgets)
			for _, name in { "Store", "Quests" } do
				local root = c:Open(name)
				c:Advance(0.5)
				local row = Widgets.FindTabs(root)
				expect(row ~= nil).toBe(true)
				expect(legendText(c)).toBe("Ⓐ Select · Ⓑ Close · LB/RB Tabs")
				local first = row.Selected
				c:Press("ButtonR1")
				c:Advance(0.3)
				expect(row.Selected ~= first).toBe(true)
				expectCursorIn(c, root, name .. " after RB")
				c:Press("ButtonL1")
				c:Advance(0.3)
				expect(row.Selected).toBe(first)
				-- On a tab button, the cursor follows the tab.
				local tabButton = row.Root:GetChildren()
				local onTab
				for _, b in tabButton do
					if b:IsA("GuiButton") then
						onTab = b
						break
					end
				end
				guiService(c).SelectedObject = onTab
				c:Press("ButtonR1")
				expect(c:Selected() ~= onTab and c:Selected():IsDescendantOf(row.Root)).toBe(true)
				c:Close(name)
			end
			expectClean(c)
		end)

		it("scopes a dialog over a screen and hands the selection back when it closes", function()
			local h, p, c = boot()
			veteran(h, p)
			c:Advance(1)
			c:UseGamepad(true)
			local root = c:Open("Monsters")
			c:Advance(0.5)
			c:Press("DPadDown")
			local before = c:Selected()
			expectCursorIn(c, root, "Monsters")
			local Dialog = c:require(c.clientFolder.UI.Screens.Parts.Dialog)
			local dialog
			c.world:Run(function()
				dialog = Dialog.confirm(c.kernel.UI.Top, { Title = "Sure?", Text = "A test question." })
			end)
			c:Settle()
			expectCursorIn(c, dialog.Root, "Dialog")
			expect(c:HasText("Cancel", c:Selected())).toBe(true) -- the safe choice first
			expect(root.SelectionGroup).toBe(false) -- the scope moved to the dialog
			for _ = 1, 10 do
				c:Press("DPadRight")
				expect(c:Selected():IsDescendantOf(dialog.Root)).toBe(true)
			end
			c:Press("ButtonB")
			expect(dialog.IsOpen()).toBe(false)
			expect(c.kernel.Router:Current()).toBe("Monsters") -- B closed only the dialog
			expect(c:Selected()).toBe(before)
			expect(root.SelectionGroup).toBe(true)
			expectClean(c)
		end)

		it("scopes WelcomeBack when the pad is picked up while it is already open", function()
			local _, _, c = boot()
			local root = c:Open("WelcomeBack")
			c:Advance(0.5)
			expect(c:Selected()).toBe(nil)
			c:UseGamepad(true)
			expect(root.SelectionGroup).toBe(true)
			expectCursorIn(c, root, "WelcomeBack")
			c:Press("ButtonB")
			expect(c.kernel.Router:IsOpen("WelcomeBack")).toBe(false)
			expect(c:Selected()).toBe(nil)
			expectClean(c)
		end)

		it("switching back to touch restores everything it changed", function()
			local h, p, c = boot()
			veteran(h, p)
			c:Advance(1)
			local root = c:Open("Store")
			c:Advance(0.5)
			local before = scopeProps(root)
			c:UseGamepad(true)
			expectCursorIn(c, root, "Store")
			expect(scopeProps(root) ~= before and root.SelectionGroup).toBe(true)
			c:UseGamepad(false)
			expect(c:Selected()).toBe(nil)
			expect(scopeProps(root)).toEqual(before)
			expect(c.playerGui.SelectionImageObject).toBe(nil)
			expect(next(c.world.input.actions)).toBe(nil)
			expect(legendText(c)).toBe(nil)
			-- A keyboard key also counts as leaving pad mode.
			c:UseGamepad(true)
			expect(root.SelectionGroup).toBe(true)
			c:Press("E")
			expect(root.SelectionGroup).toBe(false)
			expect(c:Selected()).toBe(nil)
			expectClean(c)
		end)
	end)

	describe("Gamepad minigames", function()
		local LAUNCH = Config.Regions.ById.dunes.opensAt

		-- Runs one race; `press(i)` presses the keys for step i. Returns the server section.
		local function race(h, p, c, m, press)
			local screen = c:Open("Racing")
			c:Advance(0.5)
			c:Click(screen:FindFirstChild("PickRacer", true))
			c:Advance(0.5)
			local cell = c:Screen("Monsters"):FindFirstChild(m.id, true)
			c:Click(cell:FindFirstChild("Tap"))
			c:Advance(1)
			expect(screen:FindFirstChild("Track", true) ~= nil).toBe(true)
			for i = 1, 200 do
				if screen:FindFirstChild("RaceResult", true) then
					break
				end
				press(i)
				c:Advance(0.45, 0.05)
			end
			expect(screen:FindFirstChild("RaceResult", true) ~= nil).toBe(true)
			expect(c:HasText("place", screen)).toBe(true)
			return h:Section(p, "Racing")
		end

		local function keysOf(tbl): { string }
			local keys = {}
			for k in tbl do
				table.insert(keys, tostring(k))
			end
			table.sort(keys)
			return keys
		end

		it("picks a racer through Monsters pick mode with the pad and races with pad Jump and Boost", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = LAUNCH + 3600 })
			local p = h:Join()
			levelTo(h, p, 16)
			local m = h:System("Monsters"):Create(p, { line = "zappip", rarity = 5, stage = 3 }, "test", true)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			c:UseGamepad(true)
			local screen = c:Open("Racing")
			c:Advance(0.5)
			expectCursorIn(c, screen, "Racing lobby")

			-- Pick mode round trip: A on "Pick a racer", B backs out to Racing.
			local pickButton = screen:FindFirstChild("PickRacer", true)
			navigateTo(c, pickButton)
			c:Press("ButtonA")
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Monsters")
			expectCursorIn(c, c:Screen("Monsters"), "Monsters pick mode")
			c:Press("ButtonB")
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Racing")
			expectCursorIn(c, screen, "Racing after backing out of pick mode")

			-- And for real: pick the racer with A.
			navigateTo(c, screen:FindFirstChild("PickRacer", true))
			c:Press("ButtonA")
			c:Advance(0.5)
			local monsters = c:Screen("Monsters")
			navigateTo(c, monsters:FindFirstChild(m.id, true):FindFirstChild("Tap"))
			c:Press("ButtonA")
			c:Advance(1)
			expect(c.kernel.Router:Current()).toBe("Racing")
			expect(screen:FindFirstChild("Track", true) ~= nil).toBe(true)
			-- While racing there is no cursor, so A jumps instead of pressing a button.
			expect(c:Selected()).toBe(nil)
			expect(legendText(c)).toBe("Ⓐ Jump · RT Boost · Ⓑ Close")
			for i = 1, 200 do
				if screen:FindFirstChild("RaceResult", true) then
					break
				end
				if i % 2 == 0 then
					c:Press("ButtonA")
				end
				if i % 5 == 0 then
					c:Press("ButtonR2")
				end
				expect(c:Selected()).toBe(nil)
				c:Advance(0.45, 0.05)
			end
			expect(screen:FindFirstChild("RaceResult", true) ~= nil).toBe(true)
			expect(c:HasText("place", screen)).toBe(true)
			local padSection = h:Section(p, "Racing")
			expect(padSection.races).toBe(1)
			-- The result screen gets the cursor back.
			c:Advance(0.3)
			expectCursorIn(c, screen, "Racing result")
			c:Close("Racing")

			-- The same race on a keyboard gives the same result shape.
			local p2 = h:Join()
			levelTo(h, p2, 16)
			local m2 = h:System("Monsters"):Create(p2, { line = "zappip", rarity = 5, stage = 3 }, "test", true)
			local c2 = ClientHarness.new(h, p2)
			c2:Advance(1)
			local keySection = race(h, p2, c2, m2, function(i)
				if i % 2 == 0 then
					c2:Press("Space")
				end
				if i % 5 == 0 then
					c2:Press("LeftShift")
				end
			end)
			expect(keySection.races).toBe(1)
			expect(keysOf(padSection)).toEqual(keysOf(keySection))
			expectClean(c)
			expectClean(c2)
		end)

		it("surfs with the D-pad and the left stick, one lane per push", function()
			local SPLASH = Config.Events.ById.summersplash
			local h = TestKernel.new({ systems = allSystems(), startTime = SPLASH.startsAt + 3600 })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			c:UseGamepad(true)
			local screen = c:Open("Surf")
			c:Advance(0.5)
			navigateTo(c, screen:FindFirstChild("StartSurf", true))
			c:Press("ButtonA")
			c:Advance(0.2)
			expect(screen:FindFirstChild("Waves", true) ~= nil).toBe(true)
			expect(c:Selected()).toBe(nil)
			local surfer = screen:FindFirstChild("Surfer", true)
			local function x()
				c:Advance(0.1)
				return surfer.Position.X.Offset
			end
			local start = x()
			c:Press("DPadRight")
			local right = x()
			expect(right > start).toBe(true)
			c:Press("DPadLeft")
			expect(x()).toBe(start)
			-- Stick: one lane per push, re-armed near the centre.
			c:Stick(-0.9, 0)
			local left = x()
			expect(left < start).toBe(true)
			c:Stick(0.9, 0) -- not re-armed: the stick never came back inside the centre
			c:Stick(0.2, 0)
			c:Stick(0.95, 0)
			expect(x()).toBe(start)
			c:Stick(1, 0) -- held: no second lane
			expect(x()).toBe(start)
			-- Weave with the D-pad for the rest of the run.
			for i = 1, 60 do
				if screen:FindFirstChild("SurfResult", true) then
					break
				end
				c:Press(if i % 3 == 0 then "DPadLeft" else "DPadRight")
				c:Advance(0.8, 0.1)
			end
			c:Advance(3, 0.1)
			expect(screen:FindFirstChild("SurfResult", true) ~= nil).toBe(true)
			expect(h:Section(p, "Surf").runs).toBe(1)
			c:Advance(0.3)
			expectCursorIn(c, screen, "Surf result")
			c:Close("Surf")
			expectClean(c)
		end)
	end)
end
