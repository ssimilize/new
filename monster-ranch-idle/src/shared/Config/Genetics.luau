--[[
	Genetics (update 3.6): stat genes. Genes only change battle stats (HP, ATK, DEF, SPD);
	they never change how a monster looks, its size, its coin income or its price.

	Every monster carries a pair of genes per stat, one from each parent. Each gene is worth
	0..MaxGene points and every point adds PctPerPoint to that stat, so a pair is worth
	0..2 × MaxGene points (+0% .. +20%). Logic/Genetics holds the rules.

	  Stats          the stats that have genes, in display order (Luck has none: no battle reads it)
	  HatchRange     each gene of a hatched, rewarded or pre-genetics monster rolls in this range
	  SurgeChance    breeding: chance each inherited gene gains +1 point (capped at MaxGene)
	  BigSurgeChance breeding: chance it gains +2 instead (checked first)
	  Grades         a stat's grade from its pair's points, best first
]]

local Genetics = {}

Genetics.Stats = { "hp", "atk", "def", "spd" }
Genetics.StatNames = { hp = "HP", atk = "ATK", def = "DEF", spd = "SPD" }

Genetics.MaxGene = 10
Genetics.PctPerPoint = 0.01
Genetics.HatchRange = { 0, 5 }
Genetics.SurgeChance = 0.08
Genetics.BigSurgeChance = 0.01

Genetics.Grades = {
	{ grade = "S", min = 18, color = "#F2C14E" },
	{ grade = "A", min = 14, color = "#B06AE8" },
	{ grade = "B", min = 10, color = "#4E9BF2" },
	{ grade = "C", min = 5, color = "#5DBB63" },
	{ grade = "D", min = 0, color = "#9AA0A6" },
}

return Genetics
