--[[
	Jobs (update 3.7): the Job Board. Teens and Adults resting in the barn take a job that runs
	on one of their stats (Config/Jobs, Logic/Jobs): herders keep pen Mood up, miners dig coins,
	guards make coin jars hold longer, foragers gather food and scouts find eggs.

	Save section (profile.Jobs):
	  slots = { [1..MaxSlots] = Slot }   -- always MaxSlots entries; see Logic/Jobs for Slot
	Session (session.Jobs): { slotCount }

	Actions:
	  Jobs.Assign { slot, job, id, flavor? }  -- an empty open slot and a free Teen/Adult in the barn
	  Jobs.Recall { slot }                    -- pays what the worker has stored, frees it
	  Jobs.Collect {}                         -- pays every collecting worker; returns { rewards }
	  Jobs.SetFlavor { slot, flavor }         -- a forager's flavour; pays its stored food first

	Rules:
	  • unlock Config.Jobs.Unlock; slots = Logic/Jobs.SlotCount (BaseSlots + SlotUnlocks reached)
	  • workers carry the busy tag "job" until recalled; a worker that leaves the ranch (rebirth)
	    frees its slot
	  • miners, foragers and scouts store at most MaxHours of work, online or offline; scout eggs
	    are rolled per whole hour from the slot's seed, so they cannot be rerolled
	  • guards: Ranch:RegisterJarBonus("jobs"); herders: Monsters:RegisterMoodDecayModifier("jobs")
	    (pen monsters only)

	Public API:
	  Jobs:SlotCount(player) -> number
	  Jobs:Workers(player, jobId) -> { Monster }   -- the monsters on that job right now
	  Jobs:RegisterOutputBoost(key, fn(player, monsterId) -> { { from, to, pct } }?)
	                                              -- 3.10 (Kitchen dishes): extra output for one
	                                                 worker over a time window (Logic/Jobs.BoostedSeconds);
	                                                 miners, foragers and scouts only

	Bus: publishes JobsCollected { rewards } and RateModifiersChanged (guards changed);
	WelcomeItem when workers stored work while the player was away.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local JobsLogic = require(Shared.Logic.Jobs)

local Jobs = {
	Name = "Jobs",
	Dependencies = { "Currency", "Progression", "Rewards", "Monsters" },
	OptionalDependencies = { "Ranch" },
}

local BUSY_TAG = "job"

local ctx
local Config, Rules
local Progression, Rewards, Monsters

local notified = {} -- [player] = { [slot] = true } slots whose "storage full" toast was shown
local outputBoosts = {} -- [key] = fn(player, monsterId) -> { { from, to, pct } }?

local function maxSlots(): number
	return Config.Jobs.MaxSlots
end

Jobs.Profile = {
	Version = 1,
	Default = function()
		local slots = {}
		for i = 1, maxSlots() do
			slots[i] = JobsLogic.EmptySlot()
		end
		return { slots = slots }
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

local function refreshSession(player)
	local sess = ctx:Session(player)
	if not sess or not section(player) then
		return
	end
	local count = JobsLogic.SlotCount(isUnlocked(player))
	if sess.slotCount ~= count then
		sess.slotCount = count
		ctx:DirtySession(player)
	end
end

local function workerOf(player, slot)
	return slot.monster and Monsters:Get(player, slot.monster)
end

local function resetSlot(player, index: number)
	local s = section(player)
	local flavor = s.slots[index] and s.slots[index].flavor
	s.slots[index] = JobsLogic.EmptySlot()
	if flavor then
		s.slots[index].flavor = flavor
	end
	ctx:Dirty(player, "slots")
	if notified[player] then
		notified[player][index] = nil
	end
end

local function guardsChanged(player)
	ctx.Bus:Publish("RateModifiersChanged", player, {})
end

-- Pays one slot's stored work into `into`; returns nothing. Updates the slot's counters.
local function settle(player, index: number, into)
	local s = section(player)
	local slot = s.slots[index]
	local m = workerOf(player, slot)
	if not m then
		return
	end
	local boosts = {}
	for key, fn in outputBoosts do
		local ok, list = pcall(fn, player, m.id)
		if ok and type(list) == "table" then
			for _, b in list do
				table.insert(boosts, b)
			end
		elseif not ok then
			warn(string.format("[Jobs] output boost %s failed: %s", key, tostring(list)))
		end
	end
	local rewards, since, carry, rolled =
		JobsLogic.Collect(slot, m, ctx:Now(), JobsLogic.ScoutEggs(isUnlocked(player)), if #boosts > 0 then boosts else nil)
	slot.since, slot.carry, slot.rolled = since, carry, rolled
	for _, item in rewards do
		table.insert(into, item)
	end
	ctx:Dirty(player, "slots")
	if notified[player] then
		notified[player][index] = nil
	end
end

local function grant(player, items)
	if #items == 0 then
		return {}
	end
	local granted = Rewards:Grant(player, items, "jobs")
	ctx.Bus:Publish("JobsCollected", player, { rewards = granted })
	return granted
end

local function mustSlot(player, index: number)
	local slot = section(player).slots[index]
	if not slot then
		ctx:Fail("That job slot doesn't exist")
	end
	return slot
end

-- Public API ------------------------------------------------------------------------------

function Jobs:SlotCount(player): number
	return JobsLogic.SlotCount(isUnlocked(player))
end

function Jobs:Workers(player, jobId: string)
	local list = {}
	local s = section(player)
	if not s then
		return list
	end
	for _, slot in s.slots do
		if slot.job == jobId then
			local m = workerOf(player, slot)
			if m then
				table.insert(list, m)
			end
		end
	end
	return list
end

function Jobs:RegisterOutputBoost(key: string, fn)
	outputBoosts[key] = fn
end

-- Actions ---------------------------------------------------------------------------------

local function assign(player, payload)
	Progression:Require(player, Rules.Unlock)
	if payload.slot > Jobs:SlotCount(player) then
		local key = Rules.SlotUnlocks[payload.slot - Rules.BaseSlots]
		ctx:Fail(string.format("Job slot %d opens at Ranch Level %d", payload.slot, Progression:UnlockLevel(key)))
	end
	local slot = mustSlot(player, payload.slot)
	if slot.job then
		ctx:Fail("Recall this slot's worker first")
	end
	local m, why = Monsters:Available(player, payload.id)
	if not m then
		ctx:Fail(why or "That monster doesn't exist")
	end
	if (m.stage or 1) < Rules.MinStage then
		ctx:Fail("Only Teens and Adults can work")
	end
	if m.loc == "pen" then
		ctx:Fail(Formulas.DisplayName(m) .. " works in a pen. Move it to the barn first")
	end
	local s = section(player)
	local index = payload.slot
	s.slots[index] = {
		job = payload.job,
		monster = m.id,
		since = ctx:Now(),
		carry = 0,
		rolled = 0,
		flavor = payload.flavor or slot.flavor or Config.Food.Ids[1],
		seed = ctx.Rng:Int(1, 2147483646),
	}
	Monsters:SetBusy(player, m.id, BUSY_TAG)
	ctx:Dirty(player, "slots")
	if notified[player] then
		notified[player][index] = nil
	end
	if payload.job == "guard" then
		guardsChanged(player)
	end
	return nil
end

local function recall(player, payload)
	local slot = mustSlot(player, payload.slot)
	if not slot.job then
		ctx:Fail("That slot is empty")
	end
	local items = {}
	settle(player, payload.slot, items)
	local job, id = slot.job, slot.monster
	local m = id and Monsters:Get(player, id)
	if m and m.busy == BUSY_TAG then
		Monsters:SetBusy(player, id, false)
	end
	resetSlot(player, payload.slot)
	if job == "guard" then
		guardsChanged(player)
	end
	return { rewards = grant(player, items) }
end

local function collectAll(player)
	local items = {}
	for index, slot in section(player).slots do
		if slot.job and Rules.ById[slot.job] and Rules.ById[slot.job].collects then
			settle(player, index, items)
		end
	end
	return { rewards = grant(player, items) }
end

local function setFlavor(player, payload)
	local slot = mustSlot(player, payload.slot)
	if slot.job ~= "forager" then
		ctx:Fail("Only foragers pick a flavour")
	end
	local items = {}
	settle(player, payload.slot, items)
	slot.flavor = payload.flavor
	ctx:Dirty(player, "slots")
	return { rewards = grant(player, items) }
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
	local now = ctx:Now()
	for index, slot in s.slots do
		if JobsLogic.IsFull(slot, now) and not seen[index] then
			seen[index] = true
			local m = workerOf(player, slot)
			if m then
				ctx:Notify(player, string.format("%s's storage is full. Collect on the Job Board!", Formulas.DisplayName(m)), "info")
			end
		end
	end
end

-- Lifecycle -----------------------------------------------------------------------------------

function Jobs.Init(context)
	ctx = context
	Config = ctx.Config
	Rules = Config.Jobs
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")
	Monsters = ctx:GetSystem("Monsters")
	table.clear(notified)

	ctx.Net:Handle("Jobs.Assign", assign)
	ctx.Net:Handle("Jobs.Recall", recall)
	ctx.Net:Handle("Jobs.Collect", collectAll)
	ctx.Net:Handle("Jobs.SetFlavor", setFlavor)

	ctx.Bus:Subscribe("LevelUp", function(player)
		refreshSession(player)
	end)
	ctx.Bus:Subscribe("MonsterRemoved", function(player, detail)
		local s = player and section(player)
		if not s then
			return
		end
		for index, slot in s.slots do
			if slot.monster == detail.id then
				local wasGuard = slot.job == "guard"
				resetSlot(player, index)
				if wasGuard then
					guardsChanged(player)
				end
			end
		end
	end)

	ctx:Every(10, function()
		for _, player in ctx:Players() do
			announceFull(player)
		end
	end)
end

function Jobs.Start()
	local Ranch = ctx:GetSystem("Ranch")
	if Ranch then
		Ranch:RegisterJarBonus("jobs", function(player)
			return JobsLogic.GuardSeconds(Jobs:Workers(player, "guard"))
		end)
	end
	Monsters:RegisterMoodDecayModifier("jobs", function(player, m)
		if m.loc ~= "pen" or m.busy then
			return 0
		end
		return JobsLogic.Shield(Jobs:Workers(player, "herder"))
	end)
end

function Jobs.PlayerAdded(player, info)
	local s = section(player)
	-- A save from before a slot count change keeps exactly MaxSlots slots.
	for i = 1, maxSlots() do
		if type(s.slots[i]) ~= "table" then
			s.slots[i] = JobsLogic.EmptySlot()
		end
	end
	notified[player] = {}
	local now = ctx:Now()
	local lastSeen = info and info.lastSeen or 0
	local stored = 0
	for index, slot in s.slots do
		if slot.job then
			local m = workerOf(player, slot)
			if not m then
				resetSlot(player, index)
			else
				-- Re-assert the busy tag in case a crash saved the worker without it.
				if m.busy ~= BUSY_TAG then
					Monsters:SetBusy(player, m.id, BUSY_TAG)
				end
				local job = Rules.ById[slot.job]
				if job and job.collects and lastSeen > 0 and now - math.max(slot.since or now, lastSeen) >= 60 then
					stored += 1
				end
			end
		end
	end
	if stored > 0 then
		ctx.Bus:Publish("WelcomeItem", player, {
			kind = "jobs",
			text = if stored == 1
				then "A worker has goods on the Job Board"
				else string.format("%d workers have goods on the Job Board", stored),
		})
	end
	refreshSession(player)
	guardsChanged(player)
end

function Jobs.PlayerRemoving(player)
	notified[player] = nil
end

return Jobs
