-- S5 Leaderboards: live per-server boards, weekly global boards through the Leaderboards
-- adapter (OrderedDataStores), weekly Stampede damage, and last week's champions.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Boards = Config.Leaderboards

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "HallOfFame", "Expeditions", "Leaderboards" }

	local function boot()
		return TestKernel.new({ systems = SYSTEMS })
	end

	local function give(h, player, line, weight)
		local record = h:System("Monsters"):Create(player, { line = line, rarity = 2, weight = weight }, "test", true)
		return record
	end

	local function row(list, userId)
		for i, r in list or {} do
			if r.userId == userId then
				return r, i
			end
		end
		return nil
	end

	describe("Weeks", function()
		it("counts weeks from the Saturday anchor", function()
			expect(Boards.Week(Boards.WeekAnchor)).toBe(0)
			expect(Boards.Week(Boards.WeekAnchor - 1)).toBe(-1)
			expect(Boards.Week(Boards.WeekAnchor + Boards.WeekSeconds)).toBe(1)
			expect(Boards.WeekEndsAt(0)).toBe(Boards.WeekAnchor + Boards.WeekSeconds)
			expect(Boards.Key("codex", 3)).toBe("codex_w3")
		end)
	end)

	describe("Server boards", function()
		it("ranks everyone on the server and labels the heaviest monster", function()
			local h = boot()
			local a = h:Join(8001, "Ana")
			local b = h:Join(8002, "Ben")
			give(h, a, "cindlet", 3.5)
			give(h, b, "bubblin", 12.25)
			give(h, b, "mossbun", 1)
			h:Advance(Boards.ServerRefresh)
			local heaviest = h:Client(a).global.Leaderboards.server.heaviest
			expect(heaviest[1].userId).toBe(8002)
			expect(heaviest[1].value).toBe(1225)
			expect(type(heaviest[1].label)).toBe("string")
			expect(heaviest[2].userId).toBe(8001)
			local codex = h:Client(a).global.Leaderboards.server.codex
			expect(row(codex, 8002).value).toBe(2)
			expect(row(codex, 8001).value).toBe(1)
		end)

		it("leaves players with nothing off a board", function()
			local h = boot()
			local a = h:Join(8003)
			h:Advance(Boards.ServerRefresh)
			local G = h:Client(a).global.Leaderboards
			expect(#G.server.halloffame).toBe(0)
			expect(#G.server.stage).toBe(0)
		end)
	end)

	describe("Stampede damage", function()
		it("adds damage from each Stampede and resets it every week", function()
			local h = boot()
			local a = h:Join(8010)
			h.kernel.Bus:Publish("BossDamage", a, { damage = 1200.7, rank = 1 })
			h.kernel.Bus:Publish("BossDamage", a, { damage = 300, rank = 2 })
			expect(h:Section(a, "Leaderboards").stampede).toBe(1500)
			expect(h:System("Leaderboards"):Value(a, "stampede")).toBe(1500)
			h:Advance(Boards.WeekEndsAt(Boards.Week(h.adapters.Clock.Now())) - h.adapters.Clock.Now() + 1)
			expect(h:System("Leaderboards"):Value(a, "stampede")).toBe(0)
		end)
	end)

	describe("Global boards", function()
		it("submits values and reads this week's top list with names", function()
			local h = boot()
			h.adapters.names[9999] = "FarAway"
			local week = Boards.Week(h.adapters.Clock.Now())
			h.adapters.boards[Boards.Key("heaviest", week)] = { [9999] = 5000 }
			local a = h:Join(8020, "Ana")
			give(h, a, "cindlet", 2)
			h:Advance(Boards.GlobalRefresh)
			local submitted = h.adapters.boards[Boards.Key("heaviest", week)]
			expect(submitted[8020]).toBe(200)
			local G = h:Client(a).global.Leaderboards
			expect(G.global.heaviest[1].name).toBe("FarAway")
			expect(G.global.heaviest[2].name).toBe("Ana")
			expect(G.globalAt).toBeGreaterThan(0)
		end)

		it("only writes values that changed, and writes on leave", function()
			local h = boot()
			local writes = 0
			local submit = h.adapters.Leaderboards.Submit
			h.adapters.Leaderboards.Submit = function(...)
				writes += 1
				return submit(...)
			end
			local a = h:Join(8030)
			give(h, a, "cindlet", 2)
			h:Advance(Boards.GlobalRefresh)
			local afterFirst = writes
			expect(afterFirst).toBe(2) -- heaviest + codex
			h:Advance(Boards.GlobalRefresh)
			expect(writes).toBe(afterFirst)
			give(h, a, "bubblin", 9)
			h:Leave(a)
			expect(writes).toBe(afterFirst + 2)
			local week = Boards.Week(h.adapters.Clock.Now())
			expect(h.adapters.boards[Boards.Key("heaviest", week)][8030]).toBe(900)
		end)

		it("keeps working when the store is down", function()
			local h = boot()
			local a = h:Join(8040)
			local before = h:Client(a).global.Leaderboards.globalAt
			h.adapters.leaderboardsDown = true
			give(h, a, "cindlet", 2)
			h:Advance(Boards.GlobalRefresh + Boards.ServerRefresh)
			local G = h:Client(a).global.Leaderboards
			expect(G.globalAt).toBe(before)
			expect(#G.server.heaviest).toBe(1)
			h.adapters.leaderboardsDown = false
			h:Advance(Boards.GlobalRefresh)
			G = h:Client(a).global.Leaderboards
			expect(G.globalAt).toBeGreaterThan(before)
			expect(G.global.heaviest[1].userId).toBe(8040)
		end)
	end)

	describe("Champions", function()
		it("gives last week's #1 their title", function()
			local h = boot()
			local week = Boards.Week(h.adapters.Clock.Now())
			h.adapters.boards[Boards.Key("codex", week - 1)] = { [8050] = 40, [8051] = 12 }
			h.adapters.boards[Boards.Key("stage", week - 1)] = { [7777] = 30 }
			h.adapters.names[7777] = "Trailblazer7"
			local a = h:Join(8050, "Cleo")
			h:Advance(Boards.ChampionRefresh)
			local champions = h:Client(a).global.Leaderboards.champions
			expect(champions.codex.userId).toBe(8050)
			expect(champions.codex.name).toBe("Cleo")
			expect(champions.stage.name).toBe("Trailblazer7")
			expect(champions.heaviest).toBe(false)
			expect(h:System("Leaderboards"):Titles(8050)).toEqual({ "codex" })
		end)

		it("rolls over at the end of the week", function()
			local h = boot()
			local a = h:Join(8060)
			give(h, a, "cindlet", 4)
			h:Advance(Boards.GlobalRefresh)
			local now = h.adapters.Clock.Now()
			h:Advance(Boards.WeekEndsAt(Boards.Week(now)) - now + Boards.ServerRefresh)
			local G = h:Client(a).global.Leaderboards
			expect(G.week).toBe(Boards.Week(now) + 1)
			expect(G.champions.heaviest.userId).toBe(8060)
			expect(h:System("Leaderboards"):Titles(8060)).toEqual({ "heaviest", "codex" })
		end)
	end)
end
