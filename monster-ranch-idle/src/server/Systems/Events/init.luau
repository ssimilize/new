--[[
	Events (S6): the seasonal event calendar (Config.Events) and event tokens earned by
	playing. Update 1.2 (Lunar Lanterns) made events calendar-driven; Flags.ActiveEvent can
	still force one (or false to turn them off).

	Save section (profile.Events): { event, day, earned }
	  event  = id of the event `earned` belongs to (tokens earned today are per event)
	  day    = UTC day of `earned`; a new day or a new event resets it
	  earned = tokens earned today (≤ Config.Events.Earn.dailyCap)
	  login  = UTC day the daily login bonus was last paid

	Global state (global.Events): { id, name, endsAt, token = { name, glyph, color } }
	  id = false when no event runs. Refreshed every 30 s so events start and end on time.

	Token sources (Config.Events.Earn): daily login (PlayerReady), BossJoined, ExpeditionClaimed
	(per hour of duration), StageCleared (first clears), EggHatched. Tokens go to
	Currency "token.<eventId>" with reason "event_<source>".

	Public API:
	  Events:Active() -> eventDef?          -- the running event
	  Events:Grant(player, amount, source) -> granted   -- respects the daily cap
]]

local Events = {
	Name = "Events",
	Dependencies = { "Currency" },
}

Events.Profile = {
	Version = 1,
	Default = function()
		return { event = false, day = 0, earned = 0, login = 0 }
	end,
}

local ctx
local Config
local Currency

local function active()
	return Config.Events.Active(ctx:Now())
end

local function publish()
	local g = ctx:Global()
	local e = active()
	local id = if e then e.id else false
	if g.id == id and g.endsAt == (if e then e.endsAt else 0) then
		return
	end
	g.id = id
	g.name = if e then e.name else ""
	g.endsAt = if e then e.endsAt else 0
	g.token = if e then table.clone(e.token) else false
	ctx:DirtyGlobal()
end

function Events:Active()
	return active()
end

function Events:Grant(player, amount: number, source: string): number
	local e = active()
	local s = ctx:Section(player)
	if not e or not s or amount <= 0 then
		return 0
	end
	local today = ctx:Day()
	if s.event ~= e.id or s.day ~= today then
		s.event = e.id
		s.day = today
		s.earned = 0
	end
	local room = Config.Events.Earn.dailyCap - s.earned
	local granted = math.max(0, math.min(math.floor(amount), room))
	if granted <= 0 then
		return 0
	end
	s.earned += granted
	ctx:Dirty(player)
	Currency:Add(player, "token." .. e.id, granted, "event_" .. source)
	return granted
end

function Events.Init(context)
	ctx = context
	Config = ctx.Config
	Currency = ctx:GetSystem("Currency")
	local Earn = Config.Events.Earn

	ctx.Bus:Subscribe("PlayerReady", function(player)
		local e = active()
		local s = ctx:Section(player)
		if not e or not s or s.login == ctx:Day() then
			return
		end
		s.login = ctx:Day()
		ctx:Dirty(player, "login")
		local granted = Events:Grant(player, Earn.dailyLogin, "login")
		if granted > 0 then
			ctx:Notify(player, string.format("%s: +%d %s for logging in today!", e.name, granted, e.token.name), "reward")
		end
	end)
	ctx.Bus:Subscribe("BossJoined", function(player)
		Events:Grant(player, Earn.bossJoined, "boss")
	end)
	ctx.Bus:Subscribe("ExpeditionClaimed", function(player, detail)
		local hours = (tonumber(detail and detail.duration) or 0) / 3600
		Events:Grant(player, math.floor(hours * Earn.expeditionPerHour + 0.5), "expedition")
	end)
	ctx.Bus:Subscribe("StageCleared", function(player, detail)
		if detail and detail.first then
			Events:Grant(player, Earn.stageFirstClear, "stage")
		end
	end)
	ctx.Bus:Subscribe("EggHatched", function(player)
		Events:Grant(player, Earn.hatch, "hatch")
	end)

	local g = ctx:Global()
	g.id, g.name, g.endsAt, g.token = false, "", 0, false
	publish()
end

function Events.Start()
	ctx:Every(30, publish)
end

return Events
