--[[
	Monster Racing (update 3.0 · Year Two): race one of your Adults down the Racetrack
	against three ghost racers. Everyone races the same track each day (the day number
	seeds it), so times compare fairly.

	Your monster runs at its riding speed (Config.Riding.SpeedFor) × SpeedScale metres per
	second. Two moves, both skill:
	  Jump   airborne for JumpSeconds; a hurdle passed on the ground is a stumble
	         (StumbleSeconds standing still). Landing starts JumpCooldown.
	  Boost  costs BoostCost stamina for ×BoostMult speed over BoostSeconds; stamina refills
	         StaminaRegen per second up to MaxStamina.
	Mud patches slow you to ×MudMult (a boost still multiplies on top).

	Anti-cheat: the client sends only { t, a = "jump"|"boost" } moves; the server replays them
	(Logic/Racing.Simulate) against the track and your monster's speed, and the race must
	have taken at least that long on the wall clock.

	Ghosts finish at Par × GhostPace. Par is the track run at ParSpeed with a boost whenever
	one is ready and every hurdle jumped. Places pay `PlaceRewards` for the first
	`RewardedPerDay` races each day and Racing Cup points (`CupPoints`) toward the weekly
	"Racing Cup" leaderboard.
]]

local Racing = {}

Racing.Unlock = "racing"
Racing.Length = 600 -- metres
Racing.Step = 0.05 -- simulation step (seconds)
Racing.MaxSeconds = 90 -- a race that hasn't finished by now is over
Racing.SpeedScale = 0.5 -- riding speed (studs/s) → race speed (m/s): 10–20 m/s
Racing.JumpSeconds = 0.6
Racing.JumpCooldown = 0.25
Racing.StumbleSeconds = 1.0
Racing.BoostCost = 40
Racing.BoostMult = 1.5
Racing.BoostSeconds = 1.5
Racing.MaxStamina = 100
Racing.StaminaRegen = 12
Racing.MudMult = 0.6
Racing.MaxInputs = 200
Racing.GraceSeconds = 1.5
Racing.LateSeconds = 30

-- Track generation (Logic/Racing.Track)
Racing.StartClear = 40 -- metres with nothing at the start
Racing.EndClear = 25
Racing.Gap = { 28, 60 } -- metres between features
Racing.MudChance = 0.3
Racing.MudLength = { 20, 40 }

Racing.ParSpeed = 15 -- m/s (riding speed 30)
Racing.GhostPace = { 0.94, 1.0, 1.08 }
Racing.GhostNames = { "Dash Doe", "Turbo Tam", "Zippy Zed", "Blitz Bea", "Rocket Rue", "Swift Sol", "Pip Pronto", "Nova Nell" }

Racing.RewardedPerDay = 10
Racing.PlaceRewards = {
	{ { kind = "ribbons", amount = 6 }, { kind = "coins", seconds = 600, amount = 0 } },
	{ { kind = "ribbons", amount = 4 }, { kind = "coins", seconds = 300, amount = 0 } },
	{ { kind = "ribbons", amount = 2 }, { kind = "coins", seconds = 120, amount = 0 } },
	{ { kind = "ribbons", amount = 1 } },
}
Racing.CupPoints = { 3, 2, 1, 0 }

return Racing
