--[[
	Quality (glow-up P): the one quality level every visual reads. Client only, no Roblox calls,
	so any module (Vfx, MonsterAnimator, controllers, screens) may require it.

		Quality.Level() -> 1 | 2 | 3          1 = low, 2 = medium, 3 = high (Config.Quality.Rank)
		Quality.Id() -> "low" | "medium" | "high"
		Quality.IsLow() -> boolean            Level() == 1: what the old lowGraphics readers use
		Quality.Choice() -> "auto" | "high" | "low"   the player's Graphics setting
		Quality.AutoLevel() -> level          what the Auto stepper measured (shown as "Auto · Medium")
		Quality.Changed                       Signal(level, previous): fires only when Level() changes
		Quality.SetChoice(choice)             the Quality controller, from profile.Settings
		Quality.SetAuto(level)                the Quality controller's stepper (tests may call it)
		Quality.Stats                         { frameMs, particles, animated } for the Studio overlay

	Reduced motion is NOT a quality level: it stays UI/Anim.enabled, driven only by the player's
	explicit Low choice (Settings.lowGraphics, the Broadcasts controller). Auto dropping to Low
	cuts effects and detail but never the motion of menus, toasts or celebrations.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Kernel.Signal)
local Logic = require(Shared.Logic.Quality)
local Config = require(Shared.Config)

local Quality = {}

local IDS = { "low", "medium", "high" }

local choice = "auto"
local autoLevel = math.clamp(Config.Quality.Auto.start or 3, 1, 3)
local level = autoLevel

Quality.Changed = Signal.new()
Quality.Stats = { frameMs = 0, particles = 0, animated = 0 }

local function update()
	local nextLevel = Logic.Resolve(choice, autoLevel)
	if nextLevel ~= level then
		local previous = level
		level = nextLevel
		Quality.Changed:Fire(level, previous)
	end
end

function Quality.Level(): number
	return level
end

function Quality.Id(): string
	return IDS[level]
end

function Quality.IsLow(): boolean
	return level == 1
end

function Quality.Choice(): string
	return choice
end

function Quality.AutoLevel(): number
	return autoLevel
end

function Quality.SetChoice(value: string)
	if value ~= "auto" and value ~= "high" and value ~= "low" then
		value = "auto"
	end
	choice = value
	update()
end

function Quality.SetAuto(value: number)
	autoLevel = math.clamp(math.floor(tonumber(value) or 3), 1, 3)
	update()
end

return Quality
