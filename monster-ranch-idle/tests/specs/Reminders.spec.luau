-- Glow-up Reminders: opt-in, planning on leave, the MemoryStore queue with leases, caps, and failing soft.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Reminders")

	local DAY = 86400
	local HOUR = 3600
	local START = 20003 * DAY + 10 * HOUR -- a Monday, 10:00 UTC
	local R = Config.Reminders

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Ranch", "LoginStreak", "Reminders" }

	local function deepCopy(v)
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	-- In-memory stand-in for the MemoryStore + Open Cloud adapter (Kernel/RemindersAdapter).
	local function fakeAdapter()
		local f = { maps = { queue = {}, caps = {} }, posts = {}, result = { true, 200 }, available = true, calls = 0 }
		function f.Available()
			f.calls += 1
			return f.available
		end
		function f.Put(map, key, value, sortKey, _ttl)
			f.maps[map][key] = { value = deepCopy(value), sortKey = sortKey }
			return true
		end
		function f.Remove(map, key)
			f.maps[map][key] = nil
			return true
		end
		function f.Update(map, key, transform, _ttl)
			local current = f.maps[map][key]
			local new = transform(if current then deepCopy(current.value) else nil)
			if new == nil then
				return true, nil
			end
			f.maps[map][key] = { value = deepCopy(new), sortKey = if current then current.sortKey else nil }
			return true, deepCopy(new)
		end
		function f.Due(map, upTo, limit)
			local rows = {}
			for key, entry in f.maps[map] do
				if entry.sortKey and entry.sortKey < upTo then
					table.insert(rows, { key = key, value = deepCopy(entry.value), sortKey = entry.sortKey })
				end
			end
			table.sort(rows, function(a, b)
				return a.sortKey < b.sortKey
			end)
			while #rows > limit do
				table.remove(rows)
			end
			return true, rows
		end
		function f.Post(url, body, secret)
			table.insert(f.posts, { url = url, body = body, secret = secret })
			if f.onPost then
				f.onPost()
			end
			return f.result[1], f.result[2]
		end
		function f.Country()
			return f.country
		end
		function f.UniverseId()
			return 4242
		end
		function f.JobId()
			return "job-a"
		end
		function f.count(map)
			local n = 0
			for _ in f.maps[map] do
				n += 1
			end
			return n
		end
		return f
	end

	local saved
	local function turnOn()
		saved = { secret = R.SecretName, templates = table.clone(R.Templates) }
		R.SecretName = "notify_key"
		for kind in R.Templates do
			R.Templates[kind] = "tpl-" .. kind
		end
	end
	local function turnOff()
		if saved then
			R.SecretName = saved.secret
			for kind, id in saved.templates do
				R.Templates[kind] = id
			end
			saved = nil
		end
	end

	local function boot(fake)
		local h = TestKernel.new({ systems = SYSTEMS, startTime = START })
		h.adapters.Reminders = fake
		return h
	end

	local function hatched(h, p)
		h.kernel.Bus:Publish("EggHatched", p, { id = "e1", egg = "meadow", rarity = 1, variant = 0 })
	end

	local function startExpedition(h, p, seconds: number)
		h.kernel.Bus:Publish("ExpeditionStarted", p, { slot = 1, duration = seconds })
	end

	describe("Reminders", function()
		it("stays off and never touches the adapter while the config is empty", function()
			local fake = fakeAdapter()
			local h = boot(fake)
			local p = h:Join()
			h:Call(p, "Reminders.SetOptIn", { on = true })
			startExpedition(h, p, 4 * HOUR)
			p = h:Rejoin(p, 60)
			hatched(h, p)
			expect(h:Client(p).session.Reminders.available).toBe(false)
			expect(h:Client(p).session.Reminders.prompt).toBe(false)
			h:Leave(p)
			h.adapters.advance(5 * HOUR)
			h:System("Reminders"):Poll()
			expect(fake.calls).toBe(0)
			expect(fake.count("queue")).toBe(0)
			expect(#fake.posts).toBe(0)
		end)

		it("asks for the opt-in once, after the first hatch of the second session", function()
			turnOn()
			local ok, err = pcall(function()
				local h = boot(fakeAdapter())
				local p = h:Join()
				hatched(h, p)
				expect(h:Client(p).session.Reminders.prompt).toBe(false)
				p = h:Rejoin(p, HOUR)
				expect(h:Client(p).session.Reminders.available).toBe(true)
				hatched(h, p)
				expect(h:Client(p).session.Reminders.prompt).toBe(true)
				h:Call(p, "Reminders.SetOptIn", { on = true })
				local client = h:Client(p)
				expect(client.session.Reminders.prompt).toBe(false)
				expect(client.profile.Reminders.asked).toBe(true)
				expect(client.profile.Reminders.on).toBe(true)
				expect(client.profile.Reminders.exp).toBeNil() -- private
				p = h:Rejoin(p, HOUR)
				hatched(h, p)
				expect(h:Client(p).session.Reminders.prompt).toBe(false)
			end)
			turnOff()
			assert(ok, err)
		end)

		it("plans reminders when an opted-in player leaves and clears them on return", function()
			turnOn()
			local ok, err = pcall(function()
				local fake = fakeAdapter()
				local h = boot(fake)
				local p = h:Join()
				h:Call(p, "Reminders.SetOptIn", { on = true })
				startExpedition(h, p, 4 * HOUR)
				h:Leave(p)
				local entry = fake.maps.queue["u" .. p.UserId .. ":expedition"]
				expect(entry ~= nil).toBe(true)
				expect(entry.sortKey).toBe(START + 4 * HOUR)
				expect(entry.value.u).toBe(p.UserId)
				p = h:Join(p.UserId, p.Name)
				expect(fake.count("queue")).toBe(0)
				-- Opted out: nothing is planned.
				h:Call(p, "Reminders.SetOptIn", { on = false })
				h:Leave(p)
				expect(fake.count("queue")).toBe(0)
			end)
			turnOff()
			assert(ok, err)
		end)

		it("sends a due reminder exactly once across two servers", function()
			turnOn()
			local ok, err = pcall(function()
				local fake = fakeAdapter()
				local h1 = boot(fake)
				local p = h1:Join()
				h1:Call(p, "Reminders.SetOptIn", { on = true })
				startExpedition(h1, p, 4 * HOUR)
				h1:Leave(p)
				local h2 = boot(fake)
				h1.adapters.advance(4 * HOUR + 60)
				h2.adapters.advance(4 * HOUR + 60)
				-- Server B polls while server A is in the middle of sending: the lease stops it.
				fake.onPost = function()
					fake.onPost = nil
					h2:System("Reminders"):Poll()
				end
				h1:System("Reminders"):Poll()
				expect(#fake.posts).toBe(1)
				local post = fake.posts[1]
				expect(post.url).toBe(string.format(R.Url, p.UserId))
				expect(post.secret).toBe("notify_key")
				-- The starter egg and the expedition are both due; the egg is sooner, and the
				-- expedition then waits out the gap between two reminders (and is dropped).
				expect(post.body.payload.message_id).toBe("tpl-egg")
				expect(post.body.payload.type).toBe("MOMENT")
				expect(post.body.source.universe).toBe("universes/4242")
				expect(fake.count("queue")).toBe(0)
				h2:System("Reminders"):Poll()
				expect(#fake.posts).toBe(1)
			end)
			turnOff()
			assert(ok, err)
		end)

		it("caps sends per player per day and retries a failed send", function()
			turnOn()
			local ok, err = pcall(function()
				local fake = fakeAdapter()
				local h = boot(fake)
				local now = START
				local function put(userId, kind, due)
					local value = { u = userId, kind = kind, exp = due + DAY, tries = 0, lease = 0 }
					fake.Put("queue", "u" .. userId .. ":" .. kind, value, due, DAY)
				end
				put(7, "egg", now - 10)
				put(7, "expedition", now - 5)
				h:System("Reminders"):Poll()
				expect(#fake.posts).toBe(1) -- the second is too soon after the first
				expect(fake.count("queue")).toBe(0)

				fake.result = { false, 503 }
				put(8, "egg", now - 10)
				h:System("Reminders"):Poll()
				expect(#fake.posts).toBe(2)
				expect(fake.maps.queue["u8:egg"].value.tries).toBe(1)
				expect(fake.maps.caps["u8"].value.n).toBe(0) -- refunded
				h:System("Reminders"):Poll() -- leased: not retried yet
				expect(#fake.posts).toBe(2)
				fake.result = { true, 200 }
				h.adapters.advance(R.LeaseSeconds + 1)
				h:System("Reminders"):Poll()
				expect(#fake.posts).toBe(3)
				expect(fake.count("queue")).toBe(0)

				-- A refused request (4xx) is dropped, not retried.
				fake.result = { false, 400 }
				put(9, "egg", now + R.LeaseSeconds)
				h:System("Reminders"):Poll()
				expect(fake.count("queue")).toBe(0)
			end)
			turnOff()
			assert(ok, err)
		end)

		it("fails soft when the adapter breaks or is missing", function()
			turnOn()
			local ok, err = pcall(function()
				local fake = fakeAdapter()
				local function boom()
					error("MemoryStore is down")
				end
				fake.Put, fake.Remove, fake.Due, fake.Update, fake.Country = boom, boom, boom, boom, boom
				local h = boot(fake)
				local p = h:Join()
				h:Call(p, "Reminders.SetOptIn", { on = true })
				startExpedition(h, p, 4 * HOUR)
				h:Leave(p)
				p = h:Join(p.UserId, p.Name)
				h.adapters.advance(5 * HOUR)
				h:System("Reminders"):Poll()
				h:Advance(R.PollSeconds + 1)
				fake.Available = boom
				expect(h:System("Reminders"):Enabled()).toBe(false)
				-- No adapter at all (Lune has no MemoryStore): still just off.
				local bare = TestKernel.new({ systems = SYSTEMS, startTime = START })
				local q = bare:Join()
				expect(bare:Client(q).session.Reminders.available).toBe(false)
				bare:Leave(q)
			end)
			turnOff()
			assert(ok, err)
		end)
	end)

	describe("Reminders logic", function()
		it("moves a reminder out of the quiet hours of a rough local time", function()
			local midnight = 20003 * DAY
			-- US (UTC-6): 05:00 UTC is 23:00 local → waits for 08:00 local (14:00 UTC).
			expect(Logic.Place(midnight + 5 * HOUR, midnight + DAY, midnight, -6)).toBe(midnight + 14 * HOUR)
			expect(Logic.Place(midnight + 16 * HOUR, midnight + DAY, midnight, -6)).toBe(midnight + 16 * HOUR)
			expect(Logic.Place(midnight + 5 * HOUR, midnight + DAY, midnight, nil)).toBe(midnight + 5 * HOUR)
			-- A streak ending before 08:00 local goes out just before 22:00 local instead.
			local placed = Logic.Place(midnight + 5 * HOUR, midnight + 6 * HOUR, midnight, -6)
			expect(placed).toBe(midnight + 4 * HOUR - 15 * 60)
			expect(Logic.Place(midnight + 5 * HOUR, midnight + 6 * HOUR, midnight + 4 * HOUR, -6)).toBeNil()
		end)

		it("plans the soonest reminders, never right after leaving", function()
			local now = START
			local plan = Logic.Plan({
				eggsReadyAt = now + 600,
				expeditionsBackAt = now + 8 * HOUR,
				stampede = true,
				streakDeadline = (20003 + 1) * DAY,
				templates = { egg = "a", expedition = "b", stampede = "c", streak = "" },
			}, now)
			expect(#plan).toBe(R.MaxPlanned)
			expect(plan[1].kind).toBe("egg")
			expect(plan[1].dueAt).toBe(now + R.MinAwaySeconds)
			for _, item in plan do
				expect(item.kind ~= "streak").toBe(true)
				expect(item.dueAt < item.expiresAt).toBe(true)
			end
			local streakOnly = Logic.Plan({ streakDeadline = (20003 + 1) * DAY, templates = { streak = "s" } }, now)
			expect(streakOnly[1].dueAt).toBe((20003 + 1) * DAY - R.Streak.hoursLeft * HOUR)
		end)

		it("allows a few reminders a day, spaced out", function()
			local now = START
			local ok1, r1 = Logic.Allow(nil, now)
			expect(ok1).toBe(true)
			local ok2 = Logic.Allow(r1, now + 60)
			expect(ok2).toBe(false)
			local ok3, r3 = Logic.Allow(r1, now + R.MinGapSeconds)
			expect(ok3).toBe(true)
			local ok4 = Logic.Allow(r3, now + 2 * R.MinGapSeconds)
			expect(ok4).toBe(R.MaxPerDay > 2)
			local okNext = Logic.Allow(r3, now + DAY)
			expect(okNext).toBe(true)
			expect(Logic.Refund(r3).n).toBe(1)
		end)
	end)
end
