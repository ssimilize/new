-- S4: Logic/BattleSim and Logic/Loot (pure rules).
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local BattleSim = t.Shared("Logic.BattleSim")
	local Loot = t.Shared("Logic.Loot")
	local MonsterGen = t.Shared("Logic.MonsterGen")
	local Rng = t.Shared("Logic.Rng")
	local Config = t.Shared("Config")

	-- A plain monster: no traits, adult by default.
	local function mon(line: string, overrides: { [string]: any }?)
		local record = MonsterGen.New(Rng.new(7), { line = line, rarity = 1, stage = 3, traits = {}, hidden = 0, variant = 0 }, 0)
		record.lv = 10
		for k, v in overrides or {} do
			record[k] = v
		end
		return record
	end

	local function count(replay, kind: string, actor: string?): number
		local n = 0
		for _, e in replay.events do
			if e.kind == kind and (actor == nil or e.actor == actor) then
				n += 1
			end
		end
		return n
	end

	local function firstSeed(from: number, to: number, predicate): number?
		for seed = from, to do
			if predicate(seed) then
				return seed
			end
		end
		return nil
	end

	describe("BattleSim.Simulate", function()
		it("is deterministic for a seed and produces the §7 replay shape", function()
			local allies = { mon("cindlet"), mon("bubblin"), mon("mossbun") }
			local enemies = BattleSim.BuildEnemies("meadow", 5, 99)
			local a = BattleSim.Simulate(allies, enemies, 1234)
			local b = BattleSim.Simulate(allies, enemies, 1234)
			expect(a).toEqual(b)
			expect(a.seed).toBe(1234)
			expect(#a.units).toBe(6)
			expect(a.units[1].key).toBe("a1")
			expect(a.units[1].side).toBe("ally")
			expect(a.units[4].key).toBe("e1")
			expect(a.units[4].appearance.line).toBeTruthy()
			expect(#a.events).toBeGreaterThan(0)
			local e = a.events[1]
			expect(type(e.turn)).toBe("number")
			expect(type(e.amount)).toBe("number")
			expect(type(e.hp)).toBe("number")
			-- A different seed plays out differently.
			local c = BattleSim.Simulate(allies, enemies, 4321)
			local differs = not pcall(function()
				expect(a.events).toEqual(c.events)
			end)
			expect(differs).toBe(true)
		end)

		it("does not mutate the monster records", function()
			local ally = mon("cindlet")
			local before = table.clone(ally)
			BattleSim.Simulate({ ally }, { mon("mossbun") }, 5)
			expect(ally).toEqual(before)
		end)

		it("applies the element advantage multiplier", function()
			-- Ember beats Sprout: every ally hit on the sprout carries mult 1.5.
			local replay = BattleSim.Simulate({ mon("cindlet") }, { mon("mossbun") }, 11)
			local sawAdvantage, sawDisadvantage = false, false
			for _, e in replay.events do
				if (e.kind == "hit" or e.kind == "crit") and e.actor == "a1" then
					expect(e.mult).toBe(1.5)
					sawAdvantage = true
				elseif (e.kind == "hit" or e.kind == "crit") and e.actor == "e1" then
					expect(e.mult).toBe(0.7)
					sawDisadvantage = true
				end
			end
			expect(sawAdvantage).toBe(true)
			expect(sawDisadvantage).toBe(true)
		end)

		it("gives the element-advantaged side the edge over many seeds", function()
			local wins = 0
			for seed = 1, 40 do
				-- Tide beats Ember; equal-ish stat lines.
				if BattleSim.Simulate({ mon("bubblin") }, { mon("cindlet") }, seed).win then
					wins += 1
				end
			end
			expect(wins).toBeGreaterThan(30)
		end)

		it("caps battles at MaxTurns as a loss", function()
			local replay = BattleSim.Simulate({ mon("pebblet") }, { mon("pebblet") }, 3, { maxTurns = 2 })
			expect(replay.turns).toBe(2)
			expect(replay.win).toBe(false)
			local full = BattleSim.Simulate({ mon("pebblet") }, { mon("pebblet", { statMult = 40 }) }, 3)
			expect(full.turns).toBeAtLeast(1)
			expect(full.turns <= Config.Regions.MaxTurns).toBe(true)
		end)

		it("charges a special every third action", function()
			local replay = BattleSim.Simulate({ mon("cindlet") }, { mon("pebblet") }, 8, { maxTurns = 6 })
			local specials = 0
			for _, e in replay.events do
				if e.kind == "special" and e.actor == "a1" then
					specials += 1
					expect(e.skill).toBe("strike")
					expect(e.turn % 3).toBe(0)
				end
			end
			expect(specials).toBe(2)
		end)

		it("heals, shields and taunts with support specials", function()
			local healer = BattleSim.Simulate(
				{ mon("mossbun"), mon("cindlet") },
				{ mon("acornling"), mon("pebblet") },
				21,
				{ maxTurns = 6 }
			)
			expect(count(healer, "heal", "a1")).toBeGreaterThan(0)
			local shielder = BattleSim.Simulate({ mon("coralbun"), mon("cindlet") }, { mon("acornling") }, 21, { maxTurns = 3 })
			expect(count(shielder, "shield", "a1")).toBe(2)
			-- The enemy taunts at its third action; afterwards every ally attack goes to it.
			local taunt = BattleSim.Simulate({ mon("cindlet"), mon("staticat") }, { mon("mossbun"), mon("pebblet") }, 4, { maxTurns = 4 })
			local tauntTurn
			for _, e in taunt.events do
				if e.kind == "special" and e.skill == "taunt" then
					tauntTurn = e.turn
				elseif tauntTurn and e.turn == tauntTurn + 1 and e.actor:sub(1, 1) == "a" and e.kind == "hit" then
					expect(e.target).toBe("e2")
				end
			end
			expect(tauntTurn).toBe(3)
		end)

		it("shields absorb damage before HP", function()
			local replay = BattleSim.Simulate({ mon("coralbun") }, { mon("pebblet") }, 2, { maxTurns = 5 })
			local shielded = false
			for i, e in replay.events do
				if e.kind == "shield" then
					shielded = true
					-- The next enemy hit on a1 is absorbed: HP unchanged.
					for j = i + 1, #replay.events do
						local nxt = replay.events[j]
						if (nxt.kind == "hit" or nxt.kind == "crit") and nxt.target == "a1" then
							expect(nxt.hp).toBe(e.hp)
							break
						end
					end
					break
				end
			end
			expect(shielded).toBe(true)
		end)

		it("stuns skip the target's next action", function()
			local seed = firstSeed(1, 300, function(s)
				local r = BattleSim.Simulate({ mon("zappip") }, { mon("pebblet") }, s, { maxTurns = 3 })
				return count(r, "stun") > 0
			end)
			expect(seed).toBeTruthy()
			local replay = BattleSim.Simulate({ mon("zappip") }, { mon("pebblet") }, seed :: number, { maxTurns = 3 })
			local stunTurn
			for _, e in replay.events do
				if e.kind == "stun" then
					expect(e.target).toBe("e1")
					stunTurn = e.turn
				elseif stunTurn and e.kind == "stunned" then
					expect(e.actor).toBe("e1")
					break
				end
			end
			expect(count(replay, "stunned", "e1")).toBe(1)
		end)

		it("reflects thorns damage and regenerates", function()
			local thorny = BattleSim.Simulate({ mon("cindlet") }, { mon("emberslug") }, 6, { maxTurns = 3 })
			expect(count(thorny, "reflect", "e1")).toBeGreaterThan(0)
			local regen = BattleSim.Simulate({ mon("bubblin") }, { mon("pebblet") }, 6, { maxTurns = 6 })
			expect(count(regen, "regen", "a1")).toBeGreaterThan(0)
		end)

		it("applies night, boss and stat bonuses", function()
			local owl = mon("cindlet", { traits = { 10 } }) -- Night Owl
			local enemy = { mon("pebblet") }
			local function firstHit(opts, unit)
				local r = BattleSim.Simulate({ unit or owl }, enemy, 77, opts)
				for _, e in r.events do
					if e.actor == "a1" and (e.kind == "hit" or e.kind == "crit") then
						return e.amount, r
					end
				end
				return 0, r
			end
			local day = firstHit({ maxTurns = 1 })
			local night = firstHit({ maxTurns = 1, night = true })
			expect(night).toBeGreaterThan(day)
			local brawler = mon("cindlet", { traits = { 16 } })
			local plain = firstHit({ maxTurns = 1 }, brawler)
			local boss = firstHit({ maxTurns = 1, boss = true }, brawler)
			expect(boss).toBeGreaterThan(plain)
			local _, bonus = firstHit({ maxTurns = 1, statBonus = 0.2 })
			local _, normal = firstHit({ maxTurns = 1 })
			expect(bonus.units[1].maxHp).toBeGreaterThan(normal.units[1].maxHp)
		end)

		it("keeps replays within the event cap", function()
			local allies = {
				mon("mossbun", { statMult = 30 }),
				mon("bubblin", { statMult = 30 }),
				mon("coralbun", { statMult = 30 }),
				mon("acornling", { statMult = 30 }),
			}
			local enemies = {}
			for i = 1, 5 do
				enemies[i] = mon(if i % 2 == 0 then "emberslug" else "crystomp", { statMult = 30 })
			end
			local replay = BattleSim.Simulate(allies, enemies, 1)
			expect(#replay.events <= BattleSim.MaxEvents).toBe(true)
			expect(replay.turns).toBe(Config.Regions.MaxTurns)
			expect(replay.truncated).toBe(true)
		end)
	end)

	describe("BattleSim.BuildEnemies", function()
		it("builds WaveSize enemies from the region's lines with interpolated levels", function()
			local wave = BattleSim.BuildEnemies("meadow", 1, 5)
			expect(#wave).toBe(Config.Regions.WaveSize)
			for _, e in wave do
				expect(table.find(Config.Regions.ById.meadow.enemyLines, e.line)).toBeTruthy()
				expect(e.lv).toBe(1)
				expect(e.rarity).toBe(1)
				expect(e.boss).toBe(false)
			end
			local late = BattleSim.BuildEnemies("meadow", 19, 5)
			expect(late[1].lv).toBeGreaterThan(10)
			expect(late[1].rarity).toBe(2)
			expect(BattleSim.BuildEnemies("meadow", 4, 5)).toEqual(BattleSim.BuildEnemies("meadow", 4, 5))
		end)

		it("uses the boss form with BossStatMult on stages 10 and 20", function()
			local wave = BattleSim.BuildEnemies("meadow", 10, 5)
			expect(#wave).toBe(1)
			expect(wave[1].boss).toBe(true)
			expect(wave[1].form).toBe("thornbuck")
			expect(wave[1].name).toBe("Thistlebuck")
			expect(wave[1].statMult).toBeGreaterThan(1)
			local replay = BattleSim.Simulate({ mon("cindlet") }, wave, 1, { maxTurns = 1 })
			expect(replay.units[2].boss).toBe(true)
			expect(replay.units[2].name).toBe("Thistlebuck")
			expect(BattleSim.BuildEnemies("gloom", 20, 1)[1].form).toBe("hollowgaze")
		end)

		it("recommends more power on later stages", function()
			local last = 0
			for _, stage in { 1, 5, 9, 12, 19 } do
				local p = BattleSim.RecommendedPower("meadow", stage)
				expect(p).toBeGreaterThan(last)
				last = p
			end
			expect(BattleSim.RecommendedPower("coral", 1)).toBeGreaterThan(BattleSim.RecommendedPower("meadow", 1))
		end)
	end)

	describe("Loot", function()
		it("scales with duration and applies the duration bonus", function()
			local short = Loot.ExpeditionLoot("meadow", 3, 900, { seed = 1 })
			local long = Loot.ExpeditionLoot("meadow", 3, 28800, { seed = 1 })
			local function amount(list, kind)
				local n = 0
				for _, r in list do
					if r.kind == kind then
						n += r.amount
					end
				end
				return n
			end
			local per = Config.Regions.LootPerMinute(Config.Regions.GlobalIndex("meadow", 3))
			expect(amount(short, "coins")).toBe(math.floor(per.coins * 15))
			expect(amount(long, "coins")).toBe(math.floor(per.coins * 480 * 1.2))
			expect(amount(long, "food")).toBe(math.floor(per.food * 480 * 1.2))
			expect(amount(long, "treats")).toBeGreaterThan(amount(short, "treats"))
		end)

		it("gives mostly the region's flavour and no bonus on partial loot", function()
			local list = Loot.ExpeditionLoot("ember", 5, 14400, { seed = 3 })
			local spicy, total = 0, 0
			for _, r in list do
				if r.kind == "food" then
					total += r.amount
					if r.id == "spicy" then
						spicy += r.amount
					end
				end
			end
			expect(spicy / total >= 0.7).toBe(true)
			local partial = Loot.ExpeditionLoot("meadow", 3, 3600, { seed = 1, partial = true })
			local per = Config.Regions.LootPerMinute(Config.Regions.GlobalIndex("meadow", 3))
			expect(partial[1].amount).toBe(math.floor(per.coins * 60))
		end)

		it("applies lootPct and rolls eggs per minute respecting fromStage", function()
			local base = Loot.ExpeditionLoot("meadow", 3, 3600, { seed = 1 })
			local lucky = Loot.ExpeditionLoot("meadow", 3, 3600, { seed = 1, lootPct = 0.5 })
			expect(lucky[1].amount).toBeNear(base[1].amount * 1.5, 1.5)
			local groveBefore, groveAfter, meadowEggs = 0, 0, 0
			for seed = 1, 60 do
				for _, r in Loot.ExpeditionLoot("meadow", 9, 28800, { seed = seed }) do
					if r.kind == "egg" and r.id == "grove" then
						groveBefore += r.amount
					elseif r.kind == "egg" and r.id == "meadow" then
						meadowEggs += r.amount
					end
				end
				for _, r in Loot.ExpeditionLoot("meadow", 10, 28800, { seed = seed }) do
					if r.kind == "egg" and r.id == "grove" then
						groveAfter += r.amount
					end
				end
			end
			expect(groveBefore).toBe(0)
			expect(groveAfter).toBeGreaterThan(0)
			-- 480 rolls at 1% ≈ 4.8 meadow eggs per 8 h run.
			expect(meadowEggs / 60 > 2 and meadowEggs / 60 < 9).toBe(true)
			expect(Loot.ExpeditionLoot("meadow", 3, 3600, { seed = 9 })).toEqual(Loot.ExpeditionLoot("meadow", 3, 3600, { seed = 9 }))
		end)

		it("merges reward lists", function()
			local merged = Loot.Merge({
				{ { kind = "coins", amount = 5 }, { kind = "food", id = "sweet", amount = 1 } },
				{ { kind = "coins", amount = 7 } },
			})
			expect(#merged).toBe(2)
			expect(merged[1].amount).toBe(12)
		end)
	end)
end
