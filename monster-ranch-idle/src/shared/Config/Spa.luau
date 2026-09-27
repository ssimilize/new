--[[
	Hot Springs & Spa (update 3.13 · Wild things): steaming pools on the ranch's west strip. A
	Teen or Adult from the barn soaks in one pool (busy tag "spa") for the soak's time, then the
	player collects it and the monster carries the soak's buff for BuffHours. Rules in Logic/Spa,
	the server in Systems/Spa, the pools on the plot in Controllers/Spa.

	  Pools     pools 1 and 2 open with Unlock (Ranch Level 29), pool 3 with PoolUnlocks[3] (45).
	  Salts     each soak is paid on the spot with a bath salt made of honey (any kind, through
	            Apiary:SpendAnyHoney) and food of one flavour (Currency food.<flavour>). Without
	            the Apiary no soak is offered.
	  Soaks     warm     30 min   +GrowthPct growth meals from feeding (growing monsters only)
	            mineral  1 h      +OutputPct Job Board output and Apiary honey for that monster
	            herbal   2 h      Mood to the max and BondPoints bond points, when collected
	  Buff      from the collect for BuffHours; one buff per monster, a new soak replaces it.
]]

local Spa = {}

Spa.Unlock = "spa"
Spa.PoolUnlocks = { "spa", "spa", "spa_pool_3" } -- pool i opens at PoolUnlocks[i]
Spa.MaxPools = #Spa.PoolUnlocks
Spa.MinStage = 2 -- Teens and Adults
Spa.BuffHours = 4
Spa.FinishNotify = true

Spa.Soaks = {
	{
		id = "warm",
		name = "Warm Soak",
		desc = "+20% growth from meals for 4 hours",
		minutes = 30,
		honey = 2,
		food = "spicy",
		foodAmount = 5,
		growthPct = 0.20,
		growing = true, -- only a monster that still grows can take it
		color = "#F28C5B",
	},
	{
		id = "mineral",
		name = "Mineral Soak",
		desc = "+15% Job Board and Apiary output for 4 hours",
		minutes = 60,
		honey = 2,
		food = "savory",
		foodAmount = 5,
		outputPct = 0.15,
		color = "#7FB8C9",
	},
	{
		id = "herbal",
		name = "Herbal Soak",
		desc = "Full Mood and 3 bond points",
		minutes = 120,
		honey = 3,
		food = "sweet",
		foodAmount = 5,
		bondPoints = 3,
		color = "#8BC98B",
	},
}

-- The spa on the plot (plot-local, x toward the gate): a wooden deck with three round pools and
-- a small roof, centred on `offset`; keep-out {-66, 23, 7, 8} in Config.Decor. `size` is the
-- footprint the plot-layout test checks.
Spa.World = { offset = { -66, 0, 23 }, size = { 14, 16 }, promptDistance = 12 }

Spa.ById = {}
Spa.Ids = {}
for i, soak in Spa.Soaks do
	soak.order = i
	Spa.ById[soak.id] = soak
	table.insert(Spa.Ids, soak.id)
end

return Spa
