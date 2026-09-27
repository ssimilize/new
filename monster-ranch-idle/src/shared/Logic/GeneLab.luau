--[[
	GeneLab (update 3.10): the Gene Lab's pure rules, shared by the server (Systems/GeneLab) and
	the client (Screens/GeneLab). Numbers live in Config.GeneLab.

	  GeneLab.Weaker(genes, stat) -> (index 1|2, gene)   the gene a tune raises (the first on a tie)
	  GeneLab.Cost(gene) -> number                       Stardust for one tune of that gene
	  GeneLab.Chance(gene) -> number?                    success chance; nil at or above the Cap
	  GeneLab.Seed(userId, monsterId, attempt) -> number
	  GeneLab.Roll(seed, chance) -> boolean              the seeded success roll
	  GeneLab.TunesLeft(section, day) -> number          section = profile.GeneLab
]]

local Config = require(script.Parent.Parent.Config)
local Genetics = require(script.Parent.Genetics)
local Rng = require(script.Parent.Rng)

local Rules = Config.GeneLab

local GeneLab = {}

function GeneLab.Weaker(genes, stat: string): (number, number)
	local a, b = Genetics.Pair(genes, stat)
	if b < a then
		return 2, b
	end
	return 1, a
end

function GeneLab.Cost(gene: number): number
	return Rules.CostPerStep * (gene + 1)
end

function GeneLab.Chance(gene: number): number?
	if gene >= Rules.Cap then
		return nil
	end
	for _, row in Rules.Chances do
		if gene <= row.max then
			return row.chance
		end
	end
	return nil
end

function GeneLab.Seed(userId: number, monsterId: string, attempt: number): number
	return Rng.seed("genelab", userId, monsterId, attempt)
end

function GeneLab.Roll(seed: number, chance: number): boolean
	return Rng.new(seed):Next() < chance
end

function GeneLab.TunesLeft(section, day: number): number
	if type(section) ~= "table" or section.day ~= day then
		return Rules.DailyTunes
	end
	return math.max(0, Rules.DailyTunes - (tonumber(section.tunes) or 0))
end

return GeneLab
