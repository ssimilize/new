--[[
	GeneGrades (update 3.6): stat genes (Logic/Genetics) as grade letters.

		GeneGrades.color(points) -> Color3                 the grade's colour
		GeneGrades.badge({ Points, Size?, TextSize?, Position?, AnchorPoint?, LayoutOrder?, Parent })
		  -> Frame                                         one grade letter on its colour
		GeneGrades.row(genes, { Height?, PerRow?, LayoutOrder?, Parent }) -> Frame
		                                                   "HP B  ATK C  DEF A  SPD S", centred;
		                                                   PerRow = 2 makes two lines of two
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Genetics = require(Shared.Logic.Genetics)

local Theme = require(script.Parent.Parent.Theme)
local Create = require(script.Parent.Parent.Create)

local New = Create.New
local C = Theme.Colors

local GeneGrades = {}

function GeneGrades.color(points: number): Color3
	return Color3.fromHex(Genetics.Grade(points).color)
end

function GeneGrades.badge(props)
	local color = GeneGrades.color(props.Points)
	local root = New("Frame", {
		Name = "Grade",
		BackgroundColor3 = color,
		Size = props.Size or UDim2.fromOffset(26, 20),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { Create.Corner(6), Create.Stroke(2) })
	Create.Text({
		Text = Genetics.Grade(props.Points).grade,
		TextSize = props.TextSize or Theme.TextSize.Small,
		TextColor3 = Theme.OnColor(color),
		Stroke = Theme.OnColor(color) == C.White,
		Size = UDim2.fromScale(1, 1),
		TextWrapped = false,
		Parent = root,
	})
	return root
end

function GeneGrades.row(genes, props)
	local height = props.Height or 20
	local perRow = props.PerRow or #Config.Genetics.Stats
	local labelWidth, badgeWidth, gap = 30, math.floor(height * 1.1), 8
	local lines = math.ceil(#Config.Genetics.Stats / perRow)
	local root = New("Frame", {
		Name = "GeneGrades",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, lines * height + (lines - 1) * 4),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { Create.List("y", 4, Enum.HorizontalAlignment.Center) })
	local line
	for i, stat in Config.Genetics.Stats do
		if (i - 1) % perRow == 0 then
			line = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, height),
				LayoutOrder = i,
				Parent = root,
			}, { Create.List("x", gap, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
		end
		-- Fixed widths, so the cells line up from row to row.
		local cell = New("Frame", {
			Name = "Gene_" .. stat,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(labelWidth + 3 + badgeWidth, height),
			LayoutOrder = i,
			Parent = line,
		})
		Create.Text({
			Text = Config.Genetics.StatNames[stat],
			Font = Theme.Fonts.Body,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = C.TextMuted,
			Stroke = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.fromOffset(labelWidth, height),
			TextWrapped = false,
			Parent = cell,
		})
		GeneGrades.badge({
			Points = Genetics.Points(genes, stat),
			Position = UDim2.fromOffset(labelWidth + 3, 0),
			Size = UDim2.fromOffset(badgeWidth, height),
			TextSize = Theme.TextSize.Tiny + 1,
			Parent = cell,
		})
	end
	return root
end

return GeneGrades
