--[[
	Celebrate: the celebration kit (rewards that travel) and the moment queue.

	Sizes come from Logic/Celebration: small < medium < big < huge (coins are judged against
	the ranch's income, gems and items by steps). Everything is drawn on ctx.UI.Feedback.

	  Celebrate:Reward(items, opts?) -> size
	      items = { Reward } ({ kind, amount, id? }). Coins, gems and items fly in an arc from
	      opts.from (a GuiObject, a BasePart / Vector3 / CFrame projected through the camera,
	      or a Vector2 in Feedback-layer units; default the screen centre) into their HUD
	      counter or button (Hud:GetTarget), which pulses as each lands, with rising coin ticks.
	      A "+N" pops at the origin. The counter is held (Hud:HoldCounter) and counts up when
	      the first icon lands, faster for small payouts, slower for big ones. Big and huge add
	      the screen part (Play). opts: size? (forces a size), minSize?, hold? (from :Hold),
	      label? (false = no "+N", when the caller already shows one).
	  Celebrate:Hold(kinds) -> handle          freeze HUD counters ("coins" | "gems" | "food")
	      before a request so the new balance waits for the flight; handle:Release() on failure
	  Celebrate:Play(size, opts?)              the screen-wide part: coin shower and confetti
	                                           (big+), a light camera shake and FOV kick (huge),
	                                           gamepad rumble, the size's sound (opts.sound: a
	                                           moment's own sting instead, false = none)
	  Celebrate:CountUp(label, from, to, size, format) -> stop()
	  Celebrate:Shockwave(gui, color?)         a ring expanding from a GuiObject (level-ups)
	  Celebrate:Slam(gui, color?)              a star slams onto a GuiObject (star-ups)
	  Celebrate:Flourish(gui?)                 a small sparkle at a GuiObject (default top-centre)
	  Celebrate:Moment(key, fn, opts?)         an in-world moment (a Vfx burst): runs now, or is
	      held while a Router screen, a Focus modal (hatch reveal, evolution popup, dialogs) or
	      the hatch reveal covers the world, and runs once the view has been clear for a beat.
	      A newer moment with the same key replaces a held one. opts: settle? (seconds to let a
	      popup that opens with the same event appear first), flourish? (false = no stand-in
	      sparkle while held), at? (GuiObject for the sparkle).
	  Celebrate:IsCovered() -> boolean  ·  Celebrate:Pending() -> number (held moments)

	Settings.lowGraphics (Anim.enabled == false): counters still update and a short "+N" cue and
	sound play; no flying swarms, shower, confetti, shake, FOV kick, shockwaves or sparkles.
	At most MAX_FLYING icons and MAX_FX shower / confetti pieces exist at once; every piece is
	destroyed when it lands.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HapticService = game:GetService("HapticService")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Logic.Format)
local Celebration = require(Shared.Logic.Celebration)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Focus = require(UI.Focus)
local Icon = require(UI.Components.Icon)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)

local New = Create.New
local C = Theme.Colors

local Celebrate = {
	Name = "Celebrate",
	Dependencies = { "Hud" },
}

local MAX_FLYING = 24
local MAX_FX = 70
local STREAK_WINDOW = 3 -- seconds between coin payouts that still count as a streak
local TICK_GAP = 0.06 -- at most one coin tick this often
local SETTLE = 0.35 -- a popup opened by the same event gets this long to appear
local POLL = 0.25
local CLEAR_SECONDS = 0.5 -- the view must be clear this long before a held moment plays
local MAX_HELD = 6
local MAX_AGE = 180 -- held moments older than this are dropped

-- Reward kind -> HUD counter that is held while it flies, and the HUD target it flies into.
local COUNTER = { coins = "coins", gems = "gems", food = "food" }
local TARGET = {
	coins = "coins",
	gems = "gems",
	food = "food",
	treats = "food",
	egg = "incubator",
	monster = "monster",
	accessory = "monster",
	decor = "Ranch",
	xp = "level",
}
local CONFETTI = { C.Pink, C.Blue, C.Gold, C.Green, C.Purple, C.Orange }

local ctx
local fxLayer: Frame
local particles = {} -- { gui, t0, dur, update(alpha), done?, kind }
local stepConn: RBXScriptConnection? = nil
local flying = 0
local fxCount = 0
local streak, lastCoinAt, lastTickAt = 0, -math.huge, -math.huge
local held = {} -- { { key, fn, at } } oldest first
local watching = false
local shakeState = { bound = false, untilAt = 0, length = 1, magnitude = 0 }
local fovState = { base = nil :: number?, token = 0 }

-- Geometry ----------------------------------------------------------------------------

local function layerSize(): Vector2
	return fxLayer.AbsoluteSize / math.max(ctx.UI.Scale or 1, 0.01)
end

local function toLayer(screen: Vector2): Vector2
	return (screen - fxLayer.AbsolutePosition) / math.max(ctx.UI.Scale or 1, 0.01)
end

-- A point in Feedback-layer units for a GuiObject, a world position or a Vector2.
local function pointOf(from: any): Vector2?
	if typeof(from) == "Instance" then
		if from:IsA("GuiObject") then
			if from.AbsoluteSize.X <= 0 and from.AbsoluteSize.Y <= 0 then
				return nil
			end
			return toLayer(from.AbsolutePosition + from.AbsoluteSize / 2)
		elseif from:IsA("BasePart") then
			from = from.Position
		elseif from:IsA("Attachment") then
			from = from.WorldPosition
		else
			return nil
		end
	end
	if typeof(from) == "CFrame" then
		from = from.Position
	end
	if typeof(from) == "Vector3" then
		local camera = workspace.CurrentCamera
		if not camera then
			return nil
		end
		local point, onScreen = camera:WorldToViewportPoint(from)
		if not onScreen then
			return nil
		end
		return toLayer(Vector2.new(point.X, point.Y))
	end
	if typeof(from) == "Vector2" then
		return from
	end
	return nil
end

local function centre(): Vector2
	local size = layerSize()
	return Vector2.new(size.X / 2, size.Y * 0.45)
end

local function hud()
	return ctx:GetController("Hud")
end

-- The particle loop: one RenderStepped connection drives every flying piece. -----------

local function step()
	local now = os.clock()
	for i = #particles, 1, -1 do
		local p = particles[i]
		local alpha = (now - p.t0) / p.dur
		if alpha >= 0 then
			p.gui.Visible = true
			p.update(math.min(alpha, 1))
		end
		if alpha >= 1 or p.gui.Parent == nil then
			table.remove(particles, i)
			if p.kind == "fly" then
				flying -= 1
			else
				fxCount -= 1
			end
			p.gui:Destroy()
			if p.done then
				task.spawn(p.done)
			end
		end
	end
	if #particles == 0 and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

local function add(p)
	p.gui.Visible = false
	table.insert(particles, p)
	if p.kind == "fly" then
		flying += 1
	else
		fxCount += 1
	end
	if not stepConn then
		stepConn = RunService.RenderStepped:Connect(step)
	end
end

local function place(gui: GuiObject, point: Vector2)
	gui.Position = UDim2.fromOffset(point.X, point.Y)
end

local function bezier(a: Vector2, b: Vector2, c: Vector2, t: number): Vector2
	local u = 1 - t
	return a * (u * u) + b * (2 * u * t) + c * (t * t)
end

-- Sounds ------------------------------------------------------------------------------

local function playTick(key: string)
	local now = os.clock()
	if now - lastTickAt < TICK_GAP then
		return
	end
	lastTickAt = now
	ctx:Sound(key)
end

-- Rumble (only when the last input came from a pad) ----------------------------------

local function rumble(strength: number)
	if strength <= 0 then
		return
	end
	local last = UserInputService:GetLastInputType()
	if not string.match(last.Name, "^Gamepad%d$") then
		return
	end
	local ok, supported = pcall(function()
		return HapticService:IsVibrationSupported(last) and HapticService:IsMotorSupported(last, Enum.VibrationMotor.Large)
	end)
	if not ok or not supported then
		return
	end
	HapticService:SetMotor(last, Enum.VibrationMotor.Large, math.clamp(strength, 0, 1))
	task.delay(0.2 + strength * 0.25, function()
		HapticService:SetMotor(last, Enum.VibrationMotor.Large, 0)
	end)
end

-- Camera: shake and FOV kick (huge) ---------------------------------------------------

local SHAKE_BINDING = "CelebrateShake"

local function cameraShake(magnitude: number, seconds: number)
	local camera = workspace.CurrentCamera
	-- A scripted camera (plot focus, cutscenes) would keep the offset; only shake the follow cam.
	if magnitude <= 0 or not camera or camera.CameraType == Enum.CameraType.Scriptable then
		return
	end
	shakeState.magnitude = math.max(shakeState.magnitude, magnitude)
	shakeState.untilAt = os.clock() + seconds
	shakeState.length = seconds
	if shakeState.bound then
		return
	end
	shakeState.bound = true
	RunService:BindToRenderStep(SHAKE_BINDING, Enum.RenderPriority.Camera.Value + 1, function()
		local left = shakeState.untilAt - os.clock()
		local cam = workspace.CurrentCamera
		if left <= 0 or not cam or cam.CameraType == Enum.CameraType.Scriptable then
			RunService:UnbindFromRenderStep(SHAKE_BINDING)
			shakeState.bound = false
			shakeState.magnitude = 0
			return
		end
		local m = shakeState.magnitude * left / shakeState.length
		cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * 2 * m, (math.random() - 0.5) * 2 * m, 0)
	end)
end

local function fovKick(degrees: number)
	local camera = workspace.CurrentCamera
	if degrees <= 0 or not camera then
		return
	end
	fovState.token += 1
	local token = fovState.token
	-- Remember the resting FOV once, so overlapping kicks always settle back on it.
	local base = fovState.base or camera.FieldOfView
	fovState.base = base
	Anim.tween(camera, { FieldOfView = base + degrees }, 0.12, Enum.EasingStyle.Quad)
	task.delay(0.12, function()
		if token ~= fovState.token then
			return
		end
		Anim.tween(camera, { FieldOfView = base }, 0.45, Enum.EasingStyle.Quad)
		task.delay(0.5, function()
			if token == fovState.token then
				fovState.base = nil
			end
		end)
	end)
end

-- Screen pieces -----------------------------------------------------------------------

local function shower(count: number)
	local size = layerSize()
	for _ = 1, count do
		if fxCount >= MAX_FX then
			return
		end
		local px = math.random(20, 60)
		local gui = Icon.new("coin", px)
		gui.AnchorPoint = Vector2.new(0.5, 0.5)
		gui.Parent = fxLayer
		local x = math.random() * size.X
		local fromY = -40 - math.random() * 160
		local sway = (math.random() - 0.5) * 80
		local spin = (math.random() - 0.5) * 720
		add({
			kind = "fx",
			gui = gui,
			t0 = os.clock() + math.random() * 0.35,
			dur = 1.1 + math.random() * 0.5,
			update = function(a)
				place(gui, Vector2.new(x + math.sin(a * 6) * sway * 0.3 + sway * a, fromY + (size.Y + 120 - fromY) * a * a))
				gui.Rotation = spin * a
			end,
		})
	end
end

local function confetti(count: number)
	local size = layerSize()
	for i = 1, count do
		if fxCount >= MAX_FX then
			return
		end
		local gui = New("Frame", {
			Name = "Confetti",
			BackgroundColor3 = CONFETTI[(i % #CONFETTI) + 1],
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(math.random(6, 10), math.random(10, 16)),
			Parent = fxLayer,
		})
		-- Two bursts from the lower corners that arc up and flutter down.
		local left = i % 2 == 0
		local start = Vector2.new(if left then 0 else size.X, size.Y * 0.75)
		local peak = Vector2.new(
			if left then size.X * (0.1 + math.random() * 0.45) else size.X * (0.45 + math.random() * 0.45),
			size.Y * (0.05 + math.random() * 0.25)
		)
		local land = Vector2.new(peak.X + (math.random() - 0.5) * 160, size.Y + 30)
		local spin = (math.random() - 0.5) * 1080
		add({
			kind = "fx",
			gui = gui,
			t0 = os.clock() + math.random() * 0.15,
			dur = 1.5 + math.random() * 0.6,
			update = function(a)
				local point
				if a < 0.3 then
					point = bezier(start, (start + peak) / 2 - Vector2.new(0, 60), peak, a / 0.3)
				else
					point = peak:Lerp(land, ((a - 0.3) / 0.7) ^ 1.6)
				end
				place(gui, point + Vector2.new(math.sin(a * 14) * 10, 0))
				gui.Rotation = spin * a
			end,
		})
	end
end

-- "+1.2K" at the origin. Also the one cue left in low graphics.
local function amountLabel(point: Vector2, text: string, color: Color3)
	local label = Create.Text({
		Name = "Amount",
		Text = text,
		TextColor3 = color,
		TextSize = Theme.TextSize.Title,
		Stroke = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(point.X, point.Y - 10),
		Size = UDim2.fromOffset(220, 40),
		ZIndex = 5,
		Parent = fxLayer,
	})
	if Anim.enabled then
		Anim.popIn(label, 0.2)
		Anim.tween(
			label,
			{ Position = UDim2.fromOffset(point.X, point.Y - 60), TextTransparency = 1 },
			1.1,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			Anim.tween(stroke, { Transparency = 1 }, 1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end
	task.delay(1.15, function()
		label:Destroy()
	end)
end

local function iconFor(item, px: number): GuiObject
	if item.kind == "egg" then
		return MonsterIcon.egg(if type(item.id) == "string" then item.id else "meadow", px)
	elseif item.kind == "monster" or item.kind == "decor" or item.kind == "accessory" then
		return Icon.new("star", px)
	end
	return Icon.new(StoreKit.iconFor(tostring(item.kind or "coins")), px)
end

-- Flies `count` icons from `origin` to `target`; onLand(i, count) runs as each one lands.
local function fly(item, origin: Vector2, target: Vector2, count: number, onLand: (number, number) -> ())
	local room = math.max(0, MAX_FLYING - flying)
	local n = math.min(count, room)
	if n <= 0 then
		onLand(1, 1)
		return
	end
	for i = 1, n do
		local gui = iconFor(item, 30)
		gui.AnchorPoint = Vector2.new(0.5, 0.5)
		gui.ZIndex = 6
		gui.Parent = fxLayer
		local angle = math.random() * math.pi * 2
		local scatter = origin + Vector2.new(math.cos(angle), math.sin(angle)) * (18 + math.random() * 40)
		local control = (scatter + target) / 2 + Vector2.new((math.random() - 0.5) * 160, -(120 + math.random() * 80))
		local scale = Anim.scaleOf(gui)
		add({
			kind = "fly",
			gui = gui,
			t0 = os.clock() + (i - 1) * 0.05,
			dur = 0.75 + math.random() * 0.2,
			update = function(a)
				if a < 0.22 then
					local e = 1 - (1 - a / 0.22) ^ 2
					place(gui, origin:Lerp(scatter, e))
					scale.Scale = 0.5 + 0.7 * e
				else
					local t = ((a - 0.22) / 0.78) ^ 1.7
					place(gui, bezier(scatter, control, target, t))
					scale.Scale = 1.2 - 0.5 * t
				end
			end,
			done = function()
				onLand(i, n)
			end,
		})
	end
end

-- Public ------------------------------------------------------------------------------

function Celebrate:Hold(kinds: { string })
	local open: { [string]: boolean } = {}
	local handle = {
		open = open,
		-- Lets go of one counter (counting up over `seconds`), or of every one still held.
		Release = function(_, kind: string?, seconds: number?)
			local h = hud()
			for k in open do
				if kind == nil or k == kind then
					open[k] = nil
					if h then
						h:ReleaseCounter(k, seconds)
					end
				end
			end
		end,
	}
	local h = hud()
	for _, kind in kinds do
		if COUNTER[kind] and not open[kind] and h then
			open[kind] = true
			h:HoldCounter(kind)
		end
	end
	return handle
end

-- opts.sound: a Config.Sounds key to play instead of the size's own (false: none), for a moment
-- that has its own sting (Rebirth).
function Celebrate:Play(size: string, opts: { sound: (string | false)? }?)
	local plan = Celebration.Plan(size, not Anim.enabled)
	local sound = plan.sound
	if opts and opts.sound ~= nil then
		sound = opts.sound
	end
	if sound then
		ctx:Sound(sound)
	end
	rumble(plan.rumble)
	shower(plan.shower)
	confetti(plan.confetti)
	if plan.shake > 0 then
		cameraShake(plan.shake, 0.45)
	end
	fovKick(plan.fov)
end

function Celebrate:Reward(items: { any }?, opts: { [string]: any }?): string
	local options = opts or {}
	local list = {}
	for _, item in items or {} do
		if type(item) == "table" and type(item.kind) == "string" and (tonumber(item.amount) or 0) > 0 then
			table.insert(list, item)
		end
	end
	local income = StoreKit.num(ctx.Store, "session.Ranch.income")
	local size = options.size or Celebration.Size(list, income)
	if options.minSize then
		size = Celebration.Max(size, options.minSize)
	end
	local plan = Celebration.Plan(size, not Anim.enabled)
	local origin = pointOf(options.from) or centre()

	-- Hold every counter this reward moves (reusing a hold taken before the request).
	local kinds = {}
	for _, item in list do
		if COUNTER[item.kind] then
			table.insert(kinds, item.kind)
		end
	end
	local hold = options.hold or self:Hold(kinds)
	for kind in hold.open do
		if not table.find(kinds, kind) then
			hold:Release(kind)
		end
	end
	if #list == 0 then
		return size
	end

	local now = os.clock()
	local h = hud()
	local labelled = false
	for index, item in list do
		if index > 4 then
			break
		end
		local amount = tonumber(item.amount) or 0
		if options.label ~= false and not labelled and (item.kind == "coins" or item.kind == "gems") then
			labelled = true
			amountLabel(origin, "+" .. Format.short(amount), if item.kind == "coins" then C.Gold else C.Pink)
		end
		if item.kind == "coins" then
			streak = if now - lastCoinAt <= STREAK_WINDOW then streak + 1 else 1
			lastCoinAt = now
		end
		local targetGui = h and TARGET[item.kind] and h:GetTarget(TARGET[item.kind])
		local target = targetGui and pointOf(targetGui)
		local count = if item.kind == "coins"
			then plan.icons
			elseif item.kind == "gems" then math.max(2, math.ceil(plan.icons * 0.6))
			elseif COUNTER[item.kind] then 3
			else math.min(math.max(1, math.floor(amount)), 3)
		if plan.icons <= 0 then
			count = 0
		end
		local counter = COUNTER[item.kind]
		local currentStreak = streak
		local function land(i: number, n: number)
			if counter then
				if i == 1 then
					hold:Release(counter, plan.countTime)
				end
				if h then
					h:PulseCounter(counter)
				end
			elseif targetGui then
				Anim.pulse(targetGui, 0.12)
			end
			if item.kind == "coins" then
				playTick(Celebration.TickKey(i, n, currentStreak))
			elseif item.kind == "gems" then
				playTick("GemTick")
			elseif i == 1 then
				ctx:Sound("ItemPop")
			end
		end
		if target and count > 0 then
			fly(item, origin, target, count, land)
		else
			land(1, 1)
		end
	end
	if plan.icons > 0 then
		ctx:Sound("Whoosh")
	end
	self:Play(size)
	return size
end

function Celebrate:CountUp(label: TextLabel, from: number, to: number, size: string, format: (number) -> string): () -> ()
	local plan = Celebration.Plan(size, false)
	return Anim.countUp(label, from, to, plan.countTime + 0.3, format)
end

function Celebrate:Shockwave(gui: GuiObject?, color: Color3?)
	local point = gui and pointOf(gui)
	if not Anim.enabled or not point or fxCount >= MAX_FX then
		return
	end
	local ring = New("Frame", {
		Name = "Shockwave",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20),
		ZIndex = 4,
		Parent = fxLayer,
	}, { Create.Round(), Create.Stroke(5, color or C.Gold, 0) })
	place(ring, point)
	local stroke = ring:FindFirstChildOfClass("UIStroke")
	local reach = math.max((gui :: GuiObject).AbsoluteSize.X / math.max(ctx.UI.Scale or 1, 0.01), 120) + 140
	add({
		kind = "fx",
		gui = ring,
		t0 = os.clock(),
		dur = 0.55,
		update = function(a)
			local e = 1 - (1 - a) ^ 3
			ring.Size = UDim2.fromOffset(20 + reach * e, 20 + reach * e * 0.6)
			if stroke then
				stroke.Transparency = a
				stroke.Thickness = 5 * (1 - a) + 1
			end
		end,
	})
end

function Celebrate:Slam(gui: GuiObject?, color: Color3?)
	local point = gui and pointOf(gui)
	if not point then
		return
	end
	ctx:Sound("StarUp")
	local star = Icon.new("star", 96)
	star.Name = "Slam"
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.ZIndex = 7
	star.Parent = fxLayer
	place(star, point)
	if not Anim.enabled then
		task.delay(0.6, function()
			star:Destroy()
		end)
		return
	end
	local scale = Anim.scaleOf(star)
	scale.Scale = 3
	Anim.tween(scale, { Scale = 1 }, 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.16, function()
		self:Shockwave(gui, color or C.Orange)
		Anim.shake(gui :: GuiObject)
		rumble(0.4)
		Anim.tween(scale, { Scale = 0.01 }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.55, function()
			star:Destroy()
		end)
	end)
end

function Celebrate:Flourish(gui: GuiObject?)
	if not Anim.enabled then
		return
	end
	local point = (gui and pointOf(gui)) or Vector2.new(layerSize().X / 2, 90)
	for i = 1, 8 do
		if fxCount >= MAX_FX then
			return
		end
		local spark = New("Frame", {
			Name = "Sparkle",
			BackgroundColor3 = if i % 2 == 0 then C.Gold else C.White,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = 45,
			Size = UDim2.fromOffset(12, 12),
			ZIndex = 6,
			Parent = fxLayer,
		}, { Create.Stroke(2, C.Ink, 0.2) })
		local angle = (i / 8) * math.pi * 2
		local away = Vector2.new(math.cos(angle), math.sin(angle)) * (46 + (i % 3) * 14)
		add({
			kind = "fx",
			gui = spark,
			t0 = os.clock(),
			dur = 0.55,
			update = function(a)
				local e = 1 - (1 - a) ^ 2
				place(spark, point + away * e)
				local s = 12 * (1 - a * a)
				spark.Size = UDim2.fromOffset(s, s)
			end,
		})
	end
	self:Shockwave(gui, C.Gold)
end

function Celebrate:IsCovered(): boolean
	if ctx.Router:Current() ~= nil or Focus.top() ~= nil then
		return true
	end
	local hatchery = ctx:GetController("Hatchery")
	return hatchery ~= nil and hatchery:IsShowing()
end

function Celebrate:Pending(): number
	return #held
end

local function run(key: string, fn: () -> ())
	task.spawn(function()
		local ok, err = xpcall(fn, debug.traceback)
		if not ok then
			warn(string.format("[Celebrate] moment %s failed: %s", key, tostring(err)))
		end
	end)
end

local function watch()
	if watching then
		return
	end
	watching = true
	task.spawn(function()
		local clearFor = 0
		while #held > 0 do
			task.wait(POLL)
			local now = os.clock()
			for i = #held, 1, -1 do
				if now - held[i].at > MAX_AGE then
					table.remove(held, i)
				end
			end
			if Celebrate:IsCovered() then
				clearFor = 0
			else
				clearFor += POLL
			end
			if clearFor >= CLEAR_SECONDS and #held > 0 then
				local entry = table.remove(held, 1)
				run(entry.key, entry.fn)
				clearFor = 0 -- the next held moment waits another beat
			end
		end
		watching = false
	end)
end

function Celebrate:Moment(key: string, fn: () -> (), opts: { [string]: any }?)
	local options = opts or {}
	local function hold()
		for i, entry in held do
			if entry.key == key then
				table.remove(held, i)
				break
			end
		end
		table.insert(held, { key = key, fn = fn, at = os.clock() })
		while #held > MAX_HELD do
			table.remove(held, 1)
		end
		if options.flourish ~= false then
			self:Flourish(options.at)
		end
		watch()
	end
	if self:IsCovered() then
		hold()
		return
	end
	task.delay(options.settle or SETTLE, function()
		if #held == 0 and not self:IsCovered() then
			run(key, fn)
		else
			hold()
		end
	end)
end

function Celebrate.Init(context)
	ctx = context
	fxLayer = New("Frame", {
		Name = "Celebrate",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5, -- over the feedback stack
		Parent = ctx.UI.Feedback,
	})
end

function Celebrate.Start() end

return Celebrate
