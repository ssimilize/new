--[[
	DailyLogin (glow-up): the moments around the daily streak and reminders.

	  auto-open   once per join, when today's streak day is unclaimed, opens the LoginStreak
	              screen: only after the Welcome Back summary is done and nothing else is open,
	              and never while the tutorial runs (the HUD's Daily badge waits instead)
	  opt-in      when session.Reminders.prompt turns true (the server asks after the first
	              hatch of a later session), shows Roblox's notification opt-in and answers
	              Reminders.SetOptIn { on }

	Public:
	  DailyLogin:AskOptIn() -> boolean   shows ExperienceNotificationService's opt-in (yields);
	                                     true when the player is (or already was) opted in.
	                                     false when the service is unavailable or they declined.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Streak = require(Shared.Logic.LoginStreak)

local DailyLogin = {
	Name = "DailyLogin",
	Dependencies = { "Notifications" },
}

local SCREEN = "LoginStreak"
local FIRST_CHECK = 3 -- seconds after the first state arrives (Welcome Back opens first)
local CHECK_EVERY = 1
local GIVE_UP_AFTER = 180

local ctx
local asking = false

local function tutorialRunning(): boolean
	local step = tonumber(ctx.Store:Get("profile.Quests.tutorial.step"))
	return step ~= nil and step <= #Config.Quests.Tutorial
end

local function claimable(): boolean
	local state = ctx.Store:Get("profile.LoginStreak")
	if type(state) ~= "table" then
		return false
	end
	return Streak.Preview(state, ctx:Now() // 86400).canClaim
end

local function tryAutoOpen(elapsed: number)
	if not ctx.Router:Has(SCREEN) or tutorialRunning() or not claimable() then
		return -- nothing to show this session (the badge covers a later claim)
	end
	local busy = ctx.Store:Get("session.WelcomeBack.pending") == true or ctx.Router:Current() ~= nil
	if not busy then
		ctx.Router:Open(SCREEN)
		return
	end
	if elapsed < GIVE_UP_AFTER then
		task.delay(CHECK_EVERY, tryAutoOpen, elapsed + CHECK_EVERY)
	end
end

function DailyLogin:AskOptIn(): boolean
	local okService, service = pcall(function()
		return game:GetService("ExperienceNotificationService")
	end)
	if not okService or not service then
		return false
	end
	local okCan, can = pcall(function()
		return service:CanPromptOptInAsync()
	end)
	if not okCan then
		return false
	end
	if not can then
		return true -- already opted in (or not eligible; Roblox then drops the reminders)
	end
	local closed = false
	local okConnect, conn = pcall(function()
		return service.OptInPromptClosed:Connect(function()
			closed = true
		end)
	end)
	local okPrompt = pcall(function()
		service:PromptOptIn()
	end)
	local waited = 0
	while okPrompt and okConnect and not closed and waited < 120 do
		waited += task.wait(0.5)
	end
	if okConnect and conn then
		conn:Disconnect()
	end
	if not okPrompt then
		return false
	end
	local okAfter, still = pcall(function()
		return service:CanPromptOptInAsync()
	end)
	return okAfter and still == false
end

local function onPrompt(state)
	if type(state) ~= "table" or state.prompt ~= true or asking then
		return
	end
	asking = true
	task.spawn(function()
		local accepted = DailyLogin:AskOptIn()
		ctx.Net:Request("Reminders.SetOptIn", { on = accepted })
		asking = false
	end)
end

function DailyLogin.Init(context)
	ctx = context
	ctx.Store:WhenReady(function()
		task.delay(FIRST_CHECK, tryAutoOpen, 0)
	end)
	ctx.Store:Observe("session.Reminders", onPrompt)
end

function DailyLogin.Start() end

return DailyLogin
