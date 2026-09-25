--[[
	Seasonal events (design §18, event calendar). An event runs from `startsAt` to `endsAt`
	(unix seconds, Saturdays at 15:00 UTC with the weekly update). While it runs:
	  · items tagged `event = id` (eggs, decor, pen themes, species) are on sale / shown,
	  · `token` prices mean this event's token (Currency key "token.<id>"),
	  · players earn tokens by playing (Events.Earn, capped per UTC day),
	  · its event weather (Config.Weather entries with `event = id`) can roll, and
	    Weather.EventBoosts[id] multiplies other weather.

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
	},
	{
		id = "lunarlanterns",
		name = "Lunar Lanterns",
		startsAt = 1801926000, -- Sat 6 Feb 2027, 15:00 UTC (update 1.2)
		endsAt = 1803740400, -- Sat 27 Feb 2027
		token = { name = "Lantern Coins", glyph = "✺", color = "#FF7A45" },
		color = "#E5484D",
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

-- The running event's definition, or nil.
function Events.Active(now: number)
	local forced = Flags.ActiveEvent
	if forced == false then
		return nil
	elseif type(forced) == "string" then
		return Events.ById[forced]
	end
	for _, e in Events.List do
		if now >= e.startsAt and now < e.endsAt then
			return e
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
		if e.startsAt > now and (best == nil or e.startsAt < best.startsAt) then
			best = e
		end
	end
	return best
end

return Events
