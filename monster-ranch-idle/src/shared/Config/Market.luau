--[[
	Market (update 1.3 · Market Day, design §18): asynchronous listings across every server.

	A seller lists a monster or an egg for a coin price. The item leaves their profile at
	once (escrow, stored in the listing), so it can never be traded, sold or duplicated
	while listed. Any player on any server can buy it; exactly one purchase can win. The
	seller receives `price × (1 − Tax)` in their mailbox (collected on any server); the tax
	is a coin sink. Listings that expire or are cancelled send the item back through the
	mailbox too.

	Club trading post: a listing can be posted to the seller's club only (`club = true`).
	Only members of that club see and buy it, and it pays `ClubTax` instead of `Tax`.

	Price history: every sale is recorded per item key (Market.ItemKey) in daily buckets
	for the last `HistoryDays` days (see Logic/PriceHistory and the PriceHistory system).
]]

local Market = {}

Market.Unlock = "market"
Market.Tax = 0.08
Market.ClubTax = 0.0
Market.MaxListings = 8 -- active listings per player
Market.DurationSeconds = 48 * 3600
Market.MinPrice = 100
Market.MaxPrice = 1e12
Market.PageSize = 24 -- listings per Market.Browse page
Market.MailSyncSeconds = 60 -- how often a server collects mail for its players
Market.HistoryDays = 30
Market.BrowseCacheSeconds = 10 -- a server may reuse a browse result this long

-- The item key groups listings and price history:
--   monsters: "m:<line>:<rarity>:<variant>"   (variant 0 normal, 1 golden, 2 rainbow)
--   eggs:     "e:<eggType>"
function Market.ItemKey(kind: string, item): string
	if kind == "egg" then
		return "e:" .. tostring(item.type)
	end
	return string.format("m:%s:%d:%d", tostring(item.line), tonumber(item.rarity) or 1, tonumber(item.variant) or 0)
end

-- Seller's share after tax (whole coins, rounded down).
function Market.Proceeds(price: number, club: boolean?): number
	local tax = if club then Market.ClubTax else Market.Tax
	return math.floor(price * (1 - tax))
end

return Market
