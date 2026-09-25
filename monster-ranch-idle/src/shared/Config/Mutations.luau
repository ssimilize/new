--[[
	Mutations: weather-applied value multipliers. A monster holds at most `MaxPerMonster`.
	Some pairs merge into a combo that takes a single slot.
]]

local Mutations = {}

Mutations.MaxPerMonster = 2

Mutations.List = {
	{ id = "soaked", name = "Soaked", mult = 1.5, color = "#4FB6F2", statPct = 0.02 },
	{ id = "scorched", name = "Scorched", mult = 1.5, color = "#F0663A", statPct = 0.02 },
	{ id = "charged", name = "Charged", mult = 2, color = "#F5C630", statPct = 0.02 },
	{ id = "frosted", name = "Frosted", mult = 2, color = "#BFE9FF", statPct = 0.02 },
	{ id = "starstruck", name = "Starstruck", mult = 3, color = "#FFD447", statPct = 0.03 },
	{ id = "shadow", name = "Shadow", mult = 4, color = "#3A2D55", statPct = 0.03 },
	{ id = "prismatic", name = "Prismatic", mult = 8, color = "#FF7AC8", statPct = 0.05 },
	{ id = "glow", name = "Glow", mult = 3, color = "#FFB547", statPct = 0.03 }, -- Lantern Night (1.2)
	{ id = "blossom", name = "Blossom", mult = 3, color = "#FF9EC7", statPct = 0.03 }, -- Pollen Storm (1.4)
	-- Combos (never rolled directly)
	{ id = "frozen", name = "Frozen", mult = 3.5, color = "#9FE3FF", statPct = 0.04, combo = { "soaked", "frosted" } },
	{ id = "plasma", name = "Plasma", mult = 4, color = "#C06BFF", statPct = 0.04, combo = { "scorched", "charged" } },
	-- Update 1.1 · Coral Depths
	{ id = "pearl", name = "Pearl", mult = 5, color = "#F3EEE2", statPct = 0.05, combo = { "soaked", "starstruck" } },
}

Mutations.ById = {}
Mutations.Combos = {} -- "a+b" (sorted) -> combo id
for _, m in Mutations.List do
	Mutations.ById[m.id] = m
	if m.combo then
		local pair = table.clone(m.combo)
		table.sort(pair)
		Mutations.Combos[pair[1] .. "+" .. pair[2]] = m.id
	end
end

return Mutations
