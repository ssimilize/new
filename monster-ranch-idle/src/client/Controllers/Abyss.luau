--[[
	Abyss controller (R2-ABYSS): the Sunken Abyss's Descent, its walk-in — swum-in — Area and its
	local darkness, built entirely on this client (like Controllers/DeepReef / ClockworkCanyon),
	from Config.Abyss + Visuals/AbyssBuild + Visuals/AbyssLife. Nothing is built in the Trading
	Hub place.

	  Chasm ("Dive Deeper")   dropped into the Deep Reef's own Area once it exists (Config.Abyss
	                          .Descent's offset from Config.DeepReef.Area's centre). Only works
	                          while already swimming there (Controllers/DeepReef.IsSwimming) and
	                          past Ranch Level Config.Abyss.Unlock; hands the running swim loop off
	                          to the deeper AbyssArea (DeepReef.Descend) and stacks a second, darker
	                          ColorCorrectionEffect ("AbyssColor") on top of the Reef's own light —
	                          the Reef's Weather hold / ambience swap is left running underneath,
	                          untouched.
	  Ascent Bell ("Ascend")  the safe way back up: hands the swim back to the Deep Reef's own Area
	                          (DeepReef.Ascend) and drops the AbyssColor effect.
	  Gate Portal ("Enter")   opens the Expeditions screen on the "abyss" region (its own opensAt
	                          gates the expedition itself, same as every region).

	Abyss.IsDescended() -> boolean   the local character is swimming in the AbyssArea.
	Abyss.Stats() -> (Model?, Folder?, boolean)   tests: the chasm, the area, whether descended.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Client = script.Parent.Parent
local AbyssBuild = require(Client.Visuals.AbyssBuild)
local AbyssLife = require(Client.Visuals.AbyssLife)
local Quality = require(Client.Visuals.Quality)
local StoreKit = require(Client.UI.Components.StoreKit)
local Wake = require(Client.Visuals.Wake)

local Cfg = Config.Abyss
local hex = Color3.fromHex

local Abyss = {
	Name = "Abyss",
	Dependencies = { "DeepReef" },
}

local ctx
local chasm: Model? = nil
local area: Folder? = nil
local life = nil
local lifeWake = nil -- Visuals/Wake: the life only moves while the camera is near the Area
local lowGraphics = false
local built = false
local descended = false
local abyssColor: ColorCorrectionEffect? = nil

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function unlocked(): boolean
	return StoreKit.level(ctx.Store) >= (Config.Unlocks.Features[Cfg.Unlock] or math.huge)
end

local function prompt(parent: Instance, action: string, object: string, distance: number, onTrigger: () -> ())
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = distance
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Parent = parent
	p.Triggered:Connect(onTrigger)
	return p
end

local function buildAbyssColor()
	if abyssColor then
		return
	end
	local L = Cfg.Light
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "AbyssColor"
	effect.TintColor = hex(L.tint)
	effect.Brightness = L.brightness
	effect.Contrast = L.contrast
	effect.Saturation = L.saturation
	effect.Parent = Lighting
	abyssColor = effect
end

local function destroyAbyssColor()
	if abyssColor then
		abyssColor:Destroy()
		abyssColor = nil
	end
end

local function descend()
	if not unlocked() then
		ctx:Toast(string.format("The Sunken Abyss opens at Ranch Level %d", Config.Unlocks.Features[Cfg.Unlock]), "info")
		return
	end
	if descended or not built then
		return
	end
	local reef = ctx:GetController("DeepReef")
	if not reef or not reef.IsSwimming or not reef.IsSwimming() then
		return
	end
	local at = v3(Cfg.Area.center) + v3(Cfg.Area.arrive)
	if reef.Descend(Cfg.Area, at, "ReefDive") then
		descended = true
		buildAbyssColor()
	end
end

local function ascend()
	if not descended then
		return
	end
	descended = false
	destroyAbyssColor()
	local reef = ctx:GetController("DeepReef")
	if reef and reef.Ascend then
		local at = v3(Config.DeepReef.Area.center) + v3(Config.DeepReef.Area.arrive)
		reef.Ascend(at, "ReefDive")
	end
end

-- World wiring ----------------------------------------------------------------------------------

local function wireChasm(model: Model)
	local pad = model:FindFirstChild("DivePad", true)
	if pad then
		prompt(pad, "Dive Deeper", "Sunken Abyss", 10, descend)
	end
end

local function wireArea(folder: Folder)
	local bell = folder:FindFirstChild("AscentBell")
	local returnPad = bell and bell:FindFirstChild("ReturnPad")
	if returnPad then
		prompt(returnPad, "Ascend", "Ascent Bell", 12, ascend)
	end
	local gate = folder:FindFirstChild("Gate")
	local portal = gate and gate:FindFirstChild("Portal")
	if portal then
		prompt(portal, "Enter", "Abyss Gate", 14, function()
			if ctx.Router:Has("Expeditions") then
				ctx.Router:Open("Expeditions", { region = Cfg.Region })
			end
		end)
	end
end

local function build()
	if built then
		return
	end
	local reef = ctx:GetController("DeepReef")
	if not reef then
		return
	end
	local _, reefArea = reef.Stats()
	if not reefArea then
		return
	end
	built = true
	chasm = AbyssBuild.Descent(reefArea :: Folder)
	area = AbyssBuild.Area(workspace)
	life = AbyssLife.Build(area :: Folder, lowGraphics)
	lifeWake = Wake.new(v3(Cfg.Area.center), Cfg.Area.radius)
	wireChasm(chasm :: Model)
	wireArea(area :: Folder)
end

-- Public ----------------------------------------------------------------------------------------

function Abyss.IsDescended(): boolean
	return descended
end

-- Tests: the chasm and area models, and whether the local swim is in the AbyssArea.
function Abyss.Stats(): (Model?, Folder?, boolean)
	return chasm, area, descended
end

function Abyss.Init(context)
	ctx = context
	lowGraphics = Quality.IsLow()
end

function Abyss.Start()
	Quality.Changed:Connect(function()
		local low = Quality.IsLow()
		if low ~= lowGraphics then
			lowGraphics = low
			if life then
				AbyssLife.SetLow(life, low)
			end
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		-- The Deep Reef controller's own reset (a lost or respawned character) already stops the
		-- swim and gives its light back; this only cleans up the extra darkness stacked on top.
		if descended then
			descended = false
			destroyAbyssColor()
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		if not built then
			acc += dt
			if acc < 0.5 then
				return
			end
			acc = 0
			if ctx.Store.Ready and ctx.Store:Get("global.TradingHub.mode") ~= "hub" then
				build()
			end
			return
		end
		if life then
			local awake, changed = Wake.Step(lifeWake, dt)
			if changed then
				AbyssLife.SetAwake(life, awake)
			end
			AbyssLife.Step(life, dt, awake)
		end
	end)
end

return Abyss
