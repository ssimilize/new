--[[
	Boss (S4): the Stampede, a server-wide boss every Config.Boss.Period seconds.

	Schedule (aligned to the clock, so every server fights at :00 and :30):
	  idle ──(LobbySeconds before start)──► lobby ──(startsAt)──► active ──(endsAt or HP 0)──► idle
	  next start = ceil(now / Period) × Period; boss = Rotation[(startsAt / Period) % #Rotation + 1]

	Global (global.Boss):
	  { state = "idle"|"lobby"|"active", bossId, startsAt, endsAt, hp, maxHp, participants,
	    board = { { userId, name, damage } },          -- board: top 10 by damage
	    squads = { { userId, looks = { { line, form, stage, rarity, variant } } } } }
	  squads (glow-up U): what each joined squad looks like, for the arena drawn in the world
	  (Controllers/StampedeArena); in join order, at most Arena.squadPlayers players and
	  Arena.squadPerPlayer looks each. Render-only (no monster ids); cleared when a lobby opens.
	  While idle, startsAt/endsAt/bossId describe the NEXT fight; hp/maxHp/board keep the
	  last fight's result until the next lobby opens.
	Session (session.Boss): { joined, damage, cheer }   -- cheer 0..1

	Actions:
	  Boss.Join   Ranch Level unlock, lobby or active, non-empty default squad. The squad's
	              power is locked in at join time. Late joiners add their share of HP.
	  Boss.Cheer  { taps } fills the cheer meter (+CheerPerTap each, max 1). Taps beyond
	              MaxTapsPerSecond are ignored. The meter decays every tick.

	Every tick (TickSeconds) each participant deals
	  power × DamagePerPowerPerSecond × (1 + cheer × CheerMaxBonus + modifiers + Boss Brawler)
	  × weather (Config.Weather effects.bossDamage, e.g. Thunderstorm 1.1)
	Boss Brawler is weighted by each squad member's share of the squad's power.
	Max HP = Σ squad power × Duration × HpPerSquadPower × 0.8.

	Announcements (to every player on the server, joined or not):
	  Boss.Starting { bossId, startsAt }          when the lobby opens (LobbySeconds before the start)
	  Boss.Started  { bossId, startsAt, endsAt }  the horn, when the fight goes live

	End: everyone who joined and is still on the server gets the participation chest (players
	below minDamageShare only if they cheered). The top 3 by damage get a Stampede Egg; others
	with ≥ shareForEggChance of the damage have an eggChance roll. Fires Boss.Result per
	participant, publishes BossDamage per participant and then BossEnded.

	Public API:
	  Boss:State() -> global.Boss table (read-only)
	  Boss:RegisterDamageModifier(key, fn(player) -> pct)
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)

local Boss = {
	Name = "Boss",
	Dependencies = { "Progression", "Rewards", "Monsters", "Expeditions" },
	OptionalDependencies = { "Weather" },
}

local BOARD_SIZE = 10
local HP_FACTOR = 0.8

local ctx
local Cfg
local Progression, Rewards, Monsters, Expeditions

local damageModifiers = {} -- [key] = fn(player) -> pct
local participants = {} -- array in join order
local byUser = {} -- [userId] = participant

-- Schedule --------------------------------------------------------------------------------

local function nextStart(now: number): number
	return math.ceil(now / Cfg.Period) * Cfg.Period
end

local function bossFor(startsAt: number)
	local slot = math.floor(startsAt / Cfg.Period)
	return Cfg.Rotation[(slot % #Cfg.Rotation) + 1]
end

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

local function scheduleNext(now: number)
	local G = global()
	local startsAt = nextStart(now)
	G.state = "idle"
	G.startsAt = startsAt
	G.endsAt = startsAt + Cfg.Duration
	G.bossId = bossFor(startsAt).id
	G.hp = G.hp or 0
	G.maxHp = G.maxHp or 0
	G.participants = G.participants or 0
	G.board = G.board or {}
	G.squads = G.squads or {}
	ctx:DirtyGlobal()
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

local function openLobby()
	local G = global()
	table.clear(participants)
	table.clear(byUser)
	G.state = "lobby"
	G.hp = 0
	G.maxHp = 0
	G.participants = 0
	G.board = {}
	G.squads = {}
	ctx:DirtyGlobal()
	for _, player in ctx:Players() do
		setSession(player, false, 0, 0)
	end
	ctx.Net:FireAll("Boss.Starting", { bossId = G.bossId, startsAt = G.startsAt })
end

local function hpShare(power: number, seconds: number): number
	return power * seconds * Cfg.HpPerSquadPower * HP_FACTOR
end

local function activate()
	local G = global()
	local total = 0
	for _, p in participants do
		total += p.power
	end
	G.state = "active"
	G.maxHp = math.floor(hpShare(total, Cfg.Duration))
	G.hp = G.maxHp
	ctx:DirtyGlobal()
	ctx.Net:FireAll("Boss.Started", { bossId = G.bossId, startsAt = G.startsAt, endsAt = G.endsAt })
end

-- Glow-up U: the squad's looks for the arena in the world, capped (render-only, no ids).
local function addSquadLooks(player, ids: { string })
	local arena = Cfg.Arena
	local G = global()
	if not arena or #G.squads >= arena.squadPlayers then
		return
	end
	local looks = {}
	for _, id in ids do
		local m = Monsters:Get(player, id)
		if m and #looks < arena.squadPerPlayer then
			table.insert(looks, { line = m.line, form = m.form, stage = m.stage, rarity = m.rarity, variant = m.variant or 0 })
		end
	end
	if #looks > 0 then
		table.insert(G.squads, { userId = player.UserId, looks = looks })
	end
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
			warn(string.format("[Boss] damage modifier %s failed: %s", key, tostring(value)))
		end
	end
	return total
end

-- Boss Brawler bonus of a squad, weighted by each member's share of the squad's power.
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

local function finish(now: number)
	local G = global()
	local won = #participants > 0 and G.hp <= 0
	local ranked = refreshBoard()
	local totalDamage = 0
	for _, p in ranked do
		totalDamage += p.damage
	end
	local rules = Cfg.Rewards
	for rank, p in ranked do
		local player = p.player
		if player and ctx:IsReady(player) then
			local share = if totalDamage > 0 then p.damage / totalDamage else 0
			local eligible = share >= rules.minDamageShare or p.cheered
			local items = {}
			local egg = false
			if eligible then
				for _, item in rules.participation do
					table.insert(items, table.clone(item))
				end
				egg = rank <= rules.topGuaranteed or (share >= rules.shareForEggChance and ctx.Rng:Chance(rules.eggChance))
				if egg then
					table.insert(items, { kind = "egg", id = rules.egg, amount = 1 })
				end
			end
			local granted = if #items > 0 then Rewards:Grant(player, items, "boss", { silent = true }) else {}
			local gotEgg = false
			for _, item in granted do
				if item.kind == "egg" then
					gotEgg = true
				end
			end
			ctx.Net:Fire(player, "Boss.Result", {
				rank = rank,
				share = share,
				damage = math.floor(p.damage),
				rewards = granted,
				egg = gotEgg,
			})
			ctx.Analytics.Custom(player, "boss_reward", rank, { boss = G.bossId, egg = tostring(gotEgg) })
			ctx.Bus:Publish("BossDamage", player, { damage = math.floor(p.damage), rank = rank })
			setSession(player, false, p.damage, 0)
		end
	end
	ctx.Bus:Publish("BossEnded", nil, { bossId = G.bossId, won = won })
	table.clear(participants)
	table.clear(byUser)
	scheduleNext(now)
end

local function tick()
	local now = ctx:Now()
	local G = global()
	if G.state == "idle" and now >= G.startsAt - Cfg.LobbySeconds then
		openLobby()
	end
	if G.state == "lobby" and now >= G.startsAt then
		activate()
	end
	if G.state ~= "active" then
		return
	end
	if now >= G.endsAt then
		finish(now)
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
			G.hp = math.max(0, G.hp - damage)
			p.cheer = math.max(0, p.cheer - Cfg.CheerDecayPerSecond * dt)
			setSession(player, true, p.damage, p.cheer)
		end
	end
	G.hp = math.floor(G.hp)
	refreshBoard()
	ctx:DirtyGlobal()
	if G.hp <= 0 and #participants > 0 then
		finish(now)
	end
end

-- Public API ----------------------------------------------------------------------------------

function Boss:State()
	return global()
end

function Boss:RegisterDamageModifier(key: string, fn)
	damageModifiers[key] = fn
end

-- Lifecycle -----------------------------------------------------------------------------------

function Boss.Init(context)
	ctx = context
	Cfg = ctx.Config.Boss
	-- Module state is reset per kernel; modifiers register in Start(), after every Init.
	damageModifiers = {}
	participants = {}
	byUser = {}
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")
	Monsters = ctx:GetSystem("Monsters")
	Expeditions = ctx:GetSystem("Expeditions")

	scheduleNext(ctx:Now())

	ctx.Net:Handle("Boss.Join", function(player)
		Progression:Require(player, Cfg.Unlock)
		local G = global()
		if G.state ~= "lobby" and G.state ~= "active" then
			ctx:Fail("The Stampede isn't here yet")
		end
		if byUser[player.UserId] then
			ctx:Fail("You're already in the Stampede")
		end
		local ids = Expeditions:GetSquad(player)
		if #ids == 0 then
			ctx:Fail("Pick a squad first")
		end
		local power = Expeditions:SquadPower(player)
		if power <= 0 then
			ctx:Fail("Pick a squad first")
		end
		local entry = {
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
		table.insert(participants, entry)
		byUser[player.UserId] = entry
		addSquadLooks(player, ids)
		if G.state == "active" then
			local share = math.floor(hpShare(power, math.max(0, G.endsAt - ctx:Now())))
			G.maxHp += share
			G.hp += share
		end
		refreshBoard()
		ctx:DirtyGlobal()
		setSession(player, true, 0, 0)
		ctx.Bus:Publish("BossJoined", player, {})
		ctx.Bus:Publish("RanchXP", player, { amount = ctx.Config.Unlocks.XP.bossJoin, reason = "boss" })
		ctx.Analytics.Custom(player, "boss_join", power, { boss = G.bossId })
		return nil
	end)

	ctx.Net:Handle("Boss.Cheer", function(player, payload)
		local entry = byUser[player.UserId]
		if not entry then
			ctx:Fail("Join the Stampede first")
		end
		if global().state ~= "active" then
			ctx:Fail("The Stampede hasn't started yet")
		end
		-- Token bucket: at most MaxTapsPerSecond taps count, however fast requests arrive.
		local perSecond = Cfg.MaxTapsPerSecond or 15
		local now = ctx.Clock.Precise()
		entry.taps = math.min(perSecond, entry.taps + (now - entry.tapsAt) * perSecond)
		entry.tapsAt = now
		local accepted = math.min(payload.taps, math.floor(entry.taps))
		if accepted > 0 then
			entry.taps -= accepted
			entry.cheered = true
			entry.cheer = math.min(1, entry.cheer + accepted * Cfg.CheerPerTap)
			setSession(player, true, entry.damage, entry.cheer)
		end
		return { cheer = entry.cheer }
	end)

	ctx:Every(Cfg.TickSeconds, tick)
end

function Boss.PlayerAdded(player)
	-- Rejoining mid-fight picks the player's place back up.
	local entry = byUser[player.UserId]
	if entry then
		entry.player = player
		setSession(player, true, entry.damage, entry.cheer)
	else
		setSession(player, false, 0, 0)
	end
end

function Boss.PlayerRemoving(player)
	local entry = byUser[player.UserId]
	if entry and entry.player == player then
		-- Damage stays on the board; ticks and rewards need the player on the server.
		entry.player = nil
	end
end

return Boss
