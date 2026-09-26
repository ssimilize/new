--[[
	QABridge (client): stages client states for checks in Studio. Studio only (Main.client
	attaches it when RunService:IsStudio()); see the server's Kernel/QABridge.

	execute_luau (Client) has its own module cache, so it cannot reach the running controllers.
	Attach puts a BindableFunction at LocalPlayer.PlayerScripts.QABridge:

		PlayerScripts.QABridge:Invoke(command, args) -> { ok = boolean, result = any, err = string? }

	  store      { path }                      ctx.Store:Get(path), e.g. "global.Titan"
	  controller { name, method, args?, dot? } a controller's public function; dot = true calls
	                                           controller.method(...), else controller:method(...)
	  open       { screen, params? }           Router:Open
	  close      {}                            Router:Close
	  request    { action, payload? }          a Net request as this player, as the UI would send it
	  config     { path, value }               sets a shared Config value on this client only
	Every command but store needs the Workspace attribute QA_MemoryProfiles (the server then runs
	on in-memory stores, so nothing a check does reaches the real save).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QABridge = {}

local function pack(...)
	return table.pack(...)
end

local commands = {}

function commands.store(kernel, args)
	return kernel.Store:Get(args.path)
end

function commands.controller(kernel, args)
	local ctl = kernel:GetController(args.name)
	assert(ctl, "no controller " .. tostring(args.name))
	local fn = ctl[args.method]
	assert(type(fn) == "function", tostring(args.name) .. " has no function " .. tostring(args.method))
	local list = args.args or {}
	if args.dot then
		return pack(fn(table.unpack(list)))
	end
	return pack(fn(ctl, table.unpack(list)))
end

function commands.open(kernel, args)
	kernel.Router:Open(args.screen, args.params)
	return args.screen
end

function commands.close(kernel)
	kernel.Router:Close()
	return true
end

function commands.request(kernel, args)
	return pack(kernel.Net:Request(args.action, args.payload))
end

function commands.config(_kernel, args)
	local path = args.path
	assert(type(path) == "table" and #path >= 2, 'path = { "DeepReef", "Unlock" }')
	local node = require(ReplicatedStorage.Shared.Config)
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
	if command ~= "store" and workspace:GetAttribute("QA_MemoryProfiles") ~= true then
		return { ok = false, err = command .. " needs QA_MemoryProfiles (set the Workspace attribute in Edit, then Play)" }
	end
	local ok, result = pcall(fn, kernel, args or {})
	if ok then
		return { ok = true, result = result }
	end
	return { ok = false, err = tostring(result) }
end

function QABridge.Attach(kernel)
	local holder = Players.LocalPlayer:WaitForChild("PlayerScripts")
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
