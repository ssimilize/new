--[[
	Quality controller (glow-up P): feeds Visuals/Quality, the level every visual reads.

	  profile.Settings   the Graphics choice (Logic/Quality.Choice: lowGraphics = Low, else
	                     settings.graphics "auto" | "high") -> Quality.SetChoice
	  RenderStepped      frame times into the Auto stepper (Logic/Quality, Config.Quality.Auto);
	                     once a second it is evaluated and Quality.SetAuto gets the level. No
	                     frames count for the first `warmup` seconds, for `hold` seconds after a
	                     screen opens (Router.Opened) or the character jumps `teleportStuds` in
	                     one frame, and single frames over `hitchMs` are dropped.
	  Visuals/Vfx        starts the particle budget loop (Vfx.StartBudget)

	Studio only: a perf overlay (median frame time, level, live particles, animated models) in the
	top-left corner while Config.Quality.Overlay.enabled or the Workspace attribute PerfOverlay is
	true. It is never built in a live server (RunService:IsStudio()).
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logic = require(Shared.Logic.Quality)

local Client = script.Parent.Parent
local Quality = require(Client.Visuals.Quality)
local Vfx = require(Client.Visuals.Vfx)
local Create = require(Client.UI.Create)

local QualityController = {
	Name = "Quality",
	Dependencies = {},
}

local ctx
local stepper: Logic.Stepper
local connections: { any } = {}
local lastRoot: Vector3? = nil
local sinceEval = 0
local overlay: TextLabel? = nil

local function rootPosition(): Vector3?
	local character = ctx.Player.Character
	local root = character and character.PrimaryPart
	return if root then root.Position else nil
end

local function onFrame(dt: number)
	local now = os.clock()
	local pos = rootPosition()
	if pos and lastRoot and (pos - lastRoot).Magnitude >= stepper.cfg.teleportStuds then
		Logic.Hold(stepper, now)
	end
	lastRoot = pos
	Logic.Sample(stepper, dt, now)
	sinceEval += dt
	if sinceEval >= 1 then
		sinceEval = 0
		local level, changed = Logic.Evaluate(stepper, now)
		Quality.Stats.frameMs = stepper.median
		if changed then
			Quality.SetAuto(level)
		end
	end
end

local function overlayOn(): boolean
	return ctx.Config.Quality.Overlay.enabled == true or workspace:GetAttribute("PerfOverlay") == true
end

local function paintOverlay()
	if not overlay then
		return
	end
	overlay.Visible = overlayOn()
	if overlay.Visible then
		local stats = Quality.Stats
		overlay.Text = string.format(
			"%.1f ms  %s (%s)  %d particles  %d animated",
			stats.frameMs,
			Quality.Id(),
			Quality.Choice(),
			math.floor(Vfx.Live() + 0.5),
			stats.animated
		)
	end
end

local function buildOverlay()
	overlay = Create.New("TextLabel", {
		Name = "PerfOverlay",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.Code,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutoLocalize = false,
		Size = UDim2.fromOffset(420, 20),
		Position = UDim2.fromOffset(4, 4),
		Visible = false,
		Parent = ctx.UI.Top,
	})
	local elapsed = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt: number)
			elapsed += dt
			if elapsed >= ctx.Config.Quality.Overlay.refresh then
				elapsed = 0
				paintOverlay()
			end
		end)
	)
end

function QualityController.Init(context)
	ctx = context
	stepper = Logic.NewStepper(ctx.Config.Quality.Auto, os.clock())
end

function QualityController.Start()
	local lastChoice = Quality.Choice()
	table.insert(
		connections,
		ctx.Store:Observe("profile.Settings", function(settings)
			local choice = Logic.Choice(settings)
			if choice ~= lastChoice then
				if choice == "auto" then
					-- Back to auto: measure afresh from the level Auto had reached.
					Logic.Reset(stepper, os.clock(), Quality.AutoLevel())
				end
				lastChoice = choice
			end
			Quality.SetChoice(choice)
		end)
	)
	table.insert(connections, RunService.RenderStepped:Connect(onFrame))
	table.insert(
		connections,
		ctx.Router.Opened:Connect(function()
			Logic.Hold(stepper, os.clock())
		end)
	)
	Vfx.StartBudget()
	if RunService:IsStudio() then
		buildOverlay()
	end
end

-- Tests and the Studio overlay: the stepper's current state.
function QualityController:Stepper()
	return stepper
end

function QualityController.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	Vfx.StopBudget()
	if overlay then
		overlay:Destroy()
		overlay = nil
	end
end

return QualityController
