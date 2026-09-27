--[[
	Trial Tower (update 3.12 · Honey & stars). From Ranch Level 26 (Unlocks "trial_tower") the
	player climbs an endless tower with their Expeditions squad, one floor per won fight. The
	tower stands in the Market Square (Config.World.Hub id "trialTower") and is also reached from
	the Expeditions screen's header. Rules in Logic/TrialTower, the server in Systems/TrialTower.

	Enemies: floor f is fought in region Regions.List[ceil(f / RegionFloors)] (the last region from
	then on) on a stage drawn with a seed of ("tower", week, f), so everyone meets the same wave
	that week. Every BossEvery-th floor is a boss floor: one of that region's bosses. Each enemy's
	stats are scaled so its power is Power(f) = BasePower × Growth^(f − 1) (a boss: × BossMult);
	levels and rarities are the stage's own, for show.

	Attempts: DailyAttempts a UTC day; a loss uses one, a win uses none. With none left a loss
	spends a Retry token (Rewards kind "tower_retry"; +1 on every Expedition Bounty, the
	Travelling Merchant's Retry Token offer), at most RetryCap held.

	Weekly: the climb (floor = the next floor to fight, best = highest cleared) starts over at the
	leaderboard week (Config.Leaderboards.Week, Saturday 15:00 UTC). The week's best feeds the
	"tower" board. Milestones (every MilestoneEvery floors) pay once a week each; Records (every
	RecordEvery floors) pay gems once ever, the first time the all-time record reaches them.
]]

local TrialTower = {}

TrialTower.Unlock = "trial_tower"
TrialTower.Source = "tower" -- Rewards source (reward card "Rewards · Trial Tower")
TrialTower.DailyAttempts = 3
TrialTower.RetryCap = 99

-- Enemies.
TrialTower.RegionFloors = 10 -- floors per region band (floors 1-10 Meadow, 11-20 Coral, ...)
TrialTower.BossEvery = 10
TrialTower.BasePower = 190 -- power of one floor-1 enemy (a Level-26 squad of Rare-ish Adults tops out near floor 12)
TrialTower.Growth = 1.07 -- power × this per floor (×10 power ≈ +34 floors: a maxed squad of 5 reaches 40+)
TrialTower.BossMult = 1.8 -- a boss's power, in floor enemies (it fights alone)

-- Weekly milestones: every MilestoneEvery floors, once a week each.
TrialTower.MilestoneEvery = 5
TrialTower.MilestoneSeconds = 600 -- coins: seconds of ranch income per 5 floors (×1 at 5, ×2 at 10, ...)
TrialTower.MilestoneDust = 3 -- stardust per 5 floors
TrialTower.MilestoneGems = { [25] = 60, [50] = 150 }

-- One-time-ever record bonus: every RecordEvery floors, gems.
TrialTower.RecordEvery = 10
TrialTower.RecordGems = 40

return TrialTower
