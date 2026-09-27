--!strict
-- Guildhall Idle look book for Atelier (data; game specifics live here, not in Atelier.luau).
--
-- Bodies follow AnimLibrary's chibi R15 (rig.hero / rig.villager at scale 0.55; part budgets
-- hero <= 46, villager <= 34 at high). Every swatch is a colour of art/STYLE_LOCK.json (v1,
-- sealed) through `lock = "group.name"`, optionally shaded (value / sat, HSV multipliers);
-- only skin tones come from `kit` (the lock names none). Roles match Life's rules
-- (villager, lamplighter, child) plus trades and the six hero classes.

local function list(s: string): { string }
	local out = {}
	for w in string.gmatch(s, "[%w_]+") do
		table.insert(out, w)
	end
	return out
end

local NONE3 = list("none none none")

return {
	id = "guildhall",
	-- colours the lock does not name (reported as off-lock by `foundry atelier looks`)
	kit = {
		skin1 = "#F6D7B8",
		skin2 = "#EFC39A",
		skin3 = "#D9A274",
		skin4 = "#B77B52",
		skin5 = "#8E5A3A",
		skin6 = "#5E3A26",
	},
	swatches = {
		-- skin (kit)
		skin_1 = { kit = "skin1", tier = 1 },
		skin_2 = { kit = "skin2", tier = 1 },
		skin_3 = { kit = "skin3", tier = 1 },
		skin_4 = { kit = "skin4", tier = 1 },
		skin_5 = { kit = "skin5", tier = 1 },
		skin_6 = { kit = "skin6", tier = 1 },
		-- hair (lock-derived)
		hair_black = { lock = "ui.ink", value = 1.25, tier = 1 },
		hair_dark = { lock = "world.oak", value = 0.55, tier = 1 },
		hair_brown = { lock = "world.oak", value = 0.95, tier = 1 },
		hair_chestnut = { lock = "world.oak", value = 1.35, sat = 1.1, tier = 1 },
		hair_ginger = { lock = "roof.homes", value = 1.05, tier = 1 },
		hair_blond = { lock = "roof.production", value = 1.08, sat = 0.75, tier = 1 },
		hair_grey = { lock = "world.fieldstone", value = 1.12, sat = 0.35, tier = 1 },
		-- undyed cloth and naturals
		linen = { lock = "world.plaster", tier = 1 },
		oat = { lock = "world.path", tier = 1 },
		undyed = { lock = "world.oak", value = 1.5, sat = 0.7, tier = 1 },
		parchment = { lock = "ui.parchment", tier = 2 },
		bleached = { lock = "world.plaster", value = 1.06, sat = 0.55, tier = 2 },
		-- greys and darks
		stone_grey = { lock = "world.fieldstone", tier = 1 },
		slate = { lock = "world.fieldstone", value = 0.62, tier = 1 },
		charcoal = { lock = "roof.craft", tier = 1 },
		fine_black = { lock = "ui.ink", value = 1.6, tier = 3 },
		-- faded dyes (cheap)
		faded_madder = { lock = "roof.homes", value = 1.12, sat = 0.55, tier = 1 },
		faded_woad = { lock = "roof.civic", value = 1.2, sat = 0.5, tier = 1 },
		faded_moss = { lock = "world.meadow", value = 0.95, sat = 0.55, tier = 1 },
		-- dyes
		madder = { lock = "roof.homes", tier = 2 },
		woad = { lock = "roof.civic", tier = 2 },
		moss = { lock = "world.meadow", value = 0.78, tier = 2 },
		meadow = { lock = "world.meadow", tier = 2 },
		weld = { lock = "roof.production", tier = 2 },
		ochre = { lock = "roof.training", tier = 2 },
		teal = { lock = "ui.go", tier = 2 },
		sky = { lock = "world.water", tier = 2 },
		-- costly dyes
		heather = { lock = "roof.social", tier = 3 },
		violet = { lock = "roof.arcane", tier = 3 },
		crimson = { lock = "ui.danger", tier = 3 },
		-- leather
		bark = { lock = "world.oak", tier = 1 },
		dark_leather = { lock = "world.oak", value = 0.7, tier = 1 },
		tan_leather = { lock = "world.oak", value = 1.35, sat = 0.9, tier = 2 },
		-- metal
		iron = { lock = "world.fieldstone", value = 0.78, sat = 0.4, tier = 1 },
		steel = { lock = "world.fieldstone", value = 1.06, sat = 0.45, tier = 2 },
		brass = { lock = "ui.brass", tier = 2 },
		gold = { lock = "ui.brass", value = 1.1, sat = 1.1, tier = 3 },
		-- the face and light
		eye_ink = { lock = "ui.ink", tier = 1 },
		mouth_red = { lock = "roof.homes", value = 0.55, tier = 1 },
		blush_rose = { lock = "roof.homes", value = 1.25, sat = 0.45, tier = 1 },
		glint_white = { lock = "ui.parchment", value = 1.1, sat = 0.15, tier = 1 },
		lamp = { lock = "world.lamp", tier = 2 },
	},
	fixed = { eye = "eye_ink", mouth = "mouth_red", blush = "blush_rose", glint = "glint_white" },
	skins = list("skin_1 skin_2 skin_3 skin_4 skin_5 skin_6"),
	hairColours = list("hair_black hair_dark hair_brown hair_chestnut hair_ginger hair_blond hair_grey"),

	palette = {
		base = {
			shirt = list("linen oat undyed faded_madder faded_woad faded_moss parchment bleached madder woad moss weld teal"),
			trousers = list("bark dark_leather slate charcoal stone_grey faded_woad undyed moss woad fine_black"),
			boots = list("dark_leather bark charcoal tan_leather fine_black"),
			primary = list("madder woad moss meadow weld ochre teal sky faded_madder faded_woad faded_moss charcoal heather violet crimson"),
			secondary = list("linen oat parchment stone_grey slate faded_woad faded_moss weld ochre sky bleached"),
			accent = list("madder weld woad teal meadow crimson heather ochre faded_madder"),
			trim = list("oat linen stone_grey brass gold"),
			leather = list("bark dark_leather tan_leather"),
			metal = list("iron steel"),
			natural = list("oat linen undyed parchment bleached"),
		},
	},

	faces = {
		eyes = list("round wide narrow dot sleepy almond"),
		brows = list("straight arched thick thin angled worried none"),
		mouths = list("smile grin small flat open smirk pout"),
		blush = 0.5,
	},

	bodies = {
		villager = {
			template = "chibi",
			scale = 0.55,
			builds = { average = 4, slim = 2, stout = 2, lanky = 1, round = 1 },
			height = { 0.94, 1.06 },
			budget = 34,
			hair = {
				hair_cap = 2, hair_tuft = 2, hair_long = 2, hair_bun = 2, hair_ponytail = 2, hair_spiky = 1,
				hair_bob = 2, hair_braid = 1, hair_curls = 1, hair_topknot = 1, hair_bald = 1, hair_beard = 1,
			},
		},
		hero = {
			template = "chibi",
			scale = 0.55,
			builds = { average = 3, broad = 2, slim = 2, stout = 1, lanky = 1 },
			height = { 0.98, 1.08 },
			budget = 46,
			hair = {
				hair_cap = 2, hair_tuft = 2, hair_long = 2, hair_bun = 1, hair_ponytail = 2, hair_spiky = 2,
				hair_bob = 1, hair_braid = 1, hair_topknot = 1, hair_beard = 1,
			},
		},
		child = {
			template = "chibi",
			scale = 0.55,
			builds = { sprout = 1 },
			height = { 0.72, 0.8 },
			budget = 30,
			hair = { hair_cap = 2, hair_tuft = 2, hair_bun = 1, hair_ponytail = 2, hair_bob = 2, hair_braid = 1, hair_curls = 1 },
			faces = {
				eyes = list("round wide big dot"),
				brows = list("arched thin none"),
				mouths = list("smile grin open small"),
				blush = 0.8,
			},
		},
	},

	-- defaults for a slot a role does not list
	outfit = {
		head = list("none none none straw_hat flat_cap kerchief beret hood headband bucket_hat"),
		torso = list("none none apron vest shawl jerkin bodice"),
		legs = list("none none none skirt long_skirt breeches patched_trousers"),
		feet = list("none none tall_boots clogs sandals"),
		back = list("none none none none none satchel backpack"),
		hands = list("none none none none none gloves"),
	},
	accessories = list("belt pouch scarf necklace flower_pin keyring spectacles earrings"),

	wealth = {
		poor = { tiers = { 1, 1 }, accessories = { 0, 1 } },
		common = { tiers = { 1, 2 }, accessories = { 0, 2 } },
		rich = { tiers = { 2, 3 }, accessories = { 1, 3 } },
	},

	cultures = {
		valley = { weight = 4, prefer = { primary = list("madder meadow"), accent = list("weld") }, pieces = list("kerchief straw_hat flower_crown") },
		highland = { weight = 2, prefer = { primary = list("woad moss"), secondary = list("slate") }, pieces = list("kilt fur_collar fur_boots") },
		coastal = { weight = 2, prefer = { primary = list("sky teal"), accent = list("sky") }, pieces = list("bucket_hat bandana") },
		southern = { weight = 1, prefer = { primary = list("ochre weld"), accent = list("crimson") }, pieces = list("sash poncho sandals") },
	},

	defaultRole = "villager",
	roles = {
		villager = { crowd = 6, body = { "villager" }, wealth = { poor = 2, common = 5, rich = 1 } },
		lamplighter = {
			crowd = 1,
			body = { "villager" },
			wealth = { poor = 1, common = 2 },
			outfit = { head = list("flat_cap feather_cap"), torso = list("long_coat vest"), back = NONE3, hands = list("gloves") },
			accessories = list("hip_lantern"),
			palette = { primary = list("charcoal woad faded_woad"), accent = list("weld ochre") },
		},
		child = {
			crowd = 2,
			body = { "child" },
			wealth = { poor = 1, common = 3 },
			outfit = {
				head = list("none none none flat_cap kerchief headband flower_crown nightcap"),
				torso = list("none none apron overalls vest"),
				legs = list("none skirt breeches"),
				feet = list("none bare_feet clogs sandals"),
				back = NONE3,
				hands = NONE3,
			},
			accessories = list("scarf flower_pin"),
		},
		blacksmith = {
			crowd = 1,
			body = { "villager" },
			wealth = { poor = 1, common = 3 },
			outfit = {
				head = list("none bandana flat_cap"),
				torso = list("smith_apron smith_apron jerkin"),
				legs = list("none none"),
				feet = list("tall_boots"),
				back = NONE3,
				hands = list("gloves hammer"),
			},
			accessories = list("belt pouch"),
			palette = { shirt = list("charcoal oat faded_madder"), trousers = list("charcoal dark_leather slate") },
		},
		farmer = {
			crowd = 2,
			body = { "villager" },
			wealth = { poor = 3, common = 3 },
			outfit = {
				head = list("straw_hat straw_hat kerchief bucket_hat none"),
				torso = list("overalls apron none vest"),
				legs = list("none patched_trousers leg_wraps"),
				feet = list("clogs tall_boots"),
				back = list("none none basket_back"),
				hands = list("none pitchfork"),
			},
			accessories = list("scarf pouch"),
		},
		baker = {
			crowd = 1,
			body = { "villager" },
			wealth = { common = 3, rich = 1 },
			outfit = { head = list("chef_toque kerchief"), torso = list("apron apron"), legs = list("none skirt"), back = NONE3, hands = list("none ladle") },
			palette = { shirt = list("linen bleached oat") },
		},
		merchant = {
			crowd = 1,
			body = { "villager" },
			wealth = { common = 2, rich = 3 },
			outfit = { head = list("beret top_hat feather_cap"), torso = list("long_coat vest sash"), legs = list("breeches none"), feet = list("pointed_shoes tall_boots"), back = list("none satchel") },
			accessories = list("necklace pouch keyring earrings spectacles"),
		},
		guard = {
			crowd = 1,
			body = { "villager", "hero" },
			wealth = { common = 3, rich = 1 },
			outfit = { head = list("kettle_helm nasal_helm mail_coif"), torso = list("mail_shirt tabard"), legs = list("none tassets"), feet = list("tall_boots"), back = list("none short_cape"), hands = list("bracers gauntlets") },
			accessories = list("belt belt_mace"),
			palette = { primary = list("woad madder"), metal = list("iron steel") },
		},
		scholar = {
			crowd = 1,
			body = { "villager" },
			wealth = { common = 2, rich = 2 },
			outfit = { head = list("none beret nightcap"), torso = list("scholar_gown robe"), legs = list("none"), feet = list("none pointed_shoes"), back = list("none satchel"), hands = list("book") },
			accessories = list("spectacles necklace"),
			palette = { primary = list("woad violet heather charcoal") },
		},
		fisher = {
			crowd = 1,
			body = { "villager" },
			wealth = { poor = 2, common = 2 },
			outfit = { head = list("bucket_hat bandana"), torso = list("vest overalls jerkin"), legs = list("none leg_wraps"), feet = list("tall_boots bare_feet"), back = list("basket_back none") },
			accessories = list("scarf keyring"),
		},
		carpenter = {
			crowd = 1,
			body = { "villager" },
			wealth = { poor = 1, common = 3 },
			outfit = { head = list("flat_cap none"), torso = list("apron jerkin"), legs = list("none"), feet = list("tall_boots clogs"), back = list("firewood none none"), hands = list("hammer gloves") },
			accessories = list("belt pouch"),
		},
		herbalist = {
			crowd = 1,
			body = { "villager" },
			wealth = { poor = 1, common = 2 },
			outfit = { head = list("hood flower_crown kerchief"), torso = list("shawl robe apron"), legs = list("long_skirt none"), feet = list("sandals none"), back = list("basket_back satchel") },
			accessories = list("pouch necklace flower_pin"),
			palette = { primary = list("moss meadow faded_moss teal") },
		},
		noble = {
			crowd = 1,
			body = { "villager" },
			wealth = { rich = 1 },
			outfit = { head = list("top_hat circlet feather_cap"), torso = list("long_coat mantle bodice"), legs = list("breeches long_skirt"), feet = list("pointed_shoes"), back = list("cloak none") },
			accessories = list("necklace earrings belt"),
			palette = { primary = list("heather violet crimson woad"), trim = list("gold brass") },
		},
		bard = {
			crowd = 1,
			body = { "villager" },
			wealth = { poor = 1, common = 2 },
			outfit = { head = list("feather_cap beret"), torso = list("vest sash bodice"), legs = list("breeches"), feet = list("pointed_shoes tall_boots"), back = list("lute_back") },
			accessories = list("scarf earrings flower_pin"),
		},
		miner = {
			crowd = 1,
			body = { "villager" },
			wealth = { poor = 2, common = 2 },
			outfit = { head = list("miner_helmet"), torso = list("jerkin overalls"), legs = list("none patched_trousers"), feet = list("tall_boots"), back = list("none backpack"), hands = list("gloves none") },
			accessories = list("goggles belt"),
		},
		-- heroes: the class colour where the camera sees it (mantle, cape) and the class kit
		blade = {
			crowd = 1,
			body = { "hero" },
			wealth = { common = 2, rich = 1 },
			lockOutfit = true,
			outfit = { head = list("crested_helm headband nasal_helm"), torso = list("mantle breastplate"), legs = list("none"), feet = list("tall_boots"), back = list("sword_back"), hands = list("buckler") },
			accessories = list("belt"),
			palette = { primary = list("madder crimson") },
		},
		warden = {
			crowd = 1,
			body = { "hero" },
			wealth = { common = 2, rich = 1 },
			lockOutfit = true,
			outfit = { head = list("kettle_helm nasal_helm mail_coif"), torso = list("mantle mail_shirt"), legs = list("tassets none"), feet = list("sabatons tall_boots"), back = list("cloak"), hands = list("tower_shield") },
			accessories = list("belt_mace belt"),
			palette = { primary = list("woad faded_woad") },
		},
		ranger = {
			crowd = 1,
			body = { "hero" },
			wealth = { common = 3 },
			lockOutfit = true,
			outfit = { head = list("hood feather_cap"), torso = list("mantle jerkin"), legs = list("none chaps"), feet = list("tall_boots"), back = list("quiver bow_back"), hands = list("bracers") },
			accessories = list("belt pouch"),
			palette = { primary = list("moss meadow") },
		},
		arcanist = {
			crowd = 1,
			body = { "hero" },
			wealth = { common = 2, rich = 2 },
			lockOutfit = true,
			outfit = { head = list("pointed_hat wide_hat circlet"), torso = list("robe"), legs = list("none"), feet = list("pointed_shoes none"), back = list("staff_back"), hands = list("none book") },
			accessories = list("necklace belt"),
			palette = { primary = list("violet heather"), accent = list("sky teal") },
		},
		cleric = {
			crowd = 1,
			body = { "hero" },
			wealth = { common = 2, rich = 1 },
			lockOutfit = true,
			outfit = { head = list("mitre veil hood"), torso = list("tabard robe"), legs = list("long_skirt none"), feet = list("sandals"), back = list("cloak none"), hands = list("none book") },
			accessories = list("hip_lantern necklace"),
			palette = { primary = list("parchment bleached"), trim = list("brass gold") },
		},
		rogue = {
			crowd = 1,
			body = { "hero" },
			wealth = { poor = 1, common = 2 },
			lockOutfit = true,
			outfit = { head = list("hood bandana"), torso = list("jerkin bandolier"), legs = list("none leg_wraps"), feet = list("tall_boots"), back = list("short_cape"), hands = list("bracers gloves") },
			accessories = list("daggers face_mask"),
			palette = { primary = list("charcoal slate"), secondary = list("charcoal") },
		},
	},

	crowd = { minDistance = 0.3, window = 2, attempts = 16 },
}
