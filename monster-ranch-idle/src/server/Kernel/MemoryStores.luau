--[[
	MemoryStores: an in-memory stand-in for DataStoreService, for QA in Studio only.

	Studio's Play loads the owner's real save and writes real leaderboards. With the Workspace
	attribute QA_MemoryProfiles = true (set it in Edit before Play; Studio only, ignored on live
	servers), Adapters.Roblox builds every DataStore-backed adapter on this instead, so a QA
	session can grant levels, join fights and race without touching anything real. Everything is
	gone when Play stops. MemoryStoreService (short-lived, expiring) is left as it is.

	Covers what Adapters uses: GetDataStore(name) and GetOrderedDataStore(name) with GetAsync,
	SetAsync, UpdateAsync (transform returning nil = no write), RemoveAsync, IncrementAsync and
	GetSortedAsync (pages: GetCurrentPage, IsFinished, AdvanceToNextPageAsync), plus
	GetRequestBudgetForRequestType.
]]

local MemoryStores = {}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[deepCopy(k)] = deepCopy(v)
	end
	return out
end

local function newStore()
	local data = {}
	local store = {}
	function store:GetAsync(key: string)
		return deepCopy(data[key])
	end
	function store:SetAsync(key: string, value)
		data[key] = deepCopy(value)
	end
	function store:UpdateAsync(key: string, transform)
		local result = transform(deepCopy(data[key]))
		if result ~= nil then
			data[key] = deepCopy(result)
		end
		return deepCopy(result)
	end
	function store:RemoveAsync(key: string)
		local old = data[key]
		data[key] = nil
		return old
	end
	function store:IncrementAsync(key: string, delta: number?)
		data[key] = (tonumber(data[key]) or 0) + (delta or 1)
		return data[key]
	end
	function store:GetSortedAsync(ascending: boolean, pageSize: number)
		local rows = {}
		for key, value in data do
			if type(value) == "number" then
				table.insert(rows, { key = key, value = value })
			end
		end
		table.sort(rows, function(a, b)
			if ascending then
				return a.value < b.value
			end
			return a.value > b.value
		end)
		local size = math.max(1, pageSize or 50)
		local pages = { IsFinished = false }
		local at = 1
		function pages:GetCurrentPage()
			local page = {}
			for i = at, math.min(#rows, at + size - 1) do
				table.insert(page, rows[i])
			end
			return page
		end
		function pages:AdvanceToNextPageAsync()
			at += size
			self.IsFinished = at + size - 1 >= #rows
		end
		pages.IsFinished = size >= #rows
		return pages
	end
	return store
end

function MemoryStores.new()
	local stores, ordered = {}, {}
	local service = {}
	function service:GetDataStore(name: string, scope: string?)
		local key = name .. "/" .. (scope or "global")
		stores[key] = stores[key] or newStore()
		return stores[key]
	end
	function service:GetOrderedDataStore(name: string, scope: string?)
		local key = name .. "/" .. (scope or "global")
		ordered[key] = ordered[key] or newStore()
		return ordered[key]
	end
	function service:GetRequestBudgetForRequestType(_requestType)
		return 1000
	end
	return service
end

return MemoryStores
