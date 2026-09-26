--[[
	Shine: a slow diagonal glint that sweeps across a rarity-framed tile (monster cards, item
	tiles) for Epic and better. A white overlay whose UIGradient transparency leaves one soft band
	visible; the band's Offset is tweened corner to corner on a loop with a rest between passes.
	Nothing is added in low graphics (Anim.enabled off), below Epic, or twice on the same tile.

		Shine.attach(card, appearance.rarity, Theme.Radius.Card)   -- -> the overlay Frame or nil
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Shared.Config)
local Create = require(script.Parent.Parent.Create)
local Anim = require(script.Parent.Parent.Anim)

local Shine = {}

Shine.MinRarity = 4 -- Epic
for i, r in Config.Rarities.List do
	if r.name == "Epic" then
		Shine.MinRarity = i
	end
end

local SWEEP = TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 2.6)

function Shine.attach(tile: GuiObject, rarity: number?, radius: number?): Frame?
	if not Anim.enabled or (rarity or 0) < Shine.MinRarity or tile:FindFirstChild("Shine") then
		return nil
	end
	local overlay = Create.New("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = tile.ZIndex + 8,
		Active = false,
		Parent = tile,
	}, { Create.Corner(radius or 12) })
	local g = Instance.new("UIGradient")
	g.Rotation = 35
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Offset = Vector2.new(-1, 0)
	g.Parent = overlay
	TweenService:Create(g, SWEEP, { Offset = Vector2.new(1, 0) }):Play()
	return overlay
end

return Shine
