--!strict
-- Atelier: seeded look genomes -> bodies, wardrobes, faces and palettes. Pure: no Roblox
-- services, no game kernel. The same seed and look book give the same person everywhere, so a
-- Life Director agent (or a save) only has to carry the seed.
--
--   local Atelier = require("../Atelier/Atelier")
--   local looks = Atelier.resolve(require(<game look book>), Palette.hex)   -- lock -> hex, once
--   local g = Atelier.roll(1234, { looks = looks, role = "blacksmith" })   -- a genome (data)
--   local desc = Atelier.describe(g, looks, { detail = "high", prefix = "GI_" })
--   local model = Atelier.build(desc, WorldSpec.instanceFactory({ Instance = Instance, ... }), workspace)
--   local crowd = Atelier.crowd(7, 40, { looks = looks })                  -- no two neighbours alike
--
-- A genome (schema: foundry/tools/atelier/genome.schema.json):
--   { v = 1, seed, looks = <look book id>, role,
--     body = { rig = <body set>, build, height }, skin = <swatch>, hair = { style, colour },
--     outfit = { head, torso, legs, feet, back, hands }   -- piece ids or "none"
--     accessories = { piece ids, sorted }, palette = { role, culture, wealth, slots = { slot = swatch } },
--     face = { eyes, brows, mouth, blush, texture } }
-- Colours are swatch NAMES; the look book maps swatches to the game's style lock (or its kit),
-- so a genome never carries a hex and a lock change recolours every person at once.
--
-- Descriptors are WorldSpec-shaped ({ className, name, props, children }, typed values
-- { t = "Vector3" | "CFrame" | "Color3" | "Enum" }), plus { t = "Ref", name } for Motor6D /
-- Weld Part0 / Part1 and PrimaryPart, which Atelier.build sets after every node exists.
-- CFrame values are position + YXZ orientation in degrees (WorldSpec's convention).

local Contract = require("../Contract/Contract")
local Bodies = require("./Bodies")
local Colour = require("./Colour")
local Faces = require("./Faces")
local Wardrobe = require("./Wardrobe")

local Atelier = {}

Atelier.VERSION = 1
Atelier.Bodies = Bodies
Atelier.Colour = Colour
Atelier.Faces = Faces
Atelier.Wardrobe = Wardrobe
Atelier.SLOTS = Wardrobe.SLOTS
Atelier.WEALTH = { "poor", "common", "rich" }
-- palette slots a genome rolls (skin and hair colour are rolled on their own)
Atelier.PALETTE_SLOTS = { "shirt", "trousers", "boots", "primary", "secondary", "accent", "trim", "leather", "metal", "natural" }
-- colour slots every look book fixes (the same for everyone)
Atelier.FIXED_SLOTS = { "eye", "mouth", "blush", "glint" }
Atelier.DETAIL = { low = 1, medium = 2, high = 3 }
-- whole outfit slots dropped (in this order) when a body is over its part budget
Atelier.DROP_ORDER = { "hands", "back", "legs", "feet", "torso", "head" }

-- helpers ------------------------------------------------------------------------------------

local function sortedKeys(t: any): { string }
	local keys = {}
	for k in t or {} do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

local function pickList(list: { any }, u: number): any
	return list[math.min(#list, math.floor(u * #list) + 1)]
end

-- weights = { key = weight } (sorted keys, so every VM agrees)
local function pickWeighted(weights: any, u: number): string?
	local keys = sortedKeys(weights)
	local total = 0
	for _, k in keys do
		total += math.max(0, weights[k])
	end
	if total <= 0 then
		return nil
	end
	local x = u * total
	for _, k in keys do
		x -= math.max(0, weights[k])
		if x < 0 then
			return k
		end
	end
	return keys[#keys]
end

local function round(x: number, step: number): number
	return math.floor(x / step + 0.5) * step
end

local function has(list: { any }?, v: any): boolean
	for _, x in list or {} do
		if x == v then
			return true
		end
	end
	return false
end

-- look books -----------------------------------------------------------------------------------

-- Every piece a look book can use: the built-in wardrobe plus the look book's own `pieces`.
function Atelier.pieces(looks: any): { [string]: any }
	local out = {}
	for _, p in Wardrobe.pieces do
		out[p.id] = p
	end
	for _, p in (looks and looks.pieces) or {} do
		out[p.id] = p
	end
	return out
end

function Atelier.template(looks: any, name: string): any
	return ((looks and looks.rigs) or {})[name] or Bodies.templates[name]
end

local function tierRange(looks: any, wealth: string): (number, number)
	local w = (looks.wealth or {})[wealth]
	local t = (w and w.tiers) or { 1, 3 }
	return t[1], t[2]
end

-- Every problem with a look book (before or after resolve). Empty = usable.
function Atelier.checkLooks(looks: any): { string }
	local problems = {}
	local function bad(msg: string)
		table.insert(problems, msg)
	end
	if type(looks) ~= "table" then
		return { "a look book must be a table" }
	end
	if type(looks.id) ~= "string" or looks.id == "" then
		bad("looks.id must be a non-empty string")
	end
	local sw = looks.swatches
	if type(sw) ~= "table" or next(sw) == nil then
		bad("looks.swatches must name at least one swatch")
		sw = {}
	end
	for _, name in sortedKeys(sw) do
		local s = sw[name]
		local w = `swatch {name}`
		if type(s) ~= "table" then
			bad(`{w}: must be a table with lock = "group.name" or kit = "name"`)
			continue
		end
		if (s.lock == nil) == (s.kit == nil) then
			bad(`{w}: needs exactly one of lock = "group.name" or kit = "name"`)
		end
		if s.lock ~= nil and (type(s.lock) ~= "string" or not string.match(s.lock, "^[%w_]+%.[%w_]+$")) then
			bad(`{w}: lock must be "group.name", got {tostring(s.lock)}`)
		end
		if s.kit ~= nil and not Colour.isHex((looks.kit or {})[s.kit]) then
			bad(`{w}: kit {tostring(s.kit)} is not a #rrggbb entry of looks.kit`)
		end
		if s.hex ~= nil and not Colour.isHex(s.hex) then
			bad(`{w}: resolved hex {tostring(s.hex)} is not #rrggbb`)
		end
		if type(s.tier) ~= "number" or s.tier < 1 or s.tier > 3 then
			bad(`{w}: tier must be 1..3`)
		end
		for _, k in { "value", "sat" } do
			if s[k] ~= nil and (type(s[k]) ~= "number" or s[k] < 0 or s[k] > 3) then
				bad(`{w}: {k} must be a number 0..3`)
			end
		end
	end
	local function swatchList(where: string, list: any, allowEmpty: boolean?)
		if type(list) ~= "table" or (#list == 0 and not allowEmpty) then
			bad(`{where}: must be a non-empty list of swatch names`)
			return
		end
		for _, n in list do
			if sw[n] == nil then
				bad(`{where}: unknown swatch {tostring(n)}`)
			end
		end
	end
	for _, slot in Atelier.FIXED_SLOTS do
		local n = (looks.fixed or {})[slot]
		if sw[n] == nil then
			bad(`fixed.{slot}: must name a swatch, got {tostring(n)}`)
		end
	end
	swatchList("skins", looks.skins)
	swatchList("hairColours", looks.hairColours)
	local pal = looks.palette or {}
	for _, slot in Atelier.PALETTE_SLOTS do
		swatchList(`palette.base.{slot}`, (pal.base or {})[slot])
	end
	-- pieces
	local all = Atelier.pieces(looks)
	local attach = {}
	for _, p in Bodies.PARTS do
		attach[p.name] = true
	end
	for _, p in Wardrobe.check(looks.pieces or {}, attach) do
		bad("looks.pieces: " .. p)
	end
	local function pieceList(where: string, list: any, slot: string, allowNone: boolean)
		if type(list) ~= "table" or #list == 0 then
			bad(`{where}: must be a non-empty list of {slot} piece ids`)
			return
		end
		for _, id in list do
			if id == "none" and allowNone then
				continue
			end
			local p = all[id]
			if p == nil then
				bad(`{where}: unknown piece {tostring(id)}`)
			elseif p.slot ~= slot then
				bad(`{where}: piece {id} is a {p.slot} piece, not {slot}`)
			end
		end
	end
	for _, slot in Atelier.SLOTS do
		pieceList(`outfit.{slot}`, (looks.outfit or {})[slot], slot, true)
	end
	pieceList("accessories", looks.accessories, "accessory", false)
	-- wealth
	for _, w in Atelier.WEALTH do
		local d = (looks.wealth or {})[w]
		if type(d) ~= "table" or type(d.tiers) ~= "table" or #d.tiers ~= 2 or type(d.accessories) ~= "table" or #d.accessories ~= 2 then
			bad(`wealth.{w}: needs tiers = {"{lo, hi}"} and accessories = {"{lo, hi}"}`)
		elseif d.tiers[1] > d.tiers[2] or d.tiers[1] < 1 or d.tiers[2] > 3 then
			bad(`wealth.{w}: tiers must be 1 <= lo <= hi <= 3`)
		elseif d.accessories[1] > d.accessories[2] or d.accessories[1] < 0 or d.accessories[2] > 4 then
			bad(`wealth.{w}: accessories must be 0 <= lo <= hi <= 4`)
		end
	end
	-- bodies
	local bodies = looks.bodies
	if type(bodies) ~= "table" or next(bodies) == nil then
		bad("looks.bodies must name at least one body set")
		bodies = {}
	end
	for _, name in sortedKeys(bodies) do
		local b = bodies[name]
		local w = `bodies.{name}`
		local t = Atelier.template(looks, b.template)
		if t == nil then
			bad(`{w}: unknown template {tostring(b.template)}`)
		else
			for _, p in Bodies.checkTemplate(b.template, t) do
				bad(`{w}: {p}`)
			end
		end
		if type(b.scale) ~= "number" or b.scale <= 0 then
			bad(`{w}: scale must be a positive number`)
		end
		if type(b.builds) ~= "table" or next(b.builds) == nil then
			bad(`{w}: builds must weight at least one build`)
		else
			for _, k in sortedKeys(b.builds) do
				if Bodies.builds[k] == nil and ((looks.builds or {})[k] == nil) then
					bad(`{w}: unknown build {k}`)
				end
			end
		end
		if type(b.height) ~= "table" or #b.height ~= 2 or b.height[1] > b.height[2] or b.height[1] <= 0 then
			bad(`{w}: height must be {"{lo, hi}"} multipliers, lo <= hi`)
		end
		if type(b.budget) ~= "number" or b.budget < 16 then
			bad(`{w}: budget must be a part count >= 16 (the body alone is 16 parts)`)
		end
		if type(b.hair) ~= "table" or next(b.hair) == nil then
			bad(`{w}: hair must weight at least one hair style`)
		else
			for _, id in sortedKeys(b.hair) do
				local p = all[id]
				if p == nil or p.slot ~= "hair" then
					bad(`{w}: hair {id} is not a hair piece`)
				end
			end
		end
		for _, p in Faces.checkSet(`{w}.faces`, b.faces or looks.faces) do
			bad(p)
		end
	end
	-- cultures
	local cultures = looks.cultures
	if type(cultures) ~= "table" or next(cultures) == nil then
		bad("looks.cultures must name at least one culture")
		cultures = {}
	end
	for _, name in sortedKeys(cultures) do
		local c = cultures[name]
		if type(c.weight) ~= "number" or c.weight < 0 then
			bad(`cultures.{name}: weight must be a number >= 0`)
		end
		for _, slot in sortedKeys(c.prefer) do
			if not has(Atelier.PALETTE_SLOTS, slot) then
				bad(`cultures.{name}.prefer: {slot} is not a palette slot`)
			else
				swatchList(`cultures.{name}.prefer.{slot}`, c.prefer[slot])
			end
		end
		for _, id in c.pieces or {} do
			if all[id] == nil then
				bad(`cultures.{name}.pieces: unknown piece {tostring(id)}`)
			end
		end
	end
	-- roles
	local roles = looks.roles
	if type(roles) ~= "table" or next(roles) == nil then
		bad("looks.roles must name at least one role")
		roles = {}
	end
	if roles[looks.defaultRole] == nil then
		bad(`defaultRole {tostring(looks.defaultRole)} is not a role`)
	end
	for _, name in sortedKeys(roles) do
		local r = roles[name]
		local w = `roles.{name}`
		if type(r.body) ~= "table" or #r.body == 0 then
			bad(`{w}: body must list at least one body set`)
		else
			for _, b in r.body do
				if bodies[b] == nil then
					bad(`{w}: unknown body set {tostring(b)}`)
				end
			end
		end
		for _, k in sortedKeys(r.wealth) do
			if not has(Atelier.WEALTH, k) then
				bad(`{w}: wealth {k} is not poor | common | rich`)
			end
		end
		for _, slot in sortedKeys(r.outfit) do
			if not has(Atelier.SLOTS, slot) then
				bad(`{w}: outfit slot {slot} is not one of head torso legs feet back hands`)
			else
				pieceList(`{w}.outfit.{slot}`, r.outfit[slot], slot, true)
			end
		end
		if r.accessories ~= nil then
			if #r.accessories > 0 then
				pieceList(`{w}.accessories`, r.accessories, "accessory", false)
			end
		end
		for _, slot in sortedKeys(r.palette) do
			if not has(Atelier.PALETTE_SLOTS, slot) then
				bad(`{w}.palette: {slot} is not a palette slot`)
			else
				swatchList(`{w}.palette.{slot}`, r.palette[slot])
			end
		end
		if r.hairColours ~= nil then
			swatchList(`{w}.hairColours`, r.hairColours)
		end
		if r.crowd ~= nil and (type(r.crowd) ~= "number" or r.crowd < 0) then
			bad(`{w}: crowd must be a weight >= 0`)
		end
	end
	return problems
end

-- Resolve every swatch to a hex through the game's lock palette ({ group = { name = "#hex" } },
-- e.g. a compiled lock's Palette.hex) and the look book's kit. Returns a copy with
-- swatches[name].hex and .source ("lock:group.name" or "kit:name"); raises on a missing colour.
function Atelier.resolve(looks: any, lockGroups: any): any
	local out = table.clone(looks)
	out.swatches = {}
	local missing = {}
	for _, name in sortedKeys(looks.swatches) do
		local s = table.clone(looks.swatches[name])
		local base, source
		if s.lock then
			local g, n = string.match(s.lock, "^([%w_]+)%.([%w_]+)$")
			local grp = g and (lockGroups or {})[g]
			base = grp and grp[n]
			source = "lock:" .. tostring(s.lock)
		elseif s.kit then
			base = (looks.kit or {})[s.kit]
			source = "kit:" .. tostring(s.kit)
		end
		if not Colour.isHex(base) then
			table.insert(missing, `{name} ({source})`)
		else
			s.hex = if s.value or s.sat then Colour.shade(base, s.value, s.sat) else string.upper(base)
			s.source = source
		end
		out.swatches[name] = s
	end
	if #missing > 0 then
		error("Atelier.resolve: swatches with no colour in the lock or kit: " .. table.concat(missing, ", "), 2)
	end
	out.resolved = true
	return out
end

-- roll -----------------------------------------------------------------------------------------

local function lookBook(context: any): any
	local looks = context and context.looks
	assert(type(looks) == "table", "Atelier.roll needs context.looks (a look book)")
	return looks
end

-- Draw `n` numbers up front so an overridden choice never shifts the ones after it.
local function draws(rng: Contract.Rng, n: number): { number }
	local u = table.create(n)
	for i = 1, n do
		u[i] = rng:next()
	end
	return u
end

local MAX_ACCESSORIES = 4

-- A genome for `seed`. context = { looks, role?, culture?, wealth?, rig? } (overrides skip
-- nothing: every draw is taken, so naming the role a seed would have rolled gives the same person).
function Atelier.roll(seed: number, context: any): any
	local looks = lookBook(context)
	assert(type(seed) == "number" and seed == math.floor(seed), "Atelier.roll needs an integer seed")
	local rng = Contract.Rng.new(seed)
	local u = draws(rng, 32)
	local all = Atelier.pieces(looks)
	local ctx = context or {}

	-- who
	local roleWeights = {}
	for name, r in looks.roles do
		roleWeights[name] = r.crowd or 1
	end
	local role = ctx.role or pickWeighted(roleWeights, u[1]) or looks.defaultRole
	local R = looks.roles[role]
	if R == nil then
		error(`Atelier.roll: unknown role {tostring(role)} (look book {tostring(looks.id)})`, 2)
	end
	local cultureWeights = {}
	for name, c in looks.cultures do
		cultureWeights[name] = c.weight
	end
	local culture = ctx.culture or pickWeighted(cultureWeights, u[2])
	local C = looks.cultures[culture]
	if C == nil then
		error(`Atelier.roll: unknown culture {tostring(culture)}`, 2)
	end
	local wealth = ctx.wealth or pickWeighted(R.wealth or { common = 1 }, u[3]) or "common"
	if not has(Atelier.WEALTH, wealth) then
		error(`Atelier.roll: unknown wealth {tostring(wealth)}`, 2)
	end
	local lo, hi = tierRange(looks, wealth)

	-- body
	local rig = ctx.rig or pickList(R.body, u[4])
	local B = looks.bodies[rig]
	if B == nil then
		error(`Atelier.roll: unknown body set {tostring(rig)}`, 2)
	end
	local build = pickWeighted(B.builds, u[5]) or "average"
	local height = round(B.height[1] + (B.height[2] - B.height[1]) * u[6], 0.01)
	local skin = pickList(looks.skins, u[7])
	local hairStyle = pickWeighted(B.hair, u[8])
	local hairColour = pickList(R.hairColours or looks.hairColours, u[9])

	-- outfit: the role's list for a slot (else the look book's), plus the culture's pieces for
	-- that slot, minus pieces above or below the wealth's tiers (never empty: the cheapest stays)
	local outfit = {}
	for i, slot in Atelier.SLOTS do
		local list = table.clone((R.outfit or {})[slot] or (looks.outfit or {})[slot] or { "none" })
		if not (R.lockOutfit and (R.outfit or {})[slot]) then
			for _, id in C.pieces or {} do
				local p = all[id]
				if p and p.slot == slot then
					table.insert(list, id)
				end
			end
		end
		local ok = {}
		for _, id in list do
			local p = all[id]
			if id == "none" or (p and p.tier >= lo and p.tier <= hi) then
				table.insert(ok, id)
			end
		end
		if #ok == 0 then
			local best, bestTier = list[1], math.huge
			for _, id in list do
				local p = all[id]
				if p and p.tier < bestTier then
					best, bestTier = id, p.tier
				end
			end
			ok = { best }
		end
		outfit[slot] = pickList(ok, u[9 + i])
	end

	-- accessories: a count from the wealth, distinct, within tiers
	local W = (looks.wealth or {})[wealth] or { accessories = { 0, 1 } }
	local nAcc = W.accessories[1] + math.floor(u[16] * (W.accessories[2] - W.accessories[1] + 1))
	local pool = {}
	for _, id in R.accessories or looks.accessories or {} do
		local p = all[id]
		if p and p.tier >= lo and p.tier <= hi and not has(pool, id) then
			table.insert(pool, id)
		end
	end
	local accessories = {}
	for k = 1, math.min(nAcc, MAX_ACCESSORIES) do
		if #pool == 0 then
			break
		end
		local idx = math.min(#pool, math.floor(u[16 + k] * #pool) + 1)
		table.insert(accessories, table.remove(pool, idx))
	end
	table.sort(accessories)

	-- palette: per slot, the role's swatches (else the base), the culture's preferred ones
	-- counted twice, filtered to the wealth's tiers (never empty)
	local slots = {}
	local sw = looks.swatches
	for i, slot in Atelier.PALETTE_SLOTS do
		local list = table.clone((R.palette or {})[slot] or looks.palette.base[slot])
		for _, n in ((C.prefer or {})[slot]) or {} do
			table.insert(list, n)
			table.insert(list, n)
		end
		local ok = {}
		for _, n in list do
			local t = sw[n] and sw[n].tier or 1
			if t >= lo and t <= hi then
				table.insert(ok, n)
			end
		end
		if #ok == 0 then
			local best, bestTier = list[1], math.huge
			for _, n in list do
				local t = sw[n] and sw[n].tier or 1
				if t < bestTier then
					best, bestTier = n, t
				end
			end
			ok = { best }
		end
		local k = math.min(#ok, math.floor(u[20 + i] * #ok) + 1)
		local pick = ok[k]
		-- readability: secondary differs from primary, trousers from shirt (next candidate)
		local clash = (slot == "secondary" and pick == slots.primary) or (slot == "trousers" and pick == slots.shirt)
		if clash then
			for step = 1, #ok - 1 do
				local alt = ok[(k - 1 + step) % #ok + 1]
				if alt ~= pick then
					pick = alt
					break
				end
			end
		end
		slots[slot] = pick
	end

	-- face
	local F = B.faces or looks.faces
	local eyes = pickList(F.eyes, u[31])
	local fu = u[32]
	local brows = pickList(F.brows, (fu * 7) % 1)
	local mouth = pickList(F.mouths, (fu * 13) % 1)
	local blush = ((fu * 29) % 1) < (F.blush or 0.5)

	return {
		v = Atelier.VERSION,
		seed = seed,
		looks = looks.id,
		role = role,
		body = { rig = rig, build = build, height = height },
		skin = skin,
		hair = { style = hairStyle, colour = hairColour },
		outfit = outfit,
		accessories = accessories,
		palette = { role = role, culture = culture, wealth = wealth, slots = slots },
		face = { eyes = eyes, brows = brows, mouth = mouth, blush = blush, texture = Faces.textureId(eyes, brows, mouth) },
	}
end

-- Every problem with a genome against a look book (unknown pieces, swatches, slots).
function Atelier.checkGenome(g: any, looks: any): { string }
	local problems = {}
	local function bad(m: string)
		table.insert(problems, m)
	end
	if type(g) ~= "table" then
		return { "a genome must be a table" }
	end
	if g.v ~= Atelier.VERSION then
		bad(`v must be {Atelier.VERSION}`)
	end
	if type(g.seed) ~= "number" then
		bad("seed must be a number")
	end
	if g.looks ~= looks.id then
		bad(`looks {tostring(g.looks)} is not this look book ({tostring(looks.id)})`)
	end
	if looks.roles[g.role] == nil then
		bad(`unknown role {tostring(g.role)}`)
	end
	local body = g.body or {}
	if looks.bodies[body.rig] == nil then
		bad(`unknown body set {tostring(body.rig)}`)
	end
	if Bodies.builds[body.build] == nil and (looks.builds or {})[body.build] == nil then
		bad(`unknown build {tostring(body.build)}`)
	end
	if type(body.height) ~= "number" or body.height <= 0 then
		bad("body.height must be a positive multiplier")
	end
	local sw = looks.swatches
	if sw[g.skin] == nil then
		bad(`unknown skin swatch {tostring(g.skin)}`)
	end
	local all = Atelier.pieces(looks)
	local hs = g.hair and all[g.hair.style]
	if hs == nil or hs.slot ~= "hair" then
		bad(`unknown hair style {tostring(g.hair and g.hair.style)}`)
	end
	if sw[g.hair and g.hair.colour] == nil then
		bad(`unknown hair colour {tostring(g.hair and g.hair.colour)}`)
	end
	for _, slot in Atelier.SLOTS do
		local id = (g.outfit or {})[slot]
		if id ~= "none" then
			local p = all[id]
			if p == nil or p.slot ~= slot then
				bad(`outfit.{slot}: {tostring(id)} is not a {slot} piece`)
			end
		end
	end
	for _, id in g.accessories or {} do
		local p = all[id]
		if p == nil or p.slot ~= "accessory" then
			bad(`accessories: {tostring(id)} is not an accessory`)
		end
	end
	local pal = g.palette or {}
	for _, slot in Atelier.PALETTE_SLOTS do
		if sw[(pal.slots or {})[slot]] == nil then
			bad(`palette.slots.{slot}: unknown swatch {tostring((pal.slots or {})[slot])}`)
		end
	end
	if not has(Atelier.WEALTH, pal.wealth) then
		bad(`palette.wealth {tostring(pal.wealth)} is not poor | common | rich`)
	end
	if looks.cultures[pal.culture] == nil then
		bad(`unknown culture {tostring(pal.culture)}`)
	end
	local f = g.face or {}
	if Faces.eyes[f.eyes] == nil or Faces.brows[f.brows] == nil or Faces.mouths[f.mouth] == nil then
		bad(`face {tostring(f.eyes)}/{tostring(f.brows)}/{tostring(f.mouth)} names an unknown style`)
	elseif f.texture ~= Faces.textureId(f.eyes, f.brows, f.mouth) then
		bad(`face.texture {tostring(f.texture)} does not match its styles`)
	end
	return problems
end

-- distance -------------------------------------------------------------------------------------

Atelier.WEIGHTS = {
	role = 0.04,
	rig = 0.08,
	build = 0.08,
	height = 0.04,
	skin = 0.08,
	hairStyle = 0.1,
	hairColour = 0.1,
	outfit = 0.3, -- shared by the six slots
	accessories = 0.04,
	primary = 0.1,
	secondary = 0.06,
	accent = 0.04,
	face = 0.06,
}

local function hexOf(looks: any, swatch: string): string?
	local s = looks and looks.swatches and looks.swatches[swatch]
	return s and s.hex
end

-- 0 = the same swatch; else 1, or (with a resolved look book) the colours' distance x 2.5, capped.
local function colourTerm(looks: any, a: string, b: string): number
	if a == b then
		return 0
	end
	local ha, hb = hexOf(looks, a), hexOf(looks, b)
	if ha and hb then
		return math.min(1, 2.5 * Colour.distance(ha, hb))
	end
	return 1
end

-- How different two people look, 0 (identical) .. 1. `looks` (resolved) makes colours compare
-- by hue and value instead of by name.
function Atelier.distance(a: any, b: any, looks: any?): number
	local W = Atelier.WEIGHTS
	local d, total = 0, 0
	local function add(w: number, x: number)
		d += w * x
		total += w
	end
	add(W.role, if a.role == b.role then 0 else 1)
	add(W.rig, if a.body.rig == b.body.rig then 0 else 1)
	add(W.build, if a.body.build == b.body.build then 0 else 1)
	add(W.height, math.min(1, math.abs(a.body.height - b.body.height) / 0.12))
	add(W.skin, colourTerm(looks, a.skin, b.skin))
	add(W.hairStyle, if a.hair.style == b.hair.style then 0 else 1)
	add(W.hairColour, colourTerm(looks, a.hair.colour, b.hair.colour))
	for _, slot in Atelier.SLOTS do
		add(W.outfit / #Atelier.SLOTS, if a.outfit[slot] == b.outfit[slot] then 0 else 1)
	end
	local union, inter = {}, 0
	for _, id in a.accessories do
		union[id] = true
	end
	for _, id in b.accessories do
		if union[id] then
			inter += 1
		end
		union[id] = true
	end
	local nu = 0
	for _ in union do
		nu += 1
	end
	add(W.accessories, if nu == 0 then 0 else 1 - inter / nu)
	for _, slot in { "primary", "secondary", "accent" } do
		add(W[slot], colourTerm(looks, a.palette.slots[slot], b.palette.slots[slot]))
	end
	local fa, fb = a.face, b.face
	local fd = (if fa.eyes == fb.eyes then 0 else 1) + (if fa.brows == fb.brows then 0 else 1) + (if fa.mouth == fb.mouth then 0 else 1)
	add(W.face, fd / 3)
	return d / total
end

-- crowds ---------------------------------------------------------------------------------------

-- The seed of person i (1-based), attempt k (0-based) in a crowd seeded `seed`.
function Atelier.crowdSeed(seed: number, i: number, attempt: number): number
	return (math.floor(math.abs(seed)) * 1000003 + i * 7919 + attempt * 104729) % 2147483647
end

-- Pairs of neighbours (within `window` places in the line) closer than `minDistance`.
function Atelier.checkCrowd(people: { any }, minDistance: number, window: number?, looks: any?): { any }
	local out = {}
	local w = window or 2
	for i = 2, #people do
		for j = math.max(1, i - w), i - 1 do
			local d = Atelier.distance(people[i], people[j], looks)
			if d < minDistance then
				table.insert(out, { i = j, j = i, d = d })
			end
		end
	end
	return out
end

-- A line of n people where no two within `window` places are closer than `minDistance`.
-- context = { looks, role?, roles? (cycled per person), culture?, wealth? }
-- opts = { minDistance?, window?, attempts? } (defaults: looks.crowd, else 0.3 / 2 / 16).
-- Returns { people, seeds, report = { n, minDistance, window, attempts, rerolls, worst, violations } }.
function Atelier.crowd(seed: number, n: number, context: any, opts: any?): any
	local looks = lookBook(context)
	local o = opts or {}
	local defaults = looks.crowd or {}
	local minD = o.minDistance or defaults.minDistance or 0.3
	local window = o.window or defaults.window or 2
	local attempts = o.attempts or defaults.attempts or 16
	local people, seeds = {}, {}
	local rerolls = 0
	for i = 1, n do
		local ctx = table.clone(context)
		if context.roles and #context.roles > 0 then
			ctx.role = context.roles[(i - 1) % #context.roles + 1]
		end
		local best, bestSeed, bestD = nil, 0, -1
		for k = 0, attempts - 1 do
			local s = Atelier.crowdSeed(seed, i, k)
			local g = Atelier.roll(s, ctx)
			local nearest = math.huge
			for j = math.max(1, i - window), i - 1 do
				nearest = math.min(nearest, Atelier.distance(g, people[j], looks))
			end
			if nearest > bestD then
				best, bestSeed, bestD = g, s, nearest
			end
			if nearest >= minD then
				break
			end
			rerolls += 1
		end
		people[i] = best
		seeds[i] = bestSeed
	end
	local violations = Atelier.checkCrowd(people, minD, window, looks)
	local worst = math.huge
	for i = 2, #people do
		for j = math.max(1, i - window), i - 1 do
			worst = math.min(worst, Atelier.distance(people[i], people[j], looks))
		end
	end
	return {
		people = people,
		seeds = seeds,
		report = {
			n = n,
			minDistance = minD,
			window = window,
			attempts = attempts,
			rerolls = rerolls,
			worst = if worst == math.huge then nil else worst,
			violations = violations,
		},
	}
end

-- parts and descriptors ------------------------------------------------------------------------

-- Row-major 3x3 of CFrame.Angles(rx, ry, rz) (degrees): Rx * Ry * Rz.
local function anglesMatrix(rot: { number }?): { number }
	local r = rot or { 0, 0, 0 }
	local a, b, c = math.rad(r[1]), math.rad(r[2]), math.rad(r[3])
	local ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
	-- Rx*Ry
	local m = {
		cb, 0, sb,
		sa * sb, ca, -sa * cb,
		-ca * sb, sa, ca * cb,
	}
	-- (Rx*Ry)*Rz
	return {
		m[1] * cc + m[2] * sc, -m[1] * sc + m[2] * cc, m[3],
		m[4] * cc + m[5] * sc, -m[4] * sc + m[5] * cc, m[6],
		m[7] * cc + m[8] * sc, -m[7] * sc + m[8] * cc, m[9],
	}
end
Atelier.anglesMatrix = anglesMatrix

-- YXZ Euler angles (degrees) of a row-major rotation (CFrame:ToEulerAnglesYXZ).
local function toYXZ(m: { number }): (number, number, number)
	local x = math.asin(math.max(-1, math.min(1, -m[6])))
	local y = math.atan2(m[3], m[9])
	local z = math.atan2(m[4], m[5])
	local function deg(v: number): number
		local d = math.deg(v)
		return math.floor(d * 1e4 + 0.5) / 1e4
	end
	return deg(x), deg(y), deg(z)
end
Atelier.toYXZ = toYXZ

local function colourFor(genome: any, looks: any, slot: string): (string, string)
	local swatch
	if slot == "skin" then
		swatch = genome.skin
	elseif slot == "hair" then
		swatch = genome.hair.colour
	elseif (looks.fixed or {})[slot] then
		swatch = looks.fixed[slot]
	else
		swatch = genome.palette.slots[slot]
	end
	local s = looks.swatches[swatch]
	if s == nil or s.hex == nil then
		error(`Atelier: colour slot {slot} -> swatch {tostring(swatch)} has no resolved hex (Atelier.resolve the look book first)`, 3)
	end
	return swatch, s.hex
end

local function r3(v: number): number
	return math.floor(v * 1000 + 0.5) / 1000
end

-- The person as a flat list of parts at rest (world studs, pivot at the soles, facing -z):
-- { name, kind = body | hair | face | outfit | accessory, slot?, piece?, attach, shape, size,
--   pos, R (row-major 3x3), offset (from the attach part, studs), rot, color (slot), swatch,
--   hex, material, transparency }. opts = { detail = "low" | "medium" | "high" }.
-- Returns parts, joints, info = { count, budget, dropped = { piece ids }, height }.
function Atelier.parts(genome: any, looks: any, opts: any?): ({ any }, { any }, any)
	local o = opts or {}
	local detail = Atelier.DETAIL[o.detail or "high"] or 3
	local B = looks.bodies[genome.body.rig]
	if B == nil then
		error(`Atelier.parts: unknown body set {tostring(genome.body.rig)}`, 2)
	end
	local template = Atelier.template(looks, B.template)
	local build = Bodies.builds[genome.body.build] or (looks.builds or {})[genome.body.build] or {}
	local layout, jointsAt = Bodies.layout(template, build)
	local S = B.scale * genome.body.height
	local all = Atelier.pieces(looks)

	-- body paint groups -> colour slot, then outfit tints
	local paint = { torso = "shirt", sleeve = "shirt", legs = "trousers", feet = "boots", hands = "skin", skin = "skin" }
	for _, slot in Atelier.SLOTS do
		local p = all[genome.outfit[slot]]
		for _, g in sortedKeys(p and p.tint) do
			paint[g] = p.tint[g]
		end
	end

	-- the pieces worn, in draw order
	local worn = {}
	local headPiece = all[genome.outfit.head]
	local hairShows = (headPiece and headPiece.hair) or "all"
	local hairPiece = all[genome.hair.style]
	if hairPiece and hairShows ~= "none" then
		local ps = {}
		for _, part in hairPiece.parts do
			if hairShows == "all" or part.back then
				table.insert(ps, part)
			end
		end
		table.insert(worn, { kind = "hair", id = hairPiece.id, parts = ps })
	end
	table.insert(worn, { kind = "face", id = "face", parts = Faces.parts(genome.face) })
	for _, slot in Atelier.SLOTS do
		local p = all[genome.outfit[slot]]
		if p then
			table.insert(worn, { kind = "outfit", slot = slot, id = p.id, parts = p.parts })
		end
	end
	for _, id in genome.accessories do
		local p = all[id]
		if p then
			table.insert(worn, { kind = "accessory", slot = "accessory", id = id, parts = p.parts })
		end
	end

	-- detail, then the part budget (whole accessories last-first, then small trim, then whole
	-- outfit pieces in DROP_ORDER; body, hair and face always stay)
	local function keep(part: any, minRank: number): boolean
		local q = part.minQuality and Atelier.DETAIL[part.minQuality] or 1
		return q <= minRank
	end
	local function count(rank: number): number
		local n = #Bodies.PARTS
		for _, w in worn do
			if not w.dropped then
				for _, part in w.parts do
					if keep(part, rank) then
						n += 1
					end
				end
			end
		end
		return n
	end
	local dropped = {}
	local rank = detail
	local budget = B.budget
	for i = #worn, 1, -1 do
		if count(rank) <= budget then
			break
		end
		if worn[i].kind == "accessory" then
			worn[i].dropped = true
			table.insert(dropped, worn[i].id)
		end
	end
	while count(rank) > budget and rank > 1 do
		rank -= 1
	end
	for _, slot in Atelier.DROP_ORDER do
		if count(rank) <= budget then
			break
		end
		for _, w in worn do
			if w.kind == "outfit" and w.slot == slot and not w.dropped then
				w.dropped = true
				table.insert(dropped, w.id)
			end
		end
	end

	local parts = {}
	local used = {}
	local function uniqueName(n: string): string
		if not used[n] then
			used[n] = true
			return n
		end
		local k = 2
		while used[`{n}_{k}`] do
			k += 1
		end
		used[`{n}_{k}`] = true
		return `{n}_{k}`
	end
	for _, bp in Bodies.PARTS do
		local L = layout[bp.name]
		local slot = if bp.paint == "hidden" then "skin" else (paint[bp.paint] or "skin")
		local swatch, hex = colourFor(genome, looks, slot)
		table.insert(parts, {
			name = uniqueName(bp.name),
			kind = "body",
			attach = bp.name,
			shape = if L.round then "Ball" else "Block",
			size = { r3(L.size[1] * S), r3(L.size[2] * S), r3(L.size[3] * S) },
			pos = { r3(L.pos[1] * S), r3(L.pos[2] * S), r3(L.pos[3] * S) },
			R = { 1, 0, 0, 0, 1, 0, 0, 0, 1 },
			offset = { 0, 0, 0 },
			rot = { 0, 0, 0 },
			color = slot,
			swatch = swatch,
			hex = hex,
			material = "SmoothPlastic",
			transparency = if bp.paint == "hidden" then 1 else 0,
		})
	end
	for _, w in worn do
		if w.dropped then
			continue
		end
		for _, part in w.parts do
			if not keep(part, rank) then
				continue
			end
			local L = layout[part.attach]
			local k = L.ratio
			local off = { part.offset[1] * k[1] * S, part.offset[2] * k[2] * S, part.offset[3] * k[3] * S }
			local size = { part.size[1] * k[1] * S, part.size[2] * k[2] * S, part.size[3] * k[3] * S }
			local swatch, hex = colourFor(genome, looks, part.color)
			table.insert(parts, {
				name = uniqueName(part.name),
				kind = w.kind,
				slot = w.slot,
				piece = w.id,
				attach = part.attach,
				shape = part.shape,
				size = { r3(size[1]), r3(size[2]), r3(size[3]) },
				pos = { r3(L.pos[1] * S + off[1]), r3(L.pos[2] * S + off[2]), r3(L.pos[3] * S + off[3]) },
				R = anglesMatrix(part.rot),
				offset = { r3(off[1]), r3(off[2]), r3(off[3]) },
				rot = part.rot or { 0, 0, 0 },
				color = part.color,
				swatch = swatch,
				hex = hex,
				material = part.material or "SmoothPlastic",
				transparency = part.transparency or 0,
				face = part.face,
			})
		end
	end
	local joints = {}
	for _, j in Bodies.JOINTS do
		local at = jointsAt[j.name].at
		table.insert(joints, { name = j.name, part0 = j.part0, part1 = j.part1, at = { r3(at[1] * S), r3(at[2] * S), r3(at[3] * S) } })
	end
	local info = {
		count = #parts,
		budget = budget,
		detail = rank,
		dropped = dropped,
		height = r3(Bodies.height(layout) * S),
	}
	return parts, joints, info
end

local function vec3(v: { number }): any
	return { t = "Vector3", x = v[1], y = v[2], z = v[3] }
end
local function cframe(p: { number }, R: { number }?): any
	local rx, ry, rz = 0, 0, 0
	if R then
		rx, ry, rz = toYXZ(R)
	end
	return { t = "CFrame", x = p[1], y = p[2], z = p[3], rx = rx, ry = ry, rz = rz }
end
local function color3(hex: string): any
	local r, g, b = Colour.parse(hex)
	return { t = "Color3", r = r, g = g, b = b }
end
local function enum(e: string, n: string): any
	return { t = "Enum", enum = e, name = n }
end
local function ref(name: string): any
	return { t = "Ref", name = name }
end

-- The person as one Model descriptor (WorldSpec shape). opts = { detail?, prefix? (attribute
-- prefix, e.g. "GI_"), name?, system? (sets <prefix>System) }. Returns desc, info.
function Atelier.describe(genome: any, looks: any, opts: any?): (any, any)
	local o = opts or {}
	local prefix = o.prefix or ""
	local parts, joints, info = Atelier.parts(genome, looks, o)
	local byName = {}
	for _, p in parts do
		byName[p.name] = p
	end
	local jointOf = {}
	for _, j in joints do
		jointOf[j.part1] = j
	end
	local children = {}
	for _, p in parts do
		local props: any = {
			Size = vec3(p.size),
			CFrame = cframe(p.pos, p.R),
			Color = color3(p.hex),
			Material = enum("Material", p.material),
			Transparency = p.transparency,
			Anchored = p.name == "HumanoidRootPart",
			CanCollide = false,
			CanTouch = false,
			CanQuery = p.name == "HumanoidRootPart",
			Massless = p.name ~= "HumanoidRootPart",
		}
		local className = "Part"
		local kids = {}
		if p.shape == "Cylinder" then
			props.Shape = enum("PartType", "Cylinder")
		elseif p.shape == "Wedge" then
			className = "WedgePart"
		elseif p.shape == "Ball" then
			table.insert(kids, { className = "SpecialMesh", name = "Mesh", props = { MeshType = enum("MeshType", "Sphere") }, children = {} })
		end
		if p.name == "HumanoidRootPart" then
			props.PivotOffset = cframe({ 0, -p.pos[2], 0 })
		end
		if p.kind == "body" then
			local j = jointOf[p.name]
			if j then
				local p0 = byName[j.part0]
				table.insert(kids, {
					className = "Motor6D",
					name = j.name,
					props = {
						Part0 = ref(j.part0),
						Part1 = ref(j.part1),
						C0 = cframe({ r3(j.at[1] - p0.pos[1]), r3(j.at[2] - p0.pos[2]), r3(j.at[3] - p0.pos[3]) }),
						C1 = cframe({ r3(j.at[1] - p.pos[1]), r3(j.at[2] - p.pos[2]), r3(j.at[3] - p.pos[3]) }),
					},
					children = {},
				})
			end
		else
			local attrs: any = { [prefix .. "Piece"] = p.piece or "" }
			if p.face then
				attrs[prefix .. "Face"] = p.face
			end
			props.Attributes = attrs
			table.insert(kids, {
				className = "Weld",
				name = "PieceWeld",
				props = { Part0 = ref(p.attach), Part1 = ref(p.name), C0 = cframe(p.offset, p.R) },
				children = {},
			})
		end
		table.insert(children, { className = className, name = p.name, props = props, children = kids })
	end
	local outfitIds = {}
	for _, slot in Atelier.SLOTS do
		table.insert(outfitIds, genome.outfit[slot])
	end
	local attrs: any = {
		[prefix .. "LookSeed"] = genome.seed,
		[prefix .. "RigKind"] = genome.body.rig,
		[prefix .. "RigScale"] = r3(looks.bodies[genome.body.rig].scale * genome.body.height),
		[prefix .. "Role"] = genome.role,
		[prefix .. "Outfit"] = table.concat(outfitIds, ","),
		[prefix .. "FaceTexture"] = genome.face.texture,
		[prefix .. "Atelier"] = Atelier.VERSION,
	}
	if o.system then
		attrs[prefix .. "System"] = o.system
	end
	local desc = {
		className = "Model",
		name = o.name or `Atelier_{genome.seed}`,
		props = { Attributes = attrs, PrimaryPart = ref("HumanoidRootPart") },
		children = children,
	}
	return desc, info
end

-- Make a descriptor through a WorldSpec-style factory(className, props, parent) -> instance.
-- Ref props are set once every node exists, through setRef(inst, key, target) (default: a
-- mock node's props table, else inst[key] = target). The root is parented last.
function Atelier.build(desc: any, factory: any, parent: any?, setRef: any?): (any, number)
	local named = {}
	local pending = {}
	local made = 0
	local function make(d: any, par: any?): any
		local props = {}
		local refs = {}
		for k, v in d.props or {} do
			if type(v) == "table" and v.t == "Ref" then
				refs[k] = v.name
			else
				props[k] = v
			end
		end
		props.Name = d.name
		local inst = factory(d.className, props, par)
		made += 1
		if par ~= nil and named[d.name] == nil then
			named[d.name] = inst
		end
		for _, k in sortedKeys(refs) do
			table.insert(pending, { inst = inst, key = k, name = refs[k] })
		end
		for _, c in d.children or {} do
			make(c, inst)
		end
		return inst
	end
	local root = make(desc, nil)
	local set = setRef
		or function(inst: any, key: string, target: any)
			if type(inst) == "table" and type(inst.props) == "table" then
				inst.props[key] = target
			else
				inst[key] = target
			end
		end
	for _, p in pending do
		local target = named[p.name]
		if target == nil then
			error(`Atelier.build: {p.key} names {p.name}, which the descriptor does not make`, 2)
		end
		set(p.inst, p.key, target)
	end
	if parent ~= nil then
		root.Parent = parent
	end
	return root, made
end

-- adapter-bound use ----------------------------------------------------------------------------

-- An Atelier bound to a game: looks (resolved) + the Contract adapter (tag, log).
function Atelier.new(adapter: Contract.Adapter, looks: any): any
	local problems = Contract.check(adapter)
	assert(#problems == 0, "Atelier.new: " .. table.concat(problems, "; "))
	assert(looks and looks.resolved, "Atelier.new needs a resolved look book (Atelier.resolve)")
	local self = {}
	function self.roll(seed: number, context: any?): any
		local ctx = table.clone(context or {})
		ctx.looks = looks
		return Atelier.roll(seed, ctx)
	end
	function self.describe(genome: any, opts: any?): (any, any)
		local o = table.clone(opts or {})
		if o.detail == nil then
			o.detail = ({ "low", "medium", "high" })[adapter.quality()] or "high"
		end
		return Atelier.describe(genome, looks, o)
	end
	function self.build(genome: any, factory: any, parent: any?, opts: any?): any
		local desc, info = self.describe(genome, opts)
		if #info.dropped > 0 then
			adapter.log("info", "Atelier: over the part budget, dropped pieces", { seed = genome.seed, dropped = info.dropped })
		end
		local root = Atelier.build(desc, factory, parent, opts and opts.setRef)
		adapter.tag(root, (opts and opts.system) or "Atelier")
		return root, info
	end
	return self
end

return Atelier
