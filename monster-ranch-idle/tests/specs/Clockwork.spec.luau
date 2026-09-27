-- Clockwork Canyon (R2-CLOCKWORK, roadmap 4.1): the region the 3.4 plan never shipped (the Deep
-- Reef took region slot 8), its Egg, three Spark/Stone lines, the raid's gear mechanic, unlock
-- gating and Codex wiring, and Config.Clockwork itself (the landmark and the walk-in area).
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local Config = t.Shared("Config")
	local EggRoll = t.Shared("Logic.EggRoll")
	local Rng = t.Shared("Logic.Rng")
	local BattleSim = t.Shared("Logic.BattleSim")
	local MonsterGen = t.Shared("Logic.MonsterGen")
	local CodexLogic = t.Shared("Logic.Codex")

	local REGION = Config.Regions.ById.clockwork
	local LINES = { "cogling", "gritcog", "brassling" }

	local function mon(line: string, form: string?, overrides: { [string]: any }?)
		local record = MonsterGen.New(Rng.new(7), { line = line, rarity = 1, stage = 3, traits = {}, hidden = 0, variant = 0 }, 0)
		record.lv = 10
		if form then
			record.form = form
		end
		for k, v in overrides or {} do
			record[k] = v
		end
		return record
	end

	describe("Clockwork Canyon region", function()
		it("is region 9, opens after the Deep Reef, and is gated by Ranch Level", function()
			expect(REGION.order).toBe(9)
			expect(REGION.unlock).toBe("region_clockwork")
			expect(Config.Unlocks.Features.region_clockwork).toBe(68)
			expect(Config.Unlocks.Features.region_clockwork <= Config.Unlocks.MaxLevel).toBe(true)
			expect(Config.Unlocks.Names.region_clockwork).toBe("Clockwork Canyon")
			expect(os.date("!%A", REGION.opensAt)).toBe("Saturday")
			expect(os.date("!%H:%M", REGION.opensAt)).toBe("15:00")
			expect(REGION.opensAt > Config.Regions.ById.reef.opensAt).toBe(true)
			expect(Config.Regions.IsOpen(REGION, REGION.opensAt - 1)).toBe(false)
			expect(Config.Regions.IsOpen(REGION, REGION.opensAt)).toBe(true)
		end)

		it("has a level band above the Deep Reef and rewards in line with it, and a valid boss track", function()
			-- The +6 step every later region takes (sky->dunes->glacier->reef all +6; see report).
			expect(REGION.levels[1]).toBe(Config.Regions.ById.reef.levels[1] + 6)
			expect(REGION.levels[2]).toBe(Config.Regions.ById.reef.levels[2] + 6)
			expect(REGION.rarity[1]).toBe(Config.Regions.ById.reef.rarity[1])
			expect(REGION.rarity[2]).toBe(Config.Regions.ById.reef.rarity[2])
			expect(Config.Regions.Stages("clockwork")).toBe(Config.Regions.StagesPerRegion)
			for stage, boss in REGION.bosses do
				expect(stage >= 1 and stage <= Config.Regions.StagesPerRegion).toBe(true)
				expect(Config.Species.ById[boss.line] ~= nil).toBe(true)
				expect(Config.Species.FormById[boss.form] ~= nil).toBe(true)
			end
			expect(REGION.bosses[20].firstClear[1].id).toBe("clockwork") -- like reef/glacier/dunes' stage-20 boss
			for _, line in REGION.enemyLines do
				expect(Config.Species.ById[line] ~= nil).toBe(true)
			end
			for _, egg in REGION.eggs do
				expect(Config.Eggs.ById[egg.egg] ~= nil).toBe(true)
				expect(egg.perMinute > 0).toBe(true)
			end
			-- The Global Index continues cleanly on from every earlier region (Regions.GlobalIndex).
			expect(Config.Regions.GlobalIndex("clockwork", 1)).toBe((REGION.order - 1) * Config.Regions.StagesPerRegion + 1)
		end)
	end)

	describe("Clockwork Egg", function()
		it("hatches only Cogling, Gritcog and Brassling", function()
			expect(Config.Eggs.ById.clockwork.unlock).toBe("region_clockwork")
			expect(Config.Eggs.ById.clockwork.pool).toBe("clockwork")
			expect(Config.Species.Pools.clockwork).toEqual(LINES)
			local rng = Rng.new(51)
			local seen = {}
			for _ = 1, 300 do
				local spec = EggRoll.roll(rng, Config.Eggs.ById.clockwork, {})
				expect(table.find(LINES, spec.line) ~= nil).toBe(true)
				seen[spec.line] = true
			end
			for _, line in LINES do
				expect(seen[line]).toBe(true)
			end
		end)
	end)

	describe("The three Spark/Stone lines", function()
		it("carry Spark and/or Stone, and have sane forms and stats", function()
			for _, id in LINES do
				local def = Config.Species.ById[id]
				expect(table.find(def.elements, "spark") ~= nil or table.find(def.elements, "stone") ~= nil).toBe(true)
				expect(def.added).toBe("4.1")
				expect(#def.forms).toBe(3)
				expect(#def.forms[3]).toBe(1) -- no diet branch: exactly 9 forms across the three lines
				expect(def.base.hp > 0 and def.base.atk > 0 and def.base.def > 0 and def.base.spd > 0).toBe(true)
				expect(Config.Species.Skills[def.special] ~= nil).toBe(true)
				expect(Config.Species.Passives[def.passive] ~= nil).toBe(true)
			end
			expect(Config.Species.ById.brassling.elements).toEqual({ "spark", "stone" })
			-- The Gearwarden (stage 10) and the Sparking Sovereign (stage 20).
			expect(REGION.bosses[10].line).toBe("gritcog")
			expect(REGION.bosses[20].line).toBe("cogling")
		end)
	end)

	describe("Codex", function()
		it("tracks the region and every new form, once the content is wired in", function()
			local milestone = CodexLogic.ById()["region_clockwork"]
			expect(milestone ~= nil).toBe(true)
			local formSet = {}
			for _, f in milestone.forms do
				formSet[f] = true
			end
			for _, id in { "cogling", "gearwing", "dynamowasp", "gritcog", "flywheel", "geartitan", "brassling", "clockfox", "brassrunner" } do
				expect(formSet[id]).toBe(true)
			end
		end)
	end)

	describe("Config.Clockwork", function()
		it("shapes the landmark, the area and the gears sanely", function()
			expect(#Config.Clockwork.Landmark.position).toBe(3)
			expect(#Config.Clockwork.Area.center).toBe(3)
			expect(Config.Clockwork.Area.radius > 0).toBe(true)
			expect(Config.Clockwork.Gears.towerSpeed > 0).toBe(true)
			expect(Config.Clockwork.Gears.groundSpeedMax >= Config.Clockwork.Gears.groundSpeedMin).toBe(true)
			for _, prop in Config.Clockwork.Props do
				expect(#prop.size).toBe(3)
			end
		end)
	end)

	describe("The Clockwork Sovereign raid", function()
		local RAID = Config.Raids.ById.clockwork

		it("opens after Clockwork Canyon, with a boss and adds drawn from real forms", function()
			expect(RAID.opensAt).toBe(REGION.opensAt)
			expect(Config.Raids.UnlockFor(RAID)).toBe("raid_clockwork")
			expect(Config.Unlocks.Features.raid_clockwork <= Config.Unlocks.MaxLevel).toBe(true)
			expect(Config.Species.ById[RAID.boss.line] ~= nil).toBe(true)
			expect(Config.Species.FormById[RAID.boss.form] ~= nil).toBe(true)
			expect(#RAID.adds).toBe(3)
			for _, add in RAID.adds do
				expect(add.line).toBe("gritcog") -- the three gears
				expect(Config.Species.ById[add.line].special).toBe("taunt")
			end
		end)

		it("breaks the gears in order: the boss (e1) takes far less damage than a boss with no taunting guards", function()
			-- A strong, identical squad against two enemy line-ups that only differ in whether the
			-- guards taunt (the real Config.Species "taunt" special vs a "strike" control): proves
			-- the mechanic comes from that field, and that BattleSim.pickTarget's taunt check (it
			-- returns the first living taunter in list order) is what funnels the damage.
			local function allies()
				return {
					mon("brassling", "brassrunner", { rarity = 6, stars = 5, lv = 90, statMult = 1.6 }),
					mon("brassling", "brassrunner", { rarity = 6, stars = 5, lv = 90, statMult = 1.6 }),
					mon("brassling", "brassrunner", { rarity = 6, stars = 5, lv = 90, statMult = 1.6 }),
					mon("brassling", "brassrunner", { rarity = 6, stars = 5, lv = 90, statMult = 1.6 }),
					mon("brassling", "brassrunner", { rarity = 6, stars = 5, lv = 90, statMult = 1.6 }),
				}
			end
			local function boss()
				return mon("cogling", "dynamowasp", { rarity = 6, stars = 5, lv = 60, statMult = 1, hpMult = 4, boss = true })
			end
			local function realGears()
				return {
					mon("gritcog", "geartitan", { rarity = 5, stars = 4, lv = 54, statMult = 1 }),
					mon("gritcog", "geartitan", { rarity = 5, stars = 4, lv = 54, statMult = 1 }),
					mon("gritcog", "geartitan", { rarity = 5, stars = 4, lv = 54, statMult = 1 }),
				}
			end
			-- A control line-up: the same stats, but a line whose special is not "taunt".
			local function controlGears()
				return {
					mon("scorchmoth", nil, { rarity = 5, stars = 4, lv = 54, statMult = 1 }),
					mon("scorchmoth", nil, { rarity = 5, stars = 4, lv = 54, statMult = 1 }),
					mon("scorchmoth", nil, { rarity = 5, stars = 4, lv = 54, statMult = 1 }),
				}
			end
			expect(Config.Species.ById.scorchmoth.special ~= "taunt").toBe(true)

			-- What share of every ally hit lands on the boss rather than a guard: a rate, so it
			-- is duration-independent (a cumulative-damage or "HP left when guards fall" total
			-- instead would favour whichever guard is tankier regardless of targeting, since a
			-- longer fight just gives more turns for stray hits either way).
			local function bossShareOfHits(gearsFn): number
				local bossHits, total = 0, 0
				for seed = 1, 12 do
					local replay = BattleSim.Simulate(allies(), { boss(), gearsFn()[1], gearsFn()[2], gearsFn()[3] }, seed)
					for _, e in replay.events do
						if e.actor and string.sub(e.actor, 1, 1) == "a" and e.target and e.amount and e.amount > 0 then
							total += 1
							if e.target == "e1" then
								bossHits += 1
							end
						end
					end
				end
				return bossHits / total
			end

			local realShare = bossShareOfHits(realGears)
			local controlShare = bossShareOfHits(controlGears)
			expect(controlShare > 0.5).toBe(true) -- no taunt: the boss (list[1], the "front") takes over half the hits
			expect(realShare < controlShare * 0.5).toBe(true) -- taunting guards cut the boss's share by more than half
			expect(realShare < 0.35).toBe(true)
		end)
	end)
end
