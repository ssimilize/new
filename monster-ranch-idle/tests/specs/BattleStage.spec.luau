-- Glow-up V: Logic/BattleStage (pure planning for the 3D battle stage) as plain units.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local Plan = t.Shared("Logic.BattleStage")
	local Tuning = t.Shared("Config.BattleStage")

	local function unit(key: string, side: string, boss: boolean?, maxHp: number?)
		return { key = key, side = side, boss = boss or false, maxHp = maxHp or 100, name = key }
	end

	local function squad(n: number, side: string, boss: boolean?)
		local prefix = if side == "enemy" then "e" else "a"
		local list = {}
		for i = 1, n do
			table.insert(list, unit(prefix .. i, side))
		end
		if boss then
			table.insert(list, unit((if side == "enemy" then "e" else "a") .. "boss", side, true))
		end
		return list
	end

	describe("BattleStage.Choose", function()
		it("falls back to 2D when the camera isn't free", function()
			local mode, reason = Plan.Choose({ units = 4, low = false, cameraFree = false }, Tuning)
			expect(mode).toBe("2d")
			expect(reason).toBe("camera")
		end)

		it("falls back to 2D on Low quality past the unit cap", function()
			local under = Plan.Choose({ units = Tuning.fallback.lowMaxUnits, low = true, cameraFree = true }, Tuning)
			local over = Plan.Choose({ units = Tuning.fallback.lowMaxUnits + 1, low = true, cameraFree = true }, Tuning)
			expect(under).toBe("3d")
			expect(over).toBe("2d")
		end)

		it("falls back to 2D when the frame is too slow", function()
			local fine = Plan.Choose({ units = 4, low = false, cameraFree = true, frameMs = Tuning.fallback.maxFrameMs }, Tuning)
			local slow = Plan.Choose({ units = 4, low = false, cameraFree = true, frameMs = Tuning.fallback.maxFrameMs + 1 }, Tuning)
			expect(fine).toBe("3d")
			expect(slow).toBe("2d")
		end)
	end)

	describe("BattleStage.Theme", function()
		it("picks a region theme and falls back to default", function()
			expect(Plan.Theme(Tuning, "meadow")).toBe(Tuning.themes.meadow)
			expect(Plan.Theme(Tuning, "arena")).toBe(Tuning.themes.arena)
			expect(Plan.Theme(Tuning, "raid")).toBe(Tuning.themes.raid)
			expect(Plan.Theme(Tuning, "not_a_region")).toBe(Tuning.themes.default)
			expect(Plan.Theme(Tuning)).toBe(Tuning.themes.default)
		end)
	end)

	describe("BattleStage.Placement", function()
		for n = 1, 8 do
			it(string.format("lays out %d allies and %d enemies without overlap", n, n), function()
				local units = {}
				for _, u in squad(n, "ally") do
					table.insert(units, u)
				end
				for _, u in squad(n, "enemy") do
					table.insert(units, u)
				end
				local placement = Plan.Placement(units, Tuning)
				local seen = {}
				for _, u in units do
					local spot = placement[u.key]
					expect(spot ~= nil).toBe(true)
					local sign = if u.side == "enemy" then 1 else -1
					expect(spot.x * sign > 0).toBe(true) -- allies at x<0, enemies at x>0
					local at = tostring(spot.x) .. "," .. tostring(spot.z)
					expect(seen[at]).toBeNil()
					seen[at] = true
				end
			end)
		end

		it("stands a raid boss behind its row, bigger", function()
			local units = squad(8, "ally")
			for _, u in squad(1, "enemy", true) do
				table.insert(units, u)
			end
			local placement = Plan.Placement(units, Tuning)
			local boss = placement["eboss"]
			expect(boss.boss).toBe(true)
			expect(boss.scale).toBe(Tuning.scale.boss)
			for _, u in units do
				if u.side == "enemy" and not u.boss then
					expect(boss.x > placement[u.key].x).toBe(true) -- further from the centre line
				end
			end
		end)

		it("centres a lone boss with no row in front of it", function()
			local units = squad(1, "enemy", true)
			table.remove(units, 1) -- keep only the boss
			local placement = Plan.Placement(units, Tuning)
			expect(placement["eboss"].z).toBe(0)
		end)
	end)

	describe("BattleStage.Size", function()
		it("clamps the drawn scale between min and max and grows a boss", function()
			local tiny = Plan.Size(0.2, false, Tuning)
			local huge = Plan.Size(5, false, Tuning)
			local mid = Plan.Size(1, false, Tuning)
			local boss = Plan.Size(1, true, Tuning)
			expect(tiny > 0).toBe(true)
			expect(huge > 0).toBe(true)
			expect(boss > mid).toBe(true)
		end)
	end)

	describe("pace and shots", function()
		local function events(n: number, kinds: { string }?)
			local list = {}
			for i = 1, n do
				table.insert(list, { turn = 1, actor = "a1", target = "e1", kind = (kinds and kinds[i]) or "hit", amount = 5, hp = 90 })
			end
			return list
		end

		it("clamps the per-event step to pace.min/.max", function()
			expect(Plan.Step(1000, Tuning.pace)).toBe(Tuning.pace.min)
			expect(Plan.Step(1, Tuning.pace)).toBe(Tuning.pace.max)
		end)

		it("adds pace.extra after a crit/special/faint", function()
			local step = Plan.Step(10, Tuning.pace)
			expect(Plan.Pause({ kind = "hit" }, step, Tuning.pace)).toBe(step)
			expect(Plan.Pause({ kind = "crit" }, step, Tuning.pace)).toBe(step + Tuning.pace.extra)
			expect(Plan.Pause({ kind = "faint" }, step, Tuning.pace)).toBe(step + Tuning.pace.extra)
		end)

		it("finds the finishing blow just before the last faint", function()
			-- BattleSim logs a faint with the same actor/target as the hit that caused it.
			local list = {
				{ turn = 1, actor = "a1", target = "e1", kind = "hit", amount = 5, hp = 50 },
				{ turn = 1, actor = "a1", target = "e1", kind = "crit", amount = 50, hp = 0 },
				{ turn = 1, actor = "a1", target = "e1", kind = "faint", hp = 0 },
			}
			expect(Plan.FinishingBlow(list)).toBe(2)
		end)

		it("opens on a wide shot and closes on the finishing blow", function()
			local units = { unit("a1", "ally", false, 100), unit("e1", "enemy", false, 100) }
			local list = {
				{ turn = 1, actor = "a1", target = "e1", kind = "hit", amount = 10, hp = 90 },
				{ turn = 2, actor = "a1", target = "e1", kind = "crit", amount = 90, hp = 0 },
				{ turn = 2, actor = "a1", target = "e1", kind = "faint", hp = 0 },
			}
			local shots = Plan.Shots(list, units, Tuning)
			expect(shots[1].kind).toBe("wide")
			expect(shots[2].kind).toBe("close")
		end)

		it("never cuts twice within minCut seconds", function()
			local units = { unit("a1", "ally"), unit("e1", "enemy") }
			local list = events(6, { "crit", "crit", "crit", "crit", "crit", "crit" })
			local shots = Plan.Shots(list, units, Tuning)
			local step = Plan.Step(#list, Tuning.pace)
			local times, t = {}, Tuning.pace.lead
			for i, ev in list do
				if shots[i] then
					table.insert(times, t)
				end
				t += Plan.Pause(ev, step, Tuning.pace)
			end
			for i = 2, #times do
				expect(times[i] - times[i - 1] >= Tuning.camera.minCut - 1e-6).toBe(true)
			end
		end)
	end)

	describe("BattleStage.Limiter", function()
		it("caps how many start in the same second", function()
			local lim = Plan.Limiter(5, 1)
			expect(lim:Take(0)).toBe(true)
			expect(lim:Take(0)).toBe(false) -- perSecond = 1 already spent this second
			expect(lim:Take(1)).toBe(true) -- a new second
		end)

		it("caps how many are alive at once, freed by Done", function()
			local lim = Plan.Limiter(1, 99)
			expect(lim:Take(0)).toBe(true)
			expect(lim:Take(0.01)).toBe(false) -- live cap reached even though the rate allows it
			lim:Done()
			expect(lim:Take(0.02)).toBe(true)
		end)

		it("a priority take ignores the per-second rate but not the live cap", function()
			local lim = Plan.Limiter(1, 0)
			expect(lim:Take(0)).toBe(false) -- perSecond 0 blocks a normal take
			expect(lim:Take(0, true)).toBe(true)
			expect(lim:Take(0, true)).toBe(false) -- live cap 1
		end)

		it("live = 0 never takes", function()
			local lim = Plan.Limiter(0, 99)
			expect(lim:Take(0)).toBe(false)
		end)
	end)

	describe("BattleStage.Caps", function()
		it("returns fewer, and no sparks, on Low", function()
			local low = Plan.Caps(Tuning, true)
			local normal = Plan.Caps(Tuning, false)
			expect(low.bolts.live <= normal.bolts.live).toBe(true)
			expect(low.sparks.live).toBe(0)
		end)
	end)

	describe("state and floaters", function()
		it("applies damage, shields absorb first, and faint zeroes HP", function()
			local units = { unit("a1", "ally", false, 100) }
			local state = Plan.NewState(units)
			Plan.Apply(state, { actor = "e1", target = "a1", kind = "shield", amount = 20 })
			expect(state.shield.a1).toBe(20)
			Plan.Apply(state, { actor = "e1", target = "a1", kind = "hit", amount = 30, hp = 90 })
			expect(state.hp.a1).toBe(90) -- 10 lost, 20 absorbed from the shield
			expect(state.shield.a1).toBe(0)
			Plan.Apply(state, { actor = "e1", target = "a1", kind = "faint", hp = 0 })
			expect(state.hp.a1).toBe(0)
			expect(state.fainted.a1).toBe(true)
		end)

		it("clears stun on a stunned event and marks it on a stun", function()
			local units = { unit("a1", "ally") }
			local state = Plan.NewState(units)
			Plan.Apply(state, { actor = "a1", kind = "stun", amount = 0 })
			expect(state.stunned.a1).toBe(true)
			Plan.Apply(state, { actor = "a1", kind = "stunned" })
			expect(state.stunned.a1).toBeNil()
		end)

		it("floats a crit bigger and colors heals green, crits gold", function()
			local crit = Plan.Floater({ kind = "crit" }, "50")
			local heal = Plan.Floater({ kind = "heal" }, "20")
			local miss = Plan.Floater({ kind = "miss" }, "0")
			expect(crit.big).toBe(true)
			expect(crit.color).toBe("Gold")
			expect(heal.color).toBe("Green")
			expect(miss.text).toBe("MISS")
		end)
	end)

	describe("BattleStage.Attacks / Hurts", function()
		it("classifies event kinds", function()
			expect(Plan.Attacks("hit")).toBe(true)
			expect(Plan.Attacks("heal")).toBe(false)
			expect(Plan.Hurts("crit")).toBe(true)
			expect(Plan.Hurts("miss")).toBe(false)
		end)
	end)
end
