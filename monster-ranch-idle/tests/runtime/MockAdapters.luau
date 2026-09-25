--[[
	MockAdapters: an in-memory replacement for src/server/Kernel/Adapters.luau.
	Time is manual, DataStore writes are deep-copied (so non-serializable data is caught),
	and every outward call is recorded so tests can assert on it.
]]

local MockAdapters = {}

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		assert(type(k) == "string" or type(k) == "number", "non-serializable key type: " .. type(k))
		assert(type(x) ~= "function", "functions cannot be saved or sent: key " .. tostring(k))
		out[k] = deepCopy(x)
	end
	return out
end
MockAdapters.deepCopy = deepCopy

--[[
	options.network: a table shared by several MockAdapters to act as one Roblox universe
	(tests for cross-server features create it with MockAdapters.network()). It carries the
	club store and MessagingService subscribers.
]]
local jobCounter = 0

function MockAdapters.network()
	return {
		clubs = {},
		subscribers = {},
		clubsDown = false,
		clubWars = {}, -- [week] = { [clubId] = points } (3.1)
		market = { listings = {}, mail = {} }, -- listings[id] = record (item included)
		prices = {}, -- price history records by item key
		marketDown = false,
		arena = {}, -- Arena records by userId (2.1)
		arenaDown = false,
		hubBoard = {}, -- Trade Board ads by id (3.0)
		hubDown = false,
		teleports = {}, -- { { userId, placeId, jobId? } } in call order (3.0)
		placesDown = false, -- fail Places.List (3.0.1)
		designs = {}, -- Workshop design records by id (3.0)
		designFeed = {}, -- design ids, newest first
		royalties = {}, -- [userId] = ribbons owed (3.0.1)
		reported = {}, -- design ids hidden by reports, oldest first (3.0.1)
		designReads = 0, -- Designs.Get calls, to check caching (3.0.1)
		designsDown = false,
	}
end

function MockAdapters.new(options: { startTime: number?, network: any?, placeMode: string? }?)
	local opts = options or {}
	local network = opts.network or MockAdapters.network()
	local now = opts.startTime or 1790000000 -- a Thursday in Sept 2026 (UTC)
	local precise = 0

	local a = {}
	a.log = { kicks = {}, events = {}, states = {}, analytics = {}, published = {}, ads = {} }
	jobCounter += 1
	a.JobId = "test-job-" .. tostring(jobCounter)
	a.PlaceId = 0
	a.PlaceMode = opts.placeMode -- "hub" runs this server as the Trading Hub (3.0)
	a.IsStudio = false
	a.OfflineMaxSeconds = 7 * 24 * 3600

	a.Clock = {
		Now = function()
			return math.floor(now)
		end,
		Precise = function()
			return precise
		end,
		-- Unfloored unix time; the client harness uses it as workspace:GetServerTimeNow().
		Unix = function()
			return now
		end,
	}
	-- Client harnesses register here to receive events and state as they are sent.
	a.clients = {}
	function a.advance(seconds: number)
		-- Rounded to microseconds so many small frame steps add up exactly (0.1 × 10 = 1).
		now = math.floor((now + seconds) * 1e6 + 0.5) / 1e6
		precise = math.floor((precise + seconds) * 1e6 + 0.5) / 1e6
	end
	function a.setTime(unix: number)
		now = unix
	end
	a.Seed = function()
		return 1234567
	end
	a.Wait = function(_seconds) end
	a.Spawn = function(fn, ...)
		fn(...)
	end
	a._step = nil
	a.OnStep = function(fn)
		a._step = fn
	end
	a._close = nil
	a.BindToClose = function(fn)
		a._close = fn
	end

	-- Players
	a._onAdded, a._onRemoving = nil, nil
	a.friends = {} -- [userId] = { [userId] = true }
	a.groups = {} -- [userId] = { [groupId] = true }
	a.ranks = {} -- [userId] = { [groupId] = rank } (3.0.1)
	a.Players = {
		OnAdded = function(fn)
			a._onAdded = fn
		end,
		OnRemoving = function(fn)
			a._onRemoving = fn
		end,
		GetPlayers = function()
			return {}
		end,
		Kick = function(player, message)
			player.kicked = message
			table.insert(a.log.kicks, { player = player, message = message })
		end,
		IsFriendsWith = function(player, userId)
			local f = a.friends[player.UserId]
			return f ~= nil and f[userId] == true
		end,
		IsInGroup = function(player, groupId)
			local g = a.groups[player.UserId]
			return g ~= nil and g[groupId] == true
		end,
		RankInGroup = function(player, groupId)
			local r = a.ranks[player.UserId]
			return r and r[groupId] or 0
		end,
		NameOf = function(userId)
			return a.names[userId]
		end,
	}
	a.names = {} -- [userId] = name, for players who are not on the server

	-- Global leaderboards: boards[key][userId] = value. Set a.leaderboardsDown to fail calls.
	a.boards = {}
	a.leaderboardsDown = false
	a.Leaderboards = {
		Submit = function(key, userId, value)
			if a.leaderboardsDown then
				return false
			end
			assert(value == math.floor(value), "leaderboard values must be whole numbers")
			a.boards[key] = a.boards[key] or {}
			a.boards[key][userId] = value
			return true
		end,
		Top = function(key, count)
			if a.leaderboardsDown then
				return nil
			end
			local list = {}
			for userId, value in a.boards[key] or {} do
				table.insert(list, { userId = userId, value = value })
			end
			table.sort(list, function(x, y)
				if x.value ~= y.value then
					return x.value > y.value
				end
				return x.userId < y.userId
			end)
			while #list > count do
				table.remove(list)
			end
			return list
		end,
	}

	-- Transport
	a._onRequest = nil
	a.Transport = {
		OnRequest = function(_, fn)
			a._onRequest = fn
		end,
		Fire = function(_, player, name, payload)
			local list = a.log.events[player]
			if not list then
				list = {}
				a.log.events[player] = list
			end
			table.insert(list, { name = name, payload = deepCopy(payload) })
			local client = a.clients[player]
			if client then
				client("event", name, deepCopy(payload))
			end
		end,
		SendState = function(_, player, message)
			local list = a.log.states[player]
			if not list then
				list = {}
				a.log.states[player] = list
			end
			table.insert(list, deepCopy(message))
			local client = a.clients[player]
			if client then
				client("state", deepCopy(message))
			end
		end,
	}

	-- DataStore
	a.store = {}
	a.failNextUpdates = 0
	a.DataStore = {
		Update = function(_, key, transform)
			if a.failNextUpdates > 0 then
				a.failNextUpdates -= 1
				return false, "simulated DataStore failure"
			end
			local current = deepCopy(a.store[key])
			local result = transform(current)
			if result ~= nil then
				a.store[key] = deepCopy(result)
			end
			return true, deepCopy(result)
		end,
	}

	-- Marketplace
	a.ownedPasses = {} -- [userId] = { [gamePassId] = true }
	a.Marketplace = {
		OwnsPass = function(player, id)
			local owned = a.ownedPasses[player.UserId]
			return owned ~= nil and owned[id] == true
		end,
		SetProcessReceipt = function(fn)
			a._processReceipt = fn
		end,
		OnPassPurchased = function(fn)
			a._onPassPurchased = fn
		end,
		PurchaseGranted = "PurchaseGranted",
		NotProcessedYet = "NotProcessedYet",
	}

	a.restrictedPaidRandom = {} -- [userId] = true
	a.Policy = {
		PaidRandomItemsAllowed = function(player)
			return not a.restrictedPaidRandom[player.UserId]
		end,
	}

	a.adResult = true
	a.Ads = {
		ShowRewarded = function(player, placement)
			table.insert(a.log.ads, { player = player, placement = placement })
			return a.adResult
		end,
	}

	a._subscribers = network.subscribers -- shared across servers on the same network
	a.Messaging = {
		Publish = function(topic, data)
			table.insert(a.log.published, { topic = topic, data = deepCopy(data) })
			for _, fn in a._subscribers[topic] or {} do
				fn(deepCopy(data))
			end
		end,
		Subscribe = function(topic, fn)
			a._subscribers[topic] = a._subscribers[topic] or {}
			table.insert(a._subscribers[topic], fn)
		end,
	}

	-- Clubs store (shared through options.network). Set network.clubsDown to fail calls.
	a.network = network
	a.Clubs = {
		Get = function(id)
			if network.clubsDown then
				return false, nil
			end
			return true, deepCopy(network.clubs[id])
		end,
		Update = function(id, transform)
			if network.clubsDown then
				return false, nil
			end
			local result = transform(deepCopy(network.clubs[id]))
			if result ~= nil then
				network.clubs[id] = deepCopy(result)
			end
			return true, deepCopy(result)
		end,
		IndexWar = function(week, id, points)
			if network.clubsDown then
				return false
			end
			network.clubWars[week] = network.clubWars[week] or {}
			network.clubWars[week][id] = math.floor(points)
			return true
		end,
		TopWar = function(week, count)
			if network.clubsDown then
				return false, {}
			end
			local rows = {}
			for id, points in network.clubWars[week] or {} do
				table.insert(rows, { id = id, points = points })
			end
			table.sort(rows, function(x, y)
				if x.points ~= y.points then
					return x.points > y.points
				end
				return x.id < y.id
			end)
			while #rows > count do
				table.remove(rows)
			end
			return true, rows
		end,
	}

	-- Arena (2.1), shared through options.network; network.arenaDown fails every call.
	network.arena = network.arena or {}
	a.Arena = {
		Get = function(userId)
			if network.arenaDown then
				return false, nil
			end
			return true, deepCopy(network.arena[userId])
		end,
		Update = function(userId, transform)
			if network.arenaDown then
				return false, nil
			end
			local result = transform(deepCopy(network.arena[userId]))
			if result ~= nil then
				network.arena[userId] = deepCopy(result)
			end
			return true, deepCopy(result)
		end,
		Index = function(_userId, _rating)
			return not network.arenaDown
		end,
		Near = function(rating, window, count)
			if network.arenaDown then
				return false, {}
			end
			local list = {}
			for userId, record in network.arena do
				if record.team and math.abs((record.rating or 0) - rating) <= window then
					table.insert(list, { userId = userId, rating = record.rating })
				end
			end
			table.sort(list, function(x, y)
				return x.userId < y.userId
			end)
			while #list > count do
				table.remove(list)
			end
			return true, list
		end,
	}

	-- Trading Hub (3.0): the Trade Board and teleports, shared through options.network.
	-- Teleports are only recorded; set network.hubDown to fail the board.
	a.Teleport = {
		ToPlace = function(player, placeId)
			table.insert(network.teleports, { userId = player.UserId, placeId = placeId })
			return true, nil
		end,
		ToServer = function(player, placeId, jobId)
			table.insert(network.teleports, { userId = player.UserId, placeId = placeId, jobId = jobId })
			return true, nil
		end,
	}
	-- The universe's places (3.0.1). Tests fill a.places with { name, placeId }.
	a.places = {}
	a.Places = {
		List = function()
			if network.placesDown then
				return false, {}
			end
			return true, deepCopy(a.places)
		end,
	}
	a.HubBoard = {
		Post = function(ad, ttl)
			if network.hubDown then
				return false
			end
			local copy = deepCopy(ad)
			copy._expires = now + ttl
			network.hubBoard[ad.id] = copy
			return true
		end,
		Remove = function(id)
			if network.hubDown then
				return false
			end
			network.hubBoard[id] = nil
			return true
		end,
		List = function(limit)
			if network.hubDown then
				return false, {}
			end
			local list = {}
			for id, ad in network.hubBoard do
				if ad._expires > now then
					local copy = deepCopy(ad)
					copy._expires = nil
					table.insert(list, copy)
				else
					network.hubBoard[id] = nil
				end
			end
			table.sort(list, function(x, y)
				if x.postedAt ~= y.postedAt then
					return x.postedAt > y.postedAt
				end
				return x.id < y.id
			end)
			while #list > limit do
				table.remove(list)
			end
			return true, list
		end,
	}

	-- Workshop designs (3.0), shared through options.network; designsDown fails every call.
	a.Designs = {
		Create = function(record)
			if network.designsDown or network.designs[record.id] ~= nil then
				return false
			end
			network.designs[record.id] = deepCopy(record)
			table.insert(network.designFeed, 1, record.id)
			return true
		end,
		Get = function(id)
			if network.designsDown then
				return false, nil
			end
			network.designReads += 1
			return true, deepCopy(network.designs[id])
		end,
		Owe = function(userId, amount)
			if network.designsDown then
				return false
			end
			network.royalties[userId] = (network.royalties[userId] or 0) + amount
			return true
		end,
		Collect = function(userId)
			if network.designsDown then
				return false, 0
			end
			local owed = network.royalties[userId] or 0
			network.royalties[userId] = nil
			return true, owed
		end,
		Flag = function(id)
			if network.designsDown then
				return false
			end
			if not table.find(network.reported, id) then
				table.insert(network.reported, id)
			end
			return true
		end,
		Unflag = function(id)
			if network.designsDown then
				return false
			end
			local at = table.find(network.reported, id)
			if at then
				table.remove(network.reported, at)
			end
			return true
		end,
		Flagged = function(count)
			if network.designsDown then
				return false, {}
			end
			local ids = {}
			for i = 1, math.min(count, #network.reported) do
				ids[i] = network.reported[i]
			end
			return true, ids
		end,
		Update = function(id, transform)
			if network.designsDown then
				return false, nil
			end
			local result = transform(deepCopy(network.designs[id]))
			if result ~= nil then
				network.designs[id] = deepCopy(result)
			end
			return true, deepCopy(result)
		end,
		Index = function(_id, _likes)
			return not network.designsDown
		end,
		Top = function(count)
			if network.designsDown then
				return false, {}
			end
			local list = {}
			for id, record in network.designs do
				table.insert(list, { id = id, likes = record.likes or 0 })
			end
			table.sort(list, function(x, y)
				if x.likes ~= y.likes then
					return x.likes > y.likes
				end
				return x.id < y.id
			end)
			local ids = {}
			for i = 1, math.min(count, #list) do
				ids[i] = list[i].id
			end
			return true, ids
		end,
		Recent = function(count)
			if network.designsDown then
				return false, {}
			end
			local ids = {}
			for i = 1, math.min(count, #network.designFeed) do
				ids[i] = network.designFeed[i]
			end
			return true, ids
		end,
	}

	-- Market and price history (shared through options.network). Set network.marketDown to
	-- fail every call. Browse returns open listings only, like the MemoryStore index.
	local market = network.market
	local function marketUp()
		return not network.marketDown
	end
	a.Market = {
		Create = function(listing)
			if not marketUp() or market.listings[listing.id] ~= nil then
				return false
			end
			market.listings[listing.id] = deepCopy(listing)
			return true
		end,
		Get = function(id)
			if not marketUp() then
				return false, nil
			end
			return true, deepCopy(market.listings[id])
		end,
		Update = function(id, transform)
			if not marketUp() then
				return false, nil
			end
			local result = transform(deepCopy(market.listings[id]))
			if result ~= nil then
				market.listings[id] = deepCopy(result)
			end
			return true, deepCopy(result)
		end,
		Browse = function(query)
			if not marketUp() then
				return false, nil
			end
			local scope = query.scope or "all"
			local list = {}
			for _, l in market.listings do
				local inScope = if scope == "all" then not l.club else l.club == scope
				if
					l.state == "open"
					and inScope
					and (query.kind == nil or l.kind == query.kind)
					and (query.key == nil or l.key == query.key)
				then
					local copy = deepCopy(l)
					copy.item = nil
					table.insert(list, copy)
				end
			end
			table.sort(list, function(x, y)
				if x.price ~= y.price then
					return if query.sort == "-price" then x.price > y.price else x.price < y.price
				end
				return x.id < y.id
			end)
			return true, list
		end,
		-- Two-phase, deduplicated mailbox (see Adapters.luau): mail[userId] = { entries, acked }.
		MailAdd = function(userId, entry)
			if not marketUp() then
				return false
			end
			local box = market.mail[userId] or { entries = {}, acked = {} }
			market.mail[userId] = box
			if entry.id ~= nil then
				if table.find(box.acked, entry.id) then
					return true
				end
				for _, e in box.entries do
					if e.id == entry.id then
						return true
					end
				end
			end
			table.insert(box.entries, deepCopy(entry))
			return true
		end,
		MailPeek = function(userId)
			if not marketUp() then
				return false, nil
			end
			local box = market.mail[userId]
			return true, deepCopy(if box then box.entries else {})
		end,
		MailAck = function(userId, ids)
			if not marketUp() then
				return false
			end
			local box = market.mail[userId]
			if not box then
				return true
			end
			local drop = {}
			for _, id in ids do
				drop[id] = true
			end
			local kept = {}
			for _, e in box.entries do
				if e.id ~= nil and drop[e.id] then
					table.insert(box.acked, e.id)
				else
					table.insert(kept, e)
				end
			end
			box.entries = kept
			while #box.acked > 200 do
				table.remove(box.acked, 1)
			end
			return true
		end,
	}
	a.PriceHistory = {
		Get = function(key)
			if not marketUp() then
				return false, nil
			end
			return true, deepCopy(network.prices[key])
		end,
		Update = function(key, transform)
			if not marketUp() then
				return false, nil
			end
			local result = transform(deepCopy(network.prices[key]))
			if result ~= nil then
				network.prices[key] = deepCopy(result)
			end
			return true, deepCopy(result)
		end,
	}

	a.Text = {
		Filter = function(text, _userId)
			if string.find(string.lower(text), "badword") then
				return string.rep("#", #text)
			end
			return text
		end,
	}

	a.Analytics = {
		Custom = function(player, name, value, fields)
			table.insert(a.log.analytics, { kind = "custom", player = player, name = name, value = value, fields = fields })
		end,
		Economy = function(player, isSource, currency, amount, balance, transactionType, sku)
			table.insert(a.log.analytics, {
				kind = "economy",
				player = player,
				isSource = isSource,
				currency = currency,
				amount = amount,
				balance = balance,
				transactionType = transactionType,
				sku = sku,
			})
		end,
		Onboarding = function(player, step, stepName)
			table.insert(a.log.analytics, { kind = "onboarding", player = player, step = step, name = stepName })
		end,
	}

	a.Workspace = nil
	return a
end

return MockAdapters
