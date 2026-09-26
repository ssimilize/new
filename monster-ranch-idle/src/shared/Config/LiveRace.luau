--[[
	Live races (glow-up LR): up to six riders race their mounts round a loop track in the world,
	north-west of plot 6. Rules: Logic/LiveRace; server: Systems/LiveRace; gear: Systems/RaceGear.

	One heat at a time: idle → lobby (LobbySeconds, or FullSeconds once MaxRiders are in) →
	countdown (3-2-1-GO) → running (Laps laps, checkpoints in order) → podium → idle.
	With fewer than MinPlayers riders, ghosts from Monster Racing (Config.Racing) fill the field.

	Speed (studs/s) = Config.Riding.SpeedFor(monster) × SpeedScale; a boost multiplies it by
	BoostMult for BoostSeconds and costs BoostCost of a meter that refills slowly on its own, fast
	while drafting (close behind another rider) or drifting (steering hard through a curve).
	Hurdles need a jump (else a stumble: StunMult speed for StumbleSeconds); boost pads on one
	half of the track give a free boost. Places pay Monster Racing's PlaceRewards and Cup points
	(Racing:Award, the same daily cap).

	Anti-cheat: riders report their position (x, z) every ReportEvery seconds. The server
	projects it onto the centreline and refuses a report that leaves the track or moves farther
	(along the track or in a straight line) than the rider's speed allows over the interval
	(boosts and stumbles counted, × CapSlack + SlackStuds). A refused report snaps the rider back
	and is a strike; MaxStrikes strikes disqualify. Checkpoints are credited in order from the
	accepted distance, so a lap cut short or run backwards never counts.

	Racing gear is cosmetic only (the design doc asks for no stat nudge): saddles, trails and
	banners earned from race milestones, drawn on the mount. `mesh` ids are optional
	(Visuals/RaceTrack draws parts with materials until a mesh is uploaded).
]]

local LiveRace = {}

LiveRace.Unlock = "racing"
LiveRace.MaxRiders = 6
LiveRace.MinPlayers = 2 -- fewer riders than this race the ghosts too
LiveRace.LobbySeconds = 12
LiveRace.FullSeconds = 3 -- a full lobby starts this soon
LiveRace.CountdownSeconds = 3
LiveRace.Laps = 2
LiveRace.MaxSeconds = 150 -- a heat that runs this long ends; riders still out are DNF
LiveRace.FinishWindow = 25 -- after the first rider finishes, the rest have this long
LiveRace.PodiumSeconds = 8
LiveRace.TickSeconds = 0.25

-- The loop: two straights along x joined by half circles. `center` = { x, y, z }.
LiveRace.Track = {
	center = { -210, 0, 340 },
	straight = 120,
	radius = 40,
	halfWidth = 12,
	curveSegments = 12, -- road pieces per half circle (Visuals/RaceTrack)
	roadY = 0.1,
	mesh = "", -- optional road mesh id
}
-- Fractions of a lap. Checkpoint arches (the last one, 1, is the start/finish line).
LiveRace.Checkpoints = { 0.25, 0.5, 0.75, 1 }
LiveRace.Hurdles = { 0.14, 0.6 }
LiveRace.BoostPads = { { at = 0.38, side = -1 }, { at = 0.88, side = 1 } } -- side: -1 outside, 1 inside
LiveRace.PadLength = 10
LiveRace.Lanes = { -10, -6, -2, 2, 6, 10 } -- grid lateral offsets (studs; + = inside of the loop)
-- The start pad beside the start line (outside the loop) and the podium beside it.
LiveRace.StartPad = { -228, 0, 283 }
LiveRace.Podium = { -190, 0, 283 }

-- Riding
LiveRace.SpeedScale = 1
LiveRace.SteerSpeed = 16 -- studs/s sideways
LiveRace.JumpSeconds = 0.6
LiveRace.JumpHeight = 5
LiveRace.JumpCooldown = 0.25
LiveRace.StumbleSeconds = 1
LiveRace.StunMult = 0.3
LiveRace.BoostMult = 1.5
LiveRace.BoostSeconds = 1.5
LiveRace.BoostCost = 35
LiveRace.MeterMax = 100
LiveRace.MeterStart = 50
LiveRace.MeterRegen = 4 -- per second, always
LiveRace.DraftRegen = 20 -- per second while drafting
LiveRace.DriftRegen = 14 -- per second while drifting through a curve
LiveRace.DraftRange = 18 -- studs behind another rider
LiveRace.DraftLateral = 5
LiveRace.DriftSteer = 0.5 -- |steer| at or above this through a curve is a drift

-- Anti-cheat
LiveRace.ReportEvery = 0.25
LiveRace.CapSlack = 1.15
LiveRace.SlackStuds = 4
LiveRace.StartGrace = 1 -- extra seconds allowed in the first report (the server clock is whole seconds)
LiveRace.OffTrack = 6 -- studs past the edge before a report counts as off the track
LiveRace.JumpGrace = 0.5
LiveRace.MaxStrikes = 5
LiveRace.MaxGap = 5 -- a report interval longer than this is counted as this long

-- Ghosts (fewer than MinPlayers riders): Config.Racing.GhostNames at Config.Racing.GhostPace × par,
-- par = the heat's distance at ParSpeed.
LiveRace.ParSpeed = 30

-- Effects (client): budgets are per client and drop at Low quality.
LiveRace.Camera = { back = 16, up = 7, ahead = 8, pitch = -0.28, fov = 70, boostFov = 82 }
LiveRace.SpeedLines = 10
LiveRace.DriftTrails = 3 -- riders whose drift sparks show at once (nearest first)

-- Racing gear: cosmetic. `need` = { stat, n } from profile.RaceGear:
--   races (any race finished), live (live races finished), podiums (live top 3), wins (any 1st),
--   duels (live wins against another player).
LiveRace.GearKinds = { "saddle", "trail", "banner" }
LiveRace.Gear = {
	{
		id = "saddle_rookie",
		kind = "saddle",
		name = "Rookie Saddle",
		how = "Finish a race",
		color = "#B8733A",
		color2 = "#6B3F1F",
		material = "Fabric",
		mesh = "",
		need = { stat = "races", n = 1 },
	},
	{
		id = "trail_dust",
		kind = "trail",
		name = "Dust Trail",
		how = "Finish 3 live races",
		color = "#E8C99A",
		color2 = "#FFF3DA",
		material = "Neon",
		mesh = "",
		need = { stat = "live", n = 3 },
	},
	{
		id = "banner_checker",
		kind = "banner",
		name = "Checkered Banner",
		how = "Finish in the top 3 of a live race",
		color = "#FFFFFF",
		color2 = "#222222",
		material = "Fabric",
		mesh = "",
		need = { stat = "podiums", n = 1 },
	},
	{
		id = "saddle_gold",
		kind = "saddle",
		name = "Golden Saddle",
		how = "Win 5 races",
		color = "#FFD447",
		color2 = "#B8860B",
		material = "Foil",
		mesh = "",
		need = { stat = "wins", n = 5 },
	},
	{
		id = "trail_comet",
		kind = "trail",
		name = "Comet Trail",
		how = "Finish 10 live races",
		color = "#7FD8FF",
		color2 = "#FFFFFF",
		material = "Neon",
		mesh = "",
		need = { stat = "live", n = 10 },
	},
	{
		id = "banner_crown",
		kind = "banner",
		name = "Champion Banner",
		how = "Win a live race against another player",
		color = "#8B6AD8",
		color2 = "#FFD447",
		material = "Fabric",
		mesh = "",
		need = { stat = "duels", n = 1 },
	},
}
LiveRace.GearById = {}
for _, item in LiveRace.Gear do
	LiveRace.GearById[item.id] = item
end

return LiveRace
