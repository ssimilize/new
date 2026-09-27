--[[
	Calendar (update 3.8 · Reasons to come back): the events calendar's pure rules (Logic/Calendar)
	at fixed timestamps where known windows exist, the shared Stampede slot (Logic/Titan
	.NextStampede) against the Boss system's own schedule, and the "event" reminder.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local MockAdapters = t.MockAdapters
	local Config = t.Shared("Config")
	local Calendar = t.Shared("Logic.Calendar")
	local TitanLogic = t.Shared("Logic.Titan")
	local Arena = t.Shared("Logic.Arena")
	local Reminders = t.Shared("Logic.Reminders")

	local DAY = 86400
	local HOUR = 3600

	local FROSTFALL = Config.Events.ById.frostfall
	local SPRING = Config.Events.ById.springbloom
	local TITAN = Config.Titan.Schedule[1].startsAt
	local MIRAGE = Config.Regions.ById.dunes
	local IN_FROSTFALL = FROSTFALL.startsAt + 5 * DAY -- Thu 17 Dec 2026, 15:00 UTC

	local function byKind(list, kind: string)
		local out = {}
		for _, e in list do
			if e.kind == kind then
				table.insert(out, e)
			end
		end
		return out
	end

	local function keys(list)
		local out = {}
		for _, e in list do
			out[e.key] = e
		end
		return out
	end

	local function withFlag(value, fn)
		local saved = Config.Flags.ActiveEvent
		Config.Flags.ActiveEvent = value
		local ok, err = pcall(fn)
		Config.Flags.ActiveEvent = saved
		if not ok then
			error(err, 0)
		end
	end

	describe("Calendar.Entries", function()
		it("lists the running event, pass season, arena season and the Saturday reset during Frostfall", function()
			local list = Calendar.Entries(IN_FROSTFALL, 7 * DAY)
			local k = keys(list)
			local event = k["event:frostfall:" .. FROSTFALL.startsAt]
			expect(event ~= nil).toBe(true)
			expect(event.name).toBe("Frostfall")
			expect(event.endsAt).toBe(FROSTFALL.endsAt)
			expect(event.icon).toBe("token_frostfall")

			local pass = k["pass:1"]
			expect(pass ~= nil).toBe(true)
			expect(pass.name).toBe("Ranch Pass · Frostfall Ranch")
			expect(pass.screen).toBe("Quests")

			local season = Arena.SeasonAt(IN_FROSTFALL)
			expect(season).toBe(2)
			local arena = k["arena:2"]
			expect(arena ~= nil).toBe(true)
			expect(arena.endsAt).toBe(Arena.SeasonEndsAt(2))
			expect(arena.screen).toBe("Arena")

			local week = Config.Leaderboards.Week(IN_FROSTFALL)
			local reset = k["reset:" .. (week + 1)]
			expect(reset ~= nil).toBe(true)
			expect(reset.startsAt).toBe(Config.Leaderboards.WeekEndsAt(week))
			expect(reset.endsAt).toBe(nil)

			-- Nothing past the horizon, nothing already over.
			for _, e in list do
				expect(e.startsAt < IN_FROSTFALL + 7 * DAY).toBe(true)
				expect(e.endsAt == nil or e.endsAt > IN_FROSTFALL).toBe(true)
				expect(type(e.blurb)).toBe("string")
			end
			expect(#byKind(list, "egghunt")).toBe(0)
		end)

		it("shows titan invasions, region openings and reruns with their dates", function()
			local list = Calendar.Entries(TITAN - 3 * HOUR, DAY)
			local titan = byKind(list, "titan")[1]
			expect(titan ~= nil).toBe(true)
			expect(titan.startsAt).toBe(TITAN)
			expect(titan.endsAt).toBe(TITAN + Config.Titan.Duration)
			expect(titan.name).toBe("Titan · " .. Config.Titan.Rotation[Config.Titan.Schedule[1].rotation].name)

			local before = Calendar.Entries(MIRAGE.opensAt - 2 * DAY, 30 * DAY)
			local k = keys(before)
			local region = k["region:dunes"]
			expect(region ~= nil).toBe(true)
			expect(region.startsAt).toBe(MIRAGE.opensAt)
			expect(region.name).toBe("New region · Mirage Dunes")
			expect(region.screen).toBe("Expeditions")
			local rerun = FROSTFALL.reruns[1]
			expect(k["event:frostfall:" .. rerun.startsAt] ~= nil).toBe(true)
			-- Opened regions drop off.
			expect(keys(Calendar.Entries(MIRAGE.opensAt + 1, DAY))["region:dunes"]).toBe(nil)
		end)

		it("sorts by start, then by kind for the same moment", function()
			-- Year Two's pass season starts the moment Mirage Dunes opens.
			local list = Calendar.Entries(MIRAGE.opensAt - 2 * DAY, 30 * DAY)
			for i = 2, #list do
				expect(list[i - 1].startsAt <= list[i].startsAt).toBe(true)
			end
			local regionAt, passAt
			for i, e in list do
				if e.key == "region:dunes" then
					regionAt = i
				elseif e.kind == "pass" and e.startsAt == MIRAGE.opensAt then
					passAt = i
				end
			end
			expect(regionAt ~= nil and passAt ~= nil).toBe(true)
			expect(regionAt < passAt).toBe(true)
		end)

		it("has Egg Hunt rounds only while Spring Bloom runs", function()
			local inBloom = SPRING.startsAt + HOUR + 60
			local rounds = byKind(Calendar.Entries(inBloom, DAY), "egghunt")
			expect(#rounds).toBe(2)
			local round, endsAt = t.Shared("Logic.EggHunt").Round(inBloom)
			expect(rounds[1].key).toBe("egghunt:" .. round)
			expect(rounds[1].endsAt).toBe(endsAt)
			expect(rounds[2].startsAt).toBe(endsAt)
			expect(#byKind(Calendar.Entries(IN_FROSTFALL, DAY), "egghunt")).toBe(0)
			expect(#byKind(Calendar.Entries(SPRING.startsAt - HOUR, DAY), "egghunt")).toBe(0)
			expect(#byKind(Calendar.Entries(SPRING.endsAt + HOUR, DAY), "egghunt")).toBe(0)
		end)

		it("follows Flags.ActiveEvent like Events.Active", function()
			withFlag(false, function()
				local list = Calendar.Entries(IN_FROSTFALL, 400 * DAY)
				expect(#byKind(list, "event")).toBe(0)
				expect(#byKind(list, "egghunt")).toBe(0)
			end)
			withFlag("springbloom", function()
				local events = byKind(Calendar.Entries(IN_FROSTFALL, 400 * DAY), "event")
				expect(#events).toBe(1)
				expect(events[1].name).toBe("Spring Bloom")
				expect(events[1].endsAt).toBe(nil)
				expect(#byKind(Calendar.Now(IN_FROSTFALL), "event")).toBe(1)
				expect(#byKind(Calendar.Entries(IN_FROSTFALL, DAY), "egghunt")).toBe(2)
			end)
		end)
	end)

	describe("Now, Soon and Sections", function()
		it("Now lists what runs with its end; Soon skips running things, the Stampede and egg rounds", function()
			local now = Calendar.Now(IN_FROSTFALL)
			local k = keys(now)
			expect(k["event:frostfall:" .. FROSTFALL.startsAt] ~= nil).toBe(true)
			expect(k["pass:1"] ~= nil).toBe(true)
			expect(k["arena:2"] ~= nil).toBe(true)
			for _, e in now do
				expect(e.startsAt <= IN_FROSTFALL).toBe(true)
			end

			local at = TITAN - 3 * HOUR
			local soon = Calendar.Soon(at, DAY)
			local titan = byKind(soon, "titan")[1]
			expect(titan ~= nil).toBe(true)
			expect(titan.startsAt).toBe(TITAN)
			for _, e in soon do
				expect(e.startsAt > at).toBe(true)
				expect(e.kind ~= "stampede").toBe(true)
				expect(e.kind ~= "egghunt").toBe(true)
			end
			expect(#byKind(Calendar.Entries(at, DAY), "stampede")).toBe(1)
			-- Out of range: nothing titan-shaped a week before.
			expect(#byKind(Calendar.Soon(TITAN - 7 * DAY, DAY), "titan")).toBe(0)
			expect(#byKind(Calendar.Soon(SPRING.startsAt + HOUR, DAY), "egghunt")).toBe(0)
		end)

		it("splits the screen's sections at the Saturday reset and keeps far big dates", function()
			local at = 1790000000 -- a Thursday in Sept 2026, before arena season 1
			local s = Calendar.Sections(at)
			-- 3.11: the Ranch Season is always running (the week of `at` is summer); the next one
			-- starts at the reset.
			expect(#s.now).toBe(1)
			expect(s.now[1].kind).toBe("season")
			expect(s.now[1].name).toBe("Summer")
			expect(#byKind(s.week, "season")).toBe(1)
			local resetAt = Config.Leaderboards.WeekEndsAt(Config.Leaderboards.Week(at))
			expect(keys(s.week)["reset:1"] ~= nil).toBe(true)
			expect(#byKind(s.week, "stampede")).toBe(1)
			for _, e in s.week do
				expect(e.startsAt <= resetAt).toBe(true)
			end
			local later = keys(s.later)
			expect(later["arena:1"] ~= nil).toBe(true)
			expect(later["arena:2"]).toBe(nil) -- a recurring kind past 30 days is left out
			-- One of each big kind however far: the next event, titan and region.
			expect(#byKind(s.later, "event")).toBe(1)
			expect(later["event:frostfall:" .. FROSTFALL.startsAt] ~= nil).toBe(true)
			expect(#byKind(s.later, "titan")).toBe(1)
			expect(later["titan:" .. TITAN] ~= nil).toBe(true)
			expect(#byKind(s.later, "region")).toBe(1)
			expect(later["region:dunes"] ~= nil).toBe(true)
			expect(#byKind(s.later, "pass")).toBe(1)
		end)

		it("NextBig finds the next titan, event or region for the reminder", function()
			local big = Calendar.NextBig(TITAN - 5 * HOUR, DAY)
			expect(big ~= nil).toBe(true)
			expect(big.kind).toBe("titan")
			expect(Calendar.NextBig(1790000000, 14 * DAY)).toBe(nil)
		end)
	end)

	describe("the Stampede slot", function()
		it("matches the Boss system's schedule, titan skip included", function()
			local Boss = Config.Boss
			local T = Config.Titan
			local boot = TITAN - T.LobbySeconds - 50
			local h = TestKernel.new({
				systems = { "Currency", "Progression", "Rewards", "Monsters", "Expeditions", "Titan", "Boss" },
				network = MockAdapters.network(),
				startTime = boot,
				stubs = { Eggs = {
					Add = function()
						return {}
					end,
				} },
			})
			local startsAt = h:System("Boss"):State().startsAt
			expect(startsAt).toBe(TitanLogic.NextStampede(Boss, T, boot))
			expect(startsAt > math.ceil(boot / Boss.Period) * Boss.Period).toBe(true) -- a slot was skipped
			expect(TitanLogic.HoldsStampede(Boss, T, startsAt)).toBe(false)
			expect(byKind(Calendar.Entries(boot, DAY), "stampede")[1].startsAt).toBe(startsAt)

			-- Away from a titan the slot is the plain clock.
			local plain = 1790000000
			expect(TitanLogic.NextStampede(Boss, T, plain)).toBe(math.ceil(plain / Boss.Period) * Boss.Period)
			expect(TitanLogic.NextStampede(Boss, nil, boot)).toBe(math.ceil(boot / Boss.Period) * Boss.Period)
		end)

		it("shows a running Stampede in Now until it ends", function()
			local slot = math.ceil(1790000000 / Config.Boss.Period) * Config.Boss.Period
			local now = Calendar.Now(slot + 30)
			local fight = byKind(now, "stampede")[1]
			expect(fight ~= nil).toBe(true)
			expect(fight.startsAt).toBe(slot)
			expect(fight.endsAt).toBe(slot + Config.Boss.Duration)
			expect(#byKind(Calendar.Now(slot + Config.Boss.Duration), "stampede")).toBe(0)
		end)
	end)

	describe("the event reminder", function()
		local templates = { egg = "e", expedition = "x", stampede = "s", streak = "k", event = "v" }

		it("is a Config.Reminders kind with an empty template id", function()
			expect(table.find(Config.Reminders.Kinds, "event") ~= nil).toBe(true)
			expect(Config.Reminders.Templates.event).toBe("")
		end)

		it("plans a nudge 30 minutes before the start, and none once too close", function()
			local now = 1790000000
			local lead = Config.Reminders.Event.leadSeconds
			expect(lead).toBe(30 * 60)
			local plan = Reminders.Plan({ eventAt = now + 3 * HOUR, templates = templates }, now)
			expect(#plan).toBe(1)
			expect(plan[1].kind).toBe("event")
			expect(plan[1].dueAt).toBe(now + 3 * HOUR - lead)
			expect(plan[1].expiresAt).toBe(now + 3 * HOUR)
			expect(#Reminders.Plan({ eventAt = now + 40 * 60, templates = templates }, now)).toBe(0)
			-- Off while its template id is empty (the shipped config).
			expect(#Reminders.Plan({ eventAt = now + 3 * HOUR }, now)).toBe(0)
		end)

		it("gets the next titan from the Reminders system's facts", function()
			local R = Config.Reminders
			local saved = R.Templates.event
			R.Templates.event = "tpl-event"
			local ok, err = pcall(function()
				local h = TestKernel.new({
					systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Ranch", "LoginStreak", "Reminders" },
					startTime = TITAN - 5 * HOUR,
				})
				local p = h:Join()
				local plan = h:System("Reminders"):Plan(p)
				local event
				for _, item in plan do
					if item.kind == "event" then
						event = item
					end
				end
				expect(event ~= nil).toBe(true)
				expect(event.dueAt).toBe(TITAN - R.Event.leadSeconds)
				expect(event.expiresAt).toBe(TITAN)
			end)
			R.Templates.event = saved
			if not ok then
				error(err, 0)
			end
		end)
	end)
end
