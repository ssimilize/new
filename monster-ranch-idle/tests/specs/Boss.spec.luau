-- S4: Boss system (the Stampede).
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Cfg = Config.Boss

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Expeditions", "Boss" }
	local START = 1000000 * Cfg.Period -- a fight starts exactly here
	local TO_LOBBY = 100 - Cfg.LobbySeconds + 1 -- seconds from boot until the lobby is open

	local function boot(options: { [string]: any }?)
		local opts = options or {}
		local eggs = {}
		local stubs = {
			Eggs = {
				Add = function(_, player, eggType, source, amount)
					table.insert(eggs, { userId = player.UserId, egg = eggType, source = source, amount = amount or 1 })
					return {}
				end,
			},
		}
		if opts.weather then
			stubs.Weather = opts.weather
		end
		local h = TestKernel.new({ systems = SYSTEMS, stubs = stubs, startTime = START - 100 })
		local topics = { BossJoined = {}, BossEnded = {}, RanchXP = {} }
		for topic, list in topics do
			h.kernel.Bus:Subscribe(topic, function(player, detail)
				table.insert(list, { player = player, detail = detail })
			end)
		end
		return h, eggs, topics
	end

	-- A player at the boss unlock level with a squad of `n` monsters.
	local function fighter(h, spec: { [string]: any }?)
		local s = spec or {}
		local p = h:Join()
		h:Section(p, "Progression").level = s.level or 4
		local M = h:System("Monsters")
		local ids = {}
		for i = 1, s.n or 3 do
			local m = M:Create(p, {
				line = s.line or "cindlet",
				rarity = s.rarity or 2,
				stage = s.stage or 3,
				traits = s.traits or { 3, 4 },
				hidden = 5,
			}, "test", true) -- force: ignore capacity providers leaked by other specs
			m.lv = s.lv or 20
			ids[i] = m.id
		end
		if (s.n or 3) > 0 then
			h:Call(p, "Expeditions.SetSquad", { ids = ids })
		end
		return p
	end

	local function boardDamage(h, p): number
		for _, row in h:System("Boss"):State().board do
			if row.userId == p.UserId then
				return row.damage
			end
		end
		return 0
	end

	describe("Boss schedule", function()
		it("follows idle → lobby → active → idle aligned to the clock with a rotating boss", function()
			local h, eggs, topics = boot()
			local B = h:System("Boss")
			local state = B:State()
			expect(state.state).toBe("idle")
			expect(state.startsAt).toBe(START)
			expect(state.endsAt).toBe(START + Cfg.Duration)
			expect(state.bossId).toBe(Cfg.Rotation[(1000000 % #Cfg.Rotation) + 1].id)

			local p1 = fighter(h, { rarity = 3 })
			local p2 = fighter(h)
			local p3 = fighter(h, { rarity = 1 })
			local p4 = fighter(h, { rarity = 1, lv = 5 })
			expect(h:Reject(p1, "Boss.Join")).toContain("isn't here yet")

			h:Advance(TO_LOBBY)
			expect(B:State().state).toBe("lobby")
			for _, p in { p1, p2, p3 } do
				h:Call(p, "Boss.Join")
			end
			expect(#topics.BossJoined).toBe(3)
			expect(topics.RanchXP[#topics.RanchXP].detail.amount).toBe(Config.Unlocks.XP.bossJoin)
			expect(h:Client(p1).session.Boss.joined).toBe(true)
			expect(h:Client(p2).global.Boss.participants).toBe(3)

			h:Advance(Cfg.LobbySeconds)
			state = B:State()
			expect(state.state).toBe("active")
			local E = h:System("Expeditions")
			local power = E:SquadPower(p1) + E:SquadPower(p2) + E:SquadPower(p3)
			expect(state.maxHp).toBe(math.floor(power * Cfg.Duration * Cfg.HpPerSquadPower * 0.8))

			-- A late joiner adds their share of the remaining time.
			h:Advance(5)
			local before = state.maxHp
			h:Call(p4, "Boss.Join")
			expect(state.maxHp).toBeGreaterThan(before)

			h:Advance(Cfg.Duration)
			state = B:State()
			expect(state.state).toBe("idle")
			expect(state.startsAt).toBe(START + Cfg.Period)
			expect(state.bossId).toBe(Cfg.Rotation[(1000001 % #Cfg.Rotation) + 1].id)
			expect(#topics.BossEnded).toBe(1)
			expect(topics.BossEnded[1].detail.won).toBe(true)
			expect(topics.BossEnded[1].detail.bossId).toBe(Cfg.Rotation[(1000000 % #Cfg.Rotation) + 1].id)

			local ranks = {}
			for _, p in { p1, p2, p3, p4 } do
				local result = h:LastEvent(p, "Boss.Result")
				expect(result).toBeTruthy()
				ranks[result.payload.rank] = p
				expect(result.payload.damage).toBeGreaterThan(0)
				expect(#result.payload.rewards).toBeGreaterThan(0)
			end
			expect(ranks[1]).toBe(p1)
			expect(h:LastEvent(p1, "Boss.Result").payload.egg).toBe(true)
			expect(h:LastEvent(ranks[3], "Boss.Result").payload.egg).toBe(true)
			local stampede = 0
			for _, e in eggs do
				if e.egg == Cfg.Rewards.egg then
					stampede += 1
				end
			end
			expect(stampede).toBeAtLeast(3)
			local board = state.board
			expect(#board).toBe(4)
			expect(board[1].damage >= board[2].damage and board[2].damage >= board[3].damage).toBe(true)
			expect(h:Client(p1).session.Boss.joined).toBe(false)
		end)

		it("pays the participation chest converted with ranch income", function()
			local h = boot()
			local p = fighter(h)
			h:Advance(TO_LOBBY)
			h:Call(p, "Boss.Join")
			local C = h:System("Currency")
			local coins, gems = C:Balance(p, "coins"), C:Balance(p, "gems")
			h:Advance(Cfg.LobbySeconds + Cfg.Duration)
			-- No Ranch plugged in: Rewards converts 600 s at 1 coin/s, min 100.
			expect(C:Balance(p, "coins") - coins).toBe(600)
			expect(C:Balance(p, "gems") - gems).toBe(5)
		end)

		it("ends unbeaten when nobody joins", function()
			local h, _, topics = boot()
			fighter(h)
			h:Advance(TO_LOBBY + Cfg.LobbySeconds + Cfg.Duration)
			expect(#topics.BossEnded).toBe(1)
			expect(topics.BossEnded[1].detail.won).toBe(false)
			expect(h:System("Boss"):State().state).toBe("idle")
		end)
	end)

	describe("Boss.Join", function()
		it("needs the unlock, an open fight and a squad, and joins once", function()
			local h = boot()
			local low = fighter(h, { level = 3 })
			local empty = fighter(h, { n = 0 })
			local p = fighter(h)
			h:Advance(TO_LOBBY)
			expect(h:Reject(low, "Boss.Join")).toContain("Ranch Level 4")
			expect(h:Reject(empty, "Boss.Join")).toContain("Pick a squad")
			h:Call(p, "Boss.Join")
			h:Advance(1)
			expect(h:Reject(p, "Boss.Join")).toContain("already")
		end)

		it("keeps a player's place across a rejoin and skips players who left", function()
			local h = boot()
			local p1 = fighter(h)
			local p2 = fighter(h)
			h:Advance(TO_LOBBY)
			h:Call(p1, "Boss.Join")
			h:Call(p2, "Boss.Join")
			h:Advance(Cfg.LobbySeconds + 5)
			local back = h:Rejoin(p1, 2)
			expect(h:Client(back).session.Boss.joined).toBe(true)
			h:Leave(p2)
			local frozen = boardDamage(h, p2)
			h:Advance(10)
			expect(boardDamage(h, p2)).toBe(frozen)
			h:Advance(Cfg.Duration)
			expect(h:LastEvent(back, "Boss.Result")).toBeTruthy()
			expect(h:LastEvent(p2, "Boss.Result")).toBeNil()
		end)
	end)

	describe("Boss damage and cheer", function()
		it("applies modifiers, Boss Brawler and thunderstorm weather", function()
			local weather = "thunderstorm"
			local h = boot({
				weather = {
					Current = function()
						return { id = weather, endsAt = 0 }
					end,
				},
			})
			local plain = fighter(h)
			local modded = fighter(h)
			local brawler = fighter(h, { traits = { 16, 3 } })
			h:System("Boss"):RegisterDamageModifier("test", function(player)
				return if player == modded then 0.5 else 0
			end)
			h:Advance(TO_LOBBY)
			for _, p in { plain, modded, brawler } do
				h:Call(p, "Boss.Join")
			end
			h:Advance(Cfg.LobbySeconds)
			local before = {}
			for _, p in { plain, modded, brawler } do
				before[p] = boardDamage(h, p)
			end
			h:Advance(Cfg.TickSeconds)
			local function dealt(p)
				return boardDamage(h, p) - before[p]
			end
			local E = h:System("Expeditions")
			local perTick = Cfg.DamagePerPowerPerSecond * Cfg.TickSeconds * 1.1
			expect(dealt(plain)).toBeNear(E:SquadPower(plain) * perTick, 1.5)
			expect(dealt(modded)).toBeNear(E:SquadPower(modded) * 1.5 * perTick, 1.5)
			expect(dealt(brawler)).toBeNear(E:SquadPower(brawler) * 1.2 * perTick, 1.5)
			weather = "clear"
			before[plain] = boardDamage(h, plain)
			h:Advance(Cfg.TickSeconds)
			expect(dealt(plain)).toBeNear(E:SquadPower(plain) * Cfg.DamagePerPowerPerSecond * Cfg.TickSeconds, 1.5)
		end)

		it("fills the cheer meter, caps spam and decays", function()
			local h = boot()
			local p1 = fighter(h)
			local p2 = fighter(h)
			expect(h:Reject(p1, "Boss.Cheer", { taps = 5 })).toContain("Join the Stampede")
			h:Advance(TO_LOBBY)
			h:Call(p1, "Boss.Join")
			h:Call(p2, "Boss.Join")
			expect(h:Reject(p1, "Boss.Cheer", { taps = 5 })).toContain("hasn't started")
			h:Advance(Cfg.LobbySeconds)
			expect(h:Invoke(p1, "Boss.Cheer", { taps = Cfg.MaxTapsPerRequest + 1 }).err).toBe("BadRequest")
			-- Spam many max-size requests in the same instant.
			local tooFast, cheer = 0, 0
			for _ = 1, 10 do
				local res = h:Invoke(p1, "Boss.Cheer", { taps = Cfg.MaxTapsPerRequest })
				if res.ok then
					cheer = res.data.cheer
				elseif res.err == "TooFast" then
					tooFast += 1
				end
			end
			expect(tooFast).toBeGreaterThan(0)
			expect(cheer <= Cfg.MaxTapsPerSecond * Cfg.CheerPerTap + 1e-9).toBe(true)
			expect(cheer).toBeGreaterThan(0)
			h:Advance(Cfg.TickSeconds)
			local after = h:Client(p1).session.Boss.cheer
			expect(after).toBeNear(cheer - Cfg.CheerDecayPerSecond * Cfg.TickSeconds, 1e-6)
			expect(boardDamage(h, p1)).toBeGreaterThan(boardDamage(h, p2))
			-- The meter never passes 1.
			for _ = 1, 20 do
				h:Advance(1)
				h:Invoke(p1, "Boss.Cheer", { taps = Cfg.MaxTapsPerRequest })
			end
			expect(h:System("Boss"):State().state).toBe("active")
			expect(h:Client(p1).session.Boss.cheer <= 1).toBe(true)
		end)

		it("gives nothing to idle leechers below the damage share floor", function()
			local h = boot()
			local strong1 = fighter(h, { rarity = 5, lv = 40 })
			local strong2 = fighter(h, { rarity = 5, lv = 40 })
			local weak = fighter(h, { rarity = 1, stage = 1, lv = 1, n = 1, line = "pebblet" })
			h:System("Boss"):RegisterDamageModifier("whales", function(player)
				return if player == weak then 0 else 20
			end)
			h:Advance(TO_LOBBY)
			for _, p in { strong1, strong2, weak } do
				h:Call(p, "Boss.Join")
			end
			h:Advance(Cfg.LobbySeconds + Cfg.Duration)
			local result = h:LastEvent(weak, "Boss.Result").payload
			expect(result.share < Cfg.Rewards.minDamageShare).toBe(true)
			expect(#result.rewards).toBe(0)
			expect(result.egg).toBe(false)
			expect(#h:LastEvent(strong1, "Boss.Result").payload.rewards).toBeGreaterThan(0)
		end)
	end)
end
