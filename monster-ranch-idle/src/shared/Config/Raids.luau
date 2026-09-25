--[[
	Raids (update 2.1): 4-player co-op boss fights on a server. The host opens a lobby for a
	raid and brings up to `PerPlayer` Adults; up to `MaxPlayers` players join with theirs,
	and the host launches one battle: every member's monsters (up to 8) against the raid
	boss and its adds (Logic/BattleSim, `MaxTurns`). A win pays each member the raid's
	`reward` (a Raid Egg: the only way to hatch the raid lines) for their first
	`DailyRewards` raid wins of the UTC day, `Consolation` after that or on a loss.

	Raid monsters: { line, form?, level, rarity, stars, statMult, hpMult? }; hpMult raises HP only,
	so bosses last long without one-shotting a team. Tuned with BattleSim: the Titan falls to
	eight Legendary+ Adults (Lv 50, 4★) but not to eight Epics or four Legendaries; the Wyrm
	needs eight maxed Mythics.
]]

local Raids = {}

Raids.Unlock = "raids"
Raids.MaxPlayers = 4
Raids.PerPlayer = 2
Raids.LobbySeconds = 180
Raids.DailyRewards = 3
Raids.MaxTurns = 40
Raids.Consolation = { { kind = "coins", seconds = 300, amount = 0 } }

Raids.List = {
	{
		id = "titan",
		name = "Stormcrag Titan",
		order = 1,
		desc = "A mountain that learned to throw lightning.",
		boss = { line = "titanling", form = "stormcolossus", level = 42, rarity = 5, stars = 4, statMult = 1, hpMult = 5 },
		adds = {
			{ line = "tempestray", level = 36, rarity = 4, stars = 3, statMult = 1 },
			{ line = "titanling", level = 36, rarity = 4, stars = 3, statMult = 1 },
		},
		reward = { { kind = "egg", id = "raid", amount = 1 }, { kind = "gems", amount = 25 } },
	},
	{
		id = "wyrm",
		name = "Umbral Wyrm",
		order = 2,
		desc = "It swallowed a sunset and never gave it back.",
		boss = { line = "wyrmlet", form = "umbralwyrm", level = 50, rarity = 6, stars = 4, statMult = 1, hpMult = 9 },
		adds = {
			{ line = "wyrmlet", level = 44, rarity = 5, stars = 3, statMult = 1 },
			{ line = "hollowisp", level = 44, rarity = 5, stars = 3, statMult = 1 },
		},
		reward = { { kind = "egg", id = "raid", amount = 2 }, { kind = "gems", amount = 40 } },
	},
}

Raids.ById = {}
for _, r in Raids.List do
	Raids.ById[r.id] = r
end

return Raids
