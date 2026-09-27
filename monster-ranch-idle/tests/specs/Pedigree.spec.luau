--[[
	Pedigree & breeding planner (update 3.9): the `ped` field bred babies carry (parents and
	grandparents, never deeper, never ids), its survival through Trade and the Market, the exact
	odds of Logic/Genetics.Odds against a Monte-Carlo run of Genetics.Inherit, Breeding.SetTarget,
	the target toast and the once-per-stat A / S ribbon milestones.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Genetics = t.Shared("Logic.Genetics")
	local Pedigree = t.Shared("Logic.Pedigree")
	local BreedingLogic = t.Shared("Logic.Breeding")
	local Rng = t.Shared("Logic.Rng")

	local Stats = Config.Genetics.Stats

	local function uniform(a, b)
		local genes = {}
		for _, stat in Stats do
			genes[stat] = { a, b }
		end
		return genes
	end

	local function sum(odds)
		local total = 0
		for _, p in odds do
			total += p
		end
		return total
	end

	-- Odds ---------------------------------------------------------------------------------

	describe("Genetics.Odds", function()
		it("is an exact distribution: sums to 1, every points key present", function()
			local rng = Rng.new(Rng.seed("pedigree", "odds"))
			for _ = 1, 200 do
				local a, b = {}, {}
				for _, stat in Stats do
					a[stat] = { rng:Int(0, 10), rng:Int(0, 10) }
					b[stat] = { rng:Int(0, 10), rng:Int(0, 10) }
				end
				for _, stat in Stats do
					local odds = Genetics.Odds(a, b, stat)
					expect(math.abs(sum(odds) - 1)).toBeLessThan(1e-12)
					for points = 0, 2 * Config.Genetics.MaxGene do
						expect(odds[points] ~= nil).toBe(true)
					end
					local grades = Genetics.GradeOdds(a, b, stat)
					expect(math.abs(sum(grades) - 1)).toBeLessThan(1e-12)
					-- AtLeast reads either table the same way.
					for _, g in Config.Genetics.Grades do
						expect(Genetics.AtLeast(odds, g.grade)).toBeNear(Genetics.AtLeast(grades, g.grade), 1e-12)
					end
					expect(Genetics.AtLeast(grades, "D")).toBeNear(1, 1e-12)
				end
			end
		end)

		it("matches the surge rules by hand: zeros, the cap, a maxed gene and broken genes", function()
			local big, small = Config.Genetics.BigSurgeChance, Config.Genetics.SurgeChance
			local keep = 1 - big - small
			local zero = Genetics.Odds(uniform(0, 0), uniform(0, 0), "hp")
			expect(zero[0]).toBeNear(keep * keep, 1e-12)
			expect(zero[1]).toBeNear(2 * keep * small, 1e-12)
			expect(zero[2]).toBeNear(small * small + 2 * keep * big, 1e-12)
			expect(zero[3]).toBeNear(2 * small * big, 1e-12)
			expect(zero[4]).toBeNear(big * big, 1e-12)
			-- Genes at 10 never surge: two maxed parents always give 20.
			expect(Genetics.Odds(uniform(10, 10), uniform(10, 10), "atk")[20]).toBe(1)
			-- A 9 surges to 10 either way (+1, or +2 capped).
			local nine = Genetics.Odds(uniform(9, 9), uniform(10, 10), "def")
			expect(nine[20]).toBeNear(big + small, 1e-12)
			expect(nine[19]).toBeNear(keep, 1e-12)
			-- One gene from each parent's pair at 1/2: {0, 10} x {10, 10}.
			local split = Genetics.Odds(uniform(0, 10), uniform(10, 10), "spd")
			expect(split[20]).toBeNear(0.5, 1e-12)
			expect(split[10]).toBeNear(0.5 * keep, 1e-12)
			-- Missing or invalid genes count as zero, like Inherit.
			local broken = Genetics.Odds(nil, { hp = { -3, 2.5 } }, "hp")
			for points, p in zero do
				expect(broken[points]).toBeNear(p, 1e-12)
			end
			-- Grades: 14 + 0 surges is an A; with {7,7} x {7,7} A-or-better is certain.
			expect(Genetics.AtLeast(Genetics.GradeOdds(uniform(7, 7), uniform(7, 7), "hp"), "A")).toBeNear(1, 1e-12)
			expect(Genetics.AtLeast(Genetics.GradeOdds(uniform(7, 7), uniform(7, 7), "hp"), "S")).toBeNear(big * big, 1e-12)
			expect(Genetics.AtLeast({}, "Z")).toBe(0)
			expect(Genetics.Grades({ hp = { 5, 5 }, atk = { 7, 7 }, def = { 3, 3 }, spd = { 0, 0 }, luck = { 9, 9 } })).toBe("BACDS")
		end)

		it("agrees with 200,000 seeded Inherit rolls", function()
			local a = { hp = { 3, 9 }, atk = { 0, 10 }, def = { 5, 5 }, spd = { 9, 10 }, luck = { 1, 2 } }
			local b = { hp = { 8, 4 }, atk = { 10, 10 }, def = { 0, 7 }, spd = { 9, 9 }, luck = { 6, 0 } }
			local N = 200000
			local counts, gradeCounts = {}, {}
			for _, stat in Stats do
				counts[stat] = {}
				gradeCounts[stat] = {}
			end
			local rng = Rng.new(Rng.seed("pedigree", "monte-carlo"))
			for _ = 1, N do
				local genes = Genetics.Inherit(rng, a, b)
				for _, stat in Stats do
					local points = genes[stat][1] + genes[stat][2]
					counts[stat][points] = (counts[stat][points] or 0) + 1
					local grade = Genetics.Grade(points).grade
					gradeCounts[stat][grade] = (gradeCounts[stat][grade] or 0) + 1
				end
			end
			-- 0.005 is over 4.5 standard deviations for any probability at N = 200k.
			local worst = 0
			for _, stat in Stats do
				for points, p in Genetics.Odds(a, b, stat) do
					worst = math.max(worst, math.abs((counts[stat][points] or 0) / N - p))
				end
				for grade, p in Genetics.GradeOdds(a, b, stat) do
					worst = math.max(worst, math.abs((gradeCounts[stat][grade] or 0) / N - p))
				end
			end
			expect(worst).toBeLessThan(0.005)
		end)
	end)

	-- System -------------------------------------------------------------------------------

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Social", "Breeding" }

	local function levelTo(h, p, level)
		local xp = 0
		for l = 1, level - 1 do
			xp += Config.Unlocks.XPToNext(l)
		end
		h:System("Progression"):AddXP(p, xp, "test")
	end

	local function boot(options)
		local opts = options or {}
		local h = TestKernel.new({ systems = opts.systems or SYSTEMS, stubs = opts.stubs })
		local p = h:Join()
		levelTo(h, p, opts.level or 12)
		h:System("Currency"):Add(p, "coins", 1e9, "test")
		return h, p, h:System("Monsters")
	end

	local function adult(M, p, fields)
		local spec = { stage = 3, line = "cindlet", rarity = 2, variant = 0, traits = { 3, 4 }, hidden = 5 }
		for k, v in fields or {} do
			spec[k] = v
		end
		return M:Create(p, spec, "test", true)
	end

	-- Starts a pod, pins a seed whose baby passes `accept` (default: any), waits and claims.
	local function breed(h, p, a, b, accept)
		h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
		local pod = h:Section(p, "Breeding").pods[1]
		for seed = 1, 20000 do
			local spec = BreedingLogic.Roll(Rng.new(seed), a, b)
			if accept == nil or accept(spec.genes) then
				pod.seed = seed
				break
			end
		end
		h:Advance(Config.Breeding.Seconds[math.max(a.rarity, b.rarity)] + 1)
		return h:Call(p, "Breeding.Claim", { pod = 1 })
	end

	local function hasId(tbl): boolean
		for key, value in tbl do
			if key == "id" then
				return true
			end
			if type(value) == "table" and hasId(value) then
				return true
			end
		end
		return false
	end

	describe("Pedigree on bred babies", function()
		it("records both parents, no grandparents for hatched parents, and never an id", function()
			local h, p, M = boot()
			local a = adult(M, p, { genes = uniform(2, 6) })
			a.name = "Blaze" -- names come from Monsters.Rename, not the spec
			local b = adult(M, p, { line = "bubblin", rarity = 3, genes = uniform(5, 5) })
			local baby = breed(h, p, a, b).monster
			local ped = baby.ped
			expect(type(ped)).toBe("table")
			expect(ped.a).toEqual({
				line = "cindlet",
				form = a.form,
				rarity = 2,
				name = "Blaze",
				gen = 0,
				grades = Genetics.Grades(a.genes),
			})
			expect(ped.b.line).toBe("bubblin")
			expect(ped.b.rarity).toBe(3)
			expect(ped.b.name).toBeNil()
			expect(ped.b.grades).toBe("BBBBB")
			expect(ped.aa).toBeNil()
			expect(ped.bb).toBeNil()
			expect(hasId(ped)).toBe(false)
			-- It replicates with the record; hatched monsters have none.
			expect(type(h:Client(p).profile.Monsters.list[baby.id].ped)).toBe("table")
			expect(a.ped).toBeNil()
		end)

		it("takes grandparents from each parent's own pedigree and stops there", function()
			local h, p, M = boot()
			local g1 = adult(M, p, { line = "mossbun", genes = uniform(9, 9) })
			local g2 = adult(M, p, { line = "zappip", genes = uniform(0, 1) })
			local g0 = adult(M, p, { line = "bubblin", genes = uniform(3, 3) })
			-- A parent that is itself a grandchild: its pedigree already has grandparents.
			local deepPed = Pedigree.Build(
				{ line = "coralbun", rarity = 1, genes = uniform(1, 1), ped = Pedigree.Build(g0, g0) },
				{ line = "cindlet", rarity = 1, genes = uniform(2, 2) }
			)
			local a = adult(M, p, { gen = 1, genes = uniform(5, 5), ped = Pedigree.Build(g1, g2) })
			local b = adult(M, p, { line = "bubblin", gen = 2, genes = uniform(5, 6), ped = deepPed })
			local baby = breed(h, p, a, b).monster
			expect(baby.gen).toBe(3)
			local ped = baby.ped
			expect(ped.a.gen).toBe(1)
			expect(ped.aa.line).toBe("mossbun")
			expect(ped.aa.grades).toBe("SSSSS")
			expect(ped.ab.line).toBe("zappip")
			expect(ped.ba.line).toBe("coralbun")
			expect(ped.bb.line).toBe("cindlet")
			-- Depth limit: six slots, and a snapshot never carries its own pedigree.
			local keys = {}
			for key in ped do
				table.insert(keys, key)
			end
			table.sort(keys)
			expect(keys).toEqual({ "a", "aa", "ab", "b", "ba", "bb" })
			for _, snap in ped do
				expect(snap.ped).toBeNil()
				expect(snap.genes).toBeNil()
			end
			-- Copies, not references to the parents' tables.
			expect(ped.aa ~= a.ped.a).toBe(true)
			expect(hasId(ped)).toBe(false)
			expect(Pedigree.ParentNames(ped)).toBe(Pedigree.Name(ped.a))
		end)

		it("survives a trade and a Market sale as its own table", function()
			local h, p, M = boot()
			local a = adult(M, p, { genes = uniform(4, 4) })
			local b = adult(M, p, { line = "mossbun", genes = uniform(6, 6) })
			a.name, b.name = "Mom", "Dad"
			local baby = M:Get(p, breed(h, p, a, b).monster.id)
			local q = h:Join(nil, "Buyer")
			local copy = M:Insert(q, baby, "trade")
			expect(copy.ped).toEqual(baby.ped)
			expect(copy.ped ~= baby.ped).toBe(true)
			expect(copy.ped.a ~= baby.ped.a).toBe(true)
			copy.ped.a.name = "Changed"
			expect(baby.ped.a.name).toBe("Mom")
			-- The Market's public view names the parents and shows no ids.
			local Listing = t.Server("Systems.Market.Listing")
			local view = Listing.ItemView("monster", baby)
			expect(view.parents).toEqual({ "Mom", "Dad" })
			expect(hasId(view)).toBe(false)
			expect(Listing.ItemView("monster", a).parents).toBe(false)
			expect(Listing.ItemView("egg", { type = "grove" }).parents).toBe(false)
			-- A record escrowed before 3.9 has no pedigree and gets none.
			local old = table.clone(baby)
			old.ped = nil
			expect(M:Insert(q, old, "market").ped).toBeNil()
		end)

		it("names the parents in the trade log", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Trade" } })
			local x, y = h:Join(nil, "Alice"), h:Join(nil, "Bob")
			for _, pl in { x, y } do
				levelTo(h, pl, 12)
				h.kernel.Data:Get(pl)._meta.playSeconds = 3600
			end
			local M = h:System("Monsters")
			local g1 = adult(M, x)
			g1.name = "Pip"
			local g2 = adult(M, x, { line = "mossbun" })
			local baby = adult(M, x, { gen = 1, ped = Pedigree.Build(g1, g2) })
			local other = adult(M, y, { line = "zappip" })
			h:Call(x, "Trade.Request", { target = y.UserId })
			h:Call(y, "Trade.Respond", { from = x.UserId, accept = true })
			h:Call(x, "Trade.SetOffer", { items = { { kind = "monster", id = baby.id } } })
			h:Call(y, "Trade.SetOffer", { items = { { kind = "monster", id = other.id } } })
			h:Call(x, "Trade.SetReady", { ready = true })
			h:Call(y, "Trade.SetReady", { ready = true })
			h:Call(x, "Trade.Confirm")
			h:Call(y, "Trade.Confirm")
			for _ = 1, 30 do
				if #h:Section(x, "Trade").log > 0 then
					break
				end
				h:Advance(1)
			end
			local log = h:Section(x, "Trade").log
			expect(#log).toBe(1)
			expect(log[1].gave[1].parents).toEqual({ "Pip", Pedigree.Name(Pedigree.Snap(g2)) })
			expect(log[1].got[1].parents).toBeNil()
			local received
			for _, m in M:All(y) do
				if m.line == "cindlet" then
					received = m
				end
			end
			expect(received.ped).toEqual(baby.ped)
			expect(received.ped ~= baby.ped).toBe(true)
		end)
	end)

	describe("Breeding target", function()
		it("sets, validates and clears the target", function()
			local h, p = boot({ level = 5 })
			expect(h:Reject(p, "Breeding.SetTarget", { stat = "atk", grade = "A" })).toContain("Level 12")
			levelTo(h, p, 12)
			expect(h:Section(p, "Breeding").target).toBe(false)
			h:Call(p, "Breeding.SetTarget", { stat = "atk", grade = "A" })
			expect(h:Section(p, "Breeding").target).toEqual({ stat = "atk", grade = "A" })
			expect(h:Client(p).profile.Breeding.target).toEqual({ stat = "atk", grade = "A" })
			h:Advance(1)
			expect(h:Reject(p, "Breeding.SetTarget", { stat = "luck" })).toContain("Pick a grade")
			h:Advance(1)
			expect(h:Reject(p, "Breeding.SetTarget", { stat = "luck", grade = "D" }) ~= "").toBe(true)
			h:Advance(1)
			expect(h:Reject(p, "Breeding.SetTarget", { stat = "mood", grade = "A" }) ~= "").toBe(true)
			expect(h:Section(p, "Breeding").target).toEqual({ stat = "atk", grade = "A" })
			h:Advance(1)
			h:Call(p, "Breeding.SetTarget", { grade = "S" }) -- no stat clears
			expect(h:Section(p, "Breeding").target).toBe(false)
		end)

		it("celebrates a baby that meets the target, not one that misses it", function()
			local h, p, M = boot()
			h:Call(p, "Breeding.SetTarget", { stat = "hp", grade = "B" })
			local a, b = adult(M, p, { genes = uniform(5, 5) }), adult(M, p, { genes = uniform(5, 5) })
			local res = breed(h, p, a, b)
			expect(res.targetMet).toBe(true)
			local want =
				string.format("Breeding target reached! HP grade %s", Genetics.Grade(Genetics.Points(res.monster.genes, "hp")).grade)
			local seen = false
			for _, e in h:Events(p, "Kernel.Notify") do
				seen = seen or e.payload.text == want
			end
			expect(seen).toBe(true)
			h:Advance(1)
			h:Call(p, "Breeding.SetTarget", { stat = "hp", grade = "S" })
			local c, d = adult(M, p, { genes = uniform(5, 5) }), adult(M, p, { genes = uniform(5, 5) })
			local before = #h:Events(p, "Kernel.Notify")
			local miss = breed(h, p, c, d)
			expect(miss.targetMet).toBe(false)
			for i = before + 1, #h:Events(p, "Kernel.Notify") do
				expect(string.find(h:Events(p, "Kernel.Notify")[i].payload.text, "target reached", 1, true)).toBeNil()
			end
		end)
	end)

	describe("Grade milestones", function()
		local function ribbons(h, p)
			return h:System("Currency"):Balance(p, "ribbons")
		end
		local function noS(genes)
			for _, stat in Stats do
				if genes[stat][1] + genes[stat][2] >= 18 then
					return false
				end
			end
			return true
		end

		it("pays 10 ribbons for the first A and the first S in each stat, once each", function()
			local h, p, M = boot()
			local reward = Config.Breeding.MilestoneRibbons
			-- Grade A in every stat (7 + 7 = 14, no surge up to S): five A milestones.
			local r0 = ribbons(h, p)
			breed(h, p, adult(M, p, { genes = uniform(7, 7) }), adult(M, p, { genes = uniform(7, 7) }), noS)
			expect(ribbons(h, p) - r0).toBe(5 * reward)
			expect(h:Section(p, "Breeding").milestones).toEqual({ hp = "A", atk = "A", def = "A", spd = "A", luck = "A" })
			local granted = h:LastEvent(p, "Rewards.Granted")
			expect(granted.payload.source).toBe("breeding_target")
			-- The same again pays nothing.
			local r1 = ribbons(h, p)
			breed(h, p, adult(M, p, { genes = uniform(7, 7) }), adult(M, p, { genes = uniform(7, 7) }), noS)
			expect(ribbons(h, p)).toBe(r1)
			-- Grade S everywhere: five S milestones, then never again.
			breed(h, p, adult(M, p, { genes = uniform(9, 9) }), adult(M, p, { genes = uniform(9, 9) }))
			expect(ribbons(h, p) - r1).toBe(5 * reward)
			local r2 = ribbons(h, p)
			breed(h, p, adult(M, p, { genes = uniform(10, 10) }), adult(M, p, { genes = uniform(10, 10) }))
			expect(ribbons(h, p)).toBe(r2)
			expect(ribbons(h, p) - r0).toBe(10 * reward) -- ten awards at most
		end)

		it("pays both A and S when a stat's first high grade is an S, target or not", function()
			local h, p, M = boot()
			local r0 = ribbons(h, p)
			local genes = { hp = { 10, 10 }, atk = { 0, 0 }, def = { 0, 0 }, spd = { 0, 0 }, luck = { 0, 0 } }
			breed(h, p, adult(M, p, { genes = genes }), adult(M, p, { genes = genes }), function(g)
				return g.atk[1] + g.atk[2] < 5
			end)
			expect(ribbons(h, p) - r0).toBe(2 * Config.Breeding.MilestoneRibbons)
			expect(h:Section(p, "Breeding").milestones).toEqual({ hp = "S" })
		end)
	end)

	describe("Save migration", function()
		it("adds target = false and milestones to a version 1 Breeding save", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local userId = 3939
			h.adapters.store["player_" .. userId] = {
				v = 1,
				data = {
					_meta = { created = 1690000000, lastSeen = 1700000500, joins = 3, playSeconds = 999, versions = { Breeding = 1 } },
					Breeding = {
						pods = {
							{ state = "idle", a = false, b = false, startedAt = 0, endsAt = 0, seed = 0 },
							{ state = "idle", a = false, b = false, startedAt = 0, endsAt = 0, seed = 0 },
						},
						daily = { day = 0, counts = {} },
						discovered = { cindlet = true },
					},
				},
			}
			local p = h:Join(userId, "Veteran")
			local s = h:Section(p, "Breeding")
			expect(h.kernel.Data:Get(p)._meta.versions.Breeding).toBe(2)
			expect(s.target).toBe(false)
			expect(s.milestones).toEqual({})
			expect(s.discovered.cindlet).toBe(true)
		end)
	end)
end
