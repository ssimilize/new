--[[
	Logic/Postcards (glow-up X): pure rules for postcards from expeditions (Config/Postcards).

	  Postcards.Slim(appearance) -> SlimAppearance      what a card keeps of a squad member
	  Postcards.Full(slim, species) -> Appearance       back to a drawable appearance (elements, archetype)
	  Postcards.PickLine(regionId, cfg, roll) -> lineId roll: fn(n) -> 1..n
	  Postcards.LineText(lineId, cfg) -> string         the English line with one %s
	  Postcards.Summarise(items, max) -> { Reward }     merged kind/id amounts, the biggest first
	  Postcards.Trim(cards, cfg) -> { cardId }          which cards drop: per region, then the total
	  Postcards.Favourites(cards) -> number
	  Postcards.Sorted(cards, regionId?) -> { Card }    newest first
	  Postcards.Clean(card, config) -> Card?            a card from mail or an old save, checked field by field
	  Postcards.Migrate(section, fromVersion) -> section

	Card = { id, n, region, stage, at, line, hero, squad = { SlimAppearance }, loot = { Reward },
	         fav: boolean, from: string|false, sent = { userId } }
]]

local Postcards = {}

local SLIM_KEYS = { "line", "form", "name", "aura" }

local function str(value, max: number): string?
	if type(value) ~= "string" or #value == 0 then
		return nil
	end
	return string.sub(value, 1, max)
end

local function num(value, lo: number, hi: number, default: number): number
	local n = tonumber(value)
	if n == nil or n ~= n then
		return default
	end
	return math.clamp(n, lo, hi)
end

function Postcards.Slim(ap)
	local slim = {
		stage = ap.stage,
		rarity = ap.rarity,
		variant = ap.variant or 0,
		weight = ap.weight,
		muts = table.clone(ap.muts or {}),
	}
	for _, key in SLIM_KEYS do
		slim[key] = ap[key]
	end
	if type(ap.acc) == "table" and next(ap.acc) then
		slim.acc = table.clone(ap.acc)
	end
	return slim
end

function Postcards.Full(slim, species)
	local def = species and species.ById[slim.line]
	local ap = table.clone(slim)
	ap.muts = table.clone(slim.muts or {})
	ap.elements = if def then table.clone(def.elements) else {}
	ap.archetype = if def then def.archetype else "blob"
	ap.lv = 1
	ap.stars = 1
	return ap
end

local function linesOf(regionId: string?, cfg)
	return cfg.Scene(regionId).lines
end

function Postcards.PickLine(regionId: string?, cfg, roll: (number) -> number): string
	local lines = linesOf(regionId, cfg)
	return lines[math.clamp(roll(#lines), 1, #lines)].id
end

function Postcards.LineText(lineId: string?, cfg): string
	return cfg.LineById[lineId or ""] or cfg.DefaultScene.lines[1].text
end

function Postcards.Summarise(items, max: number)
	local out, index = {}, {}
	for _, item in items or {} do
		if type(item) == "table" and type(item.kind) == "string" then
			local amount = tonumber(item.amount) or 1
			local key = item.kind .. "|" .. tostring(item.id or "")
			local entry = index[key]
			if entry then
				entry.amount += amount
			else
				entry = { kind = item.kind, amount = amount }
				if type(item.id) == "string" then
					entry.id = item.id
				end
				if type(item.rarity) == "number" then
					entry.rarity = item.rarity
				end
				index[key] = entry
				table.insert(out, entry)
			end
		end
	end
	-- Coins first, then the rarer things (eggs, monsters), then food and the rest.
	local rank = { coins = 1, monster = 2, egg = 3, accessory = 4, decor = 5, gems = 6 }
	table.sort(out, function(a, b)
		local ra, rb = rank[a.kind] or 9, rank[b.kind] or 9
		if ra ~= rb then
			return ra < rb
		end
		return a.amount > b.amount
	end)
	while #out > max do
		table.remove(out)
	end
	return out
end

local function newestFirst(a, b)
	return (a.n or 0) > (b.n or 0)
end

function Postcards.Sorted(cards, regionId: string?)
	local list = {}
	for _, card in cards or {} do
		if regionId == nil or card.region == regionId then
			table.insert(list, card)
		end
	end
	table.sort(list, newestFirst)
	return list
end

function Postcards.Favourites(cards): number
	local n = 0
	for _, card in cards or {} do
		if card.fav then
			n += 1
		end
	end
	return n
end

-- Oldest non-favourites drop first: past `perRegion` in their region, then past `maxTotal`.
function Postcards.Trim(cards, cfg): { string }
	local dropped = {}
	local gone = {}
	local counts = {}
	local all = Postcards.Sorted(cards)
	for _, card in all do
		if not card.fav then
			counts[card.region] = (counts[card.region] or 0) + 1
			if counts[card.region] > cfg.perRegion then
				gone[card.id] = true
				table.insert(dropped, card.id)
			end
		end
	end
	local total = #all - #dropped
	for i = #all, 1, -1 do
		if total <= cfg.maxTotal then
			break
		end
		local card = all[i]
		if not card.fav and not gone[card.id] then
			gone[card.id] = true
			table.insert(dropped, card.id)
			total -= 1
		end
	end
	return dropped
end

local function cleanSlim(ap, species)
	if type(ap) ~= "table" then
		return nil
	end
	local line = str(ap.line, 40)
	local def = line and species.ById[line]
	if not def then
		return nil
	end
	local stage = math.floor(num(ap.stage, 1, 3, 1))
	local form = str(ap.form, 40)
	-- forms[1] and [2] are the baby and teen; forms[3] is the list of adult branches.
	local found = species.Form(line, stage, form)
	if not found or found.id ~= form then
		stage = 1
		found = species.Form(line, 1)
		form = if found then found.id else line
	end
	local muts = {}
	for i, m in (if type(ap.muts) == "table" then ap.muts else {}) do
		if i > 2 then
			break
		end
		if type(m) == "string" then
			table.insert(muts, string.sub(m, 1, 30))
		end
	end
	local slim = {
		line = line,
		form = form,
		stage = stage,
		rarity = math.floor(num(ap.rarity, 1, 6, 1)),
		variant = math.floor(num(ap.variant, 0, 3, 0)),
		weight = num(ap.weight, 0.01, 1e6, def.weight or 1),
		muts = muts,
		name = str(ap.name, 30) or (def.forms[1] and def.forms[1].name) or line,
		aura = str(ap.aura, 30),
	}
	if type(ap.acc) == "table" then
		local acc = {}
		for slot, id in ap.acc do
			if type(slot) == "string" and type(id) == "string" then
				acc[string.sub(slot, 1, 20)] = string.sub(id, 1, 40)
			end
		end
		if next(acc) then
			slim.acc = acc
		end
	end
	return slim
end

-- A card rebuilt from known fields only (mail from another server, or an old save).
function Postcards.Clean(card, config)
	if type(card) ~= "table" then
		return nil
	end
	local cfg = config.Postcards
	local region = str(card.region, 30)
	if not region then
		return nil
	end
	local squad = {}
	for _, ap in (if type(card.squad) == "table" then card.squad else {}) do
		if #squad >= cfg.maxMonsters then
			break
		end
		local slim = cleanSlim(ap, config.Species)
		if slim then
			table.insert(squad, slim)
		end
	end
	if #squad == 0 then
		return nil
	end
	local loot = {}
	for _, item in (if type(card.loot) == "table" then card.loot else {}) do
		if type(item) == "table" and type(item.kind) == "string" and #loot < cfg.maxLoot then
			table.insert(loot, {
				kind = string.sub(item.kind, 1, 20),
				id = str(item.id, 40),
				amount = math.floor(num(item.amount, 0, 1e15, 1)),
				rarity = if type(item.rarity) == "number" then math.floor(num(item.rarity, 1, 6, 1)) else nil,
			})
		end
	end
	local line = str(card.line, 40)
	if not line or not cfg.LineById[line] then
		line = cfg.DefaultScene.lines[1].id
	end
	local sent = {}
	for _, userId in (if type(card.sent) == "table" then card.sent else {}) do
		if type(userId) == "number" and #sent < cfg.maxSentPerCard then
			table.insert(sent, userId)
		end
	end
	return {
		id = str(card.id, 20) or "",
		n = math.floor(num(card.n, 0, 1e12, 0)),
		region = region,
		stage = math.floor(num(card.stage, 0, 999, 0)),
		at = math.floor(num(card.at, 0, 1e12, 0)),
		line = line,
		hero = str(card.hero, 30) or squad[1].name,
		squad = squad,
		loot = loot,
		fav = card.fav == true,
		from = if type(card.from) == "string" then string.sub(card.from, 1, 30) else false,
		sent = sent,
	}
end

-- Version 1 is the first save shape; later versions add their steps here. Every load also passes
-- through Normalise (Systems/Postcards), so a lowered cap or a bad card never survives a join.
function Postcards.Migrate(section, _fromVersion: number)
	return section
end

return Postcards
