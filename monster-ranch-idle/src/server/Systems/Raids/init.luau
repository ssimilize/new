--[[
	Raids (update 2.1): 4-player co-op raid bosses on a server. Rules: Config/Raids.

	Global (global.Raids): { lobbies = { [lobbyId] = Lobby } }
	  Lobby = { id, raid, host = userId, hostName, expiresAt,
	            members = { { userId, name, power } } }   -- members[1] is the host
	Session (session.Raids): { lobby = lobbyId|false }
	Save section (profile.Raids): { day, rewarded, wins, runs }
	  rewarded = raid wins paid with the raid reward today (≤ Config.DailyRewards)

	Actions: Raids.Open { raid, ids }, Raids.Join { lobby, ids }, Raids.Leave, Raids.Launch.
	Monster ids stay server-side. Launch (host) re-checks every member's monsters, drops
	members who left or whose monsters are gone, simulates one battle (BattleSim, up to
	MaxPlayers × PerPlayer allies against the boss and adds) and sends each member
	Raids.Result { raid, replay, win, rewards }. Lobbies expire after LobbySeconds.
	Publishes RaidFinished (player, { raid, win }).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local BattleSim = require(Shared.Logic.BattleSim)
local Formulas = require(Shared.Logic.Formulas)

local Raids = {
	Name = "Raids",
	Dependencies = { "Progression", "Monsters", "Rewards" },
}

Raids.Profile = {
	Version = 1,
	Default = function()
		return { day = 0, rewarded = 0, wins = 0, runs = 0 }
	end,
}

local ctx
local Config -- Config.Raids
local Progression, Monsters, Rewards

local teams = {} -- [lobbyId] = { [userId] = { monsterId } }
local memberOf = {} -- [userId] = lobbyId
local nextId = 0

local function lobbies()
	return ctx:Global().lobbies
end

local function setSession(player)
	local sess = ctx:Session(player)
	if sess then
		sess.lobby = memberOf[player.UserId] or false
		ctx:DirtySession(player)
	end
end

local function playerOf(userId: number)
	return ctx:PlayerByUserId(userId)
end

local function checkTeam(player, ids: { string }): number
	local seen, power = {}, 0
	for _, id in ids do
		local m = Monsters:Get(player, id)
		if not m then
			ctx:Fail("That monster doesn't exist")
		end
		if m.stage < 3 then
			ctx:Fail("Only Adults can join a raid")
		end
		if m.busy then
			ctx:Fail(Formulas.DisplayName(m) .. " is busy")
		end
		if seen[id] then
			ctx:Fail("Pick different monsters")
		end
		seen[id] = true
		power += Formulas.MonsterPower(m)
	end
	return math.floor(power)
end

local function close(id: string)
	local lobby = lobbies()[id]
	if not lobby then
		return
	end
	for _, member in lobby.members do
		memberOf[member.userId] = nil
		local p = playerOf(member.userId)
		if p then
			setSession(p)
		end
	end
	lobbies()[id] = nil
	teams[id] = nil
	ctx:DirtyGlobal("lobbies")
end

local function removeMember(userId: number)
	local id = memberOf[userId]
	local lobby = id and lobbies()[id]
	if not lobby then
		memberOf[userId] = nil
		return
	end
	if lobby.host == userId then
		close(id)
		return
	end
	for i, member in lobby.members do
		if member.userId == userId then
			table.remove(lobby.members, i)
			break
		end
	end
	teams[id][userId] = nil
	memberOf[userId] = nil
	local p = playerOf(userId)
	if p then
		setSession(p)
	end
	ctx:DirtyGlobal("lobbies")
end

-- Enemy side -----------------------------------------------------------------------------

local function raidRecord(spec, isBoss: boolean)
	local def = ctx.Config.Species.ById[spec.line]
	local form = ctx.Config.Species.Form(spec.line, 3, spec.form)
	return {
		line = spec.line,
		stage = 3,
		form = form.id,
		rarity = spec.rarity,
		variant = 0,
		muts = {},
		traits = {},
		hidden = 0,
		weight = def.weight,
		lv = spec.level,
		stars = spec.stars,
		mood = 100,
		name = "",
		statMult = spec.statMult,
		hpMult = spec.hpMult,
		boss = if isBoss then true else nil,
	}
end

local function enemiesFor(raid)
	local list = { raidRecord(raid.boss, true) }
	for _, add in raid.adds do
		table.insert(list, raidRecord(add, false))
	end
	return list
end

-- Actions ------------------------------------------------------------------------------

local function open(player, raidId: string, ids)
	Progression:Require(player, Config.Unlock)
	if memberOf[player.UserId] then
		ctx:Fail("You're already in a raid lobby")
	end
	local power = checkTeam(player, ids)
	nextId += 1
	local id = "R" .. tostring(nextId)
	lobbies()[id] = {
		id = id,
		raid = raidId,
		host = player.UserId,
		hostName = player.DisplayName or player.Name,
		expiresAt = ctx:Now() + Config.LobbySeconds,
		members = { { userId = player.UserId, name = player.DisplayName or player.Name, power = power } },
	}
	teams[id] = { [player.UserId] = table.clone(ids) }
	memberOf[player.UserId] = id
	ctx:DirtyGlobal("lobbies")
	setSession(player)
	return { lobby = id }
end

local function join(player, id: string, ids)
	Progression:Require(player, Config.Unlock)
	local lobby = lobbies()[id]
	if not lobby then
		ctx:Fail("That raid lobby is gone")
	end
	if memberOf[player.UserId] then
		ctx:Fail("You're already in a raid lobby")
	end
	if #lobby.members >= Config.MaxPlayers then
		ctx:Fail("That raid is full")
	end
	local power = checkTeam(player, ids)
	table.insert(lobby.members, { userId = player.UserId, name = player.DisplayName or player.Name, power = power })
	teams[id][player.UserId] = table.clone(ids)
	memberOf[player.UserId] = id
	ctx:DirtyGlobal("lobbies")
	setSession(player)
	return { members = #lobby.members }
end

local function payout(player, raid, win: boolean)
	local s = ctx:Section(player)
	if not s then
		return {}
	end
	if s.day ~= ctx:Day() then
		s.day = ctx:Day()
		s.rewarded = 0
	end
	s.runs += 1
	local items = Config.Consolation
	if win then
		s.wins += 1
		if s.rewarded < Config.DailyRewards then
			s.rewarded += 1
			items = raid.reward
		end
	end
	ctx:Dirty(player)
	return Rewards:Grant(player, items, "raid", { silent = true })
end

local function launch(player)
	local id = memberOf[player.UserId]
	local lobby = id and lobbies()[id]
	if not lobby then
		ctx:Fail("You're not in a raid lobby")
	end
	if lobby.host ~= player.UserId then
		ctx:Fail("Only the host can start the raid")
	end
	local raid = Config.ById[lobby.raid]
	-- Everyone's monsters, in join order; members who can't field theirs sit out.
	local allies, fighters = {}, {}
	for _, member in table.clone(lobby.members) do
		local p = playerOf(member.userId)
		local ok = p ~= nil
		local records = {}
		if p then
			for _, mid in teams[id][member.userId] or {} do
				local m = Monsters:Get(p, mid)
				if not m or m.busy or m.stage < 3 then
					ok = false
				else
					table.insert(records, m)
				end
			end
		end
		if ok and #records > 0 then
			table.insert(fighters, p)
			for _, m in records do
				table.insert(allies, m)
			end
		elseif member.userId ~= lobby.host then
			removeMember(member.userId)
		end
	end
	if #fighters == 0 then
		ctx:Fail("Your raid team isn't ready")
	end
	local seed = ctx.Rng:Int(1, 2 ^ 30)
	local replay = BattleSim.Simulate(allies, enemiesFor(raid), seed, {
		boss = true,
		maxAllies = Config.MaxPlayers * Config.PerPlayer,
		maxTurns = Config.MaxTurns,
	})
	local win = replay.win == true
	close(id)
	for _, p in fighters do
		local rewards = payout(p, raid, win)
		ctx.Net:Fire(p, "Raids.Result", { raid = raid.id, replay = replay, win = win, rewards = rewards })
		ctx.Bus:Publish("RaidFinished", p, { raid = raid.id, win = win })
	end
	return { win = win }
end

-- Lifecycle ----------------------------------------------------------------------------

function Raids.Init(context)
	ctx = context
	Config = ctx.Config.Raids
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	Rewards = ctx:GetSystem("Rewards")
	table.clear(teams)
	table.clear(memberOf)
	ctx:Global().lobbies = {}

	ctx.Net:Handle("Raids.Open", function(player, payload)
		return open(player, payload.raid, payload.ids)
	end)
	ctx.Net:Handle("Raids.Join", function(player, payload)
		return join(player, payload.lobby, payload.ids)
	end)
	ctx.Net:Handle("Raids.Leave", function(player)
		if not memberOf[player.UserId] then
			ctx:Fail("You're not in a raid lobby")
		end
		removeMember(player.UserId)
		return nil
	end)
	ctx.Net:Handle("Raids.Launch", function(player)
		return launch(player)
	end)
end

function Raids.Start()
	ctx:Every(5, function()
		local now = ctx:Now()
		for id, lobby in table.clone(lobbies()) do
			if now >= lobby.expiresAt then
				close(id)
			end
		end
	end)
end

function Raids.PlayerAdded(player, _info)
	setSession(player)
end

function Raids.PlayerRemoving(player)
	removeMember(player.UserId)
end

return Raids
