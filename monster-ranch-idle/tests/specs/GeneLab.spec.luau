--[[
	GeneLab (update 3.10 · Ranch life): the Gene Lab's rules (Logic/GeneLab), lock-aware genetics
	(Logic/Genetics Inherit/Odds/GradeOdds/Range with locks), and the system on the server: seeded
	tunes, costs, the cap at 8, the daily limit, refusals, locks through a real breeding, a
	cancelled pod keeping its lock, and a traded monster losing it.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Genetics = t.Shared("Logic.Genetics")
	local Lab = t.Shared("Logic.GeneLab")
	local BreedingLogic = t.Shared("Logic.Breeding")
	local Rng = t.Shared("Logic.Rng")

	local Rules = Config.GeneLab
	local DAY = 86400

	local function uniform(a, b)
		local g = {}
		for _, stat in Config.Genetics.Stats do
			g[stat] = { a, b }
		end
		return g
	end

	local function with(genes, stat, a, b)
		local g = Genetics.Copy(genes)
		g[stat] = { a, b }
		return g
	end

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function boot(level: number?)
		local h = TestKernel.new({ systems = allSystems() })
		local p = h:Join()
		levelTo(h, p, level or Config.Unlocks.Features.gene_lab)
		h:System("Currency"):Add(p, "stardust", 1e6, "test")
		h:System("Currency"):Add(p, "coins", 1e9, "test")
		return h, p, h:System("Monsters")
	end

	local function adult(M, p, fields)
		local spec = { line = "cindlet", rarity = 2, stage = 3, variant = 0, genes = uniform(3, 3) }
		for k, v in fields or {} do
			spec[k] = v
		end
		return M:Create(p, spec, "test", true)
	end

	local function stardust(h, p): number
		return h:Section(p, "Currency").stardust
	end

	-- Tunes `stat` once and checks the outcome against the seeded roll the rules promise.
	local function tuneChecked(h, p, m, stat: string)
		local s = h:Section(p, "GeneLab")
		local attempt = s.attempts
		local index, gene = Lab.Weaker(m.genes, stat)
		local other = m.genes[stat][3 - index]
		local chance = Lab.Chance(gene)
		local expected = Lab.Roll(Lab.Seed(p.UserId, m.id, attempt), chance)
		local before = stardust(h, p)
		local res = h:Call(p, "GeneLab.Tune", { id = m.id, stat = stat })
		h:Advance(1)
		expect(res.success).toBe(expected)
		expect(res.cost).toBe(Lab.Cost(gene))
		expect(res.chance).toBe(chance)
		expect(stardust(h, p)).toBe(before - Lab.Cost(gene))
		expect(m.genes[stat][index]).toBe(if expected then gene + 1 else gene)
		expect(m.genes[stat][3 - index]).toBe(other)
		expect(s.attempts).toBe(attempt + 1)
		return res
	end

	describe("Gene Lab rules", function()
		it("tunes the weaker gene (the first on a tie) at the promised cost and odds", function()
			expect({ Lab.Weaker({ hp = { 3, 6 } }, "hp") }).toEqual({ 1, 3 })
			expect({ Lab.Weaker({ hp = { 6, 2 } }, "hp") }).toEqual({ 2, 2 })
			expect({ Lab.Weaker({ hp = { 4, 4 } }, "hp") }).toEqual({ 1, 4 })
			expect(Lab.Cost(0)).toBe(20)
			expect(Lab.Cost(7)).toBe(160)
			for gene = 0, 4 do
				expect(Lab.Chance(gene)).toBe(0.9)
			end
			expect(Lab.Chance(5)).toBe(0.6)
			expect(Lab.Chance(6)).toBe(0.6)
			expect(Lab.Chance(7)).toBe(0.35)
			expect(Lab.Chance(8)).toBeNil()
			expect(Lab.Chance(10)).toBeNil()
			expect(Lab.TunesLeft(nil, 5)).toBe(5)
			expect(Lab.TunesLeft({ day = 5, tunes = 3 }, 5)).toBe(2)
			expect(Lab.TunesLeft({ day = 4, tunes = 5 }, 5)).toBe(5)
		end)

		it("rolls success at the promised rate from its seeds", function()
			local wins = 0
			for i = 1, 4000 do
				if Lab.Roll(Lab.Seed(1, "m" .. i, i), 0.35) then
					wins += 1
				end
			end
			expect(wins / 4000).toBeNear(0.35, 0.03)
		end)
	end)

	describe("Gene locks in genetics", function()
		local a = with(uniform(3, 3), "hp", 2, 9)
		local b = with(uniform(4, 4), "hp", 1, 6)

		it("changes nothing without locks, and draws the same numbers with them", function()
			expect(Genetics.Odds(a, b, "hp", nil, nil)).toEqual(Genetics.Odds(a, b, "hp"))
			expect(Genetics.Odds(a, b, "hp", "atk", "def")).toEqual(Genetics.Odds(a, b, "hp"))
			for seed = 1, 200 do
				local plain = Genetics.Inherit(Rng.new(seed), a, b)
				local locked = Genetics.Inherit(Rng.new(seed), a, b, "hp", nil)
				for _, stat in Config.Genetics.Stats do
					if stat ~= "hp" then
						expect(locked[stat]).toEqual(plain[stat])
					end
				end
				expect(locked.hp[2]).toBe(plain.hp[2])
			end
		end)

		it("passes a locked parent's better gene for certain, surges after", function()
			local counts = {}
			for seed = 1, 3000 do
				local genes = Genetics.Inherit(Rng.new(seed), a, b, "hp", "hp")
				expect(genes.hp[1] >= 9).toBe(true)
				expect(genes.hp[2] >= 6).toBe(true)
				counts[genes.hp[1]] = (counts[genes.hp[1]] or 0) + 1
			end
			expect((counts[10] or 0) > 0).toBe(true) -- a surge still lifts it
		end)

		it("gives exact planner odds and ranges with locks", function()
			-- A locked parent acts like a parent with its better gene twice.
			local aBest = with(a, "hp", 9, 9)
			expect(Genetics.Odds(a, b, "hp", "hp")).toEqual(Genetics.Odds(aBest, b, "hp"))
			expect(Genetics.GradeOdds(a, b, "hp", "hp")).toEqual(Genetics.GradeOdds(aBest, b, "hp"))
			expect({ Genetics.Range(a, b, "hp", "hp", nil) }).toEqual({ 10, 15 })
			expect({ Genetics.Range(a, b, "hp") }).toEqual({ 3, 15 })
			expect(Genetics.Preview(a, b, "hp").stats[1].lo).toBe(10)
			-- Sampled Inherit agrees with the exact odds.
			local odds = Genetics.Odds(a, b, "hp", "hp", nil)
			local seen, n = {}, 20000
			for seed = 1, n do
				local g = Genetics.Inherit(Rng.new(seed * 7919), a, b, "hp", nil)
				local points = g.hp[1] + g.hp[2]
				seen[points] = (seen[points] or 0) + 1
			end
			for points, p in odds do
				expect((seen[points] or 0) / n).toBeNear(p, 0.015)
			end
			expect(Genetics.AtLeast(Genetics.GradeOdds(a, b, "hp", "hp"), "B") > Genetics.AtLeast(Genetics.GradeOdds(a, b, "hp"), "B")).toBe(
				true
			)
		end)
	end)

	describe("Gene Lab tunes", function()
		it("opens at Ranch Level 21", function()
			local h, p, M = boot(20)
			local m = adult(M, p)
			expect(h:Reject(p, "GeneLab.Tune", { id = m.id, stat = "hp" })).toContain("Ranch Level 21")
			expect(h:Reject(p, "GeneLab.Lock", { id = m.id, stat = "hp" })).toContain("Ranch Level 21")
		end)

		it("tunes the weaker gene with the seeded roll, publishes GeneTuned and counts the day", function()
			local h, p, M = boot()
			local m = adult(M, p, { genes = with(uniform(3, 3), "atk", 6, 2) })
			local tuned = {}
			h.kernel.Bus:Subscribe("GeneTuned", function(player, detail)
				if player == p then
					table.insert(tuned, detail)
				end
			end)
			local res = tuneChecked(h, p, m, "atk")
			expect(tuned[1]).toEqual({ stat = "atk", success = res.success })
			expect(res.tunesLeft).toBe(Rules.DailyTunes - 1)
			local s = h:Section(p, "GeneLab")
			expect(s.tunes).toBe(1)
			expect(h:Client(p).profile.GeneLab.tunes).toBe(1)
			-- A tie raises the first gene.
			local tie = adult(M, p, { genes = uniform(4, 4) })
			tuneChecked(h, p, tie, "def")
			expect(#tuned).toBe(2)
		end)

		it("keeps the spent Stardust on a miss and never goes past 8", function()
			local h, p, M = boot()
			local m = adult(M, p, { genes = with(uniform(3, 3), "spd", 7, 9) })
			local misses, hits = 0, 0
			while m.genes.spd[1] < 8 do
				local res = tuneChecked(h, p, m, "spd")
				if res.success then
					hits += 1
				else
					misses += 1
				end
				if h:Section(p, "GeneLab").tunes >= Rules.DailyTunes then
					h:Advance(DAY)
				end
			end
			expect(hits).toBe(1)
			expect(m.genes.spd).toEqual({ 8, 9 })
			local before, attempts = stardust(h, p), h:Section(p, "GeneLab").attempts
			expect(h:Reject(p, "GeneLab.Tune", { id = m.id, stat = "spd" })).toContain("Both SPD genes are 8 or higher")
			expect(stardust(h, p)).toBe(before)
			expect(h:Section(p, "GeneLab").attempts).toBe(attempts)
			-- Genes above the cap from breeding are left alone too.
			local surged = adult(M, p, { genes = with(uniform(3, 3), "hp", 10, 9) })
			expect(h:Reject(p, "GeneLab.Tune", { id = surged.id, stat = "hp" })).toContain("8 or higher")
		end)

		it("allows 5 tunes per UTC day and keeps the attempt count across a rejoin", function()
			local h, p, M = boot()
			local m = adult(M, p, { genes = uniform(0, 0) })
			for _ = 1, Rules.DailyTunes do
				tuneChecked(h, p, m, "luck")
			end
			expect(h:Reject(p, "GeneLab.Tune", { id = m.id, stat = "luck" })).toContain("No Gene Lab tunes left today")
			local attempts = h:Section(p, "GeneLab").attempts
			expect(attempts).toBe(Rules.DailyTunes)
			local p2 = h:Rejoin(p, 60)
			expect(h:Section(p2, "GeneLab").attempts).toBe(attempts)
			expect(h:Reject(p2, "GeneLab.Tune", { id = m.id, stat = "luck" })).toContain("No Gene Lab tunes left today")
			h:Advance(DAY)
			local again = h:System("Monsters"):Get(p2, m.id)
			tuneChecked(h, p2, again, "luck")
			expect(h:Section(p2, "GeneLab").tunes).toBe(1)
		end)

		it("refuses babies, busy monsters, strangers' ids and a short purse", function()
			local h, p, M = boot()
			local baby = adult(M, p, { stage = 1 })
			expect(h:Reject(p, "GeneLab.Tune", { id = baby.id, stat = "hp" })).toContain("must be an Adult to use the Gene Lab")
			expect(h:Reject(p, "GeneLab.Tune", { id = "m9999", stat = "hp" })).toContain("doesn't exist")
			local a, b = adult(M, p), adult(M, p)
			h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
			expect(h:Reject(p, "GeneLab.Tune", { id = a.id, stat = "hp" })).toContain("busy")
			expect(h:Reject(p, "GeneLab.Lock", { id = a.id, stat = "hp" })).toContain("busy")
			local m = adult(M, p)
			expect(h:Invoke(p, "GeneLab.Tune", { id = m.id, stat = "charm" }).ok).toBe(false)
			h:System("Currency"):Spend(p, { stardust = stardust(h, p) - 10 }, "test")
			expect(h:Reject(p, "GeneLab.Tune", { id = m.id, stat = "hp" })).toContain("Stardust")
			expect(stardust(h, p)).toBe(10)
			expect(h:Section(p, "GeneLab").tunes).toBe(0)
			expect(h:Section(p, "GeneLab").attempts).toBe(0)
		end)
	end)

	describe("Gene locks", function()
		it("costs 5 Star Shards, replaces without refund and refuses the same stat", function()
			local h, p, M = boot()
			local HoF = h:System("HallOfFame")
			local m = adult(M, p)
			expect(h:Reject(p, "GeneLab.Lock", { id = m.id, stat = "hp" })).toContain("Not enough Star Shards")
			HoF:AddStarShards(p, 12, "test")
			local shards = HoF:StarShards(p)
			expect(h:Call(p, "GeneLab.Lock", { id = m.id, stat = "hp" })).toEqual({ stat = "hp", cost = 5 })
			expect(m.geneLock).toBe("hp")
			expect(h:Client(p).profile.Monsters.list[m.id].geneLock).toBe("hp")
			expect(HoF:StarShards(p)).toBe(shards - 5)
			h:Advance(1)
			expect(h:Reject(p, "GeneLab.Lock", { id = m.id, stat = "hp" })).toContain("already locked")
			expect(HoF:StarShards(p)).toBe(shards - 5)
			h:Call(p, "GeneLab.Lock", { id = m.id, stat = "atk" })
			expect(m.geneLock).toBe("atk")
			expect(HoF:StarShards(p)).toBe(shards - 10)
		end)

		it("passes the better gene through a real breeding and is used up by it", function()
			local h, p, M = boot()
			h:System("HallOfFame"):AddStarShards(p, 20, "test")
			local a = adult(M, p, { genes = with(uniform(3, 3), "hp", 2, 9) })
			local b = adult(M, p, { line = "bubblin", genes = with(uniform(4, 4), "hp", 1, 6) })
			h:Call(p, "GeneLab.Lock", { id = a.id, stat = "hp" })
			h:Call(p, "GeneLab.Lock", { id = b.id, stat = "hp" })
			h:Advance(1)
			local preview = BreedingLogic.Outcomes(a, b).genes.stats[1]
			expect({ preview.lo, preview.hi }).toEqual({ 15, 15 })

			-- A cancelled pod keeps the locks.
			h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
			h:Call(p, "Breeding.Cancel", { pod = 1 })
			expect(a.geneLock).toBe("hp")
			expect(b.geneLock).toBe("hp")
			h:Advance(1)

			h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
			local pod = h:Section(p, "Breeding").pods[1]
			local seed = pod.seed
			local snapA, snapB = table.clone(a), table.clone(b)
			h:Advance(pod.endsAt - h.adapters.Clock.Now() + 1)
			local baby = h:Call(p, "Breeding.Claim", { pod = 1 }).monster
			expect(baby.genes.hp[1] >= 9).toBe(true)
			expect(baby.genes.hp[2] >= 6).toBe(true)
			-- Exactly Logic/Breeding's roll with the locks; without them only hp could differ.
			local spec = BreedingLogic.Roll(Rng.new(seed), snapA, snapB)
			expect(baby.genes).toEqual(spec.genes)
			snapA.geneLock, snapB.geneLock = nil, nil
			local plain = BreedingLogic.Roll(Rng.new(seed), snapA, snapB)
			for _, stat in Config.Genetics.Stats do
				if stat ~= "hp" then
					expect(baby.genes[stat]).toEqual(plain.genes[stat])
				end
			end
			expect(a.geneLock).toBeNil()
			expect(b.geneLock).toBeNil()
			expect(h:Client(p).profile.Monsters.list[a.id].geneLock).toBeNil()
		end)

		it("is cleared when the monster is traded away", function()
			local h, p, M = boot()
			local q = h:Join(nil, "Bob")
			levelTo(h, q, Config.Unlocks.Features.gene_lab)
			for _, player in { p, q } do
				h.kernel.Data:Get(player)._meta.playSeconds = 3600
			end
			h:System("HallOfFame"):AddStarShards(p, 5, "test")
			local m = adult(M, p)
			h:Call(p, "GeneLab.Lock", { id = m.id, stat = "def" })
			local mq = adult(M, q, { line = "bubblin" })
			h:Call(p, "Trade.Request", { target = q.UserId })
			h:Call(q, "Trade.Respond", { from = p.UserId, accept = true })
			h:Call(p, "Trade.SetOffer", { items = { { kind = "monster", id = m.id } } })
			h:Call(q, "Trade.SetOffer", { items = { { kind = "monster", id = mq.id } } })
			h:Call(p, "Trade.SetReady", { ready = true })
			h:Call(q, "Trade.SetReady", { ready = true })
			h:Call(p, "Trade.Confirm")
			h:Call(q, "Trade.Confirm")
			h:Advance(Config.Social.Trade.countdownSeconds + 1)
			expect(M:Get(p, m.id)).toBeNil()
			local got = nil
			for _, r in M:All(q) do
				if r.line == "cindlet" then
					got = r
				end
			end
			expect(got ~= nil).toBe(true)
			expect(got.geneLock).toBeNil()
			expect(got.genes).toEqual(m.genes)
		end)
	end)

	describe("Weekly goal", function()
		it("has a genelab goal counting every tune", function()
			local found = nil
			for _, def in Config.Weekly.Pool do
				if def.family == "genelab" then
					found = def
				end
			end
			expect(found ~= nil).toBe(true)
			expect(found.topic).toBe("GeneTuned")
			expect(found.target).toBe(5)
			expect(found.unlock).toBe("gene_lab")
			expect(found.filter).toBeNil()
		end)
	end)
end
