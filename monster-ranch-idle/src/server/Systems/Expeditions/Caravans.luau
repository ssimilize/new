--[[
	Caravans (part of Expeditions, S4): co-op expeditions for 2–4 players on the same server.

	Lobby (global.Expeditions.caravans[id], mirrored into each member's session.Expeditions.caravan):
	  { id, host = userId, hostName, region, stage, duration,
	    members = { { userId, name, slot, power } },   -- members[1] is the host
	    expiresAt }

	Flow:
	  OpenCaravan   host picks region/stage (≤ their cleared stage) and 4 h or 8 h; the host's
	                first free slot and default squad are reserved. The lobby expires after
	                Regions.Caravan.lobbySeconds.
	  JoinCaravan   another player reserves one free slot and a squad (≤ maxPlayers).
	  LeaveCaravan  a member leaves; the host leaving closes the lobby.
	  LaunchCaravan host only, ≥ minPlayers: every member's slot starts an expedition tagged
	                with the caravan id (+lootBonus and the shared chest on claim). Members who
	                are no longer ready (left, slot taken, squad busy) are dropped first.
	Players leaving the server are removed; a leaving host closes the lobby.
	Squad ids stay server-side (never replicated in the lobby).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local TableUtil = require(Shared.Logic.TableUtil)

local Caravans = {}

local ctx
local host -- helpers from Expeditions/init.luau
local Cfg

local nextId = 0
local squads = {} -- [caravanId] = { ["u" .. userId] = { id } }
local memberOf = {} -- [userId] = caravanId

local function userKey(userId: number): string
	return "u" .. tostring(userId)
end

local function displayName(player): string
	return player.DisplayName or player.Name or ("Player " .. tostring(player.UserId))
end

local function lobbies()
	local root = ctx:Global()
	if not root.caravans then
		root.caravans = {}
	end
	return root.caravans
end

local function memberIndex(lobby, userId: number): number?
	for i, m in lobby.members do
		if m.userId == userId then
			return i
		end
	end
	return nil
end

-- Pushes the lobby to the global list and to every member's session.
local function publish(lobby)
	ctx:DirtyGlobal("caravans", lobby.id)
	for _, m in lobby.members do
		local player = ctx:PlayerByUserId(m.userId)
		if player then
			host.setSessionCaravan(player, TableUtil.deepCopy(lobby))
		end
	end
end

local function close(id: string, message: string?)
	local lobby = lobbies()[id]
	if not lobby then
		return
	end
	lobbies()[id] = nil
	squads[id] = nil
	ctx:DirtyGlobal("caravans", id)
	for _, m in lobby.members do
		if memberOf[m.userId] == id then
			memberOf[m.userId] = nil
		end
		local player = ctx:PlayerByUserId(m.userId)
		if player then
			host.setSessionCaravan(player, false)
			if message then
				ctx:Notify(player, message, "info")
			end
		end
	end
end

local function removeMember(id: string, userId: number)
	local lobby = lobbies()[id]
	if not lobby then
		return
	end
	local index = memberIndex(lobby, userId)
	if index then
		table.remove(lobby.members, index)
	end
	if squads[id] then
		squads[id][userKey(userId)] = nil
	end
	if memberOf[userId] == id then
		memberOf[userId] = nil
	end
	local player = ctx:PlayerByUserId(userId)
	if player then
		host.setSessionCaravan(player, false)
	end
	publish(lobby)
end

local function freeSlot(player): number?
	local count = host.slotCount(player)
	for i, slot in host.slotsOf(player) do
		if i > count then
			break
		end
		if slot.state == "idle" then
			return i
		end
	end
	return nil
end

-- Can this member still go? Returns (ok, why?).
local function checkMember(player, slotIndex: number, ids: { string }): (boolean, string?)
	if slotIndex > host.slotCount(player) then
		return false, "That expedition slot is locked"
	end
	if host.slotsOf(player)[slotIndex].state ~= "idle" then
		return false, "That slot is already exploring"
	end
	local records, why = host.checkSquad(player, ids)
	if not records then
		return false, why
	end
	return true, nil
end

local function liveLobby(id: string)
	local lobby = lobbies()[id]
	if not lobby or lobby.expiresAt <= ctx:Now() then
		ctx:Fail("That caravan has already left or closed")
	end
	return lobby
end

local function requireOpen(player)
	if not ctx.Config.Flags.Caravans then
		ctx:Fail("Caravans are closed right now")
	end
	host.progression:Require(player, Cfg.unlock)
end

-- Public (used by Expeditions) ----------------------------------------------------------

function Caravans.Init(context, helpers)
	ctx = context
	host = helpers
	Cfg = ctx.Config.Regions.Caravan
	nextId = 0
	squads = {}
	memberOf = {}
	lobbies()
	ctx:DirtyGlobal("caravans")
end

-- Is this slot reserved by the player's open caravan lobby?
function Caravans.IsReserved(player, slotIndex: number): boolean
	local id = memberOf[player.UserId]
	local lobby = id and lobbies()[id]
	if not lobby then
		return false
	end
	local index = memberIndex(lobby, player.UserId)
	return index ~= nil and lobby.members[index].slot == slotIndex
end

function Caravans.Of(player)
	local id = memberOf[player.UserId]
	return id and lobbies()[id]
end

function Caravans.Tick(now: number)
	for id, lobby in table.clone(lobbies()) do
		if lobby.expiresAt <= now then
			close(id, "The caravan lobby expired before it launched")
		end
	end
end

function Caravans.PlayerRemoving(player)
	local id = memberOf[player.UserId]
	local lobby = id and lobbies()[id]
	if not lobby then
		memberOf[player.UserId] = nil
		return
	end
	if lobby.host == player.UserId then
		close(id, "The caravan host left the server")
	else
		removeMember(id, player.UserId)
	end
end

-- Action handlers ---------------------------------------------------------------------------

function Caravans.Open(player, payload)
	requireOpen(player)
	local region = host.requireRegion(player, payload.region)
	if memberOf[player.UserId] then
		ctx:Fail("You're already in a caravan")
	end
	local cleared = host.cleared(player, payload.region)
	if payload.stage > cleared then
		ctx:Fail("Clear this stage before leading a caravan there")
	end
	local duration = tonumber(payload.duration)
	if not duration or not table.find(Cfg.durations, duration) then
		ctx:Fail("Caravans last 4 or 8 hours")
	end
	local slotIndex = freeSlot(player)
	if not slotIndex then
		ctx:Fail("You need a free expedition slot")
	end
	local ids = host.getSquad(player)
	local ok, why = checkMember(player, slotIndex :: number, ids)
	if not ok then
		ctx:Fail(why or "Your squad can't go")
	end

	nextId += 1
	local id = "c" .. tostring(nextId)
	local lobby = {
		id = id,
		host = player.UserId,
		hostName = displayName(player),
		region = region.id,
		stage = payload.stage,
		duration = duration,
		members = {
			{ userId = player.UserId, name = displayName(player), slot = slotIndex, power = host.powerOf(player, ids) },
		},
		expiresAt = ctx:Now() + Cfg.lobbySeconds,
	}
	lobbies()[id] = lobby
	squads[id] = { [userKey(player.UserId)] = table.clone(ids) }
	memberOf[player.UserId] = id
	publish(lobby)
	return { caravan = id }
end

function Caravans.Join(player, payload)
	requireOpen(player)
	local lobby = liveLobby(payload.caravan)
	local current = memberOf[player.UserId]
	if current == lobby.id then
		ctx:Fail("You're already in this caravan")
	elseif current then
		ctx:Fail("You're already in another caravan")
	end
	if #lobby.members >= Cfg.maxPlayers then
		ctx:Fail("That caravan is full")
	end
	if Caravans.IsReserved(player, payload.slot) then
		ctx:Fail("That slot is saved for your caravan")
	end
	local ok, why = checkMember(player, payload.slot, payload.squad)
	if not ok then
		ctx:Fail(why or "Your squad can't go")
	end
	table.insert(lobby.members, {
		userId = player.UserId,
		name = displayName(player),
		slot = payload.slot,
		power = host.powerOf(player, payload.squad),
	})
	squads[lobby.id][userKey(player.UserId)] = table.clone(payload.squad)
	memberOf[player.UserId] = lobby.id
	publish(lobby)
	local hostPlayer = ctx:PlayerByUserId(lobby.host)
	if hostPlayer then
		ctx:Notify(hostPlayer, displayName(player) .. " joined your caravan", "info")
	end
	return nil
end

function Caravans.Leave(player, payload)
	local lobby = lobbies()[payload.caravan]
	if not lobby or memberOf[player.UserId] ~= lobby.id then
		ctx:Fail("You're not in that caravan")
	end
	if lobby.host == player.UserId then
		close(lobby.id, "The host closed the caravan")
	else
		removeMember(lobby.id, player.UserId)
	end
	return nil
end

function Caravans.Launch(player, payload)
	local lobby = liveLobby(payload.caravan)
	if lobby.host ~= player.UserId then
		ctx:Fail("Only the host can launch the caravan")
	end
	if #lobby.members < Cfg.minPlayers then
		ctx:Fail(string.format("A caravan needs at least %d players", Cfg.minPlayers))
	end
	local id = lobby.id
	local roster = squads[id]

	-- The host must be ready; anyone else who isn't is dropped from the lobby.
	local ready = {}
	for _, m in table.clone(lobby.members) do
		local member = ctx:PlayerByUserId(m.userId)
		local ids = roster[userKey(m.userId)] or {}
		local ok, why
		if member then
			ok, why = checkMember(member, m.slot, ids)
		else
			ok, why = false, "left the server"
		end
		if m.userId == lobby.host then
			if not ok then
				ctx:Fail(why or "You can't launch right now")
			end
			table.insert(ready, { player = member, slot = m.slot, ids = ids })
		elseif ok then
			table.insert(ready, { player = member, slot = m.slot, ids = ids })
		else
			removeMember(id, m.userId)
			if member then
				ctx:Notify(member, string.format("You were dropped from the caravan: %s", tostring(why)), "error")
			end
		end
	end
	if #ready < Cfg.minPlayers then
		ctx:Fail("Not enough players are ready to launch")
	end

	local endsAt = 0
	for _, entry in ready do
		local e = host.startRun(entry.player, entry.slot, lobby.region, lobby.stage, lobby.duration, entry.ids, id)
		if entry.player == player then
			endsAt = e
		elseif entry.player then
			ctx:Notify(entry.player, "The caravan set off!", "success")
		end
	end
	-- Runs carry the caravan id now; the lobby itself is done.
	lobbies()[id] = nil
	squads[id] = nil
	ctx:DirtyGlobal("caravans", id)
	for _, entry in ready do
		memberOf[entry.player.UserId] = nil
		host.setSessionCaravan(entry.player, false)
	end
	return { endsAt = endsAt }
end

return Caravans
