--[[
	Logic/Tourists (update 3.10 · Ranch life): pure rules for Ranch Tourists (tuning and the
	appeal formula in Config/Tourists). No Roblox APIs; Tourists.spec tests all of it.

	  Tourists.Appeal(facts) -> Appeal
	      facts = { layout = { { id } }, level, pens = { { capacity, count } }, rarities = { n }, codex, favored? }
	      favored (3.11): the season's favourite category (Config.Seasons appeal), weighted by
	      Logic/Seasons.AppealWeights (a perfect ranch still scores 100)
	      Appeal = { score = 0..100, stars = 1..5, parts = { [categoryId] = 0..1 }, tip = string }
	  Tourists.Stars(score) -> 1..5
	  Tourists.Tip(parts, kinds) -> string              kinds = { [kind] = pieces placed }
	  Tourists.Offset(userId) -> seconds                this player's slot offset (0..Interval-1)
	  Tourists.Slot(userId, now) -> number              the visit slot `now` falls in
	  Tourists.NextAt(userId, now) -> unix              when the next tourist arrives
	  Tourists.Review(userId, slot, appeal, at) -> Review
	      Review = { at, stars, who, good, gi, bad = categoryId|false, bi }   (seeded per slot)
	  Tourists.Pay(stars, visits) -> { Reward }         coins as seconds of ranch income
	  Tourists.Push(book, review)                       newest first, at most BookSize
	  Tourists.StarText(stars) -> "★★★☆☆"
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)
local DecorLayout = require(script.Parent.DecorLayout)
local Seasons = require(script.Parent.Seasons)

local Rules = Config.Tourists

local Tourists = {}

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

function Tourists.Stars(score: number): number
	local stars = 1
	for _, step in Rules.StarSteps do
		if score >= step then
			stars += 1
		end
	end
	return math.min(stars, 5)
end

-- The first missing kind's tip when variety is weakest; the category's tip otherwise.
function Tourists.Tip(parts, kinds): string
	local weakest, low = nil, math.huge
	for _, c in Rules.Categories do
		local v = parts[c.id] or 0
		if v < 1 and v < low then
			weakest, low = c.id, v
		end
	end
	if not weakest then
		return Rules.Tips.perfect.text
	end
	if weakest == "variety" or (weakest == "decor" and (kinds.light or 0) == 0 and (parts.decor or 0) > 0) then
		for _, kind in Rules.Kinds do
			if (kinds[kind] or 0) == 0 then
				return Rules.KindTips[kind].text
			end
		end
	end
	return Rules.Tips[weakest].text
end

function Tourists.Appeal(facts)
	facts = if type(facts) == "table" then facts else {}
	local layout = if type(facts.layout) == "table" then facts.layout else {}
	local kinds, count = {}, 0
	for _, e in layout do
		local def = type(e) == "table" and Config.Decor.ById[e.id]
		if def then
			count += 1
			kinds[def.kind] = (kinds[def.kind] or 0) + 1
		end
	end
	local distinct = 0
	for _ in kinds do
		distinct += 1
	end

	local owned, filled, capacity = 0, 0, 0
	for _, pen in (if type(facts.pens) == "table" then facts.pens else {}) do
		owned += 1
		local cap = math.max(1, tonumber(pen.capacity) or 1)
		capacity += cap
		filled += math.min(cap, tonumber(pen.count) or 0)
	end
	local maxPens = Config.Economy.Pens.max

	local rarities = table.clone(if type(facts.rarities) == "table" then facts.rarities else {})
	table.sort(rarities, function(a, b)
		return a > b
	end)
	local top, sum = math.min(Rules.RarityTop, #rarities), 0
	for i = 1, top do
		sum += rarities[i]
	end
	local topRarity = #Config.Rarities.List

	local parts = {
		decor = clamp01(count / math.max(1, math.min(Rules.DecorFull, DecorLayout.Cap(facts.level)))),
		variety = clamp01(distinct / Rules.VarietyFull),
		pens = clamp01(0.5 * owned / maxPens + 0.5 * (if capacity > 0 then filled / capacity else 0)),
		rarity = if top > 0 then clamp01(sum / Rules.RarityTop / topRarity) else 0,
		codex = clamp01((tonumber(facts.codex) or 0) / Rules.CodexFull),
	}
	local score = 0
	for id, weight in Seasons.AppealWeights(Rules.Weights, facts.favored) do
		score += weight * parts[id]
	end
	local bonus = math.clamp(tonumber(facts.bonus) or 0, 0, Rules.BonusMax)
	score = math.clamp(math.floor(score + bonus + 0.5), 0, 100)
	return { score = score, stars = Tourists.Stars(score), parts = parts, tip = Tourists.Tip(parts, kinds), bonus = bonus }
end

-- Slots --------------------------------------------------------------------------------------

function Tourists.Offset(userId: number): number
	return Rng.seed("tourists", userId) % Rules.Interval
end

function Tourists.Slot(userId: number, now: number): number
	return math.floor((now - Tourists.Offset(userId)) / Rules.Interval)
end

function Tourists.NextAt(userId: number, now: number): number
	return (Tourists.Slot(userId, now) + 1) * Rules.Interval + Tourists.Offset(userId)
end

-- Reviews and pay -----------------------------------------------------------------------------

function Tourists.Review(userId: number, slot: number, appeal, at: number)
	local parts = appeal.parts or {}
	local good, bad, hi, lo = Rules.Categories[1].id, nil, -1, math.huge
	for _, c in Rules.Categories do
		local v = parts[c.id] or 0
		if v > hi then
			good, hi = c.id, v
		end
		if v < 1 and v < lo then
			bad, lo = c.id, v
		end
	end
	if bad == good then
		bad = nil
	end
	if hi < Rules.PraiseMin then
		good = nil
	end
	local rng = Rng.new(Rng.seed("tourists", userId, slot))
	return {
		at = at,
		stars = appeal.stars or 1,
		who = rng:Int(1, #Rules.Visitors),
		good = good or false,
		gi = if good then rng:Int(1, #Rules.Praise[good]) else 0,
		bad = bad or false,
		bi = if bad then rng:Int(1, #Rules.Gripes[bad]) else 0,
	}
end

function Tourists.Pay(stars: number, visits: number)
	return { { kind = "coins", amount = 0, seconds = Rules.SecondsPerStar * math.clamp(stars, 1, 5) * math.max(1, visits) } }
end

function Tourists.Push(book, review)
	table.insert(book, 1, review)
	while #book > Rules.BookSize do
		table.remove(book)
	end
end

function Tourists.StarText(stars: number): string
	local n = math.clamp(math.floor(tonumber(stars) or 0), 0, 5)
	return string.rep("★", n) .. string.rep("☆", 5 - n)
end

return Tourists
