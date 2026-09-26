--[[
	Reminders (glow-up): opt-in offline reminders through Roblox Experience Notifications
	(Config.Reminders, planning rules in Logic/Reminders). Everything no-ops while the config
	is empty, while the adapter is missing (Studio without API access, Lune without a fake) or
	when a call fails.

	Opt-in: after the first hatch of a player's second (or later) session, and only while
	the feature is on, session.Reminders.prompt turns true once; the client shows Roblox's
	opt-in prompt (ExperienceNotificationService:PromptOptIn) and answers with
	Reminders.SetOptIn { on }. The answer is remembered (profile.Reminders.asked / on) and the
	prompt never comes back by itself; the Daily streak screen has a Reminders on/off button.

	Planning: when an opted-in player leaves, the facts (eggs ready, expeditions back, next
	Stampede for players who have joined one, a streak about to break) go through
	Logic/Reminders.Plan and each planned item is written to the MemoryStore map "queue"
	(key "u<userId>:<kind>", sortKey = due time). Joining again removes them.

	Sending: every PollSeconds each server reads due items, leases one with an atomic update
	(lease + owner), checks the per-player daily cap (map "caps", Logic/Reminders.Allow) and
	POSTs the Open Cloud user notification. Sent, refused (4xx) and expired items are removed;
	a failed send is retried after its lease, up to MaxTries.

	Save section (profile.Reminders): { on, asked, askedAt, stampede, exp, queued }
	  exp (private) = { [slot 1..4]: unix the running expedition comes back, 0 = none }
	  queued (private) = items may be waiting in the queue (cancel them on join)
	Session (session.Reminders): { available, prompt }

	Actions: Reminders.SetOptIn { on }
	Public API: Reminders:Enabled() -> boolean, Reminders:Poll() (tests), Reminders:Plan(player)
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Reminders)
local Adapter = require(script.Adapter)

local Reminders = {
	Name = "Reminders",
	Dependencies = {},
	OptionalDependencies = { "Eggs", "LoginStreak" },
}

local EXP_SLOTS = 4

Reminders.Profile = {
	Version = 1,
	Default = function()
		return { on = false, asked = false, askedAt = 0, stampede = false, exp = { 0, 0, 0, 0 }, queued = false }
	end,
	Private = { "exp", "queued" },
}

local ctx
local Config

local roblox = nil
local triedRoblox = false
local polling = false
local leaseCounter = 0
local countries = {} -- [player] = country code (rough local time for quiet hours)
local promptedThisSession = {} -- [player] = true once the opt-in prompt was offered

local function adapter()
	local provided = ctx.Services.Reminders
	if provided ~= nil then
		return provided
	end
	if not triedRoblox then
		triedRoblox = true
		roblox = Adapter.Roblox()
	end
	return roblox
end

local function enabled(): boolean
	if not Config.Reminders.Enabled() then
		return false
	end
	local a = adapter()
	if not a then
		return false
	end
	local ok, available = pcall(a.Available)
	return ok and available == true
end

local function key(userId: number, kind: string): string
	return string.format("u%d:%s", userId, kind)
end

local function spawn(fn)
	ctx.Services.Spawn(function()
		local ok, err = pcall(fn)
		if not ok then
			warn("[Reminders] " .. tostring(err))
		end
	end)
end

-- Facts ------------------------------------------------------------------------------

local function facts(player)
	local s = ctx:Section(player)
	local now = ctx:Now()
	local out = { stampede = s.stampede == true }
	local Eggs = ctx:GetSystem("Eggs")
	if Eggs and Eggs.PublicSlots then
		local latest = 0
		for _, slot in Eggs:PublicSlots(player) do
			if (tonumber(slot.endsAt) or 0) > now then
				latest = math.max(latest, slot.endsAt)
			end
		end
		out.eggsReadyAt = if latest > 0 then latest else nil
	end
	local back = 0
	for _, endsAt in s.exp or {} do
		if (tonumber(endsAt) or 0) > now then
			back = math.max(back, endsAt)
		end
	end
	out.expeditionsBackAt = if back > 0 then back else nil
	local Streak = ctx:GetSystem("LoginStreak")
	if Streak and Streak.Status then
		local status = Streak:Status(player)
		if status and status.streak >= Config.Reminders.Streak.minStreak then
			out.streakDeadline = status.deadline
		end
	end
	local country = countries[player]
	out.offset = if country then Config.Reminders.Offsets[country] else nil
	return out
end

function Reminders:Plan(player)
	return Logic.Plan(facts(player), ctx:Now())
end

function Reminders:Enabled(): boolean
	return enabled()
end

-- Sending ----------------------------------------------------------------------------

local function body(a, kind: string)
	return {
		source = { universe = "universes/" .. tostring(a.UniverseId()) },
		payload = {
			message_id = Config.Reminders.Templates[kind],
			type = "MOMENT",
			join_experience = { launch_data = "reminder_" .. kind },
			analytics_data = { category = "reminder_" .. kind },
		},
	}
end

local function sendOne(a, row, now: number)
	local item = row.value
	if type(item) ~= "table" or type(item.u) ~= "number" or type(item.kind) ~= "string" then
		a.Remove("queue", row.key)
		return
	end
	if (tonumber(item.lease) or 0) > now then
		return -- another server holds it
	end
	local template = Config.Reminders.Templates[item.kind]
	if (tonumber(item.exp) or 0) <= now or (tonumber(item.tries) or 0) >= Config.Reminders.MaxTries or not template or template == "" then
		a.Remove("queue", row.key)
		return
	end
	if ctx:PlayerByUserId(item.u) then
		a.Remove("queue", row.key) -- they are playing here
		return
	end
	leaseCounter += 1
	local owner = string.format("%s#%d", tostring(a.JobId()), leaseCounter)
	local okLease, leased = a.Update("queue", row.key, function(old)
		if type(old) ~= "table" or (tonumber(old.lease) or 0) > now then
			return nil
		end
		local new = table.clone(old)
		new.lease = now + Config.Reminders.LeaseSeconds
		new.owner = owner
		new.tries = (tonumber(old.tries) or 0) + 1
		return new
	end, math.max(60, (tonumber(item.exp) or now) - now))
	if not okLease or type(leased) ~= "table" or leased.owner ~= owner then
		return
	end
	local allowed = false
	local okCap = a.Update("caps", "u" .. item.u, function(old)
		local ok, record = Logic.Allow(old, now)
		allowed = ok
		return if ok then record else nil
	end, 2 * 86400)
	if not okCap then
		return -- the lease runs out and the item is retried
	end
	if not allowed then
		a.Remove("queue", row.key)
		return
	end
	local sent, status = a.Post(string.format(Config.Reminders.Url, item.u), body(a, item.kind), Config.Reminders.SecretName)
	status = tonumber(status) or 0
	if sent or (status >= 400 and status < 500 and status ~= 429) then
		a.Remove("queue", row.key)
	end
	if not sent then
		a.Update("caps", "u" .. item.u, Logic.Refund, 2 * 86400) -- a failed send never uses up the day
	end
end

function Reminders:Poll()
	if polling or not enabled() then
		return
	end
	local a = adapter()
	polling = true
	local ok, err = pcall(function()
		local now = ctx:Now()
		local okDue, rows = a.Due("queue", now + 1, Config.Reminders.BatchSize)
		if okDue then
			for _, row in rows do
				sendOne(a, row, now)
			end
		end
	end)
	polling = false
	if not ok then
		warn("[Reminders] poll failed: " .. tostring(err))
	end
end

-- Lifecycle --------------------------------------------------------------------------

function Reminders.Init(context)
	ctx = context
	Config = ctx.Config

	ctx.Net:Handle("Reminders.SetOptIn", function(player, payload)
		local s = ctx:Section(player)
		s.on = payload.on == true
		ctx:Dirty(player, "on")
		if not s.asked then
			s.asked = true
			s.askedAt = ctx:Now()
			ctx:Dirty(player, "asked")
			ctx:Dirty(player, "askedAt")
		end
		local sess = ctx:Session(player)
		if sess.prompt then
			sess.prompt = false
			ctx:DirtySession(player)
		end
		return { on = s.on }
	end)

	ctx.Bus:Subscribe("EggHatched", function(player)
		local s = ctx:Section(player)
		local meta = ctx:Meta(player)
		if not s or s.asked or promptedThisSession[player] or not meta or (meta.joins or 0) < 2 then
			return
		end
		local sess = ctx:Session(player)
		if not sess.available then
			return
		end
		promptedThisSession[player] = true
		sess.prompt = true
		ctx:DirtySession(player)
	end)
	ctx.Bus:Subscribe("BossJoined", function(player)
		local s = ctx:Section(player)
		if s and not s.stampede then
			s.stampede = true
			ctx:Dirty(player, "stampede")
		end
	end)
	ctx.Bus:Subscribe("ExpeditionStarted", function(player, detail)
		local s = ctx:Section(player)
		local slot = tonumber(detail and detail.slot)
		if s and slot and slot >= 1 and slot <= EXP_SLOTS then
			s.exp[slot] = ctx:Now() + (tonumber(detail.duration) or 0)
		end
	end)
	ctx.Bus:Subscribe("ExpeditionClaimed", function(player, detail)
		local s = ctx:Section(player)
		local slot = tonumber(detail and detail.slot)
		if s and slot and slot >= 1 and slot <= EXP_SLOTS then
			s.exp[slot] = 0
		end
	end)
	ctx.Bus:Subscribe("Rebirthed", function(player)
		local s = ctx:Section(player)
		if s then
			s.exp = { 0, 0, 0, 0 }
		end
	end)
end

function Reminders.Start()
	ctx:Every(Config.Reminders.PollSeconds, function()
		if Config.Reminders.Enabled() then
			spawn(function()
				Reminders:Poll()
			end)
		end
	end)
end

function Reminders.PlayerAdded(player, _info)
	local s = ctx:Section(player)
	if type(s.exp) ~= "table" or #s.exp ~= EXP_SLOTS then
		s.exp = { 0, 0, 0, 0 }
	end
	local sess = ctx:Session(player)
	sess.available = enabled()
	sess.prompt = false
	ctx:DirtySession(player)
	if not sess.available then
		return
	end
	local a = adapter()
	local userId = player.UserId
	local wasQueued = s.queued
	s.queued = false
	spawn(function()
		if wasQueued then
			for _, kind in Config.Reminders.Kinds do
				a.Remove("queue", key(userId, kind))
			end
		end
		local country = a.Country(player)
		if country and ctx:Section(player) ~= nil then
			countries[player] = country
		end
	end)
end

function Reminders.PlayerRemoving(player)
	promptedThisSession[player] = nil
	local s = ctx:Section(player)
	local ok, plan = pcall(function()
		if not s or not s.on or not enabled() then
			return {}
		end
		return Logic.Plan(facts(player), ctx:Now())
	end)
	countries[player] = nil
	if not ok or #plan == 0 then
		return
	end
	s.queued = true
	local a = adapter()
	local userId = player.UserId
	spawn(function()
		for _, item in plan do
			local value = { u = userId, kind = item.kind, exp = item.expiresAt, tries = 0, lease = 0 }
			a.Put("queue", key(userId, item.kind), value, item.dueAt, item.expiresAt - ctx:Now() + 3600)
		end
	end)
end

return Reminders
