--[[
	LiveRace (glow-up LR): pure track/rider/heat rules (Logic/LiveRace), the server system
	(Systems/LiveRace, several riders including exploit attempts) and racing gear (Systems/RaceGear).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.LiveRace")
	local LR = Config.LiveRace

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Riding", "Racing", "LiveRace", "RaceGear" }

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function adult(h, p, line: string, rarity: number?)
		return h:System("Monsters"):Create(p, { line = line, rarity = rarity or 6, stage = 3 }, "test", true)
	end

	-- Rides an Adult and joins the current heat; returns { speed, lane, heat }.
	local function joinAsRider(h, p, line: string)
		levelTo(h, p, 16)
		local m = adult(h, p, line)
		local mount = h:Call(p, "Riding.Mount", { id = m.id })
		local join = h:Call(p, "LiveRace.Join", {})
		return { speed = mount.speed, lane = join.lane, heat = join.heat }
	end

	-- Sends honest reports along the centreline at a steady pace, jumping ahead of every hurdle
	-- (any lap) so nothing stumbles. Returns the last Progress reply.
	local function honestRun(h, p, heat: number, speed: number)
		local len = Logic.Length()
		local total = Logic.Total()
		local dt = LR.ReportEvery
		local hurdles = {}
		for lap = 0, LR.Laps - 1 do
			for _, f in LR.Hurdles do
				table.insert(hurdles, lap * len + f * len)
			end
		end
		table.sort(hurdles)
		local nextHurdle = 1
		local progress = 0
		local reply
		while progress < total do
			local nextProgress = math.min(total, progress + speed * dt)
			if hurdles[nextHurdle] and hurdles[nextHurdle] <= nextProgress then
				h:Call(p, "LiveRace.Jump", { heat = heat })
				nextHurdle += 1
			end
			h:Advance(dt)
			progress = nextProgress
			local x, z = Logic.Point(progress, 0)
			reply = h:Call(p, "LiveRace.Progress", { heat = heat, x = x, z = z, drift = false })
			if reply.finished then
				break
			end
		end
		return reply
	end

	describe("LiveRace logic", function()
		it("projects the track back onto itself, straights and curves alike", function()
			for _, u in { 0, 10, LR.Track.straight, LR.Track.straight + 5, Logic.Length() * 0.5, Logic.Length() - 1 } do
				for _, lat in { -8, 0, 8 } do
					local x, z = Logic.Point(u, lat)
					local u2, lat2 = Logic.Project(x, z)
					expect(math.abs(Logic.Wrap(u2 - u)) < 0.01).toBe(true)
					expect(math.abs(lat2 - lat) < 0.01).toBe(true)
				end
			end
			local _, _, off = Logic.Project(LR.Track.center[1], LR.Track.center[3])
			expect(off > 0).toBe(true) -- the infield is well past the track edge
		end)

		it("flags curves and wraps delta progress", function()
			expect(Logic.IsCurve(5)).toBe(false)
			expect(Logic.IsCurve(LR.Track.straight + 5)).toBe(true)
			expect(math.abs(Logic.Wrap(Logic.Length() - 1) - -1) < 0.001).toBe(true)
			expect(Logic.Wrap(1)).toBe(1)
		end)

		it("orders checkpoints across laps and counts them", function()
			expect(Logic.CheckpointCount()).toBe(#LR.Checkpoints * LR.Laps)
			expect(Logic.Threshold(1)).toBe(LR.Checkpoints[1] * Logic.Length())
			expect(Logic.Threshold(#LR.Checkpoints + 1)).toBe(Logic.Length() + LR.Checkpoints[1] * Logic.Length())
			expect(Logic.Crossed(0, Logic.Length() + 1, 0)).toBe(true)
			expect(Logic.Crossed(0, 1, 5)).toBe(false)
		end)

		it("caps allowed distance with boosts and stumbles, and refills the meter", function()
			local plain = Logic.Allowed(10, 0, 1, {}, {})
			expect(plain > 10 and plain < 10 * 2).toBe(true) -- CapSlack + a flat SlackStuds allowance
			local boosted = Logic.Allowed(10, 0, 1, { { 0, 1 } }, {})
			expect(boosted > plain).toBe(true)
			local stumbled = Logic.Allowed(10, 0, 1, {}, { { 0, 1 } })
			expect(stumbled < plain).toBe(true)
			expect(Logic.Refill(0, 100, false, false)).toBe(LR.MeterMax)
			expect(Logic.Refill(LR.MeterMax, 1, false, false)).toBe(LR.MeterMax)
			local drafted = Logic.Refill(0, 1, true, false)
			expect(drafted > LR.MeterRegen).toBe(true)
		end)

		it("gates joining and closes the lobby on time or a full grid", function()
			local ok = Logic.CanJoin("idle", 0, false)
			expect(ok).toBe(true)
			expect((Logic.CanJoin("running", 0, false))).toBe(false)
			expect(select(2, Logic.CanJoin("lobby", 0, true))).toBe("You're already in this race")
			expect(select(2, Logic.CanJoin("lobby", LR.MaxRiders, false))).toBe("This race is full")
			expect(Logic.LobbyDone(0, 100, 0)).toBe(false) -- nobody in yet
			expect(Logic.LobbyDone(100, 100, 1)).toBe(true) -- time's up
			expect(Logic.LobbyDone(0, 100, LR.MaxRiders, 0)).toBe(false)
			expect(Logic.LobbyDone(LR.FullSeconds, 100, LR.MaxRiders, 0)).toBe(true) -- full grid, grace elapsed
		end)

		it("only fills with ghosts under MinPlayers, and orders finishers, stragglers, then DQs", function()
			expect(#Logic.Ghosts(LR.MinPlayers, 1)).toBe(0)
			local ghosts = Logic.Ghosts(0, 1)
			expect(#ghosts > 0).toBe(true)
			local order = Logic.Order({
				{ id = "a", finished = true, time = 10, progress = 0 },
				{ id = "b", finished = false, time = 0, progress = 50 },
				{ id = "c", finished = false, time = 0, progress = 20, dq = true },
				{ id = "d", finished = true, time = 5, progress = 0 },
			})
			expect(order[1].id).toBe("d")
			expect(order[2].id).toBe("a")
			expect(order[3].id).toBe("b")
			expect(order[4].id).toBe("c")
			for i, e in order do
				expect(e.place).toBe(i)
			end
		end)
	end)

	describe("LiveRace server", function()
		it("races two riders, pays the winner, DNFs the straggler, and grants racing gear milestones", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p1 = h:Join()
			local p2 = h:Join()
			local r1 = joinAsRider(h, p1, "zappip")
			expect(r1.lane).toBe(1)
			h:Advance(2)
			local r2 = joinAsRider(h, p2, "cindlet")
			expect(r2.lane).toBe(2)
			expect(r1.heat).toBe(r2.heat)
			expect(h:Client(p1).global.LiveRace.state).toBe("lobby")

			-- Two humans (>= MinPlayers): the lobby runs its full timer, no ghosts fill in. (The
			-- lobby's clock started when p1 joined, 2 s before p2, so only LobbySeconds - 2 is left.)
			h:Advance(LR.LobbySeconds - 2 + 1)
			expect(h:Client(p1).global.LiveRace.state).toBe("countdown")
			expect(#h:Client(p1).global.LiveRace.ghosts).toBe(0)
			h:Advance(LR.CountdownSeconds + 1)
			expect(h:Client(p1).global.LiveRace.state).toBe("running")

			-- Rider 1 races cleanly to the finish.
			local finish1 = honestRun(h, p1, r1.heat, r1.speed)
			expect(finish1.finished).toBe(true)
			expect(h:Session(p1, "LiveRace").finished).toBe(true)

			-- Rider 2 never moves: the heat ends at MaxSeconds and DNFs them, still paid.
			h:Advance(LR.MaxSeconds + LR.FinishWindow + 2)
			expect(h:Client(p1).global.LiveRace.state).toBe("idle")

			local res1 = h:Session(p1, "LiveRace").result
			expect(res1.place).toBe(1)
			expect(res1.finished).toBe(true)
			expect(res1.dq).toBe(false)
			expect(#res1.rewards > 0).toBe(true)
			expect(res1.cup > 0).toBe(true)

			local res2 = h:Session(p2, "LiveRace").result
			expect(res2.finished).toBe(false) -- DNF
			expect(res2.dq).toBe(false)
			expect(res2.place).toBe(2)
			expect(res2.field).toBe(2)

			-- Racing gear: a first finish grants the rookie saddle and equips it; the milestone
			-- counters (races/live/podiums/wins) moved for both riders.
			local gear1 = h:Section(p1, "RaceGear")
			expect(gear1.owned.saddle_rookie).toBe(true)
			expect(gear1.equipped.saddle).toBe("saddle_rookie")
			expect(gear1.wins).toBe(1)
			expect(gear1.live).toBe(1)
			expect(gear1.podiums).toBe(1)
			local gear2 = h:Section(p2, "RaceGear")
			expect(gear2.owned.saddle_rookie).toBe(true) -- any finished race counts, even a DNF
			expect(gear2.live).toBe(1)
			-- A DNF is paid like the last reward row (Racing:Award), so its place for RaceGear's
			-- milestone bus detail is past 3rd: no podium credit for standing still.
			expect(gear2.podiums).toBe(0)

			-- Equip / unequip through the action (own item, right slot).
			expect(h:Reject(p1, "RaceGear.Equip", { kind = "saddle", item = "saddle_gold" })).toBe("You haven't earned that gear yet")
			expect(h:Reject(p1, "RaceGear.Equip", { kind = "trail", item = "saddle_rookie" })).toBe("That gear doesn't go there")
			h:Call(p1, "RaceGear.Equip", { kind = "saddle", item = "" })
			expect(h:Section(p1, "RaceGear").equipped.saddle).toBe(false)
			-- A podium finish also grants and auto-equips the Checkered Banner, so the server-wide
			-- entry stays (just without a saddle).
			expect(h:Client(p1).global.RaceGear.here["u" .. p1.UserId].saddle).toBe(false)
			expect(h:Client(p1).global.RaceGear.here["u" .. p1.UserId].banner).toBe("banner_checker")
		end)

		it("rejects a checkpoint skipper (a huge jump ahead) and a speed hacker (too fast, on track)", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p1 = h:Join()
			local p2 = h:Join()
			local skipper = joinAsRider(h, p1, "zappip")
			h:Advance(2)
			local hacker = joinAsRider(h, p2, "cindlet")
			h:Advance(LR.LobbySeconds + 1)
			h:Advance(LR.CountdownSeconds + 1)
			expect(h:Client(p1).global.LiveRace.state).toBe("running")

			-- Checkpoint skipper: cuts straight across the infield to grab a later checkpoint,
			-- far past the track's edge.
			for i = 1, LR.MaxStrikes do
				h:Advance(0.3)
				local x, z = LR.Track.center[1], LR.Track.center[3]
				local reply = h:Call(p1, "LiveRace.Progress", { heat = skipper.heat, x = x, z = z, drift = false })
				expect(reply.accepted).toBe(false)
				expect(reply.progress).toBe(0) -- snapped back every time; never credited
				if i < LR.MaxStrikes then
					expect(h:Session(p1, "LiveRace").dq).toBe(false)
				end
			end
			expect(h:Session(p1, "LiveRace").dq).toBe(true)
			expect(h:Session(p1, "LiveRace").strikes).toBe(LR.MaxStrikes)

			-- Speed hacker: a correct, on-track position, just far more of the track than even a
			-- generous (MaxGap-clamped) wall clock could allow at this rider's speed.
			local tooFar = math.min(Logic.Length() * 0.45, Logic.Allowed(hacker.speed, 0, LR.MaxGap, {}, {}) + 40)
			for _ = 1, LR.MaxStrikes do
				h:Advance(0.05)
				local x, z = Logic.Point(tooFar, 0)
				local reply = h:Call(p2, "LiveRace.Progress", { heat = hacker.heat, x = x, z = z, drift = false })
				expect(reply.accepted).toBe(false)
			end
			expect(h:Session(p2, "LiveRace").dq).toBe(true)
		end)
	end)
end
