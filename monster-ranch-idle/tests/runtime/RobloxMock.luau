--[[
	RobloxMock: a strict, in-memory Roblox client runtime for Lune, used to run the real
	client code (controllers, screens, visuals) and the server's world builder in tests.

	What is real:
	  · Datatypes and Enums come from @lune/roblox (UDim2, CFrame, Color3, Enum.Font, …), so
	    maths and invalid enum items behave exactly like Roblox.
	  · Every class and property is checked against Roblox's reflection database: creating an
	    unknown or non-creatable class, reading or writing a property that does not exist,
	    writing a read-only property, or assigning the wrong type raises the same kind of
	    error Roblox would.

	What is emulated (enough for UI and world code, not physics):
	  · Instances: hierarchy, names, attributes (with Roblox's type rules), Clone/Destroy,
	    property-changed signals, a simple layout pass for AbsoluteSize/AbsolutePosition,
	    model pivots.
	  · Signals: Connect/Once/Wait/Disconnect; handlers run in new threads like Roblox.
	  · A virtual task scheduler (spawn/defer/delay/wait/cancel) driven by World:Frame(dt), so
	    tests control time and never sleep.
	  · Services: Players, RunService, TweenService (tweens land at their end values when
	    they finish), UserInputService, MarketplaceService (prompts are recorded), Debris,
	    Lighting, GuiService, Workspace (camera, server time), ContextActionService, and input
	    devices in world.input (last input type, connected pads, action bindings; driven by
	    ClientHarness:UseGamepad / :Press / :Stick).

	Errors thrown in any game thread are collected in world.errors with a traceback instead
	of crashing the test, the way they would print to Studio's output.

	Only the members game code actually uses are implemented. Anything else raises
	"X is not a valid member of Y" so a gap in the mock is loud, never silently wrong.
]]

local roblox = require("@lune/roblox")

local DB = roblox.getReflectionDatabase()
local Enum = roblox.Enum
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local UDim2 = roblox.UDim2
local Color3 = roblox.Color3

local luneTypeof = typeof

local RobloxMock = {}

-- ─── Reflection ─────────────────────────────────────────────────────────────────────

local classCache = {}

local function hasTag(tags, tag: string): boolean
	return tags ~= nil and table.find(tags, tag) ~= nil
end

local function classInfo(name: string)
	local cached = classCache[name]
	if cached then
		return cached
	end
	local ok, def = pcall(function()
		return DB:GetClass(name)
	end)
	if not ok or def == nil then
		return nil
	end
	local chain = {}
	local props, defaults = {}, {}
	local cursor = def
	while cursor do
		table.insert(chain, cursor.Name)
		for propName, prop in cursor.Properties do
			if props[propName] == nil then
				props[propName] = prop
			end
		end
		for propName, value in cursor.DefaultProperties or {} do
			if defaults[propName] == nil then
				defaults[propName] = value
			end
		end
		cursor = if cursor.Superclass then DB:GetClass(cursor.Superclass) else nil
	end
	local isA = {}
	for _, n in chain do
		isA[n] = true
	end
	local info = {
		Name = name,
		chain = chain,
		isA = isA,
		props = props,
		defaults = defaults,
		creatable = not hasTag(def.Tags, "NotCreatable") and not hasTag(def.Tags, "Service"),
		service = hasTag(def.Tags, "Service"),
	}
	classCache[name] = info
	return info
end
RobloxMock.classInfo = classInfo

local SIMPLE_TYPES = {
	Bool = "boolean",
	Float32 = "number",
	Float64 = "number",
	Int32 = "number",
	Int64 = "number",
	String = "string",
	BinaryString = "string",
	Content = "string",
	ContentId = "string",
	Color3uint8 = "Color3",
}

local ROBLOX_TYPES = {
	UDim2 = true,
	UDim = true,
	Vector2 = true,
	Vector3 = true,
	CFrame = true,
	Color3 = true,
	ColorSequence = true,
	NumberSequence = true,
	NumberRange = true,
	Rect = true,
	Font = true,
	BrickColor = true,
	PhysicalProperties = true,
	Ray = true,
	Faces = true,
	Axes = true,
	Vector2int16 = true,
	Vector3int16 = true,
}

local TWEENABLE = {
	number = true,
	boolean = true,
	CFrame = true,
	Rect = true,
	Color3 = true,
	UDim = true,
	UDim2 = true,
	Vector2 = true,
	Vector2int16 = true,
	Vector3 = true,
	EnumItem = true,
}

local ATTRIBUTE_TYPES = {
	string = true,
	boolean = true,
	number = true,
	UDim = true,
	UDim2 = true,
	BrickColor = true,
	Color3 = true,
	Vector2 = true,
	Vector3 = true,
	CFrame = true,
	NumberSequence = true,
	ColorSequence = true,
	NumberRange = true,
	Rect = true,
	Font = true,
	EnumItem = true,
}

-- ─── Scheduler ──────────────────────────────────────────────────────────────────────

local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(world)
	return setmetatable({
		world = world,
		timers = {}, -- { at, thread, args, elapsedFrom? }
		deferred = {}, -- { thread, args }
		cancelled = setmetatable({}, { __mode = "k" }),
		seq = 0,
	}, Scheduler)
end

function Scheduler:_resume(thread: thread, ...)
	if self.cancelled[thread] or coroutine.status(thread) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		self.world:_error(debug.traceback(thread, tostring(err)))
	end
end

function Scheduler:spawn(fnOrThread, ...)
	local thread = if type(fnOrThread) == "thread" then fnOrThread else coroutine.create(fnOrThread)
	self:_resume(thread, ...)
	return thread
end

function Scheduler:defer(fnOrThread, ...)
	local thread = if type(fnOrThread) == "thread" then fnOrThread else coroutine.create(fnOrThread)
	table.insert(self.deferred, { thread = thread, args = table.pack(...) })
	return thread
end

function Scheduler:delay(seconds: number?, fnOrThread, ...)
	local thread = if type(fnOrThread) == "thread" then fnOrThread else coroutine.create(fnOrThread)
	self.seq += 1
	table.insert(
		self.timers,
		{ at = self.world:Clock() + math.max(0, seconds or 0), seq = self.seq, thread = thread, args = table.pack(...) }
	)
	return thread
end

function Scheduler:wait(seconds: number?)
	local thread = coroutine.running()
	if not coroutine.isyieldable() then
		error("task.wait called from a thread that cannot yield", 2)
	end
	local started = self.world:Clock()
	self.seq += 1
	table.insert(self.timers, { at = started + math.max(0, seconds or 0), seq = self.seq, thread = thread, waitFrom = started })
	return coroutine.yield()
end

function Scheduler:cancel(thread: thread)
	self.cancelled[thread] = true
	if coroutine.status(thread) == "suspended" then
		pcall(coroutine.close, thread)
	end
end

function Scheduler:runDeferred()
	-- Deferred work can defer more work; cap the rounds so a loop cannot hang the test.
	for _ = 1, 50 do
		if #self.deferred == 0 then
			return
		end
		local batch = self.deferred
		self.deferred = {}
		for _, item in batch do
			self:_resume(item.thread, table.unpack(item.args, 1, item.args.n))
		end
	end
	self.world:_error("deferred work kept re-scheduling itself for 50 rounds")
end

function Scheduler:runTimers()
	local now = self.world:Clock()
	while true do
		local dueIndex, due = nil, nil
		for i, timer in self.timers do
			if timer.at <= now and (due == nil or timer.at < due.at or (timer.at == due.at and timer.seq < due.seq)) then
				dueIndex, due = i, timer
			end
		end
		if not due then
			return
		end
		table.remove(self.timers, dueIndex)
		if due.waitFrom then
			self:_resume(due.thread, now - due.waitFrom)
		else
			self:_resume(due.thread, table.unpack(due.args, 1, due.args.n))
		end
		self:runDeferred()
	end
end

function Scheduler:taskLibrary()
	local sched = self
	return {
		spawn = function(fn, ...)
			return sched:spawn(fn, ...)
		end,
		defer = function(fn, ...)
			return sched:defer(fn, ...)
		end,
		delay = function(seconds, fn, ...)
			return sched:delay(seconds, fn, ...)
		end,
		wait = function(seconds)
			return sched:wait(seconds)
		end,
		cancel = function(thread)
			sched:cancel(thread)
		end,
		synchronize = function() end,
		desynchronize = function() end,
	}
end

-- ─── Signals ────────────────────────────────────────────────────────────────────────

local signalRegistry = setmetatable({}, { __mode = "k" })
local connectionRegistry = setmetatable({}, { __mode = "k" })

local Signal = {}
Signal.__index = Signal

function Signal.new(world, name: string?, queueWhenIdle: boolean?)
	local self = setmetatable({ _world = world, _conns = {}, _name = name or "Signal", _queue = if queueWhenIdle then {} else nil }, Signal)
	signalRegistry[self] = true
	return self
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Attempt to connect failed: Passed value is not a function")
	local conn
	conn = setmetatable({
		Connected = true,
		_fn = fn,
		Disconnect = function(c)
			c.Connected = false
			local i = table.find(self._conns, c)
			if i then
				table.remove(self._conns, i)
			end
		end,
	}, {
		__index = function(_, key)
			error(tostring(key) .. " is not a valid member of RBXScriptConnection", 2)
		end,
	})
	connectionRegistry[conn] = true
	table.insert(self._conns, conn)
	-- RemoteEvents queue messages until the first listener connects.
	if self._queue and #self._queue > 0 then
		local queued = self._queue
		self._queue = {}
		for _, args in queued do
			self._world.sched:defer(fn, table.unpack(args, 1, args.n))
		end
	end
	return conn
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Wait()
	local thread = coroutine.running()
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		self._world.sched:_resume(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:ConnectParallel(fn)
	return self:Connect(fn)
end

-- Internal (not part of the Roblox API).
function Signal:_fire(...)
	if #self._conns == 0 and self._queue then
		table.insert(self._queue, table.pack(...))
		return
	end
	for _, conn in table.clone(self._conns) do
		if conn.Connected then
			self._world.sched:spawn(conn._fn, ...)
		end
	end
end

function Signal:_disconnectAll()
	for _, conn in table.clone(self._conns) do
		conn:Disconnect()
	end
end

-- ─── Instances ──────────────────────────────────────────────────────────────────────

local records = setmetatable({}, { __mode = "k" })
RobloxMock.records = records

local function isInstance(value): boolean
	return type(value) == "table" and records[value] ~= nil
end
RobloxMock.isInstance = isInstance

local function recOf(proxy)
	local rec = records[proxy]
	if not rec then
		error("expected an Instance, got " .. luneTypeof(proxy), 3)
	end
	return rec
end

-- Members[className] = { methods = {}, events = { name = true }, get = {}, set = {} }
local Members = {}
local function members(className: string)
	Members[className] = Members[className] or { methods = {}, events = {}, get = {}, set = {} }
	return Members[className]
end

local function findMember(rec, kind: string, key: string)
	for _, cls in rec.class.chain do
		local m = Members[cls]
		if m and m[kind][key] ~= nil then
			return m[kind][key]
		end
	end
	return nil
end

local function fullName(rec): string
	local parts = {}
	local cursor = rec
	while cursor and cursor.class.Name ~= "DataModel" do
		table.insert(parts, 1, cursor.props.Name)
		cursor = cursor.parent and records[cursor.parent]
	end
	return table.concat(parts, ".")
end

local function typeError(rec, key: string, expected: string, value)
	error(
		string.format(
			"Unable to assign property %s. %s expected, got %s (on %s %q)",
			key,
			expected,
			luneTypeof(value),
			rec.class.Name,
			fullName(rec)
		),
		4
	)
end

-- Validates and normalises a value for a reflected property.
local function coerce(rec, key: string, prop, value)
	local datatype = prop.Datatype
	if string.sub(datatype, 1, 5) == "Enum." then
		local enumName = string.sub(datatype, 6)
		local enum = Enum[enumName]
		if luneTypeof(value) == "EnumItem" then
			if value.EnumType ~= enum then
				typeError(rec, key, datatype, value)
			end
			return value
		elseif type(value) == "string" or type(value) == "number" then
			for _, item in enum:GetEnumItems() do
				if item.Name == value or item.Value == value then
					return item
				end
			end
		end
		typeError(rec, key, datatype, value)
	end
	if datatype == "Ref" then
		if value ~= nil and not isInstance(value) then
			typeError(rec, key, "Instance", value)
		end
		return value
	end
	local simple = SIMPLE_TYPES[datatype]
	if simple then
		if datatype == "Content" or datatype == "ContentId" then
			if type(value) == "string" or luneTypeof(value) == "Content" then
				return value
			end
			typeError(rec, key, "string", value)
		end
		if luneTypeof(value) ~= simple then
			typeError(rec, key, simple, value)
		end
		if simple == "number" and value ~= value then
			error(string.format("Unable to assign property %s: NaN on %s", key, fullName(rec)), 4)
		end
		return value
	end
	if ROBLOX_TYPES[datatype] then
		if luneTypeof(value) ~= datatype then
			typeError(rec, key, datatype, value)
		end
		return value
	end
	return value
end

local function defaultFor(rec, key: string, prop)
	local value = rec.class.defaults[key]
	if value ~= nil then
		return value
	end
	local datatype = prop.Datatype
	if string.sub(datatype, 1, 5) == "Enum." then
		-- Roblox's default is the item with the lowest value (AutomaticSize.None, TextTruncate.None).
		-- GetEnumItems() comes back in a different order in different processes, so taking
		-- the first item made unset enums (AutomaticSize, …) random between runs.
		local best
		for _, item in Enum[string.sub(datatype, 6)]:GetEnumItems() do
			if best == nil or item.Value < best.Value then
				best = item
			end
		end
		return best
	end
	local simple = SIMPLE_TYPES[datatype]
	if simple == "boolean" then
		return false
	elseif simple == "number" then
		return 0
	elseif simple == "string" then
		return ""
	elseif datatype == "UDim2" then
		return UDim2.new()
	elseif datatype == "UDim" then
		return roblox.UDim.new()
	elseif datatype == "Vector2" then
		return Vector2.zero
	elseif datatype == "Vector3" then
		return Vector3.zero
	elseif datatype == "CFrame" then
		return CFrame.identity
	elseif datatype == "Color3" or datatype == "Color3uint8" then
		return Color3.new()
	end
	return nil
end

local function descendantsOf(rec, out)
	for _, child in rec.children do
		table.insert(out, child)
		descendantsOf(records[child], out)
	end
	return out
end

local function isDescendantOf(rec, ancestorProxy): boolean
	local cursor = rec.parent
	while cursor do
		if cursor == ancestorProxy then
			return true
		end
		cursor = records[cursor].parent
	end
	return false
end

local function signalFor(rec, name: string)
	rec.signals[name] = rec.signals[name] or Signal.new(rec.world, name, rec.queueEvents and rec.queueEvents[name])
	return rec.signals[name]
end

local function firePropChanged(rec, key: string)
	local sig = rec.propSignals[key]
	if sig then
		sig:_fire()
	end
	local changed = rec.signals.Changed
	if changed then
		changed:_fire(key)
	end
end

local function setParent(rec, newParent)
	if rec.parentLocked then
		error(
			string.format("The Parent property of %s is locked, current parent: NULL, new parent %s", rec.props.Name, tostring(newParent)),
			3
		)
	end
	if newParent ~= nil and not isInstance(newParent) then
		typeError(rec, "Parent", "Instance", newParent)
	end
	if newParent == rec.proxy or (newParent and isDescendantOf(records[newParent], rec.proxy)) then
		error("Attempt to set " .. fullName(rec) .. " as its own ancestor", 3)
	end
	local old = rec.parent
	if old == newParent then
		return
	end
	if old then
		local oldRec = records[old]
		local i = table.find(oldRec.children, rec.proxy)
		if i then
			table.remove(oldRec.children, i)
		end
		if oldRec.signals.ChildRemoved then
			oldRec.signals.ChildRemoved:_fire(rec.proxy)
		end
	end
	rec.parent = newParent
	if newParent then
		local parentRec = records[newParent]
		table.insert(parentRec.children, rec.proxy)
		if parentRec.signals.ChildAdded then
			parentRec.signals.ChildAdded:_fire(rec.proxy)
		end
		local cursor = newParent
		local added = { rec.proxy }
		descendantsOf(rec, added)
		while cursor do
			local cr = records[cursor]
			if cr.signals.DescendantAdded then
				for _, d in added do
					cr.signals.DescendantAdded:_fire(d)
				end
			end
			cursor = cr.parent
		end
	end
	if rec.signals.AncestryChanged then
		rec.signals.AncestryChanged:_fire(rec.proxy, newParent)
	end
	firePropChanged(rec, "Parent")
end

local instanceMeta = {}

instanceMeta.__index = function(proxy, key)
	local rec = records[proxy]
	if key == "Parent" then
		return rec.parent
	elseif key == "ClassName" then
		return rec.class.Name
	elseif key == "Name" then
		return rec.props.Name
	end
	local getter = findMember(rec, "get", key)
	if getter then
		return getter(rec)
	end
	local method = findMember(rec, "methods", key)
	if method then
		return method
	end
	if findMember(rec, "events", key) then
		return signalFor(rec, key)
	end
	local prop = rec.class.props[key]
	if prop and prop.Scriptability ~= "None" then
		local value = rec.props[key]
		if value == nil then
			value = defaultFor(rec, key, prop)
		end
		return value
	end
	for _, child in rec.children do
		if records[child].props.Name == key then
			return child
		end
	end
	error(string.format("%s is not a valid member of %s %q", tostring(key), rec.class.Name, fullName(rec)), 2)
end

instanceMeta.__newindex = function(proxy, key, value)
	local rec = records[proxy]
	if key == "Parent" then
		setParent(rec, value)
		return
	elseif key == "Name" then
		if type(value) ~= "string" then
			typeError(rec, key, "string", value)
		end
		rec.props.Name = value
		firePropChanged(rec, "Name")
		return
	end
	local setter = findMember(rec, "set", key)
	if setter then
		setter(rec, value)
		firePropChanged(rec, key)
		return
	end
	local prop = rec.class.props[key]
	if not prop or prop.Scriptability == "None" then
		error(string.format("%s is not a valid member of %s %q", tostring(key), rec.class.Name, fullName(rec)), 2)
	end
	if prop.Scriptability ~= "ReadWrite" and prop.Scriptability ~= "Custom" then
		error(string.format("Unable to assign property %s. Property is read only (%s)", key, rec.class.Name), 2)
	end
	local coerced = coerce(rec, key, prop, value)
	if rec.props[key] ~= coerced then
		rec.props[key] = coerced
		firePropChanged(rec, key)
	end
end

instanceMeta.__tostring = function(proxy)
	return records[proxy].props.Name
end

local function newInstance(world, className: string)
	local info = classInfo(className)
	if not info then
		error(string.format("Unable to create an Instance of type %q", className), 3)
	end
	local proxy = setmetatable({}, instanceMeta)
	local rec = {
		proxy = proxy,
		class = info,
		world = world,
		props = { Name = className },
		children = {},
		parent = nil,
		attributes = {},
		signals = {},
		propSignals = {},
		tags = {},
		extra = {},
	}
	records[proxy] = rec
	return proxy, rec
end
RobloxMock.newInstance = newInstance

-- Sets a value without checks (engine-owned properties such as Player.UserId).
function RobloxMock.rawSet(proxy, key: string, value)
	local rec = recOf(proxy)
	if key == "Parent" then
		setParent(rec, value)
	else
		rec.props[key] = value
		firePropChanged(rec, key)
	end
end

function RobloxMock.fire(proxy, eventName: string, ...)
	local rec = recOf(proxy)
	assert(findMember(rec, "events", eventName), eventName .. " is not an event of " .. rec.class.Name)
	signalFor(rec, eventName):_fire(...)
end

function RobloxMock.hasConnections(proxy, eventName: string): boolean
	local rec = recOf(proxy)
	local sig = rec.signals[eventName]
	return sig ~= nil and #sig._conns > 0
end

-- ─── Instance members ───────────────────────────────────────────────────────────────

local function define(className: string, spec)
	local m = members(className)
	for name, fn in spec.methods or {} do
		m.methods[name] = fn
	end
	for _, name in spec.events or {} do
		m.events[name] = true
	end
	for name, fn in spec.get or {} do
		m.get[name] = fn
	end
	for name, fn in spec.set or {} do
		m.set[name] = fn
	end
end

local function validAttributeName(name): boolean
	return type(name) == "string"
		and #name > 0
		and #name <= 100
		and string.match(name, "^[%w_]+$") ~= nil
		and string.sub(name, 1, 3) ~= "RBX"
end

local function cloneRec(rec)
	local copy, copyRec = newInstance(rec.world, rec.class.Name)
	for k, v in rec.props do
		copyRec.props[k] = v
	end
	for k, v in rec.attributes do
		copyRec.attributes[k] = v
	end
	for k in rec.tags do
		copyRec.tags[k] = true
	end
	for k, v in rec.extra do
		copyRec.extra[k] = v
	end
	local map = { [rec.proxy] = copy }
	for _, child in rec.children do
		local childRec = records[child]
		if childRec.props.Archivable ~= false then
			local childCopy, childMap = cloneRec(childRec)
			records[childCopy].parent = copy
			table.insert(copyRec.children, childCopy)
			for k, v in childMap do
				map[k] = v
			end
		end
	end
	return copy, map
end

local function destroy(rec)
	if rec.destroyed then
		return
	end
	rec.destroyed = true
	if rec.signals.Destroying then
		rec.signals.Destroying:_fire()
	end
	for _, child in table.clone(rec.children) do
		destroy(records[child])
	end
	if rec.parent then
		setParent(rec, nil)
	end
	rec.parentLocked = true
	for _, sig in rec.signals do
		sig:_disconnectAll()
	end
	for _, sig in rec.propSignals do
		sig:_disconnectAll()
	end
end

define("Instance", {
	events = {
		"ChildAdded",
		"ChildRemoved",
		"DescendantAdded",
		"DescendantRemoving",
		"AncestryChanged",
		"Changed",
		"Destroying",
		"AttributeChanged",
	},
	methods = {
		Destroy = function(self)
			destroy(recOf(self))
		end,
		Clone = function(self)
			local rec = recOf(self)
			if rec.props.Archivable == false then
				return nil
			end
			local copy, map = cloneRec(rec)
			-- Remap Ref properties that pointed inside the cloned tree (e.g. PrimaryPart, welds).
			for original, cloned in map do
				local oRec, cRec = records[original], records[cloned]
				for k, v in oRec.props do
					if isInstance(v) and map[v] then
						cRec.props[k] = map[v]
					end
				end
			end
			return copy
		end,
		ClearAllChildren = function(self)
			for _, child in table.clone(recOf(self).children) do
				destroy(records[child])
			end
		end,
		FindFirstChild = function(self, name: string, recursive: boolean?)
			local rec = recOf(self)
			local list = if recursive then descendantsOf(rec, {}) else rec.children
			for _, child in list do
				if records[child].props.Name == name then
					return child
				end
			end
			return nil
		end,
		FindFirstChildOfClass = function(self, className: string)
			for _, child in recOf(self).children do
				if records[child].class.Name == className then
					return child
				end
			end
			return nil
		end,
		FindFirstChildWhichIsA = function(self, className: string, recursive: boolean?)
			local rec = recOf(self)
			local list = if recursive then descendantsOf(rec, {}) else rec.children
			for _, child in list do
				if records[child].class.isA[className] then
					return child
				end
			end
			return nil
		end,
		FindFirstAncestor = function(self, name: string)
			local cursor = recOf(self).parent
			while cursor do
				if records[cursor].props.Name == name then
					return cursor
				end
				cursor = records[cursor].parent
			end
			return nil
		end,
		FindFirstAncestorOfClass = function(self, className: string)
			local cursor = recOf(self).parent
			while cursor do
				if records[cursor].class.Name == className then
					return cursor
				end
				cursor = records[cursor].parent
			end
			return nil
		end,
		FindFirstAncestorWhichIsA = function(self, className: string)
			local cursor = recOf(self).parent
			while cursor do
				if records[cursor].class.isA[className] then
					return cursor
				end
				cursor = records[cursor].parent
			end
			return nil
		end,
		WaitForChild = function(self, name: string, timeout: number?)
			local rec = recOf(self)
			for _, child in rec.children do
				if records[child].props.Name == name then
					return child
				end
			end
			local world = rec.world
			local thread = coroutine.running()
			local done = false
			local conn
			conn = signalFor(rec, "ChildAdded"):Connect(function(child)
				if not done and records[child].props.Name == name then
					done = true
					conn:Disconnect()
					world.sched:_resume(thread, child)
				end
			end)
			if timeout then
				world.sched:delay(timeout, function()
					if not done then
						done = true
						conn:Disconnect()
						world.sched:_resume(thread, nil)
					end
				end)
			else
				world.sched:delay(5, function()
					if not done then
						world:_warn(string.format("Infinite yield possible on '%s:WaitForChild(%q)'", fullName(rec), name))
					end
				end)
			end
			return coroutine.yield()
		end,
		GetChildren = function(self)
			return table.clone(recOf(self).children)
		end,
		GetDescendants = function(self)
			return descendantsOf(recOf(self), {})
		end,
		IsA = function(self, className: string)
			return recOf(self).class.isA[className] == true
		end,
		IsDescendantOf = function(self, ancestor)
			return isDescendantOf(recOf(self), ancestor)
		end,
		IsAncestorOf = function(self, descendant)
			return isDescendantOf(recOf(descendant), self)
		end,
		GetFullName = function(self)
			return fullName(recOf(self))
		end,
		GetAttribute = function(self, name: string)
			return recOf(self).attributes[name]
		end,
		GetAttributes = function(self)
			return table.clone(recOf(self).attributes)
		end,
		SetAttribute = function(self, name: string, value)
			local rec = recOf(self)
			if not validAttributeName(name) then
				error("Attribute name '" .. tostring(name) .. "' is invalid", 2)
			end
			if value ~= nil and not ATTRIBUTE_TYPES[luneTypeof(value)] then
				error(string.format("%s is not a supported attribute type (attribute %s)", luneTypeof(value), name), 2)
			end
			if rec.attributes[name] ~= value then
				rec.attributes[name] = value
				local sig = rec.propSignals["@" .. name]
				if sig then
					sig:_fire()
				end
				if rec.signals.AttributeChanged then
					rec.signals.AttributeChanged:_fire(name)
				end
			end
		end,
		GetAttributeChangedSignal = function(self, name: string)
			local rec = recOf(self)
			rec.propSignals["@" .. name] = rec.propSignals["@" .. name] or Signal.new(rec.world, "@" .. name)
			return rec.propSignals["@" .. name]
		end,
		GetPropertyChangedSignal = function(self, name: string)
			local rec = recOf(self)
			if name ~= "Parent" and name ~= "Name" and not rec.class.props[name] and not findMember(rec, "get", name) then
				error(string.format("%s is not a valid property name of %s", tostring(name), rec.class.Name), 2)
			end
			rec.propSignals[name] = rec.propSignals[name] or Signal.new(rec.world, name)
			return rec.propSignals[name]
		end,
		AddTag = function(self, tag: string)
			recOf(self).tags[tag] = true
		end,
		RemoveTag = function(self, tag: string)
			recOf(self).tags[tag] = nil
		end,
		HasTag = function(self, tag: string)
			return recOf(self).tags[tag] == true
		end,
		GetTags = function(self)
			local list = {}
			for tag in recOf(self).tags do
				table.insert(list, tag)
			end
			return list
		end,
	},
})

-- Layout: a small pass for AbsoluteSize/AbsolutePosition. It honours Size, Position,
-- AnchorPoint and UIScale, and ignores layouts, padding and AutomaticSize.
local function uiScaleOf(rec): number
	for _, child in rec.children do
		local c = records[child]
		if c.class.Name == "UIScale" then
			return c.props.Scale or 1
		end
	end
	return 1
end

local absolute
function absolute(rec): (Vector2, Vector2, number)
	local world = rec.world
	local cls = rec.class
	if cls.isA.LayerCollector then
		if cls.Name == "ScreenGui" then
			return Vector2.zero, world.viewport, 1
		end
		local size = rec.props.Size
		if typeof(size) == "UDim2" then
			return Vector2.zero, Vector2.new(size.X.Offset, size.Y.Offset), 1
		end
		return Vector2.zero, world.viewport, 1
	end
	if not cls.isA.GuiObject then
		return Vector2.zero, Vector2.zero, 1
	end
	local parentPos, parentSize, parentScale = Vector2.zero, world.viewport, 1
	if rec.parent and records[rec.parent].class.isA.GuiBase2d then
		parentPos, parentSize, parentScale = absolute(records[rec.parent])
	end
	local scale = parentScale * uiScaleOf(rec)
	local size = rec.props.Size or UDim2.new()
	local pos = rec.props.Position or UDim2.new()
	local anchor = rec.props.AnchorPoint or Vector2.zero
	local absSize = Vector2.new(parentSize.X * size.X.Scale + size.X.Offset * scale, parentSize.Y * size.Y.Scale + size.Y.Offset * scale)
	local absPos = parentPos
		+ Vector2.new(parentSize.X * pos.X.Scale + pos.X.Offset * parentScale, parentSize.Y * pos.Y.Scale + pos.Y.Offset * parentScale)
		- absSize * anchor
	return absPos, absSize, scale
end

define("GuiBase2d", {
	get = {
		AbsoluteSize = function(rec)
			local _, size = absolute(rec)
			return size
		end,
		AbsolutePosition = function(rec)
			local pos = absolute(rec)
			return pos
		end,
	},
})

define("GuiObject", {
	events = { "InputBegan", "InputEnded", "InputChanged", "MouseEnter", "MouseLeave", "MouseMoved", "TouchTap", "TouchLongPress" },
	methods = {
		TweenPosition = function()
			return true
		end,
		TweenSize = function()
			return true
		end,
	},
})

define("GuiButton", {
	events = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click" },
})

local function textBounds(rec): Vector2
	local text = rec.props.Text or ""
	local size = rec.props.TextSize or 14
	return Vector2.new(utf8.len(text) or #text, 1) * Vector2.new(size * 0.5, size)
end

define("TextLabel", { get = { TextBounds = textBounds } })
define("TextButton", { get = { TextBounds = textBounds } })
define("TextBox", {
	events = { "FocusLost", "Focused", "ReturnPressedFromOnScreenKeyboard" },
	get = { TextBounds = textBounds },
	methods = {
		CaptureFocus = function(self)
			recOf(self).extra.focused = true
		end,
		ReleaseFocus = function(self)
			recOf(self).extra.focused = false
		end,
		IsFocused = function(self)
			return recOf(self).extra.focused == true
		end,
	},
})

define("UIListLayout", {
	get = {
		AbsoluteContentSize = function(rec)
			local total, cross = 0, 0
			local parent = rec.parent and records[rec.parent]
			if not parent then
				return Vector2.zero
			end
			local horizontal = rec.props.FillDirection == Enum.FillDirection.Horizontal
			local padding = rec.props.Padding
			local gap = if padding then padding.Offset else 0
			local count = 0
			for _, child in parent.children do
				local c = records[child]
				if c.class.isA.GuiObject and c.props.Visible ~= false then
					local _, size = absolute(c)
					count += 1
					if horizontal then
						total += size.X
						cross = math.max(cross, size.Y)
					else
						total += size.Y
						cross = math.max(cross, size.X)
					end
				end
			end
			total += math.max(0, count - 1) * gap
			return if horizontal then Vector2.new(total, cross) else Vector2.new(cross, total)
		end,
	},
})
define("UIGridLayout", {
	get = {
		AbsoluteContentSize = function(rec)
			local parent = rec.parent and records[rec.parent]
			if not parent then
				return Vector2.zero
			end
			local cell = rec.props.CellSize or UDim2.fromOffset(100, 100)
			local count = 0
			for _, child in parent.children do
				if records[child].class.isA.GuiObject then
					count += 1
				end
			end
			return Vector2.new(cell.X.Offset, cell.Y.Offset * count)
		end,
	},
})

define("ScrollingFrame", {
	get = {
		AbsoluteCanvasSize = function(rec)
			local _, size = absolute(rec)
			return size
		end,
		AbsoluteWindowSize = function(rec)
			local _, size = absolute(rec)
			return size
		end,
	},
})

-- 3D
local function partCFrame(rec): CFrame
	return rec.props.CFrame or CFrame.identity
end

define("PVInstance", {
	methods = {
		GetPivot = function(self)
			local rec = recOf(self)
			if rec.class.isA.BasePart then
				return partCFrame(rec) * (rec.props.PivotOffset or CFrame.identity)
			end
			local primary = rec.props.PrimaryPart
			if primary and records[primary] then
				return partCFrame(records[primary])
			end
			return rec.props.WorldPivot or CFrame.identity
		end,
		PivotTo = function(self, cf)
			local rec = recOf(self)
			if typeof(cf) ~= "CFrame" then
				error("PivotTo expects a CFrame, got " .. typeof(cf), 2)
			end
			local current = self:GetPivot()
			local delta = cf * current:Inverse()
			if rec.class.isA.BasePart then
				rec.props.CFrame = delta * partCFrame(rec)
				firePropChanged(rec, "CFrame")
				return
			end
			for _, d in descendantsOf(rec, {}) do
				local dr = records[d]
				if dr.class.isA.BasePart then
					dr.props.CFrame = delta * partCFrame(dr)
				end
			end
			rec.props.WorldPivot = cf
		end,
	},
})

define("Model", {
	methods = {
		GetBoundingBox = function(self)
			local rec = recOf(self)
			local minV, maxV
			for _, d in descendantsOf(rec, {}) do
				local dr = records[d]
				if dr.class.isA.BasePart then
					local p = partCFrame(dr).Position
					local half = (dr.props.Size or Vector3.one) / 2
					minV = if minV then minV:Min(p - half) else p - half
					maxV = if maxV then maxV:Max(p + half) else p + half
				end
			end
			if not minV then
				return self:GetPivot(), Vector3.zero
			end
			return CFrame.new((minV + maxV) / 2), maxV - minV
		end,
		GetExtentsSize = function(self)
			local _, size = self:GetBoundingBox()
			return size
		end,
		GetScale = function(self)
			return recOf(self).extra.scale or 1
		end,
		ScaleTo = function(self, scale: number)
			recOf(self).extra.scale = scale
		end,
	},
})

define("BasePart", {
	events = { "Touched", "TouchEnded" },
	get = {
		Position = function(rec)
			return partCFrame(rec).Position
		end,
		Orientation = function(rec)
			local rx, ry, rz = partCFrame(rec):ToOrientation()
			return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
		end,
		Rotation = function(rec)
			local rx, ry, rz = partCFrame(rec):ToEulerAnglesXYZ()
			return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
		end,
	},
	set = {
		Position = function(rec, value)
			if typeof(value) ~= "Vector3" then
				typeError(rec, "Position", "Vector3", value)
			end
			local cf = partCFrame(rec)
			rec.props.CFrame = cf - cf.Position + value
		end,
		Orientation = function(rec, value)
			if typeof(value) ~= "Vector3" then
				typeError(rec, "Orientation", "Vector3", value)
			end
			rec.props.CFrame = CFrame.new(partCFrame(rec).Position)
				* CFrame.fromOrientation(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
		end,
	},
	methods = {
		GetMass = function(self)
			local s = recOf(self).props.Size or Vector3.one
			return s.X * s.Y * s.Z * 0.7
		end,
		ApplyImpulse = function() end,
		GetTouchingParts = function()
			return {}
		end,
	},
})

define("Humanoid", {
	events = { "Died", "MoveToFinished", "Running", "StateChanged", "HealthChanged" },
	methods = {
		MoveTo = function(self, position, _part)
			local rec = recOf(self)
			local character = rec.parent and records[rec.parent]
			local root = character and character.props.PrimaryPart
			if root then
				local rr = records[root]
				rr.props.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
			end
			rec.world.sched:defer(function()
				signalFor(rec, "MoveToFinished"):_fire(true)
			end)
		end,
		GetState = function()
			return Enum.HumanoidStateType.Running
		end,
		ChangeState = function() end,
		LoadAnimation = function()
			error("Humanoid:LoadAnimation is deprecated; use an Animator", 2)
		end,
	},
})

define("Camera", {
	get = {
		ViewportSize = function(rec)
			return rec.world.viewport
		end,
	},
	methods = {
		ScreenPointToRay = function(self, _x: number, _y: number, depth: number?)
			local cf = recOf(self).props.CFrame or CFrame.identity
			return roblox.Ray.new(cf.Position + cf.LookVector * (depth or 0), cf.LookVector)
		end,
		ViewportPointToRay = function(self, _x: number, _y: number, depth: number?)
			local cf = recOf(self).props.CFrame or CFrame.identity
			return roblox.Ray.new(cf.Position + cf.LookVector * (depth or 0), cf.LookVector)
		end,
		WorldToViewportPoint = function(self, position)
			local rec = recOf(self)
			local cf = rec.props.CFrame or CFrame.identity
			local rel = cf:PointToObjectSpace(position)
			local vp = rec.world.viewport
			return Vector3.new(vp.X / 2 + rel.X * 10, vp.Y / 2 - rel.Y * 10, -rel.Z), rel.Z < 0
		end,
		WorldToScreenPoint = function(self, position)
			return self:WorldToViewportPoint(position)
		end,
	},
})

define("ParticleEmitter", {
	methods = {
		Emit = function(self, count: number?)
			local rec = recOf(self)
			rec.extra.emitted = (rec.extra.emitted or 0) + (count or 16)
		end,
		Clear = function() end,
	},
})

define("Sound", {
	events = { "Ended", "Played", "Loaded", "Stopped", "Paused", "Resumed" },
	methods = {
		Play = function(self)
			local rec = recOf(self)
			rec.props.Playing = true
			table.insert(rec.world.log.sounds, rec.props.SoundId or "")
			signalFor(rec, "Played"):_fire(rec.props.SoundId)
			rec.world.sched:delay(0.5, function()
				if rec.props.Playing and not rec.props.Looped then
					rec.props.Playing = false
					signalFor(rec, "Ended"):_fire(rec.props.SoundId)
				end
			end)
		end,
		Stop = function(self)
			recOf(self).props.Playing = false
		end,
		Pause = function(self)
			recOf(self).props.Playing = false
		end,
		Resume = function(self)
			recOf(self).props.Playing = true
		end,
	},
})

define("ProximityPrompt", {
	events = { "Triggered", "TriggerEnded", "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded" },
	methods = {
		InputHoldBegin = function() end,
		InputHoldEnd = function() end,
	},
})

define("RemoteEvent", {
	events = { "OnClientEvent", "OnServerEvent" },
	methods = {
		FireServer = function(self, ...)
			local rec = recOf(self)
			rec.world.bridge.fireServer(rec.props.Name, ...)
		end,
	},
})

define("RemoteFunction", {
	methods = {
		InvokeServer = function(self, ...)
			local rec = recOf(self)
			return rec.world.bridge.invokeServer(rec.props.Name, ...)
		end,
	},
})

define("BindableEvent", {
	events = { "Event" },
	methods = {
		Fire = function(self, ...)
			signalFor(recOf(self), "Event"):_fire(...)
		end,
	},
})

define("Tween", {
	events = { "Completed" },
	methods = {
		Play = function(self)
			local rec = recOf(self)
			local tween = rec.extra
			if tween.playing then
				return
			end
			tween.playing = true
			rec.props.PlaybackState = Enum.PlaybackState.Playing
			local info = tween.info
			local duration = info.Time * (if info.Reverses then 2 else 1)
			local repeats = info.RepeatCount
			if repeats < 0 then
				-- Infinite tweens never complete; apply the goal once so values are exercised.
				for key, value in tween.goal do
					tween.target[key] = value
				end
				return
			end
			tween.thread = rec.world.sched:delay(info.DelayTime + duration * (repeats + 1), function()
				tween.playing = false
				if records[tween.target].destroyed then
					return
				end
				if not info.Reverses then
					for key, value in tween.goal do
						tween.target[key] = value
					end
				end
				rec.props.PlaybackState = Enum.PlaybackState.Completed
				signalFor(rec, "Completed"):_fire(Enum.PlaybackState.Completed)
			end)
		end,
		Cancel = function(self)
			local rec = recOf(self)
			if rec.extra.thread then
				rec.world.sched:cancel(rec.extra.thread)
			end
			rec.extra.playing = false
			rec.props.PlaybackState = Enum.PlaybackState.Cancelled
		end,
		Pause = function(self)
			local rec = recOf(self)
			if rec.extra.thread then
				rec.world.sched:cancel(rec.extra.thread)
			end
			rec.extra.playing = false
			rec.props.PlaybackState = Enum.PlaybackState.Paused
		end,
	},
})

define("Player", {
	events = { "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Chatted", "Idled" },
	methods = {
		GetMouse = function()
			error("Player:GetMouse is not emulated; use UserInputService", 2)
		end,
		IsFriendsWith = function()
			return false
		end,
		IsInGroup = function()
			return false
		end,
		GetRankInGroup = function()
			return 0
		end,
		Kick = function(self, message)
			recOf(self).world.log.kicked = message or ""
		end,
	},
})

-- ─── Services ───────────────────────────────────────────────────────────────────────

define("DataModel", {
	methods = {
		GetService = function(self, name: string)
			local rec = recOf(self)
			return rec.world:_service(name)
		end,
		FindService = function(self, name: string)
			return recOf(self).world.services[name]
		end,
		IsLoaded = function()
			return true
		end,
		BindToClose = function() end,
	},
	events = { "Loaded" },
	get = {
		Workspace = function(rec)
			return rec.world:_service("Workspace")
		end,
		PlaceId = function()
			return 0
		end,
		GameId = function()
			return 0
		end,
		JobId = function()
			return "client-test"
		end,
	},
})

define("Workspace", {
	methods = {
		GetServerTimeNow = function(self)
			return recOf(self).world:Clock()
		end,
		Raycast = function(self, origin, direction, params)
			if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
				error("Raycast expects (Vector3, Vector3, RaycastParams?)", 2)
			end
			if params ~= nil and luneTypeof(params) ~= "RaycastParams" and typeof(params) ~= "RaycastParams" then
				error("Raycast params must be RaycastParams", 2)
			end
			return recOf(self).world.raycastResult
		end,
		GetPartBoundsInBox = function()
			return {}
		end,
		GetPartBoundsInRadius = function()
			return {}
		end,
		GetPartsInPart = function()
			return {}
		end,
	},
	get = {
		DistributedGameTime = function(rec)
			return rec.world.elapsed
		end,
	},
})

define("Players", {
	events = { "PlayerAdded", "PlayerRemoving" },
	methods = {
		GetPlayers = function(self)
			local list = {}
			for _, child in recOf(self).children do
				if records[child].class.Name == "Player" then
					table.insert(list, child)
				end
			end
			return list
		end,
		GetPlayerByUserId = function(self, userId: number)
			for _, child in recOf(self).children do
				local r = records[child]
				if r.class.Name == "Player" and r.props.UserId == userId then
					return child
				end
			end
			return nil
		end,
		GetPlayerFromCharacter = function(self, character)
			for _, child in recOf(self).children do
				local r = records[child]
				if r.class.Name == "Player" and r.props.Character == character then
					return child
				end
			end
			return nil
		end,
		GetUserThumbnailAsync = function()
			return "rbxthumb://type=AvatarHeadShot&id=1&w=150&h=150", true
		end,
		GetNameFromUserIdAsync = function(_, userId)
			return "Player" .. tostring(userId)
		end,
	},
	get = {
		LocalPlayer = function(rec)
			return rec.world.localPlayer
		end,
	},
})

define("RunService", {
	events = { "Heartbeat", "RenderStepped", "Stepped", "PreRender", "PreAnimation", "PreSimulation", "PostSimulation" },
	methods = {
		IsClient = function()
			return true
		end,
		IsServer = function()
			return false
		end,
		IsStudio = function()
			return false
		end,
		IsRunning = function()
			return true
		end,
		BindToRenderStep = function(self, name: string, _priority: number, fn)
			recOf(self).world.renderBindings[name] = fn
		end,
		UnbindFromRenderStep = function(self, name: string)
			recOf(self).world.renderBindings[name] = nil
		end,
	},
})

local TweenInfoMeta = {}
TweenInfoMeta.__index = function(_, key)
	error(tostring(key) .. " is not a valid member of TweenInfo", 2)
end
local tweenInfoRegistry = setmetatable({}, { __mode = "k" })

local function newTweenInfo(time, style, direction, repeatCount, reverses, delayTime)
	local function checkEnum(value, enum, name)
		if value ~= nil and (luneTypeof(value) ~= "EnumItem" or value.EnumType ~= enum) then
			error("TweenInfo.new: " .. name .. " must be an " .. tostring(enum) .. " item", 3)
		end
	end
	checkEnum(style, Enum.EasingStyle, "easingStyle")
	checkEnum(direction, Enum.EasingDirection, "easingDirection")
	if time ~= nil and type(time) ~= "number" then
		error("TweenInfo.new: time must be a number", 2)
	end
	local info = {
		Time = time or 1,
		EasingStyle = style or Enum.EasingStyle.Quad,
		EasingDirection = direction or Enum.EasingDirection.Out,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delayTime or 0,
	}
	local obj = setmetatable(info, TweenInfoMeta)
	tweenInfoRegistry[obj] = true
	return obj
end

define("TweenService", {
	methods = {
		Create = function(self, target, info, goal)
			local world = recOf(self).world
			if not isInstance(target) then
				error("TweenService:Create: argument #1 must be an Instance", 2)
			end
			if not tweenInfoRegistry[info] then
				error("TweenService:Create: argument #2 must be a TweenInfo", 2)
			end
			if type(goal) ~= "table" then
				error("TweenService:Create: argument #3 must be a table", 2)
			end
			local targetRec = records[target]
			for key, value in goal do
				local prop = targetRec.class.props[key]
				local custom = findMember(targetRec, "set", key)
				if not prop and not custom then
					error(
						string.format("TweenService:Create no property named '%s' for object '%s'", tostring(key), targetRec.props.Name),
						2
					)
				end
				if not TWEENABLE[luneTypeof(value)] then
					error(string.format("TweenService:Create property named '%s' cannot be tweened due to type mismatch", key), 2)
				end
				local current = target[key]
				if luneTypeof(current) ~= luneTypeof(value) then
					error(
						string.format(
							"TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a %s, but given type is %s)",
							key,
							luneTypeof(current),
							luneTypeof(value)
						),
						2
					)
				end
			end
			local tween, rec = newInstance(world, "Tween")
			rec.extra.target = target
			rec.extra.info = info
			rec.extra.goal = table.clone(goal)
			rec.props.PlaybackState = Enum.PlaybackState.Begin
			return tween
		end,
		GetValue = function(_, alpha: number, _style, _direction)
			return alpha
		end,
	},
})

define("UserInputService", {
	events = {
		"InputBegan",
		"InputEnded",
		"InputChanged",
		"TouchTap",
		"TouchStarted",
		"TouchEnded",
		"TouchMoved",
		"LastInputTypeChanged",
		"JumpRequest",
		"WindowFocused",
		"WindowFocusReleased",
		"GamepadConnected",
		"GamepadDisconnected",
	},
	-- Input devices live in world.input (see newWorld); ClientHarness:UseGamepad / :Press
	-- change them the way plugging in a pad or pressing a key would.
	get = {
		GamepadEnabled = function(rec)
			return #rec.world.input.gamepads > 0
		end,
	},
	methods = {
		GetMouseLocation = function(self)
			return recOf(self).world.viewport / 2
		end,
		GetLastInputType = function(self)
			return recOf(self).world.input.lastType
		end,
		GetConnectedGamepads = function(self)
			return table.clone(recOf(self).world.input.gamepads)
		end,
		IsKeyDown = function()
			return false
		end,
		GetFocusedTextBox = function()
			return nil
		end,
	},
})

-- HapticService: a connected pad vibrates; the latest motor values are kept in
-- world.input.motors[padName][motorName] so a test can read what the game asked for.
define("HapticService", {
	methods = {
		IsVibrationSupported = function(self, pad)
			return table.find(recOf(self).world.input.gamepads, pad) ~= nil
		end,
		IsMotorSupported = function(self, pad, _motor)
			return table.find(recOf(self).world.input.gamepads, pad) ~= nil
		end,
		SetMotor = function(self, pad, motor, value: number)
			if luneTypeof(pad) ~= "EnumItem" or luneTypeof(motor) ~= "EnumItem" or type(value) ~= "number" then
				error("SetMotor(inputType: Enum.UserInputType, motor: Enum.VibrationMotor, value: number)", 2)
			end
			local input = recOf(self).world.input
			input.motors = input.motors or {}
			input.motors[pad.Name] = input.motors[pad.Name] or {}
			input.motors[pad.Name][motor.Name] = value
		end,
	},
})

-- ContextActionService: bindings are recorded in world.input.actions; ClientHarness:Press
-- routes a key through them (highest priority first, newest first on ties) before the GUI
-- and UserInputService see it, the order the engine uses.
local function bindAction(self, name, fn, createTouchButton, priority, inputs)
	if type(name) ~= "string" or type(fn) ~= "function" or type(createTouchButton) ~= "boolean" or type(priority) ~= "number" then
		error("BindAction(actionName: string, functionToBind: function, createTouchButton: bool, ...inputTypes)", 3)
	end
	for _, input in inputs do
		if luneTypeof(input) ~= "EnumItem" or (input.EnumType ~= Enum.KeyCode and input.EnumType ~= Enum.UserInputType) then
			error("BindAction: input types must be Enum.KeyCode or Enum.UserInputType items", 3)
		end
	end
	local state = recOf(self).world.input
	state.bindCount += 1
	state.actions[name] = { name = name, fn = fn, priority = priority, inputs = inputs, order = state.bindCount }
end

define("ContextActionService", {
	methods = {
		BindAction = function(self, name, fn, createTouchButton, ...)
			bindAction(self, name, fn, createTouchButton, Enum.ContextActionPriority.Default.Value, { ... })
		end,
		BindActionAtPriority = function(self, name, fn, createTouchButton, priority, ...)
			bindAction(self, name, fn, createTouchButton, priority, { ... })
		end,
		UnbindAction = function(self, name)
			recOf(self).world.input.actions[name] = nil
		end,
	},
})

-- A read-only InputObject as the engine hands to input events (they are not creatable).
function RobloxMock.newInput(world, fields: { [string]: any })
	local input = newInstance(world, "InputObject")
	for key, value in fields do
		RobloxMock.rawSet(input, key, value)
	end
	return input
end

define("GuiService", {
	events = { "MenuOpened", "MenuClosed" },
	methods = {
		GetGuiInset = function()
			return Vector2.new(0, 58), Vector2.zero
		end,
	},
})

define("MarketplaceService", {
	events = { "PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished", "PromptPurchaseFinished", "PromptBundlePurchaseFinished" },
	methods = {
		PromptProductPurchase = function(self, player, productId)
			if not isInstance(player) or type(productId) ~= "number" then
				error("PromptProductPurchase(player: Player, productId: number)", 2)
			end
			table.insert(recOf(self).world.log.prompts, { kind = "product", id = productId })
		end,
		PromptGamePassPurchase = function(self, player, passId)
			if not isInstance(player) or type(passId) ~= "number" then
				error("PromptGamePassPurchase(player: Player, gamePassId: number)", 2)
			end
			table.insert(recOf(self).world.log.prompts, { kind = "pass", id = passId })
		end,
		UserOwnsGamePassAsync = function()
			return false
		end,
		GetProductInfo = function(_, id)
			return { Name = "Product " .. tostring(id), PriceInRobux = 99 }
		end,
	},
})

define("Debris", {
	methods = {
		AddItem = function(self, item, lifetime: number?)
			local world = recOf(self).world
			world.sched:delay(lifetime or 10, function()
				if records[item] and not records[item].destroyed then
					item:Destroy()
				end
			end)
		end,
	},
})

define("SoundService", {
	methods = {
		PlayLocalSound = function(self, sound)
			table.insert(recOf(self).world.log.sounds, sound.SoundId)
		end,
	},
})

define("StarterGui", {
	methods = {
		SetCoreGuiEnabled = function() end,
		SetCore = function() end,
		GetCoreGuiEnabled = function()
			return true
		end,
	},
})

define("ContentProvider", {
	methods = {
		PreloadAsync = function() end,
	},
})

define("TextService", {
	methods = {
		GetTextSize = function(_, text: string, size: number)
			return Vector2.new(#text * size * 0.5, size)
		end,
	},
})

define("HttpService", {
	methods = {
		JSONEncode = function()
			error("HttpService:JSONEncode is not emulated", 2)
		end,
		GenerateGUID = function(self)
			local world = recOf(self).world
			world.guid += 1
			return string.format("{00000000-0000-0000-0000-%012d}", world.guid)
		end,
	},
})

define("Lighting", { events = { "LightingChanged" } })

-- ─── World (one client) ─────────────────────────────────────────────────────────────

local World = {}
World.__index = World

--[[
	options = {
	  clock = () -> number,        -- server unix time (float); shared with the server mock
	  viewport = Vector2?,         -- default 1280×720
	  bridge = { invokeServer = fn(name, ...), fireServer = fn(name, ...) },
	}
]]
function RobloxMock.newWorld(options)
	local world = setmetatable({}, World)
	world.clockFn = options.clock
	world.elapsed = 0
	world.viewport = options.viewport or Vector2.new(1280, 720)
	world.bridge = options.bridge or {}
	world.errors = {}
	world.warnings = {}
	world.log = { prompts = {}, sounds = {} }
	world.services = {}
	world.renderBindings = {}
	world.guid = 0
	world.raycastResult = nil
	-- Input devices: a touch phone with no pad until a test plugs one in.
	world.input = { lastType = Enum.UserInputType.Touch, gamepads = {}, actions = {}, bindCount = 0 }
	world.sched = Scheduler.new(world)
	world.task = world.sched:taskLibrary()

	local game = newInstance(world, "DataModel")
	RobloxMock.rawSet(game, "Name", "Game")
	world.game = game
	world.workspace = world:_service("Workspace")
	local camera = newInstance(world, "Camera")
	RobloxMock.rawSet(camera, "Name", "Camera")
	RobloxMock.rawSet(camera, "CFrame", CFrame.new(0, 20, 30))
	RobloxMock.rawSet(camera, "Parent", world.workspace)
	RobloxMock.rawSet(world.workspace, "CurrentCamera", camera)
	return world
end

function World:Clock(): number
	return self.clockFn()
end

function World:_error(message: string)
	table.insert(self.errors, message)
end

function World:_warn(message: string)
	table.insert(self.warnings, message)
end

local SERVICE_DEFAULTS = {
	-- A pad moves and presses the selection out of the box (GuiService navigation is on).
	GuiService = { GuiNavigationEnabled = true, AutoSelectGuiEnabled = true },
}

function World:_service(name: string)
	local existing = self.services[name]
	if existing then
		return existing
	end
	local info = classInfo(name)
	if not info or (not info.service and name ~= "Workspace") then
		error("'" .. tostring(name) .. "' is not a valid Service name", 3)
	end
	local service = newInstance(self, name)
	RobloxMock.rawSet(service, "Name", name)
	-- Live values the reflection database has no default for.
	for key, value in SERVICE_DEFAULTS[name] or {} do
		RobloxMock.rawSet(service, key, value)
	end
	records[service].parent = self.game
	table.insert(records[self.game].children, service)
	self.services[name] = service
	return service
end

-- Instance.new for game code in this world.
function World:InstanceLibrary()
	local world = self
	return {
		new = function(className: string, parent)
			local info = classInfo(className)
			if info and not info.creatable then
				error(string.format("Unable to create an Instance of type %q", className), 2)
			end
			local inst = newInstance(world, className)
			if parent ~= nil then
				inst.Parent = parent
			end
			return inst
		end,
		fromExisting = function(inst)
			return inst:Clone()
		end,
	}
end

function World:typeof(value): string
	if isInstance(value) then
		return "Instance"
	elseif type(value) == "table" and signalRegistry[value] then
		return "RBXScriptSignal"
	elseif type(value) == "table" and connectionRegistry[value] then
		return "RBXScriptConnection"
	elseif type(value) == "table" and tweenInfoRegistry[value] then
		return "TweenInfo"
	elseif type(value) == "table" and getmetatable(value) == RobloxMock.RaycastParamsMeta then
		return "RaycastParams"
	end
	return luneTypeof(value)
end

RobloxMock.RaycastParamsMeta = {}

-- Globals injected into every script loaded in this world.
function World:Globals()
	local world = self
	return {
		game = self.game,
		workspace = self.workspace,
		Instance = self:InstanceLibrary(),
		Enum = Enum,
		task = self.task,
		typeof = function(value)
			return world:typeof(value)
		end,
		tick = function()
			return world:Clock()
		end,
		time = function()
			return world.elapsed
		end,
		elapsedTime = function()
			return world.elapsed
		end,
		os = setmetatable({
			time = function(t)
				if t then
					return os.time(t)
				end
				return math.floor(world:Clock())
			end,
			clock = function()
				return world.elapsed
			end,
			date = function(format, t)
				return os.date(format, t or math.floor(world:Clock()))
			end,
		}, { __index = os }),
		wait = function()
			error("wait() is deprecated; use task.wait", 2)
		end,
		spawn = function()
			error("spawn() is deprecated; use task.spawn", 2)
		end,
		delay = function()
			error("delay() is deprecated; use task.delay", 2)
		end,
		Vector2 = Vector2,
		Vector3 = Vector3,
		CFrame = CFrame,
		Color3 = Color3,
		UDim = roblox.UDim,
		UDim2 = UDim2,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Rect = roblox.Rect,
		Font = roblox.Font,
		BrickColor = roblox.BrickColor,
		PhysicalProperties = roblox.PhysicalProperties,
		Ray = roblox.Ray,
		Region3 = roblox.Region3,
		Faces = roblox.Faces,
		Axes = roblox.Axes,
		Vector2int16 = roblox.Vector2int16,
		Vector3int16 = roblox.Vector3int16,
		TweenInfo = { new = newTweenInfo },
		RaycastParams = {
			new = function()
				return setmetatable({
					FilterDescendantsInstances = {},
					FilterType = Enum.RaycastFilterType.Exclude,
					IgnoreWater = false,
					RespectCanCollide = false,
					CollisionGroup = "Default",
				}, RobloxMock.RaycastParamsMeta)
			end,
		},
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			world:_warn(table.concat(parts, " "))
		end,
		print = function() end,
	}
end

-- Moves the client forward one frame: timers, deferred work, then the frame signals.
function World:Frame(dt: number)
	self.elapsed += dt
	self.sched:runDeferred()
	self.sched:runTimers()
	local run = self.services.RunService
	if run then
		local rec = records[run]
		for _, name in { "PreRender", "RenderStepped" } do
			if rec.signals[name] then
				rec.signals[name]:_fire(dt)
			end
		end
		for _, fn in self.renderBindings do
			self.sched:spawn(fn, dt)
		end
		for _, name in { "Stepped", "PreSimulation" } do
			if rec.signals[name] then
				rec.signals[name]:_fire(self.elapsed, dt)
			end
		end
		for _, name in { "Heartbeat", "PostSimulation" } do
			if rec.signals[name] then
				rec.signals[name]:_fire(dt)
			end
		end
	end
	self.sched:runDeferred()
end

-- Runs fn in a game thread (so it may yield) and settles deferred work.
function World:Run(fn, ...)
	local thread = self.sched:spawn(fn, ...)
	self.sched:runDeferred()
	return thread
end

function World:Signal(name: string?)
	return Signal.new(self, name)
end

RobloxMock.Signal = Signal
RobloxMock.newTweenInfo = newTweenInfo

return RobloxMock
