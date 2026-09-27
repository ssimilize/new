--[[
	CalendarClient (update 3.8 · Reasons to come back): the events calendar through the real
	client (ClientHarness): the HUD calendar button, the screen's three sections, "Go", the HUD
	countdown chips before a titan invasion, and the calendar in Spanish.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")

	local HOUR = 3600
	local TITAN = Config.Titan.Schedule[1].startsAt
	local SEPT = 1790000000 -- a Thursday in Sept 2026: nothing running, arena season 1 next week

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

	local function boot(startTime: number, opts: { [string]: any }?)
		local h = TestKernel.new({ systems = allSystems(), startTime = startTime })
		local p = h:Join()
		local c = ClientHarness.new(h, p, opts)
		c:Advance(1)
		return h, c
	end

	describe("Events calendar", function()
		it("opens from the HUD button and shows its three sections", function()
			local _, c = boot(SEPT)
			local hud = c.kernel:GetController("Hud")
			local button = hud:GetTarget("Events")
			expect(button ~= nil).toBe(true)
			expect(button.Parent.Name).toBe("Hud")
			c:Click(button)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Events")
			local screen = c:Screen("Events")
			expect(c:HasText("Now", screen)).toBe(true)
			expect(c:HasText("This week", screen)).toBe(true)
			expect(c:HasText("Coming up", screen)).toBe(true)
			-- Nothing runs yet: a friendly line instead of an empty list.
			expect(c:HasText("Nothing special is running right now.", screen)).toBe(true)
			expect(c:HasText("Weekly reset", screen)).toBe(true)
			expect(c:HasText("Arena Season 1", screen)).toBe(true)
			expect(c:HasText("Frostfall", screen)).toBe(true) -- months away, still listed
			expect(c:HasText("Starts in", screen)).toBe(true)
			expectClean(c)
		end)

		it("ticks the countdown and opens a row's screen with Go", function()
			local _, c = boot(SEPT)
			local screen = c:Open("Events")
			c:Advance(0.5)
			local slot = math.ceil(SEPT / Config.Boss.Period) * Config.Boss.Period
			local stampede = screen:FindFirstChild("Row_stampede:" .. slot, true)
			expect(stampede ~= nil).toBe(true)
			local time = stampede:FindFirstChild("Countdown", true)
			local before = time.Text
			c:Advance(3)
			expect(time.Text ~= before).toBe(true)
			local row = screen:FindFirstChild("Row_arena:1", true)
			expect(row ~= nil).toBe(true)
			c:Click(row:FindFirstChild("Go", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Arena")
			expectClean(c)
		end)

		it("shows a titan countdown chip within 24 hours, which opens the calendar", function()
			local _, c = boot(TITAN - 3 * HOUR)
			c:Advance(1)
			local chips = c.kernel.UI.Hud:FindFirstChild("EventChips", true)
			expect(chips ~= nil).toBe(true)
			local titanChip
			for _, chip in chips:GetChildren() do
				if chip:IsA("TextButton") and c:IsShown(chip) and chip:FindFirstChild("Label").Text == "Titan" then
					titanChip = chip
				end
			end
			expect(titanChip ~= nil).toBe(true)
			local clock = titanChip:FindFirstChild("Time").Text
			expect(string.match(clock, "^2:5%d:%d%d$") ~= nil).toBe(true)
			c:Click(titanChip)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Events")
			-- Hidden while a screen is open, like the weather banner.
			expect(c:IsShown(titanChip)).toBe(false)
			expect(c:HasText("Titan · " .. Config.Titan.Rotation[1].name, c:Screen("Events"))).toBe(true)
			c:Close("Events")
			c:Advance(0.5)
			expect(c:IsShown(titanChip)).toBe(true)
			expectClean(c)
		end)

		it("shows no chip when nothing starts within a day", function()
			local _, c = boot(TITAN - 7 * 24 * HOUR - 20 * HOUR)
			c:Advance(1)
			local chips = c.kernel.UI.Hud:FindFirstChild("EventChips", true)
			for _, chip in chips:GetChildren() do
				if chip:IsA("TextButton") then
					expect(c:IsShown(chip) and chip:FindFirstChild("Label").Text == "Titan").toBe(false)
				end
			end
			expectClean(c)
		end)

		it("shows the calendar in Spanish", function()
			local _, c = boot(SEPT, { localeId = "es-mx" })
			local screen = c:Open("Events")
			c:Advance(0.5)
			expect(c:HasText("Eventos")).toBe(true)
			expect(c:HasText("Ahora", screen)).toBe(true)
			expect(c:HasText("Próximamente", screen)).toBe(true)
			expect(c:HasText("Reinicio semanal", screen)).toBe(true)
			expect(c:HasText("Temporada de arena 1", screen)).toBe(true)
			expect(c:HasText("Empieza en", screen)).toBe(true)
			expectClean(c)
		end)
	end)
end
