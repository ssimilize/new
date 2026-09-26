--[[
	Monetization (S6): game passes, developer products (ProcessReceipt) and rewarded ads.

	Design rule (Config/Monetization.luau): nothing here skips a timer. Robux buys parallel
	capacity, convenience, cosmetics and server-wide fun; ads give a small, capped boost.

	Save section (profile.Monetization), version 2:
	  ads      = { day, counts = { [placement] = n } }   -- reset every UTC day
	  once     = { [productKey] = true }                 -- oncePerAccount products bought
	  vip      = { day, opened }                         -- v2: UTC day of the last VIP crate, crates opened
	  receipts = { { id, product, t, fallback? } }       -- PRIVATE, newest last, ≤ Config.ReceiptHistory

	Session (session.Monetization):
	  passes            = { [passKey] = boolean }         -- every pass key, cached on join
	  paidRandomAllowed = boolean                         -- PolicyService, cached on join (fails closed)

	Global (global.Monetization):
	  vip = { ['u'..userId] = true }                      -- VIP owners in this server (chat tags)

	Actions:
	  Monetization.RefreshPasses                  -> { passes }
	  Monetization.CanBuy { product }             -> nil, or fails with why it can't be bought now
	  Monetization.ClaimVipCrate                  -> { rewards, day }   (also fires Rewards.Granted)

	Public API (other systems):
	  Monetization:HasPass(player, key) -> boolean                     -- cached value only (no yield)
	  Monetization:RegisterProduct(handlerKey, fn(player, product, receiptInfo) -> boolean)
	  Monetization:WatchAd(player, placement) -> boolean                -- YIELDS; counts completed views only
	  Monetization:CanWatchAd(player, placement) -> boolean, reason?   -- no yield; reason is player-facing
	  Monetization:AdsLeft(player, placement) -> number
	  Monetization:PaidRandomAllowed(player) -> boolean
	  Monetization:RegisterProductCheck(handlerKey, fn(player, product) -> (boolean, reason?))
	  Monetization:CanBuy(player, productKey) -> boolean, reason?     -- no yield; reason is player-facing

	Publishes PassesChanged and RateModifiersChanged (pass ownership changed, including on join
	when the player owns any pass), Purchase and AdWatched.

	Receipts are idempotent: a PurchaseId already in `receipts` returns PurchaseGranted without
	granting again, and a receipt being processed right now is never processed twice at once.
	Anything that can't be granted yet (player not here, unknown product, missing or failing
	handler) returns NotProcessedYet, so Roblox retries on a later join.

	Purchases that can't be honoured as bought are refused before the prompt (CanBuy: the Store
	and the Quests screen ask first; product handlers add their own rule with
	RegisterProductCheck). A receipt that arrives anyway still gets fair value, never nothing:
	  - a once-per-account product bought again pays Config.GemValue(price) gems (the best gem-pack
	    rate for what was spent) and is recorded with `fallback = "gems"`;
	  - the Ranch Pass handler (Quests) banks a pass bought outside a season, or a second one in
	    the same season, for the next season.
	Both go through the same receipt history, so a replayed receipt is never paid twice.

	VIP crate: one per UTC day for VIP owners (missed days don't stack), rolled by Logic/Vip from
	Config.VipCrate, seeded by (userId, day); the fixed gift where paid random items are
	restricted. The day is recorded before anything is granted.
]]

local Monetization = {
	Name = "Monetization",
	Dependencies = { "Rewards" },
}

local Shared = game:GetService("ReplicatedStorage").Shared
local Vip = require(Shared.Logic.Vip)

local DEFAULT_RECEIPT_HISTORY = 200

Monetization.Profile = {
	Version = 2,
	Default = function()
		return { ads = { day = 0, counts = {} }, once = {}, vip = { day = 0, opened = 0 }, receipts = {} }
	end,
	Migrate = function(section, fromVersion)
		if fromVersion < 2 and type(section.vip) ~= "table" then
			section.vip = { day = 0, opened = 0 } -- v2: VIP daily crate
		end
		return section
	end,
	Private = { "receipts" },
}

local ctx
local Config -- Config.Monetization
local Rewards

local productHandlers = {} -- [handlerKey] = fn(player, product, receiptInfo) -> boolean
local productChecks = {} -- [handlerKey] = fn(player, product) -> (boolean, reason?)
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

-- VIP owners are listed server-wide so every client can tag their chat messages.
local function setVipTag(player, on: boolean)
	local global = ctx:Global()
	global.vip = global.vip or {}
	local key = "u" .. tostring(player.UserId)
	if (global.vip[key] == true) ~= on then
		global.vip[key] = if on then true else nil
		ctx:DirtyGlobal("vip")
	end
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
		setVipTag(player, s.passes[Config.VipCrate.pass] == true)
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

local function recordReceipt(section, purchaseId: string, productKey: string, fallback: string?)
	table.insert(section.receipts, { id = purchaseId, product = productKey, t = ctx:Now(), fallback = fallback })
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

-- What a repeat once-per-account product pays instead (see the header).
local function grantDuplicate(player, product): boolean
	local gems = Config.GemValue(product.price or 0)
	local ok, err = pcall(function()
		Rewards:Grant(player, { { kind = "gems", amount = gems } }, "purchase:" .. product.key)
	end)
	if not ok then
		warn(string.format("[Monetization] duplicate %s fallback failed: %s", product.key, tostring(err)))
		return false
	end
	ctx:Notify(player, string.format("You already own the %s, so you got %d gems instead.", product.name, gems), "reward")
	return true
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
	-- The Store shows bought once-only products as Owned and CanBuy refuses them, so this is a
	-- stale client or a second device: never grant the pack twice, never keep Robux for nothing.
	local duplicate = product.oncePerAccount == true and section.once[product.key] == true

	processing[purchaseId] = true
	local granted
	if duplicate then
		granted = grantDuplicate(player, product)
	else
		granted = grant(player, product, receiptInfo)
	end
	processing[purchaseId] = nil
	if not granted then
		return Marketplace.NotProcessedYet
	end

	-- The handler may have yielded; the player could have left in the meantime.
	section = ctx:Section(player)
	if not section then
		return Marketplace.NotProcessedYet
	end
	recordReceipt(section, purchaseId, product.key, if duplicate then "gems" else nil)
	if product.oncePerAccount and not duplicate then
		section.once[product.key] = true
		ctx:Dirty(player, "once", product.key)
	end
	ctx:RequestSave(player)
	local robux = tonumber(receiptInfo.CurrencySpent) or product.price or 0
	ctx.Bus:Publish("Purchase", player, { product = product.key, robux = robux })
	ctx.Analytics.Custom(player, "Purchase", robux, { product = product.key, fallback = if duplicate then "gems" else nil })
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

function Monetization:RegisterProductCheck(handlerKey: string, fn)
	assert(type(handlerKey) == "string" and type(fn) == "function", "[Monetization] RegisterProductCheck(handlerKey, fn)")
	productChecks[handlerKey] = fn
end

function Monetization:CanBuy(player, productKey: string): (boolean, string?)
	local product = Config.ProductByKey[productKey]
	if not product then
		return false, "That item isn't for sale"
	end
	local section = ctx:Section(player)
	if not section then
		return false, "Your ranch is still loading"
	end
	if product.oncePerAccount and section.once[product.key] == true then
		return false, "You already own this"
	end
	local check = product.handler and productChecks[product.handler]
	if check then
		local ok, allowed, reason = pcall(check, player, product)
		if not ok then
			warn(string.format("[Monetization] check '%s' errored: %s", product.handler, tostring(allowed)))
			return false, "Purchase unavailable right now"
		end
		if allowed ~= true then
			return false, reason or "Purchase unavailable right now"
		end
	end
	return true, nil
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
	table.clear(productChecks)
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

	ctx.Net:Handle("Monetization.CanBuy", function(player, payload)
		local ok, reason = Monetization:CanBuy(player, payload.product)
		if not ok then
			ctx:Fail(reason or "Purchase unavailable right now")
		end
		return nil
	end)

	ctx.Net:Handle("Monetization.ClaimVipCrate", function(player)
		local crate = Config.VipCrate
		local section = ctx:Section(player)
		if not section then
			ctx:Fail("Your ranch is still loading")
		end
		if not Monetization:HasPass(player, crate.pass) then
			ctx:Fail("The VIP crate comes with the VIP Rancher pass")
		end
		local today = ctx:Day()
		if not Vip.CrateReady(true, section.vip.day, today) then
			ctx:Fail("You already opened today's VIP crate. Come back tomorrow!")
		end
		-- Record the claim before granting: nothing below yields, and a failure can't repeat it.
		section.vip.day = today
		section.vip.opened = (tonumber(section.vip.opened) or 0) + 1
		ctx:Dirty(player, "vip")
		local items = Vip.RollCrate(crate, player.UserId, today, Monetization:PaidRandomAllowed(player))
		local granted = Rewards:Grant(player, items, crate.source)
		ctx:RequestSave(player)
		ctx.Analytics.Custom(player, "VipCrate", 1, { day = today })
		return { rewards = granted, day = today }
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
	setVipTag(player, false)
end

return Monetization
