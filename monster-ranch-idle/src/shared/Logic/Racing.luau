--[[
	Racing: pure rules of Monster Racing (Config/Racing), shared by the Racing system
	(authoritative time) and the Racing screen (what the player sees).

	Racing.Track(seed) -> { hurdles = { metres }, mud = { { from, to } } }   -- sorted
	Racing.New(speed) -> state                     -- a racer at the start line
	Racing.Step(track, state, inputs)              -- advances one Config.Step
	Racing.Simulate(track, speed, inputs) -> { time, finished, stumbles, jumps, boosts }
	Racing.Valid(inputs) -> ok, why?               -- { { t, a = "jump"|"boost" } }, t ascending
	Racing.Par(track) -> seconds                   -- the ghosts' pace reference
	Racing.Ghosts(track, day) -> { { name, time } } -- sorted fastest first
	Racing.Place(time, ghosts) -> 1..#ghosts+1

	An input applies at the first step whose start time is ≥ its t. A jump or boost that
	isn't ready is ignored (and recorded as ignored in the same way on both sides).
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)

local Cfg = Config.Racing

local Racing = {}

function Racing.Track(seed: number)
	local rng = Rng.new(seed)
	local hurdles, mud = {}, {}
	local x = Cfg.StartClear
	while true do
		x += rng:Int(Cfg.Gap[1], Cfg.Gap[2])
		if x > Cfg.Length - Cfg.EndClear then
			break
		end
		if rng:Chance(Cfg.MudChance) then
			local len = rng:Int(Cfg.MudLength[1], Cfg.MudLength[2])
			local to = math.min(x + len, Cfg.Length - Cfg.EndClear)
			table.insert(mud, { from = x, to = to })
			x = to
		else
			table.insert(hurdles, x)
		end
	end
	return { hurdles = hurdles, mud = mud }
end

function Racing.New(speed: number)
	return {
		t = 0,
		x = 0,
		speed = speed,
		stamina = Cfg.MaxStamina,
		air = 0, -- seconds left in the air
		cooldown = 0, -- seconds until the next jump
		boost = 0, -- seconds of boost left
		stun = 0, -- seconds of stumble left
		nextHurdle = 1,
		nextInput = 1,
		stumbles = 0,
		jumps = 0,
		boosts = 0,
		finished = false,
	}
end

local function inMud(track, x: number): boolean
	for _, m in track.mud do
		if x >= m.from and x < m.to then
			return true
		end
	end
	return false
end

-- Advances `state` by one step. Returns true once the racer has crossed the line.
function Racing.Step(track, state, inputs): boolean
	if state.finished then
		return true
	end
	local dt = Cfg.Step
	-- Inputs due at the start of this step.
	while inputs[state.nextInput] and inputs[state.nextInput].t <= state.t + 1e-9 do
		local input = inputs[state.nextInput]
		state.nextInput += 1
		if input.a == "jump" then
			if state.air <= 0 and state.cooldown <= 0 and state.stun <= 0 then
				state.air = Cfg.JumpSeconds
				state.jumps += 1
			end
		elseif input.a == "boost" then
			if state.stamina >= Cfg.BoostCost and state.boost <= 0 then
				state.stamina -= Cfg.BoostCost
				state.boost = Cfg.BoostSeconds
				state.boosts += 1
			end
		end
	end
	local v = 0
	if state.stun <= 0 then
		v = state.speed
		if state.boost > 0 then
			v *= Cfg.BoostMult
		end
		if state.air <= 0 and inMud(track, state.x) then
			v *= Cfg.MudMult
		end
	end
	local x = state.x + v * dt
	-- Hurdles passed during this step.
	local h = track.hurdles[state.nextHurdle]
	while h and x >= h do
		state.nextHurdle += 1
		if state.air <= 0 then
			state.stumbles += 1
			state.stun = Cfg.StumbleSeconds
			x = h -- stopped at the hurdle
			break
		end
		h = track.hurdles[state.nextHurdle]
	end
	state.x = x
	-- Timers
	local wasAir = state.air > 0
	state.air = math.max(0, state.air - dt)
	if wasAir and state.air <= 0 then
		state.cooldown = Cfg.JumpCooldown
	elseif not wasAir then
		state.cooldown = math.max(0, state.cooldown - dt)
	end
	state.boost = math.max(0, state.boost - dt)
	state.stun = math.max(0, state.stun - dt)
	if state.boost <= 0 then
		state.stamina = math.min(Cfg.MaxStamina, state.stamina + Cfg.StaminaRegen * dt)
	end
	state.t = math.floor((state.t + dt) * 1000 + 0.5) / 1000
	if state.x >= Cfg.Length then
		state.finished = true
	end
	return state.finished
end

function Racing.Simulate(track, speed: number, inputs)
	local state = Racing.New(speed)
	local steps = math.ceil(Cfg.MaxSeconds / Cfg.Step)
	for _ = 1, steps do
		if Racing.Step(track, state, inputs) then
			break
		end
	end
	return {
		time = if state.finished then state.t else Cfg.MaxSeconds,
		finished = state.finished,
		stumbles = state.stumbles,
		jumps = state.jumps,
		boosts = state.boosts,
	}
end

function Racing.Valid(inputs): (boolean, string?)
	if type(inputs) ~= "table" or #inputs > Cfg.MaxInputs then
		return false, "too many moves"
	end
	local last = 0
	for _, input in inputs do
		if type(input) ~= "table" or type(input.t) ~= "number" or (input.a ~= "jump" and input.a ~= "boost") then
			return false, "bad move"
		end
		if input.t ~= input.t or input.t < last or input.t > Cfg.MaxSeconds then
			return false, "moves out of order"
		end
		last = input.t
	end
	return true, nil
end

-- A reference run at ParSpeed: jump just before every hurdle, boost whenever ready.
function Racing.Par(track): number
	local speed = Cfg.ParSpeed
	local inputs = {}
	local state = Racing.New(speed)
	local steps = math.ceil(Cfg.MaxSeconds / Cfg.Step)
	for _ = 1, steps do
		local h = track.hurdles[state.nextHurdle]
		local reach = speed * (if state.boost > 0 then Cfg.BoostMult else 1) * Cfg.JumpSeconds * 0.5
		if h and h - state.x <= reach and state.air <= 0 then
			table.insert(inputs, { t = state.t, a = "jump" })
		end
		if state.stamina >= Cfg.BoostCost and state.boost <= 0 then
			table.insert(inputs, { t = state.t, a = "boost" })
		end
		if Racing.Step(track, state, inputs) then
			break
		end
	end
	return state.t
end

function Racing.Ghosts(track, day: number)
	local par = Racing.Par(track)
	local rng = Rng.new(day * 7919 + 17)
	local names = table.clone(Cfg.GhostNames)
	local ghosts = {}
	for _, pace in Cfg.GhostPace do
		local name = table.remove(names, rng:Int(1, #names))
		table.insert(ghosts, { name = name, time = math.floor(par * pace * 100 + 0.5) / 100 })
	end
	table.sort(ghosts, function(a, b)
		return a.time < b.time
	end)
	return ghosts
end

function Racing.Place(time: number, ghosts): number
	local place = 1
	for _, g in ghosts do
		if g.time < time then
			place += 1
		end
	end
	return place
end

return Racing
