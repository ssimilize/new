--[[
	Panel: a modal window with a coloured header ribbon and a close button.

		local panel = Panel.new({
			Title = "Egg Shop",
			Color = Theme.Colors.Pink,
			Size = UDim2.fromOffset(900, 470),
			OnClose = function() ctx.Router:Close("EggShop") end,
		})
		-- put content in panel.Body; add header widgets to panel.HeaderRight
]]

local Theme = require(script.Parent.Parent.Theme)
local Create = require(script.Parent.Parent.Create)
local Button = require(script.Parent.Button)

local New = Create.New

local Panel = {}
Panel.__index = Panel

Panel.HEADER = 58

function Panel.new(props: {
	Title: string?,
	Color: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	OnClose: (() -> ())?,
	Parent: Instance?,
	Name: string?,
})
	local self = setmetatable({}, Panel)
	local color = props.Color or Theme.Colors.Orange

	local root = New("Frame", {
		Name = props.Name or "Panel",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(820, 460),
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
	})
	New("Frame", {
		Name = "Shadow",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.65,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 9),
		ZIndex = 1,
		Parent = root,
	}, { Create.Corner(Theme.Radius.Panel) })
	local card = New("Frame", {
		Name = "Card",
		BackgroundColor3 = Theme.Colors.Panel,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		ClipsDescendants = true,
		Parent = root,
	}, { Create.Corner(Theme.Radius.Panel), Create.Stroke(Theme.Stroke.Panel) })
	-- With the uploaded skin, a 9-slice overlay above the card (and its header) draws the outline,
	-- the top highlight and the inner shade; the card keeps its cream fill underneath.
	if Theme.Images.PanelTexture ~= "" then
		(card:FindFirstChildOfClass("UIStroke") :: UIStroke).Enabled = false
		New("ImageLabel", {
			Name = "Skin",
			BackgroundTransparency = 1,
			Image = Theme.Images.PanelTexture,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Theme.Slices.Panel.Center,
			SliceScale = Theme.Slices.Panel.Scale,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = root,
		})
	end

	local header = New("Frame", {
		Name = "Header",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, Panel.HEADER),
		ZIndex = 3,
		Parent = card,
	}, { Create.Shade(0.12) })
	New("Frame", {
		Name = "Rule",
		BackgroundColor3 = Theme.Colors.Ink,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -2),
		Size = UDim2.new(1, 0, 0, 4),
		ZIndex = 4,
		Parent = header,
	})
	self.TitleLabel = Create.Text({
		Name = "Title",
		Text = props.Title or "",
		TextSize = Theme.TextSize.Header + 2,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.new(0.6, 0, 1, 0),
		ZIndex = 5,
		Parent = header,
	})
	local right = New("Frame", {
		Name = "HeaderRight",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0.5, 0, 0, 44),
		ZIndex = 5,
		Parent = header,
	}, { Create.List("x", 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })

	if props.OnClose then
		local close = Button.new({
			Text = "✕",
			Color = Theme.Colors.Red,
			Size = UDim2.fromOffset(44, 44),
			TextSize = 24,
			LayoutOrder = 100,
			ZIndex = 6,
			OnClick = props.OnClose,
			Parent = right,
		})
		close.Root.SelectionOrder = 2 -- a gamepad cursor lands on the content first
		self.CloseButton = close
	end

	local body = New("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, Panel.HEADER),
		Size = UDim2.new(1, 0, 1, -Panel.HEADER),
		ZIndex = 3,
		Parent = card,
	}, { Create.Padding(16, 18, 16, 18) })

	self.Root = root
	self.Card = card
	self.Header = header
	self.HeaderRight = right
	self.Body = body
	if props.Parent then
		root.Parent = props.Parent
	end
	return self
end

function Panel:SetTitle(text: string)
	self.TitleLabel.Text = text
end

function Panel:SetColor(color: Color3)
	self.Header.BackgroundColor3 = color
end

-- A white rounded card for grouping content inside a panel body.
function Panel.Card(props: { Size: UDim2?, Position: UDim2?, Parent: Instance?, Name: string?, LayoutOrder: number?, Color: Color3? })
	return New("Frame", {
		Name = props.Name or "Card",
		BackgroundColor3 = props.Color or Theme.Colors.Card,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { Create.Corner(Theme.Radius.Card), Create.Stroke(Theme.Stroke.Card) })
end

return Panel
