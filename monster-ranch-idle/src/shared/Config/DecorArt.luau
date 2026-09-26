--[[
	DecorArt (glow-up Z · Build your ranch): how every decor piece is built from parts, as data.
	Config.Decor names a `model` per piece; Art.Pieces(def) returns its parts. Drawn by
	Visuals/DecorModel. The art swap point is the piece's `mesh` id (Config.Decor): a piece with a
	non-empty `mesh` is drawn as one MeshPart-like part instead of these pieces.

	Coordinates are studs from the piece's origin on the ground (y up), before its rotation.
	Piece: { shape = "block"|"ball"|"cyl"|"wedge", size = { x, y, z }, at = { x, y, z },
	  rot = { x, y, z }? (degrees), mat = Enum.Material name, color = hex, alpha?, small?, glow? }
	A "cyl" stands upright (size y = height). `small` pieces are dropped in low graphics and on far
	plots; `glow` pieces are Neon and are where the night light sits (Controllers/Decor).
	Every model stays within Config.Decor.Layout.maxParts parts (Decor.spec checks it).
]]

local Art = {}

local function P(shape: string, size, at, mat: string, color: string, extra: { [string]: any }?)
	local piece = { shape = shape, size = size, at = at, mat = mat, color = color }
	if extra then
		for k, v in extra do
			piece[k] = v
		end
	end
	return piece
end

local SMALL = { small = true }
local GLOW = { glow = true }
local WOOD_DARK = "#6B4424"
local LEAF = "#5FAF4B"
local STONE = "#A7A29A"

-- Each model: function(a, b, def) -> { piece }; a = def.color, b = def.color2 (or a default).
Art.Models = {
	fence = function(a, _b, def)
		local m = def.mat or "WoodPlanks"
		return {
			P("block", { 4, 0.3, 0.25 }, { 0, 1.6, 0 }, m, a),
			P("block", { 0.4, 2.2, 0.4 }, { -1.8, 1.1, 0 }, m, a),
			P("block", { 0.4, 2.2, 0.4 }, { 1.8, 1.1, 0 }, m, a),
			P("block", { 4, 0.3, 0.25 }, { 0, 0.8, 0 }, m, a),
		}
	end,
	picket = function(a)
		local parts = { P("block", { 4, 0.3, 0.15 }, { 0, 1.1, -0.1 }, "WoodPlanks", a) }
		for i = 0, 4 do
			table.insert(parts, P("block", { 0.5, 1.8, 0.2 }, { -1.6 + i * 0.8, 0.9, 0 }, "WoodPlanks", a))
		end
		return parts
	end,
	wall = function(a, b, def)
		return {
			P("block", { 4, 1.8, 1 }, { 0, 0.9, 0 }, def.mat or "Cobblestone", a),
			P("block", { 4.2, 0.3, 1.2 }, { 0, 1.95, 0 }, "Slate", b, SMALL),
		}
	end,
	hedge = function(a, b)
		return {
			P("block", { 4, 2, 1.4 }, { 0, 1, 0 }, "LeafyGrass", a),
			P("ball", { 0.6, 0.6, 0.6 }, { -1, 1.9, 0.5 }, "SmoothPlastic", b, SMALL),
			P("ball", { 0.6, 0.6, 0.6 }, { 1.2, 1.7, -0.5 }, "SmoothPlastic", b, SMALL),
		}
	end,
	path = function(a, b, def)
		return {
			P("block", { 4, 0.12, 4 }, { 0, 0.06, 0 }, def.mat or "Slate", a),
			P("block", { 1.6, 0.14, 1.6 }, { -0.9, 0.07, -0.9 }, def.mat or "Slate", b, SMALL),
			P("block", { 1.6, 0.14, 1.6 }, { 0.9, 0.07, 0.9 }, def.mat or "Slate", b, SMALL),
		}
	end,
	stones = function(a, b)
		return {
			P("cyl", { 1.5, 0.15, 1.5 }, { -1.2, 0.08, -1.1 }, "Slate", a),
			P("cyl", { 1.3, 0.15, 1.3 }, { 0.2, 0.08, 0.2 }, "Slate", b),
			P("cyl", { 1.5, 0.15, 1.5 }, { 1.3, 0.08, 1.2 }, "Slate", a),
		}
	end,
	puddle = function(a)
		return { P("cyl", { 4.5, 0.12, 3.6 }, { 0, 0.06, 0 }, "Mud", a) }
	end,
	lamppost = function(a, b, def)
		return {
			P("cyl", { 1, 0.4, 1 }, { 0, 0.2, 0 }, "Metal", a),
			P("cyl", { 0.35, 5, 0.35 }, { 0, 2.6, 0 }, def.mat or "Metal", a),
			P("ball", { 0.9, 0.9, 0.9 }, { 0, 5.4, 0 }, "Neon", b, GLOW),
			P("block", { 1.3, 0.2, 1.3 }, { 0, 6, 0 }, "Metal", a),
			P("block", { 1.1, 0.12, 1.1 }, { 0, 4.9, 0 }, "Metal", a, SMALL),
		}
	end,
	lantern = function(a, b)
		return {
			P("block", { 1.3, 0.5, 1.3 }, { 0, 0.25, 0 }, "Slate", a),
			P("block", { 0.5, 1.4, 0.5 }, { 0, 1.2, 0 }, "Slate", a),
			P("block", { 1.1, 0.9, 1.1 }, { 0, 2.35, 0 }, "Slate", a, { alpha = 0.35 }),
			P("ball", { 0.6, 0.6, 0.6 }, { 0, 2.35, 0 }, "Neon", b, GLOW),
			P("wedge", { 1.6, 0.4, 0.8 }, { 0, 3, -0.4 }, "Slate", a, SMALL),
			P("wedge", { 1.6, 0.4, 0.8 }, { 0, 3, 0.4 }, "Slate", a, { small = true, rot = { 0, 180, 0 } }),
		}
	end,
	paperlantern = function(a, b)
		return {
			P("block", { 0.3, 3.6, 0.3 }, { 0, 1.8, 0 }, "Wood", WOOD_DARK),
			P("block", { 1.4, 0.2, 0.2 }, { 0.5, 3.5, 0 }, "Wood", WOOD_DARK),
			P("ball", { 1.3, 1.6, 1.3 }, { 1, 2.5, 0 }, "Neon", a, GLOW),
			P("cyl", { 0.8, 0.15, 0.8 }, { 1, 3.35, 0 }, "SmoothPlastic", b, SMALL),
		}
	end,
	torch = function(a, b)
		return {
			P("cyl", { 0.3, 3, 0.3 }, { 0, 1.5, 0 }, "Wood", a),
			P("cyl", { 0.8, 0.45, 0.8 }, { 0, 3.1, 0 }, "Metal", "#4A4A4A"),
			P("ball", { 0.6, 0.9, 0.6 }, { 0, 3.6, 0 }, "Neon", b, GLOW),
		}
	end,
	stringlights = function(a, b)
		local parts = {
			P("block", { 5.6, 0.08, 0.08 }, { 0, 3.8, 0 }, "SmoothPlastic", "#3A3A3A"),
			P("cyl", { 0.3, 4, 0.3 }, { -2.8, 2, 0 }, "Wood", WOOD_DARK),
			P("cyl", { 0.3, 4, 0.3 }, { 2.8, 2, 0 }, "Wood", WOOD_DARK),
			P("ball", { 0.45, 0.45, 0.45 }, { -1.8, 3.55, 0 }, "Neon", a, GLOW),
		}
		for i, x in { -0.6, 0.6, 1.8 } do
			table.insert(parts, P("ball", { 0.45, 0.45, 0.45 }, { x, 3.55, 0 }, "Neon", if i % 2 == 1 then b else a, SMALL))
		end
		return parts
	end,
	pond = function(a, b, def)
		local w, d = def.size[1], def.size[2]
		return {
			P("cyl", { w, 0.3, d }, { 0, 0.15, 0 }, "Slate", b),
			P("cyl", { w - 1, 0.32, d - 1 }, { 0, 0.17, 0 }, "Glass", a, { alpha = 0.25 }),
			P("cyl", { 1.2, 0.06, 1.2 }, { w * 0.18, 0.35, -d * 0.1 }, "Grass", LEAF, SMALL),
			P("cyl", { 1, 0.06, 1 }, { -w * 0.2, 0.35, d * 0.15 }, "Grass", LEAF, SMALL),
			P("ball", { 0.5, 0.4, 0.5 }, { w * 0.18, 0.5, -d * 0.1 }, "SmoothPlastic", "#FF9EC7", SMALL),
		}
	end,
	birdbath = function(a, b)
		return {
			P("cyl", { 1.1, 0.3, 1.1 }, { 0, 0.15, 0 }, "Marble", a),
			P("cyl", { 0.45, 1.6, 0.45 }, { 0, 1.1, 0 }, "Marble", a),
			P("cyl", { 1.9, 0.4, 1.9 }, { 0, 2.05, 0 }, "Marble", a),
			P("cyl", { 1.5, 0.1, 1.5 }, { 0, 2.26, 0 }, "Glass", b, { alpha = 0.3 }),
		}
	end,
	well = function(a, b)
		return {
			P("cyl", { 3, 1.6, 3 }, { 0, 0.8, 0 }, "Cobblestone", a),
			P("cyl", { 2.3, 0.1, 2.3 }, { 0, 1.5, 0 }, "Glass", "#3E8FC2", { alpha = 0.2 }),
			P("block", { 0.3, 2.4, 0.3 }, { -1.3, 2.8, 0 }, "Wood", WOOD_DARK),
			P("block", { 0.3, 2.4, 0.3 }, { 1.3, 2.8, 0 }, "Wood", WOOD_DARK),
			P("wedge", { 3.4, 0.9, 1.7 }, { 0, 4.4, -0.85 }, "WoodPlanks", b),
			P("wedge", { 3.4, 0.9, 1.7 }, { 0, 4.4, 0.85 }, "WoodPlanks", b, { rot = { 0, 180, 0 } }),
			P("cyl", { 0.8, 0.8, 0.8 }, { 0, 1.9, 0 }, "Wood", WOOD_DARK, { rot = { 0, 0, 90 }, small = true }),
		}
	end,
	fountain = function(a, b, def)
		local w, d = def.size[1], def.size[2]
		return {
			P("cyl", { w, 0.8, d }, { 0, 0.4, 0 }, "Marble", a),
			P("cyl", { w - 0.8, 0.1, d - 0.8 }, { 0, 0.82, 0 }, "Glass", b, { alpha = 0.25 }),
			P("cyl", { 0.8, 2, 0.8 }, { 0, 1.8, 0 }, "Marble", a),
			P("cyl", { 2, 0.3, 2 }, { 0, 2.9, 0 }, "Marble", a),
			P("ball", { 0.7, 1, 0.7 }, { 0, 3.4, 0 }, "Glass", b, { alpha = 0.3, small = true }),
		}
	end,
	tree = function(a, b)
		return {
			P("cyl", { 0.9, 3.5, 0.9 }, { 0, 1.75, 0 }, "Wood", b),
			P("ball", { 4.5, 3.8, 4.5 }, { 0, 4.6, 0 }, "LeafyGrass", a),
			P("ball", { 3, 2.6, 3 }, { 1.4, 5.7, 0.6 }, "LeafyGrass", a),
			P("ball", { 2.8, 2.4, 2.8 }, { -1.2, 5.4, -0.8 }, "LeafyGrass", a, SMALL),
		}
	end,
	pine = function(a, b)
		return {
			P("cyl", { 0.7, 1.4, 0.7 }, { 0, 0.7, 0 }, "Wood", b),
			P("cyl", { 3.6, 1.4, 3.6 }, { 0, 2, 0 }, "LeafyGrass", a),
			P("cyl", { 2.8, 1.3, 2.8 }, { 0, 3.2, 0 }, "LeafyGrass", a),
			P("cyl", { 1.9, 1.2, 1.9 }, { 0, 4.3, 0 }, "LeafyGrass", a),
			P("cyl", { 1, 1, 1 }, { 0, 5.2, 0 }, "LeafyGrass", a, SMALL),
		}
	end,
	palm = function(a, b)
		local parts = {
			P("cyl", { 0.7, 5, 0.7 }, { 0.3, 2.5, 0 }, "Wood", b, { rot = { 0, 0, 6 } }),
			P("ball", { 0.6, 0.6, 0.6 }, { 0.3, 4.8, 0.4 }, "SmoothPlastic", "#6B4A2B", SMALL),
		}
		for _, yaw in { 0, 90, 180, 270 } do
			local r = math.rad(yaw)
			table.insert(
				parts,
				P(
					"block",
					{ 3.2, 0.15, 0.9 },
					{ 0.3 + math.cos(r) * 1.4, 5.1, -math.sin(r) * 1.4 },
					"LeafyGrass",
					a,
					{ rot = { 0, yaw, -15 } }
				)
			)
		end
		return parts
	end,
	bush = function(a, b)
		return {
			P("ball", { 2.4, 1.8, 2.4 }, { 0, 0.9, 0 }, "LeafyGrass", a),
			P("ball", { 1.6, 1.3, 1.6 }, { 0.9, 0.7, 0.5 }, "LeafyGrass", a),
			P("ball", { 0.5, 0.5, 0.5 }, { -0.4, 1.7, 0.3 }, "SmoothPlastic", b, SMALL),
			P("ball", { 0.5, 0.5, 0.5 }, { 0.6, 1.4, -0.6 }, "SmoothPlastic", b, SMALL),
		}
	end,
	flowerbed = function(a, b, def)
		local w, d = def.size[1], def.size[2]
		local parts = {
			P("block", { w, 0.5, d }, { 0, 0.25, 0 }, "WoodPlanks", b),
			P("block", { w - 0.4, 0.52, d - 0.4 }, { 0, 0.27, 0 }, "Ground", "#6B4A2B"),
		}
		for i, spot in { { -0.3, -0.25 }, { 0.3, -0.2 }, { -0.25, 0.25 }, { 0.28, 0.22 }, { 0, 0 } } do
			table.insert(
				parts,
				P("ball", { 0.8, 0.7, 0.8 }, { spot[1] * w, 0.75, spot[2] * d }, "SmoothPlastic", a, if i > 2 then SMALL else nil)
			)
		end
		return parts
	end,
	sunflowers = function(a, b)
		local parts = {}
		for i, x in { -1.2, 0, 1.2 } do
			local h = 2.4 + (i % 2) * 0.4
			table.insert(parts, P("cyl", { 0.2, h, 0.2 }, { x, h / 2, 0 }, "Grass", b))
			table.insert(parts, P("cyl", { 1.1, 0.2, 1.1 }, { x, h, -0.1 }, "SmoothPlastic", a, { rot = { 70, 0, 0 } }))
		end
		return parts
	end,
	mushrooms = function(a, b)
		local parts = {}
		for i, spot in { { -1.2, -1 }, { 1.2, -0.8 }, { 1, 1.2 }, { -1, 1.1 } } do
			table.insert(parts, P("cyl", { 0.4, 0.6, 0.4 }, { spot[1], 0.3, spot[2] }, "SmoothPlastic", b, if i > 2 then SMALL else nil))
			table.insert(parts, P("ball", { 1, 0.55, 1 }, { spot[1], 0.7, spot[2] }, "SmoothPlastic", a))
		end
		return parts
	end,
	pot = function(a, b)
		return {
			P("cyl", { 1.3, 1, 1.3 }, { 0, 0.5, 0 }, "Brick", a),
			P("ball", { 1.5, 1.5, 1.5 }, { 0, 1.5, 0 }, "LeafyGrass", b),
		}
	end,
	bench = function(a, b, def)
		local m = def.mat or "WoodPlanks"
		return {
			P("block", { 4, 0.25, 1.2 }, { 0, 1, 0 }, m, a),
			P("block", { 4, 1, 0.2 }, { 0, 1.7, 0.5 }, m, a),
			P("block", { 0.3, 1, 1 }, { -1.6, 0.5, 0 }, "Metal", b),
			P("block", { 0.3, 1, 1 }, { 1.6, 0.5, 0 }, "Metal", b),
		}
	end,
	picnic = function(a, b)
		return {
			P("block", { 5, 0.3, 2.4 }, { 0, 1.8, 0 }, "WoodPlanks", a),
			P("block", { 5, 0.25, 0.8 }, { 0, 1, -1.7 }, "WoodPlanks", a),
			P("block", { 5, 0.25, 0.8 }, { 0, 1, 1.7 }, "WoodPlanks", a),
			P("block", { 0.3, 1.8, 3.8 }, { -2, 0.9, 0 }, "Wood", b),
			P("block", { 0.3, 1.8, 3.8 }, { 2, 0.9, 0 }, "Wood", b),
			P("block", { 1.4, 0.05, 1.4 }, { 0.8, 1.97, 0 }, "Fabric", "#E5484D", SMALL),
		}
	end,
	cart = function(a, b)
		local parts = {
			P("block", { 3.6, 0.8, 2.2 }, { 0, 1.2, 0 }, "WoodPlanks", a),
			P("block", { 3.2, 0.8, 1.8 }, { 0, 1.9, 0 }, "Grass", b),
			P("block", { 1.6, 0.2, 0.2 }, { 2.5, 1.2, 0 }, "Wood", WOOD_DARK, SMALL),
		}
		for _, w in { { -1, -1.2 }, { 1, -1.2 }, { -1, 1.2 }, { 1, 1.2 } } do
			table.insert(parts, P("cyl", { 1.4, 0.3, 1.4 }, { w[1], 0.7, w[2] }, "Wood", WOOD_DARK, { rot = { 90, 0, 0 } }))
		end
		return parts
	end,
	mailbox = function(a, b)
		return {
			P("block", { 0.3, 2.4, 0.3 }, { 0, 1.2, 0 }, "Wood", WOOD_DARK),
			P("block", { 0.9, 0.8, 1.4 }, { 0, 2.7, 0 }, "Metal", a),
			P("block", { 0.1, 0.6, 0.3 }, { 0.5, 3, 0.4 }, "SmoothPlastic", b, SMALL),
		}
	end,
	sign = function(a, b)
		return {
			P("block", { 0.3, 3, 0.3 }, { 0, 1.5, 0 }, "Wood", WOOD_DARK),
			P("block", { 2.4, 0.9, 0.2 }, { 0.6, 2.5, 0 }, "WoodPlanks", a),
			P("block", { 2, 0.7, 0.2 }, { -0.5, 1.6, 0 }, "WoodPlanks", b, SMALL),
		}
	end,
	barrel = function(a, b)
		return {
			P("cyl", { 1.6, 2, 1.6 }, { 0, 1, 0 }, "Wood", a),
			P("cyl", { 1.7, 0.15, 1.7 }, { 0, 0.5, 0 }, "Metal", b, SMALL),
			P("cyl", { 1.7, 0.15, 1.7 }, { 0, 1.5, 0 }, "Metal", b, SMALL),
		}
	end,
	crate = function(a, b)
		return {
			P("block", { 2, 2, 2 }, { 0, 1, 0 }, "WoodPlanks", a),
			P("block", { 2.05, 0.3, 2.05 }, { 0, 0.4, 0 }, "Wood", b, SMALL),
			P("block", { 2.05, 0.3, 2.05 }, { 0, 1.6, 0 }, "Wood", b, SMALL),
		}
	end,
	arch = function(a, b, def)
		local m = def.mat or "WoodPlanks"
		local glow = if def.glow then GLOW else nil
		return {
			P("block", { 0.8, 5, 0.8 }, { -2.6, 2.5, 0 }, m, a),
			P("block", { 0.8, 5, 0.8 }, { 2.6, 2.5, 0 }, m, a),
			P("block", { 6.2, 0.8, 0.9 }, { 0, 5.3, 0 }, if def.glow then "Neon" else m, a, glow),
			P("ball", { 1, 1, 1 }, { -2.6, 5.8, 0 }, "SmoothPlastic", b, SMALL),
			P("ball", { 1, 1, 1 }, { 2.6, 5.8, 0 }, "SmoothPlastic", b, SMALL),
			P("ball", { 1.2, 1.2, 1.2 }, { 0, 5.9, 0 }, "SmoothPlastic", b, SMALL),
		}
	end,
	bridge = function(a, b)
		return {
			P("wedge", { 2.4, 0.9, 3 }, { 0, 0.45, -1.5 }, "WoodPlanks", b, { rot = { 0, 180, 0 } }),
			P("wedge", { 2.4, 0.9, 3 }, { 0, 0.45, 1.5 }, "WoodPlanks", b),
			P("block", { 0.25, 0.25, 6 }, { -1.1, 1.6, 0 }, "Wood", a),
			P("block", { 0.25, 0.25, 6 }, { 1.1, 1.6, 0 }, "Wood", a),
			P("block", { 0.3, 1.6, 0.3 }, { -1.1, 0.8, 0 }, "Wood", a, SMALL),
			P("block", { 0.3, 1.6, 0.3 }, { 1.1, 0.8, 0 }, "Wood", a, SMALL),
		}
	end,
	statue = function(a, b, def)
		local m = def.mat or "Marble"
		return {
			P("block", { 2.4, 1.2, 2.4 }, { 0, 0.6, 0 }, "Marble", b),
			P("ball", { 1.9, 1.7, 1.7 }, { 0, 2.05, 0 }, m, a),
			P("ball", { 1.4, 1.3, 1.3 }, { 0, 3.3, 0.1 }, m, a),
			P("wedge", { 0.4, 0.8, 0.5 }, { -0.45, 4.1, 0.1 }, m, a, SMALL),
			P("wedge", { 0.4, 0.8, 0.5 }, { 0.45, 4.1, 0.1 }, m, a, SMALL),
		}
	end,
	lion = function(a, b)
		return {
			P("block", { 2, 1, 2.6 }, { 0, 0.5, 0 }, "Slate", b),
			P("block", { 1.4, 1.6, 2 }, { 0, 1.8, 0.2 }, "Slate", a),
			P("ball", { 1.8, 1.8, 1.4 }, { 0, 3, -0.6 }, "Slate", a),
			P("ball", { 0.7, 0.7, 0.7 }, { 0.5, 1.4, -1 }, "Slate", a, SMALL),
		}
	end,
	obelisk = function(a, b)
		return {
			P("block", { 2, 0.6, 2 }, { 0, 0.3, 0 }, "Marble", STONE),
			P("block", { 1, 4, 1 }, { 0, 2.6, 0 }, "Marble", a),
			P("ball", { 0.7, 0.7, 0.7 }, { 0, 4.9, 0 }, "Neon", b, GLOW),
		}
	end,
	windmill = function(a, b)
		return {
			P("cyl", { 2.6, 5, 2.6 }, { 0, 2.5, 0 }, "WoodPlanks", a),
			P("cyl", { 3, 0.6, 3 }, { 0, 5.3, 0 }, "Slate", b),
			P("cyl", { 0.6, 0.4, 0.6 }, { 0, 4.4, -1.4 }, "Wood", WOOD_DARK, { rot = { 90, 0, 0 } }),
			P("block", { 0.5, 7, 0.1 }, { 0, 4.4, -1.65 }, "WoodPlanks", "#F2E6CF", { rot = { 0, 0, 20 } }),
			P("block", { 0.5, 7, 0.1 }, { 0, 4.4, -1.65 }, "WoodPlanks", "#F2E6CF", { rot = { 0, 0, 110 } }),
			P("block", { 0.9, 1.4, 0.1 }, { 0, 0.7, -1.3 }, "Wood", WOOD_DARK, SMALL),
		}
	end,
	swing = function(a, b)
		return {
			P("block", { 0.4, 4, 0.4 }, { -2.6, 2, 0 }, "Wood", b),
			P("block", { 0.4, 4, 0.4 }, { 2.6, 2, 0 }, "Wood", b),
			P("block", { 5.6, 0.3, 0.3 }, { 0, 4, 0 }, "Wood", b),
			P("block", { 0.08, 2.6, 0.08 }, { -0.6, 2.7, 0 }, "Fabric", "#D8C8A8", SMALL),
			P("block", { 0.08, 2.6, 0.08 }, { 0.6, 2.7, 0 }, "Fabric", "#D8C8A8", SMALL),
			P("block", { 1.6, 0.2, 0.6 }, { 0, 1.35, 0 }, "SmoothPlastic", a),
		}
	end,
	tower = function(a, b)
		local parts = {
			P("block", { 3.4, 0.3, 3.4 }, { 0, 1.8, 0 }, "WoodPlanks", a),
			P("block", { 3.4, 0.3, 3.4 }, { 0, 3.8, 0 }, "WoodPlanks", a),
			P("cyl", { 0.6, 1.8, 0.6 }, { 0, 2.8, 0 }, "Fabric", "#D8C8A8", SMALL),
		}
		for _, c in { { -1.5, -1.5 }, { 1.5, -1.5 }, { -1.5, 1.5 }, { 1.5, 1.5 } } do
			table.insert(parts, P("block", { 0.3, 4, 0.3 }, { c[1], 2, c[2] }, "Wood", b))
		end
		return parts
	end,
	seesaw = function(a, b)
		return {
			P("wedge", { 0.8, 1, 1 }, { 0, 0.5, 0 }, "Metal", b),
			P("block", { 6, 0.2, 0.8 }, { 0, 1.05, 0 }, "WoodPlanks", a, { rot = { 0, 0, 8 } }),
			P("block", { 0.8, 0.5, 0.7 }, { -2.6, 0.85, 0 }, "SmoothPlastic", b, SMALL),
			P("block", { 0.8, 0.5, 0.7 }, { 2.6, 1.55, 0 }, "SmoothPlastic", b, SMALL),
		}
	end,
	slide = function(a, b)
		return {
			P("block", { 2, 0.3, 2 }, { 0, 3, -1.8 }, "WoodPlanks", b),
			P("block", { 0.3, 3, 0.3 }, { -0.8, 1.5, -2.6 }, "Wood", b),
			P("block", { 0.3, 3, 0.3 }, { 0.8, 1.5, -2.6 }, "Wood", b),
			P("wedge", { 1.6, 3, 3.8 }, { 0, 1.5, 0.9 }, "SmoothPlastic", a, { rot = { 0, 180, 0 } }),
			P("block", { 1.6, 0.2, 0.2 }, { 0, 1, -2.6 }, "Wood", b, SMALL),
		}
	end,
	tireswing = function(a, b)
		return {
			P("block", { 0.4, 5, 0.4 }, { 0, 2.5, -1.2 }, "Wood", b),
			P("block", { 0.3, 0.3, 2.6 }, { 0, 5, 0 }, "Wood", b),
			P("block", { 0.08, 2.4, 0.08 }, { 0, 3.8, 1.1 }, "Fabric", "#D8C8A8", SMALL),
			P("cyl", { 1.6, 0.5, 1.6 }, { 0, 2, 1.1 }, "Fabric", a, { rot = { 90, 0, 0 } }),
		}
	end,
	log = function(a, b)
		return {
			P("cyl", { 1.2, 3.4, 1.2 }, { 0, 0.6, 0 }, "Wood", a, { rot = { 0, 0, 90 } }),
			P("cyl", { 1, 0.1, 1 }, { 1.72, 0.6, 0 }, "Wood", b, { rot = { 0, 0, 90 }, small = true }),
		}
	end,
	bouncy = function(a, b)
		return {
			P("cyl", { 0.8, 1.2, 0.8 }, { 0, 0.6, 0 }, "SmoothPlastic", "#F4EBD9"),
			P("ball", { 3, 1.4, 3 }, { 0, 1.6, 0 }, "SmoothPlastic", a),
			P("ball", { 0.5, 0.3, 0.5 }, { 0.7, 2.25, 0.4 }, "SmoothPlastic", b, SMALL),
			P("ball", { 0.5, 0.3, 0.5 }, { -0.6, 2.2, -0.5 }, "SmoothPlastic", b, SMALL),
		}
	end,
	sandbox = function(a, b)
		return {
			P("block", { 3.4, 0.5, 3.4 }, { 0, 0.25, 0 }, "Sand", a),
			P("block", { 4, 0.6, 0.3 }, { 0, 0.3, -1.85 }, "WoodPlanks", b),
			P("block", { 4, 0.6, 0.3 }, { 0, 0.3, 1.85 }, "WoodPlanks", b),
			P("block", { 0.3, 0.6, 3.4 }, { -1.85, 0.3, 0 }, "WoodPlanks", b),
			P("block", { 0.3, 0.6, 3.4 }, { 1.85, 0.3, 0 }, "WoodPlanks", b),
			P("cyl", { 0.6, 0.6, 0.6 }, { 0.8, 0.8, 0.6 }, "SmoothPlastic", "#E5484D", SMALL),
		}
	end,
	ball = function(a, b)
		return {
			P("ball", { 1.8, 1.8, 1.8 }, { 0, 0.9, 0 }, "SmoothPlastic", a),
			P("cyl", { 1.85, 0.35, 1.85 }, { 0, 0.9, 0 }, "SmoothPlastic", b, SMALL),
		}
	end,
	yarn = function(a, b)
		return {
			P("ball", { 1.2, 1.2, 1.2 }, { 0, 0.6, 0 }, "Fabric", a),
			P("block", { 1.2, 0.08, 0.08 }, { 0.9, 0.05, 0.3 }, "Fabric", b, SMALL),
		}
	end,
	ring = function(a, b)
		return {
			P("ball", { 2.2, 0.6, 2.2 }, { 0, 0.3, 0 }, "SmoothPlastic", a),
			P("cyl", { 1, 0.62, 1 }, { 0, 0.3, 0 }, "SmoothPlastic", b),
		}
	end,
	snowman = function(a, b)
		return {
			P("ball", { 3, 2.8, 3 }, { 0, 1.4, 0 }, "Snow", a),
			P("ball", { 2.2, 2, 2.2 }, { 0, 3.3, 0 }, "Snow", a),
			P("ball", { 1.5, 1.4, 1.5 }, { 0, 4.8, 0 }, "Snow", a),
			P("wedge", { 0.25, 0.25, 0.8 }, { 0, 4.8, -0.9 }, "SmoothPlastic", "#F08A4B", { rot = { 0, 180, 0 }, small = true }),
			P("cyl", { 1.1, 0.8, 1.1 }, { 0, 5.8, 0 }, "SmoothPlastic", b),
		}
	end,
	sled = function(a, b)
		return {
			P("block", { 3, 0.2, 1.4 }, { 0, 0.6, 0 }, "WoodPlanks", a),
			P("block", { 3.2, 0.15, 0.15 }, { 0, 0.2, -0.6 }, "Metal", b),
			P("block", { 3.2, 0.15, 0.15 }, { 0, 0.2, 0.6 }, "Metal", b),
			P("block", { 0.2, 0.4, 1.2 }, { -1, 0.4, 0 }, "Wood", a, SMALL),
			P("block", { 0.2, 0.4, 1.2 }, { 1, 0.4, 0 }, "Wood", a, SMALL),
		}
	end,
	basket = function(a, b)
		return {
			P("cyl", { 1.8, 1, 1.8 }, { 0, 0.5, 0 }, "Fabric", a),
			P("block", { 0.15, 1.4, 1.8 }, { 0, 1.3, 0 }, "Fabric", a, SMALL),
			P("ball", { 0.55, 0.7, 0.55 }, { -0.4, 1.1, 0.2 }, "SmoothPlastic", b),
			P("ball", { 0.55, 0.7, 0.55 }, { 0.4, 1.1, -0.2 }, "SmoothPlastic", "#8FE3FF", SMALL),
			P("ball", { 0.55, 0.7, 0.55 }, { 0.1, 1.15, 0.45 }, "SmoothPlastic", "#FFD447", SMALL),
		}
	end,
	topiary = function(a, b)
		return {
			P("cyl", { 1.6, 1, 1.6 }, { 0, 0.5, 0 }, "Brick", b),
			P("ball", { 2.2, 2, 1.8 }, { 0, 2, 0 }, "LeafyGrass", a),
			P("ball", { 1.4, 1.4, 1.4 }, { 0, 3.5, -0.2 }, "LeafyGrass", a),
			P("block", { 0.4, 1.4, 0.3 }, { -0.35, 4.6, -0.2 }, "LeafyGrass", a),
			P("block", { 0.4, 1.4, 0.3 }, { 0.35, 4.6, -0.2 }, "LeafyGrass", a),
			P("ball", { 0.6, 0.6, 0.6 }, { 0, 1.8, 1 }, "SmoothPlastic", "#FFFFFF", SMALL),
		}
	end,
	kite = function(a, b)
		return {
			P("cyl", { 0.2, 5, 0.2 }, { 0, 2.5, 0 }, "Wood", WOOD_DARK),
			P("block", { 2, 2, 0.1 }, { 0, 5.4, 0 }, "Fabric", a, { rot = { 0, 0, 45 } }),
			P("block", { 0.4, 0.3, 0.05 }, { 0.3, 3.9, 0 }, "Fabric", b, SMALL),
			P("block", { 0.4, 0.3, 0.05 }, { 0.5, 3.3, 0 }, "Fabric", b, SMALL),
		}
	end,
	chair = function(a, b)
		local parts = {
			P("block", { 1.6, 0.2, 1.4 }, { 0, 2.6, 0 }, "WoodPlanks", a),
			P("block", { 1.6, 1.4, 0.2 }, { 0, 3.3, 0.6 }, "WoodPlanks", a),
			P("block", { 1.8, 0.4, 1.6 }, { 0, 4.6, 0.4 }, "Fabric", b, SMALL),
		}
		for _, c in { { -0.7, -0.6 }, { 0.7, -0.6 }, { -0.7, 0.6 }, { 0.7, 0.6 } } do
			table.insert(parts, P("block", { 0.25, 2.6, 0.25 }, { c[1], 1.3, c[2] }, "WoodPlanks", a))
		end
		return parts
	end,
	rack = function(a, b)
		return {
			P("block", { 3.4, 0.3, 0.6 }, { 0, 2, 0 }, "Wood", WOOD_DARK),
			P("block", { 0.3, 2.2, 0.6 }, { -1.6, 1.1, 0 }, "Wood", WOOD_DARK),
			P("block", { 0.3, 2.2, 0.6 }, { 1.6, 1.1, 0 }, "Wood", WOOD_DARK),
			P("block", { 0.25, 3.4, 1 }, { -0.8, 1.7, 0.3 }, "SmoothPlastic", a, { rot = { 0, 0, 8 } }),
			P("block", { 0.25, 3.4, 1 }, { 0, 1.7, 0.3 }, "SmoothPlastic", b, { rot = { 0, 0, 8 } }),
			P("block", { 0.25, 3.4, 1 }, { 0.8, 1.7, 0.3 }, "SmoothPlastic", a, { rot = { 0, 0, 8 }, small = true }),
		}
	end,
	pumpkins = function(a, b)
		local parts = {}
		for i, s in { { 0, 0, 1.8 }, { 1.4, 0.8, 1.2 }, { -1.3, -0.6, 1.3 } } do
			table.insert(parts, P("ball", { s[3], s[3] * 0.8, s[3] }, { s[1], s[3] * 0.4, s[2] }, "SmoothPlastic", a))
			table.insert(parts, P("cyl", { 0.2, 0.4, 0.2 }, { s[1], s[3] * 0.8 + 0.1, s[2] }, "Grass", b, if i > 1 then SMALL else nil))
		end
		return parts
	end,
	jack = function(a, b)
		return {
			P("ball", { 2.4, 2, 2.4 }, { 0, 1, 0 }, "SmoothPlastic", a),
			P("cyl", { 0.3, 0.5, 0.3 }, { 0, 2.1, 0 }, "Grass", "#3E7A2E"),
			P("block", { 0.4, 0.4, 0.1 }, { -0.45, 1.3, -1.12 }, "Neon", b, GLOW),
			P("block", { 0.4, 0.4, 0.1 }, { 0.45, 1.3, -1.12 }, "Neon", b, SMALL),
		}
	end,
	scarecrow = function(a, b)
		return {
			P("block", { 0.3, 4, 0.3 }, { 0, 2, 0 }, "Wood", WOOD_DARK),
			P("block", { 3, 0.25, 0.25 }, { 0, 3, 0 }, "Wood", WOOD_DARK),
			P("block", { 1.2, 1.4, 0.6 }, { 0, 2.8, 0 }, "Fabric", a),
			P("ball", { 1, 1, 1 }, { 0, 4, 0 }, "Fabric", b),
			P("cyl", { 1.5, 0.15, 1.5 }, { 0, 4.45, 0 }, "Fabric", "#5A3A1E", SMALL),
			P("cyl", { 0.8, 0.6, 0.8 }, { 0, 4.75, 0 }, "Fabric", "#5A3A1E", SMALL),
		}
	end,
	haystack = function(a, b)
		return {
			P("cyl", { 3, 1.4, 3 }, { 0, 0.7, 0 }, "Grass", a),
			P("ball", { 2.6, 1.4, 2.6 }, { 0, 1.4, 0 }, "Grass", b),
		}
	end,
	tub = function(a, b)
		return {
			P("cyl", { 2.2, 1, 2.2 }, { 0, 0.5, 0 }, "WoodPlanks", a),
			P("cyl", { 1.9, 0.05, 1.9 }, { 0, 0.95, 0 }, "Glass", "#4FB6F2", { alpha = 0.3 }),
			P("ball", { 0.5, 0.5, 0.5 }, { -0.4, 1, 0.2 }, "SmoothPlastic", b),
			P("ball", { 0.5, 0.5, 0.5 }, { 0.4, 1, -0.3 }, "SmoothPlastic", b, SMALL),
		}
	end,
	post = function(a, b)
		return {
			P("block", { 2, 0.4, 2 }, { 0, 0.2, 0 }, "WoodPlanks", a),
			P("cyl", { 0.7, 3.4, 0.7 }, { 0, 2.1, 0 }, "Fabric", b),
			P("block", { 1.4, 0.3, 1.4 }, { 0, 3.9, 0 }, "WoodPlanks", a),
			P("ball", { 0.5, 0.5, 0.5 }, { 0.6, 3.2, 0 }, "Fabric", "#E5484D", SMALL),
		}
	end,
	bale = function(a, b)
		return {
			P("block", { 3, 2, 2 }, { 0, 1, 0 }, "Grass", a),
			P("block", { 0.2, 2.05, 2.05 }, { -0.7, 1, 0 }, "Fabric", b, SMALL),
			P("block", { 0.2, 2.05, 2.05 }, { 0.7, 1, 0 }, "Fabric", b, SMALL),
		}
	end,
	trough = function(a, b)
		return {
			P("block", { 3.6, 1, 1.6 }, { 0, 0.5, 0 }, "WoodPlanks", b),
			P("block", { 3.2, 0.1, 1.2 }, { 0, 0.98, 0 }, "Glass", a, { alpha = 0.25 }),
		}
	end,
	globe = function(a, b)
		return {
			P("cyl", { 2, 0.6, 2 }, { 0, 0.3, 0 }, "Wood", b),
			P("ball", { 2.2, 2.2, 2.2 }, { 0, 1.7, 0 }, "Glass", a, { alpha = 0.45 }),
			P("ball", { 0.8, 0.8, 0.8 }, { 0, 1.2, 0 }, "Snow", "#FFFFFF", SMALL),
		}
	end,
	crystal = function(a, b)
		return {
			P("block", { 0.9, 3, 0.9 }, { 0, 1.5, 0 }, "Glass", a, { rot = { 0, 20, 8 } }),
			P("block", { 0.7, 2, 0.7 }, { 0.8, 1, 0.3 }, "Glass", a, { rot = { 0, 40, -18 } }),
			P("block", { 0.6, 1.6, 0.6 }, { -0.7, 0.8, -0.3 }, "Neon", b, { rot = { 0, 10, 16 }, glow = true }),
		}
	end,
	gifts = function(a, b)
		return {
			P("block", { 1.8, 1.4, 1.8 }, { 0, 0.7, 0 }, "SmoothPlastic", a),
			P("block", { 1.2, 1, 1.2 }, { 1.3, 0.5, 0.6 }, "SmoothPlastic", b),
			P("block", { 1, 0.8, 1 }, { 0.1, 1.8, 0.1 }, "SmoothPlastic", b, SMALL),
			P("block", { 0.3, 1.45, 1.85 }, { 0, 0.7, 0 }, "SmoothPlastic", "#FFD447", SMALL),
		}
	end,
	umbrella = function(a, b)
		return {
			P("cyl", { 0.2, 4.5, 0.2 }, { 0, 2.25, 0 }, "Metal", "#EDE3D3"),
			P("cyl", { 4.5, 0.3, 4.5 }, { 0, 4.4, 0 }, "Fabric", a),
			P("ball", { 0.4, 0.4, 0.4 }, { 0, 4.7, 0 }, "SmoothPlastic", b, SMALL),
			P("block", { 2, 0.06, 1 }, { 1, 0.03, 1 }, "Fabric", b, SMALL),
		}
	end,
	castle = function(a, b)
		local parts = { P("block", { 2.6, 1, 2.6 }, { 0, 0.5, 0 }, "Sand", a), P("block", { 1.2, 1.8, 1.2 }, { 0, 1.9, 0 }, "Sand", a) }
		for _, c in { { -1.1, -1.1 }, { 1.1, -1.1 }, { -1.1, 1.1 }, { 1.1, 1.1 } } do
			table.insert(parts, P("cyl", { 0.7, 1.8, 0.7 }, { c[1], 0.9, c[2] }, "Sand", b))
		end
		return parts
	end,
	shells = function(a, b)
		return {
			P("ball", { 0.9, 0.45, 0.7 }, { 0, 0.22, 0 }, "SmoothPlastic", a),
			P("ball", { 0.7, 0.35, 0.6 }, { 0.8, 0.18, 0.4 }, "SmoothPlastic", b),
			P("ball", { 0.8, 0.4, 0.6 }, { -0.7, 0.2, 0.5 }, "SmoothPlastic", a, SMALL),
			P("ball", { 0.6, 0.3, 0.5 }, { 0.2, 0.15, -0.7 }, "SmoothPlastic", b, SMALL),
		}
	end,
}

-- The parts of one piece (a fresh table; callers may keep it).
function Art.Pieces(def): { any }
	local build = Art.Models[def.model] or Art.Models.crate
	return build(def.color or "#C9A26B", def.color2 or STONE, def)
end

return Art
