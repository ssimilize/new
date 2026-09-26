--[[
	World controller (C1): renders every ranch plot on top of the server-built geometry
	(Workspace.World, see Systems/World/Build.luau) from replicated state.

	  global.Plots   monsters in pens (MonsterModel + MonsterAnimator, wandering), gold statues on
	                 pedestals, incubator eggs (EggModel, wobble faster near endsAt, READY glow),
	                 pen theme colours and decor, the owner sign above each plot gate
	  profile.Ranch + session.Ranch    live coin jars over the local player's own pens
	                 (BillboardGuis in PlayerGui; tap = Ranch.Collect + coin burst)
	  global.Weather night flag (monsters nap at night)
	  Visuals/Quality  the quality level (glow-up P): other plots draw fewer monsters per pen by
	                 level and distance (Logic/Quality.PenCap, re-checked once a second as the camera
	                 moves), their animators are marked SetOwn(false) for the animator's distance LOD;
	                 Vfx and MonsterAnimator follow the level on their own

	Particle effects (Visuals/Vfx): every pen monster is marked as own / other plot (Vfx.SetOwned).
	Moment bursts: Eggs.Hatched and Monsters.Evolved burst at the monster once it appears in the
	pen (or at the character if it does not within HATCH_WAIT), Progression.LevelUp round the
	character; the client bus topic "Vfx.Burst" (name, { id }?) takes "monsterLevelUp" (at that pen
	monster, MonsterDetail) and "rebirth" (character + Star Altar, the Rebirth screen). Every moment
	goes through Celebrate:Moment, which holds it while a screen or popup covers the world (the
	hatch reveal, the evolution popup, MonsterDetail, Rebirth) and plays it once the view clears.
	Coin and heart bursts use the coin / heart sprites, or the plain emitters while those are not
	uploaded. A jar tap also flies its coins into the HUD counter (Celebrate:Reward).

	Sounds (client/Audio): pen monsters are tracked for Soundscape's chatter, cry when they play
	"happy" (rate-limited in Audio/Voices), when petted and on a level-up burst; a jar collect is
	a positional JarCollect plus a CoinTick streak.

	Taps on monsters are raycast against their Body parts (a 3D monster's invisible Hit box):
	own monster -> MonsterDetail, someone else's -> Social.Pet with hearts. Taps on own eggs open Incubators.
	The local character is moved to its plot once global.Plots lists the local UserId, and
	again on every respawn. Client bus: subscribes to "World.FocusPlot" (plotIndex).
	Glow-up L: Community.Trick (server event) plays a trick on that pen monster; World.PlayTrick and
	World.NearestOwn serve the emote wheel (Controllers/Community).

	Monsters are diffed by id and rebuilt only when their appearance changes; released models
	are pooled by appearance key. At most MAX_PER_PEN monsters are rendered per pen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local JarModule = Shared.Logic:FindFirstChild("Jar")
local Jar = if JarModule then require(JarModule) :: any else nil
local QualityRules = require(Shared.Logic.Quality)

local Client = script.Parent.Parent
local MonsterModel = require(Client.Visuals.MonsterModel)
local EggModel = require(Client.Visuals.EggModel)
local MonsterAnimator = require(Client.Visuals.MonsterAnimator)
local Vfx = require(Client.Visuals.Vfx)
local Quality = require(Client.Visuals.Quality)
local Audio = require(Client.Audio)
local Voices = require(Client.Audio.Voices)
local VfxConfig = require(Shared.Config.Vfx)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Anim = require(Client.UI.Anim)
local Icon = require(Client.UI.Components.Icon)

local New = Create.New
local WorldConfig = Config.World

local World = {
	Name = "World",
	Dependencies = {},
}

local PLOT_COUNT = #WorldConfig.Plots
local MAX_PENS = math.min(Config.Economy.Pens.max, #WorldConfig.PenOffsets)
local MAX_PER_PEN = 10 -- own plot; other plots: Config.Quality.Lod.penCap by level and distance
local MAX_STATUES = WorldConfig.StatueRow.count
local STATUE_SPACING = WorldConfig.StatueRow.spacing
local POOL_MAX = 40
local TICK = 0.2
local PEN_FLOOR_TOP = 0.4 -- fallback when Workspace.World is missing (see Build.luau)
local TAP_SLOP = 14
local TAP_TIME = 0.4
local READY_SOON = 60 -- seconds before endsAt when eggs start wobbling hard
local HATCH_WAIT = 2 -- seconds a hatched / evolved monster has to show up in a pen for its burst

local GOLD_DARK = Color3.fromHex("#9A6B12")
local GOLD_LIGHT = Color3.fromHex("#FFE38A")
local LOCKED_GROUND = Color3.fromHex("#B7C49C")
local LOCKED_FENCE = Color3.fromHex("#B8A68C")
local PEDESTAL = Color3.fromHex("#EDE3D3")
local READY_COLOR = Color3.fromHex("#FFD447")

local ctx
local player = Players.LocalPlayer
local world: Instance? = nil
local folder: Folder? = nil
local fx = {} :: { anchor: Attachment?, coins: ParticleEmitter?, hearts: ParticleEmitter? }
local views = {}
local bodyToEntry = {} -- [BasePart] = monster entry
local eggParts = {} -- [BasePart] = { view }
local pool = {} -- [appearanceKey] = { Model }
local poolCount = 0
local connections = {}
local running = false
local lowGraphics = Quality.IsLow()
local night = false
local latestPlots = nil
local ownIndex: number? = nil
local ranchProfile = nil
local ranchSession = nil
local jars = {} -- [pen] = { gui, label, fill, busy, text }
local jarPenCount = -1
local jarPlot: number? = nil
local petBusy = false
local focusToken = 0
local movedCharacter: Model? = nil
local pendingBursts = {} -- [monsterId] = { name, opts } waiting for the monster to appear

-- Geometry ---------------------------------------------------------------------------

local function plotFrame(index: number): CFrame
	local plot = WorldConfig.Plots[index]
	local c = plot.center
	return CFrame.new(c[1], WorldConfig.GroundY, c[3]) * CFrame.Angles(0, math.rad((plot.facing or 0) - 90), 0)
end

-- Studs from the camera to a plot's centre (the distance LOD's measure).
local function plotDistance(index: number): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 0
	end
	return (camera.CFrame.Position - plotFrame(index).Position).Magnitude
end

local function plotModel(index: number): Instance?
	local plots = world and world:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot" .. index)
end

local function penModel(index: number, pen: number): Instance?
	local plot = plotModel(index)
	local pens = plot and plot:FindFirstChild("Pens")
	return pens and pens:FindFirstChild("Pen" .. pen)
end

local function penFloor(index: number, pen: number): BasePart?
	local model = penModel(index, pen)
	local floor = model and model:FindFirstChild("Floor")
	return if floor and floor:IsA("BasePart") then floor else nil
end

-- Top-centre CFrame of a pen floor (plot orientation) and its half extents.
local function penArea(index: number, pen: number): (CFrame, number, number)
	local floor = penFloor(index, pen)
	if floor then
		return floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0), floor.Size.X / 2, floor.Size.Z / 2
	end
	local o = WorldConfig.PenOffsets[pen]
	return plotFrame(index) * CFrame.new(o[1], PEN_FLOOR_TOP, o[3]), WorldConfig.PenSize[1] / 2, WorldConfig.PenSize[2] / 2
end

local function randomPoint(area: CFrame, hx: number, hz: number, margin: number): Vector3
	local mx = math.max(0.5, hx - margin)
	local mz = math.max(0.5, hz - margin)
	return area:PointToWorldSpace(Vector3.new((math.random() * 2 - 1) * mx, 0, (math.random() * 2 - 1) * mz))
end

local function randomFacing(pos: Vector3): CFrame
	local a = math.random() * math.pi * 2
	return CFrame.lookAt(pos, pos + Vector3.new(math.cos(a), 0, math.sin(a)))
end

-- Effects -----------------------------------------------------------------------------

local function makeEmitter(color: Color3, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Rate = 0
	e.LightEmission = 0.3
	e.EmissionDirection = Enum.NormalId.Top
	for k, v in props do
		(e :: any)[k] = v
	end
	return e
end

local function buildFx(parent: Instance)
	local part = Instance.new("Part")
	part.Name = "Fx"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(0, -50, 0)
	part.Parent = parent
	local anchor = Instance.new("Attachment")
	anchor.Parent = part
	fx.anchor = anchor
	local coins = makeEmitter(Theme.Colors.Coin, {
		Size = NumberSequence.new(0.7, 0.35),
		Speed = NumberRange.new(14, 24),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, -45, 0),
		Lifetime = NumberRange.new(0.8, 1.2),
		RotSpeed = NumberRange.new(-200, 200),
	})
	coins.Parent = anchor
	fx.coins = coins
	local hearts = makeEmitter(Theme.Colors.Pink, {
		Size = NumberSequence.new(0.9, 0.2),
		Speed = NumberRange.new(4, 7),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, 3, 0),
		Drag = 2,
		Lifetime = NumberRange.new(1, 1.4),
		LightEmission = 0.6,
	})
	hearts.Parent = anchor
	fx.hearts = hearts
end

-- A coin or heart burst: the sprite preset (Config.Vfx.Bursts[name]) when its sprite is uploaded,
-- else the plain emitter.
local function burst(name: string, emitter: ParticleEmitter?, position: Vector3, count: number)
	if Vfx.Burst(name, position) > 0 then
		return
	end
	if not emitter or not fx.anchor then
		return
	end
	fx.anchor.WorldPosition = position
	emitter:Emit(if lowGraphics then math.ceil(count / 2) else count)
end

-- Floating text that rises and fades over an adornee (hearts, "+123").
local function floatText(adornee: Instance, text: string, color: Color3)
	if not folder then
		return
	end
	local gui = New("BillboardGui", {
		Name = "FloatText",
		Adornee = adornee,
		Size = UDim2.fromOffset(160, 50),
		StudsOffset = Vector3.new(0, 2, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = folder,
	})
	local label = Create.Text({
		Text = text,
		TextColor3 = color,
		TextSize = Theme.TextSize.Title,
		Size = UDim2.fromScale(1, 1),
		Stroke = true,
		Parent = gui,
	})
	Anim.tween(gui, { StudsOffset = Vector3.new(0, 6, 0) }, 1.1, Enum.EasingStyle.Quad)
	Anim.tween(label, { TextTransparency = 1 }, 1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(gui, 1.2)
end

-- Moment bursts ---------------------------------------------------------------------------

local function characterFeet(): CFrame?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.CFrame * CFrame.new(0, -3, 0)
	end
	return nil
end

local function hubBody(id: string): BasePart?
	local hub = world and world:FindFirstChild("Hub")
	local buildings = hub and hub:FindFirstChild("Buildings")
	local building = buildings and buildings:FindFirstChild(id)
	local body = building and building:FindFirstChild("Body")
	return if body and body:IsA("BasePart") then body else nil
end

local function ownEntry(id: any)
	local view = if ownIndex then views[ownIndex] else nil
	local entry = view and view.entries[id]
	return if entry and entry.alive then entry else nil
end

-- A burst at a pen monster's feet, sized to the monster.
local function monsterBurst(entry, name: string, opts)
	local root = entry.model.PrimaryPart
	if not root then
		return
	end
	local height = entry.model:GetAttribute("Height")
	local options = table.clone(opts or {})
	options.scale = if type(height) == "number" then height / VfxConfig.RefHeight else 1
	Vfx.Burst(name, root.CFrame, options)
end

-- At the monster if it is in one of the local player's pens, else round the character.
local function momentAt(id: any, name: string, opts)
	local entry = ownEntry(id)
	if entry then
		monsterBurst(entry, name, opts)
		return
	end
	local feet = characterFeet()
	if feet then
		Vfx.Burst(name, feet, opts)
	end
end

-- A monster that just hatched or evolved is (re)built when global.Plots catches up: burst when it
-- appears (spawnEntry), or after HATCH_WAIT wherever momentAt finds it.
local function expectMonster(id: any, name: string, opts, ready: (Model) -> boolean)
	local entry = ownEntry(id)
	if entry and ready(entry.model) then
		monsterBurst(entry, name, opts)
		return
	end
	local pending = { name = name, opts = opts }
	pendingBursts[id] = pending
	task.delay(HATCH_WAIT, function()
		if pendingBursts[id] == pending then
			pendingBursts[id] = nil
			momentAt(id, name, opts)
		end
	end)
end

-- Plays an in-world moment where the player can see it: Celebrate holds it while a screen or
-- popup covers the world. Without the kit (it failed to start) the moment plays at once.
local function moment(key: string, fn: () -> (), opts: { [string]: any }?)
	local kit = ctx:GetController("Celebrate")
	if kit then
		kit:Moment(key, fn, opts)
	else
		fn()
	end
end

local function onHatched(payload)
	local monster = type(payload) == "table" and payload.monster
	if type(monster) ~= "table" then
		return
	end
	local rarity = type(monster.rarity) == "number" and Config.Rarities.Get(monster.rarity)
	local opts = { color = if rarity then Color3.fromHex(rarity.color) else nil }
	-- The hatch reveal is the feedback while it is up; the burst waits for it to close.
	moment("hatch:" .. tostring(monster.id), function()
		expectMonster(monster.id, "hatch", opts, function()
			return true
		end)
	end, { flourish = false })
end

local function onEvolved(payload)
	if type(payload) ~= "table" then
		return
	end
	moment("evolve:" .. tostring(payload.id), function()
		local line = nil
		local entry = ownEntry(payload.id)
		if entry then
			line = entry.model:GetAttribute("Line")
		end
		local def = type(line) == "string" and Config.Species.ById[line]
		expectMonster(payload.id, "evolve", { elements = if def then def.elements else nil }, function(model)
			return model:GetAttribute("Form") == payload.toForm
		end)
	end, { flourish = false })
end

local function onBurstTopic(name: any, info: any)
	if name == "monsterLevelUp" and type(info) == "table" then
		-- MonsterDetail shows its own shockwave at the click.
		moment("monsterLevelUp:" .. tostring(info.id), function()
			momentAt(info.id, "monsterLevelUp")
			local entry = ownEntry(info.id)
			if entry then
				Voices.Cry(entry.model, "levelUp")
			end
		end, { flourish = false })
	elseif name == "rebirth" then
		moment("rebirth", function()
			local feet = characterFeet()
			if feet then
				Vfx.Burst("rebirth", feet)
			end
			local altar = hubBody("starAltar")
			if altar then
				Vfx.Burst("rebirth", altar.CFrame * CFrame.new(0, -altar.Size.Y / 2 + 0.2, -altar.Size.Z * 0.85))
			end
		end)
	end
end

-- Model pool ------------------------------------------------------------------------------

local function accessoryKey(acc): string
	if type(acc) ~= "table" then
		return ""
	end
	local list = {}
	for slot, id in acc do
		table.insert(list, tostring(slot) .. "=" .. tostring(id))
	end
	table.sort(list)
	return table.concat(list, "+")
end

-- The part a tap raycasts: a placeholder's "Body", a 3D monster's invisible "Hit" box.
local function tapPart(model: Model): BasePart?
	local part = model:FindFirstChild("Body") or model:FindFirstChild("Hit")
	return if part and part:IsA("BasePart") then part else nil
end

local function appearanceKey(a): string
	return table.concat({
		tostring(a.line),
		tostring(a.form),
		tostring(a.stage or 1),
		tostring(a.variant or 0),
		tostring(a.rarity or 0), -- the ground glow (Vfx) differs by rarity
		table.concat(a.muts or {}, "+"),
		tostring(math.floor((a.weight or 0) * 10 + 0.5)),
		tostring(a.archetype),
		accessoryKey(a.acc), -- worn accessories are built into the model
		tostring(a.aura or ""), -- 3.3 mastery aura (Vfx)
	}, "|")
end

local function hasMutation(a, id: string): boolean
	for _, m in a.muts or {} do
		if m == id then
			return true
		end
	end
	return false
end

local function acquireModel(appearance, key: string): Model?
	local list = pool[key]
	if list and #list > 0 then
		poolCount -= 1
		return table.remove(list)
	end
	local ok, model = pcall(MonsterModel.Build, appearance)
	if not ok then
		warn("[World] MonsterModel.Build failed: " .. tostring(model))
		return nil
	end
	if hasMutation(appearance, "prismatic") then
		model:SetAttribute("Prismatic", true)
	end
	local body = tapPart(model)
	if body then
		body.CanQuery = true
	end
	return model
end

local function releaseModel(model: Model, key: string)
	model.Parent = nil
	if poolCount >= POOL_MAX then
		model:Destroy()
		return
	end
	pool[key] = pool[key] or {}
	table.insert(pool[key], model)
	poolCount += 1
end

-- Plot views --------------------------------------------------------------------------------

local function getView(index: number)
	local view = views[index]
	if view then
		return view
	end
	local plotFolder = Instance.new("Folder")
	plotFolder.Name = "Plot" .. index
	plotFolder.Parent = folder
	view = {
		index = index,
		userId = 0,
		folder = plotFolder,
		entries = {},
		statues = {},
		statueKey = "",
		eggs = {},
		penKeys = {},
		decor = {},
		sign = nil,
		signLabel = nil,
		subLabel = nil,
	}
	views[index] = view
	return view
end

local function removeEntry(view, entry)
	entry.alive = false
	if entry.body then
		bodyToEntry[entry.body] = nil
	end
	entry.animator:Destroy()
	Voices.Untrack(entry.model)
	releaseModel(entry.model, entry.key)
	view.entries[entry.id] = nil
end

local function placeInPen(entry)
	local area, hx, hz = penArea(entry.plot, entry.pen)
	local pos = randomPoint(area, hx, hz, entry.margin)
	entry.animator:Stop()
	entry.animator:SetBase(randomFacing(pos))
	entry.animator:Play("idle")
	entry.nextAt = os.clock() + math.random() * 3
end

local function spawnEntry(view, id: string, appearance, key: string, pen: number)
	local model = acquireModel(appearance, key)
	if not model then
		return nil
	end
	local height = model:GetAttribute("Height")
	local body = tapPart(model)
	local entry = {
		id = id,
		key = key,
		pen = pen,
		plot = view.index,
		owner = view.userId,
		name = appearance.name,
		model = model,
		body = body,
		animator = MonsterAnimator.new(model),
		margin = 1.5 + (if type(height) == "number" then height * 0.4 else 1.2),
		nextAt = 0,
		alive = true,
	}
	placeInPen(entry)
	model.Parent = view.folder
	if entry.body then
		bodyToEntry[entry.body] = entry
	end
	view.entries[id] = entry
	local own = view.userId == player.UserId
	Vfx.SetOwned(model, own) -- pooled models move between plots
	entry.animator:SetOwn(own)
	Voices.Track(model)
	local pending = if own then pendingBursts[id] else nil
	if pending then
		pendingBursts[id] = nil
		task.defer(monsterBurst, entry, pending.name, pending.opts)
	end
	return entry
end

local function syncMonsters(view, data)
	local seen = {}
	local own = view.userId == player.UserId
	local distance = plotDistance(view.index)
	view.lodBand = QualityRules.Band(Config.Quality.Lod, Quality.Level(), distance)
	local cap = QualityRules.PenCap(Config.Quality.Lod, Quality.Level(), own, distance, MAX_PER_PEN)
	for p, pen in data.pens or {} do
		if type(p) == "number" and p <= MAX_PENS and type(pen) == "table" then
			local n = 0
			for _, m in pen.monsters or {} do
				if n >= cap then
					break
				end
				if type(m) == "table" and type(m.id) == "string" and type(m.appearance) == "table" and not seen[m.id] then
					n += 1
					seen[m.id] = true
					local key = appearanceKey(m.appearance)
					local entry = view.entries[m.id]
					if entry and entry.key ~= key then
						removeEntry(view, entry)
						entry = nil
					end
					if entry then
						entry.name = m.appearance.name
						if entry.pen ~= p then
							entry.pen = p
							placeInPen(entry)
						end
					else
						spawnEntry(view, m.id, m.appearance, key, p)
					end
				end
			end
		end
	end
	for id, entry in view.entries do
		if not seen[id] then
			removeEntry(view, entry)
		end
	end
end

local function goldTint(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			-- A 3D monster's textured Mesh ignores Color: it wears the Golden look (MonsterLooks) instead.
			if d.Name ~= "Root" and d.Name ~= "Mesh" and d.Name ~= "Hit" then
				local c = d.Color
				local lum = 0.3 * c.R + 0.59 * c.G + 0.11 * c.B
				d.Color = GOLD_DARK:Lerp(GOLD_LIGHT, math.clamp(lum * 1.2, 0, 1))
				d.Material = Enum.Material.Metal
			end
		elseif d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") or d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
end

local function clearStatues(view)
	for _, inst in view.statues do
		inst:Destroy()
	end
	table.clear(view.statues)
	view.statueKey = ""
end

-- 3.3: the plinth style the plot's owner equipped (global.Mastery.here), or nil for the default.
local function plinthFor(userId: number)
	local here = ctx.Store:Get("global.Mastery.here")
	local info = type(here) == "table" and here["u" .. tostring(userId)]
	local id = type(info) == "table" and info.plinth
	local def = type(id) == "string" and Config.Mastery.ItemById[id]
	return if def and def.kind == "plinth" then def else nil
end

local function syncStatues(view, data)
	local list = data.statues or {}
	local plinth = plinthFor(view.userId)
	local keys = { if plinth then plinth.id else "" }
	for i = 1, math.min(#list, MAX_STATUES) do
		if type(list[i]) == "table" then
			table.insert(keys, appearanceKey(list[i]))
		end
	end
	local key = table.concat(keys, ";")
	if key == view.statueKey then
		return
	end
	clearStatues(view)
	view.statueKey = key
	local origin = plotFrame(view.index)
	local o = WorldConfig.StatueRowOffset
	local placed = 0
	for i = 1, math.min(#list, MAX_STATUES) do
		local appearance = list[i]
		if type(appearance) == "table" then
			local cf = origin * CFrame.new(o[1] + placed * STATUE_SPACING, 0.3, o[3])
			placed += 1
			local pedestal = New("Part", {
				Name = "Pedestal",
				Anchored = true,
				CanCollide = true,
				CanQuery = false,
				CanTouch = false,
				Size = Vector3.new(WorldConfig.StatueRow.pedestal, 1.6, WorldConfig.StatueRow.pedestal),
				CFrame = cf * CFrame.new(0, 0.8, 0),
				Color = if plinth then Color3.fromHex(plinth.color) else PEDESTAL,
				Material = if plinth then (Enum.Material :: any)[plinth.material] else Enum.Material.SmoothPlastic,
				TopSurface = Enum.SurfaceType.Smooth,
				Parent = view.folder,
			})
			table.insert(view.statues, pedestal)
			local ok, model = pcall(MonsterModel.Build, appearance, { vfx = false, look = "golden" }) -- statues: no particles
			if ok then
				goldTint(model)
				model.Name = "Statue"
				model:PivotTo(cf * CFrame.new(0, 1.6, 0))
				model.Parent = view.folder
				table.insert(view.statues, model)
			end
		end
	end
end

local function clearEgg(egg)
	if egg.part then
		eggParts[egg.part] = nil
	end
	egg.animator:Destroy()
	egg.model:Destroy()
end

local function clearEggs(view)
	for slot, egg in view.eggs do
		clearEgg(egg)
		view.eggs[slot] = nil
	end
end

local function padTop(index: number): CFrame
	local plot = plotModel(index)
	local pad = plot and plot:FindFirstChild("IncubatorPad")
	local frame = plotFrame(index)
	if pad and pad:IsA("BasePart") then
		-- The pad is a cylinder lying on its side: its X axis is vertical.
		local top = pad.Position.Y + pad.Size.X / 2
		return frame.Rotation + Vector3.new(pad.Position.X, top, pad.Position.Z)
	end
	local o = WorldConfig.IncubatorOffset
	return frame * CFrame.new(o[1], 0.8, o[3])
end

-- One spot per incubator slot (Config.Economy.Incubators.maxSlots): four corners and the middle.
local EGG_SPOTS = { { -3, -3 }, { 3, -3 }, { -3, 3 }, { 3, 3 }, { 0, 0 } }

local function syncEggs(view, data)
	local list = data.incubators or {}
	local now = ctx:Now()
	local top: CFrame? = nil
	for slot = 1, #EGG_SPOTS do
		local info = list[slot]
		local egg = view.eggs[slot]
		local key = if type(info) == "table" and info.type then tostring(info.type) else nil
		local endsAt = if key then tonumber(info.endsAt) or 0 else 0
		-- Slots are compacted after a hatch, so a glowing egg can be replaced by an unready one.
		if egg and (egg.key ~= key or (egg.ready and endsAt > now)) then
			clearEgg(egg)
			view.eggs[slot] = nil
			egg = nil
		elseif egg then
			egg.endsAt = endsAt
		end
		if key and not egg then
			top = top or padTop(view.index)
			local ok, model = pcall(EggModel.Build, info.type)
			if ok then
				local root = model.PrimaryPart
				local half = if root then root.Size.Y / 2 else 1.3
				local spot = EGG_SPOTS[slot]
				local base = (top :: CFrame) * CFrame.new(spot[1], half, spot[2]) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
				if root then
					root.CanQuery = true
				end
				local animator = MonsterAnimator.new(model)
				animator:SetBase(base)
				animator:Play("wobble")
				model.Parent = view.folder
				egg = { key = key, endsAt = endsAt, model = model, animator = animator, part = root, ready = false }
				if root then
					eggParts[root] = view
				end
				view.eggs[slot] = egg
			end
		end
	end
end

local function setReady(view, egg)
	egg.ready = true
	egg.animator:SetIntensity(1)
	local root = egg.model.PrimaryPart
	if not root then
		return
	end
	EggModel.SetReady(egg.model, true) -- a warm glow and rising twinkles
	if view.userId == player.UserId then
		local gui = New("BillboardGui", {
			Name = "Ready",
			Size = UDim2.fromOffset(110, 34),
			StudsOffset = Vector3.new(0, 2.6, 0),
			AlwaysOnTop = true,
			MaxDistance = 120,
			LightInfluence = 0,
			Parent = root,
		})
		Create.Text({
			Text = "READY!",
			TextColor3 = READY_COLOR,
			TextSize = Theme.TextSize.Button,
			Size = UDim2.fromScale(1, 1),
			Stroke = true,
			Parent = gui,
		})
	end
end

local function tickEggs(now: number)
	for _, view in views do
		for _, egg in view.eggs do
			if not egg.ready then
				local remaining = egg.endsAt - now
				if remaining <= 0 then
					setReady(view, egg)
				elseif remaining < READY_SOON then
					egg.animator:SetIntensity(0.25 + 0.65 * (1 - remaining / READY_SOON))
				else
					egg.animator:SetIntensity(0.06)
				end
			end
		end
	end
end

-- Pen colours and decor ------------------------------------------------------------------

local function paintPen(index: number, pen: number, ground: Color3, fence: Color3, fenceTransparency: number)
	local model = penModel(index, pen)
	if not model then
		return
	end
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			if child.Name == "Floor" then
				child.Color = ground
			else
				child.Color = fence
				child.Transparency = fenceTransparency
			end
		end
	end
end

local DECOR_SPOTS = { { -0.62, -0.55 }, { 0.62, -0.55 }, { 0, -0.62 } }

local function syncDecor(view, pen: number, decorList)
	local old = view.decor[pen]
	if old then
		for _, part in old do
			part:Destroy()
		end
	end
	view.decor[pen] = nil
	if type(decorList) ~= "table" or #decorList == 0 then
		return
	end
	local area, hx, hz = penArea(view.index, pen)
	local parts = {}
	for i, id in decorList do
		local def = Config.Decor.ById[id]
		local spot = DECOR_SPOTS[i]
		if def and spot then
			-- Placeholder shapes from Config.Decor (`shape`); art replaces these later.
			local shape = def.shape or "block"
			local base = area * CFrame.new(spot[1] * hx, 0, spot[2] * hz)
			local color = Color3.fromHex(def.color)
			local glow = id == "lantern" or id == "rainbow_arch"
			local function piece(name: string, partShape: Enum.PartType, size: Vector3, cf: CFrame, pieceColor: Color3?)
				local part = New("Part", {
					Name = name,
					Anchored = true,
					CanCollide = false,
					CanQuery = false,
					CanTouch = false,
					CastShadow = false,
					Shape = partShape,
					Size = size,
					CFrame = cf,
					Color = pieceColor or color,
					Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic,
					Parent = view.folder,
				})
				table.insert(parts, part)
				return part
			end
			if shape == "disc" then
				-- Cylinders lie along X, so turn it upright: a flat puddle on the ground.
				piece(
					"Decor_" .. id,
					Enum.PartType.Cylinder,
					Vector3.new(0.3, 5, 5),
					base * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90))
				)
			elseif shape == "ball" then
				piece("Decor_" .. id, Enum.PartType.Ball, Vector3.new(2.6, 2.6, 2.6), base * CFrame.new(0, 1.3, 0))
			elseif shape == "tall" then
				piece(
					"Decor_" .. id,
					Enum.PartType.Block,
					Vector3.new(0.4, 3.6, 0.4),
					base * CFrame.new(0, 1.8, 0),
					Color3.fromHex("#EDE3D3")
				)
				piece("Decor_" .. id .. "_Top", Enum.PartType.Ball, Vector3.new(1.8, 1.8, 1.8), base * CFrame.new(0, 3.8, 0))
			else
				piece("Decor_" .. id, Enum.PartType.Block, Vector3.new(2.6, 2.4, 2.6), base * CFrame.new(0, 1.2, 0))
			end
		end
	end
	view.decor[pen] = parts
end

local function syncPens(view, data)
	local pens = if data then data.pens or {} else {}
	for p = 1, MAX_PENS do
		local pen = pens[p]
		local owned = type(pen) == "table"
		local themeId = if owned then pen.theme or "wood" else "locked"
		local decorKey = if owned and type(pen.decor) == "table" then table.concat(pen.decor, ",") else ""
		local key = themeId .. "#" .. decorKey
		if view.penKeys[p] ~= key then
			view.penKeys[p] = key
			if owned then
				local theme = Config.Decor.PenThemeById[themeId] or Config.Decor.PenThemes[1]
				paintPen(view.index, p, Color3.fromHex(theme.ground), Color3.fromHex(theme.fence), 0)
			else
				paintPen(view.index, p, LOCKED_GROUND, LOCKED_FENCE, 0.45)
			end
			syncDecor(view, p, if owned then pen.decor else nil)
		end
	end
end

-- Plot sign ----------------------------------------------------------------------------------

local function syncSign(view, data)
	local plot = plotModel(view.index)
	local gate = plot and plot:FindFirstChild("Gate")
	local board = gate and gate:FindFirstChild("Sign")
	if not view.sign then
		local gui = New("BillboardGui", {
			Name = "PlotSign" .. view.index,
			Size = UDim2.fromScale(20, 5),
			StudsOffset = Vector3.new(0, 3.4, 0),
			MaxDistance = 260,
			LightInfluence = 0,
			Parent = view.folder,
		})
		view.signLabel = Create.Text({ Text = "", TextScaled = true, Size = UDim2.fromScale(1, 0.62), Stroke = 3, Parent = gui })
		view.subLabel = Create.Text({
			Text = "",
			TextScaled = true,
			TextColor3 = Theme.Colors.Gold,
			Position = UDim2.fromScale(0, 0.62),
			Size = UDim2.fromScale(1, 0.38),
			Stroke = true,
			Parent = gui,
		})
		view.sign = gui
	end
	local gui = view.sign
	gui.Adornee = board or (plot and plot:FindFirstChild("Floor"))
	if not data or view.userId == 0 then
		gui.Enabled = board ~= nil
		view.signLabel.Text = "Empty Ranch"
		view.subLabel.Text = ""
		return
	end
	gui.Enabled = true
	local own = view.userId == player.UserId
	view.signLabel.Text = if own then "Your Ranch" else string.format("%s's Ranch", tostring(data.name or "?"))
	view.subLabel.Text = string.format("Lv %d  ·  ♥ %s", tonumber(data.level) or 1, Format.short(tonumber(data.likes) or 0))
end

local function clearView(view)
	for _, entry in view.entries do
		removeEntry(view, entry)
	end
	clearStatues(view)
	clearEggs(view)
end

-- Character & camera --------------------------------------------------------------------------

local function moveCharacterHome(character: Model?)
	if not ownIndex or not character or movedCharacter == character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	if not root or not ownIndex or character.Parent == nil then
		return
	end
	task.wait(0.2) -- let the default spawn placement finish first
	if movedCharacter == character or character.Parent == nil then
		return
	end
	movedCharacter = character
	local frame = plotFrame(ownIndex)
	local pos = (frame * CFrame.new(WorldConfig.PlotSize[1] / 2 - 10, 4, 0)).Position
	local look = (frame * CFrame.new(0, 4, 0)).Position
	character:PivotTo(CFrame.lookAt(pos, look))
end

local function focusPlot(index: any)
	local i = tonumber(index)
	local camera = workspace.CurrentCamera
	if not i or not WorldConfig.Plots[i] or not camera then
		return
	end
	focusToken += 1
	local token = focusToken
	local frame = plotFrame(i)
	local target = frame.Position
	local eye = (frame * CFrame.new(WorldConfig.PlotSize[1] * 0.85, 75, 0)).Position
	camera.CameraType = Enum.CameraType.Scriptable
	Anim.tween(camera, { CFrame = CFrame.lookAt(eye, target) }, 1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	task.delay(4.5, function()
		if token == focusToken and camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
		end
	end)
end

-- Coin jars (own plot) --------------------------------------------------------------------------

local function destroyJars()
	for pen, jar in jars do
		jar.gui:Destroy()
		jars[pen] = nil
	end
end

local function collect(pen: number)
	local jar = jars[pen]
	if not jar or jar.busy then
		return
	end
	jar.busy = true
	Anim.pulse(jar.button, 0.15)
	-- The coin counter waits for the coins to fly in rather than jumping on the reply.
	local kit = ctx:GetController("Celebrate")
	local hold = kit and kit:Hold({ "coins" })
	local ok, result = ctx.Net:Request("Ranch.Collect", { pen = pen })
	jar.busy = false
	local coins = if ok and type(result) == "table" then tonumber(result.coins) or 0 else 0
	if ok then
		local floor = ownIndex and penFloor(ownIndex, pen)
		local area = if ownIndex then penArea(ownIndex, pen) else nil
		local at = if area then area.Position + Vector3.new(0, 4, 0) else nil
		if at then
			burst("coins", fx.coins, at, 24)
		end
		if floor and coins > 0 then
			floatText(floor, "+" .. Format.short(coins), Theme.Colors.Gold)
		end
		-- The landing coins tick up the streak (Celebrate); here, the jar itself.
		Audio.Chain({ "JarCollect", "CoinCollect" }, { at = if area then area.Position else nil })
		if kit and coins > 0 then
			-- From the jar on screen (the float text already says "+N", so no second label).
			kit:Reward({ { kind = "coins", amount = coins } }, { from = at, hold = hold, label = false })
		end
	else
		ctx:Toast(tostring(result), "error")
	end
	if hold and coins <= 0 then
		hold:Release()
	end
end

local function buildJar(pen: number, floor: BasePart, playerGui: Instance)
	local gui = New("BillboardGui", {
		Name = "Jar" .. pen,
		Adornee = floor,
		Size = UDim2.fromOffset(124, 60),
		StudsOffset = Vector3.new(0, 5.5, 0),
		AlwaysOnTop = true,
		MaxDistance = 160,
		ResetOnSpawn = false,
		LightInfluence = 0,
		Active = true,
		Parent = playerGui,
	})
	local button = New("TextButton", {
		Name = "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.Panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(116, 52),
		Parent = gui,
	}, { Create.Corner(Theme.Radius.Button), Create.Stroke(Theme.Stroke.Button) })
	local icon = Icon.new("coin", 28)
	icon.Position = UDim2.fromOffset(8, 6)
	icon.Parent = button
	local label = Create.Text({
		Name = "Amount",
		Text = "0",
		TextColor3 = Theme.Colors.Text,
		TextSize = Theme.TextSize.Button,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		Position = UDim2.fromOffset(42, 5),
		Size = UDim2.new(1, -48, 0, 30),
		Stroke = false,
		Parent = button,
	})
	local barBack = New("Frame", {
		Name = "Bar",
		BackgroundColor3 = Theme.Colors.PanelDeep,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 8, 1, -13),
		Size = UDim2.new(1, -16, 0, 7),
		Parent = button,
	}, { Create.Round() })
	local fill = New("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.Colors.Coin,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = barBack,
	}, { Create.Round() })
	local jar = { gui = gui, button = button, label = label, fill = fill, busy = false, text = "", full = nil }
	button.Activated:Connect(function()
		task.spawn(collect, pen)
	end)
	jars[pen] = jar
end

local function syncJars()
	local pens = ranchProfile and ranchProfile.pens
	local count = if type(pens) == "table" then #pens else 0
	if ownIndex == jarPlot and count == jarPenCount then
		return
	end
	destroyJars()
	jarPlot, jarPenCount = ownIndex, count
	if not ownIndex then
		return
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	for pen = 1, math.min(count, MAX_PENS) do
		local floor = penFloor(ownIndex, pen)
		if floor then
			buildJar(pen, floor, playerGui)
		end
	end
end

local function jarValue(pen, rate: number, cap: number, now: number): number
	local stored = tonumber(pen.jar) or 0
	local jarAt = tonumber(pen.jarAt) or now
	if Jar and Jar.Value then
		return Jar.Value(stored, rate, jarAt, now, cap)
	end
	if rate <= 0 then
		return stored
	end
	return math.max(stored, math.min(stored + rate * math.max(0, now - jarAt), rate * cap))
end

local function lookup(map, index: number): number
	if type(map) ~= "table" then
		return 0
	end
	return tonumber(map[index] or map[tostring(index)]) or 0
end

local function tickJars(now: number)
	local pens = ranchProfile and ranchProfile.pens
	if type(pens) ~= "table" then
		return
	end
	local rates = ranchSession and ranchSession.rates
	local caps = ranchSession and ranchSession.caps
	for index, jar in jars do
		local pen = pens[index]
		if type(pen) == "table" then
			local rate = lookup(rates, index)
			local cap = lookup(caps, index)
			local value = jarValue(pen, rate, cap, now)
			local capCoins = rate * cap
			local text = Format.short(math.floor(value))
			if text ~= jar.text then
				jar.text = text
				jar.label.Text = text
			end
			local fraction = if capCoins > 0 then math.clamp(value / capCoins, 0, 1) else 0
			jar.fill.Size = UDim2.fromScale(fraction, 1)
			local full = fraction >= 0.999
			if full ~= jar.full then
				jar.full = full
				jar.fill.BackgroundColor3 = if full then Theme.Colors.Green else Theme.Colors.Coin
				jar.label.TextColor3 = if full then Theme.Colors.Green else Theme.Colors.Text
			end
		end
	end
end

-- Wandering -------------------------------------------------------------------------------------

local function decide(entry, clockNow: number)
	local animator = entry.animator
	local roll = math.random()
	if night and roll < 0.55 then
		animator:Play("sleep")
		entry.nextAt = clockNow + 6 + math.random() * 10
		return
	end
	roll = math.random()
	if roll < 0.62 then
		local area, hx, hz = penArea(entry.plot, entry.pen)
		entry.nextAt = math.huge
		animator:MoveTo(randomPoint(area, hx, hz, entry.margin), function()
			if entry.alive then
				entry.nextAt = os.clock() + 1.5 + math.random() * 3.5
			end
		end)
	elseif roll < 0.74 then
		animator:Play("happy")
		Voices.Cry(entry.model, "happy")
		entry.nextAt = clockNow + 2 + math.random() * 2
	elseif roll < 0.86 then
		animator:Play("eat")
		entry.nextAt = clockNow + 2.5 + math.random() * 2.5
	else
		animator:Play("idle")
		entry.nextAt = clockNow + 2 + math.random() * 3
	end
end

local function tickWander()
	local clockNow = os.clock()
	for _, view in views do
		for _, entry in view.entries do
			if clockNow >= entry.nextAt and not entry.animator:IsMoving() then
				decide(entry, clockNow)
			end
		end
	end
end

-- Taps -------------------------------------------------------------------------------------------

local function onMonsterTapped(entry)
	if entry.owner == player.UserId then
		entry.animator:Play("happy")
		Voices.Cry(entry.model, "pet")
		ctx.Router:Open("MonsterDetail", { id = entry.id })
		return
	end
	if petBusy then
		return
	end
	petBusy = true
	task.spawn(function()
		local ok, result = ctx.Net:Request("Social.Pet", { owner = entry.owner, id = entry.id })
		petBusy = false
		if not ok then
			ctx:Toast(tostring(result), "error")
			return
		end
		if entry.alive then
			entry.animator:Play("happy")
			local root = entry.model.PrimaryPart
			local head = root and root:FindFirstChild("Head")
			local at = if head and head:IsA("Attachment") then head else root
			if at then
				local position = if head and head:IsA("Attachment") then head.WorldPosition else (root :: BasePart).Position
				burst("hearts", fx.hearts, position, 10)
				floatText(at, "♥", Theme.Colors.Pink)
				Audio.Play("Pet", { at = position })
				Voices.Cry(entry.model, "pet")
			end
		end
		local left = type(result) == "table" and tonumber(result.left)
		local name = tostring(entry.name or "a monster")
		local text = if left then string.format("You petted %s! %d pets left today", name, left) else string.format("You petted %s!", name)
		ctx:Toast(text, "success")
	end)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function handleTap(position: Vector3)
	local camera = workspace.CurrentCamera
	if not camera or not folder then
		return
	end
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	rayParams.FilterDescendantsInstances = { folder }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	if not result then
		return
	end
	local entry = bodyToEntry[result.Instance]
	if entry and entry.alive then
		onMonsterTapped(entry)
		return
	end
	local view = eggParts[result.Instance]
	if view and view.userId == player.UserId then
		ctx.Router:Open("Incubators")
	end
end

local function connectInput()
	local starts = {}
	local function keyOf(input: InputObject): any
		return if input.UserInputType == Enum.UserInputType.Touch then input else "mouse"
	end
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				starts[keyOf(input)] = { input.Position, os.clock() }
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			local kind = input.UserInputType
			if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
				return
			end
			local key = keyOf(input)
			local start = starts[key]
			starts[key] = nil
			if not start then
				return
			end
			if (input.Position - start[1]).Magnitude > TAP_SLOP or os.clock() - start[2] > TAP_TIME then
				return
			end
			handleTap(input.Position)
		end)
	)
end

-- State ---------------------------------------------------------------------------------------------

local function onPlots(list)
	latestPlots = list
	if not folder then
		return
	end
	local newOwn = nil
	for i = 1, PLOT_COUNT do
		local data = if type(list) == "table" then list[i] else nil
		if type(data) ~= "table" then
			data = nil
		end
		local view = getView(i)
		local userId = if data then tonumber(data.userId) or 0 else 0
		if userId ~= view.userId then
			clearView(view)
			view.userId = userId
		end
		if data and userId ~= 0 then
			if userId == player.UserId then
				newOwn = i
			end
			syncMonsters(view, data)
			syncStatues(view, data)
			syncEggs(view, data)
			syncPens(view, data)
		else
			syncPens(view, nil)
		end
		syncSign(view, data)
	end
	local first = ownIndex == nil and newOwn ~= nil
	if newOwn ~= ownIndex then
		movedCharacter = nil
	end
	ownIndex = newOwn
	syncJars()
	if first then
		task.spawn(moveCharacterHome, player.Character)
	end
end

-- Distance LOD: another plot whose distance band changed is re-synced (more or fewer monsters).
local function tickLod()
	if type(latestPlots) ~= "table" then
		return
	end
	local level = Quality.Level()
	for index, view in views do
		local data = latestPlots[index]
		if view.userId ~= 0 and view.userId ~= player.UserId and type(data) == "table" then
			if QualityRules.Band(Config.Quality.Lod, level, plotDistance(index)) ~= view.lodBand then
				syncMonsters(view, data)
			end
		end
	end
end

local function loop()
	local elapsed = 0
	local sinceLod = 0
	while running do
		local dt = task.wait(TICK)
		elapsed += dt
		sinceLod += dt
		local now = ctx:Now()
		tickWander()
		tickJars(now)
		if elapsed >= 0.5 then
			elapsed = 0
			tickEggs(now)
		end
		if sinceLod >= 1 then
			sinceLod = 0
			tickLod()
		end
	end
end

-- Photo mode (PhotoMode controller): the local player's pen monsters within `radius` studs of
-- `position`, nearest first, as { model, animator } (the animator is live; do not Destroy it).
function World:OwnMonstersNear(position: Vector3, radius: number): { { model: Model, animator: any } }
	local view = if ownIndex then views[ownIndex] else nil
	local found = {}
	for _, entry in if view then view.entries else {} do
		if entry.alive then
			local distance = (entry.animator:GetPosition() - position).Magnitude
			if distance <= radius then
				table.insert(found, { model = entry.model, animator = entry.animator, distance = distance })
			end
		end
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	return found
end

-- Tricks (glow-up L) ------------------------------------------------------------------------------

-- Plays a Config.Community trick on a pen monster (any plot), falling back while the animator
-- lacks the trick's own state. Returns whether that monster is on screen here.
function World.PlayTrick(owner: number, id: string, trickId: string): boolean
	local def = Config.Community and Config.Community.TrickById[trickId]
	if not def then
		return false
	end
	for _, view in views do
		if view.userId == owner then
			local entry = view.entries[id]
			if entry and entry.alive then
				local state = def.state
				if not MonsterAnimator.HasState(state) then
					state = def.fallback or "happy"
				end
				entry.animator:Stop()
				entry.animator:Play(state)
				entry.nextAt = os.clock() + 2.5
				if state == "happy" or state == "trick" then
					Voices.Cry(entry.model, "happy")
				end
				return true
			end
		end
	end
	return false
end

-- The local player's pen monster nearest to `position` within `range` studs, or nil.
function World.NearestOwn(position: Vector3, range: number): string?
	local view = if ownIndex then views[ownIndex] else nil
	if not view then
		return nil
	end
	local best, bestDistance = nil, range
	for id, entry in view.entries do
		local root = entry.alive and entry.model.PrimaryPart
		if root then
			local distance = (root.Position - position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = id, distance
			end
		end
	end
	return best
end

local function onTrick(payload)
	if type(payload) == "table" and type(payload.owner) == "number" and type(payload.id) == "string" then
		World.PlayTrick(payload.owner, payload.id, tostring(payload.trick))
	end
end

function World.Init(context)
	ctx = context
	table.insert(
		connections,
		ctx.Bus:Subscribe("World.FocusPlot", function(index)
			focusPlot(index)
		end)
	)
	table.insert(connections, ctx.Bus:Subscribe("Vfx.Burst", onBurstTopic))
	table.insert(connections, ctx.Net:On("Eggs.Hatched", onHatched))
	table.insert(connections, ctx.Net:On("Monsters.Evolved", onEvolved))
	table.insert(connections, ctx.Net:On("Community.Trick", onTrick)) -- glow-up L: emote wheel tricks
	table.insert(
		connections,
		ctx.Net:On("Progression.LevelUp", function()
			-- The level-up banner and the HUD shockwave are the feedback while a screen is open.
			moment("ranchLevelUp", function()
				local feet = characterFeet()
				if feet then
					Vfx.Burst("ranchLevelUp", feet)
				end
			end, { flourish = false })
		end)
	)
end

function World.Start()
	world = workspace:WaitForChild("World", 30)
	if not world then
		warn("[World] Workspace.World not found; rendering with Config.World positions")
	end
	local f = Instance.new("Folder")
	f.Name = "WorldClient"
	f.Parent = workspace
	folder = f
	buildFx(f)
	running = true

	connectInput()
	table.insert(
		connections,
		player.CharacterAdded:Connect(function(character)
			moveCharacterHome(character)
		end)
	)
	table.insert(
		connections,
		Quality.Changed:Connect(function()
			lowGraphics = Quality.IsLow()
			if latestPlots then
				onPlots(latestPlots)
			end
		end)
	)
	table.insert(
		connections,
		ctx.Store:Observe("global.Weather", function(weather)
			night = type(weather) == "table" and weather.night == true
		end)
	)
	table.insert(
		connections,
		ctx.Store:Observe("profile.Ranch", function(ranch)
			ranchProfile = ranch
			syncJars()
		end)
	)
	table.insert(
		connections,
		ctx.Store:Observe("session.Ranch", function(ranch)
			ranchSession = ranch
		end)
	)
	table.insert(connections, ctx.Store:Observe("global.Plots", onPlots))
	table.insert(
		connections,
		ctx.Store:Observe("global.Mastery.here", function()
			onPlots(ctx.Store:Get("global.Plots"))
		end)
	)
	task.spawn(loop)
end

-- Tears everything down (not called by the kernel today; kept so the controller can be unplugged).
function World.Destroy()
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, view in views do
		clearView(view)
	end
	table.clear(views)
	destroyJars()
	for _, list in pool do
		for _, model in list do
			model:Destroy()
		end
	end
	table.clear(pool)
	poolCount = 0
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return World
