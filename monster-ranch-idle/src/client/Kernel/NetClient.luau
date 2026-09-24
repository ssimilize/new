--[[
	NetClient: the client half of Kernel.Net.

		local ok, dataOrErr = net:Request("Shop.BuyEgg", { egg = "meadow", amount = 1 })
		net:On("Eggs.Hatched", function(payload) ... end)

	Requests yield. Patches attached to a response are applied to the Store before the
	request returns, so UI reading the Store right after sees the new values.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Api = require(ReplicatedStorage.Shared.Kernel.Api)

local NetClient = {}
NetClient.__index = NetClient

function NetClient.new(store)
	local folder = ReplicatedStorage:WaitForChild("KernelRemotes")
	local self = setmetatable({
		_store = store,
		_request = folder:WaitForChild("Request"),
		_handlers = {},
		_pending = {}, -- actions currently in flight (debounce)
	}, NetClient)

	folder:WaitForChild("Event").OnClientEvent:Connect(function(name, payload)
		local list = self._handlers[name]
		if list then
			for _, fn in table.clone(list) do
				task.spawn(fn, payload)
			end
		end
	end)
	folder:WaitForChild("State").OnClientEvent:Connect(function(message)
		if message.kind == "snapshot" then
			store:ApplySnapshot(message.tree)
		elseif message.kind == "patch" then
			store:ApplyPatches(message.patches)
		end
	end)
	return self
end

-- Returns (true, data) or (false, errorMessage). Never throws.
function NetClient:Request(action: string, payload: any?): (boolean, any)
	if Api.Actions[action] == nil then
		warn("[NetClient] undeclared action " .. action)
		return false, "UnknownAction"
	end
	local ok, response = pcall(function()
		return self._request:InvokeServer(action, payload)
	end)
	if not ok or type(response) ~= "table" then
		return false, "Connection problem. Try again."
	end
	if response.patches then
		self._store:ApplyPatches(response.patches)
	end
	if response.ok then
		return true, response.data
	end
	return false, response.err
end

-- Like Request, but ignores the call if the same action is already in flight
-- (protects against double taps). Returns (false, "Busy") when skipped.
function NetClient:RequestOnce(action: string, payload: any?): (boolean, any)
	if self._pending[action] then
		return false, "Busy"
	end
	self._pending[action] = true
	local ok, result = self:Request(action, payload)
	self._pending[action] = nil
	return ok, result
end

function NetClient:On(event: string, fn: (any) -> ())
	if Api.Events[event] == nil then
		warn("[NetClient] listening to undeclared event " .. event)
	end
	self._handlers[event] = self._handlers[event] or {}
	table.insert(self._handlers[event], fn)
	return {
		Disconnect = function()
			local list = self._handlers[event]
			local i = list and table.find(list, fn)
			if i then
				table.remove(list, i)
			end
		end,
	}
end

return NetClient
