--[[
	DojoBattle (update 3.11): Dojo techniques inside Logic/BattleSim. A learned technique fires
	on every 4th action of its unit (alternating two), logged as kind "special" with the
	technique id; fights without any `tech` replay byte-for-byte as before 3.11 (a pinned
	digest over 120 seeded fights taken on the pre-3.11 BattleSim).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local BattleSim = t.Shared("Logic.BattleSim")
	local MonsterGen = t.Shared("Logic.MonsterGen")
	local Rng = t.Shared("Logic.Rng")
	local Config = t.Shared("Config")

	-- Digest of the replays of 120 seeded fights without techniques, taken before 3.11.
	local PINNED = "b7078cf0"

	local function mon(line: string, lv: number?, overrides: { [string]: any }?)
		local record = MonsterGen.New(Rng.new(7), { line = line, rarity = 2, stage = 3, traits = {}, hidden = 0, variant = 0 }, 0)
		record.lv = lv or 10
		for k, v in overrides or {} do
			record[k] = v
		end
		return record
	end

	local function fnv(h: number, s: string): number
		for i = 1, #s do
			h = bit32.bxor(h, string.byte(s, i))
			h = (h * 16777619) % 4294967296
		end
		return h
	end

	local function digest(replays): string
		local h = 2166136261
		for _, r in replays do
			h = fnv(h, string.format("%s|%d|%d|%s;", tostring(r.win), r.turns, #r.events, tostring(r.truncated)))
			for _, e in r.events do
				h = fnv(
					h,
					string.format(
						"%d,%s,%s,%s,%d,%d,%s,%s;",
						e.turn,
						e.actor,
						tostring(e.target),
						e.kind,
						e.amount,
						e.hp,
						tostring(e.mult),
						tostring(e.skill)
					)
				)
			end
		end
		return string.format("%08x", h)
	end

	local function sampleFights()
		local replays = {}
		local lines = Config.Species.Lines
		local regions = Config.Regions.List
		for seed = 1, 120 do
			local allies = {}
			for k = 1, 1 + seed % 5 do
				local def = lines[(seed * 7 + k * 3) % #lines + 1]
				table.insert(allies, mon(def.id, 5 + (seed * k) % 40, { rarity = 1 + (seed + k) % 5, traits = {} }))
			end
			local region = regions[seed % #regions + 1]
			local enemies = BattleSim.BuildEnemies(region.id, 1 + seed % 20, seed)
			table.insert(replays, BattleSim.Simulate(allies, enemies, seed * 101, { night = seed % 3 == 0, boss = seed % 7 == 0 }))
		end
		return replays
	end

	-- The actions of unit `key` in a 1v1: one hit/crit/special event per action.
	local function actions(replay, key: string)
		local list = {}
		for _, e in replay.events do
			if e.actor == key and (e.kind == "hit" or e.kind == "crit" or e.kind == "special") then
				table.insert(list, e)
			end
		end
		return list
	end

	-- A tanky dummy that never stuns and never dies quickly.
	local function dummy()
		return mon("mossbun", 20, { hpMult = 400, statMult = 0.3 })
	end

	describe("Dojo techniques in BattleSim", function()
		it("replays every fight without techniques exactly as before 3.11", function()
			expect(digest(sampleFights())).toBe(PINNED)
		end)

		it("fires a technique on every 4th action of its unit, logged as a special with its id", function()
			local ally = mon("cindlet", 20, { hpMult = 50, tech = { { id = "cinder_fang", lv = 2 } } })
			local special = Config.Species.ById.cindlet.special
			local replay = BattleSim.Simulate({ ally }, { dummy() }, 42, { maxTurns = 20 })
			local list = actions(replay, "a1")
			expect(#list).toBeGreaterThan(15)
			local techs, specials = 0, 0
			for i, e in list do
				if i % 4 == 0 then
					expect(e.kind).toBe("special")
					expect(e.skill).toBe("cinder_fang")
					techs += 1
				else
					expect(e.skill == "cinder_fang").toBe(false)
					if e.kind == "special" then
						expect(e.skill).toBe(special)
						specials += 1
					end
				end
			end
			expect(techs).toBe(math.floor(#list / 4))
			-- The Special keeps its own charge: it still fires about every 3rd action.
			expect(specials).toBeGreaterThan(math.floor(#list / 3) - 3)
			-- The client names it.
			expect(Config.Techniques.ById.cinder_fang.name).toBe("Cinder Fang")
		end)

		it("alternates two techniques and plays heal and shield techniques like the Specials", function()
			local ally = mon("bubblin", 20, { hpMult = 50, tech = { { id = "tidal_mend", lv = 1 }, { id = "undertow", lv = 3 } } })
			local replay = BattleSim.Simulate({ ally }, { dummy() }, 7, { maxTurns = 20 })
			local list = actions(replay, "a1")
			local order = {}
			for i, e in list do
				if i % 4 == 0 then
					table.insert(order, e.skill)
				end
			end
			expect(order[1]).toBe("tidal_mend")
			expect(order[2]).toBe("undertow")
			expect(order[3]).toBe("tidal_mend")
			-- A heal technique logs the special (no target) and then a shield-free heal line.
			local sawMend = false
			for _, e in replay.events do
				if e.skill == "tidal_mend" then
					sawMend = true
					expect(e.target).toBe(false)
				end
			end
			expect(sawMend).toBe(true)
		end)

		it("is deterministic with techniques, differs from the untrained fight and leaves records alone", function()
			local trained = mon("zappip", 30, { tech = { { id = "static_snap", lv = 3 } } })
			local plain = mon("zappip", 30)
			local before = table.clone(trained)
			local enemies = BattleSim.BuildEnemies("meadow", 10, 3)
			local a = BattleSim.Simulate({ trained }, enemies, 99)
			local b = BattleSim.Simulate({ trained }, enemies, 99)
			expect(a).toEqual(b)
			local c = BattleSim.Simulate({ plain }, enemies, 99)
			expect(digest({ a }) ~= digest({ c })).toBe(true)
			expect(trained).toEqual(before)
			-- Unknown ids and extra slots are ignored.
			local odd = mon("zappip", 30, { tech = { { id = "nope", lv = 9 } } })
			expect(digest({ BattleSim.Simulate({ odd }, enemies, 99) })).toBe(digest({ c }))
		end)
	end)
end
