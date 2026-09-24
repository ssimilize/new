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
	}

	adapters.Transport = makeTransport()
	adapters.DataStore = makeDataStore()

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
