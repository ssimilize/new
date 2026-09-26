--[[
	Parts/Dialog (C3): small modal dialogs drawn in a layer above screens (usually
	ctx.UI.Top), for confirmations, results and requests from the C3 screens and controllers.

		local d = Dialog.show(ctx.UI.Top, {
			Title = "Recall expedition?",
			Color = Theme.Colors.Red,
			Size = Vector2.new(520, 300),
			Text = "You keep partial loot and lose the duration bonus.",
			Build = function(content, close) ... end,  -- optional extra content (vertical list)
			Buttons = { { Text = "Recall", Color = Theme.Colors.Red, OnClick = function() ... end } },
			Closable = true,                           -- ✕ button (default true)
			OnClose = function() end,
		})
		d.Close()

	A button's OnClick may return `false` to keep the dialog open. Buttons close it otherwise.

		Dialog.confirm(layer, { Title, Text, ConfirmText, ConfirmColor, OnConfirm, Build? })
]]

local UI = script.Parent.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Panel = require(UI.Components.Panel)
local Button = require(UI.Components.Button)
local Focus = require(UI.Focus)

local New = Create.New
local C = Theme.Colors

local Dialog = {}

function Dialog.show(layer: Instance, props)
	local size = props.Size or Vector2.new(520, 300)
	local closed = false

	-- Full-screen blocker: sinks taps so nothing underneath is pressed by accident.
	local dim = New("TextButton", {
		Name = "Dialog",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(10, 18, 14),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = props.ZIndex or 50,
		Selectable = false, -- a tap blocker, never a gamepad target
		Parent = layer,
	})

	local api = {}
	local function close()
		if closed then
			return
		end
		closed = true
		Focus.remove(dim)
		dim:Destroy()
		if props.OnClose then
			task.spawn(props.OnClose)
		end
	end
	api.Close = close
	api.IsOpen = function()
		return not closed
	end

	local panel = Panel.new({
		Title = props.Title or "",
		Color = props.Color or C.Orange,
		Size = UDim2.fromOffset(size.X, size.Y),
		OnClose = if props.Closable ~= false then close else nil,
		Parent = dim,
	})
	panel.Root.Active = true

	local buttons = props.Buttons or {}
	local hasButtons = #buttons > 0
	local content = New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, if hasButtons then -64 else 0),
		Parent = panel.Body,
	}, { Create.List("y", 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top) })

	if props.Text then
		Create.Text({
			Text = props.Text,
			Font = Theme.Fonts.Body,
			TextColor3 = C.Text,
			Stroke = false,
			TextSize = Theme.TextSize.Body,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = 1,
			Parent = content,
		})
	end
	if props.Build then
		props.Build(content, close)
	end

	if hasButtons then
		local row = New("Frame", {
			Name = "Buttons",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1, 0, 0, 56),
			Parent = panel.Body,
		}, { Create.List("x", 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
		local width = math.clamp(math.floor((size.X - 60) / #buttons) - 12, 120, 240)
		for i, spec in buttons do
			Button.new({
				Text = spec.Text,
				Color = spec.Color or C.Green,
				Size = UDim2.fromOffset(spec.Width or width, 54),
				TextSize = spec.TextSize or Theme.TextSize.Body + 2,
				LayoutOrder = i,
				Parent = row,
				OnClick = function()
					if closed then
						return
					end
					local keep = false
					if spec.OnClick then
						keep = spec.OnClick() == false
					end
					if not keep then
						close()
					end
				end,
			})
		end
	end

	api.Root = dim
	api.Panel = panel
	api.Content = content
	if not closed then
		-- A gamepad cursor stays inside the dialog; B closes it only when ✕ could.
		Focus.push(dim, if props.Closable ~= false then close else nil)
	end
	Anim.popIn(panel.Root)
	return api
end

-- Yes / no dialog. OnConfirm runs after the dialog closes.
function Dialog.confirm(layer: Instance, props)
	return Dialog.show(layer, {
		Title = props.Title or "Are you sure?",
		Color = props.Color or props.ConfirmColor or C.Orange,
		Size = props.Size or Vector2.new(540, 300),
		Text = props.Text,
		Build = props.Build,
		Buttons = {
			{ Text = props.CancelText or "Cancel", Color = C.Gray },
			{
				Text = props.ConfirmText or "Confirm",
				Color = props.ConfirmColor or C.Green,
				OnClick = function()
					if props.OnConfirm then
						task.spawn(props.OnConfirm)
					end
				end,
			},
		},
	})
end

return Dialog
