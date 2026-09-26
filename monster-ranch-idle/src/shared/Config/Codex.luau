--[[
	Codex (glow-up O): milestones that pay, the walk-in Codex Museum and the Hall of Fame plaza.
	Server: Systems/Codex (claims) and Systems/HallOfFame (the plaza). Rules: Logic/Codex
	(milestones from the species, egg and region data) and Logic/Museum (layout and LOD).

	Milestones are built from the content, so a new line, egg or region adds its own track:
	  element  per element (a line's first element; hybrids and event lines are left out):
	           find ElementSteps forms, then every form of that element.
	  egg      per egg pool (eggs that share a pool share one track): every form of every line
	           that pool can hatch. Event eggs have tracks too, claimable whenever they are done.
	  region   per expedition region: every form of the lines met there (enemies, depths, bosses).
	  total    TotalSteps forms across the Codex, then Complete: every form of every line that is
	           not an event line (hybrids count). Event lines never gate the Complete milestone.

	Rewards are earned by collecting, never sold (pillar P5): modest gems (a whole Codex pays
	about as much as a few weeks of daily streaks), titles and the Codex Crown aura. Titles and
	the aura are Mastery cosmetics (Config/Mastery appends Codex.Items to its Rewards), so they
	are equipped in the Mastery screen, shown on nameplates, and a monster still wears at most
	one mastery-style aura.

	BadgeIds: Roblox badge ids per milestone id; 0 or missing = no badge.
]]

local Codex = {}

Codex.Source = "codex" -- Rewards source (reward card title "Rewards · Codex")

Codex.ElementSteps = { 3, 8 } -- then "every form"; a step at or past the element's total is dropped
Codex.TotalSteps = { 25, 50, 100, 150 } -- dropped when at or past the Complete count

Codex.Gems = {
	elementStep = { 5, 15 }, -- per ElementSteps entry
	elementAll = 30,
	egg = 20,
	region = 25,
	total = { 10, 20, 40, 60 }, -- per TotalSteps entry
	complete = 100,
}

-- Titles per element completed (Codex.Items) and for the overall steps.
Codex.ElementTitles = {
	ember = "title_codex_ember",
	tide = "title_codex_tide",
	sprout = "title_codex_sprout",
	spark = "title_codex_spark",
	gloom = "title_codex_gloom",
	stone = "title_codex_stone",
	light = "title_codex_light",
	void = "title_codex_void",
}
Codex.TotalTitles = { [50] = "title_codex_collector", [100] = "title_codex_scholar" }
Codex.CompleteItems = { "title_codex_master", "aura_codex_crown" }

-- Mastery cosmetics granted by milestones (same shape as Config/Mastery Rewards, no cost).
Codex.Items = {
	{ id = "title_codex_ember", kind = "title", name = "Ember Keeper", desc = "Find every Ember form in the Codex." },
	{ id = "title_codex_tide", kind = "title", name = "Tide Keeper", desc = "Find every Tide form in the Codex." },
	{ id = "title_codex_sprout", kind = "title", name = "Sprout Keeper", desc = "Find every Sprout form in the Codex." },
	{ id = "title_codex_spark", kind = "title", name = "Spark Keeper", desc = "Find every Spark form in the Codex." },
	{ id = "title_codex_gloom", kind = "title", name = "Gloom Keeper", desc = "Find every Gloom form in the Codex." },
	{ id = "title_codex_stone", kind = "title", name = "Stone Keeper", desc = "Find every Stone form in the Codex." },
	{ id = "title_codex_light", kind = "title", name = "Light Keeper", desc = "Find every Light form in the Codex." },
	{ id = "title_codex_void", kind = "title", name = "Void Keeper", desc = "Find every Void form in the Codex." },
	{ id = "title_codex_collector", kind = "title", name = "Keen Collector", desc = "Find 50 forms in the Codex." },
	{ id = "title_codex_scholar", kind = "title", name = "Codex Scholar", desc = "Find 100 forms in the Codex." },
	{ id = "title_codex_master", kind = "title", name = "Codex Master", desc = "Complete the whole Codex." },
	{
		id = "aura_codex_crown",
		kind = "aura",
		name = "Codex Crown Aura",
		desc = "Complete the whole Codex. Prism stars circle your mastered monsters.",
		vfx = "codexCrown",
	},
}

-- Roblox badge ids by milestone id (0 = none). Fill in after creating the badges on the site.
Codex.BadgeIds = {
	total_50 = 0,
	total_100 = 0,
	complete = 0,
}

-- The walk-in Codex Museum (client-built for the local player's own Codex; Controllers/CodexMuseum).
-- `origin` is the entrance's centre; the hall runs along -z from there. One wing per element,
-- `wingsPerRow` side by side along x, each `wingWidth` wide, pedestals `spacing` apart.
Codex.Museum = {
	origin = { 125, 0, -180 },
	wingWidth = 15,
	wingsPerRow = 5,
	spacing = 6.5,
	rowsPerWing = 3, -- pedestals side by side across a wing
	wallHeight = 10,
	pedestal = { 3.6, 2.4, 3.6 },
	maxModels = 12, -- live 3D monsters at once (phones)
	lowModels = 6, -- in low graphics
	modelRange = 55, -- studs from the camera within which a pedestal may build its 3D model
	signRange = 110, -- beyond this pedestals keep only their plate (no portrait sign)
	updateEvery = 0.5, -- seconds between LOD passes
}

-- Hall of Fame plaza: each player's best statue (highest rarity, newest first) on a pedestal,
-- for everyone on the server (global.HallOfFame.plaza). `max` statues at once; the rest wait.
Codex.Plaza = {
	origin = { -120, 0, -200 },
	max = 12,
	perRow = 6,
	spacing = 10,
	rowGap = 12,
	pedestal = { 5, 2.5, 5 },
	modelRange = 120, -- statues build their model only within this range of the camera
}

return Codex
