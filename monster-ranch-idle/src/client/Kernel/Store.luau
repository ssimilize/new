--[[
	Store: the client's read-only mirror of replicated state (see Api.State).

		store:Get("profile.Currency.coins")
		local conn = store:Observe("profile.Monsters.list", function(list) ... end)
		conn:Disconnect()

	Observe calls the callback once immediately (after the first snapshot) and again
	whenever a patch touches the observed path, one of its ancestors or descendants.
	Never mutate tables returned by Get: they are the store's own data.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Kernel.Signal)
local TableUtil = require(ReplicatedStorage.Shared.Logic.TableUtil)

local Store = {}
Store.__index = Store

function Store.new()
	return setmetatable({
		_tree = { profile = {}, session = {}, global = {} },
		_observers = {},
		Ready = false,
		ReadySignal = Signal.new(),
		Changed = Signal.new(), -- (path: string)
	}, Store)
end

function Store:Get(path: string): any
	return TableUtil.getPath(self._tree, TableUtil.splitPath(path))
end

local function overlaps(a: string, b: string): boolean
	if a == b then
		return true
	end
	if #a < #b then
		return string.sub(b, 1, #a + 1) == a .. "."
	end
	return string.sub(a, 1, #b + 1) == b .. "."
end

function Store:_notify(changedPaths: { string })
	for _, observer in table.clone(self._observers) do
		if observer.connected then
			for _, path in changedPaths do
				if overlaps(path, observer.path) then
					task.spawn(observer.fn, self:Get(observer.path))
					break
				end
			end
		end
	end
	for _, path in changedPaths do
		self.Changed:Fire(path)
	end
end

function Store:Observe(path: string, fn: (any) -> ())
	local observer = { path = path, fn = fn, connected = true }
	table.insert(self._observers, observer)
	if self.Ready then
		task.spawn(fn, self:Get(path))
	end
	return {
		Disconnect = function()
			observer.connected = false
			local i = table.find(self._observers, observer)
			if i then
				table.remove(self._observers, i)
			end
		end,
	}
end

function Store:ApplySnapshot(tree)
	self._tree = {
		profile = tree.profile or {},
		session = tree.session or {},
		global = tree.global or {},
	}
	local wasReady = self.Ready
	self.Ready = true
	if not wasReady then
		self.ReadySignal:Fire()
	end
	self:_notify({ "profile", "session", "global" })
end

function Store:ApplyPatches(patches: { { any } })
	if not patches or #patches == 0 then
		return
	end
	local changed = {}
	for _, patch in patches do
		local path, value = patch[1], patch[2]
		TableUtil.setPath(self._tree, TableUtil.splitPath(path), value)
		table.insert(changed, path)
	end
	if self.Ready then
		self:_notify(changed)
	end
end

function Store:WhenReady(fn: () -> ())
	if self.Ready then
		task.spawn(fn)
	else
		self.ReadySignal:Once(fn)
	end
end

return Store
