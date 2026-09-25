-- S5 PriceHistory (update 1.3): daily price buckets (Logic/PriceHistory), the suggested
-- price, and the PriceHistory system recording MarketSold sales from several servers into
-- one record, its per-key cache, retries while the store is down, and key validation.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local MockAdapters = t.MockAdapters
	local Config = t.Shared("Config")
	local Market = Config.Market
	local History = t.Shared("Logic.PriceHistory")

	local DAY = 20000
	local KEY = "m:cindlet:3:0"
	local EGG = "e:meadow"

	local function add(record, prices, day)
		for _, price in prices do
			record = History.Add(record, price, day, KEY)
		end
		return record
	end

	local function server(network, startTime)
		return TestKernel.new({ systems = { "PriceHistory" }, network = network, startTime = startTime })
	end

	local function sold(h, key, price)
		h.kernel.Bus:Publish("MarketSold", nil, {
			listing = "L-test",
			key = key,
			kind = if string.sub(key, 1, 1) == "e" then "egg" else "monster",
			price = price,
			proceeds = Market.Proceeds(price),
			buyer = 1,
			seller = 2,
			club = false,
		})
	end

	local function counting(h)
		local calls = { get = 0, update = 0 }
		local service = h.adapters.PriceHistory
		local get, update = service.Get, service.Update
		service.Get = function(...)
			calls.get += 1
			return get(...)
		end
		service.Update = function(...)
			calls.update += 1
			return update(...)
		end
		return calls
	end

	describe("Buckets", function()
		it("creates the record and tracks low, high, count and average per day", function()
			local r = add(nil, { 500, 300, 700.9 }, DAY)
			expect(r.key).toBe(KEY)
			expect(#r.days).toBe(1)
			local b = r.days[1]
			expect(b.day).toBe(DAY)
			expect(b.count).toBe(3)
			expect(b.low).toBe(300)
			expect(b.high).toBe(700)
			expect(b.sum).toBe(1500)
			local series = History.Series(r, DAY)
			expect(series).toEqual({ { day = DAY, count = 3, low = 300, high = 700, avg = 500 } })
			expect(History.Last(r)).toBe(700)
		end)

		it("opens a new bucket when the day rolls over and keeps days oldest first", function()
			local r = add(nil, { 100, 200 }, DAY)
			r = add(r, { 900 }, DAY + 1)
			r = add(r, { 400 }, DAY - 1) -- a late write for an earlier day
			expect(#r.days).toBe(3)
			expect(r.days[1].day).toBe(DAY - 1)
			expect(r.days[2].day).toBe(DAY)
			expect(r.days[3].day).toBe(DAY + 1)
			expect(r.days[2].count).toBe(2)
			expect(History.Last(r)).toBe(900) -- the late sale is not the latest one
		end)

		it("rounds the average to whole coins", function()
			local series = History.Series(add(nil, { 100, 101 }, DAY), DAY)
			expect(series[1].avg).toBe(101)
		end)

		it("leaves gaps for days without sales", function()
			local r = add(nil, { 100 }, DAY)
			r = add(r, { 300 }, DAY + 4)
			local series = History.Series(r, DAY + 4)
			expect(#series).toBe(2)
			expect(series[1].day).toBe(DAY)
			expect(series[2].day).toBe(DAY + 4)
		end)

		it("keeps at most HistoryDays days", function()
			local r = nil
			for d = 0, Market.HistoryDays + 9 do
				r = History.Add(r, 1000 + d, DAY + d, KEY)
			end
			local newest = DAY + Market.HistoryDays + 9
			expect(#r.days).toBe(Market.HistoryDays)
			expect(r.days[1].day).toBe(newest - Market.HistoryDays + 1)
			expect(r.days[#r.days].day).toBe(newest)
			-- a sale older than the window is ignored
			History.Add(r, 5, DAY, KEY)
			expect(#r.days).toBe(Market.HistoryDays)
			expect(r.days[1].day).toBe(newest - Market.HistoryDays + 1)
		end)

		it("shows only the days within HistoryDays of today", function()
			local r = add(nil, { 100 }, DAY)
			r = add(r, { 200 }, DAY + 10)
			expect(#History.Series(r, DAY + 10)).toBe(2)
			expect(#History.Series(r, DAY + Market.HistoryDays)).toBe(1)
			expect(#History.Series(r, DAY + 10 + Market.HistoryDays)).toBe(0)
			expect(#History.Series(r, DAY - 1)).toBe(0) -- nothing from the future
		end)

		it("ignores bad prices and survives malformed records", function()
			local r = add(nil, { 0, -5, 0 / 0, math.huge }, DAY)
			expect(#r.days).toBe(0)
			expect(History.Last(r)).toBe(nil)
			local broken = { key = KEY, days = { { day = DAY, count = 2, low = 10, high = 20, sum = 30 }, "junk", { day = "x" } } }
			expect(#History.Series(broken, DAY)).toBe(1)
			expect(History.Last(broken)).toBe(15)
			History.Add(broken, 40, DAY, KEY)
			expect(#broken.days).toBe(1)
			expect(broken.days[1].count).toBe(3)
			expect(History.Series(nil, DAY)).toEqual({})
			expect(History.Last(nil)).toBe(nil)
		end)
	end)

	describe("Suggest", function()
		it("is nil without data", function()
			expect(History.Suggest(nil)).toBe(nil)
			expect(History.Suggest(History.New(KEY))).toBe(nil)
		end)

		it("averages every sale when they are all recent", function()
			local r = add(nil, { 1000, 2000 }, DAY)
			r = add(r, { 3000 }, DAY - 3)
			expect(History.Suggest(r)).toBe(2000)
			expect(History.Suggest(r, DAY)).toBe(2000)
		end)

		it("weights the last RecentDays toward the suggestion", function()
			local r = add(nil, { 10000 }, DAY - 20)
			r = add(r, { 1000 }, DAY)
			-- (10000 × 1 + 1000 × 3) / (1 + 3)
			expect(History.Suggest(r, DAY)).toBe(3250)
			expect(History.Suggest(r)).toBe(3250)
		end)

		it("rounds to a whole coin and clamps to the price limits", function()
			expect(History.Suggest(add(nil, { 1001, 1002 }, DAY))).toBe(1002)
			expect(History.Suggest(add(nil, { 1 }, DAY))).toBe(Market.MinPrice)
		end)

		it("ignores sales outside the window of today", function()
			local r = add(nil, { 5000 }, DAY)
			expect(History.Suggest(r, DAY + Market.HistoryDays)).toBe(nil)
			expect(History.Suggest(r, DAY + 1)).toBe(5000)
		end)
	end)

	describe("Keys", function()
		it("accepts keys made by Config.Market.ItemKey", function()
			expect(History.ValidKey(Market.ItemKey("monster", { line = "cindlet", rarity = 3, variant = 2 }))).toBe(true)
			expect(History.ValidKey(Market.ItemKey("egg", { type = "meadow" }))).toBe(true)
		end)

		it("rejects unknown lines, eggs, rarities, variants and other shapes", function()
			for _, key in
				{
					"m:nope:1:0",
					"m:cindlet:0:0",
					"m:cindlet:7:0",
					"m:cindlet:1:3",
					"m:cindlet:01:0",
					"e:nope",
					"e:",
					"x:meadow",
					"meadow",
					"m:cindlet:1",
					"e:meadow ",
					"",
				}
			do
				expect(History.ValidKey(key)).toBe(false)
			end
			expect(History.ValidKey(nil)).toBe(false)
			expect(History.ValidKey(12)).toBe(false)
		end)
	end)

	describe("System", function()
		it("records sales from two servers into one record", function()
			local network = MockAdapters.network()
			local a = server(network)
			local b = server(network)
			sold(a, KEY, 1200)
			sold(b, KEY, 800)
			sold(b, EGG, 450)
			local record = network.prices[KEY]
			expect(record.key).toBe(KEY)
			expect(#record.days).toBe(1)
			expect(record.days[1].count).toBe(2)
			expect(record.days[1].low).toBe(800)
			expect(record.days[1].high).toBe(1200)
			expect(network.prices[EGG].days[1].sum).toBe(450)

			-- a third server reads the combined record
			local c = server(network)
			local p = c:Join(7001)
			local data = c:Call(p, "PriceHistory.Get", { key = KEY })
			expect(data.key).toBe(KEY)
			expect(#data.days).toBe(1)
			expect(data.days[1].avg).toBe(1000)
			expect(data.days[1].count).toBe(2)
			expect(data.last).toBe(800)
			expect(c:System("PriceHistory"):Suggest(KEY)).toBe(1000)
			-- the server that wrote last cached the record it wrote
			expect(b:System("PriceHistory"):Suggest(KEY)).toBe(1000)
		end)

		it("files sales under the UTC day they happened", function()
			local network = MockAdapters.network()
			local start = DAY * 86400 + 86400 - 100
			local h = server(network, start)
			sold(h, KEY, 1000)
			h:Advance(200)
			sold(h, KEY, 3000)
			local days = network.prices[KEY].days
			expect(#days).toBe(2)
			expect(days[1].day).toBe(DAY)
			expect(days[2].day).toBe(DAY + 1)
			local p = h:Join(7002)
			local data = h:Call(p, "PriceHistory.Get", { key = KEY })
			expect(#data.days).toBe(2)
			expect(data.last).toBe(3000)
		end)

		it("returns an empty history for an item that never sold", function()
			local h = server(MockAdapters.network())
			local p = h:Join(7003)
			local data = h:Call(p, "PriceHistory.Get", { key = EGG })
			expect(data.key).toBe(EGG)
			expect(data.days).toEqual({})
			expect(data.last).toBe(nil)
			expect(h:System("PriceHistory"):Suggest(EGG)).toBe(nil)
		end)

		it("caches reads per key for 60 s", function()
			local network = MockAdapters.network()
			local a = server(network)
			local b = server(network)
			sold(b, KEY, 1000)
			local calls = counting(a)
			local p = a:Join(7004)
			expect(a:Call(p, "PriceHistory.Get", { key = KEY }).days[1].count).toBe(1)
			a:Advance(1)
			sold(b, KEY, 2000) -- another server: this one keeps its cached copy
			expect(a:Call(p, "PriceHistory.Get", { key = KEY }).days[1].count).toBe(1)
			expect(a:System("PriceHistory"):Suggest(KEY)).toBe(1000)
			expect(calls.get).toBe(1)
			a:Advance(60)
			local data = a:Call(p, "PriceHistory.Get", { key = KEY })
			expect(data.days[1].count).toBe(2)
			expect(data.last).toBe(2000)
			expect(calls.get).toBe(2)
			-- other keys have their own cache entry
			a:Call(p, "PriceHistory.Get", { key = EGG })
			expect(calls.get).toBe(3)
		end)

		it("invalidates the cached key when this server records a sale", function()
			local network = MockAdapters.network()
			local a = server(network)
			local b = server(network)
			sold(b, KEY, 1000)
			local p = a:Join(7005)
			expect(a:Call(p, "PriceHistory.Get", { key = KEY }).days[1].count).toBe(1)
			sold(b, KEY, 2000)
			a:Advance(1)
			sold(a, KEY, 3000)
			local data = a:Call(p, "PriceHistory.Get", { key = KEY })
			expect(data.days[1].count).toBe(3) -- includes the other server's sale too
			expect(data.days[1].high).toBe(3000)
			expect(data.last).toBe(3000)
		end)

		it("queues sales while the store is down and retries every 30 s", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = h:Join(7006)
			network.marketDown = true
			sold(h, KEY, 1500)
			sold(h, KEY, 2500)
			expect(network.prices[KEY]).toBe(nil)
			-- this server still shows its own sales
			local data = h:Call(p, "PriceHistory.Get", { key = KEY })
			expect(data.days[1].count).toBe(2)
			expect(h:System("PriceHistory"):Suggest(KEY)).toBe(2000)
			h:Advance(30)
			expect(network.prices[KEY]).toBe(nil) -- still down: nothing dropped
			network.marketDown = false
			h:Advance(30)
			local record = network.prices[KEY]
			expect(record.days[1].count).toBe(2)
			expect(record.days[1].sum).toBe(4000)
			h:Advance(60)
			expect(network.prices[KEY].days[1].count).toBe(2) -- written once
		end)

		it("fails politely when nothing can be read", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = h:Join(7007)
			network.marketDown = true
			expect(h:Reject(p, "PriceHistory.Get", { key = KEY })).toBe("The market is busy. Try again")
			expect(h:System("PriceHistory"):Suggest(KEY)).toBe(nil)
		end)

		it("uses a stale cached record while the store is down", function()
			local network = MockAdapters.network()
			local h = server(network)
			local other = server(network)
			sold(other, KEY, 1000)
			local p = h:Join(7008)
			h:Call(p, "PriceHistory.Get", { key = KEY })
			network.marketDown = true
			h:Advance(120)
			local data = h:Call(p, "PriceHistory.Get", { key = KEY })
			expect(data.days[1].count).toBe(1)
		end)

		it("rejects keys that aren't market items", function()
			local h = server(MockAdapters.network())
			local p = h:Join(7009)
			for _, key in { "m:nope:1:0", "e:dragon", "m:cindlet:9:0", "hello" } do
				expect(h:Reject(p, "PriceHistory.Get", { key = key })).toBe("That item isn't sold on the market")
				h:Advance(1)
			end
			expect(h:System("PriceHistory"):Suggest("e:dragon")).toBe(nil)
		end)

		it("ignores malformed sales", function()
			local network = MockAdapters.network()
			local h = server(network)
			sold(h, "m:nope:1:0", 1000)
			sold(h, KEY, -3)
			h.kernel.Bus:Publish("MarketSold", nil, { key = KEY })
			expect(next(network.prices)).toBe(nil)
		end)
	end)
end
