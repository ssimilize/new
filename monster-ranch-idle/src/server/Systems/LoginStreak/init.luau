--[[
	LoginStreak (glow-up): the daily login calendar (Config.LoginStreak, rules in
	Logic/LoginStreak). One claim per UTC day, decided by the server's own day only
	(ctx:Day()), so a client clock or time-zone change can never claim twice.

	Save section (profile.LoginStreak), replicated whole:
	  { last, streak, pos, track, cycles, total, best, shield, shieldWeek, savedDay }
	  (fields documented in Logic/LoginStreak). Version 1; Migrate clamps a damaged section.

	Actions:
	  LoginStreak.Claim   claims today's calendar day (+ the milestone it reaches) through
	                      Rewards:Grant (source "daily_streak", so the client's reward card
	                      shows it). Fails "Already claimed today. Come back tomorrow!".
	Publishes StreakClaimed (player, { day, streak, track, shieldUsed, restarted }).

	Public API:
	  LoginStreak:Status(player) -> { claimedToday, streak, shields, deadline? }
	      deadline = unix end of the last UTC day that keeps a shield-less streak (Reminders)
]]

local LoginStreak = {
	Name = "LoginStreak",
	Dependencies = { "Rewards", "Progression" },
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logic = require(ReplicatedStorage.Shared.Logic.LoginStreak)

local ctx
local Config

LoginStreak.Profile = {
	Version = 1,
	Default = function()
		return {
			last = 0,
			streak = 0,
			pos = 0,
			track = 0,
			cycles = 0,
			total = 0,
			best = 0,
			shield = 1,
			shieldWeek = 0,
			savedDay = 0,
		}
	end,
	-- Future versions migrate here; today it only repairs a damaged section.
	Migrate = function(section, _fromVersion)
		for key, value in section do
			if type(value) ~= "number" then
				section[key] = nil
			end
		end
		section.pos = math.clamp(section.pos or 0, 0, 7)
		section.shield = math.clamp(section.shield or 1, 0, 1)
		return section
	end,
}

function LoginStreak:Status(player)
	local s = ctx:Section(player)
	if not s then
		return nil
	end
	local today = ctx:Day()
	return {
		claimedToday = (s.last or 0) >= today,
		streak = s.streak or 0,
		shields = Logic.ShieldsAt(s, today),
		deadline = Logic.Deadline(s, today),
	}
end

function LoginStreak.Init(context)
	ctx = context
	Config = ctx.Config
	local Rewards = ctx:GetSystem("Rewards")
	local Progression = ctx:GetSystem("Progression")

	ctx.Net:Handle("LoginStreak.Claim", function(player)
		local s = ctx:Section(player)
		local today = ctx:Day()
		local preview = Logic.Preview(s, today)
		if not preview.canClaim then
			ctx:Fail("Already claimed today. Come back tomorrow!")
		end
		local cycles = s.cycles or 0
		-- Record the claim before granting: nothing below yields, and a repeat request sees it.
		Logic.Apply(s, preview, today)
		ctx:Dirty(player)
		local items = Logic.Resolve(Logic.Items(preview, cycles), function(key)
			return Progression:IsUnlocked(player, key)
		end)
		local granted = Rewards:Grant(player, items, Config.LoginStreak.Source)
		ctx.Bus:Publish("StreakClaimed", player, {
			day = preview.pos,
			streak = preview.streak,
			track = preview.track,
			shieldUsed = preview.shieldUsed,
			restarted = preview.restarted,
		})
		ctx:RequestSave(player)
		return {
			day = preview.pos,
			streak = preview.streak,
			track = preview.track,
			shieldUsed = preview.shieldUsed,
			restarted = preview.restarted,
			milestone = if preview.milestone then preview.milestone.day else 0,
			items = granted,
		}
	end)
end

function LoginStreak.PlayerAdded(player, _info)
	local s = ctx:Section(player)
	-- Start the weekly shield clock at the first join (Default cannot read the time).
	if (s.shieldWeek or 0) == 0 then
		s.shieldWeek = Logic.Week(ctx:Day())
		ctx:Dirty(player, "shieldWeek")
	end
end

return LoginStreak
