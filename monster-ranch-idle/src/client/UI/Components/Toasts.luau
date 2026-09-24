--[[
	Toasts: short messages stacked at the top of the screen.
		Toasts.show("Not enough coins", "error")
	Kinds: info · success · error · reward
]]

local Theme = require(script.Parent.Parent.Theme)
local Create = require(script.Parent.Parent.Create)
local Anim = require(script.Parent.Parent.Anim)

local New = Create.New

local Toasts = {}

local container: Frame? = nil
local COLORS = {
	info = Color3.fromHex("#1F2B24"),
	success = Theme.Colors.Green,
	error = Theme.Colors.Red,
	reward = Theme.Colors.Orange,
}
local MAX = 4

function Toasts.init(layer: Instance)
	container = New("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(560, 300),
		Parent = layer,
	}, { Create.List("y", 8, Enum.HorizontalAlignment.Center) })
end

function Toasts.show(text: string, kind: string?, duration: number?)
	if not container then
		warn("[Toasts] " .. text)
		return
	end
	local count = 0
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count >= MAX then
		for _, child in container:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
				break
			end
		end
	end
	local toast = New("Frame", {
		BackgroundColor3 = COLORS[kind or "info"] or COLORS.info,
		BackgroundTransparency = if kind == "info" or kind == nil then 0.2 else 0,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Parent = container,
	}, { Create.Corner(12), Create.Stroke(2.5), Create.Padding(8, 16, 8, 16) })
	Create.Text({
		Text = text,
		TextSize = Theme.TextSize.Body,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		TextWrapped = false,
		Parent = toast,
	})
	Anim.popIn(toast, 0.18)
	task.delay(duration or 2.6, function()
		if toast.Parent then
			toast:Destroy()
		end
	end)
end

return Toasts
