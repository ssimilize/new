--[[
	Apiary & Honey (update 3.12 · Honey & stars): beehives on the ranch's north strip. Each open
	hive is tended by one Adult; it makes honey on the server clock (online and offline) in the
	kind of the season it was made in. Rules in Logic/Apiary, the server in Systems/Apiary.

	  Hives     hive 1 opens with Unlock (Ranch Level 14), hives 2 and 3 with HiveUnlocks (27, 42).
	  Rate      honey an hour = BasePerHour × √W × (SproutBonus if the keeper is a Sprout monster),
	            W = SPD ÷ Config.Jobs.RefBase.spd (the Job Board's power: about 1 for an average
	            worker, 0.5 for a Common Teen, 35 for a maxed Mythic). √W like every Job Board job,
	            so a maxed Mythic makes about 35 an hour, not 210.
	  Storage   a hive holds CapHours of its own rate (+ Observatory:Perk "hive_hours" when the
	            Observatory exists), then stops until collected.
	  Kinds     Kinds[i].season: spring blossom, summer clover, autumn heather, winter frost
	            (Logic/Seasons.At); a stretch across the weekly turnover pays both kinds.
	  Royal     each hive collect with at least 1 honey rolls RoyalJelly.chance (seeded per player
	            and collect number) for 1 Royal Jelly, kept in the same store.
	  Selling   SellSeconds[kind] of ranch income a unit (Rewards coins with `seconds`): honey 45 s,
	            Royal Jelly 20 minutes.
]]

local Apiary = {}

Apiary.Unlock = "apiary"
Apiary.HiveUnlocks = { "apiary", "apiary_hive_2", "apiary_hive_3" } -- hive i opens at HiveUnlocks[i]
Apiary.MaxHives = #Apiary.HiveUnlocks
Apiary.MinStage = 3 -- Adults only

Apiary.BasePerHour = 6
Apiary.SproutBonus = 1.25
Apiary.SproutElement = "sprout"
Apiary.CapHours = 8
Apiary.StoreCap = 9999 -- per kind
Apiary.FullNotify = true

Apiary.Kinds = {
	{ id = "blossom", name = "Blossom Honey", season = "spring", color = "#F4A6C6" },
	{ id = "clover", name = "Clover Honey", season = "summer", color = "#F2C230" },
	{ id = "heather", name = "Heather Honey", season = "autumn", color = "#C7743A" },
	{ id = "frost", name = "Frost Honey", season = "winter", color = "#BFE3F2" },
}
Apiary.RoyalJelly = { id = "royal_jelly", name = "Royal Jelly", chance = 0.02, color = "#FFF4D6" }

Apiary.SellSeconds = { blossom = 45, clover = 45, heather = 45, frost = 45, royal_jelly = 1200 }

-- The apiary on the plot (plot-local, x toward the gate): three hive stands in a row, centred on
-- `offset`; keep-out {-8, -47, 12, 6} in Config.Decor. `size` is the footprint the plot-layout
-- test checks (Config.World pieces must not overlap it).
Apiary.World = { offset = { -8, 0, -47 }, size = { 22, 10 }, spacing = 7, promptDistance = 12 }

Apiary.ById = {}
Apiary.Ids = {} -- the four honey kinds, in order
Apiary.AllIds = {} -- the honey kinds and Royal Jelly (what the store holds)
Apiary.BySeason = {}
for i, kind in Apiary.Kinds do
	kind.order = i
	Apiary.ById[kind.id] = kind
	Apiary.BySeason[kind.season] = kind
	table.insert(Apiary.Ids, kind.id)
	table.insert(Apiary.AllIds, kind.id)
end
Apiary.RoyalJelly.order = #Apiary.Kinds + 1
Apiary.ById[Apiary.RoyalJelly.id] = Apiary.RoyalJelly
table.insert(Apiary.AllIds, Apiary.RoyalJelly.id)

return Apiary
