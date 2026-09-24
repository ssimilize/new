--[[
	Tutorial controller (C3).

	Reads profile.Quests.tutorial.step and Config.Quests.Tutorial and shows a compact
	instruction card (text + progress) plus a bouncing arrow over
	ctx:GetController("Hud"):GetTarget(step.arrow) (a missing HUD or target just hides the
	arrow). `ack` steps get a "Got it" button → Quests.Ack { step = id }. Quests.StepDone
	shows a small reward toast. Everything hides once the tutorial is done.
	Also publishes the client bus topic "Tutorial.Arrow" (target name or nil) on every step.
]]

local RunService = game:GetService("RunService")

local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)
local Button = require(script.Parent.Parent.UI.Components.Button)
local Widgets = require(script.Parent.Parent.UI.Components.Widgets)
local Anim = require(script.Parent.Parent.UI.Anim)
local Util = require(script.Parent.Parent.UI.Screens.Parts.Util)

local New = Create.New
local C = Theme.Colors

local Tutorial = {
	Name = "Tutorial",
	Dependencies = { "Hud" },
}

local ctx
local card, stepLabel, textLabel, progressBar, ackButton, arrow
local currentDef = nil
local arrowName: string? = nil
local lastArrowTopic = "\0"
local renderConn = nil
local cachedTarget: GuiObject? = nil
local lastLookup = 0
local acking = false

local function getTarget(name: string): GuiObject?
	local hud = ctx:GetController("Hud")
	if not hud or type(hud.GetTarget) ~= "function" then
		return nil
	end
	local ok, target = pcall(hud.GetTarget, hud, name)
	if ok and typeof(target) == "Instance" and target:IsA("GuiObject") then
		return target
	end
	return nil
end

local function onScreen(gui: GuiObject): boolean
	if not gui.Visible or not gui:IsDescendantOf(game) then
		return false
	end
	local parent = gui.Parent
	while parent and parent:IsA("GuiObject") do
		if not parent.Visible then
			return false
		end
		parent = parent.Parent
	end
	return gui.AbsoluteSize.X > 0
end

local function stopArrow()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	cachedTarget = nil
	if arrow then
		arrow.Visible = false
	end
end

local function startArrow()
	if renderConn then
		return
	end
	local t0 = os.clock()
	renderConn = RunService.RenderStepped:Connect(function()
		if not arrowName then
			arrow.Visible = false
			return
		end
		local now = os.clock()
		if now - lastLookup > 0.5 or (cachedTarget and not cachedTarget.Parent) then
			lastLookup = now
			cachedTarget = getTarget(arrowName)
		end
		local target = cachedTarget
		-- Hide while a menu covers the HUD.
		if not target or ctx.Router:Current() ~= nil or not onScreen(target) then
			arrow.Visible = false
			return
		end
		local overlay = ctx.UI.Overlay
		local scale = if overlay.Size.X.Offset > 0 then overlay.AbsoluteSize.X / overlay.Size.X.Offset else 1
		if scale <= 0 then
			scale = 1
		end
		local rel = (target.AbsolutePosition - overlay.AbsolutePosition) / scale
		local size = target.AbsoluteSize / scale
		local bounce = if Anim.enabled then math.sin((now - t0) * 5) * 8 else 0
		local below = rel.Y < 90
		arrow.Text = if below then "▲" else "▼"
		if below then
			arrow.AnchorPoint = Vector2.new(0.5, 0)
			arrow.Position = UDim2.fromOffset(rel.X + size.X / 2, rel.Y + size.Y + 4 + bounce)
		else
			arrow.AnchorPoint = Vector2.new(0.5, 1)
			arrow.Position = UDim2.fromOffset(rel.X + size.X / 2, rel.Y - 4 + bounce)
		end
		arrow.Visible = true
	end)
end

local function render(tutorial)
	local Steps = ctx.Config.Quests.Tutorial
	local step = if type(tutorial) == "table" then tutorial.step else nil
	local def = if type(step) == "number" then Steps[step] else nil
	currentDef = def
	local newArrow = if def then def.arrow else nil
	if newArrow ~= lastArrowTopic then
		lastArrowTopic = newArrow
		ctx.Bus:Publish("Tutorial.Arrow", newArrow)
	end
	if not def then
		card.Visible = false
		arrowName = nil
		stopArrow()
		return
	end
	local wasVisible = card.Visible
	card.Visible = true
	stepLabel.Text = string.format("Step %d of %d", step, #Steps)
	textLabel.Text = def.text
	local target = def.target or 1
	local progress = math.clamp(if type(tutorial.progress) == "number" then tutorial.progress else 0, 0, target)
	progressBar.Root.Visible = target > 1
	progressBar:SetValue(progress / target, true)
	progressBar:SetText(string.format("%d / %d", progress, target))
	ackButton:SetVisible(def.ack == true)
	ackButton:SetDisabled(false)
	acking = false
	if not wasVisible then
		Anim.popIn(card)
	end
	arrowName = newArrow
	cachedTarget = nil
	lastLookup = 0
	if arrowName then
		startArrow()
	else
		stopArrow()
	end
end

function Tutorial.Init(context)
	ctx = context
	local overlay = ctx.UI.Overlay

	card = New("Frame", {
		Name = "TutorialCard",
		BackgroundColor3 = C.Dark,
		BackgroundTransparency = 0.12,
		AnchorPoint = Vector2.new(0, 1),
		-- Bottom-left, narrow enough to clear the HUD bottom bar (x ≥ 230 at design size).
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(210, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = overlay,
	}, {
		Create.Corner(14),
		Create.Stroke(3, C.Gold),
		Create.Padding(10, 14, 12, 14),
		Create.List("y", 6),
	})
	stepLabel = Create.Text({
		Text = "",
		Font = Theme.Fonts.Body,
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.Gold,
		Stroke = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		Parent = card,
	})
	textLabel = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 2,
		Parent = card,
	})
	progressBar = Widgets.Bar({ Color = C.Gold, Value = 0, Text = "", Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 3, Parent = card })
	ackButton = Button.new({
		Text = "Got it",
		Color = C.Green,
		Size = UDim2.fromOffset(160, 48),
		TextSize = Theme.TextSize.Body,
		LayoutOrder = 4,
		Parent = card,
	})
	ackButton:SetVisible(false)
	ackButton:SetOnClick(function()
		local def = currentDef
		if not def or acking then
			return
		end
		acking = true
		ackButton:SetDisabled(true)
		local ok = Util.request(ctx, "Quests.Ack", { step = def.id })
		if not ok and currentDef == def then
			acking = false
			ackButton:SetDisabled(false)
		end
	end)

	arrow = Create.Text({
		Name = "TutorialArrow",
		Text = "▼",
		TextSize = 54,
		TextColor3 = C.Gold,
		Stroke = true,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(60, 60),
		Visible = false,
		ZIndex = 20,
		Parent = overlay,
	})
	local stroke = arrow:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 3
	end

	ctx.Store:Observe("profile.Quests.tutorial", render)

	ctx.Net:On("Quests.StepDone", function(payload)
		if type(payload) ~= "table" then
			return
		end
		local parts = {}
		for _, item in payload.rewards or {} do
			table.insert(parts, Util.rewardText(item))
		end
		if #parts > 0 then
			ctx:Toast("Nice! + " .. table.concat(parts, ", "), "reward")
		else
			ctx:Toast("Nice!", "success")
		end
	end)
end

function Tutorial.Start() end

-- Lets other controllers ask where the tutorial is (e.g. to pulse a button). Returns the
-- current step definition or nil when the tutorial is finished.
function Tutorial:GetStep()
	return currentDef
end

return Tutorial
