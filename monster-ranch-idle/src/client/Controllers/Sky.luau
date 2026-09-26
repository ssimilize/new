--[[
	Sky controller (Ambience): the sky above the Weather controller's light.

	  Sky            a Sky in Lighting (the place's own if it has one): sun, moon and star count, and
	                 the skybox faces from Config.Ambience.Sky ("" keeps Roblox's default sky)
	  Clouds         Terrain Clouds; cover, density and colour per weather id, blended over a few
	                 seconds and shaded at night. Off with lowGraphics.
	  SunRays        a SunRaysEffect whose intensity follows the weather, zero at night. Off with lowGraphics.
	  DepthOfField   a faint far-distance haze. Only at the High quality level (Visuals/Quality).
	  GoldenHour     its own ColorCorrectionEffect ("AmbienceGoldenHour"), stacked on the Weather
	                 controller's: warm through dusk and dawn, white (no effect) otherwise.

	The day/dusk/night mood itself stays with the Weather controller (ColorCorrection, Atmosphere,
	ClockTime); this reads Lighting.ClockTime and global.Weather.id. Updates 5 times a second and
	writes a property only when it moved. Each layer has a switch in Config.Ambience.Layers and a
	live override attribute on Lighting ("Ambience_clouds" = false ...).
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Ambience)
local Quality = require(script.Parent.Parent.Visuals.Quality)

local Cfg = Config.Ambience

local Sky = {
	Name = "Sky",
	Dependencies = { "Weather" },
}

local STEP = 0.2 -- seconds between updates

local ctx
local connections = {}
local made: { Instance } = {}
local lowGraphics = Quality.IsLow() -- Visuals/Quality (glow-up P)
local weatherId = "clear"
local since = STEP
local written = {}

local sky: Sky?
local clouds: Clouds?
local sunRays: SunRaysEffect?
local dof: DepthOfFieldEffect?
local golden: ColorCorrectionEffect?

-- Blended cloud look (cover, density, r, g, b).
local look = { cover = 0, density = 0, r = 1, g = 1, b = 1 }
local lookReady = false

local function layer(name: string): boolean
	return Logic.Enabled(Cfg.Layers, name, Lighting:GetAttribute("Ambience_" .. name))
end

local function set(inst: Instance?, prop: string, value: any, epsilon: number?)
	if not inst then
		return
	end
	local key = tostring(inst) .. "." .. prop
	local last = written[key]
	if type(value) == "number" and type(last) == "number" and math.abs(last - value) <= (epsilon or 0.002) then
		return
	end
	if last == value then
		return
	end
	(inst :: any)[prop] = value
	written[key] = value
end

local function build()
	local S = Cfg.Sky
	local existing = Lighting:FindFirstChildOfClass("Sky")
	if existing then
		sky = existing
	else
		local s = Instance.new("Sky")
		s.Name = "AmbienceSky"
		table.insert(made, s)
		sky = s
	end
	local s = sky :: Sky
	-- all six faces or none, so a half-pasted set never shows a seam
	local faces = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }
	local complete = true
	for _, face in faces do
		local id = S[string.lower(string.sub(face, 1, 1)) .. string.sub(face, 2)]
		if type(id) ~= "string" or id == "" then
			complete = false
		end
	end
	if complete then
		for _, face in faces do
			(s :: any)[face] = S[string.lower(string.sub(face, 1, 1)) .. string.sub(face, 2)]
		end
	end
	if S.sunTexture ~= "" then
		s.SunTextureId = S.sunTexture
	end
	if S.moonTexture ~= "" then
		s.MoonTextureId = S.moonTexture
	end
	s.SunAngularSize = S.sunAngularSize
	s.MoonAngularSize = S.moonAngularSize
	s.StarCount = S.starCount
	if not existing then
		s.Parent = Lighting
	end

	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local c = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
		if c.Parent == nil then
			c.Name = "AmbienceClouds"
			c.Parent = terrain
			table.insert(made, c)
		end
		clouds = c
	end

	-- The place's own SunRays / DepthOfField, when it has them, are driven here rather than doubled
	-- by a second effect (two SunRaysEffects add up; checked in Studio 2026-09-26).
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if not rays then
		rays = Instance.new("SunRaysEffect")
		rays.Name = "AmbienceSunRays"
		rays.Parent = Lighting
		table.insert(made, rays)
	end
	rays.Spread = Cfg.SunRays.spread
	rays.Intensity = 0
	sunRays = rays

	local D = Cfg.DepthOfField
	local d = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if not d then
		d = Instance.new("DepthOfFieldEffect")
		d.Name = "AmbienceDepthOfField"
		d.Parent = Lighting
		table.insert(made, d)
	end
	d.FarIntensity = D.farIntensity
	d.FocusDistance = D.focusDistance
	d.InFocusRadius = D.inFocusRadius
	d.NearIntensity = D.nearIntensity
	d.Enabled = false
	dof = d

	local g = Instance.new("ColorCorrectionEffect")
	g.Name = "AmbienceGoldenHour"
	g.Parent = Lighting
	table.insert(made, g)
	golden = g
end

local function update(dt: number)
	local clock = tonumber(Lighting.ClockTime) or 14
	local L = Cfg.Lights
	local night = Logic.Night(clock, L.on, L.off)

	if sky then
		set(sky, "CelestialBodiesShown", layer("sky"))
	end

	if clouds then
		local cover, density, r, g, b = Logic.Clouds(Cfg.Clouds, weatherId, night)
		if lookReady then
			local k = 1 - math.exp(-dt / Cfg.Clouds.blend)
			look.cover += (cover - look.cover) * k
			look.density += (density - look.density) * k
			look.r += (r - look.r) * k
			look.g += (g - look.g) * k
			look.b += (b - look.b) * k
		else
			look.cover, look.density, look.r, look.g, look.b = cover, density, r, g, b
			lookReady = true
		end
		set(clouds, "Enabled", layer("clouds") and not lowGraphics)
		set(clouds, "Cover", look.cover, 0.003)
		set(clouds, "Density", look.density, 0.003)
		local key = string.format("%.3f,%.3f,%.3f", look.r, look.g, look.b)
		if written.cloudColor ~= key then
			written.cloudColor = key
			clouds.Color = Color3.new(look.r, look.g, look.b)
		end
	end

	local raysOn = layer("sunRays") and not lowGraphics
	set(sunRays, "Enabled", raysOn)
	if raysOn then
		set(sunRays, "Intensity", Logic.SunRays(Cfg.SunRays, weatherId, night), 0.002)
	end

	set(dof, "Enabled", layer("depthOfField") and not lowGraphics and Quality.Level() >= 3)

	local G = Cfg.GoldenHour
	local w = if layer("goldenHour") then Logic.GoldenHour(clock, G) else 0
	local tr, tg, tb = Logic.HexToRgb(G.tint)
	local key = string.format("%.3f", w)
	if written.golden ~= key and golden then
		written.golden = key
		golden.TintColor = Color3.new(1 + (tr - 1) * w, 1 + (tg - 1) * w, 1 + (tb - 1) * w)
		golden.Saturation = G.saturation * w
		golden.Brightness = G.brightness * w
		golden.Enabled = w > 0.001
	end
end

local function onWeather(w)
	local id = if type(w) == "table" and type(w.id) == "string" then w.id else "clear"
	weatherId = id
end

function Sky.Init(context)
	ctx = context
	build()
end

function Sky.Start()
	table.insert(connections, ctx.Store:Observe("global.Weather", onWeather))
	table.insert(
		connections,
		Quality.Changed:Connect(function()
			lowGraphics = Quality.IsLow()
		end)
	)
	update(0)
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			since += dt
			if since >= STEP then
				update(since)
				since = 0
			end
		end)
	)
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function Sky.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, inst in made do
		inst:Destroy()
	end
	table.clear(made)
end

return Sky
