--[[
	Widgets: small building blocks used across screens.

	  Widgets.Pill({ Icon = "coin", Text = "1.28M", Parent })       -> { Root, Label, SetText }
	  Widgets.Bar({ Color, Value = 0..1, Size, Parent, Text? })     -> { Root, SetValue(v, animate?), SetText }
	  Widgets.Chip({ Text, Color, Parent, TextSize? })               -> Frame
	  Widgets.Scroll({ Size, Position, Parent, Cell = Vector2, Padding }) -> ScrollingFrame (grid)
	  Widgets.List({ Size, Position, Parent, Padding })             -> ScrollingFrame (vertical list)
	  Widgets.Tabs({ Tabs = { { id, text } }, Selected, OnChanged, Parent, Size }) -> { Root, Select(id), Step(delta) }
	  Widgets.FindTabs(container) -> tabs?  the first shown Tabs inside container (gamepad LB / RB)
	  Widgets.Countdown(label, getEndsAt, format?, onDone?)         -> disconnect fn
	  Widgets.RarityChip(index, Parent) / Widgets.ElementChip(id, Parent) / Widgets.MutationChip(id, Parent)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Theme = require(script.Parent.Parent.Theme)
local Create = require(script.Parent.Parent.Create)
local Anim = require(script.Parent.Parent.Anim)
local Icon = require(script.Parent.Icon)
local Button = require(script.Parent.Button)
local Audio = require(script.Parent.Parent.Parent.Audio)

local New = Create.New
local C = Theme.Colors

local Widgets = {}

function Widgets.Pill(props)
	local root = New("Frame", {
		Name = props.Name or "Pill",
		BackgroundColor3 = C.Dark,
		BackgroundTransparency = 0.35,
		Size = props.Size or UDim2.fromOffset(150, 40),
		AutomaticSize = if props.Size then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, {
		Create.Round(),
		Create.Stroke(2.5, C.White, 0.1),
		Create.Padding(4, 16, 4, 5),
		Create.List("x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	local icon = Icon.new(props.Icon or "coin", 30)
	icon.LayoutOrder = 1
	icon.Parent = root
	local label = Create.Text({
		Text = props.Text or "0",
		TextSize = Theme.TextSize.Button,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = root,
	})
	return {
		Root = root,
		Label = label,
		SetText = function(_, text: string)
			label.Text = text
		end,
	}
end

function Widgets.Bar(props)
	local root = New("Frame", {
		Name = props.Name or "Bar",
		BackgroundColor3 = Color3.fromHex("#E7DCC2"),
		Size = props.Size or UDim2.new(1, 0, 0, 18),
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		ClipsDescendants = true,
		Parent = props.Parent,
	}, { Create.Round(), Create.Stroke(2.5) })
	local fill = New("Frame", {
		Name = "Fill",
		BackgroundColor3 = props.Color or C.Green,
		Size = UDim2.fromScale(math.clamp(props.Value or 0, 0, 1), 1),
		Parent = root,
	}, { Create.Round(), Create.Shade(0.2) })
	local text
	if props.Text then
		text = Create.Text({
			Text = props.Text,
			TextSize = Theme.TextSize.Tiny + 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = root,
		})
	end
	local api = { Root = root, Fill = fill }
	function api.SetValue(_, v: number, animate: boolean?)
		local target = UDim2.fromScale(math.clamp(v, 0, 1), 1)
		if animate then
			Anim.tween(fill, { Size = target }, 0.3)
		else
			fill.Size = target
		end
	end
	function api.SetText(_, t: string)
		if text then
			text.Text = t
		end
	end
	function api.SetColor(_, color: Color3)
		fill.BackgroundColor3 = color
	end
	return api
end

function Widgets.Chip(props)
	local color = props.Color or C.Gray
	local root = New("Frame", {
		Name = props.Name or "Chip",
		BackgroundColor3 = color,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, props.Height or 26),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { Create.Round(), Create.Stroke(2), Create.Padding(0, 10, 0, 10) })
	Create.Text({
		Text = props.Text or "",
		TextSize = props.TextSize or Theme.TextSize.Tiny + 1,
		TextColor3 = Theme.OnColor(color),
		Stroke = Theme.OnColor(color) == C.White,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextWrapped = false,
		Parent = root,
	})
	return root
end

function Widgets.RarityChip(index: number, parent: Instance?)
	return Widgets.Chip({ Text = string.upper(Theme.RarityName(index)), Color = Theme.Rarity(index), Parent = parent })
end

function Widgets.ElementChip(id: string, parent: Instance?)
	local e = Config.Elements.ById[id]
	return Widgets.Chip({ Text = if e then e.name else id, Color = Theme.Element(id), Parent = parent })
end

function Widgets.MutationChip(id: string, parent: Instance?)
	local m = Config.Mutations.ById[id]
	local text = if m then string.format("%s ×%s", m.name, tostring(m.mult)) else id
	return Widgets.Chip({ Text = text, Color = Theme.Mutation(id), Parent = parent })
end

function Widgets.VariantChip(variant: number, parent: Instance?)
	if variant == 1 then
		return Widgets.Chip({ Text = "GOLDEN", Color = Color3.fromHex("#E0A915"), Parent = parent })
	elseif variant == 2 then
		local chip = Widgets.Chip({ Text = "RAINBOW", Color = C.Pink, Parent = parent })
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHex("#FF7A7A")),
			ColorSequenceKeypoint.new(0.5, Color3.fromHex("#7BE07B")),
			ColorSequenceKeypoint.new(1, Color3.fromHex("#C17BFF")),
		})
		g.Parent = chip
		return chip
	end
	return nil
end

function Widgets.Scroll(props)
	local cell = props.Cell or Vector2.new(140, 170)
	local root = New("ScrollingFrame", {
		Name = props.Name or "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.TextMuted,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = props.Parent,
	}, { Create.Grid(cell, props.Padding or 12), Create.Padding(6, 12, 10, 6) })
	return root
end

function Widgets.List(props)
	return New("ScrollingFrame", {
		Name = props.Name or "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.TextMuted,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = props.Parent,
	}, { Create.List("y", props.Padding or 10), Create.Padding(4, 12, 10, 4) })
end

-- Every Tabs row by its Root, so the Gamepad controller can find and step the open
-- screen's tabs without each screen wiring LB / RB itself. Weak keys: rows die with screens.
local tabsByRoot = setmetatable({}, { __mode = "k" })

function Widgets.Tabs(props)
	local root = New("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.new(1, 0, 0, 44),
		Position = props.Position or UDim2.new(),
		Parent = props.Parent,
	}, { Create.List("x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	local buttons = {}
	local api = { Root = root, Selected = props.Selected or (props.Tabs[1] and props.Tabs[1].id) }
	local function refresh()
		for id, b in buttons do
			b:SetColor(if id == api.Selected then C.Orange else C.Gray)
		end
	end
	for i, tab in props.Tabs do
		buttons[tab.id] = Button.new({
			Text = tab.text,
			TextSize = Theme.TextSize.Small + 1,
			Size = UDim2.fromOffset(tab.width or 130, 40),
			LayoutOrder = i,
			Color = C.Gray,
			Parent = root,
			Sound = "UITab",
			OnClick = function()
				api:Select(tab.id)
			end,
		})
		buttons[tab.id].Root.SelectionOrder = 1 -- a gamepad cursor lands on the content first
	end
	function api.Select(_, id: string)
		api.Selected = id
		refresh()
		if props.OnChanged then
			props.OnChanged(id)
		end
	end
	-- Selects the previous (-1) or next (+1) shown tab, wrapping; returns its button.
	function api.Step(_, delta: number): GuiObject?
		local shown = {}
		for _, tab in props.Tabs do
			if buttons[tab.id].Root.Visible then
				table.insert(shown, tab.id)
			end
		end
		if #shown == 0 then
			return nil
		end
		local at = table.find(shown, api.Selected) or 1
		local id = shown[(at - 1 + delta) % #shown + 1]
		Audio.Play("UITab")
		api:Select(id)
		return buttons[id].Root
	end
	refresh()
	tabsByRoot[root] = api
	return api
end

local function shownWithin(gui: Instance, container: Instance): boolean
	local cursor: Instance? = gui
	while cursor and cursor ~= container do
		if cursor:IsA("GuiObject") and not (cursor :: GuiObject).Visible then
			return false
		end
		cursor = cursor.Parent
	end
	return cursor == container
end

function Widgets.FindTabs(container: Instance)
	for _, d in container:GetDescendants() do
		local api = tabsByRoot[d]
		if api and shownWithin(d, container) then
			return api
		end
	end
	return nil
end

-- Keeps a label showing the time left until getEndsAt() (unix seconds). Returns a stop fn.
function Widgets.Countdown(label: TextLabel, getEndsAt: () -> number?, format: ((number) -> string)?, onDone: (() -> ())?)
	local fmt = format or Format.clock
	local fired = false
	local acc = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		if not label.Parent then
			conn:Disconnect()
			return
		end
		local endsAt = getEndsAt()
		if not endsAt or endsAt <= 0 then
			return
		end
		local left = endsAt - workspace:GetServerTimeNow()
		if left <= 0 then
			label.Text = fmt(0)
			if not fired and onDone then
				fired = true
				task.spawn(onDone)
			end
		else
			fired = false
			label.Text = fmt(left)
		end
	end)
	return function()
		conn:Disconnect()
	end
end

-- A small "currency + number" row used in costs and reward lists.
function Widgets.Amount(props)
	local root = New("Frame", {
		Name = "Amount",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, props.Height or 28),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { Create.List("x", 5, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	local icon = Icon.new(props.Icon or "coin", props.IconSize or 24)
	icon.LayoutOrder = 1
	icon.Parent = root
	Create.Text({
		Text = props.Text or "",
		TextColor3 = props.Color or C.Text,
		Stroke = props.Color == nil and false or nil,
		TextSize = props.TextSize or Theme.TextSize.Body,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = root,
	})
	return root
end

return Widgets
