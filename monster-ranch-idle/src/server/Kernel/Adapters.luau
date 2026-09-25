--[[
	Adapters: the only place the server kernel and systems touch Roblox services.
	Systems reach them through ctx.Services. Tests replace this whole table with
	tests/runtime/MockAdapters.luau, which is why systems must never call
	game:GetService for anything listed here.

	Every adapter call that can fail is wrapped in pcall and returns a safe default.
]]

local Adapters = {}

local REMOTES_FOLDER = "KernelRemotes"
local DATASTORE_NAME = "MonsterRanch_Profiles_v1"

local function makeTransport()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = REMOTES_FOLDER
		folder.Parent = ReplicatedStorage
	end
	local function remote(className: string, name: string)
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		local r = Instance.new(className)
		r.Name = name
		r.Parent = folder
		return r
	end
	local request = remote("RemoteFunction", "Request")
	local event = remote("RemoteEvent", "Event")
	local state = remote("RemoteEvent", "State")

	return {
		OnRequest = function(_, fn)
			request.OnServerInvoke = function(player, action, payload)
				return fn(player, action, payload)
			end
		end,
		Fire = function(_, player, name, payload)
			event:FireClient(player, name, payload)
		end,
		SendState = function(_, player, message)
			state:FireClient(player, message)
		end,
	}
end

local function makeDataStore()
	local DataStoreService = game:GetService("DataStoreService")
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if not ok then
		warn("[Adapters] DataStore unavailable (enable Studio API access). Using an in-memory store: progress will not be saved.")
		local memory = {}
		return {
			Update = function(_, key, transform)
				local result = transform(memory[key])
				if result ~= nil then
					memory[key] = result
				end
				return true, result
			end,
		}
	end
	return {
		Update = function(_, key, transform)
			-- Respect the request budget so autosaves never starve player loads.
			for _ = 1, 20 do
				local budget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
				if budget > 0 then
					break
				end
				task.wait(0.5)
			end
			return pcall(function()
				return store:UpdateAsync(key, transform)
			end)
		end,
	}
end

function Adapters.Roblox()
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local MarketplaceService = game:GetService("MarketplaceService")
	local PolicyService = game:GetService("PolicyService")
	local MessagingService = game:GetService("MessagingService")
	local TextService = game:GetService("TextService")
	local AnalyticsService = game:GetService("AnalyticsService")

	local isStudio = RunService:IsStudio()
	local nameCache = {}

	local adapters = {}
	adapters.JobId = if game.JobId ~= "" then game.JobId else "studio-" .. tostring(math.random(1, 1e9))
	adapters.PlaceId = game.PlaceId
	adapters.IsStudio = isStudio
	adapters.OfflineMaxSeconds = 7 * 24 * 3600

	adapters.Clock = {
		Now = function(): number
			return os.time()
		end,
		Precise = function(): number
			return os.clock()
		end,
	}
	adapters.Seed = function()
		return math.floor((os.clock() * 1e6 + os.time()) % 4294967296)
	end
	adapters.Wait = function(seconds: number)
		task.wait(seconds)
	end
	adapters.Spawn = function(fn, ...)
		task.spawn(fn, ...)
	end
	adapters.OnStep = function(fn)
		RunService.Heartbeat:Connect(fn)
	end
	adapters.BindToClose = function(fn)
		game:BindToClose(fn)
	end

	adapters.Players = {
		OnAdded = function(fn)
			Players.PlayerAdded:Connect(function(player)
				fn(player)
			end)
		end,
		OnRemoving = function(fn)
			Players.PlayerRemoving:Connect(fn)
		end,
		GetPlayers = function()
			return Players:GetPlayers()
		end,
		Kick = function(player, message: string)
			if player and player.Parent then
				player:Kick(message)
			end
		end,
		IsFriendsWith = function(player, userId: number): boolean
			local ok, result = pcall(function()
				return player:IsFriendsWith(userId)
			end)
			return ok and result == true
		end,
		IsInGroup = function(player, groupId: number): boolean
			if groupId == 0 then
				return false
			end
			local ok, result = pcall(function()
				return player:IsInGroup(groupId)
			end)
			return ok and result == true
		end,
		-- Display name for any user id (players who are not on this server). Cached.
		NameOf = function(userId: number): string?
			local cached = nameCache[userId]
			if cached then
				return cached
			end
			local online = Players:GetPlayerByUserId(userId)
			if online then
				nameCache[userId] = online.DisplayName
				return online.DisplayName
			end
			local ok, name = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			if ok and type(name) == "string" then
				nameCache[userId] = name
				return name
			end
			return nil
		end,
	}

	adapters.Transport = makeTransport()
	adapters.DataStore = makeDataStore()

	local DataStoreService = game:GetService("DataStoreService")

	-- Clubs: one record per club in its own DataStore, keyed by the club code. Update is
	-- atomic (UpdateAsync) so servers can write the same club at the same time; the
	-- transform may return nil to leave the record unchanged.
	local clubStore = nil
	local function clubs()
		if clubStore == nil then
			local ok, store = pcall(function()
				return DataStoreService:GetDataStore("MonsterRanch_Clubs_v1")
			end)
			clubStore = if ok then store else false
		end
		return clubStore or nil
	end
	adapters.Clubs = {
		Get = function(id: string): (boolean, any)
			local store = clubs()
			if not store then
				return false, nil
			end
			local ok, record = pcall(function()
				return store:GetAsync(id)
			end)
			return ok, if ok then record else nil
		end,
		Update = function(id: string, transform): (boolean, any)
			local store = clubs()
			if not store then
				return false, nil
			end
			local result = nil
			local ok = pcall(function()
				store:UpdateAsync(id, function(current)
					result = transform(current)
					return result
				end)
			end)
			return ok, result
		end,
	}

	-- Market (update 1.3). Listing records (with the escrowed item) live in a DataStore
	-- keyed by listing id; open listings are also indexed in MemoryStore sorted maps for
	-- browsing (one map per scope and kind, sorted by price, expiring with the listing).
	-- Mailboxes (sale proceeds, returned items) are one DataStore key per user.
	-- VERIFY in a live server: MemoryStore quotas and GetRangeAsync paging.
	local MemoryStoreService = game:GetService("MemoryStoreService")
	local function storeOf(name: string)
		local ok, store = pcall(function()
			return DataStoreService:GetDataStore(name)
		end)
		return if ok then store else nil
	end
	local listingStore = storeOf("MonsterRanch_Market_v1")
	local mailStore = storeOf("MonsterRanch_Mail_v1")
	local historyStore = storeOf("MonsterRanch_Prices_v1")
	local function indexName(scope: string, kind: string): string
		return if scope == "all" then "mk_all_" .. kind else "mk_club_" .. scope
	end
	local function indexOf(listing)
		local scope = if listing.club then listing.club else "all"
		return MemoryStoreService:GetSortedMap(indexName(scope, listing.kind))
	end
	local function summary(listing)
		local copy = table.clone(listing)
		copy.item = nil -- the escrowed record stays in the DataStore
		return copy
	end
	local function atomic(store, key: string, transform)
		if not store then
			return false, nil
		end
		local result = nil
		local ok = pcall(function()
			store:UpdateAsync(key, function(current)
				result = transform(current)
				return result
			end)
		end)
		return ok, result
	end
	adapters.Market = {
		Create = function(listing): boolean
			local ok = atomic(listingStore, listing.id, function(current)
				if current ~= nil then
					return nil
				end
				return listing
			end)
			if ok then
				pcall(function()
					local ttl = math.clamp(listing.expiresAt - os.time(), 60, 45 * 86400)
					indexOf(listing):SetAsync(listing.id, summary(listing), ttl, listing.price)
				end)
			end
			return ok
		end,
		Get = function(id: string): (boolean, any)
			if not listingStore then
				return false, nil
			end
			local ok, record = pcall(function()
				return listingStore:GetAsync(id)
			end)
			return ok, if ok then record else nil
		end,
		Update = function(id: string, transform): (boolean, any)
			local ok, result = atomic(listingStore, id, transform)
			if ok and result and result.state ~= "open" then
				pcall(function()
					indexOf(result):RemoveAsync(id)
				end)
			end
			return ok, result
		end,
		Browse = function(query): (boolean, any)
			local ok, result = pcall(function()
				local scope = query.scope or "all"
				local kinds = if query.kind then { query.kind } elseif scope == "all" then { "monster", "egg" } else { "" }
				local list = {}
				for _, kind in kinds do
					local map = MemoryStoreService:GetSortedMap(indexName(scope, kind))
					local direction = if query.sort == "-price" then Enum.SortDirection.Descending else Enum.SortDirection.Ascending
					for _, entry in map:GetRangeAsync(direction, 200) do
						local v = entry.value
						if type(v) == "table" and (query.key == nil or v.key == query.key) then
							table.insert(list, v)
						end
					end
				end
				return list
			end)
			return ok, if ok then result else nil
		end,
		MailAdd = function(userId: number, entry): boolean
			local ok = atomic(mailStore, "mail_" .. tostring(userId), function(current)
				local list = if type(current) == "table" then current else {}
				table.insert(list, entry)
				return list
			end)
			return ok
		end,
		MailTake = function(userId: number): (boolean, any)
			local taken = nil
			local ok = atomic(mailStore, "mail_" .. tostring(userId), function(current)
				taken = if type(current) == "table" then current else {}
				if #taken == 0 then
					return nil
				end
				return {}
			end)
			return ok, if ok then (taken or {}) else nil
		end,
	}
	adapters.PriceHistory = {
		Get = function(key: string): (boolean, any)
			if not historyStore then
				return false, nil
			end
			local ok, record = pcall(function()
				return historyStore:GetAsync(key)
			end)
			return ok, if ok then record else nil
		end,
		Update = function(key: string, transform): (boolean, any)
			return atomic(historyStore, key, transform)
		end,
	}

	-- Global leaderboards: one OrderedDataStore per board per week (key from
	-- Config.Leaderboards.Key). Values are whole numbers; failures return false / nil.
	adapters.Leaderboards = {
		Submit = function(key: string, userId: number, value: number): boolean
			local ok = pcall(function()
				DataStoreService:GetOrderedDataStore("LB_" .. key):SetAsync(tostring(userId), math.floor(value))
			end)
			return ok
		end,
		Top = function(key: string, count: number): { { userId: number, value: number } }?
			local ok, result = pcall(function()
				local pages = DataStoreService:GetOrderedDataStore("LB_" .. key):GetSortedAsync(false, count)
				local list = {}
				for _, entry in pages:GetCurrentPage() do
					local userId = tonumber(entry.key)
					if userId then
						table.insert(list, { userId = userId, value = entry.value })
					end
				end
				return list
			end)
			return if ok then result else nil
		end,
	}

	adapters.Marketplace = {
		OwnsPass = function(player, gamePassId: number): boolean
			if gamePassId == 0 then
				return false
			end
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
			end)
			return ok and result == true
		end,
		-- fn(receiptInfo) -> Enum.ProductPurchaseDecision
		SetProcessReceipt = function(fn)
			MarketplaceService.ProcessReceipt = fn
		end,
		OnPassPurchased = function(fn)
			MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
				if purchased then
					fn(player, passId)
				end
			end)
		end,
		PurchaseGranted = Enum.ProductPurchaseDecision.PurchaseGranted,
		NotProcessedYet = Enum.ProductPurchaseDecision.NotProcessedYet,
	}

	adapters.Policy = {
		PaidRandomItemsAllowed = function(player): boolean
			local ok, info = pcall(function()
				return PolicyService:GetPolicyInfoForPlayerAsync(player)
			end)
			if not ok or type(info) ~= "table" then
				return false -- fail closed
			end
			return info.ArePaidRandomItemsRestricted ~= true
		end,
	}

	-- Rewarded video ads. The AdService API surface is checked at runtime; in Studio (or when
	-- the API is unavailable) ads are simulated as watched so flows can be tested.
	-- VERIFY in Studio against the current AdService documentation before launch.
	adapters.Ads = {
		ShowRewarded = function(player, placement: string): boolean
			if isStudio then
				return true
			end
			local ok, result = pcall(function()
				local AdService = game:GetService("AdService")
				local available = AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
				if available.AdAvailabilityResult ~= Enum.AdAvailabilityResult.IsAvailable then
					return false
				end
				local reward = AdService:CreateAdRewardFromDevProductId(0)
				local shown = AdService:ShowRewardedVideoAdAsync(player, reward)
				return shown == Enum.ShowAdResult.ShowCompleted
			end)
			if not ok then
				warn("[Adapters] rewarded ad failed for " .. placement .. ": " .. tostring(result))
				return false
			end
			return result == true
		end,
	}

	adapters.Messaging = {
		Publish = function(topic: string, data: any)
			pcall(function()
				MessagingService:PublishAsync(topic, data)
			end)
		end,
		Subscribe = function(topic: string, fn: (any) -> ())
			task.spawn(function()
				local ok, err = pcall(function()
					MessagingService:SubscribeAsync(topic, function(message)
						fn(message.Data)
					end)
				end)
				if not ok then
					warn("[Adapters] MessagingService subscribe failed: " .. tostring(err))
				end
			end)
		end,
	}

	adapters.Text = {
		-- Returns the filtered string for public display, or nil if filtering failed.
		Filter = function(text: string, fromUserId: number): string?
			local ok, result = pcall(function()
				local filtered = TextService:FilterStringAsync(text, fromUserId)
				return filtered:GetNonChatStringForBroadcastAsync()
			end)
			return if ok then result else nil
		end,
	}

	adapters.Analytics = {
		Custom = function(player, name: string, value: number?, fields: { [string]: string }?)
			pcall(function()
				AnalyticsService:LogCustomEvent(player, name, value or 1, fields)
			end)
		end,
		Economy = function(
			player,
			isSource: boolean,
			currency: string,
			amount: number,
			balance: number,
			transactionType: string,
			sku: string?
		)
			pcall(function()
				AnalyticsService:LogEconomyEvent(
					player,
					if isSource then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink,
					currency,
					amount,
					balance,
					transactionType,
					sku
				)
			end)
		end,
		Onboarding = function(player, step: number, stepName: string)
			pcall(function()
				AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
			end)
		end,
	}

	adapters.Workspace = workspace
	return adapters
end

return Adapters
