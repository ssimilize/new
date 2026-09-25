--[[
	Market listings (part of Market): pure functions over listing records, so the rules that
	decide who wins a sale are testable without a server. Transforms passed to
	Services.Market.Update run on a fresh copy of the record, may run more than once and
	return nil for "no change", so none of them has side effects.

	Listing record (ARCHITECTURE §8), plus:
	  view   = the public item view, stored with the listing because the browse index keeps
	           everything except `item` (the escrowed record never leaves the DataStore)
	  token  = the request that closed it (sale or close), to recognise our own write when an
	           Update reports a failure after it had already landed

	Client view (Market.Browse / Mine / List):
	  { id, seller, sellerName, kind, key, price, createdAt, expiresAt, club = boolean,
	    mine = boolean, state, item = ItemView }
	  ItemView = { appearance = Appearance | false, egg = eggType | false, name, rarity, variant,
	               stage, lv, stars, weight, muts = { string }, traits = { traitId } }
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Appearance = require(Shared.Logic.Appearance)
local Formulas = require(Shared.Logic.Formulas)

local Cfg = Config.Market

local Listing = {}

-- Public view of an item: what every player may see. Never the hidden trait, never ids.
function Listing.ItemView(kind: string, record)
	if kind == "egg" then
		local def = Config.Eggs.ById[record.type]
		return {
			appearance = false,
			egg = record.type,
			name = if def then def.name else tostring(record.type),
			rarity = 0,
			variant = 0,
			stage = 0,
			lv = 0,
			stars = 0,
			weight = 0,
			muts = {},
			traits = {},
		}
	end
	return {
		appearance = Appearance.Of(record),
		egg = false,
		name = Formulas.DisplayName(record),
		rarity = record.rarity,
		variant = record.variant or 0,
		stage = record.stage,
		lv = record.lv or 1,
		stars = record.stars or 1,
		weight = record.weight,
		muts = table.clone(record.muts or {}),
		traits = table.clone(record.traits or {}),
	}
end

function Listing.New(spec)
	return {
		id = spec.id,
		seller = spec.seller,
		sellerName = spec.sellerName,
		kind = spec.kind,
		item = spec.item,
		key = Cfg.ItemKey(spec.kind, spec.item),
		price = spec.price,
		createdAt = spec.now,
		expiresAt = spec.now + Cfg.DurationSeconds,
		club = spec.club or false,
		state = "open",
		view = Listing.ItemView(spec.kind, spec.item),
	}
end

-- "L<seller>-<unix>-<seq>": unique without a JobId because seq is saved with the seller.
function Listing.Id(userId: number, now: number, seq: number): string
	return string.format("L%d-%d-%d", userId, now, seq)
end

function Listing.View(listing, viewerId: number)
	local item = listing.view
	if type(item) ~= "table" then
		item = if type(listing.item) == "table" then Listing.ItemView(listing.kind, listing.item) else false
	end
	return {
		id = listing.id,
		seller = listing.seller,
		sellerName = listing.sellerName or "",
		kind = listing.kind,
		key = listing.key,
		price = listing.price,
		createdAt = listing.createdAt,
		expiresAt = listing.expiresAt,
		club = listing.club ~= false and listing.club ~= nil,
		mine = listing.seller == viewerId,
		state = listing.state or "open",
		item = item,
	}
end

function Listing.IsOpen(listing, now: number): boolean
	return type(listing) == "table" and listing.state == "open" and (listing.expiresAt or 0) > now
end

-- Open, unexpired listings matching the optional kind and key.
function Listing.Filter(list, now: number, kind: string?, key: string?)
	local out = {}
	for _, listing in list do
		if
			type(listing) == "table"
			and (listing.state == nil or listing.state == "open")
			and (listing.expiresAt or 0) > now
			and (kind == nil or listing.kind == kind)
			and (key == nil or listing.key == key)
		then
			table.insert(out, listing)
		end
	end
	return out
end

-- Sorts in place: "price" cheapest first, "-price" dearest first, "new" newest first.
function Listing.Sort(list, sort: string?)
	table.sort(list, function(a, b)
		if sort == "new" then
			if a.createdAt ~= b.createdAt then
				return a.createdAt > b.createdAt
			end
		elseif a.price ~= b.price then
			return if sort == "-price" then a.price > b.price else a.price < b.price
		end
		return a.id < b.id
	end)
	return list
end

-- Returns page `page` (1-based) and whether more pages follow.
function Listing.Page(list, page: number, size: number)
	local out = {}
	local first = (page - 1) * size + 1
	for i = first, math.min(#list, first + size - 1) do
		table.insert(out, list[i])
	end
	return out, #list > page * size
end

-- Transform: open → sold to `buyer`, only while the listing still matches what they saw.
function Listing.Sell(current, buyer: { userId: number, name: string }, price: number, now: number, token: string)
	if not Listing.IsOpen(current, now) or current.price ~= price or current.seller == buyer.userId then
		return nil
	end
	current.state = "sold"
	current.buyer = buyer.userId
	current.buyerName = buyer.name
	current.closedAt = now
	current.token = token
	return current
end

-- Transform: open → cancelled (or expired once its time is up) by its seller.
function Listing.Close(current, sellerId: number, now: number, token: string, reason: string)
	if type(current) ~= "table" or current.state ~= "open" or current.seller ~= sellerId then
		return nil
	end
	if reason == "expired" and current.expiresAt > now then
		return nil
	end
	current.state = if current.expiresAt <= now then "expired" else reason
	current.closedAt = now
	current.token = token
	return current
end

-- Transform used after a Create that reported failure: if the write landed anyway, close it
-- without returning the item (the seller already has it back).
function Listing.Void(current, sellerId: number, now: number)
	if type(current) ~= "table" or current.state ~= "open" or current.seller ~= sellerId then
		return nil
	end
	current.state = "cancelled"
	current.closedAt = now
	current.void = true
	return current
end

return Listing
