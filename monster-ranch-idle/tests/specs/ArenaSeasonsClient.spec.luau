--[[
	ArenaSeasonsClient (update 3.8): the Arena screen's Season tab through the real client
	(ClientHarness): the season and its ticking countdown, the featured lines, the season best,
	the reward track, the season board with your rank, the pre-season view, and Spanish.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness, MockAdapters = t.TestKernel, t.ClientHarness, t.MockAdapters
	local Config = t.Shared("Config")
	local ArenaLogic = t.Shared("Logic.Arena")
	local Format = t.Shared("Logic.Format")

	local S1 = ArenaLogic.SeasonStartsAt(1)
	local S2 = ArenaLogic.SeasonStartsAt(2)

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

	-- A player with a season-1 arena record of `rating`, on the Season tab.
	local function seasonTab(startTime: number?, rating: number?, options, tabText: string?)
		local net = MockAdapters.network()
		if rating then
			net.arena[7001] = {
				userId = 7001,
				name = "Sky",
				rating = rating,
				team = ArenaLogic.Bot(1000, 3).team,
				wins = 4,
				losses = 1,
				updatedAt = 0,
				season = ArenaLogic.SeasonAt(startTime or 0),
			}
		end
		local h = TestKernel.new({ systems = allSystems(), network = net, startTime = startTime })
		local p = h:Join(7001, "Sky")
		levelTo(h, p, 20)
		local c = ClientHarness.new(h, p, options)
		c:Advance(1)
		local screen = c:Open("Arena")
		c:Advance(0.5)
		c:Click(c:Button(tabText or "Season", screen))
		c:Advance(0.5)
		return h, p, c, screen
	end

	describe("Arena Season tab", function()
		it("shows the season, a ticking countdown, the featured lines, the reward track and your rank", function()
			local h, _, c, screen = seasonTab(S1 + 3600, 1300)
			local countdown = screen:FindFirstChild("SeasonCountdown", true)
			local now = h.adapters.Clock.Now()
			expect(countdown.Text).toBe(string.format("Arena Season 1 · ends in %s", Format.duration(S2 - now)))
			local before = countdown.Text
			c:Advance(3 * 3600) -- the countdown ticks while the tab is open
			countdown = screen:FindFirstChild("SeasonCountdown", true)
			expect(countdown.Text ~= before).toBe(true)
			expect(countdown.Text).toBe(string.format("Arena Season 1 · ends in %s", Format.duration(S2 - h.adapters.Clock.Now())))
			for _, line in ArenaLogic.Featured(1) do
				local cell = screen:FindFirstChild("Featured_" .. line, true)
				expect(cell ~= nil).toBe(true)
				expect(c:HasText("+10%", cell)).toBe(true)
				expect(c:HasText(Config.Species.Form(line, 1).name, cell)).toBe(true)
			end
			expect(screen:FindFirstChild("SeasonBest", true).Text).toBe("Season best: Gold")
			for _, tierId in { "silver", "gold", "crystal", "champion" } do
				expect(screen:FindFirstChild("Track_" .. tierId, true) ~= nil).toBe(true)
			end
			expect(screen:FindFirstChild("Track_bronze", true)).toBe(nil)
			expect(c:HasText("Title: Arena Champion · Aura: Champion's Crown Aura", screen)).toBe(true)
			expect(c:HasText("Gold Arena Cup", screen)).toBe(true)
			-- The season board reaches the client: you are #1 of 1.
			c:Advance(Config.Leaderboards.GlobalRefresh)
			expect(screen:FindFirstChild("Rank1", true).Text).toBe("1. Sky · 1,300")
			expect(screen:FindFirstChild("SeasonYou", true).Text).toBe("You: #1 · 1,300")
			expectClean(c)
		end)

		it("counts down to season 1 before it starts and shows only your rating and tier", function()
			local h, _, c, screen = seasonTab(nil, nil)
			local now = h.adapters.Clock.Now()
			expect(ArenaLogic.SeasonAt(now)).toBe(0)
			expect(screen:FindFirstChild("SeasonCountdown", true).Text).toBe(
				string.format("Season %d starts in %s", 1, Format.duration(S1 - now))
			)
			expect(c:HasText("The season board opens with Season 1.", screen)).toBe(true)
			expect(screen:FindFirstChild("SeasonYou", true).Text).toBe("Your rating: 1,000 · Bronze tier")
			expect(screen:FindFirstChild("SeasonBest", true).Text).toBe("Season best: none yet")
			-- Season 1's featured lines are already on show.
			expect(screen:FindFirstChild("Featured_" .. ArenaLogic.Featured(1)[1], true) ~= nil).toBe(true)
			expectClean(c)
		end)

		it("shows the Season tab in Spanish", function()
			local _, _, c, screen = seasonTab(S1 + 3600, 1300, { localeId = "es-mx" }, "Temporada")
			expect(c:HasText("Temporada", screen)).toBe(true)
			expect(c:HasText("Mejor de la temporada: Oro", screen)).toBe(true)
			expect(c:HasText("Top 10 de la temporada", screen)).toBe(true)
			expectClean(c)
		end)
	end)
end
