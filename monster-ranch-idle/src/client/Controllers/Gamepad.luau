--[[
	Gamepad (update 3.2): controller support. Dormant until the last input comes from a pad.

	Roblox already moves GuiService.SelectedObject with the D-pad / left stick and presses the
	selected button with A (GuiButton.Activated, which every button here uses), so A is never
	bound: binding it would sink every button press. This controller decides what may be
	selected, what is selected, what B does and what the player is told.

	  mode       active while UserInputService's last input type is a gamepad (checked on
	             LastInputTypeChanged, GamepadConnected / Disconnected, and at Start when
	             GamepadEnabled). Touch, mouse or keyboard input switches it off, and switching
	             off restores everything it changed.
	  scope      the topmost open layer: a UI/Focus modal (Dialog, InsetPopup, hatch reveal,
	             evolution popup), else the open Router screen. Its root gets SelectionGroup and
	             SelectionBehavior* = Stop, so the engine's navigation cannot wander onto the HUD
	             or onto hidden screens. Old values come back when the scope changes.
	  focus      level-triggered, every frame while active: when the selection is not a shown,
	             selectable control inside the scope, it moves to the control last selected in
	             that scope (a closed dialog hands selection back), else to the first control
	             (lowest SelectionOrder, then tree order; tabs and ✕ rank after content). With
	             no scope it returns to what was selected before the first screen opened
	             (usually nothing, so A still jumps). Being level-triggered, screens that were
	             already open when the pad was picked up (WelcomeBack at boot) are scoped too.
	  B          closes the scope through its own path (the Focus close function or
	             Router:Close, which runs the screen's Close). With nothing open B passes on.
	  LB / RB    previous / next tab of the first Widgets.Tabs row in the scope.
	  Y          opens Monsters when nothing is open.
	  scrolling  the selected control is scrolled into view inside its ScrollingFrames.
	  cursor     PlayerGui.SelectionImageObject = a Theme.Colors.Gold outline.
	  legend     one line of button hints in the bottom-left corner of ctx.UI.Overlay, below
	             the toast lane and left of the HUD's bottom bar.
	A scope root with a string attribute GamepadLegend (Racing and Surf while a run is on) has
	no cursor: the selection is cleared so A and the D-pad reach the minigame, and the legend
	shows that string instead.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Focus = require(UI.Focus)
local Widgets = require(UI.Components.Widgets)
local Manifest = require(script.Parent.Parent.Manifest)

local New = Create.New
local C = Theme.Colors

local Gamepad = {
	Name = "Gamepad",
	Dependencies = {},
}

local PRIORITY = Enum.ContextActionPriority.High.Value
local SCROLL_MARGIN = 8 -- design px kept between a selected control and a scroll edge

-- Each legend is one whole string (translations match whole displayed strings).
local LEGEND_HUD = "Ⓨ Monsters"
local LEGEND_SCREEN = "Ⓐ Select · Ⓑ Close"
local LEGEND_TABS = "Ⓐ Select · Ⓑ Close · LB/RB Tabs"
local LEGEND_CHOICE = "Ⓐ Select"

-- Keyed by UserInputType name.
local POINTERS = {
	Touch = true,
	Keyboard = true,
	MouseButton1 = true,
	MouseButton2 = true,
	MouseButton3 = true,
	MouseMovement = true,
	MouseWheel = true,
}
local SCOPE_BEHAVIOURS = { "SelectionBehaviorUp", "SelectionBehaviorDown", "SelectionBehaviorLeft", "SelectionBehaviorRight" }
local ACTIONS = { "GamepadBack", "GamepadPrevTab", "GamepadNextTab", "GamepadMonsters" }

local ctx
local active = false
local cursor: Frame
local legend: Frame
local legendLabel: TextLabel
local conns = {} -- live only while active
local scoped = nil -- { root, saved } the root whose selection properties we changed
local scopeRoot = nil -- the scope seen by the last sync
local hudSelection = nil -- the selection before the first scope opened
local remembered = setmetatable({}, { __mode = "k" }) -- scope root -> last control selected in it
local savedImage = nil -- PlayerGui.SelectionImageObject before activation
local openOrder = {} -- Router screen names, most recently opened last
local syncQueued = false
local runShown = false -- the legend shows a screen's GamepadLegend

-- Scope ------------------------------------------------------------------------------------

local function screenRoot(name: string): GuiObject?
	return ctx.Router:Root(name)
end

local function openScreen(): string?
	local router = ctx.Router
	local current = router:Current()
	if current and router:IsOpen(current) then
		return current
	end
	for i = #openOrder, 1, -1 do
		if router:IsOpen(openOrder[i]) then
			return openOrder[i]
		end
	end
	for _, name in Manifest.Screens do
		if router:IsOpen(name) then
			return name
		end
	end
	return nil
end

-- Returns the scope root and either its Focus entry (modal) or its screen name.
local function currentScope(): (GuiObject?, any, string?)
	local modal = Focus.top()
	if modal then
		return modal.root, modal, nil
	end
	local name = openScreen()
	local root = name and screenRoot(name)
	if root then
		return root, nil, name
	end
	return nil, nil, nil
end

local function unscope()
	if not scoped then
		return
	end
	local root, saved = scoped.root, scoped.saved
	scoped = nil
	if root.Parent then
		for key, value in saved do
			root[key] = value
		end
	end
end

local function applyScope(root: GuiObject?)
	if scoped and scoped.root == root then
		return
	end
	unscope()
	if not root then
		return
	end
	local props: any = root
	local saved = { SelectionGroup = props.SelectionGroup }
	for _, key in SCOPE_BEHAVIOURS do
		saved[key] = props[key]
	end
	scoped = { root = root, saved = saved }
	props.SelectionGroup = true
	for _, key in SCOPE_BEHAVIOURS do
		props[key] = Enum.SelectionBehavior.Stop
	end
end

-- Focus ------------------------------------------------------------------------------------

local function valid(gui: Instance?, root: Instance?): boolean
	if not gui or not gui.Parent or not gui:IsA("GuiObject") or not (gui :: GuiObject).Selectable then
		return false
	end
	if root and not gui:IsDescendantOf(root) then
		return false
	end
	return Focus.isShown(gui)
end

local function firstControl(root: GuiObject): GuiObject?
	local best, bestOrder = nil, math.huge
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") and d.Selectable and d.SelectionOrder < bestOrder and Focus.isShown(d) then
			best, bestOrder = d, d.SelectionOrder
		end
	end
	return best
end

local function setSelection(gui: GuiObject?)
	if GuiService.SelectedObject ~= gui then
		GuiService.SelectedObject = gui
	end
end

-- Compares with the English last set, not the label (Localize shows it translated), so the
-- per-frame sync doesn't rewrite the label every frame.
local legendShown = ""
local function setLegend(text: string)
	if legendShown ~= text then
		legendShown = text
		legendLabel.Text = text
	end
end

-- `full` also re-reads the legend (a descendant walk); the per-frame pass skips it unless
-- the scope changed.
local function sync(full: boolean)
	if full then
		syncQueued = false
	end
	if not active then
		return
	end
	local root, modal = currentScope()
	local selected = GuiService.SelectedObject
	if not root then
		if scopeRoot then
			-- The last scope closed: hand the selection back to what it was before.
			local back = hudSelection
			hudSelection = nil
			scopeRoot = nil
			unscope()
			setSelection(if valid(back, nil) then back else nil)
		end
		setLegend(LEGEND_HUD)
		return
	end
	if not scopeRoot then
		hudSelection = if selected and not selected:IsDescendantOf(root) then selected else nil
	end
	full = full or scopeRoot ~= root
	scopeRoot = root
	applyScope(root)

	local runLegend = root:GetAttribute("GamepadLegend")
	if type(runLegend) == "string" then
		runShown = true
		setLegend(runLegend)
		setSelection(nil) -- the screen reads the pad itself; a selection would swallow A and the D-pad
		return
	end
	if full or runShown then
		runShown = false
		if modal and not modal.close then
			setLegend(LEGEND_CHOICE)
		elseif Widgets.FindTabs(root) then
			setLegend(LEGEND_TABS)
		else
			setLegend(LEGEND_SCREEN)
		end
	end

	if valid(selected, root) then
		remembered[root] = selected
		return
	end
	local target = remembered[root]
	if not valid(target, root) then
		target = firstControl(root)
	end
	setSelection(target)
end

local function queueSync()
	if active and not syncQueued then
		syncQueued = true
		task.defer(sync, true)
	end
end

-- Keeps the selected control inside the visible part of every ScrollingFrame around it.
local function scrollIntoView(gui: GuiObject?)
	if not gui then
		return
	end
	local scale = ctx.UI.Scale or 1
	local margin = SCROLL_MARGIN * scale
	local node = gui.Parent
	while node and node:IsA("GuiObject") do
		if node:IsA("ScrollingFrame") then
			local frame = node :: ScrollingFrame
			local offset = gui.AbsolutePosition - frame.AbsolutePosition
			local size, view = gui.AbsoluteSize, frame.AbsoluteSize
			local dx, dy = 0, 0
			if offset.Y < 0 then
				dy = offset.Y - margin
			elseif offset.Y + size.Y > view.Y then
				dy = offset.Y + size.Y - view.Y + margin
			end
			if offset.X < 0 then
				dx = offset.X - margin
			elseif offset.X + size.X > view.X then
				dx = offset.X + size.X - view.X + margin
			end
			if dx ~= 0 or dy ~= 0 then
				-- CanvasPosition is in the frame's own (unscaled) units; the layer's UIScale
				-- is what turns them into the absolute pixels measured above.
				local canvas = frame.CanvasPosition
				frame.CanvasPosition = Vector2.new(math.max(0, canvas.X + dx / scale), math.max(0, canvas.Y + dy / scale))
			end
		end
		node = node.Parent
	end
end

-- Buttons ------------------------------------------------------------------------------------

local function back(_, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local root, modal, name = currentScope()
	if not root then
		return Enum.ContextActionResult.Pass
	end
	if modal then
		if modal.close then
			task.spawn(modal.close)
		end
	elseif name then
		ctx.Router:Close(name)
	end
	return Enum.ContextActionResult.Sink
end

local function stepTabs(delta: number)
	return function(_, state: Enum.UserInputState)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local root = currentScope()
		local row = root and Widgets.FindTabs(root)
		if not row then
			return Enum.ContextActionResult.Pass
		end
		local selected = GuiService.SelectedObject
		local onTab = selected ~= nil and selected:IsDescendantOf(row.Root)
		local button = row:Step(delta)
		if onTab and button then
			setSelection(button)
		end
		queueSync()
		return Enum.ContextActionResult.Sink
	end
end

local function openMonsters(_, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if currentScope() ~= nil or not ctx.Router:Has("Monsters") then
		return Enum.ContextActionResult.Pass
	end
	ctx.Router:Open("Monsters")
	return Enum.ContextActionResult.Sink
end

-- Mode ---------------------------------------------------------------------------------------

local function activate()
	if active then
		return
	end
	active = true
	local playerGui = ctx.UI.Gui.Parent :: PlayerGui
	savedImage = playerGui.SelectionImageObject
	playerGui.SelectionImageObject = cursor
	legend.Visible = true
	ContextActionService:BindActionAtPriority("GamepadBack", back, false, PRIORITY, Enum.KeyCode.ButtonB)
	ContextActionService:BindActionAtPriority("GamepadPrevTab", stepTabs(-1), false, PRIORITY, Enum.KeyCode.ButtonL1)
	ContextActionService:BindActionAtPriority("GamepadNextTab", stepTabs(1), false, PRIORITY, Enum.KeyCode.ButtonR1)
	ContextActionService:BindActionAtPriority("GamepadMonsters", openMonsters, false, PRIORITY, Enum.KeyCode.ButtonY)
	table.insert(
		conns,
		RunService.Heartbeat:Connect(function()
			sync(false)
		end)
	)
	table.insert(
		conns,
		GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
			scrollIntoView(GuiService.SelectedObject)
			queueSync()
		end)
	)
	scopeRoot = nil
	hudSelection = nil
	sync(true)
end

local function deactivate()
	if not active then
		return
	end
	active = false
	for _, conn in conns do
		conn:Disconnect()
	end
	table.clear(conns)
	for _, name in ACTIONS do
		ContextActionService:UnbindAction(name)
	end
	unscope()
	scopeRoot = nil
	hudSelection = nil
	-- A selection only exists for pads; touch and mouse play starts from none.
	setSelection(nil)
	local playerGui = ctx.UI.Gui.Parent :: PlayerGui
	playerGui.SelectionImageObject = savedImage
	savedImage = nil
	legend.Visible = false
end

local function evaluate(lastType: Enum.UserInputType)
	if string.match(lastType.Name, "^Gamepad%d$") then
		activate()
	elseif POINTERS[lastType.Name] then
		deactivate()
	end
end

-- Lifecycle ------------------------------------------------------------------------------------

function Gamepad.Init(context)
	ctx = context
	cursor = New("Frame", {
		Name = "GamepadCursor",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-5, -5),
		Size = UDim2.new(1, 10, 1, 10),
	}, { Create.Corner(Theme.Radius.Button + 4), Create.Stroke(4, C.Gold, 0) })
	legend = New("Frame", {
		Name = "GamepadLegend",
		BackgroundColor3 = C.Dark,
		BackgroundTransparency = 0.35,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -4),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		Visible = false,
		Parent = ctx.UI.Overlay,
	}, { Create.Round(), Create.Padding(2, 10, 2, 10) })
	legendLabel = Create.Text({
		Name = "Keys",
		Text = LEGEND_HUD,
		TextSize = Theme.TextSize.Small,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextWrapped = false,
		Parent = legend,
	})
	-- Always connected (they only record and queue); nothing runs while dormant.
	ctx.Router.Opened:Connect(function(name: string)
		local at = table.find(openOrder, name)
		if at then
			table.remove(openOrder, at)
		end
		table.insert(openOrder, name)
		local root = screenRoot(name)
		if root then
			remembered[root] = nil -- a fresh open starts on its first control
		end
		queueSync()
	end)
	ctx.Router.Closed:Connect(queueSync)
	Focus.Changed:Connect(queueSync)
end

function Gamepad.Start()
	UserInputService.LastInputTypeChanged:Connect(evaluate)
	UserInputService.GamepadConnected:Connect(function()
		evaluate(UserInputService:GetLastInputType())
	end)
	UserInputService.GamepadDisconnected:Connect(function()
		if #UserInputService:GetConnectedGamepads() == 0 then
			deactivate()
		end
	end)
	-- Level-triggered start: a pad already in use at boot scopes whatever is open now.
	if UserInputService.GamepadEnabled then
		evaluate(UserInputService:GetLastInputType())
	end
end

return Gamepad
