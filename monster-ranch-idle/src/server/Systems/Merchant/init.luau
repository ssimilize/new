--[[
	Merchant (update 3.11 · Seasons & secrets): the Travelling Merchant. A caravan parks in the
	Market Square for Config.Merchant.Stay seconds out of every Cycle (the client draws it and its
	"Trade" prompt, Controllers/Merchant). Each visit sells the same Slots offers to everyone
	(Logic/Merchant.Stock); each player may buy an offer up to its limit per visit, paying one of
	its ways to pay (coins, gems, amber, fish, Pantry dishes or 3.12 honey), all or nothing.

	Save section (profile.Merchant), version 1:
	  visit   = the visit `bought` counts (a new visit clears it)
	  bought  = { [offerId] = n }   bought this visit
	  scrolls = Trait Scrolls owned (at most Config.Merchant.ScrollCap)
	  rerolls = scrolls ever read; seeds the next reroll, so a rejoin never rerolls
	  trades  = purchases ever
	Session (session.Merchant): { shovels }  the Dig Site is plugged in and unlocked for this player

	Actions:
	  Merchant.Buy { offer, pay }   -> { offer, pay, amount, bought, left, total? }
	  Merchant.Reroll { id, slot }  -> { trait, old, scrolls }   a Trait Scroll rerolls one visible
	                                   trait (Logic/Merchant.Reroll: hatch weights, never the hidden
	                                   trait, never a duplicate)

	Delivery: scroll (this section), seeds (Kitchen:AddSeeds), bait (Fishing:AddBait), shovels
	(DigSite:AddShovels, only while DigSite is plugged in and `dig_site` is unlocked), decor and
	egg (Rewards, source "merchant"), tower_retry (TrialTower:AddRetries, 3.12). Kitchen, Fishing,
	DigSite, TrialTower and Ranch are optional and looked up in Start; a missing one means its
	offers (and ways to pay) are refused.

	Bus: publishes MerchantBought (player, { item, pay }) per purchase (Weekly goal "merchant_3").
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local Logic = require(Shared.Logic.Merchant)

local Merchant = {
	Name = "Merchant",
	Dependencies = { "Currency", "Progression", "Monsters", "Rewards" },
	OptionalDependencies = { "Kitchen", "Fishing", "DigSite", "Ranch", "Apiary", "TrialTower" },
}

Merchant.Profile = {
	Version = 1,
	Default = function()
		return { visit = 0, bought = {}, scrolls = 0, rerolls = 0, trades = 0 }
	end,
	Migrate = function(section)
		return section
	end,
}

local DIG_UNLOCK = "dig_site"
local TICK = 5

local ctx
local Config, Rules
local Currency, Progression, Monsters, Rewards
local Kitchen, Fishing, DigSite, Ranch, Apiary, TrialTower

local announced = {} -- [player] = the visit already announced

local function section(player)
	return ctx:Section(player)
end

local function digOpen(player): boolean
	return DigSite ~= nil and Config.Unlocks.Features[DIG_UNLOCK] ~= nil and Progression:IsUnlocked(player, DIG_UNLOCK)
end

local function refreshSession(player)
	local sess = ctx:Session(player)
	if not sess or not section(player) then
		return
	end
	local shovels = digOpen(player)
	if sess.shovels ~= shovels then
		sess.shovels = shovels
		ctx:DirtySession(player)
	end
end

-- Clears `bought` when a new visit has started.
local function refreshVisit(player, s, visit: number)
	if s.visit ~= visit then
		s.visit = visit
		s.bought = {}
		ctx:Dirty(player, "visit")
		ctx:Dirty(player, "bought")
	end
end

local function income(player): number
	if Ranch then
		local ok, n = pcall(Ranch.IncomePerSecond, Ranch, player)
		if ok and type(n) == "number" then
			return n
		end
	end
	return 0
end

-- Fails the request when this slot cannot be delivered to this player right now.
local function checkDelivery(player, s, slot)
	if slot.unlock and Config.Unlocks.Features[slot.unlock] then
		Progression:Require(player, slot.unlock)
	end
	if slot.kind == "scroll" then
		if (s.scrolls or 0) + slot.amount > Rules.ScrollCap then
			ctx:Fail("You can't carry more Trait Scrolls")
		end
	elseif slot.kind == "seeds" then
		if not Kitchen then
			ctx:Fail("The Kitchen isn't open yet")
		end
	elseif slot.kind == "bait" then
		if not Fishing then
			ctx:Fail("The Fishing Pond isn't open yet")
		end
	elseif slot.kind == "shovels" then
		if not digOpen(player) then
			ctx:Fail("The Dig Site isn't open yet")
		end
	elseif slot.kind == "tower_retry" then
		if not TrialTower then
			ctx:Fail("The Trial Tower isn't open yet")
		end
	end
end

-- Takes the price, all or nothing (fails the request when it can't).
local function charge(player, pay, amount: number)
	if pay.kind == "coins" or pay.kind == "gems" or pay.kind == "amber" then
		Currency:Charge(player, { [pay.kind] = amount }, "merchant")
	elseif pay.kind == "fish" then
		if not Fishing or not Fishing:SpendFish(player, amount) then
			ctx:Fail("Not enough fish")
		end
	elseif pay.kind == "dishes" then
		if not Kitchen or not Kitchen:SpendDishes(player, amount) then
			ctx:Fail("Not enough Pantry dishes")
		end
	elseif pay.kind == "honey" then
		-- 3.12: any honey but Royal Jelly, the most plentiful kind first (Apiary:SpendAnyHoney).
		if not Apiary or not Apiary:SpendAnyHoney(player, amount) then
			ctx:Fail("Not enough honey")
		end
	else
		ctx:Fail("That way to pay isn't offered")
	end
end

local function deliver(player, s, slot): number?
	if slot.kind == "scroll" then
		s.scrolls = (s.scrolls or 0) + slot.amount
		ctx:Dirty(player, "scrolls")
		return s.scrolls
	elseif slot.kind == "seeds" then
		return Kitchen:AddSeeds(player, slot.amount)
	elseif slot.kind == "bait" then
		return Fishing:AddBait(player, slot.amount)
	elseif slot.kind == "shovels" then
		return DigSite:AddShovels(player, slot.amount)
	elseif slot.kind == "tower_retry" then
		return TrialTower:AddRetries(player, slot.amount)
	elseif slot.kind == "decor" or slot.kind == "egg" then
		Rewards:Grant(player, { { kind = slot.kind, id = slot.item, amount = slot.amount } }, "merchant", { silent = true })
	end
	return nil
end

-- Actions ----------------------------------------------------------------------------------

local function buy(player, payload)
	Progression:Require(player, Rules.Unlock)
	local now = ctx:Now()
	local at = Logic.At(now)
	if not at.present then
		ctx:Fail(string.format("The merchant is away. Back in %s", Format.duration(at.nextAt - now)))
	end
	local slot = Logic.Find(at.visit, payload.offer)
	if not slot then
		ctx:Fail("The merchant isn't selling that this visit")
	end
	local pay = slot.pay[payload.pay]
	if not pay then
		ctx:Fail("That way to pay isn't offered")
	end
	local s = section(player)
	refreshVisit(player, s, at.visit)
	local have = s.bought[slot.offer] or 0
	if have >= slot.limit then
		ctx:Fail("You bought all of those this visit")
	end
	checkDelivery(player, s, slot)
	local amount = Logic.PayAmount(pay, income(player))
	charge(player, pay, amount)
	local total = deliver(player, s, slot)

	s.bought[slot.offer] = have + 1
	s.trades = (s.trades or 0) + 1
	ctx:Dirty(player, "bought", slot.offer)
	ctx:Dirty(player, "trades")
	ctx.Bus:Publish("MerchantBought", player, { item = slot.offer, pay = pay.kind })
	ctx.Analytics.Custom(player, "MerchantBought", amount, { item = slot.offer, pay = pay.kind })
	return {
		offer = slot.offer,
		pay = pay.kind,
		amount = amount,
		bought = have + 1,
		left = slot.limit - have - 1,
		total = total,
	}
end

local function reroll(player, payload)
	Progression:Require(player, Rules.Unlock)
	local s = section(player)
	if (s.scrolls or 0) <= 0 then
		ctx:Fail("No Trait Scrolls left")
	end
	local m, why = Monsters:Available(player, payload.id)
	if not m then
		ctx:Fail(why or "That monster doesn't exist")
	end
	if type(m.traits) ~= "table" or m.traits[payload.slot] == nil then
		ctx:Fail("That trait slot is empty")
	end
	local n = s.rerolls or 0
	local trait = Logic.Reroll(m, payload.slot, Logic.ScrollSeed(player.UserId, m, n))
	if not trait then
		ctx:Fail("No other trait can roll in that slot")
	end
	local old = m.traits[payload.slot]
	m.traits[payload.slot] = trait
	Monsters:Changed(player, m.id, { "traits" })
	s.scrolls -= 1
	s.rerolls = n + 1
	ctx:Dirty(player, "scrolls")
	ctx:Dirty(player, "rerolls")
	ctx.Bus:Publish("RateModifiersChanged", player, {})
	local def = Config.Traits.ById[trait]
	ctx:Notify(player, string.format("%s rolled %s", Formulas.DisplayName(m), if def then def.name else tostring(trait)), "reward")
	ctx.Analytics.Custom(player, "MerchantReroll", n + 1, { trait = tostring(trait) })
	return { trait = trait, old = old, scrolls = s.scrolls }
end

-- Public API ------------------------------------------------------------------------------

function Merchant:Scrolls(player): number
	local s = section(player)
	return if s then s.scrolls or 0 else 0
end

-- Lifecycle -------------------------------------------------------------------------------

local function announce(player)
	local at = Logic.At(ctx:Now())
	if at.present and announced[player] ~= at.visit and Progression:IsUnlocked(player, Rules.Unlock) then
		announced[player] = at.visit
		ctx:Notify(player, "The Travelling Merchant is in the Market Square!", "info")
	end
end

function Merchant.Init(context)
	ctx = context
	Config = ctx.Config
	Rules = Config.Merchant
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	Rewards = ctx:GetSystem("Rewards")

	ctx.Net:Handle("Merchant.Buy", buy)
	ctx.Net:Handle("Merchant.Reroll", reroll)

	ctx.Bus:Subscribe("LevelUp", function(player)
		if player and section(player) then
			refreshSession(player)
		end
	end)
	ctx:Every(TICK, function()
		for _, player in ctx:Players() do
			if section(player) then
				announce(player)
			end
		end
	end)
end

function Merchant.Start()
	Kitchen = ctx:GetSystem("Kitchen")
	Fishing = ctx:GetSystem("Fishing")
	DigSite = ctx:GetSystem("DigSite")
	TrialTower = ctx:GetSystem("TrialTower") -- 3.12: Retry tokens
	Ranch = ctx:GetSystem("Ranch")
	Apiary = ctx:GetSystem("Apiary")
end

function Merchant.PlayerAdded(player)
	local s = section(player)
	s.bought = if type(s.bought) == "table" then s.bought else {}
	s.scrolls = tonumber(s.scrolls) or 0
	s.rerolls = tonumber(s.rerolls) or 0
	s.trades = tonumber(s.trades) or 0
	refreshVisit(player, s, Logic.Visit(ctx:Now()))
	refreshSession(player)
end

function Merchant.PlayerRemoving(player)
	announced[player] = nil
end

return Merchant
