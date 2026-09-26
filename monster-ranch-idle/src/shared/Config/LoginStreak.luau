--[[
	LoginStreak (glow-up): the daily login calendar.

	A 7-day calendar that loops (day 7 pays the most) plus a 28-day milestone track that counts
	days CLAIMED, not consecutive days, so a broken streak never costs milestone progress.
	One claim per UTC day, on the server (Systems/LoginStreak, rules in Logic/LoginStreak).

	Reward items are Rewards items ({ kind, id?, amount, seconds? }) with two extras resolved by
	Logic/LoginStreak.Resolve before granting (the client resolves them the same way to preview):
	  { kind = "coins", seconds = n }           n seconds of the player's ranch income (min 100)
	  { kind = "egg", id = "ladder", step = s } the best egg of EggLadder the player has unlocked,
	                                            `s` rungs higher (capped at the top rung)

	Shield: one is held at a time and refills every UTC week (Monday). It absorbs one missed day
	automatically on the next claim. Without it the 7-day calendar restarts at day 1; the
	milestone track keeps its progress.
]]

local LoginStreak = {}

LoginStreak.Source = "daily_streak" -- Rewards source (reward card title "Rewards · Daily streak")

LoginStreak.Shield = { max = 1 }

-- Egg rungs for `id = "ladder"` rewards, lowest first: { egg, unlock key (Config.Unlocks) }.
LoginStreak.EggLadder = {
	{ egg = "meadow", unlock = "egg_meadow" },
	{ egg = "grove", unlock = "egg_grove" },
	{ egg = "crystal", unlock = "egg_crystal" },
}

-- The 7-day loop. `big` marks the day drawn larger in the calendar.
LoginStreak.Days = {
	{ { kind = "coins", seconds = 900 } },
	{ { kind = "food", id = "random", amount = 5 }, { kind = "treats", amount = 5 } },
	{ { kind = "egg", id = "ladder", step = 0, amount = 1 } },
	{ { kind = "coins", seconds = 1800 }, { kind = "gems", amount = 3 } },
	{ { kind = "stardust", amount = 20 }, { kind = "treats", amount = 10 } },
	{ { kind = "gems", amount = 5 }, { kind = "food", id = "random", amount = 10 } },
	{ { kind = "egg", id = "ladder", step = 1, amount = 1 }, { kind = "gems", amount = 15 }, { kind = "coins", seconds = 3600 } },
}
LoginStreak.BigDay = 7

-- Milestones on the 28-day track (days claimed in the current track). `first` replaces `items`
-- the first time the track is completed (cycles == 0): the Golden Streak Scarf is earned once.
LoginStreak.TrackLength = 28
LoginStreak.Milestones = {
	{ day = 7, items = { { kind = "stardust", amount = 50 }, { kind = "treats", amount = 15 } } },
	{ day = 14, items = { { kind = "gems", amount = 25 }, { kind = "egg", id = "ladder", step = 1, amount = 1 } } },
	{ day = 21, items = { { kind = "gems", amount = 40 }, { kind = "stardust", amount = 80 } } },
	{
		day = 28,
		first = {
			{ kind = "accessory", id = "golden_streak_scarf", amount = 1 },
			{ kind = "egg", id = "starlit", amount = 1 },
			{ kind = "gems", amount = 50 },
		},
		items = { { kind = "egg", id = "starlit", amount = 1 }, { kind = "gems", amount = 75 } },
	},
}

return LoginStreak
