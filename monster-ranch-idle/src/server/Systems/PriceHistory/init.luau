--[[
	PriceHistory (S5, update 1.3 · Market Day): what market items sell for, per item key
	(Config.Market.ItemKey), across every server. The bucket maths is pure and shared with
	the client in Logic/PriceHistory.

	Records live in their own DataStore through ctx.Services.PriceHistory (Get / atomic
	Update), one per item key: { key, days = { { day, count, low, high, sum } }, last, lastDay }.

	Writes: every MarketSold topic (published by Market on the buyer's server, player nil)
	becomes one sale on the UTC day it happened. Sales are queued per key and written with
	one atomic Update per key; a failed write stays queued and is retried every
	RetrySeconds (never dropped). Sales this server has not written yet are still shown to
	its own players (cached record + queued sales).

	Reads: records are cached per key for CacheSeconds. A sale recorded by this server
	invalidates that key (and a successful write caches the record it wrote), so the
	buyer's server shows it at once; other servers catch up when their cache expires. When the store is down a stale cached
	record is used rather than failing.

	No save section, no replicated state.

	Actions: PriceHistory.Get { key } -> { key, days = Series, last? }
	Public API:
	  PriceHistory:Suggest(key) -> price?   -- suggested sell price (cached read), nil without data
	  PriceHistory:Get(key) -> record?      -- cached record merged with queued sales (read-only)
	  PriceHistory:Flush()                  -- writes every queued sale now (tests / shutdown)
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local History = require(Shared.Logic.PriceHistory)

local PriceHistory = {
	Name = "PriceHistory",
	Dependencies = {},
}

PriceHistory.CacheSeconds = 60
PriceHistory.RetrySeconds = 30

local ctx

local cache = {} -- [key] = { at = unix, record = record | false }
local queue = {} -- [key] = { { price, day } } sales not written yet, oldest first
local writing = {} -- [key] = true while an Update is in flight

-- Helpers ---------------------------------------------------------------------------------

local function now(): number
	return ctx:Now()
end

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

-- The record this server's players should see: the cached record plus unwritten sales.
local function merged(key: string, record)
	local list = queue[key]
	if not list or #list == 0 then
		return if record then record else nil
	end
	local copy = if record then deepCopy(record) else nil
	for _, sale in list do
		copy = History.Add(copy, sale.price, sale.day, key)
	end
	return copy
end

-- Writes (and retries) ------------------------------------------------------------------------

local function writeKey(key: string)
	local service = ctx.Services.PriceHistory
	local list = queue[key]
	if writing[key] or not service or not list or #list == 0 then
		return
	end
	writing[key] = true
	queue[key] = nil
	-- UpdateAsync may run the transform more than once; it only reads `list`.
	local ok, result = service.Update(key, function(current)
		local record = current
		for _, sale in list do
			record = History.Add(record, sale.price, sale.day, key)
		end
		return record
	end)
	writing[key] = nil
	if ok then
		-- The written record is the freshest copy there is; anything else is re-read.
		cache[key] = if type(result) == "table" then { at = now(), record = result } else nil
		ctx:Log("PriceHistory: recorded %d sale(s) of %s", #list, key)
	else
		-- Keep the order: these sales happened before anything queued meanwhile.
		local later = queue[key] or {}
		table.move(later, 1, #later, #list + 1, list)
		queue[key] = list
		ctx:Log("PriceHistory: write for %s failed, %d sale(s) queued", key, #list)
		return
	end
	if queue[key] and #queue[key] > 0 then
		writeKey(key) -- sales that arrived while the write was in flight
	end
end

local function record(key: string, price: number, day: number)
	queue[key] = queue[key] or {}
	table.insert(queue[key], { price = price, day = day })
	cache[key] = nil
	ctx.Services.Spawn(writeKey, key)
end

-- Reads ---------------------------------------------------------------------------------------

-- Returns (found, record?): found is false only when nothing could be read or cached.
local function read(key: string): (boolean, any)
	local entry = cache[key]
	if entry and now() - entry.at < PriceHistory.CacheSeconds then
		return true, merged(key, entry.record or nil)
	end
	local service = ctx.Services.PriceHistory
	local ok, current = false, nil
	if service then
		ok, current = service.Get(key)
	end
	if ok then
		local value = if type(current) == "table" then current else false
		cache[key] = { at = now(), record = value }
		return true, merged(key, value or nil)
	end
	if entry then
		return true, merged(key, entry.record or nil) -- stale beats nothing while the store is down
	end
	if queue[key] then
		return true, merged(key, nil)
	end
	return false, nil
end

local function prune()
	local t = now()
	for key, entry in cache do
		if t - entry.at >= PriceHistory.CacheSeconds * 10 then
			cache[key] = nil
		end
	end
end

-- Public API ----------------------------------------------------------------------------------

function PriceHistory:Get(key: string)
	if not History.ValidKey(key) then
		return nil
	end
	local _, current = read(key)
	return current
end

function PriceHistory:Suggest(key: string): number?
	if not History.ValidKey(key) then
		return nil
	end
	local found, current = read(key)
	if not found then
		return nil
	end
	return History.Suggest(current, ctx:Day())
end

function PriceHistory:Flush()
	for key in table.clone(queue) do
		writeKey(key)
	end
end

-- Actions -------------------------------------------------------------------------------------

local function registerActions()
	ctx.Net:Handle("PriceHistory.Get", function(_player, payload)
		local key = payload.key
		if not History.ValidKey(key) then
			ctx:Fail("That item isn't sold on the market")
		end
		local found, current = read(key)
		if not found then
			ctx:Fail("The market is busy. Try again")
		end
		return { key = key, days = History.Series(current, ctx:Day()), last = History.Last(current) }
	end)
end

-- Lifecycle -----------------------------------------------------------------------------------

function PriceHistory.Init(context)
	ctx = context
	table.clear(cache)
	table.clear(queue)
	table.clear(writing)

	registerActions()

	ctx.Bus:Subscribe("MarketSold", function(_player, detail)
		local key = detail and detail.key
		local price = tonumber(detail and detail.price)
		if not History.ValidKey(key) or not price or price ~= price or price <= 0 or price == math.huge then
			ctx:Log("PriceHistory: ignored a sale with key %s", tostring(key))
			return
		end
		record(key, math.floor(price), ctx:Day())
	end)
end

function PriceHistory.Start()
	ctx:Every(PriceHistory.RetrySeconds, function()
		prune()
		if next(queue) ~= nil then
			ctx.Services.Spawn(function()
				PriceHistory:Flush()
			end)
		end
	end)
end

return PriceHistory
