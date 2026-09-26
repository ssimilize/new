--[[
	Cinematics (glow-up N): the hatch in the world, evolution you watch, and short looks at a
	monster after a star-up or level-up. Every shot goes through CameraDirector; the maths is
	Logic/Cinematic and the tuning Config/Cinematics. Presentation only: the server result and its
	rewards have already landed when any of this starts, and nothing here waits on or gates them.

		Cinematics:Hatch(entries, onDone) -> boolean
		    Hatchery hands over its queue ({ monster, egg, slot, isNew }, in montage order). When the
		    local player's incubator is on screen nearby (an open Incubators screen is closed first
		    and reopened by ReopenAfterHatch) the eggs sit on the pad, wobble longer and harder the
		    rarer the result (three cracks, EggCrack), burst (Bursts.hatch scaled by rarity; Mythic
		    also gets light beams and a tinted world), and the monster hops out and cries, with a
		    NEW! stamp on a first discovery and a SHINY! shower for Golden and Rainbow. Several eggs
		    are a quick montage. Sets entry.inWorld and calls onDone(ran) once; false = the 2D reveal.
		Cinematics:ClaimNew(monster) -> boolean  a form not in the codex yet (claimed once per form)
		Cinematics:ReopenAfterHatch()             reopens Incubators if Hatch closed it
		Cinematics:TakeEvolve(payload, showCard) -> boolean
		    Notifications, on Monsters.Evolved: when the monster is in the player's pen on screen, it
		    glows white and spins up in an element-coloured vortex (Bursts.evolveVortex) while the
		    old and new forms pulse through each other, a flash (Bursts.evolve), and the new form
		    lands with its cry where the old one stood; then showCard(). False = card now.
		Cinematics:Evolved(payload) -> boolean   World's evolve moment (after the screen closed):
		    true when TakeEvolve already showed it or the in-world version plays now (no card)
		Cinematics:Spotlight(id, burst) -> boolean  World's monsterLevelUp / monsterStarUp moments
		Cinematics:Played() -> { hatch, evolve, spotlight }   counts (tests)

	Everything a shot builds lives in Workspace.Cinematic (and a ColorCorrectionEffect
	"CinematicPulse" in Lighting) and is gone when the shot ends, skipped or not; World's own egg
	and monster models are hidden with LocalTransparencyModifier meanwhile and given back.
	lowGraphics: no egg sparkles, three beams instead of six, reduced motion (no spin, no flash,
	a gentler wobble, CameraDirector cuts).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Appearance = require(Shared.Logic.Appearance)
local AudioRules = require(Shared.Logic.Audio)
local Cinematic = require(Shared.Logic.Cinematic)
local Tuning = require(Shared.Config.Cinematics)

local Client = script.Parent.Parent
local Audio = require(Client.Audio)
local Voices = require(Client.Audio.Voices)
local EggModel = require(Client.Visuals.EggModel)
local MonsterModel = require(Client.Visuals.MonsterModel)
local MonsterAnimator = require(Client.Visuals.MonsterAnimator)
local Vfx = require(Client.Visuals.Vfx)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Anim = require(Client.UI.Anim)
local StoreKit = require(Client.UI.Components.StoreKit)

local New = Create.New
local C = Theme.Colors
local CAM = Tuning.Camera
local HATCH = Tuning.Hatch
local EVOLVE = Tuning.Evolve

local SHINY_GOLD = Color3.fromHex("#FFD447")
local FRESH_SECONDS = 10 -- a codex entry that landed this recently still counts as new
local BEAMS, BEAMS_LOW = 6, 3
local SOURCE_SCREEN = "Incubators" -- the screen a hatch is started from; closed for the shot

local Cinematics = {
	Name = "Cinematics",
	Dependencies = {},
}

local ctx
local folder: Folder? = nil
local beams = {} -- pooled Parts
local known = nil -- [line .. ":" .. form] = true, the codex as last seen
local fresh = {} -- [key] = os.clock() it arrived in the codex
local evolveClaimed = {} -- [monsterId] = true: an evolution already shown in the world
local reopen = false
local played = { hatch = 0, evolve = 0, spotlight = 0 }

-- Helpers -----------------------------------------------------------------------------------

local function director()
	return ctx:GetController("CameraDirector")
end

local function world()
	return ctx:GetController("World")
end

local function lowGraphics(): boolean
	local settings = ctx.Store:Get("profile.Settings")
	return type(settings) == "table" and settings.lowGraphics == true
end

local function stage(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "Cinematic"
	f.Parent = workspace
	folder = f
	return f
end

-- On screen and close enough to be worth a shot.
local function inView(position: Vector3): boolean
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - position).Magnitude > CAM.visibleRange then
		return false
	end
	local _, onScreen = camera:WorldToViewportPoint(position)
	return onScreen == true
end

-- World's own models are hidden, not touched otherwise; `hidden` remembers what to give back.
local function hide(hidden, model: Instance?)
	if not model or hidden[model] then
		return
	end
	hidden[model] = true
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			hidden[d] = d.LocalTransparencyModifier
			d.LocalTransparencyModifier = 1
		elseif d:IsA("BillboardGui") or d:IsA("ParticleEmitter") then
			hidden[d] = d.Enabled
			d.Enabled = false
		end
	end
end

local function unhide(hidden)
	for inst, value in hidden do
		if typeof(inst) == "Instance" and value ~= true then
			pcall(function()
				if inst:IsA("BasePart") then
					inst.LocalTransparencyModifier = value
				else
					(inst :: any).Enabled = value
				end
			end)
		end
	end
	table.clear(hidden)
end

local function parts(model: Model): { BasePart }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function setShown(list: { BasePart }, shown: boolean)
	local value = if shown then 0 else 1
	for _, p in list do
		p.LocalTransparencyModifier = value
	end
end

-- Runs fn(t) every frame for `seconds`; returns true if the shot was skipped.
local function during(h, seconds: number, fn: (number) -> ()): boolean
	local t0 = os.clock()
	while true do
		local t = os.clock() - t0
		fn(math.min(t, seconds))
		if h:Skipped() then
			return true
		end
		if t >= seconds then
			return false
		end
		RunService.Heartbeat:Wait()
	end
end

local function stamp(model: Model, text: string, color: Color3, lift: number)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local height = model:GetAttribute("Height")
	local gui = New("BillboardGui", {
		Name = "Stamp",
		Size = UDim2.fromOffset(170, 48),
		StudsOffset = Vector3.new(0, (if type(height) == "number" then height else 3) + lift, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = root,
	})
	local label = Create.Text({
		Text = text,
		TextColor3 = color,
		TextSize = Theme.TextSize.Hero,
		Size = UDim2.fromScale(1, 1),
		Rotation = -6,
		Stroke = true,
		Parent = gui,
	})
	Anim.popIn(label, 0.25)
	ctx:Sound("ItemPop")
end

-- Light beams (Mythic) ----------------------------------------------------------------------

local function beamParts(count: number, color: Color3): { BasePart }
	for i = #beams + 1, count do
		local p = Instance.new("Part")
		p.Name = "Beam" .. i
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Size = Vector3.new(0.4, 0.4, 16)
		beams[i] = p
	end
	local list = {}
	for i = 1, count do
		local p = beams[i]
		p.Color = color
		p.Transparency = 1
		p.Parent = stage()
		list[i] = p
	end
	return list
end

local function placeBeams(list: { BasePart }, center: CFrame, spin: number, strength: number)
	local n = #list
	for i, p in list do
		local yaw = spin + (i / n) * math.pi * 2
		p.CFrame = center * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(50), 0, 0) * CFrame.new(0, 0, -8)
		p.Transparency = 1 - 0.55 * strength
	end
end

local function dropBeams()
	for _, p in beams do
		p.Parent = nil
	end
end

-- The hatch ---------------------------------------------------------------------------------

local function rarityColor(m): Color3
	if m.variant == 1 then
		return SHINY_GOLD
	end
	return Theme.Rarity(tonumber(m.rarity) or 1)
end

local function hatchSting(m)
	local rarity = tonumber(m.rarity) or 1
	Audio.Chain(AudioRules.HatchChain(rarity, 0))
	if m.variant == 2 then
		Audio.Chain({ "HatchRainbow", "HatchGolden" })
	elseif m.variant == 1 then
		Audio.Play("HatchGolden")
	end
	if rarity >= 6 then
		ctx:Sound("CelebrateHuge")
	elseif rarity >= 5 then
		ctx:Sound("CelebrateBig")
	end
end

-- One egg's beat. `slot` = { entry, egg (our model), center (CFrame), half }.
local function beat(h, slot, montage: boolean, shot)
	local entry = slot.entry
	local m = entry.monster
	local plan = Cinematic.HatchPlan(HATCH, m.rarity, m.variant, montage)
	local color = rarityColor(m)
	local center: CFrame = slot.center
	local ground = center * CFrame.new(0, -slot.half, 0)
	local camera = workspace.CurrentCamera
	local towards = if camera then camera.CFrame.Position else center.Position + Vector3.new(0, 0, 10)
	if montage and slot ~= shot.slots[1] then
		h:Frame(ground.Position, math.max(slot.half * 2 * 1.6, 4), 0.35) -- the next egg on the pad
	end

	-- 1. The wobble with its three cracks (and, for Mythic, beams and a blush on the world).
	local amplitude = if h.reduced then 0.35 else 1
	local beamList = if plan.beams then beamParts(if h.low then BEAMS_LOW else BEAMS, color) else nil
	local pulse = nil
	if plan.pulse then
		pulse = Instance.new("ColorCorrectionEffect")
		pulse.Name = "CinematicPulse"
		pulse.Parent = Lighting
		shot.pulse = pulse
	end
	local tint = Color3.fromHex(HATCH.pulse.tint)
	local cracked = 0
	local skipped = during(h, plan.wobble, function(t)
		local tilt = math.rad(Cinematic.Wobble(plan, t) * amplitude)
		slot.egg:PivotTo(ground * CFrame.Angles(tilt * 0.4, 0, tilt) * CFrame.new(0, slot.half, 0))
		while cracked < 3 and t >= plan.cracks[cracked + 1] do
			cracked += 1
			EggModel.SetCrack(slot.egg, cracked)
			ctx:Sound("EggCrack")
		end
		local a = if plan.wobble > 0 then t / plan.wobble else 1
		if beamList then
			placeBeams(beamList, center, if h.reduced then 0 else t * 1.2, a)
		end
		if pulse then
			local k = a * a
			pulse.TintColor = Color3.new(1, 1, 1):Lerp(tint, k)
			pulse.Saturation = HATCH.pulse.saturation * k
			pulse.Brightness = HATCH.pulse.brightness * k
		end
	end)

	-- 2. The burst, and the monster hops out of it (also the skip target).
	slot.egg:Destroy()
	slot.egg = nil
	Vfx.Burst("hatch", center, { color = color, scale = plan.burst })
	if plan.shiny then
		Vfx.Burst("shinyShower", center * CFrame.new(0, 4, 0), { color = if m.variant == 1 then SHINY_GOLD else nil })
	end
	hatchSting(m)
	entry.inWorld = true
	local okAp, ap = pcall(Appearance.Of, m)
	if okAp then
		local okModel, model = pcall(MonsterModel.Build, ap, { anchored = true, vfx = not h.low })
		if okModel and model then
			model.Parent = stage()
			local face = Vector3.new(towards.X, ground.Position.Y, towards.Z)
			local base = if (face - ground.Position).Magnitude > 0.1 then CFrame.lookAt(ground.Position, face) else ground
			local animator = MonsterAnimator.new(model)
			animator:SetBase(base)
			table.insert(shot.monsters, { model = model, animator = animator })
			if skipped or h.reduced then
				animator:SetBase(base * CFrame.new(0, 0, -2))
				animator:Play("happy")
			else
				animator:MoveTo((base * CFrame.new(0, 0, -2.5)).Position, function()
					animator:Play("happy")
				end)
			end
			task.delay(0.35, Voices.Cry, model, "hatch")
			if entry.isNew then
				stamp(model, "NEW!", C.Gold, 1.2)
			end
			if plan.shiny then
				stamp(model, "SHINY!", color, if entry.isNew then 2.6 else 1.2)
			end
		end
	end
	if skipped then
		return true
	end
	return h:Wait(plan.reveal)
end

local function cleanupHatch(shot)
	for _, slot in shot.slots do
		if slot.egg then
			slot.egg:Destroy()
			slot.egg = nil
		end
	end
	for _, rec in shot.monsters do
		rec.animator:Destroy()
		rec.model:Destroy()
	end
	table.clear(shot.monsters)
	if shot.pulse then
		shot.pulse:Destroy()
		shot.pulse = nil
	end
	dropBeams()
	unhide(shot.hidden)
end

function Cinematics:Hatch(entries, onDone: (boolean) -> ()): boolean
	local cam, w = director(), world()
	if not (cam and w) or #entries == 0 then
		return false
	end
	local first = entries[1]
	local spot = w:IncubatorEgg(tostring(first.egg), tonumber(first.slot) or 1)
	if not spot or not inView(spot.Position) then
		return false
	end
	local current = ctx.Router:Current()
	if current == SOURCE_SCREEN then
		ctx.Router:Close(SOURCE_SCREEN)
		reopen = true
	elseif current ~= nil then
		return false
	end
	if not cam:CanStart() then
		self:ReopenAfterHatch()
		return false
	end

	-- Every egg of the montage sits on the pad from the start; World's own copies are hidden.
	local shot = { slots = {}, monsters = {}, hidden = {}, pulse = nil }
	local taken = {}
	local low = lowGraphics()
	for _, entry in entries do
		local center, worldEgg = w:IncubatorEgg(tostring(entry.egg), tonumber(entry.slot) or 1, taken)
		if center then
			if worldEgg then
				taken[worldEgg] = true
				hide(shot.hidden, worldEgg)
			end
			local eggType = if Config.Eggs.ById[entry.egg] or entry.egg == "starter" then entry.egg else "meadow"
			local ok, egg = pcall(EggModel.Build, eggType, { anchored = true, vfx = not low })
			if ok and egg then
				local root = egg.PrimaryPart
				local half = if root then root.Size.Y / 2 else 1.3
				egg:PivotTo(center)
				egg.Parent = stage()
				table.insert(shot.slots, { entry = entry, egg = egg, center = center, half = half })
			end
		end
	end
	if #shot.slots == 0 then
		unhide(shot.hidden)
		self:ReopenAfterHatch()
		return false
	end
	played.hatch += 1
	local montage = #shot.slots > 1
	local base = shot.slots[1]
	cam:Play({
		position = (base.center * CFrame.new(0, -base.half, 0)).Position,
		height = math.max(base.half * 2 * 1.6, 4),
		run = function(h)
			for _, slot in shot.slots do
				if beat(h, slot, montage, shot) then
					break
				end
			end
			for _, slot in shot.slots do
				slot.entry.inWorld = true -- a skip jumps to the summary cards
			end
		end,
		onDone = function(ran: boolean)
			cleanupHatch(shot)
			onDone(ran)
		end,
	})
	return true
end

function Cinematics:ReopenAfterHatch()
	if reopen then
		reopen = false
		if ctx.Router:Current() == nil and ctx.Router:Has(SOURCE_SCREEN) then
			ctx.Router:Open(SOURCE_SCREEN)
		end
	end
end

-- Discovery ---------------------------------------------------------------------------------

local function onCodex(codex)
	if type(codex) ~= "table" then
		return
	end
	local first = known == nil
	known = known or {}
	for line, entry in codex do
		if type(entry) == "table" and type(entry.forms) == "table" then
			for form in entry.forms do
				local key = tostring(line) .. ":" .. tostring(form)
				if not known[key] then
					known[key] = true
					if not first then
						fresh[key] = os.clock() -- the codex beat the Eggs.Hatched event here
					end
				end
			end
		end
	end
end

function Cinematics:ClaimNew(monster): boolean
	if type(monster) ~= "table" or type(monster.line) ~= "string" or type(monster.form) ~= "string" then
		return false
	end
	local key = monster.line .. ":" .. monster.form
	local isNew
	if known == nil then
		isNew = Cinematic.IsNewForm(ctx.Store:Get("profile.Monsters.codex"), monster.line, monster.form)
		known = {}
	else
		isNew = not known[key] or (fresh[key] ~= nil and os.clock() - fresh[key] < FRESH_SECONDS)
	end
	known[key] = true
	fresh[key] = nil
	return isNew
end

-- Evolution ---------------------------------------------------------------------------------

local function evolveAppearances(payload)
	local toInfo = Config.Species.FormById[payload.toForm or ""]
	local m = StoreKit.monster(ctx.Store, payload.id)
	local lineId = (m and m.line) or (toInfo and toInfo.line.id)
	if not lineId then
		return nil
	end
	local rarity = m and m.rarity or 1
	local variant = m and m.variant or 0
	local stageNo = tonumber(payload.stage) or (toInfo and toInfo.stage) or 2
	local okFrom, fromAp = pcall(Appearance.Preview, lineId, math.max(1, stageNo - 1), payload.fromForm, rarity, variant)
	local okTo, toAp = false, nil
	if m and m.form == payload.toForm then
		okTo, toAp = pcall(Appearance.Of, m)
	else
		okTo, toAp = pcall(Appearance.Preview, lineId, stageNo, payload.toForm, rarity, variant)
	end
	if not (okFrom and okTo) then
		return nil
	end
	local line = Config.Species.ById[lineId]
	return fromAp, toAp, if line then line.elements else nil
end

local function canShoot(id: any)
	local cam, w = director(), world()
	if not (cam and w and cam:CanStart()) then
		return nil
	end
	local own = w:OwnMonster(id)
	if not own or not inView(own.animator:GetPosition()) then
		return nil
	end
	return own
end

local function playEvolve(payload, own, showCard: (() -> ())?)
	local fromAp, toAp, elements = evolveAppearances(payload)
	if not fromAp then
		return false
	end
	local okOld, oldModel = pcall(MonsterModel.Build, fromAp, { anchored = true, vfx = false })
	local okNew, newModel = pcall(MonsterModel.Build, toAp, { anchored = true, vfx = false })
	if not (okOld and okNew and oldModel and newModel) then
		return false
	end
	local w = world()
	local id = payload.id
	local ground: Vector3 = own.animator:GetPosition()
	local facing = own.model:GetPivot().Rotation
	local base = CFrame.new(ground) * facing
	local height = math.max(tonumber(newModel:GetAttribute("Height")) or 3, tonumber(oldModel:GetAttribute("Height")) or 3)
	local color = if type(elements) == "table" and elements[1] then Theme.Element(elements[1]) else C.White
	local hidden = {}
	played.evolve += 1

	oldModel.Parent = stage()
	newModel.Parent = stage()
	local oldAnim, newAnim = MonsterAnimator.new(oldModel), MonsterAnimator.new(newModel)
	oldAnim:SetBase(base)
	newAnim:SetBase(base)
	local oldParts, newParts = parts(oldModel), parts(newModel)
	setShown(newParts, false)
	local glow = Instance.new("Highlight")
	glow.Name = "EvolveGlow"
	glow.FillColor = C.White
	glow.OutlineColor = C.White
	glow.FillTransparency = 1
	glow.OutlineTransparency = 1
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Adornee = oldModel
	glow.Parent = stage()
	local flashGui: Frame? = nil

	local function keepWorldHidden()
		local now = w:OwnMonster(id, 2)
		if now then
			hide(hidden, now.model)
			now.animator:SetBase(base)
		end
	end

	local function cleanup()
		oldAnim:Destroy()
		newAnim:Destroy()
		oldModel:Destroy()
		newModel:Destroy()
		glow:Destroy()
		if flashGui then
			flashGui:Destroy()
		end
		unhide(hidden)
		-- The new form stands where the old one did, not at a random spot in the pen.
		local deadline = os.clock() + 4
		task.spawn(function()
			while os.clock() < deadline do
				local now = w:OwnMonster(id, 1)
				if now and now.model:GetAttribute("Form") == payload.toForm then
					now.animator:SetBase(base)
					now.animator:Play("happy")
					return
				end
				task.wait(0.25)
			end
		end)
	end

	director():Play({
		position = ground,
		height = height,
		run = function(h)
			keepWorldHidden()
			local showingNew, spinAngle, nextVortex, nextCheck = false, 0, 0, 0
			local flashed, landed = false, false
			local last = 0
			local total = Cinematic.EvolveLength(EVOLVE)
			local skipped = during(h, total, function(t)
				local s = Cinematic.EvolveAt(EVOLVE, t)
				local dt = t - last
				last = t
				if t >= nextCheck then
					nextCheck = t + 0.25
					keepWorldHidden()
				end
				if s.new ~= showingNew then
					showingNew = s.new
					setShown(oldParts, not showingNew)
					setShown(newParts, showingNew)
					glow.Adornee = if showingNew then newModel else oldModel
				end
				glow.FillTransparency = 1 - 0.85 * s.glow
				glow.OutlineTransparency = 1 - s.glow
				if not h.reduced then
					spinAngle += s.spin * math.pi * 2 * dt
				end
				local lift = if s.phase == "spin" or s.phase == "flash" then 0.6 * math.min(1, s.spin / EVOLVE.spinTurns) else 0
				local cf = base * CFrame.new(0, lift, 0) * CFrame.Angles(0, spinAngle, 0)
				oldAnim:SetBase(cf)
				newAnim:SetBase(cf)
				if (s.phase == "spin" or s.phase == "glow") and t >= nextVortex then
					nextVortex = t + EVOLVE.vortexEvery
					Vfx.Burst("evolveVortex", base, { color = color, scale = height / 3 })
				end
				if s.phase == "flash" and not flashed then
					flashed = true
					Vfx.Burst("evolve", base, { elements = elements, scale = height / 3 })
					ctx:Sound("Evolve")
					if not h.reduced then
						local gui = New("Frame", {
							Name = "EvolveFlash",
							BackgroundColor3 = C.White,
							BackgroundTransparency = 0.1,
							Size = UDim2.fromScale(1, 1),
							ZIndex = 39,
							Parent = ctx.UI.Top,
						})
						flashGui = gui
						Anim.tween(gui, { BackgroundTransparency = 1 }, 0.5)
					end
				end
				if s.phase == "land" and not landed then
					landed = true
					newAnim:SetBase(base)
					newAnim:Play("happy")
					Voices.Cry(newModel, "evolve")
				end
			end)
			if skipped then
				setShown(oldParts, false)
				setShown(newParts, true)
			end
		end,
		onDone = function()
			cleanup()
			if showCard then
				showCard()
			end
		end,
	})
	return true
end

function Cinematics:TakeEvolve(payload, showCard: () -> ()): boolean
	if type(payload) ~= "table" or payload.id == nil then
		return false
	end
	local own = canShoot(payload.id)
	if not (own and playEvolve(payload, own, showCard)) then
		return false
	end
	evolveClaimed[payload.id] = true -- World's evolve moment then has nothing left to show
	return true
end

function Cinematics:Evolved(payload): boolean
	if type(payload) ~= "table" or payload.id == nil then
		return false
	end
	if evolveClaimed[payload.id] then
		evolveClaimed[payload.id] = nil
		return true
	end
	local own = canShoot(payload.id)
	return own ~= nil and playEvolve(payload, own, nil)
end

-- Star-ups and level-ups --------------------------------------------------------------------

function Cinematics:Spotlight(id: any, burst: string): boolean
	local own = canShoot(id)
	if not own then
		return false
	end
	played.spotlight += 1
	local height = tonumber(own.model:GetAttribute("Height")) or 3
	world():OwnMonster(id, Tuning.Spotlight.hold + 1.5)
	director():Play({
		position = own.animator:GetPosition(),
		height = height,
		run = function(h)
			if h:Wait(if h.reduced then 0.1 else CAM.glideIn * 0.8) then
				return
			end
			local root = own.model.PrimaryPart
			if root then
				Vfx.Burst(burst, root.CFrame, { scale = height / 3 })
			end
			own.animator:Play("happy")
			Voices.Cry(own.model, "levelUp")
			h:Wait(Tuning.Spotlight.hold)
		end,
	})
	return true
end

function Cinematics:Played()
	return table.clone(played)
end

function Cinematics.Init(context)
	ctx = context
end

function Cinematics.Start()
	ctx.Store:Observe("profile.Monsters.codex", onCodex)
end

return Cinematics
