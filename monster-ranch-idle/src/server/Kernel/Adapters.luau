--[[
	Adapters: the only place the server kernel and systems touch Roblox services.
	Systems reach them through ctx.Services. Tests replace this whole table with
	tests/runtime/MockAdapters.luau, which is why systems must never call
	game:GetService for anything listed here.

	Every adapter call that can fail is wrapped in pcall and returns a safe default.
]]

local RemindersAdapter = require(script.Parent.RemindersAdapter)

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
	local BadgeService = game:GetService("BadgeService")

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
		-- The player's rank in a group (0 = not a member or unknown).
		RankInGroup = function(player, groupId: number): number
			if groupId == 0 then
				return 0
			end
			local ok, result = pcall(function()
				return player:GetRankInGroup(groupId)
			end)
			return if ok and type(result) == "number" then result else 0
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
		-- Club Wars ladder (3.1): one OrderedDataStore per week, club id -> war points.
		IndexWar = function(week: number, id: string, points: number): boolean
			return (
				pcall(function()
					DataStoreService:GetOrderedDataStore("MonsterRanch_ClubWars_w" .. tostring(week)):SetAsync(id, math.floor(points))
				end)
			)
		end,
		TopWar = function(week: number, count: number): (boolean, { any })
			local ok, rows = pcall(function()
				local page = DataStoreService:GetOrderedDataStore("MonsterRanch_ClubWars_w" .. tostring(week))
					:GetSortedAsync(false, math.clamp(count, 1, 100))
					:GetCurrentPage()
				local out = {}
				for _, entry in page do
					table.insert(out, { id = entry.key, points = entry.value })
				end
				return out
			end)
			return ok, if ok then rows else {}
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
	local function normalizeBox(current)
		if type(current) ~= "table" then
			return { entries = {}, acked = {} }
		end
		if current.entries == nil then -- an old plain list of entries
			return { entries = current, acked = {} }
		end
		current.acked = current.acked or {}
		return current
	end
	local function isKnownMail(box, id): boolean
		if id == nil then
			return false
		end
		if table.find(box.acked, id) then
			return true
		end
		for _, e in box.entries do
			if e.id == id then
				return true
			end
		end
		return false
	end
	local function ackBox(box, ids)
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
		return box
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
		-- Mailbox record: { entries = { entry }, acked = { entry id } }. Every entry has an `id`;
		-- MailAdd skips ids already in the box or acknowledged recently, so retries never
		-- deliver twice. Reading is two-phase: MailPeek, apply + save, then MailAck.
		MailAdd = function(userId: number, entry): boolean
			local ok = atomic(mailStore, "mail_" .. tostring(userId), function(current)
				local box = normalizeBox(current)
				if isKnownMail(box, entry.id) then
					return nil
				end
				table.insert(box.entries, entry)
				return box
			end)
			return ok
		end,
		MailPeek = function(userId: number): (boolean, any)
			if not mailStore then
				return false, nil
			end
			local seen = nil
			local ok = atomic(mailStore, "mail_" .. tostring(userId), function(current)
				seen = normalizeBox(current).entries
				return nil -- read the latest value without writing
			end)
			return ok, if ok then (seen or {}) else nil
		end,
		MailAck = function(userId: number, ids: { string }): boolean
			local ok = atomic(mailStore, "mail_" .. tostring(userId), function(current)
				return ackBox(normalizeBox(current), ids)
			end)
			return ok
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
	-- Arena (update 2.1): one record per player { userId, name, rating, team, wins, losses,
	-- updatedAt } in a DataStore (atomic Update), and ratings in an OrderedDataStore for
	-- matchmaking. VERIFY in a live server: GetSortedAsync min/max paging.
	local arenaStore = storeOf("MonsterRanch_Arena_v1")
	local arenaIndex = nil
	local function ratings()
		if arenaIndex == nil then
			local ok, store = pcall(function()
				return DataStoreService:GetOrderedDataStore("MonsterRanch_ArenaRatings_v1")
			end)
			arenaIndex = if ok then store else false
		end
		return arenaIndex or nil
	end
	adapters.Arena = {
		Get = function(userId: number): (boolean, any)
			if not arenaStore then
				return false, nil
			end
			local ok, record = pcall(function()
				return arenaStore:GetAsync(tostring(userId))
			end)
			return ok, if ok then record else nil
		end,
		Update = function(userId: number, transform): (boolean, any)
			return atomic(arenaStore, tostring(userId), transform)
		end,
		Index = function(userId: number, rating: number): boolean
			local store = ratings()
			if not store then
				return false
			end
			local ok = pcall(function()
				store:SetAsync(tostring(userId), math.floor(rating))
			end)
			return ok
		end,
		-- Players rated within `window` of `rating` (closest first is up to the caller).
		Near = function(rating: number, window: number, count: number): (boolean, { { userId: number, rating: number } })
			local store = ratings()
			if not store then
				return false, {}
			end
			local ok, list = pcall(function()
				local pages =
					store:GetSortedAsync(false, math.clamp(count, 1, 100), math.floor(rating - window), math.floor(rating + window))
				local out = {}
				for _, entry in pages:GetCurrentPage() do
					local userId = tonumber(entry.key)
					if userId then
						table.insert(out, { userId = userId, rating = entry.value })
					end
				end
				return out
			end)
			return ok, if ok then list else {}
		end,
	}

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

	-- Trading Hub (update 3.0). PlaceMode is the Studio override (Workspace attribute
	-- PlaceMode = "hub"); the TradingHub config decides the mode from it and PlaceId.
	adapters.PlaceMode = workspace:GetAttribute("PlaceMode")
	local TeleportService = game:GetService("TeleportService")
	-- A teleport can still fail after TeleportAsync returns (TeleportInitFailed): retry the
	-- same target up to twice for transient failures (3.0.1).
	local pendingTeleports = {} -- [player] = { placeId, options?, tries }
	local function teleport(player, placeId: number, options): (boolean, string?)
		pendingTeleports[player] = { placeId = placeId, options = options, tries = 0 }
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, { player }, options)
		end)
		if not ok then
			pendingTeleports[player] = nil
		end
		return ok, if ok then nil else tostring(err)
	end
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		local pending = pendingTeleports[player]
		local transient = result == Enum.TeleportResult.Flooded or result == Enum.TeleportResult.Failure
		if not pending or not transient or pending.tries >= 2 then
			pendingTeleports[player] = nil
			warn("[Adapters] teleport failed: " .. tostring(result) .. " " .. tostring(message))
			return
		end
		pending.tries += 1
		task.delay(2 * pending.tries, function()
			if player.Parent then
				pcall(function()
					TeleportService:TeleportAsync(pending.placeId, { player }, pending.options)
				end)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		pendingTeleports[player] = nil
	end)
	adapters.Teleport = {
		-- To a public server of another place in this universe.
		ToPlace = function(player, placeId: number): (boolean, string?)
			return teleport(player, placeId, nil)
		end,
		-- To one running server (JobId) of a place.
		ToServer = function(player, placeId: number, jobId: string): (boolean, string?)
			local options = Instance.new("TeleportOptions")
			options.ServerInstanceId = jobId
			return teleport(player, placeId, options)
		end,
	}
	-- The places of this universe { { name, placeId } } (3.0.1: the Trading Hub finds its
	-- place ids by name, so nobody has to copy ids into Config).
	local AssetService = game:GetService("AssetService")
	adapters.Places = {
		List = function(): (boolean, { any })
			local ok, list = pcall(function()
				local out = {}
				local pages = AssetService:GetGamePlacesAsync()
				while true do
					for _, place in pages:GetCurrentPage() do
						table.insert(out, { name = place.Name, placeId = place.PlaceId })
					end
					if pages.IsFinished or #out >= 50 then
						break
					end
					pages:AdvanceToNextPageAsync()
				end
				return out
			end)
			return ok, if ok then list else {}
		end,
	}
	-- The Trade Board: one MemoryStore sorted map, ad id -> ad, sorted by post time.
	-- VERIFY in a live server: MemoryStore quotas with many hub servers.
	local boardOk, board = pcall(function()
		return MemoryStoreService:GetSortedMap("MonsterRanch_HubBoard_v1")
	end)
	adapters.HubBoard = {
		Post = function(ad, ttl: number): boolean
			if not boardOk then
				return false
			end
			return (pcall(function()
				board:SetAsync(ad.id, ad, math.clamp(ttl, 60, 3600), ad.postedAt)
			end))
		end,
		Remove = function(id: string): boolean
			if not boardOk then
				return false
			end
			return (pcall(function()
				board:RemoveAsync(id)
			end))
		end,
		List = function(limit: number): (boolean, { any })
			if not boardOk then
				return false, {}
			end
			local ok, items = pcall(function()
				return board:GetRangeAsync(Enum.SortDirection.Descending, math.clamp(limit, 1, 200))
			end)
			if not ok then
				return false, {}
			end
			local ads = {}
			for _, item in items do
				table.insert(ads, item.value)
			end
			return true, ads
		end,
	}

	-- Workshop designs (update 3.0): one DataStore record per design, a likes index for the
	-- Top gallery (OrderedDataStore) and a "recent" feed key (newest first, capped).
	local designStore = storeOf("MonsterRanch_Designs_v1")
	local royaltyStore = storeOf("MonsterRanch_Royalties_v1")
	local feedStore = storeOf("MonsterRanch_DesignFeed_v1")
	local likesOk, likesIndex = pcall(function()
		return DataStoreService:GetOrderedDataStore("MonsterRanch_DesignLikes_v1")
	end)
	adapters.Designs = {
		Create = function(record): boolean
			local created = false
			local ok = atomic(designStore, record.id, function(current)
				if current ~= nil then
					return nil
				end
				created = true
				return record
			end)
			if ok and created then
				atomic(feedStore, "recent", function(current)
					local list = if type(current) == "table" then current else {}
					table.insert(list, 1, record.id)
					while #list > 100 do
						table.remove(list)
					end
					return list
				end)
			end
			return ok and created
		end,
		Get = function(id: string): (boolean, any)
			if not designStore then
				return false, nil
			end
			local ok, record = pcall(function()
				return designStore:GetAsync(id)
			end)
			return ok, if ok then record else nil
		end,
		Update = function(id: string, transform): (boolean, any)
			return atomic(designStore, id, transform)
		end,
		Index = function(id: string, likes: number): boolean
			if not likesOk then
				return false
			end
			return (pcall(function()
				likesIndex:SetAsync(id, math.max(0, math.floor(likes)))
			end))
		end,
		Top = function(count: number): (boolean, { string })
			if not likesOk then
				return false, {}
			end
			local ok, ids = pcall(function()
				local page = likesIndex:GetSortedAsync(false, math.clamp(count, 1, 100)):GetCurrentPage()
				local list = {}
				for _, entry in page do
					table.insert(list, entry.key)
				end
				return list
			end)
			return ok, if ok then ids else {}
		end,
		-- Royalty ledger (3.0.1): ribbons owed to a designer, one key per designer, so a
		-- claim is a single write however many designs they have.
		Owe = function(userId: number, amount: number): boolean
			return (atomic(royaltyStore, tostring(userId), function(current)
				return (tonumber(current) or 0) + amount
			end))
		end,
		Collect = function(userId: number): (boolean, number)
			local taken = 0
			local ok = atomic(royaltyStore, tostring(userId), function(current)
				taken = tonumber(current) or 0
				return if taken > 0 then 0 else nil
			end)
			return ok, if ok then taken else 0
		end,
		-- Moderation feed (3.0.1): designs hidden by reports, oldest first.
		Flag = function(id: string): boolean
			return (
				atomic(feedStore, "reported", function(current)
					local list = if type(current) == "table" then current else {}
					if table.find(list, id) then
						return nil
					end
					table.insert(list, id)
					while #list > 200 do
						table.remove(list, 1)
					end
					return list
				end)
			)
		end,
		Unflag = function(id: string): boolean
			return (
				atomic(feedStore, "reported", function(current)
					local list = if type(current) == "table" then current else {}
					local at = table.find(list, id)
					if not at then
						return nil
					end
					table.remove(list, at)
					return list
				end)
			)
		end,
		Flagged = function(count: number): (boolean, { string })
			if not feedStore then
				return false, {}
			end
			local ok, list = pcall(function()
				return feedStore:GetAsync("reported")
			end)
			if not ok then
				return false, {}
			end
			local ids = {}
			for i, id in (if type(list) == "table" then list else {}) do
				if i > count then
					break
				end
				table.insert(ids, id)
			end
			return true, ids
		end,
		Recent = function(count: number): (boolean, { string })
			if not feedStore then
				return false, {}
			end
			local ok, list = pcall(function()
				return feedStore:GetAsync("recent")
			end)
			if not ok then
				return false, {}
			end
			local ids = {}
			for i, id in (if type(list) == "table" then list else {}) do
				if i > count then
					break
				end
				table.insert(ids, id)
			end
			return true, ids
		end,
	}

	adapters.Workspace = workspace
	-- A MeshPart from a published Mesh asset, for World/Dress. Yields; nil if it fails to load.
	-- A server dressing the world asks for ~90 meshes in a row, and a load in that burst can fail
	-- where the same mesh loads fine a minute later (seven buildings came up bare in one Play test,
	-- 2026-09-25), so a failed load is tried again before its building keeps the placeholder.
	adapters.CreateMeshPart = function(uri: string): MeshPart?
		for attempt = 1, 3 do
			local ok, part = pcall(function()
				return game:GetService("AssetService"):CreateMeshPartAsync(Content.fromUri(uri), {
					CollisionFidelity = Enum.CollisionFidelity.Hull,
				})
			end)
			if ok then
				return part
			end
			warn(string.format("[Adapters] mesh %s, attempt %d: %s", uri, attempt, tostring(part)))
			if attempt < 3 then
				task.wait(2 * attempt)
			end
		end
		return nil
	end
	-- Offline reminders (glow-up I): MemoryStore queue + Open Cloud notifications. nil when the
	-- services can't be reached; the Reminders system is off then.
	adapters.Reminders = RemindersAdapter.Roblox()

	-- Roblox badges (glow-up O: Codex milestones). May yield; callers run it through Spawn.
	adapters.Badges = {
		Award = function(userId: number, badgeId: number): boolean
			local ok, awarded = pcall(function()
				return BadgeService:AwardBadge(userId, badgeId)
			end)
			return ok and awarded == true
		end,
	}

	-- Limited editions (glow-up W): one counter per edition in its own DataStore. UpdateAsync
	-- makes a claim atomic across servers: Claim -> (true, n) the next number, (true, nil) the
	-- edition is full, (false, nil) the store failed (the monster stays pending and is tried
	-- again). nil when the store can't be opened: the system then counts in the profile store.
	local editionStore = storeOf("MonsterRanch_Editions_v1")
	adapters.Editions = if editionStore
		then {
			Claim = function(editionId: string, size: number): (boolean, number?)
				local minted = nil
				local ok = pcall(function()
					editionStore:UpdateAsync(editionId, function(current)
						local count = math.max(0, math.floor(tonumber(current) or 0))
						if count >= size then
							minted = nil
							return nil -- full: write nothing
						end
						minted = count + 1
						return minted
					end)
				end)
				return ok, if ok then minted else nil
			end,
		}
		else nil

	-- Ranch visits (glow-up Y): one snapshot per player in its own DataStore (tagged with the
	-- user id for erasure requests), and where a friend is playing right now. nil when the
	-- store can't be opened: visits, snapshots and the Ranch of the Week stage are off then.
	local ranchStore = storeOf("MonsterRanch_Ranches_v1")
	adapters.Ranches = if ranchStore
		then {
			Save = function(userId: number, snap): boolean
				return (pcall(function()
					ranchStore:SetAsync("u" .. tostring(userId), snap, { userId })
				end))
			end,
			Load = function(userId: number): (boolean, any)
				local ok, snap = pcall(function()
					return ranchStore:GetAsync("u" .. tostring(userId))
				end)
				return ok, if ok then snap else nil
			end,
			-- (true, { placeId, jobId }) while they play in this universe, (true, nil) when they
			-- don't, (false, nil) when the lookup failed.
			Locate = function(userId: number): (boolean, any)
				local ok, _, _, placeId, jobId = pcall(function()
					return TeleportService:GetPlayerPlaceInstanceAsync(userId)
				end)
				if not ok then
					return false, nil
				end
				if type(placeId) == "number" and placeId ~= 0 and type(jobId) == "string" and jobId ~= "" then
					return true, { placeId = placeId, jobId = jobId }
				end
				return true, nil
			end,
		}
		else nil

	return adapters
end

return Adapters
