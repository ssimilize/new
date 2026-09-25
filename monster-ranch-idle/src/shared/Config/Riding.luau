--[[
	Riding (update 2.0): travel the hub on one of your Adult monsters. The mount is drawn
	under your character for everyone and you move at its riding speed:
	  speed = clamp(Base + species base SPD × PerSpd + (rarity − 1) × PerRarity, Min, Max)
	(walking is WalkSpeed). Any Adult can be a mount unless it is busy.
]]

local Species = require(script.Parent.Species)

local Riding = {}

Riding.Unlock = "riding"
Riding.WalkSpeed = 16
Riding.Base = 20
Riding.PerSpd = 0.5
Riding.PerRarity = 1.5
Riding.Min = 20
Riding.Max = 40
Riding.MountScale = 1.8 -- mounts are drawn bigger so a player fits on top

function Riding.SpeedFor(m): number
	local def = Species.ById[m.line]
	local spd = if def then def.base.spd else 10
	local speed = Riding.Base + spd * Riding.PerSpd + ((m.rarity or 1) - 1) * Riding.PerRarity
	return math.clamp(math.floor(speed * 10 + 0.5) / 10, Riding.Min, Riding.Max)
end

return Riding
