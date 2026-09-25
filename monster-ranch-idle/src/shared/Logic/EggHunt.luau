--[[
	EggHunt: pure egg-hunt round rules shared by the EggHunt system and the client.

	EggHunt.Round(now) -> (round, endsAt)       -- rounds are aligned to the unix clock
	EggHunt.SpotsFor(round) -> { spotIndex }    -- Config.EggHunt.PerRound distinct spots, sorted
	EggHunt.Distance(a, b) -> studs             -- a, b = { x, y, z } or Vector3-like { X, Y, Z }
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)

local Cfg = Config.EggHunt

local EggHunt = {}

function EggHunt.Round(now: number): (number, number)
	local round = math.floor(now / Cfg.RoundSeconds)
	return round, (round + 1) * Cfg.RoundSeconds
end

function EggHunt.SpotsFor(round: number): { number }
	local indices = {}
	for i = 1, #Cfg.Spots do
		indices[i] = i
	end
	local rng = Rng.new(Rng.seed("egghunt", round))
	rng:Shuffle(indices)
	local picked = table.move(indices, 1, Cfg.PerRound, 1, {})
	table.sort(picked)
	return picked
end

local function xyz(p): (number, number, number)
	if p.X ~= nil then
		return p.X, p.Y, p.Z
	end
	return p[1], p[2], p[3]
end

function EggHunt.Distance(a, b): number
	local ax, ay, az = xyz(a)
	local bx, by, bz = xyz(b)
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
end

return EggHunt
