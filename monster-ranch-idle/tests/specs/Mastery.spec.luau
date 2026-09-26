-- 3.3 Mastery: Ranch Mastery from capped XP, Line Mastery, the Star Shard Constellation (rerolls,
-- cosmetics, perks), the Mythic Ladder, the mastery leaderboard and the appearance aura.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Mastery")
	local M = Config.Mastery

	local SEASON = Config.Quests.Seasons[#Config.Quests.Seasons]
	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Monetization", "Quests", "HallOfFame", "Leaderboards", "Mastery" }

	local function boot(startTime: number?)
		local h = TestKernel.new({ systems = SYSTEMS, startTime = startTime or (SEASON.startsAt + 3600) })
		local p = h:Join()
		return h, p
	end

	local function atCap(h, p)
		local s = h:Section(p, "Progression")
		s.level = Config.Unlocks.MaxLevelAt(h.adapters.Clock.Now())
		s.xp = 0
	end

	local function shards(h, p, n: number)
		h:Section(p, "HallOfFame").starShards = n
	end

	local function adult(h, p, line: string, traits)
		return h:System("Monsters"):Create(p, { line = line, rarity = 3, stage = 3, traits = traits or { 3, 4 }, hidden = 5 }, "test", true)
	end

	describe("Mastery rules", function()
		it("prices Ranch and Line Mastery with gently rising, uncapped costs", function()
			expect(Logic.RanchCost(0)).toBe(M.RanchBase)
			expect(Logic.RanchCost(10)).toBe(M.RanchBase + 10 * M.RanchStep)
			local level, xp, gained = Logic.AddRanchXP(0, 0, M.RanchBase + Logic.RanchCost(1) + 5)
			expect(level).toBe(2)
			expect(xp).toBe(5)
			expect(gained).toBe(2)
			expect(Logic.RanchCost(500) > Logic.RanchCost(499)).toBe(true)
			expect((Logic.LineLevel(0))).toBe(0)
			expect((Logic.LineLevel(M.LineBase))).toBe(1)
			local total = 0
			for l = 0, M.Tiers[3].level - 1 do
				total += Logic.LineCost(l)
			end
			expect(Logic.LineTier((Logic.LineLevel(total))).id).toBe("gold")
			expect(Logic.LineTier((Logic.LineLevel(total - 1))).id).toBe("silver")
			expect(Logic.TierIndex(0)).toBe(0)
		end)

		it("shows honest reroll odds and rolls from the hatch pool without duplicates", function()
			local record = { id = "m1", born = 5, traits = { 3, 4 }, hidden = 5 }
			local odds = Logic.RerollOdds(record, 1)
			local sum = 0
			for _, row in odds do
				sum += row.pct
				expect(row.id ~= 3 and row.id ~= 4 and row.id ~= 5).toBe(true)
				expect(Config.Traits.ById[row.id].hiddenOnly ~= true).toBe(true)
			end
			expect(sum).toBeNear(1)
			for done = 0, 20 do
				local seed = Logic.RerollSeed(42, record, done)
				local a = Logic.RerollTrait(record, 1, seed)
				expect(a).toBe(Logic.RerollTrait(record, 1, seed)) -- seeded: the same every time
				expect(a ~= 3 and a ~= 4 and a ~= 5).toBe(true)
			end
			expect(Logic.RerollTrait(record, 3, 1)).toBeNil()
			expect(Logic.RerollCost(0)).toBe(M.RerollCosts[1])
			expect(Logic.RerollCost(99)).toBe(M.RerollCosts[#M.RerollCosts])
		end)

		it("maps ladder points to tiers and knows when a season runs", function()
			expect(Logic.LadderPoints(M.LadderXP * 3, M.LadderLine * 2)).toBe(5)
			expect(Logic.LadderTier(0)).toBe(0)
			expect(Logic.LadderTier(M.Ladder[2].points)).toBe(2)
			expect(Logic.SeasonAt(SEASON.startsAt)).toBe(SEASON.season)
			expect(Logic.SeasonAt(SEASON.endsAt + 1)).toBe(0)
		end)

		it("keeps every item named, priced and translatable, and gives no battle stats", function()
			for _, item in M.Shop do
				expect(type(item.name) == "string" and type(item.desc) == "string").toBe(true)
				if item.kind == "perk" then
					expect(#item.costs).toBe(item.maxLevel)
					for key in item.effect do
						expect(key == "hatchSpeed" or key == "jarCapSeconds" or key == "lootPct").toBe(true)
					end
				else
					expect(type(item.cost)).toBe("number")
				end
			end
			for _, row in M.Ladder do
				for _, id in { row.item, row.item2 } do
					if id then
						expect(M.ItemById[id] ~= nil).toBe(true)
					end
				end
			end
		end)
	end)

	describe("Mastery system", function()
		it("banks capped Ranch XP as Ranch Mastery and pays Star Shards per level", function()
			local h, p = boot(SEASON.endsAt + 3600) -- between seasons: no ladder shards in the count
			atCap(h, p)
			h:System("Progression"):AddXP(p, M.RanchBase + 10, "test")
			local s = h:Section(p, "Mastery")
			expect(s.level).toBe(1)
			expect(s.xp).toBe(10)
			expect(s.total).toBe(M.RanchBase + 10)
			expect(h:Section(p, "Progression").xp).toBe(0)
			expect(h:Section(p, "HallOfFame").starShards).toBe(M.ShardsPerLevel)
			-- Below the cap nothing overflows.
			local h2, p2 = boot()
			h2:System("Progression"):AddXP(p2, 50, "test")
			expect(h2:Section(p2, "Mastery").total).toBe(0)
		end)

		it("pays the milestone every tenth Ranch Mastery level", function()
			local h, p = boot(SEASON.endsAt + 3600)
			local xp = 0
			for l = 0, M.MilestoneEvery - 1 do
				xp += Logic.RanchCost(l)
			end
			h:System("Mastery"):AddXP(p, xp, "test")
			expect(h:Section(p, "Mastery").level).toBe(M.MilestoneEvery)
			expect(h:Section(p, "HallOfFame").starShards).toBe(M.MilestoneEvery * M.ShardsPerLevel + M.MilestoneShards)
		end)

		it("earns Line Mastery from levelling, evolving, fights and retiring", function()
			local h, p = boot()
			local m = adult(h, p, "cindlet")
			local bus = h.kernel.Bus
			bus:Publish("MonsterLeveled", p, { id = m.id, lv = 2 })
			bus:Publish("MonsterEvolved", p, { id = m.id, stage = 3, form = m.form })
			local other = adult(h, p, "mossbun")
			bus:Publish("StageCleared", p, {
				region = Config.Regions.List[1].id,
				stage = 1,
				first = false,
				squad = { m.id, other.id, m.id },
			})
			bus:Publish("ArenaBattle", p, { won = false, rating = 1000, squad = { m.id } }) -- a loss counts nothing
			bus:Publish("RaidFinished", p, { raid = "x", win = true, squad = { other.id } })
			local lines = h:Section(p, "Mastery").lines
			local P = M.LinePoints
			expect(lines.cindlet).toBe(P.levelUp + P.evolve + P.fightWin)
			expect(lines.mossbun).toBe(2 * P.fightWin)
			h:System("Monsters"):Remove(p, m.id, "retire")
			expect(lines.cindlet).toBe(P.levelUp + P.evolve + P.fightWin + P.retireBase + P.retirePerRarity * 3)
			-- A sold monster is not a retirement.
			h:System("Monsters"):Remove(p, other.id, "sell")
			expect(lines.mossbun).toBe(2 * P.fightWin)
		end)

		it("rerolls a chosen slot for rising Star Shard costs, seeded and never a duplicate", function()
			local h, p = boot()
			local m = adult(h, p, "cindlet", { 3, 4 })
			expect(h:Reject(p, "Mastery.Reroll", { id = m.id, slot = 1 })).toBe("Not enough Star Shards")
			shards(h, p, 100)
			local expected = Logic.RerollTrait(m, 2, Logic.RerollSeed(p.UserId, m, 0))
			local data = h:Call(p, "Mastery.Reroll", { id = m.id, slot = 2 })
			expect(data.trait).toBe(expected)
			expect(data.cost).toBe(M.RerollCosts[1])
			expect(m.traits[1]).toBe(3)
			expect(m.traits[2]).toBe(expected)
			expect(m.traits[2] ~= 4 and m.traits[2] ~= 3 and m.traits[2] ~= 5).toBe(true)
			h:Advance(1)
			local second = h:Call(p, "Mastery.Reroll", { id = m.id, slot = 1 })
			expect(second.cost).toBe(M.RerollCosts[2])
			expect(second.rerolls).toBe(2)
			expect(h:Section(p, "HallOfFame").starShards).toBe(100 - M.RerollCosts[1] - M.RerollCosts[2])
			h:Advance(1)
			expect(h:Reject(p, "Mastery.Reroll", { id = m.id, slot = 3 })).toBe("That trait slot is empty")
			expect(h:Reject(p, "Mastery.Reroll", { id = "m999", slot = 1 })).toBe("That monster doesn't exist")
			h:System("Monsters"):SetBusy(p, m.id, "expedition")
			h:Advance(1)
			expect(string.find(h:Reject(p, "Mastery.Reroll", { id = m.id, slot = 1 }), "is busy", 1, true) ~= nil).toBe(true)
			h:System("Monsters"):SetBusy(p, m.id, false)
			h:System("Monsters"):Remove(p, m.id, "sell")
			expect(h:Section(p, "Mastery").rerolls[m.id]).toBeNil()
		end)

		it("buys, equips and takes off cosmetics, and caps perks", function()
			local h, p = boot()
			local aura = M.ShopById.aura_starlight
			expect(h:Reject(p, "Mastery.Buy", { item = aura.id })).toBe("Not enough Star Shards")
			shards(h, p, 200)
			h:Call(p, "Mastery.Buy", { item = aura.id })
			local s = h:Section(p, "Mastery")
			expect(s.owned[aura.id]).toBe(true)
			expect(s.equipped.aura).toBe(aura.id)
			h:Advance(1)
			expect(h:Reject(p, "Mastery.Buy", { item = aura.id })).toBe("You already own that")
			h:Call(p, "Mastery.Equip", { kind = "aura", item = "" })
			expect(s.equipped.aura).toBe(false)
			h:Advance(1)
			expect(h:Reject(p, "Mastery.Equip", { kind = "flourish", item = aura.id })).toBe("That item doesn't go there")
			expect(h:Reject(p, "Mastery.Equip", { kind = "title", item = "title_mythic" })).toBe("You don't own that yet")
			h:Call(p, "Mastery.Buy", { item = "flourish_crown" })
			expect(h.kernel.State:GlobalRoot("Mastery").here["u" .. p.UserId].flourish).toBe("flourish_crown")

			local perk = M.ShopById.perk_jar
			for level = 1, perk.maxLevel do
				h:Advance(1)
				expect(h:Call(p, "Mastery.Buy", { item = perk.id }).level).toBe(level)
			end
			h:Advance(1)
			expect(h:Reject(p, "Mastery.Buy", { item = perk.id })).toBe(perk.name .. " is already maxed")
			expect(h:System("Mastery"):PerkEffect(p, "jarCapSeconds")).toBe(perk.maxLevel * perk.effect.jarCapSeconds)
		end)

		it("grants each ladder tier once in a season and counts the week for the leaderboard", function()
			local h, p = boot()
			local Mastery = h:System("Mastery")
			Mastery:AddXP(p, M.Ladder[1].points * M.LadderXP, "test")
			local s = h:Section(p, "Mastery")
			expect(s.ladder.season).toBe(SEASON.season)
			expect(s.ladder.tier).toBe(1)
			local after1 = h:Section(p, "HallOfFame").starShards
			Mastery:AddLinePoints(p, "cindlet", (M.Ladder[2].points - M.Ladder[1].points) * M.LadderLine, "test")
			expect(s.ladder.tier).toBe(2)
			expect(s.owned[M.Ladder[2].item]).toBe(true)
			Mastery:AddXP(p, 1, "test") -- no tier is paid twice
			expect(s.ladder.tier).toBe(2)
			expect(h:Section(p, "HallOfFame").starShards >= after1).toBe(true)
			expect(Mastery:WeekPoints(p)).toBe(M.Ladder[2].points)
			expect((h:System("Leaderboards"):Value(p, "mastery"))).toBe(M.Ladder[2].points)
		end)

		it("keeps no ladder between seasons but still counts the week", function()
			local h, p = boot(SEASON.endsAt + 3600)
			h:System("Mastery"):AddXP(p, M.Ladder[3].points * M.LadderXP, "test")
			local s = h:Section(p, "Mastery")
			expect(s.ladder.season).toBe(0)
			expect(s.ladder.tier).toBe(0)
			expect(h:System("Mastery"):WeekPoints(p)).toBe(M.Ladder[3].points)
		end)

		it("puts the mastery aura on a Gold line's public appearance", function()
			local h, p = boot()
			local m = adult(h, p, "cindlet")
			expect(h:System("Monsters"):Appearance(p, m.id).aura).toBeNil()
			local points = 0
			for l = 0, M.Tiers[3].level - 1 do
				points += Logic.LineCost(l)
			end
			h:System("Mastery"):AddLinePoints(p, "cindlet", points, "test")
			expect(h:System("Monsters"):Appearance(p, m.id).aura).toBe("gold")
			shards(h, p, 100)
			h:Call(p, "Mastery.Buy", { item = "aura_comet" })
			expect(h:System("Monsters"):Appearance(p, m.id).aura).toBe("comet")
		end)

		it("fills a missing section on load", function()
			local h, p = boot()
			local s = h:Section(p, "Mastery")
			s.equipped = nil
			s.week = nil
			h:System("Mastery").Profile.Migrate(s, 0)
			expect(s.equipped.aura).toBe(false)
			expect(s.week.id).toBe(0)
		end)
	end)

	describe("Mastery client", function()
		local ClientHarness = t.ClientHarness

		local function allSystems()
			local list = {}
			for _, name in t.Server("Manifest").Systems do
				if name ~= "World" then
					table.insert(list, name)
				end
			end
			return list
		end

		it("shows the HUD entry at the cap, the three tabs, a badge and a reroll with odds", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = SEASON.startsAt + 3600 })
			local p = h:Join()
			local m = adult(h, p, "cindlet")
			local points = 0
			for l = 0, M.Tiers[3].level - 1 do
				points += Logic.LineCost(l)
			end
			h:System("Mastery"):AddLinePoints(p, "cindlet", points, "test")
			shards(h, p, 50)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local hud = c.playerGui
			local entry = hud:FindFirstChild("MasteryEntry", true)
			expect(entry ~= nil).toBe(true)
			expect(entry.Visible).toBe(true) -- a Gold line shows the entry before the cap

			local screen = c:Open("Mastery")
			c:Advance(1)
			expect(c:HasText("Gold Mastery", screen)).toBe(true)
			c:Click(c:Button("Ladder", screen))
			c:Advance(1)
			expect(c:HasText("Copper · 25 points", screen)).toBe(true)
			c:Click(c:Button("Star Shards", screen))
			c:Advance(1)
			expect(c:HasText("Choose a monster", screen)).toBe(true)

			local detail = c:Open("MonsterDetail", { id = m.id })
			c:Advance(1)
			expect(c:HasText("Gold Mastery", detail)).toBe(true)

			local data = h:Call(p, "Mastery.Reroll", { id = m.id, slot = 1 })
			expect(data.cost).toBe(M.RerollCosts[1])
			c:Advance(1)
			local problems = c:Problems()
			if #problems > 0 then
				error(table.concat(problems, "\n\n"))
			end
		end)
	end)
end
