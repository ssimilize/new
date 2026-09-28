--[[
	Spa (update 3.13 · Wild things): the Hot Springs on the ranch's west strip (the client builds
	them, Controllers/Spa, and its "Soak" prompt opens the Spa screen). Each open pool holds one
	Teen or Adult from the barn (busy tag "spa") for its soak's time on the server clock, online
	and offline. When the time is up the player collects it (nothing is applied until then): the
	monster is freed and carries the soak's buff for Config.Spa.BuffHours from the collect.
	Config.Spa, Logic/Spa.

	Save section (profile.Spa), version 1:
	  pools  = { [1..MaxPools] = { monster = id|false, soak = id|false, at, endsAt } }  -- Logic/Spa
	  buffs  = { [monsterId] = { soak, from, endsAt } }   one per monster; expired ones are pruned
	  soaks  = number                                     soaks collected, ever
	Session (session.Spa): { pools, apiary }   open pools; the Apiary is plugged in (salts need honey)

	Actions:
	  Spa.Soak { pool, id, soak }   an open, empty pool, a free Teen/Adult in the barn; pays the bath
	                                salt (honey via Apiary:SpendAnyHoney + food) -> { endsAt }
	  Spa.Collect { pool }          a finished soak: frees the monster, starts its buff (herbal: Mood
	                                to the max + bond points now) -> { soak, endsAt }
	  Spa.Cancel { pool }           ends a soak early: the monster is freed, the salt is lost

	Public API:
	  Spa:Buff(player, monsterId) -> { soak, endsAt }?   the monster's buff while it lasts
	  Spa:PoolCount(player) -> number

	Buffs reach their consumers through registries set up in Start (all optional):
	  warm     Monsters:RegisterMealModifier("spa")   × (1 + growthPct) growth meals
	  mineral  Jobs:RegisterOutputBoost("spa")        + outputPct over the buff's window
	           Apiary:RegisterRateBoost("spa")        + outputPct honey over the buff's window
	  herbal   Monsters:AddMood (to max) and Bond:AddPoints on collect
	Optional: Apiary (salts; without it no soak is offered), Bond, Jobs.
	Bus: publishes SpaSoaked (player, { monsterId, soak }) on collect; WelcomeItem when soaks
	finished while the player was away.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local Logic = require(Shared.Logic.Spa)

local Spa = {
	Name = "Spa",
	Dependencies = { "Currency", "Progression", "Monsters" },
	OptionalDependencies = { "Apiary", "Bond", "Jobs" },
}

local BUSY_TAG = "spa"
local HOUR = 3600

local ctx
local Config, Rules
local Currency, Progression, Monsters
local Apiary, Bond

local notified = {} -- [player] = { [pool] = true } finished soaks already toasted

Spa.Profile = {
	Version = 1,
	Default = function()
		local pools = {}
		for i = 1, Config.Spa.MaxPools do
			pools[i] = Logic.EmptyPool()
		end
		return { pools = pools, buffs = {}, soaks = 0 }
	end,
}

-- Helpers ------------------------------------------------------------------------------

local function section(player)
	return ctx:Section(player)
end

local function isUnlocked(player)
	return function(key: string): boolean
		return Progression:IsUnlocked(player, key)
	end
end

local function hasApiary(): boolean
	return Apiary ~= nil and Apiary.SpendAnyHoney ~= nil and Apiary.HoneyCount ~= nil
end

local function refreshSession(player)
	local sess = ctx:Session(player)
	if not sess or not section(player) then
		return
	end
	local count = Logic.PoolCount(isUnlocked(player))
	local apiary = hasApiary()
	if sess.pools ~= count or sess.apiary ~= apiary then
		sess.pools = count
		sess.apiary = apiary
		ctx:DirtySession(player)
	end
end

local function mustPool(player, index: number)
	local pool = section(player).pools[index]
	if not pool then
		ctx:Fail("That pool doesn't exist")
	end
	return pool
end

local function free(player, index: number)
	local pool = section(player).pools[index]
	local id = pool.monster
	local m = id and Monsters:Get(player, id)
	if m and m.busy == BUSY_TAG then
		Monsters:SetBusy(player, id, false)
	end
	section(player).pools[index] = Logic.EmptyPool()
	ctx:Dirty(player, "pools")
	if notified[player] then
		notified[player][index] = nil
	end
end

local function pruneBuffs(player)
	local s = section(player)
	local now = ctx:Now()
	for id, buff in s.buffs do
		if not Logic.Active(buff, now) or not Monsters:Get(player, id) then
			s.buffs[id] = nil
			ctx:Dirty(player, "buffs")
		end
	end
end

local function buffOf(player, id)
	local s = section(player)
	return s and type(id) == "string" and Logic.Active(s.buffs[id], ctx:Now()) or nil
end

-- Public API ------------------------------------------------------------------------------

function Spa:PoolCount(player): number
	return Logic.PoolCount(isUnlocked(player))
end

function Spa:Buff(player, monsterId: string)
	local b = buffOf(player, monsterId)
	return if b then { soak = b.soak, endsAt = b.endsAt } else nil
end

-- Actions ---------------------------------------------------------------------------------

local function soak(player, payload)
	Progression:Require(player, Rules.Unlock)
	local index = payload.pool
	if index > Spa:PoolCount(player) then
		ctx:Fail(string.format("Spa pool %d opens at Ranch Level %d", index, Progression:UnlockLevel(Rules.PoolUnlocks[index])))
	end
	local pool = mustPool(player, index)
	if pool.monster then
		ctx:Fail("Someone is already soaking in this pool")
	end
	if not hasApiary() then
		ctx:Fail("Bath salts need honey from the Apiary")
	end
	local m, why = Monsters:Available(player, payload.id)
	if not m then
		ctx:Fail(why or "That monster doesn't exist")
	end
	local ok, reason = Logic.CanTake(m, payload.soak)
	if not ok then
		ctx:Fail(reason or "That monster can't soak")
	end
	if m.loc == "pen" then
		ctx:Fail(string.format("%s works in a pen. Move it to the barn first", Formulas.DisplayName(m)))
	end
	local cost = Logic.Cost(payload.soak)
	if Apiary:HoneyCount(player) < cost.honey then
		ctx:Fail(string.format("A bath salt needs %d honey", cost.honey))
	end
	local food = {}
	for flavour, n in cost.food do
		food["food." .. flavour] = n
	end
	local afford, missing = Currency:CanAfford(player, food)
	if not afford then
		ctx:Fail(Currency:MissingText(missing :: string))
	end
	if not Apiary:SpendAnyHoney(player, cost.honey) then
		ctx:Fail(string.format("A bath salt needs %d honey", cost.honey))
	end
	Currency:Charge(player, food, "spa")
	local now = ctx:Now()
	pool.monster = m.id
	pool.soak = payload.soak
	pool.at = now
	pool.endsAt = now + Logic.Seconds(payload.soak)
	Monsters:SetBusy(player, m.id, BUSY_TAG)
	ctx:Dirty(player, "pools")
	if notified[player] then
		notified[player][index] = nil
	end
	return { endsAt = pool.endsAt }
end

local function collect(player, payload)
	local index = payload.pool
	local pool = mustPool(player, index)
	if not pool.monster then
		ctx:Fail("Nobody is soaking in this pool")
	end
	local now = ctx:Now()
	if not Logic.Done(pool, now) then
		ctx:Fail("The soak isn't done yet")
	end
	local id, soakId = pool.monster, pool.soak
	free(player, index)
	local s = section(player)
	local def = Rules.ById[soakId]
	if not Monsters:Get(player, id) or not def then
		return { soak = soakId, endsAt = now }
	end
	local endsAt = now + Rules.BuffHours * HOUR
	s.buffs[id] = { soak = soakId, from = now, endsAt = endsAt }
	s.soaks = (tonumber(s.soaks) or 0) + 1
	ctx:Dirty(player, "buffs")
	ctx:Dirty(player, "soaks")
	if def.bondPoints then
		Monsters:AddMood(player, id, Config.Economy.Mood.max)
		if Bond and Bond.AddPoints then
			Bond:AddPoints(player, id, def.bondPoints, "spa")
		end
	end
	pruneBuffs(player)
	ctx.Bus:Publish("SpaSoaked", player, { monsterId = id, soak = soakId })
	return { soak = soakId, endsAt = endsAt }
end

local function cancel(player, payload)
	local pool = mustPool(player, payload.pool)
	if not pool.monster then
		ctx:Fail("Nobody is soaking in this pool")
	end
	free(player, payload.pool)
	return nil
end

-- Timers ------------------------------------------------------------------------------------

local function announceDone(player)
	local s = section(player)
	if not s or not Rules.FinishNotify then
		return
	end
	local seen = notified[player]
	if not seen then
		seen = {}
		notified[player] = seen
	end
	local now = ctx:Now()
	for index, pool in s.pools do
		local m = pool.monster and Monsters:Get(player, pool.monster)
		if m and not seen[index] and Logic.Done(pool, now) then
			seen[index] = true
			ctx:Notify(player, string.format("%s's soak is done. Collect it at the Spa!", Formulas.DisplayName(m)), "info")
		end
	end
end

-- Lifecycle -----------------------------------------------------------------------------------

function Spa.Init(context)
	ctx = context
	Config = ctx.Config
	Rules = Config.Spa
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	table.clear(notified)

	ctx.Net:Handle("Spa.Soak", soak)
	ctx.Net:Handle("Spa.Collect", collect)
	ctx.Net:Handle("Spa.Cancel", cancel)

	ctx.Bus:Subscribe("LevelUp", function(player)
		refreshSession(player)
	end)
	ctx.Bus:Subscribe("MonsterRemoved", function(player, detail)
		local s = player and section(player)
		if not s or type(detail) ~= "table" then
			return
		end
		for index, pool in s.pools do
			if pool.monster == detail.id then
				s.pools[index] = Logic.EmptyPool()
				ctx:Dirty(player, "pools")
				if notified[player] then
					notified[player][index] = nil
				end
			end
		end
		if detail.id and s.buffs[detail.id] then
			s.buffs[detail.id] = nil
			ctx:Dirty(player, "buffs")
		end
	end)

	ctx:Every(10, function()
		for _, player in ctx:Players() do
			announceDone(player)
			refreshSession(player)
		end
	end)
end

function Spa.Start()
	Apiary = ctx:GetSystem("Apiary")
	Bond = ctx:GetSystem("Bond")
	local Jobs = ctx:GetSystem("Jobs")
	Monsters:RegisterMealModifier("spa", function(player, id)
		local s = section(player)
		return if s then Logic.GrowthMult(s.buffs[id], ctx:Now()) else 1
	end)
	if Jobs and Jobs.RegisterOutputBoost then
		Jobs:RegisterOutputBoost("spa", function(player, id)
			local s = section(player)
			return if s then Logic.OutputBoosts(s.buffs[id]) else nil
		end)
	end
	if Apiary and Apiary.RegisterRateBoost then
		Apiary:RegisterRateBoost("spa", function(player, id)
			local s = section(player)
			return if s then Logic.OutputBoosts(s.buffs[id]) else nil
		end)
	end
end

function Spa.PlayerAdded(player, info)
	local s = section(player)
	s.buffs = if type(s.buffs) == "table" then s.buffs else {}
	s.pools = if type(s.pools) == "table" then s.pools else {}
	for i = 1, Rules.MaxPools do
		if type(s.pools[i]) ~= "table" then
			s.pools[i] = Logic.EmptyPool()
		end
	end
	notified[player] = {}
	local now = ctx:Now()
	local lastSeen = info and info.lastSeen or 0
	local finished = 0
	for index, pool in s.pools do
		if pool.monster then
			local m = Monsters:Get(player, pool.monster)
			if not m then
				s.pools[index] = Logic.EmptyPool()
				ctx:Dirty(player, "pools")
			else
				-- Re-assert the busy tag in case a crash saved the monster without it.
				if m.busy ~= BUSY_TAG then
					Monsters:SetBusy(player, m.id, BUSY_TAG)
				end
				local endsAt = tonumber(pool.endsAt) or 0
				if lastSeen > 0 and endsAt > lastSeen and endsAt <= now then
					finished += 1
				end
			end
		end
	end
	pruneBuffs(player)
	if finished > 0 then
		ctx.Bus:Publish("WelcomeItem", player, {
			kind = "spa",
			text = if finished == 1 then "A spa soak finished" else string.format("%d spa soaks finished", finished),
		})
	end
	refreshSession(player)
end

function Spa.PlayerRemoving(player)
	notified[player] = nil
end

return Spa
