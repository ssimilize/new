--[[
	ClockworkCanyon controller (R2-CLOCKWORK): the gear tower landmark and the walk-in canyon
	Area, built entirely on this client (like Controllers/DeepReef), from Config.Clockwork +
	Visuals/ClockworkBuild + Visuals/ClockworkGears. Nothing is built in the Trading Hub place.

	  Gate Portal ("Enter")   opens the Expeditions screen on the "clockwork" region (its own
	                          opensAt and Ranch Level gate the expedition itself, same as every
	                          region; the Expeditions screen shows the lock, like every region -
	                          there is no separate teleport to gate here, unlike the Deep Reef's
	                          dive: Clockwork Canyon is walked to, not swum to).
	  Gears                   every gear the builder made turns client-side every Heartbeat
	                          (Visuals/ClockworkGears), cheap (a handful of parts) and
	                          streaming-safe (a gear whose model has streamed out is dropped from
	                          the list instead of erroring).

	ClockworkCanyon.GearCount() -> number   tests: how many gears are currently turning.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Client = script.Parent.Parent
local ClockworkBuild = require(Client.Visuals.ClockworkBuild)
local ClockworkGears = require(Client.Visuals.ClockworkGears)

local Cfg = Config.Clockwork

local ClockworkCanyon = {
	Name = "ClockworkCanyon",
	Dependencies = {},
}

local ctx
local built = false
local landmark, area
local gearState

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

local function wireArea(folder: Folder)
	local gate = folder:FindFirstChild("Gate")
	local portal = gate and gate:FindFirstChild("Portal")
	if portal then
		prompt(portal, "Enter", "Clockwork Gate", 14, function()
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
	built = true
	landmark = ClockworkBuild.Landmark(workspace)
	area = ClockworkBuild.Area(workspace)
	wireArea(area :: Folder)
	local gears = ClockworkGears.Build(landmark :: Model)
	for _, g in ClockworkGears.Build(area :: Folder).gears do
		table.insert(gears.gears, g)
	end
	gearState = gears
end

-- Tests: how many gears are currently turning.
function ClockworkCanyon.GearCount(): number
	return ClockworkGears.Count(gearState)
end

function ClockworkCanyon.Init(context)
	ctx = context
end

function ClockworkCanyon.Start()
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
		ClockworkGears.Step(gearState, dt)
	end)
end

return ClockworkCanyon
