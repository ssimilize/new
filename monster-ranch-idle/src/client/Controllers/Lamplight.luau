--[[
	Lamplight controller (Ambience "lights"): the world lights up at dusk.

	Light sources (Config.Ambience.Lights.kinds), found once Workspace.World exists:
	  door       a warm PointLight over the door of every hub building and every plot's barn
	  window     a SurfaceLight spilling out of every hub building's front (its Body's Front face)
	  campfire   a flickering PointLight in every campfire (scenery)
	  crystals   a faint violet PointLight in every crystal cluster (scenery)
	  fountain   a cool PointLight over the plaza fountain

	There are no lantern or street-lamp parts in the world; add a kind here when they exist.
	Every light is off by day. Twice a second the night level (Logic/Ambience.Night of
	Lighting.ClockTime, so it fades in through the dusk sweep and out through dawn) scales the
	brightness, and only the `max` nearest sources within `radius` of the camera are enabled
	(`maxLow` with lowGraphics). A source's holder part and light are made the first time it is
	picked and reused after. Nothing casts shadows. Campfires flicker 10 times a second.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Ambience)
local SceneryIndex = require(script.Parent.Parent.Visuals.SceneryIndex)

local Cfg = Config.Ambience
local L = Cfg.Lights

local Lamplight = {
	Name = "Lamplight",
	Dependencies = {},
}

local FLICKER_STEP = 0.1
local REFRESH = 15 -- seconds between re-reading the buildings (a rebuilt hub)

type Source = {
	kind: string,
	X: number,
	Z: number,
	make: () -> (BasePart, Light),
	holder: BasePart?,
	light: Light?,
	on: boolean,
	seed: number,
}

local ctx
local connections = {}
local sources: { Source } = {}
local lit: { Source } = {}
local folder: Folder? = nil
local lowGraphics = false
local sceneryVersion = -1
local world: Instance? = nil
local night = 0
local sincePick = math.huge
local sinceFlicker = 0
local sinceRefresh = 0
local clock = 0

local function layer(name: string): boolean
	return Logic.Enabled(Cfg.Layers, name, Lighting:GetAttribute("Ambience_" .. name))
end

local function holderFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "AmbienceLights"
	f.Parent = workspace
	folder = f
	return f
end

local function holderPart(name: string, size: Vector3, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = holderFolder()
	return p
end

local function pointLight(kind: string, parent: Instance): PointLight
	local k = L.kinds[kind]
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex(k.color)
	light.Range = k.range
	light.Brightness = 0
	light.Shadows = false
	light.Enabled = false
	light.Parent = parent
	return light
end

local function add(kind: string, at: Vector3, make: () -> (BasePart, Light))
	if not L.kinds[kind] then
		return
	end
	table.insert(sources, { kind = kind, X = at.X, Z = at.Z, make = make, on = false, seed = #sources * 1.7 })
end

local function addDoor(door: Instance)
	if not door:IsA("BasePart") then
		return
	end
	local cf = door.CFrame * CFrame.new(0, door.Size.Y / 2 + 1, -2.5)
	add("door", cf.Position, function()
		local p = holderPart("DoorLight", Vector3.new(0.2, 0.2, 0.2), cf)
		return p, pointLight("door", p)
	end)
end

local function addWindow(body: Instance)
	if not body:IsA("BasePart") then
		return
	end
	local size = body.Size
	local cf = body.CFrame * CFrame.new(0, -size.Y * 0.1, -size.Z / 2 - 0.3)
	add("window", cf.Position, function()
		local p = holderPart("WindowLight", Vector3.new(size.X * 0.8, size.Y * 0.5, 0.2), cf)
		local k = L.kinds.window
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Front
		light.Angle = k.angle
		light.Color = Color3.fromHex(k.color)
		light.Range = k.range
		light.Brightness = 0
		light.Shadows = false
		light.Enabled = false
		light.Parent = p
		return p, light
	end)
end

local function addAt(kind: string, part: BasePart, lift: number)
	local at = part.Position + Vector3.new(0, part.Size.Y * lift, 0)
	add(kind, at, function()
		local p = holderPart(kind .. "Light", Vector3.new(0.2, 0.2, 0.2), CFrame.new(at))
		return p, pointLight(kind, p)
	end)
end

local function collect()
	for _, s in sources do
		if s.holder then
			s.holder:Destroy()
		end
	end
	table.clear(sources)
	table.clear(lit)
	local w = world
	if not w then
		return
	end
	local hub = w:FindFirstChild("Hub")
	local buildings = hub and hub:FindFirstChild("Buildings")
	if buildings then
		for _, model in buildings:GetChildren() do
			local door, body = model:FindFirstChild("Door"), model:FindFirstChild("Body")
			if door then
				addDoor(door)
			end
			if body and door then
				addWindow(body)
			end
		end
	end
	local fountain = hub and hub:FindFirstChild("Fountain")
	local basin = fountain and fountain:FindFirstChild("Basin")
	if basin and basin:IsA("BasePart") then
		add("fountain", basin.Position + Vector3.new(0, 3, 0), function()
			local p = holderPart("FountainLight", Vector3.new(0.2, 0.2, 0.2), CFrame.new(basin.Position + Vector3.new(0, 3, 0)))
			return p, pointLight("fountain", p)
		end)
	end
	local plots = w:FindFirstChild("Plots")
	if plots then
		for _, plot in plots:GetChildren() do
			local barn = plot:FindFirstChild("Barn")
			local door = barn and barn:FindFirstChild("Door")
			if door then
				addDoor(door)
			end
		end
	end
	for _, part in SceneryIndex.Get("campfire") do
		addAt("campfire", part, 0.2)
	end
	for _, part in SceneryIndex.Get("crystals") do
		addAt("crystals", part, 0.1)
	end
	sceneryVersion = SceneryIndex.Version()
end

local function brightness(s: Source): number
	local k = L.kinds[s.kind]
	local b = k.brightness * night
	if k.flicker then
		local n = math.sin(clock * 11 + s.seed) * 0.5 + math.sin(clock * 23.7 + s.seed * 3) * 0.3 + math.sin(clock * 5.3) * 0.2
		b *= 1 + k.flicker * n
	end
	return b
end

local function switch(s: Source, on: boolean)
	if s.on == on then
		return
	end
	s.on = on
	if on and not s.holder then
		s.holder, s.light = s.make()
	end
	if s.light then
		s.light.Enabled = on
	end
end

local function pick()
	night = if layer("lights") then Logic.Night(tonumber(Lighting.ClockTime) or 14, L.on, L.off) else 0
	local want = {}
	if night > 0.001 then
		local camera = workspace.CurrentCamera
		if camera then
			local p = camera.CFrame.Position
			for _, i in Logic.Nearest(sources, p.X, p.Z, L.radius, Logic.Cap(L, lowGraphics)) do
				want[sources[i]] = true
			end
		end
	end
	table.clear(lit)
	for _, s in sources do
		switch(s, want[s] == true)
		if s.on then
			table.insert(lit, s)
			local light = s.light :: Light
			light.Brightness = brightness(s)
		end
	end
end

local function flicker()
	for _, s in lit do
		if L.kinds[s.kind].flicker and s.light then
			s.light.Brightness = brightness(s)
		end
	end
end

local function step(dt: number)
	clock += dt
	sincePick += dt
	sinceFlicker += dt
	sinceRefresh += dt
	if world and (SceneryIndex.Version() ~= sceneryVersion or sinceRefresh >= REFRESH) then
		sinceRefresh = 0
		if SceneryIndex.Version() ~= sceneryVersion or #sources == 0 then
			collect()
			sincePick = math.huge
		end
	end
	if sincePick >= L.update then
		sincePick = 0
		pick()
	elseif sinceFlicker >= FLICKER_STEP then
		sinceFlicker = 0
		flicker()
	end
end

function Lamplight.Init(context)
	ctx = context
end

function Lamplight.Start()
	SceneryIndex.Start()
	table.insert(
		connections,
		ctx.Store:Observe("profile.Settings", function(settings)
			local low = type(settings) == "table" and settings.lowGraphics == true
			if low ~= lowGraphics then
				lowGraphics = low
				sincePick = math.huge
			end
		end)
	)
	table.insert(connections, RunService.Heartbeat:Connect(step))
	task.spawn(function()
		local w = workspace:WaitForChild("World", 60)
		if w then
			world = w
			collect()
			sincePick = math.huge
		end
	end)
end

-- Tests: how many lights are on, and how many sources exist.
function Lamplight.Stats(): (number, number)
	return #lit, #sources
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function Lamplight.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	world = nil
	collect()
	if folder then
		folder:Destroy()
	end
end

return Lamplight
