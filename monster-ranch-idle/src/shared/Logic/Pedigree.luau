--[[
	Pedigree (update 3.9): a bred monster's family, two generations deep. Pure rules shared by
	the server (breeding, trades, the Market view) and the client (the family tree).

	Monster record field `ped` (bred monsters only; hatched and rewarded monsters have none):
	  { a = Snap, b = Snap, aa = Snap?, ab = Snap?, ba = Snap?, bb = Snap? }
	  a, b    the parents when the baby was bred
	  aa, ab  parent a's own parents (its ped.a / ped.b), ba, bb the same for parent b
	Snap = { line, form, rarity, variant?, name?, gen, grades }
	  grades  one grade letter per gene stat in Config.Genetics.Stats order ("BACDS")
	Never deeper than grandparents, and never an id: ids are per player and change on trade.

	  Pedigree.Snap(m) -> Snap                  a monster as its descendants remember it
	  Pedigree.Build(a, b) -> ped               a baby of parents a and b
	  Pedigree.Copy(ped) -> ped?                a clean deep copy (nil when there is none)
	  Pedigree.Name(snap) -> string             its name, or its form's name
	  Pedigree.ParentNames(ped) -> (string, string)?
]]

local Config = require(script.Parent.Parent.Config)
local Genetics = require(script.Parent.Genetics)

local Pedigree = {}

local SLOTS = { "a", "b", "aa", "ab", "ba", "bb" }
local GRADE_LETTERS = {}
for _, g in Config.Genetics.Grades do
	table.insert(GRADE_LETTERS, g.grade)
end
local GRADE_PATTERN = "^[" .. table.concat(GRADE_LETTERS) .. "]+$"

local function validSnap(snap): boolean
	return type(snap) == "table"
		and type(snap.line) == "string"
		and type(snap.rarity) == "number"
		and type(snap.grades) == "string"
		and #snap.grades == #Config.Genetics.Stats
		and string.match(snap.grades, GRADE_PATTERN) ~= nil
end

local function copySnap(snap)
	if not validSnap(snap) then
		return nil
	end
	return {
		line = snap.line,
		form = if type(snap.form) == "string" then snap.form else nil,
		rarity = snap.rarity,
		variant = if type(snap.variant) == "number" and snap.variant ~= 0 then snap.variant else nil,
		name = if type(snap.name) == "string" and snap.name ~= "" then snap.name else nil,
		gen = if type(snap.gen) == "number" then snap.gen else 0,
		grades = snap.grades,
	}
end

function Pedigree.Snap(m)
	return {
		line = m.line,
		form = if type(m.form) == "string" then m.form else nil,
		rarity = m.rarity or 1,
		variant = if type(m.variant) == "number" and m.variant ~= 0 then m.variant else nil,
		name = if type(m.name) == "string" and m.name ~= "" then m.name else nil,
		gen = tonumber(m.gen) or 0,
		grades = Genetics.Grades(m.genes),
	}
end

function Pedigree.Build(a, b)
	local pa = if type(a.ped) == "table" then a.ped else {}
	local pb = if type(b.ped) == "table" then b.ped else {}
	return {
		a = Pedigree.Snap(a),
		b = Pedigree.Snap(b),
		aa = copySnap(pa.a),
		ab = copySnap(pa.b),
		ba = copySnap(pb.a),
		bb = copySnap(pb.b),
	}
end

function Pedigree.Copy(ped)
	if type(ped) ~= "table" then
		return nil
	end
	local out, any = {}, false
	for _, slot in SLOTS do
		out[slot] = copySnap(ped[slot])
		any = any or out[slot] ~= nil
	end
	return if any then out else nil
end

function Pedigree.Name(snap): string
	if type(snap.name) == "string" and snap.name ~= "" then
		return snap.name
	end
	local entry = snap.form and Config.Species.FormById[snap.form]
	if entry then
		return entry.form.name
	end
	local line = Config.Species.ById[snap.line]
	return if line then line.name else tostring(snap.line)
end

function Pedigree.ParentNames(ped): (string?, string?)
	if type(ped) ~= "table" or not validSnap(ped.a) or not validSnap(ped.b) then
		return nil, nil
	end
	return Pedigree.Name(ped.a), Pedigree.Name(ped.b)
end

return Pedigree
