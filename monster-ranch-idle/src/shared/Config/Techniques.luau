--[[
	Techniques (update 3.11 · Seasons & secrets): the Dojo's learned battle techniques.

	Two per element (Config/Elements). An Adult learns techniques of its own element(s) at the
	Dojo (Systems/Dojo, rules in Logic/Dojo) and keeps them on its record as
	`m.tech = { { id, lv } }` (at most MaxSlots; the 2nd slot opens at Bond heart Slot2Hearts).

	In battle (Logic/BattleSim) a unit with techniques fires one every Charge-th action of its
	own, on a charge separate from the species Special; with two it alternates them. A technique
	uses the effect vocabulary of the species Specials (Config/Species.Skills):
	  strike  one enemy, `power` × ATK
	  blast   every enemy, `power` × ATK each
	  drain   one enemy, then heals itself for `lifesteal` of the damage
	  stun    one enemy, then a `stunChance` chance to stun it
	  heal    every ally heals `heal` of its max HP
	  shield  every ally gains a `shield` share of its max HP as a shield (Special cap applies)
	`levels[lv]` holds the numbers for levels 1..MaxLevel.

	Training (Systems/Dojo): Train[lv] = { stardust, seconds } to learn (lv 1) or level up to lv.
]]

local Techniques = {}

Techniques.Unlock = "dojo" -- Config.Unlocks.Features.dojo (Ranch Level 24)
Techniques.MinStage = 3 -- Adults only
Techniques.MaxSlots = 2
Techniques.Slot2Hearts = 5 -- Bond heart that opens the 2nd slot
Techniques.MaxLevel = 3
Techniques.Charge = 4 -- every 4th action of the unit
Techniques.BusyTag = "dojo"

Techniques.Train = {
	{ stardust = 300, seconds = 20 * 60 },
	{ stardust = 900, seconds = 60 * 60 },
	{ stardust = 2000, seconds = 3 * 60 * 60 },
}

-- Player-facing one-liners per kind (the Dojo rows).
Techniques.KindText = {
	strike = "A heavy hit on one enemy.",
	blast = "Hits every enemy.",
	drain = "Hits one enemy and heals itself.",
	stun = "Hits one enemy and may stun it.",
	heal = "Heals every ally.",
	shield = "Shields every ally.",
}

-- Numbers per kind and level (balance gate: tests/specs/DojoBalance.spec.luau). A basic hit
-- is power 1; a technique replaces one action in four.
local Levels = {
	strike = { { power = 1.1 }, { power = 1.16 }, { power = 1.22 } },
	blast = { { power = 0.38 }, { power = 0.43 }, { power = 0.48 } },
	drain = { { power = 1.0, lifesteal = 0.25 }, { power = 1.02, lifesteal = 0.3 }, { power = 1.05, lifesteal = 0.35 } },
	stun = { { power = 0.95, stunChance = 0.1 }, { power = 1.0, stunChance = 0.14 }, { power = 1.05, stunChance = 0.18 } },
	heal = { { heal = 0.07 }, { heal = 0.085 }, { heal = 0.1 } },
	shield = { { shield = 0.07 }, { shield = 0.083 }, { shield = 0.095 } },
}
Techniques.Levels = Levels

Techniques.List = {
	{
		id = "flare_burst",
		name = "Flare Burst",
		element = "ember",
		kind = "blast",
		levels = Levels.blast,
	},
	{
		id = "cinder_fang",
		name = "Cinder Fang",
		element = "ember",
		kind = "strike",
		levels = Levels.strike,
	},
	{
		id = "undertow",
		name = "Undertow",
		element = "tide",
		kind = "drain",
		levels = Levels.drain,
	},
	{
		id = "tidal_mend",
		name = "Tidal Mend",
		element = "tide",
		kind = "heal",
		levels = Levels.heal,
	},
	{
		id = "bramble_guard",
		name = "Bramble Guard",
		element = "sprout",
		kind = "shield",
		levels = Levels.shield,
	},
	{
		id = "sap_leech",
		name = "Sap Leech",
		element = "sprout",
		kind = "drain",
		levels = Levels.drain,
	},
	{
		id = "static_snap",
		name = "Static Snap",
		element = "spark",
		kind = "stun",
		levels = Levels.stun,
	},
	{
		id = "chain_spark",
		name = "Chain Spark",
		element = "spark",
		kind = "blast",
		levels = Levels.blast,
	},
	{
		id = "dread_howl",
		name = "Dread Howl",
		element = "gloom",
		kind = "stun",
		levels = Levels.stun,
	},
	{
		id = "night_veil",
		name = "Night Veil",
		element = "gloom",
		kind = "shield",
		levels = Levels.shield,
	},
	{
		id = "boulder_slam",
		name = "Boulder Slam",
		element = "stone",
		kind = "strike",
		levels = Levels.strike,
	},
	{
		id = "quake",
		name = "Quake",
		element = "stone",
		kind = "blast",
		levels = Levels.blast,
	},
	{
		id = "radiant_mend",
		name = "Radiant Mend",
		element = "light",
		kind = "heal",
		levels = Levels.heal,
	},
	{
		id = "sunbeam",
		name = "Sunbeam",
		element = "light",
		kind = "strike",
		levels = Levels.strike,
	},
	{
		id = "null_grasp",
		name = "Null Grasp",
		element = "void",
		kind = "stun",
		levels = Levels.stun,
	},
	{
		id = "rift_rend",
		name = "Rift Rend",
		element = "void",
		kind = "strike",
		levels = Levels.strike,
	},
}

Techniques.ById = {}
Techniques.Ids = {}
Techniques.ByElement = {} -- [element] = { technique }
for _, tech in Techniques.List do
	Techniques.ById[tech.id] = tech
	table.insert(Techniques.Ids, tech.id)
	Techniques.ByElement[tech.element] = Techniques.ByElement[tech.element] or {}
	table.insert(Techniques.ByElement[tech.element], tech)
end

return Techniques
