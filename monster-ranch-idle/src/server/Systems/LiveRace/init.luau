--[[
	LiveRace (glow-up LR): live races round the track in the world, up to Config.LiveRace.MaxRiders
	riders on their mounts. Rules: Config/LiveRace and Logic/LiveRace. Pays through Racing:Award.

	No save section. One heat at a time on the server:
	  idle → lobby (LobbySeconds, or FullSeconds once full) → countdown (goAt) → running → podium → idle
	With fewer than MinPlayers riders the Monster Racing ghosts join the heat.

	Session (session.LiveRace): { heat: number|false, meter, lap, progress, strikes, finished,
	                              dq, result = { place, time, finished, field, rewards, cup, dq }|false }
	Global  (global.LiveRace):  { state, heat, lobbyEndsAt, goAt, podiumEndsAt, laps,
	                              racers = { { userId, name, appearance, lane, progress, lateral, finished, dq } },
	                              ghosts = { { name, time, lane } }, results = { Result }|false }
	  Result = { name, place, time|false, ghost, userId, dq, appearance? }

	Actions:
	  LiveRace.Join {} -> { heat, lane }        the player must be riding an Adult (Riding:MountOf)
	  LiveRace.Leave {}                          in the lobby frees the lane; while running = forfeit
	  LiveRace.Progress { heat, x, z, drift } -> { accepted, x, z, progress, lap, meter, finished }
	    the rider's position; refused (snap back to x, z, a strike) when off the track or faster
	    than Logic.Allowed; checkpoints are credited in order from accepted distance only.
	  LiveRace.Jump { heat } -> { ok }           opens the hurdle window (JumpSeconds + JumpGrace)
	  LiveRace.Boost { heat } -> { meter, seconds }
	The rider leaves the heat on dismount, leaving the server, or MaxStrikes strikes (disqualified).
	Server clocks: phase times are ctx:Now() seconds; race times are Clock.Precise() since GO.
	Public: LiveRace:Heat() -> the heat record (tests), LiveRace:IsRacing(player) -> boolean.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.LiveRace)
local Appearance = require(Shared.Logic.Appearance)

local LiveRace = {
	Name = "LiveRace",
	Dependencies = { "Progression", "Monsters", "Riding", "Racing" },
}

local ctx
local Cfg -- Config.LiveRace
local Progression, Monsters, Riding, Racing

local heat = nil -- the current heat (nil = idle)
local lastHeat = 0

local function precise(): number
	return ctx.Clock.Precise()
end

local function round(n: number, step: number): number
	return math.floor(n / step + 0.5) * step
end

local function isHub(): boolean
	local services = ctx.Services
	return ctx.Config.TradingHub.Mode(services.PlaceId, services.PlaceMode) == "hub"
end

local function count(): number
	local n = 0
	if heat then
		for _ in heat.racers do
			n += 1
		end
	end
	return n
end

-- State ---------------------------------------------------------------------------------------

local function publish()
	local g = ctx:Global()
	if not heat then
		g.state = "idle"
		g.heat = lastHeat
		g.lobbyEndsAt, g.goAt, g.podiumEndsAt = 0, 0, 0
		g.laps = Cfg.Laps
		g.racers, g.ghosts, g.results = {}, {}, false
	else
		g.state = heat.state
		g.heat = heat.id
		g.lobbyEndsAt = heat.lobbyEndsAt
		g.goAt = heat.goAt or 0
		g.podiumEndsAt = heat.podiumEndsAt or 0
		g.laps = Cfg.Laps
		local list = {}
		for _, r in heat.racers do
			table.insert(list, {
				userId = r.userId,
				name = r.name,
				appearance = r.appearance,
				lane = r.lane,
				progress = round(r.progress, 0.1),
				lateral = round(r.lateral, 0.1),
				finished = r.finished,
				dq = r.dq or r.out,
			})
		end
		table.sort(list, function(a, b)
			return a.lane < b.lane
		end)
		g.racers = list
		g.ghosts = heat.ghosts or {}
		g.results = heat.results or false
	end
	-- Every field above changes together on every publish; mark them all, not just "state"
	-- (each is its own replicated path — see Kernel/State's header).
	for _, key in { "state", "heat", "lobbyEndsAt", "goAt", "podiumEndsAt", "laps", "racers", "ghosts", "results" } do
		ctx:DirtyGlobal(key)
	end
end

local function setSession(player, fields)
	local sess = ctx:Session(player)
	if not sess then
		return
	end
	for k, v in fields do
		sess[k] = v
	end
	ctx:DirtySession(player)
end

local function sync(r)
	setSession(r.player, {
		heat = heat and heat.id or false,
		meter = round(r.meter, 0.1),
		lap = math.min(Cfg.Laps, r.cp // #Cfg.Checkpoints + 1),
		progress = round(r.progress, 0.1),
		strikes = r.strikes,
		finished = r.finished,
		dq = r.dq,
	})
end

local function clearSession(player, result)
	setSession(player, {
		heat = false,
		meter = Cfg.MeterStart,
		lap = 0,
		progress = 0,
		strikes = 0,
		finished = false,
		dq = false,
		result = result or false,
	})
end

local function reply(r, accepted: boolean)
	return {
		accepted = accepted,
		x = r.x,
		z = r.z,
		progress = r.progress,
		lap = math.min(Cfg.Laps, r.cp // #Cfg.Checkpoints + 1),
		meter = r.meter,
		finished = r.finished,
	}
end

-- Meter ---------------------------------------------------------------------------------------

local function refill(r, t: number)
	local from = r.meterAt or t
	if t > from then
		r.meter = Logic.Refill(r.meter, t - from, r.drafting, r.drifting)
	end
	r.meterAt = t
end

local function prune(spans, t: number)
	for i = #spans, 1, -1 do
		if spans[i][2] < t - 10 then
			table.remove(spans, i)
		end
	end
end

-- Heat lifecycle ------------------------------------------------------------------------------

local function toIdle()
	if heat then
		for player in heat.racers do
			local sess = ctx:Session(player)
			if sess and sess.heat == heat.id then
				setSession(player, { heat = false })
			end
		end
	end
	heat = nil
	publish()
end

local function startRunning()
	heat.state = "running"
	heat.goPrecise = precise()
	for _, r in heat.racers do
		-- The server's clock is whole seconds, so GO may have been up to a second ago.
		r.lastAt = heat.goPrecise - Cfg.StartGrace
		r.meterAt = heat.goPrecise
		sync(r)
	end
	publish()
end

local function settle()
	local entries = {}
	local humans = 0
	for _, r in heat.racers do
		humans += 1
		table.insert(entries, {
			id = "u" .. r.userId,
			r = r,
			name = r.name,
			finished = r.finished,
			time = r.time or 0,
			progress = r.progress,
			dq = r.dq or r.out,
		})
	end
	for i, gh in heat.ghosts or {} do
		local done = gh.time <= Cfg.MaxSeconds
		table.insert(entries, {
			id = "g" .. i,
			name = gh.name,
			ghost = true,
			finished = done,
			time = gh.time,
			progress = if done then Logic.Total() else Logic.GhostProgress(gh, Cfg.MaxSeconds),
			dq = false,
		})
	end
	local order = Logic.Order(entries)
	local results = {}
	for _, e in order do
		local r = e.r
		table.insert(results, {
			name = e.name,
			place = e.place,
			time = if e.finished then e.time else false,
			ghost = e.ghost == true,
			userId = if r then r.userId else 0,
			dq = e.dq == true,
			appearance = if r then r.appearance else nil,
		})
		if r then
			local player = r.player
			if r.out then
				clearSession(player, false)
			elseif r.dq then
				clearSession(player, { place = e.place, dq = true, field = #order, rewards = {}, cup = 0, finished = false, time = 0 })
			else
				-- A rider still out when the heat ends is paid like the last row (Monster Racing's DNF).
				local paid = Racing:Award(player, {
					place = if e.finished then e.place else math.max(e.place, #ctx.Config.Racing.PlaceRewards),
					time = e.time,
					finished = e.finished,
					live = true,
					riders = humans,
				})
				clearSession(player, {
					place = e.place,
					time = if e.finished then e.time else 0,
					finished = e.finished,
					field = #order,
					rewards = paid.rewards,
					cup = paid.cup,
					dq = false,
				})
			end
		end
	end
	heat.results = results
	heat.state = "podium"
	heat.podiumEndsAt = ctx:Now() + Cfg.PodiumSeconds
	publish()
end

local function update()
	if not heat then
		return
	end
	local now = ctx:Now()
	if heat.state == "lobby" then
		if count() == 0 then
			toIdle()
		elseif Logic.LobbyDone(now, heat.lobbyEndsAt, count(), heat.fullAt) then
			heat.state = "countdown"
			heat.goAt = now + Cfg.CountdownSeconds
			heat.ghosts = Logic.Ghosts(count(), heat.id * 7919 + ctx:Day())
			publish()
		end
	end
	if heat and heat.state == "countdown" and now >= heat.goAt then
		startRunning()
	end
	if heat and heat.state == "running" then
		if count() == 0 then
			toIdle()
			return
		end
		local elapsed = precise() - heat.goPrecise
		local active = 0
		for player, r in heat.racers do
			if not (r.finished or r.dq or r.out) then
				if Riding:MountOf(player) ~= r.monster then
					r.out = true -- got off the mount: out of the race
					publish()
				else
					active += 1
				end
			end
		end
		local windowShut = heat.firstFinish ~= nil and elapsed >= heat.firstFinish + Cfg.FinishWindow
		if active == 0 or elapsed >= Cfg.MaxSeconds or windowShut then
			settle()
		end
	elseif heat and heat.state == "podium" and now >= heat.podiumEndsAt then
		toIdle()
	end
end

local function tick()
	update()
	if not heat or heat.state ~= "running" then
		return
	end
	local t = precise()
	local list = {}
	for _, r in heat.racers do
		if not (r.finished or r.dq or r.out) then
			table.insert(list, r)
		end
	end
	for _, r in list do
		refill(r, t)
		r.drafting = Logic.Drafting(r, list)
	end
	publish()
end

-- Actions -------------------------------------------------------------------------------------

local function racerOf(player, heatId: number?)
	local r = heat and heat.racers[player]
	if not r or (heatId and heat.id ~= heatId) then
		ctx:Fail("That race is over")
	end
	return r
end

local function join(player)
	if isHub() then
		ctx:Fail("Live races run on ranch servers")
	end
	Progression:Require(player, Cfg.Unlock)
	local id = Riding:MountOf(player)
	local m = id and Monsters:Get(player, id)
	if not m then
		ctx:Fail("Ride one of your Adults to race")
	end
	if m.stage ~= 3 then
		ctx:Fail("Only Adults can race")
	end
	update()
	local ok, why = Logic.CanJoin(if heat then heat.state else "idle", count(), heat ~= nil and heat.racers[player] ~= nil)
	if not ok then
		ctx:Fail(why :: string)
	end
	if not heat then
		lastHeat += 1
		heat = { id = lastHeat, state = "lobby", lobbyEndsAt = ctx:Now() + Cfg.LobbySeconds, racers = {} }
		for _, other in ctx:Players() do
			if other ~= player then
				ctx:Notify(other, "A live race is starting at the Racetrack! Ride to the start pad to join.", "info")
			end
		end
	end
	local used = {}
	for _, r in heat.racers do
		used[r.lane] = true
	end
	local lane = 1
	while used[lane] do
		lane += 1
	end
	local lateral = Cfg.Lanes[lane]
	local x, z = Logic.Point(0, lateral)
	local r = {
		player = player,
		userId = player.UserId,
		name = player.DisplayName or player.Name,
		monster = id,
		appearance = Appearance.Of(m),
		speed = Logic.SpeedFor(m),
		lane = lane,
		u = 0,
		x = x,
		z = z,
		lateral = lateral,
		lastAt = precise(),
		progress = 0,
		cp = 0,
		boosts = {},
		stuns = {},
		jumpAt = nil,
		meter = Cfg.MeterStart,
		meterAt = nil,
		drafting = false,
		drifting = false,
		strikes = 0,
		finished = false,
		time = nil,
		dq = false,
		out = false,
	}
	heat.racers[player] = r
	if count() >= Cfg.MaxRiders then
		heat.fullAt = ctx:Now()
	end
	setSession(player, { result = false })
	sync(r)
	publish()
	return { heat = heat.id, lane = lane }
end

local function leave(player)
	local r = heat and heat.racers[player]
	if not r then
		ctx:Fail("You aren't in a race")
	end
	if heat.state == "lobby" or heat.state == "countdown" then
		heat.racers[player] = nil
		heat.fullAt = nil
		clearSession(player, false)
		update()
		publish()
	elseif heat.state == "running" then
		r.out = true -- a forfeit: no place, no reward
		clearSession(player, false)
		publish()
		update()
	else
		clearSession(player, nil)
	end
	return nil
end

local function progress(player, payload)
	local r = racerOf(player, payload.heat)
	update()
	if not heat or heat.state ~= "running" or r.finished or r.dq or r.out then
		return reply(r, true)
	end
	if Riding:MountOf(player) ~= r.monster then
		r.out = true
		clearSession(player, false)
		publish()
		return reply(r, false)
	end
	local t = precise()
	refill(r, t)
	local x, z = payload.x, payload.z
	local u, lateral, off = Logic.Project(x, z)
	local ds = Logic.Wrap(u - r.u)
	local chord = math.sqrt((x - r.x) ^ 2 + (z - r.z) ^ 2)
	local from = r.progress
	local to = from + ds
	local len = Logic.Length()
	local padHit = false
	for _, pad in Cfg.BoostPads do
		if Logic.Crossed(from, to, pad.at * len) and lateral * pad.side >= 0.5 then
			padHit = true
		end
	end
	local spans = r.boosts
	if padHit then
		spans = table.clone(r.boosts)
		table.insert(spans, { r.lastAt, t + Cfg.BoostSeconds })
	end
	local allowed = Logic.Allowed(r.speed, r.lastAt, t, spans, r.stuns)
	if off > Cfg.OffTrack or math.abs(ds) > allowed or chord > allowed then
		r.strikes += 1
		if r.strikes >= Cfg.MaxStrikes then
			r.dq = true
			publish()
		end
		sync(r)
		return reply(r, false)
	end
	if padHit then
		table.insert(r.boosts, { r.lastAt, t + Cfg.BoostSeconds })
	end
	for _, f in Cfg.Hurdles do
		if Logic.Crossed(from, to, f * len) then
			local jumped = r.jumpAt ~= nil and r.jumpAt + Cfg.JumpSeconds + Cfg.JumpGrace >= r.lastAt
			if not jumped then
				-- Crossed somewhere in [lastAt, t]: the earliest start is the lenient one.
				table.insert(r.stuns, { r.lastAt, r.lastAt + Cfg.StumbleSeconds })
			end
		end
	end
	local total = Logic.CheckpointCount()
	while r.cp < total and Logic.Threshold(r.cp + 1) <= to do
		r.cp += 1
		if r.cp == total then
			local line = Logic.Threshold(total)
			local frac = if to > from then (line - from) / (to - from) else 1
			local before = math.max(0, r.lastAt - heat.goPrecise)
			local now = t - heat.goPrecise
			r.finished = true
			r.time = round(math.max(0, before + (now - before) * frac), 0.01)
			if not heat.firstFinish then
				heat.firstFinish = now
			end
		end
	end
	r.progress = to
	r.u, r.x, r.z, r.lateral, r.lastAt = u, x, z, lateral, t
	r.drifting = payload.drift == true and Logic.IsCurve(u)
	prune(r.boosts, t)
	prune(r.stuns, t)
	sync(r)
	if r.finished then
		publish()
		update()
	end
	return reply(r, true)
end

local function jump(player, heatId: number)
	local r = racerOf(player, heatId)
	update()
	if not heat or heat.state ~= "running" or r.finished or r.dq or r.out then
		return { ok = false }
	end
	local t = precise()
	-- A jump is only ready again after landing and the cooldown (a little early for lag).
	if r.jumpAt and t - r.jumpAt < Cfg.JumpSeconds + Cfg.JumpCooldown - 0.2 then
		return { ok = false }
	end
	r.jumpAt = t
	return { ok = true }
end

local function boost(player, heatId: number)
	local r = racerOf(player, heatId)
	update()
	if not heat or heat.state ~= "running" or r.finished or r.dq or r.out then
		ctx:Fail("The race hasn't started")
	end
	local t = precise()
	refill(r, t)
	local last = r.boosts[#r.boosts]
	if last and last[2] > t + 0.2 then
		ctx:Fail("Already boosting")
	end
	if r.meter < Cfg.BoostCost then
		ctx:Fail("Not enough boost")
	end
	r.meter -= Cfg.BoostCost
	table.insert(r.boosts, { t, t + Cfg.BoostSeconds })
	sync(r)
	return { meter = r.meter, seconds = Cfg.BoostSeconds }
end

-- Public API ----------------------------------------------------------------------------------

function LiveRace:Heat()
	return heat
end

function LiveRace:IsRacing(player): boolean
	local r = heat and heat.racers[player]
	return r ~= nil and not (r.finished or r.dq or r.out)
end

-- Lifecycle -----------------------------------------------------------------------------------

function LiveRace.Init(context)
	ctx = context
	Cfg = ctx.Config.LiveRace
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	Riding = ctx:GetSystem("Riding")
	Racing = ctx:GetSystem("Racing")
	heat = nil
	lastHeat = 0
	publish()

	ctx.Net:Handle("LiveRace.Join", function(player)
		return join(player)
	end)
	ctx.Net:Handle("LiveRace.Leave", function(player)
		return leave(player)
	end)
	ctx.Net:Handle("LiveRace.Progress", function(player, payload)
		return progress(player, payload)
	end)
	ctx.Net:Handle("LiveRace.Jump", function(player, payload)
		return jump(player, payload.heat)
	end)
	ctx.Net:Handle("LiveRace.Boost", function(player, payload)
		return boost(player, payload.heat)
	end)
	ctx:Every(Cfg.TickSeconds, tick)
end

function LiveRace.PlayerAdded(player)
	clearSession(player, false)
end

function LiveRace.PlayerRemoving(player)
	if heat and heat.racers[player] then
		heat.racers[player] = nil
		heat.fullAt = nil
		publish()
		update()
	end
end

return LiveRace
