--[[
	Logic/Visits (glow-up Y): pure rules for ranch snapshots and the crown. No Roblox APIs, so
	everything here is unit-tested in Lune (Visits.spec).

	  Visits.Build(Config, plot, best, now) -> Snapshot     from a public plot record (Plots:Public)
	  Visits.Sanitize(Config, raw) -> Snapshot?              repairs or rejects a loaded record
	  Visits.Fit(Config, snap) -> (Snapshot, dropped)        trims monsters (then best, decor) to maxBytes
	  Visits.Encode(value) -> string                         deterministic text (size estimate, change key)
	  Visits.Size(value) -> number                           #Encode(value)
	  Visits.Leader(rows) -> userId?                         most likes, ties by the earliest `at`
	  Visits.Monsters(snap, max) -> { Appearance }           the ranch's showiest monsters (the stage)

	Snapshot (version 1; every field is always present):
	  { v, userId, name, level, likes, at,
	    pens   = { { theme = string|false, decor = { decorId }, capacity, jarTier, monsters = { Appearance } } },
	    garden = { tier, plots = { { flavor = string|false, readyAt } } } | false,
	    best   = { { hearts, appearance = Appearance } },   -- Bond best friends, the gate
	    decor  = { { [string]: string|number|boolean } } }  -- placed ranch decor (the ranch builder fills it)
]]

local Visits = {}

local function str(value: any, max: number): string?
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return string.sub(value, 1, max)
end

local function int(value: any, min: number, max: number, default: number): number
	local n = tonumber(value)
	if n == nil or n ~= n then
		return default
	end
	return math.clamp(math.floor(n), min, max)
end

local function num(value: any, min: number, max: number, default: number): number
	local n = tonumber(value)
	if n == nil or n ~= n then
		return default
	end
	return math.clamp(n, min, max)
end

-- Appearance ------------------------------------------------------------------------------------

local function appearance(Config, raw, S)
	if type(raw) ~= "table" then
		return nil
	end
	local line = str(raw.line, 32)
	local form = str(raw.form, 32)
	if not line or not form or not Config.Species.ById[line] then
		return nil
	end
	local muts = {}
	for _, m in (if type(raw.muts) == "table" then raw.muts else {}) do
		local id = str(m, 32)
		if id and #muts < S.maxMuts then
			table.insert(muts, id)
		end
	end
	local elements = {}
	for _, e in (if type(raw.elements) == "table" then raw.elements else {}) do
		local id = str(e, 16)
		if id and #elements < 3 then
			table.insert(elements, id)
		end
	end
	local out = {
		line = line,
		form = form,
		stage = int(raw.stage, 1, 9, 1),
		rarity = int(raw.rarity, 1, #Config.Rarities.List, 1),
		variant = int(raw.variant, 0, #Config.Rarities.Variants, 0),
		muts = muts,
		weight = num(raw.weight, 0, 100000, 1),
		name = str(raw.name, S.maxName) or "",
		elements = elements,
		archetype = str(raw.archetype, 32) or "",
		lv = int(raw.lv, 1, 1000, 1),
		stars = int(raw.stars, 0, 10, 0),
	}
	if type(raw.acc) == "table" then
		local acc, n = {}, 0
		for slot, id in raw.acc do
			local s, a = str(slot, 16), str(id, 48)
			if s and a and n < S.maxAcc then
				acc[s] = a
				n += 1
			end
		end
		if n > 0 then
			out.acc = acc
		end
	end
	local aura = str(raw.aura, 48)
	if aura then
		out.aura = aura
	end
	return out
end

local function decorEntry(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local out, n = {}, 0
	for k, v in raw do
		if type(k) == "string" and #k <= 24 and n < 8 then
			local t = type(v)
			if t == "string" then
				out[k] = string.sub(v, 1, 48)
				n += 1
			elseif t == "boolean" or (t == "number" and v == v and v > -1e6 and v < 1e6) then
				out[k] = v
				n += 1
			end
		end
	end
	return if n > 0 then out else nil
end

-- Snapshots -------------------------------------------------------------------------------------

function Visits.Sanitize(Config, raw)
	if type(raw) ~= "table" then
		return nil
	end
	local S = Config.Visits.Snapshot
	local userId = int(raw.userId, 0, 1e15, 0)
	if userId <= 0 then
		return nil
	end
	local pens = {}
	for _, pen in (if type(raw.pens) == "table" then raw.pens else {}) do
		if #pens >= S.maxPens then
			break
		end
		if type(pen) == "table" then
			local theme = str(pen.theme, 32)
			if theme and not Config.Decor.PenThemeById[theme] then
				theme = nil
			end
			local decor = {}
			for _, id in (if type(pen.decor) == "table" then pen.decor else {}) do
				local d = str(id, 32)
				if d and #decor < 12 then
					table.insert(decor, d)
				end
			end
			local monsters = {}
			for _, m in (if type(pen.monsters) == "table" then pen.monsters else {}) do
				local a = appearance(Config, if type(m) == "table" and m.appearance then m.appearance else m, S)
				if a and #monsters < S.maxMonstersPerPen then
					table.insert(monsters, a)
				end
			end
			table.insert(pens, {
				theme = theme or false,
				decor = decor,
				capacity = int(pen.capacity, 1, 1000, Config.Economy.Pens.startCapacity),
				jarTier = int(pen.jarTier, 1, 100, 1),
				monsters = monsters,
			})
		end
	end
	local garden = false
	if type(raw.garden) == "table" then
		local plots = {}
		for _, p in (if type(raw.garden.plots) == "table" then raw.garden.plots else {}) do
			if #plots >= S.maxGardenPlots then
				break
			end
			local flavor = if type(p) == "table" then str(p.flavor, 16) else nil
			if flavor and not table.find(Config.Food.Ids, flavor) then
				flavor = nil
			end
			table.insert(plots, { flavor = flavor or false, readyAt = if type(p) == "table" then num(p.readyAt, 0, 1e10, 0) else 0 })
		end
		garden = { tier = int(raw.garden.tier, 0, 100, 1), plots = plots }
	end
	local best = {}
	for _, b in (if type(raw.best) == "table" then raw.best else {}) do
		if #best >= S.maxBest then
			break
		end
		local a = type(b) == "table" and appearance(Config, b.appearance, S)
		if a then
			table.insert(best, { hearts = int(b.hearts, 0, 100, 0), appearance = a })
		end
	end
	local decor = {}
	for _, d in (if type(raw.decor) == "table" then raw.decor else {}) do
		if #decor >= S.maxDecor then
			break
		end
		local entry = decorEntry(d)
		if entry then
			table.insert(decor, entry)
		end
	end
	return {
		v = S.version,
		userId = userId,
		name = str(raw.name, S.maxName) or "Rancher",
		level = int(raw.level, 0, 1000, 0),
		likes = int(raw.likes, 0, 1e9, 0),
		at = num(raw.at, 0, 1e10, 0),
		pens = pens,
		garden = garden,
		best = best,
		decor = decor,
	}
end

-- best = { { hearts, appearance } } (Bond best friends, already looked up by the caller).
function Visits.Build(Config, plot, best, now: number)
	plot = if type(plot) == "table" then plot else {}
	local snap = Visits.Sanitize(Config, {
		userId = plot.userId,
		name = plot.name,
		level = plot.level,
		likes = plot.likes,
		at = now,
		pens = plot.pens,
		garden = plot.garden,
		best = best,
		decor = plot.decor, -- the ranch builder's placed decor, when the plot record carries it
	})
	return if snap then (Visits.Fit(Config, snap)) else nil
end

-- Encoding --------------------------------------------------------------------------------------

local function encode(value, out)
	local t = type(value)
	if t == "table" then
		if #value > 0 or next(value) == nil then
			table.insert(out, "[")
			for i, v in value do
				if i > 1 then
					table.insert(out, ",")
				end
				encode(v, out)
			end
			table.insert(out, "]")
		else
			local keys = {}
			for k in value do
				table.insert(keys, tostring(k))
			end
			table.sort(keys)
			table.insert(out, "{")
			for i, k in keys do
				if i > 1 then
					table.insert(out, ",")
				end
				table.insert(out, string.format("%q:", k))
				local v = value[k]
				if v == nil then
					v = value[tonumber(k)]
				end
				encode(v, out)
			end
			table.insert(out, "}")
		end
	elseif t == "string" then
		table.insert(out, string.format("%q", value))
	elseif t == "number" then
		table.insert(out, if value == math.floor(value) then string.format("%d", value) else string.format("%.4g", value))
	else
		table.insert(out, tostring(value))
	end
end

function Visits.Encode(value): string
	local out = {}
	encode(value, out)
	return table.concat(out)
end

function Visits.Size(value): number
	return #Visits.Encode(value)
end

-- Drops monsters from the fullest pen's back until the snapshot fits, then best friends, then
-- placed decor. Returns the snapshot (changed in place) and how many entries were dropped.
function Visits.Fit(Config, snap)
	local max = Config.Visits.Snapshot.maxBytes
	local dropped = 0
	while Visits.Size(snap) > max do
		local fullest, count = nil, 0
		for _, pen in snap.pens do
			if #pen.monsters > count then
				fullest, count = pen, #pen.monsters
			end
		end
		if fullest then
			table.remove(fullest.monsters)
		elseif #snap.best > 0 then
			table.remove(snap.best)
		elseif #snap.decor > 0 then
			table.remove(snap.decor)
		else
			break
		end
		dropped += 1
	end
	return snap, dropped
end

-- The showiest monsters of a snapshot: rarity, then variant, then weight.
function Visits.Monsters(snap, max: number)
	local list = {}
	if type(snap) ~= "table" then
		return list
	end
	for _, pen in snap.pens or {} do
		for _, a in pen.monsters or {} do
			table.insert(list, a)
		end
	end
	table.sort(list, function(a, b)
		if a.rarity ~= b.rarity then
			return a.rarity > b.rarity
		end
		if a.variant ~= b.variant then
			return a.variant > b.variant
		end
		return (a.weight or 0) > (b.weight or 0)
	end)
	while #list > max do
		table.remove(list)
	end
	return list
end

-- Crown -----------------------------------------------------------------------------------------

-- rows = { { userId, likes, at } } (at = when the ranch reached its count). nil when nobody has a like.
function Visits.Leader(rows): number?
	local best = nil
	for _, row in rows do
		if (row.likes or 0) > 0 then
			if
				not best
				or row.likes > best.likes
				or (row.likes == best.likes and (row.at < best.at or (row.at == best.at and row.userId < best.userId)))
			then
				best = row
			end
		end
	end
	return if best then best.userId else nil
end

return Visits
