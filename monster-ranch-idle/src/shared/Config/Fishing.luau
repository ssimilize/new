--[[
	Fishing Pond (update 3.10 · Ranch life). A pond in the north strip of every plot
	(Config.World.Pond) with a "Fish" prompt that opens the Fishing screen. From Ranch Level 13
	(Unlocks "fishing").

	Casts: FreeCasts a UTC day, then one Bait each (bait comes from Expedition Bounties and
	Rewards kind "bait"). A cast is spent when the line goes in (Fishing.Start).

	The minigame (Logic/Fishing): a fish swims up and down a bar along a course seeded by the
	server; hold to lift the catch zone, let go and it sinks. While the zone covers the fish the
	catch meter fills, otherwise it drains. Full = caught, empty or out of time = it got away.
	The client sends only its hold / release moves; the server replays them (the Surf and Racing
	anti-cheat pattern: grace and late wall-clock checks, one-shot run ids).

	Which fish bites is a seeded roll over Rarities[].weight; the fishing buddy's Luck multiplies
	every weight but common by (1 + bonus). Bonus = Loot.LuckBonus with the buddy's Luck counted
	BuddyShares times (a buddy fishes like a whole squad, so it reaches Loot.LuckLootMax).
	Extras on a catch use the Bounties formula: min(cap, chance × (1 + bonus)).

	Fish: { id, name, rarity, color, weight = { min, max } kg }. Rarity: { id, name, weight,
	value (seconds of ranch income one fish sells for), speed = { min, max } (seconds a move
	takes), range (furthest move, bar = 0..1), pause (chance a move stays put), fill, drain
	(meter per second) }.
]]

local Fishing = {}

Fishing.Unlock = "fishing"
Fishing.Source = "fishing" -- Rewards source (reward card "Rewards · Fishing")

Fishing.FreeCasts = 10 -- a UTC day
Fishing.MaxBait = 999
Fishing.BuddyShares = 5

-- The minigame. Positions run 0 (bottom) .. 1 (top).
Fishing.Duration = 20 -- seconds before the fish gets away
Fishing.Step = 0.05 -- fixed simulation step (seconds)
Fishing.ZoneSize = 0.26
Fishing.Lift = 2.4 -- zone acceleration while held (bar per second²)
Fishing.Gravity = 2 -- and while released
Fishing.MaxSpeed = 0.9
Fishing.StartMeter = 0.3
Fishing.StartFish = 0.5
Fishing.FishRange = { 0.3, 0.95 } -- the fish never swims below the resting zone: nobody reeling = it gets away
Fishing.MaxInputs = 400
Fishing.GraceSeconds = 1.5 -- network slack when checking a run's wall-clock time
Fishing.LateSeconds = 30 -- a run must be finished within Duration + this

Fishing.Rarities = {
	{ id = "common", name = "Common", weight = 60, value = 60, speed = { 1.4, 2.4 }, range = 0.35, pause = 0.3, fill = 0.3, drain = 0.12 },
	{
		id = "uncommon",
		name = "Uncommon",
		weight = 28,
		value = 150,
		speed = { 1, 1.8 },
		range = 0.5,
		pause = 0.2,
		fill = 0.26,
		drain = 0.14,
	},
	{ id = "rare", name = "Rare", weight = 10, value = 400, speed = { 0.7, 1.3 }, range = 0.65, pause = 0.15, fill = 0.22, drain = 0.16 },
	{
		id = "legendary",
		name = "Legendary",
		weight = 2,
		value = 1200,
		speed = { 0.5, 1 },
		range = 0.75,
		pause = 0.1,
		fill = 0.2,
		drain = 0.18,
	},
}

Fishing.Fish = {
	{ id = "minnow", name = "Pond Minnow", rarity = "common", color = "#9FB8C8", weight = { 0.05, 0.2 } },
	{ id = "bluegill", name = "Bluegill", rarity = "common", color = "#4F8FD6", weight = { 0.1, 0.5 } },
	{ id = "perch", name = "Sunny Perch", rarity = "common", color = "#E8C547", weight = { 0.2, 0.8 } },
	{ id = "mudcat", name = "Mud Catfish", rarity = "common", color = "#8A6A4A", weight = { 0.5, 2.5 } },
	{ id = "trout", name = "Rainbow Trout", rarity = "uncommon", color = "#E88AA8", weight = { 0.5, 3 } },
	{ id = "eel", name = "Ribbon Eel", rarity = "uncommon", color = "#5E8C4A", weight = { 0.3, 2 } },
	{ id = "pike", name = "Reed Pike", rarity = "uncommon", color = "#7FA35A", weight = { 1, 5 } },
	{ id = "carp", name = "Golden Carp", rarity = "uncommon", color = "#F2A93B", weight = { 1, 6 } },
	{ id = "puffer", name = "Bubble Puffer", rarity = "rare", color = "#F5E6A8", weight = { 0.3, 1.5 } },
	{ id = "glowfin", name = "Glowfin", rarity = "rare", color = "#6FF2D8", weight = { 0.5, 2 } },
	{ id = "koi", name = "Lantern Koi", rarity = "rare", color = "#FF7A45", weight = { 2, 8 } },
	{ id = "sturgeon", name = "Stone Sturgeon", rarity = "rare", color = "#8E8A83", weight = { 5, 20 } },
	{ id = "moonscale", name = "Moonscale", rarity = "legendary", color = "#C9C2FF", weight = { 3, 12 } },
	{ id = "ember_bass", name = "Ember Bass", rarity = "legendary", color = "#E5484D", weight = { 4, 15 } },
	{ id = "crystal_ray", name = "Crystal Ray", rarity = "legendary", color = "#A9DEFF", weight = { 6, 25 } },
	{ id = "pond_king", name = "Pond King", rarity = "legendary", color = "#F5C630", weight = { 15, 60 } },
}

-- Extras on a catch: one decor piece at most (first that rolls), then a region egg.
Fishing.Decor = {
	{ id = "old_boot", chance = 0.04, cap = 0.08 },
	{ id = "sunken_chest", chance = 0.015, cap = 0.03 },
}
Fishing.Egg = "pearl" -- Coral Reef's region egg (its first-clear reward; never sold)
Fishing.EggChance = 0.05
Fishing.EggChanceMax = 0.1

Fishing.RarityById = {}
for i, r in Fishing.Rarities do
	r.order = i
	Fishing.RarityById[r.id] = r
end
Fishing.ById = {}
Fishing.Ids = {}
for i, f in Fishing.Fish do
	assert(Fishing.RarityById[f.rarity], "[Config.Fishing] unknown rarity " .. tostring(f.rarity))
	assert(Fishing.ById[f.id] == nil, "[Config.Fishing] duplicate fish " .. f.id)
	f.order = i
	Fishing.ById[f.id] = f
	table.insert(Fishing.Ids, f.id)
end

return Fishing
