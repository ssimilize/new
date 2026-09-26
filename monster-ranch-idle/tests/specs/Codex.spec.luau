-- Glow-up O: Codex milestones (maths, claiming, double claims and exploits, badges, save
-- migration), the Hall of Fame plaza, and the Codex Museum's layout, LOD and pooling rules.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Codex")
	local Museum = t.Shared("Logic.Museum")

	local SYSTEMS = {
		"Currency",
		"Progression",
		"Rewards",
		"Monsters",
		"Eggs",
		"Shop",
		"Ranch",
		"Accessories",
		"HallOfFame",
		"Mastery",
		"Codex",
	}

	local function boot(systems)
		local h = TestKernel.new({ systems = systems or SYSTEMS })
		local p = h:Join()
		return h, p
	end

	-- Marks forms discovered the way Monsters records them.
	local function discover(h, p, formIds: { string })
		local codex = h:Section(p, "Monsters").codex
		for _, formId in formIds do
			local info = Config.Species.FormById[formId]
			local entry = codex[info.line.id]
			if not entry then
				entry = { forms = {}, variants = { normal = true }, count = 1 }
				codex[info.line.id] = entry
			end
			entry.forms[formId] = true
		end
	end

	local function milestone(id: string)
		local m = Logic.ById()[id]
		assert(m, "no milestone " .. id)
		return m
	end

	local function first(list, n)
		local out = {}
		for i = 1, n do
			out[i] = list[i]
		end
		return out
	end

	describe("Codex milestones (logic)", function()
		it("builds unique milestones whose rewards all exist", function()
			local seen = {}
			for _, m in Logic.Milestones() do
				expect(seen[m.id]).toBeNil()
				seen[m.id] = true
				expect(string.match(m.id, "^%d+$")).toBeNil()
				expect(m.need >= 1 and m.need <= #m.forms).toBe(true)
				for _, itemId in m.items do
					expect(Config.Mastery.ItemById[itemId] ~= nil).toBe(true)
				end
				for _, formId in m.forms do
					expect(Config.Species.FormById[formId] ~= nil).toBe(true)
				end
			end
			for _, item in Config.Codex.Items do
				if item.kind == "aura" then
					expect(t.Shared("Config.Vfx").Mastery[item.vfx] ~= nil).toBe(true)
				end
			end
		end)

		it("leaves event lines out of Complete and shares a track between eggs of one pool", function()
			local complete = milestone("complete")
			for _, formId in complete.forms do
				expect(Config.Species.FormById[formId].line.event).toBeNil()
			end
			expect(complete.all).toBe(true)
			local common = 0
			for _, m in Logic.Milestones() do
				if m.id == "egg_common" then
					common += 1
				end
			end
			expect(common).toBe(1)
			expect(milestone("egg_common").key).toBe("meadow")
			-- A region's track includes its bosses' lines (Coral Coast's Old Snapjaw).
			local coral = milestone("region_coral")
			expect(table.find(coral.forms, "tidecrusher") ~= nil).toBe(true)
			-- Element steps come before the element's "every form".
			expect(milestone("el_ember_3").need).toBe(3)
			expect(milestone("el_ember_all").order > milestone("el_ember_8").order).toBe(true)
		end)

		it("counts progress only from discovered forms of the track", function()
			local m = milestone("el_ember_all")
			local found = Logic.Found({ cindlet = { forms = { cindlet = true, kindlefox = true, bubblin = true } }, junk = 5 })
			local have, need = Logic.Progress(m, found)
			expect(have).toBe(2)
			expect(need).toBe(#m.forms)
			expect(Logic.IsDone(milestone("el_ember_3"), found)).toBe(false)
			expect(Logic.Claimable({ x = { forms = { cindlet = true, kindlefox = true, blazefang = true } } }, {})).toBe(1)
			expect(Logic.Claimable({ x = { forms = { cindlet = true, kindlefox = true, blazefang = true } } }, { el_ember_3 = 1 })).toBe(0)
		end)
	end)

	describe("Codex claims", function()
		it("claims a done milestone once and pays gems through the reward card", function()
			local h, p = boot()
			local before = h:Section(p, "Currency").gems
			discover(h, p, { "cindlet", "kindlefox", "blazefang" })
			expect(h:System("Codex"):ClaimableCount(p)).toBe(1)
			local data = h:Call(p, "Codex.Claim", { milestone = "el_ember_3" })
			expect(data.gems).toBe(Config.Codex.Gems.elementStep[1])
			expect(h:Section(p, "Currency").gems).toBe(before + data.gems)
			expect(h:LastEvent(p, "Rewards.Granted").payload.source).toBe("codex")
			expect(h:Client(p).profile.Codex.claimed.el_ember_3 ~= nil).toBe(true)
			expect(h:Client(p).profile.Codex.badges).toBeNil() -- private
			h:Advance(1)
			expect(h:Reject(p, "Codex.Claim", { milestone = "el_ember_3" })).toBe("Already claimed")
			expect(h:Section(p, "Currency").gems).toBe(before + data.gems)
			expect(h:System("Codex"):ClaimableCount(p)).toBe(0)
		end)

		it("refuses unknown, unfinished, malformed and too-fast claims", function()
			local h, p = boot()
			discover(h, p, { "cindlet" })
			expect(h:Reject(p, "Codex.Claim", { milestone = "el_ember_3" })).toBe("Find 2 more forms first")
			h:Advance(1)
			expect(h:Reject(p, "Codex.Claim", { milestone = "total_9999" })).toBe("That milestone doesn't exist")
			h:Advance(1)
			h:Reject(p, "Codex.Claim", { milestone = 12 })
			h:Advance(1)
			h:Reject(p, "Codex.Claim", {})
			h:Advance(1)
			h:Reject(p, "Codex.Claim", { milestone = string.rep("a", 60) })
			local tooFast
			for _ = 1, 6 do
				local res = h:Invoke(p, "Codex.Claim", { milestone = "el_ember_3" })
				if res.err == "TooFast" then
					tooFast = true
				end
			end
			expect(tooFast).toBe(true)
			expect(next(h:Section(p, "Codex").claimed)).toBeNil()
		end)

		it("grants element titles and wears one only when no title is worn", function()
			local h, p = boot()
			local ember = milestone("el_ember_all")
			local tide = milestone("el_tide_all")
			discover(h, p, ember.forms)
			discover(h, p, tide.forms)
			h:Call(p, "Codex.Claim", { milestone = "el_ember_all" })
			local mastery = h:Section(p, "Mastery")
			expect(mastery.owned.title_codex_ember).toBe(true)
			expect(mastery.equipped.title).toBe("title_codex_ember")
			h:Advance(1)
			h:Call(p, "Codex.Claim", { milestone = "el_tide_all" })
			expect(mastery.owned.title_codex_tide).toBe(true)
			expect(mastery.equipped.title).toBe("title_codex_ember")
			local here = h:Client(p).global.Mastery.here["u" .. p.UserId]
			expect(here.title).toBe("title_codex_ember")
			-- The title can be swapped in the Mastery screen like any other.
			h:Advance(1)
			h:Call(p, "Mastery.Equip", { kind = "title", item = "title_codex_tide" })
			expect(mastery.equipped.title).toBe("title_codex_tide")
		end)

		it("pays the whole Codex with a title, the Codex Crown aura and a badge, once", function()
			local h, p = boot()
			local awarded = {}
			h.adapters.Badges = {
				Award = function(userId, badgeId)
					table.insert(awarded, { userId, badgeId })
					return true
				end,
			}
			local old = Config.Codex.BadgeIds.complete
			Config.Codex.BadgeIds.complete = 123456
			local rebuiltBadge = milestone("complete").badge
			milestone("complete").badge = 123456
			local ok, err = pcall(function()
				discover(h, p, milestone("complete").forms)
				local data = h:Call(p, "Codex.Claim", { milestone = "complete" })
				expect(data.gems).toBe(Config.Codex.Gems.complete)
				local mastery = h:Section(p, "Mastery")
				expect(mastery.owned.title_codex_master).toBe(true)
				expect(mastery.owned.aura_codex_crown).toBe(true)
				expect(mastery.equipped.aura).toBe("aura_codex_crown")
				h:Advance(1)
				expect(#awarded).toBe(1)
				expect(awarded[1][2]).toBe(123456)
				p = h:Rejoin(p, 10)
				h:Advance(1)
				expect(#awarded).toBe(1)
				-- A monster of a Bronze+ line wears the Codex Crown through Mastery's one aura.
				expect(Config.Mastery.ItemById.aura_codex_crown.vfx).toBe("codexCrown")
			end)
			Config.Codex.BadgeIds.complete = old
			milestone("complete").badge = rebuiltBadge
			if not ok then
				error(err, 0)
			end
		end)

		it("retries a badge that failed and skips badges without an adapter", function()
			local h, p = boot()
			local m = milestone("el_ember_3")
			local oldBadge = m.badge
			m.badge = 777
			local ok, err = pcall(function()
				discover(h, p, first(m.forms, 3))
				h:Call(p, "Codex.Claim", { milestone = "el_ember_3" }) -- no adapter: skipped quietly
				expect(h:Section(p, "Codex").badges.el_ember_3).toBeNil()
				local calls = 0
				h.adapters.Badges = {
					Award = function()
						calls += 1
						if calls == 1 then
							error("BadgeService is down")
						end
						return true
					end,
				}
				p = h:Rejoin(p, 10)
				h:Advance(1)
				expect(calls).toBe(1)
				expect(h:Section(p, "Codex").badges.el_ember_3).toBeNil()
				p = h:Rejoin(p, 10)
				h:Advance(1)
				expect(calls).toBe(2)
				expect(h:Section(p, "Codex").badges.el_ember_3).toBe(true)
			end)
			m.badge = oldBadge
			if not ok then
				error(err, 0)
			end
		end)

		it("keeps cosmetics owed when Mastery is not plugged in", function()
			local list = {}
			for _, name in SYSTEMS do
				if name ~= "Mastery" then
					table.insert(list, name)
				end
			end
			local h, p = boot(list)
			discover(h, p, milestone("el_ember_all").forms)
			h:Call(p, "Codex.Claim", { milestone = "el_ember_all" })
			expect(h:Section(p, "Codex").owed[1]).toBe("title_codex_ember")
		end)

		it("keeps claims across a rejoin and migrates a damaged section", function()
			local h, p = boot()
			discover(h, p, first(milestone("el_ember_3").forms, 3))
			h:Call(p, "Codex.Claim", { milestone = "el_ember_3" })
			p = h:Rejoin(p, 60)
			h:Advance(1)
			expect(h:Reject(p, "Codex.Claim", { milestone = "el_ember_3" })).toBe("Already claimed")
			local section = h:System("Codex").Profile.Migrate({
				claimed = { el_ember_3 = 100, [5] = 1, bad = "x", old = true },
				owed = { "title_codex_ember", 7 },
				badges = { complete = true, nope = 1 },
				junk = "x",
			}, 0)
			expect(section.claimed.el_ember_3).toBe(100)
			expect(section.claimed.old).toBe(0)
			expect(section.claimed.bad).toBeNil()
			expect(section.claimed[5]).toBeNil()
			expect(#section.owed).toBe(1)
			expect(section.badges.complete).toBe(true)
			expect(section.badges.nope).toBeNil()
			expect(section.junk).toBeNil()
			local fresh = h:System("Codex").Profile.Migrate({}, 0)
			expect(next(fresh.claimed)).toBeNil()
		end)
	end)

	describe("Hall of Fame plaza", function()
		local function statue(rarity: number, formId: string)
			local info = Config.Species.FormById[formId]
			return {
				appearance = { line = info.line.id, form = formId, stage = info.stage, rarity = rarity },
				retiredAt = 1,
				rarity = rarity,
				element = info.line.elements[1],
			}
		end

		it("shows each player's best statue to everyone, capped, and frees the slot on leave", function()
			local oldMax = Config.Codex.Plaza.max
			Config.Codex.Plaza.max = 1
			local ok, err = pcall(function()
				local h = TestKernel.new({ systems = SYSTEMS })
				local a = h:Join(101, "Ana")
				local b = h:Join(102, "Ben")
				h:Section(a, "HallOfFame").entries = { statue(2, "kindlefox"), statue(5, "blazefang"), statue(5, "cindlet") }
				h:Section(b, "HallOfFame").entries = { statue(3, "bubblin") }
				a = h:Rejoin(a, 5)
				b = h:Rejoin(b, 5)
				local plaza = h:Client(b).global.HallOfFame.plaza
				expect(plaza.u101.name).toBe("Ana")
				expect(plaza.u101.appearance.form).toBe("blazefang")
				expect(plaza.u101.slot).toBe(1)
				expect(plaza.u102).toBeNil() -- the plaza is full: Ben waits
				h:Leave(a)
				h:Step()
				plaza = h:Client(b).global.HallOfFame.plaza
				expect(plaza.u101).toBeNil()
				expect(plaza.u102.slot).toBe(1)
				expect(plaza.u102.appearance.form).toBe("bubblin")
			end)
			Config.Codex.Plaza.max = oldMax
			if not ok then
				error(err, 0)
			end
		end)

		it("picks the rarest statue, newest first", function()
			expect(Museum.BestStatue({}) == nil).toBe(true)
			local best = Museum.BestStatue({ statue(3, "cindlet"), statue(4, "kindlefox"), statue(4, "blazefang") })
			expect(best.appearance.form).toBe("kindlefox")
			expect(Museum.FreeSlot({ u1 = { slot = 1 }, u2 = { slot = 3 } }, 3)).toBe(2)
			expect(Museum.FreeSlot({ u1 = { slot = 1 } }, 1)).toBeNil()
		end)
	end)

	describe("Codex Museum rules", function()
		it("lays out one pedestal per line inside the museum grounds", function()
			local layout = Museum.Layout(Config)
			local lines = {}
			for _, p in layout.pedestals do
				expect(lines[p.line]).toBeNil()
				lines[p.line] = true
			end
			expect(#layout.pedestals).toBe(#Config.Species.Lines)
			local zone = Config.World.CodexGrounds[1]
			local b = layout.bounds
			expect(b.minX >= zone.center[1] - zone.size[1] / 2).toBe(true)
			expect(b.maxX <= zone.center[1] + zone.size[1] / 2).toBe(true)
			expect(b.minZ >= zone.center[2] - zone.size[2] / 2).toBe(true)
			expect(b.maxZ <= zone.center[2] + zone.size[2] / 2).toBe(true)
			-- Plots stay clear of both grounds.
			for _, ground in Config.World.CodexGrounds do
				for _, plot in Config.World.Plots do
					local dx = math.abs(plot.center[1] - ground.center[1])
					local dz = math.abs(plot.center[3] - ground.center[2])
					local clear = dx > (Config.World.PlotSize[1] + ground.size[1]) / 2
						or dz > (Config.World.PlotSize[2] + ground.size[2]) / 2
					expect(clear).toBe(true)
				end
			end
		end)

		it("builds at most the cap of models, nearest first, and never for unknown lines", function()
			local pedestals = {}
			for i = 1, 40 do
				pedestals[i] = { line = "l" .. i, x = i * 3, z = 0 }
			end
			local known = {}
			for i = 1, 40 do
				known["l" .. i] = i ~= 2
			end
			local opts = { max = 5, modelRange = 60, signRange = 100 }
			local out, scratch = {}, {}
			Museum.Plan(pedestals, 0, 0, known, opts, out, scratch)
			local models = 0
			for i, state in out do
				if state == "model" then
					models += 1
					expect(i <= 6).toBe(true)
				end
			end
			expect(models).toBe(5)
			expect(out[2]).toBe("plate")
			expect(out[25]).toBe("sign") -- 75 studs: past the model range, within the sign range
			expect(out[40]).toBe("plate")
			-- Stepping a little keeps the current models (hysteresis), with no new tables.
			opts.previous = table.clone(out)
			Museum.Plan(pedestals, 4, 0, known, opts, out, scratch)
			local scratchSize = #scratch
			Museum.Plan(pedestals, 4, 0, known, opts, out, scratch)
			expect(#scratch).toBe(scratchSize)
			expect(out[1]).toBe("model")
			local after = 0
			for _, state in out do
				if state == "model" then
					after += 1
				end
			end
			expect(after).toBe(5)
		end)

		it("pools spare models by key and destroys the oldest past the cap", function()
			local destroyed = {}
			local pool = Museum.newPool(2, function(obj)
				table.insert(destroyed, obj)
			end)
			pool:Give("a", "A1")
			pool:Give("b", "B1")
			expect(pool:Take("a")).toBe("A1")
			expect(pool:Take("a")).toBeNil()
			pool:Give("c", "C1")
			pool:Give("d", "D1")
			expect(destroyed[1]).toBe("B1")
			expect(pool:Size()).toBe(2)
			pool:Clear()
			expect(#destroyed).toBe(3)
		end)
	end)
end
