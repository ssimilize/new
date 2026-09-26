--[[
	TitanInvasion (glow-up TT): the scheduled titan invasion, live in the world. Reads
	global.Titan / session.Titan; the Titan system is unchanged apart from what it publishes.
	Tuning: Config.Titan.Arena; place: Config.World.StampedeArena (the same arena as the
	Stampede - Controllers/StampedeArena is untouched and keeps running its own fights there).

	  banner    a bigger variant of the Stampede's call (Controllers/Stampede): "The Titan is
	            coming!" with a countdown, then "The Titan is here!". Opened by Titan.Starting /
	            Titan.Started, or from replicated state for a player who arrives mid-invasion;
	            closing it sticks until the next phase. Its button is Join until you have joined
	            (lobby or fight), then Cheer while the fight is on: taps batched into Titan.Cheer
	            every 0.5 s, the button showing your cheer meter (session.Titan.cheer).
	  bar       once the fight is live, the banner also shows the SHARED hp (global.Titan.hp /
	            maxHp - every server's damage drains the same pool) and
	            "{servers} servers · {players} players fighting" underneath, refreshed every
	            frame from replicated state.
	  giant     a stationary titan at the arena centre (Config.World.StampedeArena.center),
	            Config.Titan.Arena.bossScale big, from Config.Titan.Rotation; its own storm
	            (ColorCorrectionEffect "TitanStorm", stacked like the Stampede's, own tint).
	            Staggers at the Arena.staggers HP fractions and falls (faint) when the pool
	            empties, or roars and stands down if the clock runs out first.
	  cleanup   the giant, its bar, the storm and the banner are all destroyed
	            Arena.fallSeconds + Arena.leaveSeconds after the end.

	The giant and the storm are drawn in the main place only (the hub has no arena); the banner,
	joining and cheering work in both. No squads or cheer bolts are drawn for the titan (the
	Stampede's choreography reads global.Boss); the Stampede skips any period that overlaps an
	invasion (Systems/Boss), so the arena is the titan's alone meanwhile.

	Public: TitanInvasion:Stats() -> { phase, giant: boolean, storm: number }   (tests)
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Appearance = require(Shared.Logic.Appearance)
local Logic = require(Shared.Logic.StampedeArena) -- Crossed (staggers), Approach (storm fade)

local Client = script.Parent.Parent
local MonsterModel = require(Client.Visuals.MonsterModel)
local MonsterAnimator = require(Client.Visuals.MonsterAnimator)
local Vfx = require(Client.Visuals.Vfx)
local Quality = require(Client.Visuals.Quality)
local Audio = require(Client.Audio)
local Voices = require(Client.Audio.Voices)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Anim = require(Client.UI.Anim)
local Button = require(Client.UI.Components.Button)
local Widgets = require(Client.UI.Components.Widgets)
local MonsterIcon = require(Client.UI.Components.MonsterIcon)
local StoreKit = require(Client.UI.Components.StoreKit)

local New = Create.New
local C = Theme.Colors
local A = Config.Titan.Arena

local TitanInvasion = {
	Name = "TitanInvasion",
	Dependencies = { "Hud" },
}

local PURPLE = Color3.fromHex("#6A3FA0")
local STEP = 0.1

local ctx
local connections = {}
local clock = 0
local acc = 0
local folder: Folder? = nil

local current: GuiObject? = nil -- the banner (heads-up, then the live bar)
local stopCountdown: (() -> ())? = nil
local fill: Frame? = nil
local countLabel: TextLabel? = nil
local joinButton = nil -- Button: shown until you join (lobby and fight)
local cheerButton = nil -- Button: shown once you've joined and the fight is on
local bannerKey: string? = nil -- startsAt .. phase of the banner last opened (a close sticks)
local shownCheerText: string? = nil

local pendingTaps = 0
local requesting = false
local flushAcc = 0
local lastError = -math.huge
local mainPlace: boolean? = nil -- the giant and the storm only in the main place (not the hub)

local phase = "off" -- off | gather | fight | ending
local phaseAt = 0
local giant = nil -- { model, anim, def, height, gui, bar }
local lastFrac: number? = nil
local lastFlinch = -math.huge

local storm = { weight = 0, target = 0, flash = 0, nextLightning = 0, written = -1 }
local stormEffect: ColorCorrectionEffect? = nil
local stormTint = Color3.fromHex(A.storm.tint)

local centre = Vector3.new(Config.World.StampedeArena.center[1], Config.World.GroundY or 0, Config.World.StampedeArena.center[2])

-- ─── Helpers ────────────────────────────────────────────────────────────────────────

local function titanState()
	local t = ctx.Store:Get("global.Titan")
	return if type(t) == "table" then t else {}
end

local function titanDef(id: any)
	return Config.Titan.ById[id]
end

local function ensureFolder(): Folder
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "TitanInvasion"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

-- ─── Banner + shared bar ────────────────────────────────────────────────────────────

local function close()
	if stopCountdown then
		stopCountdown()
		stopCountdown = nil
	end
	local banner = current
	current, fill, countLabel = nil, nil, nil
	joinButton, cheerButton, shownCheerText = nil, nil, nil
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

local function session()
	local s = ctx.Store:Get("session.Titan")
	return if type(s) == "table" then s else {}
end

local function joinTitan()
	if not StoreKit.isUnlocked(ctx.Store, Config.Titan.Unlock) then
		return
	end
	local ok, err = ctx.Net:Request("Titan.Join")
	if ok then
		ctx:Toast("You joined the titan fight!", "success")
	else
		ctx:Toast(tostring(err), "error")
	end
end

-- Taps are batched into Titan.Cheer every 0.5 s (the action's caps, like Boss.Cheer).
local function cheer()
	pendingTaps = math.min(pendingTaps + 1, Config.Titan.MaxTapsPerRequest * 2)
	if cheerButton then
		Anim.pulse(cheerButton.Root, 0.08)
	end
end

local function flush()
	if pendingTaps <= 0 or requesting then
		return
	end
	local taps = math.min(pendingTaps, Config.Titan.MaxTapsPerRequest)
	pendingTaps -= taps
	requesting = true
	task.spawn(function()
		local ok, res = ctx.Net:Request("Titan.Cheer", { taps = taps })
		requesting = false
		if not ok then
			pendingTaps = 0
			if clock - lastError > 4 then
				lastError = clock
				ctx:Toast(tostring(res), "error")
			end
		end
	end)
end

-- Join until you have joined; then, while the fight is on, Cheer (with your cheer meter).
local function updateActions(g)
	if not current then
		return
	end
	local joined = session().joined == true
	if joinButton then
		joinButton:SetVisible(not joined)
		joinButton:SetDisabled(not StoreKit.isUnlocked(ctx.Store, Config.Titan.Unlock))
	end
	if cheerButton then
		local fighting = joined and g.state == "active"
		cheerButton:SetVisible(fighting)
		local meter = math.clamp(tonumber(session().cheer) or 0, 0, 1)
		local text = if meter > 0 then string.format("Cheer! %d%%", math.floor(meter * 100 + 0.5)) else "Cheer!"
		if fighting and text ~= shownCheerText then
			shownCheerText = text
			cheerButton:SetText(text)
		end
	end
end

local function buildBanner(payload: any, live: boolean)
	close()
	local def = titanDef(payload.titanId)
	local banner = New("Frame", {
		Name = "TitanBanner",
		BackgroundColor3 = if live then PURPLE else C.Dark,
		BackgroundTransparency = if live then 0 else 0.1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(640, if live then 130 else 76),
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
		Text = if live then "The Titan is here!" else "The Titan is coming!",
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
			return string.format("%s · %s left", if def then def.name else "Titan", Format.clock(left))
		end
		return string.format("The Titan starts in %s!", Format.clock(left))
	end)

	-- The action button (Join, then Cheer once the fight is on) sits right of the title; on the
	-- taller live banner it and Close keep to the top row, clear of the HP bar.
	local actionAnchor = if live then Vector2.new(1, 0) else Vector2.new(1, 0.5)
	local actionAt = if live then UDim2.new(1, -56, 0, 8) else UDim2.new(1, -54, 0.5, 0)
	joinButton = Button.new({
		Name = "Join",
		Text = "Join",
		Color = C.Green,
		Size = UDim2.fromOffset(110, 50),
		AnchorPoint = actionAnchor,
		Position = actionAt,
		ZIndex = 10,
		Parent = banner,
		OnClick = function()
			task.spawn(joinTitan)
		end,
	})
	if live then
		local track = New("Frame", {
			BackgroundColor3 = C.Dark,
			Position = UDim2.fromOffset(20, 78),
			Size = UDim2.new(1, -40, 0, 20),
			ZIndex = 9,
			Parent = banner,
		}, { Create.Corner(10), Create.Stroke(2, C.Gold, 0) })
		fill = New("Frame", { BackgroundColor3 = PURPLE, Size = UDim2.fromScale(1, 1), ZIndex = 9, Parent = track }, { Create.Corner(10) })
		countLabel = Create.Text({
			Text = "",
			TextSize = Theme.TextSize.Small,
			TextColor3 = C.White,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(20, 102),
			Size = UDim2.new(1, -40, 0, 22),
			ZIndex = 9,
			Parent = banner,
		})
		cheerButton = Button.new({
			Name = "Cheer",
			Text = "Cheer!",
			Color = C.Orange,
			Size = UDim2.fromOffset(110, 50),
			AnchorPoint = actionAnchor,
			Position = actionAt,
			Sound = false,
			ZIndex = 10,
			Parent = banner,
			OnClick = cheer,
		})
		cheerButton:SetVisible(false)
	end
	Button.new({
		Name = "Close",
		Text = "✕",
		Color = C.Gray,
		Size = UDim2.fromOffset(44, 44),
		TextSize = 22,
		AnchorPoint = actionAnchor,
		Position = if live then UDim2.new(1, -6, 0, 11) else UDim2.new(1, -6, 0.5, 0),
		ZIndex = 10,
		Parent = banner,
		OnClick = close,
	})
	updateActions(titanState())

	Anim.popIn(banner, 0.25)
end

-- Opens the banner for this invasion's phase once: from the Titan.Starting / Titan.Started
-- events, or from replicated state for a player who arrived after them. Closing it sticks
-- until the next phase.
local function showBanner(g, live: boolean)
	local key = tostring(g.startsAt) .. (if live then ":live" else ":soon")
	if key == bannerKey then
		return
	end
	bannerKey = key
	buildBanner(g, live)
end

local function updateBar(g)
	if not fill or not countLabel then
		return
	end
	local maxHp = tonumber(g.maxHp) or 0
	local hp = tonumber(g.hp) or 0
	local frac = if maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 0
	fill.Size = UDim2.fromScale(frac, 1)
	countLabel.Text = string.format("%d servers · %d players fighting", tonumber(g.servers) or 0, tonumber(g.players) or 0)
end

-- ─── The giant ──────────────────────────────────────────────────────────────────────

local function roar()
	if not giant then
		return
	end
	Audio.Play(Voices.Key(giant.def.line), { at = giant.model, pitch = A.roarPitch, volume = 1, near = 20, far = 300 })
end

local function destroyGiant()
	if giant then
		if giant.anim then
			giant.anim:Destroy()
		end
		if giant.model then
			giant.model:Destroy()
		end
		if giant.gui then
			giant.gui:Destroy()
		end
		giant = nil
	end
	lastFrac = nil
	lastFlinch = -math.huge
end

local function hpBar(model: Model, height: number, def)
	local anchor = model.PrimaryPart
	if not anchor then
		return nil, nil
	end
	local gui = New("BillboardGui", {
		Name = "TitanHp",
		Adornee = anchor,
		Size = UDim2.fromOffset(280, 56),
		StudsOffsetWorldSpace = Vector3.new(0, height * 0.6 + 4, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = ensureFolder(),
	})
	local name = Create.Text({
		Text = def.name,
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Header,
		TextColor3 = C.White,
		TextStrokeTransparency = 0.4,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = gui,
	})
	name.TextScaled = true
	local track = New("Frame", {
		BackgroundColor3 = C.Dark,
		Position = UDim2.fromOffset(10, 32),
		Size = UDim2.new(1, -20, 0, 16),
		Parent = gui,
	}, { Create.Corner(8), Create.Stroke(2, C.Gold, 0) })
	local barFill = New("Frame", { BackgroundColor3 = PURPLE, Size = UDim2.fromScale(1, 1), Parent = track }, { Create.Corner(8) })
	return gui, barFill
end

local function spawnGiant(g)
	local def = titanDef(g.titanId)
	if not def then
		return
	end
	local ok, ap = pcall(Appearance.Preview, def.line, 3, def.form, 4)
	if not ok or not ap then
		return
	end
	local ok2, model = pcall(MonsterModel.Build, ap, { anchored = true, scale = A.bossScale, vfx = not Quality.IsLow() })
	if not ok2 or not model then
		return
	end
	model.Parent = ensureFolder()
	Vfx.SetOwned(model, false)
	model:PivotTo(CFrame.lookAt(centre, centre - Vector3.xAxis))
	local height = tonumber(model:GetAttribute("Height")) or 24
	local anim = MonsterAnimator.new(model)
	anim:SetOwn(false)
	local gui, barFill = hpBar(model, height, def)
	giant = { model = model, anim = anim, def = def, height = height, gui = gui, bar = barFill }
	lastFrac = nil
	roar()
end

local function stagger()
	if not giant then
		return
	end
	giant.anim:Play("hurt")
	lastFlinch = clock
	Vfx.Burst("evolve", centre + Vector3.new(0, giant.height * 0.5, 0), { scale = 4, elements = { giant.def.element } })
	roar()
	ctx:Sound("Crit")
end

local function stepGiant(g)
	if not giant then
		return
	end
	local maxHp = tonumber(g.maxHp) or 0
	local hp = tonumber(g.hp) or 0
	if maxHp <= 0 then
		return
	end
	local frac = math.clamp(hp / maxHp, 0, 1)
	if lastFrac and frac < lastFrac then
		if Logic.Crossed(lastFrac, frac, A.staggers) then
			stagger()
		elseif clock - lastFlinch >= A.flinchGap and giant.anim:GetState() == "idle" then
			lastFlinch = clock
			giant.anim:Play("hurt")
		end
	end
	if giant.bar and frac ~= lastFrac then
		giant.bar.Size = UDim2.fromScale(frac, 1)
	end
	lastFrac = frac
end

local function startEnd(fell: boolean)
	phase = "ending"
	phaseAt = clock
	if giant then
		if fell then
			giant.anim:Play("faint")
			Vfx.Burst("rebirth", centre + Vector3.new(0, giant.height * 0.4, 0), { scale = 4 })
			ctx:Sound("KO")
			roar()
		else
			giant.anim:Play("happy")
			roar()
		end
		if giant.bar then
			giant.bar.Size = UDim2.fromScale(if fell then 0 else 1, 1)
		end
	end
end

-- ─── Storm ──────────────────────────────────────────────────────────────────────────

local function stepStorm(dt: number)
	local S = A.storm
	storm.weight = Logic.Approach(storm.weight, storm.target, dt, S.fade)
	storm.flash = math.max(0, storm.flash - dt * 1.5)
	local w = storm.weight
	if w <= 0 and storm.flash <= 0 then
		if stormEffect then
			stormEffect:Destroy()
			stormEffect = nil
			storm.written = -1
		end
		return
	end
	if not stormEffect then
		local e = Instance.new("ColorCorrectionEffect")
		e.Name = "TitanStorm"
		e.Parent = Lighting
		stormEffect = e
	end
	local key = math.floor(w * 200) + math.floor(storm.flash * 200) * 1000
	if key == storm.written then
		return
	end
	storm.written = key
	local e = stormEffect :: ColorCorrectionEffect
	e.TintColor = C.White:Lerp(stormTint, w)
	e.Brightness = S.brightness * w + storm.flash
	e.Contrast = S.contrast * w
	e.Saturation = S.saturation * w
end

local function lightning(g)
	if g.state ~= "active" or storm.weight < 1 or Quality.IsLow() or clock < storm.nextLightning then
		return
	end
	local every = A.lightningEvery
	storm.nextLightning = clock + every[1] + math.random() * (every[2] - every[1])
	storm.flash = 0.35
	ctx.Bus:Publish("Weather.Lightning", 0.8)
end

-- ─── Main loop ──────────────────────────────────────────────────────────────────────

local function clearAll()
	destroyGiant()
	close()
	phase = "off"
end

local function onStarting(payload)
	if type(payload) ~= "table" then
		return
	end
	ctx:Sound("StampedeSoon")
	showBanner(payload, false)
	ctx.Bus:Publish("Hud.Flash", "Titan")
end

local function onStarted(payload)
	if type(payload) ~= "table" then
		return
	end
	ctx:Sound("BossHorn")
	showBanner(payload, true)
	ctx.Bus:Publish("Hud.Flash", "Titan")
end

local function step()
	if mainPlace == nil and ctx.Store.Ready then
		mainPlace = ctx.Store:Get("global.TradingHub.mode") ~= "hub"
	end
	local g = titanState()
	local live = g.state == "lobby" or g.state == "active"
	if live then
		showBanner(g, g.state == "active")
	end
	updateActions(g)
	flushAcc += STEP
	if flushAcc >= 0.5 then
		flushAcc = 0
		flush()
	end
	storm.target = if live and mainPlace then 1 else 0
	lightning(g)

	if g.state == "active" then
		phase = "fight"
		if not giant and mainPlace then
			spawnGiant(g)
		end
		stepGiant(g)
		updateBar(g)
	elseif phase == "fight" then
		startEnd((tonumber(g.hp) or 1) <= 0 and (tonumber(g.maxHp) or 0) > 0)
	elseif phase == "ending" then
		if clock >= phaseAt + A.fallSeconds + A.leaveSeconds then
			clearAll()
		end
	elseif not live and phase ~= "off" and phase ~= "ending" then
		clearAll()
	elseif live and phase == "off" then
		phase = "gather"
	end
end

-- ─── Public ─────────────────────────────────────────────────────────────────────────

function TitanInvasion:Stats()
	return { phase = phase, giant = giant ~= nil, storm = storm.weight }
end

function TitanInvasion.Init(context)
	ctx = context
	ctx.Net:On("Titan.Starting", onStarting)
	ctx.Net:On("Titan.Started", onStarted)
end

function TitanInvasion.Start()
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			clock += dt
			stepStorm(dt)
			acc += dt
			if acc >= STEP then
				acc = 0
				step()
			end
		end)
	)
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function TitanInvasion.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	clearAll()
	if stormEffect then
		stormEffect:Destroy()
		stormEffect = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return TitanInvasion
