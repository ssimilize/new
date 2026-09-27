--[[
	QABridge: stages game states for checks in Studio. Studio only (Main.server attaches it when
	RunService:IsStudio()); a live server never has it.

	Studio's execute_luau runs in its own module cache, so it cannot reach this kernel or change
	the Config the game reads. Attach puts a BindableFunction at ServerStorage.QABridge: invoke it
	from execute_luau (Server) and the command runs inside the game.

		ServerStorage.QABridge:Invoke(command, args) -> { ok = boolean, result = any, err = string? }

	Read commands:
	  players                          { { userId, name, ready } }
	  global  { system }               that system's global state table
	  section { userId, system }       a player's save section (a copy)
	  livechecks                       runs Kernel/LiveChecks against the REAL adapters (never
	                                    QA_MemoryProfiles); refused unless Adapters.IsStudio or
	                                    Adapters.IsOwnerServer, see docs/GO_LIVE.md §6
	Write commands (refused unless the session runs on QA_MemoryProfiles, see Kernel/Adapters, so
	they can never change a real save):
	  set     { userId, path, value }  profile field, path = { system, key, ... }; marks it dirty
	  call    { userId, action, payload? }   a Net action as that player (the real handler path)
	  system  { system, method, args? }      a system's public method, api:method(table.unpack(args))
	  titan   { seconds, rotation? }   schedules a titan invasion `seconds` from now (Config.Titan)
	  config  { path, value }          sets a shared Config value in this server, path = { "Boss", "Period" }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QABridge = {}

local WRITES = { set = true, call = true, system = true, titan = true, config = true }

local function playerFor(kernel, userId: number)
	local player = kernel:PlayerByUserId(tonumber(userId) or 0)
	assert(player, "no player " .. tostring(userId) .. " on this server")
	return player
end

local function copy(value, depth: number?)
	depth = depth or 0
	if type(value) ~= "table" or depth > 12 then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = copy(v, depth + 1)
	end
	return out
end

local commands = {}

function commands.players(kernel)
	local out = {}
	for player in kernel._players do
		table.insert(out, { userId = player.UserId, name = player.Name, ready = kernel:IsReady(player) })
	end
	return out
end

function commands.global(kernel, args)
	return copy(kernel.State:GlobalRoot(args.system))
end

function commands.section(kernel, args)
	local data = kernel.Data:Get(playerFor(kernel, args.userId))
	return copy(data and data[args.system])
end

function commands.set(kernel, args)
	local player = playerFor(kernel, args.userId)
	local data = kernel.Data:Get(player)
	assert(data, "profile not loaded")
	local path = args.path
	assert(type(path) == "table" and #path >= 2, "path = { system, key, ... }")
	local node = data
	for i = 1, #path - 1 do
		node = node[path[i]]
		assert(type(node) == "table", "no table at " .. table.concat(path, ".", 1, i))
	end
	node[path[#path]] = args.value
	kernel.State:Dirty(player, { "profile", table.unpack(path, 1, #path - 1) })
	return args.value
end

function commands.call(kernel, args)
	return kernel.Net:Invoke(playerFor(kernel, args.userId), args.action, args.payload)
end

function commands.system(kernel, args)
	local api = kernel:_systemApi(args.system)
	assert(api, "no system " .. tostring(args.system))
	local fn = api[args.method]
	assert(type(fn) == "function", tostring(args.system) .. " has no method " .. tostring(args.method))
	return copy(table.pack(fn(api, table.unpack(args.args or {}))))
end

local function sharedConfig()
	return require(ReplicatedStorage.Shared.Config)
end

function commands.titan(kernel, args)
	local startsAt = kernel.Clock.Now() + math.max(0, tonumber(args.seconds) or 0)
	table.insert(sharedConfig().Titan.Schedule, { startsAt = startsAt, rotation = args.rotation or 1 })
	return startsAt
end

-- Runs against the REAL adapters (kernel.Adapters), never QA_MemoryProfiles: it must prove
-- the real Roblox services, not the in-memory stubs. Guarded separately from WRITES below.
function commands.livechecks(kernel)
	local LiveChecks = require(script.Parent.LiveChecks)
	return LiveChecks.Run(kernel.Adapters)
end

function commands.config(_kernel, args)
	local path = args.path
	assert(type(path) == "table" and #path >= 2, 'path = { "Boss", "Period" }')
	local node = sharedConfig()
	for i = 1, #path - 1 do
		node = node[path[i]]
		assert(type(node) == "table", "no table at " .. table.concat(path, ".", 1, i))
	end
	node[path[#path]] = args.value
	return args.value
end

-- Runs one command; never throws.
function QABridge.Run(kernel, command: string, args: any?): { ok: boolean, result: any, err: string? }
	local fn = commands[command]
	if not fn then
		return { ok = false, err = "unknown command " .. tostring(command) }
	end
	if WRITES[command] and kernel.Adapters.QA ~= true then
		return { ok = false, err = command .. " needs QA_MemoryProfiles (set the Workspace attribute in Edit, then Play)" }
	end
	if command == "livechecks" and not (kernel.Adapters.IsStudio or kernel.Adapters.IsOwnerServer) then
		return { ok = false, err = "livechecks needs Studio or the experience owner's private server (docs/GO_LIVE.md §6)" }
	end
	local ok, result = pcall(fn, kernel, args or {})
	if ok then
		return { ok = true, result = result }
	end
	return { ok = false, err = tostring(result) }
end

function QABridge.Attach(kernel)
	local holder = game:GetService("ServerStorage")
	local old = holder:FindFirstChild("QABridge")
	if old then
		old:Destroy()
	end
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "QABridge"
	bridge.OnInvoke = function(command, args)
		return QABridge.Run(kernel, command, args)
	end
	bridge.Parent = holder
	return bridge
end

return QABridge
