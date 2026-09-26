--[[
	Weather controller (C1): the look of the server weather and the day/night cycle.

	Reads global.Weather { id, night, phaseEndsAt, ... } and Visuals/Quality.IsLow() (glow-up P).
	  day/night   Lighting.ClockTime holds ~14 by day and ~0.5 at night. Around each phase
	              change it sweeps forward through dusk or dawn, centred on phaseEndsAt, so
	              every client computes the same sky from server time (no tween state).
	  weather     one profile per Config.Weather id (ColorCorrection, Bloom, Atmosphere fog
	              and sky tint, particle rates). Values blend exponentially to the new target,
	              so weather changes fade in and out over a few seconds.
	  particles   one invisible anchored part follows the camera with rain, snow and star
	              streak emitters (rates only, never re-created). lowGraphics scales rates down.
	              They use the Vfx sprites (droplet, snowflake, petal, star; applySprites).
	  extras      thunderstorm lightning flashes (Lighting.Brightness + ColorCorrection pulses; each one
	              publishes client bus "Weather.Lightning" (strength 0..1) so Soundscape times thunder),
	              aurora animated tint over ColorCorrection and the Atmosphere sky colour.

	One RenderStepped connection; properties are written only when their value changes.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Quality = require(script.Parent.Parent.Visuals.Quality)
local WeatherConfig = Config.Weather

local Weather = {
	Name = "Weather",
	Dependencies = {},
}

local DAY_CLOCK = 14
local NIGHT_CLOCK = 24.5 -- 0.5 on the next day; values are wrapped with % 24
local TRANSITION_HALF = 20 -- seconds either side of a phase change
local BLEND_TIME = 1.6 -- exponential blend time constant (≈ 5 s to settle)
local LOW_PARTICLES = 0.35
local EMITTER_HEIGHT = 32

local hex = Color3.fromHex

--[[
	Profile fields (numbers so they blend without allocations):
	  tint (Color3) brightness contrast saturation   ColorCorrection
	  bloom bloomSize                                 Bloom
	  density haze sky (Color3)                        Atmosphere
	  rain snow stars pollen                           particles per second (full quality)
	  lightning aurora                                 0..1 weights for the animated extras
]]
local BASE = {
	tint = hex("#FFFFFF"),
	brightness = 0,
	contrast = 0.05,
	saturation = 0.1,
	bloom = 0.25,
	bloomSize = 24,
	density = 0.26,
	haze = 0,
	sky = hex("#C7E6FF"),
	rain = 0,
	snow = 0,
	stars = 0,
	pollen = 0,
	lightning = 0,
	aurora = 0,
}

local PROFILES = {
	clear = {},
	rain = {
		tint = hex("#D3DCE6"),
		brightness = -0.08,
		contrast = 0.02,
		saturation = -0.2,
		density = 0.46,
		haze = 1.6,
		sky = hex("#98A6B6"),
		rain = 450,
	},
	heatwave = {
		tint = hex("#FFE0BC"),
		brightness = 0.05,
		contrast = 0.08,
		saturation = 0.22,
		bloom = 0.9,
		bloomSize = 40,
		density = 0.32,
		haze = 2.6,
		sky = hex("#FFD7A3"),
	},
	thunderstorm = {
		tint = hex("#BFC8D8"),
		brightness = -0.14,
		contrast = 0.06,
		saturation = -0.3,
		density = 0.52,
		haze = 2.2,
		sky = hex("#76808F"),
		rain = 650,
		lightning = 1,
	},
	snow = {
		tint = hex("#E2EFFF"),
		brightness = 0.03,
		saturation = -0.15,
		density = 0.42,
		haze = 1.3,
		sky = hex("#E4F1FF"),
		snow = 160,
	},
	bloodmoon = {
		tint = hex("#FFA69E"),
		brightness = -0.04,
		contrast = 0.14,
		saturation = 0.12,
		bloom = 0.5,
		density = 0.36,
		haze = 0.8,
		sky = hex("#B8342E"),
	},
	starfall = {
		tint = hex("#F1E9FF"),
		saturation = 0.15,
		bloom = 0.7,
		bloomSize = 32,
		sky = hex("#B9A8FF"),
		stars = 14,
	},
	-- Lunar Lanterns (1.2): warm lantern light over a dark night sky.
	lanternnight = {
		tint = hex("#FFD9B8"),
		saturation = 0.2,
		bloom = 0.8,
		bloomSize = 36,
		density = 0.2,
		haze = 0.6,
		sky = hex("#4A1F3A"),
		stars = 8,
	},
	-- Spring Bloom (1.4): a warm, hazy pink day full of drifting pollen.
	pollenstorm = {
		tint = hex("#FFF0E0"),
		saturation = 0.2,
		bloom = 0.45,
		density = 0.34,
		haze = 1.1,
		sky = hex("#FFD6E8"),
		pollen = 120,
	},
	-- Summer Splash (2.0): a bright, warm beach day.
	beachday = {
		tint = hex("#FFF4DE"),
		brightness = 0.05,
		saturation = 0.3,
		bloom = 0.5,
		sky = hex("#7FD4FF"),
	},
	aurora = {
		saturation = 0.25,
		bloom = 0.6,
		bloomSize = 32,
		sky = hex("#7FFFD0"),
		aurora = 1,
	},
}

local NIGHT_TINT = { 0.78, 0.84, 1 }

local FIELDS = {
	"tintR",
	"tintG",
	"tintB",
	"brightness",
	"contrast",
	"saturation",
	"bloom",
	"bloomSize",
	"density",
	"haze",
	"skyR",
	"skyG",
	"skyB",
	"rain",
	"snow",
	"stars",
	"pollen",
	"lightning",
	"aurora",
}

local SCALAR_FIELDS = {
	"brightness",
	"contrast",
	"saturation",
	"bloom",
	"bloomSize",
	"density",
	"haze",
	"rain",
	"snow",
	"stars",
	"pollen",
	"lightning",
	"aurora",
}

-- Aurora colours (precomputed; the animation indexes this table).
local AURORA_STEPS = 96
local AURORA = table.create(AURORA_STEPS)
for i = 1, AURORA_STEPS do
	local t = (i - 1) / AURORA_STEPS
	local hue = 0.38 + 0.4 * (0.5 + 0.5 * math.sin(t * math.pi * 2))
	AURORA[i] = Color3.fromHSV(hue % 1, 0.45, 1)
end

local ctx
local current = {}
local target = {}
local written = {}
local settled = false
local lowGraphics = Quality.IsLow() -- Visuals/Quality (glow-up P)
local weatherState = nil
local weatherId = "clear"
local isNight = false
local connections = {}

local cc: ColorCorrectionEffect
local bloom: BloomEffect
local atmosphere: Atmosphere
local emitterPart: Part
local emitters = {} -- rain / snow / stars / pollen
local baseLightingBrightness = 2.5
local clock = 0
local nextFlashAt = 0
local flashAt = -10

-- Target -------------------------------------------------------------------------------------

local function field(profile, key: string)
	local value = profile[key]
	if value == nil then
		value = BASE[key]
	end
	return value
end

local function computeTarget()
	local profile = PROFILES[weatherId] or PROFILES.clear
	local tint: Color3 = field(profile, "tint")
	local sky: Color3 = field(profile, "sky")
	local nr, ng, nb = 1, 1, 1
	if isNight then
		nr, ng, nb = NIGHT_TINT[1], NIGHT_TINT[2], NIGHT_TINT[3]
	end
	target.tintR, target.tintG, target.tintB = tint.R * nr, tint.G * ng, tint.B * nb
	target.skyR, target.skyG, target.skyB = sky.R, sky.G, sky.B
	for _, key in SCALAR_FIELDS do
		target[key] = field(profile, key)
	end
	if isNight then
		target.brightness -= 0.03
		target.saturation -= 0.05
	end
	settled = false
end

-- Helpers -------------------------------------------------------------------------------------

local function setIfChanged(inst: Instance, prop: string, key: string, value: number, epsilon: number)
	local last = written[key]
	if last == nil or math.abs(last - value) > epsilon then
		local object: any = inst
		object[prop] = value
		written[key] = value
	end
end

-- True (and remembers the new value) when any channel moved more than ~1/500.
local function colorChanged(key: string, r: number, g: number, b: number): boolean
	local last = written[key]
	if last == nil then
		last = { -1, -1, -1 }
		written[key] = last
	end
	if math.abs(last[1] - r) > 0.002 or math.abs(last[2] - g) > 0.002 or math.abs(last[3] - b) > 0.002 then
		last[1], last[2], last[3] = r, g, b
		return true
	end
	return false
end

local function smooth(p: number): number
	p = math.clamp(p, 0, 1)
	return p * p * (3 - 2 * p)
end

local function transition(fromNight: boolean, p: number): number
	if fromNight then
		return NIGHT_CLOCK + (DAY_CLOCK + 24 - NIGHT_CLOCK) * smooth(p)
	end
	return DAY_CLOCK + (NIGHT_CLOCK - DAY_CLOCK) * smooth(p)
end

local function clockTime(now: number): number
	local w = weatherState
	local steady = if isNight then NIGHT_CLOCK else DAY_CLOCK
	local phaseEndsAt = if type(w) == "table" then tonumber(w.phaseEndsAt) or 0 else 0
	if phaseEndsAt <= 0 then
		return steady % 24
	end
	local dayLength = WeatherConfig.DayLength or 1200
	local nightLength = dayLength * (WeatherConfig.NightFraction or 0.35)
	local phaseLength = if isNight then nightLength else dayLength - nightLength
	local remaining = phaseEndsAt - now
	local elapsed = phaseLength - remaining
	local v = steady
	if remaining < TRANSITION_HALF then
		v = transition(isNight, 0.5 * (1 - math.max(remaining, 0) / TRANSITION_HALF))
	elseif elapsed >= 0 and elapsed < TRANSITION_HALF then
		v = transition(not isNight, 0.5 + 0.5 * elapsed / TRANSITION_HALF)
	end
	return v % 24
end

-- Build ---------------------------------------------------------------------------------------

local function newEmitter(name: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Bottom
	e.LockedToPart = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = emitterPart
	return e
end

--[[
	Ambience layer "weatherSprites" (Config.Ambience.Layers): the Vfx sprites (Config/VfxSprites)
	replace the default sparkle, tinted by each emitter's own colours (grey twins). A sprite not
	uploaded yet keeps the default texture. Sizes grow to suit a textured sprite, and pollen's
	LightEmission drops to the daylight rule (Config/Vfx header) so petals keep their colour.
]]
local WEATHER_SPRITES = {
	rain = { sprite = "droplet", size = 0.3 },
	snow = { sprite = "snowflake", size = 0.55, rot = true },
	pollen = { sprite = "petal", size = 0.4, rot = true, lightEmission = 0.25 },
	stars = { sprite = "star", size = { 1.6, 0.2 } },
}

local function applySprites()
	local layers = Config.Ambience and Config.Ambience.Layers
	local override = Lighting:GetAttribute("Ambience_weatherSprites")
	if override == false or (override == nil and layers and layers.weatherSprites == false) then
		return
	end
	local module = ReplicatedStorage.Shared.Config:FindFirstChild("VfxSprites")
	local ok, sprites = pcall(require, module)
	if not ok or type(sprites) ~= "table" then
		return
	end
	for key, look in WEATHER_SPRITES do
		local row = sprites[look.sprite]
		local id = type(row) == "table" and (row.grey or row.color)
		local e = emitters[key]
		if e and type(id) == "string" and id ~= "" then
			e.Texture = id
			e.Size = if type(look.size) == "table" then NumberSequence.new(look.size[1], look.size[2]) else NumberSequence.new(look.size)
			if look.rot then
				e.Rotation = NumberRange.new(0, 360)
			end
			if look.lightEmission then
				e.LightEmission = look.lightEmission
			end
		end
	end
end

local function build()
	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "WeatherColor"
	cc.Parent = Lighting

	bloom = Instance.new("BloomEffect")
	bloom.Name = "WeatherBloom"
	bloom.Threshold = 0.95
	bloom.Parent = Lighting

	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then
		atmosphere = existing
	else
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "WeatherAtmosphere"
		atmosphere.Offset = 0.2
		atmosphere.Glare = 0
		atmosphere.Decay = hex("#8FB8DA")
		atmosphere.Parent = Lighting
	end

	baseLightingBrightness = Lighting.Brightness

	emitterPart = Instance.new("Part")
	emitterPart.Name = "WeatherEmitter"
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	emitterPart.CastShadow = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(140, 1, 140)
	emitterPart.CFrame = CFrame.new(0, -500, 0)
	emitterPart.Parent = workspace

	emitters.rain = newEmitter("Rain", {
		Color = ColorSequence.new(hex("#DCEBFF")),
		Transparency = NumberSequence.new(0.35),
		Size = NumberSequence.new(0.14),
		Speed = NumberRange.new(70, 90),
		Lifetime = NumberRange.new(0.55, 0.75),
		SpreadAngle = Vector2.new(4, 4),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		LightEmission = 0.2,
	})
	emitters.snow = newEmitter("Snow", {
		Color = ColorSequence.new(hex("#FFFFFF")),
		Transparency = NumberSequence.new(0.1),
		Size = NumberSequence.new(0.4),
		Speed = NumberRange.new(5, 8),
		Lifetime = NumberRange.new(5, 7),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(1.5, 0, 0.8),
		RotSpeed = NumberRange.new(-60, 60),
		LightEmission = 0.3,
	})
	emitters.pollen = newEmitter("Pollen", {
		Color = ColorSequence.new(hex("#FFE38A"), hex("#FFB3D1")),
		Transparency = NumberSequence.new(0.2, 0.8),
		Size = NumberSequence.new(0.25),
		Speed = NumberRange.new(3, 6),
		Lifetime = NumberRange.new(6, 9),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(2.5, 0.4, 1.2),
		RotSpeed = NumberRange.new(-90, 90),
		LightEmission = 0.5,
	})
	emitters.stars = newEmitter("Stars", {
		Color = ColorSequence.new(hex("#FFE38A"), hex("#FFFFFF")),
		Transparency = NumberSequence.new(0, 1),
		Size = NumberSequence.new(1.4, 0.1),
		Speed = NumberRange.new(55, 75),
		Lifetime = NumberRange.new(1, 1.4),
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(25, 0, 10),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		LightEmission = 1,
	})

	applySprites()

	for _, key in FIELDS do
		current[key] = 0
	end
	computeTarget()
	for _, key in FIELDS do
		current[key] = target[key]
	end
end

-- Frame ---------------------------------------------------------------------------------------

local function step(dt: number)
	clock += dt
	local now = ctx:Now()

	if not settled then
		local k = 1 - math.exp(-dt / BLEND_TIME)
		local maxDiff = 0
		for _, key in FIELDS do
			local c = current[key]
			local d = target[key] - c
			local ad = math.abs(d)
			if ad > maxDiff then
				maxDiff = ad
			end
			current[key] = c + d * k
		end
		if maxDiff < 0.002 then
			for _, key in FIELDS do
				current[key] = target[key]
			end
			settled = true
		end
	end

	-- Lightning: two quick pulses at random intervals while a storm is blended in.
	local flash = 0
	if current.lightning > 0.5 then
		if clock >= nextFlashAt then
			flashAt = clock
			nextFlashAt = clock + 4 + math.random() * 9
			ctx.Bus:Publish("Weather.Lightning", current.lightning)
		end
		local t = clock - flashAt
		if t < 0.08 then
			flash = 1
		elseif t > 0.16 and t < 0.26 then
			flash = 0.65
		end
		flash *= current.lightning
	else
		nextFlashAt = clock + 2 + math.random() * 4
	end

	-- ColorCorrection (aurora overrides the tint with an animated colour).
	local r, g, b = current.tintR, current.tintG, current.tintB
	local skyR, skyG, skyB = current.skyR, current.skyG, current.skyB
	local aurora = current.aurora
	if aurora > 0.01 then
		local c = AURORA[math.floor(clock * 6) % AURORA_STEPS + 1]
		r += (c.R - r) * aurora * 0.55
		g += (c.G - g) * aurora * 0.55
		b += (c.B - b) * aurora * 0.55
		local s = AURORA[(math.floor(clock * 6) + 32) % AURORA_STEPS + 1]
		skyR += (s.R - skyR) * aurora
		skyG += (s.G - skyG) * aurora
		skyB += (s.B - skyB) * aurora
	end
	if colorChanged("tint", r, g, b) then
		cc.TintColor = Color3.new(r, g, b)
	end
	if colorChanged("sky", skyR, skyG, skyB) then
		atmosphere.Color = Color3.new(skyR, skyG, skyB)
	end
	setIfChanged(cc, "Brightness", "brightness", current.brightness + flash * 0.35, 0.002)
	setIfChanged(cc, "Contrast", "contrast", current.contrast, 0.002)
	setIfChanged(cc, "Saturation", "saturation", current.saturation, 0.002)
	setIfChanged(bloom, "Intensity", "bloom", if lowGraphics then current.bloom * 0.5 else current.bloom, 0.005)
	setIfChanged(bloom, "Size", "bloomSize", current.bloomSize, 0.2)
	setIfChanged(atmosphere, "Density", "density", current.density, 0.002)
	setIfChanged(atmosphere, "Haze", "haze", current.haze, 0.01)
	setIfChanged(Lighting, "Brightness", "lightingBrightness", baseLightingBrightness + flash * 3, 0.01)
	setIfChanged(Lighting, "ClockTime", "clockTime", clockTime(now), 0.002)

	-- Particles
	local quality = if lowGraphics then LOW_PARTICLES else 1
	local total = current.rain + current.snow + current.stars + current.pollen
	setIfChanged(emitters.rain, "Rate", "rain", math.floor(current.rain * quality), 0.5)
	setIfChanged(emitters.snow, "Rate", "snow", math.floor(current.snow * quality), 0.5)
	setIfChanged(emitters.stars, "Rate", "stars", math.floor(current.stars * quality + 0.5), 0.5)
	setIfChanged(emitters.pollen, "Rate", "pollen", math.floor(current.pollen * quality), 0.5)
	if total >= 0.5 then
		local camera = workspace.CurrentCamera
		if camera then
			local p = camera.CFrame.Position
			emitterPart.CFrame = CFrame.new(p.X, p.Y + EMITTER_HEIGHT, p.Z)
		end
	end
end

-- Lifecycle -------------------------------------------------------------------------------------

local function onWeather(w)
	weatherState = if type(w) == "table" then w else nil
	local id = if weatherState and type(weatherState.id) == "string" then weatherState.id else "clear"
	if not PROFILES[id] then
		id = "clear"
	end
	local night = weatherState ~= nil and weatherState.night == true
	if id ~= weatherId or night ~= isNight then
		weatherId = id
		isNight = night
		computeTarget()
	end
end

function Weather.Init(context)
	ctx = context
	build()
end

function Weather.Start()
	table.insert(connections, ctx.Store:Observe("global.Weather", onWeather))
	table.insert(
		connections,
		Quality.Changed:Connect(function()
			lowGraphics = Quality.IsLow()
		end)
	)
	table.insert(connections, RunService.RenderStepped:Connect(step))
end

-- Tears everything down (not called by the kernel today; kept so the controller can be unplugged).
function Weather.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	cc:Destroy()
	bloom:Destroy()
	if atmosphere.Name == "WeatherAtmosphere" then
		atmosphere:Destroy()
	end
	emitterPart:Destroy()
	Lighting.Brightness = baseLightingBrightness
end

return Weather
