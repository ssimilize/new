--[[
	InsetPopup (C2): a small modal card shown inside a screen (flavour picker, rename, decor
	picker, confirmations). It dims its parent (usually panel.Card) and closes when the dim
	area or the ✕ is tapped. Content goes in popup.Body; call popup:Show() / popup:Hide().

		local popup = InsetPopup.new({ Parent = panel.Card, Title = "Feed", Size = UDim2.fromOffset(420, 300) })
		Tiles.clear(popup.Body) ... popup:Show()
]]

local Theme = require(script.Parent.Parent.Theme)
local Create = require(script.Parent.Parent.Create)
local Anim = require(script.Parent.Parent.Anim)
local Button = require(script.Parent.Button)
local Focus = require(script.Parent.Parent.Focus)

local New = Create.New

local InsetPopup = {}
InsetPopup.__index = InsetPopup

function InsetPopup.new(props: { Parent: Instance, Title: string?, Size: UDim2?, Color: Color3?, OnHide: (() -> ())? })
	local self = setmetatable({}, InsetPopup)
	self._onHide = props.OnHide
	local dim = New("TextButton", {
		Name = "Popup",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.Dark,
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
		Selectable = false, -- tap blockers, never gamepad targets
		Parent = props.Parent,
		Activated = function()
			self:Hide()
		end,
	})
	local box = New("TextButton", { -- a button so taps inside never reach the dim
		Name = "Box",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.Panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = props.Size or UDim2.fromOffset(420, 300),
		ZIndex = 41,
		Selectable = false,
		Parent = dim,
	}, { Create.Corner(Theme.Radius.Panel), Create.Stroke(Theme.Stroke.Panel) })
	local header = New("Frame", {
		Name = "Header",
		BackgroundColor3 = props.Color or Theme.Colors.Orange,
		Size = UDim2.new(1, 0, 0, 50),
		ZIndex = 42,
		Parent = box,
	}, { Create.Corner(Theme.Radius.Panel), Create.Shade(0.12) })
	self.TitleLabel = Create.Text({
		Text = props.Title or "",
		TextSize = Theme.TextSize.Header,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -80, 1, 0),
		ZIndex = 43,
		Parent = header,
	})
	local close = Button.new({
		Text = "✕",
		Color = Theme.Colors.Red,
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		TextSize = 22,
		ZIndex = 44,
		Parent = header,
		OnClick = function()
			self:Hide()
		end,
	})
	close.Root.SelectionOrder = 2 -- a gamepad cursor lands on the content first
	self.Body = New("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		ZIndex = 42,
		Parent = box,
	}, { Create.Padding(12, 14, 12, 14) })
	self.Root = dim
	self.Box = box
	return self
end

function InsetPopup:SetTitle(text: string)
	self.TitleLabel.Text = text
end

function InsetPopup:SetSize(size: UDim2)
	self.Box.Size = size
end

function InsetPopup:Show()
	self.Root.Visible = true
	Anim.popIn(self.Box, 0.18)
	Focus.push(self.Root, function()
		self:Hide()
	end)
end

function InsetPopup:Hide()
	if not self.Root.Visible then
		return
	end
	self.Root.Visible = false
	Focus.remove(self.Root)
	if self._onHide then
		task.spawn(self._onHide)
	end
end

function InsetPopup:IsOpen(): boolean
	return self.Root.Visible
end

return InsetPopup
