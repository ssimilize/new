-- Eight elements: two rock-paper-scissors triangles and a pair.
-- Triangle A: ember > sprout > tide > ember.   Triangle B: spark > gloom > stone > spark.
-- Pair C (update 2.0): light and void each beat the other and are neutral to the rest,
-- so a Light-vs-Void fight is a race where both sides hit hard.
--
-- `glyph` (R2-A11Y): drawn next to the colour on every element chip in colour-blind mode.
-- Every glyph is checked against FredokaOne's blank-glyph list in tests/specs/Glyphs.spec.luau.
-- `cbColor` (stone, light; R2-A11Y): used instead of `color` in colour-blind mode only -
-- simulated protanopia/deuteranopia (Vienot/Brettel matrices) found stone's tan reading almost
-- identical to sprout's green, and light's gold almost identical to spark's gold.
local Elements = {}

Elements.List = {
	{
		id = "ember",
		name = "Ember",
		glyph = "☼",
		color = "#F57A45",
		light = "#FFD2AE",
		accent = "#FFB547",
		beats = "sprout",
		triangle = "A",
	},
	{
		id = "tide",
		name = "Tide",
		glyph = "●",
		color = "#4AA6F0",
		light = "#D2EDFF",
		accent = "#9FD7FF",
		beats = "ember",
		triangle = "A",
	},
	{
		id = "sprout",
		name = "Sprout",
		glyph = "❀",
		color = "#62BF55",
		light = "#E0F6CF",
		accent = "#8EE07A",
		beats = "tide",
		triangle = "A",
	},
	{
		id = "spark",
		name = "Spark",
		glyph = "★",
		color = "#F6CD3A",
		light = "#FFF4C2",
		accent = "#FFE680",
		beats = "gloom",
		triangle = "B",
	},
	{
		id = "gloom",
		name = "Gloom",
		glyph = "◇",
		color = "#9168D0",
		light = "#E4D6F8",
		accent = "#C9A8FF",
		beats = "stone",
		triangle = "B",
	},
	{
		id = "stone",
		name = "Stone",
		glyph = "▲",
		color = "#A68B70",
		cbColor = "#B8A47A",
		light = "#E6D9C8",
		accent = "#EDE3D3",
		beats = "spark",
		triangle = "B",
	},
	{
		id = "light",
		name = "Light",
		glyph = "◎",
		color = "#F2C94C",
		cbColor = "#FFE9C2",
		light = "#FFF6D6",
		accent = "#FFFBEA",
		beats = "void",
		triangle = "C",
		added = "2.0",
	},
	{
		id = "void",
		name = "Void",
		glyph = "◆",
		color = "#3B3470",
		light = "#DAD5F2",
		accent = "#5CE1E6",
		beats = "light",
		triangle = "C",
		added = "2.0",
	},
}

Elements.ById = {}
for _, e in Elements.List do
	Elements.ById[e.id] = e
end

Elements.Advantage = 1.5
Elements.Disadvantage = 0.7

-- Damage multiplier for one attacking element against one defending element.
function Elements.Multiplier(attacker: string, defender: string): number
	local a = Elements.ById[attacker]
	local d = Elements.ById[defender]
	if not a or not d then
		return 1
	end
	if a.beats == defender then
		return Elements.Advantage
	end
	if d.beats == attacker then
		return Elements.Disadvantage
	end
	return 1
end

-- Hybrids have two elements. An attacking hybrid uses its best element; a defending
-- hybrid suffers its worst matchup. Both rules mean: take the highest pair multiplier.
function Elements.MultiplierMulti(attackers: { string }, defenders: { string }): number
	local best = 0
	for _, a in attackers do
		for _, d in defenders do
			best = math.max(best, Elements.Multiplier(a, d))
		end
	end
	return best
end

return Elements
