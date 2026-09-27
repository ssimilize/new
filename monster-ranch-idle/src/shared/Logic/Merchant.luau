--[[
	Merchant (update 3.11): the Travelling Merchant's schedule, stock and prices. Pure: server,
	client and tests agree without talking.

	  Merchant.Visit(now) -> number                 the visit index k whose cycle holds `now`
	  Merchant.At(now) -> { visit, present, startsAt, endsAt, nextAt }
	      present = the caravan is parked now; startsAt/endsAt = this cycle's visit;
	      nextAt = when the caravan next arrives (this cycle's start while present, else the next)
	  Merchant.Offerable(offer) -> boolean          its unlock key exists (else never rolled)
	  Merchant.Stock(visit) -> { Slot }             the visit's Slots offers, the same for everyone
	      Slot = { offer, kind, name, amount, limit, item?, pay = { Pay } }  item = decor / egg id
	  Merchant.Find(visit, offerId) -> Slot?
	  Merchant.CoinPrice(incomePerSecond, seconds) -> number
	  Merchant.PayText(pay, amount) -> string       "Pay 1,200 Coins", "Pay 3 Fish"
	  Merchant.ScrollSeed(userId, record, n) -> number
	  Merchant.Reroll(record, slot, seed) -> traitId?   a visible slot's new trait: the hatch roll
	      weights (Logic/Mastery.RerollTrait), never the hidden trait, never a duplicate
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)
local Format = require(script.Parent.Format)
local Mastery = require(script.Parent.Mastery)

local Cfg = Config.Merchant

local Merchant = {}

function Merchant.Visit(now: number): number
	return math.floor((now - Cfg.Offset) / Cfg.Cycle)
end

function Merchant.At(now: number)
	local visit = Merchant.Visit(now)
	local startsAt = visit * Cfg.Cycle + Cfg.Offset
	local endsAt = startsAt + Cfg.Stay
	local present = now >= startsAt and now < endsAt
	return {
		visit = visit,
		present = present,
		startsAt = startsAt,
		endsAt = endsAt,
		nextAt = if present then startsAt else startsAt + Cfg.Cycle,
	}
end

function Merchant.Offerable(offer): boolean
	return offer.unlock == nil or Config.Unlocks.Features[offer.unlock] ~= nil
end

local function pickWeighted(rng, list)
	local weights = {}
	for i, e in list do
		weights[i] = e.weight
	end
	return list[rng:Weighted(weights)]
end

local function slotOf(offer, visit: number, rng)
	local slot = {
		offer = offer.id,
		kind = offer.kind,
		name = offer.name,
		desc = offer.desc,
		amount = offer.amount,
		limit = offer.limit,
		unlock = offer.unlock,
		pay = offer.pay,
	}
	if offer.kind == "decor" then
		local id = Cfg.Decor[(visit + offer.decor) % #Cfg.Decor + 1]
		local def = Config.Decor.ById[id]
		slot.item = id
		slot.name = if def then def.name else id
		slot.desc = "A decor piece only the merchant sells."
	elseif offer.kind == "egg" then
		local id = pickWeighted(rng, offer.eggs).id
		local def = Config.Eggs.ById[id]
		slot.item = id
		slot.name = if def then def.name else id
		slot.desc = "An egg to hatch at your ranch."
	end
	return slot
end

function Merchant.Stock(visit: number)
	local rng = Rng.new(Rng.seed("merchant", visit))
	local pool = {}
	for _, offer in Cfg.Offers do
		if Merchant.Offerable(offer) then
			table.insert(pool, offer)
		end
	end
	local out = {}
	while #out < Cfg.Slots and #pool > 0 do
		local weights = {}
		for i, offer in pool do
			weights[i] = offer.weight
		end
		local index = rng:Weighted(weights)
		local offer = table.remove(pool, index)
		table.insert(out, slotOf(offer, visit, rng))
	end
	return out
end

function Merchant.Find(visit: number, offerId: string)
	for _, slot in Merchant.Stock(visit) do
		if slot.offer == offerId then
			return slot
		end
	end
	return nil
end

function Merchant.CoinPrice(incomePerSecond: number, seconds: number): number
	local income = if type(incomePerSecond) == "number" and incomePerSecond == incomePerSecond then incomePerSecond else 0
	return math.max(Cfg.MinCoins, math.floor(math.max(0, income) * seconds))
end

-- The amount of one way to pay (coins need the ranch income).
function Merchant.PayAmount(pay, incomePerSecond: number): number
	if pay.kind == "coins" and pay.seconds then
		return Merchant.CoinPrice(incomePerSecond, pay.seconds)
	end
	return pay.amount or 0
end

local PAY_FORMAT = {
	coins = "Pay %s Coins",
	gems = "Pay %s Gems",
	amber = "Pay %s Amber",
	fish = "Pay %s Fish",
	dishes = "Pay %s Dishes",
	honey = "Pay %s Honey", -- 3.12
}

function Merchant.PayText(pay, amount: number): string
	if pay.kind == "dishes" and amount == 1 then
		return "Pay 1 Dish"
	end
	return string.format(PAY_FORMAT[pay.kind] or "%s", Format.commas(amount))
end

function Merchant.ScrollSeed(userId: number, record, n: number): number
	return Rng.seed("merchant_scroll", userId, record.id, record.born or 0, n)
end

function Merchant.Reroll(record, slot: number, seed: number): number?
	return Mastery.RerollTrait(record, slot, seed)
end

return Merchant
