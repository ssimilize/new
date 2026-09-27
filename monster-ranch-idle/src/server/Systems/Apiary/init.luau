--[[
	Apiary (update 3.12 · Honey & stars): beehives on the ranch's north strip (the client builds
	them, Controllers/Apiary, and its "Tend" prompt opens the Apiary screen). Each open hive is
	tended by one Adult from the barn (busy tag "apiary") and makes honey on the server clock,
	online and offline, in the kind of the season it was made in. Config.Apiary, Logic/Apiary.

	Save section (profile.Apiary), version 1:
	  hives    = { [1..MaxHives] = { monster = id|false, at, stored = { [kind]: n } } }  -- Logic/Apiary
	  store    = { [kind]: n }     honey and Royal Jelly collected (at most StoreCap each)
	  collects = number            hive collects with honey, ever (seeds the Royal Jelly roll)
	  made     = number            honey collected, ever (Royal Jelly not counted)
	Session (session.Apiary): { hives, extra }   open hives; extra storage hours (Observatory)

	Actions:
	  Apiary.Assign { hive, id }     an open, empty hive and a free Adult in the barn
	  Apiary.Unassign { hive }       collects that hive, frees its keeper -> { honey }
	  Apiary.Collect {}              every hive's whole honey into the store -> { honey }
	                                 (each hive with honey rolls for Royal Jelly)
	  Apiary.Sell { kind, amount }   honey for coins (SellSeconds of ranch income each) -> { coins }

	Public API:
	  Apiary:Honey(player) -> { [kind]: n }          a copy of the store
	  Apiary:Have(player, kind) -> number
	  Apiary:AddHoney(player, kind, n) -> number     the kind's count after adding (Rewards kind honey)
	  Apiary:SpendHoney(player, kind, n) -> boolean  all or nothing
	  Apiary:HoneyCount(player) -> number            the four honey kinds together (not Royal Jelly)
	  Apiary:RegisterRateBoost(key, fn(player, monsterId) -> { { from, to, pct } }?)
	                                                 3.13 (Spa mineral soak): extra honey for one
	                                                 keeper over a time window
	  Apiary:SpendAnyHoney(player, n) -> boolean     n honey of any kind, the most plentiful kind
	                                                 first (Merchant pay kind `honey`), all or nothing

	Optional: Observatory (Perk "hive_hours" = extra storage hours), looked up in Start.
	Bus: publishes HoneyCollected (player, { kind, amount, honey }) once per kind collected
	(honey = false for Royal Jelly, so the weekly goal skips it); WelcomeItem when hives filled
	while the player was away.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local Logic = require(Shared.Logic.Apiary)

local Apiary = {
	Name = "Apiary",
	Dependencies = { "Currency", "Progression", "Rewards", "Monsters" },
	OptionalDependencies = { "Observatory" },
}

local BUSY_TAG = "apiary"

local ctx
local Config, Rules
local Progression, Rewards, Monsters
local Observatory

local notified = {} -- [player] = { [hive] = true } full hives already toasted
local rateBoosts = {} -- [key] = fn(player, monsterId) -> { { from, to, pct } }?

Apiary.Profile = {
	Version = 1,
	Default = function()
		local hives = {}
		for i = 1, Config.Apiary.MaxHives do
			hives[i] = Logic.EmptyHive()
		end
		return { hives = hives, store = {}, collects = 0, made = 0 }
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

local function extraHours(player): number
	if not Observatory or not Observatory.Perk then
		return 0
	end
	local ok, n = pcall(Observatory.Perk, Observatory, player, "hive_hours")
	return if ok and type(n) == "number" and n == n then math.max(0, n) else 0
end

local function refreshSession(player)
	local sess = ctx:Session(player)
	if not sess or not section(player) then
		return
	end
	local count = Logic.HiveCount(isUnlocked(player))
	local extra = extraHours(player)
	if sess.hives ~= count or sess.extra ~= extra then
		sess.hives = count
		sess.extra = extra
		ctx:DirtySession(player)
	end
end

local function keeperOf(player, hive)
	return hive.monster and Monsters:Get(player, hive.monster)
end

local function validKind(kind): boolean
	return type(kind) == "string" and Rules.ById[kind] ~= nil
end

local function whole(n): number
	return if type(n) == "number" and n == n and n ~= math.huge then math.max(0, math.floor(n)) else 0
end

-- Brings one hive's stored honey up to now (the hive's `at` moves to now).
local function settle(player, index: number)
	local s = section(player)
	local hive = s.hives[index]
	local now = ctx:Now()
	local m = keeperOf(player, hive)
	local boosts = nil
	if m then
		for key, fn in rateBoosts do
			local ok, list = pcall(fn, player, m.id)
			if ok and type(list) == "table" then
				boosts = boosts or {}
				for _, b in list do
					table.insert(boosts, b)
				end
			elseif not ok then
				warn(string.format("[Apiary] rate boost %s failed: %s", key, tostring(list)))
			end
		end
	end
	hive.stored = Logic.Settle(hive, m, now, extraHours(player), boosts)
	hive.at = now
	ctx:Dirty(player, "hives")
end

-- Moves one hive's whole honey into `got` (and rolls its Royal Jelly). Returns nothing.
local function takeHive(player, index: number, got)
	local s = section(player)
	settle(player, index)
	local hive = s.hives[index]
	local taken, rest = Logic.Take(hive.stored)
	hive.stored = rest
	local n = 0
	for kind, amount in taken do
		got[kind] = (got[kind] or 0) + amount
		n += amount
	end
	if n >= 1 then
		s.collects = (tonumber(s.collects) or 0) + 1
		ctx:Dirty(player, "collects")
		if Logic.RoyalJelly(player.UserId, s.collects) then
			local id = Rules.RoyalJelly.id
			got[id] = (got[id] or 0) + 1
		end
	end
	if notified[player] then
		notified[player][index] = nil
	end
end

-- Puts collected honey in the store and tells everyone who counts it.
local function bank(player, got)
	local s = section(player)
	for _, kind in Rules.AllIds do
		local n = got[kind]
		if n and n > 0 then
			s.store[kind] = math.min(Rules.StoreCap, (s.store[kind] or 0) + n)
			local isHoney = kind ~= Rules.RoyalJelly.id
			if isHoney then
				s.made = (tonumber(s.made) or 0) + n
			end
			ctx.Bus:Publish("HoneyCollected", player, { kind = kind, amount = n, honey = isHoney })
		end
	end
	ctx:Dirty(player, "store")
	ctx:Dirty(player, "made")
end

local function mustHive(player, index: number)
	local hive = section(player).hives[index]
	if not hive then
		ctx:Fail("That beehive doesn't exist")
	end
	return hive
end

-- Public API ------------------------------------------------------------------------------

function Apiary:RegisterRateBoost(key: string, fn)
	rateBoosts[key] = fn
end

function Apiary:HiveCount(player): number
	return Logic.HiveCount(isUnlocked(player))
end

function Apiary:Honey(player)
	local s = section(player)
	return if s then table.clone(s.store) else {}
end

function Apiary:Have(player, kind: string): number
	local s = section(player)
	return if s and validKind(kind) then tonumber(s.store[kind]) or 0 else 0
end

function Apiary:AddHoney(player, kind: string, n: number): number
	local s = section(player)
	if not s or not validKind(kind) then
		return 0
	end
	s.store[kind] = math.min(Rules.StoreCap, (tonumber(s.store[kind]) or 0) + whole(n))
	ctx:Dirty(player, "store")
	return s.store[kind]
end

function Apiary:SpendHoney(player, kind: string, n: number): boolean
	local s = section(player)
	if not s or not validKind(kind) or type(n) ~= "number" or n ~= n or n < 0 or n % 1 ~= 0 then
		return false
	end
	local have = tonumber(s.store[kind]) or 0
	if have < n then
		return false
	end
	s.store[kind] = if have - n > 0 then have - n else nil
	ctx:Dirty(player, "store")
	return true
end

function Apiary:HoneyCount(player): number
	local n = 0
	for _, kind in Rules.Ids do
		n += Apiary:Have(player, kind)
	end
	return n
end

function Apiary:SpendAnyHoney(player, n: number): boolean
	local s = section(player)
	if not s or type(n) ~= "number" or n ~= n or n < 0 or n % 1 ~= 0 or Apiary:HoneyCount(player) < n then
		return false
	end
	local order = table.clone(Rules.Ids)
	table.sort(order, function(a, b)
		local ca, cb = Apiary:Have(player, a), Apiary:Have(player, b)
		if ca ~= cb then
			return ca > cb
		end
		return Rules.ById[a].order < Rules.ById[b].order
	end)
	local left = n
	for _, kind in order do
		if left <= 0 then
			break
		end
		local take = math.min(Apiary:Have(player, kind), left)
		if take > 0 then
			Apiary:SpendHoney(player, kind, take)
			left -= take
		end
	end
	return true
end

-- Actions ---------------------------------------------------------------------------------

local function assign(player, payload)
	Progression:Require(player, Rules.Unlock)
	local index = payload.hive
	if index > Apiary:HiveCount(player) then
		ctx:Fail(string.format("Beehive %d opens at Ranch Level %d", index, Progression:UnlockLevel(Rules.HiveUnlocks[index])))
	end
	local hive = mustHive(player, index)
	if hive.monster then
		ctx:Fail("This beehive already has a keeper")
	end
	local m, why = Monsters:Available(player, payload.id)
	if not m then
		ctx:Fail(why or "That monster doesn't exist")
	end
	if (m.stage or 1) < Rules.MinStage then
		ctx:Fail("Only Adults can tend a beehive")
	end
	if m.loc == "pen" then
		ctx:Fail(string.format("%s works in a pen. Move it to the barn first", Formulas.DisplayName(m)))
	end
	-- Honey a hive held before (a keeper who left the ranch) stays in it until collected.
	settle(player, index)
	hive.monster = m.id
	hive.at = ctx:Now()
	Monsters:SetBusy(player, m.id, BUSY_TAG)
	ctx:Dirty(player, "hives")
	if notified[player] then
		notified[player][index] = nil
	end
	return nil
end

local function unassign(player, payload)
	local index = payload.hive
	local hive = mustHive(player, index)
	if not hive.monster then
		ctx:Fail("That beehive has no keeper")
	end
	local got = {}
	takeHive(player, index, got)
	local id = hive.monster
	local m = Monsters:Get(player, id)
	if m and m.busy == BUSY_TAG then
		Monsters:SetBusy(player, id, false)
	end
	hive.monster = false
	hive.at = ctx:Now()
	ctx:Dirty(player, "hives")
	bank(player, got)
	return { honey = got }
end

local function collect(player)
	Progression:Require(player, Rules.Unlock)
	local got = {}
	for index in section(player).hives do
		takeHive(player, index, got)
	end
	if next(got) == nil then
		ctx:Fail("No honey to collect yet")
	end
	bank(player, got)
	return { honey = got }
end

local function sell(player, payload)
	Progression:Require(player, Rules.Unlock)
	local kind, amount = payload.kind, payload.amount
	if Apiary:Have(player, kind) < amount then
		ctx:Fail(string.format("Not enough %s", Logic.Name(kind)))
	end
	if not Apiary:SpendHoney(player, kind, amount) then
		ctx:Fail(string.format("Not enough %s", Logic.Name(kind)))
	end
	local granted = Rewards:Grant(player, { { kind = "coins", seconds = Logic.SellSeconds(kind, amount), amount = 0 } }, "apiary")
	local coins = 0
	for _, item in granted do
		if item.kind == "coins" then
			coins += item.amount or 0
		end
	end
	return { coins = coins }
end

-- Timers ------------------------------------------------------------------------------------

local function announceFull(player)
	local s = section(player)
	if not s or not Rules.FullNotify then
		return
	end
	local seen = notified[player]
	if not seen then
		seen = {}
		notified[player] = seen
	end
	local now, extra = ctx:Now(), extraHours(player)
	for index, hive in s.hives do
		local m = keeperOf(player, hive)
		if m and not seen[index] and Logic.SecondsToFull(hive, m, now, extra) <= 0 then
			seen[index] = true
			ctx:Notify(player, string.format("%s's beehive is full. Collect at the Apiary!", Formulas.DisplayName(m)), "info")
		end
	end
end

-- Lifecycle -----------------------------------------------------------------------------------

function Apiary.Init(context)
	ctx = context
	Config = ctx.Config
	Rules = Config.Apiary
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")
	Monsters = ctx:GetSystem("Monsters")
	table.clear(notified)
	table.clear(rateBoosts)

	ctx.Net:Handle("Apiary.Assign", assign)
	ctx.Net:Handle("Apiary.Unassign", unassign)
	ctx.Net:Handle("Apiary.Collect", collect)
	ctx.Net:Handle("Apiary.Sell", sell)

	ctx.Bus:Subscribe("LevelUp", function(player)
		refreshSession(player)
	end)
	ctx.Bus:Subscribe("StarCharted", function(player)
		if player and section(player) then
			refreshSession(player)
		end
	end)
	ctx.Bus:Subscribe("MonsterRemoved", function(player, detail)
		local s = player and section(player)
		if not s or type(detail) ~= "table" then
			return
		end
		for index, hive in s.hives do
			if hive.monster == detail.id then
				-- The keeper is gone: what the hive made so far stays in it (a new keeper or
				-- Collect takes it); nothing more is made until someone tends it.
				hive.monster = false
				hive.at = ctx:Now()
				ctx:Dirty(player, "hives")
				if notified[player] then
					notified[player][index] = nil
				end
			end
		end
	end)

	ctx:Every(10, function()
		for _, player in ctx:Players() do
			announceFull(player)
			refreshSession(player)
		end
	end)
end

function Apiary.Start()
	Observatory = ctx:GetSystem("Observatory")
end

function Apiary.PlayerAdded(player, info)
	local s = section(player)
	s.store = if type(s.store) == "table" then s.store else {}
	s.hives = if type(s.hives) == "table" then s.hives else {}
	for i = 1, Rules.MaxHives do
		if type(s.hives[i]) ~= "table" then
			s.hives[i] = Logic.EmptyHive()
		end
		s.hives[i].stored = if type(s.hives[i].stored) == "table" then s.hives[i].stored else {}
	end
	notified[player] = {}
	local now = ctx:Now()
	local lastSeen = info and info.lastSeen or 0
	local extra = extraHours(player)
	local filled = 0
	for _, hive in s.hives do
		if hive.monster then
			local m = keeperOf(player, hive)
			if not m then
				hive.monster = false
				hive.at = now
				ctx:Dirty(player, "hives")
			else
				-- Re-assert the busy tag in case a crash saved the keeper without it.
				if m.busy ~= BUSY_TAG then
					Monsters:SetBusy(player, m.id, BUSY_TAG)
				end
				local wasFull = lastSeen > 0 and Logic.SecondsToFull(hive, m, lastSeen, extra) <= 0
				if lastSeen > 0 and not wasFull and Logic.SecondsToFull(hive, m, now, extra) <= 0 then
					filled += 1
				end
			end
		end
		hive.at = tonumber(hive.at) or now
	end
	if filled > 0 then
		ctx.Bus:Publish("WelcomeItem", player, {
			kind = "apiary",
			text = if filled == 1 then "A beehive filled with honey" else string.format("%d beehives filled with honey", filled),
		})
	end
	refreshSession(player)
end

function Apiary.PlayerRemoving(player)
	notified[player] = nil
end

return Apiary
