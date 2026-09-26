--[[
	Parts/Battle (glow-up V): the one entry point for showing a fight. Stage fights / expeditions,
	the Arena and raids call it with the 2D viewer's options (Parts/BattleReplay) plus `stage`:

		local viewer = Battle.play(ctx, {
			replay, win, rewards, title, winText?, loseText?, retryText?, onRetry?, nextText?, onNext?,
			onClose?,
			stage = "meadow",          -- a Config.Regions id, "arena" or "raid" (Config/BattleStage themes)
		})
		viewer.Destroy()

	It draws the fight on the 3D battle stage (Parts/BattleStage) when it can, else in the 2D viewer:
	Logic/BattleStage.Choose with the CameraDirector free for a stage shot (no PhotoMode, no mount,
	no Focus modal, no other shot playing), Quality Low only up to `fallback.lowMaxUnits` fighters,
	and a median frame no slower than `fallback.maxFrameMs`. The 3D viewer itself hands over to the
	2D one if its shot cannot start or the stage fails to build.

		Battle.Mode(ctx, opts) -> "3d" | "2d", reason
		Battle.SetMode(mode?)       tests: force "3d" or "2d" (nil = choose)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.BattleStage)
local Plan = require(Shared.Logic.BattleStage)

local Client = script.Parent.Parent.Parent.Parent
local Quality = require(Client.Visuals.Quality)
local BattleReplay = require(script.Parent.BattleReplay)
local BattleStage = require(script.Parent.BattleStage)

local Battle = {}

local forced: string? = nil

function Battle.SetMode(mode: string?)
	forced = if mode == "3d" or mode == "2d" then mode else nil
end

function Battle.Mode(ctx, opts): (string, string)
	local director = ctx:GetController("CameraDirector")
	if not director then
		return "2d", "camera"
	end
	local cameraFree = director:CanStart(true) and (not director:IsBusy() or BattleStage.Holding())
	if forced == "2d" then
		return "2d", "forced"
	elseif forced == "3d" and cameraFree then
		return "3d", "forced"
	end
	local replay = opts.replay or {}
	local stats = Quality.Stats
	return Plan.Choose({
		units = #(replay.units or {}),
		low = Quality.IsLow(),
		cameraFree = cameraFree,
		frameMs = if type(stats) == "table" then stats.frameMs else nil,
	}, Tuning)
end

function Battle.play(ctx, opts)
	local ok, mode = pcall(Battle.Mode, ctx, opts)
	if ok and mode == "3d" then
		return BattleStage.play(ctx, opts, function()
			return BattleReplay.play(ctx, opts)
		end)
	end
	return BattleReplay.play(ctx, opts)
end

return Battle
