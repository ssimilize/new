--[[
	Museum Exhibits (update 3.12 · Honey & stars): a Curator wing beside the walk-in Codex Museum
	(Config.World.CuratorWing, built on the client by Controllers/CuratorWing) where the player puts
	what they have collected on display. From Ranch Level 18 (Unlocks "exhibits"). A Curator desk
	in the wing ("Exhibits" prompt) and a header button on the Codex screen open the Exhibits screen.

	Sets (their items are read from the other configs by Logic/Exhibits.Items, so new content adds
	itself; a set whose source config is missing is hidden):
	  fossils   Fossil Hall   Config.DigSite.Fossils           filled by itself when a fossil is complete
	  aquarium  Aquarium      Config.Fishing.Fish               donate one caught fish (Fishing:SpendFish)
	  relics    Relic Room    DigSite.Relics + Fishing.Decor    donate one copy from decor storage
	                          + Merchant.Decor                  (never a placed one)
	  honey     Honey Shelf   Config.Apiary.Kinds + RoyalJelly  donate one jar (Apiary:SpendHoney)
	  stars     Star Atlas    Config.Observatory.Charts         filled by itself when a chart is charted
	  insects   Insect Hall   Config.Bugs.List                  3.13: filled by itself when a bug is first caught
	                                                            (the bug is not used up)

	Rewards: each set pays at a third, two thirds and all of its items (ceil counts), claimed on the
	screen (Exhibits.Claim, one step at a time): gems and stardust = set size × PerItem × the step's
	Share (rounded up), and the set's title (Items, a Mastery cosmetic) on completing it.

	Tourists: each filled exhibit adds appeal, floor(AppealMax × filled ÷ total) over the sets shown.
]]

local Exhibits = {}

Exhibits.Unlock = "exhibits"
Exhibits.Source = "exhibits" -- Rewards source (reward card "Rewards · Exhibits")
Exhibits.AppealMax = 10

Exhibits.Steps = { 1 / 3, 2 / 3, 1 } -- share of a set's items (ceil) for each reward step
Exhibits.Share = { 0.25, 0.25, 0.5 } -- share of the set's gems and stardust paid at each step
Exhibits.GemsPerItem = 6
Exhibits.StardustPerItem = 30

-- fill: "auto" (the system fills it) or "donate" (a button per item).
-- config: the Config module the set's items come from; the set is hidden while it is missing.
Exhibits.Sets = {
	{
		id = "fossils",
		name = "Fossil Hall",
		fill = "auto",
		config = "DigSite",
		hint = "Complete it at the Dig Site",
		color = "#E3D5B8",
		titleItem = "title_exhibit_fossils",
	},
	{ id = "aquarium", name = "Aquarium", fill = "donate", config = "Fishing", color = "#4F8FD6", titleItem = "title_exhibit_aquarium" },
	{ id = "relics", name = "Relic Room", fill = "donate", config = "Decor", color = "#B8643A", titleItem = "title_exhibit_relics" },
	{ id = "honey", name = "Honey Shelf", fill = "donate", config = "Apiary", color = "#F2B233", titleItem = "title_exhibit_honey" },
	{
		id = "stars",
		name = "Star Atlas",
		fill = "auto",
		config = "Observatory",
		hint = "Chart it at the Observatory",
		color = "#6B5BD6",
		titleItem = "title_exhibit_stars",
	},
	{
		id = "insects",
		name = "Insect Hall",
		fill = "auto",
		config = "Bugs",
		hint = "Catch it in the Bug Catching Meadow",
		color = "#7FB24A",
		titleItem = "title_exhibit_insects",
	},
}

-- Mastery cosmetics granted on completing a set (Config/Mastery appends them to its Rewards).
Exhibits.Items = {
	{ id = "title_exhibit_fossils", kind = "title", name = "Bone Curator", desc = "Complete the Fossil Hall exhibit." },
	{ id = "title_exhibit_aquarium", kind = "title", name = "Aquarist", desc = "Complete the Aquarium exhibit." },
	{ id = "title_exhibit_relics", kind = "title", name = "Relic Keeper", desc = "Complete the Relic Room exhibit." },
	{ id = "title_exhibit_honey", kind = "title", name = "Honey Curator", desc = "Complete the Honey Shelf exhibit." },
	{ id = "title_exhibit_stars", kind = "title", name = "Star Curator", desc = "Complete the Star Atlas exhibit." },
	{ id = "title_exhibit_insects", kind = "title", name = "Bug Curator", desc = "Complete the Insect Hall exhibit." },
}

-- The wing's pedestals (Logic/Exhibits.Layout): rows of `perRow` along x, `spacing` apart, a row
-- per `rowGap` going south from the desk, `setGap` more between sets. LOD like the Codex Museum:
-- every pedestal keeps its plate, the nearest `maxModels` filled ones build their Part display.
Exhibits.Wing = {
	perRow = 10, -- 3.13: 10 (was 9) so the Insect Hall fits the wing
	spacing = 3.8,
	rowGap = 4.4,
	setGap = 2.4,
	front = 10, -- studs from the north edge to the first row (the desk stands there)
	pedestal = { 2.4, 1.6, 2.4 },
	wallHeight = 9,
	maxModels = 16,
	lowModels = 8,
	modelRange = 40,
	signRange = 80,
	updateEvery = 0.5,
	promptDistance = 12,
}

Exhibits.ById = {}
for i, set in Exhibits.Sets do
	assert(Exhibits.ById[set.id] == nil, "[Config.Exhibits] duplicate set " .. set.id)
	set.order = i
	Exhibits.ById[set.id] = set
end
Exhibits.Ids = {}
for _, set in Exhibits.Sets do
	table.insert(Exhibits.Ids, set.id)
end

return Exhibits
