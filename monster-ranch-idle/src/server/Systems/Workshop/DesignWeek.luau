--[[
	Design Week (R2, part of Workshop): a rotating theme (Config.Workshop.Themes, by
	`ctx.Config.Leaderboards.Week`), player entries and cross-server votes, and a once-only
	rollover that features the week's top `Winners` entries for sale the following week.

	Design record fields added (on top of Workshop/init.luau's shape):
	  weekEntry = { week, theme, votes, voters = { [tostring(userId)]: true }, enteredAt }
	           -- replaced whole each time the design is (re-)entered into a week
	  featured = week | nil          -- the week number it is sold as Featured
	  featuredNotified = boolean     -- the designer has been told (set once, any server)

	Entries are indexed cross-server by week (Services.Designs.EnterWeek / WeekEntries, a
	small id list per week key) so a "theme" gallery tab can list them; votes live on the
	design record itself and add up the same way Workshop's likes already do (Designs.Update).

	Save section additions (profile.Workshop):
	  designWeek = { week, entered = designId | false }         -- one entry per player per week
	  votesToday = { day, n }                                   -- daily vote budget

	Session addition (session.Workshop):
	  theme    = { id, name, endsAt, entered, votesLeft, entries = { EntryView } }
	  featured = { DesignView }   -- this week's Featured designs, buyable in the Gallery

	Rollover: once a week turns over, the previous week's entries are ranked by votes and the
	top `Config.Winners` get `featured = week + 1` via Services.Designs.Rollover (an atomic
	write keyed by week, so a second server running the same rollover is a no-op) -- see
	`finalize`. Notifying the designer only reaches them if they are online on the server that
	finalizes; `checkNotify` (run on PlayerAdded) catches every other case from the persisted
	`featuredNotified` flag, reusing ctx:Notify (there is no separate Mail/Notifications system
	to plug into).

	Actions: Workshop.Enter { design } -> { design, theme }
	         Workshop.Vote { design }  -> { votes }
	         Workshop.Theme            -> fills session.Workshop.theme + .featured
]]

local DesignWeek = {}

local ctx
local Config -- Config.Workshop
local host -- helpers from Workshop/init.luau

local entryLists = {} -- [week] = { at, ids } (small cache, like Workshop's Top/New lists)
local settled = {} -- [week] = true once this server saw that week's winners featured
local checking = false -- a timer check is in flight (it yields on the Designs store)

local function week(): number
	return ctx.Config.Leaderboards.Week(ctx:Now())
end

local function theme(wk: number)
	return Config.ThemeForWeek(wk)
end

local function weekEntries(wk: number): { string }
	local cached = entryLists[wk]
	if cached and ctx:Now() - cached.at <= Config.ListCacheSeconds then
		return cached.ids
	end
	local ok, ids = host.service().WeekEntries(wk)
	if not ok then
		ctx:Fail("The Workshop is busy. Try again in a moment")
	end
	entryLists[wk] = { at = ctx:Now(), ids = ids }
	return ids
end

local function entryView(record, player)
	return {
		id = record.id,
		name = record.name,
		creatorName = record.creatorName,
		shape = record.shape,
		slot = record.slot,
		color = record.color,
		color2 = record.color2,
		votes = record.weekEntry and record.weekEntry.votes or 0,
		mine = record.creator == player.UserId,
		voted = record.weekEntry ~= nil and record.weekEntry.voters ~= nil and record.weekEntry.voters[tostring(player.UserId)] == true,
	}
end

-- Actions ------------------------------------------------------------------------------

local function enter(player, id: string)
	local s = host.mustSection(player)
	host.Progression:Require(player, Config.Unlock)
	local wk = week()
	if s.designWeek.week ~= wk then
		s.designWeek = { week = wk, entered = false }
	end
	if s.designWeek.entered then
		ctx:Fail("You already entered this week's Design Week")
	end
	if not table.find(s.designs, id) then
		ctx:Fail("That design isn't yours")
	end
	local record = host.getDesign(id)
	if record.creator ~= player.UserId then
		ctx:Fail("That design isn't yours")
	end
	if record.hidden or record.removed then
		ctx:Fail("That design isn't available")
	end
	local t = theme(wk)
	local ok, updated = host.service().Update(id, function(current)
		if type(current) ~= "table" then
			return nil
		end
		current.weekEntry = { week = wk, theme = t.id, votes = 0, voters = {}, enteredAt = ctx:Now() }
		return current
	end)
	if not ok or type(updated) ~= "table" then
		ctx:Fail("The Workshop is busy. Try again in a moment")
	end
	host.remember(updated)
	host.service().EnterWeek(wk, id)
	entryLists[wk] = nil
	s.designWeek.entered = id
	ctx:Dirty(player, "designWeek")
	ctx:RequestSave(player)
	return { design = id, theme = t.id }
end

local function vote(player, id: string)
	local s = host.mustSection(player)
	local today = ctx:Day()
	if s.votesToday.day ~= today then
		s.votesToday = { day = today, n = 0 }
	end
	if s.votesToday.n >= Config.VotesPerDay then
		ctx:Fail("You've used today's votes. Come back tomorrow!")
	end
	local wk = week()
	local record = host.getDesign(id)
	if type(record.weekEntry) ~= "table" or record.weekEntry.week ~= wk then
		ctx:Fail("That design isn't entered this week")
	end
	if record.creator == player.UserId then
		ctx:Fail("You can't vote for your own design")
	end
	local key = tostring(player.UserId)
	if record.weekEntry.voters and record.weekEntry.voters[key] then
		ctx:Fail("You already voted for that design")
	end
	local ok, updated = host.service().Update(id, function(current)
		if type(current) ~= "table" or type(current.weekEntry) ~= "table" or current.weekEntry.week ~= wk then
			return nil
		end
		current.weekEntry.voters = current.weekEntry.voters or {}
		if current.weekEntry.voters[key] then
			return nil
		end
		current.weekEntry.voters[key] = true
		current.weekEntry.votes = (current.weekEntry.votes or 0) + 1
		return current
	end)
	if not ok or type(updated) ~= "table" or type(updated.weekEntry) ~= "table" then
		ctx:Fail("You already voted for that design")
	end
	host.remember(updated)
	s.votesToday.n += 1
	ctx:Dirty(player, "votesToday")
	return { votes = updated.weekEntry.votes }
end

local function browseTheme(player)
	local s = host.mustSection(player)
	local wk = week()
	local t = theme(wk)
	local entries = {}
	for _, id in weekEntries(wk) do
		local ok, record = host.fetch(id)
		if ok and type(record) == "table" and type(record.weekEntry) == "table" and record.weekEntry.week == wk and not record.hidden then
			table.insert(entries, entryView(record, player))
		end
	end
	table.sort(entries, function(a, b)
		if a.votes ~= b.votes then
			return a.votes > b.votes
		end
		return a.id < b.id
	end)
	local today = ctx:Day()
	local votesLeft = if s.votesToday.day == today then math.max(0, Config.VotesPerDay - s.votesToday.n) else Config.VotesPerDay
	local entered = if s.designWeek.week == wk then s.designWeek.entered else false

	local sess = ctx:Session(player)
	sess.theme = {
		id = t.id,
		name = t.name,
		endsAt = ctx.Config.Leaderboards.WeekEndsAt(wk),
		entered = entered,
		votesLeft = votesLeft,
		entries = entries,
	}
	sess.featured = host.featuredGallery(player, wk)
	ctx:DirtySession(player)
	return { count = #entries }
end

-- Rollover -------------------------------------------------------------------------------

-- Sets `featured = week + 1` on each winner that lacks it (idempotent: a server that crashed
-- between the rollover write and these updates is repaired by the next check anywhere), and
-- tells a designer who is online here.
local function feature(wk: number, winners: { string })
	for _, id in winners do
		local changed = false
		local uok, updated = host.service().Update(id, function(current)
			if type(current) ~= "table" or current.featured == wk + 1 then
				return nil
			end
			changed = true
			current.featured = wk + 1
			current.featuredNotified = false
			return current
		end)
		if uok and changed and type(updated) == "table" then
			host.remember(updated)
			local online = ctx:PlayerByUserId(updated.creator)
			if online then
				ctx:Notify(online, string.format('Your design "%s" was featured this week!', tostring(updated.name)), "success")
				host.service().Update(id, function(current)
					if type(current) ~= "table" or current.featuredNotified ~= false then
						return nil
					end
					current.featuredNotified = true
					return current
				end)
			end
		end
	end
end

-- Ranks a finished week's entries and features the top `Winners`, once (Services.Designs.Rollover
-- is an atomic write on a week key: a second call, on this or another server, is a no-op). A
-- week already rolled over (by any server) is read back from Results and only its featured
-- flags are made sure of; after that this server never looks at that week again.
local function finalize(wk: number)
	if wk < 0 or settled[wk] then
		return
	end
	local rok, result = host.service().Results(wk)
	if not rok then
		return
	end
	if type(result) == "table" and result.finalizedAt then
		feature(wk, result.winners or {})
		settled[wk] = true
		return
	end
	local ids = weekEntries(wk)
	local ranked = {}
	for _, id in ids do
		local ok, record = host.fetch(id, -1)
		if ok and type(record) == "table" and type(record.weekEntry) == "table" and record.weekEntry.week == wk and not record.removed then
			table.insert(ranked, { id = id, votes = record.weekEntry.votes or 0, enteredAt = record.weekEntry.enteredAt or 0 })
		end
	end
	table.sort(ranked, function(a, b)
		if a.votes ~= b.votes then
			return a.votes > b.votes
		end
		if a.enteredAt ~= b.enteredAt then
			return a.enteredAt < b.enteredAt
		end
		return a.id < b.id
	end)
	local winners = {}
	for i = 1, math.min(Config.Winners, #ranked) do
		table.insert(winners, ranked[i].id)
	end

	local applied = false
	local ok = host.service().Rollover(wk, function(current)
		if type(current) == "table" and current.finalizedAt then
			return nil -- already rolled over
		end
		applied = true
		return { week = wk, theme = theme(wk).id, winners = winners, finalizedAt = ctx:Now() }
	end)
	if not ok or not applied then
		return -- another server won the write: the next check reads its Results
	end
	feature(wk, winners)
	settled[wk] = true
	ctx:Log("design week %d rolled over: %d winner(s)", wk, #winners)
end

-- Tells a designer whose win they missed (offline, or on a different server) the first time
-- their Workshop session loads afterwards.
local function checkNotify(player, s)
	for i = #s.designs, math.max(1, #s.designs - 10), -1 do
		local id = s.designs[i]
		local ok, record = host.fetch(id, -1)
		if ok and type(record) == "table" and record.featured and record.featuredNotified == false then
			ctx:Notify(player, string.format('Your design "%s" was featured this week!', tostring(record.name)), "success")
			local uok, updated = host.service().Update(id, function(current)
				if type(current) ~= "table" or current.featuredNotified ~= false then
					return nil
				end
				current.featuredNotified = true
				return current
			end)
			if uok and type(updated) == "table" then
				host.remember(updated)
			end
		end
	end
end

-- Public ---------------------------------------------------------------------------------

-- Finalizes last week if nobody has yet (safe to call often; exposed for tests too).
function DesignWeek.Check()
	finalize(week() - 1)
end

function DesignWeek.PlayerAdded(player)
	local s = ctx:Section(player)
	if not s then
		return
	end
	local wk = week()
	if s.designWeek.week ~= wk then
		s.designWeek = { week = wk, entered = false }
	end
	checkNotify(player, s)
end

function DesignWeek.Init(context, helpers)
	ctx = context
	Config = ctx.Config.Workshop
	host = helpers
	table.clear(entryLists)
	table.clear(settled)
	checking = false

	ctx.Net:Handle("Workshop.Enter", function(player, payload)
		return enter(player, payload.design)
	end)
	ctx.Net:Handle("Workshop.Vote", function(player, payload)
		return vote(player, payload.design)
	end)
	ctx.Net:Handle("Workshop.Theme", browseTheme)

	-- The check yields on the Designs store, so it runs off the scheduler (Services.Spawn),
	-- one at a time; once last week is settled it costs nothing.
	ctx:Every(60, function()
		if checking or settled[week() - 1] then
			return
		end
		checking = true
		ctx.Services.Spawn(function()
			local ok, err = pcall(DesignWeek.Check)
			checking = false
			if not ok then
				ctx:Log("design week check failed: %s", tostring(err))
			end
		end)
	end)
end

return DesignWeek
