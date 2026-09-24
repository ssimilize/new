--[[
	Client: boots the real client (Main.client.luau, every controller and screen in the
	client Manifest) inside RobloxMock against the full server, and drives it the way a
	player would. Any runtime error, Roblox API misuse (unknown property, wrong type,
	read-only write, bad enum) or remote-shape problem fails the test.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function boot(options)
		local h = TestKernel.new({ systems = allSystems() })
		local player = h:Join()
		local c = ClientHarness.new(h, player, options)
		c:Advance(1)
		return h, player, c
	end

	-- A max-level player with every currency and one monster of every species line, so
	-- every screen shows its unlocked, populated state.
	local function veteran(h, player)
		local Config = t.Shared("Config")
		h:System("Progression"):AddXP(player, 1e9, "test")
		local currency = h:System("Currency")
		for key, amount in { coins = 1e9, gems = 1e5, stardust = 1e5, treats = 1e4, friendship = 1e4 } do
			currency:Add(player, key, amount, "test")
		end
		for flavor in Config.Food.ById or {} do
			currency:Add(player, "food." .. flavor, 100, "test")
		end
		local ids = {}
		for i, line in Config.Species.Lines do
			local stage = (i % 3) + 1
			local spec = { line = line.id, rarity = line.rarity or 2, stage = stage }
			if stage == 3 then
				local adults = line.forms[3]
				spec.form = adults[1].id
			end
			local record = h:System("Monsters"):Create(player, spec, "test", true)
			table.insert(ids, record.id)
		end
		h:System("Eggs"):Add(player, "meadow", "test", 3)
		h:Step()
		return ids
	end

	local function expectClean(c)
		local problems = c:Problems()
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	describe("RobloxMock", function()
		local function world()
			local h = TestKernel.new({ systems = {} })
			local c = ClientHarness.new(h, h:Join(), { noBoot = true })
			return c.globals, c
		end

		it("rejects the API mistakes Roblox rejects", function()
			local g = world()
			local frame = g.Instance.new("Frame")
			local function fails(fn, pattern)
				local ok, err = pcall(fn)
				expect(ok).toBe(false)
				if pattern and not string.find(tostring(err), pattern, 1, true) then
					error("expected error containing " .. pattern .. ", got " .. tostring(err))
				end
			end
			fails(function()
				frame.NotAProperty = 1
			end, "not a valid member")
			fails(function()
				return frame.NotAProperty
			end, "not a valid member")
			fails(function()
				frame.Size = g.Vector2.new(1, 1)
			end, "UDim2 expected")
			fails(function()
				frame.Visible = nil
			end, "boolean expected")
			fails(function()
				frame.AbsoluteSize = g.Vector2.new(1, 1)
			end, "read only")
			fails(function()
				frame.AutomaticSize = g.Enum.Font.GothamBold
			end, "Enum.AutomaticSize")
			fails(function()
				g.Instance.new("NotAClass")
			end, "Unable to create")
			fails(function()
				g.Instance.new("Workspace")
			end, "Unable to create")
			fails(function()
				frame:SetAttribute("bad", {})
			end, "not a supported attribute type")
			fails(function()
				frame.Parent = frame
			end, "own ancestor")
			frame:Destroy()
			fails(function()
				frame.Parent = g.workspace
			end, "locked")
			fails(function()
				g.game:GetService("TweenService"):Create(g.Instance.new("Frame"), g.TweenInfo.new(1), { Visible = "yes" })
			end, "type mismatch")
			-- Valid code passes: enum by name, UDim2 maths, attributes.
			local ok = g.Instance.new("TextLabel")
			ok.TextXAlignment = "Left"
			ok.Size = g.UDim2.fromOffset(10, 10) + g.UDim2.fromScale(1, 0)
			ok:SetAttribute("count", 3)
			expect(ok.TextXAlignment).toBe(g.Enum.TextXAlignment.Left)
			expect(ok:GetAttribute("count")).toBe(3)
		end)

		it("runs task timers and signals on the virtual clock", function()
			local g, c = world()
			local log = {}
			c.world:Run(function()
				g.task.delay(2, function()
					table.insert(log, "delay")
				end)
				g.task.spawn(function()
					g.task.wait(1)
					table.insert(log, "wait")
				end)
			end)
			c:Advance(0.5)
			expect(#log).toBe(0)
			c:Advance(1)
			expect(log).toEqual({ "wait" })
			c:Advance(1)
			expect(log).toEqual({ "wait", "delay" })
		end)

		it("reports errors thrown in game threads", function()
			local g, c = world()
			local button = g.Instance.new("TextButton")
			button.Activated:Connect(function()
				error("boom")
			end)
			c:Click(button)
			expect(#c.world.errors).toBe(1)
			expect(string.find(c.world.errors[1], "boom", 1, true) ~= nil).toBe(true)
		end)
	end)

	describe("Client", function()
		it("boots with every controller ready and the HUD built", function()
			local _, _, c = boot()
			expectClean(c)
			expect(#c:Descendants() > 200).toBe(true)
			expect(c.world.workspace:FindFirstChild("World") ~= nil).toBe(true)
			expect(c.kernel ~= nil).toBe(true)
			for name, entry in c.kernel._controllers do
				if entry.state ~= "ready" then
					error("controller " .. name .. " is " .. tostring(entry.state))
				end
			end
			expect(c:Store("profile") ~= nil).toBe(true)
		end)

		it("opens and closes every screen for a new player", function()
			local _, _, c = boot()
			local manifest = c:require(c.clientFolder.Manifest)
			for _, name in manifest.Screens do
				if name == "MonsterDetail" then
					continue -- needs a monster id; covered by the first-session test
				end
				local root = c:Open(name)
				if not root then
					error("screen " .. name .. " did not build")
				end
				c:Advance(0.5)
				if not c:IsShown(root) then
					local chain = {}
					local cursor = root
					while cursor do
						table.insert(chain, cursor.Name .. (if cursor:IsA("GuiObject") then "(" .. tostring(cursor.Visible) .. ")" else ""))
						cursor = cursor.Parent
					end
					error(name .. " is not shown: " .. table.concat(chain, " < ") .. "\n" .. table.concat(c:Problems(), "\n"))
				end
				c:Close(name)
				c:Advance(0.2)
				local problems = c:Problems()
				if #problems > 0 then
					error(name .. ":\n" .. table.concat(problems, "\n\n"))
				end
			end
		end)

		it("plays the first hatch through the UI", function()
			local _, _, c = boot()
			c:Advance(10)
			local incubators = c:Open("Incubators")
			c:Click(c:Button("Choose!", incubators))
			c:Advance(0.5)
			local top = c.kernel.UI.Top
			local choices = top:FindFirstChild("Choices", true)
			expect(choices ~= nil).toBe(true)
			c:Click(c:Button("Choose", choices:FindFirstChild("mossbun")))
			c:Advance(5)
			local nameIt = c:Button("Name it", top)
			expect(nameIt ~= nil).toBe(true)
			c:Click(c:Button("Nice!", top))
			c:Advance(2)
			local list = c:Store("profile.Monsters.list")
			local count = 0
			for _, m in list do
				count += 1
				expect(m.line).toBe("mossbun")
			end
			expect(count).toBe(1)
			expect(choices:IsDescendantOf(c.playerGui)).toBe(false)
			expectClean(c)
		end)

		it("survives clicking every button on every screen as a veteran player", function()
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			local ids = veteran(h, player)
			local c = ClientHarness.new(h, player)
			c:Advance(2)
			expectClean(c)
			local manifest = c:require(c.clientFolder.Manifest)
			local report = {}
			local clicks = 0
			for _, name in manifest.Screens do
				local params = if name == "MonsterDetail" then { id = ids[1] } else nil
				local root = c:Open(name, params)
				c:Advance(0.5)
				local count = math.min(#c:Buttons(root), 60)
				expect(c:IsShown(root)).toBe(true)
				for i = 1, count do
					root = c:Open(name, params)
					c:Advance(0.2)
					local button = c:Buttons(root)[i]
					if not button then
						break
					end
					local label = ClientHarness.buttonText(button)
					local before = {}
					for _, b in c:Buttons(c.kernel.UI.Top) do
						before[b] = true
					end
					c:Click(button)
					c:Advance(1)
					clicks += 1
					-- Follow through one confirmation dialog, if the click opened one.
					for _, b in c:Buttons(c.kernel.UI.Top) do
						if not before[b] then
							label ..= " → " .. ClientHarness.buttonText(b)
							c:Click(b)
							c:Advance(1)
							break
						end
					end
					local problems = c:Problems({ "Infinite yield possible" })
					if #problems > 0 then
						table.insert(report, string.format("[%s] button %d %q:\n  %s", name, i, label, table.concat(problems, "\n  ")))
						c:ClearProblems()
					end
					if c.kernel.Router:Current() then
						c:Close()
					end
				end
				c:Close(name)
			end
			expect(#c.requests).toBeGreaterThan(10)
			if #report > 0 then
				error(#report .. " failing clicks (of " .. clicks .. "):\n\n" .. table.concat(report, "\n\n"))
			end
		end)

		it("survives a long random walk through the whole UI", function()
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			veteran(h, player)
			local c = ClientHarness.new(h, player)
			c:Advance(2)
			local rng = Random and Random.new(7) or nil
			math.randomseed(7)
			local report = {}
			local path = {}
			for step = 1, 600 do
				local buttons = c:Buttons()
				if #buttons == 0 then
					break
				end
				local button = buttons[if rng then rng:NextInteger(1, #buttons) else math.random(1, #buttons)]
				local label = ClientHarness.buttonText(button)
				table.insert(path, label)
				if #path > 8 then
					table.remove(path, 1)
				end
				c:Click(button)
				c:Advance(if step % 50 == 0 then 30 else 0.4)
				local problems = c:Problems({ "Infinite yield possible" })
				if #problems > 0 then
					table.insert(
						report,
						string.format("step %d after %s:\n  %s", step, table.concat(path, " › "), table.concat(problems, "\n  "))
					)
					c:ClearProblems()
				end
			end
			if #report > 0 then
				error(#report .. " problems:\n\n" .. table.concat(report, "\n\n"))
			end
		end)

		it("fits every screen on a small phone", function()
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			local ids = veteran(h, player)
			local viewport = t.Roblox.Vector2.new(568, 320)
			local c = ClientHarness.new(h, player, { viewport = viewport })
			c:Advance(1)
			local manifest = c:require(c.clientFolder.Manifest)
			local overflow = {}
			for _, name in manifest.Screens do
				local params = if name == "MonsterDetail" then { id = ids[1] } else nil
				local root = c:Open(name, params)
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
				error("off-screen on 568x320:\n  " .. table.concat(overflow, "\n  "))
			end
		end)

		it("draws the leaderboard board and the champion's nameplate", function()
			local h = TestKernel.new({ systems = allSystems() })
			local Boards = t.Shared("Config").Leaderboards
			local player = h:Join(8801, "Champ")
			local week = Boards.Week(h.adapters.Clock.Now())
			h.adapters.boards[Boards.Key("codex", week - 1)] = { [8801] = 30 }
			veteran(h, player)
			local c = ClientHarness.new(h, player)
			c:Advance(Boards.ChampionRefresh)
			local body = c.world.workspace.World.Hub.Buildings.leaderboard.Body
			local gui = body:FindFirstChild("BoardGui")
			expect(gui ~= nil).toBe(true)
			local texts = {}
			for _, d in gui:GetDescendants() do
				if d:IsA("TextLabel") and d.Text ~= "" then
					table.insert(texts, d.Text)
				end
			end
			expect(#texts).toBeGreaterThan(2)
			local plate = c.character.HumanoidRootPart:FindFirstChild("ChampionTitle")
			if not plate then
				local champs = c:Store("global.Leaderboards.champions")
				error(
					"no plate; champions.codex = "
						.. tostring(champs and champs.codex and champs.codex.userId)
						.. " problems: "
						.. table.concat(c:Problems(), "\n")
				)
			end
			expect(string.find(plate.Title.Text, "Master Collector", 1, true) ~= nil).toBe(true)
			local screen = c:Open("Leaderboards", { board = "codex" })
			c:Advance(1)
			expect(c:HasText("Master Collector", screen)).toBe(true)
			expect(c:HasText("You! Nice work.", screen)).toBe(true)
			expectClean(c)
		end)
	end)
end
