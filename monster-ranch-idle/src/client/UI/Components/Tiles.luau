--[[
	Tiles (C2): tiny layout helpers built on the UI kit, so screens stay short and every
	colour and font still comes from Theme.

	  Tiles.label(props)            dark text on cream/white (no outline); props override
	  Tiles.frame(props, children)  transparent Frame
	  Tiles.row(props) / col(props) transparent Frame with a list layout
	  Tiles.card(props)             white rounded card (Panel.Card)
	  Tiles.tap(gui, fn)            invisible full-size TextButton on top of `gui`
	  Tiles.clear(container)        destroys GuiObject children (keeps layouts/padding)
	  Tiles.badge(parent)           red corner badge -> { Root, Set(text | nil) }
	  Tiles.lock(parent, text)      grey lock overlay -> Frame
	  Tiles.cost(cost, parent, eventId?, props?) row of Widgets.Amount for a price table
]]

local Theme = require(script.Parent.Parent.Theme)
local Create = require(script.Parent.Parent.Create)
local Icon = require(script.Parent.Icon)
local Widgets = require(script.Parent.Widgets)
local Panel = require(script.Parent.Panel)
local StoreKit = require(script.Parent.StoreKit)
local Format = require(game:GetService("ReplicatedStorage").Shared.Logic.Format)

local New = Create.New
local C = Theme.Colors

local Tiles = {}

function Tiles.label(props: { [string]: any }): TextLabel
	local p = {
		TextColor3 = C.Text,
		Stroke = false,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in props do
		p[k] = v
	end
	return Create.Text(p)
end

function Tiles.frame(props: { [string]: any }?, children: { Instance }?): Frame
	local p = { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }
	for k, v in props or {} do
		p[k] = v
	end
	return New("Frame", p, children)
end

function Tiles.row(props: { [string]: any }, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?)
	return Tiles.frame(props, { Create.List("x", padding or 8, hAlign, vAlign or Enum.VerticalAlignment.Center) })
end

function Tiles.col(props: { [string]: any }, padding: number?, hAlign: Enum.HorizontalAlignment?)
	return Tiles.frame(props, { Create.List("y", padding or 8, hAlign) })
end

function Tiles.card(props: { [string]: any }): Frame
	return Panel.Card(props)
end

function Tiles.tap(gui: GuiObject, fn: () -> (), zIndex: number?): TextButton
	return New("TextButton", {
		Name = "Tap",
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex or 20,
		Parent = gui,
		Activated = function()
			task.spawn(fn)
		end,
	})
end

function Tiles.clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Tiles.badge(parent: GuiObject, zIndex: number?)
	local root = New("Frame", {
		Name = "Badge",
		BackgroundColor3 = C.Red,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(26, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		ZIndex = zIndex or 30,
		Parent = parent,
	}, { Create.Round(), Create.Stroke(2.5), Create.Padding(0, 6, 0, 6) })
	local label = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Small,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 14, 1, 0),
		TextWrapped = false,
		ZIndex = (zIndex or 30) + 1,
		Parent = root,
	})
	return {
		Root = root,
		Set = function(_, text: string?)
			root.Visible = text ~= nil and text ~= "" and text ~= "0"
			label.Text = text or ""
		end,
	}
end

function Tiles.lock(parent: GuiObject, text: string?, zIndex: number?): Frame
	local overlay = New("Frame", {
		Name = "Lock",
		BackgroundColor3 = C.Dark,
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex or 15,
		Parent = parent,
	}, { Create.Corner(Theme.Radius.Card), Create.List("y", 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local icon = Icon.new("lock", 30)
	icon.LayoutOrder = 1
	icon.Parent = overlay
	if text then
		Create.Text({
			Text = text,
			TextSize = Theme.TextSize.Small,
			Size = UDim2.new(1, -8, 0, 36),
			LayoutOrder = 2,
			ZIndex = (zIndex or 15) + 1,
			Parent = overlay,
		})
	end
	return overlay
end

function Tiles.cost(cost: { [string]: number }?, parent: Instance?, eventId: string?, props: { [string]: any }?)
	local p = props or {}
	local row = Tiles.row({
		Name = "Cost",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, p.Height or 26),
		LayoutOrder = p.LayoutOrder or 0,
		Parent = parent,
	}, 10)
	for key, amount in StoreKit.asTable(cost) do
		Widgets.Amount({
			Icon = StoreKit.iconFor(StoreKit.costKey(key, eventId)),
			Text = Format.short(amount),
			TextSize = p.TextSize or Theme.TextSize.Body,
			IconSize = p.IconSize or 22,
			Height = p.Height or 26,
			Color = p.Color,
			Parent = row,
		})
	end
	return row
end

return Tiles
