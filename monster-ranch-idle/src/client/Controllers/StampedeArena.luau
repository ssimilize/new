--[[
	StampedeArena (glow-up U): the Stampede, live in the world. Everything is drawn on this client
	from replicated state (global.Boss, session.Boss); the Boss system is unchanged apart from the
	squad looks it lists in global.Boss.squads. Tuning: Config.Boss.Arena; place:
	Config.World.StampedeArena; pure rules: Logic/StampedeArena.

	  storm     while the lobby is open and the fight runs (server-wide, every player): its own
	            ColorCorrectionEffect "StampedeStorm" in Lighting, stacked on the Weather and Sky
	            controllers' effects (they never write it), faded in and out and destroyed when it
	            reaches zero, so Lighting is left exactly as it was. Lightning flashes pulse it and
	            publish client bus "Weather.Lightning" (Soundscape's thunder); not at Low quality.
	  music     :Live() tells Soundscape to play the Stampede music (MusicStampede) meanwhile.
	  arena     a sand ring and posts, built once in the main place (never in the hub place).
	  squads    while the player is within Arena.viewRange: every joined squad (Logic Pick: yours
	            first, then round-robin, capped by the Quality level) stands in rings round the
	            centre (Logic Rings) and attacks on a staggered rhythm (Logic AttackOffset). Only
	            your own squad keeps its particle effects.
	  the giant when the fight goes live: the boss's form from Config.Boss.Rotation, bossScale x size,
	            charges in from the east (or stands in the centre for a late arrival), roars (its
	            voice pitched down), swings every bossAttackEvery, flinches when damage lands (at most
	            every flinchGap), staggers at the Arena.staggers HP fractions, and falls (faint) with
	            a big burst at 0 HP; if time runs out it roars and walks off. HP bar above it.
	  cheer     near the arena, joined and fighting: a Cheer button (HUD) batches taps into Boss.Cheer
	            every 0.5 s (the existing action and caps) and throws a bolt in your lead monster's
	            element colour from you to the giant: pooled parts, at most boltsPerSecond, with a hit
	            flash and a floating number (your squad's damage in the last second).
	  far away  a "To the arena" button (HUD) while the lobby or fight is on: joins if you can, then
	            moves your character to the arena's edge. Nothing happens unless it is tapped.
	  loot      Broadcasts hands Boss.Result to :Fountain first: at the arena, the chest the server
	            granted flies out of the fallen giant (Celebrate:Reward from its position), then the
	            result popup opens. Elsewhere (or behind a screen) the popup shows as before.

	Buttons hide while a Router screen is open. Models, bolts and numbers live in
	Workspace.StampedeArena.Live and are removed Arena.leaveSeconds after the end.

	Public:
	  StampedeArena:Live() -> boolean             the lobby or fight is on (main place)
	  StampedeArena:Fountain(payload, done) -> boolean
	      payload = Boss.Result; done(rewarded) is always called once when true is returned
	      (rewarded = the rewards already flew). false: the caller shows the result itself.
	  StampedeArena.Stats() -> { phase, boss, squad, bolts, storm }   (tests)
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Appearance = require(Shared.Logic.Appearance)
local Logic = require(Shared.Logic.StampedeArena)

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
local StoreKit = require(Client.UI.Components.StoreKit)

local New = Create.New
local C = Theme.Colors
local A = Config.Boss.Arena
local Place = Config.World.StampedeArena

local StampedeArena = {
	Name = "StampedeArena",
	Dependencies = { "Hud" },
}

local STEP = 0.1 -- seconds between logic steps (the frame loop only moves bolts, numbers and the storm)
local FLUSH = 0.5 -- seconds between Boss.Cheer requests
local FLASH_SECONDS = 0.2
local NUMBER_SECONDS = 0.9
local NUMBER_POOL = 6
local BOLT_SIZE = 1.4
local RED = Color3.fromHex("#C0573E")
local SAND = Color3.fromHex("#D9B98A")
local RIM = Color3.fromHex("#8A6A4A")

local ctx
local connections = {}
local clock = 0 -- seconds since Start, advanced by Heartbeat (deterministic in tests)
local acc, flushAcc = 0, 0
local mainPlace: boolean? = nil
local folder: Folder? = nil
local live: Folder? = nil

local phase = "off" -- off | gather (lobby) | fight | fall | leave
local phaseEnds = 0
local phaseAt = 0
local boss = nil -- { model, anim, def, height, bar, gui }
local squad = {} -- { { model, anim, nextAttack } }
local squadKey = ""
local lastHp: number? = nil
local lastFrac: number? = nil
local lastFlinch = -math.huge
local nextBossAttack = 0

local storm = { weight = 0, target = 0, flash = 0, nextLightning = 0, written = -1 }
local stormEffect: ColorCorrectionEffect? = nil
local stormTint = Color3.fromHex(A.storm.tint)

local bolts = {} -- pool: { part, t, from, to, active, flashing }
local numbers = {} -- pool: { part, gui, label, t, active }
local pacer = Logic.newPacer(A.boltsPerSecond)
local boltColor = C.Gold
local myDamage: number? = nil
local myDelta = 0

local cheerButton, goButton
local pendingTaps = 0
local requesting = false
local lastError = -math.huge
local pendingFountain = nil -- { payload, done, fired, firedAt, since }

local centre = Vector3.new(Place.center[1], Config.World.GroundY or 0, Place.center[2])

-- ─── Helpers ───────────────────────────────────────────────────────────────────────

local function bossState()
	local b = ctx.Store:Get("global.Boss")
	return if type(b) == "table" then b else {}
end

local function session()
	local s = ctx.Store:Get("session.Boss")
	return if type(s) == "table" then s else {}
end

local function isLive(b): boolean
	return mainPlace == true and (b.state == "lobby" or b.state == "active")
end

local function bossDef(bossId: any)
	for _, def in Config.Boss.Rotation do
		if def.id == bossId then
			return def
		end
	end
	return nil
end

local function viewer(): Vector3?
	local character = ctx.Player and ctx.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function flatDistance(p: Vector3?): number
	if not p then
		return math.huge
	end
	local dx, dz = p.X - centre.X, p.Z - centre.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function kit()
	return ctx:GetController("Celebrate")
end

-- Where bolts land and bursts go off: the giant's chest.
local function aimPoint(): Vector3
	if not boss then
		return centre + Vector3.new(0, 6, 0)
	end
	local root = boss.model.PrimaryPart
	local base = if root then root.Position else centre
	return Vector3.new(base.X, (centre.Y + boss.height * 0.55), base.Z)
end

local function roar()
	if not boss then
		return
	end
	Audio.Play(Voices.Key(boss.def.line), { at = boss.model, pitch = A.roarPitch, volume = 1, near = 20, far = 300 })
end

-- ─── The arena ─────────────────────────────────────────────────────────────────────

local function buildArena()
	local f = Instance.new("Folder")
	f.Name = "StampedeArena"
	local r = Place.radius
	-- Cylinders lie along X; turned upright they read as a flat disc.
	local upright = CFrame.Angles(0, 0, math.pi / 2)
	part({
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, r * 2 + 3, r * 2 + 3),
		CFrame = CFrame.new(centre + Vector3.new(0, 0.15, 0)) * upright,
		Color = RIM,
		Material = Enum.Material.Slate,
		Parent = f,
	})
	part({
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, r * 2, r * 2),
		CFrame = CFrame.new(centre + Vector3.new(0, 0.2, 0)) * upright,
		Color = SAND,
		Material = Enum.Material.Sand,
		Parent = f,
	})
	for i = 1, 8 do
		local a = (i - 0.5) / 8 * math.pi * 2
		local at = centre + Vector3.new(math.cos(a) * (r + 1), 3, math.sin(a) * (r + 1))
		part({
			Name = "Post",
			Size = Vector3.new(1.2, 6, 1.2),
			CFrame = CFrame.new(at),
			Color = RIM,
			Material = Enum.Material.Wood,
			Parent = f,
		})
		part({
			Name = "Flag",
			Size = Vector3.new(0.2, 1.6, 2.4),
			CFrame = CFrame.new(at + Vector3.new(0, 2.4, 0)) * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, 1.3),
			Color = RED,
			Material = Enum.Material.Fabric,
			Parent = f,
		})
	end
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(0.4, 3, 14),
		CFrame = CFrame.new(centre + Vector3.new(-(r + 3), 5, 0)),
		Color = RED,
		Parent = f,
	})
	local gui = New("SurfaceGui", { Face = Enum.NormalId.Left, CanvasSize = Vector2.new(420, 90), LightInfluence = 0, Parent = sign })
	Create.Text({ Text = "Stampede Arena", TextSize = Theme.TextSize.Title, TextScaled = true, Size = UDim2.fromScale(1, 1), Parent = gui })
	local l = Instance.new("Folder")
	l.Name = "Live"
	l.Parent = f
	f.Parent = workspace
	folder = f
	live = l
end

-- ─── Models ────────────────────────────────────────────────────────────────────────

local function destroyModel(entry)
	if entry.anim then
		entry.anim:Destroy()
	end
	if entry.model then
		entry.model:Destroy()
	end
end

local function clearSquad()
	for _, entry in squad do
		destroyModel(entry)
	end
	table.clear(squad)
	squadKey = ""
end

local function clearBoss()
	if boss then
		destroyModel(boss)
		if boss.gui then
			boss.gui:Destroy()
		end
		boss = nil
	end
end

local function build(appearance, scale: number?, effects: boolean): Model?
	local ok, model = pcall(MonsterModel.Build, appearance, { anchored = true, scale = scale, vfx = effects })
	if not ok or not model then
		return nil
	end
	model.Parent = live
	Vfx.SetOwned(model, false)
	return model
end

local function keyOf(b): string
	local parts = { tostring(Quality.Level()) }
	for _, entry in (if type(b.squads) == "table" then b.squads else {}) do
		if type(entry) == "table" then
			table.insert(parts, tostring(entry.userId) .. ":" .. tostring(type(entry.looks) == "table" and #entry.looks or 0))
		end
	end
	return table.concat(parts, ",")
end

local function leadColor(b)
	local me = ctx.Player and ctx.Player.UserId
	for _, entry in (if type(b.squads) == "table" then b.squads else {}) do
		if type(entry) == "table" and entry.userId == me and type(entry.looks) == "table" and entry.looks[1] then
			local def = Config.Species.ById[entry.looks[1].line]
			local element = def and def.elements and Config.Elements.ById[def.elements[1]]
			if element then
				return Color3.fromHex(element.color)
			end
		end
	end
	return C.Gold
end

local function syncSquad(b)
	local key = keyOf(b)
	if key == squadKey then
		return
	end
	clearSquad()
	squadKey = key
	boltColor = leadColor(b)
	local picked = Logic.Pick(b.squads, ctx.Player and ctx.Player.UserId, A.squadPerPlayer, Logic.MaxMonsters(A, Quality.Level()))
	local rings = Logic.Rings(#picked, A.ringInner, A.ringGap, A.ringSpacing)
	local low = Quality.IsLow()
	for i, pick in picked do
		local look = pick.look
		local ok, ap = pcall(Appearance.Preview, look.line, look.stage, look.form, look.rarity, look.variant)
		local model = if ok and ap then build(ap, nil, pick.mine and not low) else nil
		if model then
			local anim = MonsterAnimator.new(model)
			anim:SetOwn(pick.mine)
			local at = centre + Vector3.new(rings[i].x, 0, rings[i].z)
			anim:SetBase(CFrame.lookAt(at, Vector3.new(centre.X, at.Y, centre.Z)))
			table.insert(squad, { model = model, anim = anim, nextAttack = clock + Logic.AttackOffset(i, #picked, A.attackEvery) })
		end
	end
end

local function hpBar(model: Model, height: number, def)
	local anchor = model.PrimaryPart
	if not anchor then
		return nil, nil
	end
	local gui = New("BillboardGui", {
		Name = "StampedeHp",
		Adornee = anchor,
		Size = UDim2.fromOffset(240, 56),
		StudsOffsetWorldSpace = Vector3.new(0, height * 0.6 + 4, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = A.viewRange,
		Parent = live,
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
	local fill = New("Frame", { BackgroundColor3 = RED, Size = UDim2.fromScale(1, 1), Parent = track }, { Create.Corner(8) })
	return gui, fill
end

local function spawnBoss(b)
	local def = bossDef(b.bossId)
	if not def then
		return
	end
	local ok, ap = pcall(Appearance.Preview, def.line, 3, def.form, 4)
	local model = if ok and ap then build(ap, A.bossScale, not Quality.IsLow()) else nil
	if not model then
		return
	end
	local height = tonumber(model:GetAttribute("Height")) or 24
	local anim = MonsterAnimator.new(model)
	anim:SetOwn(false)
	local gui, fill = hpBar(model, height, def)
	boss = { model = model, anim = anim, def = def, height = height, gui = gui, bar = fill }
	local west = centre - Vector3.xAxis
	if ctx:Now() - (tonumber(b.startsAt) or 0) < 4 then
		-- The charge: in from the east, facing the square.
		local from = centre + Vector3.new(A.chargeFrom, 0, 0)
		anim:SetBase(CFrame.lookAt(from, centre))
		anim:MoveTo(centre, function()
			roar()
			if boss and boss.anim == anim then
				anim:Play("attack")
			end
		end)
		nextBossAttack = clock + A.bossAttackEvery + 3
	else
		anim:SetBase(CFrame.lookAt(centre, west))
		roar()
		nextBossAttack = clock + A.bossAttackEvery
	end
	lastHp, lastFrac = nil, nil
end

local function clearAll()
	clearBoss()
	clearSquad()
	phase = "off"
	if pendingFountain and not pendingFountain.closed then
		pendingFountain.closed = true
		task.spawn(pendingFountain.done, pendingFountain.fired == true)
	end
	pendingFountain = nil
end

-- ─── Bolts and numbers ─────────────────────────────────────────────────────────────

local function freeNumber()
	for _, n in numbers do
		if not n.active then
			return n
		end
	end
	if #numbers >= NUMBER_POOL or not live then
		return nil
	end
	local anchor = part({ Name = "HitNumber", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, Parent = live })
	local gui = New("BillboardGui", {
		Size = UDim2.fromOffset(140, 50),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		Parent = anchor,
	})
	local label = New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Title,
		TextColor3 = C.White,
		TextStrokeTransparency = 0.2,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Parent = gui,
	})
	local n = { part = anchor, gui = gui, label = label, t = 0, active = false }
	table.insert(numbers, n)
	return n
end

local function showNumber(at: Vector3)
	if myDelta <= 0 then
		return
	end
	local n = freeNumber()
	if not n then
		return
	end
	n.active = true
	n.t = 0
	n.part.CFrame = CFrame.new(at + Vector3.new((math.random() - 0.5) * 6, 2, (math.random() - 0.5) * 6))
	n.label.Text = "-" .. Format.short(math.floor(myDelta))
	n.label.TextColor3 = boltColor
	n.label.TextTransparency = 0
	n.gui.StudsOffset = Vector3.zero
	n.gui.Enabled = true
end

local function freeBolt()
	for _, bolt in bolts do
		if not bolt.active then
			return bolt
		end
	end
	if #bolts >= A.boltsPerSecond + 2 or not live then
		return nil
	end
	local p = part({
		Name = "Bolt",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(BOLT_SIZE, BOLT_SIZE, BOLT_SIZE),
		Material = Enum.Material.Neon,
		Transparency = 1,
		Parent = live,
	})
	local bolt = { part = p, t = 0, from = centre, to = centre, active = false, flashing = false }
	table.insert(bolts, bolt)
	return bolt
end

local function launchBolt()
	if not boss then
		return
	end
	local bolt = freeBolt()
	if not bolt then
		return
	end
	local from = (viewer() or centre) + Vector3.new(0, 3, 0)
	bolt.from = from
	bolt.to = aimPoint()
	bolt.t = 0
	bolt.active = true
	bolt.flashing = false
	bolt.part.Color = boltColor
	bolt.part.Size = Vector3.new(BOLT_SIZE, BOLT_SIZE, BOLT_SIZE)
	bolt.part.Transparency = 0
	bolt.part.CFrame = CFrame.new(from)
end

local function hit(bolt)
	Vfx.Burst("hatch", bolt.to, { color = boltColor, scale = 1 })
	showNumber(bolt.to)
	if boss and clock - lastFlinch >= A.flinchGap and boss.anim:GetState() == "idle" and not boss.anim:IsMoving() then
		lastFlinch = clock
		boss.anim:Play("hurt")
	end
end

local function stepBolts(dt: number)
	for _, bolt in bolts do
		if bolt.active then
			bolt.t += dt
			if not bolt.flashing then
				local p = bolt.t / A.boltSeconds
				if p >= 1 then
					bolt.flashing = true
					bolt.part.CFrame = CFrame.new(bolt.to)
					hit(bolt)
				else
					bolt.part.CFrame = CFrame.new(bolt.from:Lerp(bolt.to, p) + Vector3.new(0, math.sin(p * math.pi) * 4, 0))
				end
			else
				local f = (bolt.t - A.boltSeconds) / FLASH_SECONDS
				if f >= 1 then
					bolt.active = false
					bolt.part.Transparency = 1
				else
					local s = BOLT_SIZE + f * 4
					bolt.part.Size = Vector3.new(s, s, s)
					bolt.part.Transparency = f
				end
			end
		end
	end
	for _, n in numbers do
		if n.active then
			n.t += dt
			local f = n.t / NUMBER_SECONDS
			if f >= 1 then
				n.active = false
				n.gui.Enabled = false
			else
				n.gui.StudsOffset = Vector3.new(0, f * 4, 0)
				n.label.TextTransparency = math.max(0, f * 1.4 - 0.4)
			end
		end
	end
end

local function activeBolts(): number
	local count = 0
	for _, bolt in bolts do
		if bolt.active then
			count += 1
		end
	end
	return count
end

-- ─── Storm ─────────────────────────────────────────────────────────────────────────

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
		e.Name = "StampedeStorm"
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

local function lightning(b)
	if b.state ~= "active" or storm.weight < 1 or Quality.IsLow() or clock < storm.nextLightning then
		return
	end
	local every = A.lightningEvery
	storm.nextLightning = clock + every[1] + math.random() * (every[2] - every[1])
	storm.flash = 0.35
	ctx.Bus:Publish("Weather.Lightning", 0.8)
end

-- ─── The fight ─────────────────────────────────────────────────────────────────────

local function startEnd(fell: boolean)
	phase = if fell then "fall" else "leave"
	phaseAt = clock
	phaseEnds = clock + A.fallSeconds + A.fountainSeconds + A.leaveSeconds
	if boss then
		local pos = aimPoint()
		if fell then
			boss.anim:Play("faint")
			Vfx.Burst("rebirth", pos, { scale = 3 })
			Vfx.Burst("coins", pos, { scale = 3 })
			ctx:Sound("KO")
			roar()
			local k = kit()
			if k then
				k:Play("medium", { sound = false })
			end
		else
			boss.anim:Play("happy")
			roar()
			boss.anim:MoveTo(centre + Vector3.new(A.chargeFrom * 2, 0, 0))
		end
		if boss.bar then
			boss.bar.Size = UDim2.fromScale(if fell then 0 else 1, 1)
		end
	end
	for _, entry in squad do
		entry.anim:Play(if fell then "happy" else "idle")
	end
end

local function stagger()
	if not boss then
		return
	end
	boss.anim:Play("hurt")
	lastFlinch = clock
	Vfx.Burst("evolve", aimPoint(), { scale = 3, elements = { boss.def.element } })
	roar()
	ctx:Sound("Crit")
	local k = kit()
	if k then
		k:Play("medium", { sound = false })
	end
end

local function stepFight(b)
	-- HP: flinch, stagger, the bar.
	local maxHp = tonumber(b.maxHp) or 0
	local hp = tonumber(b.hp) or 0
	if boss and maxHp > 0 then
		local frac = math.clamp(hp / maxHp, 0, 1)
		if lastHp and hp < lastHp then
			if Logic.Crossed(lastFrac, frac, A.staggers) then
				stagger()
			elseif clock - lastFlinch >= A.flinchGap and boss.anim:GetState() == "idle" and not boss.anim:IsMoving() then
				lastFlinch = clock
				boss.anim:Play("hurt")
			end
		end
		if boss.bar and frac ~= lastFrac then
			boss.bar.Size = UDim2.fromScale(frac, 1)
		end
		lastHp, lastFrac = hp, frac
	end
	-- Rhythm: the giant swings slowly, the squads ripple round the ring.
	if boss and clock >= nextBossAttack and not boss.anim:IsMoving() then
		nextBossAttack = clock + A.bossAttackEvery
		boss.anim:Play("attack")
	end
	for _, entry in squad do
		if clock >= entry.nextAttack then
			entry.nextAttack += A.attackEvery
			if entry.nextAttack < clock then
				entry.nextAttack = clock + A.attackEvery
			end
			entry.anim:Play("attack")
		end
	end
end

local function fireFountain(f)
	f.fired = true
	f.firedAt = clock
	local payload = f.payload
	local pos = aimPoint()
	Vfx.Burst("coins", pos, { scale = 3 })
	if payload.egg then
		Vfx.Burst("hatch", pos, { scale = 2, color = C.Gold })
	end
	local k = kit()
	if k and type(payload.rewards) == "table" then
		local rank = tonumber(payload.rank) or 0
		k:Reward(payload.rewards, { from = pos, minSize = if rank >= 1 and rank <= 3 then "big" else nil })
	end
end

local function stepFountain()
	local f = pendingFountain
	if not f or f.closed then
		return
	end
	local ended = phase == "fall" or phase == "leave"
	if not f.fired then
		-- Wait for the fall; if the end never shows up here, fly the loot anyway.
		if (ended and clock >= phaseAt + A.fallSeconds) or clock >= f.since + A.fallSeconds + 3 then
			fireFountain(f)
		end
	elseif clock >= f.firedAt + A.fountainSeconds then
		f.closed = true
		pendingFountain = nil
		task.spawn(f.done, true)
	end
end

-- ─── Buttons and taps ──────────────────────────────────────────────────────────────

local function teleport()
	local character = ctx.Player and ctx.Player.Character
	if not character then
		return
	end
	local spot = centre + Vector3.new(-(Place.radius + 6), 3, 0)
	character:PivotTo(CFrame.lookAt(spot, Vector3.new(centre.X, spot.Y, centre.Z)))
end

local function goToArena()
	local b = bossState()
	if isLive(b) and not session().joined and StoreKit.isUnlocked(ctx.Store, Config.Boss.Unlock) then
		local ok, err = ctx.Net:Request("Boss.Join")
		if ok then
			ctx:Toast("You joined the Stampede!", "success")
		else
			ctx:Toast(tostring(err), "error")
		end
	end
	teleport()
end

local function cheer()
	pendingTaps = math.min(pendingTaps + 1, Config.Boss.MaxTapsPerRequest * 2)
	if pacer:Take(clock) then
		launchBolt()
	end
	if cheerButton then
		Anim.pulse(cheerButton.Root, 0.08)
	end
end

local function flush()
	if pendingTaps <= 0 or requesting then
		return
	end
	local taps = math.min(pendingTaps, Config.Boss.MaxTapsPerRequest)
	pendingTaps -= taps
	requesting = true
	task.spawn(function()
		local ok, res = ctx.Net:Request("Boss.Cheer", { taps = taps })
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

local function buildButtons()
	cheerButton = Button.new({
		Name = "StampedeCheer",
		Text = "Cheer!",
		Color = RED,
		Size = UDim2.fromOffset(160, 64),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Sound = false,
		Parent = ctx.UI.Hud,
		OnClick = cheer,
	})
	cheerButton:SetVisible(false)
	goButton = Button.new({
		Name = "StampedeGo",
		Text = "To the arena",
		Color = C.Green,
		Size = UDim2.fromOffset(200, 56),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Parent = ctx.UI.Hud,
		OnClick = function()
			task.spawn(goToArena)
		end,
	})
	goButton:SetVisible(false)
end

local shownCheer, shownGo = false, false
local function updateButtons(b, distance: number)
	local covered = ctx.Router:Current() ~= nil
	local near = distance <= A.nearRange
	local wantCheer = not covered and near and phase == "fight" and b.state == "active" and session().joined == true
	local wantGo = not covered and not near and isLive(b)
	if wantCheer ~= shownCheer then
		shownCheer = wantCheer
		cheerButton:SetVisible(wantCheer)
	end
	if wantGo ~= shownGo then
		shownGo = wantGo
		goButton:SetVisible(wantGo)
	end
end

-- ─── Main loop ─────────────────────────────────────────────────────────────────────

local function step()
	if mainPlace == nil then
		if not ctx.Store.Ready then
			return
		end
		mainPlace = ctx.Store:Get("global.TradingHub.mode") ~= "hub"
		if mainPlace then
			buildArena()
		end
	end
	if not mainPlace then
		return
	end
	local b = bossState()
	local on = isLive(b)
	storm.target = if on then 1 else 0
	lightning(b)
	local distance = flatDistance(viewer())
	local inView = distance <= A.viewRange

	if phase == "fall" or phase == "leave" then
		if clock >= phaseEnds and not pendingFountain then
			clearAll()
		end
	elseif on and inView then
		syncSquad(b)
		if b.state == "active" then
			if not boss then
				spawnBoss(b)
			end
			phase = "fight"
			stepFight(b)
		else
			phase = "gather"
		end
	elseif phase == "fight" and not on then
		startEnd((tonumber(b.hp) or 1) <= 0 and (tonumber(b.maxHp) or 0) > 0)
	elseif phase ~= "off" then
		clearAll() -- walked away, or the lobby closed without a fight
	end
	stepFountain()
	updateButtons(b, distance)
end

local function onSession(s)
	local damage = if type(s) == "table" then tonumber(s.damage) else nil
	if damage and myDamage and damage > myDamage then
		myDelta = damage - myDamage
	elseif not damage or damage == 0 then
		myDelta = 0
	end
	myDamage = damage
end

-- ─── Public ────────────────────────────────────────────────────────────────────────

function StampedeArena:Live(): boolean
	return isLive(bossState())
end

function StampedeArena:Fountain(payload, done: (boolean) -> ()): boolean
	if type(payload) ~= "table" or not boss or (phase ~= "fight" and phase ~= "fall" and phase ~= "leave") then
		return false
	end
	if ctx.Router:Current() ~= nil or flatDistance(viewer()) > A.viewRange then
		return false
	end
	if pendingFountain and not pendingFountain.closed then
		pendingFountain.closed = true
		task.spawn(pendingFountain.done, pendingFountain.fired == true)
	end
	pendingFountain = { payload = payload, done = done, fired = false, firedAt = 0, since = clock, closed = false }
	return true
end

function StampedeArena.Stats()
	return {
		phase = phase,
		boss = boss ~= nil,
		squad = #squad,
		bolts = activeBolts(),
		storm = storm.weight,
	}
end

function StampedeArena.Init(context)
	ctx = context
end

function StampedeArena.Start()
	buildButtons()
	table.insert(connections, ctx.Store:Observe("session.Boss", onSession))
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			clock += dt
			stepBolts(dt)
			stepStorm(dt)
			acc += dt
			flushAcc += dt
			if acc >= STEP then
				acc = 0
				step()
			end
			if flushAcc >= FLUSH then
				flushAcc = 0
				flush()
			end
		end)
	)
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function StampedeArena.Destroy()
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
	table.clear(bolts)
	table.clear(numbers)
end

return StampedeArena
