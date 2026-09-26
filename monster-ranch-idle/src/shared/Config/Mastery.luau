--[[
	Mastery: the endgame layer (update 3.3). Server: Systems/Mastery. Rules: Logic/Mastery.

	Design (for the ~25% of players who optimise, without leaving anyone else behind):

	1. Ranch Mastery. At the Ranch Level cap in force (Unlocks.MaxLevelAt) Ranch XP is no longer
	   thrown away: Progression publishes it as "RanchXPOverflow" and it fills an endless Ranch
	   Mastery track. Level L -> L + 1 costs RanchBase + RanchStep x L XP (2,500, 2,750, 3,000 ...;
	   Mastery 100 costs 27,250, about a Ranch Level at 70), never capped. Every Mastery level pays
	   ShardsPerLevel Star Shards, and every 10th pays MilestoneShards more.

	2. Line Mastery. Every species line earns points from what the player does with its monsters,
	   at any Ranch Level (LinePoints): hatching, levelling, evolving, winning fights (expeditions,
	   raids, arena; once per line per fight), retiring. Line level L -> L + 1 costs LineBase +
	   LineStep x L points, never capped. Tiers (badges in MonsterDetail and the Codex) at
	   Bronze 5 · Silver 12 · Gold 25 · Mythic 40. Gold and Mythic lines wear a mastery aura
	   (Config/Vfx Mastery.gold / .mythic). Line Mastery grants no stats at all.

	3. The Star Shard Constellation (Shop). Shards (Hall of Fame retires, Ranch Mastery, the
	   ladder) buy:
	   · trait rerolls: pick a visible trait slot; the new trait is a seeded roll (Rng.seed of the
	     player, monster and reroll count, so rejoining never changes it) from the same pool as a
	     hatch (MonsterGen.PickTrait), never one the monster already has. Cost RerollCosts[n] for
	     the n-th reroll of that monster (then the last entry: the price never runs away).
	   · prestige cosmetics: auras (shown on monsters of Bronze+ lines, replacing the Gold/Mythic
	     look), nameplate flourishes, statue plinth styles.
	   · mastery perks: small, capped convenience (incubator speed, coin jar size, expedition
	     loot). Nothing here touches battle stats: the Arena normalises stats and raids are tuned
	     for maxed Mythics, so fights stay exactly as they were.

	4. The Mythic Ladder. While a Ranch Pass season runs (Quests.Seasons), mastery gained earns
	   ladder points: 1 per LadderXP Ranch Mastery XP plus 1 per LadderLine Line Mastery points.
	   Tier rewards are granted once per season the moment a tier is reached (Ladder). The same
	   points, counted per week, are the 7th leaderboard ("mastery").

	Kinds of shop item: "reroll" is not an item (Mastery.Reroll); "aura", "flourish", "plinth"
	and "title" are cosmetics (owned once, equipped with Mastery.Equip); "perk" has levels.
]]

local Mastery = {}

-- Ranch Mastery --------------------------------------------------------------------------
Mastery.RanchBase = 2500
Mastery.RanchStep = 250
Mastery.ShardsPerLevel = 1
Mastery.MilestoneEvery = 10
Mastery.MilestoneShards = 3

-- The HUD entry appears once the player is at the cap, has any Ranch Mastery, or a Silver line.
Mastery.HudTier = 2

-- Line Mastery ---------------------------------------------------------------------------
Mastery.LineBase = 50
Mastery.LineStep = 25
Mastery.LinePoints = {
	hatchBase = 8, -- + hatchPerRarity x rarity
	hatchPerRarity = 2,
	levelUp = 1, -- per level gained
	evolve = 20,
	fightWin = 3, -- per line in the winning team (once per line per fight)
	retireBase = 20, -- + retirePerRarity x rarity
	retirePerRarity = 10,
}

Mastery.Tiers = {
	{ id = "bronze", name = "Bronze", level = 5, color = "#C9834A" },
	{ id = "silver", name = "Silver", level = 12, color = "#B9C3CF" },
	{ id = "gold", name = "Gold", level = 25, color = "#F2C230", aura = "gold" },
	{ id = "mythic", name = "Mythic", level = 40, color = "#E8436F", aura = "mythic" },
}

-- Star Shard Constellation ---------------------------------------------------------------
Mastery.RerollCosts = { 3, 5, 8, 12, 16, 20 }

Mastery.Shop = {
	-- Prestige auras (Config/Vfx Mastery[vfx])
	{
		id = "aura_starlight",
		kind = "aura",
		name = "Starlight Aura",
		desc = "Soft stars drift round your mastered monsters.",
		cost = 12,
		vfx = "starlight",
	},
	{ id = "aura_aurora", kind = "aura", name = "Aurora Aura", desc = "Ribbons of green and violet light.", cost = 20, vfx = "aurora" },
	{
		id = "aura_comet",
		kind = "aura",
		name = "Comet Aura",
		desc = "Little comets circle your mastered monsters.",
		cost = 30,
		vfx = "comet",
	},
	-- Nameplate flourishes
	{
		id = "flourish_sparkle",
		kind = "flourish",
		name = "Sparkle Flourish",
		desc = "A sparkle on your nameplate.",
		cost = 8,
		glyph = "✦",
		color = "#8FD3FF",
	},
	{
		id = "flourish_crown",
		kind = "flourish",
		name = "Crown Flourish",
		desc = "A crown on your nameplate.",
		cost = 15,
		glyph = "👑",
		color = "#F2C230",
	},
	{
		id = "flourish_comet",
		kind = "flourish",
		name = "Comet Flourish",
		desc = "A comet on your nameplate.",
		cost = 25,
		glyph = "☄",
		color = "#FF8A3D",
	},
	-- Statue plinth styles
	{
		id = "plinth_marble",
		kind = "plinth",
		name = "Marble Plinth",
		desc = "White marble under your statues.",
		cost = 10,
		color = "#EDEAE4",
		material = "Marble",
	},
	{
		id = "plinth_obsidian",
		kind = "plinth",
		name = "Obsidian Plinth",
		desc = "Polished black stone under your statues.",
		cost = 15,
		color = "#2A2433",
		material = "Glass",
	},
	{
		id = "plinth_starstone",
		kind = "plinth",
		name = "Starstone Plinth",
		desc = "Glowing blue stone under your statues.",
		cost = 25,
		color = "#4F7BD9",
		material = "Neon",
	},
	-- Mastery perks (levels; effect per level; capped by maxLevel)
	{
		id = "perk_hatch",
		kind = "perk",
		name = "Warm Nests",
		desc = "Eggs hatch 1% faster per level (up to 5%).",
		costs = { 5, 8, 12, 16, 20 },
		maxLevel = 5,
		effect = { hatchSpeed = 0.01 },
	},
	{
		id = "perk_jar",
		kind = "perk",
		name = "Deep Jars",
		desc = "Coin jars hold 10 more minutes per level (up to 30).",
		costs = { 6, 10, 15 },
		maxLevel = 3,
		effect = { jarCapSeconds = 600 },
	},
	{
		id = "perk_loot",
		kind = "perk",
		name = "Keen Eyes",
		desc = "Expedition loot +1% per level (up to 5%).",
		costs = { 5, 8, 12, 16, 20 },
		maxLevel = 5,
		effect = { lootPct = 0.01 },
	},
}

-- Rewards that are not sold (the ladder's). Same shape as shop cosmetics, no cost.
Mastery.Rewards = {
	{ id = "flourish_laurel", kind = "flourish", name = "Laurel Flourish", desc = "A ladder reward.", glyph = "❦", color = "#62BF55" },
	{ id = "plinth_gilded", kind = "plinth", name = "Gilded Plinth", desc = "A ladder reward.", color = "#E0B040", material = "Foil" },
	{ id = "aura_mythic_flame", kind = "aura", name = "Mythic Flame Aura", desc = "A ladder reward.", vfx = "mythicFlame" },
	{ id = "title_mythic", kind = "title", name = "Mythic Master", desc = "Reach the top of a Mythic Ladder." },
	{ id = "title_gold", kind = "title", name = "Gold Wrangler", desc = "Reach Gold on a Mythic Ladder." },
}

-- Mythic Ladder --------------------------------------------------------------------------
Mastery.LadderXP = 100 -- Ranch Mastery XP per ladder point
Mastery.LadderLine = 10 -- Line Mastery points per ladder point
Mastery.Ladder = {
	{ points = 25, name = "Copper", shards = 2 },
	{ points = 75, name = "Bronze", item = "flourish_laurel" },
	{ points = 150, name = "Silver", shards = 4 },
	{ points = 300, name = "Gold", shards = 5, item = "title_gold" },
	{ points = 500, name = "Platinum", item = "plinth_gilded" },
	{ points = 800, name = "Mythic", shards = 8, item = "title_mythic", item2 = "aura_mythic_flame" },
}

-- Glow-up O: Codex milestone titles and the Codex Crown aura (Config/Codex.Items) are Mastery
-- cosmetics too: owned through Codex claims, equipped with Mastery.Equip.
for _, item in require(script.Parent.Codex).Items do
	table.insert(Mastery.Rewards, item)
end

Mastery.EquipKinds = { "aura", "flourish", "plinth", "title" }

Mastery.ShopById = {}
Mastery.ItemById = {}
for _, item in Mastery.Shop do
	Mastery.ShopById[item.id] = item
	Mastery.ItemById[item.id] = item
end
for _, item in Mastery.Rewards do
	Mastery.ItemById[item.id] = item
end
Mastery.TierById = {}
for i, tier in Mastery.Tiers do
	tier.index = i
	Mastery.TierById[tier.id] = tier
end

return Mastery
