--[[
	Workshop (update 3.0 · Year Two): accessories designed by players. Rules: Config/Workshop.

	Cross-server records (ctx.Services.Designs), one per design:
	  { id, creator, creatorName, name, shape, slot, color, color2, likes, copies,
	    earned, reports = { userId }, hidden, removed?, reviewed?, createdAt }
	`earned` counts the Royalty ribbons a design has made (stats). What a designer is owed sits
	in a per-designer ledger (Services.Designs.Owe / Collect, 3.0.1), so Workshop.Claim is one
	write however many designs they have.

	Budgets (3.0.1): design records and the Top / New id lists are cached on the server
	(Config.CacheSeconds / ListCacheSeconds); writes refresh the cache with what they wrote.

	Moderation (3.0.1): a design hidden by ReportsToHide reports joins the moderation feed
	(Services.Designs.Flag). Moderators (Config.Moderators user ids, or ModeratorGroup rank)
	see it in session.Workshop.queue and restore it (reports cleared) or remove it for good
	(`removed`, renamed "Removed design"; copies already bought keep working).

	Save section (profile.Workshop):
	  designs = { designId }                 -- this player's designs (newest last)
	  made    = { week, n }                  -- designs published this leaderboard week
	  copies  = { [designId] = { n, name, shape, slot, color, color2, creatorName } }  -- storage
	  liked   = { [designId] = true }
	  next                                   -- counter for this player's design ids
	Session (session.Workshop): { tab, gallery = { DesignView }, moderator, queue = { DesignView + reports } }
	  DesignView = { id, name, creatorName, shape, slot, color, color2, likes, copies, mine }

	Actions:
	  Workshop.Create { name, shape, color, color2 } -> { design }   -- publishes; 1 free copy
	  Workshop.Browse { tab = "top"|"new"|"mine" }                   -- fills session.gallery
	  Workshop.Like { design }       Workshop.Report { design }
	  Workshop.Buy { design }        -- a copy into storage for CopyPrice; the designer earns Royalty
	  Workshop.Equip { id, design }  -- a stored copy onto a monster (encoded acc id)
	  Workshop.Claim -> { ribbons }  -- royalties from your designs
	  Workshop.ModQueue              -- moderators: fills session.queue from the feed
	  Workshop.Moderate { design, verdict = "restore"|"remove" }
	Worn copies come back to storage through Accessories:Return ("ugc:" handler).
	Publishes DesignPublished (player, { design }), DesignBought (player, { design, creator }).
]]

local Workshop = {
	Name = "Workshop",
	Dependencies = { "Currency", "Progression", "Monsters", "Accessories", "Rewards" },
}

Workshop.Profile = {
	Version = 1,
	Default = function()
		return { designs = {}, made = { week = 0, n = 0 }, copies = {}, liked = {}, next = 1 }
	end,
}

local ctx
local Config -- Config.Workshop
local Acc -- Config.Accessories
local Currency, Progression, Monsters, Accessories, Rewards

local records = {} -- [designId] = { at, record } (server cache)
local lists = {} -- [tab] = { at, ids }

local function mustSection(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

local function service()
	local s = ctx.Services.Designs
	if not s then
		ctx:Fail("The Workshop is closed right now")
	end
	return s
end

local function week(): number
	return ctx.Config.Leaderboards.Week(ctx:Now())
end

-- Remembers a record just read or written.
local function remember(record)
	if type(record) == "table" and record.id then
		records[record.id] = { at = ctx:Now(), record = record }
	end
	return record
end

-- A design record, from the cache when it is at most `maxAge` seconds old.
local function fetch(id: string, maxAge: number?): (boolean, any)
	local hit = records[id]
	if hit and ctx:Now() - hit.at <= (maxAge or Config.CacheSeconds) then
		return true, hit.record
	end
	local ok, record = service().Get(id)
	if ok and type(record) == "table" then
		remember(record)
	end
	return ok, record
end

local function getDesign(id: string)
	local ok, record = fetch(id, -1) -- purchases always read fresh
	if not ok then
		ctx:Fail("The Workshop is busy. Try again in a moment")
	end
	if type(record) ~= "table" then
		ctx:Fail("That design doesn't exist")
	end
	return record
end

local function isModerator(player): boolean
	if table.find(Config.Moderators, player.UserId) then
		return true
	end
	local group = Config.ModeratorGroup
	if group.id ~= 0 and ctx.Services.Players.RankInGroup then
		return ctx.Services.Players.RankInGroup(player, group.id) >= group.minRank
	end
	return false
end

local function view(record, userId: number)
	return {
		id = record.id,
		name = record.name,
		creatorName = record.creatorName,
		shape = record.shape,
		slot = record.slot,
		color = record.color,
		color2 = record.color2,
		likes = record.likes or 0,
		copies = record.copies or 0,
		mine = record.creator == userId,
	}
end

local function storeCopy(player, s, record, n: number)
	local copy = s.copies[record.id]
	if not copy then
		copy = {
			n = 0,
			name = record.name,
			shape = record.shape,
			slot = record.slot,
			color = record.color,
			color2 = record.color2,
			creatorName = record.creatorName,
		}
		s.copies[record.id] = copy
	end
	copy.n = math.max(0, copy.n + n)
	ctx:Dirty(player, "copies", record.id)
end

-- A worn copy coming back from a monster (Accessories:Return, "ugc:" ids).
local function returnWorn(player, accessoryId: string)
	local s = ctx:Section(player)
	local d = Acc.Decode(accessoryId)
	if not s or not d then
		return
	end
	local copy = s.copies[d.design]
	if copy then
		copy.n += 1
		ctx:Dirty(player, "copies", d.design)
	else
		storeCopy(player, s, {
			id = d.design,
			name = "Custom accessory",
			shape = d.shape,
			slot = d.slot,
			color = d.color,
			color2 = d.color2,
			creatorName = "",
		}, 1)
	end
end

-- Actions ------------------------------------------------------------------------------

local function cleanName(player, text: string): string
	local trimmed = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
	trimmed = string.gsub(trimmed, "%s+", " ")
	local length = utf8.len(trimmed) or #trimmed
	if length < Config.NameMin or length > Config.NameMax then
		ctx:Fail(string.format("Names must be %d to %d characters", Config.NameMin, Config.NameMax))
	end
	local filtered = ctx.Services.Text.Filter(trimmed, player.UserId)
	if filtered == nil then
		ctx:Fail("Couldn't check that name. Try again")
	end
	if filtered ~= trimmed then
		ctx:Fail("That name isn't allowed")
	end
	return trimmed
end

local function create(player, payload)
	local s = mustSection(player)
	Progression:Require(player, Config.Unlock)
	local slot = Acc.ShapeSlots[payload.shape]
	if not slot then
		ctx:Fail("That shape isn't available")
	end
	if not table.find(Config.Palette, payload.color) or not table.find(Config.Palette, payload.color2) then
		ctx:Fail("Pick colours from the palette")
	end
	if s.made.week ~= week() then
		s.made = { week = week(), n = 0 }
	end
	if s.made.n >= Config.PerWeek then
		ctx:Fail(string.format("You can publish %d designs a week", Config.PerWeek))
	end
	local name = cleanName(player, payload.name)
	local svc = service()
	Currency:Charge(player, Config.SubmitCost, "workshop_design")
	local id = string.format("%dx%d", player.UserId, s.next)
	local record = {
		id = id,
		creator = player.UserId,
		creatorName = player.DisplayName or player.Name,
		name = name,
		shape = payload.shape,
		slot = slot,
		color = payload.color,
		color2 = payload.color2,
		likes = 0,
		copies = 0,
		earned = 0,
		reports = {},
		hidden = false,
		createdAt = ctx:Now(),
	}
	if not svc.Create(record) then
		-- Refund: nothing was published.
		for key, amount in Config.SubmitCost do
			Currency:Add(player, key, amount, "workshop_refund")
		end
		ctx:Fail("The Workshop is busy. Try again in a moment")
	end
	svc.Index(id, 0)
	remember(record)
	lists.new = nil
	s.next += 1
	s.made.n += 1
	table.insert(s.designs, id)
	while #s.designs > Config.MaxDesignsKept do
		table.remove(s.designs, 1)
	end
	storeCopy(player, s, record, 1)
	ctx:Dirty(player)
	ctx:RequestSave(player)
	ctx.Bus:Publish("DesignPublished", player, { design = id })
	return { design = id }
end

local function browse(player, tab: string)
	local s = mustSection(player)
	local svc = service()
	local ids
	if tab == "mine" then
		ids = {}
		for i = #s.designs, math.max(1, #s.designs - Config.GallerySize + 1), -1 do
			table.insert(ids, s.designs[i])
		end
	else
		local cached = lists[tab]
		if cached and ctx:Now() - cached.at <= Config.ListCacheSeconds then
			ids = cached.ids
		else
			local ok, list = (if tab == "top" then svc.Top else svc.Recent)(Config.GallerySize * 2)
			if not ok then
				ctx:Fail("The Workshop is busy. Try again in a moment")
			end
			ids = list
			lists[tab] = { at = ctx:Now(), ids = list }
		end
	end
	local gallery = {}
	for _, id in ids do
		if #gallery >= Config.GallerySize then
			break
		end
		local ok, record = fetch(id)
		if ok and type(record) == "table" and (not record.hidden or record.creator == player.UserId) then
			local v = view(record, player.UserId)
			v.liked = s.liked[id] == true
			table.insert(gallery, v)
		end
	end
	local sess = ctx:Session(player)
	sess.tab = tab
	sess.gallery = gallery
	ctx:DirtySession(player)
	return { count = #gallery }
end

local function patchView(player, record)
	local sess = ctx:Session(player)
	for i, v in sess.gallery or {} do
		if v.id == record.id then
			local nv = view(record, player.UserId)
			nv.liked = v.liked
			sess.gallery[i] = nv
			ctx:DirtySession(player)
			return nv
		end
	end
	return nil
end

local function like(player, id: string)
	local s = mustSection(player)
	if s.liked[id] then
		ctx:Fail("You already like that design")
	end
	local count = 0
	for _ in s.liked do
		count += 1
	end
	if count >= Config.MaxLiked then
		ctx:Fail("You've liked a lot of designs already!")
	end
	local svc = service()
	local ok, record = svc.Update(id, function(current)
		if type(current) ~= "table" then
			return nil
		end
		current.likes = (current.likes or 0) + 1
		return current
	end)
	if not ok or type(record) ~= "table" then
		ctx:Fail("That design doesn't exist")
	end
	remember(record)
	svc.Index(id, record.likes)
	s.liked[id] = true
	ctx:Dirty(player, "liked", id)
	local v = patchView(player, record)
	if v then
		v.liked = true
	end
	return { likes = record.likes }
end

local function report(player, id: string)
	local svc = service()
	local ok, record = svc.Update(id, function(current)
		if type(current) ~= "table" then
			return nil
		end
		current.reports = current.reports or {}
		if not table.find(current.reports, player.UserId) and #current.reports < 50 then
			table.insert(current.reports, player.UserId)
		end
		if #current.reports >= Config.ReportsToHide and not current.hidden then
			current.hidden = true
			current.flagged = true
		end
		return current
	end)
	if not ok or type(record) ~= "table" then
		ctx:Fail("That design doesn't exist")
	end
	remember(record)
	if record.flagged and not record.removed then
		svc.Flag(id)
	end
	-- Hide it from the reporter's gallery right away.
	local sess = ctx:Session(player)
	for i, v in sess.gallery or {} do
		if v.id == id then
			table.remove(sess.gallery, i)
			ctx:DirtySession(player)
			break
		end
	end
	return { hidden = record.hidden == true }
end

local function buy(player, id: string)
	local s = mustSection(player)
	Progression:Require(player, Config.Unlock)
	local record = getDesign(id)
	if record.hidden and record.creator ~= player.UserId then
		ctx:Fail("That design isn't available")
	end
	local copy = s.copies[id]
	if copy and copy.n >= Config.MaxCopies then
		ctx:Fail(string.format("You can keep %d copies of a design", Config.MaxCopies))
	end
	Currency:Charge(player, Config.CopyPrice, "workshop_copy")
	if record.removed then
		ctx:Fail("That design isn't available")
	end
	local royalty = if record.creator ~= player.UserId then Config.Royalty else 0
	local ok, updated = service().Update(id, function(current)
		if type(current) ~= "table" then
			return nil
		end
		current.copies = (current.copies or 0) + 1
		current.earned = (current.earned or 0) + royalty
		return current
	end)
	if not ok or type(updated) ~= "table" then
		for key, amount in Config.CopyPrice do
			Currency:Add(player, key, amount, "workshop_refund")
		end
		ctx:Fail("The Workshop is busy. Try again in a moment")
	end
	remember(updated)
	if royalty > 0 and not service().Owe(record.creator, royalty) then
		ctx:Log("royalty for %s not recorded (%d ribbons)", tostring(record.creator), royalty)
	end
	storeCopy(player, s, updated, 1)
	patchView(player, updated)
	ctx:RequestSave(player)
	ctx.Bus:Publish("DesignBought", player, { design = id, creator = record.creator })
	return { owned = s.copies[id].n }
end

local function equip(player, monsterId: string, id: string)
	local s = mustSection(player)
	Progression:Require(player, Config.Unlock)
	local copy = s.copies[id]
	if not copy or copy.n < 1 then
		ctx:Fail("You don't have a spare copy of that design")
	end
	local m = Monsters:Get(player, monsterId)
	if not m then
		ctx:Fail("That monster doesn't exist")
	end
	if m.busy == "trade" then
		ctx:Fail("That monster is in a trade")
	end
	copy.n -= 1
	ctx:Dirty(player, "copies", id)
	local encoded = Acc.Encode(id, copy.shape, copy.color, copy.color2)
	local previous = Monsters:SetAccessory(player, monsterId, copy.slot, encoded)
	Accessories:Return(player, previous)
	return { slot = copy.slot }
end

local function claim(player)
	mustSection(player)
	local ok, total = service().Collect(player.UserId)
	if not ok then
		ctx:Fail("The Workshop is busy. Try again in a moment")
	end
	if total > 0 then
		Rewards:Grant(player, { { kind = "ribbons", amount = total } }, "workshop_royalty")
		ctx:RequestSave(player)
	end
	return { ribbons = total }
end

-- Moderation ---------------------------------------------------------------------------

local function mustModerate(player)
	if not isModerator(player) then
		ctx:Fail("Only moderators can do that")
	end
end

local function modQueue(player)
	mustModerate(player)
	local svc = service()
	local ok, ids = svc.Flagged(Config.GallerySize)
	if not ok then
		ctx:Fail("The Workshop is busy. Try again in a moment")
	end
	local queue = {}
	for _, id in ids do
		local got, record = fetch(id, -1)
		if got and type(record) == "table" then
			local v = view(record, player.UserId)
			v.reports = #(record.reports or {})
			v.creatorId = record.creator
			table.insert(queue, v)
		end
	end
	local sess = ctx:Session(player)
	sess.queue = queue
	ctx:DirtySession(player)
	return { count = #queue }
end

local function moderate(player, id: string, verdict: string)
	mustModerate(player)
	local svc = service()
	local ok, record = svc.Update(id, function(current)
		if type(current) ~= "table" then
			return nil
		end
		current.flagged = false
		current.reviewed = true
		if verdict == "restore" then
			current.hidden = false
			current.reports = {}
		else
			current.hidden = true
			current.removed = true
			current.name = "Removed design"
		end
		return current
	end)
	if not ok or type(record) ~= "table" then
		ctx:Fail("That design doesn't exist")
	end
	remember(record)
	svc.Unflag(id)
	local sess = ctx:Session(player)
	for i, v in sess.queue or {} do
		if v.id == id then
			table.remove(sess.queue, i)
			ctx:DirtySession(player)
			break
		end
	end
	ctx:Log("design %s %s by moderator %d", id, verdict, player.UserId)
	return { verdict = verdict }
end

-- Lifecycle ----------------------------------------------------------------------------

function Workshop.Init(context)
	ctx = context
	Config = ctx.Config.Workshop
	Acc = ctx.Config.Accessories
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	Accessories = ctx:GetSystem("Accessories")
	Rewards = ctx:GetSystem("Rewards")
	table.clear(records)
	table.clear(lists)

	Accessories:RegisterReturn(Acc.UgcPrefix, returnWorn)

	ctx.Net:Handle("Workshop.Create", create)
	ctx.Net:Handle("Workshop.Browse", function(player, payload)
		return browse(player, payload.tab)
	end)
	ctx.Net:Handle("Workshop.Like", function(player, payload)
		return like(player, payload.design)
	end)
	ctx.Net:Handle("Workshop.Report", function(player, payload)
		return report(player, payload.design)
	end)
	ctx.Net:Handle("Workshop.Buy", function(player, payload)
		return buy(player, payload.design)
	end)
	ctx.Net:Handle("Workshop.Equip", function(player, payload)
		return equip(player, payload.id, payload.design)
	end)
	ctx.Net:Handle("Workshop.Claim", claim)
	ctx.Net:Handle("Workshop.ModQueue", modQueue)
	ctx.Net:Handle("Workshop.Moderate", function(player, payload)
		return moderate(player, payload.design, payload.verdict)
	end)
end

function Workshop.PlayerAdded(player)
	local sess = ctx:Session(player)
	sess.tab = "new"
	sess.gallery = {}
	sess.moderator = isModerator(player)
	sess.queue = {}
	ctx:DirtySession(player)
end

return Workshop
