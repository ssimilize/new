--[[
	Clubs (update 1.2, design §18): groups of up to 30 players across every server, with
	weekly club goals and a weekly club boss. Club records live in their own DataStore
	(Services.Clubs); weeks follow the leaderboard week (Saturday 15:00 UTC).

	Goals: each week `GoalsPerWeek` goals are drawn from `Goals` (the same draw on every
	server). A goal's target is `perMember` × the member count when the week started (at
	least `MinScaleMembers`). Members add progress by playing; when a goal is done every
	member can claim its reward once that week.

	Boss: a weekly club boss with `hpPerMember` × members HP. Each member attacks up to
	`attacksPerDay` times a UTC day; an attack deals `damagePerRootPower` × √(squad power),
	so newer players still matter. Everyone who attacked can claim the reward once it falls.

	Club Wars (update 3.1, from `War.startsAt`): members earn war points for their club from
	raids, racing and Stampedes (`War.sources`, at most `War.dailyCap` per member per UTC day).
	A weekly ladder ranks every club across servers. When the week ends, each club lands in a
	league by its points, the top `War.champion.top` clubs are Champions, and every member who
	earned war points claims that reward during the next week.
	Banners (3.1): officers can hang a Workshop design they own as the club banner.
]]

local Clubs = {}

Clubs.Unlock = "clubs"
Clubs.MaxMembers = 30
Clubs.CreateCost = { coins = 50000 }
Clubs.NameLength = { 3, 20 }
Clubs.TagLength = { 2, 4 } -- letters and digits, shown upper case
Clubs.CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" -- no 0/O or 1/I
Clubs.CodeLength = 6
Clubs.SyncSeconds = 60 -- how often a server writes contributions and re-reads its clubs
Clubs.MinScaleMembers = 5

Clubs.Colors = { "#E5484D", "#F2A93B", "#FFD447", "#43B649", "#4FB6F2", "#8B6AD8", "#EF6FA8", "#3B3F46" }
Clubs.Emblems = {
	{ id = "star", glyph = "★" },
	{ id = "paw", glyph = "🐾" },
	{ id = "flame", glyph = "🔥" },
	{ id = "leaf", glyph = "🍃" },
	{ id = "bolt", glyph = "⚡" },
	{ id = "moon", glyph = "🌙" },
	{ id = "wave", glyph = "🌊" },
	{ id = "gem", glyph = "💎" },
}
Clubs.EmblemById = {}
for _, e in Clubs.Emblems do
	Clubs.EmblemById[e.id] = e
end

-- Roles, highest first. Officers can kick members and change settings; only the owner
-- can promote, demote or hand over the club.
Clubs.Roles = { "owner", "officer", "member" }

Clubs.GoalsPerWeek = 3
-- `topic`: Bus topic that adds progress; `amount`: field of the detail to add (default 1);
-- `per`: divide that field (expedition seconds → hours); `filter`: detail fields to match.
Clubs.Goals = {
	{ id = "hatch", text = "Hatch %s eggs", topic = "EggHatched", perMember = 40 },
	{ id = "stages", text = "Clear %s new stages", topic = "StageCleared", filter = { first = true }, perMember = 8 },
	{ id = "stampede", text = "Join %s Stampedes", topic = "BossJoined", perMember = 6 },
	{ id = "expeditions", text = "Explore for %s hours", topic = "ExpeditionClaimed", amount = "duration", per = 3600, perMember = 16 },
	{ id = "breed", text = "Breed %s monsters", topic = "Bred", perMember = 3 },
	{ id = "pets", text = "Pet %s monsters on other ranches", topic = "PetGiven", perMember = 20 },
	{ id = "feed", text = "Feed %s meals", topic = "MonsterFed", perMember = 30 },
}
Clubs.GoalById = {}
for _, g in Clubs.Goals do
	Clubs.GoalById[g.id] = g
end
-- Reward for the 1st, 2nd and 3rd goal of the week.
Clubs.GoalRewards = {
	{ { kind = "gems", amount = 30 } },
	{ { kind = "egg", id = "grove", amount = 1 }, { kind = "treats", amount = 20 } },
	{ { kind = "egg", id = "crystal", amount = 1 } },
}

Clubs.Boss = {
	names = { "The Tangled Titan", "Grumblecrag", "Mistmaw", "Sir Squallington" },
	hpPerMember = 30000,
	attacksPerDay = 3,
	damagePerRootPower = 100,
	minDamage = 500,
	reward = { { kind = "egg", id = "stampede", amount = 1 }, { kind = "gems", amount = 50 } },
}

-- Club Wars (update 3.1) ------------------------------------------------------------
Clubs.War = {
	startsAt = 1833375600, -- Sat 5 Feb 2028, 15:00 UTC (update 3.1)
	dailyCap = 150,
	-- points: fixed per event; field × mult: from the event's detail; filter: detail must match;
	-- bonus when detail.rank ≤ bonusRank.
	sources = {
		{ id = "raid", topic = "RaidFinished", filter = { win = true }, points = 25, text = "Win a raid: 25" },
		{ id = "race", topic = "RaceFinished", field = "cup", mult = 5, text = "Racing Cup points ×5" },
		{ id = "stampede", topic = "BossDamage", points = 5, bonusRank = 3, bonus = 10, text = "Finish a Stampede: 5 (+10 in the top 3)" },
	},
	leagues = {
		{ id = "bronze", name = "Bronze", min = 0, color = "#C98B4E", reward = { { kind = "gems", amount = 20 } } },
		{
			id = "silver",
			name = "Silver",
			min = 600,
			color = "#B9C3CC",
			reward = { { kind = "gems", amount = 40 }, { kind = "ribbons", amount = 20 } },
		},
		{
			id = "gold",
			name = "Gold",
			min = 1500,
			color = "#F5C630",
			reward = { { kind = "gems", amount = 70 }, { kind = "egg", id = "crystal", amount = 1 } },
		},
		{
			id = "diamond",
			name = "Diamond",
			min = 3000,
			color = "#7CC7FF",
			reward = { { kind = "gems", amount = 110 }, { kind = "egg", id = "royal", amount = 1 } },
		},
	},
	-- The week's top clubs on the ladder (replaces their league reward).
	champion = {
		top = 3,
		name = "Champion",
		color = "#FF7AC8",
		reward = { { kind = "gems", amount = 160 }, { kind = "egg", id = "royal", amount = 2 } },
	},
	ladderSize = 10,
	ladderRefresh = 300, -- seconds between ladder reads per server
}

-- The league a weekly war score lands in.
function Clubs.League(points: number)
	local best = Clubs.War.leagues[1]
	for _, league in Clubs.War.leagues do
		if points >= league.min then
			best = league
		end
	end
	return best
end

return Clubs
