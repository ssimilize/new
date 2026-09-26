--[[
	Community (glow-up L): monster tricks for the emote wheel, friend invites, the "Join our group"
	reward, Roblox Premium perks and the VIP balcony gate. Tuning in Config.Community, pure rules in
	Logic/Community. Player emotes need no server: the client plays Roblox's default emotes on its
	own character, and character animation replicates to everyone.

	  Tricks    Community.Trick { id, trick }: the monster must be the player's and in a pen; one
	            trick every TrickCooldown seconds. Fires Community.Trick { owner, id, trick } to
	            everyone, and the World controller plays it on that pen monster.
	  Invites   a first join whose launch data is "invite:<userId>" from a Roblox friend gets
	            Invites.inviteeReward once (profile.Community.invitedBy); the inviter gets
	            Invites.inviterReward by Market mail (kind "invite", id "invite:<invitee>"), at most
	            weeklyCap a UTC week, counted where the inviter collects it.
	  Group     Community.ClaimGroup: once per account, members of Config.Quests.GroupId only
	            (refused while it is 0; the client hides the row).
	  Premium   Community.ClaimPremium: Premium.daily once a UTC day. global.Community.premium lists
	            the Premium members here for the nameplate badge.
	  Balcony   Community.Balcony { enter }: up for VIP Rancher owners, down for anyone. Every
	            patrolSeconds the server moves characters without VIP off the deck.

	Roblox reads go through optional adapters so Lune can stand in for them, with a live
	fallback on the Player object (the same kind of read as SkyIslands' character position):
	  Services.Players.JoinData(player) -> table?     (player:GetJoinData())
	  Services.Players.IsPremium(player) -> boolean   (player.MembershipType == Premium)
	  Services.Characters.Position(player) -> {x,y,z}?, .MoveTo(player, {x,y,z})   (the character)

	Save section (profile.Community), version 1:
	  invitedBy = userId | 0, invites = { week, count }, invitesTotal, group = boolean, premiumDay
	Global (global.Community): premium = { ['u'..userId] = true }
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Community)

local Community = {
	Name = "Community",
	Dependencies = { "Rewards", "Monsters" },
	OptionalDependencies = { "Market", "Monetization", "Ranch" },
}

Community.Profile = {
	Version = 1,
	Default = function()
		return { invitedBy = 0, invites = { week = 0, count = 0 }, invitesTotal = 0, group = false, premiumDay = 0 }
	end,
}

local ctx
local Config, Cfg
local Rewards, Monsters

local lastTrick = {} -- [player] = ctx:Now() of the player's last trick
local premium = {} -- [player] = boolean (cached on join, refreshed on claim)

-- Helpers -------------------------------------------------------------------------------------

local function section(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

local function displayName(player): string
	return player.DisplayName or player.Name
end

local function joinData(player)
	local players = ctx.Services.Players
	if players and type(players.JoinData) == "function" then
		local ok, data = pcall(players.JoinData, player)
		return if ok then data else nil
	end
	local ok, data = pcall(function()
		return player:GetJoinData()
	end)
	return if ok then data else nil
end

local function isPremium(player): boolean
	local players = ctx.Services.Players
	if players and type(players.IsPremium) == "function" then
		local ok, result = pcall(players.IsPremium, player)
		return ok and result == true
	end
	local ok, result = pcall(function()
		return player.MembershipType == Enum.MembershipType.Premium
	end)
	return ok and result == true
end

local function characterPosition(player): { number }?
	local chars = ctx.Services.Characters
	if chars and type(chars.Position) == "function" then
		local ok, pos = pcall(chars.Position, player)
		return if ok and type(pos) == "table" then pos else nil
	end
	local ok, pos = pcall(function()
		local p = player.Character.HumanoidRootPart.Position
		return { p.X, p.Y, p.Z }
	end)
	return if ok then pos else nil
end

local function moveCharacter(player, to: { number }): boolean
	local chars = ctx.Services.Characters
	if chars and type(chars.MoveTo) == "function" then
		local ok, moved = pcall(chars.MoveTo, player, to)
		return ok and moved ~= false
	end
	local ok = pcall(function()
		player.Character:PivotTo(CFrame.new(to[1], to[2], to[3]))
	end)
	return ok
end

local function hasVip(player): boolean
	local Monetization = ctx:GetSystem("Monetization")
	return Monetization ~= nil and Monetization:HasPass(player, Cfg.VipBalcony.pass)
end

local function setPremium(player, on: boolean)
	premium[player] = on
	local global = ctx:Global()
	global.premium = global.premium or {}
	local key = "u" .. player.UserId
	if (global.premium[key] == true) ~= on then
		global.premium[key] = if on then true else nil
		ctx:DirtyGlobal("premium")
	end
end

-- Tricks --------------------------------------------------------------------------------------

local function trick(player, payload)
	section(player)
	local def = Cfg.TrickById[payload.trick]
	local m = Monsters:Get(player, payload.id)
	if not m then
		ctx:Fail("That monster doesn't exist")
	end
	local Ranch = ctx:GetSystem("Ranch")
	if Ranch and Ranch:PenOf(player, payload.id) <= 0 then
		ctx:Fail("Only monsters in your pens can do tricks")
	end
	local now = ctx:Now()
	if lastTrick[player] and now - lastTrick[player] < Cfg.TrickCooldown then
		ctx:Fail("Give your monster a moment to rest")
	end
	lastTrick[player] = now
	ctx.Net:FireAll("Community.Trick", { owner = player.UserId, id = payload.id, trick = def.id })
	return { state = def.state }
end

-- Invites -------------------------------------------------------------------------------------

local function processInvite(player)
	local inviter = Logic.ParseInvite(joinData(player), Cfg.Invites.launchPrefix)
	local s = ctx:Section(player)
	if not inviter or inviter == player.UserId or not s or s.invitedBy ~= 0 then
		return
	end
	local players = ctx.Services.Players
	local ok, friends = pcall(players.IsFriendsWith, player, inviter)
	s = ctx:Section(player) -- the friendship check yields
	if not ok or friends ~= true or not s or s.invitedBy ~= 0 then
		return
	end
	s.invitedBy = inviter
	ctx:Dirty(player, "invitedBy")
	Rewards:Grant(player, Cfg.Invites.inviteeReward, "invite")
	ctx:Notify(player, "Welcome! You and your friend both get a gift for playing together.", "reward")
	local Market = ctx:GetSystem("Market")
	if Market then
		Market:Send(player, inviter, {
			id = "invite:" .. player.UserId,
			kind = "invite",
			from = player.UserId,
			fromName = displayName(player),
		})
	end
	ctx:RequestSave(player)
	ctx.Bus:Publish("InviteJoined", player, { inviter = inviter })
	ctx.Analytics.Custom(player, "InviteJoined", 1, {})
end

-- Market mail of kind "invite", collected by the inviter.
local function receiveInvite(player, entry): boolean
	local s = ctx:Section(player)
	if not s then
		return false
	end
	local name = if type(entry.fromName) == "string" then entry.fromName else "A friend"
	local week = Logic.Week(ctx:Day())
	if s.invites.week ~= week then
		s.invites = { week = week, count = 0 }
	end
	s.invitesTotal += 1
	ctx:Dirty(player, "invitesTotal")
	if s.invites.count >= Cfg.Invites.weeklyCap then
		ctx:Dirty(player, "invites")
		ctx:Notify(player, string.format("%s joined from your invite! You've had all your invite gifts this week.", name), "info")
		return true
	end
	s.invites.count += 1
	ctx:Dirty(player, "invites")
	Rewards:Grant(player, Cfg.Invites.inviterReward, "invite")
	ctx:Notify(player, string.format("%s joined from your invite! Here's a thank-you gift.", name), "reward")
	return true
end

-- Group and Premium ---------------------------------------------------------------------------

local function claimGroup(player)
	local groupId = tonumber(Config.Quests.GroupId) or 0
	if groupId == 0 then
		ctx:Fail("Coming soon")
	end
	if section(player).group then
		ctx:Fail("Already claimed")
	end
	local players = ctx.Services.Players
	local ok, member = pcall(players.IsInGroup, player, groupId)
	if not ok or member ~= true then
		ctx:Fail("Join our Roblox group first, then claim")
	end
	local s = section(player) -- the group check yields
	if s.group then
		ctx:Fail("Already claimed")
	end
	s.group = true
	ctx:Dirty(player, "group")
	local granted = Rewards:Grant(player, Cfg.Group.reward, "group")
	ctx:RequestSave(player)
	return { rewards = granted }
end

local function claimPremium(player)
	local s = section(player)
	local day = ctx:Day()
	if s.premiumDay == day then
		ctx:Fail("Already claimed today. Come back tomorrow!")
	end
	local on = isPremium(player)
	s = section(player)
	setPremium(player, on)
	if not on then
		ctx:Fail("This gift is for Roblox Premium members")
	end
	if s.premiumDay == day then
		ctx:Fail("Already claimed today. Come back tomorrow!")
	end
	s.premiumDay = day
	ctx:Dirty(player, "premiumDay")
	local granted = Rewards:Grant(player, Cfg.Premium.daily, "premium")
	ctx:RequestSave(player)
	return { rewards = granted }
end

-- VIP balcony ---------------------------------------------------------------------------------

local function deckSpot(): { number }
	local b = Cfg.VipBalcony
	return { b.deck[1], b.deck[2] + b.height + 3, b.deck[3] }
end

local function balcony(player, payload)
	section(player)
	if payload.enter then
		if not hasVip(player) then
			ctx:Fail("The balcony is for VIP Rancher owners")
		end
		if not moveCharacter(player, deckSpot()) then
			ctx:Fail("Try again in a moment")
		end
	else
		moveCharacter(player, Cfg.VipBalcony.exit)
	end
	return nil
end

local function patrol()
	for _, player in ctx:Players() do
		if not hasVip(player) then
			local pos = characterPosition(player)
			if pos and Logic.InDeck(pos, Cfg.VipBalcony) then
				moveCharacter(player, Cfg.VipBalcony.exit)
				ctx:Notify(player, "The balcony is for VIP Rancher owners", "info")
			end
		end
	end
end

-- Public API ----------------------------------------------------------------------------------

function Community:IsPremium(player): boolean
	return premium[player] == true
end

-- Lifecycle -----------------------------------------------------------------------------------

function Community.Init(context)
	ctx = context
	Config = ctx.Config
	Cfg = Config.Community
	Rewards = ctx:GetSystem("Rewards")
	Monsters = ctx:GetSystem("Monsters")
	table.clear(lastTrick)
	table.clear(premium)
	local global = ctx:Global()
	global.premium = {}

	ctx.Net:Handle("Community.Trick", trick)
	ctx.Net:Handle("Community.ClaimGroup", claimGroup)
	ctx.Net:Handle("Community.ClaimPremium", claimPremium)
	ctx.Net:Handle("Community.Balcony", balcony)
	-- After the snapshot, so the invitee sees the reward popup and toast.
	ctx.Bus:Subscribe("PlayerReady", function(player, detail)
		if type(detail) == "table" and detail.firstJoin then
			ctx.Services.Spawn(function()
				processInvite(player)
			end)
		end
	end)
end

function Community.Start()
	local Market = ctx:GetSystem("Market")
	if Market then
		Market:RegisterMail("invite", receiveInvite)
	end
	ctx:Every(Cfg.VipBalcony.patrolSeconds, patrol)
end

function Community.PlayerAdded(player, _info)
	setPremium(player, isPremium(player))
end

function Community.PlayerRemoving(player)
	lastTrick[player] = nil
	premium[player] = nil
	local global = ctx:Global()
	local key = "u" .. player.UserId
	if global.premium and global.premium[key] then
		global.premium[key] = nil
		ctx:DirtyGlobal("premium")
	end
end

return Community
