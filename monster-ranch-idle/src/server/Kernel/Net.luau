--[[
	Net: validated, rate-limited request handling.

	Flow for every client request:
	  ready? → declared in Api? → handler plugged in? → schema valid? → rate ok?
	  → handler(player, payload) → { ok, data | err, patches }

	`patches` carries the requesting player's pending state changes so the client applies
	them before the request resolves (a RemoteFunction response and a RemoteEvent are not
	ordered relative to each other).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Api = require(Shared.Kernel.Api)
local Failure = require(script.Parent.Failure)
local RateLimiter = require(script.Parent.RateLimiter)

local Net = {}
Net.__index = Net

Net.GenericError = "Something went wrong. Please try again."

function Net.new(kernel, transport)
	local self = setmetatable({
		_kernel = kernel,
		_transport = transport,
		_handlers = {},
		_limiter = RateLimiter.new(kernel.Clock),
	}, Net)
	transport:OnRequest(function(player, action, payload)
		return self:Invoke(player, action, payload)
	end)
	return self
end

function Net:Handle(owner: string, action: string, handler: (any, any) -> any)
	local def = Api.Actions[action]
	assert(def, string.format("[Net] %s tried to handle undeclared action '%s' (add it to Api.Actions)", owner, action))
	local prefix = string.match(action, "^([^%.]+)%.")
	assert(prefix == owner, string.format("[Net] action '%s' belongs to '%s', not '%s'", action, tostring(prefix), owner))
	assert(self._handlers[action] == nil, "[Net] action handled twice: " .. action)
	self._handlers[action] = handler
end

function Net:IsHandled(action: string): boolean
	return self._handlers[action] ~= nil
end

local function respond(self, player, response)
	response.patches = self._kernel.State:TakePatches(player, false)
	return response
end

function Net:Invoke(player: any, action: any, payload: any)
	if type(action) ~= "string" then
		return { ok = false, err = "BadRequest" }
	end
	local kernel = self._kernel
	if not kernel:IsReady(player) then
		return { ok = false, err = "NotReady" }
	end
	local def = Api.Actions[action]
	if not def then
		return { ok = false, err = "UnknownAction" }
	end
	local handler = self._handlers[action]
	if not handler then
		return { ok = false, err = "NotAvailable" }
	end
	local valid, why = def.schema(payload)
	if not valid then
		kernel.Log("Net", "rejected %s from %s: %s", action, tostring(player.UserId), tostring(why))
		return { ok = false, err = "BadRequest" }
	end
	if not self._limiter:Allow(player, action, def.rate or 5) then
		return { ok = false, err = "TooFast" }
	end
	local ok, result = xpcall(handler, function(err)
		if Failure.is(err) then
			return err
		end
		return debug.traceback(tostring(err), 2)
	end, player, payload)
	if ok then
		return respond(self, player, { ok = true, data = result })
	end
	if Failure.is(result) then
		return respond(self, player, { ok = false, err = result.message })
	end
	warn(string.format("[Net] %s errored: %s", action, tostring(result)))
	return respond(self, player, { ok = false, err = Net.GenericError })
end

function Net:Fire(player: any, event: string, payload: any)
	if Api.Events[event] == nil then
		warn("[Net] firing undeclared event " .. event)
	end
	self._transport:Fire(player, event, payload)
end

function Net:FireAll(event: string, payload: any)
	if Api.Events[event] == nil then
		warn("[Net] firing undeclared event " .. event)
	end
	for _, player in self._kernel:ReadyPlayers() do
		self._transport:Fire(player, event, payload)
	end
end

function Net:Forget(player: any)
	self._limiter:Forget(player)
end

return Net
