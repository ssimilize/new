--[[
	Accessories (update 1.5 · Showtime): cosmetic items a monster wears, one per slot.
	They change nothing but looks (and how Monster Contest judges score a theme).

	  slot   head · face · neck · back
	  shape  what MonsterModel draws (see Visuals/MonsterModel → accessory shapes)
	  color / color2  hex colours
	  price  { gems = n } or { ribbons = n } (Contest Ribbons), or nil when only earned
	  tags   themes it fits (Config.Contests themes list the tags they reward)

	Owned accessories wait in storage (profile.Accessories.owned) until equipped; an equipped
	accessory lives on the monster record (`acc = { [slot] = id }`) and comes back to storage
	when the monster leaves the ranch (sold, traded, listed, retired or lost to a rebirth).
]]

local Accessories = {}

Accessories.Unlock = "wardrobe"
Accessories.Slots = { "head", "face", "neck", "back" }
Accessories.SlotNames = { head = "Head", face = "Face", neck = "Neck", back = "Back" }

local function item(def)
	def.added = def.added or "1.5"
	return def
end

Accessories.List = {
	-- Head ---------------------------------------------------------------------------
	item({
		id = "sprout_cap",
		name = "Sprout Cap",
		slot = "head",
		shape = "cap",
		color = "#79C455",
		color2 = "#FFFFFF",
		tags = { "nature", "cute" },
	}),
	item({
		id = "top_hat",
		name = "Top Hat",
		slot = "head",
		shape = "tophat",
		color = "#2B2B2B",
		color2 = "#E5484D",
		price = { gems = 60 },
		tags = { "fancy", "royal" },
	}),
	item({
		id = "royal_crown",
		name = "Royal Crown",
		slot = "head",
		shape = "crown",
		color = "#FFD447",
		price = { gems = 150 },
		tags = { "royal", "fancy" },
	}),
	item({
		id = "party_hat",
		name = "Party Hat",
		slot = "head",
		shape = "cone",
		color = "#FF7AC8",
		color2 = "#FFE38A",
		price = { gems = 30 },
		tags = { "silly", "sweet" },
	}),
	item({
		id = "witch_hat",
		name = "Witch Hat",
		slot = "head",
		shape = "wizard",
		color = "#3A2D55",
		color2 = "#9B6BFF",
		price = { gems = 80 },
		tags = { "spooky" },
	}),
	item({
		id = "wizard_hat",
		name = "Star Wizard Hat",
		slot = "head",
		shape = "wizard",
		color = "#2E3A78",
		color2 = "#FFE680",
		price = { ribbons = 60 },
		tags = { "space", "fancy" },
	}),
	item({
		id = "beanie",
		name = "Cozy Beanie",
		slot = "head",
		shape = "beanie",
		color = "#4FB6F2",
		color2 = "#FFFFFF",
		price = { gems = 40 },
		tags = { "winter", "cute" },
	}),
	item({
		id = "flower_crown",
		name = "Flower Crown",
		slot = "head",
		shape = "flowers",
		color = "#FF9EC7",
		color2 = "#FFE38A",
		price = { ribbons = 40 },
		tags = { "nature", "cute" },
	}),
	item({
		id = "halo",
		name = "Halo",
		slot = "head",
		shape = "halo",
		color = "#FFF3B0",
		price = { gems = 120 },
		tags = { "space", "fancy" },
	}),
	item({
		id = "bunny_ears",
		name = "Bunny Ears",
		slot = "head",
		shape = "ears",
		color = "#FFFFFF",
		color2 = "#FFB3D1",
		price = { gems = 50 },
		tags = { "cute", "sweet" },
	}),
	item({
		id = "devil_horns",
		name = "Little Horns",
		slot = "head",
		shape = "horns",
		color = "#E5484D",
		price = { gems = 50 },
		tags = { "spooky", "silly" },
	}),
	item({
		id = "chef_hat",
		name = "Chef Hat",
		slot = "head",
		shape = "chef",
		color = "#FFFFFF",
		price = { gems = 45 },
		tags = { "sweet", "silly" },
	}),
	item({
		id = "sun_hat",
		name = "Sun Hat",
		slot = "head",
		shape = "brim",
		color = "#F4DFA6",
		color2 = "#FF6B6B",
		price = { gems = 55 },
		tags = { "beach" },
	}),
	item({
		id = "hero_helmet",
		name = "Hero Helmet",
		slot = "head",
		shape = "helmet",
		color = "#E5484D",
		color2 = "#FFD447",
		price = { ribbons = 80 },
		tags = { "hero", "sporty" },
	}),
	item({
		id = "space_helmet",
		name = "Space Helmet",
		slot = "head",
		shape = "bubble",
		color = "#DFF3FF",
		price = { ribbons = 120 },
		tags = { "space" },
	}),
	-- Face ---------------------------------------------------------------------------
	item({
		id = "round_glasses",
		name = "Round Glasses",
		slot = "face",
		shape = "glasses",
		color = "#2B2B2B",
		price = { gems = 35 },
		tags = { "fancy", "silly" },
	}),
	item({
		id = "sunglasses",
		name = "Sunglasses",
		slot = "face",
		shape = "shades",
		color = "#1D1D1D",
		price = { gems = 45 },
		tags = { "beach", "sporty" },
	}),
	item({
		id = "star_shades",
		name = "Star Shades",
		slot = "face",
		shape = "shades",
		color = "#FFD447",
		price = { ribbons = 50 },
		tags = { "space", "silly" },
	}),
	item({
		id = "monocle",
		name = "Monocle",
		slot = "face",
		shape = "monocle",
		color = "#FFD447",
		price = { gems = 70 },
		tags = { "fancy", "royal" },
	}),
	item({
		id = "hero_mask",
		name = "Hero Mask",
		slot = "face",
		shape = "mask",
		color = "#1D1D1D",
		price = { gems = 50 },
		tags = { "hero" },
	}),
	item({
		id = "mustache",
		name = "Dapper Mustache",
		slot = "face",
		shape = "mustache",
		color = "#5A3A1E",
		price = { gems = 25 },
		tags = { "silly", "fancy" },
	}),
	item({
		id = "blush",
		name = "Rosy Cheeks",
		slot = "face",
		shape = "blush",
		color = "#FF9EC7",
		price = { ribbons = 20 },
		tags = { "cute", "sweet" },
	}),
	item({
		id = "snorkel",
		name = "Snorkel",
		slot = "face",
		shape = "goggles",
		color = "#3FB6D9",
		price = { gems = 40 },
		tags = { "beach", "sporty" },
	}),
	-- Neck ---------------------------------------------------------------------------
	item({
		id = "red_scarf",
		name = "Red Scarf",
		slot = "neck",
		shape = "scarf",
		color = "#E5484D",
		price = { gems = 30 },
		tags = { "winter", "cute" },
	}),
	item({
		id = "bow_tie",
		name = "Bow Tie",
		slot = "neck",
		shape = "bowtie",
		color = "#2B2B2B",
		price = { gems = 35 },
		tags = { "fancy", "royal" },
	}),
	item({
		id = "pink_bow",
		name = "Big Pink Bow",
		slot = "neck",
		shape = "bowtie",
		color = "#FF7AC8",
		price = { ribbons = 30 },
		tags = { "cute", "sweet" },
	}),
	item({
		id = "gold_medal",
		name = "Gold Medal",
		slot = "neck",
		shape = "medal",
		color = "#FFD447",
		price = { ribbons = 100 },
		tags = { "sporty", "hero" },
	}),
	item({
		id = "flower_lei",
		name = "Flower Lei",
		slot = "neck",
		shape = "lei",
		color = "#FF6FA5",
		color2 = "#FFE38A",
		price = { gems = 45 },
		tags = { "beach", "nature" },
	}),
	item({
		id = "pearl_necklace",
		name = "Pearl Necklace",
		slot = "neck",
		shape = "lei",
		color = "#F4EFE4",
		price = { gems = 90 },
		tags = { "fancy", "royal" },
	}),
	item({
		id = "jingle_bell",
		name = "Jingle Bell",
		slot = "neck",
		shape = "bell",
		color = "#FFD447",
		color2 = "#E5484D",
		price = { gems = 30 },
		tags = { "winter", "silly" },
	}),
	-- Back ---------------------------------------------------------------------------
	item({
		id = "royal_cape",
		name = "Royal Cape",
		slot = "back",
		shape = "cape",
		color = "#8B2E8F",
		color2 = "#FFD447",
		price = { gems = 110 },
		tags = { "royal", "fancy" },
	}),
	item({
		id = "hero_cape",
		name = "Hero Cape",
		slot = "back",
		shape = "cape",
		color = "#E5484D",
		price = { ribbons = 70 },
		tags = { "hero" },
	}),
	item({
		id = "bat_wings",
		name = "Bat Wings",
		slot = "back",
		shape = "wings",
		color = "#3A2D55",
		price = { gems = 90 },
		tags = { "spooky" },
	}),
	item({
		id = "fairy_wings",
		name = "Fairy Wings",
		slot = "back",
		shape = "wings",
		color = "#DFF3FF",
		color2 = "#FF9EC7",
		price = { ribbons = 90 },
		tags = { "nature", "cute" },
	}),
	item({
		id = "backpack",
		name = "Explorer Pack",
		slot = "back",
		shape = "pack",
		color = "#D9A066",
		price = { gems = 40 },
		tags = { "sporty", "nature" },
	}),
	item({
		id = "jetpack",
		name = "Jetpack",
		slot = "back",
		shape = "jetpack",
		color = "#9AA39C",
		color2 = "#F0663A",
		price = { ribbons = 150 },
		tags = { "space", "hero" },
	}),
	item({
		id = "surfboard",
		name = "Surfboard",
		slot = "back",
		shape = "board",
		color = "#3FB6D9",
		color2 = "#FFFFFF",
		price = { gems = 60 },
		tags = { "beach", "sporty" },
	}),
	-- Ranch Pass Season 3 exclusives (never sold)
	item({
		id = "starlight_crown",
		name = "Starlight Crown",
		slot = "head",
		shape = "crown",
		color = "#B9A7FF",
		tags = { "royal", "space" },
	}),
	item({
		id = "rainbow_wings",
		name = "Rainbow Wings",
		slot = "back",
		shape = "wings",
		color = "#FF7AC8",
		color2 = "#7CC7FF",
		tags = { "cute", "nature" },
	}),
}

Accessories.ById = {}
for _, a in Accessories.List do
	assert(Accessories.ById[a.id] == nil, "duplicate accessory " .. a.id)
	assert(table.find(Accessories.Slots, a.slot), "bad accessory slot " .. a.id)
	Accessories.ById[a.id] = a
end

return Accessories
