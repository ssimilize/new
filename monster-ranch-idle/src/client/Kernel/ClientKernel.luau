--[[
	ClientKernel: lifecycle for client controllers and screens.

	A controller is a ModuleScript returning:
	  { Name = "Hud", Dependencies = { "Sound" }?, Init = function(ctx) end, Start = function() end }

	ctx (per controller):
	  ctx.Name, ctx.Config, ctx.Api
	  ctx.Net:Request(action, payload) -> ok, dataOrErr     ctx.Net:RequestOnce(...)
	  ctx.Net:On(event, fn)
	  ctx.Store:Get(path) / ctx.Store:Observe(path, fn) / ctx.Store:WhenReady(fn)
	  ctx.Router:Open(screenName, params) / Close(name?) / IsOpen(name) / Root(name)
	  ctx.UI.Hud / ctx.UI.Screens / ctx.UI.Overlay / ctx.UI.Top   (scaled layers)
	  ctx.Bus:Publish(topic, ...) / ctx.Bus:Subscribe(topic, fn)  (client-only topics)
	  ctx:GetController(name)
	  ctx:Now()                    server-synchronised unix time
	  ctx:Toast(text, kind)        info | success | error | reward
	  ctx:Sound(key, opts?)        plays Config.Sounds[key] through client/Audio (no-op while its id is
	                               empty); opts = { at?, pitch?, volume? } (see Audio.Play)
	  ctx.Player                   LocalPlayer
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Signal = require(Shared.Kernel.Signal)

local Store = require(script.Parent.Store)
local NetClient = require(script.Parent.NetClient)
local Router = require(script.Parent.Router)
local Layers = require(script.Parent.Parent.UI.Layers)
local Toasts = require(script.Parent.Parent.UI.Components.Toasts)
local Audio = require(script.Parent.Parent.Audio)

local ClientKernel = {}
ClientKernel.__index = ClientKernel

function ClientKernel.new()
	local self = setmetatable({}, ClientKernel)
	self.Player = Players.LocalPlayer
	self.Config = require(Shared.Config)
	self.Api = require(Shared.Kernel.Api)
	self.Store = Store.new()
	self.Net = NetClient.new(self.Store)
	self.UI = Layers.create(self.Player)
	self.Bus = self:_makeBus()
	self._controllers = {}
	self._order = {}
	self.Router = Router.new(self)
	Toasts.init(self.UI.Overlay)
	Audio.Attach(self.Store, self.Config.Sounds)
	self.Net:On("Kernel.Notify", function(payload)
		Toasts.show(payload.text, payload.kind)
		if payload.kind == "error" then
			Audio.Play("Error")
		end
	end)
	return self
end

function ClientKernel:_makeBus()
	local signals = {}
	local function get(topic)
		signals[topic] = signals[topic] or Signal.new()
		return signals[topic]
	end
	return {
		Publish = function(_, topic: string, ...)
			get(topic):Fire(...)
		end,
		Subscribe = function(_, topic: string, fn)
			return get(topic):Connect(fn)
		end,
	}
end

function ClientKernel:AddController(module)
	assert(type(module) == "table" and type(module.Name) == "string", "controller must have a Name")
	assert(self._controllers[module.Name] == nil, "controller added twice: " .. module.Name)
	self._controllers[module.Name] = { module = module, state = "added" }
end

function ClientKernel:GetController(name: string)
	local entry = self._controllers[name]
	return entry and entry.state == "ready" and entry.module or nil
end

function ClientKernel:Now(): number
	return workspace:GetServerTimeNow()
end

function ClientKernel:Toast(text: string, kind: string?)
	Toasts.show(text, kind)
	if kind == "error" then
		Audio.Play("Error")
	end
end

-- Pooled, grouped and settings-aware (client/Audio); returns the Sound, or nil when nothing played.
function ClientKernel:Sound(key: string, opts: any?): Sound?
	return Audio.Play(key, opts)
end

function ClientKernel:_context(entry)
	local kernel = self
	local ctx = setmetatable({
		Name = entry.module.Name,
		Config = self.Config,
		Api = self.Api,
		Net = self.Net,
		Store = self.Store,
		Router = self.Router,
		UI = self.UI,
		Bus = self.Bus,
		Player = self.Player,
	}, {
		__index = function(_, key)
			local method = ClientKernel[key]
			if type(method) == "function" then
				return function(_, ...)
					return method(kernel, ...)
				end
			end
			return nil
		end,
	})
	return ctx
end

-- Shared context used by screens (they are built lazily by the Router).
function ClientKernel:ScreenContext(name: string)
	return self:_context({ module = { Name = name } })
end

local function order(controllers)
	local names = {}
	for name in controllers do
		table.insert(names, name)
	end
	table.sort(names)
	local result, visiting, done = {}, {}, {}
	local function visit(name)
		if done[name] then
			return
		end
		assert(not visiting[name], "controller dependency cycle at " .. name)
		visiting[name] = true
		for _, dep in controllers[name].module.Dependencies or {} do
			if controllers[dep] then
				visit(dep)
			end
		end
		visiting[name] = nil
		done[name] = true
		table.insert(result, name)
	end
	for _, name in names do
		visit(name)
	end
	return result
end

function ClientKernel:Start()
	self._order = order(self._controllers)
	for _, name in self._order do
		local entry = self._controllers[name]
		entry.ctx = self:_context(entry)
		if entry.module.Init then
			local ok, err = xpcall(entry.module.Init, debug.traceback, entry.ctx)
			entry.state = if ok then "ready" else "failed"
			if not ok then
				warn(string.format("[ClientKernel] %s.Init failed: %s", name, tostring(err)))
			end
		else
			entry.state = "ready"
		end
	end
	for _, name in self._order do
		local entry = self._controllers[name]
		if entry.state == "ready" and entry.module.Start then
			task.spawn(function()
				local ok, err = xpcall(entry.module.Start, debug.traceback)
				if not ok then
					warn(string.format("[ClientKernel] %s.Start failed: %s", name, tostring(err)))
				end
			end)
		end
	end
end

return ClientKernel
