-- Food flavours. The majority flavour a Teen eats decides its adult branch.
local Food = {}

Food.List = {
	{ id = "sweet", name = "Sweet Berries", color = "#EF6FA8" },
	{ id = "spicy", name = "Fire Peppers", color = "#E5484D" },
	{ id = "savory", name = "Hearty Roots", color = "#A0703D" },
	{ id = "sour", name = "Zing Limes", color = "#C3D93B" },
}

Food.ById = {}
Food.Ids = {}
for _, f in Food.List do
	Food.ById[f.id] = f
	table.insert(Food.Ids, f.id)
end

return Food
