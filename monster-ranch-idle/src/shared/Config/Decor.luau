--[[
	Ranch decor. Placing decor in a pen gives its monsters a Mood aura (+`mood` every
	Economy.Mood.decayEvery seconds, which offsets decay). Max `PerPen` decor per pen.
	price: { coins = n } / { gems = n } / { friendship = n } / { token = n }
	shape: placeholder model in the pen: "block" (default), "ball", "disc" (flat, on the
	ground) or "tall" (a post with a round top). The art team replaces these later.
	set: a themed set shown together in the Store (e.g. "beach", update 1.1).
]]

local Decor = {}

Decor.PerPen = 3

Decor.List = {
	{ id = "hay_bale", name = "Hay Bale", price = { coins = 500 }, mood = 1, color = "#E3C565" },
	{ id = "water_trough", name = "Water Trough", price = { coins = 2500 }, mood = 1, color = "#4FB6F2" },
	{ id = "flower_bed", name = "Flower Bed", price = { coins = 12000 }, mood = 2, color = "#EF6FA8" },
	{ id = "scratch_post", name = "Scratch Post", price = { coins = 60000 }, mood = 2, color = "#A0703D" },
	{ id = "mud_puddle", name = "Mud Puddle", price = { friendship = 40 }, mood = 2, color = "#7A5A3A", shape = "disc" },
	{ id = "lantern", name = "Glow Lantern", price = { friendship = 90 }, mood = 3, color = "#FFD447", shape = "tall" },
	{ id = "fountain", name = "Tiny Fountain", price = { coins = 750000 }, mood = 3, color = "#7FD0F5", shape = "ball" },
	{ id = "rainbow_arch", name = "Rainbow Arch", price = { gems = 250 }, mood = 4, color = "#FF7AC8" },
	{ id = "crystal_cluster", name = "Crystal Cluster", price = { gems = 400 }, mood = 4, color = "#A9DEFF", shape = "ball" },
	{ id = "snow_globe", name = "Snow Globe", price = { token = 250 }, mood = 3, color = "#E6F6FF", shape = "ball", event = "frostfall" },
	{ id = "gift_pile", name = "Gift Pile", price = { token = 150 }, mood = 2, color = "#E5484D", event = "frostfall" },
	{ id = "golden_statue", name = "Golden Statue", price = { gems = 900 }, mood = 5, color = "#F4C43A" },
	-- Update 1.2 · Lunar Lanterns event decor
	{ id = "paper_lantern", name = "Paper Lantern", price = { token = 200 }, mood = 3, color = "#E5484D", shape = "tall", event = "lunarlanterns" },
	{ id = "moon_gate", name = "Moon Gate", price = { token = 350 }, mood = 4, color = "#C98B2E", event = "lunarlanterns" },
	-- Update 1.1 · Coral Depths beach set
	{ id = "sandcastle", name = "Sandcastle", price = { coins = 40000 }, mood = 2, color = "#EFD08A", set = "beach" },
	{
		id = "beach_umbrella",
		name = "Beach Umbrella",
		price = { coins = 180000 },
		mood = 3,
		color = "#FF6B6B",
		shape = "tall",
		set = "beach",
	},
	{ id = "shell_pile", name = "Shell Pile", price = { friendship = 120 }, mood = 3, color = "#F7C6D9", shape = "ball", set = "beach" },
	{ id = "tide_pool", name = "Tide Pool", price = { gems = 300 }, mood = 4, color = "#3FB6D9", shape = "disc", set = "beach" },
}

Decor.ById = {}
for _, d in Decor.List do
	Decor.ById[d.id] = d
end

-- Pen themes (cosmetic fences and ground).
Decor.PenThemes = {
	{ id = "wood", name = "Wooden Fence", price = nil, fence = "#9C6130", ground = "#A2D776" },
	{ id = "stone", name = "Stone Wall", price = { gems = 200 }, fence = "#8E8E8E", ground = "#B8C98A" },
	{ id = "candy", name = "Candy Fence", price = { gems = 350 }, fence = "#FF8FC8", ground = "#FFE3F1" },
	{ id = "snowglobe", name = "Snow Globe", price = { token = 600 }, fence = "#BFE9FF", ground = "#F2FAFF", event = "frostfall" },
	{ id = "boardwalk", name = "Beach Boardwalk", price = { gems = 300 }, fence = "#D9A066", ground = "#F4DFA6" },
	{ id = "lantern_garden", name = "Lantern Garden", price = { token = 600 }, fence = "#B3282D", ground = "#F6E7C8", event = "lunarlanterns" },
}
Decor.PenThemeById = {}
for _, t in Decor.PenThemes do
	Decor.PenThemeById[t.id] = t
end

return Decor
