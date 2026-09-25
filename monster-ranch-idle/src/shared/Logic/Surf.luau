--[[
	Surf: pure rules of the Surf Shack minigame (Config/Surf), shared by the Surf system
	(authoritative score) and the Surf screen (what the player sees).

	Surf.Course(seed) -> { { t, lane, kind = "rock"|"shell" } }   -- sorted by t
	  t = when the item reaches the surfer's line (seconds after the run starts)
	Surf.LaneAt(inputs, t) -> lane                                  -- Config.StartLane before any input
	Surf.Valid(inputs) -> ok, why?                                   -- { { t, lane } }, t ascending, in range
	Surf.Simulate(seed, inputs) -> { score, shells, hits, survived, wiped }
	  An item counts when the surfer is in its lane at its t (input at exactly t already applies).
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)

local Cfg = Config.Surf

local Surf = {}

function Surf.Course(seed: number)
	local rng = Rng.new(seed)
	local items = {}
	local t = Cfg.FirstItemAt
	while t < Cfg.Duration do
		local lane = rng:Int(1, Cfg.Lanes)
		local kind = if rng:Chance(Cfg.ShellChance) then "shell" else "rock"
		table.insert(items, { t = t, lane = lane, kind = kind })
		if kind == "rock" and rng:Chance(Cfg.DoubleRockChance) then
			local other = (lane + rng:Int(0, Cfg.Lanes - 2)) % Cfg.Lanes + 1
			table.insert(items, { t = t, lane = other, kind = "rock" })
		end
		local speed = 1 - Cfg.SpeedUp * (t / Cfg.Duration)
		t += rng:Float(Cfg.Gap[1], Cfg.Gap[2]) * speed
		t = math.floor(t * 1000 + 0.5) / 1000
	end
	return items
end

function Surf.LaneAt(inputs, t: number): number
	local lane = Cfg.StartLane
	for _, input in inputs do
		if input.t <= t then
			lane = input.lane
		else
			break
		end
	end
	return lane
end

function Surf.Valid(inputs): (boolean, string?)
	if type(inputs) ~= "table" or #inputs > Cfg.MaxInputs then
		return false, "too many moves"
	end
	local last = 0
	for _, input in inputs do
		if type(input) ~= "table" or type(input.t) ~= "number" or type(input.lane) ~= "number" then
			return false, "bad move"
		end
		if input.t < last or input.t > Cfg.Duration or input.t ~= input.t then
			return false, "moves out of order"
		end
		if input.lane < 1 or input.lane > Cfg.Lanes or input.lane % 1 ~= 0 then
			return false, "bad lane"
		end
		last = input.t
	end
	return true, nil
end

function Surf.Simulate(seed: number, inputs)
	local shells, hits = 0, 0
	local survived = Cfg.Duration
	local wiped = false
	for _, item in Surf.Course(seed) do
		if Surf.LaneAt(inputs, item.t) == item.lane then
			if item.kind == "shell" then
				shells += 1
			else
				hits += 1
				if hits >= Cfg.Lives then
					survived = item.t
					wiped = true
					break
				end
			end
		end
	end
	return {
		score = shells * Cfg.ShellPoints + math.floor(survived) * Cfg.SecondPoints,
		shells = shells,
		hits = hits,
		survived = survived,
		wiped = wiped,
	}
end

return Surf
