-- S5 Breeding: Logic/Breeding odds, inheritance and the Breeding system (pods, limits, offline).
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Breeding")
	local Rng = t.Shared("Logic.Rng")
	local Formulas = t.Shared("Logic.Formulas")

	-- A plain adult record for pure-logic tests.
	local function parent(fields)
		local m = {
			id = "m1",
			line = "cindlet",
			stage = 3,
			form = "blazefang",
			rarity = 1,
			variant = 0,
			muts = {},
			traits = { 3, 4 },
			hidden = 5,
			weight = 3.2,
			lv = 1,
			stars = 1,
			mood = 70,
			gen = 0,
		}
		for k, v in fields or {} do
			m[k] = v
		end
		return m
	end

	local function pctOf(list, key, value)
		for _, entry in list do
			if entry[key] == value then
				return entry.pct
			end
		end
		return 0
	end

	describe("Logic/Breeding.Outcomes", function()
		it("gives 45/45/10 with a hybrid recipe and 50/50 without", function()
			local a = parent({ line = "cindlet" }) -- ember
			local b = parent({ line = "bubblin", form = "pearlfin" }) -- tide
			local o = Logic.Outcomes(a, b)
			expect(pctOf(o.species, "line", "cindlet")).toBeNear(45)
			expect(pctOf(o.species, "line", "bubblin")).toBeNear(45)
			expect(pctOf(o.species, "line", "steamling")).toBeNear(10)
			for _, entry in o.species do
				expect(entry.hybrid).toBe(entry.line == "steamling")
			end
			local plain = Logic.Outcomes(a, parent({ line = "mossbun", form = "thornbuck" }))
			expect(#plain.species).toBe(2)
			expect(pctOf(plain.species, "line", "mossbun")).toBeNear(50)
			local same = Logic.Outcomes(a, parent({ id = "m2" }))
			expect(#same.species).toBe(1)
			expect(same.species[1].pct).toBeNear(100)
		end)

		it("rolls rarity lower 60 / higher 32 / up 8, capped at Legendary", function()
			local o = Logic.Outcomes(parent({ rarity = 3 }), parent({ rarity = 4 }))
			expect(pctOf(o.rarity, "rarity", 3)).toBeNear(60)
			expect(pctOf(o.rarity, "rarity", 4)).toBeNear(32)
			expect(pctOf(o.rarity, "rarity", 5)).toBeNear(8)
			local sameTier = Logic.Outcomes(parent({ rarity = 2 }), parent({ rarity = 2 }))
			expect(pctOf(sameTier.rarity, "rarity", 2)).toBeNear(92)
			expect(pctOf(sameTier.rarity, "rarity", 3)).toBeNear(8)
			local capped = Logic.Outcomes(parent({ rarity = 4 }), parent({ rarity = 5 }))
			expect(pctOf(capped.rarity, "rarity", 5)).toBeNear(40)
			expect(pctOf(capped.rarity, "rarity", 6)).toBe(0)
			local legends = Logic.Outcomes(parent({ rarity = 5 }), parent({ rarity = 5 }))
			expect(pctOf(legends.rarity, "rarity", 5)).toBeNear(98)
			expect(pctOf(legends.rarity, "rarity", 6)).toBeNear(2)
			-- ascending order for the screen
			for i = 2, #o.rarity do
				expect(o.rarity[i].rarity).toBeGreaterThan(o.rarity[i - 1].rarity)
			end
		end)

		it("computes time, fee, mutation and variant chances", function()
			local a, b = parent({ rarity = 2 }), parent({ rarity = 4, line = "bubblin", form = "pearlfin" })
			local o = Logic.Outcomes(a, b)
			expect(o.seconds).toBe(Config.Breeding.Seconds[4])
			expect(o.fee).toBe(math.floor(0.1 * math.max(Formulas.Value(a), Formulas.Value(b))))
			expect(o.mutationChance).toBe(0)
			expect(o.rainbowChance).toBeNear(Config.Rarities.VariantChance.rainbow)
			expect(o.goldenChance).toBeNear(Config.Rarities.VariantChance.golden)

			local fertile = parent({ rarity = 4, traits = { 13, 3 } })
			expect(Logic.Outcomes(fertile, b).seconds).toBe(math.floor(Config.Breeding.Seconds[4] * 0.75))
			expect(Logic.Outcomes(fertile, parent({ id = "m9", traits = { 13, 4 } })).seconds).toBe(
				math.floor(Config.Breeding.Seconds[4] * 0.5)
			)

			local mutated = Logic.Outcomes(parent({ muts = { "soaked" } }), b)
			expect(mutated.mutationChance).toBeNear(0.2)
			local rainbows = Logic.Outcomes(parent({ variant = 2 }), parent({ variant = 2 }))
			expect(rainbows.rainbowChance).toBeNear(1 / 100)
			local golden = Logic.Outcomes(parent({ variant = 1 }), parent())
			expect(golden.goldenChance).toBeNear(1 / 20)
			local heart = Logic.Outcomes(parent({ variant = 1, hidden = 18 }), parent())
			expect(heart.goldenChance).toBeNear(3 / 20)
		end)
	end)

	describe("Logic/Breeding.Roll", function()
		it("matches the species and rarity odds over many rolls", function()
			local rng = Rng.new(2024)
			local a = parent({ line = "cindlet", rarity = 3 })
			local b = parent({ line = "bubblin", form = "pearlfin", rarity = 4 })
			local species, rarity, hybrids = {}, {}, 0
			local N = 20000
			for _ = 1, N do
				local spec, isHybrid = Logic.Roll(rng, a, b)
				species[spec.line] = (species[spec.line] or 0) + 1
				rarity[spec.rarity] = (rarity[spec.rarity] or 0) + 1
				if isHybrid then
					hybrids += 1
				end
			end
			expect(species.cindlet / N).toBeNear(0.45, 0.02)
			expect(species.bubblin / N).toBeNear(0.45, 0.02)
			expect(species.steamling / N).toBeNear(0.10, 0.015)
			expect(hybrids).toBe(species.steamling)
			expect(rarity[3] / N).toBeNear(0.60, 0.02)
			expect(rarity[4] / N).toBeNear(0.32, 0.02)
			expect(rarity[5] / N).toBeNear(0.08, 0.01)
			expect(rarity[6]).toBeNil()
		end)

		it("gives Mythic only from a Legendary pair, at about 2%", function()
			local rng = Rng.new(77)
			local mythic, N = 0, 20000
			for _ = 1, N do
				if Logic.Roll(rng, parent({ rarity = 5 }), parent({ rarity = 5 })).rarity == 6 then
					mythic += 1
				end
			end
			expect(mythic / N).toBeNear(0.02, 0.005)
		end)

		it("inherits traits per slot with a 12% fresh roll", function()
			local rng = Rng.new(5)
			local a = parent({ traits = { 1, 2 }, hidden = 5 })
			local b = parent({ traits = { 3, 4 }, hidden = 6 })
			local fresh, slots, hiddenFromParents = 0, 0, 0
			local N = 10000
			for _ = 1, N do
				local spec = Logic.Roll(rng, a, b)
				expect(#spec.traits).toBe(2)
				expect(spec.traits[1] ~= spec.traits[2]).toBe(true)
				expect(spec.hidden ~= spec.traits[1] and spec.hidden ~= spec.traits[2]).toBe(true)
				for _, id in spec.traits do
					slots += 1
					if id > 4 then
						fresh += 1
					end
				end
				if spec.hidden == 5 or spec.hidden == 6 then
					hiddenFromParents += 1
				end
			end
			-- 12% fresh rolls, and ~35% of those land back on a parent trait (1..4 hold 400 of the
			-- 1090 visible weight), so about 0.12 × 0.65 ≈ 7.8% of slots hold a brand-new trait
			expect(fresh / slots).toBeNear(0.078, 0.015)
			-- without Firstborn the hidden trait is rolled fresh: 5 and 6 hold ~21% of the weight left
			expect(hiddenFromParents / N).toBeNear(0.21, 0.04)
		end)

		it("passes a parent's hidden trait with Firstborn", function()
			local rng = Rng.new(6)
			local a = parent({ traits = { 1, 2 }, hidden = 17 }) -- Firstborn
			local b = parent({ traits = { 3, 4 }, hidden = 19 })
			for _ = 1, 500 do
				local spec = Logic.Roll(rng, a, b)
				expect(spec.hidden == 17 or spec.hidden == 19).toBe(true)
			end
		end)

		it("inherits a parent mutation 20% of the time", function()
			local rng = Rng.new(8)
			local a = parent({ muts = { "soaked" } })
			local b = parent({ muts = { "charged", "shadow" } })
			local inherited, N = 0, 10000
			for _ = 1, N do
				local spec = Logic.Roll(rng, a, b)
				if #spec.muts > 0 then
					inherited += 1
					expect(#spec.muts).toBe(1)
					local m = spec.muts[1]
					expect(m == "soaked" or m == "charged" or m == "shadow").toBe(true)
				end
			end
			expect(inherited / N).toBeNear(0.2, 0.02)
		end)

		it("rolls rainbow and golden variants from the parents", function()
			local rng = Rng.new(9)
			local rainbow, golden, N = 0, 0, 20000
			for _ = 1, N do
				if Logic.Roll(rng, parent({ variant = 2 }), parent({ variant = 2 })).variant == 2 then
					rainbow += 1
				end
				if Logic.Roll(rng, parent({ variant = 1 }), parent()).variant == 1 then
					golden += 1
				end
			end
			expect(rainbow / N).toBeNear(0.01, 0.004)
			expect(golden / N).toBeNear(0.05, 0.008)
		end)

		it("averages weight ±20%, bumps the generation and starts as a Baby", function()
			local rng = Rng.new(10)
			local a = parent({ weight = 4.0, gen = 2 })
			local b = parent({ weight = 6.0, gen = 5 })
			for _ = 1, 500 do
				local spec = Logic.Roll(rng, a, b)
				expect(spec.stage).toBe(1)
				expect(spec.gen).toBe(6)
				expect(spec.weight).toBeAtLeast(3.99)
				expect(spec.weight).toBeAtMost(6.01)
			end
		end)

		it("is deterministic for a seed", function()
			local a, b = parent({ line = "cindlet" }), parent({ line = "bubblin", form = "pearlfin" })
			local x = Logic.Roll(Rng.new(123), a, b)
			local y = Logic.Roll(Rng.new(123), a, b)
			expect(x).toEqual(y)
		end)
	end)

	-- System ---------------------------------------------------------------------------------

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Social", "Breeding" }

	-- Pins a player's monster capacity with one provider per kernel (Monsters keeps providers in
	-- module state, so a provider must never answer for another test's players).
	local function setCapacity(h, p, n)
		local M = h:System("Monsters")
		if not h.s5Capacity then
			local cap = {}
			h.s5Capacity = cap
			M:RegisterCapacityProvider(function(player)
				return cap[player.UserId] or 0
			end)
		end
		h.s5Capacity[p.UserId] = 0
		h.s5Capacity[p.UserId] = n - M:Capacity(p)
	end

	local function levelTo(h, p, level)
		local xp = 0
		for l = 1, level - 1 do
			xp += Config.Unlocks.XPToNext(l)
		end
		h:System("Progression"):AddXP(p, xp, "test")
	end

	local function adult(M, p, fields)
		local spec = { stage = 3, line = "cindlet", rarity = 2, traits = { 3, 4 }, hidden = 5 }
		for k, v in fields or {} do
			spec[k] = v
		end
		return M:Create(p, spec, "test", true)
	end

	local function boot(options)
		local opts = options or {}
		local h = TestKernel.new({ systems = SYSTEMS, stubs = opts.stubs })
		local p = h:Join()
		levelTo(h, p, opts.level or 12)
		local M = h:System("Monsters")
		setCapacity(h, p, 100)
		h:System("Currency"):Add(p, "coins", 1e9, "test")
		return h, p, M
	end

	local function onTopic(h, topic)
		local seen = {}
		h.kernel.Bus:Subscribe(topic, function(player, detail)
			table.insert(seen, { player = player, detail = detail })
		end)
		return seen
	end

	-- Finds a seed that rolls a hybrid for the pair and writes it into the running pod.
	local function forceHybrid(h, p, pod, a, b)
		for seed = 1, 5000 do
			local _, isHybrid = Logic.Roll(Rng.new(seed), a, b)
			if isHybrid then
				h:Section(p, "Breeding").pods[pod].seed = seed
				return seed
			end
		end
		error("no hybrid seed found")
	end

	describe("Breeding system", function()
		it("is locked until Ranch Level 12", function()
			local h, p, M = boot({ level = 5 })
			local a, b = adult(M, p), adult(M, p, { line = "bubblin" })
			expect(h:Reject(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })).toContain("Level 12")
		end)

		it("breeds two adults: fee, busy parents, timer, claim and XP", function()
			local h, p, M = boot()
			local bred = onTopic(h, "Bred")
			local a, b = adult(M, p), adult(M, p, { line = "mossbun", rarity = 3 })
			local coins = h:Section(p, "Currency").coins
			local fee = Logic.Fee(a, b)
			local data = h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
			expect(data.endsAt).toBe(h.adapters.Clock.Now() + Config.Breeding.Seconds[3])
			expect(h:Section(p, "Currency").coins).toBe(coins - fee)
			expect(a.busy).toBe("breeding")
			expect(b.busy).toBe("breeding")
			expect(h:Client(p).profile.Breeding.pods[1].state).toBe("running")
			expect(h:Session(p, "Breeding").podCount).toBe(1)
			expect(h:Session(p, "Breeding").breedsPerDay).toBe(2)

			expect(h:Reject(p, "Breeding.Claim", { pod = 1 })).toContain("Still breeding")
			h:Advance(Config.Breeding.Seconds[3])
			local xpBefore = h:Section(p, "Progression").xp
			local claim = h:Call(p, "Breeding.Claim", { pod = 1 })
			local baby = claim.monster
			expect(baby.stage).toBe(1)
			expect(baby.gen).toBe(1)
			expect(baby.line == "cindlet" or baby.line == "mossbun").toBe(true)
			expect(claim.hybridDiscovered).toBe(false)
			expect(a.busy).toBe(false)
			expect(b.busy).toBe(false)
			expect(h:Section(p, "Breeding").pods[1].state).toBe("idle")
			expect(h:Section(p, "Breeding").discovered[baby.line]).toBe(true)
			expect(#bred).toBe(1)
			expect(bred[1].detail.id).toBe(baby.id)
			expect(h:Section(p, "Progression").xp ~= xpBefore).toBe(true)
			expect(h:Reject(p, "Breeding.Claim", { pod = 1 })).toContain("Nothing is breeding")
		end)

		it("rejects bad pairs, busy parents and a second pod without the pass", function()
			local h, p, M = boot()
			local a, b, c = adult(M, p), adult(M, p), adult(M, p)
			local baby = M:Create(p, { line = "cindlet", rarity = 1 }, "test", true)
			expect(h:Reject(p, "Breeding.Start", { pod = 1, a = a.id, b = a.id })).toContain("two different")
			expect(h:Reject(p, "Breeding.Start", { pod = 1, a = a.id, b = baby.id })).toContain("Adult")
			expect(h:Reject(p, "Breeding.Start", { pod = 1, a = a.id, b = "m999" })).toContain("doesn't exist")
			expect(h:Reject(p, "Breeding.Start", { pod = 2, a = a.id, b = b.id })).toContain("Breeding Pod pass")
			h:Advance(2) -- rate limit: Start allows a burst of 4
			h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
			h:Advance(1)
			expect(h:Reject(p, "Breeding.Start", { pod = 1, a = c.id, b = a.id })).toContain("already in use")
			M:SetBusy(p, c.id, "expedition")
			local d = adult(M, p)
			h:Advance(1)
			expect(h:Reject(p, "Breeding.Cancel", { pod = 2 })).toContain("empty")
			h:Call(p, "Breeding.Cancel", { pod = 1 })
			expect(h:Reject(p, "Breeding.Start", { pod = 1, a = c.id, b = d.id })).toContain("busy")
		end)

		it("fails when coins are short", function()
			local h, p, M = boot()
			local a, b = adult(M, p, { rarity = 5, lv = 1 }), adult(M, p, { rarity = 5 })
			h:System("Currency"):Spend(p, { coins = h:Section(p, "Currency").coins }, "test")
			expect(h:Reject(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })).toContain("Not enough")
			expect(a.busy).toBe(false)
		end)

		it("limits breeds per monster per UTC day; cancel frees parents without a refund", function()
			local h, p, M = boot()
			local a, b = adult(M, p), adult(M, p)
			local coins = h:Section(p, "Currency").coins
			for _ = 1, 2 do
				h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
				h:Call(p, "Breeding.Cancel", { pod = 1 })
				h:Advance(1)
			end
			expect(a.busy).toBe(false)
			expect(h:Section(p, "Currency").coins).toBe(coins - 2 * Logic.Fee(a, b))
			expect(h:Reject(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })).toContain("no breeds left today")
			h:Advance(86400)
			h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
		end)

		it("adds per-day bonus providers and the Breeding Pod pass", function()
			local h, p, M = boot({
				stubs = {
					Monetization = {
						HasPass = function(_, _player, key)
							return key == "breedingPod"
						end,
					},
				},
			})
			h:System("Breeding"):RegisterBreedsPerDayBonus("test", function()
				return 1
			end)
			h:Advance(10)
			expect(h:Client(p).session.Breeding.breedsPerDay).toBe(3)
			expect(h:Client(p).session.Breeding.podCount).toBe(2)
			local a, b, c, d = adult(M, p), adult(M, p), adult(M, p), adult(M, p)
			h:Call(p, "Breeding.Start", { pod = 2, a = a.id, b = b.id })
			h:Call(p, "Breeding.Start", { pod = 1, a = c.id, b = d.id })
			for _ = 1, 2 do
				h:Advance(1)
				h:Call(p, "Breeding.Cancel", { pod = 2 })
				h:Call(p, "Breeding.Start", { pod = 2, a = a.id, b = b.id })
			end
			h:Advance(1)
			h:Call(p, "Breeding.Cancel", { pod = 2 })
			expect(h:Reject(p, "Breeding.Start", { pod = 2, a = a.id, b = b.id })).toContain("no breeds left")
		end)

		it("keeps the baby in the pod when the ranch is full, then gives the same baby", function()
			local h, p, M = boot()
			local a, b = adult(M, p), adult(M, p, { line = "bubblin" })
			h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
			local seed = h:Section(p, "Breeding").pods[1].seed
			local expected = Logic.Roll(Rng.new(seed), a, b)
			h:Advance(Config.Breeding.Seconds[2])
			setCapacity(h, p, M:Count(p))
			expect(h:Reject(p, "Breeding.Claim", { pod = 1 })).toContain("full")
			expect(a.busy).toBe("breeding")
			expect(h:Section(p, "Breeding").pods[1].state).toBe("running")
			setCapacity(h, p, 100)
			h:Advance(1)
			local baby = h:Call(p, "Breeding.Claim", { pod = 1 }).monster
			expect(baby.line).toBe(expected.line)
			expect(baby.traits).toEqual(expected.traits)
			expect(baby.weight).toBe(expected.weight)
		end)

		it("announces a hybrid discovery once per server", function()
			local h, p, M = boot()
			local bred = onTopic(h, "Bred")
			local a, b = adult(M, p, { line = "cindlet" }), adult(M, p, { line = "bubblin" })
			h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
			forceHybrid(h, p, 1, a, b)
			h:Advance(Config.Breeding.Seconds[2])
			local claim = h:Call(p, "Breeding.Claim", { pod = 1 })
			expect(claim.monster.line).toBe("steamling")
			expect(claim.hybridDiscovered).toBe(true)
			expect(bred[1].detail.hybrid).toBe(true)
			expect(bred[1].detail.discovery).toBe(true)
			local broadcast = h:LastEvent(p, "Social.Broadcast")
			expect(broadcast.payload.kind).toBe("discovery")
			expect(broadcast.payload.text).toContain("Steamling")

			-- a second rancher breeding the same hybrid here is not a server discovery
			local q = h:Join()
			levelTo(h, q, 12)
			setCapacity(h, q, 100)
			h:System("Currency"):Add(q, "coins", 1e9, "test")
			local c, d = adult(M, q, { line = "cindlet" }), adult(M, q, { line = "bubblin" })
			h:Call(q, "Breeding.Start", { pod = 1, a = c.id, b = d.id })
			forceHybrid(h, q, 1, c, d)
			h:Advance(Config.Breeding.Seconds[2])
			local claim2 = h:Call(q, "Breeding.Claim", { pod = 1 })
			expect(claim2.hybridDiscovered).toBe(true)
			expect(bred[2].detail.discovery).toBe(false)
		end)

		it("finishes while offline: Welcome Back item, parents stay busy until claimed", function()
			local h, p, M = boot()
			local welcome = onTopic(h, "WelcomeItem")
			local a, b = adult(M, p), adult(M, p)
			h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
			local p2 = h:Rejoin(p, 3 * 3600)
			local items = {}
			for _, w in welcome do
				if w.detail.kind == "breeding" then
					table.insert(items, w)
				end
			end
			expect(#items).toBe(1)
			expect(items[1].player).toBe(p2)
			setCapacity(h, p2, 100)
			expect(M:Get(p2, a.id).busy).toBe("breeding")
			h:Call(p2, "Breeding.Claim", { pod = 1 })
			expect(M:Get(p2, a.id).busy).toBe(false)
		end)

		it("tells an online player when a pod is ready", function()
			local h, p, M = boot()
			local a, b = adult(M, p), adult(M, p)
			h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
			h:Advance(Config.Breeding.Seconds[2] + 2)
			local toasts = 0
			for _, e in h:Events(p, "Kernel.Notify") do
				if string.find(e.payload.text, "Breeding Barn", 1, true) then
					toasts += 1
				end
			end
			expect(toasts).toBe(1)
		end)
	end)
end
