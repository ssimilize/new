--[[
	State: replicates server data to clients as a read-only tree.

	  profile.<System>.*  each system's save section (minus Private keys)
	  session.<System>.*  per-player, not saved
	  global.<System>.*   server-wide

	Systems never send state by hand: they change their data and mark the path dirty
	(ctx:Dirty / ctx:DirtySession / ctx:DirtyGlobal). At flush time the kernel reads the
	*current* value at each dirty path and sends it, so marking the same path many times in
	one frame costs nothing. Patches are also attached to request responses so the client
	sees the new state before the request resolves.

	Arrays must be replicated whole (mark the array's path, never "list.3" after a removal),
	because deleting an array element through a path would leave a hole.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local TableUtil = require(Shared.Logic.TableUtil)

local State = {}
State.__index = State

function State.new(kernel, transport)
	return setmetatable({
		_kernel = kernel,
		_transport = transport,
		_pending = {}, -- [player] = { [pathString] = true }
		_global = {}, -- global tree: [SystemName] = table
		_globalPending = {}, -- [pathString] = true
	}, State)
end

function State:GlobalRoot(systemName: string): { [any]: any }
	local root = self._global[systemName]
	if not root then
		root = {}
		self._global[systemName] = root
	end
	return root
end

local function mark(set: { [string]: boolean }, path: string)
	set[path] = true
end

function State:Dirty(player: any, parts: { any })
	local set = self._pending[player]
	if not set then
		set = {}
		self._pending[player] = set
	end
	mark(set, TableUtil.joinPath(parts))
end

function State:DirtyGlobal(parts: { any })
	mark(self._globalPending, TableUtil.joinPath(parts))
end

-- Returns the private-key filter for a profile path, or true if the path must not replicate.
function State:_isPrivate(parts: { any }): boolean
	if parts[1] ~= "profile" then
		return false
	end
	local system = self._kernel:_systemEntry(parts[2])
	if not system or not system.module.Profile then
		return false
	end
	local spec = system.module.Profile
	if spec.Replicate == false then
		return true
	end
	if parts[3] ~= nil and spec.Private then
		for _, key in spec.Private do
			if key == parts[3] then
				return true
			end
		end
	end
	return false
end

function State:_valueAt(player: any, parts: { any }): any
	local root = parts[1]
	if root == "profile" then
		local data = self._kernel.Data:Get(player)
		return data and TableUtil.getPath(data, { table.unpack(parts, 2) })
	elseif root == "session" then
		local record = self._kernel._players[player]
		return record and TableUtil.getPath(record.session, { table.unpack(parts, 2) })
	elseif root == "global" then
		return TableUtil.getPath(self._global, { table.unpack(parts, 2) })
	end
	return nil
end

-- Collapses a set of dirty paths: drops any path whose ancestor is also dirty.
local function collapse(set: { [string]: boolean }): { string }
	local list = {}
	for path in set do
		local ancestorDirty = false
		local prefix = ""
		for part in string.gmatch(path, "[^%.]+") do
			prefix = if prefix == "" then part else prefix .. "." .. part
			if prefix ~= path and set[prefix] then
				ancestorDirty = true
				break
			end
		end
		if not ancestorDirty then
			table.insert(list, path)
		end
	end
	table.sort(list)
	return list
end

-- Builds (and clears) the patch list for one player. Includes pending global patches
-- only when `includeGlobal` is set (FlushAll handles global patches for everyone).
function State:TakePatches(player: any, includeGlobal: boolean?): { { any } }
	local set = self._pending[player] or {}
	self._pending[player] = nil
	if includeGlobal then
		for path in self._globalPending do
			set["global." .. path] = true
		end
	end
	local patches = {}
	for _, path in collapse(set) do
		local parts = TableUtil.splitPath(path)
		if not self:_isPrivate(parts) then
			table.insert(patches, { path, TableUtil.deepCopy(self:_valueAt(player, parts)) })
		end
	end
	return patches
end

-- Sends every pending patch to every ready player. Called by the kernel on a short timer.
function State:FlushAll()
	local globalPaths = collapse(self._globalPending)
	self._globalPending = {}
	for _, player in self._kernel:ReadyPlayers() do
		local set = self._pending[player] or {}
		self._pending[player] = nil
		for _, path in globalPaths do
			set["global." .. path] = true
		end
		if next(set) ~= nil then
			self._pending[player] = set
			local patches = self:TakePatches(player, false)
			if #patches > 0 then
				self._transport:SendState(player, { kind = "patch", patches = patches })
			end
		end
	end
end

-- Full tree for a player who just became ready.
function State:Snapshot(player: any)
	local data = self._kernel.Data:Get(player) or {}
	local profile = {}
	for name, entry in self._kernel._systems do
		local spec = entry.module.Profile
		if spec and spec.Replicate ~= false and data[name] ~= nil then
			local copy = TableUtil.deepCopy(data[name])
			for _, key in spec.Private or {} do
				copy[key] = nil
			end
			profile[name] = copy
		end
	end
	local record = self._kernel._players[player]
	return {
		profile = profile,
		session = TableUtil.deepCopy(record and record.session or {}),
		global = TableUtil.deepCopy(self._global),
	}
end

function State:SendSnapshot(player: any)
	self._pending[player] = nil
	self._transport:SendState(player, { kind = "snapshot", tree = self:Snapshot(player) })
end

function State:Forget(player: any)
	self._pending[player] = nil
end

return State
