--[[
	Genetics (update 3.6): stat genes. Pure rules shared by the server (rolls, inheritance,
	save migration) and the client (grades, breeding preview). Numbers live in Config.Genetics.

	Genes (monster record field `genes`):
	  { hp = { a, b }, atk = { a, b }, def = { a, b }, spd = { a, b } }
	  one gene from each parent per stat, each an integer 0..MaxGene. A stat's points are the
	  pair's sum and add PctPerPoint each to that stat (Formulas.Stats). A record without genes
	  (enemies, raid bosses) counts as all zero.

	  Genetics.Roll(rng) -> Genes                 hatched and rewarded monsters (HatchRange)
	  Genetics.Seeded(seed) -> Genes              the same roll from a seed (save migration)
	  Genetics.Inherit(rng, a, b) -> (Genes, surges)
	                                              a baby of parents' genes a and b: per stat one
	                                              gene of each parent's pair at random, then each
	                                              gene may surge +1 / +2 (capped). surges = count
	  Genetics.Valid(genes) -> boolean
	  Genetics.Copy(genes) -> Genes
	  Genetics.Pair(genes, stat) -> (number, number)
	  Genetics.Points(genes, stat) -> number      0..2 × MaxGene
	  Genetics.Bonus(genes, stat) -> number       fraction added to the stat (0.15 = +15%)
	  Genetics.Total(genes) -> number             points over every stat (0..MaxTotal)
	  Genetics.Grade(points) -> { grade, min, color }
	  Genetics.Range(a, b, stat) -> (lo, hi)      a baby's possible points before surges
	  Genetics.Preview(a, b) -> { stats = { { stat, lo, hi } }, surgeChance }
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)

local Rules = Config.Genetics

local Genetics = {}

Genetics.MaxTotal = #Rules.Stats * 2 * Rules.MaxGene

local function validGene(v): boolean
	return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= Rules.MaxGene
end

function Genetics.Valid(genes): boolean
	if type(genes) ~= "table" then
		return false
	end
	for _, stat in Rules.Stats do
		local pair = genes[stat]
		if type(pair) ~= "table" or not validGene(pair[1]) or not validGene(pair[2]) then
			return false
		end
	end
	return true
end

function Genetics.Pair(genes, stat: string): (number, number)
	local pair = if type(genes) == "table" then genes[stat] else nil
	if type(pair) ~= "table" then
		return 0, 0
	end
	local a = if validGene(pair[1]) then pair[1] else 0
	local b = if validGene(pair[2]) then pair[2] else 0
	return a, b
end

function Genetics.Copy(genes)
	local copy = {}
	for _, stat in Rules.Stats do
		local a, b = Genetics.Pair(genes, stat)
		copy[stat] = { a, b }
	end
	return copy
end

function Genetics.Points(genes, stat: string): number
	local a, b = Genetics.Pair(genes, stat)
	return a + b
end

function Genetics.Bonus(genes, stat: string): number
	return Genetics.Points(genes, stat) * Rules.PctPerPoint
end

function Genetics.Total(genes): number
	local total = 0
	for _, stat in Rules.Stats do
		total += Genetics.Points(genes, stat)
	end
	return total
end

function Genetics.Grade(points: number)
	for _, g in Rules.Grades do
		if points >= g.min then
			return g
		end
	end
	return Rules.Grades[#Rules.Grades]
end

function Genetics.Roll(rng)
	local lo, hi = Rules.HatchRange[1], Rules.HatchRange[2]
	local genes = {}
	for _, stat in Rules.Stats do
		genes[stat] = { rng:Int(lo, hi), rng:Int(lo, hi) }
	end
	return genes
end

function Genetics.Seeded(seed: number)
	return Genetics.Roll(Rng.new(seed))
end

local function surge(rng, gene: number): (number, boolean)
	local roll = rng:Next()
	local gain = if roll < Rules.BigSurgeChance then 2 elseif roll < Rules.BigSurgeChance + Rules.SurgeChance then 1 else 0
	if gain == 0 or gene >= Rules.MaxGene then
		return gene, false
	end
	return math.min(Rules.MaxGene, gene + gain), true
end

function Genetics.Inherit(rng, a, b)
	local genes, surges = {}, 0
	for _, stat in Rules.Stats do
		local a1, a2 = Genetics.Pair(a, stat)
		local b1, b2 = Genetics.Pair(b, stat)
		local fromA = if rng:Int(1, 2) == 1 then a1 else a2
		local fromB = if rng:Int(1, 2) == 1 then b1 else b2
		local surgedA, surgedB
		fromA, surgedA = surge(rng, fromA)
		fromB, surgedB = surge(rng, fromB)
		surges += (if surgedA then 1 else 0) + (if surgedB then 1 else 0)
		genes[stat] = { fromA, fromB }
	end
	return genes, surges
end

function Genetics.Range(a, b, stat: string): (number, number)
	local a1, a2 = Genetics.Pair(a, stat)
	local b1, b2 = Genetics.Pair(b, stat)
	return math.min(a1, a2) + math.min(b1, b2), math.max(a1, a2) + math.max(b1, b2)
end

function Genetics.Preview(a, b)
	local stats = {}
	for _, stat in Rules.Stats do
		local lo, hi = Genetics.Range(a, b, stat)
		table.insert(stats, { stat = stat, lo = lo, hi = hi })
	end
	return { stats = stats, surgeChance = Rules.SurgeChance + Rules.BigSurgeChance }
end

return Genetics
