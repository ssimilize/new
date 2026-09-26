--[[
	Parts/BattleStage (glow-up V): a BattleReplay (ARCHITECTURE.md §7) drawn on the 3D battle stage
	(Visuals/BattleArena) through one CameraDirector stage shot. Callers go through Parts/Battle,
	which picks this or the 2D viewer (Parts/BattleReplay); the options are the 2D viewer's.

		local viewer = BattleStage.play(ctx, opts, fallback)   -- fallback() -> the 2D viewer
		viewer.Destroy()
		viewer.Mode() -> "3d" | "2d"        "2d" once it has handed over to the fallback
		viewer.Arena() -> BattleArena?      while the stage is up (tests)
		viewer.Speed() -> 1 | 2

	Events play in order at the 2D viewer's pace: the attacker plays its attack clip and lunges, a
	bolt in its element flies (Config/VfxSprites), the target flinches with a hit flash and a
	spark, floating numbers show damage (crits bigger), heals, shields and stuns, KO'd monsters
	faint, HP bars sit over heads. Specials and element multipliers get the 2D viewer's callouts.
	Camera cuts come from Logic/BattleStage.Shots (wide, over the shoulder on big hits, a close-up
	on the finishing blow; CameraDirector cuts instead of gliding under reduced motion). The
	result: winners cheer (a cry), Victory / Defeat sting, Celebrate:Play on a win with rewards,
	then the shared result card (Parts/BattleResult) over the stage.

	A tap anywhere toggles 2x speed; Skip jumps to the result (the HP bars and KOs fast-forward).
	The root is named "BattleReplay" in ctx.UI.Top like the 2D viewer's (Soundscape's battle music,
	specs). The Router's screen layer is hidden while the stage shows and given back after. If the
	shot cannot start (CameraDirector) or the stage fails to build, the 2D viewer takes over; if the
	camera is taken back mid-fight (PhotoMode, a mount), the result card shows on a plain backdrop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Tuning = require(Shared.Config.BattleStage)
local Plan = require(Shared.Logic.BattleStage)
local Celebration = require(Shared.Logic.Celebration)

local Client = script.Parent.Parent.Parent.Parent
local UI = Client.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Button = require(UI.Components.Button)
local Quality = require(Client.Visuals.Quality)
local BattleArena = require(Client.Visuals.BattleArena)
local Voices = require(Client.Audio.Voices)
local BattleResult = require(script.Parent.BattleResult)

local New = Create.New
local C = Theme.Colors
local UP = Vector3.new(0, 1, 0)

local BattleStage = {}

-- Stage shots running now: a Retry / Next from the result card starts the next fight while the
-- last shot is still letting go of the camera, and should get the stage too.
local holding = 0

function BattleStage.Holding(): boolean
	return holding > 0
end

local function sideCentre(arena, side: string): Vector3?
	local sum, n = Vector3.zero, 0
	for _, view in arena.order do
		if view.side == side then
			sum += view.pos
			n += 1
		end
	end
	return if n > 0 then sum / n else nil
end

function BattleStage.play(ctx, opts, fallback: () -> any)
	local replay = opts.replay or { units = {}, events = {} }
	local units = replay.units or {}
	local events = replay.events or {}
	local win = if opts.win ~= nil then opts.win else replay.win == true
	local director = ctx:GetController("CameraDirector")
	local low = Quality.IsLow()

	local api = {}
	local alive = true
	local skipped = false
	local resultShown = false
	local speed = 1
	local inner = nil -- the 2D viewer after a hand-over
	local arena = nil
	local screensWere: boolean? = nil

	-- Chrome ------------------------------------------------------------------------------------

	local root = New("TextButton", {
		Name = "BattleReplay",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromHex("#1D2B22"),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 45,
		Parent = ctx.UI.Top,
	})
	root:SetAttribute("Stage3D", true)
	-- The cut into the stage hides behind a quick fade from dark.
	local fade = New("Frame", {
		Name = "Fade",
		BackgroundColor3 = Color3.fromHex("#101812"),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = root,
	})
	Create.Text({
		Text = opts.title or "Battle",
		TextSize = Theme.TextSize.Header + 2,
		Stroke = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.new(0.56, 0, 0, 34),
		ZIndex = 5,
		Parent = root,
	})
	local turnLabel = Create.Text({
		Text = "Turn 1",
		TextSize = Theme.TextSize.Body,
		Stroke = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, 18),
		Size = UDim2.fromOffset(200, 28),
		ZIndex = 5,
		Parent = root,
	})
	local skipButton = Button.new({
		Text = "Skip ▸▸",
		Color = C.Gray,
		Size = UDim2.fromOffset(130, 48),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 10),
		ZIndex = 6,
		Parent = root,
	})
	local speedChip = Create.Text({
		Name = "Speed",
		Text = "2× speed",
		TextSize = Theme.TextSize.Body,
		TextColor3 = C.Gold,
		Stroke = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 20, 1, -44),
		Size = UDim2.fromOffset(200, 28),
		ZIndex = 5,
		Visible = false,
		Parent = root,
	})
	local hint = Create.Text({
		Name = "Hint",
		Text = "Tap to speed up",
		TextSize = Theme.TextSize.Body,
		Stroke = true,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(320, 28),
		ZIndex = 5,
		Parent = root,
	})
	local callout = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Title,
		TextColor3 = C.Gold,
		Stroke = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(0.8, 0, 0, 40),
		ZIndex = 10,
		Parent = root,
	})
	callout.TextTransparency = 1

	local function hideScreens()
		local layer = ctx.UI.Screens
		if layer and screensWere == nil then
			screensWere = layer.Visible
			layer.Visible = false
		end
	end
	local function restoreScreens()
		local layer = ctx.UI.Screens
		if layer and screensWere ~= nil then
			layer.Visible = screensWere
		end
		screensWere = nil
	end
	hideScreens()

	local function teardown()
		if arena then
			arena:Destroy()
			arena = nil
		end
	end

	local function destroy()
		if inner then
			inner.Destroy()
			return
		end
		if not alive then
			return
		end
		alive = false
		root:Destroy()
		restoreScreens()
		teardown()
	end
	api.Destroy = destroy

	function api.Mode(): string
		return if inner then "2d" else "3d"
	end
	function api.Arena()
		return arena
	end
	function api.Speed(): number
		return speed
	end

	-- The 2D viewer takes over (nothing of the stage stays behind).
	local function handOver()
		if not alive or inner then
			return
		end
		alive = false
		root:Destroy()
		restoreScreens()
		teardown()
		inner = fallback()
	end

	root.Activated:Connect(function()
		if resultShown or not alive then
			return
		end
		speed = if speed == 1 then 2 else 1
		speedChip.Visible = speed == 2
		hint.Visible = false
		if arena then
			arena:SetSpeed(speed)
		end
	end)

	-- Replay state ------------------------------------------------------------------------------

	local state = Plan.NewState(units)
	local shots = Plan.Shots(events, units, Tuning)
	local step = Plan.Step(#events, Tuning.pace)
	local names = {}
	for _, unit in units do
		names[unit.key] = unit.name or "?"
	end

	local function refreshBar(key: string?)
		if not (arena and key) then
			return
		end
		local frac = (state.hp[key] or 0) / (state.maxHp[key] or 1)
		arena:SetBar(key, frac, (state.shield[key] or 0) > 0, state.stunned[key] == true)
	end

	local calloutToken = 0
	local function showCallout(text: string, color: Color3)
		if skipped then
			return
		end
		calloutToken += 1
		local token = calloutToken
		callout.Text = text
		callout.TextColor3 = color
		callout.TextTransparency = 0
		Anim.pulse(callout, 0.2)
		task.delay(0.9, function()
			if token == calloutToken and callout.Parent then
				Anim.tween(callout, { TextTransparency = 1 }, 0.25)
			end
		end)
	end

	local function floater(key: string?, ev, priority: boolean?)
		if not (arena and key) then
			return
		end
		local f = Plan.Floater(ev, Format.short(math.floor(ev.amount or 0)))
		if f then
			arena:Number(key, f.text, C[f.color] or C.White, f.big, priority)
		end
	end

	local function sleep(seconds: number)
		local left = seconds
		local last = os.clock()
		while alive and not skipped and left > 0 do
			RunService.Heartbeat:Wait() -- a frame (task.wait() would not advance the clock in the Lune mock)
			local now = os.clock()
			left -= (now - last) * speed
			last = now
		end
	end

	-- Camera ------------------------------------------------------------------------------------

	local handle = nil
	local held = false -- this viewer's shot counts in `holding`
	local cam = Tuning.camera

	local function look(eye: Vector3, at: Vector3, seconds: number?)
		if handle and not handle:Aborted() then
			handle:Look(eye, at, seconds)
		end
	end

	local function wide(seconds: number?)
		local w = cam.wide
		look(arena.center + Vector3.new(0, w.height, w.distance), arena.center + UP * w.look, seconds)
	end

	local function cut(shot)
		if not arena then
			return
		end
		if shot.kind == "wide" then
			wide(cam.glide)
			return
		end
		local actor, target = arena:Get(shot.actor), arena:Get(shot.target)
		if shot.kind == "shoulder" and actor and target then
			local s = cam.shoulder
			local flat = Vector3.new(target.pos.X - actor.pos.X, 0, target.pos.Z - actor.pos.Z)
			local dir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(1, 0, 0)
			local side = Vector3.new(-dir.Z, 0, dir.X) -- to the attacker's right, toward the wide camera
			if side.Z < 0 then
				side = -side
			end
			local eye = actor.pos - dir * (s.back * math.max(1, actor.size)) + side * s.side + UP * (s.height * math.max(1, actor.size))
			look(eye, target.pos + UP * (target.height * 0.5), cam.glide)
		elseif shot.kind == "close" and target then
			local c = cam.close
			local toward = if actor then Vector3.new(actor.pos.X - target.pos.X, 0, 0) else Vector3.zero
			local away = (Vector3.new(0, 0, 1) + (if toward.Magnitude > 1e-3 then toward.Unit * 0.6 else Vector3.zero)).Unit
			local reach = c.distance * math.max(1, target.height / 3)
			look(target.pos + away * reach + UP * c.height, target.pos + UP * (target.height * 0.5), cam.glide)
		end
	end

	-- One event -----------------------------------------------------------------------------------

	local function play(ev)
		turnLabel.Text = "Turn " .. tostring(ev.turn or 1)
		local kind = ev.kind
		local target = if ev.target then ev.target else ev.actor
		local subject = Plan.Apply(state, ev)
		if Plan.Attacks(kind) then
			arena:Attack(ev.actor, target)
			local flight = math.min(Tuning.pace.bolt, step * 0.9)
			if target ~= ev.actor then
				arena:Bolt(ev.actor, target, flight)
			end
			if kind == "special" then
				local skill = ev.skill and Config.Species.Skills[ev.skill]
				showCallout(string.format("%s used %s!", names[ev.actor] or "?", if skill then skill.name else "a special"), C.Gold)
			end
			if ev.mult and ev.mult > 1 then
				showCallout(string.format("Super effective ×%s", tostring(ev.mult)), C.Green)
			elseif ev.mult and ev.mult < 1 then
				showCallout(string.format("Resisted ×%s", tostring(ev.mult)), C.Gray)
			end
			local attacker = arena:Get(ev.actor)
			local element = attacker and attacker.element
			arena:After(flight, function()
				if kind ~= "miss" then
					arena:Impact(target, Plan.Hurts(kind), element)
					if kind == "hit" or kind == "crit" then
						ctx:Sound(if kind == "crit" then "Crit" else "Hit")
					end
				end
				floater(target, ev, kind == "crit" or kind == "special" or kind == "stun")
				refreshBar(subject)
			end)
			return
		end
		if kind == "reflect" then
			arena:Impact(target, true, nil)
			floater(target, ev)
		elseif kind == "heal" or kind == "regen" then
			floater(subject, ev)
			if subject then
				arena:Spark(subject, nil, "hearts")
			end
			ctx:Sound("Heal", if kind == "regen" then { volume = 0.6 } else nil)
		elseif kind == "shield" or kind == "stunned" then
			floater(subject, ev)
		elseif kind == "faint" then
			arena:Faint(subject)
			floater(subject, ev, true)
			ctx:Sound("KO")
		end
		refreshBar(subject)
	end

	-- Result --------------------------------------------------------------------------------------

	local function celebrate()
		if not win or not (opts.rewards and #opts.rewards > 0) then
			return
		end
		local celebrateController = ctx:GetController("Celebrate")
		if not celebrateController then
			return
		end
		pcall(function()
			local income = tonumber(ctx.Store:Get("session.Ranch.income")) or 0
			local size = Celebration.Size(opts.rewards, income)
			local hasBoss = false
			for _, unit in units do
				hasBoss = hasBoss or unit.boss == true
			end
			if hasBoss then
				size = Celebration.Max(size, "big")
			end
			celebrateController:Play(size, { sound = false })
		end)
	end

	local function showResult(plain: boolean?)
		if resultShown or not alive then
			return
		end
		resultShown = true
		skipButton:SetVisible(false)
		hint.Visible = false
		speedChip.Visible = false
		callout.TextTransparency = 1
		if plain then
			root.BackgroundTransparency = 0.04
		end
		-- The dark band keeps the card readable over a bright stage.
		fade.BackgroundTransparency = 0.55
		BattleResult.show(ctx, root, opts, win, {
			close = function()
				destroy()
				if opts.onClose then
					task.spawn(opts.onClose)
				end
			end,
			alive = function()
				return alive
			end,
		})
		if not plain and arena then
			local winners = if win then "ally" else "enemy"
			local cried = false
			for _, view in arena.order do
				if view.side == winners and not state.fainted[view.key] then
					arena:Cheer(view.key)
					if not cried then
						cried = true
						pcall(Voices.Cry, view.model, "happy")
					end
				end
			end
			local centre = sideCentre(arena, winners)
			if centre then
				local sign = if winners == "ally" then -1 else 1
				look(arena.center + Vector3.new(sign * 3, 7, 20), centre + UP * 2, cam.glide)
			end
			celebrate()
		end
	end

	-- Jump to the end: every remaining event lands on the bars and the KO'd lie down.
	local function fastForward(from: number)
		for j = from, #events do
			Plan.Apply(state, events[j])
		end
		if not arena then
			return
		end
		arena:ClearEffects()
		for _, view in arena.order do
			refreshBar(view.key)
			if state.fainted[view.key] and view.animator:GetState() ~= "faint" then
				arena:Faint(view.key)
			end
		end
	end

	local nextEvent = 1
	local function skip()
		if skipped or not alive then
			return
		end
		skipped = true
		fastForward(nextEvent)
		nextEvent = #events + 1
		showResult(arena == nil)
	end
	skipButton:SetOnClick(skip)

	-- The shot ------------------------------------------------------------------------------------

	local function run(h)
		handle = h
		if not alive or resultShown then
			return -- closed or skipped before the shot began: nothing to show
		end
		held = true
		holding += 1
		local ok, err = pcall(function()
			arena = BattleArena.new({
				theme = Plan.Theme(Tuning, opts.stage),
				units = units,
				placement = Plan.Placement(units, Tuning),
				low = low,
			})
			arena:Build()
		end)
		if not ok then
			warn("[BattleStage] the stage failed, showing the 2D viewer: " .. tostring(err))
			handOver()
			return
		end
		if not alive then
			teardown()
			return
		end
		arena:SetSpeed(speed)
		for _, unit in units do
			refreshBar(unit.key)
		end
		wide(0)
		if Anim.enabled then
			Anim.tween(fade, { BackgroundTransparency = 1 }, 0.3)
		else
			fade.BackgroundTransparency = 1
		end
		task.delay(3, function()
			if hint.Parent then
				hint.Visible = false
			end
		end)
		sleep(Tuning.pace.lead)
		while alive and not skipped and nextEvent <= #events do
			if h:Aborted() then
				break
			end
			local i = nextEvent
			local ev = events[i]
			nextEvent += 1
			if shots[i] then
				cut(shots[i])
			end
			local played, problem = pcall(play, ev)
			if not played then
				warn("[BattleStage] event failed: " .. tostring(problem))
			end
			sleep(Plan.Pause(ev, step, Tuning.pace))
		end
		if h:Aborted() and alive then
			-- The camera went back to the player: finish on a plain card, the stage goes now.
			skipped = true
			fastForward(nextEvent)
			nextEvent = #events + 1
			teardown()
			showResult(true)
			return
		end
		if alive and not skipped then
			sleep(Tuning.pace.tail)
			skip()
		end
		-- Hold the stage behind the result card until it closes (or the camera is taken back).
		while alive and not h:Aborted() do
			RunService.Heartbeat:Wait()
		end
		teardown()
	end

	local function runShot(h)
		local ok, err = pcall(run, h)
		if held then
			held = false
			holding -= 1
		end
		teardown()
		if not ok then
			warn("[BattleStage] " .. tostring(err))
			if alive and not resultShown then
				handOver()
			end
		end
	end

	director:Play({
		stage = true,
		position = Vector3.new(Tuning.origin[1], Tuning.origin[2], Tuning.origin[3]),
		height = 8,
		run = runShot,
		onDone = function(ran: boolean)
			if not ran then
				handOver()
			end
		end,
	})

	return api
end

return BattleStage
