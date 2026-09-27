--[[
	Logic/Strays (update 3.13 · Wild things): pure rules for Stray Monsters (tuning in
	Config/Strays). No Roblox APIs; Strays.spec tests all of it.

	  Strays.Offset(userId) -> seconds              this player's slot offset (0..Interval-1)
	  Strays.Slot(userId, now) -> number            the arrival slot `now` falls in
	  Strays.ArriveAt(userId, slot) -> unix         when that slot's stray arrives
	  Strays.LeavesAt(userId, slot) -> unix         when it wanders off (ArriveAt + Stay)
	  Strays.Seed(userId, slot, secret) -> number   the stray's seed (secret is the save's private one)
	  Strays.Pool(isUnlocked) -> { lineId }         the lines a stray can be: every line of an egg
	      pool the player can buy (egg unlocked, sold, no event, no rebirth stars), sorted
	  Strays.Roll(seed, pool, night) -> Stray?      nil for an empty pool
	      Stray = { line, rarity, mood = { "wait" | flavourId } }   (rarity drawn first, then the
	      line, then the moods: the night odds only move the rarity)
	  Strays.Favourite(lineId) -> flavourId         the line's first element's favourite treat
	  Strays.Hint(want) -> string                   the honest hint for one round's mood
	  Strays.Score(mood, choices) -> number         rounds answered right
	  Strays.Befriended(correct) -> boolean
	  Strays.Cost(choices) -> { [currencyKey]: n }  the food the treats cost
	  Strays.Name(lineId) -> string                 the adult's name (its first adult form)
	  Strays.GeneBonus(genes, rng) -> (Genes, stat) a copy with one stat raised one grade: the
	      lower gene of the pair first, then the other, until the pair reaches the next grade's
	      points (each gene capped at MaxGene); an S-grade stat gets +1 on its lower gene if it can
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)
local Genetics = require(script.Parent.Genetics)

local Rules = Config.Strays

local Strays = {}

-- Slots ----------------------------------------------------------------------------------------

function Strays.Offset(userId: number): number
	return Rng.seed("strays", userId) % Rules.Interval
end

function Strays.Slot(userId: number, now: number): number
	return math.floor((now - Strays.Offset(userId)) / Rules.Interval)
end

function Strays.ArriveAt(userId: number, slot: number): number
	return slot * Rules.Interval + Strays.Offset(userId)
end

function Strays.LeavesAt(userId: number, slot: number): number
	return Strays.ArriveAt(userId, slot) + Rules.Stay
end

function Strays.Seed(userId: number, slot: number, secret: number): number
	return Rng.seed("stray", userId, slot, secret)
end

-- The stray ---------------------------------------------------------------------------------------

function Strays.Pool(isUnlocked: (string) -> boolean): { string }
	local seen, out = {}, {}
	for _, egg in Config.Eggs.List do
		if egg.price and not egg.event and not egg.rebirths and egg.unlock and isUnlocked(egg.unlock) then
			for _, lineId in Config.Species.Pools[egg.pool] or {} do
				local def = Config.Species.ById[lineId]
				if def and not def.event and not seen[lineId] then
					seen[lineId] = true
					table.insert(out, lineId)
				end
			end
		end
	end
	table.sort(out)
	return out
end

function Strays.Favourite(lineId: string): string
	local def = Config.Species.ById[lineId]
	local element = def and def.elements and def.elements[1]
	return Rules.Favourite[element] or "sweet"
end

function Strays.Roll(seed: number, pool: { string }, night: boolean)
	if #pool == 0 then
		return nil
	end
	local rng = Rng.new(seed)
	local rarity = rng:Weighted(if night then Rules.NightOdds else Rules.Odds)
	local line = pool[rng:Int(1, #pool)]
	local favourite = Strays.Favourite(line)
	local mood = {}
	for i = 1, Rules.Rounds do
		mood[i] = if rng:Next() < Rules.WaitChance then "wait" else favourite
	end
	return { line = line, rarity = rarity, mood = mood }
end

function Strays.Hint(want: string): string
	if want == "wait" then
		return Rules.WaitHint
	end
	return Rules.TreatHints[want] or Rules.WaitHint
end

function Strays.Score(mood: { string }, choices: { string }): number
	local n = 0
	for i = 1, Rules.Rounds do
		if mood[i] ~= nil and choices[i] == mood[i] then
			n += 1
		end
	end
	return n
end

function Strays.Befriended(correct: number): boolean
	return correct >= Rules.Need
end

function Strays.Cost(choices: { string }): { [string]: number }
	local cost = {}
	for _, c in choices do
		if c ~= "wait" then
			local key = "food." .. c
			cost[key] = (cost[key] or 0) + Rules.TreatCost
		end
	end
	return cost
end

function Strays.Name(lineId: string): string
	local form = Config.Species.Form(lineId, 3)
	return if form then form.name else lineId
end

-- The adoption gift -----------------------------------------------------------------------------

local function nextGradeMin(points: number): number?
	local best = nil
	for _, g in Config.Genetics.Grades do
		if g.min > points and (best == nil or g.min < best) then
			best = g.min
		end
	end
	return best
end

function Strays.GeneBonus(genes, rng)
	local out = Genetics.Copy(genes)
	local stats = Config.Genetics.Stats
	local stat = stats[rng:Int(1, #stats)]
	local pair = out[stat]
	local max = Config.Genetics.MaxGene
	local lowI = if pair[1] <= pair[2] then 1 else 2
	local target = nextGradeMin(pair[1] + pair[2])
	if target == nil then
		pair[lowI] = math.min(max, pair[lowI] + 1)
		return out, stat
	end
	for _, i in { lowI, 3 - lowI } do
		local need = target - (pair[1] + pair[2])
		if need > 0 then
			pair[i] = math.min(max, pair[i] + need)
		end
	end
	return out, stat
end

return Strays
