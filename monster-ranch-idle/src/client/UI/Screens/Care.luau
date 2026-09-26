--[[
	Care (glow-up Q): the care menu for one of your own pen monsters, opened by tapping it in the
	pen (Controllers/Care) with params { id }. Non-modal, so the monster stays in view.

	  Menu      name, bond hearts (Parts/BondBadge), the next heart, the income bonus, three care
	            gestures with their bond status, the tricks it has learned (Community.Trick) and
	            Details (MonsterDetail).
	  Gestures  about five seconds each on a full-screen pad over the world (Logic/Bond.Gesture):
	              Pet    press and hold
	              Brush  drag back and forth
	              Play   tap each time it bounces (the ring pulses on the beat)
	            A gamepad, or Space on a keyboard, gets the hold version of all three (A / R2 /
	            Space held, ContextActionService). Finishing plays the reaction with hearts
	            (World.PlayCare, Voices) and, when that kind is ready for this monster, asks
	            Bond.Care; otherwise it just says when bond grows again. It never fails.
	Opened with no id it picks your first pen monster (or says how to open it).
	Low graphics: no beat pulse animation; World halves the hearts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Bond)
local Formulas = require(Shared.Logic.Formulas)
local Format = require(Shared.Logic.Format)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Focus = require(UI.Focus)
local Button = require(UI.Components.Button)
local BondBadge = require(script.Parent.Parts.BondBadge)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Bond

local Care = { Name = "Care" }

local CARD_W, CARD_H = 600, 262
local HOLD_ACTION = "CareHold"
local HOLD_PRIORITY = 3000 -- above the Gamepad controller's bindings while a gesture runs

local function glyph(text: string): TextLabel
	local label = Create.Text({ Text = text, TextScaled = true, Size = UDim2.fromOffset(22, 22) })
	label:SetAttribute("Localize", false)
	return label
end

local function isPad(kind): boolean
	return kind ~= nil and string.sub(kind.Name, 1, 7) == "Gamepad"
end

function Care.Build(ctx)
	local root = New("Frame", { Name = "Care", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })

	local currentId: string? = nil
	local gesture = nil
	local gestureKind = nil
	local clock = 0
	local lastQuarter = 0
	local busy = false
	local heartbeat: RBXScriptConnection? = nil
	local observers = {}
	local stopGesture: () -> ()

	-- The pad over the world that reads the gesture.
	local pad = New("TextButton", {
		Name = "CarePad",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = root,
	})
	local beat = New("Frame", {
		Name = "Beat",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(96, 96),
		BackgroundColor3 = C.Pink,
		BackgroundTransparency = 0.35,
		Visible = false,
		Parent = pad,
	}, { Create.Corner(48), Create.Stroke(3) })
	Create.Text({ Text = "Tap!", TextSize = Theme.TextSize.Header, Size = UDim2.fromScale(1, 1), Stroke = true, Parent = beat })

	local card = New("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = C.Panel,
		Parent = root,
	}, { Create.Corner(18), Create.Stroke(4) })

	local title = Create.Text({
		Name = "Title",
		Text = "",
		TextSize = Theme.TextSize.Header,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.fromOffset(CARD_W - 90, 30),
		Parent = card,
	})
	title:SetAttribute("Localize", false)
	local hearts = Create.Text({
		Name = "Hearts",
		Text = "",
		TextSize = Theme.TextSize.Header,
		TextColor3 = C.Pink,
		Stroke = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 40),
		Size = UDim2.fromOffset(260, 28),
		Parent = card,
	})
	hearts:SetAttribute("Localize", false)
	local status = Create.Text({
		Name = "Status",
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(284, 40),
		Size = UDim2.fromOffset(CARD_W - 300, 28),
		Parent = card,
	})
	local bonus = Create.Text({
		Name = "Bonus",
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.Green,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 70),
		Size = UDim2.fromOffset(CARD_W - 36, 22),
		Parent = card,
	})

	local function close()
		ctx.Router:Close("Care")
	end
	Button.new({
		Name = "Close",
		Text = "✕",
		Color = C.Red,
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Parent = card,
		OnClick = close,
	})

	-- Menu -------------------------------------------------------------------------------------
	local menu = New("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 96),
		Size = UDim2.fromOffset(CARD_W - 36, CARD_H - 104),
		Parent = card,
	})
	local empty = Create.Text({
		Name = "Empty",
		Text = "Tap one of your pen monsters to care for it.",
		TextSize = Theme.TextSize.Body,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = menu,
	})

	local kindButtons, kindLabels = {}, {}
	local startGesture
	for i, kind in Cfg.Kinds do
		local x = (i - 1) * 190
		kindButtons[kind.id] = Button.new({
			Name = "Care_" .. kind.id,
			Text = kind.name,
			Color = C.Pink,
			Size = UDim2.fromOffset(178, 56),
			Position = UDim2.fromOffset(x, 0),
			Icon = glyph(kind.glyph),
			Parent = menu,
			OnClick = function()
				startGesture(kind)
			end,
		})
		kindLabels[kind.id] = Create.Text({
			Name = "Status_" .. kind.id,
			Text = "",
			TextSize = Theme.TextSize.Small,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(x, 58),
			Size = UDim2.fromOffset(178, 20),
			Parent = menu,
		})
	end

	local trickButtons = {}
	for i, trick in Cfg.Tricks do
		trickButtons[trick.id] = Button.new({
			Name = "Trick_" .. trick.id,
			Text = trick.name,
			Color = C.Purple,
			Size = UDim2.fromOffset(130, 48),
			Position = UDim2.fromOffset((i - 1) * 138, 100),
			TextSize = Theme.TextSize.Small,
			Icon = glyph(trick.glyph),
			Parent = menu,
			OnClick = function()
				if not currentId or busy then
					return
				end
				busy = true
				local ok, err = ctx.Net:Request("Community.Trick", { id = currentId, trick = trick.id })
				busy = false
				if not ok then
					ctx:Toast(tostring(err), "error")
				end
			end,
		})
	end
	local details = Button.new({
		Name = "Details",
		Text = "Details",
		Color = C.Blue,
		Size = UDim2.fromOffset(140, 48),
		Position = UDim2.fromOffset(CARD_W - 36 - 140, 100),
		TextSize = Theme.TextSize.Small,
		Parent = menu,
		OnClick = function()
			local id = currentId
			close()
			if id then
				ctx.Router:Open("MonsterDetail", { id = id })
			end
		end,
	})

	-- Gesture view -----------------------------------------------------------------------------
	local run = New("Frame", {
		Name = "Gesture",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 96),
		Size = UDim2.fromOffset(CARD_W - 36, CARD_H - 104),
		Visible = false,
		Parent = card,
	})
	local hint = Create.Text({
		Name = "Hint",
		Text = "",
		TextSize = Theme.TextSize.Body,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = run,
	})
	local bar = New("Frame", {
		Name = "Bar",
		BackgroundColor3 = C.PanelDeep,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = run,
	}, { Create.Corner(12), Create.Stroke(2) })
	local fill = New("Frame", {
		Name = "Fill",
		BackgroundColor3 = C.Pink,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	}, { Create.Corner(12) })
	Button.new({
		Name = "Stop",
		Text = "Stop",
		Color = C.Gray,
		Size = UDim2.fromOffset(140, 48),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		TextSize = Theme.TextSize.Small,
		Parent = run,
		OnClick = function()
			if gesture then
				stopGesture()
			end
		end,
	})

	-- State ------------------------------------------------------------------------------------
	local function monster()
		local list = ctx.Store:Get("profile.Monsters.list")
		return if currentId and type(list) == "table" then list[currentId] else nil
	end

	local function firstPenMonster(): string?
		local list = ctx.Store:Get("profile.Monsters.list")
		local ids = {}
		for id, m in if type(list) == "table" then list else {} do
			if type(m) == "table" and m.loc == "pen" then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		return ids[1]
	end

	local function refresh()
		local m = monster()
		empty.Visible = m == nil
		for _, b in kindButtons do
			b:SetVisible(m ~= nil)
		end
		for _, label in kindLabels do
			label.Visible = m ~= nil
		end
		details:SetVisible(m ~= nil)
		if not m or not currentId then
			title.Text = ""
			hearts.Text = ""
			status.Text = ""
			bonus.Text = ""
			for _, b in trickButtons do
				b:SetVisible(false)
			end
			return
		end
		local info = BondBadge.of(ctx, currentId)
		title.Text = Formulas.DisplayName(m)
		hearts.Text = BondBadge.row(info.hearts)
		status.Text = if info.need > 0 then string.format("Next heart: %d/%d", info.into, info.need) else "Best friends forever!"
		bonus.Text = if info.pct > 0 then string.format("+%d%% coins from this monster", math.floor(info.pct * 100 + 0.5)) else ""
		local now = ctx:Now()
		for _, kind in Cfg.Kinds do
			local ready, left = Logic.Ready(info.entry, kind.id, now, Cfg)
			kindLabels[kind.id].Text = if ready then "Adds bond" else string.format("Bond again in %s", Format.duration(left))
		end
		for _, trick in Cfg.Tricks do
			local b = trickButtons[trick.id]
			local learned = info.hearts >= trick.bond
			b:SetVisible(true)
			b:SetText(if learned then trick.name else string.format("%s ♥%d", trick.name, trick.bond))
			b:SetDisabled(not learned)
		end
	end

	local function setGestureView(on: boolean)
		menu.Visible = not on
		run.Visible = on
		pad.Visible = on
	end

	local function unbindHold()
		pcall(function()
			ContextActionService:UnbindAction(HOLD_ACTION)
		end)
	end

	function stopGesture()
		gesture = nil
		gestureKind = nil
		beat.Visible = false
		unbindHold()
		setGestureView(false)
		refresh()
	end

	local function finish(kind, id: string)
		local m = monster()
		local name = if m then Formulas.DisplayName(m) else "Your monster"
		local lowGraphics = ctx.Store:Get("profile.Settings.lowGraphics") == true
		local world = ctx:GetController("World")
		if world and world.PlayCare then
			world.PlayCare(id, kind.state, if lowGraphics then 6 else 12)
		end
		ctx:Sound("Pet")
		local info = BondBadge.of(ctx, id)
		local ready, left = Logic.Ready(info.entry, kind.id, ctx:Now(), Cfg)
		if not ready then
			ctx:Toast(string.format("%s loved that! Bond grows again in %s", name, Format.duration(left)), "info")
			return
		end
		local ok, res = ctx.Net:Request("Bond.Care", { id = id, kind = kind.id })
		if not ok then
			ctx:Toast(tostring(res), "error")
			return
		end
		local now = if type(res) == "table" then tonumber(res.hearts) or 0 else 0
		if now > info.hearts then
			local celebrate = ctx:GetController("Celebrate")
			if celebrate then
				celebrate:Play("small")
			end
			ctx:Toast(string.format("%s is now at %d bond hearts!", name, now), "reward")
			local learned = type(res) == "table" and Config.Community.TrickById[res.learned]
			if learned then
				ctx:Toast(string.format("%s learned a new trick: %s!", name, learned.name), "reward")
			end
		else
			ctx:Toast(string.format("%s loved that! +1 bond", name), "success")
		end
	end

	local function onFrame(dt: number)
		clock += dt
		if not gesture then
			return
		end
		gesture:Step(clock)
		local progress = gesture:Progress()
		fill.Size = UDim2.fromScale(progress, 1)
		if beat.Visible and Anim.enabled then
			local phase = gesture:Beat(clock)
			local size = 80 + 36 * phase * phase
			beat.Size = UDim2.fromOffset(size, size)
		end
		local quarter = math.floor(progress * 4)
		if quarter > lastQuarter and quarter < 4 then
			lastQuarter = quarter
			ctx:Sound("Pet")
			local world = ctx:GetController("World")
			if world and world.PlayCare and currentId then
				world.PlayCare(currentId, "happy", 3)
			end
		end
		if gesture:Done() then
			local kind, id = gestureKind, currentId
			stopGesture()
			if kind and id then
				task.spawn(finish, kind, id)
			end
		end
	end

	local function onHold(_name, state, _input)
		if not gesture or not gestureKind then
			return Enum.ContextActionResult.Pass
		end
		if not gesture.hold then
			gesture = Logic.Gesture.new(gestureKind.id, Cfg, true)
			gesture:Step(clock)
			beat.Visible = false
			hint.Text = "Hold the button to care"
		end
		if state == Enum.UserInputState.Begin then
			gesture:Down(clock)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			gesture:Up(clock)
		end
		return Enum.ContextActionResult.Sink
	end

	startGesture = function(kind)
		if not currentId or not monster() then
			return
		end
		local hold = isPad(UserInputService:GetLastInputType())
		gesture = Logic.Gesture.new(kind.id, Cfg, hold)
		gesture:Step(clock)
		gestureKind = kind
		lastQuarter = 0
		fill.Size = UDim2.fromScale(0, 1)
		hint.Text = if hold then "Hold the button to care" else kind.hint
		beat.Visible = not hold and kind.id == "play"
		beat.Size = UDim2.fromOffset(96, 96)
		setGestureView(true)
		unbindHold()
		ContextActionService:BindActionAtPriority(
			HOLD_ACTION,
			onHold,
			false,
			HOLD_PRIORITY,
			Enum.KeyCode.ButtonA,
			Enum.KeyCode.ButtonR2,
			Enum.KeyCode.Space
		)
	end

	local function pointer(input: InputObject): boolean
		local t = input.UserInputType
		return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
	end
	pad.InputBegan:Connect(function(input)
		if gesture and pointer(input) then
			gesture:Down(clock, input.Position.X)
		end
	end)
	pad.InputChanged:Connect(function(input)
		local t = input.UserInputType
		if gesture and (t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch) then
			gesture:Move(clock, input.Position.X)
		end
	end)
	pad.InputEnded:Connect(function(input)
		if gesture and pointer(input) then
			gesture:Up(clock)
		end
	end)

	local tick = 0
	return {
		Root = root,
		Modal = false,
		Open = function(params)
			local id = type(params) == "table" and params.id or nil
			currentId = if type(id) == "string" then id else firstPenMonster()
			gesture = nil
			setGestureView(false)
			refresh()
			Focus.push(card, close)
			for _, conn in observers do
				conn:Disconnect()
			end
			observers = {
				ctx.Store:Observe("profile.Bond", function()
					if not gesture then
						refresh()
					end
				end),
				ctx.Store:Observe("profile.Monsters.list", function()
					if not gesture then
						refresh()
					end
				end),
			}
			if heartbeat then
				heartbeat:Disconnect()
			end
			tick = 0
			heartbeat = RunService.Heartbeat:Connect(function(dt)
				onFrame(dt)
				tick += dt
				if tick >= 1 and not gesture then
					tick = 0
					refresh() -- the cooldown countdowns
				end
			end)
		end,
		Close = function()
			gesture = nil
			gestureKind = nil
			unbindHold()
			Focus.remove(card)
			for _, conn in observers do
				conn:Disconnect()
			end
			observers = {}
			if heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end
		end,
	}
end

return Care
