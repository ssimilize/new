--[[
	Monster Contests (update 1.5 · Showtime): themed shows on each server, in the style of
	Dress to Impress. Every `CycleSeconds` (on the unix clock, so every server runs the same
	theme at the same time) a show runs:

	  entry   `EntrySeconds`: players enter one monster (dress it up in the Wardrobe; the
	          outfit is locked in when the runway starts)
	  runway  each entry walks for `RunwaySeconds`; everyone else rates it 1–5 stars
	  results `ResultsSeconds`: podium, ribbons and gems
	  idle    until the next show

	Score = VoteWeight × average stars + (1 − VoteWeight) × judge score, or the judge score
	alone when nobody voted (quiet servers still get a show). The judge rewards accessories
	whose tags fit the theme (`JudgeScore`). Ties go to more votes, then the earlier entry.
]]

local Accessories = require(script.Parent.Accessories)

local Contests = {}

Contests.Unlock = "contests"
Contests.CycleSeconds = 10 * 60
Contests.EntrySeconds = 90
Contests.RunwaySeconds = 8
Contests.ResultsSeconds = 25
Contests.MaxEntries = 12
Contests.VoteWeight = 0.7
Contests.VoteRibbon = 1 -- ribbons per entry voted on …
Contests.VoteRibbonMax = 5 -- … up to this many per show

Contests.Judge = { base = 2, perMatch = 0.75, perWorn = 0.25, max = 5 }

-- Paid when the results show (Config.Rewards items). `entered` goes to everyone else who
-- took part.
Contests.Prizes = {
	[1] = { { kind = "ribbons", amount = 30 }, { kind = "gems", amount = 15 } },
	[2] = { { kind = "ribbons", amount = 20 }, { kind = "gems", amount = 10 } },
	[3] = { { kind = "ribbons", amount = 12 }, { kind = "gems", amount = 5 } },
	entered = { { kind = "ribbons", amount = 5 } },
}

Contests.Themes = {
	{
		id = "royal_ball",
		name = "Royal Ball",
		desc = "Crowns, capes and your fanciest pose.",
		tags = { "royal", "fancy" },
		color = "#8B2E8F",
	},
	{
		id = "spooky_night",
		name = "Spooky Night",
		desc = "Horns, wings and a little bit of fright.",
		tags = { "spooky" },
		color = "#3A2D55",
	},
	{ id = "beach_day", name = "Beach Day", desc = "Sun hats, shades and surf's up!", tags = { "beach" }, color = "#3FB6D9" },
	{
		id = "garden_party",
		name = "Garden Party",
		desc = "Flowers, leaves and fairy wings.",
		tags = { "nature", "cute" },
		color = "#43B649",
	},
	{
		id = "space_explorers",
		name = "Space Explorers",
		desc = "Helmets, jetpacks and starry style.",
		tags = { "space" },
		color = "#2E3A78",
	},
	{
		id = "sweet_treats",
		name = "Sweet Treats",
		desc = "As cute and sugary as a cupcake.",
		tags = { "sweet", "cute" },
		color = "#FF7AC8",
	},
	{
		id = "superheroes",
		name = "Superheroes",
		desc = "Masks, capes and medals. Save the day!",
		tags = { "hero", "sporty" },
		color = "#E5484D",
	},
	{
		id = "winter_wonderland",
		name = "Winter Wonderland",
		desc = "Scarves, beanies and jingle bells.",
		tags = { "winter" },
		color = "#7CC7FF",
	},
	{ id = "silly_hats", name = "Silly Hat Day", desc = "The sillier the better.", tags = { "silly" }, color = "#F2A93B" },
	{ id = "dapper_gents", name = "Dapper Day", desc = "Top hats, monocles and a fine mustache.", tags = { "fancy" }, color = "#5A3A1E" },
}

Contests.ThemeById = {}
for _, theme in Contests.Themes do
	Contests.ThemeById[theme.id] = theme
end

-- The show number and its phase times at `now`.
function Contests.Show(now: number)
	local show = math.floor(now / Contests.CycleSeconds)
	local startsAt = show * Contests.CycleSeconds
	return {
		show = show,
		startsAt = startsAt,
		entryEndsAt = startsAt + Contests.EntrySeconds,
		nextAt = startsAt + Contests.CycleSeconds,
	}
end

-- The theme of show `show` (a fixed shuffle so themes don't repeat back to back).
function Contests.ThemeFor(show: number)
	local n = #Contests.Themes
	return Contests.Themes[(show * 7 + 3) % n + 1]
end

-- Judge score (0..Judge.max) of an outfit { [slot] = accessoryId } for a theme.
function Contests.JudgeScore(acc, theme): number
	local J = Contests.Judge
	local score = J.base
	for _, id in (if type(acc) == "table" then acc else {}) do
		local def = Accessories.Resolve(id) -- catalogue items and Workshop designs (3.0)
		if def then
			score += J.perWorn
			for _, tag in def.tags do
				if table.find(theme.tags, tag) then
					score += J.perMatch
					break
				end
			end
		end
	end
	return math.min(J.max, score)
end

return Contests
