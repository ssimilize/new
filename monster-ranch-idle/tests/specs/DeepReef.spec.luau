-- Deep Reef data (glow-up DR, roadmap 4.0 · Tides of the Deep): the region, its Egg, three Tide
-- lines that swim, and Config.DeepReef itself (the dock, the area and the swim tuning).
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local Config = t.Shared("Config")
	local Format = t.Shared("Logic.Format")
	local EggRoll = t.Shared("Logic.EggRoll")
	local Rng = t.Shared("Logic.Rng")

	local REEF = Config.Regions.ById.reef
	local SWIMMERS = { "finnip", "glowray", "shellkin" }

	describe("Deep Reef region", function()
		it("opens Sat 1 Jul 2028 at Ranch Level 64, after everything on the roadmap so far", function()
			expect(REEF.order).toBe(8)
			expect(REEF.unlock).toBe("region_reef")
			expect(Config.Unlocks.Features.region_reef).toBe(64)
			expect(Config.Unlocks.Names.region_reef).toBe("Deep Reef")
			expect(Format.date(REEF.opensAt)).toBe("1 Jul 2028")
			expect(os.date("!%A", REEF.opensAt)).toBe("Saturday")
			expect(os.date("!%H:%M", REEF.opensAt)).toBe("15:00")
			-- After 3.2's Frostbite Glacier (11 Mar 2028) and its Season 8 (ends 15 Apr 2028).
			expect(REEF.opensAt > Config.Regions.ById.glacier.opensAt).toBe(true)
			expect(Config.Regions.IsOpen(REEF, REEF.opensAt - 1)).toBe(false)
			expect(Config.Regions.IsOpen(REEF, REEF.opensAt)).toBe(true)
		end)

		it("has a level band, a boss track and loot in line with the other level-60+ regions", function()
			expect(REEF.levels[1] >= 60).toBe(true)
			expect(REEF.levels[2] > REEF.levels[1]).toBe(true)
			expect(REEF.rarity[1] >= 1 and REEF.rarity[2] <= 6).toBe(true)
			expect(Config.Regions.Stages(REEF.id)).toBe(Config.Regions.StagesPerRegion)
			for stage, boss in REEF.bosses do
				expect(stage >= 1 and stage <= Config.Regions.StagesPerRegion).toBe(true)
				expect(Config.Species.ById[boss.line] ~= nil).toBe(true)
				expect(Config.Species.FormById[boss.form] ~= nil).toBe(true)
			end
			for _, line in REEF.enemyLines do
				expect(Config.Species.ById[line] ~= nil).toBe(true)
				expect(Config.DeepReef.Swims(line)).toBe(true) -- every reef enemy swims
			end
			for _, egg in REEF.eggs do
				expect(Config.Eggs.ById[egg.egg] ~= nil).toBe(true)
				expect(egg.perMinute > 0).toBe(true)
			end
		end)
	end)

	describe("Reef Egg", function()
		it("hatches only Finnip, Glowray and Shellkin, all of them swims", function()
			expect(Config.Eggs.ById.reef.unlock).toBe("region_reef")
			expect(Config.Eggs.ById.reef.pool).toBe("reef")
			expect(Config.Species.Pools.reef).toEqual(SWIMMERS)
			local rng = Rng.new(77)
			local seen = {}
			for _ = 1, 300 do
				local spec = EggRoll.roll(rng, Config.Eggs.ById.reef, {})
				expect(table.find(SWIMMERS, spec.line) ~= nil).toBe(true)
				seen[spec.line] = true
			end
			for _, line in SWIMMERS do
				expect(seen[line]).toBe(true)
			end
			for _, egg in Config.Eggs.List do
				if egg.id ~= "reef" then
					for _, line in SWIMMERS do
						expect(table.find(Config.Species.Pools[egg.pool] or {}, line)).toBeNil()
					end
				end
			end
		end)
	end)

	describe("The three Tide lines", function()
		it("all swim, carry Tide, and have sane forms and stats", function()
			for _, id in SWIMMERS do
				local def = Config.Species.ById[id]
				expect(def.swims).toBe(true)
				expect(table.find(def.elements, "tide") ~= nil).toBe(true)
				expect(def.added).toBe("4.0")
				expect(#def.forms).toBe(3)
				expect(#def.forms[3] >= 1).toBe(true)
				expect(def.base.hp > 0 and def.base.atk > 0 and def.base.def > 0 and def.base.spd > 0).toBe(true)
				expect(Config.DeepReef.Swims(id)).toBe(true)
			end
			-- A boss form for each: the Kelp Warden (Shellkin) and the Lantern Tide (Glowray).
			expect(REEF.bosses[10].line).toBe("shellkin")
			expect(REEF.bosses[20].line).toBe("glowray")
		end)

		it("does not mark an unrelated, non-swimming line as a swimmer", function()
			expect(Config.DeepReef.Swims("mossbun")).toBe(false)
			expect(Config.DeepReef.Swims(nil)).toBe(false)
			expect(Config.DeepReef.Swims("not-a-line")).toBe(false)
		end)

		it("keeps every swims-flagged line already in the game swimming too", function()
			for _, id in { "bubblin", "shellsnap", "anglit", "jellow", "surfotter", "sunnyray", "tempestray", "floelet", "pengling" } do
				expect(Config.DeepReef.Swims(id)).toBe(true)
			end
		end)
	end)

	describe("Config.DeepReef", function()
		it("shapes the dock, the area and the swim tuning sanely", function()
			expect(#Config.DeepReef.Dock.position).toBe(3)
			expect(#Config.DeepReef.Area.center).toBe(3)
			expect(Config.DeepReef.Area.floorY < Config.DeepReef.Area.surfaceY).toBe(true)
			expect(Config.DeepReef.Area.radius > 0).toBe(true)
			local S = Config.DeepReef.Swim
			expect(S.speed > 0 and S.vertical > 0 and S.accel > 0 and S.drag > 0).toBe(true)
			expect(S.mountFactor > 1).toBe(true) -- a swimmer mount really is faster
			expect(S.mountMin > 1).toBe(true)
			expect(S.clipRate > 0 and S.clipRate < 1).toBe(true) -- strokes, not steps: slower than 1x
			local L = Config.DeepReef.Life
			expect(L.shafts.maxLow <= L.shafts.max).toBe(true)
			expect(L.fish.schoolsLow <= L.fish.schools).toBe(true)
			expect(L.fish.perSchoolLow <= L.fish.perSchool).toBe(true)
			expect(L.kelp.maxLow <= L.kelp.max).toBe(true)
			for _, name in Config.DeepReef.Light.layers do
				expect(type(name)).toBe("string")
			end
		end)
	end)
end
