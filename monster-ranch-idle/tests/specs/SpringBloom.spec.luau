-- Update 1.4 · Spring Bloom (calendar, Pollen Storm + Blossom, Bloom Egg, the hub egg
-- hunt), the Celestial Egg and the Season 2 Ranch Pass.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Events = Config.Events
	local HuntCfg = Config.EggHunt
	local Hunt = t.Shared("Logic.EggHunt")

	local BLOOM = Events.ById.springbloom
	local DURING = BLOOM.startsAt + 3600

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function standAt(p, spot: number)
		local pos = HuntCfg.Spots[spot]
		p.Character = { HumanoidRootPart = { Position = { X = pos[1], Y = pos[2] + 2, Z = pos[3] } } }
	end

	local function petals(h, p)
		return h:System("Currency"):Balance(p, "token.springbloom")
	end

	describe("Spring Bloom calendar and weather", function()
		it("runs in April after Lunar Lanterns without overlapping", function()
			expect(Events.ActiveId(BLOOM.startsAt - 1)).toBeNil()
			expect(Events.ActiveId(BLOOM.startsAt)).toBe("springbloom")
			expect(Events.ActiveId(BLOOM.endsAt)).toBeNil()
			expect(BLOOM.startsAt).toBeGreaterThan(Events.ById.lunarlanterns.endsAt)
			expect(os.date("!%d %b %Y", BLOOM.startsAt)).toBe("03 Apr 2027")
		end)

		it("rolls Pollen Storm only by day during the event, giving Blossom", function()
			local WeatherRoll = t.Shared("Logic.WeatherRoll")
			local index
			for i, w in Config.Weather.List do
				if w.id == "pollenstorm" then
					index = i
				end
			end
			expect(WeatherRoll.Weights({ night = false })[index]).toBe(0)
			expect(WeatherRoll.Weights({ night = true, event = "springbloom" })[index]).toBe(0)
			expect(WeatherRoll.Weights({ night = false, event = "springbloom" })[index]).toBeGreaterThan(0)
			expect(Config.Weather.ById.pollenstorm.mutation).toBe("blossom")
			expect(Config.Mutations.ById.blossom.mult).toBe(3)
		end)
	end)

	describe("Bloom and Celestial eggs", function()
		it("hatches the three Spring Bloom lines with Blossom", function()
			local EggRoll = t.Shared("Logic.EggRoll")
			local rng = t.Shared("Logic.Rng").new(9)
			local lines = {}
			for _ = 1, 300 do
				local spec = EggRoll.roll(rng, Config.Eggs.ById.bloom, {})
				lines[spec.line] = true
				expect(spec.muts).toEqual({ "blossom" })
				expect(Config.Species.ById[spec.line].event).toBe("springbloom")
			end
			expect(lines.budling and lines.pollenpuff and lines.tulipup).toBe(true)
		end)

		it("hatches only the celestial lines from the Celestial Egg", function()
			local EggRoll = t.Shared("Logic.EggRoll")
			local rng = t.Shared("Logic.Rng").new(4)
			local lines = {}
			for _ = 1, 300 do
				local spec = EggRoll.roll(rng, Config.Eggs.ById.celestial, {})
				lines[spec.line] = true
				expect(spec.rarity >= 3).toBe(true)
			end
			expect(lines.cometkit and lines.moonmoth and lines.orbiton).toBe(true)
			local n = 0
			for _ in lines do
				n += 1
			end
			expect(n).toBe(3)
		end)

		it("sells the Celestial Egg only to ranches with a Rebirth Star", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Rebirth" } })
			local p = h:Join()
			levelTo(h, p, 40)
			h:System("Currency"):Add(p, "coins", 20000000, "test")
			local function inStock()
				local n = h:Client(p).global.Shop.stock.celestial
				return n ~= nil and n ~= 0
			end
			for _ = 1, 60 do
				if inStock() then
					break
				end
				h:Advance(Config.Eggs.RestockSeconds)
			end
			expect(inStock()).toBe(true)
			expect(h:Reject(p, "Shop.BuyEgg", { egg = "celestial", amount = 1 })).toBe("Rebirth your ranch to unlock the Celestial Egg")
			h:Section(p, "Rebirth").stars = 1
			local bought = h:Call(p, "Shop.BuyEgg", { egg = "celestial", amount = 1 })
			expect(#bought.eggs).toBe(1)
		end)
	end)

	describe("Egg hunt", function()
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Events", "EggHunt", "Quests" }

		it("hides the same eggs on every server for each round", function()
			local round, endsAt = Hunt.Round(DURING)
			expect(endsAt - DURING <= HuntCfg.RoundSeconds).toBe(true)
			local a = Hunt.SpotsFor(round)
			expect(#a).toBe(HuntCfg.PerRound)
			expect(Hunt.SpotsFor(round)).toEqual(a)
			local seen = {}
			for _, i in a do
				expect(seen[i]).toBeNil()
				seen[i] = true
				expect(HuntCfg.Spots[i] ~= nil).toBe(true)
			end
			local differs = false
			for r = round + 1, round + 5 do
				if table.concat(Hunt.SpotsFor(r), ",") ~= table.concat(a, ",") then
					differs = true
				end
			end
			expect(differs).toBe(true)
			-- No spot sits inside a hub building or the fountain.
			for _, spot in HuntCfg.Spots do
				expect(Hunt.Distance(spot, Config.World.Fountain.position) > Config.World.Fountain.radius).toBe(true)
				for _, b in Config.World.Hub do
					local inside = math.abs(spot[1] - b.position[1]) < b.size[1] / 2 + 2
						and math.abs(spot[3] - b.position[3]) < b.size[3] / 2 + 2
					expect(inside).toBe(false)
				end
			end
		end)

		it("pays for each egg found nearby, once, with a bonus for the whole round", function()
			local h = TestKernel.new({ systems = SYSTEMS, startTime = DURING })
			local p = h:Join()
			local g = h:Client(p).global.EggHunt
			expect(g.active).toBe(true)
			expect(#g.spots).toBe(HuntCfg.PerRound)
			local start = petals(h, p)

			local first = g.spots[1]
			local missing = 1
			while table.find(g.spots, missing) do
				missing += 1
			end
			standAt(p, missing)
			expect(h:Reject(p, "EggHunt.Find", { spot = missing })).toBe("There's no egg there right now. New eggs hide every 20 minutes!")
			p.Character = nil
			expect(h:Reject(p, "EggHunt.Find", { spot = first })).toBe("Get closer to the egg")
			standAt(p, g.spots[2])
			expect(h:Reject(p, "EggHunt.Find", { spot = first })).toBe("Get closer to the egg")

			local found = {}
			for i, spot in g.spots do
				standAt(p, spot)
				h:Advance(1)
				found[i] = h:Call(p, "EggHunt.Find", { spot = spot })
			end
			expect(found[1].tokens).toBe(HuntCfg.Reward)
			expect(found[1].left).toBe(HuntCfg.PerRound - 1)
			expect(found[#found].complete).toBe(true)
			expect(found[#found].tokens).toBe(HuntCfg.Reward + HuntCfg.RoundBonus)
			expect(petals(h, p) - start).toBe(HuntCfg.PerRound * HuntCfg.Reward + HuntCfg.RoundBonus)
			h:Advance(1)
			expect(h:Reject(p, "EggHunt.Find", { spot = g.spots[#g.spots] })).toBe("You already found that egg")
			expect(h:Client(p).profile.EggHunt.total).toBe(HuntCfg.PerRound)
			expect(h:Section(p, "Quests").achievements.egghunt_20.progress).toBe(HuntCfg.PerRound)

			-- A rejoin in the same round does not bring the eggs back.
			p = h:Rejoin(p, 30)
			standAt(p, g.spots[1])
			expect(h:Reject(p, "EggHunt.Find", { spot = g.spots[1] })).toBe("You already found that egg")

			-- The next round hides fresh eggs.
			local _, endsAt = Hunt.Round(h.adapters.Clock.Now())
			h:Advance(endsAt - h.adapters.Clock.Now() + 6)
			local nextSpots = h:Client(p).global.EggHunt.spots
			expect(h:Client(p).global.EggHunt.round).toBe(g.round + 1)
			standAt(p, nextSpots[1])
			expect(h:Call(p, "EggHunt.Find", { spot = nextSpots[1] }).found).toBe(1)
		end)

		it("caps finds per day and closes with the event", function()
			local h = TestKernel.new({ systems = SYSTEMS, startTime = DURING })
			local p = h:Join()
			h:Section(p, "EggHunt").finds = HuntCfg.DailyFinds
			h:Section(p, "EggHunt").day = math.floor(h.adapters.Clock.Now() / 86400)
			local spot = h:Client(p).global.EggHunt.spots[1]
			standAt(p, spot)
			expect(h:Reject(p, "EggHunt.Find", { spot = spot })).toBe("You've found all the eggs you can today. Come back tomorrow!")

			local after = TestKernel.new({ systems = SYSTEMS, startTime = BLOOM.endsAt + 60 })
			local q = after:Join()
			expect(after:Client(q).global.EggHunt.active).toBe(false)
			standAt(q, 1)
			expect(after:Reject(q, "EggHunt.Find", { spot = 1 })).toBe("The egg hunt isn't on right now")
		end)
	end)

	describe("Season 2 Ranch Pass", function()
		local Q = Config.Quests

		it("switches to Season 2 when it starts and keeps Season 1 until then", function()
			local s1, s2 = Q.Seasons[1], Q.Seasons[2]
			expect(Q.PassAt(s1.startsAt - 10).season).toBe(1)
			expect(Q.PassAt(s1.startsAt + 10).season).toBe(1)
			expect(Q.PassAt(s1.endsAt + 86400).season).toBe(1)
			expect(Q.PassAt(s2.startsAt).season).toBe(2)
			expect(s2.startsAt >= s1.endsAt).toBe(true)
			expect(#s2.tiers).toBe(15)
			for _, tier in s2.tiers do
				for _, track in { tier.free, tier.premium } do
					for _, reward in track do
						if reward.kind == "egg" then
							expect(Config.Eggs.ById[reward.id] ~= nil).toBe(true)
						elseif reward.kind == "decor" then
							expect(Config.Decor.ById[reward.id] ~= nil).toBe(true)
						elseif reward.kind == "monster" then
							expect(Config.Species.ById[reward.id] ~= nil).toBe(true)
						end
					end
				end
			end
		end)

		it("starts a fresh Season 2 pass for players who had Season 1", function()
			local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Quests" }
			local h = TestKernel.new({ systems = SYSTEMS, startTime = Q.Seasons[1].startsAt + 3600 })
			local p = h:Join()
			local pass = h:Section(p, "Quests").pass
			expect(pass.season).toBe(1)
			pass.xp = 900
			p = h:Rejoin(p, Q.Seasons[2].startsAt - h.adapters.Clock.Now() + 60)
			pass = h:Section(p, "Quests").pass
			expect(pass.season).toBe(2)
			expect(pass.xp).toBe(0)
			expect(#pass.claimed.free).toBe(#Q.Seasons[2].tiers)
		end)
	end)
end
