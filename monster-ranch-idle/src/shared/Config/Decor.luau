--[[
	Ranch decor. Placing decor in a pen gives its monsters a Mood aura (+`mood` every
	Economy.Mood.decayEvery seconds, which offsets decay). Max `PerPen` decor per pen.
	price: { coins = n } / { gems = n } / { friendship = n } / { token = n }
]]

local Decor = {}

Decor.PerPen = 3

Decor.List = {
	{ id = "hay_bale", name = "Hay Bale", price = { coins = 500 }, mood = 1, color = "#E3C565" },
	{ id = "water_trough", name = "Water Trough", price = { coins = 2500 }, mood = 1, color = "#4FB6F2" },
	{ id = "flower_bed", name = "Flower Bed", price = { coins = 12000 }, mood = 2, color = "#EF6FA8" },
	{ id = "scratch_post", name = "Scratch Post", price = { coins = 60000 }, mood = 2, color = "#A0703D" },
	{ id = "mud_puddle", name = "Mud Puddle", price = { friendship = 40 }, mood = 2, color = "#7A5A3A" },
	{ id = "lantern", name = "Glow Lantern", price = { friendship = 90 }, mood = 3, color = "#FFD447" },
	{ id = "fountain", name = "Tiny Fountain", price = { coins = 750000 }, mood = 3, color = "#7FD0F5" },
	{ id = "rainbow_arch", name = "Rainbow Arch", price = { gems = 250 }, mood = 4, color = "#FF7AC8" },
	{ id = "crystal_cluster", name = "Crystal Cluster", price = { gems = 400 }, mood = 4, color = "#A9DEFF" },
	{ id = "snow_globe", name = "Snow Globe", price = { token = 250 }, mood = 3, color = "#E6F6FF", event = "frostfall" },
	{ id = "gift_pile", name = "Gift Pile", price = { token = 150 }, mood = 2, color = "#E5484D", event = "frostfall" },
	{ id = "golden_statue", name = "Golden Statue", price = { gems = 900 }, mood = 5, color = "#F4C43A" },
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
}
Decor.PenThemeById = {}
for _, t in Decor.PenThemes do
	Decor.PenThemeById[t.id] = t
end

return Decor
