--[[
	Editions (glow-up W): numbered limited editions. Rules in Logic/Editions, the server side in
	Systems/Editions.

	Every event species line (Config.Species lines tagged `event`) is a limited line: a monster of
	that line that is hatched or granted (Sources) gets a serial number, unique across all servers,
	"#37 of 500". Numbers come from one atomic counter per edition (Services.Editions, or the
	profile DataStore key "Edition_<id>" until that adapter exists). Bred, traded and bought
	monsters are never numbered at arrival: a number is minted once and travels with its record.

	When an edition is full the line stops being limited: later monsters of it are granted as
	ordinary, unnumbered monsters. Every limited line is earnable for free (event eggs are bought
	with event tokens earned by playing), never only through Robux.

	Record fields: ltd = edition id (set at creation), ltdOf = the edition size, ltdNo = the number
	(nil while the store could not be reached; numbered later, on any server).
]]

local Species = require(script.Parent.Species)

local Editions = {}

Editions.DefaultSize = 500
Editions.Sizes = {} -- [lineId] = edition size, overriding DefaultSize
Editions.Sources = { hatch = true, reward = true } -- Monsters:Create sources that mint a number

Editions.Attempts = 3 -- store tries per numbering pass
Editions.RetrySeconds = 60 -- how often pending monsters of players on this server are tried again
Editions.Color = "#B07CFF" -- chip colour

Editions.List = {}
Editions.ById = {}
Editions.ByLine = {}
for _, line in Species.Lines do
	if type(line) == "table" and line.event and line.id then
		local edition = { id = line.id, line = line.id, event = line.event, size = Editions.Sizes[line.id] or Editions.DefaultSize }
		table.insert(Editions.List, edition)
		Editions.ById[edition.id] = edition
		Editions.ByLine[line.id] = edition
	end
end

return Editions
