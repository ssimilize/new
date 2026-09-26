--[[
	EmoteWheel (glow-up L): a radial wheel of player emotes (outer ring, Config.Community.Emotes)
	and monster tricks (inner ring, Config.Community.Tricks). Opened by the Community controller
	(HUD Emotes button, G, D-pad down). Picking one plays it and closes the wheel; a tap outside,
	the centre ✕ or B closes it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Button = require(UI.Components.Button)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Community

local EmoteWheel = { Name = "EmoteWheel" }

local OUTER, INNER = 188, 92
local WHEEL = 520

local function glyph(text: string): TextLabel
	local label = Create.Text({
		Text = text,
		TextScaled = true,
		Size = UDim2.fromOffset(22, 22),
	})
	label:SetAttribute("Localize", false)
	return label
end

function EmoteWheel.Build(ctx)
	local root = New("Frame", {
		Name = "EmoteWheel",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	local function close()
		ctx.Router:Close("EmoteWheel")
	end
	New("TextButton", {
		Name = "Dim",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Size = UDim2.fromScale(1, 1),
		Selectable = false,
		Parent = root,
	}).Activated:Connect(close)

	local wheel = New("Frame", {
		Name = "Wheel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WHEEL, WHEEL),
		BackgroundColor3 = C.Panel or Color3.fromHex("#FFF7E3"),
		BackgroundTransparency = 0.15,
		Parent = root,
	}, { Create.Corner(WHEEL / 2), Create.Stroke(4) })
	New("Frame", {
		Name = "Inner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(INNER * 2 + 70, INNER * 2 + 70),
		BackgroundColor3 = C.Green,
		BackgroundTransparency = 0.7,
		Parent = wheel,
	}, { Create.Corner((INNER * 2 + 70) / 2) })

	local function place(gui: GuiObject, index: number, count: number, radius: number)
		local angle = -math.pi / 2 + (index - 1) * (2 * math.pi / count)
		gui.AnchorPoint = Vector2.new(0.5, 0.5)
		gui.Position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, math.sin(angle) * radius)
	end

	for i, emote in Cfg.Emotes do
		local b = Button.new({
			Name = "Emote_" .. emote.id,
			Text = emote.name,
			Color = C.Purple,
			Size = UDim2.fromOffset(118, 48),
			TextSize = Theme.TextSize.Small,
			Icon = glyph(emote.glyph),
			Parent = wheel,
			OnClick = function()
				close()
				ctx:GetController("Community").PlayEmote(emote.id)
			end,
		})
		place(b.Root, i, #Cfg.Emotes, OUTER)
	end
	for i, trick in Cfg.Tricks do
		local b = Button.new({
			Name = "Trick_" .. trick.id,
			Text = trick.name,
			Color = C.Green,
			Size = UDim2.fromOffset(118, 46),
			TextSize = Theme.TextSize.Small,
			Icon = glyph(trick.glyph),
			Parent = wheel,
			OnClick = function()
				close()
				task.spawn(function()
					ctx:GetController("Community").Trick(trick.id)
				end)
			end,
		})
		place(b.Root, i, #Cfg.Tricks, INNER)
	end
	Create.Text({
		Name = "TricksLabel",
		Text = "Monster tricks",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -26),
		Size = UDim2.fromOffset(160, 20),
		TextSize = Theme.TextSize.Small,
		Parent = wheel,
	})
	local closeButton = Button.new({
		Name = "Close",
		Text = "✕",
		Color = C.Red,
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = wheel,
		OnClick = close,
	})
	closeButton.Root.Position = UDim2.new(0.5, 0, 0.5, 14)

	return {
		Root = root,
		Open = function()
			Anim.popIn(wheel)
		end,
		Close = function() end,
	}
end

return EmoteWheel
