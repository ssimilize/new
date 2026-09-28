--[[
	Strays (update 3.13 · Wild things): Stray Monsters. The slot clock (45-minute cadence with a
	per-player offset, a 20-minute stay), the seeded stray (night odds better over a sample, the
	line pool, honest hints), the unlock gate, the mood kept off session and client state, right
	answers befriending and wrong ones scaring it off, treats spent, one attempt per stray, the
	one-shot submit, the daily cap, the full-barn refusal, the adopted Adult with its gene bonus
	and StrayBefriended, the arrival toast and the weekly goal strays_3.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Strays")
	local Genetics = t.Shared("Logic.Genetics")
	local WeatherRoll = t.Shared("Logic.WeatherRoll")
	local Rng = t.Shared("Logic.Rng")

	local Cfg = Config.Strays
	local BASE = 1790000000
	local UID = 4242
	local SLOT = Logic.Slot(UID, BASE) + 1
	local ARRIVE = Logic.ArriveAt(UID, SLOT)

	local CORE = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Decor", "Weekly", "Strays" }

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	-- A server whose clock is `at` (default: 10 s after a stray arrives), the player at `level`.
	local function boot(opts)
		opts = opts or {}
		local h = TestKernel.new({ systems = CORE, startTime = opts.at or ARRIVE + 10 })
		local befriended = {}
		h.kernel.Bus:Subscribe("StrayBefriended", function(_, detail)
			table.insert(befriended, detail)
		end)
		local p = h:Join(UID)
		levelTo(h, p, opts.level or Config.Unlocks.Features.strays)
		h:Advance(1)
		return h, p, befriended
	end

	-- The stray's hidden mood, worked out the way the server does.
	local function moodOf(h, p, slot: number)
		local s = h:Section(p, "Strays")
		local P = h:System("Progression")
		local pool = Logic.Pool(function(key)
			return P:IsUnlocked(p, key)
		end)
		local night = WeatherRoll.Phase(Logic.ArriveAt(p.UserId, slot))
		return Logic.Roll(Logic.Seed(p.UserId, slot, s.secret), pool, night)
	end

	local function feed(h, p, n: number)
		for _, id in Config.Food.Ids do
			h:System("Currency"):Add(p, "food." .. id, n, "test")
		end
	end

	local function wrong(mood)
		local out = {}
		for i, want in mood do
			out[i] = if want == "wait" then "sour" else "wait"
		end
		return out
	end

	describe("Logic", function()
		it("keeps 45-minute slots with a per-player offset and a 20-minute stay", function()
			expect(Cfg.Interval).toBe(45 * 60)
			expect(Cfg.Stay).toBe(20 * 60)
			local a, b = Logic.Offset(1), Logic.Offset(2)
			expect(a >= 0 and a < Cfg.Interval).toBe(true)
			local differ = false
			for id = 2, 20 do
				if Logic.Offset(id) ~= a then
					differ = true
				end
			end
			expect(differ).toBe(true)
			expect(b >= 0 and b < Cfg.Interval).toBe(true)
			local slot = Logic.Slot(UID, BASE)
			expect(Logic.ArriveAt(UID, slot) <= BASE).toBe(true)
			expect(Logic.ArriveAt(UID, slot + 1) > BASE).toBe(true)
			expect(Logic.ArriveAt(UID, slot + 1) - Logic.ArriveAt(UID, slot)).toBe(Cfg.Interval)
			expect(Logic.LeavesAt(UID, slot) - Logic.ArriveAt(UID, slot)).toBe(Cfg.Stay)
			expect(Logic.Slot(UID, ARRIVE)).toBe(SLOT)
			expect(Logic.Slot(UID, ARRIVE - 1)).toBe(SLOT - 1)
		end)

		it("rolls better rarities at night over a seeded sample, from the same seed otherwise", function()
			local pool = Logic.Pool(function()
				return true
			end)
			local day, night = 0, 0
			for seed = 1, 600 do
				local d, n = Logic.Roll(seed, pool, false), Logic.Roll(seed, pool, true)
				day += d.rarity
				night += n.rarity
				expect(d.line).toBe(n.line)
				expect(d.mood).toEqual(n.mood)
				expect(#d.mood).toBe(Cfg.Rounds)
				expect(Logic.Roll(seed, pool, false)).toEqual(d)
			end
			expect(night > day * 1.15).toBe(true)
			expect(Logic.Roll(1, {}, false)).toBeNil()
		end)

		it("draws lines of buyable eggs only, maps every element to a treat and gives honest hints", function()
			local meadowOnly = Logic.Pool(function(key)
				return key == "egg_meadow"
			end)
			expect(#meadowOnly > 0).toBe(true)
			for _, line in meadowOnly do
				local def = Config.Species.ById[line]
				expect(def.event).toBeNil()
				expect(table.find(def.pools, "common") ~= nil).toBe(true)
			end
			for _, el in Config.Elements.List do
				expect(Config.Food.ById[Cfg.Favourite[el.id]] ~= nil).toBe(true)
			end
			expect(Logic.Hint("wait")).toBe(Cfg.WaitHint)
			expect(Logic.Hint("spicy")).toBe("It sniffs the air... something spicy?")
			expect(Logic.Favourite("cindlet")).toBe("spicy")
			expect(Logic.Name("cindlet")).toBe("Blazefang")
			expect(Logic.Score({ "wait", "spicy", "wait" }, { "wait", "sweet", "wait" })).toBe(2)
			expect(Logic.Befriended(2)).toBe(true)
			expect(Logic.Befriended(1)).toBe(false)
			expect(Logic.Cost({ "spicy", "wait", "spicy" })).toEqual({ ["food.spicy"] = 2 })
		end)

		it("raises one stat gene a grade", function()
			for seed = 1, 100 do
				local rng = Rng.new(seed)
				local genes = Genetics.Roll(rng)
				local out, stat = Logic.GeneBonus(genes, rng)
				local before, after = Genetics.Points(genes, stat), Genetics.Points(out, stat)
				expect(after > before).toBe(true)
				local g0, g1 = Genetics.Grade(before), Genetics.Grade(after)
				expect(g1.min > g0.min).toBe(true)
				for _, other in Config.Genetics.Stats do
					if other ~= stat then
						expect(Genetics.Points(out, other)).toBe(Genetics.Points(genes, other))
					end
				end
			end
			local top = { hp = { 10, 9 }, atk = { 10, 9 }, def = { 10, 9 }, spd = { 10, 9 }, luck = { 10, 9 } }
			local out, stat = Logic.GeneBonus(top, Rng.new(1))
			expect(Genetics.Points(out, stat)).toBe(20)
		end)
	end)

	describe("Visits", function()
		it("opens at Ranch Level 10 and shows no stray before", function()
			expect(Config.Unlocks.Features.strays).toBe(10)
			local h, p = boot({ level = 9 })
			expect(h:Session(p, "Strays").stray).toBe(false)
			expect(h:Reject(p, "Strays.Start", { slot = SLOT })).toContain("Ranch Level 10")
		end)

		it("shows the stray in session without its mood, stays 20 minutes, then wanders off", function()
			local h, p = boot({ at = Logic.LeavesAt(UID, SLOT) - 20 })
			local view = h:Session(p, "Strays").stray
			expect(view.slot).toBe(SLOT)
			expect(view.leavesAt).toBe(Logic.LeavesAt(UID, SLOT))
			expect(view.mood).toBeNil()
			expect(view.line).toBe(moodOf(h, p, SLOT).line)
			local client = h:Client(p)
			expect(client.profile.Strays.secret).toBeNil()
			expect(client.session.Strays.stray.mood).toBeNil()
			expect(h:Section(p, "Strays").met[view.line]).toBe(1)
			h:Advance(30)
			expect(h:Session(p, "Strays").stray).toBe(false)
			expect(h:Reject(p, "Strays.Start", { slot = SLOT })).toBe("That stray has wandered off")
		end)

		it("toasts a new arrival while online and has nothing for slots missed while away", function()
			local h, p = boot({ at = ARRIVE - 20 })
			expect(h:Session(p, "Strays").stray).toBe(false)
			h:Advance(30)
			local line = moodOf(h, p, SLOT).line
			local toast = h:LastEvent(p, "Kernel.Notify")
			expect(toast.payload.text).toBe(string.format("A stray %s is wandering near your gate!", Logic.Name(line)))
			expect(h:Session(p, "Strays").stray.slot).toBe(SLOT)
			-- Away for three slots: only the stray here now (if any) counts; nothing is owed.
			local q = h:Rejoin(p, Cfg.Interval * 3 + Cfg.Stay + 60)
			expect(h:Session(q, "Strays").stray).toBe(false)
			local met = 0
			for _, n in h:Section(q, "Strays").met do
				met += n
			end
			expect(met).toBe(1)
		end)
	end)

	describe("Befriending", function()
		it("befriends on right answers, spends the treats and adopts an Adult with a gene bonus", function()
			local h, p, befriended = boot()
			feed(h, p, 5)
			local mood = moodOf(h, p, SLOT)
			local res = h:Call(p, "Strays.Start", { slot = SLOT })
			expect(res.line).toBe(mood.line)
			expect(res.rarity).toBe(mood.rarity)
			for i, want in mood.mood do
				expect(res.hints[i]).toBe(Logic.Hint(want))
			end
			local out = h:Call(p, "Strays.Submit", { slot = SLOT, choices = mood.mood })
			expect(out.befriended).toBe(true)
			expect(out.correct).toBe(3)
			local spent = 0
			for _, want in mood.mood do
				if want ~= "wait" then
					spent += 1
				end
			end
			local fav = Logic.Favourite(mood.line)
			expect(h:System("Currency"):Balance(p, "food." .. fav)).toBe(5 - spent)
			local m = h:System("Monsters"):Get(p, out.id)
			expect(m.stage).toBe(3)
			expect(m.line).toBe(mood.line)
			expect(m.rarity).toBe(mood.rarity)
			local secret = h:Section(p, "Strays").secret
			local base = Genetics.Roll(Rng.new(Rng.seed("stray-adopt", UID, SLOT, secret)))
			expect(Genetics.Grade(Genetics.Points(m.genes, out.gene)).min > Genetics.Grade(Genetics.Points(base, out.gene)).min).toBe(true)
			expect(befriended).toEqual({ { line = mood.line, rarity = mood.rarity } })
			local s = h:Section(p, "Strays")
			expect(s.friends[mood.line]).toBe(1)
			expect(s.total).toBe(1)
			expect(s.adopted).toBe(1)
			-- One-shot: the same submit again is refused, and so is a second attempt.
			expect(h:Reject(p, "Strays.Submit", { slot = SLOT, choices = mood.mood })).toBe("That stray has wandered off")
			expect(h:Reject(p, "Strays.Start", { slot = SLOT })).toBe("You already tried to befriend this stray")
			expect(h:Session(p, "Strays").stray.tried).toBe(true)
		end)

		it("scares the stray off on wrong answers, one attempt only", function()
			local h, p, befriended = boot()
			feed(h, p, 5)
			local mood = moodOf(h, p, SLOT)
			local count = h:System("Monsters"):Count(p)
			h:Call(p, "Strays.Start", { slot = SLOT })
			-- Asking again while it is open gives the same hints (no reroll).
			local again = h:Call(p, "Strays.Start", { slot = SLOT })
			expect(again.line).toBe(mood.line)
			local out = h:Call(p, "Strays.Submit", { slot = SLOT, choices = wrong(mood.mood) })
			expect(out.befriended).toBe(false)
			expect(out.correct).toBe(0)
			expect(out.answers).toEqual(mood.mood)
			expect(h:System("Monsters"):Count(p)).toBe(count)
			expect(#befriended).toBe(0)
			expect(h:Reject(p, "Strays.Start", { slot = SLOT })).toBe("You already tried to befriend this stray")
		end)

		it("refuses a treat the player has no food for, using nothing", function()
			local h, p = boot()
			local mood = moodOf(h, p, SLOT)
			h:Call(p, "Strays.Start", { slot = SLOT })
			local err = h:Reject(p, "Strays.Submit", { slot = SLOT, choices = { "spicy", "wait", "wait" } })
			expect(err).toContain("Not enough")
			feed(h, p, Cfg.Rounds)
			local out = h:Call(p, "Strays.Submit", { slot = SLOT, choices = mood.mood })
			expect(out.befriended).toBe(true)
		end)

		it("stops at 3 adoptions a UTC day and refuses when the barn is full", function()
			local h, p = boot()
			local s = h:Section(p, "Strays")
			s.adopted = Cfg.DailyCap
			expect(h:Reject(p, "Strays.Start", { slot = SLOT })).toBe("You've befriended 3 strays today. More tomorrow!")
			s.day = 0 -- a new UTC day resets the count
			h:System("Monsters"):RegisterCapacityProvider(function()
				return 0
			end)
			expect(h:Reject(p, "Strays.Start", { slot = SLOT })).toBe("Your barn is full")
			expect(s.tried).toBe(-1)
		end)

		it("counts StrayBefriended for the weekly goal strays_3", function()
			local goal = Config.Weekly.ById.strays_3
			expect(goal.family).toBe("strays")
			expect(goal.unlock).toBe("strays")
			expect(goal.topic).toBe("StrayBefriended")
			expect(goal.target).toBe(3)
			local h, p = boot()
			feed(h, p, 5)
			local w = h:Section(p, "Weekly")
			w.goals = { { id = "strays_3", progress = 0 } }
			local mood = moodOf(h, p, SLOT)
			h:Call(p, "Strays.Start", { slot = SLOT })
			h:Call(p, "Strays.Submit", { slot = SLOT, choices = mood.mood })
			expect(w.goals[1].progress).toBe(1)
		end)
	end)
end
