--[[
	Species lines. A line is one monster family with three stages:
	  stage 1 = Baby, stage 2 = Teen, stage 3 = Adult.
	Branching lines have several adult forms; the teen's majority diet flavour picks one
	(`diet` on each adult form, the first adult is the default).

	archetype: which placeholder body the Visuals builders draw
	  blob · fox · bunny · moth · slug · bug · golem · sprite
	base: stats of a Common, level 1, 1-star adult. Stage scaling is in Economy.Stages.
	weight: average adult weight in kg (rolled 0.5×–2× at birth).
	special / passive: ids from Species.Skills / Species.Passives (used by BattleSim).
	pools: which egg pools this line can hatch from.
	added: the update that introduced the line (lines without it shipped at launch).
]]

local Species = {}

Species.Skills = {
	strike = { name = "Strike", target = "single", power = 2.2, desc = "A heavy hit on one enemy." },
	blast = { name = "Blast", target = "all", power = 1.2, desc = "Hits every enemy." },
	heal = { name = "Mend", target = "allies", heal = 0.25, desc = "Heals every ally for 25% of their max HP." },
	shield = { name = "Shell Up", target = "allies", shield = 0.2, desc = "Shields every ally for 20% of their max HP." },
	taunt = { name = "Taunt", target = "self", turns = 2, defUp = 0.3, desc = "Draws every attack for 2 turns and raises DEF." },
	drain = { name = "Drain", target = "single", power = 1.6, lifesteal = 0.5, desc = "Hits one enemy and heals for half the damage." },
	stun = { name = "Jolt", target = "single", power = 1.4, stunChance = 0.3, desc = "Hits one enemy with a 30% chance to stun." },
}

Species.Passives = {
	thorns = { name = "Thorns", value = 0.15, desc = "Reflects 15% of damage taken." },
	crit = { name = "Keen", value = 0.15, desc = "+15% critical hit chance." },
	regen = { name = "Regrowth", value = 0.05, desc = "Heals 5% of max HP each turn." },
	haste = { name = "Tailwind", value = 0.1, desc = "+10% SPD for the whole squad." },
	guard = { name = "Sturdy", value = 0.1, desc = "Takes 10% less damage." },
	rally = { name = "Rally", value = 0.08, desc = "+8% ATK for the whole squad." },
	lucky = { name = "Treasure Nose", value = 0.1, desc = "+10% expedition loot." },
}

local function line(def)
	return def
end

Species.Lines = {
	-- ── Ember ─────────────────────────────────────────────────────────────
	line({
		id = "cindlet",
		elements = { "ember" },
		archetype = "fox",
		forms = {
			{ id = "cindlet", name = "Cindlet" },
			{ id = "kindlefox", name = "Kindlefox" },
			{
				{ id = "blazefang", name = "Blazefang", diet = "spicy" },
				{ id = "hearthtail", name = "Hearthtail", diet = "sweet" },
			},
		},
		base = { hp = 120, atk = 34, def = 18, spd = 14, luck = 4 },
		weight = 3.2,
		special = "strike",
		passive = "crit",
		pools = { "common" },
	}),
	line({
		id = "scorchmoth",
		elements = { "ember" },
		archetype = "moth",
		forms = {
			{ id = "scorchling", name = "Scorchling" },
			{ id = "scorchmoth", name = "Scorchmoth" },
			{ { id = "pyremoth", name = "Pyremoth" } },
		},
		base = { hp = 95, atk = 30, def = 14, spd = 19, luck = 6 },
		weight = 0.9,
		special = "blast",
		passive = "haste",
		pools = { "common" },
	}),
	line({
		id = "emberslug",
		elements = { "ember" },
		archetype = "slug",
		forms = {
			{ id = "emberslug", name = "Emberslug" },
			{ id = "magmaslug", name = "Magmaslug" },
			{ { id = "cinderwyrm", name = "Cinderwyrm" } },
		},
		base = { hp = 150, atk = 26, def = 24, spd = 9, luck = 3 },
		weight = 5.5,
		special = "drain",
		passive = "thorns",
		pools = { "common" },
	}),
	-- ── Tide ──────────────────────────────────────────────────────────────
	line({
		id = "bubblin",
		elements = { "tide" },
		archetype = "blob",
		forms = {
			{ id = "bubblin", name = "Bubblin" },
			{ id = "brinelotl", name = "Brinelotl" },
			{
				{ id = "tsunamander", name = "Tsunamander", diet = "sour" },
				{ id = "pearlfin", name = "Pearlfin", diet = "sweet" },
			},
		},
		base = { hp = 130, atk = 28, def = 20, spd = 13, luck = 5 },
		weight = 2.6,
		special = "blast",
		passive = "regen",
		pools = { "common" },
	}),
	line({
		id = "drizzlet",
		elements = { "tide" },
		archetype = "sprite",
		forms = { { id = "drizzlet", name = "Drizzlet" }, { id = "rainpuff", name = "Rainpuff" }, { { id = "nimbuff", name = "Nimbuff" } } },
		base = { hp = 100, atk = 22, def = 16, spd = 17, luck = 8 },
		weight = 0.6,
		special = "heal",
		passive = "lucky",
		pools = { "common" },
	}),
	line({
		id = "coralbun",
		elements = { "tide" },
		archetype = "bunny",
		forms = { { id = "coralbun", name = "Coralbun" }, { id = "reefhop", name = "Reefhop" }, { { id = "coralord", name = "Coralord" } } },
		base = { hp = 125, atk = 25, def = 26, spd = 12, luck = 4 },
		weight = 3.8,
		special = "shield",
		passive = "guard",
		pools = { "common" },
	}),
	-- ── Sprout ────────────────────────────────────────────────────────────
	line({
		id = "mossbun",
		elements = { "sprout" },
		archetype = "bunny",
		forms = {
			{ id = "mossbun", name = "Mossbun" },
			{ id = "clovermane", name = "Clovermane" },
			{
				{ id = "thornbuck", name = "Thornbuck", diet = "savory" },
				{ id = "bloomhorn", name = "Bloomhorn", diet = "sweet" },
			},
		},
		base = { hp = 135, atk = 27, def = 22, spd = 13, luck = 5 },
		weight = 4.1,
		special = "heal",
		passive = "regen",
		pools = { "common" },
	}),
	line({
		id = "petalpaw",
		elements = { "sprout" },
		archetype = "fox",
		forms = {
			{ id = "petalpaw", name = "Petalpaw" },
			{ id = "blossomcat", name = "Blossomcat" },
			{ { id = "florallynx", name = "Florallynx" } },
		},
		base = { hp = 105, atk = 32, def = 15, spd = 18, luck = 6 },
		weight = 2.9,
		special = "strike",
		passive = "crit",
		pools = { "common" },
	}),
	line({
		id = "acornling",
		elements = { "sprout" },
		archetype = "golem",
		forms = {
			{ id = "acornling", name = "Acornling" },
			{ id = "oakling", name = "Oakling" },
			{ { id = "elderoak", name = "Elderoak" } },
		},
		base = { hp = 165, atk = 22, def = 30, spd = 8, luck = 3 },
		weight = 9.0,
		special = "taunt",
		passive = "thorns",
		pools = { "common" },
	}),
	-- ── Spark ─────────────────────────────────────────────────────────────
	line({
		id = "zappip",
		elements = { "spark" },
		archetype = "fox",
		forms = {
			{ id = "zappip", name = "Zappip" },
			{ id = "voltfurr", name = "Voltfurr" },
			{
				{ id = "stormwhisker", name = "Stormwhisker", diet = "spicy" },
				{ id = "glowtail", name = "Glowtail", diet = "sour" },
			},
		},
		base = { hp = 105, atk = 33, def = 15, spd = 20, luck = 5 },
		weight = 1.8,
		special = "stun",
		passive = "haste",
		pools = { "common" },
	}),
	line({
		id = "buzzbee",
		elements = { "spark" },
		archetype = "bug",
		forms = {
			{ id = "buzzbee", name = "Buzzbee" },
			{ id = "hummbolt", name = "Hummbolt" },
			{ { id = "thunderqueen", name = "Thunderqueen" } },
		},
		base = { hp = 95, atk = 31, def = 14, spd = 21, luck = 7 },
		weight = 0.7,
		special = "blast",
		passive = "rally",
		pools = { "common" },
	}),
	line({
		id = "staticat",
		elements = { "spark" },
		archetype = "fox",
		forms = {
			{ id = "staticat", name = "Staticat" },
			{ id = "sparkitty", name = "Sparkitty" },
			{ { id = "voltpanther", name = "Voltpanther" } },
		},
		base = { hp = 115, atk = 35, def = 17, spd = 18, luck = 4 },
		weight = 3.4,
		special = "strike",
		passive = "crit",
		pools = { "common" },
	}),
	-- ── Stone ─────────────────────────────────────────────────────────────
	line({
		id = "pebblet",
		elements = { "stone" },
		archetype = "golem",
		forms = {
			{ id = "pebblet", name = "Pebblet" },
			{ id = "cragrump", name = "Cragrump" },
			{
				{ id = "boulderback", name = "Boulderback", diet = "savory" },
				{ id = "geodeon", name = "Geodeon", diet = "sour" },
			},
		},
		base = { hp = 170, atk = 24, def = 32, spd = 7, luck = 3 },
		weight = 12.0,
		special = "taunt",
		passive = "guard",
		pools = { "common" },
	}),
	line({
		id = "rumblet",
		elements = { "stone" },
		archetype = "blob",
		forms = {
			{ id = "rumblet", name = "Rumblet" },
			{ id = "quakemole", name = "Quakemole" },
			{ { id = "terramole", name = "Terramole" } },
		},
		base = { hp = 140, atk = 29, def = 25, spd = 11, luck = 6 },
		weight = 4.8,
		special = "stun",
		passive = "lucky",
		pools = { "common" },
	}),
	line({
		id = "crystomp",
		elements = { "stone" },
		archetype = "golem",
		forms = {
			{ id = "crystomp", name = "Crystomp" },
			{ id = "quartzhorn", name = "Quartzhorn" },
			{ { id = "gemmoth", name = "Gemmoth" } },
		},
		base = { hp = 160, atk = 30, def = 28, spd = 8, luck = 5 },
		weight = 14.0,
		special = "shield",
		passive = "thorns",
		pools = { "common" },
	}),
	-- ── Gloom ─────────────────────────────────────────────────────────────
	line({
		id = "hushling",
		elements = { "gloom" },
		archetype = "sprite",
		forms = {
			{ id = "hushling", name = "Hushling" },
			{ id = "murkmoth", name = "Murkmoth" },
			{
				{ id = "hollowgaze", name = "Hollowgaze", diet = "sour" },
				{ id = "moonveil", name = "Moonveil", diet = "sweet" },
			},
		},
		base = { hp = 110, atk = 31, def = 16, spd = 16, luck = 7 },
		weight = 1.1,
		special = "drain",
		passive = "crit",
		pools = { "common" },
	}),
	line({
		id = "wisplet",
		elements = { "gloom" },
		archetype = "sprite",
		forms = {
			{ id = "wisplet", name = "Wisplet" },
			{ id = "wispkin", name = "Wispkin" },
			{ { id = "lanternshade", name = "Lanternshade" } },
		},
		base = { hp = 100, atk = 27, def = 15, spd = 19, luck = 9 },
		weight = 0.5,
		special = "heal",
		passive = "lucky",
		pools = { "common" },
	}),
	line({
		id = "gloomcap",
		elements = { "gloom" },
		archetype = "blob",
		forms = {
			{ id = "gloomcap", name = "Gloomcap" },
			{ id = "shadeshroom", name = "Shadeshroom" },
			{ { id = "umbracap", name = "Umbracap" } },
		},
		base = { hp = 145, atk = 26, def = 24, spd = 10, luck = 5 },
		weight = 3.0,
		special = "stun",
		passive = "regen",
		pools = { "common" },
	}),
	-- ── Hybrids (breeding only; also rare Stampede drops) ─────────────────
	line({
		id = "steamling",
		elements = { "ember", "tide" },
		archetype = "blob",
		hybrid = true,
		forms = {
			{ id = "steamling", name = "Steamling" },
			{ id = "vaporkin", name = "Vaporkin" },
			{ { id = "geyserdrake", name = "Geyserdrake" } },
		},
		base = { hp = 140, atk = 36, def = 22, spd = 15, luck = 6 },
		weight = 4.0,
		special = "blast",
		passive = "haste",
		pools = { "hybrid" },
	}),
	line({
		id = "mudpuff",
		elements = { "tide", "stone" },
		archetype = "blob",
		hybrid = true,
		forms = { { id = "mudpuff", name = "Mudpuff" }, { id = "bogtoad", name = "Bogtoad" }, { { id = "mireback", name = "Mireback" } } },
		base = { hp = 185, atk = 25, def = 34, spd = 8, luck = 5 },
		weight = 10.0,
		special = "taunt",
		passive = "guard",
		pools = { "hybrid" },
	}),
	line({
		id = "thornbolt",
		elements = { "spark", "sprout" },
		archetype = "bug",
		hybrid = true,
		forms = {
			{ id = "thornbolt", name = "Thornbolt" },
			{ id = "voltvine", name = "Voltvine" },
			{ { id = "thundergrove", name = "Thundergrove" } },
		},
		base = { hp = 125, atk = 37, def = 19, spd = 18, luck = 6 },
		weight = 2.4,
		special = "stun",
		passive = "rally",
		pools = { "hybrid" },
	}),
	line({
		id = "lavashell",
		elements = { "ember", "stone" },
		archetype = "golem",
		hybrid = true,
		forms = {
			{ id = "lavashell", name = "Lavashell" },
			{ id = "magmatle", name = "Magmatle" },
			{ { id = "volcanoise", name = "Volcanoise" } },
		},
		base = { hp = 175, atk = 30, def = 33, spd = 8, luck = 4 },
		weight = 16.0,
		special = "shield",
		passive = "thorns",
		pools = { "hybrid" },
	}),
	line({
		id = "eclipsette",
		elements = { "gloom", "spark" },
		archetype = "moth",
		hybrid = true,
		forms = {
			{ id = "eclipsette", name = "Eclipsette" },
			{ id = "umbravolt", name = "Umbravolt" },
			{ { id = "eclipsior", name = "Eclipsior" } },
		},
		base = { hp = 115, atk = 38, def = 17, spd = 20, luck = 9 },
		weight = 1.2,
		special = "drain",
		passive = "lucky",
		pools = { "hybrid" },
	}),
	line({
		id = "mirebloom",
		elements = { "gloom", "sprout" },
		archetype = "sprite",
		hybrid = true,
		forms = {
			{ id = "mirebloom", name = "Mirebloom" },
			{ id = "bogblossom", name = "Bogblossom" },
			{ { id = "nightbloom", name = "Nightbloom" } },
		},
		base = { hp = 150, atk = 28, def = 24, spd = 13, luck = 6 },
		weight = 3.6,
		special = "heal",
		passive = "regen",
		pools = { "hybrid" },
	}),
	-- ── Coral Depths (update 1.1) · hatch only from Pearl Eggs ─────────────
	line({
		id = "shellsnap",
		elements = { "tide" },
		archetype = "bug",
		added = "1.1",
		forms = {
			{ id = "shellsnap", name = "Shellsnap" },
			{ id = "clawcrest", name = "Clawcrest" },
			{
				{ id = "tidecrusher", name = "Tidecrusher", diet = "sour" },
				{ id = "pearlguard", name = "Pearlguard", diet = "sweet" },
			},
		},
		base = { hp = 150, atk = 30, def = 30, spd = 9, luck = 4 },
		weight = 7.5,
		special = "taunt",
		passive = "thorns",
		pools = { "pearl" },
	}),
	line({
		id = "jellow",
		elements = { "spark" },
		archetype = "blob",
		added = "1.1",
		forms = {
			{ id = "jellow", name = "Jellow" },
			{ id = "glimmerjel", name = "Glimmerjel" },
			{ { id = "voltmedusa", name = "Voltmedusa" } },
		},
		base = { hp = 100, atk = 38, def = 14, spd = 20, luck = 7 },
		weight = 0.9,
		special = "stun",
		passive = "haste",
		pools = { "pearl" },
	}),
	line({
		id = "anglit",
		elements = { "tide", "spark" },
		archetype = "slug",
		added = "1.1",
		forms = {
			{ id = "anglit", name = "Anglit" },
			{ id = "lanternfin", name = "Lanternfin" },
			{ { id = "abyssangler", name = "Abyssangler" } },
		},
		base = { hp = 130, atk = 36, def = 20, spd = 13, luck = 10 },
		weight = 5.0,
		special = "drain",
		passive = "lucky",
		pools = { "pearl" },
	}),
	-- ── Lunar Lanterns event (update 1.2) ─────────────────────────────────
	line({
		id = "lanternling",
		elements = { "ember", "spark" },
		archetype = "fox",
		event = "lunarlanterns",
		added = "1.2",
		forms = {
			{ id = "lanternling", name = "Lanternling" },
			{ id = "lanternwyrm", name = "Lanternwyrm" },
			{ { id = "lanterndragon", name = "Lantern Dragon" } },
		},
		base = { hp = 140, atk = 40, def = 22, spd = 16, luck = 8 },
		weight = 6.0,
		special = "blast",
		passive = "rally",
		pools = { "lunarlanterns" },
	}),
	line({
		id = "mochibun",
		elements = { "stone" },
		archetype = "bunny",
		event = "lunarlanterns",
		added = "1.2",
		forms = {
			{ id = "mochibun", name = "Mochibun" },
			{ id = "mooncrest", name = "Mooncrest" },
			{ { id = "jadehare", name = "Jadehare" } },
		},
		base = { hp = 150, atk = 26, def = 30, spd = 12, luck = 9 },
		weight = 2.8,
		special = "shield",
		passive = "lucky",
		pools = { "lunarlanterns" },
	}),
	line({
		id = "wickit",
		elements = { "spark" },
		archetype = "sprite",
		event = "lunarlanterns",
		added = "1.2",
		forms = {
			{ id = "wickit", name = "Wickit" },
			{ id = "crackleflit", name = "Crackleflit" },
			{ { id = "skyblossom", name = "Skyblossom" } },
		},
		base = { hp = 100, atk = 39, def = 15, spd = 21, luck = 7 },
		weight = 0.5,
		special = "stun",
		passive = "haste",
		pools = { "lunarlanterns" },
	}),
	-- ── Frostfall event (winter 2026) ─────────────────────────────────────
	line({
		id = "snowmitt",
		elements = { "tide" },
		archetype = "bunny",
		event = "frostfall",
		forms = {
			{ id = "snowmitt", name = "Snowmitt" },
			{ id = "frostpaw", name = "Frostpaw" },
			{ { id = "glacierfang", name = "Glacierfang" } },
		},
		base = { hp = 135, atk = 33, def = 22, spd = 15, luck = 6 },
		weight = 3.5,
		special = "blast",
		passive = "guard",
		pools = { "frostfall" },
	}),
	line({
		id = "pinepip",
		elements = { "sprout" },
		archetype = "golem",
		event = "frostfall",
		forms = {
			{ id = "pinepip", name = "Pinepip" },
			{ id = "sprucesprout", name = "Sprucesprout" },
			{ { id = "evergrand", name = "Evergrand" } },
		},
		base = { hp = 170, atk = 26, def = 30, spd = 9, luck = 5 },
		weight = 8.0,
		special = "shield",
		passive = "regen",
		pools = { "frostfall" },
	}),
	line({
		id = "frostfly",
		elements = { "spark" },
		archetype = "moth",
		event = "frostfall",
		forms = {
			{ id = "frostfly", name = "Frostfly" },
			{ id = "icewing", name = "Icewing" },
			{ { id = "aurorawing", name = "Aurorawing" } },
		},
		base = { hp = 105, atk = 36, def = 16, spd = 21, luck = 8 },
		weight = 0.8,
		special = "stun",
		passive = "haste",
		pools = { "frostfall" },
	}),
}

-- Lookups ---------------------------------------------------------------

Species.ById = {}
Species.FormById = {} -- formId -> { line = lineDef, stage = n, form = formDef }
Species.Pools = {} -- poolId -> { lineId, ... }

for _, def in Species.Lines do
	Species.ById[def.id] = def
	for stage, entry in def.forms do
		if stage == 3 then
			for _, form in entry do
				Species.FormById[form.id] = { line = def, stage = 3, form = form }
			end
		else
			Species.FormById[entry.id] = { line = def, stage = stage, form = entry }
		end
	end
	for _, pool in def.pools do
		Species.Pools[pool] = Species.Pools[pool] or {}
		table.insert(Species.Pools[pool], def.id)
	end
end

-- Returns the form definition for a line at a stage. For adults, `formId` picks the branch.
function Species.Form(lineId: string, stage: number, formId: string?)
	local def = Species.ById[lineId]
	if not def then
		return nil
	end
	if stage < 3 then
		return def.forms[stage]
	end
	local adults = def.forms[3]
	if formId then
		for _, form in adults do
			if form.id == formId then
				return form
			end
		end
	end
	return adults[1]
end

-- Picks the adult branch from a diet table { sweet = n, spicy = n, savory = n, sour = n }.
-- The flavour with the most meals wins; ties and unmatched flavours fall back to the first adult.
function Species.AdultForDiet(lineId: string, diet: { [string]: number }?)
	local def = Species.ById[lineId]
	local adults = def.forms[3]
	if #adults == 1 or not diet then
		return adults[1]
	end
	local bestFlavor, bestCount, tie = nil, 0, false
	for flavor, count in diet do
		if count > bestCount then
			bestFlavor, bestCount, tie = flavor, count, false
		elseif count == bestCount and count > 0 then
			tie = true
		end
	end
	if bestFlavor and not tie then
		for _, form in adults do
			if form.diet == bestFlavor then
				return form
			end
		end
	end
	return adults[1]
end

function Species.IsBranching(lineId: string): boolean
	local def = Species.ById[lineId]
	return def ~= nil and #def.forms[3] > 1
end

return Species
