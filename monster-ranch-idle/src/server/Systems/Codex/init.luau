--[[
	Codex (glow-up O): milestones that pay. Discoveries stay where they always were
	(profile.Monsters.codex, read through Monsters:Codex); this system only keeps which
	milestones were claimed. Milestones, their progress and rewards: Logic/Codex + Config/Codex.

	Save section (profile.Codex, version 1):
	  claimed = { [milestoneId] = unix }   each milestone once per account
	  owed    = { itemId }                 Mastery cosmetics still to hand over (Mastery absent)
	  badges  = { [milestoneId] = true }   Roblox badges awarded (private; retried on join)

	Actions: Codex.Claim { milestone } -> { milestone, gems, items }
	  Fails: unknown milestone, already claimed, not done yet ("Find N more forms first").
	  Gems arrive through Rewards:Grant (source "codex": the reward card); titles and the Codex
	  Crown aura through Mastery:GrantItem (worn at once when that slot is empty).
	Publishes CodexClaimed (player, { milestone, kind }).

	Adapter (optional; absent = badges skipped): ctx.Services.Badges.Award(userId, badgeId) -> boolean

	Public API:
	  Codex:Claimed(player) -> { [milestoneId]: unix }
	  Codex:ClaimableCount(player) -> number
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Codex)

local Codex = {
	Name = "Codex",
	Dependencies = { "Monsters", "Rewards" },
	OptionalDependencies = { "Mastery" },
}

-- Fills anything missing and drops what is not ours (a damaged or hand-edited section).
local function normalize(s)
	if type(s) ~= "table" then
		s = {}
	end
	local claimed = {}
	if type(s.claimed) == "table" then
		for id, at in s.claimed do
			if type(id) == "string" and (type(at) == "number" or at == true) then
				claimed[id] = if type(at) == "number" then at else 0
			end
		end
	end
	local owed = {}
	if type(s.owed) == "table" then
		for _, itemId in s.owed do
			if type(itemId) == "string" then
				table.insert(owed, itemId)
			end
		end
	end
	local badges = {}
	if type(s.badges) == "table" then
		for id, yes in s.badges do
			if type(id) == "string" and yes == true then
				badges[id] = true
			end
		end
	end
	for key in s do
		s[key] = nil
	end
	s.claimed, s.owed, s.badges = claimed, owed, badges
	return s
end

Codex.Profile = {
	Version = 1,
	Default = function()
		return { claimed = {}, owed = {}, badges = {} }
	end,
	Migrate = function(section, _fromVersion)
		return normalize(section)
	end,
	Private = { "badges" },
}

local ctx
local Monsters, Rewards

local function mustSection(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

-- Mastery cosmetics: handed over now, or kept owed until Mastery is plugged in.
local function payItems(player, s)
	if #s.owed == 0 then
		return
	end
	local Mastery = ctx:GetSystem("Mastery")
	if not Mastery then
		return
	end
	local left = {}
	for _, itemId in s.owed do
		if not Mastery:GrantItem(player, itemId, true) then
			table.insert(left, itemId)
		end
	end
	s.owed = left
	ctx:Dirty(player, "owed")
end

-- Roblox badges for claimed milestones that have one; the adapter may yield, so off the request.
local function awardBadges(player, s)
	local adapter = ctx.Services.Badges
	if type(adapter) ~= "table" or type(adapter.Award) ~= "function" then
		return
	end
	local ids = Logic.ById()
	for id in s.claimed do
		local m = ids[id]
		if m and m.badge > 0 and not s.badges[id] then
			s.badges[id] = true -- one attempt in flight; cleared again if it fails
			ctx.Services.Spawn(function()
				local ok, awarded = pcall(adapter.Award, player.UserId, m.badge)
				local live = ctx:Section(player)
				if live and not (ok and awarded ~= false) then
					live.badges[id] = nil
					ctx:Log("Codex badge %s not awarded to %s: %s", id, tostring(player.UserId), tostring(awarded))
				end
			end)
		end
	end
end

local function claim(player, payload)
	local s = mustSection(player)
	local m = Logic.ById()[payload.milestone]
	if not m then
		ctx:Fail("That milestone doesn't exist")
	end
	if s.claimed[m.id] then
		ctx:Fail("Already claimed")
	end
	local have, need = Logic.Progress(m, Logic.Found(Monsters:Codex(player)))
	if have < need then
		ctx:Fail(string.format("Find %d more forms first", need - have))
	end
	s.claimed[m.id] = ctx:Now()
	ctx:Dirty(player, "claimed", m.id)
	if m.gems > 0 then
		Rewards:Grant(player, { { kind = "gems", amount = m.gems } }, ctx.Config.Codex.Source)
	end
	if #m.items > 0 then
		for _, itemId in m.items do
			table.insert(s.owed, itemId)
		end
		payItems(player, s)
	end
	awardBadges(player, s)
	ctx.Bus:Publish("CodexClaimed", player, { milestone = m.id, kind = m.kind })
	ctx.Analytics.Custom(player, "CodexMilestone", m.order, { milestone = m.id })
	ctx:RequestSave(player)
	return { milestone = m.id, gems = m.gems, items = m.items }
end

-- Public API ------------------------------------------------------------------------------

function Codex:Claimed(player)
	local s = ctx:Section(player)
	return if s then s.claimed else {}
end

function Codex:ClaimableCount(player): number
	local s = ctx:Section(player)
	if not s then
		return 0
	end
	return Logic.Claimable(Monsters:Codex(player), s.claimed)
end

-- Lifecycle ------------------------------------------------------------------------------

function Codex.Init(context)
	ctx = context
	Monsters = ctx:GetSystem("Monsters")
	Rewards = ctx:GetSystem("Rewards")
	ctx.Net:Handle("Codex.Claim", claim)
end

function Codex.PlayerAdded(player, _info)
	local s = ctx:Section(player)
	if not s then
		return
	end
	normalize(s)
	ctx:Dirty(player, "claimed")
	payItems(player, s)
	awardBadges(player, s)
end

return Codex
