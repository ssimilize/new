--[[
	TestKernel: boots the REAL kernel with MockAdapters and only the systems a test asks for.
	This is how every system is tested in isolation before it is plugged into the Manifest.

		local h = TestKernel.new({ systems = { "Currency", "Progression" } })
		local p = h:Join()                                   -- fake player, profile loaded
		local res = h:Invoke(p, "Shop.BuyEgg", { egg = "meadow", amount = 1 })
		local data = h:Call(p, "Ranch.CollectAll")            -- asserts ok, returns data
		h:Advance(3600)                                       -- moves time, runs timers
		h:Section(p, "Currency").coins
		h:Client(p).profile.Currency.coins                    -- what the client sees
		h:Rejoin(p, 8 * 3600)                                 -- leave, wait offline, rejoin
]]

local Loader = require("./Loader")
local MockAdapters = require("./MockAdapters")

local TestKernel = {}
TestKernel.__index = TestKernel

local nextUserId = 1000

-- A player's state log is folded once this many applied messages pile up (see _syncClient).
-- Short tests never reach it, so a client harness attaching late replays them message by message.
TestKernel.FoldStatesAt = 256

local function fakePlayer(userId: number?, name: string?)
	if not userId then
		nextUserId += 1
		userId = nextUserId
	end
	local display = name or ("Player" .. tostring(userId))
	return { UserId = userId, Name = display, DisplayName = display }
end
TestKernel.fakePlayer = fakePlayer

local function applyPath(tree, path: string, value)
	local parts = {}
	for part in string.gmatch(path, "[^%.]+") do
		table.insert(parts, if string.match(part, "^%d+$") then tonumber(part) else part)
	end
	local node = tree
	for i = 1, #parts - 1 do
		if type(node[parts[i]]) ~= "table" then
			node[parts[i]] = {}
		end
		node = node[parts[i]]
	end
	node[parts[#parts]] = value
end

--[[
	options = {
	  systems = { "Name", ... },       -- folders under src/server/Systems
	  stubs = { Name = api, ... },     -- fake dependencies
	  startTime = number?,
	  network = MockAdapters.network()?, -- share cross-server stores between kernels
	  placeMode = "hub"?,              -- run as the Trading Hub place (3.0)
	  verbose = boolean?,
	}
]]
function TestKernel.new(options)
	Loader.reset("src/server/Systems")
	local Kernel = Loader.get("Server.Kernel.Kernel")
	local adapters = MockAdapters.new({ startTime = options.startTime, network = options.network, placeMode = options.placeMode })
	local kernel = Kernel.new({ adapters = adapters, verbose = options.verbose })
	-- kernel.Foundry as Main.server builds it, on the mock clock (ctx.Foundry in every system)
	kernel.Foundry = Loader.get("Server.Kernel.ServerFoundry").new({
		folder = Loader.game:GetService("ReplicatedStorage").Shared:FindFirstChild("Foundry"),
		requireModule = Loader.require,
		Bus = kernel.Bus,
		serverTime = function()
			return adapters.Clock.Unix() -- what the client harness serves as GetServerTimeNow
		end,
		verbose = options.verbose,
	})
	for name, api in options.stubs or {} do
		kernel:Stub(name, api)
	end
	local systemsFolder = Loader.game:GetService("ServerScriptService").Server.Systems
	for _, name in options.systems or {} do
		kernel:AddSystem(Loader.require(systemsFolder[name]))
	end
	kernel:Start()
	local self = setmetatable({ kernel = kernel, adapters = adapters, _clients = {} }, TestKernel)
	for _, name in options.systems or {} do
		assert(
			kernel:SystemState(name) == "ready",
			string.format("system %s failed to start: %s", name, tostring(kernel._systems[name].error))
		)
	end
	return self
end

function TestKernel:System(name: string)
	return self.kernel:_systemApi(name)
end

function TestKernel:Join(userId: number?, name: string?)
	local player = fakePlayer(userId, name)
	self._clients[player] = { profile = {}, session = {}, global = {} }
	self.adapters._onAdded(player)
	self:_syncClient(player)
	return player
end

function TestKernel:Leave(player)
	self.adapters._onRemoving(player)
end

-- Leaves, waits `offlineSeconds`, and joins again as a new player object with the same UserId.
function TestKernel:Rejoin(player, offlineSeconds: number?)
	self:Leave(player)
	if offlineSeconds and offlineSeconds > 0 then
		self.adapters.advance(offlineSeconds)
	end
	return self:Join(player.UserId, player.Name)
end

function TestKernel:Invoke(player, action: string, payload: any?)
	local response = self.kernel.Net:Invoke(player, action, payload)
	local client = self._clients[player]
	if client and response.patches then
		for _, patch in response.patches do
			applyPath(client, patch[1], MockAdapters.deepCopy(patch[2]))
		end
	end
	return response
end

-- Invokes and asserts success; returns `data`.
function TestKernel:Call(player, action: string, payload: any?)
	local response = self:Invoke(player, action, payload)
	if not response.ok then
		error(string.format("%s failed: %s", action, tostring(response.err)), 2)
	end
	return response.data
end

-- Invokes and asserts failure; returns the error string.
function TestKernel:Reject(player, action: string, payload: any?): string
	local response = self:Invoke(player, action, payload)
	if response.ok then
		error(string.format("%s was expected to fail but succeeded", action), 2)
	end
	return response.err
end

-- Moves time forward and runs every due timer (in ≤1 s steps so periodic jobs tick).
function TestKernel:Advance(seconds: number)
	local states = self.adapters.log.states
	local remaining = seconds
	while remaining > 0 do
		local step = math.min(1, remaining)
		self.adapters.advance(step)
		if self.adapters._step then
			self.adapters._step()
		end
		remaining -= step
		-- Nothing else touches the client views mid-Advance, so syncing a long log early
		-- applies the same messages in the same order, and lets it be folded.
		for player in self._clients do
			local messages = states[player]
			if messages and #messages >= TestKernel.FoldStatesAt then
				self:_syncClient(player)
			end
		end
	end
	for player in self._clients do
		self:_syncClient(player)
	end
end

-- Runs one scheduler step without moving time (flushes state).
function TestKernel:Step()
	if self.adapters._step then
		self.adapters._step()
	end
end

function TestKernel:Section(player, systemName: string)
	local data = self.kernel.Data:Get(player)
	return data and data[systemName]
end

function TestKernel:Session(player, systemName: string)
	local record = self.kernel._players[player]
	return record and record.session[systemName]
end

-- Rebuilds the client's view from every state message the player received. Once the log is
-- long, the applied messages are folded into one snapshot that shares the view's tables (as
-- the logged snapshot already does), so a client harness attaching later still sees them.
function TestKernel:_syncClient(player)
	local client = self._clients[player]
	if not client then
		return
	end
	local log = self.adapters.log
	local messages = log.states[player] or {}
	local folded = log.folded[player]
	local base = if folded then folded.count else 0 -- messages already folded away
	client._applied = client._applied or 0
	for i = client._applied + 1, base + #messages do
		local message = messages[i - base]
		if message.kind == "snapshot" then
			client.profile = message.tree.profile
			client.session = message.tree.session
			client.global = message.tree.global
			client._snapshot = true
		else
			for _, patch in message.patches do
				applyPath(client, patch[1], MockAdapters.deepCopy(patch[2]))
			end
		end
	end
	client._applied = base + #messages
	if #messages >= TestKernel.FoldStatesAt and client._snapshot then
		local tree = { profile = client.profile, session = client.session, global = client.global }
		self.adapters.foldStates(player, #messages, tree)
	end
end

function TestKernel:Client(player)
	self.kernel.State:FlushAll()
	self:_syncClient(player)
	return self._clients[player]
end

function TestKernel:Events(player, name: string?)
	local list = {}
	for _, e in self.adapters.log.events[player] or {} do
		if name == nil or e.name == name then
			table.insert(list, e)
		end
	end
	return list
end

function TestKernel:LastEvent(player, name: string)
	local list = self:Events(player, name)
	return list[#list]
end

return TestKernel
