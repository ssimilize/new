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
	{
		id = "paper_lantern",
		name = "Paper Lantern",
		price = { token = 200 },
		mood = 3,
		color = "#E5484D",
		shape = "tall",
		event = "lunarlanterns",
	},
	{ id = "moon_gate", name = "Moon Gate", price = { token = 350 }, mood = 4, color = "#C98B2E", event = "lunarlanterns" },
	-- Update 2.1 · Harvest Moon event decor
	{
		id = "jack_o_lantern",
		name = "Jack-o'-Lantern",
		price = { token = 150 },
		mood = 3,
		color = "#F08A4B",
		shape = "ball",
		event = "harvestmoon",
	},
	{
		id = "haunted_tree",
		name = "Haunted Tree",
		price = { token = 350 },
		mood = 4,
		color = "#3A2D55",
		shape = "tall",
		event = "harvestmoon",
	},
	-- Update 2.0 · Summer Splash event decor
	{
		id = "beach_ball",
		name = "Beach Ball",
		price = { token = 150 },
		mood = 3,
		color = "#FF6B6B",
		shape = "ball",
		event = "summersplash",
	},
	{
		id = "tiki_torch",
		name = "Tiki Torch",
		price = { token = 250 },
		mood = 3,
		color = "#D9A066",
		shape = "tall",
		event = "summersplash",
	},
	-- Update 1.4 · Spring Bloom event decor
	{
		id = "tulip_patch",
		name = "Tulip Patch",
		price = { token = 150 },
		mood = 3,
		color = "#FF6FA5",
		shape = "disc",
		event = "springbloom",
	},
	{ id = "bloom_arch", name = "Bloom Arch", price = { token = 350 }, mood = 4, color = "#FFB3D1", shape = "tall", event = "springbloom" },
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

--[[
	Glow-up Z · Build your ranch: decor is placed freely on the plot (Logic/DecorLayout, Systems/Decor).
	Extra fields on every piece (legacy pieces get theirs from LEGACY_ART below):
	  model   how it is built from parts (Config/DecorArt), color2 its second colour, mat a material
	  size    { w, d } footprint in studs before rotation; flat = true lies on the ground (paths):
	          flat pieces only collide with flat pieces, so a bench may stand on a path
	  kind    tray tab: fence · path · light · water · plant · seat · arch · statue · toy · fun
	  spot    "toy": pen monsters go and play with it (anchor part attribute PenSpot, like Config.Pens)
	  light   true: lit at night (Controllers/Decor's light pool, at the piece's `glow` part)
	  starter n: the free starter set, n granted once to every ranch (also sold for coins)
	  mesh    rbxassetid of a generated mesh ("" = built from parts); texture, meshSize with it
	New pieces are cosmetic (mood 0). Legacy pieces keep their mood aura when they stand in a pen.
]]
local LEGACY_ART = {
	hay_bale = { model = "bale", size = { 3, 2 }, kind = "fun", color2 = "#B08A3E" },
	water_trough = { model = "trough", size = { 4, 2 }, kind = "water", color2 = "#8A5A2B" },
	flower_bed = { model = "flowerbed", size = { 4, 3 }, kind = "plant", color2 = "#8A5A2B" },
	scratch_post = { model = "post", size = { 2, 2 }, kind = "toy", spot = "toy", color2 = "#D8C8A8" },
	mud_puddle = { model = "puddle", size = { 5, 4 }, kind = "water", flat = true },
	lantern = { model = "lamppost", size = { 2, 2 }, kind = "light", light = true, color = "#4A4A4A", color2 = "#FFD447" },
	fountain = { model = "fountain", size = { 5, 5 }, kind = "water", color = "#EDE7DD", color2 = "#7FD0F5" },
	rainbow_arch = { model = "arch", size = { 6, 2 }, kind = "arch", glow = true, light = true, color2 = "#FFD447" },
	crystal_cluster = { model = "crystal", size = { 3, 3 }, kind = "statue", light = true, color2 = "#E6F6FF" },
	snow_globe = { model = "globe", size = { 3, 3 }, kind = "fun", color2 = "#6B4424" },
	gift_pile = { model = "gifts", size = { 3, 3 }, kind = "fun", color2 = "#43B649" },
	golden_statue = { model = "statue", size = { 3, 3 }, kind = "statue", mat = "Foil", color2 = "#EDE7DD" },
	paper_lantern = { model = "paperlantern", size = { 3, 2 }, kind = "light", light = true, color2 = "#FFD447" },
	moon_gate = { model = "arch", size = { 6, 2 }, kind = "arch", mat = "Wood", color2 = "#E5484D" },
	jack_o_lantern = { model = "jack", size = { 3, 3 }, kind = "light", light = true, color2 = "#FFB347" },
	haunted_tree = { model = "tree", size = { 5, 5 }, kind = "plant", color2 = "#2A2230" },
	beach_ball = { model = "ball", size = { 2, 2 }, kind = "toy", spot = "toy", color2 = "#FFFFFF" },
	tiki_torch = { model = "torch", size = { 2, 2 }, kind = "light", light = true, color2 = "#FF9A3C" },
	tulip_patch = { model = "flowerbed", size = { 4, 3 }, kind = "plant", color2 = "#6B8E3A" },
	bloom_arch = { model = "arch", size = { 6, 2 }, kind = "arch", color2 = "#FF6FA5" },
	sandcastle = { model = "castle", size = { 3, 3 }, kind = "fun", color2 = "#E3C27A" },
	beach_umbrella = { model = "umbrella", size = { 4, 4 }, kind = "fun", color2 = "#FFFFFF" },
	shell_pile = { model = "shells", size = { 2, 2 }, kind = "fun", color2 = "#FFE3C2" },
	tide_pool = { model = "pond", size = { 6, 5 }, kind = "water", color2 = "#8C8A84" },
}
for _, d in Decor.List do
	for k, v in LEGACY_ART[d.id] or {} do
		d[k] = v
	end
end

-- id, name, kind, model, { w, d }, price, color, color2, extra fields
local function add(id: string, name: string, kind: string, model: string, size, price, color: string, color2: string?, extra)
	local def = { id = id, name = name, kind = kind, model = model, size = size, price = price, color = color, color2 = color2, mood = 0 }
	for k, v in extra or {} do
		def[k] = v
	end
	table.insert(Decor.List, def)
end
local TOY = { spot = "toy" }
local LIGHT = { light = true }
local FLAT = { flat = true }
local function ev(eventId: string, more)
	local t = { event = eventId }
	for k, v in more or {} do
		t[k] = v
	end
	return t
end

-- Starter set: granted once to every ranch (`starter` copies), also sold for coins.
add("picket_fence", "Picket Fence", "fence", "picket", { 4, 1 }, { coins = 200 }, "#F4EBD9", nil, { set = "starter", starter = 6 })
add(
	"stone_path",
	"Stone Path",
	"path",
	"path",
	{ 4, 4 },
	{ coins = 150 },
	"#B9B3A8",
	"#9A958C",
	{ set = "starter", starter = 6, flat = true }
)
add("wood_lamp", "Wooden Lamp Post", "light", "lamppost", { 2, 2 }, { coins = 400 }, "#6B4424", "#FFD98A", {
	set = "starter",
	starter = 2,
	light = true,
	mat = "Wood",
})
add("park_bench", "Park Bench", "seat", "bench", { 4, 2 }, { coins = 500 }, "#A0703D", "#3A3A3A", { set = "starter", starter = 1 })
add(
	"play_ball",
	"Play Ball",
	"toy",
	"ball",
	{ 2, 2 },
	{ coins = 300 },
	"#4FB6F2",
	"#FFFFFF",
	{ set = "starter", starter = 1, spot = "toy" }
)
add("daisy_bed", "Daisy Bed", "plant", "flowerbed", { 4, 3 }, { coins = 250 }, "#FFFFFF", "#8A5A2B", { set = "starter", starter = 1 })
add("sapling", "Sapling", "plant", "bush", { 3, 3 }, { coins = 300 }, "#7CC65A", "#FFD447", { set = "starter", starter = 1 })
add("wood_crate", "Wooden Crate", "fun", "crate", { 2, 2 }, { coins = 150 }, "#C08A4E", "#7A4A22", { set = "starter", starter = 1 })

-- Fences and paths
add("rail_fence", "Rail Fence", "fence", "fence", { 4, 1 }, { coins = 800 }, "#9C6130")
add("stone_wall", "Stone Wall", "fence", "wall", { 4, 1 }, { coins = 3000 }, "#9A958C", "#6E6A64")
add("hedge", "Hedge Row", "fence", "hedge", { 4, 2 }, { coins = 2000 }, "#4E9A3E", "#FF8FC8")
add("iron_fence", "Iron Fence", "fence", "fence", { 4, 1 }, { coins = 20000 }, "#3A3A44", nil, { mat = "Metal" })
add("brick_path", "Brick Path", "path", "path", { 4, 4 }, { coins = 1200 }, "#B5553C", "#C9704F", { flat = true, mat = "Brick" })
add("gravel_path", "Gravel Path", "path", "path", { 4, 4 }, { coins = 600 }, "#C9C1B2", "#A8A091", { flat = true, mat = "Pebble" })
add("stepping_stones", "Stepping Stones", "path", "stones", { 4, 4 }, { coins = 900 }, "#A7A29A", "#8E8A83", FLAT)
add("plank_walk", "Plank Walk", "path", "path", { 4, 4 }, { coins = 1500 }, "#B08A5A", "#8A6A42", { flat = true, mat = "WoodPlanks" })

-- Lights
add("street_lamp", "Street Lamp", "light", "lamppost", { 2, 2 }, { coins = 8000 }, "#2F3A40", "#FFE7A3", LIGHT)
add("garden_lantern", "Garden Lantern", "light", "lantern", { 2, 2 }, { coins = 4000 }, "#A7A29A", "#FFD447", LIGHT)
add("torch_post", "Torch Post", "light", "torch", { 2, 2 }, { friendship = 30 }, "#8A5A2B", "#FF9A3C", LIGHT)
add("string_lights", "String Lights", "light", "stringlights", { 6, 1 }, { coins = 15000 }, "#FFD447", "#FF7AC8", LIGHT)
add("crystal_lamp", "Crystal Lamp", "light", "lamppost", { 2, 2 }, { gems = 120 }, "#BFE9FF", "#8FE3FF", { light = true, mat = "Glass" })

-- Water
add("lily_pond", "Lily Pond", "water", "pond", { 8, 6 }, { coins = 25000 }, "#4FB6F2", "#8C8A84")
add("bird_bath", "Bird Bath", "water", "birdbath", { 2, 2 }, { coins = 6000 }, "#EDE7DD", "#7FD0F5")
add("stone_well", "Stone Well", "water", "well", { 4, 4 }, { coins = 30000 }, "#9A958C", "#A0703D")
add("garden_fountain", "Garden Fountain", "water", "fountain", { 6, 6 }, { gems = 200 }, "#F2EEE6", "#7FD0F5")

-- Plants
add("oak_tree", "Oak Tree", "plant", "tree", { 5, 5 }, { coins = 10000 }, "#4E9A3E", "#7A4A22")
add("pine_tree", "Pine Tree", "plant", "pine", { 4, 4 }, { coins = 8000 }, "#2F7A4A", "#6B4424")
add("cherry_tree", "Cherry Tree", "plant", "tree", { 5, 5 }, { gems = 150 }, "#FFB3D1", "#6B4424")
add("palm_tree", "Palm Tree", "plant", "palm", { 5, 5 }, { coins = 20000 }, "#3FAF5A", "#A0703D")
add("round_bush", "Round Bush", "plant", "bush", { 3, 3 }, { coins = 1000 }, "#4E9A3E", "#FFFFFF")
add("rose_bed", "Rose Bed", "plant", "flowerbed", { 4, 3 }, { coins = 3000 }, "#E5484D", "#6B4424")
add("sunflower_row", "Sunflower Row", "plant", "sunflowers", { 4, 2 }, { coins = 5000 }, "#FFD447", "#4E9A3E")
add("mushroom_ring", "Mushroom Ring", "plant", "mushrooms", { 4, 4 }, { friendship = 40 }, "#E5484D", "#F4EBD9")
add("potted_plant", "Potted Plant", "plant", "pot", { 2, 2 }, { coins = 1200 }, "#C9704F", "#4E9A3E")

-- Seats and farm bits
add("stone_bench", "Stone Bench", "seat", "bench", { 4, 2 }, { coins = 4000 }, "#B9B3A8", "#8E8A83", { mat = "Slate" })
add("picnic_table", "Picnic Table", "seat", "picnic", { 5, 4 }, { coins = 7000 }, "#B07A45", "#7A4A22")
add("hay_cart", "Hay Cart", "fun", "cart", { 5, 3 }, { coins = 12000 }, "#A0703D", "#E3C565")
add("mailbox", "Mailbox", "fun", "mailbox", { 2, 2 }, { coins = 2000 }, "#4FB6F2", "#E5484D")
add("signpost", "Signpost", "fun", "sign", { 3, 1 }, { coins = 1500 }, "#C08A4E", "#A0703D")
add("barrel", "Barrel", "fun", "barrel", { 2, 2 }, { coins = 800 }, "#8A5A2B", "#4A4A4A")

-- Arches and statues
add("rose_arch", "Rose Arch", "arch", "arch", { 6, 2 }, { coins = 18000 }, "#F4EBD9", "#E5484D")
add("stone_arch", "Stone Arch", "arch", "arch", { 6, 2 }, { gems = 180 }, "#A7A29A", "#6E6A64", { mat = "Cobblestone" })
add("monster_statue", "Monster Statue", "statue", "statue", { 3, 3 }, { gems = 300 }, "#9FD6FF", "#EDE7DD")
add("star_obelisk", "Star Obelisk", "statue", "obelisk", { 2, 2 }, { gems = 250 }, "#6B5BD6", "#FFD447", LIGHT)
add("little_windmill", "Little Windmill", "statue", "windmill", { 4, 4 }, { coins = 60000 }, "#E8D8B8", "#B5553C")

-- Toys: pen monsters go and play with these (PenSpot = "toy")
add("swing_set", "Swing Set", "toy", "swing", { 6, 2 }, { coins = 9000 }, "#E5484D", "#8A5A2B", TOY)
add("climbing_tower", "Climbing Tower", "toy", "tower", { 4, 4 }, { coins = 14000 }, "#C08A4E", "#7A4A22", TOY)
add("seesaw", "Seesaw", "toy", "seesaw", { 6, 1 }, { coins = 7000 }, "#FFD447", "#4FB6F2", TOY)
add("slide", "Slide", "toy", "slide", { 2, 6 }, { friendship = 80 }, "#43B649", "#A0703D", TOY)
add("tire_swing", "Tire Swing", "toy", "tireswing", { 2, 4 }, { coins = 5000 }, "#2E2E2E", "#8A5A2B", TOY)
add("chew_log", "Chew Log", "toy", "log", { 4, 2 }, { coins = 1500 }, "#8A5A2B", "#D8B07A", TOY)
add("bouncy_mushroom", "Bouncy Mushroom", "toy", "bouncy", { 3, 3 }, { gems = 90 }, "#B56BFF", "#FFFFFF", TOY)
add("sandbox", "Sandbox", "toy", "sandbox", { 4, 4 }, { coins = 4000 }, "#EFD08A", "#A0703D", TOY)
add("yarn_ball", "Yarn Ball", "toy", "yarn", { 2, 2 }, { friendship = 20 }, "#FF7AC8", "#FF7AC8", TOY)

-- Event sets: sold for the event's token while it runs (and on every rerun)
add("snowman", "Snowman", "statue", "snowman", { 3, 3 }, { token = 200 }, "#F7FBFF", "#2E2E2E", ev("frostfall"))
add("ice_lantern", "Ice Lantern", "light", "lantern", { 2, 2 }, { token = 150 }, "#CFEFFF", "#8FE3FF", ev("frostfall", LIGHT))
add(
	"candy_cane_fence",
	"Candy Cane Fence",
	"fence",
	"fence",
	{ 4, 1 },
	{ token = 60 },
	"#E5484D",
	nil,
	ev("frostfall", { mat = "SmoothPlastic" })
)
add("frosty_pine", "Frosty Pine", "plant", "pine", { 4, 4 }, { token = 180 }, "#DDF3FF", "#6B4424", ev("frostfall"))
add("snow_sled", "Snow Sled", "toy", "sled", { 3, 2 }, { token = 120 }, "#E5484D", "#9A9AA6", ev("frostfall", TOY))

add("petal_path", "Petal Path", "path", "path", { 4, 4 }, { token = 60 }, "#FFD6E6", "#FFB3D1", ev("springbloom", FLAT))
add("egg_basket", "Egg Basket", "fun", "basket", { 2, 2 }, { token = 120 }, "#C9A26B", "#FF9EC7", ev("springbloom"))
add("bunny_topiary", "Bunny Topiary", "statue", "topiary", { 3, 3 }, { token = 250 }, "#5FAF4B", "#C9704F", ev("springbloom"))
add("blossom_lamp", "Blossom Lamp", "light", "lamppost", { 2, 2 }, { token = 150 }, "#F7A8C8", "#FFF1F7", ev("springbloom", LIGHT))
add("flower_swing", "Flower Swing", "toy", "swing", { 6, 2 }, { token = 220 }, "#FF9EC7", "#6B8E3A", ev("springbloom", TOY))

add(
	"lantern_string",
	"Lantern String",
	"light",
	"stringlights",
	{ 6, 1 },
	{ token = 150 },
	"#E5484D",
	"#FFB347",
	ev("lunarlanterns", LIGHT)
)
add("moon_bridge", "Moon Bridge", "arch", "bridge", { 3, 6 }, { token = 300 }, "#B3282D", "#C98B2E", ev("lunarlanterns"))
add("stone_lion", "Stone Lion", "statue", "lion", { 2, 3 }, { token = 220 }, "#B9B3A8", "#8E8A83", ev("lunarlanterns"))
add("bamboo_fence", "Bamboo Fence", "fence", "fence", { 4, 1 }, { token = 60 }, "#9DBF5A", nil, ev("lunarlanterns", { mat = "Wood" }))
add("dragon_kite", "Dragon Kite", "toy", "kite", { 2, 2 }, { token = 150 }, "#E5484D", "#FFD447", ev("lunarlanterns", TOY))

add("splash_pool", "Splash Pool", "toy", "pond", { 6, 6 }, { token = 250 }, "#3FD0F0", "#FF6B6B", ev("summersplash", TOY))
add("lifeguard_chair", "Lifeguard Chair", "seat", "chair", { 2, 2 }, { token = 180 }, "#F4EBD9", "#E5484D", ev("summersplash"))
add("surfboard_rack", "Surfboard Rack", "fun", "rack", { 4, 2 }, { token = 150 }, "#2EC4B6", "#FFB347", ev("summersplash"))
add(
	"sand_path",
	"Sand Path",
	"path",
	"path",
	{ 4, 4 },
	{ token = 50 },
	"#F4DFA6",
	"#E8CC8A",
	ev("summersplash", { flat = true, mat = "Sand" })
)
add("swim_ring", "Swim Ring", "toy", "ring", { 2, 2 }, { token = 80 }, "#FF6B6B", "#FFFFFF", ev("summersplash", TOY))

add("pumpkin_patch", "Pumpkin Patch", "plant", "pumpkins", { 4, 4 }, { token = 150 }, "#F08A4B", "#3E7A2E", ev("harvestmoon"))
add("scarecrow", "Scarecrow", "statue", "scarecrow", { 3, 1 }, { token = 220 }, "#6B8E3A", "#D8B07A", ev("harvestmoon"))
add("haystack", "Haystack", "fun", "haystack", { 3, 3 }, { token = 80 }, "#E3C565", "#D8B64A", ev("harvestmoon"))
add("candle_lantern", "Candle Lantern", "light", "lantern", { 2, 2 }, { token = 150 }, "#3A2D55", "#FFB347", ev("harvestmoon", LIGHT))
add("spooky_fence", "Spooky Fence", "fence", "fence", { 4, 1 }, { token = 60 }, "#4A3A5A", nil, ev("harvestmoon", { mat = "Wood" }))
add("apple_bob", "Apple Bobbing Tub", "toy", "tub", { 3, 3 }, { token = 120 }, "#8A5A2B", "#E5484D", ev("harvestmoon", TOY))

for _, d in Decor.List do
	d.mesh = d.mesh or ""
	d.kind = d.kind or "fun"
	d.size = d.size or { 3, 3 }
end

-- Placement rules (Logic/DecorLayout). Positions are plot-local grid units (× grid studs) from the
-- plot centre; rot is 0..7 in 45° steps. Keep-outs are plot-local stud rects { cx, cz, hx, hz }.
Decor.Layout = {
	grid = 2,
	capBase = 20, -- pieces at Ranch Level 1
	capStep = 10, -- + capStep every capEvery levels
	capEvery = 10,
	capMax = 80,
	maxParts = 8, -- parts one piece may use
	undo = 12, -- undo steps kept in placement mode
	penInset = 1, -- inside a pen: this far from the rails
	penOutset = 1, -- outside a pen: this far from the rails
	propClear = 3.5, -- half size of the square kept clear round each pen prop spot (Config.Pens)
	edge = 1, -- studs kept clear inside the plot's edge
	keepOut = {
		{ 0, -3, 75, 7 }, -- the middle aisle from the gate to the incubator pad
		{ 67, 0, 8, 11 }, -- the plot gate
		{ -65, -3, 9, 9 }, -- the incubator pad
		{ 58, 43, 9, 9 }, -- the barn and its door
		{ -35.5, 44, 27.5, 3.5 }, -- the Hall of Fame statue row
		{ 42, 44, 6, 5 }, -- the Feed Garden
	},
	-- Legacy pen slots (pen-local fractions of the half extents) the migration puts old decor on.
	legacySpots = { { -0.62, -0.55 }, { 0.62, -0.55 }, { 0, -0.62 } },
	lights = { max = 10, maxLow = 4, radius = 120, range = 14, brightness = 1.2 },
	farDistance = 170, -- other plots farther than this drop `small` parts
	hideDistance = 420, -- and beyond this draw no decor at all
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
	{
		id = "lantern_garden",
		name = "Lantern Garden",
		price = { token = 600 },
		fence = "#B3282D",
		ground = "#F6E7C8",
		event = "lunarlanterns",
	},
	{
		id = "blossom_glade",
		name = "Blossom Glade",
		price = { token = 600 },
		fence = "#F7A8C8",
		ground = "#C9EDA8",
		event = "springbloom",
	},
	{
		id = "tropical_lagoon",
		name = "Tropical Lagoon",
		price = { token = 600 },
		fence = "#2EC4B6",
		ground = "#F4DFA6",
		event = "summersplash",
	},
	{
		id = "haunted_hollow",
		name = "Haunted Hollow",
		price = { token = 600 },
		fence = "#3A2D55",
		ground = "#6B5B4B",
		event = "harvestmoon",
	},
	-- Update 1.4 · Rebirth biomes: never sold; each Rebirth Star grants one (Config.Rebirth.Biomes).
	{ id = "starfield", name = "Starfield Meadow", rebirth = 1, fence = "#6B5BD6", ground = "#2E3A78" },
	{ id = "crystal_tundra", name = "Crystal Tundra", rebirth = 2, fence = "#9FE3FF", ground = "#E4F4FF" },
	{ id = "aurora_isle", name = "Aurora Isle", rebirth = 3, fence = "#3DDC97", ground = "#1F4E5F" },
	{ id = "sunset_mesa", name = "Sunset Mesa", rebirth = 4, fence = "#D9653B", ground = "#F2B880" },
	{ id = "nebula", name = "Nebula Drift", rebirth = 5, fence = "#FF7AC8", ground = "#3A2D55" },
}
Decor.PenThemeById = {}
for _, t in Decor.PenThemes do
	Decor.PenThemeById[t.id] = t
end

return Decor
