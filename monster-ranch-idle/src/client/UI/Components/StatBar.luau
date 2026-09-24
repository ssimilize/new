--[[
	StatBar (C2): one "label · bar · value" row (monster stats, diet meter, egg odds).

		local row = StatBar.new({ Label = "ATK", Color = Theme.Colors.Red, Parent = list })
		row:Set(0.62, "612")
]]

local Theme = require(script.Parent.Parent.Theme)
local Create = require(script.Parent.Parent.Create)
local Widgets = require(script.Parent.Widgets)

local New = Create.New

local StatBar = {}

function StatBar.new(props: {
	Label: string,
	Color: Color3?,
	Value: number?,
	Text: string?,
	Parent: Instance?,
	LayoutOrder: number?,
	LabelWidth: number?,
	ValueWidth: number?,
	Height: number?,
	TextSize: number?,
})
	local height = props.Height or 24
	local labelWidth = props.LabelWidth or 56
	local valueWidth = props.ValueWidth or 64
	local root = New("Frame", {
		Name = "StatBar_" .. props.Label,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	local label = Create.Text({
		Text = props.Label,
		TextColor3 = Theme.Colors.Text,
		Stroke = false,
		TextSize = props.TextSize or Theme.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0, labelWidth, 1, 0),
		TextWrapped = false,
		Parent = root,
	})
	local bar = Widgets.Bar({
		Color = props.Color,
		Value = props.Value or 0,
		Position = UDim2.new(0, labelWidth + 4, 0.5, -math.floor(height * 0.35)),
		Size = UDim2.new(1, -(labelWidth + valueWidth + 12), 0, math.floor(height * 0.7)),
		Parent = root,
	})
	local value = Create.Text({
		Text = props.Text or "",
		TextColor3 = Theme.Colors.Text,
		Stroke = false,
		TextSize = props.TextSize or Theme.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, valueWidth, 1, 0),
		TextWrapped = false,
		Parent = root,
	})
	return {
		Root = root,
		Bar = bar,
		Label = label,
		Value = value,
		Set = function(_, v: number, text: string?, animate: boolean?)
			bar:SetValue(v, animate)
			if text then
				value.Text = text
			end
		end,
		SetColor = function(_, color: Color3)
			bar:SetColor(color)
		end,
	}
end

return StatBar
