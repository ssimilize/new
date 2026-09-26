--[[
	StampedeArena (glow-up U): Logic/StampedeArena as pure units (ring layout, who is drawn, attack
	rhythm, stagger thresholds, bolt pacing), the arena's reserved ground, and the squad looks the
	Boss system lists in global.Boss.squads (capped, render-only, cleared when a lobby opens).
]]

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.StampedeArena")
	local Scenery = t.Shared("Logic.Scenery")

	local A = Config.Boss.Arena
	local Cfg = Config.Boss

	describe("StampedeArena rules", function()
		it("lays squads out in rings, inner ring first, never crowding a ring", function()
			expect(#Logic.Rings(0, A.ringInner, A.ringGap, A.ringSpacing)).toBe(0)
			for _, n in { 1, 5, 24, 60 } do
				local slots = Logic.Rings(n, A.ringInner, A.ringGap, A.ringSpacing)
				expect(#slots).toBe(n)
				local lastRing = 1
				for i, s in slots do
					local r = math.sqrt(s.x * s.x + s.z * s.z)
					expect(math.abs(r - (A.ringInner + (s.ring - 1) * A.ringGap)) < 1e-6).toBe(true)
					expect(s.ring >= lastRing).toBe(true)
					lastRing = s.ring
					for j = i + 1, #slots do
						local o = slots[j]
						if o.ring == s.ring and n > 1 then
							local d = math.sqrt((o.x - s.x) ^ 2 + (o.z - s.z) ^ 2)
							expect(d >= A.ringSpacing * 0.9).toBe(true)
						end
					end
				end
			end
			-- 18 fit on the first ring; 60 need more, and stay inside the arena.
			local many = Logic.Rings(60, A.ringInner, A.ringGap, A.ringSpacing)
			expect(many[#many].ring > 1).toBe(true)
			expect(A.ringInner + (many[#many].ring - 1) * A.ringGap <= Config.World.StampedeArena.radius).toBe(true)
		end)

		it("draws your squad first, then everyone's lead before anyone's second, within the cap", function()
			local squads = {
				{ userId = 1, looks = { { line = "a1" }, { line = "a2" }, { line = "a3" } } },
				{ userId = 2, looks = { { line = "b1" }, { line = "b2" } } },
				{ userId = 3, looks = { { line = "c1" }, { line = "c2" }, { line = "c3" }, { line = "c4" } } },
			}
			local picked = Logic.Pick(squads, 2, 3, 5)
			local lines = {}
			for _, p in picked do
				table.insert(lines, p.look.line)
			end
			expect(lines).toEqual({ "b1", "b2", "a1", "c1", "a2" })
			expect(picked[1].mine).toBe(true)
			expect(picked[3].mine).toBe(false)
			-- perPlayer caps each squad (c4 never shows), and the cap is never passed.
			local all = Logic.Pick(squads, nil, 3, 100)
			expect(#all).toBe(8)
			expect(#Logic.Pick(squads, 1, 3, 2)).toBe(2)
			expect(#Logic.Pick(nil, 1, 3, 5)).toBe(0)
			-- The quality cap grows with the level.
			expect(Logic.MaxMonsters(A, 1) < Logic.MaxMonsters(A, 3)).toBe(true)
			expect(Logic.MaxMonsters(A, 9)).toBe(A.maxMonsters[#A.maxMonsters])
		end)

		it("spreads attacks over the period so neighbours never swing together", function()
			local seen = {}
			for i = 1, 12 do
				local o = Logic.AttackOffset(i, 12, A.attackEvery)
				expect(o >= 0 and o < A.attackEvery).toBe(true)
				if i > 1 then
					expect(math.abs(o - seen[i - 1]) > 0.1).toBe(true)
				end
				seen[i] = o
			end
		end)

		it("staggers once at the deepest HP threshold crossed", function()
			local th = A.staggers
			expect(Logic.Crossed(nil, 0.5, th)).toBeNil()
			expect(Logic.Crossed(1, 0.8, th)).toBeNil()
			expect(Logic.Crossed(0.8, 0.75, th)).toBe(0.75)
			expect(Logic.Crossed(0.8, 0.2, th)).toBe(0.25)
			expect(Logic.Crossed(0.75, 0.7, th)).toBeNil() -- already past 0.75
			expect(Logic.Crossed(0.4, 0.6, th)).toBeNil() -- a late joiner raised the HP
		end)

		it("paces bolts to at most boltsPerSecond in any second", function()
			local pacer = Logic.newPacer(A.boltsPerSecond)
			local granted = 0
			for _ = 1, 20 do
				if pacer:Take(10) then
					granted += 1
				end
			end
			expect(granted).toBe(A.boltsPerSecond)
			expect(pacer:Take(10.5)).toBe(false)
			expect(pacer:Take(10.99)).toBe(false)
			expect(pacer:Take(11)).toBe(true)
			-- A steady stream: never more than the cap inside a one-second window.
			local p2 = Logic.newPacer(3)
			local times = {}
			for i = 0, 100 do
				local now = i * 0.05
				if p2:Take(now) then
					table.insert(times, now)
				end
			end
			for i = 4, #times do
				expect(times[i] - times[i - 3] >= 1 - 1e-9).toBe(true)
			end
		end)

		it("fades linearly toward the target", function()
			expect(Logic.Approach(0, 1, 0.5, 2)).toBe(0.25)
			expect(Logic.Approach(0.9, 1, 1, 2)).toBe(1)
			expect(Logic.Approach(0.1, 0, 1, 2)).toBe(0)
		end)

		it("reserves open ground clear of the plaza, plots, paths and buildings", function()
			local arena = Config.World.StampedeArena
			local zones = {}
			for _, zone in Scenery.keepOut(Config) do
				if not (zone.r == arena.radius and zone.x == arena.center[1] and zone.z == arena.center[2]) then
					table.insert(zones, zone)
				end
			end
			expect(#zones < #Scenery.keepOut(Config)).toBe(true) -- scenery keeps off it
			expect(Scenery.blocked(zones, arena.center[1], arena.center[2], arena.radius)).toBe(false)
		end)
	end)

	describe("Boss squad looks", function()
		local START = 1000000 * Cfg.Period
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Expeditions", "Boss" }

		local function fighter(h, n: number)
			local p = h:Join()
			h:Section(p, "Progression").level = 4
			local M = h:System("Monsters")
			local ids = {}
			for i = 1, n do
				local m = M:Create(p, { line = "cindlet", rarity = 2, stage = 3, traits = { 3, 4 }, hidden = 5 }, "test", true)
				m.lv = 20
				ids[i] = m.id
			end
			h:Call(p, "Expeditions.SetSquad", { ids = ids })
			return p
		end

		it("lists each joined squad's looks, capped, and clears them when the next lobby opens", function()
			local h = TestKernel.new({ systems = SYSTEMS, stubs = { Eggs = { Add = function() end } }, startTime = START - 5 })
			local p1 = fighter(h, 3)
			local p2 = fighter(h, 1)
			h:Advance(2)
			local B = h:System("Boss")
			expect(B:State().state).toBe("lobby")
			h:Call(p1, "Boss.Join")
			h:Advance(2)
			h:Call(p2, "Boss.Join")
			local squads = B:State().squads
			expect(#squads).toBe(2)
			expect(squads[1].userId).toBe(p1.UserId)
			expect(#squads[1].looks).toBe(math.min(3, A.squadPerPlayer))
			expect(#squads[2].looks).toBe(1)
			local look = squads[1].looks[1]
			expect(look.line).toBe("cindlet")
			expect(look.id).toBeNil() -- render-only: no monster ids
			expect(type(look.form)).toBe("string")
			-- The fight ends; the looks stay until the next lobby clears them.
			h:Advance(4)
			B:State().hp = 1
			h:Advance(2)
			expect(B:State().state).toBe("idle")
			expect(#B:State().squads).toBe(2)
			B:State().startsAt = START + Cfg.LobbySeconds -- the lobby is due now
			h:Advance(2)
			expect(B:State().state).toBe("lobby")
			expect(#B:State().squads).toBe(0)
		end)

		it("stops listing squads past squadPlayers", function()
			local h = TestKernel.new({ systems = SYSTEMS, stubs = { Eggs = { Add = function() end } }, startTime = START - 5 })
			local players = {}
			for i = 1, A.squadPlayers + 2 do
				players[i] = fighter(h, 1)
			end
			h:Advance(2)
			for _, p in players do
				h:Call(p, "Boss.Join")
			end
			expect(#h:System("Boss"):State().squads).toBe(A.squadPlayers)
			expect(h:System("Boss"):State().participants).toBe(A.squadPlayers + 2)
		end)
	end)
end
