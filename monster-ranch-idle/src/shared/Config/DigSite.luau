--[[
	Dig Site (update 3.11 · Seasons & secrets). A roped-off sand pit in the north strip of every plot
	(Config.World.DigSite) with a "Dig" prompt on its tool rack that opens the Dig Site screen. From
	Ranch Level 16 (Unlocks "dig_site").

	A dig: a Grid × Grid field of covered tiles and Taps taps. The server makes the dig (a one-shot
	dig id; the layout is seeded by (userId, dig number, the player's private secret) and never sent
	to the client) and resolves each tap: what was under the tile, or a hint = the distance (steps
	along rows and columns) to the nearest find still buried. A dig ends when its taps run out or
	every find is dug up. Opening the screen again resumes the open dig (no reroll).

	Digs: FreeDigs a UTC day, then one Shovel each (shovels come from Expedition Bounties, the
	Travelling Merchant and Rewards kind "shovel").

	Finds (Logic/DigSite.Layout): 1 find, or 2 with TwoFindChance; each is a Kinds[] weighted roll:
	  piece  one piece (Pieces) of one fossil (Fossils); a piece you already have turns into
	         DuplicateAmber amber. All four pieces complete the fossil: its skeleton display decor
	         (Fossil.decor, Config/Decor) is granted once, and it counts for the Codex Fossils tab.
	  amber  Amber = { min, max } amber (currency "amber")
	  relic  one Relics[] decor (Part-built, never sold)
	  egg    one Egg (the Amber Egg, Config/Eggs; hatches Stone / Sprout / Gloom lines)
]]

local DigSite = {}

DigSite.Unlock = "dig_site"
DigSite.Source = "digsite" -- Rewards source (reward card "Rewards · Dig Site")

DigSite.FreeDigs = 6 -- a UTC day
DigSite.MaxShovels = 999
DigSite.Grid = 5 -- tiles per side
DigSite.Taps = 5 -- taps per dig
DigSite.TwoFindChance = 0.4
DigSite.DuplicateAmber = 5
DigSite.Amber = { 3, 8 }
DigSite.Egg = "amber"

DigSite.Kinds = {
	{ id = "piece", weight = 68 },
	{ id = "amber", weight = 24 },
	{ id = "relic", weight = 5 },
	{ id = "egg", weight = 3 },
}

DigSite.Pieces = {
	{ id = "skull", name = "Skull" },
	{ id = "ribs", name = "Ribs" },
	{ id = "legs", name = "Legs" },
	{ id = "tail", name = "Tail" },
}

-- decor: the skeleton display a completed fossil grants (Config/Decor, model "fossil_skeleton").
DigSite.Fossils = {
	{ id = "raptor", name = "Raptor", color = "#EFE6D2", decor = "fossil_raptor" },
	{ id = "trihorn", name = "Trihorn", color = "#E3D5B8", decor = "fossil_trihorn" },
	{ id = "longneck", name = "Longneck", color = "#F2EBDD", decor = "fossil_longneck" },
	{ id = "sabre_cat", name = "Sabre Cat", color = "#E8DCC4", decor = "fossil_sabre_cat" },
	{ id = "woolly_tusk", name = "Woolly Tusk", color = "#DCCDB0", decor = "fossil_woolly_tusk" },
	{ id = "sky_wing", name = "Sky Wing", color = "#F4EEE2", decor = "fossil_sky_wing" },
}

DigSite.Relics = {
	{ id = "ancient_urn", weight = 60 },
	{ id = "stone_tablet", weight = 40 },
}

DigSite.Tiles = DigSite.Grid * DigSite.Grid

DigSite.KindById = {}
for i, k in DigSite.Kinds do
	k.order = i
	DigSite.KindById[k.id] = k
end
DigSite.PieceById = {}
for i, p in DigSite.Pieces do
	p.order = i
	DigSite.PieceById[p.id] = p
end
DigSite.ById = {}
DigSite.Ids = {}
for i, f in DigSite.Fossils do
	assert(DigSite.ById[f.id] == nil, "[Config.DigSite] duplicate fossil " .. f.id)
	f.order = i
	DigSite.ById[f.id] = f
	table.insert(DigSite.Ids, f.id)
end

return DigSite
