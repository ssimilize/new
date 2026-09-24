--[[
	Signal: a tiny synchronous event emitter.

	Handlers run in connection order, in the same thread as :Fire(). An error in one
	handler is reported through `warn` and never stops the other handlers.

		local changed = Signal.new()
		local conn = changed:Connect(function(value) print(value) end)
		changed:Fire(42)
		conn:Disconnect()
]]

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local handlers = self._signal._handlers
	for i = #handlers, 1, -1 do
		if handlers[i] == self then
			table.remove(handlers, i)
			break
		end
	end
end

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	assert(type(fn) == "function", "Signal:Connect expects a function")
	local conn = setmetatable({ Connected = true, _fn = fn, _signal = self }, Connection)
	table.insert(self._handlers, conn)
	return conn
end

function Signal:Once(fn: (...any) -> ())
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...: any)
	-- Copy so handlers may disconnect themselves while firing.
	local snapshot = table.clone(self._handlers)
	for _, conn in snapshot do
		if conn.Connected then
			local ok, err = xpcall(conn._fn, debug.traceback, ...)
			if not ok then
				warn("[Signal] handler error: " .. tostring(err))
			end
		end
	end
end

function Signal:DisconnectAll()
	for _, conn in table.clone(self._handlers) do
		conn:Disconnect()
	end
end

function Signal:HandlerCount(): number
	return #self._handlers
end

return Signal
