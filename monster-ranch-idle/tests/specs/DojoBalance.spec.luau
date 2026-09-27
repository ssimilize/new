--[[
	DojoBalance (update 3.11): the Dojo's balance gate. Seeded even-level mirror fights
	(Logic/BattleSim): a team against an exact copy of itself, first untrained, then with the
	team fully trained (every member knows two techniques of its element(s) at the top level),
	then with every member knowing just one technique at the top level (once per technique).

	Gates (owner-approved design):
	  • fully trained: the win rate rises at most MaxTeamDelta over the untrained mirror
	    (FIGHTS fights, paired seeds);
	  • per technique: no technique's delta exceeds MaxSpread × the median technique's delta
	    (PER_TECH fights each, the same seeds).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local BattleSim = t.Shared("Logic.BattleSim")
	local MonsterGen = t.Shared("Logic.MonsterGen")
	local Rng = t.Shared("Logic.Rng")
	local Dojo = t.Shared("Logic.Dojo")
	local Config = t.Shared("Config")

	local FIGHTS = 2000
	local PER_TECH = 500
	local MaxTeamDelta = 0.08
	local MaxSpread = 2

	local Techniques = Config.Techniques

	-- One seeded even-level team: 3 to 5 Adults of one level (10..60), random lines and rarities.
	local function team(n: number)
		local rng = Rng.new(Rng.seed("dojo-balance", n))
		local lv = rng:Int(10, 60)
		local list = {}
		for i = 1, rng:Int(3, 5) do
			local def = rng:Pick(Config.Species.Lines)
			local m = MonsterGen.New(Rng.new(Rng.seed("dojo-balance-m", n, i)), {
				line = def.id,
				rarity = rng:Int(1, 5),
				stage = 3,
				traits = {},
				hidden = 0,
				variant = 0,
			}, 0)
			m.lv = lv
			table.insert(list, m)
		end
		return list
	end

	local function withTech(list, pick)
		local out = {}
		for i, m in list do
			local copy = table.clone(m)
			copy.tech = pick(copy, i)
			table.insert(out, copy)
		end
		return out
	end

	-- Every member knows two techniques of its element(s) at the top level.
	local function fullyTrained(m)
		local learnable = Dojo.Learnable(m)
		local tech = {}
		for i = 1, math.min(Techniques.MaxSlots, #learnable) do
			table.insert(tech, { id = learnable[i].id, lv = Techniques.MaxLevel })
		end
		return tech
	end

	local teams, baseline = {}, {}
	local function prepare(count: number)
		for n = #teams + 1, count do
			teams[n] = team(n)
			baseline[n] = BattleSim.Simulate(teams[n], teams[n], n * 7919).win
		end
	end

	local function winRate(count: number, pick): (number, number)
		prepare(count)
		local base, wins = 0, 0
		for n = 1, count do
			if baseline[n] then
				base += 1
			end
			if BattleSim.Simulate(withTech(teams[n], pick), teams[n], n * 7919).win then
				wins += 1
			end
		end
		return base / count, wins / count
	end

	describe("Dojo balance gate", function()
		it("a fully trained team gains at most 8 points over its untrained mirror", function()
			local base, trained = winRate(FIGHTS, fullyTrained)
			print(
				string.format("[DojoBalance] %d fights: untrained %.3f, trained %.3f, delta %+.3f", FIGHTS, base, trained, trained - base)
			)
			expect(trained - base <= MaxTeamDelta).toBe(true)
			expect(trained - base > 0).toBe(true)
		end)

		it("no technique's delta exceeds twice the median technique's delta", function()
			local deltas, sorted = {}, {}
			for _, tech in Techniques.List do
				local base, trained = winRate(PER_TECH, function()
					return { { id = tech.id, lv = Techniques.MaxLevel } }
				end)
				deltas[tech.id] = trained - base
				table.insert(sorted, trained - base)
			end
			table.sort(sorted)
			local median = (sorted[#sorted / 2] + sorted[#sorted / 2 + 1]) / 2
			local lines = {}
			for _, tech in Techniques.List do
				table.insert(lines, string.format("%s %+.3f", tech.id, deltas[tech.id]))
			end
			print(string.format("[DojoBalance] median %+.3f · %s", median, table.concat(lines, ", ")))
			expect(median > 0).toBe(true)
			for _, tech in Techniques.List do
				if deltas[tech.id] > MaxSpread * median then
					error(string.format("%s delta %+.3f is over %d x the median %+.3f", tech.id, deltas[tech.id], MaxSpread, median))
				end
			end
		end)
	end)
end
