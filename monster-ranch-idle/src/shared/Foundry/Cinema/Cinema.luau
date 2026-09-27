--!strict
-- Cinema (LT5 Lens and Cinema): a camera language per game. Pure maths on plain { x, y, z }
-- tables; the game turns poses into CFrames (CFrame.lookAt(position, lookAt)) and owns every
-- Instance (camera, DepthOfFieldEffect, ColorCorrection, UI).
--
--   local Cinema = require("../Cinema/Cinema")
--   local profile = Cinema.profile("guildhall")          -- packages/Cinema/profiles/<game>.luau
--   local lang = Cinema.Language.new(profile)
--   local pose = lang.frame({ x = 10, y = 0, z = 4 }, 2)  -- { position, lookAt, look, fov, distance, ... }
--   local dof = Cinema.Focus.dof(profile.focus, pose.distance, adapter.quality())
--   local director = Cinema.Rails.director(adapter, Cinema.moments(profile), sink)
--   local photo = Cinema.PhotoMode.new(adapter, Cinema.photoConfig(profile), sink)
--   local rec = Cinema.Recorder.new({ hz = 30 })
--
-- Modules: Vec, Ease, Language, Focus, Rails, PhotoMode, Recorder (each file documents itself).

local Ease = require("./Ease")
local Focus = require("./Focus")
local Language = require("./Language")
local PhotoMode = require("./PhotoMode")
local Rails = require("./Rails")
local Recorder = require("./Recorder")
local Vec = require("./Vec")

local Cinema = {}

Cinema.VERSION = "0.1.0"
Cinema.Vec = Vec
Cinema.Ease = Ease
Cinema.Language = Language
Cinema.Focus = Focus
Cinema.Rails = Rails
Cinema.PhotoMode = PhotoMode
Cinema.Recorder = Recorder

Cinema.PROFILES = table.freeze({ "guildhall", "monster-ranch" })

-- The shipped profile for a game id (string requires must be literals, hence the branches).
-- Required lazily: a game synced with vendor.ownDataOnly carries only its own profile, so
-- asking for another game's errors here, and only when asked.
local function loadProfile(game: string, load: () -> any): any
	local ok, profile = pcall(load)
	if not ok then
		error(`Cinema.profile: the {game} camera profile is not vendored in this game (a sync with `
			.. `vendor.ownDataOnly keeps only the game's own profile): {profile}`, 3)
	end
	return profile
end

function Cinema.profile(game: string): any
	if game == "guildhall" then
		return loadProfile(game, function() return require("./profiles/guildhall") end)
	elseif game == "monster-ranch" then
		return loadProfile(game, function() return require("./profiles/monster-ranch") end)
	end
	error(`Cinema.profile: no camera language for {game} (have {table.concat(Cinema.PROFILES, ", ")})`, 2)
end

-- The profile's moments with rail names swapped for the rail tables, ready for Rails.director.
function Cinema.moments(profile: any): { any }
	local out = {}
	for _, m in ipairs(profile.moments or {}) do
		local copy = table.clone(m)
		if type(m.rail) == "string" then
			copy.rail = (profile.rails or {})[m.rail]
			if copy.rail == nil then
				error(`Cinema.moments: moment {m.id or m.on} names an unknown rail {m.rail}`, 2)
			end
		end
		table.insert(out, copy)
	end
	return out
end

-- The PhotoMode config for a profile: its photo block plus its focus curve.
function Cinema.photoConfig(profile: any): any
	local p = profile.photo
	if type(p) ~= "table" then
		error(`Cinema.photoConfig: {profile.game} has no photo block`, 2)
	end
	local cfg = table.clone(p)
	if cfg.focus == nil then
		cfg.focus = profile.focus
	end
	return cfg
end

-- Every problem with a profile: language, focus curve (and that the subject stays sharp at every
-- band), rails, moments and photo config. {} when the profile is usable.
function Cinema.validateProfile(profile: any): { string }
	local problems = Language.validate(profile)
	if #problems > 0 then
		return problems
	end
	if profile.focus ~= nil then
		for _, p in ipairs(Focus.check(profile.focus, Focus.zoomsFor(profile))) do
			table.insert(problems, "focus: " .. p)
		end
	end
	for name, rail in pairs(profile.rails or {}) do
		for _, p in ipairs(Rails.validate(rail)) do
			table.insert(problems, `rails.{name}: {p}`)
		end
	end
	local ok, moments = pcall(Cinema.moments, profile)
	if not ok then
		table.insert(problems, tostring(moments))
	else
		for _, p in ipairs(Rails.validateMoments(moments)) do
			table.insert(problems, p)
		end
	end
	if profile.photo ~= nil then
		for _, p in ipairs(PhotoMode.validate(Cinema.photoConfig(profile))) do
			table.insert(problems, p)
		end
	end
	return problems
end

return Cinema
