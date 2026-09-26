--[[
	SceneryMotion controller (Ambience "campfires", "fountain", "windmills", "sway"): scenery that moves.

	  campfires   flames, embers and smoke (Config.Vfx.Scenery.campfire) on the nearest `max`
	              campfires; flames and embers glow more at night (Config.Vfx.Night)
	  windmills   leaves and dust blowing past the sails of the nearest windmills. The windmill
	              mesh is one piece with its sails, so the sails cannot turn without a split mesh.
	  fountain    the plaza fountain's jet, the curtain off the bowl, ripples and mist, while the
	              camera is within `radius`
	  sway        the nearest trees and bushes rock gently about their base, `rate` times a second;
	              an item leaving the set goes back to its exact placed CFrame

	Effects come from a fixed pool of Visuals/SceneryFx holders per kind (built on first use, never
	more than `max`), moved to the nearest items once a second (Config.Ambience.Scenery.pick).
	lowGraphics: `maxLow` holders (campfires 2, windmills 0), every rate halved, no sway.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Ambience)
local Visuals = script.Parent.Parent.Visuals
local Quality = require(Visuals.Quality)
local SceneryIndex = require(Visuals.SceneryIndex)
local SceneryFx = require(Visuals.SceneryFx)

local Cfg = Config.Ambience
local S = Cfg.Scenery

local SceneryMotion = {
	Name = "SceneryMotion",
	Dependencies = {},
}

local POOLED = { campfire = "campfires", windmill = "windmills" } -- scenery kind -> layer

local connections = {}
local lowGraphics = false
local pools: { [string]: { any } } = {} -- kind -> SceneryFx holders
local fountainFx = nil
local fountainModel: Instance? = nil
local sincePick = math.huge
local sinceSway = 0
local clock = 0

-- Sway: [part] = { base = CFrame, pivot = Vector3, angle, speed, seed }
local swaying: { [BasePart]: any } = {}

local function layer(name: string): boolean
	return Logic.Enabled(Cfg.Layers, name, Lighting:GetAttribute("Ambience_" .. name))
end

local function cameraXZ(): (number?, number?)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil
	end
	local p = camera.CFrame.Position
	return p.X, p.Z
end

local function pickPool(kind: string, x: number, z: number)
	local entry = S[kind]
	local cap = if layer(POOLED[kind]) then Logic.Cap(entry, lowGraphics) else 0
	local pool = pools[kind]
	if not pool then
		pool = {}
		pools[kind] = pool
	end
	local parts = SceneryIndex.Get(kind)
	local chosen = if cap > 0 then Logic.Nearest(SceneryIndex.Points(kind), x, z, entry.radius, cap) else {}
	local wanted = {}
	for _, i in chosen do
		wanted[parts[i]] = true
	end
	-- keep holders that already sit on a wanted item; free the rest
	local free = {}
	local served = {}
	for _, h in pool do
		if h.item and wanted[h.item] and h.item.Parent then
			served[h.item] = true
		else
			h.item = nil
			h:SetActive(false)
			table.insert(free, h)
		end
	end
	for _, i in chosen do
		local part = parts[i]
		if not served[part] then
			local h = table.remove(free)
			if not h and #pool < cap then
				h = SceneryFx.new(kind)
				if h then
					table.insert(pool, h)
				end
			end
			if not h then
				break
			end
			h.item = part
			h:Place(part.Position, part.Size)
			h:SetActive(true)
		end
	end
end

local function fountainBox(name: string): (Vector3?, Vector3?)
	local part = fountainModel and fountainModel:FindFirstChild(name)
	if not (part and part:IsA("BasePart")) then
		return nil, nil
	end
	-- the fountain's discs are cylinders turned on their side: X is their height
	return part.Position, Vector3.new(part.Size.Y, part.Size.X, part.Size.Z)
end

local function pickFountain(x: number, z: number)
	if not fountainModel or not fountainModel.Parent then
		local world = workspace:FindFirstChild("World")
		local hub = world and world:FindFirstChild("Hub")
		fountainModel = hub and hub:FindFirstChild("Fountain")
	end
	local basin = fountainModel and fountainModel:FindFirstChild("Basin")
	if not (basin and basin:IsA("BasePart")) then
		return
	end
	local dx, dz = basin.Position.X - x, basin.Position.Z - z
	local near = dx * dx + dz * dz <= S.fountain.radius * S.fountain.radius
	local on = near and layer("fountain")
	if on and not fountainFx then
		fountainFx = SceneryFx.new("fountain")
		if fountainFx then
			local c, s = fountainBox("Basin")
			fountainFx:Place(c :: Vector3, s :: Vector3, fountainBox)
		end
	end
	if fountainFx then
		fountainFx:SetActive(on)
	end
end

local function unsway(part: BasePart)
	local rec = swaying[part]
	swaying[part] = nil
	if rec and part.Parent then
		part.CFrame = rec.base
	end
end

local function pickSway(x: number, z: number)
	local cfg = S.sway
	local cap = if layer("sway") then Logic.Cap(cfg, lowGraphics) else 0
	local points, parts = {}, {}
	if cap > 0 then
		for kind in cfg.kinds do
			local list = SceneryIndex.Get(kind)
			for i, p in SceneryIndex.Points(kind) do
				table.insert(points, p)
				table.insert(parts, list[i])
			end
		end
	end
	local wanted = {}
	for _, i in Logic.Nearest(points, x, z, cfg.radius, cap) do
		wanted[parts[i]] = true
	end
	for part in swaying do
		if not wanted[part] then
			unsway(part)
		end
	end
	for part in wanted do
		if not swaying[part] and part.Parent then
			local k = cfg.kinds[part.Name]
			local base = part.CFrame
			swaying[part] = {
				base = base,
				-- the pivot is the bottom centre, in the part's own frame
				offset = CFrame.new(0, part.Size.Y / 2, 0),
				angle = k.angle,
				speed = k.speed,
				seed = (base.Position.X * 0.37 + base.Position.Z * 0.61) % (math.pi * 2),
			}
		end
	end
end

local function sway()
	for part, rec in swaying do
		local ax, az = Logic.Sway(clock, rec.seed, rec.angle, rec.speed)
		local pivot = rec.base * rec.offset:Inverse()
		part.CFrame = pivot * CFrame.Angles(ax, 0, az) * rec.offset
	end
end

local function pick()
	local x, z = cameraXZ()
	if not x or not z then
		return
	end
	for kind in POOLED do
		pickPool(kind, x, z)
	end
	pickFountain(x, z)
	pickSway(x, z)
	SceneryFx.SetNight(Logic.Night(tonumber(Lighting.ClockTime) or 14, Cfg.Lights.on, Cfg.Lights.off))
end

local function step(dt: number)
	clock += dt
	sincePick += dt
	sinceSway += dt
	if sincePick >= S.pick then
		sincePick = 0
		pick()
	end
	if next(swaying) ~= nil and sinceSway >= 1 / S.sway.rate then
		sinceSway = 0
		sway()
	end
end

function SceneryMotion.Init(_context) end

function SceneryMotion.Start()
	SceneryIndex.Start()
	local function onQuality()
		local low = Quality.IsLow()
		if low ~= lowGraphics then
			lowGraphics = low
			SceneryFx.SetQuality(low)
			sincePick = math.huge
		end
	end
	onQuality()
	table.insert(connections, Quality.Changed:Connect(onQuality))
	table.insert(connections, RunService.Heartbeat:Connect(step))
end

-- Tests: active effect holders by kind ("campfire", "windmill", "fountain") and swaying items.
function SceneryMotion.Stats(): { [string]: number }
	local out = { sway = 0, fountain = if fountainFx and fountainFx.active then 1 else 0 }
	for kind, pool in pools do
		local n = 0
		for _, h in pool do
			if h.active then
				n += 1
			end
		end
		out[kind] = n
	end
	for _ in swaying do
		out.sway += 1
	end
	return out
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function SceneryMotion.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for part in swaying do
		unsway(part)
	end
	for _, pool in pools do
		for _, h in pool do
			h:Destroy()
		end
	end
	table.clear(pools)
	if fountainFx then
		fountainFx:Destroy()
		fountainFx = nil
	end
end

return SceneryMotion
