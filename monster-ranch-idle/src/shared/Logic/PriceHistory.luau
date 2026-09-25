--[[
	PriceHistory (update 1.3 · Market Day): daily price buckets for one market item key.
	Pure maths shared by the PriceHistory system (authoritative writes) and the client
	(the price chart and the suggested price on the sell screen).

	Record (one per item key, stored through ctx.Services.PriceHistory):
	  { key, days = { { day, count, low, high, sum } }, last?, lastDay? }
	    days     UTC day numbers (unix / 86400), oldest first, one bucket per day with a
	             sale, at most Config.Market.HistoryDays days back from the newest one
	    last     the price of the most recent sale (by day, then by arrival)
	    lastDay  the day of that sale

	  PriceHistory.New(key) -> record
	  PriceHistory.Add(record?, price, day, key?) -> record
	    records one sale (whole coins, rounded down). Creates the record when nil, updates
	    it in place otherwise (safe inside an atomic Update transform). Sales older than the
	    window are ignored; old buckets are trimmed.
	  PriceHistory.Series(record?, today) -> { { day, count, low, high, avg } }
	    oldest first, only days within HistoryDays of `today`; days without sales are
	    omitted (the chart leaves gaps). `avg` is rounded to a whole coin.
	  PriceHistory.Last(record?) -> price?
	  PriceHistory.Suggest(record?, today?) -> price?
	    a recent average for the sell screen: every sale counts, sales in the last
	    RecentDays count RecentWeight times as much. Rounded to a whole coin and clamped to
	    Config.Market.MinPrice..MaxPrice; nil without data (or without data in the window
	    of `today` when it is given).
	  PriceHistory.ValidKey(key) -> boolean
	    a key made by Config.Market.ItemKey: "m:<line>:<rarity>:<variant>" with a known
	    line, rarity and variant, or "e:<eggType>" with a known egg.
]]

local Config = require(script.Parent.Parent.Config)

local Market = Config.Market

local PriceHistory = {}

PriceHistory.RecentDays = 7
PriceHistory.RecentWeight = 3

local function isNumber(v): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function round(v: number): number
	return math.floor(v + 0.5)
end

-- Drops malformed buckets (bad saves must never break the chart) and keeps the order.
local function cleanDays(days)
	local out = {}
	if type(days) ~= "table" then
		return out
	end
	for _, b in days do
		if
			type(b) == "table"
			and isNumber(b.day)
			and isNumber(b.count)
			and b.count > 0
			and isNumber(b.low)
			and isNumber(b.high)
			and isNumber(b.sum)
		then
			table.insert(out, b)
		end
	end
	table.sort(out, function(a, b)
		return a.day < b.day
	end)
	return out
end

function PriceHistory.New(key: string?)
	return { key = key or "", days = {} }
end

function PriceHistory.Add(record, price: number, day: number, key: string?)
	if type(record) ~= "table" then
		record = PriceHistory.New(key)
	end
	if type(record.key) ~= "string" or (record.key == "" and key) then
		record.key = key or ""
	end
	record.days = cleanDays(record.days)
	if not isNumber(price) or price <= 0 or not isNumber(day) then
		return record
	end
	price = math.floor(price)
	day = math.floor(day)
	local days = record.days

	local newest = if #days > 0 then days[#days].day else day
	if day <= math.max(newest, day) - Market.HistoryDays then
		return record -- older than anything we keep
	end

	local index = #days + 1
	for i, b in days do
		if b.day == day then
			index = -i
			break
		elseif b.day > day then
			index = i
			break
		end
	end
	if index < 0 then
		local b = days[-index]
		b.count += 1
		b.sum += price
		b.low = math.min(b.low, price)
		b.high = math.max(b.high, price)
	else
		table.insert(days, index, { day = day, count = 1, low = price, high = price, sum = price })
	end

	local cutoff = days[#days].day - Market.HistoryDays
	while #days > 0 and days[1].day <= cutoff do
		table.remove(days, 1)
	end

	if not isNumber(record.lastDay) or day >= record.lastDay then
		record.last = price
		record.lastDay = day
	end
	return record
end

function PriceHistory.Series(record, today: number)
	local out = {}
	if type(record) ~= "table" then
		return out
	end
	for _, b in cleanDays(record.days) do
		if b.day > today - Market.HistoryDays and b.day <= today then
			table.insert(out, { day = b.day, count = b.count, low = b.low, high = b.high, avg = round(b.sum / b.count) })
		end
	end
	return out
end

function PriceHistory.Last(record): number?
	if type(record) ~= "table" then
		return nil
	end
	if isNumber(record.last) and record.last > 0 then
		return record.last
	end
	-- Records without `last` fall back to the newest day's average.
	local days = cleanDays(record.days)
	local b = days[#days]
	return if b then round(b.sum / b.count) else nil
end

function PriceHistory.Suggest(record, today: number?): number?
	if type(record) ~= "table" then
		return nil
	end
	local days = cleanDays(record.days)
	if #days == 0 then
		return nil
	end
	local reference = today or days[#days].day
	local total, weight = 0, 0
	for _, b in days do
		if b.day > reference - Market.HistoryDays and b.day <= reference then
			local w = if b.day > reference - PriceHistory.RecentDays then PriceHistory.RecentWeight else 1
			total += b.sum * w
			weight += b.count * w
		end
	end
	if weight <= 0 then
		return nil
	end
	return math.clamp(round(total / weight), Market.MinPrice, Market.MaxPrice)
end

function PriceHistory.ValidKey(key: any): boolean
	if type(key) ~= "string" or #key > 40 then
		return false
	end
	local eggType = string.match(key, "^e:([%w_]+)$")
	if eggType then
		return Config.Eggs.ById[eggType] ~= nil
	end
	local line, rarity, variant = string.match(key, "^m:([%w_]+):(%d+):(%d+)$")
	if not line then
		return false
	end
	local r, v = tonumber(rarity), tonumber(variant)
	return Config.Species.ById[line] ~= nil
		and r ~= nil
		and Config.Rarities.List[r] ~= nil
		and v ~= nil
		and Config.Rarities.Variants[v] ~= nil
		and key == Market.ItemKey("monster", { line = line, rarity = r, variant = v })
end

return PriceHistory
