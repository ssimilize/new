--[[
	Bugs (update 3.13 · Wild things): the Bug Catching Meadow. The config and meadow placement, the
	seeded path and its net window, seasonal and night bugs only in their time, the honey lure's
	better odds, the unlock gate, 12 swings a UTC day and the reset, the server replay (a swing in
	the window catches; early, late, too quick and replayed ids do not), the lure spending honey
	through a stub Apiary, selling, the Bug Log counts, Codex milestones, the Insect Hall filling
	itself (and back-filling on join) and the weekly goal bugs_15.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Bugs")
	local Scenery = t.Shared("Logic.Scenery")
	local WeatherRoll = t.Shared("Logic.WeatherRoll")

	local Cfg = Config.Bugs
	local CORE = {
		"Currency",
		"Progression",
		"Rewards",
		"Monsters",
		"Eggs",
		"Shop",
		"Decor",
		"DigSite",
		"Fishing",
		"HallOfFame",
		"Mastery",
		"Codex",
		"Exhibits",
		"Weekly",
		"Bugs",
	}

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function boot(opts)
		opts = opts or {}
		local h = TestKernel.new({ systems = CORE, stubs = opts.stubs, startTime = opts.at })
		local caught = {}
		h.kernel.Bus:Subscribe("BugCaught", function(_, detail)
			table.insert(caught, detail)
		end)
		local p = h:Join()
		levelTo(h, p, opts.level or Config.Unlocks.Features.bug_meadow)
		return h, p, caught
	end

	local function middle(path): number
		local enter, leave = Logic.Window(path)
		return math.floor((enter + leave) / 2 * 1000 + 0.5) / 1000
	end

	-- One swing timed into the middle of the net window; returns the Submit result.
	local function catch(h, p)
		local res = h:Call(p, "Bugs.Start")
		local at = middle(res.path)
		h:Advance(at + 0.05)
		return h:Call(p, "Bugs.Submit", { id = res.id, t = at })
	end

	describe("Config and Logic", function()
		it("lists about 20 bugs in four rarities with a meadow scenery keeps off", function()
			expect(#Cfg.List >= 18).toBe(true)
			local seasons, nights = {}, 0
			for _, b in Cfg.List do
				expect(b.rarity >= 1 and b.rarity <= 4).toBe(true)
				expect(b.coins > 0).toBe(true)
				if b.season then
					seasons[b.season] = true
				end
				if b.night then
					nights += 1
				end
			end
			for _, id in { "spring", "summer", "autumn", "winter" } do
				expect(seasons[id]).toBe(true)
			end
			expect(nights > 0).toBe(true)
			expect(Config.Unlocks.Features.bug_meadow).toBe(17)
			local m = Config.World.BugMeadow
			expect(m.center[1]).toBe(-120)
			expect(m.center[2]).toBe(44)
			expect(m.radius <= 22).toBe(true)
			expect(table.find(Config.World.Scenery.keepOut, m) ~= nil).toBe(true)
			local others = {}
			for _, zone in Scenery.keepOut(Config) do
				if not (zone.r == m.radius and zone.x == m.center[1] and zone.z == m.center[2]) then
					table.insert(others, zone)
				end
			end
			expect(Scenery.blocked(others, m.center[1], m.center[2], m.radius)).toBe(false)
		end)

		it("replays the same path from the same seed, with narrower windows for rarer bugs", function()
			expect(Logic.Seed(1, 2, 3, 4)).toBe(Logic.Seed(1, 2, 3, 4))
			expect(Logic.Seed(1, 2, 3, 4) ~= Logic.Seed(1, 2, 4, 4)).toBe(true)
			local avg = {}
			for r = 1, 4 do
				local sum = 0
				for seed = 1, 150 do
					local a, b = Logic.Path(seed, r), Logic.Path(seed, r)
					expect(a).toEqual(b)
					local enter, leave = Logic.Window(a)
					expect(enter > 0 and leave > enter).toBe(true)
					expect(Logic.Hit(a, (enter + leave) / 2)).toBe(true)
					expect(Logic.Hit(a, enter - Cfg.Grace - 0.05)).toBe(false)
					expect(Logic.Hit(a, leave + Cfg.Grace + 0.05)).toBe(false)
					expect(Logic.Hit(a, a.total + 0.2)).toBe(false)
					sum += leave - enter
				end
				avg[r] = sum / 150
			end
			expect(avg[1] > avg[2] and avg[2] > avg[3] and avg[3] > avg[4]).toBe(true)
		end)

		it("rolls seasonal bugs only in their season and night bugs only at night", function()
			for _, season in { "spring", "summer", "autumn", "winter" } do
				for _, night in { false, true } do
					local seenSeasonal, seenNight = false, false
					for seed = 1, 3000 do
						local b = Logic.Roll(seed, season, night, true)
						expect(b.season == nil or b.season == season).toBe(true)
						expect(not b.night or night).toBe(true)
						seenSeasonal = seenSeasonal or b.season == season
						seenNight = seenNight or b.night == true
					end
					expect(seenSeasonal).toBe(true)
					expect(seenNight).toBe(night)
				end
			end
			-- The night flag is the Weather night phase.
			local LENGTH = Config.Weather.DayLength
			local base = 1790000000 - 1790000000 % LENGTH
			local dusk = base + math.floor(LENGTH * (1 - Config.Weather.NightFraction))
			expect(Logic.Night(dusk + 5)).toBe(true)
			expect(Logic.Night(dusk - 5)).toBe(false)
			expect(Logic.Night(dusk + 5)).toBe((WeatherRoll.Phase(dusk + 5)))
		end)

		it("rolls rarer bugs with the honey lure over a seeded sample", function()
			local plain, lured = 0, 0
			for seed = 1, 2000 do
				plain += Logic.Roll(seed, "spring", false, false).rarity
				lured += Logic.Roll(seed, "spring", false, true).rarity
			end
			expect(lured > plain * 1.15).toBe(true)
			local a, b = Logic.RarityChances(false), Logic.RarityChances(true)
			expect(b[3] + b[4] > a[3] + a[4]).toBe(true)
		end)
	end)

	describe("Swings", function()
		it("is locked before Ranch Level 17", function()
			local h, p = boot({ level = 1 })
			expect(h:Reject(p, "Bugs.Start")).toBe(string.format("Unlocks at Ranch Level %d", Config.Unlocks.Features.bug_meadow))
		end)

		it("gives 12 free swings a UTC day and resets them the next day", function()
			local h, p = boot()
			for i = 1, Cfg.FreeSwings do
				h:Advance(1)
				local res = h:Call(p, "Bugs.Start")
				expect(res.left).toBe(Cfg.FreeSwings - i)
				expect(res.id).toBe(i)
			end
			expect(h:Reject(p, "Bugs.Start")).toBe("No swings left today. Come back tomorrow")
			h:Advance(86400)
			expect(h:Call(p, "Bugs.Start").left).toBe(Cfg.FreeSwings - 1)
			expect(h:Section(p, "Bugs").secret ~= 0).toBe(true)
		end)

		it("catches a bug swung at inside the net and misses early or late swings", function()
			local h, p, caught = boot()
			local res = catch(h, p)
			expect(res.caught).toBe(true)
			local def = Cfg.ById[res.bug]
			expect(def ~= nil).toBe(true)
			expect(res.rarity).toBe(def.rarity)
			expect(res.first).toBe(true)
			local s = h:Section(p, "Bugs")
			expect(s.log[res.bug]).toBe(1)
			expect(s.jar[res.bug]).toBe(1)
			expect(s.total).toBe(1)
			expect(#caught).toBe(1)
			expect(caught[1].bug).toBe(res.bug)
			expect(caught[1].rarity).toBe(def.rarity)

			-- Early: before the bug reaches the net.
			local early = h:Call(p, "Bugs.Start")
			local enter, leave = Logic.Window(early.path)
			h:Advance(enter)
			local miss = h:Call(p, "Bugs.Submit", { id = early.id, t = math.max(0, enter - 0.3) })
			expect(miss.caught).toBe(false)
			expect(miss.bug).toBeNil()
			-- Late: after it has left.
			local late = h:Call(p, "Bugs.Start")
			enter, leave = Logic.Window(late.path)
			h:Advance(leave + 0.5)
			expect(h:Call(p, "Bugs.Submit", { id = late.id, t = leave + 0.3 }).caught).toBe(false)
			expect(s.total).toBe(1)
			expect(#caught).toBe(1)
		end)

		it("refuses a swing sent before its time, a replayed id and a very late one", function()
			local h, p = boot()
			local res = h:Call(p, "Bugs.Start")
			local at = middle(res.path)
			expect(h:Reject(p, "Bugs.Submit", { id = res.id, t = at })).toBe("That swing was too quick")
			expect(h:Reject(p, "Bugs.Submit", { id = res.id, t = at })).toBe("That bug has flown off. Swing again!")
			local again = h:Call(p, "Bugs.Start")
			h:Advance(again.path.total + Cfg.LateSeconds + 1)
			expect(h:Reject(p, "Bugs.Submit", { id = again.id, t = middle(again.path) })).toBe("That bug has flown off. Swing again!")
			-- A new Start replaces the open swing.
			local first = h:Call(p, "Bugs.Start")
			local second = h:Call(p, "Bugs.Start")
			h:Advance(5)
			expect(h:Reject(p, "Bugs.Submit", { id = first.id, t = 1 })).toBe("That bug has flown off. Swing again!")
			expect(second.id).toBe(first.id + 1)
		end)
	end)

	describe("Honey lure", function()
		it("spends 3 honey through the Apiary for 5 lured swings", function()
			local honey = 4
			local h, p = boot({
				stubs = {
					Apiary = {
						SpendAnyHoney = function(_, _player, n)
							if honey < n then
								return false
							end
							honey -= n
							return true
						end,
					},
				},
			})
			expect(h:Call(p, "Bugs.Lure").lure).toBe(Cfg.LureSwings)
			expect(honey).toBe(1)
			expect(h:Reject(p, "Bugs.Lure")).toBe("Your honey lure is still working")
			for i = 1, Cfg.LureSwings do
				h:Advance(1)
				expect(h:Call(p, "Bugs.Start").lure).toBe(Cfg.LureSwings - i)
			end
			expect(h:Reject(p, "Bugs.Lure")).toBe(string.format("You need %d honey for a lure", Cfg.LureHoney))
			expect(honey).toBe(1)
		end)

		it("is not offered without the Apiary", function()
			local h, p = boot()
			expect(h:Reject(p, "Bugs.Lure")).toBe("You need an Apiary for honey lures")
		end)
	end)

	describe("Uses", function()
		it("sells bugs from the jar for coins and keeps the log", function()
			local h, p = boot()
			local s = h:Section(p, "Bugs")
			s.jar.ladybug = 3
			s.log.ladybug = 3
			local coins = h:Section(p, "Currency").coins
			local res = h:Call(p, "Bugs.Sell", { bug = "ladybug", amount = 3 })
			expect(res.coins > 0).toBe(true)
			expect(h:Section(p, "Currency").coins).toBe(coins + res.coins)
			expect(s.jar.ladybug).toBeNil()
			expect(s.log.ladybug).toBe(3)
			expect(h:Reject(p, "Bugs.Sell", { bug = "ladybug", amount = 1 })).toBe("You don't have that many bugs")
			expect(h:System("Bugs"):Caught(p)).toEqual({ ladybug = 3 })
		end)

		it("pays the Bug Log milestones through Codex.Claim", function()
			local h, p = boot()
			local s = h:Section(p, "Bugs")
			for i = 1, 5 do
				s.log[Cfg.List[i].id] = 1
			end
			expect(h:System("Bugs"):SpeciesCaught(p)).toBe(5)
			local gems = h:Section(p, "Currency").gems
			local res = h:Call(p, "Codex.Claim", { milestone = "bug_5" })
			expect(res.gems).toBe(Config.Codex.Gems.bug[1])
			expect(h:Section(p, "Currency").gems).toBe(gems + res.gems)
			expect(h:Reject(p, "Codex.Claim", { milestone = "bug_10" })).toBe("Catch 5 more kinds of bug first")
		end)

		it("puts a bug in the Insect Hall on its first catch and back-fills on join", function()
			local h, p = boot()
			local res = catch(h, p)
			expect(res.caught).toBe(true)
			local filled = h:Section(p, "Exhibits").filled
			expect(filled.insects[res.bug]).toBe(true)
			expect(h:Section(p, "Bugs").jar[res.bug]).toBe(1) -- not used up
			-- A catch the Exhibits system missed fills on the next join.
			local other = if res.bug == "ladybug" then "monarch" else "ladybug"
			h:Section(p, "Bugs").log[other] = 2
			h:System("Exhibits").PlayerAdded(p)
			expect(h:Section(p, "Exhibits").filled.insects[other]).toBe(true)
		end)

		it("counts bugs_15 on BugCaught", function()
			local goal = Config.Weekly.ById.bugs_15
			expect(goal.family).toBe("bugs")
			expect(goal.unlock).toBe("bug_meadow")
			expect(goal.topic).toBe("BugCaught")
			expect(goal.target).toBe(15)
			local h, p = boot()
			local w = h:Section(p, "Weekly")
			w.goals = { { id = "bugs_15", progress = 0 } }
			expect(catch(h, p).caught).toBe(true)
			expect(w.goals[1].progress).toBe(1)
		end)
	end)
end
