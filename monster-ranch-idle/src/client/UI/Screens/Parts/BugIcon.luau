--[[
	BugIcon (update 3.13 · Bug Catching Meadow): a bug drawn from UI shapes, no image upload. Two
	wings, a round body in the bug's colour (Config.Bugs) with a dark stripe, a head and two
	feelers. `silhouette` draws it flat and dark (not caught yet, or a bug still in flight).

	  BugIcon.new(bugId?, size, silhouette?) -> Frame   (size × size, the bug faces up)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local UI = script.Parent.Parent.Parent
local Create = require(UI.Create)

local New = Create.New

local BugIcon = {}

local SILHOUETTE = Color3.fromHex("#3B3350")
local WING = Color3.fromHex("#EAF6FF")

local function darker(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

function BugIcon.new(bugId: string?, size: number, silhouette: boolean?): Frame
	local def = if bugId then Config.Bugs.ById[bugId] else nil
	local base = if silhouette or not def then SILHOUETTE else Color3.fromHex(def.color)
	local frame = New("Frame", {
		Name = "Bug",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
	})
	for i, side in { -1, 1 } do
		New("Frame", {
			Name = "Wing" .. i,
			BackgroundColor3 = if silhouette then darker(SILHOUETTE, 0.8) else WING,
			BackgroundTransparency = if silhouette then 0 else 0.25,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + side * 0.22, 0.45),
			Size = UDim2.fromScale(0.36, 0.26),
			Rotation = side * -30,
			Parent = frame,
		}, { Create.Round() })
	end
	New("Frame", {
		Name = "Body",
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromScale(0.34, 0.5),
		Parent = frame,
	}, {
		Create.Round(),
		Create.Stroke(math.max(1, size / 32), darker(base, 0.55)),
		New("Frame", {
			Name = "Stripe",
			BackgroundColor3 = darker(base, 0.6),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55),
			Size = UDim2.fromScale(0.12, 0.8),
		}),
	})
	New("Frame", {
		Name = "Head",
		BackgroundColor3 = darker(base, 0.5),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.28),
		Size = UDim2.fromScale(0.2, 0.2),
		Parent = frame,
	}, { Create.Round() })
	for i, side in { -1, 1 } do
		New("Frame", {
			Name = "Feeler" .. i,
			BackgroundColor3 = darker(base, 0.45),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5 + side * 0.06, 0.22),
			Size = UDim2.fromScale(0.03, 0.16),
			Rotation = side * 25,
			Parent = frame,
		})
	end
	return frame
end

return BugIcon
