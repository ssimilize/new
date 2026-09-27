--[[
	LiveChecks (R2-LAUNCH): exercises the five VERIFY paths in Kernel/Adapters against whatever
	`adapters` it is given (the real Adapters.Roblox() on a live server, or MockAdapters in
	tests), safely:
	  - read-mostly: every check reads what it just wrote, nothing else
	  - a throwaway key namespace ("LiveCheck_...") with short TTLs
	  - cleaned up after itself where the adapter has a way to remove an entry

	LiveChecks.Run(adapters) -> report string, one line per check:
	  "[PASS] <name> (<seconds>s): <detail>" or "[FAIL] <name>: <error>"

	Checks:
	  Market     MemoryStore quotas and GetRangeAsync paging (Browse)
	  Arena      GetSortedAsync min/max paging (Near, read-only)
	  Ads        the AdService surface (CheckAvailable, no ad is shown)
	  HubBoard   MemoryStore quotas with many hub servers (Post/List/Remove)
	  Titan      request units with many servers (Update/Get/Remove)

	Run this from a live private server's developer console (docs/GO_LIVE.md §6):
	  require(game.ServerScriptService.Server.Kernel.LiveChecks).Run()
]]

local LiveChecks = {}

local PREFIX = "LiveCheck_"

local function timed(fn): (boolean, number, any)
	local start = os.clock()
	local ok, result = pcall(fn)
	local elapsed = os.clock() - start
	return ok, elapsed, result
end

local function line(name: string, ok: boolean, elapsed: number, detail: string): string
	if ok then
		return string.format("[PASS] %s (%.3fs): %s", name, elapsed, detail)
	end
	return string.format("[FAIL] %s (%.3fs): %s", name, elapsed, detail)
end

-- Market: post a throwaway open listing, browse it back (GetRangeAsync paging through the
-- MemoryStore index), then close it (removes it from the index). It is a club listing for a club
-- that does not exist, so it sits in its own index: no player ever sees it or can buy it.
local function checkMarket(adapters, now: number): string
	local ok, elapsed, detail = timed(function()
		local id = PREFIX .. "Market_" .. tostring(now)
		local listing = {
			id = id,
			kind = "monster",
			price = 1,
			expiresAt = now + 65,
			state = "open",
			seller = 0,
			sellerName = "LiveCheck",
			club = id,
			createdAt = now,
		}
		assert(adapters.Market.Create(listing), "Market.Create failed")
		local browseOk, list = adapters.Market.Browse({ scope = id })
		assert(browseOk, "Market.Browse failed")
		local found = false
		for _, l in list do
			if l.id == id then
				found = true
			end
		end
		local closeOk = adapters.Market.Update(id, function(current)
			if current == nil then
				return nil
			end
			current.state = "closed"
			return current
		end)
		assert(closeOk, "Market.Update (close) failed")
		return string.format("browsed %d open listings, found ours = %s, closed after", #list, tostring(found))
	end)
	return line("Market (Browse/Update)", ok, elapsed, tostring(detail))
end

-- Arena: page GetSortedAsync with a min/max window. Read-only: a probe rating would sit in the
-- real matchmaking index for good (there is no OrderedDataStore delete in the adapter) and take
-- one of every nearby player's candidate slots.
local function checkArena(adapters): string
	local ok, elapsed, detail = timed(function()
		local rating = 1000
		local nearOk, rows = adapters.Arena.Near(rating, 1000, 20)
		assert(nearOk, "Arena.Near failed")
		for _, row in rows do
			assert(math.abs(row.rating - rating) <= 1000, "Arena.Near returned a rating outside the window")
		end
		return string.format("paged %d ratings within 1000 of %d", #rows, rating)
	end)
	return line("Arena (Index/Near)", ok, elapsed, tostring(detail))
end

-- AdService: availability only, never shows an ad.
local function checkAds(adapters): string
	local ok, elapsed, detail = timed(function()
		local available, result = adapters.Ads.CheckAvailable()
		assert(available, tostring(result))
		return "AdService reachable: " .. tostring(result)
	end)
	return line("Ads (CheckAvailable)", ok, elapsed, tostring(detail))
end

-- Trade Board: post, list (GetRangeAsync), remove. Fully self-cleaning.
local function checkHubBoard(adapters, now: number): string
	local ok, elapsed, detail = timed(function()
		local id = PREFIX .. "Hub_" .. tostring(now)
		assert(adapters.HubBoard.Post({ id = id, postedAt = now }, 60), "HubBoard.Post failed")
		local listOk, ads = adapters.HubBoard.List(200)
		assert(listOk, "HubBoard.List failed")
		local found = false
		for _, ad in ads do
			if ad.id == id then
				found = true
			end
		end
		assert(adapters.HubBoard.Remove(id), "HubBoard.Remove failed")
		return string.format("listed %d ads, found ours = %s, removed after", #ads, tostring(found))
	end)
	return line("HubBoard (Post/List/Remove)", ok, elapsed, tostring(detail))
end

-- Titan: write a throwaway invasion record, read it back, then remove it. Fully self-cleaning.
local function checkTitan(adapters): string
	if adapters.Titan == nil then
		return line("Titan (Update/Get/Remove)", false, 0, "adapters.Titan unavailable (MemoryStore hash map failed to open)")
	end
	local key = PREFIX .. "Titan"
	local ok, elapsed, detail = timed(function()
		local updateOk = adapters.Titan.Update(key, function()
			return { probe = true }
		end)
		assert(updateOk, "Titan.Update failed")
		local getOk, record = adapters.Titan.Get(key)
		assert(getOk, "Titan.Get failed")
		assert(type(record) == "table" and record.probe == true, "Titan.Get did not read back the write")
		assert(adapters.Titan.Remove(key), "Titan.Remove failed")
		return "wrote, read back and removed the probe entry"
	end)
	return line("Titan (Update/Get/Remove)", ok, elapsed, tostring(detail))
end

-- Runs every check and returns one report string (never throws: a failing check is a [FAIL]
-- line, not an error).
function LiveChecks.Run(adapters): string
	adapters = adapters or require(game.ServerScriptService.Server.Kernel.Adapters).Roblox()
	local now = adapters.Clock.Now()
	local lines = {
		checkMarket(adapters, now),
		checkArena(adapters),
		checkAds(adapters),
		checkHubBoard(adapters, now),
		checkTitan(adapters),
	}
	return table.concat(lines, "\n")
end

return LiveChecks
