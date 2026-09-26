-- S3 Eggs: starter egg, incubators, hatching, pity, Hatch Rush, offline hatches, trade hooks.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Ranch", "WelcomeBack" }

	-- A fake Monetization: passes, ad results and every call it received.
	local function fakeMonetization(opts)
		local m = { passes = opts and opts.passes or {}, adResult = true, ads = {}, queried = {} }
		function m:HasPass(_player, key)
			self.queried[key] = true
			return self.passes[key] == true
		end
		function m:WatchAd(_player, placement)
			table.insert(self.ads, placement)
			return self.adResult
		end
		function m:PaidRandomAllowed(_player)
			return true
		end
		return m
	end

	local function boot(opts)
		local o = opts or {}
		local stubs = {}
		local money = nil
		if o.monetization ~= false then
			money = fakeMonetization(o)
			stubs.Monetization = money
		end
		local h = TestKernel.new({ systems = SYSTEMS, stubs = stubs })
		local p = h:Join()
		return h, p, h:System("Eggs"), money
	end

	local function levelTo(h, p, level: number)
		local s = h:Section(p, "Progression")
		local need = -s.xp
		for l = s.level, level - 1 do
			need += Config.Unlocks.XPToNext(l)
		end
		h:System("Progression"):AddXP(p, need, "test")
		expect(s.level).toBe(level)
	end

	local function now(h)
		return h.adapters.Clock.Now()
	end

	local function hatchStarter(h, p)
		h:Advance(Config.Eggs.Starter.hatchSeconds)
		return h:Call(p, "Eggs.Hatch", { slot = 1 }).monster
	end

	describe("Eggs", function()
		it("places the starter egg in incubator 1 on first join", function()
			local h, p = boot()
			local s = h:Section(p, "Eggs")
			expect(#s.slots).toBe(5) -- 3.2: incubator 4 + the pass
			expect(s.slots[1].type).toBe("starter")
			expect(s.slots[1].egg).toBe(false)
			expect(s.slots[1].endsAt).toBe(now(h) + Config.Eggs.Starter.hatchSeconds)
			expect(s.slots[2].type).toBe(false)
			local client = h:Client(p)
			expect(client.profile.Eggs.slots[1].type).toBe("starter")
			expect(client.session.Eggs.slotCount).toBe(1)
			expect(client.session.Eggs.speed).toBe(0)
		end)

		it("hatches the starter into an Uncommon that walks into pen 1", function()
			local h, p, Eggs = boot()
			local hatchedTopic
			h.kernel.Bus:Subscribe("EggHatched", function(_, detail)
				hatchedTopic = detail
			end)
			expect(h:Reject(p, "Eggs.Hatch", { slot = 1 })).toContain("isn't ready")
			local monster = hatchStarter(h, p)
			expect(monster.rarity).toBe(2)
			expect(Config.Eggs.Starter.lines).toContain(monster.line)
			local ev = h:LastEvent(p, "Eggs.Hatched").payload
			expect(ev.slot).toBe(1)
			expect(ev.egg).toBe("starter")
			expect(ev.monster.id).toBe(monster.id)
			expect(hatchedTopic.egg).toBe("starter")
			expect(hatchedTopic.rarity).toBe(2)
			local s = h:Section(p, "Eggs")
			expect(s.slots[1].type).toBe(false)
			expect(s.hatched).toBe(1)
			expect(h:System("Ranch"):PenOf(p, monster.id)).toBe(1)
			expect(h:System("Monsters"):Get(p, monster.id).loc).toBe("pen")
			expect(h:Section(p, "Progression").xp).toBe(Config.Rarities.List[2].xp)
			expect(Eggs:PublicSlots(p)).toEqual({})
		end)

		it("lets the player choose the starter's line", function()
			local h, p = boot()
			h:Advance(Config.Eggs.Starter.hatchSeconds)
			expect(h:Reject(p, "Eggs.HatchAll")).toContain("starter")
			expect(h:Reject(p, "Eggs.Hatch", { slot = 1, starter = "blazefang" })).toBeTruthy()
			local monster = h:Call(p, "Eggs.Hatch", { slot = 1, starter = "bubblin" }).monster
			expect(monster.line).toBe("bubblin")
			expect(monster.rarity).toBe(Config.Eggs.Starter.rarity)
		end)

		it("gives the starter egg only once", function()
			local h, p = boot()
			hatchStarter(h, p)
			local p2 = h:Rejoin(p, 60)
			expect(h:Section(p2, "Eggs").slots[1].type).toBe(false)
			local h2, q = boot()
			local q2 = h2:Rejoin(q, 60) -- left before hatching: still one starter
			local count = 0
			for _, slot in h2:Section(q2, "Eggs").slots do
				if slot.type == "starter" then
					count += 1
				end
			end
			expect(count).toBe(1)
		end)

		it("places owned eggs into unlocked, empty incubators only", function()
			local h, p, Eggs = boot()
			hatchStarter(h, p)
			local ids = Eggs:Add(p, "meadow", "test", 3)
			expect(ids).toEqual({ "e1", "e2", "e3" })
			expect(Eggs:Count(p)).toBe(3)
			expect(h:Reject(p, "Eggs.Place", { egg = "e1", slot = 2 })).toContain("locked")
			expect(h:Reject(p, "Eggs.Place", { egg = "e1", slot = 5 })).toContain("locked")
			expect(h:Reject(p, "Eggs.Place", { egg = "e99", slot = 1 })).toContain("doesn't exist")
			local data = h:Call(p, "Eggs.Place", { egg = "e1", slot = 1 })
			expect(data.endsAt).toBe(now(h) + Config.Eggs.ById.meadow.hatchSeconds)
			expect(Eggs:Get(p, "e1")).toBeNil() -- incubating eggs leave storage (not tradable)
			expect(Eggs:Remove(p, "e1")).toBeNil()
			expect(h:Client(p).profile.Eggs.slots[1].egg).toBe("e1")
			expect(h:Reject(p, "Eggs.Place", { egg = "e2", slot = 1 })).toContain("busy")
			expect(Eggs:PublicSlots(p)).toEqual({ { type = "meadow", endsAt = data.endsAt } })

			-- Another player can't place eggs they don't own (ids are per player).
			local other = h:Join()
			h:Advance(8)
			expect(h:Reject(other, "Eggs.Place", { egg = "e2", slot = 1 })).toContain("busy")
			hatchStarter(h, other)
			expect(h:Reject(other, "Eggs.Place", { egg = "e2", slot = 1 })).toContain("doesn't exist")
		end)

		it("counts earned incubators plus the Extra Incubator pass, up to 4", function()
			local h, p, Eggs, money = boot({ passes = { extraIncubator = true } })
			expect(Eggs:SlotCount(p)).toBe(2)
			expect(h:Session(p, "Eggs").slotCount).toBe(2)
			levelTo(h, p, 3)
			expect(h:Session(p, "Eggs").slotCount).toBe(3)
			levelTo(h, p, 30)
			expect(h:Session(p, "Eggs").slotCount).toBe(4)
			money.passes.extraIncubator = false
			h.kernel.Bus:Publish("PassesChanged", p, { passes = money.passes })
			expect(h:Session(p, "Eggs").slotCount).toBe(3)
			expect(money.queried.extraIncubator).toBe(true)
		end)

		it("sums speed providers, caps them and fixes the timer at placement", function()
			local h, p, Eggs = boot()
			hatchStarter(h, p)
			Eggs:RegisterSpeedProvider("testA", function()
				return 0.5
			end)
			Eggs:RegisterSpeedProvider("testB", function()
				return 0.5
			end)
			Eggs:RegisterSpeedProvider("testBroken", function()
				error("boom")
			end)
			local ok, err = pcall(function()
				expect(Eggs:Speed(p)).toBe(Config.Economy.IncubatorSpeedCap)
				local id = Eggs:Add(p, "royal", "test")[1]
				local data = h:Call(p, "Eggs.Place", { egg = id, slot = 1 })
				expect(data.endsAt).toBe(now(h) + math.floor(3600 * 0.25 + 0.5))
			end)
			Eggs:RegisterSpeedProvider("testA", nil)
			Eggs:RegisterSpeedProvider("testB", nil)
			Eggs:RegisterSpeedProvider("testBroken", nil)
			assert(ok, err)
			expect(Eggs:Speed(p)).toBe(0)
			expect(h:Section(p, "Eggs").slots[1].endsAt).toBe(now(h) + 900) -- unchanged
		end)

		it("auto-places the best eggs and hatches everything that's ready", function()
			local h, p, Eggs = boot()
			hatchStarter(h, p)
			expect(h:Reject(p, "Eggs.PlaceAuto")).toContain("don't have any eggs")
			levelTo(h, p, 3)
			Eggs:Add(p, "meadow", "test", 2)
			Eggs:Add(p, "crystal", "test")
			Eggs:Add(p, "grove", "test")
			expect(h:Call(p, "Eggs.PlaceAuto").placed).toBe(2)
			local s = h:Section(p, "Eggs")
			expect(s.slots[1].type).toBe("crystal")
			expect(s.slots[2].type).toBe("grove")
			expect(Eggs:Count(p)).toBe(2)
			expect(h:Reject(p, "Eggs.PlaceAuto")).toContain("busy")
			expect(h:Reject(p, "Eggs.HatchAll")).toContain("No eggs are ready")
			h:Advance(Config.Eggs.ById.crystal.hatchSeconds)
			local data = h:Call(p, "Eggs.HatchAll")
			expect(#data.monsters).toBe(2)
			expect(s.slots[1].type).toBe(false)
			expect(s.slots[2].type).toBe(false)
			expect(s.hatched).toBe(3)
		end)

		it("refuses to hatch into a full ranch without burning the egg or pity", function()
			local h, p, Eggs = boot()
			local M = h:System("Monsters")
			hatchStarter(h, p)
			local id = Eggs:Add(p, "starlit", "test")[1]
			h:Call(p, "Eggs.Place", { egg = id, slot = 1 })
			h:Section(p, "Eggs").pity.starlit = 10
			while M:Count(p) < M:Capacity(p) do
				M:Create(p, { line = "mossbun", rarity = 1 }, "test", true)
			end
			h:Advance(Config.Eggs.ById.starlit.hatchSeconds)
			expect(h:Reject(p, "Eggs.Hatch", { slot = 1 })).toContain("full")
			expect(h:Reject(p, "Eggs.HatchAll")).toContain("full")
			local s = h:Section(p, "Eggs")
			expect(s.slots[1].type).toBe("starlit")
			expect(s.pity.starlit).toBe(10)
			-- Make room: now it hatches.
			for mid in M:All(p) do
				if M:Get(p, mid).line == "mossbun" and M:Get(p, mid).rarity == 1 then
					M:Remove(p, mid, "sell")
					break
				end
			end
			local monster = h:Call(p, "Eggs.Hatch", { slot = 1 }).monster
			expect(monster.rarity).toBeAtLeast(3)
			expect(s.pity.starlit == 0 or s.pity.starlit == 11).toBe(true)
		end)

		it("pays the Starlit pity and the Royal lucky meter from saved counters", function()
			local h, p, Eggs = boot()
			hatchStarter(h, p)
			levelTo(h, p, 3)
			local s = h:Section(p, "Eggs")
			s.pity.starlit = Config.Eggs.ById.starlit.pity.count - 1
			s.pity.royal = Config.Eggs.ById.royal.luckyMeter.every - 1
			local a = Eggs:Add(p, "starlit", "test")[1]
			local b = Eggs:Add(p, "royal", "test")[1]
			h:Call(p, "Eggs.Place", { egg = a, slot = 1 })
			h:Call(p, "Eggs.Place", { egg = b, slot = 2 })
			h:Advance(3600)
			local first = h:Call(p, "Eggs.Hatch", { slot = 1 }).monster
			local second = h:Call(p, "Eggs.Hatch", { slot = 2 }).monster
			expect(first.rarity).toBeAtLeast(5)
			expect(second.rarity).toBeAtLeast(4)
			expect(s.pity.starlit).toBe(0)
			expect(s.pity.royal).toBe(0)
			expect(h:Client(p).profile.Eggs.pity).toEqual({ starlit = 0, royal = 0 })
		end)

		it("asks Monetization for the Lucky Hatcher pass on every hatch", function()
			local h, p, _Eggs, money = boot({ passes = { luckyHatcher = true } })
			hatchStarter(h, p)
			expect(money.queried.luckyHatcher).toBe(true)
		end)

		it("shortens a timer with a Hatch Rush ad", function()
			local h, p, Eggs, money = boot()
			hatchStarter(h, p)
			expect(h:Reject(p, "Eggs.HatchRush", { slot = 1 })).toContain("empty")
			local id = Eggs:Add(p, "royal", "test")[1]
			local endsAt = h:Call(p, "Eggs.Place", { egg = id, slot = 1 }).endsAt
			local data = h:Call(p, "Eggs.HatchRush", { slot = 1 })
			expect(data.endsAt).toBe(endsAt - Config.Monetization.Ads.hatchRush.seconds)
			expect(money.ads).toEqual({ "hatchRush" })
			money.adResult = false
			h:Advance(1)
			expect(h:Reject(p, "Eggs.HatchRush", { slot = 1 })).toContain("didn't finish")
			expect(h:Section(p, "Eggs").slots[1].endsAt).toBe(data.endsAt)
			-- Monetization's own pre-check message wins when it has one.
			money.CanWatchAd = function()
				return false, "No more ads for this today. Come back tomorrow!"
			end
			h:Advance(1)
			expect(h:Reject(p, "Eggs.HatchRush", { slot = 1 })).toContain("No more ads")
			money.CanWatchAd = nil
			money.adResult = true
			h:Advance(1)
			for _ = 1, 3 do
				h:Call(p, "Eggs.HatchRush", { slot = 1 })
				h:Advance(1)
			end
			expect(h:Reject(p, "Eggs.HatchRush", { slot = 1 })).toContain("ready to hatch")
		end)

		it("says ads aren't available without Monetization", function()
			local h, p, Eggs = boot({ monetization = false })
			hatchStarter(h, p)
			local id = Eggs:Add(p, "grove", "test")[1]
			h:Call(p, "Eggs.Place", { egg = id, slot = 1 })
			expect(h:Reject(p, "Eggs.HatchRush", { slot = 1 })).toBe("Ads aren't available")
		end)

		it("keeps eggs that finished offline ready and lists them on Welcome Back", function()
			local h, p, Eggs = boot()
			hatchStarter(h, p)
			local id = Eggs:Add(p, "royal", "test")[1]
			h:Call(p, "Eggs.Place", { egg = id, slot = 1 })
			local p2 = h:Rejoin(p, 2 * 3600)
			local wb = h:Session(p2, "WelcomeBack")
			expect(wb.pending).toBe(true)
			expect(wb.items).toContain({ kind = "eggs", text = "1 egg ready to hatch" })
			local monster = h:Call(p2, "Eggs.Hatch", { slot = 1 }).monster
			expect(monster.rarity).toBeAtLeast(3)
		end)

		it("adds, removes and inserts eggs for grants and trades", function()
			local h, p, Eggs = boot()
			local added = {}
			h.kernel.Bus:Subscribe("EggAdded", function(_, detail)
				table.insert(added, detail)
			end)
			local ids = Eggs:Add(p, "grove", "boss", 2)
			expect(#ids).toBe(2)
			expect(added[1]).toEqual({ id = ids[1], type = "grove", source = "boss" })
			local record = Eggs:Remove(p, ids[1])
			expect(record.type).toBe("grove")
			expect(Eggs:Get(p, ids[1])).toBeNil()
			local other = h:Join()
			local newId = Eggs:Insert(other, record, "trade")
			expect(Eggs:Get(other, newId).type).toBe("grove")
			expect(Eggs:Get(other, newId).source).toBe("trade")
			expect(#Eggs:Add(p, "nope", "test")).toBe(0)
			expect(Eggs:Insert(p, { type = "nope" }, "trade")).toBeNil()
			expect(Eggs:Room(p)).toBe(Config.Economy.MaxEggs - 1)
			-- Rewards grants eggs through Eggs:Add.
			h:System("Rewards"):Grant(p, { { kind = "egg", id = "meadow", amount = 2 } }, "quest")
			expect(Eggs:Count(p)).toBe(3)
		end)

		it("rejects bad payloads before any rule runs", function()
			local h, p = boot()
			expect(h:Reject(p, "Eggs.Place", { egg = "e1", slot = 0 })).toBe("BadRequest")
			expect(h:Reject(p, "Eggs.Hatch", { slot = "1" })).toBe("BadRequest")
			expect(h:Reject(p, "Eggs.PlaceAuto", { extra = true })).toBe("BadRequest")
		end)
	end)
end
