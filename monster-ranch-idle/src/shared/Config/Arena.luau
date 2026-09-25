--[[
	Arena (update 2.1): asynchronous PvP with normalized stats, so money and grinding don't
	decide fights: team building does. Every arena fighter fights as an Adult of its own
	species and form at `Normal` (rarity, level, stars) with no traits, mutations, Legacy or
	upgrades; only species stats, element, skill and passive matter.

	You set a defense team of `TeamSize` Adults (a snapshot other players fight against, on
	any server) and attack up to `AttemptsPerDay` times a day, choosing among `Candidates`
	opponents near your rating (bots fill in when too few players are near). Ratings move by
	Elo (`K`). Your best tier of the week pays `WeeklyRewards` once the week is over (weeks
	follow Config.Leaderboards: Saturday 15:00 UTC).
]]

local Arena = {}

Arena.Unlock = "arena"
Arena.TeamSize = 3
Arena.Normal = { rarity = 4, lv = 50, stars = 3 }
Arena.StartRating = 1000
Arena.MinRating = 100
Arena.K = 32
Arena.AttemptsPerDay = 5
Arena.Candidates = 3
Arena.RatingWindow = 200
Arena.MaxTurns = 30
Arena.WinReward = { { kind = "coins", seconds = 300, amount = 0 } }

Arena.Tiers = {
	{ id = "bronze", name = "Bronze", min = 0, color = "#C98B4E" },
	{ id = "silver", name = "Silver", min = 1100, color = "#B9C3CC" },
	{ id = "gold", name = "Gold", min = 1250, color = "#F5C630" },
	{ id = "crystal", name = "Crystal", min = 1400, color = "#7CC7FF" },
	{ id = "champion", name = "Champion", min = 1600, color = "#FF7AC8" },
}

Arena.WeeklyRewards = {
	bronze = { { kind = "gems", amount = 20 } },
	silver = { { kind = "gems", amount = 40 }, { kind = "ribbons", amount = 10 } },
	gold = { { kind = "gems", amount = 70 }, { kind = "ribbons", amount = 20 } },
	crystal = { { kind = "gems", amount = 110 }, { kind = "egg", id = "crystal", amount = 1 } },
	champion = { { kind = "gems", amount = 160 }, { kind = "egg", id = "royal", amount = 1 } },
}

Arena.BotNames = { "Coach Pip", "Ranger Moss", "Captain Ember", "Tide Tamer", "Sparky Sam", "Stone Sage", "Gloom Gale", "Sky Skipper" }

return Arena
