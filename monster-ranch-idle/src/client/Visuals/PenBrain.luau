--[[
	PenBrain (glow-up S, living pens): the client "pen brain" that decides what every pen monster
	does next. World owns the monster entries (model + MonsterAnimator) and calls Tick from its 0.2 s
	loop; the decisions are Logic/PenLife, the numbers Config/PenLife.

		PenBrain.Attach(ctx, api)                     World.Start; api = { views, area(plot, pen) -> (CFrame, hx, hz),
		                                               penModel(plot, pen) -> Instance?, plotFrame(plot) -> CFrame,
		                                               own() -> plotIndex? }
		PenBrain.Tick(now)                            World's loop (os.clock())
		PenBrain.Detach()                             World.Destroy
		PenBrain.SetThinkRate(plot?, rate)            THE PERF KNOB: 0..1 for one plot (nil = every plot);
		                                               multiplies the built-in distance / on-screen rate
		PenBrain.Describe(model) -> { action, moment?, traits }?   tests and debugging
		PenBrain.Stats() -> { [action]: count }                  what the brain has started (tests)
		PenBrain.Count() -> number                               minds held (leak check)

	Reads an entry's fields World already keeps: id, plot, pen, owner, model, animator, margin, alive
	and nextAt (the next decision time; the brain holds it at math.huge while it steers a walk, and
	an outside change, e.g. World.PlayTrick, takes the monster back). Minds of removed entries
	(alive = false) are swept every 5 s.

	What it does
	  Personality   own monsters use their traits (profile.Monsters.list, hidden once revealed);
	                other plots' monsters are neutral (appearance carries no traits) unless an
	                entry gets a `traits` list.
	  Day           a weighted roll (Logic/PenLife.Choose): wander (shy ones along the fence), eat
	                (gluttons at the pen's food spot, longer), sit, nap, cheer, trick, spar, chase
	                (cheerful ones pick a free pen-mate; not in lowGraphics), social (sit beside a mate).
	  Night         everyone heads for the pile (PenSpot "bed" or a corner) and sleeps; night owls stay
	                up, early birds wake before dawn, stargazers sit up. Bed time and wake-up are staggered.
	  Weather       rain: shake it off at the start and now and then; snow: shiver; sunshine: bask;
	                storm: go to a PenSpot "shelter" (else the nearest corner) and sit.
	  Moments       the owner arriving at the ranch: every monster on the plot runs to the fence and
	                cheers; a hatch or evolve (held while Celebrate:IsCovered, so it waits for the
	                reveal): pen-mates gather round the new monster; show-offs pose for a player walking past the fence,
	                greeters (Charmer, Golden Heart) run over to them.
	  Motion        steering legs toward the goal with separation from pen-mates and avoidance of decor
	                and PenSpot parts, goals clamped inside the pen floor; the animator turns smoothly.
	  Bubbles       MoodBubbles (💤 ❤ 🍖 ♪ 💧), near the camera, capped, essentials only in lowGraphics.

	Cost: plots think at a rate from their distance to the camera and whether they are on screen
	(Logic/PenLife.ThinkRate), times SetThinkRate. Per think it reads each monster's position once;
	the scratch arrays are reused, so nothing is allocated per tick after warm-up except the mind of
	a new monster and a PenSpot rescan (every few seconds per pen).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.PenLife)
local PenLife = require(Shared.Logic.PenLife)

local Visuals = script.Parent
local MonsterAnimator = require(Visuals.MonsterAnimator)
local MoodBubbles = require(Visuals.MoodBubbles)
local Voices = require(Visuals.Parent.Audio.Voices)

local PenBrain = {}

local HOLD_WALK = math.huge
local Motion = Cfg.Motion
local Think = Cfg.Think

local ctx = nil
local api = nil
local connections = {}
-- Minds by entry. A mind points back at its entry, so weak keys alone would never let go (Luau
-- has no ephemerons): Tick sweeps out minds whose entry World removed (entry.alive = false).
local minds = {}
local sweepAt = 0
local plots = {} -- [plotIndex] = plot state
local knobs = {} -- [plotIndex] = 0..1
local knobAll = 1
local stats = {}

local lowGraphics = false
local night = false
local weatherId = "clear"
local phaseEndsAt = 0
local gatherId: string? = nil
local gatherAt = 0
local gatherUntil = 0

-- Players seen by the last scan (reused arrays).
local scanUser = {} :: { number }
local scanPos = {} :: { Vector3 }
local scanSpeed = {} :: { number }
local scanN = 0
local scanAt = -math.huge
local lastPos = {} :: { [number]: Vector3 }

local situation = { night = false, weather = "clear", lowGraphics = false, hasMate = false, dawnIn = nil :: number? }

local random: () -> number = math.random -- PenBrain.SetRandom swaps in a seeded source (tests)
local sqrt = math.sqrt

local function count(action: string)
	stats[action] = (stats[action] or 0) + 1
end

local function between(range: { number }): number
	return range[1] + (range[2] - range[1]) * random()
end

-- Personality -----------------------------------------------------------------------------------

local function recordOf(entry): any
	if not ctx or entry.owner ~= Players.LocalPlayer.UserId then
		return nil
	end
	local list = ctx.Store:Get("profile.Monsters.list")
	return if type(list) == "table" then list[entry.id] else nil
end

local function newMind(entry)
	local traits = entry.traits
	if type(traits) ~= "table" then
		traits = PenLife.TraitIds(recordOf(entry))
	end
	local t = PenLife.Tendency(traits)
	local mind = {
		entry = entry,
		pen = entry.pen,
		t = t,
		r = math.max(0.8, (entry.margin - 1.5) * 1.25),
		action = "idle",
		moment = nil :: string?,
		goalX = nil :: number?,
		goalZ = 0,
		goalUntil = 0,
		arriveState = "idle",
		arriveHold = 2,
		arriveBubble = nil :: string?,
		faceAt = nil :: Vector3?,
		follow = nil :: any,
		flee = nil :: any,
		repeatState = nil :: string?,
		shakeAt = nil :: number?,
		weather = weatherId,
		night = night,
		poseAt = 0,
		nudgeAt = 0,
		slot = 1,
		index = 0,
	}
	minds[entry] = mind
	return mind
end

-- Pen state: scratch arrays, spots and obstacles -------------------------------------------------

local function plotState(index: number)
	local ps = plots[index]
	if not ps then
		ps = { acc = 1, last = 0, pens = {}, owner = nil :: string?, farSince = 0, greets = 0, greetAt = -math.huge, centre = nil }
		plots[index] = ps
	end
	return ps
end

local function penState(ps, pen: number)
	local st = ps.pens[pen]
	if not st then
		st = {
			n = 0,
			entries = {},
			minds = {},
			xs = {},
			zs = {},
			rs = {},
			free = {},
			on = 0,
			ox = {},
			oz = {},
			orr = {},
			spots = {},
			area = CFrame.identity,
			hx = 1,
			hz = 1,
			scanAt = -math.huge,
		}
		ps.pens[pen] = st
	end
	return st
end

local function addObstacle(st, x: number, z: number, r: number)
	st.on += 1
	st.ox[st.on], st.oz[st.on], st.orr[st.on] = x, z, r
end

-- A part is a pen spot or obstacle if it stands inside the pen (with a little slack).
local function considerPart(st, inst: Instance)
	local kind = inst:GetAttribute("PenSpot")
	local position, size
	if inst:IsA("BasePart") then
		position, size = inst.Position, inst.Size
	elseif inst:IsA("Model") and type(kind) == "string" then
		position, size = inst:GetPivot().Position, inst:GetExtentsSize()
	else
		return
	end
	local p = st.area:PointToObjectSpace(position)
	if math.abs(p.X) > st.hx + 1 or math.abs(p.Z) > st.hz + 1 then
		return
	end
	local r = math.max(size.X, size.Z) / 2
	if type(kind) == "string" then
		local list = st.spots[kind]
		if not list then
			list = {}
			st.spots[kind] = list
		end
		table.insert(list, { x = p.X, z = p.Z, r = if inst:IsA("Model") or inst.CanCollide then r else 0 })
		if kind == "shelter" or inst:IsA("Model") or (inst:IsA("BasePart") and inst.CanCollide) then
			addObstacle(st, p.X, p.Z, r)
		end
		return
	end
	-- Decor pieces: skip flat ones (puddles, rugs) and toppers that sit on a pole.
	if math.min(size.X, size.Y, size.Z) < 0.5 or string.sub(inst.Name, -4) == "_Top" then
		return
	end
	if string.sub(inst.Name, 1, 6) == "Decor_" or inst:GetAttribute("PenObstacle") == true then
		addObstacle(st, p.X, p.Z, r)
	end
end

local function rescan(st, plotIndex: number, pen: number, view)
	local area, hx, hz = api.area(plotIndex, pen)
	st.area, st.hx, st.hz = area, hx, hz
	st.on = 0
	table.clear(st.spots)
	local model = api.penModel(plotIndex, pen)
	if model then
		for _, inst in model:GetDescendants() do
			if inst:GetAttribute("PenSpot") ~= nil or inst:GetAttribute("PenObstacle") == true then
				considerPart(st, inst)
			end
		end
	end
	if view.folder then
		for _, inst in view.folder:GetChildren() do
			if not inst:IsA("Model") or inst:GetAttribute("PenSpot") ~= nil then
				considerPart(st, inst)
			end
		end
	end
end

-- Players -----------------------------------------------------------------------------------------

local function scanPlayers(now: number)
	local dt = now - scanAt
	scanAt = now
	scanN = 0
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local pos = root.Position
			local before = lastPos[player.UserId]
			lastPos[player.UserId] = pos
			scanN += 1
			scanUser[scanN] = player.UserId
			scanPos[scanN] = pos
			scanSpeed[scanN] = if before and dt > 0 and dt < 5 then (pos - before).Magnitude / dt else 0
		end
	end
end

local function playerPos(userId: number): Vector3?
	for i = 1, scanN do
		if scanUser[i] == userId then
			return scanPos[i]
		end
	end
	return nil
end

-- Actions ------------------------------------------------------------------------------------------

local function bubble(mind, kind: string?, now: number)
	if kind and MoodBubbles.Pop(mind.entry.model, kind, now) then
		count("bubble")
	end
end

local function clearGoal(mind)
	mind.goalX = nil
	mind.follow = nil
	mind.flee = nil
	mind.faceAt = nil
	mind.moment = nil
	mind.arriveBubble = nil
end

-- Plays a state and holds it; `repeatState` re-plays a one-shot (eat, spar) until the hold ends.
local function perform(mind, state: string, hold: number, now: number, action: string?)
	local entry = mind.entry
	local animator = entry.animator
	if animator:IsMoving() then
		animator:Stop()
	end
	animator:SetPace(1)
	if state == "happy" or state == "trick" then
		if state == "trick" and not MonsterAnimator.HasState("trick") then
			state = "happy"
		end
		Voices.Cry(entry.model, "happy")
	end
	animator:Play(state)
	mind.action = action or state
	mind.repeatState = if state == "eat" or state == "attack" then state else nil
	entry.nextAt = now + hold
	count(mind.action)
end

-- Starts a walk to a pen-local goal; on arrival it plays `state` for `hold` seconds.
local function walkTo(mind, x: number, z: number, st, state: string, hold: number, now: number, action: string, pace: number?)
	local entry = mind.entry
	x, z = PenLife.Clamp(x, z, st.hx, st.hz, entry.margin)
	mind.goalX, mind.goalZ = x, z
	mind.goalUntil = now + Motion.stuckSeconds
	mind.arriveState = state
	mind.arriveHold = hold
	mind.action = action
	mind.repeatState = nil
	entry.nextAt = HOLD_WALK
	entry.animator:SetPace((pace or 1) * (mind.t.pace or 1))
	count(action)
end

local function arrive(mind, now: number)
	local entry = mind.entry
	local faceAt = mind.faceAt
	local kind = mind.arriveBubble
	local action = mind.action
	local partner = mind.follow
	clearGoal(mind)
	perform(mind, mind.arriveState, mind.arriveHold, now, action)
	stats[action] -= 1 -- perform counted it again; the walk already did
	if faceAt then
		entry.animator:FaceToward(faceAt)
	end
	bubble(mind, kind, now)
	-- A chaser that catches up (or runs out of time) ends the runner's game too.
	local other = partner and minds[partner]
	if other and other.flee == entry then
		clearGoal(other)
		perform(other, "happy", between(Cfg.Hold.cheer), now, "chase")
		stats.chase -= 1
		bubble(other, "music", now)
	end
end

local function nearestSpot(st, kind: string, x: number, z: number)
	local list = st.spots[kind]
	local best, bestD = nil, math.huge
	for _, spot in list or {} do
		local d = (spot.x - x) ^ 2 + (spot.z - z) ^ 2
		if d < bestD then
			best, bestD = spot, d
		end
	end
	return best
end

local function pileCentre(st, pen: number): (number, number)
	local bed = st.spots.bed and st.spots.bed[1]
	if bed then
		return bed.x, bed.z
	end
	-- A back corner, alternating sides by pen so neighbouring piles do not mirror each other.
	local sx = if pen % 2 == 0 then 1 else -1
	return sx * st.hx * 0.5, -st.hz * 0.5
end

local function freeFor(st, self: number)
	local any = false
	for i = 1, st.n do
		local m = st.minds[i]
		local ok = i ~= self
			and m.goalX == nil
			and m.moment == nil
			and m.action ~= "sleep"
			and m.action ~= "nap"
			and m.action ~= "eat"
			and m.entry.nextAt ~= HOLD_WALK
		st.free[i] = ok
		any = any or ok
	end
	return any
end

local function decide(mind, st, i: number, now: number, pen: number)
	local entry = mind.entry
	local t = mind.t
	local x, z = st.xs[i], st.zs[i]
	local weather = PenLife.WeatherOf(weatherId)

	-- Now and then in the rain (the onset shake is thinkPen's).
	if weather.wet and not t.weatherproof and mind.action ~= "shake" and mind.action ~= "sleep" and random() < Cfg.WetShakeChance then
		perform(mind, "shake", between(Cfg.Hold.shake), now)
		bubble(mind, "wet", now)
		return
	end

	local action = PenLife.Choose(t, situation, random())
	if action == "sleep" then
		if mind.action == "sleep" then
			-- Already in the pile: sleep on.
			entry.nextAt = now + between(Cfg.Hold.sleep)
			bubble(mind, "sleep", now)
			return
		end
		local slot = 1
		for k = 1, st.n do
			if k ~= i and st.minds[k].action == "sleep" then
				slot += 1
			end
		end
		mind.slot = slot
		local cx, cz = pileCentre(st, pen)
		local dx, dz = PenLife.PileSlot(slot, Cfg.PileSpacing * math.max(1, mind.r))
		walkTo(mind, cx + dx, cz + dz, st, "sleep", between(Cfg.Hold.sleep), now, "sleep")
		mind.arriveBubble = "sleep"
		return
	elseif action == "stargaze" then
		perform(mind, "sit", between(Cfg.Hold.sleep), now, "stargaze")
		return
	elseif action == "wander" then
		local wx, wz = PenLife.RandomPoint(random(), random(), random(), st.hx, st.hz, entry.margin, t.edge)
		walkTo(mind, wx, wz, st, PenLife.IdleState(t, situation), between(Cfg.Hold.afterWalk), now, "wander")
		return
	elseif action == "eat" then
		local food = if t.seekFood then nearestSpot(st, "food", x, z) else nil
		if food then
			local dx, dz = PenLife.Ring(i, math.max(3, st.n), food.r + mind.r + 0.4)
			walkTo(mind, food.x + dx, food.z + dz, st, "eat", PenLife.Hold("eat", t, random()), now, "eat")
			mind.faceAt = st.area:PointToWorldSpace(Vector3.new(food.x, 0, food.z))
			mind.arriveBubble = "food"
		else
			perform(mind, "eat", PenLife.Hold("eat", t, random()), now)
			bubble(mind, "food", now)
		end
		return
	elseif action == "sit" then
		local food = if t.seekFood then nearestSpot(st, "food", x, z) else nil
		if food then
			local dx, dz = PenLife.Ring(i + 2, math.max(3, st.n), food.r + mind.r + 0.8)
			walkTo(mind, food.x + dx, food.z + dz, st, "sit", between(Cfg.Hold.sit), now, "sit")
		else
			perform(mind, "sit", between(Cfg.Hold.sit), now)
		end
		return
	elseif action == "nap" then
		perform(mind, "sleep", between(Cfg.Hold.nap), now, "nap")
		bubble(mind, "sleep", now)
		return
	elseif action == "cheer" then
		perform(mind, "happy", between(Cfg.Hold.cheer), now, "cheer")
		bubble(mind, "music", now)
		return
	elseif action == "trick" then
		perform(mind, "trick", between(Cfg.Hold.trick), now, "trick")
		return
	elseif action == "spar" then
		perform(mind, "attack", between(Cfg.Hold.spar), now, "spar")
		return
	elseif action == "chase" or action == "social" then
		local mate = if freeFor(st, i) then PenLife.PickMate(st.n, i, st.free, random()) else nil
		if mate then
			local other = st.minds[mate]
			if action == "chase" then
				local hold = between(Cfg.Hold.chase)
				walkTo(mind, st.xs[mate], st.zs[mate], st, "happy", between(Cfg.Hold.cheer), now, "chase", Cfg.Chase.chaserPace)
				mind.follow = other.entry
				mind.goalUntil = now + hold
				mind.arriveBubble = "music"
				local fx, fz = PenLife.FleePoint(st.xs[mate], st.zs[mate], x, z, st.hx, st.hz, other.entry.margin, Cfg.Chase.fleeDistance)
				walkTo(other, fx, fz, st, "happy", between(Cfg.Hold.cheer), now, "flee", Cfg.Chase.runnerPace)
				other.flee = entry
				other.goalUntil = now + hold + 1
				bubble(mind, "music", now)
			else
				local vx, vz = x - st.xs[mate], z - st.zs[mate]
				local d = math.max(1e-3, sqrt(vx * vx + vz * vz))
				local gap = (mind.r + other.r) * 1.3
				walkTo(mind, st.xs[mate] + vx / d * gap, st.zs[mate] + vz / d * gap, st, "sit", between(Cfg.Hold.social), now, "social")
				mind.faceAt = other.entry.animator:GetPosition()
				mind.arriveBubble = "love"
			end
			return
		end
		action = "idle"
	elseif action == "bask" then
		local wx, wz = PenLife.RandomPoint(random(), random(), 1, st.hx, st.hz, entry.margin + 1, 0)
		local state = if (t.nap or 0) >= Cfg.Base.nap * 2 then "sleep" else "sit"
		walkTo(mind, wx, wz, st, state, between(Cfg.Hold.bask), now, "bask")
		return
	elseif action == "shelter" then
		local spot = nearestSpot(st, "shelter", x, z)
		local gx, gz
		if spot then
			local dx, dz = PenLife.Ring(i, math.max(4, st.n), spot.r + mind.r + 0.6)
			gx, gz = spot.x + dx, spot.z + dz
		else
			gx = (if x >= 0 then 1 else -1) * st.hx
			gz = (if z >= 0 then 1 else -1) * st.hz
		end
		if mind.action == "shelter" and (x - gx) ^ 2 + (z - gz) ^ 2 < (entry.margin + 2) ^ 2 then
			perform(mind, "sit", between(Cfg.Hold.shelter), now, "shelter")
		else
			walkTo(mind, gx, gz, st, "sit", between(Cfg.Hold.shelter), now, "shelter", 1.2)
			mind.arriveBubble = "wet"
		end
		return
	elseif action == "shiver" then
		perform(mind, "shiver", between(Cfg.Hold.shiver), now)
		return
	end
	perform(mind, PenLife.IdleState(t, situation), between(Cfg.Hold.idle), now, "idle")
end

-- Moments --------------------------------------------------------------------------------------------

local function greetAt(mind, st, target: Vector3, slot: number, count: number, now: number)
	local p = st.area:PointToObjectSpace(target)
	local spacing = math.max(Cfg.Greet.spacing, mind.r * 2.4)
	local fx, fz = PenLife.FencePoint(p.X, p.Z, st.hx, st.hz, mind.entry.margin, slot, spacing, count)
	clearGoal(mind)
	walkTo(mind, fx, fz, st, "happy", between(Cfg.Hold.greet), now, "greet", 1.3)
	mind.moment = "greet"
	mind.faceAt = target
	mind.arriveBubble = "love"
end

local function ownerArrival(index: number, view, ps, now: number)
	local own = view.userId == Players.LocalPlayer.UserId
	local pos = playerPos(view.userId)
	if not pos then
		return
	end
	if not ps.centre then
		ps.centre = api.plotFrame(index).Position
	end
	local d = (pos - ps.centre).Magnitude
	local before = ps.owner
	if d <= Cfg.Greet.arriveRadius then
		ps.owner = "near"
		if before ~= "near" then
			local away = before == "far" and now - ps.farSince >= Cfg.Greet.awaySeconds
			local first = own and ps.greets == 0
			if (away or first) and now - ps.greetAt >= Cfg.Greet.cooldown then
				ps.greets += 1
				ps.greetAt = now
				for _, st in ps.pens do
					for k = 1, st.n do
						greetAt(st.minds[k], st, pos, k, st.n, now)
					end
				end
			end
		end
	elseif d >= Cfg.Greet.leaveRadius and before ~= "far" then
		ps.owner = "far"
		ps.farSince = now
	end
end

local function visitors(st, now: number)
	for k = 1, st.n do
		local mind = st.minds[k]
		local t = mind.t
		if (t.showOff or t.greeter) and now >= mind.poseAt and mind.moment == nil and mind.goalX == nil and mind.action ~= "sleep" then
			for j = 1, scanN do
				if scanSpeed[j] >= Cfg.ShowOff.minSpeed then
					local p = st.area:PointToObjectSpace(scanPos[j])
					if PenLife.NearFence(p.X, p.Z, st.hx, st.hz, Cfg.ShowOff.range) then
						mind.poseAt = now + Cfg.ShowOff.cooldown
						if t.greeter then
							greetAt(mind, st, scanPos[j], 1, 1, now)
						else
							mind.entry.animator:FaceToward(scanPos[j])
							perform(mind, "trick", between(Cfg.Hold.pose), now, "pose")
							bubble(mind, "music", now)
						end
						break
					end
				end
			end
		end
	end
end

local function gatherRound(st, focal: number, now: number)
	local centre = st.minds[focal]
	local fx, fz = st.xs[focal], st.zs[focal]
	local at = centre.entry.animator:GetPosition()
	perform(centre, "happy", between(Cfg.Hold.gather), now, "gathered")
	local k = 0
	for i = 1, st.n do
		if i ~= focal then
			k += 1
			local mind = st.minds[i]
			local dx, dz = PenLife.Ring(k, st.n - 1, Cfg.Gather.radius + mind.r + centre.r)
			clearGoal(mind)
			walkTo(mind, fx + dx, fz + dz, st, if k % 2 == 1 then "happy" else "idle", between(Cfg.Hold.gather), now, "gather")
			mind.moment = "gather"
			mind.faceAt = at
			mind.arriveBubble = "love"
		end
	end
end

-- Steering ---------------------------------------------------------------------------------------------

local function steer(mind, st, i: number, now: number, dt: number)
	local entry = mind.entry
	local animator = entry.animator
	local x, z = st.xs[i], st.zs[i]
	local follow = mind.follow and minds[mind.follow]
	local flee = mind.flee and minds[mind.flee]
	if (mind.follow and (not follow or not mind.follow.alive)) or (mind.flee and (not flee or not mind.flee.alive)) then
		clearGoal(mind)
		entry.nextAt = now
		return
	end
	local catch = Motion.arrive
	if follow then
		local fp = st.area:PointToObjectSpace(follow.entry.animator:GetPosition())
		mind.goalX, mind.goalZ = fp.X, fp.Z
		catch = Cfg.Chase.catch + mind.r + follow.r
	elseif flee then
		local cp = st.area:PointToObjectSpace(flee.entry.animator:GetPosition())
		mind.goalX, mind.goalZ = PenLife.FleePoint(x, z, cp.X, cp.Z, st.hx, st.hz, entry.margin, Cfg.Chase.fleeDistance)
	end
	local gx, gz = mind.goalX :: number, mind.goalZ
	local dx, dz = gx - x, gz - z
	local dist = sqrt(dx * dx + dz * dz)
	if now >= mind.goalUntil or (dist <= catch and not flee) then
		arrive(mind, now)
		return
	end
	local scale = if mind.action == "sleep" then Motion.separationPile else Motion.separation
	local sx, sz = PenLife.Separation(x, z, st.xs, st.zs, st.rs, st.n, i, mind.r, scale)
	local ax, az = PenLife.Avoid(x, z, st.ox, st.oz, st.orr, st.on, mind.r + Motion.obstaclePad)
	local leg = animator:GetSpeed() * dt * Motion.legSeconds
	local wx, wz = PenLife.Steer(x, z, gx, gz, sx, sz, ax, az, leg)
	wx, wz = PenLife.Clamp(wx, wz, st.hx, st.hz, entry.margin)
	animator:MoveTo(st.area:PointToWorldSpace(Vector3.new(wx, 0, wz)))
end

-- Tick -------------------------------------------------------------------------------------------------

local function thinkPen(st, pen: number, now: number, dt: number, gatherHere: number?)
	situation.hasMate = st.n > 1
	for i = 1, st.n do
		local mind = st.minds[i]
		local entry = mind.entry
		-- Night falls or day breaks: drop what it was doing (moments excepted), staggered.
		if mind.night ~= night then
			mind.night = night
			if mind.moment == nil then
				if mind.goalX then
					clearGoal(mind)
					entry.animator:Stop()
				end
				entry.nextAt = now + between(if night then Cfg.NightStagger else Cfg.DawnStagger)
			end
		end
		if mind.weather ~= weatherId then
			local onset = PenLife.Onset(mind.t, mind.weather, weatherId)
			mind.weather = weatherId
			if onset then
				mind.shakeAt = now + 0.3 + random() * 3
			end
			if PenLife.WeatherOf(weatherId).shelter and mind.moment == nil and entry.nextAt ~= HOLD_WALK then
				entry.nextAt = math.min(entry.nextAt, now + random() * 3)
			end
		end
		-- Shaking off the rain does not wait for the current action (moments and the pile aside).
		if mind.shakeAt and now >= mind.shakeAt and mind.moment == nil and mind.action ~= "sleep" then
			mind.shakeAt = nil
			if mind.goalX then
				clearGoal(mind)
			end
			perform(mind, "shake", between(Cfg.Hold.shake), now)
			bubble(mind, "wet", now)
		elseif mind.goalX then
			if entry.nextAt ~= HOLD_WALK then
				-- Someone else took the monster (a trick, a tap): let it be.
				clearGoal(mind)
			else
				steer(mind, st, i, now, dt)
			end
		elseif now >= entry.nextAt and not entry.animator:IsMoving() then
			decide(mind, st, i, now, pen)
		elseif mind.action ~= "sleep" and mind.moment == nil and now >= mind.nudgeAt and not entry.animator:IsMoving() then
			-- Resting on top of a pen-mate: shuffle aside.
			local sx, sz = PenLife.Separation(st.xs[i], st.zs[i], st.xs, st.zs, st.rs, st.n, i, mind.r, Motion.separation)
			if sx * sx + sz * sz > 0.1 then
				mind.nudgeAt = now + 2
				local state = entry.animator:GetState()
				walkTo(
					mind,
					st.xs[i] + sx * 2.5,
					st.zs[i] + sz * 2.5,
					st,
					if state == "walk" then "idle" else state,
					1 + random(),
					now,
					mind.action
				)
				stats[mind.action] -= 1
				count("nudge")
			end
		elseif mind.repeatState and entry.animator:GetState() == "idle" then
			entry.animator:Play(mind.repeatState)
		end
	end
	if gatherHere then
		gatherRound(st, gatherHere, now)
	end
	visitors(st, now)
end

function PenBrain.Tick(now: number)
	if not api then
		return
	end
	local photo = ctx and ctx:GetController("PhotoMode")
	MoodBubbles.SetSuppressed(photo ~= nil and type(photo.IsActive) == "function" and photo:IsActive() == true)
	MoodBubbles.Step(now)
	if now - scanAt >= Think.playerScan then
		scanPlayers(now)
	end
	situation.night = night
	situation.weather = weatherId
	situation.lowGraphics = lowGraphics
	situation.dawnIn = if night and ctx then phaseEndsAt - ctx:Now() else nil

	if now >= sweepAt then
		sweepAt = now + 5
		for entry, mind in minds do
			if not entry.alive then
				minds[entry] = nil
				mind.follow, mind.flee = nil, nil
			end
		end
	end

	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local camLook = if camera then camera.CFrame.LookVector else Vector3.zAxis
	local ownIndex = api.own()
	local kit = if gatherId and ctx then ctx:GetController("Celebrate") else nil
	local covered = kit ~= nil and type(kit.IsCovered) == "function" and kit:IsCovered() == true
	for index, view in api.views do
		if next(view.entries) == nil then
			plots[index] = nil -- drop the scratch arrays' references to removed monsters
			continue
		end
		local ps = plotState(index)
		if not ps.centre then
			ps.centre = api.plotFrame(index).Position
		end
		local offset = ps.centre - camPos
		local distance = offset.Magnitude
		local onScreen = distance < 60 or offset:Dot(camLook) > -0.2 * distance
		local rate = PenLife.ThinkRate(distance, onScreen, (knobs[index] or 1) * knobAll)
		if rate <= 0 then
			continue
		end
		ps.acc += rate
		if ps.acc < 1 then
			continue
		end
		ps.acc -= 1
		local dt = math.clamp(now - ps.last, Think.interval, 2)
		ps.last = now

		-- Group this plot's monsters by pen (reused arrays) and read each position once.
		for _, st in ps.pens do
			st.n = 0
		end
		for _, entry in view.entries do
			if entry.alive then
				local mind = minds[entry] or newMind(entry)
				if mind.pen ~= entry.pen then
					mind.pen = entry.pen
					clearGoal(mind)
				end
				local st = penState(ps, entry.pen)
				if now >= st.scanAt then
					st.scanAt = now + Think.spotRescan + random()
					rescan(st, index, entry.pen, view)
				end
				local n = st.n + 1
				st.n = n
				st.entries[n] = entry
				st.minds[n] = mind
				local p = st.area:PointToObjectSpace(entry.animator:GetPosition())
				st.xs[n], st.zs[n], st.rs[n] = p.X, p.Z, mind.r
				mind.index = n
			end
		end
		for _, st in ps.pens do
			for k = st.n + 1, #st.entries do
				st.entries[k] = nil
				st.minds[k] = nil
			end
		end

		ownerArrival(index, view, ps, now)
		local own = index == ownIndex
		local focalEntry = nil
		if own and gatherId and covered then
			-- Held while the hatch reveal or the evolution popup covers the world (as Celebrate:Moment
			-- holds World's bursts), so the pen gathers where the player can see it.
			gatherAt = math.max(gatherAt, now + Cfg.Gather.delay * 0.5)
			gatherUntil = math.max(gatherUntil, gatherAt + Cfg.Gather.seconds)
		elseif own and gatherId and now >= gatherAt then
			focalEntry = view.entries[gatherId]
			if focalEntry or now >= gatherUntil then
				gatherId = nil
			end
		end
		for pen, st in ps.pens do
			if st.n > 0 then
				local focal = nil
				if focalEntry and focalEntry.pen == pen then
					local m = minds[focalEntry]
					focal = m and m.index
				end
				thinkPen(st, pen, now, dt, focal)
			end
		end
	end
end

-- Knobs, events, lifecycle -------------------------------------------------------------------------------

-- Every roll the brain makes comes from `fn` (0 <= x < 1); nil puts math.random back. Specs pass a
-- seeded Logic/Rng so the pen plays out the same way on every run.
function PenBrain.SetRandom(fn: (() -> number)?)
	random = fn or math.random
end

function PenBrain.SetThinkRate(plotIndex: number?, rate: number)
	local value = math.clamp(tonumber(rate) or 1, 0, 1)
	if plotIndex == nil then
		knobAll = value
	else
		knobs[plotIndex] = value
	end
end

local function queueGather(id: any)
	if type(id) ~= "string" then
		return
	end
	local now = os.clock()
	gatherId = id
	gatherAt = now + Cfg.Gather.delay
	gatherUntil = now + Cfg.Gather.seconds
end

function PenBrain.Attach(context, worldApi)
	ctx = context
	api = worldApi
	MonsterAnimator.SetTurnRates(Motion.turnRate, Motion.faceRate)
	table.clear(connections)
	table.insert(
		connections,
		ctx.Store:Observe("profile.Settings", function(settings)
			lowGraphics = type(settings) == "table" and settings.lowGraphics == true
			MoodBubbles.SetLow(lowGraphics)
		end)
	)
	table.insert(
		connections,
		ctx.Store:Observe("global.Weather", function(weather)
			if type(weather) ~= "table" then
				return
			end
			night = weather.night == true
			weatherId = if type(weather.id) == "string" then weather.id else "clear"
			phaseEndsAt = tonumber(weather.phaseEndsAt) or 0
		end)
	)
	table.insert(
		connections,
		ctx.Net:On("Eggs.Hatched", function(payload)
			local monster = type(payload) == "table" and payload.monster
			if type(monster) == "table" then
				queueGather(monster.id)
			end
		end)
	)
	table.insert(
		connections,
		ctx.Net:On("Monsters.Evolved", function(payload)
			if type(payload) == "table" then
				queueGather(payload.id)
			end
		end)
	)
end

function PenBrain.Detach()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	MoodBubbles.Clear()
	table.clear(minds)
	table.clear(plots)
	api = nil
end

function PenBrain.Describe(model: Model): { [string]: any }?
	for entry, mind in minds do
		if entry.model == model and entry.alive then
			return { action = mind.action, moment = mind.moment, traits = table.clone(mind.t.keys), walking = mind.goalX ~= nil }
		end
	end
	return nil
end

-- Minds held (monsters the brain knows; removed ones go within 5 s).
function PenBrain.Count(): number
	local n = 0
	for _ in minds do
		n += 1
	end
	return n
end

function PenBrain.Stats(): { [string]: number }
	return table.clone(stats)
end

return PenBrain
