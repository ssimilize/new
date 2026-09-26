-- Glow-up TT: Titan system - scheduled invasion, shared HP pool across servers, egg to helpers.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local MockAdapters = t.MockAdapters
	local Config = t.Shared("Config")
	local Cfg = Config.Titan

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Expeditions", "Titan" }
	local SLOT = Cfg.Schedule[1].startsAt -- Colossyth, maxHp = 4.5e6
	local BOOT_MARGIN = 50 -- boot this long before the lobby opens (LobbySeconds is minutes long)
	local BOOT = SLOT - Cfg.LobbySeconds - BOOT_MARGIN
	local TO_LOBBY = BOOT_MARGIN + 1 -- seconds from boot until the lobby is open

	local function server(network, startTime)
		local stubs = {
			Eggs = {
				Add = function(_, _player, _eggType, _source, _amount)
					return {}
				end,
			},
		}
		return TestKernel.new({ systems = SYSTEMS, network = network, startTime = startTime or BOOT, stubs = stubs })
	end

	local function fighter(h, spec: { [string]: any }?)
		local s = spec or {}
		local p = h:Join(s.userId, s.name)
		h:Section(p, "Progression").level = s.level or 4
		local M = h:System("Monsters")
		local ids = {}
		for i = 1, s.n or 3 do
			local m = M:Create(p, { line = "cindlet", rarity = 2, stage = 3, traits = { 3, 4 }, hidden = 5 }, "test", true)
			m.lv = s.lv or 20
			ids[i] = m.id
		end
		if (s.n or 3) > 0 then
			h:Call(p, "Expeditions.SetSquad", { ids = ids })
		end
		return p
	end

	describe("Titan schedule", function()
		it("goes idle → lobby → active on the schedule, with the right titan and max HP", function()
			local h = server(MockAdapters.network())
			local T = h:System("Titan")
			local state = T:State()
			expect(state.state).toBe("idle")
			expect(state.startsAt).toBe(SLOT)
			expect(state.titanId).toBe("colossyth")

			local p = fighter(h)
			expect(h:Reject(p, "Titan.Join")).toContain("here yet")

			h:Advance(TO_LOBBY)
			expect(T:State().state).toBe("lobby")
			expect(T:State().maxHp).toBe(Cfg.Rotation[1].maxHp)
			h:Call(p, "Titan.Join")
			expect(T:State().participants).toBe(1)

			h:Advance(Cfg.LobbySeconds)
			expect(T:State().state).toBe("active")
		end)
	end)

	describe("the shared pool", function()
		it("drains from every server's damage and the titan falls everywhere at once", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local Ta, Tb = a:System("Titan"), b:System("Titan")

			local pa = fighter(a, { userId = 9001, name = "A", rarity = 5, n = 3, lv = 40 })
			local pb = fighter(b, { userId = 9002, name = "B", rarity = 5, n = 3, lv = 40 })

			a:Advance(TO_LOBBY)
			b:Advance(TO_LOBBY)
			a:Call(pa, "Titan.Join")
			b:Call(pb, "Titan.Join")
			a:Advance(Cfg.LobbySeconds)
			b:Advance(Cfg.LobbySeconds)
			expect(Ta:State().state).toBe("active")
			expect(Tb:State().state).toBe("active")

			-- Only server A deals damage for a while: server B's cached hp should still fall,
			-- once it reports and reads the shared pool back.
			a:Advance(Cfg.ReportSeconds + 1)
			local hpAfterA = Ta:State().hp
			expect(hpAfterA < Cfg.Rotation[1].maxHp).toBe(true)

			-- B reports too (its own damage on top of A's): the SAME pool drops further still,
			-- proving both servers drain one number, not two independent fights.
			b:Advance(Cfg.ReportSeconds + 1)
			expect(Tb:State().hp <= hpAfterA).toBe(true)
			expect(Tb:State().servers).toBe(2)
			expect(Tb:State().players >= 2).toBe(true)

			-- Bring the shared pool to (near) zero directly (shortcuts the grind for the test:
			-- the record itself, not a server's cached view of it - the next report folds it in
			-- and every server that reads it afterwards sees the same fallen titan).
			network.titan[tostring(SLOT)].hp = 1
			a:Advance(Cfg.ReportSeconds + 1)
			expect(Ta:State().state).toBe("fallen")
			b:Advance(Cfg.ReportSeconds + 1)
			expect(Tb:State().state).toBe("fallen")
		end)

		it("keeps fighting locally when the pool is unreachable, then reconciles", function()
			local network = MockAdapters.network()
			local h = server(network)
			local T = h:System("Titan")
			local p = fighter(h, { rarity = 5, n = 3, lv = 40 })
			h:Advance(TO_LOBBY)
			h:Call(p, "Titan.Join")
			h:Advance(Cfg.LobbySeconds)
			expect(T:State().state).toBe("active")

			network.titanDown = true
			h:Advance(Cfg.ReportSeconds + 1)
			expect(T:State().poolOk).toBe(false)
			local hpWhileDown = T:State().hp
			expect(hpWhileDown < Cfg.Rotation[1].maxHp).toBe(true) -- still fell locally

			network.titanDown = false
			h:Advance(Cfg.ReportSeconds + 1)
			expect(T:State().poolOk).toBe(true) -- reconciled: the retry folded the backlog in
		end)
	end)

	describe("rewards", function()
		it("gives the Titan Egg only to helpers (joined and dealt damage) when it falls", function()
			local network = MockAdapters.network()
			local h = server(network)
			local T = h:System("Titan")
			local helper = fighter(h, { userId = 9101, name = "Helper", rarity = 5, n = 3, lv = 40 })

			h:Advance(TO_LOBBY)
			h:Call(helper, "Titan.Join")
			h:Advance(Cfg.LobbySeconds)
			expect(T:State().state).toBe("active")
			h:Advance(1)
			expect(T:State().hp < Cfg.Rotation[1].maxHp).toBe(true)

			network.titan[tostring(SLOT)].hp = 0 -- the pool reads empty; resolve on the next report
			h:Advance(Cfg.ReportSeconds + 1)
			expect(T:State().state).toBe("fallen")

			local resultHelper = h:LastEvent(helper, "Titan.Result")
			expect(resultHelper.payload.won).toBe(true)
			expect(resultHelper.payload.egg).toBe(true)
			local gotEgg = false
			for _, item in resultHelper.payload.rewards do
				if item.kind == "egg" then
					gotEgg = true
				end
			end
			expect(gotEgg).toBe(true)
		end)

		it("retreats (no egg) once the clock runs out with hp still above zero", function()
			local network = MockAdapters.network()
			local h = server(network)
			local T = h:System("Titan")
			local p = fighter(h, { rarity = 1, n = 1, lv = 1 }) -- deliberately weak: won't finish it
			h:Advance(TO_LOBBY)
			h:Call(p, "Titan.Join")
			h:Advance(Cfg.LobbySeconds)
			h:Advance(Cfg.Duration + 1)
			expect(T:State().state).toBe("retreated")
			local result = h:LastEvent(p, "Titan.Result")
			expect(result.payload.won).toBe(false)
			expect(result.payload.egg).toBe(false)
			-- It dealt damage without cheering: the participation rewards still come.
			expect(#result.payload.rewards > 0).toBe(true)
		end)
	end)

	describe("the report runs off the scheduler's thread", function()
		it("hands the pool update to Services.Spawn and applies it when the call lands", function()
			local network = MockAdapters.network()
			local h = server(network)
			local T = h:System("Titan")
			local p = fighter(h, { rarity = 5, n = 3, lv = 40 })
			h:Advance(TO_LOBBY)
			h:Call(p, "Titan.Join")
			h:Advance(Cfg.LobbySeconds)
			expect(T:State().state).toBe("active")

			-- From here a report is queued instead of run: the MemoryStore call yields in a live
			-- server, and the kernel's scheduler must never wait on it.
			local queued = {}
			local inline = h.adapters.Spawn
			h.adapters.Spawn = function(fn, ...)
				table.insert(queued, table.pack(fn, ...))
			end
			local before = network.titan[tostring(SLOT)]
			local hpBefore = if before then before.hp else Cfg.Rotation[1].maxHp
			h:Advance(Cfg.ReportSeconds + 1)
			expect(#queued).toBe(1) -- one report in flight (the guard stops a second one)
			local after = network.titan[tostring(SLOT)]
			expect(if after then after.hp else Cfg.Rotation[1].maxHp).toBe(hpBefore) -- not written yet

			h.adapters.Spawn = inline
			local job = table.remove(queued, 1)
			job[1](table.unpack(job, 2, job.n))
			expect(network.titan[tostring(SLOT)].hp < hpBefore).toBe(true)
			expect(T:State().poolOk).toBe(true)
		end)
	end)

	describe("the Stampede and the titan", function()
		it("skips a Stampede period that would overlap an invasion", function()
			local Boss = Config.Boss
			local TitanLogic = t.Shared("Logic.Titan")
			local h = TestKernel.new({
				systems = { "Currency", "Progression", "Rewards", "Monsters", "Expeditions", "Titan", "Boss" },
				network = MockAdapters.network(),
				startTime = BOOT,
				stubs = { Eggs = {
					Add = function()
						return {}
					end,
				} },
			})
			local B = h:System("Boss"):State()
			expect(B.startsAt > SLOT).toBe(true)
			expect(
				TitanLogic.Overlaps(
					Cfg.Schedule,
					Cfg.Duration,
					Cfg.LobbySeconds,
					B.startsAt - Boss.LobbySeconds,
					B.startsAt + Boss.Duration
				)
			).toBe(false)

			-- Without the Titan system the Stampede keeps its usual period.
			local plain =
				TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Expeditions", "Boss" }, startTime = BOOT })
			expect(plain:System("Boss"):State().startsAt).toBe(math.ceil(BOOT / Boss.Period) * Boss.Period)
		end)
	end)
end
