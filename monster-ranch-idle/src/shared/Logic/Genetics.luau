--[[
	Genetics (update 3.6): stat genes. Pure rules shared by the server (rolls, inheritance,
	save migration) and the client (grades, breeding preview). Numbers live in Config.Genetics.

	Genes (monster record field `genes`):
	  { hp = { a, b }, atk = { a, b }, def = { a, b }, spd = { a, b }, luck = { a, b } }
	  one gene from each parent per stat, each an integer 0..MaxGene. A stat's points are the
	  pair's sum and add PctPerPoint each to that stat (Formulas.Stats). A record without genes
	  (enemies, raid bosses) counts as all zero.

	  Genetics.Roll(rng) -> Genes                 hatched and rewarded monsters (HatchRange)
	  Genetics.Seeded(seed) -> Genes              the same roll from a seed (save migration)
	  Genetics.Fill(genes?, rng) -> Genes         a copy with every valid pair kept and each missing
	                                              or broken pair rolled (Luck for pre-3.7 genes)
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

	Gene locks (update 3.10, the Gene Lab): Inherit, Range, Preview, Odds and GradeOdds take two
	optional trailing arguments lockA, lockB: the stat each parent has locked (its record's
	`geneLock`) or nil. A parent passes its BETTER gene of its locked stat for certain; surges
	still apply after. Without locks every result is exactly as before. Inherit draws the same
	random numbers with or without locks, so a lock never moves any other roll.

	Breeding planner (update 3.9): the exact odds of Inherit (no sampling, never a seed):
	  Genetics.Odds(a, b, stat) -> { [0..2 × MaxGene] = probability }
	                                              the baby's points in `stat` (every key present)
	  Genetics.GradeOdds(a, b, stat) -> { S, A, B, C, D }   the same, summed by grade
	  Genetics.AtLeast(odds, grade) -> number     chance of `grade` or better; `odds` is either
	                                              of the two tables above
	  Genetics.GradeMin(grade) -> number?         the points a grade letter starts at
	  Genetics.Grades(genes) -> string            one grade letter per stat, Stats order ("BACDS")
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

function Genetics.Fill(genes, rng)
	local lo, hi = Rules.HatchRange[1], Rules.HatchRange[2]
	local filled = {}
	for _, stat in Rules.Stats do
		local pair = if type(genes) == "table" then genes[stat] else nil
		if type(pair) == "table" and validGene(pair[1]) and validGene(pair[2]) then
			filled[stat] = { pair[1], pair[2] }
		else
			filled[stat] = { rng:Int(lo, hi), rng:Int(lo, hi) }
		end
	end
	return filled
end

local function surge(rng, gene: number): (number, boolean)
	local roll = rng:Next()
	local gain = if roll < Rules.BigSurgeChance then 2 elseif roll < Rules.BigSurgeChance + Rules.SurgeChance then 1 else 0
	if gain == 0 or gene >= Rules.MaxGene then
		return gene, false
	end
	return math.min(Rules.MaxGene, gene + gain), true
end

function Genetics.Inherit(rng, a, b, lockA: string?, lockB: string?)
	local genes, surges = {}, 0
	for _, stat in Rules.Stats do
		local a1, a2 = Genetics.Pair(a, stat)
		local b1, b2 = Genetics.Pair(b, stat)
		local fromA = if rng:Int(1, 2) == 1 then a1 else a2
		local fromB = if rng:Int(1, 2) == 1 then b1 else b2
		if lockA == stat then
			fromA = math.max(a1, a2)
		end
		if lockB == stat then
			fromB = math.max(b1, b2)
		end
		local surgedA, surgedB
		fromA, surgedA = surge(rng, fromA)
		fromB, surgedB = surge(rng, fromB)
		surges += (if surgedA then 1 else 0) + (if surgedB then 1 else 0)
		genes[stat] = { fromA, fromB }
	end
	return genes, surges
end

function Genetics.Range(a, b, stat: string, lockA: string?, lockB: string?): (number, number)
	local a1, a2 = Genetics.Pair(a, stat)
	local b1, b2 = Genetics.Pair(b, stat)
	local loA = if lockA == stat then math.max(a1, a2) else math.min(a1, a2)
	local loB = if lockB == stat then math.max(b1, b2) else math.min(b1, b2)
	return loA + loB, math.max(a1, a2) + math.max(b1, b2)
end

function Genetics.Preview(a, b, lockA: string?, lockB: string?)
	local stats = {}
	for _, stat in Rules.Stats do
		local lo, hi = Genetics.Range(a, b, stat, lockA, lockB)
		table.insert(stats, { stat = stat, lo = lo, hi = hi })
	end
	return { stats = stats, surgeChance = Rules.SurgeChance + Rules.BigSurgeChance }
end

-- Breeding planner (3.9) ------------------------------------------------------------------

-- One parent's contribution: either gene of the pair at 1/2 (the better one for certain when
-- `locked`, 3.10), then the surge Inherit rolls (checked the same way: +2 at BigSurgeChance,
-- else +1 at SurgeChance, capped; a gene already at MaxGene never surges).
local function parentGene(g1: number, g2: number, locked: boolean?): { [number]: number }
	if locked then
		g1 = math.max(g1, g2)
		g2 = g1
	end
	local dist = {}
	local big, small = Rules.BigSurgeChance, Rules.SurgeChance
	for _, g in { g1, g2 } do
		if g >= Rules.MaxGene then
			dist[g] = (dist[g] or 0) + 0.5
		else
			local up2, up1 = math.min(Rules.MaxGene, g + 2), math.min(Rules.MaxGene, g + 1)
			dist[up2] = (dist[up2] or 0) + 0.5 * big
			dist[up1] = (dist[up1] or 0) + 0.5 * small
			dist[g] = (dist[g] or 0) + 0.5 * (1 - big - small)
		end
	end
	return dist
end

function Genetics.Odds(a, b, stat: string, lockA: string?, lockB: string?): { [number]: number }
	local a1, a2 = Genetics.Pair(a, stat)
	local b1, b2 = Genetics.Pair(b, stat)
	local fromA, fromB = parentGene(a1, a2, lockA == stat), parentGene(b1, b2, lockB == stat)
	local odds = {}
	for points = 0, 2 * Rules.MaxGene do
		odds[points] = 0
	end
	for ga, pa in fromA do
		for gb, pb in fromB do
			odds[ga + gb] += pa * pb
		end
	end
	return odds
end

function Genetics.GradeOdds(a, b, stat: string, lockA: string?, lockB: string?)
	local out = {}
	for _, g in Rules.Grades do
		out[g.grade] = 0
	end
	for points, p in Genetics.Odds(a, b, stat, lockA, lockB) do
		local grade = Genetics.Grade(points).grade
		out[grade] += p
	end
	return out
end

function Genetics.GradeMin(grade: string): number?
	for _, g in Rules.Grades do
		if g.grade == grade then
			return g.min
		end
	end
	return nil
end

function Genetics.AtLeast(odds, grade: string): number
	local min = Genetics.GradeMin(grade)
	if type(odds) ~= "table" or not min then
		return 0
	end
	local total = 0
	for key, p in odds do
		local points = if type(key) == "number" then key else Genetics.GradeMin(key)
		if points and points >= min and type(p) == "number" then
			total += p
		end
	end
	return math.clamp(total, 0, 1)
end

function Genetics.Grades(genes): string
	local letters = {}
	for _, stat in Rules.Stats do
		table.insert(letters, Genetics.Grade(Genetics.Points(genes, stat)).grade)
	end
	return table.concat(letters)
end

return Genetics
