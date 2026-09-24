--[[
	Kernel: owns lifecycle, save data, networking, state replication and the event bus.
	Game rules live in systems (src/server/Systems), which are plugged in through the
	Manifest. See docs/ARCHITECTURE.md for the system contract.

	Lifecycle:
	  kernel:AddSystem(module)  ×N
	  kernel:Start()
	    1. sort systems by Dependencies (a missing/failed required dependency disables a system)
	    2. Init(ctx) on every system, in dependency order
	    3. Start() on every system
	    4. connect players: load profile → reconcile/migrate sections → PlayerAdded hooks
	       → ready → snapshot → Bus "PlayerReady"
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Api = require(Shared.Kernel.Api)
local Rng = require(Shared.Logic.Rng)
local TableUtil = require(Shared.Logic.TableUtil)

local Bus = require(script.Parent.Bus)
local Context = require(script.Parent.Context)
local Data = require(script.Parent.Data)
local Net = require(script.Parent.Net)
local Scheduler = require(script.Parent.Scheduler)
local State = require(script.Parent.State)

local Kernel = {}
Kernel.__index = Kernel

Kernel.AutosaveSeconds = 90
Kernel.FlushSeconds = 0.1

--[[
	options = {
	  adapters = Adapters (see Adapters.luau; tests pass MockAdapters),
	  verbose = boolean?,
	}
]]
function Kernel.new(options)
	local adapters = options.adapters
	local self = setmetatable({}, Kernel)
	self.Adapters = adapters
	self.Clock = adapters.Clock
	self.Analytics = adapters.Analytics
	self.Verbose = options.verbose == true
	self.Rng = Rng.new(adapters.Seed and adapters.Seed() or nil)
	self.Scheduler = Scheduler.new(self.Clock)
	self.Bus = Bus.new(Api.Topics)
	self.Data = Data.new(self, adapters.DataStore, adapters)
	self.State = State.new(self, adapters.Transport)
	self.Net = Net.new(self, adapters.Transport)
	self.Log = function(scope: string, fmt: string, ...: any)
		if self.Verbose then
			print(string.format("[%s] " .. fmt, scope, ...))
		end
	end
	self._systems = {} -- [name] = { module, ctx, state = "added"|"ready"|"failed", error }
	self._order = {}
	self._stubs = {}
	self._players = {} -- [player] = { ready, session, joinedAt }
	self._started = false
	return self
end

-- Registration ---------------------------------------------------------------------------

function Kernel:AddSystem(module)
	assert(type(module) == "table", "system module must return a table")
	assert(type(module.Name) == "string", "system is missing Name")
	assert(self._systems[module.Name] == nil, "system added twice: " .. module.Name)
	assert(not self._started, "cannot add systems after Start")
	self._systems[module.Name] = { module = module, state = "added" }
end

-- Tests: pretend a system exists with the given public API.
function Kernel:Stub(name: string, api)
	self._stubs[name] = api
end

function Kernel:_systemEntry(name: string)
	return self._systems[name]
end

function Kernel:_systemApi(name: string)
	local entry = self._systems[name]
	if entry and entry.state == "ready" then
		return entry.module
	end
	return self._stubs[name]
end

function Kernel:SystemState(name: string): string?
	local entry = self._systems[name]
	return entry and entry.state
end

-- Dependency order (Kahn's algorithm) over required Dependencies only. Optional
-- dependencies never affect order (so they can point "upwards" without cycles); systems
-- must look them up lazily at call time with ctx:GetSystem, never cache them in Init.
function Kernel:_resolveOrder(): { string }
	local names = TableUtil.keys(self._systems)
	table.sort(names)
	local indegree, edges = {}, {}
	for _, name in names do
		indegree[name] = 0
		edges[name] = {}
	end
	for _, name in names do
		local module = self._systems[name].module
		for _, dep in module.Dependencies or {} do
			if self._systems[dep] then
				table.insert(edges[dep], name)
				indegree[name] += 1
			end
		end
	end
	local queue, order = {}, {}
	for _, name in names do
		if indegree[name] == 0 then
			table.insert(queue, name)
		end
	end
	while #queue > 0 do
		table.sort(queue)
		local name = table.remove(queue, 1)
		table.insert(order, name)
		for _, dependent in edges[name] do
			indegree[dependent] -= 1
			if indegree[dependent] == 0 then
				table.insert(queue, dependent)
			end
		end
	end
	if #order ~= #names then
		local stuck = {}
		for _, name in names do
			if indegree[name] > 0 then
				table.insert(stuck, name)
			end
		end
		error("[Kernel] dependency cycle between: " .. table.concat(stuck, ", "))
	end
	return order
end

local function runHook(scope: string, fn, ...: any): (boolean, string?)
	local ok, err = xpcall(fn, debug.traceback, ...)
	if not ok then
		warn(string.format("[Kernel] %s failed: %s", scope, tostring(err)))
	end
	return ok, if ok then nil else tostring(err)
end

function Kernel:Start()
	assert(not self._started, "kernel already started")
	self._started = true
	self._order = self:_resolveOrder()

	-- Init in dependency order; a failed/missing required dependency disables the system.
	for _, name in self._order do
		local entry = self._systems[name]
		local missing
		for _, dep in entry.module.Dependencies or {} do
			if self:_systemApi(dep) == nil then
				missing = dep
				break
			end
		end
		if missing then
			entry.state = "failed"
			entry.error = "missing dependency " .. missing
			warn(string.format("[Kernel] %s disabled: required dependency '%s' is not plugged in or failed", name, missing))
		else
			entry.ctx = Context.new(self, entry)
			local ok, err = true, nil
			if entry.module.Init then
				ok, err = runHook(name .. ".Init", entry.module.Init, entry.ctx)
			end
			entry.state = if ok then "ready" else "failed"
			entry.error = err
		end
	end
	for _, name in self._order do
		local entry = self._systems[name]
		if entry.state == "ready" and entry.module.Start then
			runHook(name .. ".Start", entry.module.Start)
		end
	end

	self.Scheduler:Every(Kernel.FlushSeconds, function()
		self.State:FlushAll()
	end, "Kernel.Flush")
	self.Scheduler:Every(Kernel.AutosaveSeconds, function()
		self:SaveAll(false)
	end, "Kernel.Autosave")

	local adapters = self.Adapters
	adapters.Players.OnAdded(function(player)
		self:_onPlayerAdded(player)
	end)
	adapters.Players.OnRemoving(function(player)
		self:_onPlayerRemoving(player)
	end)
	for _, player in adapters.Players.GetPlayers() do
		adapters.Spawn(function()
			self:_onPlayerAdded(player)
		end)
	end
	adapters.OnStep(function()
		self.Scheduler:Step()
	end)
	adapters.BindToClose(function()
		self:Shutdown()
	end)

	local summary = {}
	for _, name in self._order do
		table.insert(summary, name .. "=" .. self._systems[name].state)
	end
	print("[Kernel] started: " .. table.concat(summary, ", "))
end

-- Players --------------------------------------------------------------------------------

function Kernel:IsReady(player: any): boolean
	local record = self._players[player]
	return record ~= nil and record.ready
end

function Kernel:ReadyPlayers(): { any }
	local list = {}
	for player, record in self._players do
		if record.ready then
			table.insert(list, player)
		end
	end
	return list
end

function Kernel:PlayerByUserId(userId: number): any?
	for player, record in self._players do
		if record.ready and player.UserId == userId then
			return player
		end
	end
	return nil
end

function Kernel:_prepareProfile(_player, data)
	local now = self.Clock.Now()
	local meta = data._meta
	if not meta then
		meta = { created = now, lastSeen = 0, joins = 0, playSeconds = 0, versions = {} }
		data._meta = meta
	end
	meta.versions = meta.versions or {}
	for _, name in self._order do
		local entry = self._systems[name]
		local spec = entry.module.Profile
		if entry.state == "ready" and spec then
			local defaults = spec.Default()
			local section = data[name]
			if section == nil then
				data[name] = defaults
				meta.versions[name] = spec.Version or 1
			else
				local from = meta.versions[name] or 1
				local to = spec.Version or 1
				if from < to and spec.Migrate then
					local ok, result = xpcall(spec.Migrate, debug.traceback, section, from)
					if ok and type(result) == "table" then
						section = result
					else
						warn(string.format("[Kernel] %s migration %d→%d failed: %s", name, from, to, tostring(result)))
					end
				end
				meta.versions[name] = to
				data[name] = TableUtil.reconcile(section, defaults)
			end
		end
	end
	return meta
end

function Kernel:_onPlayerAdded(player)
	if self._players[player] then
		return
	end
	local record = { ready = false, session = {}, joinedAt = self.Clock.Now() }
	self._players[player] = record

	local data, err = self.Data:Load(player)
	if not data then
		self._players[player] = nil
		self.Adapters.Players.Kick(player, err or "Could not load your ranch.")
		return
	end
	if self._players[player] ~= record then
		-- Player left while loading: release the lock we just took.
		self.Data:Save(player, true)
		return
	end

	local meta = self:_prepareProfile(player, data)
	local now = self.Clock.Now()
	local info = {
		firstJoin = meta.joins == 0,
		awaySeconds = if meta.lastSeen > 0 then math.clamp(now - meta.lastSeen, 0, self.Adapters.OfflineMaxSeconds or 604800) else 0,
		lastSeen = meta.lastSeen,
	}
	for _, name in self._order do
		local entry = self._systems[name]
		if entry.state == "ready" and entry.module.PlayerAdded then
			runHook(name .. ".PlayerAdded", entry.module.PlayerAdded, player, info)
		end
	end
	meta.joins += 1
	meta.lastSeen = now
	record.ready = true
	self.State:SendSnapshot(player)
	self.Bus:Publish("PlayerReady", player, info)
	self.Analytics.Custom(player, "Session_Start", info.awaySeconds, { firstJoin = tostring(info.firstJoin) })
end

function Kernel:_beforeSave(player)
	for _, name in self._order do
		local entry = self._systems[name]
		if entry.state == "ready" and entry.module.BeforeSave then
			runHook(name .. ".BeforeSave", entry.module.BeforeSave, player)
		end
	end
	local data = self.Data:Get(player)
	if data and data._meta then
		data._meta.lastSeen = self.Clock.Now()
	end
end

function Kernel:_onPlayerRemoving(player)
	local record = self._players[player]
	if not record then
		return
	end
	if record.ready then
		self.Bus:Publish("PlayerLeaving", player, {})
		for i = #self._order, 1, -1 do
			local name = self._order[i]
			local entry = self._systems[name]
			if entry.state == "ready" and entry.module.PlayerRemoving then
				runHook(name .. ".PlayerRemoving", entry.module.PlayerRemoving, player)
			end
		end
		local data = self.Data:Get(player)
		if data and data._meta then
			data._meta.playSeconds += self.Clock.Now() - record.joinedAt
		end
		self:_beforeSave(player)
		self.Data:Save(player, true)
	end
	self._players[player] = nil
	self.State:Forget(player)
	self.Net:Forget(player)
	self.Data:Forget(player)
end

function Kernel:SaveAll(release: boolean)
	for _, player in self:ReadyPlayers() do
		self:_beforeSave(player)
		if release then
			self.Data:Save(player, true)
		else
			self.Adapters.Spawn(function()
				self.Data:Save(player, false)
			end)
		end
	end
end

function Kernel:Shutdown()
	for _, player in self:ReadyPlayers() do
		self:_onPlayerRemoving(player)
	end
end

return Kernel
