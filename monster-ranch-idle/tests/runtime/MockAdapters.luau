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

function MockAdapters.new(options: { startTime: number? }?)
	local opts = options or {}
	local now = opts.startTime or 1790000000 -- a Thursday in Sept 2026 (UTC)
	local precise = 0

	local a = {}
	a.log = { kicks = {}, events = {}, states = {}, analytics = {}, published = {}, ads = {} }
	a.JobId = "test-job"
	a.PlaceId = 0
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
		now += seconds
		precise += seconds
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

	a._subscribers = {}
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
