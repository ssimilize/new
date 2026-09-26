--[[
	Button: the chunky outlined game button.

		local b = Button.new({
			Text = "Collect all",
			Color = Theme.Colors.Green,
			Size = UDim2.fromOffset(220, 58),
			Icon = Icon.new("coin", 26),     -- optional GuiObject shown left of the text
			OnClick = function() ... end,
			Parent = frame,
			Sound = "UITab",                 -- optional Config.Sounds key (default "ButtonClick"; false = silent)
		})
		b:SetText("Collect +48K")  b:SetDisabled(true)  b:SetColor(Theme.Colors.Orange)

	A press clicks (client/Audio); a press on a disabled button plays "Locked" with its shake.
]]

local Theme = require(script.Parent.Parent.Theme)
local Create = require(script.Parent.Parent.Create)
local Anim = require(script.Parent.Parent.Anim)
local Audio = require(script.Parent.Parent.Parent.Audio)

local New = Create.New

local Button = {}
Button.__index = Button

export type Props = {
	Text: string?,
	Color: Color3?,
	TextColor: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	TextSize: number?,
	Icon: GuiObject?,
	OnClick: (() -> ())?,
	Disabled: boolean?,
	LayoutOrder: number?,
	Name: string?,
	Parent: Instance?,
	Round: boolean?,
	ZIndex: number?,
	Sound: (string | false)?,
}

function Button.new(props: Props)
	local self = setmetatable({}, Button)
	self._color = props.Color or Theme.Colors.Green
	self._disabled = props.Disabled == true
	self._onClick = props.OnClick
	self._sound = if props.Sound == nil then "ButtonClick" else props.Sound

	local stroke = Create.Stroke(Theme.Stroke.Button)
	local root = New("TextButton", {
		Name = props.Name or "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = self._color,
		Size = props.Size or UDim2.fromOffset(180, 54),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	}, {
		if props.Round then Create.Round() else Create.Corner(Theme.Radius.Button),
		stroke,
		Create.Shade(0.18),
	})
	-- Bottom lip gives the 3D look.
	local lip = New("Frame", {
		Name = "Lip",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 7),
		ZIndex = root.ZIndex,
		Parent = root,
	}, { if props.Round then Create.Round() else Create.Corner(Theme.Radius.Button) })
	-- With the uploaded skin, one 9-slice image draws the outline, highlight, shade and lip over the
	-- colour fill (pill buttons keep the shapes: the skin's corners are the 14 px button radius).
	local skin = Theme.Images.ButtonTexture
	if skin ~= "" and not props.Round then
		stroke.Enabled = false
		lip.Visible = false
		New("ImageLabel", {
			Name = "Skin",
			BackgroundTransparency = 1,
			Image = skin,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Theme.Slices.Button.Center,
			SliceScale = Theme.Slices.Button.Scale,
			Size = UDim2.fromScale(1, 1),
			ZIndex = root.ZIndex,
			Parent = root,
		})
	end

	local content = New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 1, -6),
		Position = UDim2.fromOffset(6, 0),
		ZIndex = root.ZIndex + 1,
		Parent = root,
	}, { Create.List("x", 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })

	if props.Icon then
		props.Icon.LayoutOrder = 1
		props.Icon.ZIndex = root.ZIndex + 2
		props.Icon.Parent = content
	end

	self.Label = Create.Text({
		Name = "Label",
		Text = props.Text or "",
		TextSize = props.TextSize or Theme.TextSize.Button,
		TextColor3 = props.TextColor or Theme.Colors.White,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextWrapped = false,
		LayoutOrder = 2,
		ZIndex = root.ZIndex + 2,
		Parent = content,
	})

	root.MouseButton1Down:Connect(function()
		if not self._disabled then
			Anim.pressDown(root)
		end
	end)
	root.MouseButton1Up:Connect(function()
		Anim.pressUp(root)
	end)
	root.MouseLeave:Connect(function()
		Anim.pressUp(root)
	end)
	root.Activated:Connect(function()
		if self._disabled then
			Anim.shake(root)
			Audio.Play("Locked")
			return
		end
		if self._sound then
			Audio.Play(self._sound)
		end
		if self._onClick then
			task.spawn(self._onClick)
		end
	end)

	self.Root = root
	self.Content = content
	if props.Parent then
		root.Parent = props.Parent
	end
	self:SetDisabled(self._disabled)
	return self
end

function Button:SetText(text: string)
	self.Label.Text = text
end

function Button:SetColor(color: Color3)
	self._color = color
	if not self._disabled then
		self.Root.BackgroundColor3 = color
	end
end

function Button:SetDisabled(disabled: boolean)
	self._disabled = disabled
	self.Root.BackgroundColor3 = if disabled then Theme.Colors.Gray else self._color
	self.Root.AutoButtonColor = false
end

function Button:SetOnClick(fn: () -> ())
	self._onClick = fn
end

function Button:SetVisible(visible: boolean)
	self.Root.Visible = visible
end

function Button:Destroy()
	self.Root:Destroy()
end

return Button
