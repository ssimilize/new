--[[
	Surf Shack (update 2.0 · Summer Splash): a 3-lane surfing minigame. Rocks and seashells
	ride the waves toward you; switch lanes to dodge rocks and catch shells. A run lasts
	`Duration` seconds or until `Lives` rocks are hit.

	Anti-cheat: the course comes from a server seed (Logic/Surf.Course) and the client sends
	only its lane changes; the server replays them (Logic/Surf.Simulate) to get the score.
	Score = shells × ShellPoints + whole seconds survived × SecondPoints.
	Seashells paid = min(MaxTokensPerRun, floor(score / PointsPerToken)), through the event's
	daily token cap (Events:Grant).
]]

local Surf = {}

Surf.Event = "summersplash"
Surf.Duration = 45
Surf.Lanes = 3
Surf.StartLane = 2
Surf.Lives = 3
Surf.FirstItemAt = 2
Surf.Gap = { 0.55, 1.1 } -- seconds between waves (shrinks by up to SpeedUp over the run)
Surf.SpeedUp = 0.35
Surf.ShellChance = 0.45
Surf.DoubleRockChance = 0.25
Surf.ShellPoints = 10
Surf.SecondPoints = 2
Surf.PointsPerToken = 20
Surf.MaxTokensPerRun = 40
Surf.MaxInputs = 300
Surf.GraceSeconds = 1.5 -- network slack when checking a run's wall-clock time
Surf.LateSeconds = 30 -- a run must be finished within Duration + this

return Surf
