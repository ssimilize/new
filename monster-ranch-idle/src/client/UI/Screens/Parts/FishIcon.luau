--[[
	FishIcon (update 3.10 · Fishing Pond): a fish drawn from UI shapes, no image upload. A round
	body with a UIGradient in the fish's colour (Config.Fishing), a tail (a turned square), a fin
	and an eye. `silhouette` draws it flat and dark for fish not caught yet.

	  FishIcon.new(fishId, size, silhouette?) -> Frame   (size × size, the fish faces right)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local UI = script.Parent.Parent.Parent
local Create = require(UI.Create)

local New = Create.New

local FishIcon = {}

local SILHOUETTE = Color3.fromHex("#3B3350")

local function darker(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

function FishIcon.new(fishId: string, size: number, silhouette: boolean?): Frame
	local def = Config.Fishing.ById[fishId]
	local base = if silhouette then SILHOUETTE elseif def then Color3.fromHex(def.color) else Color3.fromHex("#9FB8C8")
	local frame = New("Frame", {
		Name = "Fish",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
	})
	local tail = New("Frame", {
		Name = "Tail",
		BackgroundColor3 = darker(base, 0.8),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.2, 0.5),
		Size = UDim2.fromScale(0.3, 0.3),
		Rotation = 45,
		Parent = frame,
	}, { Create.Corner(UDim.new(0.2, 0)) })
	local fin = New("Frame", {
		Name = "Fin",
		BackgroundColor3 = darker(base, 0.75),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromScale(0.24, 0.24),
		Rotation = 45,
		Parent = frame,
	}, { Create.Corner(UDim.new(0.25, 0)) })
	local body = New("Frame", {
		Name = "Body",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.56, 0.5),
		Size = UDim2.fromScale(0.66, 0.42),
		Parent = frame,
	}, {
		Create.Corner(UDim.new(0.5, 0)),
		New("UIGradient", {
			Color = ColorSequence.new(darker(base, 0.7), base),
			Rotation = -90,
		}),
	})
	New("UIStroke", {
		Color = Color3.fromHex("#2A2419"),
		Thickness = math.max(1, size / 32),
		Transparency = 0.35,
		Parent = body,
	})
	if not silhouette then
		local eye = New("Frame", {
			Name = "Eye",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.78, 0.42),
			Size = UDim2.fromScale(0.13, 0.13),
			Parent = frame,
		}, { Create.Corner(UDim.new(0.5, 0)) })
		New("Frame", {
			Name = "Pupil",
			BackgroundColor3 = Color3.fromHex("#2A2419"),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.6, 0.5),
			Size = UDim2.fromScale(0.5, 0.5),
			Parent = eye,
		}, { Create.Corner(UDim.new(0.5, 0)) })
	end
	tail.ZIndex, fin.ZIndex = 1, 1
	return frame
end

return FishIcon
