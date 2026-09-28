--[[
	StraysClient (update 3.13 · Wild things): Stray Monsters through the real client
	(ClientHarness). The stray stands on the owner's plot with its "?" bubble and "Befriend"
	prompt; the prompt opens the screen; Approach and three rounds of clicks befriend it (the
	monster joins, the stray leaves the plot); the Codex Stray Log shows the line; no stray and the
	locked screen before Level 10; Spanish text.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Strays")
	local WeatherRoll = t.Shared("Logic.WeatherRoll")

	local BASE = 1790000000
	local UID = 4242
	local SLOT = Logic.Slot(UID, BASE) + 1
	local ARRIVE = Logic.ArriveAt(UID, SLOT)

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

	local function boot(level: number?, opts)
		local h = TestKernel.new({ systems = allSystems(), startTime = ARRIVE + 10 })
		local p = h:Join(UID)
		levelTo(h, p, level or Config.Unlocks.Features.strays)
		for _, id in Config.Food.Ids do
			h:System("Currency"):Add(p, "food." .. id, 5, "test")
		end
		h:Advance(6)
		local c = ClientHarness.new(h, p, opts)
		c:Advance(1)
		return h, p, c
	end

	local function strayModel(c)
		local folder = c.world.workspace:FindFirstChild("Strays")
		return folder and folder:FindFirstChild("Stray")
	end

	local function moodOf(h, p)
		local P = h:System("Progression")
		local pool = Logic.Pool(function(key)
			return P:IsUnlocked(p, key)
		end)
		local night = WeatherRoll.Phase(ARRIVE)
		return Logic.Roll(Logic.Seed(p.UserId, SLOT, h:Section(p, "Strays").secret), pool, night)
	end

	describe("Strays", function()
		it("walks a stray onto the plot, befriends it in three rounds and logs it in the Codex", function()
			local h, p, c = boot()
			local mood = moodOf(h, p)
			local model = strayModel(c)
			expect(model ~= nil).toBe(true)
			expect(model:GetAttribute("StrayLine")).toBe(mood.line)
			expect(model:FindFirstChild("StrayBubble", true) ~= nil).toBe(true)
			local prompt = model:FindFirstChild("BefriendPrompt", true)
			expect(prompt.ActionText).toBe("Befriend")
			expect(prompt.ObjectText).toBe(Logic.Name(mood.line))

			c:Trigger(prompt)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Strays")
			local screen = c:Screen("Strays")
			expect(c:HasText(string.format("Stray %s", Logic.Name(mood.line)), screen)).toBe(true)
			c:Click(screen:FindFirstChild("Approach", true))
			c:Advance(0.5)
			local count = h:System("Monsters"):Count(p)
			for i, want in mood.mood do
				local round = screen:FindFirstChild("StrayRound", true)
				expect(round:GetAttribute("Round")).toBe(i)
				expect(c:HasText(Logic.Hint(want), screen)).toBe(true)
				c:Click(round:FindFirstChild("Choice_" .. want, true))
				c:Advance(0.5)
			end
			expect(h:System("Monsters"):Count(p)).toBe(count + 1)
			expect(c:HasText("Befriended! ", screen) or screen:FindFirstChild("StrayResult", true) ~= nil).toBe(true)
			expect(screen:FindFirstChild("StrayResult", true).Text:find(Logic.Name(mood.line), 1, true) ~= nil).toBe(true)
			c:Advance(3)
			expect(strayModel(c)).toBeNil()

			local codex = c:Open("Codex", { tab = "strays" })
			c:Advance(0.5)
			local card = codex:FindFirstChild("Stray_" .. mood.line, true)
			expect(card ~= nil).toBe(true)
			expect(card:GetAttribute("Befriended")).toBe(1)
			expect(c:HasText("Met 1 · Befriended 1", card)).toBe(true)
			expectClean(c)
		end)

		it("keeps one stray when rebuilds overlap while the model builds (Studio showed three)", function()
			local h, p, c = boot()
			expect(strayModel(c) ~= nil).toBe(true)
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local Anim = c:require(c.clientFolder.UI.Anim)
			local original, wasEnabled = MonsterModel.Build, Anim.enabled
			MonsterModel.Build = function(...)
				c.world.task.wait(0.3) -- mesh loading yields in a real client
				return original(...)
			end
			-- Two rebuilds in a row (the key includes Reduced motion), each started before the other ends.
			Anim.enabled = false
			h.kernel.State:Dirty(p, { "session", "Strays" })
			c:Advance(0.1)
			Anim.enabled = true
			h.kernel.State:Dirty(p, { "session", "Strays" })
			c:Advance(1.5)
			MonsterModel.Build, Anim.enabled = original, wasEnabled
			local strays = 0
			for _, child in c.world.workspace:FindFirstChild("Strays"):GetChildren() do
				if child.Name == "Stray" then
					strays += 1
				end
			end
			expect(strays).toBe(1)
			expectClean(c)
		end)

		it("has no stray and shows the screen locked before Level 10", function()
			local _, _, c = boot(9)
			expect(strayModel(c)).toBeNil()
			local screen = c:Open("Strays")
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 10", screen)).toBe(true)
			expectClean(c)
		end)

		it("shows the stray screen in Spanish", function()
			local _, _, c = boot(nil, { localeId = "es-mx" })
			c:Open("Strays")
			c:Advance(0.5)
			expect(c:HasText("Monstruos callejeros")).toBe(true)
			expect(c:HasText("Acercarse")).toBe(true)
			expectClean(c)
		end)
	end)
end
