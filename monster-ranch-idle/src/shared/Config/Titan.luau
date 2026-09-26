--[[
	Titan (glow-up TT): scheduled, server-wide titan invasions. A titan is announced to every
	server (Controllers/TitanInvasion: a bigger banner/horn/storm than the regular Stampede) and
	fought at the same arena (Config.World.StampedeArena) as a bigger, distinct giant. Every
	server fights its own copy of the titan, but damage from every server drains ONE shared HP
	pool (ctx.Services.Titan, see Kernel/Adapters); the titan falls everywhere at once when the
	pool empties, or retreats if `Duration` runs out first.

	Schedule: fixed dates (unix seconds, Saturdays 15:00 UTC like Events/Regions). Each entry
	picks a Rotation slot directly (no player-power scaling: Max HP is fixed by design so every
	server, however many players it has, fights the very same fight).
]]

local Titan = {}

Titan.Unlock = "boss" -- same unlock as the Stampede
Titan.LobbySeconds = 180 -- join button/banner appear this long before the start
Titan.Duration = 20 * 60
Titan.TickSeconds = 1
Titan.ReportSeconds = 5 -- how often each server folds its damage into the shared pool
Titan.StaleServerSeconds = 30 -- a server that hasn't reported in this long drops out of the count
Titan.MaxServersListed = 150 -- the shared record lists at most this many servers (shown as "150+")
Titan.DamagePerPowerPerSecond = 1.0
Titan.CheerMaxBonus = 0.2
Titan.CheerPerTap = 0.01
Titan.CheerDecayPerSecond = 0.02
Titan.MaxTapsPerRequest = 20
Titan.MaxTapsPerSecond = 15

-- Reuses the Stampede's proven forms (line/form pairs already animated end to end) at a much
-- bigger scale under a new name: no new 3D art in this pass. maxHp is the whole shared pool.
Titan.Rotation = {
	{ id = "colossyth", name = "Colossyth", line = "emberslug", form = "cinderwyrm", element = "ember", maxHp = 4.5e6 },
	{ id = "tidereaver", name = "The Tidereaver", line = "bubblin", form = "tsunamander", element = "tide", maxHp = 5e6 },
}

-- Sat 1 Apr / 15 Apr / 6 May 2028, 15:00 UTC: a first batch; Design Weeks (3.3) may add more.
Titan.Schedule = {
	{ startsAt = 1838214000, rotation = 1 }, -- Sat 1 Apr 2028: Colossyth
	{ startsAt = 1839423600, rotation = 2 }, -- Sat 15 Apr 2028: The Tidereaver
	{ startsAt = 1841238000, rotation = 1 }, -- Sat 6 May 2028: Colossyth
}

Titan.Rewards = {
	participation = {
		{ kind = "coins", seconds = 900 }, -- 15 minutes of the player's ranch output
		{ kind = "food", id = "random", amount = 8 },
		{ kind = "treats", amount = 8 },
		{ kind = "gems", amount = 8 },
	},
	egg = "titan", -- guaranteed to every helper (never a chance roll: fair, P5)
	minDamageToHelp = 1, -- dealt any damage at all counts as "helped"
}

-- Glow-up TT: the giant at the Stampede arena; no squads or cheer bolts are drawn for it
-- (Controllers/TitanInvasion keeps the client small - see the packet report for why).
Titan.Arena = {
	bossScale = 16,
	staggers = { 0.75, 0.5, 0.25 },
	flinchGap = 1.5,
	fallSeconds = 3,
	leaveSeconds = 6,
	roarPitch = 0.4,
	storm = { tint = "#6A3FA0", brightness = -0.14, contrast = 0.18, saturation = -0.4, fade = 3 },
	lightningEvery = { 5, 10 },
}

Titan.ById = {}
for _, def in Titan.Rotation do
	Titan.ById[def.id] = def
end

return Titan
