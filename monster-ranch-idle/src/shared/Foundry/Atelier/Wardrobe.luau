--!strict
-- The part-built wardrobe: every outfit piece, hair style and accessory as data, attached to
-- the R15 body's parts. Zero uploads: a piece is a few Parts (Block, Ball = a sphere-mesh
-- ellipsoid, Cylinder along x, Wedge) welded to the part it names.
--
-- A piece: { id, slot, tier, parts, hair?, tint?, tags? }
--   slot   head | torso | legs | feet | back | hands | accessory | hair
--   tier   1 plain (undyed, cheap) .. 3 costly; a genome's wealth bounds the tiers it may wear
--   hair   head pieces: how much hair shows, "all" (default) | "back" | "none"
--   tint   repaints body groups: { torso | sleeve | legs | feet | hands = colour slot }
--   parts  { name, attach (an R15 part), shape, size {x,y,z}, offset {x,y,z} from the attach
--            part's centre, rot? {x,y,z} degrees (CFrame.Angles order), color = a COLOUR SLOT
--            (never a hex: a slot is resolved through the genome's palette and the game's lock),
--            material?, transparency?, minQuality? "medium" | "high", back? (hair only) }
-- Numbers are chibi template units (Bodies.templates.chibi); a body scales every part by its
-- attach part's size ratio, so the same piece fits every build and template.

local Wardrobe = {}

Wardrobe.SLOTS = { "head", "torso", "legs", "feet", "back", "hands" }
Wardrobe.COLOUR_SLOTS = {
	"skin",
	"hair",
	"shirt",
	"trousers",
	"boots",
	"primary",
	"secondary",
	"accent",
	"trim",
	"leather",
	"metal",
	"natural",
	"eye",
	"mouth",
	"blush",
	"glint",
}
Wardrobe.SHAPES = { Block = true, Ball = true, Cylinder = true, Wedge = true }
Wardrobe.MATERIALS = { SmoothPlastic = true, Metal = true, Neon = true, Fabric = true, Wood = true }
Wardrobe.TINT_GROUPS = { torso = true, sleeve = true, legs = true, feet = true, hands = true }

local function P(name: string, attach: string, shape: string, size: { number }, offset: { number }, color: string, extra: any?): any
	local part: any = { name = name, attach = attach, shape = shape, size = size, offset = offset, color = color }
	if extra then
		for k, v in extra do
			part[k] = v
		end
	end
	return part
end

-- Mirror a part to the other side (x offsets and z/y rotations flip).
local function both(name: string, attachR: string, shape: string, size: { number }, offset: { number }, color: string, extra: any?): (any, any)
	local r = P(name .. "R", attachR, shape, size, offset, color, extra)
	local le = P(name .. "L", (string.gsub(attachR, "^Right", "Left")), shape, size, { -offset[1], offset[2], offset[3] }, color, extra)
	if extra and extra.rot then
		le.rot = { extra.rot[1], -extra.rot[2], -extra.rot[3] }
	end
	return r, le
end

local MED = { minQuality = "medium" }
local HIGH = { minQuality = "high" }
local METAL = { material = "Metal" }
local function with(a: any, b: any): any
	local o = table.clone(a)
	for k, v in b do
		o[k] = v
	end
	return o
end

local pieces: { any } = {}
local function piece(id: string, slot: string, tier: number, parts: { any }, extra: any?)
	local p: any = { id = id, slot = slot, tier = tier, parts = parts }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	table.insert(pieces, p)
end

-- head ----------------------------------------------------------------------------------------
local BRIM = { rot = { 0, 0, 90 } }
piece("straw_hat", "head", 1, {
	P("HatBrim", "Head", "Cylinder", { 0.14, 3.3, 3.3 }, { 0, 0.85, 0 }, "natural", BRIM),
	P("HatCrown", "Head", "Ball", { 2.0, 1.1, 2.0 }, { 0, 1.1, 0 }, "natural"),
})
piece("flat_cap", "head", 1, {
	P("Cap", "Head", "Ball", { 2.46, 1.2, 2.3 }, { 0, 0.7, 0.05 }, "primary"),
	P("CapPeak", "Head", "Block", { 1.4, 0.12, 0.8 }, { 0, 0.6, -1.15 }, "primary"),
})
piece("kerchief", "head", 1, {
	P("Kerchief", "Head", "Ball", { 2.46, 1.5, 2.3 }, { 0, 0.5, 0.18 }, "accent"),
	P("KerchiefKnot", "Head", "Ball", { 0.45, 0.32, 0.3 }, { 0, 0.3, 1.2 }, "accent", MED),
})
piece("beret", "head", 2, {
	P("Beret", "Head", "Ball", { 2.3, 0.7, 2.2 }, { 0.15, 1.05, 0.05 }, "primary", { rot = { 0, 0, -10 } }),
	P("BeretStalk", "Head", "Block", { 0.1, 0.22, 0.1 }, { 0.2, 1.45, 0.05 }, "primary", HIGH),
})
piece("hood", "head", 1, {
	P("Hood", "Head", "Ball", { 2.55, 2.35, 2.3 }, { 0, 0.22, 0.3 }, "primary"),
}, { hair = "none" })
piece("pointed_hat", "head", 2, {
	P("HatBrim", "Head", "Cylinder", { 0.14, 3.2, 3.2 }, { 0, 0.95, 0 }, "primary", BRIM),
	P("HatCone1", "Head", "Cylinder", { 0.8, 1.9, 1.9 }, { 0, 1.4, 0 }, "primary", BRIM),
	P("HatCone2", "Head", "Cylinder", { 0.7, 1.25, 1.25 }, { 0, 2.1, 0.08 }, "primary", BRIM),
	P("HatTip", "Head", "Cylinder", { 0.6, 0.6, 0.6 }, { 0, 2.65, 0.3 }, "primary", { rot = { 0, 0, 70 } }),
	P("HatBand", "Head", "Cylinder", { 0.2, 1.95, 1.95 }, { 0, 1.1, 0 }, "trim", with(BRIM, MED)),
})
piece("wide_hat", "head", 2, {
	P("HatBrim", "Head", "Cylinder", { 0.14, 3.8, 3.8 }, { 0, 0.9, 0 }, "primary", BRIM),
	P("HatCone1", "Head", "Cylinder", { 0.9, 1.8, 1.8 }, { 0, 1.35, 0.05 }, "primary", BRIM),
	P("HatTip", "Head", "Cylinder", { 0.9, 0.9, 0.9 }, { 0.25, 2.0, 0.3 }, "primary", { rot = { 0, 0, 55 } }),
	P("HatBand", "Head", "Cylinder", { 0.22, 1.85, 1.85 }, { 0, 1.02, 0.05 }, "trim", with(BRIM, MED)),
})
piece("circlet", "head", 3, {
	P("Circlet", "Head", "Cylinder", { 0.14, 2.34, 2.34 }, { 0, 0.38, 0.02 }, "trim", with(BRIM, METAL)),
	P("CircletGem", "Head", "Ball", { 0.26, 0.26, 0.12 }, { 0, 0.4, -1.12 }, "accent", { material = "Neon" }),
})
piece("kettle_helm", "head", 2, {
	P("HelmBrim", "Head", "Cylinder", { 0.18, 3.0, 3.0 }, { 0, 0.55, 0 }, "metal", with(BRIM, METAL)),
	P("Helm", "Head", "Ball", { 2.4, 1.3, 2.2 }, { 0, 0.72, 0.05 }, "metal", METAL),
}, { hair = "back" })
piece("nasal_helm", "head", 2, {
	P("Helm", "Head", "Ball", { 2.46, 1.5, 2.3 }, { 0, 0.55, 0.05 }, "metal", METAL),
	P("NoseGuard", "Head", "Block", { 0.16, 0.62, 0.1 }, { 0, 0.02, -1.08 }, "metal", METAL),
}, { hair = "back" })
piece("mail_coif", "head", 2, {
	P("Coif", "Head", "Ball", { 2.5, 2.3, 2.3 }, { 0, 0.26, 0.16 }, "metal", METAL),
}, { hair = "none" })
piece("crested_helm", "head", 3, {
	P("Helm", "Head", "Ball", { 2.5, 1.45, 2.32 }, { 0, 0.55, 0.05 }, "metal", METAL),
	P("HelmCrest", "Head", "Block", { 0.24, 0.55, 1.7 }, { 0, 1.3, 0.05 }, "primary"),
}, { hair = "back" })
piece("feather_cap", "head", 2, {
	P("Cap", "Head", "Ball", { 2.46, 1.1, 2.3 }, { 0, 0.78, 0.05 }, "primary"),
	P("CapPeak", "Head", "Block", { 1.6, 0.1, 0.8 }, { 0, 0.62, -1.05 }, "primary", { rot = { -8, 0, 0 } }),
	P("Feather", "Head", "Block", { 0.12, 1.1, 0.3 }, { 0.8, 1.35, 0.3 }, "accent", { rot = { -30, 0, -25 }, minQuality = "medium" }),
})
piece("headband", "head", 1, {
	P("Headband", "Head", "Cylinder", { 0.22, 2.3, 2.3 }, { 0, 0.35, 0.02 }, "accent", BRIM),
	P("BandTail", "Head", "Block", { 0.12, 0.7, 0.22 }, { 0.3, 0.02, 1.12 }, "accent", { rot = { 15, 0, -10 }, minQuality = "medium" }),
})
piece("bandana", "head", 1, {
	P("Bandana", "Head", "Ball", { 2.46, 1.3, 2.3 }, { 0, 0.62, 0.12 }, "accent"),
	P("BandanaTail", "Head", "Block", { 0.16, 0.6, 0.3 }, { 0.1, 0.15, 1.18 }, "accent", { rot = { 12, 0, -8 }, minQuality = "medium" }),
}, { hair = "back" })
piece("mitre", "head", 3, {
	P("Mitre", "Head", "Block", { 1.3, 1.5, 0.95 }, { 0, 1.55, 0 }, "primary"),
	P("MitreTop", "Head", "Ball", { 1.3, 0.8, 0.95 }, { 0, 2.3, 0 }, "primary"),
	P("MitreBand", "Head", "Block", { 0.26, 1.9, 1.0 }, { 0, 1.75, 0 }, "trim", MED),
})
piece("veil", "head", 2, {
	P("VeilBand", "Head", "Cylinder", { 0.14, 2.34, 2.34 }, { 0, 0.4, 0.02 }, "trim", BRIM),
	P("Veil", "Head", "Block", { 2.1, 1.8, 0.12 }, { 0, -0.35, 1.02 }, "secondary"),
})
piece("top_hat", "head", 3, {
	P("HatBrim", "Head", "Cylinder", { 0.12, 2.9, 2.9 }, { 0, 0.95, 0 }, "primary", BRIM),
	P("HatCrown", "Head", "Cylinder", { 1.4, 1.8, 1.8 }, { 0, 1.65, 0 }, "primary", BRIM),
	P("HatBand", "Head", "Cylinder", { 0.22, 1.84, 1.84 }, { 0, 1.1, 0 }, "trim", with(BRIM, MED)),
})
piece("chef_toque", "head", 1, {
	P("ToqueBand", "Head", "Cylinder", { 0.4, 2.2, 2.2 }, { 0, 0.95, 0 }, "natural", BRIM),
	P("ToquePuff", "Head", "Ball", { 2.2, 1.3, 2.2 }, { 0, 1.65, 0 }, "natural"),
})
piece("miner_helmet", "head", 2, {
	P("Helmet", "Head", "Ball", { 2.4, 1.25, 2.25 }, { 0, 0.72, 0.05 }, "accent"),
	P("HelmetLamp", "Head", "Cylinder", { 0.22, 0.45, 0.45 }, { 0, 0.85, -1.1 }, "metal", { rot = { 0, 90, 0 }, material = "Metal" }),
	P("LampGlow", "Head", "Ball", { 0.32, 0.32, 0.1 }, { 0, 0.85, -1.22 }, "glint", { material = "Neon", minQuality = "high" }),
}, { hair = "back" })
piece("crown", "head", 3, {
	P("CrownBand", "Head", "Cylinder", { 0.45, 2.1, 2.1 }, { 0, 1.15, 0 }, "trim", with(BRIM, METAL)),
	P("CrownPointF", "Head", "Wedge", { 0.3, 0.45, 0.3 }, { 0, 1.55, -0.9 }, "trim", METAL),
	P("CrownPointR", "Head", "Wedge", { 0.3, 0.45, 0.3 }, { 0.8, 1.55, -0.45 }, "trim", { material = "Metal", rot = { 0, -60, 0 }, minQuality = "medium" }),
	P("CrownPointL", "Head", "Wedge", { 0.3, 0.45, 0.3 }, { -0.8, 1.55, -0.45 }, "trim", { material = "Metal", rot = { 0, 60, 0 }, minQuality = "medium" }),
	P("CrownGem", "Head", "Ball", { 0.24, 0.24, 0.1 }, { 0, 1.15, -1.06 }, "accent", HIGH),
})
piece("flower_crown", "head", 1, {
	P("Wreath", "Head", "Cylinder", { 0.18, 2.34, 2.34 }, { 0, 0.62, 0 }, "secondary", BRIM),
	P("FlowerA", "Head", "Ball", { 0.36, 0.36, 0.2 }, { 0.55, 0.7, -1.0 }, "accent"),
	P("FlowerB", "Head", "Ball", { 0.36, 0.36, 0.2 }, { -0.6, 0.7, -0.98 }, "accent", MED),
	P("FlowerC", "Head", "Ball", { 0.32, 0.32, 0.2 }, { 1.12, 0.7, -0.2 }, "trim", HIGH),
})
piece("ranch_hat", "head", 1, {
	P("HatBrim", "Head", "Ball", { 3.6, 0.26, 3.2 }, { 0, 0.85, 0 }, "leather"),
	P("HatCrown", "Head", "Ball", { 2.0, 1.15, 1.9 }, { 0, 1.3, 0 }, "leather"),
	P("HatBand", "Head", "Cylinder", { 0.18, 2.02, 1.92 }, { 0, 1.05, 0 }, "accent", with(BRIM, MED)),
})
piece("bucket_hat", "head", 1, {
	P("HatBrim", "Head", "Ball", { 3.0, 0.3, 3.0 }, { 0, 0.8, 0 }, "natural"),
	P("HatCrown", "Head", "Ball", { 2.3, 1.0, 2.2 }, { 0, 1.05, 0 }, "natural"),
})
piece("nightcap", "head", 1, {
	P("Nightcap", "Head", "Ball", { 2.4, 1.2, 2.25 }, { 0, 0.75, 0.05 }, "primary"),
	P("NightcapTail", "Head", "Ball", { 0.6, 1.2, 0.6 }, { 0.6, 1.3, 0.6 }, "primary", { rot = { 0, 0, -40 } }),
	P("NightcapPom", "Head", "Ball", { 0.4, 0.4, 0.4 }, { 1.1, 1.6, 0.9 }, "natural", HIGH),
})

-- torso ---------------------------------------------------------------------------------------
piece("apron", "torso", 1, {
	P("Apron", "UpperTorso", "Block", { 1.6, 1.7, 0.1 }, { 0, -0.6, -0.57 }, "natural"),
})
piece("smith_apron", "torso", 1, {
	P("SmithApron", "UpperTorso", "Block", { 1.7, 2.1, 0.12 }, { 0, -0.75, -0.58 }, "leather"),
	P("ApronStrap", "UpperTorso", "Block", { 1.9, 0.12, 1.1 }, { 0, 0.45, 0 }, "leather"),
	P("ApronPocket", "UpperTorso", "Block", { 0.6, 0.35, 0.05 }, { 0, -0.9, -0.66 }, "trim", MED),
})
piece("vest", "torso", 2, {
	P("VestR", "UpperTorso", "Block", { 0.72, 1.16, 1.1 }, { 0.58, 0, 0 }, "secondary"),
	P("VestL", "UpperTorso", "Block", { 0.72, 1.16, 1.1 }, { -0.58, 0, 0 }, "secondary"),
	P("VestButton", "UpperTorso", "Ball", { 0.12, 0.12, 0.06 }, { 0.26, -0.2, -0.57 }, "trim", HIGH),
})
piece("tabard", "torso", 2, {
	P("Tabard", "UpperTorso", "Block", { 0.7, 1.9, 0.08 }, { 0, -0.5, -0.57 }, "primary"),
	P("TabardSign", "UpperTorso", "Block", { 0.42, 0.42, 0.06 }, { 0, 0.05, -0.62 }, "trim", { rot = { 0, 0, 45 }, minQuality = "medium" }),
})
piece("robe", "torso", 2, {
	P("Robe", "UpperTorso", "Block", { 1.95, 1.25, 1.12 }, { 0, 0, 0 }, "primary"),
	P("RobeSkirt", "LowerTorso", "Block", { 1.95, 1.3, 1.2 }, { 0, -0.62, 0 }, "primary"),
	P("RobeTrim", "UpperTorso", "Block", { 0.2, 1.26, 0.05 }, { 0, 0, -0.58 }, "trim", MED),
}, { tint = { sleeve = "primary" } })
piece("mantle", "torso", 3, {
	P("Mantle", "UpperTorso", "Block", { 2.1, 0.36, 1.2 }, { 0, 0.52, 0.04 }, "primary"),
	P("PauldronR", "RightUpperArm", "Ball", { 0.86, 0.58, 0.86 }, { 0, 0.3, 0 }, "primary"),
	P("PauldronL", "LeftUpperArm", "Ball", { 0.86, 0.58, 0.86 }, { 0, 0.3, 0 }, "primary"),
})
piece("breastplate", "torso", 3, {
	P("Breastplate", "UpperTorso", "Block", { 1.95, 1.1, 1.12 }, { 0, 0.02, 0 }, "metal", METAL),
	P("PlateRidge", "UpperTorso", "Block", { 0.12, 1.0, 0.1 }, { 0, 0, -0.58 }, "metal", with(METAL, MED)),
})
piece("mail_shirt", "torso", 2, {
	P("MailShirt", "UpperTorso", "Block", { 1.95, 1.3, 1.12 }, { 0, -0.05, 0 }, "metal", METAL),
	P("MailHem", "LowerTorso", "Block", { 1.9, 0.42, 1.12 }, { 0, -0.1, 0 }, "metal", METAL),
})
piece("bodice", "torso", 2, {
	P("Bodice", "UpperTorso", "Block", { 1.9, 0.8, 1.1 }, { 0, -0.2, 0 }, "secondary"),
	P("BodiceLace", "UpperTorso", "Block", { 0.1, 0.7, 0.05 }, { 0, -0.2, -0.58 }, "trim", HIGH),
})
piece("sash", "torso", 2, {
	P("Sash", "UpperTorso", "Block", { 0.35, 1.6, 1.1 }, { 0, 0, 0 }, "accent", { rot = { 0, 0, 35 } }),
})
piece("shawl", "torso", 1, {
	P("Shawl", "UpperTorso", "Ball", { 2.3, 0.7, 1.4 }, { 0, 0.45, 0.05 }, "secondary"),
})
piece("overalls", "torso", 1, {
	P("OverallsBib", "UpperTorso", "Block", { 1.2, 0.9, 0.08 }, { 0, -0.1, -0.56 }, "secondary"),
	P("OverallsStrapR", "UpperTorso", "Block", { 0.18, 1.22, 1.1 }, { 0.45, 0.05, 0 }, "secondary"),
	P("OverallsStrapL", "UpperTorso", "Block", { 0.18, 1.22, 1.1 }, { -0.45, 0.05, 0 }, "secondary"),
}, { tint = { legs = "secondary" } })
piece("long_coat", "torso", 3, {
	P("Coat", "UpperTorso", "Block", { 1.95, 1.25, 1.12 }, { 0, 0, 0 }, "primary"),
	P("CoatTails", "LowerTorso", "Block", { 1.9, 1.0, 0.12 }, { 0, -0.6, 0.55 }, "primary"),
	P("LapelR", "UpperTorso", "Block", { 0.3, 0.8, 0.05 }, { 0.35, 0.1, -0.58 }, "secondary", { rot = { 0, 0, -12 }, minQuality = "medium" }),
	P("LapelL", "UpperTorso", "Block", { 0.3, 0.8, 0.05 }, { -0.35, 0.1, -0.58 }, "secondary", { rot = { 0, 0, 12 }, minQuality = "medium" }),
}, { tint = { sleeve = "primary" } })
piece("fur_collar", "torso", 2, {
	P("FurCollar", "UpperTorso", "Ball", { 2.2, 0.6, 1.4 }, { 0, 0.55, 0 }, "natural"),
})
piece("jerkin", "torso", 1, {
	P("Jerkin", "UpperTorso", "Block", { 1.92, 1.22, 1.1 }, { 0, 0, 0 }, "leather"),
	P("JerkinLace", "UpperTorso", "Block", { 0.1, 0.6, 0.05 }, { 0, 0.2, -0.57 }, "trim", HIGH),
})
piece("poncho", "torso", 1, {
	P("Poncho", "UpperTorso", "Block", { 2.3, 1.1, 1.3 }, { 0, 0.05, 0 }, "primary"),
	P("PonchoStripe", "UpperTorso", "Block", { 2.32, 0.15, 1.32 }, { 0, -0.35, 0 }, "accent", MED),
})
piece("scholar_gown", "torso", 2, {
	P("Gown", "UpperTorso", "Block", { 1.95, 1.25, 1.12 }, { 0, 0, 0 }, "natural"),
	P("GownSkirt", "LowerTorso", "Block", { 1.95, 1.4, 1.2 }, { 0, -0.68, 0 }, "natural"),
}, { tint = { sleeve = "natural" } })
piece("bandolier", "torso", 1, {
	P("Bandolier", "UpperTorso", "Block", { 0.25, 1.7, 1.12 }, { 0, 0, 0 }, "leather", { rot = { 0, 0, -35 } }),
	P("BandolierPouch", "UpperTorso", "Block", { 0.3, 0.3, 0.14 }, { -0.3, -0.25, -0.6 }, "leather", MED),
})

-- legs ----------------------------------------------------------------------------------------
piece("skirt", "legs", 1, {
	P("Skirt", "LowerTorso", "Block", { 1.95, 0.9, 1.2 }, { 0, -0.45, 0 }, "secondary"),
})
piece("long_skirt", "legs", 2, {
	P("LongSkirt", "LowerTorso", "Block", { 2.0, 1.7, 1.25 }, { 0, -0.85, 0 }, "secondary"),
})
piece("kilt", "legs", 2, {
	P("Kilt", "LowerTorso", "Block", { 1.95, 0.95, 1.18 }, { 0, -0.5, 0 }, "primary"),
	P("KiltStripe", "LowerTorso", "Block", { 1.97, 0.12, 1.2 }, { 0, -0.6, 0 }, "accent", MED),
})
do
	local r1, l1 = both("Breeches", "RightUpperLeg", "Block", { 0.9, 0.95, 0.9 }, { 0, -0.02, 0 }, "trousers")
	piece("breeches", "legs", 2, { r1, l1 })
	local r2, l2 = both("Greave", "RightLowerLeg", "Block", { 0.78, 0.6, 0.78 }, { 0, 0.05, 0 }, "metal", METAL)
	piece("greaves", "legs", 3, { r2, l2 })
	local r3, l3 = both("LegWrap", "RightLowerLeg", "Block", { 0.76, 0.5, 0.76 }, { 0, 0.05, 0 }, "natural")
	piece("leg_wraps", "legs", 1, { r3, l3 })
	local r4, l4 = both("ChapUpper", "RightUpperLeg", "Block", { 0.86, 0.92, 0.86 }, { 0, 0, 0 }, "leather")
	local r5, l5 = both("ChapLower", "RightLowerLeg", "Block", { 0.78, 0.7, 0.78 }, { 0, 0, 0 }, "leather")
	piece("chaps", "legs", 2, { r4, l4, r5, l5 })
end
piece("patched_trousers", "legs", 1, {
	P("PatchKnee", "RightUpperLeg", "Block", { 0.34, 0.3, 0.05 }, { 0.05, -0.2, -0.41 }, "natural"),
	P("PatchShin", "LeftLowerLeg", "Block", { 0.3, 0.26, 0.05 }, { -0.05, 0.05, -0.37 }, "secondary", MED),
})
piece("waist_sash", "legs", 2, {
	P("WaistSash", "LowerTorso", "Block", { 1.86, 0.3, 1.12 }, { 0, 0.05, 0 }, "accent"),
	P("WaistSashTail", "LowerTorso", "Block", { 0.2, 0.6, 0.08 }, { 0.5, -0.3, -0.58 }, "accent", MED),
})
piece("tassets", "legs", 3, {
	P("Tassets", "LowerTorso", "Block", { 1.95, 0.55, 1.15 }, { 0, -0.3, 0 }, "metal", METAL),
})

-- feet ----------------------------------------------------------------------------------------
do
	local r1, l1 = both("BootShaft", "RightLowerLeg", "Block", { 0.8, 0.55, 0.8 }, { 0, -0.1, 0 }, "boots")
	piece("tall_boots", "feet", 2, { r1, l1 })
	local r2, l2 = both("SandalStrap", "RightFoot", "Block", { 0.86, 0.08, 0.6 }, { 0, 0.1, -0.1 }, "leather")
	piece("sandals", "feet", 1, { r2, l2 }, { tint = { feet = "skin" } })
	local r3, l3 = both("Clog", "RightFoot", "Block", { 0.88, 0.36, 1.16 }, { 0, 0, 0 }, "natural")
	piece("clogs", "feet", 1, { r3, l3 })
	local r4, l4 = both("ShoeToe", "RightFoot", "Wedge", { 0.5, 0.26, 0.5 }, { 0, -0.03, -0.72 }, "boots", { rot = { 0, 180, 0 } })
	piece("pointed_shoes", "feet", 3, { r4, l4 })
	local r5, l5 = both("FurCuff", "RightLowerLeg", "Ball", { 0.94, 0.42, 0.94 }, { 0, 0.05, 0 }, "natural")
	piece("fur_boots", "feet", 2, { r5, l5 })
	local r6, l6 = both("Sabaton", "RightFoot", "Block", { 0.88, 0.34, 1.18 }, { 0, 0.01, 0 }, "metal", METAL)
	piece("sabatons", "feet", 3, { r6, l6 })
	local r7, l7 = both("Welly", "RightLowerLeg", "Block", { 0.8, 0.62, 0.8 }, { 0, -0.06, 0 }, "accent")
	piece("wellies", "feet", 1, { r7, l7 }, { tint = { feet = "accent" } })
end
piece("bare_feet", "feet", 1, {}, { tint = { feet = "skin" } })

-- back ----------------------------------------------------------------------------------------
piece("cloak", "back", 2, {
	P("Cloak", "UpperTorso", "Block", { 1.85, 2.3, 0.14 }, { 0, -0.45, 0.6 }, "primary", { rot = { -6, 0, 0 } }),
})
piece("short_cape", "back", 2, {
	P("ShortCape", "UpperTorso", "Block", { 1.7, 1.35, 0.12 }, { 0, 0, 0.6 }, "primary", { rot = { -8, 0, 0 } }),
})
piece("hooded_cloak", "back", 2, {
	P("Cloak", "UpperTorso", "Block", { 1.85, 2.3, 0.14 }, { 0, -0.45, 0.6 }, "primary", { rot = { -6, 0, 0 } }),
	P("HoodDown", "UpperTorso", "Ball", { 1.6, 0.7, 0.7 }, { 0, 0.55, 0.62 }, "primary"),
})
piece("backpack", "back", 1, {
	P("Pack", "UpperTorso", "Block", { 1.3, 1.2, 0.6 }, { 0, -0.05, 0.85 }, "leather"),
	P("PackFlap", "UpperTorso", "Block", { 1.32, 0.4, 0.62 }, { 0, 0.45, 0.86 }, "leather"),
	P("PackRoll", "UpperTorso", "Cylinder", { 1.4, 0.35, 0.35 }, { 0, 0.75, 0.85 }, "natural", MED),
})
piece("satchel", "back", 1, {
	P("SatchelStrap", "UpperTorso", "Block", { 0.2, 1.6, 1.1 }, { 0, 0, 0 }, "leather", { rot = { 0, 0, 35 } }),
	P("Satchel", "LowerTorso", "Block", { 0.3, 0.55, 0.7 }, { 1.02, -0.1, 0 }, "leather"),
})
piece("quiver", "back", 2, {
	P("Quiver", "UpperTorso", "Cylinder", { 1.7, 0.48, 0.48 }, { 0.35, 0.1, 0.72 }, "leather", { rot = { 0, 0, 60 } }),
	P("Fletching", "UpperTorso", "Block", { 0.5, 0.35, 0.35 }, { 0.85, 0.95, 0.72 }, "natural", { rot = { 0, 0, 60 } }),
})
piece("sword_back", "back", 2, {
	P("SwordBlade", "UpperTorso", "Block", { 0.22, 2.4, 0.1 }, { 0.2, 0.2, 0.72 }, "metal", { rot = { 0, 0, 30 }, material = "Metal" }),
	P("SwordGuard", "UpperTorso", "Block", { 0.8, 0.16, 0.16 }, { -0.4, 1.24, 0.72 }, "trim", { rot = { 0, 0, 30 }, material = "Metal" }),
	P("SwordGrip", "UpperTorso", "Block", { 0.16, 0.5, 0.16 }, { -0.55, 1.5, 0.72 }, "leather", { rot = { 0, 0, 30 }, minQuality = "medium" }),
})
piece("bow_back", "back", 2, {
	P("BowUpper", "UpperTorso", "Block", { 0.14, 1.5, 0.14 }, { -0.45, 0.62, 0.66 }, "natural", { rot = { 0, 0, -18 } }),
	P("BowLower", "UpperTorso", "Block", { 0.14, 1.5, 0.14 }, { -0.45, -0.78, 0.66 }, "natural", { rot = { 0, 0, 18 } }),
	P("BowString", "UpperTorso", "Block", { 0.04, 2.7, 0.04 }, { -0.12, -0.08, 0.66 }, "natural", HIGH),
})
piece("staff_back", "back", 2, {
	P("Staff", "UpperTorso", "Cylinder", { 3.4, 0.22, 0.22 }, { -0.1, 0.1, 0.75 }, "leather", { rot = { 0, 0, -65 } }),
	P("StaffGem", "UpperTorso", "Ball", { 0.5, 0.5, 0.5 }, { -0.82, 1.64, 0.75 }, "accent", { material = "Neon" }),
})
piece("basket_back", "back", 1, {
	P("Basket", "UpperTorso", "Cylinder", { 1.2, 1.1, 1.1 }, { 0, -0.1, 0.9 }, "natural", BRIM),
	P("BasketRim", "UpperTorso", "Cylinder", { 0.12, 1.2, 1.2 }, { 0, 0.5, 0.9 }, "leather", with(BRIM, MED)),
})
piece("firewood", "back", 1, {
	P("LogA", "UpperTorso", "Cylinder", { 1.6, 0.34, 0.34 }, { 0, 0.1, 0.78 }, "natural"),
	P("LogB", "UpperTorso", "Cylinder", { 1.5, 0.3, 0.3 }, { 0.05, -0.2, 0.8 }, "natural", MED),
	P("LogC", "UpperTorso", "Cylinder", { 1.4, 0.3, 0.3 }, { -0.05, 0.1, 1.08 }, "natural", HIGH),
})
piece("lute_back", "back", 2, {
	P("LuteBody", "UpperTorso", "Ball", { 0.9, 1.1, 0.35 }, { 0.3, -0.3, 0.72 }, "natural"),
	P("LuteNeck", "UpperTorso", "Block", { 0.16, 1.2, 0.1 }, { -0.05, 0.55, 0.72 }, "leather", { rot = { 0, 0, 20 } }),
})
piece("milk_can", "back", 1, {
	P("Can", "UpperTorso", "Cylinder", { 1.1, 0.75, 0.75 }, { 0, -0.05, 0.85 }, "metal", { rot = { 0, 0, 90 }, material = "Metal" }),
	P("CanLid", "UpperTorso", "Cylinder", { 0.14, 0.5, 0.5 }, { 0, 0.55, 0.85 }, "metal", with(BRIM, MED)),
})

-- hands ---------------------------------------------------------------------------------------
do
	local r1, l1 = both("Glove", "RightHand", "Ball", { 0.72, 0.64, 0.72 }, { 0, 0, 0 }, "leather")
	piece("gloves", "hands", 1, { r1, l1 })
	local r2, l2 = both("Gauntlet", "RightLowerArm", "Block", { 0.66, 0.5, 0.66 }, { 0, -0.1, 0 }, "metal", METAL)
	piece("gauntlets", "hands", 3, { r2, l2 }, { tint = { hands = "metal" } })
	local r3, l3 = both("Bracer", "RightLowerArm", "Block", { 0.64, 0.45, 0.64 }, { 0, -0.05, 0 }, "leather")
	piece("bracers", "hands", 1, { r3, l3 })
	local r4, l4 = both("Mitten", "RightHand", "Ball", { 0.74, 0.66, 0.74 }, { 0, 0, 0 }, "secondary")
	piece("mittens", "hands", 1, { r4, l4 })
end
piece("buckler", "hands", 2, {
	P("Buckler", "LeftLowerArm", "Cylinder", { 0.14, 1.25, 1.25 }, { -0.4, 0, 0 }, "primary"),
	P("BucklerBoss", "LeftLowerArm", "Ball", { 0.2, 0.36, 0.36 }, { -0.49, 0, 0 }, "trim", { material = "Metal", minQuality = "medium" }),
})
piece("tower_shield", "hands", 3, {
	P("TowerShield", "LeftLowerArm", "Block", { 0.2, 2.5, 1.5 }, { -0.44, 0.05, 0 }, "primary"),
	P("ShieldRim", "LeftLowerArm", "Block", { 0.14, 2.64, 1.64 }, { -0.4, 0.05, 0 }, "metal", with(METAL, MED)),
	P("ShieldBoss", "LeftLowerArm", "Ball", { 0.2, 0.5, 0.5 }, { -0.56, 0.25, 0 }, "trim", METAL),
})
piece("hammer", "hands", 1, {
	P("HammerHaft", "RightHand", "Block", { 0.14, 1.0, 0.14 }, { 0, 0.1, -0.25 }, "natural"),
	P("HammerHead", "RightHand", "Block", { 0.5, 0.3, 0.3 }, { 0, 0.55, -0.25 }, "metal", METAL),
})
piece("book", "hands", 2, {
	P("BookCover", "LeftHand", "Block", { 0.5, 0.7, 0.18 }, { -0.05, 0.05, -0.36 }, "primary"),
	P("BookPages", "LeftHand", "Block", { 0.44, 0.64, 0.2 }, { 0.0, 0.05, -0.36 }, "natural", MED),
})
piece("pitchfork", "hands", 1, {
	P("ForkHaft", "RightHand", "Cylinder", { 2.8, 0.12, 0.12 }, { 0, 0.5, -0.2 }, "natural", BRIM),
	P("ForkTines", "RightHand", "Block", { 0.4, 0.4, 0.06 }, { 0, 2.0, -0.2 }, "metal", METAL),
})
piece("ladle", "hands", 1, {
	P("LadleHaft", "RightHand", "Block", { 0.1, 0.9, 0.1 }, { 0, 0.3, -0.25 }, "natural"),
	P("LadleBowl", "RightHand", "Ball", { 0.36, 0.2, 0.36 }, { 0, 0.8, -0.25 }, "metal", METAL),
})

-- accessories (any number; each once) ---------------------------------------------------------
piece("belt", "accessory", 1, {
	P("Belt", "LowerTorso", "Block", { 1.86, 0.22, 1.1 }, { 0, 0.12, 0 }, "leather"),
	P("BeltBuckle", "LowerTorso", "Block", { 0.34, 0.28, 0.06 }, { 0, 0.12, -0.57 }, "trim", { material = "Metal", minQuality = "high" }),
})
piece("pouch", "accessory", 1, {
	P("Pouch", "LowerTorso", "Block", { 0.4, 0.4, 0.25 }, { 0.75, -0.05, -0.45 }, "leather"),
})
piece("necklace", "accessory", 2, {
	P("NecklaceCord", "UpperTorso", "Block", { 0.9, 0.06, 0.06 }, { 0, 0.4, -0.55 }, "leather"),
	P("Pendant", "UpperTorso", "Ball", { 0.22, 0.26, 0.1 }, { 0, 0.26, -0.57 }, "trim", METAL),
})
piece("scarf", "accessory", 1, {
	P("Scarf", "UpperTorso", "Ball", { 2.0, 0.45, 1.3 }, { 0, 0.62, 0 }, "accent"),
	P("ScarfTail", "UpperTorso", "Block", { 0.3, 0.8, 0.1 }, { 0.4, 0.1, -0.6 }, "accent", MED),
})
piece("spectacles", "accessory", 2, {
	P("LensR", "Head", "Cylinder", { 0.05, 0.5, 0.5 }, { 0.44, -0.1, -1.02 }, "trim", { rot = { 0, 90, 0 }, transparency = 0.3 }),
	P("LensL", "Head", "Cylinder", { 0.05, 0.5, 0.5 }, { -0.44, -0.1, -1.02 }, "trim", { rot = { 0, 90, 0 }, transparency = 0.3 }),
	P("LensBridge", "Head", "Block", { 0.4, 0.05, 0.05 }, { 0, -0.02, -1.04 }, "trim", MED),
})
piece("eyepatch", "accessory", 1, {
	P("Eyepatch", "Head", "Ball", { 0.42, 0.46, 0.1 }, { 0.44, -0.1, -0.99 }, "leather"),
	P("PatchStrap", "Head", "Block", { 2.3, 0.08, 0.08 }, { 0, 0.2, -0.85 }, "leather", { rot = { 0, 0, -18 }, minQuality = "medium" }),
})
piece("earrings", "accessory", 2, {
	P("EarringR", "Head", "Ball", { 0.18, 0.18, 0.18 }, { 1.12, -0.42, 0 }, "trim", METAL),
	P("EarringL", "Head", "Ball", { 0.18, 0.18, 0.18 }, { -1.12, -0.42, 0 }, "trim", METAL),
})
piece("hip_lantern", "accessory", 2, {
	P("LanternCap", "LowerTorso", "Block", { 0.4, 0.14, 0.4 }, { 0.72, -0.38, -0.66 }, "metal", METAL),
	P("LanternGlass", "LowerTorso", "Block", { 0.32, 0.4, 0.32 }, { 0.72, -0.65, -0.66 }, "glint", { material = "Neon" }),
	P("LanternBase", "LowerTorso", "Block", { 0.4, 0.1, 0.4 }, { 0.72, -0.9, -0.66 }, "metal", with(METAL, MED)),
})
piece("belt_mace", "accessory", 2, {
	P("MaceHaft", "LowerTorso", "Block", { 0.14, 1.0, 0.14 }, { -0.98, -0.3, 0.2 }, "natural", { rot = { 0, 0, -8 } }),
	P("MaceHead", "LowerTorso", "Ball", { 0.42, 0.42, 0.42 }, { -1.02, 0.25, 0.2 }, "metal", METAL),
})
piece("daggers", "accessory", 2, {
	P("DaggerR", "LowerTorso", "Block", { 0.14, 0.9, 0.22 }, { 0.95, -0.35, -0.2 }, "metal", { rot = { 20, 0, 0 }, material = "Metal" }),
	P("DaggerL", "LowerTorso", "Block", { 0.14, 0.9, 0.22 }, { -0.95, -0.35, -0.2 }, "metal", { rot = { 20, 0, 0 }, material = "Metal" }),
})
piece("flower_pin", "accessory", 1, {
	P("FlowerPin", "UpperTorso", "Ball", { 0.3, 0.3, 0.12 }, { 0.55, 0.35, -0.56 }, "accent"),
})
piece("face_mask", "accessory", 2, {
	P("Mask", "Head", "Block", { 2.0, 0.6, 0.12 }, { 0, -0.6, -1.0 }, "secondary"),
})
piece("keyring", "accessory", 1, {
	P("Keyring", "LowerTorso", "Ball", { 0.3, 0.3, 0.1 }, { -0.8, 0, -0.42 }, "metal", METAL),
})
piece("goggles", "accessory", 2, {
	P("GoggleStrap", "Head", "Cylinder", { 0.14, 2.34, 2.34 }, { 0, 0.72, 0.02 }, "leather", BRIM),
	P("GoggleR", "Head", "Cylinder", { 0.14, 0.42, 0.42 }, { 0.4, 0.85, -1.0 }, "metal", { rot = { 0, 90, 0 }, material = "Metal" }),
	P("GoggleL", "Head", "Cylinder", { 0.14, 0.42, 0.42 }, { -0.4, 0.85, -1.0 }, "metal", { rot = { 0, 90, 0 }, material = "Metal", minQuality = "medium" }),
})

-- hair ----------------------------------------------------------------------------------------
local CAP = P("Hair", "Head", "Ball", { 2.42, 1.35, 2.25 }, { 0, 0.52, 0.1 }, "hair")
piece("hair_cap", "hair", 1, { CAP })
piece("hair_tuft", "hair", 1, { CAP, P("HairTuft", "Head", "Wedge", { 0.5, 0.6, 0.9 }, { 0.2, 1.25, -0.3 }, "hair", { rot = { 0, 0, -15 } }) })
piece("hair_long", "hair", 1, { CAP, P("HairBack", "Head", "Block", { 2.0, 1.7, 0.45 }, { 0, -0.3, 0.9 }, "hair", { back = true }) })
piece("hair_bun", "hair", 1, { CAP, P("HairBun", "Head", "Ball", { 0.85, 0.85, 0.85 }, { 0, 1.0, 0.85 }, "hair", { back = true }) })
piece("hair_ponytail", "hair", 1, {
	CAP,
	P("Ponytail", "Head", "Ball", { 0.6, 1.4, 0.6 }, { 0, -0.05, 1.3 }, "hair", { rot = { -20, 0, 0 }, back = true }),
})
piece("hair_spiky", "hair", 1, {
	CAP,
	P("Spike1", "Head", "Wedge", { 0.5, 0.7, 0.8 }, { -0.45, 1.15, 0 }, "hair", { rot = { 0, 0, 20 } }),
	P("Spike2", "Head", "Wedge", { 0.5, 0.8, 0.8 }, { 0.05, 1.25, 0.1 }, "hair"),
	P("Spike3", "Head", "Wedge", { 0.5, 0.7, 0.8 }, { 0.5, 1.12, 0 }, "hair", { rot = { 0, 0, -20 }, minQuality = "medium" }),
})
piece("hair_bob", "hair", 1, { P("Hair", "Head", "Ball", { 2.5, 1.7, 2.35 }, { 0, 0.25, 0.12 }, "hair") })
piece("hair_braid", "hair", 1, {
	CAP,
	P("Braid", "Head", "Ball", { 0.45, 1.4, 0.45 }, { 0.95, -0.7, 0.35 }, "hair", { rot = { 0, 0, 8 }, back = true }),
})
piece("hair_curls", "hair", 1, {
	P("Curls", "Head", "Ball", { 2.5, 1.45, 2.35 }, { 0, 0.5, 0.1 }, "hair"),
	P("CurlR", "Head", "Ball", { 0.7, 0.7, 0.7 }, { 1.0, 0.2, 0.3 }, "hair", MED),
	P("CurlL", "Head", "Ball", { 0.7, 0.7, 0.7 }, { -1.0, 0.2, 0.3 }, "hair", MED),
})
piece("hair_topknot", "hair", 1, { CAP, P("Topknot", "Head", "Ball", { 0.6, 0.6, 0.6 }, { 0, 1.35, 0.2 }, "hair") })
piece("hair_bald", "hair", 1, {})
piece("hair_beard", "hair", 1, {
	CAP,
	P("Beard", "Head", "Ball", { 1.5, 0.9, 0.6 }, { 0, -0.75, -0.72 }, "hair", { back = true }),
})

Wardrobe.pieces = pieces
Wardrobe.byId = {} :: { [string]: any }
for _, p in pieces do
	Wardrobe.byId[p.id] = p
end

-- Pieces by slot, in declaration order.
function Wardrobe.inSlot(slot: string): { any }
	local out = {}
	for _, p in pieces do
		if p.slot == slot then
			table.insert(out, p)
		end
	end
	return out
end

-- Every problem with a piece table (a game may add its own pieces through the look book).
function Wardrobe.check(list: { any }, attachNames: { [string]: boolean }): { string }
	local problems = {}
	local seen = {}
	local slotOk = { accessory = true, hair = true }
	for _, s in Wardrobe.SLOTS do
		slotOk[s] = true
	end
	local colourOk = {}
	for _, c in Wardrobe.COLOUR_SLOTS do
		colourOk[c] = true
	end
	for i, p in list do
		local where = `piece {tostring(p.id or i)}`
		if type(p.id) ~= "string" or p.id == "" or p.id == "none" then
			table.insert(problems, `{where}: needs an id (not "none")`)
		elseif seen[p.id] then
			table.insert(problems, `{where}: id used twice`)
		end
		seen[p.id or i] = true
		if not slotOk[p.slot] then
			table.insert(problems, `{where}: unknown slot {tostring(p.slot)}`)
		end
		if type(p.tier) ~= "number" or p.tier < 1 or p.tier > 3 then
			table.insert(problems, `{where}: tier must be 1..3`)
		end
		if p.hair ~= nil and p.hair ~= "all" and p.hair ~= "back" and p.hair ~= "none" then
			table.insert(problems, `{where}: hair must be all | back | none`)
		end
		for g, c in p.tint or {} do
			if not Wardrobe.TINT_GROUPS[g] or not colourOk[c] then
				table.insert(problems, `{where}: tint {tostring(g)} = {tostring(c)} is not group = colour slot`)
			end
		end
		for _, part in p.parts or {} do
			local pw = `{where} part {tostring(part.name)}`
			if not attachNames[part.attach] then
				table.insert(problems, `{pw}: attach {tostring(part.attach)} is not a body part`)
			end
			if not Wardrobe.SHAPES[part.shape] then
				table.insert(problems, `{pw}: unknown shape {tostring(part.shape)}`)
			end
			if type(part.color) ~= "string" or not colourOk[part.color] then
				table.insert(problems, `{pw}: color {tostring(part.color)} must be a colour slot (never a hex)`)
			end
			if part.material ~= nil and not Wardrobe.MATERIALS[part.material] then
				table.insert(problems, `{pw}: unknown material {tostring(part.material)}`)
			end
			if type(part.size) ~= "table" or #part.size ~= 3 or type(part.offset) ~= "table" or #part.offset ~= 3 then
				table.insert(problems, `{pw}: size and offset must be {"{x, y, z}"}`)
			else
				for _, v in part.size do
					if type(v) ~= "number" or v <= 0 then
						table.insert(problems, `{pw}: size must be positive`)
						break
					end
				end
			end
			if part.minQuality ~= nil and part.minQuality ~= "medium" and part.minQuality ~= "high" then
				table.insert(problems, `{pw}: minQuality must be medium | high`)
			end
		end
	end
	return problems
end

return Wardrobe
