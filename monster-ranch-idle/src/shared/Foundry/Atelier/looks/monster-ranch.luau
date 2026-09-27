--!strict
-- Monster Ranch Idle look book for Atelier (a PLAN: the ranch has no people yet).
--
-- Ranchers, visitors, vendors and kids on the same genome as Guildhall's townsfolk, on the
-- taller cartoon R15 template (head about a fifth of the height). Every swatch comes from the
-- DRAFT lock locks/drafts/monster-ranch.json (element colours: <element>.color / light /
-- accent), shaded where a garment needs a duller tone; only skin tones come from `kit`.
-- Faces follow the lock's creature rule: big glossy eyes with a white glint, a small happy
-- mouth. Cultures are placeholders until the ranch has regions.

local function list(s: string): { string }
	local out = {}
	for w in string.gmatch(s, "[%w_]+") do
		table.insert(out, w)
	end
	return out
end

local NONE2 = list("none none")

return {
	id = "monster-ranch",
	kit = {
		skin1 = "#FBDCC2",
		skin2 = "#F1C19A",
		skin3 = "#DDA070",
		skin4 = "#B97A4E",
		skin5 = "#8C5634",
		skin6 = "#5A3522",
	},
	swatches = {
		skin_1 = { kit = "skin1", tier = 1 },
		skin_2 = { kit = "skin2", tier = 1 },
		skin_3 = { kit = "skin3", tier = 1 },
		skin_4 = { kit = "skin4", tier = 1 },
		skin_5 = { kit = "skin5", tier = 1 },
		skin_6 = { kit = "skin6", tier = 1 },
		hair_black = { lock = "void.color", value = 0.45, tier = 1 },
		hair_brown = { lock = "stone.color", value = 0.55, tier = 1 },
		hair_auburn = { lock = "ember.color", value = 0.62, sat = 0.9, tier = 1 },
		hair_blond = { lock = "spark.color", value = 0.97, sat = 0.55, tier = 1 },
		hair_grey = { lock = "stone.light", value = 0.86, sat = 0.3, tier = 1 },
		hair_berry = { lock = "gloom.color", value = 0.8, tier = 1 },
		denim = { lock = "tide.color", value = 0.62, sat = 0.75, tier = 1 },
		denim_light = { lock = "tide.color", value = 0.9, sat = 0.45, tier = 1 },
		canvas = { lock = "stone.light", tier = 1 },
		cream = { lock = "stone.accent", tier = 1 },
		khaki = { lock = "stone.color", value = 1.15, sat = 0.8, tier = 1 },
		earth = { lock = "stone.color", value = 0.7, tier = 1 },
		leather_brown = { lock = "stone.color", value = 0.62, sat = 1.2, tier = 1 },
		tan = { lock = "stone.color", tier = 2 },
		ember_soft = { lock = "ember.light", tier = 1 },
		tide_soft = { lock = "tide.light", tier = 1 },
		sprout_soft = { lock = "sprout.light", tier = 1 },
		spark_soft = { lock = "spark.light", tier = 1 },
		ember_red = { lock = "ember.color", tier = 2 },
		tide_blue = { lock = "tide.color", tier = 2 },
		sprout_green = { lock = "sprout.color", tier = 2 },
		spark_yellow = { lock = "spark.color", tier = 2 },
		gloom_soft = { lock = "gloom.light", tier = 2 },
		ember_gold = { lock = "ember.accent", tier = 2 },
		gloom_purple = { lock = "gloom.color", tier = 3 },
		void_navy = { lock = "void.color", tier = 3 },
		light_gold = { lock = "light.color", tier = 3 },
		void_cyan = { lock = "void.accent", tier = 3 },
		steel = { lock = "stone.light", value = 0.8, sat = 0.2, tier = 1 },
		chrome = { lock = "tide.light", value = 0.88, sat = 0.3, tier = 2 },
		eye_black = { lock = "void.color", value = 0.35, tier = 1 },
		mouth_red = { lock = "ember.color", value = 0.55, tier = 1 },
		blush_peach = { lock = "ember.light", tier = 1 },
		glint_white = { lock = "light.accent", tier = 1 },
	},
	fixed = { eye = "eye_black", mouth = "mouth_red", blush = "blush_peach", glint = "glint_white" },
	skins = list("skin_1 skin_2 skin_3 skin_4 skin_5 skin_6"),
	hairColours = list("hair_black hair_brown hair_auburn hair_blond hair_grey hair_berry"),

	palette = {
		base = {
			shirt = list("canvas cream ember_soft tide_soft sprout_soft spark_soft ember_red tide_blue sprout_green spark_yellow gloom_soft"),
			trousers = list("denim denim_light khaki earth tan void_navy"),
			boots = list("leather_brown earth tan void_navy"),
			primary = list("ember_red tide_blue sprout_green spark_yellow ember_soft tide_soft sprout_soft gloom_purple void_navy"),
			secondary = list("canvas cream khaki denim_light spark_soft tide_soft gloom_soft"),
			accent = list("ember_red spark_yellow sprout_green tide_blue ember_gold void_cyan light_gold"),
			trim = list("cream canvas ember_gold light_gold"),
			leather = list("leather_brown earth tan"),
			metal = list("steel chrome"),
			natural = list("canvas cream khaki"),
		},
	},

	faces = {
		eyes = list("big round wide"),
		brows = list("straight arched thin none"),
		mouths = list("smile grin open small"),
		blush = 0.7,
	},

	bodies = {
		rancher = {
			template = "tall",
			scale = 0.8,
			builds = { average = 3, stout = 2, broad = 2, lanky = 1, round = 1 },
			height = { 0.95, 1.07 },
			budget = 40,
			hair = { hair_cap = 2, hair_tuft = 2, hair_long = 1, hair_ponytail = 2, hair_spiky = 1, hair_bob = 1, hair_braid = 1, hair_curls = 1, hair_bald = 1, hair_beard = 2 },
		},
		visitor = {
			template = "tall",
			scale = 0.8,
			builds = { average = 4, slim = 2, stout = 1, lanky = 1, round = 1 },
			height = { 0.93, 1.07 },
			budget = 40,
			hair = { hair_cap = 2, hair_tuft = 1, hair_long = 2, hair_bun = 2, hair_ponytail = 2, hair_spiky = 1, hair_bob = 2, hair_braid = 1, hair_curls = 2, hair_topknot = 1 },
		},
		kid = {
			template = "chibi",
			scale = 0.6,
			builds = { sprout = 1 },
			height = { 0.78, 0.86 },
			budget = 34,
			hair = { hair_cap = 2, hair_tuft = 2, hair_ponytail = 2, hair_bob = 2, hair_curls = 1, hair_bun = 1 },
		},
	},

	outfit = {
		head = list("none none ranch_hat bucket_hat flat_cap headband"),
		torso = list("none vest overalls jerkin"),
		legs = list("none none none"),
		feet = list("none tall_boots wellies"),
		back = list("none none none backpack"),
		hands = list("none none gloves"),
	},
	accessories = list("belt scarf pouch goggles keyring flower_pin"),

	wealth = {
		poor = { tiers = { 1, 1 }, accessories = { 0, 1 } },
		common = { tiers = { 1, 2 }, accessories = { 0, 2 } },
		rich = { tiers = { 2, 3 }, accessories = { 1, 3 } },
	},

	cultures = {
		ranchland = { weight = 3, prefer = { primary = list("ember_red sprout_green") }, pieces = list("ranch_hat overalls") },
		harbor = { weight = 1, prefer = { primary = list("tide_blue tide_soft") }, pieces = list("bucket_hat") },
		hills = { weight = 1, prefer = { primary = list("sprout_green spark_yellow") }, pieces = list("fur_collar") },
	},

	defaultRole = "visitor",
	roles = {
		rancher = {
			crowd = 3,
			body = { "rancher" },
			wealth = { poor = 1, common = 4 },
			outfit = {
				head = list("ranch_hat ranch_hat flat_cap bandana"),
				torso = list("overalls vest jerkin"),
				legs = list("none chaps"),
				feet = list("wellies tall_boots"),
				back = list("none none milk_can basket_back"),
				hands = list("gloves none pitchfork"),
			},
			accessories = list("belt scarf pouch keyring"),
			palette = { trousers = list("denim denim_light khaki") },
		},
		visitor = {
			crowd = 4,
			body = { "visitor" },
			wealth = { poor = 1, common = 4, rich = 2 },
			outfit = {
				head = list("none none bucket_hat beret flat_cap feather_cap"),
				torso = list("none vest sash long_coat shawl"),
				legs = list("none skirt long_skirt"),
				feet = list("none tall_boots sandals"),
				back = list("none backpack satchel"),
				hands = NONE2,
			},
			accessories = list("scarf necklace spectacles earrings flower_pin"),
		},
		vendor = {
			crowd = 1,
			body = { "visitor", "rancher" },
			wealth = { common = 3, rich = 1 },
			outfit = { head = list("flat_cap beret"), torso = list("apron vest"), legs = list("none"), back = list("satchel none"), hands = NONE2 },
			accessories = list("pouch keyring"),
		},
		vet = {
			crowd = 1,
			body = { "visitor" },
			wealth = { common = 2, rich = 1 },
			outfit = { head = list("none headband"), torso = list("scholar_gown"), legs = list("none"), feet = list("tall_boots"), back = list("satchel"), hands = list("gloves") },
			accessories = list("spectacles necklace"),
			palette = { natural = list("cream canvas") },
		},
		breeder = {
			crowd = 1,
			body = { "rancher" },
			wealth = { common = 2, rich = 2 },
			outfit = { head = list("ranch_hat feather_cap"), torso = list("long_coat vest"), legs = list("none"), feet = list("tall_boots"), back = list("none"), hands = list("book gloves") },
			accessories = list("goggles belt necklace"),
			palette = { primary = list("gloom_purple void_navy") },
		},
		kid = {
			crowd = 2,
			body = { "kid" },
			wealth = { poor = 1, common = 3 },
			outfit = {
				head = list("none none flat_cap headband bucket_hat"),
				torso = list("none overalls vest"),
				legs = list("none skirt"),
				feet = list("wellies sandals none"),
				back = list("none backpack"),
				hands = NONE2,
			},
			accessories = list("scarf flower_pin"),
		},
	},

	crowd = { minDistance = 0.3, window = 2, attempts = 16 },
}
