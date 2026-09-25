--[[
	Shop (S3): the Egg Shop on the global restock clock, the Feed Store, decor and pen themes,
	and the daily free egg (rewarded ad).

	Save section (profile.Shop):
	  window     = number                   -- restock window the `bought` counts belong to
	  bought     = { [eggType] = n }        -- eggs bought this window (reset every restock)
	  decor      = { [decorId] = n }        -- decor in storage (placed decor lives in Ranch pens)
	  themes     = { [themeId] = true }     -- bought pen themes (free themes are always owned)
	  freeEggDay = number                   -- UTC day of the last free-egg claim (0 = never)
	Global (global.Shop): { window, endsAt, stock = { [eggType] = n } }
	  n = -1 unlimited, 0 not in this restock; only eggs on sale right now are listed.

	Stock comes from Logic/Restock, seeded by the window number, so every server shows the
	same eggs at the same moment. Stock is a per-player allowance for the window.

	Public API (other systems):
	  Shop:AddDecor(player, decorId, n)
	  Shop:TakeDecor(player, decorId) -> boolean     -- storage → pen (Ranch)
	  Shop:ReturnDecor(player, decorId)              -- pen → storage (Ranch)
	  Shop:OwnsTheme(player, themeId) -> boolean
	  Shop:GrantTheme(player, themeId) -> boolean   -- free grant (Rebirth biomes)
	  Shop:DecorCount(player, decorId) -> number
	  Shop:Stock(eggType) -> number?                 -- this window's stock (nil = not on sale)
	  Shop:Left(player, eggType) -> number           -- what the player can still buy (-1 unlimited)

	Paid random items (Starlit Egg): blocked unless Monetization:PaidRandomAllowed(player),
	falling back to ctx.Services.Policy when Monetization is not plugged in (cached per player).
	Publishes EggBought and RanchXP (buyEgg).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Restock = require(Shared.Logic.Restock)

local Shop = {
	Name = "Shop",
	Dependencies = { "Currency", "Progression", "Eggs" },
	OptionalDependencies = { "Monetization", "Rebirth" },
}

Shop.Profile = {
	Version = 1,
	Default = function()
		return { window = 0, bought = {}, decor = {}, themes = {}, freeEggDay = 0 }
	end,
}

local ctx
local Config
local Currency, Progression, Eggs

local policyCache = {} -- [player] = boolean (Policy fallback only)
local claiming = {} -- [player] = true while the free-egg ad is showing
local lastEvent -- the running event (Config.Events) the current stock was rolled for

-- Helpers ------------------------------------------------------------------------------

local function section(player)
	return ctx:Section(player)
end

local function monetization()
	return ctx:GetSystem("Monetization")
end

local function paidRandomAllowed(player): boolean
	local M = monetization()
	if M and M.PaidRandomAllowed then
		local ok, result = pcall(M.PaidRandomAllowed, M, player)
		return ok and result == true
	end
	local cached = policyCache[player]
	if cached == nil then
		local ok, result = pcall(ctx.Services.Policy.PaidRandomItemsAllowed, player)
		cached = ok and result == true
		policyCache[player] = cached
	end
	return cached
end

local function eventActive(eventId: string?): boolean
	return eventId == nil or eventId == Config.Events.ActiveId(ctx:Now())
end

local function restock(force: boolean?)
	local g = ctx:Global()
	local window = Restock.Window(ctx:Now())
	local event = Config.Events.ActiveId(ctx:Now())
	if not force and g.window == window and lastEvent == event then
		return false
	end
	local newWindow = g.window ~= window
	g.window = window
	g.endsAt = Restock.EndsAt(window)
	g.stock = Restock.Roll(window, event)
	lastEvent = event
	ctx:DirtyGlobal()
	return newWindow
end

-- Moves a player's bought counts onto the current window.
local function syncWindow(player)
	local s = section(player)
	local window = ctx:Global().window
	if s and s.window ~= window then
		s.window = window
		s.bought = {}
		ctx:Dirty(player, "window")
		ctx:Dirty(player, "bought")
	end
end

local function charge(player, price, reason: string, times: number?)
	local cost = Currency:NormalizeCost(price)
	for key, amount in cost do
		cost[key] = amount * (times or 1)
	end
	Currency:Charge(player, cost, reason)
	return cost
end

local function watchAd(player, placement: string)
	local M = monetization()
	if not M or not Config.Flags.RewardedAds then
		ctx:Fail("Ads aren't available")
	end
	if M.CanWatchAd then
		local ok, why = M:CanWatchAd(player, placement)
		if not ok then
			ctx:Fail(why or "Ads aren't available")
		end
	elseif M.AdsLeft and M:AdsLeft(player, placement) <= 0 then
		ctx:Fail("No more ads today. Come back tomorrow!")
	end
	if not M:WatchAd(player, placement) then
		ctx:Fail("The ad didn't finish")
	end
end

-- Public API ------------------------------------------------------------------------------

function Shop:Stock(eggType: string): number?
	restock(false)
	return ctx:Global().stock[eggType]
end

function Shop:Left(player, eggType: string): number
	local stock = Shop:Stock(eggType)
	if stock == nil then
		return 0
	end
	if stock == Restock.Unlimited then
		return -1
	end
	syncWindow(player)
	local s = section(player)
	return math.max(0, stock - (s and s.bought[eggType] or 0))
end

function Shop:DecorCount(player, decorId: string): number
	local s = section(player)
	return s and s.decor[decorId] or 0
end

function Shop:AddDecor(player, decorId: string, n: number?)
	local s = section(player)
	if not s then
		return
	end
	if not Config.Decor.ById[decorId] then
		warn("[Shop] AddDecor: unknown decor " .. tostring(decorId))
		return
	end
	s.decor[decorId] = (s.decor[decorId] or 0) + math.max(1, math.floor(n or 1))
	ctx:Dirty(player, "decor", decorId)
end

function Shop:TakeDecor(player, decorId: string): boolean
	local s = section(player)
	if not s or (s.decor[decorId] or 0) <= 0 then
		return false
	end
	s.decor[decorId] -= 1
	ctx:Dirty(player, "decor", decorId)
	return true
end

function Shop:ReturnDecor(player, decorId: string)
	Shop:AddDecor(player, decorId, 1)
end

function Shop:OwnsTheme(player, themeId: string): boolean
	local def = Config.Decor.PenThemeById[themeId]
	if not def then
		return false
	end
	if def.price == nil and not def.rebirth then
		return true
	end
	local s = section(player)
	return s ~= nil and s.themes[themeId] == true
end

-- Gives a theme without charging (Rebirth biomes). Returns false if already owned.
function Shop:GrantTheme(player, themeId: string): boolean
	local s = section(player)
	if not s or not Config.Decor.PenThemeById[themeId] or s.themes[themeId] == true then
		return false
	end
	s.themes[themeId] = true
	ctx:Dirty(player, "themes", themeId)
	return true
end

-- Lifecycle ----------------------------------------------------------------------------

function Shop.Init(context)
	ctx = context
	Config = ctx.Config
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Eggs = ctx:GetSystem("Eggs")

	restock(true)

	ctx.Net:Handle("Shop.BuyEgg", function(player, payload)
		local def = Config.Eggs.ById[payload.egg]
		local amount = payload.amount
		if def.price == nil then
			ctx:Fail("That egg isn't sold in the shop")
		end
		if not eventActive(def.event) then
			ctx:Fail("That event egg isn't available right now")
		end
		Progression:Require(player, def.unlock)
		if def.rebirths then
			local Rebirth = ctx:GetSystem("Rebirth")
			if not Rebirth or Rebirth:Stars(player) < def.rebirths then
				ctx:Fail(string.format("Rebirth your ranch to unlock the %s", def.name))
			end
		end
		if def.paidRandom and not paidRandomAllowed(player) then
			ctx:Fail("That egg isn't available for your account")
		end
		restock(false)
		syncWindow(player)
		local s = section(player)
		local stock = ctx:Global().stock[payload.egg]
		if stock == nil then
			ctx:Fail("That egg isn't in the shop right now")
		end
		if stock ~= Restock.Unlimited then
			local left = stock - (s.bought[payload.egg] or 0)
			if left <= 0 then
				ctx:Fail("Sold out. Wait for the next restock!")
			elseif amount > left then
				ctx:Fail(string.format("Only %d left in this restock", left))
			end
		end
		if Eggs:Room(player) < amount then
			ctx:Fail("Your egg storage is full. Hatch some eggs first!")
		end
		charge(player, def.price, "buyEgg", amount)

		s.bought[payload.egg] = (s.bought[payload.egg] or 0) + amount
		ctx:Dirty(player, "bought", payload.egg)
		local ids = Eggs:Add(player, payload.egg, "shop", amount)
		ctx.Bus:Publish("EggBought", player, { type = payload.egg, amount = amount })
		ctx.Bus:Publish("RanchXP", player, { amount = Config.Unlocks.XP.buyEgg * amount, reason = "buyEgg" })
		if def.price.gems then
			ctx:RequestSave(player)
		end
		return { eggs = ids }
	end)

	ctx.Net:Handle("Shop.BuyFood", function(player, payload)
		Currency:Charge(player, { coins = Config.Economy.FoodPrice * payload.amount }, "buyFood")
		Currency:Add(player, "food." .. payload.flavor, payload.amount, "shop")
		return nil
	end)

	ctx.Net:Handle("Shop.BuyDecor", function(player, payload)
		local def = Config.Decor.ById[payload.decor]
		if not def.price then
			ctx:Fail("That decor isn't for sale")
		end
		if not eventActive(def.event) then
			ctx:Fail("That event decor isn't available right now")
		end
		local cost = charge(player, def.price, "buyDecor")
		Shop:AddDecor(player, payload.decor, 1)
		if cost.gems then
			ctx:RequestSave(player)
		end
		return nil
	end)

	ctx.Net:Handle("Shop.BuyTheme", function(player, payload)
		local def = Config.Decor.PenThemeById[payload.theme]
		if Shop:OwnsTheme(player, payload.theme) then
			ctx:Fail("You already own that theme")
		end
		if def.price == nil then
			ctx:Fail("That theme isn't for sale")
		end
		if not eventActive(def.event) then
			ctx:Fail("That event theme isn't available right now")
		end
		local cost = charge(player, def.price, "buyTheme")
		section(player).themes[payload.theme] = true
		ctx:Dirty(player, "themes", payload.theme)
		if cost.gems then
			ctx:RequestSave(player)
		end
		return nil
	end)

	ctx.Net:Handle("Shop.ClaimFreeEgg", function(player)
		local s = section(player)
		if s.freeEggDay == ctx:Day() then
			ctx:Fail("You already claimed today's free egg. Come back tomorrow!")
		end
		if claiming[player] then
			ctx:Fail("An ad is already playing")
		end
		if Eggs:Room(player) < 1 then
			ctx:Fail("Your egg storage is full. Hatch some eggs first!")
		end
		claiming[player] = true
		local ok, err = pcall(watchAd, player, "freeEgg")
		claiming[player] = nil
		if not ok then
			error(err, 0) -- re-raise the player-facing failure
		end
		-- The ad yields: re-check against a claim that finished meanwhile (or a new day).
		s = section(player)
		if not s then
			ctx:Fail("Your ranch isn't loaded")
		end
		if s.freeEggDay == ctx:Day() then
			ctx:Fail("You already claimed today's free egg. Come back tomorrow!")
		end
		s.freeEggDay = ctx:Day()
		ctx:Dirty(player, "freeEggDay")
		local eggType = Config.Monetization.Ads.freeEgg.egg
		local id = Eggs:Add(player, eggType, "freeEgg", 1)[1]
		return { egg = id, type = eggType }
	end)

	-- The restock clock: roll the new window's stock and reset everyone's allowance.
	ctx:Every(1, function()
		if restock(false) then
			for _, player in ctx:Players() do
				syncWindow(player)
			end
		end
	end)
end

function Shop.PlayerAdded(player, _info)
	restock(false)
	syncWindow(player)
end

function Shop.PlayerRemoving(player)
	policyCache[player] = nil
	claiming[player] = nil
end

return Shop
