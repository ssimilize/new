--[[
	Stampede: the server-wide call to the Stampede, for everyone on the server.

	  Boss.Starting { bossId, startsAt }          a banner at the top of ctx.UI.Feedback: the boss,
	                                              "The Stampede starts in 0:59!" counting down, and
	                                              a Join button (opens the Boss screen)
	  Boss.Started  { bossId, startsAt, endsAt }  the horn (BossHorn), a rumble and the banner again:
	                                              "The Stampede is here!" with the time left

	The banner sits on the Feedback layer so it shows over any open screen, and leaves by itself
	after BANNER_SECONDS (or on its close button). It is skipped while the Boss screen is open
	(that screen already shows the fight). Players below the Boss unlock see it without the Join
	button. The HUD's Stampede card keeps the countdown and glows while the fight runs (Hud).

	Public: Stampede:Banner() -> GuiObject?   the banner on screen, if any (tests)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Appearance = require(Shared.Logic.Appearance)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Button = require(UI.Components.Button)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)

local New = Create.New
local C = Theme.Colors

local Stampede = {
	Name = "Stampede",
	Dependencies = { "Hud" },
}

local BANNER_SECONDS = 9
local RED = Color3.fromHex("#C0573E")

local ctx
local current: GuiObject? = nil
local stopCountdown: (() -> ())? = nil
local token = 0

local function bossDef(bossId: any)
	for _, def in Config.Boss.Rotation do
		if def.id == bossId then
			return def
		end
	end
	return nil
end

local function close()
	token += 1
	if stopCountdown then
		stopCountdown()
		stopCountdown = nil
	end
	local banner = current
	current = nil
	if not banner then
		return
	end
	if not Anim.enabled then
		banner:Destroy()
		return
	end
	Anim.tween(Anim.scaleOf(banner), { Scale = 0.01 }, 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.2, function()
		banner:Destroy()
	end)
end

local function openBoss()
	close()
	if ctx.Router:Has("Boss") then
		ctx.Router:Open("Boss")
	end
end

-- live = false: the heads-up (counts down to startsAt); true: the fight (counts down to endsAt).
local function show(payload, live: boolean)
	if type(payload) ~= "table" or ctx.Router:IsOpen("Boss") then
		return
	end
	close()
	token += 1
	local mine = token
	local def = bossDef(payload.bossId)
	local banner = New("Frame", {
		Name = "StampedeBanner",
		BackgroundColor3 = if live then RED else C.Dark,
		BackgroundTransparency = if live then 0 else 0.1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(600, 76),
		ZIndex = 8,
		Parent = ctx.UI.Feedback,
	}, { Create.Corner(Theme.Radius.Card), Create.Stroke(3, C.Gold, 0) })
	current = banner

	local iconHolder = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(60, 60),
		ZIndex = 9,
		Parent = banner,
	})
	if def then
		local ok, ap = pcall(Appearance.Preview, def.line, 3, def.form, 4)
		if ok and ap then
			MonsterIcon.new(ap, 60).Parent = iconHolder
		end
	end
	local title = Create.Text({
		Text = if live then "The Stampede is here!" else "The Stampede is coming!",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Header,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(80, 6),
		Size = UDim2.new(1, -250, 0, 32),
		ZIndex = 9,
		Parent = banner,
	})
	title.TextScaled = true
	local line = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Body,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(80, 40),
		Size = UDim2.new(1, -250, 0, 28),
		ZIndex = 9,
		Parent = banner,
	})
	local target = tonumber(if live then payload.endsAt else payload.startsAt) or ctx:Now()
	stopCountdown = Widgets.Countdown(line, function()
		return target
	end, function(left)
		if live then
			return string.format("%s · %s left", if def then def.name else "Stampede", Format.clock(left))
		end
		return string.format("The Stampede starts in %s!", Format.clock(left))
	end)

	if StoreKit.isUnlocked(ctx.Store, Config.Boss.Unlock) then
		Button.new({
			Name = "Join",
			Text = "Join",
			Color = C.Green,
			Size = UDim2.fromOffset(110, 50),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -54, 0.5, 0),
			ZIndex = 10,
			Parent = banner,
			OnClick = openBoss,
		})
	end
	Button.new({
		Name = "Close",
		Text = "✕",
		Color = C.Gray,
		Size = UDim2.fromOffset(44, 44),
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		ZIndex = 10,
		Parent = banner,
		OnClick = close,
	})

	Anim.popIn(banner, 0.25)
	task.delay(BANNER_SECONDS, function()
		if token == mine then
			close()
		end
	end)
end

local function onStarting(payload)
	ctx:Sound("StampedeSoon")
	show(payload, false)
	ctx.Bus:Publish("Hud.Flash", "Stampede")
end

local function onStarted(payload)
	ctx:Sound("BossHorn")
	show(payload, true)
	ctx.Bus:Publish("Hud.Flash", "Stampede")
	local kit = ctx:GetController("Celebrate")
	if kit then
		kit:Play("medium") -- the rumble on a pad
	end
end

function Stampede:Banner(): GuiObject?
	return current
end

function Stampede.Init(context)
	ctx = context
	ctx.Net:On("Boss.Starting", onStarting)
	ctx.Net:On("Boss.Started", onStarted)
	ctx.Router.Opened:Connect(function(name)
		if name == "Boss" then
			close()
		end
	end)
end

function Stampede.Start() end

return Stampede
