-- Eight elements: two rock-paper-scissors triangles and a pair.
-- Triangle A: ember > sprout > tide > ember.   Triangle B: spark > gloom > stone > spark.
-- Pair C (update 2.0): light and void each beat the other and are neutral to the rest,
-- so a Light-vs-Void fight is a race where both sides hit hard.
local Elements = {}

Elements.List = {
	{ id = "ember", name = "Ember", color = "#F57A45", light = "#FFD2AE", accent = "#FFB547", beats = "sprout", triangle = "A" },
	{ id = "tide", name = "Tide", color = "#4AA6F0", light = "#D2EDFF", accent = "#9FD7FF", beats = "ember", triangle = "A" },
	{ id = "sprout", name = "Sprout", color = "#62BF55", light = "#E0F6CF", accent = "#8EE07A", beats = "tide", triangle = "A" },
	{ id = "spark", name = "Spark", color = "#F6CD3A", light = "#FFF4C2", accent = "#FFE680", beats = "gloom", triangle = "B" },
	{ id = "gloom", name = "Gloom", color = "#9168D0", light = "#E4D6F8", accent = "#C9A8FF", beats = "stone", triangle = "B" },
	{ id = "stone", name = "Stone", color = "#A68B70", light = "#E6D9C8", accent = "#EDE3D3", beats = "spark", triangle = "B" },
	{
		id = "light",
		name = "Light",
		color = "#F2C94C",
		light = "#FFF6D6",
		accent = "#FFFBEA",
		beats = "void",
		triangle = "C",
		added = "2.0",
	},
	{
		id = "void",
		name = "Void",
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
