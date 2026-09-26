--[[
	Pens that grow (glow-up R): how a pen and the Feed Garden look, as data. Drawn by the Pens
	controller through Visuals/PenDress; the choices are the pure rules in Logic/Pens.

	  Fences      fence tier by the pen's jar tier (Ranch.Upgrade "jar"): wood, timber, stone, crystal.
	              `rail` / `post` restyle the server-built fence parts (material, colour mixed from the
	              theme's fence colour toward `color` by `mix`, `alpha`); `cap` is a piece set on
	              every corner post. `themed` tiers let the theme's own rail material win.
	  Upgrades    props by the pen's capacity (Ranch.Upgrade "capacity"): one more at each step.
	  Themes      [penThemeId] = { floor, rail?, props = { propId } }: the floor material, the rail
	              material on themed tiers and one or two signature props (Config.Decor.PenThemes).
	  Habitats    [elementId] = propId: the dominant element's habitat (Logic/Pens.Dominant).
	  Props       [propId] = { pieces, spot?, mesh, texture, meshSize }
	  Garden      the Feed Garden's frame, beds, crop stages and the harvest glow.

	Coordinates are studs in pen space: x across the pen (PenSize[1]), z along it (PenSize[2]),
	origin at the floor's top centre; a piece's `at` is its centre relative to the prop's spot.
	Piece: { shape = "block"|"ball"|"cyl"|"wedge", size = { x, y, z }, at = { x, y, z },
	  rot = { x, y, z }? (degrees), mat = Enum.Material name, color = hex | "fence" | "ground" |
	  "element" | "accent" | "flavor", alpha?, small? }. A "cyl" stands upright: size x and z are
	  its diameter, y its height. `small` pieces are dropped in low graphics and at distance.
	  The first piece of a prop is its anchor: it carries PropId, PenSpot and Habitat attributes.
	Meshes: a prop with a non-empty `mesh` (rbxassetid) is drawn as one part holding a SpecialMesh
	  (`texture`, sized `meshSize`) instead of its pieces, with the same attributes.
]]

local Pens = {}

-- Parts one pen may add, by detail level ("full" own/near, "lite" low graphics, "far").
Pens.Budget = { full = 40, lite = 30, far = 16, garden = 56, gardenFar = 26 }
Pens.FarDistance = 170 -- other plots farther than this from the camera draw "far"
Pens.FarHysteresis = 20
Pens.CheckSeconds = 2 -- crop stages and distance are re-checked this often (no per-frame work)

-- Spots inside the rails (pen floor 34 x 28; rails 0.5 thick). Clear of World's decor spots
-- (x = ±10.5, z = -7.7 and x = 0, z = -8.7) and of each other.
Pens.ThemeSpots = { { 5, -11 }, { -13.5, -3 } }
Pens.HabitatSpot = { -1, 2 }

Pens.Fences = {
	{ id = "wood", jarTier = 1, themed = true, rail = { mat = "WoodPlanks" }, post = { mat = "Wood", darken = 0.2 } },
	{
		id = "timber",
		jarTier = 2,
		themed = true,
		rail = { mat = "WoodPlanks", darken = 0.08 },
		post = { mat = "Wood", darken = 0.35 },
		cap = { shape = "block", size = { 1.4, 0.4, 1.4 }, at = { 0, 0.2, 0 }, mat = "Wood", color = "#6B4424" },
	},
	{
		id = "stone",
		jarTier = 3,
		rail = { mat = "Cobblestone", color = "#9A958C", mix = 0.65 },
		post = { mat = "Slate", color = "#6E6A64", mix = 0.75 },
		cap = { shape = "block", size = { 1.5, 0.5, 1.5 }, at = { 0, 0.25, 0 }, mat = "Slate", color = "#BDB8AE" },
	},
	{
		id = "crystal",
		jarTier = 4,
		rail = { mat = "Glass", color = "#A6ECFF", mix = 0.6, alpha = 0.3 },
		post = { mat = "Marble", color = "#EAFBFF", mix = 0.8 },
		cap = { shape = "block", size = { 0.7, 1.8, 0.7 }, at = { 0, 0.9, 0 }, rot = { 0, 45, 0 }, mat = "Neon", color = "#8FE3FF" },
	},
}

-- One visible step per capacity upgrade (Economy.Pens.startCapacity .. maxCapacity).
Pens.Upgrades = {
	{ id = "hay_nest", capacity = 6, at = { 12, -1 } },
	{ id = "trough", capacity = 7, at = { -6, 10.5 } },
	{ id = "pond", capacity = 8, at = { 8, 7.5 } },
	{ id = "hut", capacity = 9, at = { -12, 3.5 } },
	{ id = "shade_tree", capacity = 10, at = { 13, -10.5 } },
}

Pens.DefaultTheme = "wood"
Pens.Themes = {
	wood = { floor = "Grass", props = { "sunflowers" } },
	stone = { floor = "Grass", rail = "Cobblestone", props = { "stone_lantern" } },
	candy = { floor = "SmoothPlastic", rail = "SmoothPlastic", props = { "lollipops" } },
	snowglobe = { floor = "Snow", rail = "Ice", props = { "snowman" } },
	boardwalk = { floor = "Sand", rail = "WoodPlanks", props = { "surfboard" } },
	lantern_garden = { floor = "Pebble", rail = "Wood", props = { "paper_lanterns", "banner" } },
	blossom_glade = { floor = "LeafyGrass", props = { "blossom_tree", "flowers" } },
	tropical_lagoon = { floor = "Sand", props = { "palm_tree" } },
	haunted_hollow = { floor = "Mud", rail = "Wood", props = { "pumpkins", "crooked_lamp" } },
	starfield = { floor = "Slate", props = { "star_lamps" } },
	crystal_tundra = { floor = "Snow", rail = "Ice", props = { "ice_spikes" } },
	aurora_isle = { floor = "Grass", props = { "aurora_banner" } },
	sunset_mesa = { floor = "Sandstone", rail = "Sandstone", props = { "cactus" } },
	nebula = { floor = "Slate", props = { "orbs" } },
}

-- The habitat shows when at least `minShare` of the pen's monsters carry the element.
Pens.Habitat = { minMonsters = 1, minShare = 0.5 }
Pens.Habitats = {
	ember = "lava_rocks",
	tide = "tide_pool",
	sprout = "leafy_grove",
	spark = "storm_rod",
	gloom = "shadow_shrooms",
	stone = "boulders",
	light = "sun_shrine",
	void = "void_shards",
}

local function up(h: number): { number }
	return { 0, h / 2, 0 }
end

Pens.Props = {
	-- Capacity upgrades -------------------------------------------------------------------
	hay_nest = {
		spot = "bed",
		pieces = {
			{ shape = "cyl", size = { 4.2, 0.7, 4.2 }, at = up(0.7), mat = "Grass", color = "#E3C565" },
			{ shape = "cyl", size = { 4.8, 0.4, 4.8 }, at = up(0.4), mat = "Wood", color = "#B08A3E", small = true },
		},
	},
	trough = {
		spot = "food",
		pieces = {
			{ shape = "block", size = { 5, 1.4, 1.8 }, at = up(1.4), mat = "WoodPlanks", color = "#8A5A2B" },
			{ shape = "block", size = { 4.4, 0.3, 1.3 }, at = { 0, 1.3, 0 }, mat = "Grass", color = "#D8B64A" },
		},
	},
	pond = {
		spot = "water",
		pieces = {
			{ shape = "cyl", size = { 7, 0.25, 7 }, at = { 0, 0.14, 0 }, mat = "Glass", color = "#4FB6F2", alpha = 0.2 },
			{ shape = "cyl", size = { 8, 0.15, 8 }, at = { 0, 0.07, 0 }, mat = "Slate", color = "#8C8A84" },
			{ shape = "cyl", size = { 1.2, 0.08, 1.2 }, at = { 1.5, 0.3, -1 }, mat = "Grass", color = "#62BF55", small = true },
			{ shape = "ball", size = { 1.4, 0.9, 1.2 }, at = { -3.4, 0.4, 1.8 }, mat = "Rock", color = "#9A958C", small = true },
		},
	},
	hut = {
		spot = "shelter",
		pieces = {
			{ shape = "block", size = { 4.6, 3.2, 4.6 }, at = up(3.2), mat = "WoodPlanks", color = "#A0703D" },
			{ shape = "wedge", size = { 5.4, 1.8, 2.9 }, at = { 0, 4.1, -1.45 }, mat = "Wood", color = "#7A4A22" },
			{ shape = "wedge", size = { 5.4, 1.8, 2.9 }, at = { 0, 4.1, 1.45 }, rot = { 0, 180, 0 }, mat = "Wood", color = "#7A4A22" },
			{ shape = "block", size = { 1.6, 2.2, 0.2 }, at = { 0, 1.1, 2.35 }, mat = "Wood", color = "#4A2E16", small = true },
		},
	},
	shade_tree = {
		spot = "shelter",
		pieces = {
			{ shape = "cyl", size = { 1, 5, 1 }, at = up(5), mat = "Wood", color = "#7A4A22" },
			{ shape = "ball", size = { 5.5, 4.5, 5.5 }, at = { 0, 6, 0 }, mat = "LeafyGrass", color = "#5DAE4B" },
			{ shape = "ball", size = { 3.5, 3, 3.5 }, at = { 1.2, 7.6, 0.8 }, mat = "LeafyGrass", color = "#7BC65E", small = true },
		},
	},

	-- Theme signatures ---------------------------------------------------------------------
	sunflowers = {
		pieces = {
			{ shape = "cyl", size = { 0.25, 2.6, 0.25 }, at = up(2.6), mat = "Grass", color = "#4E9A3A" },
			{ shape = "cyl", size = { 1.4, 0.3, 1.4 }, at = { 0, 2.7, 0.1 }, rot = { 90, 0, 0 }, mat = "SmoothPlastic", color = "#F6CD3A" },
			{ shape = "cyl", size = { 0.2, 2, 0.2 }, at = { 1.1, 1, 0.3 }, mat = "Grass", color = "#4E9A3A", small = true },
			{
				shape = "cyl",
				size = { 1, 0.25, 1 },
				at = { 1.1, 2.05, 0.4 },
				rot = { 90, 0, 0 },
				mat = "SmoothPlastic",
				color = "#F6CD3A",
				small = true,
			},
		},
	},
	stone_lantern = {
		pieces = {
			{ shape = "block", size = { 0.6, 1.6, 0.6 }, at = { 0, 1, 0 }, mat = "Slate", color = "#8E8E8E" },
			{ shape = "block", size = { 1.1, 0.9, 1.1 }, at = { 0, 2.25, 0 }, mat = "Neon", color = "#FFD98A" },
			{ shape = "block", size = { 1.6, 0.3, 1.6 }, at = { 0, 2.85, 0 }, mat = "Slate", color = "#6E6A64" },
			{ shape = "block", size = { 1.4, 0.4, 1.4 }, at = up(0.4), mat = "Slate", color = "#6E6A64", small = true },
		},
	},
	lollipops = {
		pieces = {
			{ shape = "cyl", size = { 0.2, 3, 0.2 }, at = up(3), mat = "SmoothPlastic", color = "#FFFFFF" },
			{ shape = "cyl", size = { 2, 0.4, 2 }, at = { 0, 3.4, 0 }, rot = { 90, 0, 0 }, mat = "SmoothPlastic", color = "fence" },
			{ shape = "cyl", size = { 0.18, 2.2, 0.18 }, at = { 1.6, 1.1, 0 }, mat = "SmoothPlastic", color = "#FFFFFF", small = true },
			{
				shape = "cyl",
				size = { 1.4, 0.35, 1.4 },
				at = { 1.6, 2.5, 0 },
				rot = { 90, 0, 0 },
				mat = "SmoothPlastic",
				color = "#8FD8FF",
				small = true,
			},
		},
	},
	snowman = {
		pieces = {
			{ shape = "ball", size = { 2.4, 2.4, 2.4 }, at = { 0, 1.2, 0 }, mat = "Snow", color = "#F7FBFF" },
			{ shape = "ball", size = { 1.7, 1.7, 1.7 }, at = { 0, 2.9, 0 }, mat = "Snow", color = "#F7FBFF" },
			{ shape = "ball", size = { 1.1, 1.1, 1.1 }, at = { 0, 4.1, 0 }, mat = "Snow", color = "#F7FBFF" },
			{ shape = "block", size = { 0.2, 0.2, 0.6 }, at = { 0, 4.1, 0.75 }, mat = "SmoothPlastic", color = "#F08A4B", small = true },
		},
	},
	surfboard = {
		pieces = {
			{ shape = "block", size = { 0.3, 4, 1.3 }, at = { 0, 2, 0 }, rot = { 0, 0, -10 }, mat = "SmoothPlastic", color = "#FF6B6B" },
			{
				shape = "block",
				size = { 0.32, 4, 0.3 },
				at = { 0, 2, 0 },
				rot = { 0, 0, -10 },
				mat = "SmoothPlastic",
				color = "#FFFFFF",
				small = true,
			},
		},
	},
	paper_lanterns = {
		pieces = {
			{ shape = "cyl", size = { 0.3, 4.2, 0.3 }, at = up(4.2), mat = "Wood", color = "#5A1E1E" },
			{ shape = "block", size = { 3, 0.25, 0.25 }, at = { 0, 4, 0 }, mat = "Wood", color = "#5A1E1E" },
			{ shape = "ball", size = { 0.9, 1.1, 0.9 }, at = { -1.2, 3.3, 0 }, mat = "Neon", color = "#E5484D" },
			{ shape = "ball", size = { 0.9, 1.1, 0.9 }, at = { 1.2, 3.3, 0 }, mat = "Neon", color = "#F2A33A", small = true },
		},
	},
	banner = {
		pieces = {
			{ shape = "cyl", size = { 0.25, 4.5, 0.25 }, at = up(4.5), mat = "Wood", color = "#5A1E1E" },
			{ shape = "block", size = { 0.1, 1.8, 1.4 }, at = { 0, 3.5, 0.75 }, mat = "Fabric", color = "fence" },
		},
	},
	blossom_tree = {
		pieces = {
			{ shape = "cyl", size = { 0.7, 3.5, 0.7 }, at = up(3.5), mat = "Wood", color = "#6B4424" },
			{ shape = "ball", size = { 3.6, 3, 3.6 }, at = { 0, 4.4, 0 }, mat = "LeafyGrass", color = "#F7A8C8" },
			{ shape = "ball", size = { 2.2, 1.8, 2.2 }, at = { 0.9, 5.6, 0.4 }, mat = "LeafyGrass", color = "#FFD1E3", small = true },
		},
	},
	flowers = {
		pieces = {
			{ shape = "cyl", size = { 2.6, 0.15, 2.6 }, at = up(0.15), mat = "Grass", color = "#6FBF55" },
			{ shape = "ball", size = { 0.6, 0.6, 0.6 }, at = { -0.6, 0.45, 0.3 }, mat = "SmoothPlastic", color = "#FF6FA5", small = true },
			{ shape = "ball", size = { 0.6, 0.6, 0.6 }, at = { 0.5, 0.45, -0.4 }, mat = "SmoothPlastic", color = "#FFE680", small = true },
			{ shape = "ball", size = { 0.6, 0.6, 0.6 }, at = { 0.3, 0.45, 0.7 }, mat = "SmoothPlastic", color = "#FFB3D1", small = true },
		},
	},
	palm_tree = {
		pieces = {
			{ shape = "cyl", size = { 0.6, 5, 0.6 }, at = up(5), rot = { 0, 0, 6 }, mat = "Wood", color = "#9C7446" },
			{ shape = "block", size = { 4.6, 0.2, 1 }, at = { -0.3, 5.1, 0 }, rot = { 0, 0, -8 }, mat = "LeafyGrass", color = "#3FAE5A" },
			{ shape = "block", size = { 1, 0.2, 4.6 }, at = { -0.3, 5.1, 0 }, rot = { 8, 0, 0 }, mat = "LeafyGrass", color = "#3FAE5A" },
			{ shape = "ball", size = { 0.6, 0.6, 0.6 }, at = { 0, 4.6, 0.4 }, mat = "SmoothPlastic", color = "#7A5A3A", small = true },
		},
	},
	pumpkins = {
		pieces = {
			{ shape = "ball", size = { 1.8, 1.3, 1.8 }, at = { 0, 0.65, 0 }, mat = "SmoothPlastic", color = "#F08A4B" },
			{ shape = "cyl", size = { 0.25, 0.4, 0.25 }, at = { 0, 1.45, 0 }, mat = "Wood", color = "#4E6B2A", small = true },
			{ shape = "ball", size = { 1.1, 0.8, 1.1 }, at = { 1.4, 0.4, 0.5 }, mat = "SmoothPlastic", color = "#E0702F", small = true },
		},
	},
	crooked_lamp = {
		pieces = {
			{ shape = "cyl", size = { 0.3, 3.6, 0.3 }, at = up(3.6), rot = { 0, 0, 8 }, mat = "Wood", color = "#2B2138" },
			{ shape = "ball", size = { 0.8, 0.8, 0.8 }, at = { -0.3, 3.8, 0 }, mat = "Neon", color = "#B6FF7A" },
		},
	},
	star_lamps = {
		pieces = {
			{ shape = "cyl", size = { 0.3, 3.4, 0.3 }, at = up(3.4), mat = "Metal", color = "#6B5BD6" },
			{ shape = "ball", size = { 0.9, 0.9, 0.9 }, at = { 0, 3.7, 0 }, mat = "Neon", color = "#FFF4C2" },
			{ shape = "ball", size = { 0.5, 0.5, 0.5 }, at = { 0.8, 2.6, 0.2 }, mat = "Neon", color = "#C9C2FF", small = true },
		},
	},
	ice_spikes = {
		pieces = {
			{ shape = "block", size = { 0.8, 3, 0.8 }, at = { 0, 1.4, 0 }, rot = { 0, 45, 6 }, mat = "Ice", color = "#BFE9FF" },
			{ shape = "block", size = { 0.6, 2, 0.6 }, at = { 0.9, 0.9, 0.4 }, rot = { 10, 20, -8 }, mat = "Ice", color = "#9FE3FF" },
			{
				shape = "block",
				size = { 0.5, 1.4, 0.5 },
				at = { -0.8, 0.6, 0.5 },
				rot = { -8, 60, 10 },
				mat = "Ice",
				color = "#E4F4FF",
				small = true,
			},
		},
	},
	aurora_banner = {
		pieces = {
			{ shape = "cyl", size = { 0.25, 4.5, 0.25 }, at = up(4.5), mat = "Metal", color = "#1F4E5F" },
			{ shape = "block", size = { 0.1, 1.8, 1.4 }, at = { 0, 3.5, 0.75 }, mat = "Fabric", color = "#3DDC97" },
			{ shape = "block", size = { 0.12, 0.3, 1.4 }, at = { 0, 3.1, 0.75 }, mat = "Neon", color = "#6B5BD6", small = true },
		},
	},
	cactus = {
		pieces = {
			{ shape = "cyl", size = { 1, 3, 1 }, at = up(3), mat = "Grass", color = "#4E9A3A" },
			{ shape = "ball", size = { 1, 1, 1 }, at = { 0, 3, 0 }, mat = "Grass", color = "#4E9A3A" },
			{
				shape = "cyl",
				size = { 0.6, 1.2, 0.6 },
				at = { 0.75, 1.9, 0 },
				rot = { 0, 0, -40 },
				mat = "Grass",
				color = "#5DAE4B",
				small = true,
			},
		},
	},
	orbs = {
		pieces = {
			{ shape = "cyl", size = { 1.4, 0.8, 1.4 }, at = up(0.8), mat = "Slate", color = "#3A2D55" },
			{ shape = "ball", size = { 1.3, 1.3, 1.3 }, at = { 0, 1.5, 0 }, mat = "Neon", color = "#FF7AC8", alpha = 0.15 },
			{ shape = "ball", size = { 0.5, 0.5, 0.5 }, at = { 0.9, 2.4, 0.3 }, mat = "Neon", color = "#C9A8FF", small = true },
		},
	},

	-- Element habitats ----------------------------------------------------------------------
	lava_rocks = {
		spot = "bed",
		pieces = {
			{ shape = "cyl", size = { 2.6, 0.12, 2.6 }, at = { -0.6, 0.06, 1.4 }, mat = "CrackedLava", color = "element" },
			{ shape = "ball", size = { 2.4, 1.6, 2.2 }, at = { 0, 0.7, -0.6 }, mat = "Basalt", color = "#3B332F" },
			{ shape = "ball", size = { 1.6, 1.2, 1.5 }, at = { 1.8, 0.5, 0.8 }, mat = "Basalt", color = "#4A3F39", small = true },
			{ shape = "ball", size = { 0.5, 0.5, 0.5 }, at = { -0.9, 0.35, 1.6 }, mat = "Neon", color = "accent", small = true },
		},
	},
	tide_pool = {
		spot = "water",
		pieces = {
			{ shape = "cyl", size = { 4.2, 0.25, 4.2 }, at = { 0, 0.14, 0 }, mat = "Glass", color = "element", alpha = 0.2 },
			{ shape = "cyl", size = { 4.9, 0.15, 4.9 }, at = { 0, 0.07, 0 }, mat = "Rock", color = "#CFC6B5" },
			{ shape = "ball", size = { 0.6, 0.4, 0.6 }, at = { 1.9, 0.3, 1.2 }, mat = "SmoothPlastic", color = "#F7C6D9", small = true },
		},
	},
	leafy_grove = {
		spot = "shelter",
		pieces = {
			{ shape = "ball", size = { 2.8, 2.2, 2.8 }, at = { 0, 1, 0 }, mat = "LeafyGrass", color = "element" },
			{ shape = "ball", size = { 1.9, 1.6, 1.9 }, at = { 1.8, 0.8, 0.9 }, mat = "LeafyGrass", color = "accent", small = true },
			{ shape = "ball", size = { 1.5, 1.3, 1.5 }, at = { -1.6, 0.6, 1 }, mat = "LeafyGrass", color = "#4E9A3A", small = true },
		},
	},
	storm_rod = {
		spot = "bed",
		pieces = {
			{ shape = "cyl", size = { 2.8, 0.2, 2.8 }, at = up(0.2), mat = "SmoothPlastic", color = "accent" },
			{ shape = "cyl", size = { 0.3, 3.2, 0.3 }, at = { -1.6, 1.6, -1.2 }, mat = "Metal", color = "#9AA3AD" },
			{ shape = "ball", size = { 0.9, 0.9, 0.9 }, at = { -1.6, 3.4, -1.2 }, mat = "Neon", color = "element" },
		},
	},
	shadow_shrooms = {
		spot = "shelter",
		pieces = {
			{ shape = "ball", size = { 2.2, 1, 2.2 }, at = { 0, 1.9, 0 }, mat = "SmoothPlastic", color = "element" },
			{ shape = "cyl", size = { 0.5, 1.7, 0.5 }, at = up(1.7), mat = "SmoothPlastic", color = "#E4D6F8" },
			{ shape = "cyl", size = { 0.3, 0.9, 0.3 }, at = { 1.3, 0.45, 0.7 }, mat = "SmoothPlastic", color = "#E4D6F8", small = true },
			{ shape = "ball", size = { 1.1, 0.5, 1.1 }, at = { 1.3, 1, 0.7 }, mat = "Neon", color = "accent", small = true },
		},
	},
	boulders = {
		spot = "bed",
		pieces = {
			{ shape = "ball", size = { 2.6, 2, 2.4 }, at = { 0, 0.9, 0 }, mat = "Rock", color = "element" },
			{ shape = "ball", size = { 1.8, 1.4, 1.7 }, at = { 1.9, 0.6, 0.8 }, mat = "Rock", color = "#8C735C" },
			{ shape = "ball", size = { 1, 0.8, 1 }, at = { -1.5, 0.35, 1 }, mat = "Rock", color = "#B7A58F", small = true },
		},
	},
	sun_shrine = {
		spot = "bed",
		pieces = {
			{ shape = "cyl", size = { 2.8, 0.3, 2.8 }, at = up(0.3), mat = "Marble", color = "#FFF8E6" },
			{ shape = "cyl", size = { 0.8, 1.8, 0.8 }, at = { 0, 1.2, 0 }, mat = "Marble", color = "element" },
			{ shape = "cyl", size = { 1.8, 0.12, 1.8 }, at = { 0, 2.2, 0 }, mat = "Neon", color = "accent", small = true },
		},
	},
	void_shards = {
		spot = "shelter",
		pieces = {
			{
				shape = "block",
				size = { 0.9, 2.6, 0.9 },
				at = { 0, 1.2, 0 },
				rot = { 10, 30, 0 },
				mat = "Glass",
				color = "#2A1B3D",
				alpha = 0.1,
			},
			{
				shape = "block",
				size = { 0.7, 1.8, 0.7 },
				at = { 1.1, 0.8, 0.5 },
				rot = { -12, 70, 0 },
				mat = "Glass",
				color = "#3A2758",
				alpha = 0.1,
			},
			{ shape = "cyl", size = { 2.4, 0.1, 2.4 }, at = up(0.1), mat = "Neon", color = "element", small = true },
		},
	},
}

-- Every prop can be swapped for a generated mesh later without code changes.
for _, prop in Pens.Props do
	prop.mesh = prop.mesh or ""
	prop.texture = prop.texture or ""
end

-- The Feed Garden (World.GardenOffset, World.GardenSize 10 x 8): a frame and up to 8 beds
-- (Economy.Garden.plots), 4 across and 2 deep, each with two plants.
Pens.Garden = {
	frame = { shape = "block", size = { 10.4, 0.3, 8.4 }, at = { 0, 0.15, 0 }, mat = "WoodPlanks", color = "#8A5A2B" },
	columns = 4,
	bed = { 2.1, 0.35, 3.3 }, -- x, height, z
	spacing = { 2.5, 3.9 },
	soil = { mat = "Ground", color = "#6B4A2E" },
	plants = { -0.85, 0.85 }, -- z offsets inside a bed
	-- Crop stages by growth progress (0..1): 1 seeds, 2 sprouts, 3 grown, 4 ready to harvest.
	stageAt = { 0, 0.34, 0.67 },
	stages = {
		{ size = { 0.4, 0.25, 0.4 }, mat = "Grass", color = "#8BAA4A" },
		{ size = { 0.45, 0.9, 0.45 }, mat = "Grass", color = "#7BC65E" },
		{ size = { 0.9, 1.4, 0.9 }, mat = "LeafyGrass", color = "#5DAE4B" },
		{ size = { 1, 1.6, 1 }, mat = "LeafyGrass", color = "#4E9A3A" },
	},
	fruit = { size = { 0.6, 0.6, 0.6 }, mat = "Neon" }, -- flavour colour, ready stage only
	glow = { pad = 0.18, height = 0.1, mat = "Neon", color = "#FFD447", alpha = 0.35 }, -- the harvest-ready rim
	mesh = "",
}

return Pens
