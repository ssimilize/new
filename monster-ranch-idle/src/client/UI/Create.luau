--[[
	Create: declarative instance builder plus small decorator helpers.

		local New = Create.New
		local frame = New("Frame", {
			Size = UDim2.fromOffset(200, 60),
			BackgroundColor3 = Theme.Colors.Panel,
			Parent = parent,
		}, {
			Create.Corner(12),
			Create.Stroke(3),
			New("TextButton", { Text = "Go", Activated = function() ... end }),
		})

	Function-valued props whose name is an event (Activated, MouseEnter, …) are connected.
]]

local Theme = require(script.Parent.Theme)

local Create = {}

function Create.New(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		elseif type(value) == "function" then
			local ok, member = pcall(function()
				return (inst :: any)[key]
			end)
			if ok and typeof(member) == "RBXScriptSignal" then
				member:Connect(value)
			else
				(inst :: any)[key] = value
			end
		else
			(inst :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Create.Corner(radius: number | UDim?): UICorner
	local c = Instance.new("UICorner")
	if typeof(radius) == "UDim" then
		c.CornerRadius = radius
	else
		c.CornerRadius = UDim.new(0, (radius :: number?) or Theme.Radius.Card)
	end
	return c
end

function Create.Round(): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	return c
end

-- Border stroke for frames (never applied to text).
function Create.Stroke(thickness: number?, color: Color3?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Thickness = thickness or Theme.Stroke.Card
	s.Color = color or Theme.Colors.Ink
	s.Transparency = transparency or 0
	s.LineJoinMode = Enum.LineJoinMode.Round
	return s
end

-- Outline for text labels (the "Roblox game" white-with-dark-outline look).
function Create.TextStroke(thickness: number?, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Thickness = thickness or Theme.Stroke.Text
	s.Color = color or Theme.Colors.Ink
	s.LineJoinMode = Enum.LineJoinMode.Round
	return s
end

function Create.Padding(top: number, right: number?, bottom: number?, left: number?): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, top)
	p.PaddingRight = UDim.new(0, right or top)
	p.PaddingBottom = UDim.new(0, bottom or top)
	p.PaddingLeft = UDim.new(0, left or right or top)
	return p
end

function Create.List(
	direction: "x" | "y",
	padding: number?,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = if direction == "x" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, padding or 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left
	l.VerticalAlignment = vAlign or Enum.VerticalAlignment.Top
	return l
end

function Create.Grid(cell: Vector2, padding: number?): UIGridLayout
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	g.CellPadding = UDim2.fromOffset(padding or 10, padding or 10)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	return g
end

-- Vertical shading gradient (lighter top, darker bottom) used on buttons and ribbons.
function Create.Shade(amount: number?): UIGradient
	local g = Instance.new("UIGradient")
	local dark = 1 - (amount or 0.16)
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(dark, dark, dark))
	g.Rotation = 90
	return g
end

function Create.Aspect(ratio: number): UIAspectRatioConstraint
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = ratio
	return a
end

-- A text label in the house style. Props override defaults.
function Create.Text(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Display,
		TextColor3 = Theme.Colors.White,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24),
		TextWrapped = true,
		RichText = false,
	}
	local stroke = props.Stroke
	props.Stroke = nil
	for k, v in props do
		defaults[k] = v
	end
	local label = Create.New("TextLabel", defaults)
	if stroke ~= false then
		local isLight = defaults.TextColor3 == Theme.Colors.White or stroke == true
		if isLight then
			Create.TextStroke(if type(stroke) == "number" then stroke else Theme.Stroke.Text).Parent = label
		end
	end
	return label
end

return Create
