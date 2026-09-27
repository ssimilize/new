--[[
	Dojo (update 3.11): the Dojo's rules (Logic/Dojo) and the system on the server: the unlock,
	learning and levelling up with Stardust and a timer (busy tag "dojo"), Collect and
	SkillTrained, forgetting (no refund), the 2nd slot at Bond heart 5, own-element techniques,
	one training at a time, Monsters:Insert keeping `tech`, Pedigree ignoring it, Trade's item
	view showing it, and the weekly goal dojo_3.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Dojo = t.Shared("Logic.Dojo")
	local Pedigree = t.Shared("Logic.Pedigree")

	local Rules = Config.Techniques

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
		levelTo(h, p, level or Config.Unlocks.Features.dojo)
		h:System("Currency"):Add(p, "stardust", 1e5, "test")
		return h, p, h:System("Monsters")
	end

	local function adult(M, p, fields)
		local spec = { line = "cindlet", rarity = 2, stage = 3, variant = 0 }
		for k, v in fields or {} do
			spec[k] = v
		end
		return M:Create(p, spec, "test", true)
	end

	local function stardust(h, p): number
		return h:Section(p, "Currency").stardust
	end

	-- Trains `tech` to its next level and collects it once the timer is done.
	local function trainAndCollect(h, p, m, tech: string)
		local res = h:Call(p, "Dojo.Train", { id = m.id, tech = tech })
		local _, seconds = Dojo.Cost(res.lv)
		h:Advance(seconds + 1)
		return h:Call(p, "Dojo.Collect")
	end

	describe("Dojo rules", function()
		it("opens a 2nd slot at Bond heart 5 and lists own-element techniques", function()
			expect(Dojo.Slots(0)).toBe(1)
			expect(Dojo.Slots(4)).toBe(1)
			expect(Dojo.Slots(5)).toBe(2)
			local ids = {}
			for _, tech in Dojo.Learnable({ line = "cindlet" }) do
				table.insert(ids, tech.id)
			end
			expect(ids).toEqual({ "flare_burst", "cinder_fang" })
			expect(#Rules.List).toBe(16)
			for _, e in Config.Elements.List do
				expect(#Rules.ByElement[e.id]).toBe(2)
			end
			expect({ Dojo.Cost(1) }).toEqual({ 300, 1200 })
			expect({ Dojo.Cost(2) }).toEqual({ 900, 3600 })
			expect({ Dojo.Cost(3) }).toEqual({ 2000, 10800 })
			-- Copies are deep and odd entries are dropped.
			local tech = { { id = "quake", lv = 2 } }
			local copy = Dojo.Copy(tech)
			expect(copy).toEqual(tech)
			copy[1].lv = 3
			expect(tech[1].lv).toBe(2)
			expect(Dojo.Copy({})).toBeNil()
			expect(Dojo.Known({ tech = { { id = "nope", lv = 1 }, { id = "quake", lv = 9 } } })).toEqual({ { id = "quake", lv = 3 } })
		end)
	end)

	describe("Dojo training", function()
		it("opens at Ranch Level 24", function()
			local h, p, M = boot(23)
			local m = adult(M, p)
			expect(h:Reject(p, "Dojo.Train", { id = m.id, tech = "cinder_fang" })).toContain("Ranch Level 24")
		end)

		it("learns with Stardust and a timer, holds the busy tag and publishes SkillTrained on Collect", function()
			local h, p, M = boot()
			local m = adult(M, p)
			local trained = {}
			h.kernel.Bus:Subscribe("SkillTrained", function(player, detail)
				if player == p then
					table.insert(trained, detail)
				end
			end)
			local before = stardust(h, p)
			local res = h:Call(p, "Dojo.Train", { id = m.id, tech = "cinder_fang" })
			expect(res.lv).toBe(1)
			expect(res.cost).toBe(300)
			expect(stardust(h, p)).toBe(before - 300)
			expect(m.busy).toBe("dojo")
			expect(m.tech).toBeNil()
			local s = h:Section(p, "Dojo")
			expect(s.training.id).toBe(m.id)
			expect(s.training.readyAt - s.training.startedAt).toBe(20 * 60)
			-- Busy: no expedition, trade or second training on the mat.
			local other = adult(M, p)
			expect(h:Reject(p, "Dojo.Train", { id = other.id, tech = "flare_burst" })).toContain("mat is taken")
			expect(h:Reject(p, "Dojo.Collect")).toContain("isn't finished")
			expect(h:Reject(p, "Dojo.Forget", { id = m.id, tech = "cinder_fang" })).toContain("finishes training")

			h:Advance(20 * 60 + 1)
			local got = h:Call(p, "Dojo.Collect")
			expect(got).toEqual({ id = m.id, tech = "cinder_fang", lv = 1 })
			expect(m.tech).toEqual({ { id = "cinder_fang", lv = 1 } })
			expect(m.busy).toBe(false)
			expect(s.training).toBe(false)
			expect(s.trained).toBe(1)
			expect(trained[1]).toEqual({ monsterId = m.id, skill = "cinder_fang", level = 1 })
			h:Advance(1)
			expect(h:Client(p).profile.Monsters.list[m.id].tech[1].id).toBe("cinder_fang")
		end)

		it("levels up to 3 at the promised costs and refuses past the top level", function()
			local h, p, M = boot()
			local m = adult(M, p)
			for lv = 1, 3 do
				local before = stardust(h, p)
				local got = trainAndCollect(h, p, m, "cinder_fang")
				expect(got.lv).toBe(lv)
				expect(stardust(h, p)).toBe(before - Rules.Train[lv].stardust)
			end
			expect(m.tech).toEqual({ { id = "cinder_fang", lv = 3 } })
			expect(h:Reject(p, "Dojo.Train", { id = m.id, tech = "cinder_fang" })).toContain("top level")
		end)

		it("keeps to its own element and opens the 2nd slot at Bond heart 5", function()
			local h, p, M = boot()
			local m = adult(M, p)
			expect(h:Reject(p, "Dojo.Train", { id = m.id, tech = "undertow" })).toContain("own element")
			trainAndCollect(h, p, m, "cinder_fang")
			expect(h:Reject(p, "Dojo.Train", { id = m.id, tech = "flare_burst" })).toContain("Bond heart 5")
			local Bond = h:System("Bond")
			while Bond:Hearts(p, m.id) < Rules.Slot2Hearts do
				expect(Bond:AddHeart(p, m.id, "test")).toBeTruthy()
			end
			trainAndCollect(h, p, m, "flare_burst")
			expect(m.tech).toEqual({ { id = "cinder_fang", lv = 1 }, { id = "flare_burst", lv = 1 } })
		end)

		it("forgets without a refund, and a replacement trains into the freed slot", function()
			local h, p, M = boot()
			local m = adult(M, p)
			trainAndCollect(h, p, m, "cinder_fang")
			trainAndCollect(h, p, m, "cinder_fang")
			local before = stardust(h, p)
			expect(h:Call(p, "Dojo.Forget", { id = m.id, tech = "cinder_fang" })).toEqual({ tech = "cinder_fang" })
			expect(m.tech).toBeNil()
			expect(stardust(h, p)).toBe(before)
			expect(h:Reject(p, "Dojo.Forget", { id = m.id, tech = "cinder_fang" })).toContain("doesn't know")
			local got = trainAndCollect(h, p, m, "flare_burst")
			expect(got.lv).toBe(1)
			expect(m.tech).toEqual({ { id = "flare_burst", lv = 1 } })
		end)

		it("refuses Babies and Teens", function()
			local h, p, M = boot()
			local teen = adult(M, p, { stage = 2 })
			expect(h:Reject(p, "Dojo.Train", { id = teen.id, tech = "cinder_fang" })).toContain("Only Adults")
		end)
	end)

	describe("Dojo techniques on the record", function()
		it("travel through Monsters:Insert, are ignored by Pedigree and show in Trade's item view", function()
			local h, p, M = boot()
			local m = adult(M, p)
			trainAndCollect(h, p, m, "cinder_fang")
			local copy = M:Insert(p, m, "test")
			expect(copy.tech).toEqual({ { id = "cinder_fang", lv = 1 } })
			expect(copy.tech ~= m.tech).toBe(true)
			expect(copy.tech[1] ~= m.tech[1]).toBe(true)
			expect(Pedigree.Snap(m).tech).toBeNil()
			local snap = Pedigree.Snap(m)
			local plain = table.clone(m)
			plain.tech = nil
			expect(Pedigree.Snap(plain)).toEqual(snap)

			-- Trade: the partner sees the offered monster's techniques.
			local b = h:Join(nil, "Bob")
			levelTo(h, b, Config.Unlocks.Features.dojo)
			for _, player in { p, b } do
				h.kernel.Data:Get(player)._meta.playSeconds = 3600
			end
			h:Call(p, "Trade.Request", { target = b.UserId })
			h:Call(b, "Trade.Respond", { from = p.UserId, accept = true })
			h:Call(p, "Trade.SetOffer", { items = { { kind = "monster", id = m.id } } })
			h:Advance(1)
			local theirs = h:Client(b).session.Trade.theirs
			expect(theirs.items[1].tech).toEqual({ { id = "cinder_fang", lv = 1 } })
		end)
	end)

	describe("Dojo weekly goal", function()
		it("counts dojo_3 from SkillTrained", function()
			local goal
			for _, g in Config.Weekly.Pool do
				if g.id == "dojo_3" then
					goal = g
				end
			end
			expect(goal ~= nil).toBe(true)
			expect(goal.family).toBe("dojo")
			expect(goal.unlock).toBe("dojo")
			expect(goal.topic).toBe("SkillTrained")
			local h, p, M = boot()
			local s = h:Section(p, "Weekly")
			s.goals = { { id = "dojo_3", progress = 0 }, { id = "feed_60", progress = 0 }, { id = "arena_wins_5", progress = 0 } }
			local m = adult(M, p)
			for _ = 1, 3 do
				trainAndCollect(h, p, m, "cinder_fang")
			end
			h:Step()
			expect(s.goals[1].progress).toBe(3)
		end)
	end)
end
