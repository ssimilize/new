--[[
	DishIcon (update 3.10): a Kitchen dish drawn from UI shapes, no image upload. A white plate
	with a rim, the food shape in the recipe's colour (Config.Kitchen recipe.icon) shaded with a
	UIGradient, and a topping.

	  DishIcon.new(recipe, size: number) -> Frame   -- square, `size` px
	Shapes: "round" (pie, tart), "wide" (roast, supper, feast), "bowl" (stew), "stack" (rolls, cake).
]]

local UI = script.Parent.Parent.Parent
local Create = require(UI.Create)

local New = Create.New

local DishIcon = {}

local PLATE = Color3.fromRGB(250, 248, 240)
local RIM = Color3.fromRGB(205, 196, 176)

local function hex(s: string?, fallback: Color3): Color3
	if type(s) ~= "string" then
		return fallback
	end
	local ok, c = pcall(Color3.fromHex, s)
	return if ok then c else fallback
end

local function shade(): UIGradient
	return New("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
	})
end

local function blob(parent: Instance, color: Color3, pos: UDim2, size: UDim2, corner: UDim?, z: number)
	return New("Frame", {
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = size,
		ZIndex = z,
		Parent = parent,
	}, { Create.Corner(corner or UDim.new(0.5, 0)), shade() })
end

function DishIcon.new(recipe, size: number): Frame
	local icon = recipe and recipe.icon or {}
	local root = New("Frame", {
		Name = "DishIcon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
	})
	-- The plate: a rim and a slightly smaller inner circle.
	New("Frame", {
		Name = "Plate",
		BackgroundColor3 = RIM,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromScale(0.96, 0.62),
		Parent = root,
	}, { Create.Corner(UDim.new(0.5, 0)) })
	New("Frame", {
		BackgroundColor3 = PLATE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromScale(0.84, 0.5),
		Parent = root,
	}, { Create.Corner(UDim.new(0.5, 0)) })
	local color = hex(icon.color, Color3.fromRGB(200, 140, 80))
	local top = hex(icon.top, Color3.fromRGB(240, 110, 160))
	local shape = icon.shape or "round"
	if shape == "wide" then
		blob(root, color, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.66, 0.32), UDim.new(0.4, 0), 2)
		blob(root, top, UDim2.fromScale(0.38, 0.42), UDim2.fromScale(0.16, 0.14), nil, 3)
		blob(root, top, UDim2.fromScale(0.6, 0.44), UDim2.fromScale(0.14, 0.12), nil, 3)
	elseif shape == "bowl" then
		blob(root, color, UDim2.fromScale(0.5, 0.52), UDim2.fromScale(0.6, 0.36), UDim.new(0.35, 0), 2)
		blob(root, top, UDim2.fromScale(0.5, 0.4), UDim2.fromScale(0.5, 0.14), nil, 3)
	elseif shape == "stack" then
		blob(root, color, UDim2.fromScale(0.36, 0.5), UDim2.fromScale(0.26, 0.3), UDim.new(0.3, 0), 2)
		blob(root, color, UDim2.fromScale(0.64, 0.5), UDim2.fromScale(0.26, 0.3), UDim.new(0.3, 0), 2)
		blob(root, top, UDim2.fromScale(0.36, 0.42), UDim2.fromScale(0.16, 0.1), nil, 3)
		blob(root, top, UDim2.fromScale(0.64, 0.42), UDim2.fromScale(0.16, 0.1), nil, 3)
	else
		blob(root, color, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.58, 0.4), nil, 2)
		blob(root, top, UDim2.fromScale(0.5, 0.46), UDim2.fromScale(0.42, 0.24), nil, 3)
	end
	return root
end

return DishIcon
