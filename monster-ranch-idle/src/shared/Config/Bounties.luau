--[[
	Expedition Bounties (update 3.9 · Family and fortune). From Ranch Level 6 (Unlocks "bounties")
	each player gets up to Count wanted monsters a week (Config.Leaderboards.Week, Saturday 15:00
	UTC). The draw (Logic/Bounties.Draw) is seeded by ("bounty", userId, week): regions the player
	has unlocked and that are open, distinct regions first, on a non-boss stage the player has
	already cleared, at most Window stages below their furthest clear.

	Fighting that stage puts the bounty monster in the wave (it replaces the front enemy): the
	band's line at the stage's level with StatMult stats, its own name, the Aura and a model
	Config.BattleStage.scale.bounty times bigger. The first win pays Reward once (Rewards source
	"bounty") plus the region's first egg (Regions eggs[1]) with a Luck-scaled chance:
	min(EggChanceMax, EggChance × (1 + loot bonus)), rolled from the bounty's own seed.

	Names: the bounty's name is one of Titles (a format) filled with one of Names.
]]

local Bounties = {}

Bounties.Unlock = "bounties"
Bounties.Count = 3 -- bounties a week
Bounties.Window = 10 -- stages counted back from the furthest clear (inclusive)
Bounties.StatMult = 1.5
Bounties.Aura = "bounty" -- Config.Vfx.Mastery key, drawn through look.aura
Bounties.EggChance = 0.25
Bounties.EggChanceMax = 0.5
Bounties.Source = "bounty" -- Rewards source (reward card title "Rewards · Bounty")

Bounties.Reward = {
	{ kind = "coins", seconds = 1800, amount = 0 },
	{ kind = "gems", amount = 20 },
}

-- Harvested by Locale.spec (a table named *Names): each one is translated like a boss name.
Bounties.Names = {
	"Grumbletooth",
	"Snagglefang",
	"Mudwhisker",
	"Bramblejaw",
	"Thunderhoof",
	"Gnashbelly",
	"Rattlescale",
	"Stormsnout",
	"Crookhorn",
	"Grimbristle",
	"Scowlpaw",
	"Boomtail",
}

-- Each title is one format; the name fills %s.
Bounties.Titles = {
	{ format = "%s the Fierce" },
	{ format = "%s the Sneaky" },
	{ format = "%s the Grumpy" },
	{ format = "%s the Hungry" },
	{ format = "%s the Mighty" },
	{ format = "%s the Wild" },
	{ format = "%s the Loud" },
	{ format = "%s the Terrible" },
}

return Bounties
