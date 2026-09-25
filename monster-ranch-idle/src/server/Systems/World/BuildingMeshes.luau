--[[
	World/BuildingMeshes: the Meshy models that dress the placeholder buildings (Dress.luau), by
	building id: a World.Hub id, or "barn" for every plot's barn. Each mesh is published from Studio
	and its texture uploaded (tools/blender/export_static.py has the steps). A building missing
	here keeps its placeholder boxes.
]]

return {
	barn = { mesh = "rbxassetid://108157146336421", texture = "rbxassetid://113359600899812" },
	eggShop = { mesh = "rbxassetid://139546502593659", texture = "rbxassetid://71407772597775" },
	feedStore = { mesh = "rbxassetid://128865333879706", texture = "rbxassetid://97678683897638" },
}
