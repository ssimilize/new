--[[
	HoneyStars (update 3.12 · Honey & stars): the four 3.12 systems together, with the real
	systems in place of the stand-ins each branch was built against. A finished star chart fills
	the Museum's Star Atlas and its hive-hours perk reaches the Apiary; honey from the Apiary is
	donated to the Honey Shelf; the Rewards kinds honey and tower_retry land in their systems;
	the Museum and Observatory appeal bonuses add up under the Tourists cap.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")

	local LENGTH = Config.Weather.DayLength
	local BASE = 1790000000 -- the harness's default start
	-- Early in a night, so the Observatory is open.
	local NIGHT = BASE - BASE % LENGTH + math.floor(LENGTH * (1 - Config.Weather.NightFraction)) + 5

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

	local function boot()
		local h = TestKernel.new({ systems = allSystems(), startTime = NIGHT })
		local p = h:Join()
		levelTo(h, p, Config.Unlocks.Features.trial_tower)
		return h, p
	end

	-- A chart that is open now (not seasonal, or in season) with a perk of `key`.
	local function chartWith(key: string)
		for _, c in Config.Observatory.Charts do
			if c.perk.key == key and not c.season then
				return c
			end
		end
		error("no all-year chart with perk " .. key)
	end

	-- Finishes `chart` with correct sightings (one night holds enough of them).
	local function finish(h, p, chart)
		for _ = 1, Config.Observatory.Observations do
			local res = h:Call(p, "Observatory.Start", { chart = chart.id })
			local taps = {}
			for i, star in res.order do
				table.insert(taps, { star = star, t = 0.5 + (i - 1) * 0.4 })
			end
			h:Advance(taps[#taps].t + 0.2)
			h:Call(p, "Observatory.Submit", { id = res.id, taps = taps })
		end
		expect(h:System("Observatory"):Charted(p)[chart.id]).toBe(true)
	end

	describe("Honey & stars together", function()
		it("fills the Star Atlas from a finished chart and gives the Apiary its extra storage hour", function()
			local h, p = boot()
			local donated = {}
			h.kernel.Bus:Subscribe("ExhibitDonated", function(_, detail)
				table.insert(donated, detail)
			end)
			local chart = chartWith("hive_hours")
			finish(h, p, chart)
			expect(h:Section(p, "Exhibits").filled.stars[chart.id]).toBe(true)
			expect(#donated).toBe(1)
			expect(donated[1].set).toBe("stars")
			expect(h:System("Observatory"):Perk(p, "hive_hours")).toBe(chart.perk.value)
			h:Advance(10)
			expect(h:Session(p, "Apiary").extra).toBe(chart.perk.value)
		end)

		it("donates the Apiary's honey and royal jelly to the Honey Shelf", function()
			local h, p = boot()
			local A = h:System("Apiary")
			A:AddHoney(p, "clover", 2)
			A:AddHoney(p, Config.Apiary.RoyalJelly.id, 1)
			h:Call(p, "Exhibits.Donate", { set = "honey", item = "clover" })
			h:Call(p, "Exhibits.Donate", { set = "honey", item = Config.Apiary.RoyalJelly.id })
			expect(A:Have(p, "clover")).toBe(1)
			expect(A:Have(p, Config.Apiary.RoyalJelly.id)).toBe(0)
			local filled = h:Section(p, "Exhibits").filled.honey
			expect(filled.clover).toBe(true)
			expect(filled[Config.Apiary.RoyalJelly.id]).toBe(true)
			expect(h:Reject(p, "Exhibits.Donate", { set = "honey", item = "frost" })).toBe("You don't have one to donate")
		end)

		it("pays the honey and tower_retry reward kinds into their systems", function()
			local h, p = boot()
			local retries = h:System("TrialTower"):AddRetries(p, 0)
			h:System("Rewards"):Grant(p, {
				{ kind = "honey", id = "frost", amount = 3 },
				{ kind = "tower_retry", amount = 2 },
			}, "test")
			expect(h:System("Apiary"):Have(p, "frost")).toBe(3)
			expect(h:System("TrialTower"):AddRetries(p, 0)).toBe(retries + 2)
		end)

		it("adds the Museum and Observatory appeal bonuses under the Tourists cap", function()
			local h, p = boot()
			local T = h:System("Tourists")
			expect(T:Appeal(p).bonus).toBe(0)
			local chart = chartWith("appeal")
			finish(h, p, chart)
			local fromStars = h:System("Observatory"):Perk(p, "appeal")
			expect(fromStars > 0).toBe(true)
			local fromMuseum = h:System("Exhibits"):Appeal(p)
			expect(T:Appeal(p).bonus).toBe(math.min(Config.Tourists.BonusMax, fromStars + fromMuseum))
			-- Fill every fossil and fish exhibit: the Museum's share grows, the total stays capped.
			local filled = h:Section(p, "Exhibits").filled
			filled.fossils = filled.fossils or {}
			for _, f in Config.DigSite.Fossils do
				filled.fossils[f.id] = true
			end
			filled.aquarium = filled.aquarium or {}
			for _, fish in Config.Fishing.Fish do
				filled.aquarium[fish.id] = true
			end
			local more = h:System("Exhibits"):Appeal(p)
			expect(more > fromMuseum).toBe(true)
			expect(T:Appeal(p).bonus).toBe(math.min(Config.Tourists.BonusMax, fromStars + more))
		end)
	end)
end
