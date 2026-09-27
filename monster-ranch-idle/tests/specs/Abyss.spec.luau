-- Sunken Abyss (R2-ABYSS, roadmap 4.1's own idea — Clockwork Canyon took that slot's code name
-- and its region-9 order, so this ships as region 10): its Egg, three Tide/Void lines, the raid's
-- phase2 darkness mechanic, unlock gating, Codex wiring and Config.Abyss itself (the descent point
-- and the walk-in area).
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local Config = t.Shared("Config")
	local EggRoll = t.Shared("Logic.EggRoll")
	local Rng = t.Shared("Logic.Rng")
	local BattleSim = t.Shared("Logic.BattleSim")
	local MonsterGen = t.Shared("Logic.MonsterGen")
	local CodexLogic = t.Shared("Logic.Codex")

	local REGION = Config.Regions.ById.abyss
	local LINES = { "gulperling", "wisplure", "pressurefin" }

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

	describe("Sunken Abyss region", function()
		it("is region 10, opens after Clockwork Canyon, and is gated by Ranch Level", function()
			expect(REGION.order).toBe(10)
			expect(REGION.unlock).toBe("region_abyss")
			expect(Config.Unlocks.Features.region_abyss).toBe(70)
			expect(Config.Unlocks.Features.region_abyss <= Config.Unlocks.MaxLevel).toBe(true)
			expect(Config.Unlocks.Names.region_abyss).toBe("Sunken Abyss")
			expect(os.date("!%A", REGION.opensAt)).toBe("Saturday")
			expect(os.date("!%H:%M", REGION.opensAt)).toBe("15:00")
			expect(REGION.opensAt > Config.Regions.ById.clockwork.opensAt).toBe(true)
			expect(Config.Regions.IsOpen(REGION, REGION.opensAt - 1)).toBe(false)
			expect(Config.Regions.IsOpen(REGION, REGION.opensAt)).toBe(true)
		end)

		it("has a level band above Clockwork Canyon and rewards in line with it, and a valid boss track", function()
			-- The +6 step every later region takes (sky->dunes->glacier->reef->clockwork all +6).
			expect(REGION.levels[1]).toBe(Config.Regions.ById.clockwork.levels[1] + 6)
			expect(REGION.levels[2]).toBe(Config.Regions.ById.clockwork.levels[2] + 6)
			expect(REGION.rarity[1]).toBe(Config.Regions.ById.clockwork.rarity[1])
			expect(REGION.rarity[2]).toBe(Config.Regions.ById.clockwork.rarity[2])
			expect(Config.Regions.Stages("abyss")).toBe(Config.Regions.StagesPerRegion)
			for stage, boss in REGION.bosses do
				expect(stage >= 1 and stage <= Config.Regions.StagesPerRegion).toBe(true)
				expect(Config.Species.ById[boss.line] ~= nil).toBe(true)
				expect(Config.Species.FormById[boss.form] ~= nil).toBe(true)
			end
			expect(REGION.bosses[20].firstClear[1].id).toBe("abyss")
			for _, line in REGION.enemyLines do
				expect(Config.Species.ById[line] ~= nil).toBe(true)
			end
			for _, egg in REGION.eggs do
				expect(Config.Eggs.ById[egg.egg] ~= nil).toBe(true)
				expect(egg.perMinute > 0).toBe(true)
			end
			expect(Config.Regions.GlobalIndex("abyss", 1)).toBe((REGION.order - 1) * Config.Regions.StagesPerRegion + 1)
		end)
	end)

	describe("Abyss Egg", function()
		it("hatches only Gulperling, Wisplure and Pressurefin", function()
			expect(Config.Eggs.ById.abyss.unlock).toBe("region_abyss")
			expect(Config.Eggs.ById.abyss.pool).toBe("abyss")
			expect(Config.Species.Pools.abyss).toEqual(LINES)
			local rng = Rng.new(51)
			local seen = {}
			for _ = 1, 300 do
				local spec = EggRoll.roll(rng, Config.Eggs.ById.abyss, {})
				expect(table.find(LINES, spec.line) ~= nil).toBe(true)
				seen[spec.line] = true
			end
			for _, line in LINES do
				expect(seen[line]).toBe(true)
			end
		end)
	end)

	describe("The three Tide/Void lines", function()
		it("carry Tide and/or Void, glow, swim, and have sane forms and stats", function()
			for _, id in LINES do
				local def = Config.Species.ById[id]
				expect(table.find(def.elements, "tide") ~= nil or table.find(def.elements, "void") ~= nil).toBe(true)
				expect(def.added).toBe("4.2")
				expect(def.swims).toBe(true)
				expect(def.glows).toBe(true)
				expect(#def.forms).toBe(3)
				expect(#def.forms[3]).toBe(1) -- no diet branch: exactly 9 forms across the three lines
				expect(def.base.hp > 0 and def.base.atk > 0 and def.base.def > 0 and def.base.spd > 0).toBe(true)
				expect(Config.Species.Skills[def.special] ~= nil).toBe(true)
				expect(Config.Species.Passives[def.passive] ~= nil).toBe(true)
			end
			expect(Config.Species.ById.pressurefin.elements).toEqual({ "tide", "void" })
			expect(Config.DeepReef.Swims("gulperling")).toBe(true) -- Config.Species.swims, not the old Swimmers table
			-- The Trench Maw (stage 10) and the Drowned Lantern (stage 20).
			expect(REGION.bosses[10].line).toBe("gulperling")
			expect(REGION.bosses[20].line).toBe("wisplure")
		end)
	end)

	describe("Codex", function()
		it("tracks the region and every new form, once the content is wired in", function()
			local milestone = CodexLogic.ById()["region_abyss"]
			expect(milestone ~= nil).toBe(true)
			local formSet = {}
			for _, f in milestone.forms do
				formSet[f] = true
			end
			for _, id in
				{
					"gulperling",
					"lurefang",
					"trenchmaw",
					"wisplure",
					"gloomlure",
					"voidlantern",
					"pressurefin",
					"carapacefin",
					"trenchcrown",
				}
			do
				expect(formSet[id]).toBe(true)
			end
		end)
	end)

	describe("Config.Abyss", function()
		it("shapes the descent, the area and the props sanely", function()
			expect(#Config.Abyss.Descent.offset).toBe(3)
			expect(#Config.Abyss.Area.center).toBe(3)
			expect(Config.Abyss.Area.radius > 0).toBe(true)
			expect(Config.Abyss.Area.floorY < Config.DeepReef.Area.floorY).toBe(true) -- deeper than the Reef
			for _, prop in Config.Abyss.Props do
				expect(#prop.size).toBe(3)
			end
		end)
	end)

	describe("The Trench Sovereign raid", function()
		local RAID = Config.Raids.ById.abyss

		it("opens after the Sunken Abyss, with a boss and adds drawn from real forms", function()
			expect(RAID.opensAt).toBe(REGION.opensAt)
			expect(Config.Raids.UnlockFor(RAID)).toBe("raid_abyss")
			expect(Config.Unlocks.Features.raid_abyss <= Config.Unlocks.MaxLevel).toBe(true)
			expect(Config.Species.ById[RAID.boss.line] ~= nil).toBe(true)
			expect(Config.Species.FormById[RAID.boss.form] ~= nil).toBe(true)
			expect(RAID.boss.phase2.hpThreshold > 0 and RAID.boss.phase2.hpThreshold < 1).toBe(true)
			expect(RAID.boss.phase2.accuracyPenalty > 0).toBe(true)
			expect(#RAID.adds).toBe(2)
		end)

		it("goes dark past half HP: allies miss far more often once phase2 flips, unless a glowing monster is in the squad", function()
			-- A low statMult keeps the boss's own ATK/DEF from overwhelming the squad (this is a
			-- mechanic proof, not a balance pass); a much larger hpMult keeps its HP pool the same
			-- size, so the fight takes long enough to cross the switch with turns on both sides.
			local function boss()
				return mon("pressurefin", "trenchcrown", {
					rarity = 6,
					stars = 5,
					lv = 64,
					statMult = 0.3,
					hpMult = 27,
					boss = true,
					phase2 = { hpThreshold = 0.5, accuracyPenalty = 0.4 },
				})
			end
			local function noGlowAllies()
				local list = {}
				for _ = 1, 5 do
					table.insert(list, mon("scorchmoth", nil, { rarity = 6, stars = 5, lv = 90, statMult = 1.6 }))
				end
				return list
			end
			local function glowAllies()
				local list = noGlowAllies()
				list[1] = mon("gulperling", "trenchmaw", { rarity = 6, stars = 5, lv = 90, statMult = 1.6 })
				return list
			end
			expect(Config.Species.ById.scorchmoth.glows ~= true).toBe(true)
			expect(Config.Species.ById.gulperling.glows).toBe(true)

			-- Miss-rate (a share, duration-independent) of every ally attack attempt, split by
			-- whether it landed before or after the fight's own "phase2" event turn.
			local function missShares(alliesFn)
				local missBefore, totalBefore, missAfter, totalAfter = 0, 0, 0, 0
				for seed = 1, 16 do
					local replay = BattleSim.Simulate(alliesFn(), { boss() }, seed, { maxTurns = 60 })
					local switchTurn = nil
					for _, e in replay.events do
						if e.kind == "phase2" then
							switchTurn = e.turn
							break
						end
					end
					if switchTurn then
						for _, e in replay.events do
							if
								e.actor
								and string.sub(e.actor, 1, 1) == "a"
								and e.target
								and (e.kind == "hit" or e.kind == "crit" or e.kind == "special" or e.kind == "miss")
							then
								if e.turn <= switchTurn then
									totalBefore += 1
									if e.kind == "miss" then
										missBefore += 1
									end
								else
									totalAfter += 1
									if e.kind == "miss" then
										missAfter += 1
									end
								end
							end
						end
					end
				end
				expect(totalBefore > 0 and totalAfter > 0).toBe(true) -- the fight crossed the switch with turns to spare, both sides
				return missBefore / totalBefore, missAfter / totalAfter
			end

			local darkBefore, darkAfter = missShares(noGlowAllies)
			expect(darkBefore < 0.05).toBe(true) -- no darkness yet: essentially never misses
			expect(darkAfter > 0.25).toBe(true) -- the lights are out: misses close to the 40% penalty
			expect(darkAfter > darkBefore * 4).toBe(true)

			local litBefore, litAfter = missShares(glowAllies)
			expect(litBefore < 0.05).toBe(true)
			expect(litAfter < 0.05).toBe(true) -- a glowing monster in the squad: the switch changes nothing
		end)
	end)
end
