-- Update 2.1 · Arena & Raids: normalized async PvP (two servers share the arena store),
-- 4-player raids with raid-only species, and the Harvest Moon event.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, MockAdapters = t.TestKernel, t.MockAdapters
	local Config = t.Shared("Config")
	local ArenaLogic = t.Shared("Logic.Arena")
	local A = Config.Arena
	local R = Config.Raids

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Quests", "Arena", "Raids" }

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function adults(h, p, lines, rarity, lv, stars)
		local ids = {}
		for _, line in lines do
			local m = h:System("Monsters"):Create(p, { line = line, rarity = rarity or 2, stage = 3 }, "test", true)
			m.lv = lv or 1
			m.stars = stars or 1
			table.insert(ids, m.id)
		end
		return ids
	end

	describe("Arena rules", function()
		it("normalizes every fighter: rarity, level, stars, traits and mutations don't count", function()
			local weak = { line = "cindlet", rarity = 1, stage = 3, form = "blazefang", lv = 1, stars = 1, muts = {}, traits = { 3, 4 } }
			local strong = {
				line = "cindlet",
				rarity = 6,
				stage = 3,
				form = "blazefang",
				lv = 60,
				stars = 5,
				muts = { "prismatic" },
				traits = { 1, 2, 5 },
			}
			local a = ArenaLogic.Normalize(ArenaLogic.Snapshot(weak))
			local b = ArenaLogic.Normalize(ArenaLogic.Snapshot(strong))
			local Formulas = t.Shared("Logic.Formulas")
			expect(Formulas.Stats(a)).toEqual(Formulas.Stats(b))
			expect(b.look.variant).toBe(0)
			expect(#b.look.muts).toBe(1) -- it still looks like itself
			-- Same teams, same seed: the same result.
			local team = { ArenaLogic.Snapshot(weak), ArenaLogic.Snapshot(strong), ArenaLogic.Snapshot(weak) }
			local r1 = ArenaLogic.Fight(team, team, 99)
			local r2 = ArenaLogic.Fight(team, team, 99)
			expect(r1.win).toBe(r2.win)
			expect(r1.turns).toBe(r2.turns)
		end)

		it("moves ratings by Elo and names tiers", function()
			expect(ArenaLogic.Delta(1000, 1000, true)).toBe(A.K / 2)
			expect(ArenaLogic.Delta(1000, 1000, false)).toBe(-A.K / 2)
			expect(ArenaLogic.Delta(1000, 1400, true) > ArenaLogic.Delta(1400, 1000, true)).toBe(true)
			expect(ArenaLogic.Tier(999).id).toBe("bronze")
			expect(ArenaLogic.Tier(1250).id).toBe("gold")
			expect(ArenaLogic.Tier(2000).id).toBe("champion")
			local bot = ArenaLogic.Bot(1200, 5)
			expect(#bot.team).toBe(A.TeamSize)
			for _, f in bot.team do
				expect(Config.Species.ById[f.line].raid).toBeFalsy()
				expect(Config.Species.ById[f.line].event).toBeFalsy()
			end
		end)
	end)

	describe("Arena across servers", function()
		it("fights a defense team set on another server and moves both ratings", function()
			local net = MockAdapters.network()
			local s1 = TestKernel.new({ systems = SYSTEMS, network = net })
			local s2 = TestKernel.new({ systems = SYSTEMS, network = net })
			local def = s1:Join(5001, "Dee")
			local atk = s2:Join(5002, "Ace")
			local defIds = adults(s1, def, { "gravitoad", "acornling", "pebblet" })
			expect(s1:Reject(def, "Arena.SetDefense", { ids = defIds })).toBe("Unlocks at Ranch Level 20")
			levelTo(s1, def, 20)
			levelTo(s2, atk, 20)
			local baby = s1:System("Monsters"):Create(def, { line = "zappip", rarity = 2 }, "test", true)
			expect(s1:Reject(def, "Arena.SetDefense", { ids = { defIds[1], defIds[2], baby.id } })).toBe(
				"Only Adults can fight in the arena"
			)
			s1:Advance(2)
			expect(s1:Call(def, "Arena.SetDefense", { ids = defIds }).rating).toBe(A.StartRating)
			expect(net.arena[5001].team[1].line).toBe("gravitoad")

			local atkIds = adults(s2, atk, { "wyrmlet", "lumipup", "zappip" })
			s2:Call(atk, "Arena.Refresh")
			local cands = s2:Session(atk, "Arena").candidates
			expect(#cands).toBe(A.Candidates)
			local index
			for i, c in cands do
				if c.name == "Dee" then
					index = i
				end
			end
			expect(index ~= nil).toBe(true)
			local res = s2:Call(atk, "Arena.Attack", { candidate = index, ids = atkIds })
			expect(res.replay.units ~= nil).toBe(true)
			expect(res.rating).toBe(A.StartRating + res.delta)
			expect(net.arena[5002].rating).toBe(res.rating)
			-- The defender moved the other way.
			expect(net.arena[5001].rating).toBe(A.StartRating - res.delta)
			expect(s2:Section(atk, "Arena").attempts.n).toBe(1)
			expect(s2:Session(atk, "Arena").attemptsLeft).toBe(A.AttemptsPerDay - 1)
			s2:Advance(2)
			expect(s2:Reject(atk, "Arena.Attack", { candidate = index, ids = atkIds })).toBe("Pick an opponent from the list")
		end)

		it("fills in bots, stops at the daily limit and pays the weekly tier", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			levelTo(h, p, 20)
			local ids = adults(h, p, { "wyrmlet", "nullkit", "lumipup" })
			for round = 1, A.AttemptsPerDay do
				h:Call(p, "Arena.Refresh")
				local cands = h:Session(p, "Arena").candidates
				expect(cands[1].bot).toBe(true)
				h:Advance(2)
				h:Call(p, "Arena.Attack", { candidate = 1, ids = ids })
				h:Advance(2)
				expect(h:Section(p, "Arena").attempts.n).toBe(round)
			end
			h:Call(p, "Arena.Refresh")
			h:Advance(2)
			expect(h:Reject(p, "Arena.Attack", { candidate = 1, ids = ids })).toBe("No arena battles left today. Come back tomorrow!")
			expect(h:Reject(p, "Arena.ClaimWeekly")).toBe("Finish an arena week to earn a reward")
			local best = h:Section(p, "Arena").bestTier
			expect(best ~= "").toBe(true)
			-- A week later the best tier pays once.
			p = h:Rejoin(p, 7 * 86400)
			local claim = h:Call(p, "Arena.ClaimWeekly")
			expect(claim.tier).toBe(best)
			expect(#claim.rewards >= 1).toBe(true)
			h:Advance(2)
			expect(h:Reject(p, "Arena.ClaimWeekly")).toBe("You already claimed this week's arena reward")
		end)

		it("says so when the arena store is down", function()
			local net = MockAdapters.network()
			local h = TestKernel.new({ systems = SYSTEMS, network = net })
			local p = h:Join()
			levelTo(h, p, 20)
			net.arenaDown = true
			expect(h:Reject(p, "Arena.SetDefense", { ids = adults(h, p, { "cindlet", "bubblin", "mossbun" }) })).toBe(
				"The arena is busy. Try again in a moment."
			)
		end)
	end)

	describe("Raids", function()
		local function party(h, n: number, rarity, lv, stars)
			local players = {}
			for i = 1, n do
				local p = h:Join(6000 + i, "Raider" .. i)
				levelTo(h, p, 30)
				players[i] = { p = p, ids = adults(h, p, { "wyrmlet", "titanling" }, rarity, lv, stars) }
			end
			return players
		end

		it("fights the Titan with four players and pays each the Raid Egg", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local team = party(h, 4, 6, 60, 5)
			local host = team[1]
			local lobby = h:Call(host.p, "Raids.Open", { raid = "titan", ids = host.ids }).lobby
			expect(h:Client(team[2].p).global.Raids.lobbies[lobby].raid).toBe("titan")
			for i = 2, 4 do
				h:Call(team[i].p, "Raids.Join", { lobby = lobby, ids = team[i].ids })
			end
			local extra = h:Join(6100, "Late")
			levelTo(h, extra, 30)
			expect(h:Reject(extra, "Raids.Join", { lobby = lobby, ids = adults(h, extra, { "cindlet" }, 6, 60, 5) })).toBe(
				"That raid is full"
			)
			expect(h:Reject(team[2].p, "Raids.Launch")).toBe("Only the host can start the raid")
			local res = h:Call(host.p, "Raids.Launch")
			expect(res.win).toBe(true)
			for _, member in team do
				local event = h:LastEvent(member.p, "Raids.Result").payload
				expect(event.win).toBe(true)
				expect(#event.replay.units).toBe(8 + 1 + #R.ById.titan.adds)
				expect(h:Section(member.p, "Raids").rewarded).toBe(1)
				local eggs = 0
				for _, e in h:Section(member.p, "Eggs").list do
					if e.type == "raid" then
						eggs += 1
					end
				end
				expect(eggs).toBe(1)
				expect(h:Session(member.p, "Raids").lobby).toBe(false)
			end
			expect(next(h:Client(host.p).global.Raids.lobbies)).toBeNil()
			expect(h:Section(host.p, "Quests").achievements.raid_win.progress).toBe(1)
		end)

		it("loses with a weak team, caps daily rewards and cleans up lobbies", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local weak = party(h, 1, 2, 10, 1)[1]
			h:Call(weak.p, "Raids.Open", { raid = "titan", ids = weak.ids })
			expect(h:Call(weak.p, "Raids.Launch").win).toBe(false)
			expect(h:Section(weak.p, "Raids").rewarded).toBe(0)
			expect(h:Section(weak.p, "Raids").runs).toBe(1)

			-- Daily cap: after DailyRewards wins, winning pays the consolation.
			local s = h:Section(weak.p, "Raids")
			s.day = math.floor(h.adapters.Clock.Now() / 86400)
			s.rewarded = R.DailyRewards
			local strong = party(h, 4, 6, 60, 5)
			h:Advance(2)
			local lobby = h:Call(strong[1].p, "Raids.Open", { raid = "titan", ids = strong[1].ids }).lobby
			for i = 2, 4 do
				h:Call(strong[i].p, "Raids.Join", { lobby = lobby, ids = strong[i].ids })
			end
			h:Section(strong[2].p, "Raids").day = s.day
			h:Section(strong[2].p, "Raids").rewarded = R.DailyRewards
			h:Call(strong[1].p, "Raids.Launch")
			expect(h:Section(strong[2].p, "Raids").rewarded).toBe(R.DailyRewards)
			expect(h:LastEvent(strong[2].p, "Raids.Result").payload.rewards[1].kind).toBe("coins")

			-- A member leaving drops out; the host leaving closes; lobbies expire.
			h:Advance(2)
			local id = h:Call(strong[1].p, "Raids.Open", { raid = "wyrm", ids = strong[1].ids }).lobby
			h:Call(strong[2].p, "Raids.Join", { lobby = id, ids = strong[2].ids })
			h:Leave(strong[2].p)
			expect(#h:Client(strong[1].p).global.Raids.lobbies[id].members).toBe(1)
			h:Advance(2)
			h:Call(strong[1].p, "Raids.Leave")
			expect(h:Client(strong[1].p).global.Raids.lobbies[id]).toBeNil()
			h:Advance(2)
			h:Call(strong[3].p, "Raids.Open", { raid = "wyrm", ids = strong[3].ids })
			h:Advance(R.LobbySeconds + 6)
			expect(next(h:Client(strong[3].p).global.Raids.lobbies)).toBeNil()
			expect(h:Session(strong[3].p, "Raids").lobby).toBe(false)
		end)

		it("hatches the raid lines only from the Raid Egg", function()
			local EggRoll = t.Shared("Logic.EggRoll")
			local rng = t.Shared("Logic.Rng").new(8)
			local lines = {}
			for _ = 1, 200 do
				local spec = EggRoll.roll(rng, Config.Eggs.ById.raid, {})
				lines[spec.line] = true
				expect(Config.Species.ById[spec.line].raid).toBe(true)
			end
			expect(lines.titanling and lines.wyrmlet and lines.tempestray).toBe(true)
			for _, egg in Config.Eggs.List do
				if egg.id ~= "raid" then
					expect(egg.pool ~= "raid").toBe(true)
				end
			end
		end)
	end)

	describe("Harvest Moon", function()
		it("runs in October with Blood Moon ×3, the Harvest Egg and Season 5", function()
			local HM = Config.Events.ById.harvestmoon
			expect(os.date("!%d %b %Y", HM.startsAt)).toBe("02 Oct 2027")
			expect(Config.Weather.EventBoosts.harvestmoon.bloodmoon).toBe(3)
			local EggRoll = t.Shared("Logic.EggRoll")
			local rng = t.Shared("Logic.Rng").new(2)
			local lines = {}
			for _ = 1, 200 do
				lines[EggRoll.roll(rng, Config.Eggs.ById.harvest, {}).line] = true
			end
			expect(lines.pumpkit and lines.scarecrowl and lines.batterfly).toBe(true)
			local Q = Config.Quests
			local s5 = Q.Seasons[5]
			expect(s5.startsAt >= Q.Seasons[4].endsAt).toBe(true)
			for _, tier in s5.tiers do
				for _, track in { tier.free, tier.premium } do
					for _, reward in track do
						if reward.kind == "egg" then
							expect(Config.Eggs.ById[reward.id] ~= nil).toBe(true)
						elseif reward.kind == "accessory" then
							expect(Config.Accessories.ById[reward.id] ~= nil).toBe(true)
						end
					end
				end
			end
			expect(Q.Codes.ARENAANDRAIDS.reward[1].id).toBe("raid")
		end)
	end)
end
