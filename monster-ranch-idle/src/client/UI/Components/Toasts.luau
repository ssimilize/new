--[[
	Toasts: the one feedback queue. Short messages and reward cards share a single stack just
	above the HUD bottom bar, on the Feedback layer (above popups, so a toast about the hatch
	reveal is never hidden behind it).

		Toasts.show("Not enough coins", "error")       -- kinds: info · success · error · reward
		Toasts.push(card, seconds) -> dismiss()        -- any GuiObject (Notifications' reward cards)
		Toasts.dismiss(item)

	At most MAX items show; a new one sends the oldest out. Items pop in and shrink away, and
	the list layout closes the gap as they leave. The same toast text shown again while it is
	still up refreshes that toast (and nudges it) instead of stacking a copy.
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
local ENTER = 0.2
local LEAVE = 0.16

local order = 0
local expiry = {} :: { [GuiObject]: number } -- item -> token of its current timer
local textOf = {} :: { [GuiObject]: string } -- toast -> its text (for de-duplication)

function Toasts.init(layer: Instance)
	container = New("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		-- Just above the HUD bottom bar; the top centre belongs to weather and broadcasts.
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -92),
		Size = UDim2.fromOffset(640, 300),
		Parent = layer,
	}, { Create.List("y", 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) })
end

-- Items still showing (not on their way out), oldest first.
local function live(): { GuiObject }
	local list = {}
	if not container then
		return list
	end
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") and child:GetAttribute("Leaving") ~= true then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return list
end

function Toasts.dismiss(item: GuiObject)
	if not item.Parent or item:GetAttribute("Leaving") == true then
		return
	end
	item:SetAttribute("Leaving", true)
	expiry[item] = nil
	textOf[item] = nil
	if not Anim.enabled then
		item:Destroy()
		return
	end
	-- Shrinking the UIScale shrinks the item's layout size too, so the stack closes smoothly.
	Anim.tween(Anim.scaleOf(item), { Scale = 0.01 }, LEAVE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(LEAVE + 0.02, function()
		if item.Parent then
			item:Destroy()
		end
	end)
end

local function arm(item: GuiObject, seconds: number)
	local token = (expiry[item] or 0) + 1
	expiry[item] = token
	task.delay(seconds, function()
		if expiry[item] == token then
			Toasts.dismiss(item)
		end
	end)
end

local function enter(item: GuiObject)
	local s = Anim.scaleOf(item)
	if not Anim.enabled then
		s.Scale = 1
		return
	end
	s.Scale = 0.4
	Anim.tween(s, { Scale = 1 }, ENTER, Enum.EasingStyle.Back)
end

-- Adds any GuiObject to the stack for `seconds`. Returns a function that dismisses it early.
function Toasts.push(item: GuiObject, seconds: number?): () -> ()
	if not container then
		item:Destroy()
		return function() end
	end
	local current = live()
	for i = 1, #current - MAX + 1 do
		Toasts.dismiss(current[i])
	end
	order += 1
	item.LayoutOrder = order
	item.Parent = container
	enter(item)
	arm(item, seconds or 3)
	return function()
		Toasts.dismiss(item)
	end
end

function Toasts.show(text: string, kind: string?, duration: number?)
	if not container then
		warn("[Toasts] " .. text)
		return
	end
	local key = (kind or "info") .. "|" .. text
	for _, item in live() do
		if textOf[item] == key then
			arm(item, duration or 2.6)
			Anim.pulse(item, 0.08)
			return
		end
	end
	local toast = New("Frame", {
		Name = "Toast",
		BackgroundColor3 = COLORS[kind or "info"] or COLORS.info,
		BackgroundTransparency = if kind == "info" or kind == nil then 0.2 else 0,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
	}, { Create.Corner(12), Create.Stroke(2.5), Create.Padding(8, 16, 8, 16) })
	Create.Text({
		Text = text,
		TextSize = Theme.TextSize.Body,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		TextWrapped = false,
		Parent = toast,
	})
	textOf[toast] = key
	toast.Destroying:Connect(function()
		textOf[toast] = nil
		expiry[toast] = nil
	end)
	Toasts.push(toast, duration or 2.6)
end

return Toasts
