--[[
	TrialTowerBalance (update 3.12 · Honey & stars): the Trial Tower's difficulty curve, pure and
	seeded (Logic/TrialTower). A climb gets three fights a floor (the day's attempts) and stops at
	the first floor it cannot win. Bands:
	  • a typical Level-26 squad (three Adults, Common to Rare, around Lv 26) clears floors 8-15;
	  • a strong endgame squad (five Mythic/Legendary Adults at Lv 90 with Dojo techniques) 40+;
	  • a fight is deterministic for a given (week, floor, squad, seed), with and without techniques.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local Logic = t.Shared("Logic.TrialTower")
	local MonsterGen = t.Shared("Logic.MonsterGen")
	local Rng = t.Shared("Logic.Rng")

	local function mon(line: string, rarity: number, lv: number, tech)
		local record = MonsterGen.New(Rng.new(7), { line = line, rarity = rarity, stage = 3, traits = {}, hidden = 0, variant = 0 }, 0)
		record.lv = lv
		record.tech = tech
		return record
	end

	local function typical(lv: number)
		return { mon("cindlet", 2, lv), mon("bubblin", 3, lv), mon("mossbun", 1, lv) }
	end

	local FIRE = { { id = "flare_burst", lv = 3 }, { id = "cinder_fang", lv = 3 } }
	local TIDE = { { id = "undertow", lv = 3 }, { id = "tidal_mend", lv = 3 } }
	local SPROUT = { { id = "bramble_guard", lv = 3 }, { id = "sap_leech", lv = 3 } }
	local function strong()
		return {
			mon("cindlet", 6, 90, FIRE),
			mon("bubblin", 6, 90, TIDE),
			mon("mossbun", 6, 90, SPROUT),
			mon("cindlet", 5, 90, FIRE),
			mon("bubblin", 5, 90, TIDE),
		}
	end

	-- Highest floor cleared with up to three fights a floor (stops at `cap`).
	local function climb(squad, week: number, cap: number): number
		for floor = 1, cap do
			local won = false
			for n = 0, 2 do
				if Logic.Fight(squad, week, floor, Logic.FightSeed(1, week, floor, n)).win then
					won = true
					break
				end
			end
			if not won then
				return floor - 1
			end
		end
		return cap
	end

	describe("TrialTower balance", function()
		it("lets a typical Level-26 squad clear about floors 8-15", function()
			for week = 0, 2 do
				for _, lv in { 24, 28 } do
					local best = climb(typical(lv), week, 30)
					expect(best >= 8 and best <= 16).toBe(true)
				end
			end
		end)

		it("lets a strong endgame squad with techniques reach floor 40", function()
			for week = 0, 1 do
				expect(climb(strong(), week, 40)).toBe(40)
			end
		end)

		it("fights the same way for the same week, floor, squad and seed", function()
			local plain = typical(26)
			local a = Logic.Fight(plain, 3, 7, 12345)
			local b = Logic.Fight(typical(26), 3, 7, 12345)
			expect(a).toEqual(b)
			local c = Logic.Fight(strong(), 3, 30, 777)
			local d = Logic.Fight(strong(), 3, 30, 777)
			expect(c).toEqual(d)
			expect(Logic.FightSeed(1, 3, 7, 0)).toBe(Logic.FightSeed(1, 3, 7, 0))
			expect(Logic.FightSeed(1, 3, 7, 0) ~= Logic.FightSeed(1, 3, 7, 1)).toBe(true)
		end)
	end)
end
