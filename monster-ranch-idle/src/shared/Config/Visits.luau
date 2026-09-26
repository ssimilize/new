--[[
	Visits (glow-up Y): likes that pay, the crown over the server's most-liked ranch, visiting a
	friend's ranch on any server (teleport, or its snapshot in the Visiting Showcase) and the
	Ranch of the Week stage. Rules in Logic/Visits, server in Systems/Visits, client in
	Controllers/Visits + Visuals/RanchShowcase.
]]

local Visits = {}

-- Likes that pay. A like pays the liker and the owner once per pair per UTC day, within the
-- daily caps below. The liker must pass `Gate` (same shape as Config.Community.Gifts, checked by
-- Logic/Community.GiftGate) for the like to pay anyone or count for the crown and Ranch of the
-- Week, so a fresh alt can't farm likes for a main.
Visits.Likes = {
	likerReward = { { kind = "friendship", amount = 5 } },
	ownerReward = { { kind = "friendship", amount = 10 } },
	likerPaidPerDay = 5, -- likes that pay the liker each UTC day
	ownerPaidPerDay = 10, -- received likes that pay the owner each UTC day
	mailKind = "ranchlike", -- Market mail kind for a like given to a ranch snapshot
}

Visits.Gate = { minLevel = 5, minPlaySeconds = 30 * 60, minAccountDays = 7 }

-- The crown over the gate of this server's most-liked ranch today (counted likes only).
Visits.Crown = {
	height = 16, -- studs above the gate
	color = "#FFC83D",
	glow = "#FFE08A",
	spin = 40, -- degrees per second
}

-- Snapshots of a ranch, saved through ctx.Services.Ranches when the owner leaves and every
-- `saveSeconds` while they play (only when it changed).
Visits.Snapshot = {
	version = 1,
	saveSeconds = 600,
	maxBytes = 12000, -- estimated encoded size; monsters are dropped from the back to fit
	maxPens = 6,
	maxMonstersPerPen = 8,
	maxBest = 3,
	maxDecor = 40, -- placed ranch decor (filled by the ranch builder)
	maxName = 24,
	maxMuts = 4,
	maxAcc = 6,
	maxGardenPlots = 12,
}

-- Visiting a friend: after a teleport request the client waits this long; still here means the
-- teleport failed (full server), and it asks for the snapshot instead.
Visits.Visit = { teleportWaitSeconds = 12 }

-- Places (world space, main place only). Scenery keeps off both (Config.World.VisitGrounds).
Visits.Showcase = {
	center = { 140, 0, 236 },
	size = { 120, 76 }, -- x, z: three pens across, two deep, a garden and the gate in front
	penGap = 4,
}
Visits.Stage = {
	center = { -120, 0, 214 },
	size = { 50, 36 },
	scale = 0.6, -- the winner's best monsters stand on the stage at this scale
	maxMonsters = 5,
	refreshSeconds = 1800, -- how often a server re-reads last week's winner
	modelRange = 160, -- models are built only within this range of the camera
}

-- The weekly board (Config.Leaderboards) that ranks likes received.
Visits.BoardId = "ranchlikes"

return Visits
