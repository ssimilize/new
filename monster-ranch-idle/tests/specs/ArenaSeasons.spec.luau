--[[
	ArenaSeasons (update 3.8): arena seasons. Season dates, the lazy soft reset of own and
	defender records, one ratings index per season, featured lines and their boost, the
	season-end payout by best tier (paid once; Mastery titles and aura; decor cups; gems and
	cups even without Mastery), and the season leaderboard's key and values.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, MockAdapters = t.TestKernel, t.MockAdapters
	local Config = t.Shared("Config")
	local ArenaLogic = t.Shared("Logic.Arena")
	local A = Config.Arena
	local Boards = Config.Leaderboards

	local WEEK = 7 * 86400
	local S1 = ArenaLogic.SeasonStartsAt(1)
	local S2 = ArenaLogic.SeasonStartsAt(2)

	local BASE = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Quests", "Shop", "Arena" }
	local FULL = {
		"Currency",
		"Progression",
		"Rewards",
		"Monsters",
		"Eggs",
		"Quests",
		"Shop",
		"Monetization",
		"HallOfFame",
		"Mastery",
		"Leaderboards",
		"Arena",
	}

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function adults(h, p, lines)
		local ids = {}
		for _, line in lines do
			table.insert(ids, h:System("Monsters"):Create(p, { line = line, rarity = 2, stage = 3 }, "test", true).id)
		end
		return ids
	end

	-- A stored arena record, as another server would have left it.
	local function record(userId: number, rating: number, season: number)
		return {
			userId = userId,
			name = "Rancher" .. userId,
			rating = rating,
			team = ArenaLogic.Bot(1000, userId).team,
			wins = 0,
			losses = 0,
			updatedAt = 0,
			season = season,
		}
	end

	describe("Season dates", function()
		it("runs season 1 from Saturday 3 Oct to Saturday 28 Nov 2026, 15:00 UTC, in 8-week seasons", function()
			expect(S1).toBe(1791039600) -- Sat 3 Oct 2026 15:00 UTC
			expect(ArenaLogic.SeasonEndsAt(1)).toBe(1795878000) -- Sat 28 Nov 2026 15:00 UTC
			expect(S2).toBe(ArenaLogic.SeasonEndsAt(1))
			expect(ArenaLogic.SeasonAt(S1 - 1)).toBe(0)
			expect(ArenaLogic.SeasonAt(S1)).toBe(1)
			expect(ArenaLogic.SeasonAt(S2 - 1)).toBe(1)
			expect(ArenaLogic.SeasonAt(S2)).toBe(2)
			expect(ArenaLogic.SeasonStartsAt(3) - S2).toBe(A.Season.Weeks * WEEK)
			expect(ArenaLogic.SeasonAt(1790000000)).toBe(0) -- the test clock's default start
		end)
	end)

	describe("Soft reset", function()
		it("moves a rating ResetFraction of the way back to StartRating per season missed", function()
			expect(ArenaLogic.SoftReset(1600)).toBe(1300)
			expect(ArenaLogic.SoftReset(600)).toBe(800)
			expect(ArenaLogic.SoftReset(A.StartRating)).toBe(A.StartRating)
			local r = { rating = 1800 }
			expect(ArenaLogic.Reseason(r, 2)).toBe(true) -- season 0 -> 2: two resets
			expect(r.rating).toBe(1200)
			expect(r.season).toBe(2)
			expect(ArenaLogic.Reseason(r, 2)).toBe(false)
			expect(r.rating).toBe(1200)
		end)

		it("resets your own record lazily when you join in a new season", function()
			local net = MockAdapters.network()
			net.arena[6001] = record(6001, 1600, 1)
			local h = TestKernel.new({ systems = BASE, network = net, startTime = S2 + 3600 })
			local p = h:Join(6001, "Old")
			expect(net.arena[6001].rating).toBe(1300)
			expect(net.arena[6001].season).toBe(2)
			expect(h:Session(p, "Arena").rating).toBe(1300)
			expect(h:Session(p, "Arena").season).toBe(2)
			expect(net.arenaIndex[h.adapters.Arena.IndexName(2)][6001]).toBe(1300)
			-- Only once: a rejoin in the same season leaves it alone.
			p = h:Rejoin(p, 60)
			expect(net.arena[6001].rating).toBe(1300)
		end)

		it("resets a defender from an older season before its rating moves", function()
			local net = MockAdapters.network()
			net.arena[6010] = record(6010, 1150, 1)
			net.arenaIndex["MonsterRanch_ArenaRatings_s1"] = { [6010] = 1150 }
			local h = TestKernel.new({ systems = BASE, network = net, startTime = S2 - 600 })
			local p = h:Join(6011, "Ace")
			levelTo(h, p, 20)
			local ids = adults(h, p, { "wyrmlet", "lumipup", "zappip" })
			h:Call(p, "Arena.Refresh")
			local index
			for i, c in h:Session(p, "Arena").candidates do
				if c.name == "Rancher6010" then
					index = i
				end
			end
			expect(index ~= nil).toBe(true)
			h:Advance(700) -- season 2 starts before the fight
			local res = h:Call(p, "Arena.Attack", { candidate = index, ids = ids })
			local reset = ArenaLogic.SoftReset(1150)
			expect(net.arena[6010].season).toBe(2)
			expect(net.arena[6010].rating).toBe(reset + ArenaLogic.Delta(reset, A.StartRating, not res.win))
			expect(net.arena[6011].season).toBe(2)
			expect(net.arenaIndex[h.adapters.Arena.IndexName(2)][6010]).toBe(net.arena[6010].rating)
		end)
	end)

	describe("Per-season ratings index", function()
		it("names one index per season and keeps the original before season 1", function()
			local Arena = MockAdapters.new().Arena
			expect(Arena.IndexName(0)).toBe("MonsterRanch_ArenaRatings_v1")
			expect(Arena.IndexName(1)).toBe("MonsterRanch_ArenaRatings_s1")
			expect(Arena.IndexName(4)).toBe("MonsterRanch_ArenaRatings_s4")
		end)

		it("only matches ratings from the current season", function()
			local net = MockAdapters.network()
			net.arena[6020] = record(6020, 1000, 1)
			net.arenaIndex["MonsterRanch_ArenaRatings_s1"] = { [6020] = 1000 }
			-- In season 1 the season-1 defender is found.
			local h1 = TestKernel.new({ systems = BASE, network = net, startTime = S1 + 3600 })
			local a = h1:Join(6021, "One")
			levelTo(h1, a, 20)
			h1:Call(a, "Arena.Refresh")
			local found = false
			for _, c in h1:Session(a, "Arena").candidates do
				found = found or c.name == "Rancher6020"
			end
			expect(found).toBe(true)
			-- In season 2 the season-1 index is not read: only bots.
			local h2 = TestKernel.new({ systems = BASE, network = net, startTime = S2 + 3600 })
			local b = h2:Join(6022, "Two")
			levelTo(h2, b, 20)
			h2:Call(b, "Arena.Refresh")
			for _, c in h2:Session(b, "Arena").candidates do
				expect(c.bot).toBe(true)
			end
			-- Setting a defense in season 2 indexes it in season 2 only.
			h2:Call(b, "Arena.SetDefense", { ids = adults(h2, b, { "gravitoad", "acornling", "pebblet" }) })
			expect(net.arenaIndex["MonsterRanch_ArenaRatings_s2"][6022]).toBe(A.StartRating)
			expect(net.arenaIndex["MonsterRanch_ArenaRatings_s1"][6022]).toBe(nil)
		end)
	end)

	describe("Featured lines", function()
		it("picks 3 distinct bot-pool lines per season, the same on every call", function()
			expect(#ArenaLogic.Featured(0)).toBe(0)
			local one = ArenaLogic.Featured(1)
			expect(#one).toBe(A.Season.Featured)
			expect(ArenaLogic.Featured(1)).toEqual(one)
			local seen = {}
			for _, line in one do
				local def = Config.Species.ById[line]
				expect(def ~= nil).toBe(true)
				expect(def.event).toBeFalsy()
				expect(def.raid).toBeFalsy()
				expect(#def.forms[3] >= 1).toBe(true)
				expect(seen[line]).toBe(nil)
				seen[line] = true
			end
			local differs = false
			for season = 2, 6 do
				local other = ArenaLogic.Featured(season)
				for i, line in other do
					differs = differs or line ~= one[i]
				end
			end
			expect(differs).toBe(true)
		end)

		it("boosts featured fighters' stats in Normalize, on both sides of a fight", function()
			local featured = ArenaLogic.Featured(1)
			local set = ArenaLogic.FeaturedSet(1)
			local line = featured[1]
			local fighter = { line = line, form = Config.Species.ById[line].forms[3][1].id }
			expect(ArenaLogic.Normalize(fighter, set).statMult).toBe(1 + A.Season.FeaturedBoost)
			expect(ArenaLogic.Normalize(fighter).statMult).toBe(nil)
			local plain
			for _, l in Config.Species.Lines do
				if not set[l.id] and not l.event and not l.raid then
					plain = { line = l.id, form = l.forms[3][1].id }
					break
				end
			end
			expect(ArenaLogic.Normalize(plain, set).statMult).toBe(nil)
			-- A featured mirror match is still deterministic, and old calls still work.
			local team = { fighter, fighter, fighter }
			local r1 = ArenaLogic.Fight(team, team, 11, 1)
			local r2 = ArenaLogic.Fight(team, team, 11, 1)
			expect(r1.win).toBe(r2.win)
			expect(r1.turns).toBe(r2.turns)
			expect(ArenaLogic.Fight(team, team, 11).turns ~= nil).toBe(true)
		end)
	end)

	describe("Season rewards", function()
		local RATING = { bronze = 1000, silver = 1150, gold = 1300, crystal = 1450, champion = 1700 }

		local function playSeason(tierId: string, systems)
			local net = MockAdapters.network()
			net.arena[6100] = record(6100, RATING[tierId], 1)
			local h = TestKernel.new({ systems = systems, network = net, startTime = S1 + 3600 })
			local welcome = {}
			h.kernel.Bus:Subscribe("WelcomeItem", function(_, detail)
				if detail.kind == "arena" then
					table.insert(welcome, detail)
				end
			end)
			local p = h:Join(6100, "Champ")
			expect(h:Section(p, "Arena").seasonOf).toBe(1)
			expect(h:Section(p, "Arena").seasonBest).toBe(tierId)
			local gems = h:System("Currency"):Balance(p, "gems")
			p = h:Rejoin(p, S2 - h.adapters.Clock.Now() + 60)
			return h, p, gems, welcome
		end

		for _, tierId in { "bronze", "silver", "gold", "crystal", "champion" } do
			it(string.format("pays a %s season once, when the next season starts", tierId), function()
				local h, p, gems, welcome = playSeason(tierId, FULL)
				local reward = A.SeasonRewards[tierId]
				local s = h:Section(p, "Arena")
				expect(s.seasonPaid).toBe(1)
				expect(s.seasonOf).toBe(2)
				expect(s.seasonBest).toBe(ArenaLogic.Tier(ArenaLogic.SoftReset(RATING[tierId])).id)
				local mastery = h:Section(p, "Mastery")
				local shop = h:Section(p, "Shop")
				local paid = h:System("Currency"):Balance(p, "gems") - gems
				if not reward then
					expect(paid).toBe(0)
					expect(#welcome).toBe(0)
					return
				end
				expect(paid).toBe(reward.items[1].amount)
				expect(mastery.owned[reward.titleId]).toBe(true)
				expect(mastery.equipped.title).toBe(reward.titleId)
				if reward.items[2] then
					expect(shop.decor[reward.items[2].id]).toBe(1)
				end
				if tierId == "champion" then
					expect(mastery.owned.aura_champions_crown).toBe(true)
					expect(mastery.equipped.aura).toBe("aura_champions_crown")
				else
					expect(mastery.owned.aura_champions_crown).toBeFalsy()
				end
				expect(#welcome).toBe(1)
				expect(welcome[1].kind).toBe("arena")
				local card = h:LastEvent(p, "Rewards.Granted")
				expect(card.payload.source).toBe("arena_season")
				-- Paid once: another join (and an arena action) in season 2 pays nothing more.
				local after = h:System("Currency"):Balance(p, "gems")
				p = h:Rejoin(p, 3600)
				levelTo(h, p, 20)
				h:Call(p, "Arena.Refresh")
				expect(h:System("Currency"):Balance(p, "gems")).toBe(after)
				expect(#welcome).toBe(1)
			end)
		end

		it("still pays the gems and the cup when Mastery isn't loaded", function()
			local h, p, gems = playSeason("gold", BASE)
			expect(h:System("Currency"):Balance(p, "gems") - gems).toBe(200)
			expect(h:Section(p, "Shop").decor.arena_cup_gold).toBe(1)
			expect(h:Section(p, "Arena").seasonPaid).toBe(1)
		end)

		it("defines the titles, the aura, its Vfx and the unsold cups", function()
			for _, id in { "title_arena_silver", "title_arena_gold", "title_arena_crystal", "title_arena_champion" } do
				expect(Config.Mastery.ItemById[id].kind).toBe("title")
			end
			local aura = Config.Mastery.ItemById.aura_champions_crown
			expect(aura.kind).toBe("aura")
			expect(t.Shared("Config.Vfx").Mastery[aura.vfx] ~= nil).toBe(true)
			for _, id in { "arena_cup_gold", "arena_cup_crystal", "arena_cup_champion" } do
				local def = Config.Decor.ById[id]
				expect(def.price).toBe(nil)
				expect(def.model).toBe("cup")
			end
		end)

		it("migrates a version-1 save with the season fields", function()
			local Arena = t.Server("Systems.Arena")
			local old = { defense = {}, attempts = { day = 0, n = 0 }, week = 3, bestTier = "gold", lastTier = "", claimed = false }
			local migrated = Arena.Profile.Migrate(old, 1)
			expect(migrated.seasonOf).toBe(0)
			expect(migrated.seasonBest).toBe("")
			expect(migrated.seasonPaid).toBe(0)
			expect(migrated.bestTier).toBe("gold")
			expect(Arena.Profile.Version).toBe(2)
		end)
	end)

	describe("Season leaderboard", function()
		it("keys the arena board by season and leaves it out of the weekly boards", function()
			expect(Boards.Key("arena", 3)).toBe("arena_s3")
			expect(Boards.Key("heaviest", 3)).toBe("heaviest_w3")
			expect(Boards.ById.arena.period).toBe("season")
			for _, board in Boards.Weekly do
				expect(board.id ~= "arena").toBe(true)
			end
			expect(#Boards.Weekly).toBe(#Boards.Boards - 1)
		end)

		it("submits this season's rating to arena_s<N> and names no weekly champion for it", function()
			local net = MockAdapters.network()
			net.arena[6200] = record(6200, 1320, 1)
			local h = TestKernel.new({ systems = FULL, network = net, startTime = S1 + 3600 })
			local p = h:Join(6200, "Rated")
			expect(h:System("Leaderboards"):Value(p, "arena")).toBe(1320)
			h:Advance(Boards.GlobalRefresh)
			expect(h.adapters.boards["arena_s1"][6200]).toBe(1320)
			expect(h:Client(p).global.Leaderboards.global.arena[1].value).toBe(1320)
			expect(h:Client(p).global.Leaderboards.champions.arena).toBeFalsy()
			for _, id in h:System("Leaderboards"):Titles(6200) do
				expect(id ~= "arena").toBe(true)
			end
		end)

		it("has no season value before season 1", function()
			local net = MockAdapters.network()
			net.arena[6201] = record(6201, 1320, 0)
			local h = TestKernel.new({ systems = FULL, network = net })
			local p = h:Join(6201, "Early")
			expect(h:System("Leaderboards"):Value(p, "arena")).toBe(0)
			h:Advance(Boards.GlobalRefresh)
			expect(h.adapters.boards["arena_s0"]).toBe(nil)
		end)
	end)
end
