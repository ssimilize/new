--[[
	config_dump: prints the game content the UI art tools need as JSON (forms, decor, pen themes,
	accessories, eggs, food), read straight from src/shared/Config so the tools never drift from
	the configs after a merge.

		lune run tools/ui/config_dump.luau
]]

local serde = require("@lune/serde")

local Species = require("../../src/shared/Config/Species")
local Decor = require("../../src/shared/Config/Decor")
local Accessories = require("../../src/shared/Config/Accessories")
local Eggs = require("../../src/shared/Config/Eggs")
local Food = require("../../src/shared/Config/Food")

local forms = {}
for _, line in Species.Lines do
	for stage, entry in line.forms do
		local list = if entry.id then { entry } else entry
		for _, f in list do
			table.insert(forms, { id = f.id, name = f.name, line = line.id, stage = stage, archetype = line.archetype })
		end
	end
end

local decor = {}
for _, d in Decor.List do
	table.insert(decor, { id = d.id, name = d.name, color = d.color, shape = d.shape or "block", set = d.set, event = d.event })
end

local themes = {}
for _, t in Decor.PenThemes do
	table.insert(themes, { id = t.id, name = t.name, fence = t.fence, ground = t.ground })
end

local accessories = {}
for _, a in Accessories.List do
	table.insert(accessories, { id = a.id, name = a.name, slot = a.slot, shape = a.shape, color = a.color, color2 = a.color2 })
end

local eggs = {}
for _, e in Eggs.List do
	table.insert(eggs, { id = e.id, name = e.name, shell = e.colors.shell, spots = e.colors.spots, pattern = e.pattern })
end

local food = {}
for _, f in Food.List do
	table.insert(food, { id = f.id, name = f.name, color = f.color })
end

print(serde.encode("json", {
	forms = forms,
	decor = decor,
	themes = themes,
	accessories = accessories,
	eggs = eggs,
	food = food,
}))
