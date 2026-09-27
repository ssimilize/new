--[[
	Bug Catching Meadow (update 3.13 · Wild things). A wildflower meadow west of the Market Square
	(Config.World.BugMeadow, built on the client from Parts by Controllers/BugMeadow) with a
	"Catch bugs" signpost that opens the Bugs screen. From Ranch Level 17 (Unlocks "bug_meadow").

	Swings: FreeSwings a UTC day (spent at Bugs.Start). There is no other way to swing.

	The net minigame (Logic/Bugs): a bug crosses the field from left to right along a path seeded by
	the server; the net hangs in the middle (NetCenter ± NetHalf of the field). Tap Swing once while
	the bug is inside the net. The client sends only the swing time; the server replays the path
	(Grace seconds of slack either side of the window, the wall clock must agree within ClockGrace,
	the swing must be sent within the path's time + LateSeconds, swing ids are one-shot).

	Which bug: a seeded roll over Rarities[].weight (the honey lure uses Rarities[].lure), then a
	bug of that rarity that is out right now: `season` bugs only in that season (Logic/Seasons.At),
	`night` bugs only in the Weather night phase. Rarer bugs fly faster and dart more (twist), so
	their window is narrower. The client never learns which bug it is until it is caught.

	Honey lure: LureHoney honey (Apiary:SpendAnyHoney; hidden without the Apiary) makes the next
	LureSwings swings roll with the lure weights.

	Bug: { id, name, rarity (1-4), color, coins (seconds of ranch income one bug sells for),
	season?, night? }. Rarity: { name, weight, lure, duration = { min, max } (seconds to cross),
	twist = { min, max } (0..0.9: how hard it darts) }.
]]

local Bugs = {}

Bugs.Unlock = "bug_meadow"
Bugs.Source = "bugs" -- Rewards source (reward card "Rewards · Bugs")

Bugs.FreeSwings = 12 -- a UTC day
Bugs.LureHoney = 3
Bugs.LureSwings = 5
Bugs.MaxJar = 9999

-- The minigame. Positions run 0 (left edge) .. 1 (right edge) of the field.
Bugs.Enter = -0.1 -- where the bug starts (off the field)
Bugs.Exit = 1.1 -- and where it leaves
Bugs.NetCenter = 0.5
Bugs.NetHalf = 0.09
Bugs.Delay = { 0.6, 1.4 } -- seconds before the bug flies in
Bugs.Freq = { 1.5, 3 } -- darts over one crossing
Bugs.Bob = { 0.08, 0.22 } -- up-and-down wobble (looks only)
Bugs.Grace = 0.06 -- seconds of slack either side of the net window
Bugs.ClockGrace = 1 -- network slack when checking the swing against the server clock
Bugs.LateSeconds = 20 -- a swing must be sent within the path's time + this
Bugs.MaxT = 30 -- the largest swing time the server accepts
Bugs.SampleStep = 0.005 -- seconds between samples when finding the window

Bugs.Rarities = {
	{ name = "Common", weight = 60, lure = 36, duration = { 3.2, 3.8 }, twist = { 0, 0.25 } },
	{ name = "Uncommon", weight = 27, lure = 34, duration = { 2.6, 3.1 }, twist = { 0.2, 0.5 } },
	{ name = "Rare", weight = 10, lure = 22, duration = { 2, 2.5 }, twist = { 0.4, 0.7 } },
	{ name = "Legendary", weight = 3, lure = 8, duration = { 1.5, 1.9 }, twist = { 0.6, 0.85 } },
}

-- Never reorder: ids are saved.
Bugs.List = {
	{ id = "ladybug", name = "Ladybug", rarity = 1, color = "#E5484D", coins = 45 },
	{ id = "cabbage_white", name = "Cabbage White", rarity = 1, color = "#F4F1E6", coins = 45 },
	{ id = "grasshopper", name = "Meadow Grasshopper", rarity = 1, color = "#7FB24A", coins = 45 },
	{ id = "bumblebee", name = "Bumblebee", rarity = 1, color = "#F2C230", coins = 45 },
	{ id = "pill_beetle", name = "Pill Beetle", rarity = 1, color = "#8A8494", coins = 45 },
	{ id = "damselfly", name = "Blue Damselfly", rarity = 2, color = "#4FA3E0", coins = 120 },
	{ id = "swallowtail", name = "Swallowtail", rarity = 2, color = "#F5D547", coins = 120 },
	{ id = "lacewing", name = "Green Lacewing", rarity = 2, color = "#9ED86B", coins = 120 },
	{ id = "dragonfly", name = "Emerald Dragonfly", rarity = 2, color = "#2FAF7F", coins = 120 },
	{ id = "stag_beetle", name = "Stag Beetle", rarity = 3, color = "#9A5E34", coins = 300 },
	{ id = "monarch", name = "Monarch Butterfly", rarity = 3, color = "#F28C28", coins = 300 },
	{ id = "jewel_beetle", name = "Jewel Beetle", rarity = 3, color = "#36C2B4", coins = 300 },
	{ id = "rainbow_scarab", name = "Rainbow Scarab", rarity = 4, color = "#C58CFF", coins = 900 },
	-- One per season (Logic/Seasons ids).
	{ id = "blossom_moth", name = "Blossom Moth", rarity = 2, color = "#F7A8C8", coins = 150, season = "spring" },
	{ id = "sun_cicada", name = "Sun Cicada", rarity = 2, color = "#E8B04A", coins = 150, season = "summer" },
	{ id = "maple_mantis", name = "Maple Mantis", rarity = 3, color = "#D9652B", coins = 360, season = "autumn" },
	{ id = "frost_moth", name = "Frost Moth", rarity = 3, color = "#BFE9FF", coins = 360, season = "winter" },
	-- Night bugs (the Weather night phase).
	{ id = "firefly", name = "Firefly", rarity = 2, color = "#F6F07A", coins = 150, night = true },
	{ id = "luna_moth", name = "Luna Moth", rarity = 3, color = "#B8F2C8", coins = 360, night = true },
	{ id = "star_beetle", name = "Starlight Beetle", rarity = 4, color = "#8FA8FF", coins = 1000, night = true },
}

Bugs.ById = {}
Bugs.Ids = {}
for i, b in Bugs.List do
	assert(Bugs.Rarities[b.rarity], "[Config.Bugs] unknown rarity for " .. b.id)
	assert(Bugs.ById[b.id] == nil, "[Config.Bugs] duplicate bug " .. b.id)
	b.order = i
	Bugs.ById[b.id] = b
	table.insert(Bugs.Ids, b.id)
end
-- Every rarity keeps a bug that is always out, so a roll never comes up empty.
for r = 1, #Bugs.Rarities do
	local always = false
	for _, b in Bugs.List do
		if b.rarity == r and b.season == nil and not b.night then
			always = true
		end
	end
	assert(always, "[Config.Bugs] no always-out bug of rarity " .. r)
end

return Bugs
