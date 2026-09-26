--[[
	PROTOTYPE (not part of the game): a pet genome for breeding, so a baby carries physical parts,
	stats and skills from both parents. Pure Luau, no Roblox APIs, self-contained (its own RNG),
	so it runs in Lune (prototypes/pet-genetics/test.luau) and in Studio (Lab.luau).

	The idea: each pet is built from PARTS (body, ears, tail, legs, back), each part generated
	once per species with Roblox's mesh generator (PartLibrary.luau). A genome holds two ALLELES
	per part slot (locus), one from each parent, like Mendel's peas:

	  locus     one part slot: body (the cube + face), ears (ears/horns), tail, legs, back (wings)
	  allele    a species id, or "none" for a species that lacks the part (a cat has no wings)
	  express   the allele with the higher dominance shows; a tie is a seeded coin flip.
	            The other one is carried silently and can come back in the grandchildren.
	  colour    two colour alleles, codominant: the pet's tint is their blend
	  size      polygenic: the parents' average, jittered
	  stats     a baby inherits a random point between its parents' base stats, jittered
	            (some babies beat both parents); expressed parts then add their own modifiers
	  skills    innate skills: up to 2 drawn from both parents' innate skills (small chance of a
	            brand-new one); part skills come with the expressed part (wings give Glide), so
	            what a pet looks like and what it can do always agree

	Genetics.fromSpecies(id) -> Genome                pure-bred founder
	Genetics.breed(seed, a, b) -> Genome              baby of a and b (deterministic per seed)
	Genetics.express(genome) -> Phenotype             what it looks like and can do
	Genetics.describe(genome) -> string               one-line summary for labels and logs
]]

local Genetics = {}

-- Content -----------------------------------------------------------------------------------

Genetics.Loci = { "body", "ears", "tail", "legs", "back" }
Genetics.StatNames = { "power", "speed", "luck", "vitality" }

-- Per species: which parts it has, how dominant each is, its colour, base stats and innate skills.
-- Dominance: higher shows over lower; most parts tie at 2 so a litter varies, and a few
-- characterful ones win outright (horns, wings, a corgi's short legs, a tiger's tail).
-- "none" (a missing part) has its own dominance per locus (NoneDominance).
Genetics.Species = {
	dragon = {
		name = "Dragon",
		color = { 0.33, 0.78, 0.33 },
		dominance = { body = 2, ears = 3, tail = 2, legs = 1, back = 3 },
		stats = { power = 16, speed = 9, luck = 5, vitality = 13 },
		skills = { "Fire Breath", "Hoard" },
	},
	cat = {
		name = "Cat",
		color = { 0.62, 0.64, 0.7 },
		dominance = { body = 2, ears = 2, tail = 2, legs = 2 },
		stats = { power = 8, speed = 14, luck = 12, vitality = 9 },
		skills = { "Nine Lives", "Pounce" },
	},
	dog = {
		name = "Puppy",
		color = { 0.6, 0.4, 0.26 },
		dominance = { body = 2, ears = 1, tail = 2, legs = 2 },
		stats = { power = 11, speed = 11, luck = 8, vitality = 12 },
		skills = { "Fetch", "Loyal Guard" },
	},
	corgi = {
		name = "Corgi",
		color = { 0.95, 0.6, 0.3 },
		dominance = { body = 2, ears = 2, tail = 1, legs = 3 },
		stats = { power = 9, speed = 13, luck = 11, vitality = 10 },
		skills = { "Zoomies", "Fetch" },
	},
	chick = {
		name = "Chick",
		color = { 1, 0.86, 0.3 },
		dominance = { body = 2, ears = 2, legs = 1, back = 1 }, -- no tail: the beak is part of its face
		stats = { power = 5, speed = 10, luck = 16, vitality = 7 },
		skills = { "Lucky Peck", "Early Bird" },
	},
	tiger = {
		name = "Tiger",
		color = { 1, 0.55, 0.15 },
		dominance = { body = 2, ears = 2, tail = 3, legs = 2 },
		stats = { power = 15, speed = 12, luck = 6, vitality = 11 },
		skills = { "Roar", "Pounce" },
	},
}

-- A missing part is recessive to having one (a winged parent's babies usually have wings).
Genetics.NoneDominance = { body = 0, ears = 0.5, tail = 0.5, legs = 0, back = 0.5 }

-- What an expressed part adds: stat modifiers and a skill. Keyed by locus, then species.
Genetics.PartEffects = {
	ears = {
		dragon = { stats = { power = 2 }, skill = "Horn Charge" },
		cat = { stats = { luck = 2 }, skill = "Keen Ears" },
		corgi = { stats = { luck = 1 } },
		tiger = { stats = { power = 1 } },
	},
	tail = {
		dragon = { stats = { power = 1 }, skill = "Tail Swipe" },
		tiger = { stats = { speed = 1 }, skill = "Stripe Dash" },
		cat = { stats = { luck = 1 } },
		dog = { stats = { vitality = 1 } },
	},
	legs = {
		corgi = { stats = { speed = 3 }, skill = "Zoomies" },
		tiger = { stats = { speed = 2 } },
		cat = { stats = { speed = 1 } },
	},
	back = {
		dragon = { stats = { speed = 3 }, skill = "Glide" },
		chick = { stats = { luck = 2 }, skill = "Flutter" },
	},
}

-- Brand-new skills a baby can be born with (Genetics.Rules.skillMutation).
Genetics.MutationSkills = { "Sparkle", "Double Nap", "Treasure Nose", "Sturdy", "Moonlit" }

Genetics.Rules = {
	alleleMutation = 0.01, -- per allele: becomes a random species' part instead
	skillMutation = 0.06, -- chance of one brand-new innate skill
	innateSkills = 2, -- innate skills a pet keeps
	statJitter = { 0.92, 1.12 }, -- x the inherited stat
	sizeJitter = 0.06, -- +- fraction of the parents' average size
	colorJitter = 0.04, -- +- per channel
}

-- RNG (mulberry32, same as Logic/Rng, kept here so the prototype stands alone) ----------------

local band, bor, bxor, rshift, lshift = bit32.band, bit32.bor, bit32.bxor, bit32.rshift, bit32.lshift

local function imul(a: number, b: number): number
	local ah, al = rshift(a, 16), band(a, 0xFFFF)
	local bh, bl = rshift(b, 16), band(b, 0xFFFF)
	local high = band(ah * bl + al * bh, 0xFFFF)
	return band(al * bl + lshift(high, 16), 0xFFFFFFFF)
end

local function newRng(seed: number)
	local state = band(math.floor(seed) % 4294967296, 0xFFFFFFFF)
	local rng = {}
	function rng.next(): number
		local t = band(state + 0x6D2B79F5, 0xFFFFFFFF)
		state = t
		t = imul(bxor(t, rshift(t, 15)), bor(t, 1))
		t = bxor(t, band(t + imul(bxor(t, rshift(t, 7)), bor(t, 61)), 0xFFFFFFFF))
		return bxor(t, rshift(t, 14)) / 4294967296
	end
	function rng.float(lo: number, hi: number): number
		return lo + rng.next() * (hi - lo)
	end
	function rng.int(lo: number, hi: number): number
		return lo + math.floor(rng.next() * (hi - lo + 1))
	end
	function rng.chance(p: number): boolean
		return rng.next() < p
	end
	return rng
end
Genetics.newRng = newRng

-- Types ---------------------------------------------------------------------------------------

export type Genome = {
	loci: { [string]: { string } }, -- locus -> { allele from parent 1, allele from parent 2 }
	color: { { number } }, -- two RGB alleles (0..1)
	size: number, -- studs, the body's largest dimension
	stats: { [string]: number }, -- base stats (before part modifiers)
	innate: { string }, -- innate skills
	generation: number,
	seed: number,
}

export type Phenotype = {
	parts: { [string]: string }, -- locus -> species id or "none"
	color: { number },
	size: number,
	stats: { [string]: number },
	skills: { string },
}

-- Helpers -------------------------------------------------------------------------------------

local function speciesIds(): { string }
	local ids = {}
	for id in Genetics.Species do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- The allele a species carries at a locus: its own part, or "none" if it has no such part.
local function alleleOf(speciesId: string, locus: string): string
	local def = Genetics.Species[speciesId]
	return if def and def.dominance[locus] ~= nil then speciesId else "none"
end

local function dominance(allele: string, locus: string): number
	if allele == "none" then
		return Genetics.NoneDominance[locus] or 0
	end
	return Genetics.Species[allele].dominance[locus] or 0
end

-- Which allele of a pair shows. A tie flips a coin seeded by the genome, so the same genome
-- always looks the same.
local function expressed(pair: { string }, locus: string, seed: number, index: number): string
	local a, b = pair[1], pair[2]
	if a == b then
		return a
	end
	local da, db = dominance(a, locus), dominance(b, locus)
	if da ~= db then
		return if da > db then a else b
	end
	return if newRng(seed + index * 7919).chance(0.5) then a else b
end

local function contains(list: { string }, value: string): boolean
	return table.find(list, value) ~= nil
end

-- API -----------------------------------------------------------------------------------------

function Genetics.fromSpecies(id: string): Genome
	local def = assert(Genetics.Species[id], "unknown species " .. tostring(id))
	local loci = {}
	for _, locus in Genetics.Loci do
		local allele = alleleOf(id, locus)
		loci[locus] = { allele, allele }
	end
	return {
		loci = loci,
		color = { table.clone(def.color), table.clone(def.color) },
		size = 5,
		stats = table.clone(def.stats),
		innate = table.clone(def.skills),
		generation = 0,
		seed = 0,
	}
end

function Genetics.breed(seed: number, a: Genome, b: Genome): Genome
	local rng = newRng(seed)
	local R = Genetics.Rules
	local ids = speciesIds()

	-- Parts: one allele from each parent, picked at random from that parent's pair.
	local loci = {}
	for _, locus in Genetics.Loci do
		local pair = {}
		for i, parent in { a, b } do
			local allele = parent.loci[locus][rng.int(1, 2)]
			if rng.chance(R.alleleMutation) then
				allele = alleleOf(ids[rng.int(1, #ids)], locus)
			end
			pair[i] = allele
		end
		loci[locus] = pair
	end

	-- Colour: one colour allele from each parent, jittered a little.
	local color = {}
	for i, parent in { a, b } do
		local c = parent.color[rng.int(1, 2)]
		color[i] = {}
		for ch = 1, 3 do
			color[i][ch] = math.clamp(c[ch] + rng.float(-R.colorJitter, R.colorJitter), 0, 1)
		end
	end

	-- Stats: a random point between the parents, jittered.
	local stats = {}
	for _, name in Genetics.StatNames do
		local lo, hi = a.stats[name], b.stats[name]
		local mid = lo + (hi - lo) * rng.next()
		stats[name] = math.max(1, math.round(mid * rng.float(R.statJitter[1], R.statJitter[2])))
	end

	-- Innate skills: drawn from both parents' pool, with a small chance of a brand-new one.
	local pool = {}
	for _, parent in { a, b } do
		for _, skill in parent.innate do
			if not contains(pool, skill) then
				table.insert(pool, skill)
			end
		end
	end
	local innate = {}
	if rng.chance(R.skillMutation) then
		table.insert(innate, Genetics.MutationSkills[rng.int(1, #Genetics.MutationSkills)])
	end
	while #innate < R.innateSkills and #pool > 0 do
		local skill = table.remove(pool, rng.int(1, #pool))
		if not contains(innate, skill) then
			table.insert(innate, skill)
		end
	end

	local size = (a.size + b.size) / 2 * (1 + rng.float(-R.sizeJitter, R.sizeJitter))
	return {
		loci = loci,
		color = color,
		size = size,
		stats = stats,
		innate = innate,
		generation = math.max(a.generation, b.generation) + 1,
		seed = seed,
	}
end

function Genetics.express(g: Genome): Phenotype
	local parts = {}
	for i, locus in Genetics.Loci do
		parts[locus] = expressed(g.loci[locus], locus, g.seed, i)
	end
	local color = {}
	for ch = 1, 3 do
		color[ch] = (g.color[1][ch] + g.color[2][ch]) / 2
	end
	local stats = table.clone(g.stats)
	local skills = table.clone(g.innate)
	for _, locus in Genetics.Loci do
		local effect = (Genetics.PartEffects[locus] or {})[parts[locus]]
		if effect then
			for name, add in effect.stats or {} do
				stats[name] += add
			end
			if effect.skill and not contains(skills, effect.skill) then
				table.insert(skills, effect.skill)
			end
		end
	end
	return { parts = parts, color = color, size = g.size, stats = stats, skills = skills }
end

function Genetics.describe(g: Genome): string
	local p = Genetics.express(g)
	local bits = {}
	for _, locus in Genetics.Loci do
		local shown = p.parts[locus]
		local pair = g.loci[locus]
		local hidden = if pair[1] == shown then pair[2] else pair[1]
		table.insert(bits, string.format("%s=%s%s", locus, shown, if hidden ~= shown then "(" .. hidden .. ")" else ""))
	end
	local stats = {}
	for _, name in Genetics.StatNames do
		table.insert(stats, string.format("%s %d", name:sub(1, 3), p.stats[name]))
	end
	return string.format("gen %d | %s | %s | %s", g.generation, table.concat(bits, " "), table.concat(stats, " "), table.concat(p.skills, ", "))
end

return Genetics
