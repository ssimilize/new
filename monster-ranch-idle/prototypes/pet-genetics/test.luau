--[[
	PROTOTYPE tests for Genetics.luau. Standalone (not in tests/specs, so the game's suite and CI
	never see the prototype):  lune run prototypes/pet-genetics/test
]]

local Genetics = require("./Genetics")

local passed, failed = 0, 0
local function it(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end

local function check(cond: boolean, message: string)
	if not cond then
		error(message, 2)
	end
end

local dragon, cat = Genetics.fromSpecies("dragon"), Genetics.fromSpecies("cat")
local corgi, chick = Genetics.fromSpecies("corgi"), Genetics.fromSpecies("chick")

it("a founder is pure-bred and looks like its species", function()
	local p = Genetics.express(dragon)
	for _, locus in Genetics.Loci do
		check(p.parts[locus] == "dragon", locus .. " is " .. p.parts[locus])
	end
	check(Genetics.express(cat).parts.back == "none", "a cat has no wings")
end)

it("the same seed breeds the same baby", function()
	check(Genetics.describe(Genetics.breed(42, dragon, cat)) == Genetics.describe(Genetics.breed(42, dragon, cat)), "differs")
	check(Genetics.describe(Genetics.breed(42, dragon, cat)) ~= Genetics.describe(Genetics.breed(43, dragon, cat)), "seed ignored")
end)

it("every allele comes from a parent (mutations aside)", function()
	local strays, total = 0, 0
	for seed = 1, 2000 do
		local baby = Genetics.breed(seed, corgi, chick)
		for _, locus in Genetics.Loci do
			total += 2
			local from1 = baby.loci[locus][1]
			local from2 = baby.loci[locus][2]
			if not table.find(corgi.loci[locus], from1) then
				strays += 1
			end
			if not table.find(chick.loci[locus], from2) then
				strays += 1
			end
		end
	end
	-- Only allele mutations (2%) bring anything else, and some of those land on a parent's species.
	check(strays / total < Genetics.Rules.alleleMutation, string.format("%d of %d alleles from nowhere", strays, total))
end)

it("a baby mixes parts from both parents", function()
	local mixed = 0
	for seed = 1, 500 do
		local p = Genetics.express(Genetics.breed(seed, corgi, cat))
		local seen = {}
		for _, locus in Genetics.Loci do
			seen[p.parts[locus]] = true
		end
		if seen.corgi and seen.cat then
			mixed += 1
		end
	end
	check(mixed > 400, "only " .. mixed .. " of 500 babies show parts of both parents")
end)

it("wings are dominant, and a wingless grandchild comes back in about 1 of 4 (Mendel)", function()
	-- Dragon x cat: every baby carries one wing allele and one "none", and wings show.
	local winged = 0
	local f1 = {}
	for seed = 1, 400 do
		local baby = Genetics.breed(seed, dragon, cat)
		f1[seed] = baby
		if Genetics.express(baby).parts.back == "dragon" then
			winged += 1
		end
	end
	check(winged > 380, "F1 winged " .. winged .. "/400")
	-- F1 x F1: none/none (no wings) should be ~25%.
	local wingless, n = 0, 0
	for seed = 1, 4000 do
		local a, b = f1[(seed % 400) + 1], f1[((seed * 7) % 400) + 1]
		local grand = Genetics.breed(100000 + seed, a, b)
		n += 1
		if Genetics.express(grand).parts.back == "none" then
			wingless += 1
		end
	end
	local share = wingless / n
	check(share > 0.2 and share < 0.3, string.format("F2 wingless %.3f", share))
end)

it("part skills follow the parts: a winged baby can Glide, a wingless one cannot", function()
	for seed = 1, 300 do
		local p = Genetics.express(Genetics.breed(seed, dragon, cat))
		local glides = table.find(p.skills, "Glide") ~= nil
		check(glides == (p.parts.back == "dragon"), "seed " .. seed .. ": back " .. p.parts.back .. ", glide " .. tostring(glides))
	end
end)

it("inherited stats land between the parents (within the jitter)", function()
	local R = Genetics.Rules
	for seed = 1, 1000 do
		local baby = Genetics.breed(seed, dragon, chick)
		for _, name in Genetics.StatNames do
			local lo = math.min(dragon.stats[name], chick.stats[name]) * R.statJitter[1]
			local hi = math.max(dragon.stats[name], chick.stats[name]) * R.statJitter[2]
			local v = baby.stats[name]
			check(v >= math.floor(lo) and v <= math.ceil(hi), string.format("%s %d outside %.1f..%.1f", name, v, lo, hi))
		end
	end
end)

it("innate skills come from the parents, apart from rare brand-new ones", function()
	local newOnes = 0
	for seed = 1, 1000 do
		local baby = Genetics.breed(seed, dragon, cat)
		check(#baby.innate <= Genetics.Rules.innateSkills + 1, "too many innate skills")
		for _, skill in baby.innate do
			local fromParent = table.find(dragon.innate, skill) or table.find(cat.innate, skill)
			if not fromParent then
				check(table.find(Genetics.MutationSkills, skill) ~= nil, "unknown skill " .. skill)
				newOnes += 1
			end
		end
	end
	local share = newOnes / 1000
	check(share > 0.03 and share < 0.1, string.format("brand-new skills in %.3f of babies", share))
end)

it("colour blends the parents and generations count up", function()
	local baby = Genetics.breed(7, dragon, chick)
	local p = Genetics.express(baby)
	check(baby.generation == 1, "generation " .. baby.generation)
	check(Genetics.breed(8, baby, cat).generation == 2, "grandchild generation")
	-- Green dragon x yellow chick: the red channel lands between them.
	check(p.color[1] > 0.3 and p.color[1] < 1.0, "red " .. p.color[1])
end)

print(string.format("\n%d passed, %d failed", passed, failed))
print("\nsample litter, dragon x cat:")
for seed = 1, 4 do
	print("  " .. Genetics.describe(Genetics.breed(seed, dragon, cat)))
end
if failed > 0 then
	error("prototype tests failed")
end
