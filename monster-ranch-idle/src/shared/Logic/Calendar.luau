--[[
	Calendar (update 3.8 · Reasons to come back): every dated thing in the game on one list, for
	the Events screen, the HUD countdown chips and the "event" reminder. Pure: it only reads
	Config and the existing date helpers, so server, client and tests always agree.

	  Calendar.Entries(now, horizonSeconds) -> { Entry }
	      everything running at `now` or starting before now + horizonSeconds, sorted by start
	      (then by kind, then key). Entry = { key, kind, name, startsAt, endsAt?, icon, blurb, screen? }
	      endsAt nil = a moment (a region opening, the weekly reset) or a forced event.
	  Calendar.Now(now) -> { Entry }                 what runs at `now` (with its end time)
	  Calendar.Soon(now, withinSeconds) -> { Entry } what starts within `withinSeconds`, for the
	      HUD chips: never the Stampede (the HUD has its own card), never an Egg Hunt round (they
	      run back to back all event long), never anything already running
	  Calendar.Sections(now) -> { now, week, later }  the Events screen's three lists:
	      now    running
	      week   starting up to the next Saturday reset (Config.Leaderboards.WeekEndsAt)
	      later  starting within LaterSeconds, plus the next BIG date of each kind beyond that
	  Calendar.NextBig(now, withinSeconds, kinds?) -> Entry?  the first entry of `kinds`
	      (default Calendar.ReminderKinds) starting after `now` and within `withinSeconds`

	Sources: seasonal events and reruns (Config.Events; Flags.ActiveEvent is respected the way
	Events.Active does), Ranch Pass seasons (Config.Quests), titan invasions (Config.Titan),
	region and raid openings (opensAt), Club Wars (Clubs.War.startsAt), arena seasons
	(Logic/Arena), the Saturday reset, the next Stampede (Logic/Titan.NextStampede: skips the
	slots a titan holds, like the server), Egg Hunt rounds while Spring Bloom runs, the
	Travelling Merchant (3.11, Logic/Merchant: only the visit running now and the next one, so
	the Events screen lists one or two rows, never a month of them), and (3.11) the current and
	next Ranch Season (Logic/Seasons, kind "season", named after the season).
]]

local Config = require(script.Parent.Parent.Config)
local TitanLogic = require(script.Parent.Titan)
local ArenaLogic = require(script.Parent.Arena)
local EggHuntLogic = require(script.Parent.EggHunt)
local MerchantLogic = require(script.Parent.Merchant)
local SeasonsLogic = require(script.Parent.Seasons)

local Calendar = {}

local DAY = 86400

Calendar.LaterSeconds = 30 * DAY -- the Events screen's "Coming up" window
-- One-off dates worth showing however far away (the next one of each kind).
Calendar.BigKinds = { event = true, titan = true, region = true, pass = true, raid = true, clubwars = true }
-- What the "event" reminder nudges for.
Calendar.ReminderKinds = { titan = true, event = true, region = true }

-- Same-moment entries sort in this order.
local KIND_ORDER = {
	event = 1,
	titan = 2,
	region = 3,
	raid = 4,
	pass = 5,
	clubwars = 6,
	arena = 7,
	season = 7.5, -- 3.11: a new season starts at the weekly reset, listed just before it
	reset = 8,
	egghunt = 9,
	stampede = 10,
	merchant = 11,
}

local BLURB = {
	event = "Event eggs, decor and tokens for a limited time.",
	egghunt = "Painted eggs hide around the Market Square.",
	pass = "A new Ranch Pass season with fresh rewards.",
	titan = "A giant that every server fights together.",
	region = "A new region opens for expeditions.",
	raid = "A new raid boss opens its portal.",
	clubwars = "Clubs battle for war points every week.",
	arena = "A new arena season: ratings move halfway back.",
	reset = "Leaderboards and weekly goals start over.",
	season = "Seasonal fish, recipes and decor.",
	stampede = "Join the server boss for rewards.",
	merchant = "Rare wares for coins, gems or a barter.",
}

local function entry(
	kind: string,
	key: string,
	name: string,
	startsAt: number,
	endsAt: number?,
	icon: string,
	screen: string?,
	params: any?
)
	return {
		key = key,
		kind = kind,
		name = name,
		startsAt = startsAt,
		endsAt = endsAt,
		icon = icon,
		blurb = BLURB[kind],
		screen = screen,
		params = params, -- passed to Router:Open with `screen` (e.g. { tab = "season" })
	}
end

local function running(e, now: number): boolean
	return e.startsAt <= now and (e.endsAt == nil or now < e.endsAt)
end

local function before(a, b): boolean
	if a.startsAt ~= b.startsAt then
		return a.startsAt < b.startsAt
	end
	local ka, kb = KIND_ORDER[a.kind] or 99, KIND_ORDER[b.kind] or 99
	if ka ~= kb then
		return ka < kb
	end
	return a.key < b.key
end

-- Sources ------------------------------------------------------------------------------

local function events(out, now: number, untilAt: number)
	local Events = Config.Events
	local forced = Config.Flags.ActiveEvent
	if forced == false then
		return
	elseif type(forced) == "string" then
		-- Forced on: it runs now with no end, and the calendar's own windows are ignored.
		local e = Events.ById[forced]
		if e then
			table.insert(out, entry("event", "event:" .. e.id .. ":forced", e.name, now, nil, "token_" .. e.id))
		end
		return
	end
	for _, e in Events.List do
		for _, w in Events.Windows(e) do
			if w.endsAt > now and w.startsAt < untilAt then
				table.insert(
					out,
					entry("event", string.format("event:%s:%d", e.id, w.startsAt), e.name, w.startsAt, w.endsAt, "token_" .. e.id)
				)
			end
		end
	end
end

local function eggHunt(out, now: number, untilAt: number)
	local Cfg = Config.EggHunt
	local active = Config.Events.Active(now)
	if not active or active.id ~= Cfg.Event then
		return
	end
	local round, endsAt = EggHuntLogic.Round(now)
	local startsAt = endsAt - Cfg.RoundSeconds
	table.insert(out, entry("egghunt", "egghunt:" .. round, "Egg Hunt", startsAt, endsAt, "egg"))
	local eventEnds = active.endsAt
	if Config.Flags.ActiveEvent == Cfg.Event then
		eventEnds = nil -- forced on: no end date
	end
	if endsAt < untilAt and (eventEnds == nil or endsAt < eventEnds) then
		table.insert(out, entry("egghunt", "egghunt:" .. (round + 1), "Egg Hunt", endsAt, endsAt + Cfg.RoundSeconds, "egg"))
	end
end

local function pass(out, now: number, untilAt: number)
	for _, season in Config.Quests.Seasons do
		if season.endsAt > now and season.startsAt < untilAt then
			local name = string.format("Ranch Pass · %s", season.name)
			table.insert(out, entry("pass", "pass:" .. season.season, name, season.startsAt, season.endsAt, "star", "Quests"))
		end
	end
end

local function titans(out, now: number, untilAt: number)
	local T = Config.Titan
	for _, slot in T.Schedule do
		local endsAt = slot.startsAt + T.Duration
		if endsAt > now and slot.startsAt < untilAt then
			local def = T.Rotation[slot.rotation] or T.Rotation[1]
			local name = string.format("Titan · %s", def.name)
			table.insert(out, entry("titan", "titan:" .. slot.startsAt, name, slot.startsAt, endsAt, "item_totem_thunder"))
		end
	end
end

local function openings(out, now: number, untilAt: number)
	for _, r in Config.Regions.List do
		if r.opensAt and r.opensAt > now and r.opensAt < untilAt then
			local name = string.format("New region · %s", r.name)
			table.insert(out, entry("region", "region:" .. r.id, name, r.opensAt, nil, "stardust", "Expeditions"))
		end
	end
	for _, r in Config.Raids.List do
		if r.opensAt and r.opensAt > now and r.opensAt < untilAt then
			table.insert(out, entry("raid", "raid:" .. r.id, string.format("%s raid", r.name), r.opensAt, nil, "egg", "Raids"))
		end
	end
	local war = Config.Clubs.War.startsAt
	if war and war > now and war < untilAt then
		table.insert(out, entry("clubwars", "clubwars", "Club Wars", war, nil, "ribbon", "Clubs"))
	end
end

local function arena(out, now: number, untilAt: number)
	local season = ArenaLogic.SeasonAt(now)
	if season >= 1 then
		local name = string.format("Arena Season %d", season)
		local startsAt, endsAt = ArenaLogic.SeasonStartsAt(season), ArenaLogic.SeasonEndsAt(season)
		table.insert(out, entry("arena", "arena:" .. season, name, startsAt, endsAt, "trophy", "Arena", { tab = "season" }))
	end
	local nextSeason = season + 1
	local startsAt = ArenaLogic.SeasonStartsAt(nextSeason)
	if startsAt < untilAt then
		local name = string.format("Arena Season %d", nextSeason)
		table.insert(
			out,
			entry(
				"arena",
				"arena:" .. nextSeason,
				name,
				startsAt,
				ArenaLogic.SeasonEndsAt(nextSeason),
				"trophy",
				"Arena",
				{ tab = "season" }
			)
		)
	end
end

local function reset(out, now: number, untilAt: number)
	local L = Config.Leaderboards
	local week = L.Week(now)
	local at = L.WeekEndsAt(week)
	if at < untilAt then
		table.insert(out, entry("reset", "reset:" .. (week + 1), "Weekly reset", at, nil, "ribbon", "Leaderboards"))
	end
end

-- 3.11: the season running now and the next one (a season always lasts one week).
local function seasons(out, now: number, untilAt: number)
	for _, s in { SeasonsLogic.At(now), SeasonsLogic.Next(now) } do
		local def = Config.Seasons.ById[s.id]
		if s.endsAt > now and s.startsAt < untilAt then
			table.insert(out, entry("season", "season:" .. s.startsAt, def.name, s.startsAt, s.endsAt, "food_" .. def.flavor))
		end
	end
end

local function stampede(out, now: number, untilAt: number)
	local B = Config.Boss
	-- The first slot that has not ended yet: running when it started at or before `now`.
	local startsAt = TitanLogic.NextStampede(B, Config.Titan, now - B.Duration + 1)
	if startsAt < untilAt then
		table.insert(out, entry("stampede", "stampede:" .. startsAt, "Stampede", startsAt, startsAt + B.Duration, "trophy", "Boss"))
	end
end

local function merchant(out, now: number, untilAt: number)
	local at = MerchantLogic.At(now)
	local Cfg = Config.Merchant
	local name = "Travelling Merchant"
	if at.present then
		table.insert(out, entry("merchant", "merchant:" .. at.visit, name, at.startsAt, at.endsAt, "coin", "Merchant"))
	end
	local nextVisit = MerchantLogic.Visit(at.nextAt)
	if not at.present and at.nextAt < untilAt then
		table.insert(out, entry("merchant", "merchant:" .. nextVisit, name, at.nextAt, at.nextAt + Cfg.Stay, "coin", "Merchant"))
	end
end

-- API -----------------------------------------------------------------------------------

function Calendar.Entries(now: number, horizonSeconds: number)
	local untilAt = now + math.max(0, horizonSeconds)
	local out = {}
	events(out, now, untilAt)
	eggHunt(out, now, untilAt)
	pass(out, now, untilAt)
	titans(out, now, untilAt)
	openings(out, now, untilAt)
	arena(out, now, untilAt)
	reset(out, now, untilAt)
	seasons(out, now, untilAt)
	stampede(out, now, untilAt)
	merchant(out, now, untilAt)
	table.sort(out, before)
	return out
end

function Calendar.Now(now: number)
	local list = {}
	for _, e in Calendar.Entries(now, 0) do
		if running(e, now) then
			table.insert(list, e)
		end
	end
	return list
end

function Calendar.Soon(now: number, withinSeconds: number)
	local list = {}
	for _, e in Calendar.Entries(now, withinSeconds) do
		if e.startsAt > now and e.kind ~= "stampede" and e.kind ~= "egghunt" then
			table.insert(list, e)
		end
	end
	return list
end

function Calendar.Sections(now: number)
	local weekEnds = Config.Leaderboards.WeekEndsAt(Config.Leaderboards.Week(now))
	local laterEnds = now + Calendar.LaterSeconds
	local out = { now = {}, week = {}, later = {} }
	local seenBig = {}
	for _, e in Calendar.Entries(now, math.huge) do
		if running(e, now) then
			table.insert(out.now, e)
		elseif e.startsAt <= weekEnds then
			table.insert(out.week, e)
		elseif e.startsAt < laterEnds or (Calendar.BigKinds[e.kind] and not seenBig[e.kind]) then
			-- Past 30 days, only the next one of each big kind.
			table.insert(out.later, e)
		end
		if Calendar.BigKinds[e.kind] and not running(e, now) then
			seenBig[e.kind] = true
		end
	end
	return out
end

function Calendar.NextBig(now: number, withinSeconds: number, kinds: { [string]: boolean }?)
	local wanted = kinds or Calendar.ReminderKinds
	for _, e in Calendar.Entries(now, withinSeconds) do
		if wanted[e.kind] and e.startsAt > now then
			return e
		end
	end
	return nil
end

return Calendar
