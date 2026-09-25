--[[
	Seasonal events (design §18, event calendar). An event runs from `startsAt` to `endsAt`
	(unix seconds, Saturdays at 15:00 UTC with the weekly update). While it runs:
	  · items tagged `event = id` (eggs, decor, pen themes, species) are on sale / shown,
	  · `token` prices mean this event's token (Currency key "token.<id>"),
	  · players earn tokens by playing (Events.Earn, capped per UTC day),
	  · its event weather (Config.Weather entries with `event = id`) can roll, and
	    Weather.EventBoosts[id] multiplies other weather.

	reruns (update 3.0.1): later windows { startsAt, endsAt } for the same event. A returning
	event keeps its id, token and content, so everything tagged with it comes back. Events.Active
	and Events.Next return the event with the running (or next) window's startsAt / endsAt.

	Flags.ActiveEvent overrides the calendar: an event id forces that event, `false` turns
	events off, nil (default) follows the calendar. Everything reads the running event
	through Events.Active(now) / Events.ActiveId(now), so server and client always agree.
]]

local Flags = require(script.Parent.Flags)

local Events = {}

Events.List = {
	{
		id = "frostfall",
		name = "Frostfall",
		startsAt = 1797087600, -- Sat 12 Dec 2026, 15:00 UTC (launch)
		endsAt = 1799506800, -- Sat 9 Jan 2027
		token = { name = "Snowflakes", glyph = "❄", color = "#7CC7FF" },
		color = "#7CC7FF",
		reruns = {
			-- Year 2 (update 3.0.1): Frostfall returns with a fourth winter line (Tinselkit).
			{ startsAt = 1829142000, endsAt = 1831561200 }, -- Sat 18 Dec 2027 → Sat 15 Jan 2028
		},
	},
	{
		id = "lunarlanterns",
		name = "Lunar Lanterns",
		startsAt = 1801926000, -- Sat 6 Feb 2027, 15:00 UTC (update 1.2)
		endsAt = 1803740400, -- Sat 27 Feb 2027
		token = { name = "Lantern Coins", glyph = "✺", color = "#FF7A45" },
		color = "#E5484D",
		reruns = {
			-- Year 2 (update 3.1): Lunar Lanterns returns; Lanternwyrms can now grow into the
			-- Moonlit Dragon too.
			{ startsAt = 1833375600, endsAt = 1835190000 }, -- Sat 5 Feb 2028 → Sat 26 Feb 2028
		},
	},
	{
		id = "springbloom",
		name = "Spring Bloom",
		startsAt = 1806764400, -- Sat 3 Apr 2027, 15:00 UTC (update 1.4)
		endsAt = 1808578800, -- Sat 24 Apr 2027
		token = { name = "Petals", glyph = "✿", color = "#FF9EC7" },
		color = "#FF7AB6",
	},
	{
		id = "summersplash",
		name = "Summer Splash",
		startsAt = 1814626800, -- Sat 3 Jul 2027, 15:00 UTC (update 2.0)
		endsAt = 1818255600, -- Sat 14 Aug 2027
		token = { name = "Seashells", glyph = "❂", color = "#FFB347" },
		color = "#3FB6D9",
	},
	{
		id = "harvestmoon",
		name = "Harvest Moon",
		startsAt = 1822489200, -- Sat 2 Oct 2027, 15:00 UTC (update 2.1)
		endsAt = 1824908400, -- Sat 30 Oct 2027
		token = { name = "Moon Candy", glyph = "☾", color = "#F08A4B" },
		color = "#E0701F",
	},
}

-- Tokens earned by playing while an event runs (all capped by `dailyCap` per UTC day).
Events.Earn = {
	dailyLogin = 50, -- first join of each UTC day during the event
	bossJoined = 15, -- joining a Stampede
	expeditionPerHour = 10, -- per hour of expedition claimed (15 min → 2)
	stageFirstClear = 5, -- first clear of any stage
	hatch = 2, -- each egg hatched
	dailyCap = 300,
}

Events.ById = {}
for _, e in Events.List do
	Events.ById[e.id] = e
end

-- Every window of an event: its first run, then its reruns.
function Events.Windows(e)
	local list = { { startsAt = e.startsAt, endsAt = e.endsAt } }
	for _, w in e.reruns or {} do
		table.insert(list, { startsAt = w.startsAt, endsAt = w.endsAt })
	end
	return list
end

-- The event as seen in one window: the same definition with that window's dates.
local function inWindow(e, w)
	if w.startsAt == e.startsAt then
		return e
	end
	local view = table.clone(e)
	view.startsAt, view.endsAt = w.startsAt, w.endsAt
	return view
end

-- The running event's definition (with the running window's dates), or nil.
function Events.Active(now: number)
	local forced = Flags.ActiveEvent
	if forced == false then
		return nil
	elseif type(forced) == "string" then
		return Events.ById[forced]
	end
	for _, e in Events.List do
		for _, w in Events.Windows(e) do
			if now >= w.startsAt and now < w.endsAt then
				return inWindow(e, w)
			end
		end
	end
	return nil
end

function Events.ActiveId(now: number): string?
	local e = Events.Active(now)
	return if e then e.id else nil
end

-- The next event that has not started yet (for "coming soon" teasers), or nil.
function Events.Next(now: number)
	local best = nil
	for _, e in Events.List do
		for _, w in Events.Windows(e) do
			if w.startsAt > now and (best == nil or w.startsAt < best.startsAt) then
				best = inWindow(e, w)
			end
		end
	end
	return best
end

return Events
