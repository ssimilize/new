--[[
	SceneryFx: pooled particle holders for scenery effects (Config.Vfx.Scenery: campfire flames,
	windmill leaves, the fountain's water). Same spec format and sprite rules as Visuals/Vfx; kept
	separate so the scenery pool can move emitters between items instead of creating them.

		SceneryFx.new(id) -> holder?        a holder of one invisible anchored part per spec (a spec
		                                    whose sprite is not uploaded is skipped; nil when none is left)
		holder:Place(center, size, boxOf?)  moves the parts: spec.at is a fraction of the box
		                                    (center, size); spec.on names a part and boxOf(name) returns
		                                    its (center, size) (the fountain)
		holder:SetActive(on)                emitters on (their rate) or off (particles in flight finish)
		holder.active, holder.item          bookkeeping for the caller (item = the scenery part it sits on)
		holder:Destroy()
		SceneryFx.SetNight(0..1)            flames and embers glow at night (Config.Vfx.Night weights)
		SceneryFx.SetQuality(low)           lowGraphics halves every rate
		SceneryFx.Count() -> number         live holders (tests)

	Holders live in Workspace.VfxClient.Scenery.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Presets = require(ConfigFolder:WaitForChild("Vfx"))
local spritesModule = ConfigFolder:FindFirstChild("VfxSprites")
local Sprites = {}
if spritesModule then
	local ok, list = pcall(require, spritesModule)
	if ok and type(list) == "table" then
		Sprites = list
	end
end

local SceneryFx = {}

local POINT = Vector3.new(0.2, 0.2, 0.2)

local low = false
local night = 0
local holders = {}
local folder: Folder? = nil

local Holder = {}
Holder.__index = Holder

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

local function colorSequence(value): ColorSequence
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

local function numberSequence(value): NumberSequence
	if type(value) == "number" then
		return NumberSequence.new(value)
	end
	local keys = {}
	for _, p in value do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function range(value): NumberRange
	if type(value) == "number" then
		return NumberRange.new(value)
	elseif type(value) == "table" then
		return NumberRange.new(value[1], value[2])
	end
	return NumberRange.new(0)
end

local function build(spec): ParticleEmitter?
	local id = texture(spec)
	if not id then
		return nil
	end
	local ok, emitter = pcall(function()
		local e = Instance.new("ParticleEmitter")
		e.Texture = id
		e.Color = colorSequence(spec.color)
		e.Size = numberSequence(spec.size or 1)
		e.Transparency = numberSequence(spec.transparency or Presets.Fade)
		e.Lifetime = range(spec.lifetime or { 1, 1 })
		e.Speed = range(spec.speed or 0)
		local spread = spec.spread or 0
		e.SpreadAngle = if type(spread) == "table" then Vector2.new(spread[1], spread[2]) else Vector2.new(spread, spread)
		local a = spec.accel
		e.Acceleration = if a then Vector3.new(a[1], a[2], a[3]) else Vector3.zero
		e.Drag = spec.drag or 0
		e.Rotation = range(spec.rot or 0)
		e.RotSpeed = range(spec.rotSpeed or 0)
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
		e.Rate = 0
		e.Enabled = false
		return e
	end)
	if not ok then
		warn("[SceneryFx] could not build a " .. tostring(spec.sprite) .. " emitter: " .. tostring(emitter))
		return nil
	end
	return emitter
end

-- Visuals/Vfx's night rule: LightEmission lifted and LightInfluence lowered by the sprite's weight.
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

local function holderFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local root = workspace:FindFirstChild("VfxClient")
	if not (root and root:IsA("Folder")) then
		root = Instance.new("Folder")
		root.Name = "VfxClient"
		root.Parent = workspace
	end
	local existing = root:FindFirstChild("Scenery")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		local f = Instance.new("Folder")
		f.Name = "Scenery"
		f.Parent = root
		folder = f
	end
	return folder :: Folder
end

function Holder:_apply()
	local k = if low then 0.5 else 1
	for _, rec in self.recs do
		rec.emitter.Rate = rec.spec.rate * k
		rec.emitter.Enabled = self.active
		lit(rec.emitter, rec.spec)
	end
end

function Holder:Place(center: Vector3, size: Vector3, boxOf: ((string) -> (Vector3?, Vector3?))?)
	for _, rec in self.recs do
		local c, s = center, size
		if rec.spec.on and boxOf then
			local oc, os = boxOf(rec.spec.on)
			if oc and os then
				c, s = oc, os
			end
		end
		local at = rec.spec.at or { 0, 0, 0 }
		rec.part.CFrame = CFrame.new(c + Vector3.new(at[1] * s.X, at[2] * s.Y, at[3] * s.Z))
	end
end

function Holder:SetActive(on: boolean)
	on = on == true
	if on == self.active then
		return
	end
	self.active = on
	for _, rec in self.recs do
		rec.emitter.Enabled = on
	end
end

function Holder:Destroy()
	for _, rec in self.recs do
		rec.part:Destroy()
	end
	table.clear(self.recs)
	local i = table.find(holders, self)
	if i then
		table.remove(holders, i)
	end
end

function SceneryFx.new(id: string)
	local specs = Presets.Scenery and Presets.Scenery[id]
	if type(specs) ~= "table" then
		return nil
	end
	local self = setmetatable({ id = id, recs = {}, active = false, item = nil }, Holder)
	local parent = holderFolder()
	for i, spec in specs do
		local emitter = build(spec)
		if emitter then
			local box = spec.box
			local p = Instance.new("Part")
			p.Name = id .. "Fx" .. i
			p.Size = if box then Vector3.new(box[1], box[2], box[3]) else POINT
			p.CFrame = CFrame.new(0, -500, 0)
			p.Transparency = 1
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			emitter.Parent = p
			p.Parent = parent
			table.insert(self.recs, { part = p, emitter = emitter, spec = spec })
		end
	end
	if #self.recs == 0 then
		return nil
	end
	table.insert(holders, self)
	self:_apply()
	return self
end

function SceneryFx.SetNight(amount: number)
	local value = math.clamp(tonumber(amount) or 0, 0, 1)
	if math.abs(value - night) < 0.01 and not (value == 0 and night ~= 0) and not (value == 1 and night ~= 1) then
		return
	end
	night = value
	for _, h in holders do
		h:_apply()
	end
end

function SceneryFx.SetQuality(isLow: boolean)
	low = isLow == true
	for _, h in holders do
		h:_apply()
	end
end

function SceneryFx.Count(): number
	return #holders
end

return SceneryFx
