--[[
	Monetization (S6): game passes, developer products (ProcessReceipt) and rewarded ads.

	Design rule (Config/Monetization.luau): nothing here skips a timer. Robux buys parallel
	capacity, convenience, cosmetics and server-wide fun; ads give a small, capped boost.

	Save section (profile.Monetization):
	  ads      = { day, counts = { [placement] = n } }   -- reset every UTC day
	  once     = { [productKey] = true }                 -- oncePerAccount products bought
	  receipts = { { id, product, t } }                  -- PRIVATE, newest last, ≤ Config.ReceiptHistory

	Session (session.Monetization):
	  passes            = { [passKey] = boolean }         -- every pass key, cached on join
	  paidRandomAllowed = boolean                         -- PolicyService, cached on join (fails closed)

	Public API (other systems):
	  Monetization:HasPass(player, key) -> boolean                     -- cached value only (no yield)
	  Monetization:RegisterProduct(handlerKey, fn(player, product, receiptInfo) -> boolean)
	  Monetization:WatchAd(player, placement) -> boolean                -- YIELDS; counts completed views only
	  Monetization:CanWatchAd(player, placement) -> boolean, reason?   -- no yield; reason is player-facing
	  Monetization:AdsLeft(player, placement) -> number
	  Monetization:PaidRandomAllowed(player) -> boolean

	Publishes PassesChanged and RateModifiersChanged (pass ownership changed, including on join
	when the player owns any pass), Purchase and AdWatched.

	Receipts are idempotent: a PurchaseId already in `receipts` returns PurchaseGranted without
	granting again, and a receipt being processed right now is never processed twice at once.
	Anything that can't be granted returns NotProcessedYet, so Roblox retries on a later join.
]]

local Monetization = {
	Name = "Monetization",
	Dependencies = { "Rewards" },
}

local DEFAULT_RECEIPT_HISTORY = 200

Monetization.Profile = {
	Version = 1,
	Default = function()
		return { ads = { day = 0, counts = {} }, once = {}, receipts = {} }
	end,
	Private = { "receipts" },
}

local ctx
local Config -- Config.Monetization
local Rewards

local productHandlers = {} -- [handlerKey] = fn(player, product, receiptInfo) -> boolean
local processing = {} -- [purchaseId] = true while a receipt is being granted
local watching = {} -- [player] = true while a rewarded ad is showing

-- Lookups ------------------------------------------------------------------------------
-- Scanned on every call (the lists are tiny) so ids set at runtime, or in tests, are honoured.

local function productById(productId: any)
	if type(productId) ~= "number" or productId == 0 then
		return nil
	end
	for _, product in Config.Products do
		if product.productId == productId then
			return product
		end
	end
	return nil
end

local function passById(gamePassId: any)
	if type(gamePassId) ~= "number" or gamePassId == 0 then
		return nil
	end
	for _, pass in Config.Passes do
		if pass.gamePassId == gamePassId then
			return pass
		end
	end
	return nil
end

-- Passes -------------------------------------------------------------------------------

local function session(player)
	local s = ctx:Session(player)
	if s and s.passes == nil then
		s.passes = {}
		for _, pass in Config.Passes do
			s.passes[pass.key] = false
		end
		s.paidRandomAllowed = false
	end
	return s
end

local function publishPasses(player)
	local s = session(player)
	ctx.Bus:Publish("PassesChanged", player, { passes = table.clone(s.passes) })
	ctx.Bus:Publish("RateModifiersChanged", player, {})
end

-- Marks passes as owned. Ownership only ever turns on during a session: a failed ownership
-- check (network error) must never take a pass away from a paying player.
local function setOwned(player, keys: { string }): boolean
	local s = session(player)
	if not s then
		return false
	end
	local changed = false
	for _, key in keys do
		if s.passes[key] ~= true then
			s.passes[key] = true
			changed = true
		end
	end
	if changed then
		ctx:DirtySession(player, "passes")
		publishPasses(player)
	end
	return changed
end

local function checkOwnership(player): { string }
	local owned = {}
	for _, pass in Config.Passes do
		if pass.gamePassId ~= 0 and ctx.Services.Marketplace.OwnsPass(player, pass.gamePassId) then
			table.insert(owned, pass.key)
		end
	end
	return owned
end

-- Ads ----------------------------------------------------------------------------------

local function adsSection(player)
	local s = ctx:Section(player)
	if not s then
		return nil
	end
	local today = ctx:Day()
	if s.ads.day ~= today then
		s.ads = { day = today, counts = {} }
		ctx:Dirty(player, "ads")
	end
	return s.ads
end

-- Receipts -----------------------------------------------------------------------------

local function hasReceipt(section, purchaseId: string): boolean
	for _, r in section.receipts do
		if r.id == purchaseId then
			return true
		end
	end
	return false
end

local function recordReceipt(section, purchaseId: string, productKey: string)
	table.insert(section.receipts, { id = purchaseId, product = productKey, t = ctx:Now() })
	local limit = Config.ReceiptHistory or DEFAULT_RECEIPT_HISTORY
	while #section.receipts > limit do
		table.remove(section.receipts, 1)
	end
end

local function grant(player, product, receiptInfo): boolean
	if product.handler then
		local handler = productHandlers[product.handler]
		if not handler then
			warn(string.format("[Monetization] no handler registered for '%s' (product %s)", product.handler, product.key))
			return false
		end
		local ok, result = pcall(handler, player, product, receiptInfo)
		if not ok then
			warn(string.format("[Monetization] handler '%s' errored: %s", product.handler, tostring(result)))
			return false
		end
		return result == true
	end
	local ok, err = pcall(function()
		Rewards:Grant(player, product.grant or {}, "purchase:" .. product.key)
	end)
	if not ok then
		warn(string.format("[Monetization] granting %s failed: %s", product.key, tostring(err)))
	end
	return ok
end

local function processReceipt(receiptInfo)
	local Marketplace = ctx.Services.Marketplace
	local player = ctx:PlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Marketplace.NotProcessedYet -- not in this server, or still loading: Roblox retries
	end
	local section = ctx:Section(player)
	if not section then
		return Marketplace.NotProcessedYet
	end
	local purchaseId = tostring(receiptInfo.PurchaseId)
	if hasReceipt(section, purchaseId) then
		return Marketplace.PurchaseGranted
	end
	if processing[purchaseId] then
		return Marketplace.NotProcessedYet
	end
	local product = productById(receiptInfo.ProductId)
	if not product then
		warn(
			string.format(
				"[Monetization] unknown developer product %s (set productId in Config.Monetization)",
				tostring(receiptInfo.ProductId)
			)
		)
		return Marketplace.NotProcessedYet
	end
	if product.oncePerAccount and section.once[product.key] then
		-- The store hides bought once-only products; never grant twice, and don't take the
		-- Robux for nothing either.
		warn(string.format("[Monetization] %s already bought %s (once per account)", tostring(receiptInfo.PlayerId), product.key))
		return Marketplace.NotProcessedYet
	end

	processing[purchaseId] = true
	local granted = grant(player, product, receiptInfo)
	processing[purchaseId] = nil
	if not granted then
		return Marketplace.NotProcessedYet
	end

	-- The handler may have yielded; the player could have left in the meantime.
	section = ctx:Section(player)
	if not section then
		return Marketplace.NotProcessedYet
	end
	recordReceipt(section, purchaseId, product.key)
	if product.oncePerAccount then
		section.once[product.key] = true
		ctx:Dirty(player, "once", product.key)
	end
	ctx:RequestSave(player)
	local robux = tonumber(receiptInfo.CurrencySpent) or product.price or 0
	ctx.Bus:Publish("Purchase", player, { product = product.key, robux = robux })
	ctx.Analytics.Custom(player, "Purchase", robux, { product = product.key })
	return Marketplace.PurchaseGranted
end

-- Public API ---------------------------------------------------------------------------

function Monetization:HasPass(player, key: string): boolean
	local s = ctx:Session(player)
	return s ~= nil and s.passes ~= nil and s.passes[key] == true
end

function Monetization:PaidRandomAllowed(player): boolean
	local s = ctx:Session(player)
	return s ~= nil and s.paidRandomAllowed == true
end

function Monetization:RegisterProduct(handlerKey: string, fn)
	assert(type(handlerKey) == "string" and type(fn) == "function", "[Monetization] RegisterProduct(handlerKey, fn)")
	if productHandlers[handlerKey] then
		warn("[Monetization] product handler registered twice: " .. handlerKey)
	end
	productHandlers[handlerKey] = fn
end

function Monetization:AdsLeft(player, placement: string): number
	local def = Config.Ads[placement]
	if not def or not ctx.Config.Flags.RewardedAds then
		return 0
	end
	local ads = adsSection(player)
	if not ads then
		return 0
	end
	return math.max(0, def.cap - (ads.counts[placement] or 0))
end

function Monetization:CanWatchAd(player, placement: string): (boolean, string?)
	if not Config.Ads[placement] or not ctx.Config.Flags.RewardedAds then
		return false, "Ads aren't available right now"
	end
	if watching[player] then
		return false, "An ad is already playing"
	end
	if Monetization:AdsLeft(player, placement) <= 0 then
		return false, "No more ads for this today. Come back tomorrow!"
	end
	return true, nil
end

function Monetization:WatchAd(player, placement: string): boolean
	if not Config.Ads[placement] then
		warn("[Monetization] unknown ad placement " .. tostring(placement))
		return false
	end
	if not Monetization:CanWatchAd(player, placement) then
		return false
	end
	watching[player] = true
	local ok, completed = pcall(ctx.Services.Ads.ShowRewarded, player, placement)
	watching[player] = nil
	if not ok or completed ~= true then
		return false
	end
	-- The ad yields for a while: the player may have left, or the UTC day may have rolled.
	local ads = adsSection(player)
	if not ads then
		return false
	end
	ads.counts[placement] = (ads.counts[placement] or 0) + 1
	ctx:Dirty(player, "ads")
	ctx.Bus:Publish("AdWatched", player, { placement = placement })
	ctx.Analytics.Custom(player, "AdWatched", 1, { placement = placement })
	return true
end

-- Lifecycle ----------------------------------------------------------------------------

function Monetization.Init(context)
	ctx = context
	Config = ctx.Config.Monetization
	Rewards = ctx:GetSystem("Rewards")
	-- Module state belongs to one kernel (tests boot several in one process).
	table.clear(productHandlers)
	table.clear(processing)
	table.clear(watching)

	ctx.Services.Marketplace.SetProcessReceipt(function(receiptInfo)
		local ok, result = pcall(processReceipt, receiptInfo)
		if not ok then
			warn("[Monetization] ProcessReceipt errored: " .. tostring(result))
			processing[tostring(receiptInfo and receiptInfo.PurchaseId)] = nil
			return ctx.Services.Marketplace.NotProcessedYet
		end
		return result
	end)

	ctx.Services.Marketplace.OnPassPurchased(function(player, gamePassId)
		local pass = passById(gamePassId)
		if pass and ctx:IsReady(player) and setOwned(player, { pass.key }) then
			ctx:Notify(player, pass.name .. " unlocked!", "success")
			ctx.Analytics.Custom(player, "PassPurchased", pass.price, { pass = pass.key })
		end
	end)

	ctx.Net:Handle("Monetization.RefreshPasses", function(player)
		setOwned(player, checkOwnership(player))
		return { passes = table.clone(session(player).passes) }
	end)
end

function Monetization.PlayerAdded(player, _info)
	local s = session(player)
	s.paidRandomAllowed = ctx.Services.Policy.PaidRandomItemsAllowed(player) == true
	ctx:DirtySession(player, "paidRandomAllowed")
	local owned = checkOwnership(player)
	if #owned > 0 then
		-- Systems whose PlayerAdded ran before ours (e.g. incubator slots) recompute on this.
		setOwned(player, owned)
	end
	adsSection(player)
end

function Monetization.PlayerRemoving(player)
	watching[player] = nil
end

return Monetization
