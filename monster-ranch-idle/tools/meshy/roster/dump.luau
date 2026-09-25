--[[
	Dumps the monster roster (every form of every line) as JSON for the art pipeline:
	  lune run tools/meshy/roster/dump > tools/meshy/roster/roster.json
]]
local Loader = require("../../../tests/runtime/Loader")
local serde = require("@lune/serde")
local process = require("@lune/process")

local root = string.gsub(process.cwd, "[/\]$", "")
Loader.init(root)
local Config = Loader.get("Shared.Config")

local elements = {}
for _, e in Config.Elements.List or Config.Elements do
	if type(e) == "table" and e.id then
		elements[e.id] = { name = e.name, color = e.color, light = e.light, accent = e.accent }
	end
end

local out = { elements = elements, lines = {} }
for order, line in Config.Species.Lines do
	local forms = {}
	for stage, s in line.forms do
		local list = if s.id then { s } else s
		for _, f in list do
			table.insert(forms, { id = f.id, name = f.name, stage = stage, diet = f.diet })
		end
	end
	table.insert(out.lines, {
		order = order,
		id = line.id,
		elements = line.elements,
		archetype = line.archetype,
		pools = line.pools,
		raid = line.raid,
		added = line.added,
		weight = line.weight,
		forms = forms,
	})
end
print(serde.encode("json", out, true))
