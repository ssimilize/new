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

-- Seasons (update 3.8): 8 Saturday-reset weeks each, counted from `AnchorWeek` of
-- Config.Leaderboards.Week (week 2 = Saturday 3 Oct 2026, 15:00 UTC, is season 1). At a season
-- change a rating moves `ResetFraction` of the way back to StartRating. `Featured` lines per
-- season fight with statMult 1 + FeaturedBoost. Logic/Arena has the date helpers.
Arena.Season = {
	AnchorWeek = 2,
	Weeks = 8,
	ResetFraction = 0.5,
	Featured = 3,
	FeaturedBoost = 0.1,
}

-- Season rewards (3.8), by the best tier reached in a finished season. Paid once, on the
-- player's first join or arena action after the season ends (Systems/Arena). `items` go through
-- Rewards:Grant (source "arena_season"); `titleId` and `auraId` are Mastery cosmetics
-- (Arena.SeasonItems below, merged into Config.Mastery.Rewards) granted with Mastery:GrantItem.
-- Bronze earns nothing. The cups are Config.Decor pieces that are never sold.
Arena.SeasonRewards = {
	silver = { titleId = "title_arena_silver", items = { { kind = "gems", amount = 100 } } },
	gold = {
		titleId = "title_arena_gold",
		items = { { kind = "gems", amount = 200 }, { kind = "decor", id = "arena_cup_gold", amount = 1 } },
	},
	crystal = {
		titleId = "title_arena_crystal",
		items = { { kind = "gems", amount = 400 }, { kind = "decor", id = "arena_cup_crystal", amount = 1 } },
	},
	champion = {
		titleId = "title_arena_champion",
		auraId = "aura_champions_crown",
		items = { { kind = "gems", amount = 800 }, { kind = "decor", id = "arena_cup_champion", amount = 1 } },
	},
}

-- Mastery cosmetics earned from arena seasons (owned once, equipped with Mastery.Equip).
Arena.SeasonItems = {
	{ id = "title_arena_silver", kind = "title", name = "Arena Silver", desc = "Finish an arena season in Silver or higher." },
	{ id = "title_arena_gold", kind = "title", name = "Arena Gold", desc = "Finish an arena season in Gold or higher." },
	{ id = "title_arena_crystal", kind = "title", name = "Arena Crystal", desc = "Finish an arena season in Crystal or higher." },
	{ id = "title_arena_champion", kind = "title", name = "Arena Champion", desc = "Finish an arena season in Champion." },
	{
		id = "aura_champions_crown",
		kind = "aura",
		name = "Champion's Crown Aura",
		desc = "Finish an arena season in Champion. Pink and gold crowns circle your mastered monsters.",
		vfx = "championsCrown",
	},
}

Arena.BotNames = { "Coach Pip", "Ranger Moss", "Captain Ember", "Tide Tamer", "Sparky Sam", "Stone Sage", "Gloom Gale", "Sky Skipper" }

return Arena
