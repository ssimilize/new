--[[
	Soundscape controller: music, ambience and monster chatter, on top of the Audio kit
	(src/client/Audio). Everything stays silent while the ids in Config.Sounds are empty.

	Twice a second it works out the listening context from what the client already knows:
	  raid       the Raids screen            racing   the Racing screen
	  battle     a BattleReplay viewer is up (ctx.UI.Top), or the Arena screen
	  stampede   the Boss screen is open
	  sky        SkyIslands.IsOnIslands()
	  hub        the character is inside Config.World.HubRadius of the plaza
	  night      global.Weather.night        weather   global.Weather.id
	  event      Config.Events.ActiveId(now)
	and hands it to Logic/Audio: MusicChain (crossfaded by Audio.SetMusic) and Beds (birdsong by
	day and crickets at night as scatter beds, wind on the Sky Islands, rain, the hub crowd). The fountain loop sits at
	Config.World.Fountain as a positional bed. One-shots: RainStart when rain rolls in, Thunder
	just after each lightning flash (client bus "Weather.Lightning" from the Weather controller),
	WindGust now and then up on the islands. Monster chatter: the closest few pen monsters
	(Audio/Voices), fewer and nearer with lowGraphics.

	Studio only (RunService:IsStudio()): registers the SoundCheck screen and a small "Sound Check"
	button in the top layer, so the owner can audition every key. Not reachable in live games.

	  Soundscape.Context() -> state          the last context worked out
	  Soundscape.Preview(state?)             force a context (Sound Check); nil = live again
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Logic = require(ReplicatedStorage.Shared.Logic.Audio)

local Client = script.Parent.Parent
local Audio = require(Client.Audio)
local Voices = require(Client.Audio.Voices)
local Quality = require(Client.Visuals.Quality)

local Soundscape = {
	Name = "Soundscape",
	Dependencies = {},
}

local TICK = 0.5
local BATTLE_SCREENS = { Arena = true }
local RAINY = { rain = true, thunderstorm = true }
local CHATTER = { count = 3, range = 50 }
local CHATTER_LOW = { count = 1, range = 28 }

local ctx
local weather = { id = "clear", night = false }
local lowGraphics = Quality.IsLow() -- Visuals/Quality (glow-up P)
local state = {}
local preview = nil
local nextGustAt = 0
local chatterAcc = 0

local function fountainPosition(): Vector3?
	local f = Config.World.Fountain
	local p = f and f.position
	return if p then Vector3.new(p[1], (p[2] or 0) + 3, p[3]) else nil
end

local function characterPosition(): Vector3?
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function onSky(): boolean
	local sky = ctx:GetController("SkyIslands")
	return sky ~= nil and type(sky.IsOnIslands) == "function" and sky.IsOnIslands() == true
end

local function computeState()
	local current = ctx.Router:Current()
	local position = characterPosition()
	local flat = if position then Vector3.new(position.X, 0, position.Z).Magnitude else math.huge
	local eventId = nil
	local okEvent, result = pcall(Config.Events.ActiveId, ctx:Now())
	if okEvent then
		eventId = result
	end
	return {
		raid = current == "Raids",
		racing = current == "Racing",
		battle = ctx.UI.Top:FindFirstChild("BattleReplay") ~= nil or (current ~= nil and BATTLE_SCREENS[current] == true),
		stampede = current == "Boss",
		sky = onSky(),
		hub = flat <= (Config.World.HubRadius or 95),
		night = weather.night,
		weather = weather.id,
		event = eventId,
	}
end

local function apply(s)
	Audio.SetMusic(Logic.MusicChain(s))
	for key, level in Logic.Beds(s) do
		Audio.SetLoop(key, level)
	end
	local fountain = fountainPosition()
	if fountain then
		Audio.SetLoop("AmbienceFountain", if s.sky then 0 else 1, fountain)
	end
end

local function tick()
	state = preview or computeState()
	apply(state)
	local t = os.clock()
	if state.sky and t >= nextGustAt then
		nextGustAt = t + 9 + math.random() * 12
		Audio.Play("WindGust")
	end
end

local function onWeather(w)
	local id = if type(w) == "table" and type(w.id) == "string" then w.id else "clear"
	local night = type(w) == "table" and w.night == true
	if RAINY[id] and not RAINY[weather.id] then
		Audio.Play("RainStart")
	end
	weather = { id = id, night = night }
end

-- Thunder follows the flash after a short, random "distance" delay; louder for a stronger storm.
local function onLightning(strength: any)
	if not RAINY[weather.id] and not (preview and RAINY[preview.weather]) then
		return
	end
	local s = math.clamp(tonumber(strength) or 1, 0, 1)
	task.delay(0.25 + math.random() * 1.2, function()
		Audio.Play("Thunder", { volume = 0.6 + 0.4 * s })
	end)
end

local function chatter(dt: number)
	chatterAcc += dt
	if chatterAcc < 1 then
		return
	end
	chatterAcc = 0
	local tuning = if lowGraphics then CHATTER_LOW else CHATTER
	local camera = workspace.CurrentCamera
	local listener = characterPosition() or (camera and camera.CFrame.Position)
	Voices.Chatter(listener, tuning.count, tuning.range)
end

local function addStudioTools()
	local SoundCheck = require(Client.UI.Screens.SoundCheck)
	ctx.Router:Register(SoundCheck)
	local Button = require(Client.UI.Components.Button)
	local Theme = require(Client.UI.Theme)
	local button = Button.new({
		Name = "SoundCheckButton",
		Text = "Sound Check",
		Color = Theme.Colors.Gray,
		TextSize = Theme.TextSize.Small,
		Size = UDim2.fromOffset(150, 44),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -8),
		Sound = false,
		Parent = ctx.UI.Top,
		OnClick = function()
			ctx.Router:Toggle("SoundCheck")
		end,
	})
	button.Root:SetAttribute("Localize", false)
	button.Label:SetAttribute("Localize", false)
end

function Soundscape.Context()
	return state
end

function Soundscape.Preview(s)
	preview = if type(s) == "table" then s else nil
	tick()
end

function Soundscape.Init(context)
	ctx = context
	if RunService:IsStudio() then
		addStudioTools()
	end
end

function Soundscape.Start()
	ctx.Store:Observe("global.Weather", onWeather)
	Quality.Changed:Connect(function()
		lowGraphics = Quality.IsLow()
	end)
	ctx.Bus:Subscribe("Weather.Lightning", onLightning)
	Audio.Preload("UI")
	local acc = TICK
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= TICK then
			acc = 0
			tick()
		end
		chatter(dt)
	end)
end

return Soundscape
