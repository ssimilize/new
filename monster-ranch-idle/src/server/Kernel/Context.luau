--[[
	Context: the only object a system receives from the kernel (passed to Init).

	It is scoped to one system, which is how the kernel keeps parallel-built systems apart:
	  • ctx:Section(player) returns only this system's save section.
	  • ctx:Dirty / DirtySession / DirtyGlobal can only write under this system's name.
	  • ctx.Net:Handle only accepts actions prefixed with this system's name.
	  • ctx:GetSystem only returns systems listed in Dependencies / OptionalDependencies.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Failure = require(script.Parent.Failure)

local Context = {}
Context.__index = Context

function Context.new(kernel, entry)
	local module = entry.module
	local self = setmetatable({
		Name = module.Name,
		Config = require(Shared.Config),
		Api = require(Shared.Kernel.Api),
		Clock = kernel.Clock,
		Rng = kernel.Rng,
		Services = kernel.Adapters,
		Analytics = kernel.Analytics,
		_kernel = kernel,
		_entry = entry,
		_allowed = {},
	}, Context)
	for _, dep in module.Dependencies or {} do
		self._allowed[dep] = "required"
	end
	for _, dep in module.OptionalDependencies or {} do
		self._allowed[dep] = "optional"
	end

	local ctx = self
	self.Net = {
		Handle = function(_, action: string, handler)
			kernel.Net:Handle(ctx.Name, action, handler)
		end,
		Fire = function(_, player, event: string, payload)
			ctx:_checkEvent(event)
			kernel.Net:Fire(player, event, payload)
		end,
		FireAll = function(_, event: string, payload)
			ctx:_checkEvent(event)
			kernel.Net:FireAll(event, payload)
		end,
	}
	self.Bus = {
		Publish = function(_, topic: string, player, detail)
			kernel.Bus:Publish(topic, player, detail)
		end,
		Subscribe = function(_, topic: string, fn)
			return kernel.Bus:Subscribe(topic, fn)
		end,
	}
	return self
end

function Context:_checkEvent(event: string)
	local prefix = string.match(event, "^([^%.]+)%.")
	if prefix ~= self.Name and prefix ~= "Kernel" then
		error(string.format("[%s] cannot fire event '%s' owned by another system", self.Name, event), 3)
	end
end

function Context:Log(fmt: string, ...: any)
	self._kernel.Log(self.Name, fmt, ...)
end

-- Systems -----------------------------------------------------------------------------

function Context:GetSystem(name: string)
	local kind = self._allowed[name]
	if not kind then
		error(string.format("[%s] GetSystem('%s') is not declared in Dependencies or OptionalDependencies", self.Name, name), 2)
	end
	local api = self._kernel:_systemApi(name)
	if api == nil and kind == "required" then
		error(string.format("[%s] required dependency '%s' is not available", self.Name, name), 2)
	end
	return api
end

function Context:HasSystem(name: string): boolean
	return self._kernel:_systemApi(name) ~= nil
end

-- Players -----------------------------------------------------------------------------

function Context:Players(): { any }
	return self._kernel:ReadyPlayers()
end

function Context:IsReady(player: any): boolean
	return self._kernel:IsReady(player)
end

function Context:PlayerByUserId(userId: number): any?
	return self._kernel:PlayerByUserId(userId)
end

-- Data --------------------------------------------------------------------------------

-- This system's save section for a player (nil if the profile is not loaded).
function Context:Section(player: any)
	assert(self._entry.module.Profile, string.format("[%s] has no Profile spec; it cannot own save data", self.Name))
	local data = self._kernel.Data:Get(player)
	return data and data[self.Name]
end

-- Meta info: { created, lastSeen, joins, playSeconds }. Read-only for systems.
function Context:Meta(player: any)
	local data = self._kernel.Data:Get(player)
	return data and data._meta
end

function Context:Session(player: any)
	local record = self._kernel._players[player]
	if not record then
		return nil
	end
	local section = record.session[self.Name]
	if not section then
		section = {}
		record.session[self.Name] = section
	end
	return section
end

function Context:Global()
	return self._kernel.State:GlobalRoot(self.Name)
end

function Context:Dirty(player: any, ...: any)
	self._kernel.State:Dirty(player, { "profile", self.Name, ... })
end

function Context:DirtySession(player: any, ...: any)
	self._kernel.State:Dirty(player, { "session", self.Name, ... })
end

function Context:DirtyGlobal(...: any)
	self._kernel.State:DirtyGlobal({ self.Name, ... })
end

-- Saves the player's profile soon (use after purchases and trades, never every frame).
-- Saves the player's profile now and waits for the result. Use it before a cross-server
-- write that must never get ahead of the profile (market escrow, purchases): if the server
-- dies after the external write, the saved profile already records what was intended.
-- Returns false when the save failed or the player is gone.
function Context:SaveNow(player: any): boolean
	local kernel = self._kernel
	for _ = 1, 100 do
		if not kernel.Data._saving[player] then
			break
		end
		kernel.Adapters.Wait(0.1)
	end
	if not kernel:IsReady(player) then
		return false
	end
	kernel:_beforeSave(player)
	return kernel.Data:Save(player, false) == true
end

function Context:RequestSave(player: any)
	local kernel = self._kernel
	kernel.Adapters.Spawn(function()
		if kernel:IsReady(player) then
			kernel:_beforeSave(player)
			kernel.Data:Save(player, false)
		end
	end)
end

-- Errors & messages -------------------------------------------------------------------

function Context:Fail(message: string): never
	error(Failure.new(message), 2)
end

function Context:Notify(player: any, text: string, kind: string?)
	self._kernel.Net:Fire(player, "Kernel.Notify", { text = text, kind = kind or "info" })
end

-- Time --------------------------------------------------------------------------------

function Context:Now(): number
	return self.Clock.Now()
end

function Context:Every(interval: number, fn: (number) -> ())
	return self._kernel.Scheduler:Every(interval, fn, self.Name)
end

function Context:After(delay: number, fn: () -> ())
	return self._kernel.Scheduler:After(delay, fn, self.Name)
end

-- UTC day number, used for daily resets.
function Context:Day(): number
	return math.floor(self.Clock.Now() / 86400)
end

return Context
