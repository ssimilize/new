--[[
	Editions (glow-up W): numbered limited editions of event monsters (Config.Editions,
	Logic/Editions).

	No save section of its own: the state lives on the monster record (Monsters owns it):
	  ltd   = edition id    set when the monster is created by a minting source (hatch, reward)
	  ltdOf = edition size  set with ltd
	  ltdNo = its number    1..ltdOf, unique across every server; nil while it is pending
	A traded or listed monster keeps all three (Monsters:Insert copies the record), so the number
	travels with it; it is never minted again on arrival.

	Minting: MonsterCreated (sources in Config.Editions.Sources) marks the record, then a spawned
	task claims the next number from the edition's atomic counter:
	  ctx.Services.Editions.Claim(editionId, size) -> ok, n?      (preferred; see ARCHITECTURE.md)
	  else ctx.Services.DataStore:Update("Edition_" .. id, Logic.Claim)  (the profile store)
	Each pass tries Config.Editions.Attempts times. A store that is down leaves the monster granted
	and pending: it is tried again every Config.Editions.RetrySeconds while its owner is on this
	server and on every join, on any server, so a monster is never lost and never numbered twice.
	A claim whose outcome is unknown can burn a number (a gap), never duplicate one.
	Full edition: the claim returns no number, the record's ltd / ltdOf are cleared and the monster
	stays as an ordinary one (the line stops being limited). This server then skips that edition.

	Public API:
	  Editions:NumberPending(player) -> number   numbers every pending monster now; returns how many
	                                             are still pending
	  Editions:Pending(player) -> number         pending monsters of that player
	Subscribes MonsterCreated. No actions, events, state roots or bus topics of its own.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Editions)

local Editions = {
	Name = "Editions",
	Dependencies = { "Monsters" },
}

local ctx
local Cfg
local Monsters

local inFlight = {} -- [player] = { [monsterId] = true } claims running now
local soldOut = {} -- [editionId] = true once a claim on this server found it full

-- The profile is loaded (also true inside PlayerAdded, before the kernel marks the player ready).
local function loaded(player): boolean
	return ctx:Meta(player) ~= nil
end

-- One claim against the store. Returns (ok, n?): ok false = store failed (try later); ok true
-- with n nil = the edition is full.
local function claim(edition): (boolean, number?)
	local services = ctx.Services
	local adapter = services.Editions
	if type(adapter) == "table" and adapter.Claim then
		local ok, n = adapter.Claim(edition.id, edition.size)
		return ok == true, if ok == true and type(n) == "number" then n else nil
	end
	local store = services.DataStore
	if not (store and store.Update) then
		return false, nil
	end
	local minted = nil
	local ok = store:Update("Edition_" .. edition.id, function(current)
		local count, n = Logic.Claim(current, edition.size)
		minted = n
		return count
	end)
	return ok == true, minted
end

local function claimWithRetry(edition): (boolean, number?)
	for attempt = 1, Cfg.Attempts do
		local ok, n = claim(edition)
		if ok then
			return true, n
		end
		if attempt < Cfg.Attempts and ctx.Services.Wait then
			ctx.Services.Wait(attempt)
		end
	end
	return false, nil
end

local function numberOne(player, id: string)
	local m = Monsters:Get(player, id)
	local edition = m and Logic.Pending(m) and Cfg.ById[m.ltd]
	if not m then
		return
	end
	if not edition then
		if Logic.Pending(m) then -- an edition that no longer exists: an ordinary monster
			m.ltd, m.ltdOf = nil, nil
			Monsters:Changed(player, id, { "ltd" })
		end
		return
	end
	local ok, n = true, nil
	if not soldOut[edition.id] then
		ok, n = claimWithRetry(edition)
	end
	if not ok then
		return -- still pending; tried again later
	end
	if not loaded(player) or Monsters:Get(player, id) ~= m then
		return -- left or traded away while the claim ran: the number is a gap, the copy stays pending
	end
	if n then
		m.ltdNo = n
		m.ltdOf = m.ltdOf or edition.size
	else
		soldOut[edition.id] = true
		m.ltd, m.ltdOf = nil, nil
	end
	Monsters:Changed(player, id, { "ltd" })
end

local function pendingIds(player): { string }
	local ids = {}
	for id, m in Monsters:All(player) or {} do
		if Logic.Pending(m) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

function Editions:Pending(player): number
	return #pendingIds(player)
end

function Editions:NumberPending(player): number
	if not loaded(player) then
		return 0
	end
	local running = inFlight[player]
	if not running then
		running = {}
		inFlight[player] = running
	end
	for _, id in pendingIds(player) do
		if not running[id] then
			running[id] = true
			local ok, err = pcall(numberOne, player, id)
			running[id] = nil
			if not ok then
				warn("[Editions] numbering failed: " .. tostring(err))
			end
		end
	end
	return if loaded(player) then #pendingIds(player) else 0
end

local function spawnNumbering(player)
	ctx.Services.Spawn(function()
		Editions:NumberPending(player)
	end)
end

function Editions.Init(context)
	ctx = context
	Cfg = ctx.Config.Editions
	Monsters = ctx:GetSystem("Monsters")
	table.clear(inFlight)
	table.clear(soldOut)

	ctx.Bus:Subscribe("MonsterCreated", function(player, detail)
		local m = detail and Monsters:Get(player, detail.id)
		local edition = Logic.For(m, detail and detail.source)
		if not edition or soldOut[edition.id] then
			return
		end
		m.ltd, m.ltdOf = edition.id, edition.size
		Monsters:Changed(player, detail.id, { "ltd" })
		spawnNumbering(player)
	end)

	ctx:Every(Cfg.RetrySeconds, function()
		for _, player in ctx:Players() do
			if loaded(player) and #pendingIds(player) > 0 then
				spawnNumbering(player)
			end
		end
	end)
end

function Editions.PlayerAdded(player, _info)
	if #pendingIds(player) > 0 then
		spawnNumbering(player)
	end
end

function Editions.PlayerRemoving(player)
	inFlight[player] = nil
end

return Editions
