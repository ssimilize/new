--[[
	Vfx: builds the particle effects described in Config/Vfx (data) with the sprites in
	Config/VfxSprites (generated ids). Client only; every call is safe in the Lune test mock and
	never errors on a missing sprite (that emitter is skipped).

		Vfx.AttachMonster(model, appearance) -> number    element auras (two elements: half rate each),
		                                                   mutations, shiny / rainbow, epic+ ground glow,
		                                                   the mastery aura (appearance.aura, 3.3);
		                                                   returns how many emitters it made
		Vfx.SetOwned(model, owned)                         false = on another player's plot (World)
		Vfx.AttachEgg(model, eggType, ready?) -> number    the egg's own sparkle (Config.Vfx.Eggs) and,
		                                                   while ready to hatch, Config.Vfx.EggReady;
		                                                   sized by the egg's height (EggRefHeight).
		                                                   EggModel calls it (Build, SetReady)
		Vfx.AttachLandmark(instance, id) -> Folder?        a building Model with a Body (a hub building,
		                                                   the Sky Gate; placed in its visible box) or a
		                                                   BasePart; id is a Config.Vfx.Landmarks key
		Vfx.Burst(name, cframeOrPosition, opts?) -> number one-shot :Emit from pooled emitters; returns
		                                                   how many emitters fired (0 = nothing to show:
		                                                   unknown name or no sprite uploaded yet)
		    opts.color   Color3 for specs marked useColor (hatch: the rarity colour)
		    opts.scale   multiplies sizes and speeds (a monster's Height / RefHeight)
		    opts.elements  { elementId }: also throws each aura's sprites (evolve)
		Vfx.SetNight(amount)                               0 = day .. 1 = night: glowing sprites glow more
		                                                   (Config.Vfx.Night); the Landmarks controller
		                                                   feeds it NightFromClock(Lighting.ClockTime)
		Vfx.NightFromClock(clockTime) -> number            0..1, smooth through dusk and dawn
		Vfx.SetQuality(low)                                low graphics: other plots' auras and rarity
		                                                   glows off, mutation / variant / landmark rates
		                                                   halved, bursts halved
		Vfx.Clear(modelOrInstance)                         removes what Attach* made
		Vfx.Count(modelOrInstance) -> number               emitters attached (tests, debugging)

	Monsters: emitters sit on attachments the module adds to Root ("VfxFeet", "VfxCore", "VfxHead",
	one per anchor and offset) or, for at = "body", on "VfxVolume", an invisible massless part welded
	to Root round the body. Hovering body types (moth, sprite) emit "feet" effects from the core.
	Sizes, speeds, accelerations and offsets scale with the model's Height attribute. MonsterModel
	calls AttachMonster for both the mesh and the placeholder path (opts.vfx == false skips it).

	Landmarks: the emitters live on anchored invisible parts in Workspace.VfxClient, placed in the
	box of the building's visible parts (World/Dress's 3D mesh pieces, which are smaller than the
	placeholder) in its Body's orientation, or in Body itself while nothing is visible. The Landmarks
	controller attaches again once Dress's pieces stop arriving; if the anchor leaves the Workspace
	the effect is cleared, and a new building is attached when it appears.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Config = require(ConfigFolder)
local Presets = require(ConfigFolder:WaitForChild("Vfx"))
local spritesModule = ConfigFolder:FindFirstChild("VfxSprites")
local Sprites = {}
if spritesModule then
	local ok, list = pcall(require, spritesModule)
	if ok and type(list) == "table" then
		Sprites = list
	end
end

local Vfx = {}

local POINT = Vector3.new(0.2, 0.2, 0.2)
local HOVERING = { moth = true, sprite = true }
local KIND_OFF_ON_OTHER_PLOTS = { aura = true, rarity = true, mastery = true }
local KIND_HALVED = { mutation = true, variant = true, landmark = true, egg = true }

type Rec = { emitter: ParticleEmitter, rate: number, kind: string, spec: any }
type Entry = { recs: { Rec }, owned: boolean, made: { Instance }, connection: RBXScriptConnection? }

local low = false
local night = 0 -- 0 = day .. 1 = night (Vfx.SetNight)
local registry: { [Instance]: Entry } = setmetatable({}, { __mode = "k" }) :: any
local pools: { [string]: { { part: BasePart, emitter: ParticleEmitter, spec: any } } } = {}
local container: Folder? = nil
local burstFolder: Folder? = nil

-- ─── Specs → emitters ────────────────────────────────────────────────────────────────

-- The sprite's texture id, or nil when it has not been uploaded (the emitter is skipped).
local function texture(spec): string?
	local entry = Sprites[spec.sprite]
	if type(entry) ~= "table" then
		return nil
	end
	local id = if spec.grey then entry.grey else entry.color
	if type(id) ~= "string" or id == "" then
		return nil
	end
	return id
end

local function colorSequence(value, override: Color3?): ColorSequence
	if override then
		return ColorSequence.new(override)
	end
	if type(value) == "string" then
		return ColorSequence.new(Color3.fromHex(value))
	elseif type(value) == "table" then
		local keys = {}
		for _, k in value do
			table.insert(keys, ColorSequenceKeypoint.new(k[1], Color3.fromHex(k[2])))
		end
		return ColorSequence.new(keys)
	end
	return ColorSequence.new(Color3.new(1, 1, 1))
end

local function numberSequence(value, k: number): NumberSequence
	if type(value) == "number" then
		return NumberSequence.new(value * k)
	end
	local keys = {}
	for _, p in value do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2] * k))
	end
	return NumberSequence.new(keys)
end

local function range(value, k: number): NumberRange
	if type(value) == "number" then
		return NumberRange.new(value * k)
	elseif type(value) == "table" then
		return NumberRange.new(value[1] * k, value[2] * k)
	end
	return NumberRange.new(0)
end

-- Builds one emitter from a spec (k scales sizes, speeds and accelerations). nil when the sprite
-- is missing or the spec cannot be built; never errors.
local function build(spec, k: number, colorOverride: Color3?): ParticleEmitter?
	local id = texture(spec)
	if not id then
		return nil
	end
	local ok, emitter = pcall(function()
		local e = Instance.new("ParticleEmitter")
		e.Texture = id
		e.Color = colorSequence(spec.color, colorOverride)
		e.Size = numberSequence(spec.size or 1, k)
		e.Transparency = numberSequence(spec.transparency or Presets.Fade, 1)
		e.Lifetime = range(spec.lifetime or { 1, 1 }, 1)
		e.Speed = range(spec.speed or 0, k)
		local spread = spec.spread or 0
		e.SpreadAngle = if type(spread) == "table" then Vector2.new(spread[1], spread[2]) else Vector2.new(spread, spread)
		local a = spec.accel
		e.Acceleration = if a then Vector3.new(a[1], a[2], a[3]) * k else Vector3.zero
		e.Drag = spec.drag or 0
		e.Rotation = range(spec.rot or 0, 1)
		e.RotSpeed = range(spec.rotSpeed or 0, 1)
		e.LightEmission = spec.lightEmission or 0.2
		e.LightInfluence = spec.lightInfluence or 0.3
		e.Orientation = (Enum.ParticleOrientation :: any)[spec.orientation or "FacingCamera"]
		e.EmissionDirection = (Enum.NormalId :: any)[spec.direction or "Top"]
		if spec.shape then
			e.Shape = (Enum.ParticleEmitterShape :: any)[spec.shape]
		end
		if spec.shapeStyle then
			e.ShapeStyle = (Enum.ParticleEmitterShapeStyle :: any)[spec.shapeStyle]
		end
		if spec.shapeInOut then
			e.ShapeInOut = (Enum.ParticleEmitterShapeInOut :: any)[spec.shapeInOut]
		end
		e.ZOffset = spec.zOffset or 0
		e.LockedToPart = spec.lockedToPart == true
		e.Rate = 0
		return e
	end)
	if not ok then
		warn("[Vfx] could not build a " .. tostring(spec.sprite) .. " emitter: " .. tostring(emitter))
		return nil
	end
	return emitter
end

local function factor(kind: string, owned: boolean): number
	if not low then
		return 1
	end
	if KIND_OFF_ON_OTHER_PLOTS[kind] then
		return if owned then 1 else 0
	end
	return if KIND_HALVED[kind] then 0.5 else 1
end

-- The night glow: LightEmission lifted and LightInfluence lowered by the sprite's weight
-- (Config.Vfx.Night) times how dark it is. By day this is the spec's own values.
local function lit(emitter: ParticleEmitter, spec)
	local base = spec.lightEmission or 0.2
	local influence = spec.lightInfluence or 0.3
	local cfg = Presets.Night
	local weight = if type(spec.night) == "number" then spec.night elseif cfg then cfg.sprites[spec.sprite] or 0 else 0
	local k = weight * night
	if cfg and k > 0 then
		emitter.LightEmission = math.min(base + cfg.boost * k, math.max(base, cfg.cap))
		emitter.LightInfluence = influence * (1 - k)
	else
		emitter.LightEmission = base
		emitter.LightInfluence = influence
	end
end

local function apply(entry: Entry)
	for _, rec in entry.recs do
		local f = factor(rec.kind, entry.owned)
		rec.emitter.Rate = rec.rate * f
		rec.emitter.Enabled = f > 0
		lit(rec.emitter, rec.spec)
	end
end

local function holder(): Folder
	if container and container.Parent then
		return container
	end
	local folder = workspace:FindFirstChild("VfxClient")
	if not (folder and folder:IsA("Folder")) then
		folder = Instance.new("Folder")
		folder.Name = "VfxClient"
		folder.Parent = workspace
	end
	container = folder :: Folder
	return folder :: Folder
end

local function invisiblePart(name: string, size: Vector3, cframe: CFrame, anchored: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Transparency = 1
	p.Anchored = anchored
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	return p
end

-- ─── Monsters ────────────────────────────────────────────────────────────────────────

function Vfx.AttachMonster(model: Model, appearance): number
	if typeof(model) ~= "Instance" or type(appearance) ~= "table" then
		return 0
	end
	Vfx.Clear(model)
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then
		return 0
	end
	local height = model:GetAttribute("Height")
	if type(height) ~= "number" or height <= 0 then
		height = root.Size.Y
	end
	local k = math.clamp(height / Presets.RefHeight, 0.4, 4)
	local hover = HOVERING[appearance.archetype] == true
	local entry: Entry = { recs = {}, owned = true, made = {} }
	local anchors: { [string]: Instance } = {}

	local function anchorFor(spec): Instance
		local at = spec.at or "core"
		if at == "feet" and hover then
			at = "core"
		end
		local o = spec.offset
		local key = at .. (if o then string.format("%g,%g,%g", o[1], o[2], o[3]) else "")
		local found = anchors[key]
		if found then
			return found
		end
		local made: Instance
		if at == "body" then
			local width = math.min(root.Size.X, height) * 0.9
			local centre = root.CFrame * CFrame.new(0, height * 0.5, 0)
			local volume = invisiblePart("VfxVolume", Vector3.new(width, height * 0.8, width), centre, false)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = volume
			weld.Parent = volume
			volume.Parent = model
			made = volume
		else
			local y = if at == "feet" then 0 elseif at == "head" then height else height * 0.5
			local attachment = Instance.new("Attachment")
			attachment.Name = "Vfx" .. string.upper(string.sub(at, 1, 1)) .. string.sub(at, 2)
			attachment.Position = Vector3.new(0, y, 0) + (if o then Vector3.new(o[1], o[2], o[3]) * k else Vector3.zero)
			attachment.Parent = root
			made = attachment
		end
		table.insert(entry.made, made)
		anchors[key] = made
		return made
	end

	local function add(specs, kind: string, share: number)
		for _, spec in specs or {} do
			local emitter = build(spec, k)
			if emitter then
				emitter.Parent = anchorFor(spec)
				table.insert(entry.recs, { emitter = emitter, rate = (spec.rate or 0) * share, kind = kind, spec = spec })
			end
		end
	end

	local elements = if type(appearance.elements) == "table" then appearance.elements else {}
	for _, element in elements do
		add(Presets.Auras[element], "aura", 1 / #elements)
	end
	for _, m in if type(appearance.muts) == "table" then appearance.muts else {} do
		add(Presets.Mutations[m], "mutation", 1)
	end
	if appearance.variant == 1 then
		add(Presets.Variants.shiny, "variant", 1)
	elseif appearance.variant == 2 then
		add(Presets.Variants.rainbow, "variant", 1)
	end
	local rarity = appearance.rarity
	local rarityDef = if type(rarity) == "number" then Config.Rarities.Get(rarity) else Config.Rarities.ById[rarity]
	if rarityDef then
		add(Presets.Rarity[rarityDef.id], "rarity", 1)
	end
	if type(appearance.aura) == "string" and Presets.Mastery then
		add(Presets.Mastery[appearance.aura], "mastery", 1)
	end

	if #entry.recs == 0 then
		return 0
	end
	registry[model] = entry
	apply(entry)
	return #entry.recs
end

function Vfx.SetOwned(model: Instance, owned: boolean)
	local entry = registry[model]
	if entry and entry.owned ~= owned then
		entry.owned = owned
		apply(entry)
	end
end

-- ─── Eggs ───────────────────────────────────────────────────────────────────────────

-- Anchors as for monsters, measured on the egg: "feet" its bottom, "core" its centre, "head" its
-- top, "body" an invisible part the size of the shell (sparkles on its surface).
function Vfx.AttachEgg(model: Model, eggType: string, ready: boolean?): number
	if typeof(model) ~= "Instance" or type(eggType) ~= "string" then
		return 0
	end
	Vfx.Clear(model)
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then
		return 0
	end
	local height = root.Size.Y
	local k = math.clamp(height / (Presets.EggRefHeight or 2.6), 0.4, 4)
	local entry: Entry = { recs = {}, owned = true, made = {} }
	local anchors: { [string]: Instance } = {}

	local function anchorFor(spec): Instance
		local at = spec.at or "core"
		local found = anchors[at]
		if found then
			return found
		end
		local made: Instance
		if at == "body" then
			local volume = invisiblePart("VfxVolume", root.Size, root.CFrame, false)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = volume
			weld.Parent = volume
			volume.Parent = model
			made = volume
		else
			local attachment = Instance.new("Attachment")
			attachment.Name = "VfxEgg" .. string.upper(string.sub(at, 1, 1)) .. string.sub(at, 2)
			attachment.Position = Vector3.new(0, if at == "feet" then -height / 2 elseif at == "head" then height / 2 else 0, 0)
			attachment.Parent = root
			made = attachment
		end
		table.insert(entry.made, made)
		anchors[at] = made
		return made
	end

	local function add(specs)
		for _, spec in specs or {} do
			local emitter = build(spec, k)
			if emitter then
				emitter.Parent = anchorFor(spec)
				table.insert(entry.recs, { emitter = emitter, rate = spec.rate or 0, kind = "egg", spec = spec })
			end
		end
	end

	add(Presets.Eggs and Presets.Eggs[eggType])
	if ready then
		add(Presets.EggReady)
	end
	if #entry.recs == 0 then
		for _, inst in entry.made do
			inst:Destroy()
		end
		return 0
	end
	registry[model] = entry
	apply(entry)
	return #entry.recs
end

-- ─── Landmarks ───────────────────────────────────────────────────────────────────────

-- The box a landmark's `at` fractions are measured in: the visible parts of a dressed building
-- (World/Dress's 3D mesh pieces, usually smaller than the placeholder), in the anchor's orientation;
-- the anchor itself while the building is still the placeholder or has nothing visible.
local function landmarkFrame(instance: Instance, anchor: BasePart): (CFrame, Vector3)
	local rot = anchor.CFrame.Rotation
	local lo, hi
	if instance ~= anchor then
		for _, part in instance:GetDescendants() do
			if part:IsA("BasePart") and part ~= anchor and part.Transparency < 1 then
				local c = rot:PointToObjectSpace(part.Position)
				local half = part.Size / 2
				-- the part's box in the anchor's axes (conservative for rotated pieces)
				local r = rot:ToObjectSpace(part.CFrame.Rotation)
				local e = Vector3.new(
					math.abs(r.XVector.X) * half.X + math.abs(r.YVector.X) * half.Y + math.abs(r.ZVector.X) * half.Z,
					math.abs(r.XVector.Y) * half.X + math.abs(r.YVector.Y) * half.Y + math.abs(r.ZVector.Y) * half.Z,
					math.abs(r.XVector.Z) * half.X + math.abs(r.YVector.Z) * half.Y + math.abs(r.ZVector.Z) * half.Z
				)
				lo = if lo then lo:Min(c - e) else c - e
				hi = if hi then hi:Max(c + e) else c + e
			end
		end
	end
	if not lo then
		return anchor.CFrame, anchor.Size
	end
	return rot + rot:PointToWorldSpace((lo + hi) / 2), hi - lo
end

function Vfx.AttachLandmark(instance: Instance, id: string): Folder?
	local specs = Presets.Landmarks[id]
	if typeof(instance) ~= "Instance" or not specs then
		return nil
	end
	Vfx.Clear(instance)
	local anchor = if instance:IsA("BasePart")
		then instance
		else instance:FindFirstChild("Body") or (if instance:IsA("Model") then instance.PrimaryPart else nil)
	if not (anchor and anchor:IsA("BasePart")) then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "Vfx_" .. id
	local entry: Entry = { recs = {}, owned = true, made = { folder } }
	local frame, size = landmarkFrame(instance, anchor)
	for i, spec in specs do
		local emitter = build(spec, 1)
		if emitter then
			local at = spec.at or { 0, 0, 0 }
			local box = spec.box
			local cf = frame * CFrame.new(at[1] * size.X, at[2] * size.Y, at[3] * size.Z)
			local p = invisiblePart("Emitter" .. i, if box then Vector3.new(box[1], box[2], box[3]) else POINT, cf, true)
			emitter.Parent = p
			p.Parent = folder
			table.insert(entry.recs, { emitter = emitter, rate = spec.rate or 0, kind = "landmark", spec = spec })
		end
	end
	folder.Parent = holder()
	entry.connection = anchor.AncestryChanged:Connect(function()
		if not anchor:IsDescendantOf(workspace) then
			Vfx.Clear(instance)
		end
	end)
	registry[instance] = entry
	apply(entry)
	return folder
end

-- ─── Bursts ──────────────────────────────────────────────────────────────────────────

local function burstParent(): Folder
	if burstFolder and burstFolder.Parent then
		return burstFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "Bursts"
	folder.Parent = holder()
	burstFolder = folder
	return folder
end

-- The pooled emitters for a list of specs at one size step, built on first use.
local function pool(key: string, specs, scale: number)
	local list = pools[key]
	if list then
		local alive = true
		for _, rec in list do
			if rec.part.Parent == nil then
				alive = false
			end
		end
		if alive then
			return list
		end
		for _, rec in list do
			rec.part:Destroy()
		end
	end
	list = {}
	for i, spec in specs do
		local emitter = build(spec, scale)
		if emitter then
			emitter.LockedToPart = false
			local box = spec.box
			local p = invisiblePart(
				key .. "_" .. i,
				if box then Vector3.new(box[1], box[2], box[3]) * scale else POINT,
				CFrame.new(0, -500, 0),
				true
			)
			emitter.Parent = p
			p.Parent = burstParent()
			table.insert(list, { part = p, emitter = emitter, spec = spec })
		end
	end
	pools[key] = list
	return list
end

local function fire(list, cf: CFrame, color: Color3?, count: (any) -> number): number
	local fired = 0
	for _, rec in list do
		rec.part.CFrame = cf
		if rec.spec.useColor then
			rec.emitter.Color = colorSequence(rec.spec.color, color)
		end
		local n = count(rec.spec)
		if n > 0 then
			lit(rec.emitter, rec.spec)
			rec.emitter:Emit(if low then math.ceil(n / 2) else n)
			fired += 1
		end
	end
	return fired
end

function Vfx.Burst(name: string, where: CFrame | Vector3, opts: { color: Color3?, scale: number?, elements: { string }? }?): number
	local specs = Presets.Bursts[name]
	local cf = if typeof(where) == "CFrame" then where elseif typeof(where) == "Vector3" then CFrame.new(where) else nil
	if not cf then
		return 0
	end
	local options = opts or {}
	local scale = math.clamp(math.floor((options.scale or 1) * 4 + 0.5) / 4, 0.25, 4) -- pooled per quarter step
	local fired = 0
	if specs then
		fired += fire(pool(name .. "@" .. scale, specs, scale), cf, options.color, function(spec)
			return spec.emit or 0
		end)
	end
	for _, element in options.elements or {} do
		local aura = Presets.Auras[element]
		if aura then
			fired += fire(pool("aura_" .. element .. "@" .. scale, aura, scale), cf, nil, function()
				return Presets.EvolveElementEmit
			end)
		end
	end
	return fired
end

-- ─── Quality and cleanup ─────────────────────────────────────────────────────────────

-- 0 by day, 1 at night, a smooth ramp through Config.Vfx.Night's dusk and dawn hours.
function Vfx.NightFromClock(clockTime: number): number
	local cfg = Presets.Night
	if not cfg or type(clockTime) ~= "number" then
		return 0
	end
	local c = clockTime % 24
	local function ramp(from: number, to: number): number
		local p = math.clamp((c - from) / (to - from), 0, 1)
		return p * p * (3 - 2 * p)
	end
	if c >= cfg.dawn[1] and c <= cfg.dawn[2] then
		return 1 - ramp(cfg.dawn[1], cfg.dawn[2])
	elseif c >= cfg.dusk[1] and c <= cfg.dusk[2] then
		return ramp(cfg.dusk[1], cfg.dusk[2])
	elseif c > cfg.dawn[2] and c < cfg.dusk[1] then
		return 0
	end
	return 1
end

function Vfx.SetNight(amount: number)
	local value = math.clamp(tonumber(amount) or 0, 0, 1)
	if math.abs(value - night) < 0.01 and not (value == 0 and night ~= 0) and not (value == 1 and night ~= 1) then
		return
	end
	night = value
	for _, entry in registry do
		apply(entry)
	end
end

function Vfx.SetQuality(isLow: boolean)
	low = isLow == true
	for _, entry in registry do
		apply(entry)
	end
end

function Vfx.Clear(target: Instance)
	local entry = registry[target]
	if not entry then
		return
	end
	registry[target] = nil
	if entry.connection then
		entry.connection:Disconnect()
	end
	for _, rec in entry.recs do
		rec.emitter:Destroy()
	end
	for _, inst in entry.made do
		inst:Destroy()
	end
end

function Vfx.Count(target: Instance): number
	local entry = registry[target]
	return if entry then #entry.recs else 0
end

return Vfx
