--[[
	Titan (glow-up TT): scheduled, cross-server titan invasions on top of the Stampede (Boss).

	Schedule (Config.Titan.Schedule, fixed dates): each server computes the same window on its
	own clock, exactly like Boss's period does -
	  idle ──(LobbySeconds before start)──► lobby ──(startsAt)──► active ──► fallen | retreated ──► idle
	No messaging is needed for the schedule itself; only the fight's shared HP pool crosses
	servers (ctx.Services.Titan, a MemoryStore record keyed by the slot's startsAt).

	Every server fights its own local titan (same rules as Boss's damage: joined squad power,
	ticked every TickSeconds, boosted by Cheer), but the HP that empties is the SAME pool for
	every server: every ReportSeconds this server folds its damage into the shared record with
	one atomic Update (see Kernel/Adapters `Titan`), which also records how many players this
	server has fighting. If the pool is unreachable this server keeps fighting on a cached
	estimate (Logic.Reconcile) and retries the report next tick; nothing is lost. The titan
	falls everywhere once the pool reads empty, or retreats if the clock runs out first -
	whichever a server itself observes; every server reaches the same answer once it can reach
	the pool because the recorded hp is shared.

	Global (global.Titan):
	  { state = "idle"|"lobby"|"active"|"fallen"|"retreated", titanId, startsAt, endsAt,
	    hp, maxHp,            -- the SHARED pool (best known on this server)
	    servers, players,     -- servers/players fighting across the whole game (from the pool)
	    participants,         -- players joined on THIS server
	    poolOk,                -- false while the last report to the shared pool failed
	    board = { { userId, name, damage } } }  -- this server's top 10 by damage
	Session (session.Titan): { joined, damage, cheer }

	Actions:
	  Titan.Join   Ranch Level unlock (same as Boss), lobby or active, non-empty squad.
	  Titan.Cheer  { taps } fills the cheer meter (+CheerPerTap each, max 1), same token bucket
	               as Boss.Cheer.

	End: everyone who joined on this server and dealt damage or cheered gets the usual
	participation rewards; when the titan fell, everyone who dealt damage ("helped") also gets a
	guaranteed Titan Egg - never a rank or a chance roll (P5: earned by helping). Retreated:
	participation rewards only. Fires Titan.Result per participant, publishes TitanDamage per
	participant and then TitanEnded.

	Public API:
	  Titan:State() -> global.Titan table (read-only)
	  Titan:RegisterDamageModifier(key, fn(player) -> pct)
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local TitanLogic = require(Shared.Logic.Titan)

local Titan = {
	Name = "Titan",
	Dependencies = { "Progression", "Rewards", "Monsters", "Expeditions" },
	OptionalDependencies = { "Weather" },
}

local BOARD_SIZE = 10

local ctx
local Cfg
local Progression, Rewards, Monsters, Expeditions

local damageModifiers = {} -- [key] = fn(player) -> pct
local participants = {} -- array in join order
local byUser = {} -- [userId] = participant

local pendingDamage = 0 -- damage dealt on this server, not yet folded into the shared pool
local lastReportAt = 0
local poolKey: string? = nil -- tostring(startsAt) of the invasion currently open
local resolvedFor: string? = nil -- poolKey already finished, so tick() never finishes it twice
local sharedHp, sharedMaxHp = 0, 0
local sharedServers = {}

-- Schedule --------------------------------------------------------------------------------

local function global()
	return ctx:Global()
end

local function setSession(player, joined: boolean, damage: number, cheer: number)
	local session = ctx:Session(player)
	if not session then
		return
	end
	session.joined = joined
	session.damage = math.floor(damage)
	session.cheer = cheer
	ctx:DirtySession(player)
end

local function currentEntry(now: number)
	return TitanLogic.Window(Cfg.Schedule, Cfg.Duration, Cfg.LobbySeconds, now)
end

local function titanDef(rotation: number)
	return Cfg.Rotation[rotation] or Cfg.Rotation[1]
end

local function poolKeyFor(startsAt: number): string
	return tostring(startsAt)
end

local function refreshBoard()
	local ranked = table.clone(participants)
	table.sort(ranked, function(a, b)
		if a.damage ~= b.damage then
			return a.damage > b.damage
		end
		return a.userId < b.userId
	end)
	local board = {}
	for i = 1, math.min(BOARD_SIZE, #ranked) do
		local p = ranked[i]
		board[i] = { userId = p.userId, name = p.name, damage = math.floor(p.damage) }
	end
	local G = global()
	G.board = board
	G.participants = #participants
	return ranked
end

-- Keeps startsAt/endsAt/titanId previewing the NEXT invasion (for the "coming soon" banner)
-- without touching state: "fallen"/"retreated" is a rest state that sticks around like Boss's
-- stale hp/board, until the next lobby actually opens (see openLobby's guard).
local function refreshPreview(now: number)
	local G = global()
	if G.state == nil then
		G.state = "idle"
	end
	local nextAt = TitanLogic.NextStart(Cfg.Schedule, now)
	G.startsAt = nextAt
	G.endsAt = nil
	G.titanId = nil
	if nextAt then
		for _, entry in Cfg.Schedule do
			if entry.startsAt == nextAt then
				G.titanId = titanDef(entry.rotation).id
				G.endsAt = nextAt + Cfg.Duration
				break
			end
		end
	end
	G.hp = G.hp or 0
	G.maxHp = G.maxHp or 0
	G.participants = 0
	G.servers = G.servers or 0
	G.players = G.players or 0
	G.board = G.board or {}
	G.poolOk = if G.poolOk == nil then true else G.poolOk
	ctx:DirtyGlobal()
end

-- Damage ------------------------------------------------------------------------------------

local function weatherMult(): number
	local Weather = ctx:GetSystem("Weather")
	if not Weather or not Weather.Current then
		return 1
	end
	local ok, current = pcall(Weather.Current, Weather)
	if not ok or type(current) ~= "table" then
		return 1
	end
	local def = ctx.Config.Weather.ById[current.id]
	return def and def.effects and def.effects.bossDamage or 1
end

local function modifierPct(player): number
	local total = 0
	for key, fn in damageModifiers do
		local ok, value = pcall(fn, player)
		if ok and type(value) == "number" and value == value then
			total += value
		elseif not ok then
			warn(string.format("[Titan] damage modifier %s failed: %s", key, tostring(value)))
		end
	end
	return total
end

local function brawlerPct(player, ids: { string }): number
	local weighted, total = 0, 0
	for _, id in ids do
		local m = Monsters:Get(player, id)
		if m then
			local power = Formulas.MonsterPower(m)
			total += power
			weighted += power * ctx.Config.Traits.Sum(Formulas.ActiveTraits(m), "bossDmgPct")
		end
	end
	return if total > 0 then weighted / total else 0
end

-- The shared pool: fold this server's damage in (atomic), and read back the truth.
-- The adapter yields (MemoryStore), so the call runs in its own thread: the kernel's scheduler
-- calls every system's timer inline, and a timer that waits on the network would hold up the
-- others and be run again every frame until it returned (its next due time is set only after).
-- Guarded against overlap: a slow call must not race the next tick's report (which would
-- double-send pendingDamage or read a stale sharedHp back); a report asked for meanwhile by
-- finish() runs as soon as the one in flight lands.
local reporting = false
local flushWhenDone = false
local report
report = function(now: number)
	if reporting then
		return
	end
	lastReportAt = now
	local G = global()
	local svc = ctx.Services.Titan
	if not svc or not poolKey then
		G.poolOk = false
		return
	end
	reporting = true
	local key = poolKey
	local startHp = sharedMaxHp
	local myJobId = tostring(ctx.Services.JobId)
	local myPlayers = #participants
	local damageToSend = pendingDamage
	ctx.Services.Spawn(function()
		local called, ok, result = pcall(svc.Update, key, function(current)
			local record = current
			if type(record) ~= "table" then
				record = { hp = startHp, servers = {} }
			end
			record.servers = TitanLogic.PruneServers(record.servers, now, Cfg.StaleServerSeconds, Cfg.MaxServersListed)
			record.servers[myJobId] = { players = myPlayers, at = now }
			record.hp = math.max(0, (tonumber(record.hp) or startHp) - damageToSend)
			return record
		end)
		reporting = false
		if key ~= poolKey then
			return -- the next invasion opened while this report was in flight
		end
		local live = G.state == "lobby" or G.state == "active"
		if called and ok and type(result) == "table" then
			pendingDamage -= damageToSend
			sharedHp = tonumber(result.hp) or sharedHp
			sharedServers = result.servers or {}
			G.poolOk = true
		else
			G.poolOk = false
		end
		if live then
			local serverCount, playerCount = TitanLogic.Totals(sharedServers)
			G.servers = serverCount
			G.players = playerCount
			G.hp = math.floor(TitanLogic.Reconcile(sharedHp, pendingDamage))
			ctx:DirtyGlobal()
		end
		if flushWhenDone then
			flushWhenDone = false
			if pendingDamage > 0 then
				report(ctx:Now())
			end
		end
	end)
end

local function openLobby(entry)
	local G = global()
	table.clear(participants)
	table.clear(byUser)
	pendingDamage = 0
	lastReportAt = ctx:Now()
	poolKey = poolKeyFor(entry.startsAt)
	resolvedFor = nil
	local def = titanDef(entry.rotation)
	sharedHp, sharedMaxHp = def.maxHp, def.maxHp
	G.state = "lobby"
	G.titanId = def.id
	G.startsAt = entry.startsAt
	G.endsAt = entry.startsAt + Cfg.Duration
	G.hp = def.maxHp
	G.maxHp = def.maxHp
	G.participants = 0
	G.servers = 0
	G.players = 0
	G.board = {}
	G.poolOk = true
	ctx:DirtyGlobal()
	ctx.Net:FireAll("Titan.Starting", { titanId = G.titanId, startsAt = G.startsAt })
end

local function activate(now: number)
	local G = global()
	G.state = "active"
	ctx:DirtyGlobal()
	report(now) -- a server starting mid-fight should show the real pool at once, not a full bar
	ctx.Net:FireAll("Titan.Started", { titanId = G.titanId, startsAt = G.startsAt, endsAt = G.endsAt })
end

local function finish(now: number, outcome: string)
	if resolvedFor == poolKey then
		return
	end
	resolvedFor = poolKey
	-- The last sliver of damage still counts (after the report in flight, if there is one).
	if reporting then
		flushWhenDone = true
	else
		report(now)
	end
	local G = global()
	local won = outcome == "fallen"
	local ranked = refreshBoard()
	local rules = Cfg.Rewards
	for _, p in ranked do
		local player = p.player
		if player and ctx:IsReady(player) then
			-- Dealing damage or cheering earns the participation rewards either way; the Titan
			-- Egg needs damage and a fallen titan.
			local dealt = TitanLogic.Helped(p.damage, rules.minDamageToHelp)
			local helped = won and dealt
			local eligible = dealt or p.cheered
			local items = {}
			local egg = false
			if eligible then
				for _, item in rules.participation do
					table.insert(items, table.clone(item))
				end
				if helped then
					egg = true
					table.insert(items, { kind = "egg", id = rules.egg, amount = 1 })
				end
			end
			local granted = if #items > 0 then Rewards:Grant(player, items, "titan", { silent = true }) else {}
			ctx.Net:Fire(player, "Titan.Result", {
				won = won,
				damage = math.floor(p.damage),
				rewards = granted,
				egg = egg,
			})
			ctx.Analytics.Custom(player, "titan_reward", if egg then 1 else 0, { titan = G.titanId, won = tostring(won) })
			ctx.Bus:Publish("TitanDamage", player, { damage = math.floor(p.damage), won = won })
			setSession(player, false, p.damage, 0)
		end
	end
	G.state = if won then "fallen" else "retreated"
	ctx:DirtyGlobal()
	ctx.Bus:Publish("TitanEnded", nil, { titanId = G.titanId, won = won })
	table.clear(participants)
	table.clear(byUser)
	refreshPreview(now)
end

local function tick()
	local now = ctx:Now()
	local G = global()
	local entry = currentEntry(now)
	if not entry then
		if G.state == "lobby" or G.state == "active" then
			finish(now, "retreated")
		elseif G.startsAt == nil or now >= G.startsAt then
			refreshPreview(now)
		end
		return
	end
	-- fallen/retreated is a rest state (see refreshPreview) that also needs a fresh lobby once
	-- its schedule slot rolls around again, so anything but a matching lobby/active reopens one.
	if (G.state ~= "lobby" and G.state ~= "active") or G.startsAt ~= entry.startsAt then
		openLobby(entry)
	end
	if G.state == "lobby" and now >= entry.startsAt then
		activate(now)
	end
	if G.state ~= "active" then
		return
	end

	local weather = weatherMult()
	local dt = Cfg.TickSeconds
	for _, p in participants do
		local player = p.player
		if player and ctx:IsReady(player) then
			local bonus = p.cheer * Cfg.CheerMaxBonus + p.brawler + modifierPct(player)
			local damage = p.power * Cfg.DamagePerPowerPerSecond * dt * math.max(0, 1 + bonus) * weather
			p.damage += damage
			pendingDamage += damage
			p.cheer = math.max(0, p.cheer - Cfg.CheerDecayPerSecond * dt)
			setSession(player, true, p.damage, p.cheer)
		end
	end
	G.hp = math.floor(TitanLogic.Reconcile(sharedHp, pendingDamage))
	refreshBoard()
	ctx:DirtyGlobal()

	if TitanLogic.ShouldReport(lastReportAt, now, Cfg.ReportSeconds) then
		report(now)
	end

	local outcome = TitanLogic.Outcome(global().hp, now, G.endsAt)
	if outcome ~= "active" then
		finish(now, outcome)
	end
end

-- Public API ----------------------------------------------------------------------------------

function Titan:State()
	return global()
end

function Titan:RegisterDamageModifier(key: string, fn)
	damageModifiers[key] = fn
end

-- Lifecycle -----------------------------------------------------------------------------------

function Titan.Init(context)
	ctx = context
	Cfg = ctx.Config.Titan
	damageModifiers = {}
	participants = {}
	byUser = {}
	pendingDamage = 0
	lastReportAt = 0
	poolKey = nil
	resolvedFor = nil
	sharedHp, sharedMaxHp = 0, 0
	sharedServers = {}
	reporting, flushWhenDone = false, false
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")
	Monsters = ctx:GetSystem("Monsters")
	Expeditions = ctx:GetSystem("Expeditions")

	local now = ctx:Now()
	local entry = currentEntry(now)
	if entry then
		openLobby(entry)
		if now >= entry.startsAt then
			activate(now)
		end
	else
		refreshPreview(now)
	end

	ctx.Net:Handle("Titan.Join", function(player)
		Progression:Require(player, Cfg.Unlock)
		local G = global()
		if G.state ~= "lobby" and G.state ~= "active" then
			ctx:Fail("No titan is here yet")
		end
		if byUser[player.UserId] then
			ctx:Fail("You're already fighting the titan")
		end
		local ids = Expeditions:GetSquad(player)
		if #ids == 0 then
			ctx:Fail("Pick a squad first")
		end
		local power = Expeditions:SquadPower(player)
		if power <= 0 then
			ctx:Fail("Pick a squad first")
		end
		local entryRow = {
			userId = player.UserId,
			name = player.DisplayName or player.Name,
			player = player,
			power = power,
			brawler = brawlerPct(player, ids),
			damage = 0,
			cheer = 0,
			cheered = false,
			taps = Cfg.MaxTapsPerSecond or 15,
			tapsAt = ctx.Clock.Precise(),
		}
		table.insert(participants, entryRow)
		byUser[player.UserId] = entryRow
		refreshBoard()
		ctx:DirtyGlobal()
		setSession(player, true, 0, 0)
		ctx.Bus:Publish("TitanJoined", player, {})
		ctx.Bus:Publish("RanchXP", player, { amount = ctx.Config.Unlocks.XP.bossJoin, reason = "titan" })
		ctx.Analytics.Custom(player, "titan_join", power, { titan = G.titanId })
		return nil
	end)

	ctx.Net:Handle("Titan.Cheer", function(player, payload)
		local entryRow = byUser[player.UserId]
		if not entryRow then
			ctx:Fail("Join the titan fight first")
		end
		if global().state ~= "active" then
			ctx:Fail("The titan hasn't started yet")
		end
		local perSecond = Cfg.MaxTapsPerSecond or 15
		local now = ctx.Clock.Precise()
		entryRow.taps = math.min(perSecond, entryRow.taps + (now - entryRow.tapsAt) * perSecond)
		entryRow.tapsAt = now
		local accepted = math.min(payload.taps, math.floor(entryRow.taps))
		if accepted > 0 then
			entryRow.taps -= accepted
			entryRow.cheered = true
			entryRow.cheer = math.min(1, entryRow.cheer + accepted * Cfg.CheerPerTap)
			setSession(player, true, entryRow.damage, entryRow.cheer)
		end
		return { cheer = entryRow.cheer }
	end)

	ctx:Every(Cfg.TickSeconds, tick)
end

function Titan.PlayerAdded(player)
	local entry = byUser[player.UserId]
	if entry then
		entry.player = player
		setSession(player, true, entry.damage, entry.cheer)
	else
		setSession(player, false, 0, 0)
	end
end

function Titan.PlayerRemoving(player)
	local entry = byUser[player.UserId]
	if entry and entry.player == player then
		entry.player = nil
	end
end

return Titan
