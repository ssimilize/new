-- Update 3.2 · Frostbite Glacier + Level 70, raid 3: the Frost Leviathan (date- and
-- level-gated), its own raid-only line from the Leviathan Egg, and the 3.2 content pack
-- (Ranch Pass Season 8, the FROSTBITE code, two achievements).
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, MockAdapters = t.TestKernel, t.MockAdapters
	local Config = t.Shared("Config")
	local Format = t.Shared("Logic.Format")
	local BattleSim = t.Shared("Logic.BattleSim")
	local EggRoll = t.Shared("Logic.EggRoll")
	local Rng = t.Shared("Logic.Rng")
	local R = Config.Raids
	local LEV = R.ById.leviathan
	local Q = Config.Quests

	local OPENS = LEV.opensAt
	local AFTER = OPENS + 3600
	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Quests", "Raids" }

	-- The team that beats the Umbral Wyrm, and one that counters Tide/Light (Void and Sprout
	-- attackers). Four players bring two each, in this order.
	local WYRM_TEAM = { "wyrmlet", "titanling" }
	local COUNTER_TEAM = { "nullkit", "hollowisp", "thornbolt", "pollenpuff" }

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function adults(h, p, lines)
		local ids = {}
		for _, line in lines do
			local m = h:System("Monsters"):Create(p, { line = line, rarity = 6, stage = 3 }, "test", true)
			m.lv, m.stars = 60, 5
			table.insert(ids, m.id)
		end
		return ids
	end

	-- Four raiders at `level`, each with two maxed Mythics from `lines` (cycled).
	local function party(h, level: number, lines)
		local players = {}
		for i = 1, 4 do
			local p = h:Join(8000 + i, "Diver" .. i)
			levelTo(h, p, level)
			local mine = { lines[(2 * i - 2) % #lines + 1], lines[(2 * i - 1) % #lines + 1] }
			players[i] = { p = p, ids = adults(h, p, mine) }
		end
		return players
	end

	local function eggCount(h, p, eggId: string): number
		local n = 0
		for _, e in h:Section(p, "Eggs").list do
			if e.type == eggId then
				n += 1
			end
		end
		return n
	end

	-- A BattleSim record of a maxed Mythic (or a raid monster spec).
	local function record(spec)
		local def = Config.Species.ById[spec.line]
		return {
			line = spec.line,
			stage = 3,
			form = Config.Species.Form(spec.line, 3, spec.form).id,
			rarity = spec.rarity or 6,
			variant = 0,
			muts = {},
			traits = {},
			hidden = 0,
			weight = def.weight,
			lv = spec.level or 60,
			stars = spec.stars or 5,
			mood = 100,
			name = "",
			statMult = spec.statMult,
			hpMult = spec.hpMult,
			boss = spec.boss,
		}
	end

	local function fight(lines, raid, seed: number)
		local allies = {}
		for i = 1, R.MaxPlayers * R.PerPlayer do
			table.insert(allies, record({ line = lines[(i - 1) % #lines + 1] }))
		end
		local boss = table.clone(raid.boss)
		boss.boss = true
		local enemies = { record(boss) }
		for _, add in raid.adds do
			table.insert(enemies, record(add))
		end
		return BattleSim.Simulate(allies, enemies, seed, { boss = true, maxAllies = R.MaxPlayers * R.PerPlayer, maxTurns = R.MaxTurns })
	end

	describe("Frost Leviathan", function()
		it("is raid 3: opens with the glacier, Level 60, and pays the Leviathan Egg", function()
			expect(LEV.order).toBe(3)
			expect(R.List[3].id).toBe("leviathan")
			expect(OPENS).toBe(Config.Regions.ById.glacier.opensAt)
			expect(Format.date(OPENS)).toBe("11 Mar 2028")
			expect(LEV.unlock).toBe("raid_leviathan")
			expect(Config.Unlocks.Features.raid_leviathan).toBe(60)
			expect(Config.Unlocks.Names.raid_leviathan).toBe("Frost Leviathan raid")
			expect(R.UnlockFor("leviathan")).toBe("raid_leviathan")
			expect(R.UnlockFor("titan")).toBe(R.Unlock)
			expect(R.IsOpen("titan", 0)).toBe(true)
			expect(R.IsOpen(LEV, OPENS - 1)).toBe(false)
			expect(R.IsOpen(LEV, OPENS)).toBe(true)
			expect(Config.Species.FormById[LEV.boss.form].line.id).toBe("floelet")
			for _, add in LEV.adds do
				expect(table.find(Config.Species.ById[add.line].pools, "glacier") ~= nil).toBe(true)
			end
			expect(LEV.reward[1].kind).toBe("egg")
			expect(LEV.reward[1].id).toBe("leviathan")
			expect(LEV.reward[1].amount).toBe(1)
			expect(LEV.reward[2].kind).toBe("gems")
			expect(LEV.reward[2].amount).toBe(60)

			local egg = Config.Eggs.ById.leviathan
			expect(egg.price).toBeNil()
			expect(egg.pool).toBe("leviathan")
			expect(egg.unlock).toBe("raid_leviathan")
			-- At least as generous as the Raid Egg at every rarity threshold.
			local raidEgg = Config.Eggs.ById.raid
			local mine, theirs = 0, 0
			for r = #egg.odds, 1, -1 do
				mine += egg.odds[r]
				theirs += raidEgg.odds[r]
				expect(mine >= theirs).toBe(true)
			end

			local line = Config.Species.ById.floelet
			expect(line.raid).toBe(true)
			expect(line.added).toBe("3.2")
			expect(line.elements).toEqual({ "tide", "light" })
			expect(line.forms[1].id).toBe("floelet")
			expect(line.forms[2].id).toBe("rimecoil")
			expect(line.forms[3][1].id).toBe("frostleviathan")
			expect(line.pools).toEqual({ "leviathan" })
		end)

		it("stays closed until 11 Mar 2028 while the other raids stay open", function()
			local h = TestKernel.new({ systems = SYSTEMS, startTime = OPENS - 3600 })
			local team = party(h, 60, COUNTER_TEAM)
			local host = team[1]
			expect(h:Reject(host.p, "Raids.Open", { raid = "leviathan", ids = host.ids })).toBe("Frost Leviathan opens on 11 Mar 2028")
			local titan = h:Call(host.p, "Raids.Open", { raid = "titan", ids = host.ids }).lobby
			h:Advance(2)
			h:Call(host.p, "Raids.Leave")
			expect(h:Client(host.p).global.Raids.lobbies[titan]).toBeNil()

			h.adapters.setTime(AFTER)
			h:Advance(2)
			local lobby = h:Call(host.p, "Raids.Open", { raid = "leviathan", ids = host.ids }).lobby
			expect(h:Client(team[2].p).global.Raids.lobbies[lobby].raid).toBe("leviathan")
		end)

		it("needs Ranch Level 60 to host or join", function()
			local h = TestKernel.new({ systems = SYSTEMS, startTime = AFTER })
			local low = h:Join(8101, "Low")
			levelTo(h, low, 30)
			local lowIds = adults(h, low, { "nullkit", "hollowisp" })
			expect(h:Reject(low, "Raids.Open", { raid = "leviathan", ids = lowIds })).toBe("Unlocks at Ranch Level 60")
			-- Level 30 still hosts the Titan.
			h:Call(low, "Raids.Open", { raid = "titan", ids = lowIds })
			h:Advance(2)
			h:Call(low, "Raids.Leave")
			h:Advance(2)

			local host = h:Join(8102, "High")
			levelTo(h, host, 60)
			local lobby = h:Call(host, "Raids.Open", { raid = "leviathan", ids = adults(h, host, { "nullkit" }) }).lobby
			expect(h:Reject(low, "Raids.Join", { lobby = lobby, ids = lowIds })).toBe("Unlocks at Ranch Level 60")
			expect(#h:Client(host).global.Raids.lobbies[lobby].members).toBe(1)
			levelTo(h, low, 60)
			h:Advance(2)
			expect(h:Call(low, "Raids.Join", { lobby = lobby, ids = lowIds }).members).toBe(2)
		end)

		it("falls to four players and pays the Leviathan Egg within the shared daily cap", function()
			local h = TestKernel.new({ systems = SYSTEMS, startTime = AFTER })
			local team = party(h, 60, COUNTER_TEAM)
			local day = math.floor(AFTER / 86400)
			-- Raider 2 already won three raids today; raider 3 won two.
			local s2, s3 = h:Section(team[2].p, "Raids"), h:Section(team[3].p, "Raids")
			s2.day, s2.rewarded = day, R.DailyRewards
			s3.day, s3.rewarded = day, R.DailyRewards - 1
			local gems0 = {}
			for i, member in team do
				gems0[i] = h:Section(member.p, "Currency").gems
			end

			local lobby = h:Call(team[1].p, "Raids.Open", { raid = "leviathan", ids = team[1].ids }).lobby
			for i = 2, 4 do
				h:Call(team[i].p, "Raids.Join", { lobby = lobby, ids = team[i].ids })
			end
			expect(h:Call(team[1].p, "Raids.Launch").win).toBe(true)

			for i, member in team do
				local event = h:LastEvent(member.p, "Raids.Result").payload
				expect(event.raid).toBe("leviathan")
				expect(event.win).toBe(true)
				expect(#event.replay.units).toBe(8 + 1 + #LEV.adds)
				local paid = i ~= 2
				expect(eggCount(h, member.p, "leviathan")).toBe(if paid then 1 else 0)
				expect(eggCount(h, member.p, "raid")).toBe(0)
				expect(h:Section(member.p, "Currency").gems - gems0[i]).toBe(if paid then 60 else 0)
				expect(h:Section(member.p, "Raids").rewarded).toBe(if i == 1 or i == 4 then 1 else R.DailyRewards)
				expect(h:Section(member.p, "Quests").achievements.raid_leviathan.progress).toBe(1)
				expect(h:Section(member.p, "Quests").achievements.raid_win.progress).toBe(1)
			end
			expect(h:LastEvent(team[2].p, "Raids.Result").payload.rewards[1].kind).toBe("coins")
			-- Raider 3 is now at the cap too: the next win pays the consolation.
			h:Advance(2)
			lobby = h:Call(team[3].p, "Raids.Open", { raid = "leviathan", ids = team[3].ids }).lobby
			for _, i in { 1, 2, 4 } do
				h:Call(team[i].p, "Raids.Join", { lobby = lobby, ids = team[i].ids })
			end
			expect(h:Call(team[3].p, "Raids.Launch").win).toBe(true)
			expect(eggCount(h, team[3].p, "leviathan")).toBe(1)
			expect(eggCount(h, team[1].p, "leviathan")).toBe(2)
		end)

		it("is strictly harder than the Umbral Wyrm: the Wyrm team loses, a Tide/Light counter wins", function()
			local Elements = Config.Elements
			for _, line in COUNTER_TEAM do
				expect(Elements.MultiplierMulti(Config.Species.ById[line].elements, { "tide", "light" })).toBe(Elements.Advantage)
			end
			for seed = 1, 12 do
				local s = seed * 7919
				expect(fight(WYRM_TEAM, R.ById.wyrm, s).win).toBe(true)
				expect(fight(WYRM_TEAM, LEV, s).win).toBe(false)
				expect(fight(COUNTER_TEAM, LEV, s).win).toBe(true)
			end
			-- The counter team beats the Wyrm faster than the Leviathan: it is the harder raid.
			expect(fight(COUNTER_TEAM, R.ById.wyrm, 1).turns < fight(COUNTER_TEAM, LEV, 1).turns).toBe(true)
		end)

		it("hatches the Floelet line only from the Leviathan Egg", function()
			local rng = Rng.new(32)
			local rarities = {}
			for _ = 1, 300 do
				local spec = EggRoll.roll(rng, Config.Eggs.ById.leviathan, {})
				expect(spec.line).toBe("floelet")
				rarities[spec.rarity] = true
			end
			expect(rarities[1] or rarities[2]).toBeFalsy() -- Rare or better, like the Raid Egg
			expect(Config.Species.Pools.leviathan).toEqual({ "floelet" })
			for _ = 1, 300 do
				expect(EggRoll.roll(rng, Config.Eggs.ById.raid, {}).line ~= "floelet").toBe(true)
			end
			for _, egg in Config.Eggs.List do
				if egg.id ~= "leviathan" then
					expect(egg.pool ~= "leviathan").toBe(true)
					expect(table.find(Config.Species.Pools[egg.pool] or {}, "floelet")).toBeNil()
				end
			end
			for pool, lines in Config.Species.Pools do
				if pool ~= "leviathan" then
					expect(table.find(lines, "floelet")).toBeNil()
				end
			end
		end)
	end)

	describe("3.2 content pack", function()
		it("runs Ranch Pass Season 8 from 4 Mar 2028 and claims a tier", function()
			local s7, s8 = Q.Seasons[7], Q.Seasons[8]
			expect(s8.season).toBe(8)
			expect(s8.name).toBe("Frostbite")
			expect(s8.startsAt).toBe(s7.endsAt)
			expect(Format.date(s8.startsAt)).toBe("4 Mar 2028")
			expect(s8.endsAt - s8.startsAt).toBe(42 * 86400)
			expect(Q.PassAt(s8.startsAt - 1).season).toBe(7)
			expect(Q.PassAt(s8.startsAt).season).toBe(8)
			local glacier, leviathan = 0, 0
			for _, tier in s8.tiers do
				for _, track in { tier.free, tier.premium } do
					for _, reward in track do
						if reward.kind == "egg" then
							expect(Config.Eggs.ById[reward.id] ~= nil).toBe(true)
							if reward.id == "glacier" then
								glacier += reward.amount
							end
						elseif reward.kind == "monster" then
							expect(Config.Species.ById[reward.id] ~= nil).toBe(true)
						end
					end
				end
				for _, reward in tier.premium do
					if reward.kind == "egg" and reward.id == "leviathan" then
						leviathan += reward.amount
					end
				end
				for _, reward in tier.free do
					expect(reward.kind == "egg" and reward.id == "leviathan").toBe(false)
				end
			end
			expect(glacier >= 4).toBe(true)
			expect(leviathan >= 1 and leviathan <= 2).toBe(true)
			local top = s8.tiers[#s8.tiers].premium[1]
			expect(top.kind).toBe("monster")
			expect(top.id).toBe("pengling")
			expect(top.rarity).toBe(5)

			local h = TestKernel.new({ systems = SYSTEMS, startTime = s8.startsAt + 3600 })
			local p = h:Join()
			local pass = h:Section(p, "Quests").pass
			expect(pass.season).toBe(8)
			pass.xp = s8.xpPerTier
			local coins0 = h:Section(p, "Currency").coins
			local data = h:Call(p, "Quests.ClaimPass", { tier = 1, track = "free" })
			expect(data.rewards[1].kind).toBe("coins")
			expect(h:Section(p, "Currency").coins - coins0).toBe(s8.tiers[1].free[1].amount)
		end)

		it("redeems FROSTBITE for a Glacier Egg and 50 gems until 1 Apr 2028", function()
			local code = Q.Codes.FROSTBITE
			expect(os.date("!%d %b %Y %H:%M", code.expires)).toBe("01 Apr 2028 15:00")
			local h = TestKernel.new({ systems = SYSTEMS, startTime = AFTER })
			local p = h:Join()
			local gems0 = h:Section(p, "Currency").gems
			h:Call(p, "Quests.Redeem", { code = "frostbite" })
			expect(eggCount(h, p, "glacier")).toBe(1)
			expect(h:Section(p, "Currency").gems - gems0).toBe(50)
			h:Advance(2)
			expect(h:Reject(p, "Quests.Redeem", { code = "FROSTBITE" })).toBe("You already used that code")
			h.adapters.setTime(code.expires)
			local late = h:Join()
			expect(h:Reject(late, "Quests.Redeem", { code = "FROSTBITE" })).toBe("That code has expired")
		end)

		it("adds Defeat the Frost Leviathan and Clear the Frostbite Glacier", function()
			local byId = {}
			for _, a in Q.Achievements do
				byId[a.id] = a
			end
			expect(byId.raid_leviathan.filter.raid).toBe("leviathan")
			expect(byId.raid_leviathan.topic).toBe("RaidFinished")
			expect(byId.clear_glacier.filter.region).toBe("glacier")
			expect(byId.clear_glacier.filter.stage).toBe(Config.Regions.StagesPerRegion)
			local h = TestKernel.new({ systems = SYSTEMS, startTime = AFTER })
			local p = h:Join()
			h.kernel.Bus:Publish("RaidFinished", p, { raid = "wyrm", win = true })
			h.kernel.Bus:Publish("RaidFinished", p, { raid = "leviathan", win = false })
			h.kernel.Bus:Publish("StageCleared", p, { region = "glacier", stage = 19 })
			local a = h:Section(p, "Quests").achievements
			expect(a.raid_leviathan == nil or a.raid_leviathan.progress == 0).toBe(true)
			expect(a.clear_glacier == nil or a.clear_glacier.progress == 0).toBe(true)
			h.kernel.Bus:Publish("RaidFinished", p, { raid = "leviathan", win = true })
			h.kernel.Bus:Publish("StageCleared", p, { region = "glacier", stage = 20 })
			expect(a.raid_leviathan.progress).toBe(1)
			expect(a.clear_glacier.progress).toBe(1)
			local gems0 = h:Section(p, "Currency").gems
			h:Call(p, "Quests.ClaimAchievement", { id = "raid_leviathan" })
			expect(eggCount(h, p, "leviathan")).toBe(1)
			expect(h:Section(p, "Currency").gems - gems0).toBe(100)
		end)

		it("counts a Leviathan win as a raid win for Club Wars", function()
			local net = MockAdapters.network()
			local systems = table.clone(SYSTEMS)
			for _, name in { "Accessories", "Workshop", "Clubs" } do
				table.insert(systems, name)
			end
			local h = TestKernel.new({ systems = systems, network = net, startTime = AFTER })
			local team = party(h, 60, COUNTER_TEAM)
			local host = team[1]
			h:System("Currency"):Add(host.p, "coins", 1e6, "test")
			local clubId = h:Call(host.p, "Clubs.Create", { name = "Club ICE", tag = "ICE", color = 2, emblem = "moon", open = true }).id
			h:Advance(2)
			local lobby = h:Call(host.p, "Raids.Open", { raid = "leviathan", ids = host.ids }).lobby
			for i = 2, 4 do
				h:Call(team[i].p, "Raids.Join", { lobby = lobby, ids = team[i].ids })
			end
			expect(h:Call(host.p, "Raids.Launch").win).toBe(true)
			h:System("Clubs"):Flush()
			local points = 0
			for _, rule in Config.Clubs.War.sources do
				if rule.id == "raid" then
					points = rule.points
				end
			end
			expect(points > 0).toBe(true)
			expect(net.clubs[clubId].members["u" .. host.p.UserId].war).toBe(points)
		end)
	end)
end
