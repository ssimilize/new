--[[
	Reminders adapter: the Roblox services behind offline reminders (MemoryStore, HttpService
	with an experience secret, LocalizationService). The Reminders system prefers
	ctx.Services.Reminders when the kernel provides one (tests plug an in-memory fake there);
	otherwise it builds this one, and only when Config.Reminders is filled in. It belongs in
	Kernel/Adapters.luau as Services.Reminders; it lives here so this packet leaves the kernel
	alone. Every call is wrapped in pcall and fails soft (ok = false).

	Shape (the fake in tests/specs/Reminders.spec.luau implements the same):
	  Available() -> boolean
	  Put(map, key, value, sortKey, ttlSeconds) -> ok
	  Remove(map, key) -> ok
	  Update(map, key, transform(old) -> new?, ttlSeconds) -> ok, value?   atomic; sortKey kept
	  Due(map, upTo, limit) -> ok, { { key, value, sortKey } }             sortKey < upTo, ascending
	  Post(url, body: table, secretName) -> ok, status, message?
	  Country(player) -> string?     Roblox country code, may yield
	  UniverseId() -> number         JobId() -> string
	maps: "queue" (planned reminders, sortKey = dueAt) and "caps" (per-player daily counters).
]]

local Adapter = {}

local MAP_NAMES = { queue = "MR_Reminders_v1", caps = "MR_ReminderCaps_v1" }
local MAX_TTL = 45 * 86400

local function ttl(seconds: number): number
	return math.clamp(math.floor(seconds), 60, MAX_TTL)
end

function Adapter.Roblox()
	local ok, services = pcall(function()
		return {
			memory = game:GetService("MemoryStoreService"),
			http = game:GetService("HttpService"),
			localization = game:GetService("LocalizationService"),
		}
	end)
	if not ok then
		return nil
	end
	local maps = {}
	local function map(name: string)
		if not maps[name] then
			maps[name] = services.memory:GetSortedMap(MAP_NAMES[name] or name)
		end
		return maps[name]
	end

	return {
		Available = function(): boolean
			return pcall(map, "queue") and services.http.HttpEnabled == true
		end,
		Put = function(name: string, key: string, value, sortKey: number?, seconds: number): boolean
			return (pcall(function()
				map(name):SetAsync(key, value, ttl(seconds), sortKey)
			end))
		end,
		Remove = function(name: string, key: string): boolean
			return (pcall(function()
				map(name):RemoveAsync(key)
			end))
		end,
		Update = function(name: string, key: string, transform, seconds: number): (boolean, any)
			local result = nil
			local okUpdate = pcall(function()
				result = map(name):UpdateAsync(key, function(old, sortKey)
					local new = transform(old)
					if new == nil then
						return nil
					end
					return new, sortKey
				end, ttl(seconds))
			end)
			return okUpdate, result
		end,
		Due = function(name: string, upTo: number, limit: number): (boolean, { any })
			local rows = {}
			local okRead = pcall(function()
				local items = map(name):GetRangeAsync(Enum.SortDirection.Ascending, limit, nil, { sortKey = upTo })
				for _, item in items do
					table.insert(rows, { key = item.key, value = item.value, sortKey = item.sortKey })
				end
			end)
			return okRead, rows
		end,
		Post = function(url: string, body, secretName: string): (boolean, number, string?)
			local okPost, response = pcall(function()
				local secret = services.http:GetSecret(secretName)
				return services.http:RequestAsync({
					Url = url,
					Method = "POST",
					Headers = { ["Content-Type"] = "application/json", ["x-api-key"] = secret },
					Body = services.http:JSONEncode(body),
				})
			end)
			if not okPost then
				return false, 0, tostring(response)
			end
			return response.Success == true, tonumber(response.StatusCode) or 0, response.StatusMessage
		end,
		Country = function(player): string?
			local okCountry, code = pcall(function()
				return services.localization:GetCountryRegionForPlayerAsync(player)
			end)
			return if okCountry and type(code) == "string" then code else nil
		end,
		UniverseId = function(): number
			return game.GameId
		end,
		JobId = function(): string
			return game.JobId
		end,
	}
end

return Adapter
