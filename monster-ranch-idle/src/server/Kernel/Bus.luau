--[[
	Bus: server-side publish/subscribe between systems. Topics are declared in Api.Topics;
	publishing an undeclared topic warns once so typos are caught early.
	Handlers run synchronously and are isolated: one failing handler never blocks others.
]]

local Signal = require(game:GetService("ReplicatedStorage").Shared.Kernel.Signal)

local Bus = {}
Bus.__index = Bus

function Bus.new(topics: { [string]: any })
	return setmetatable({ _topics = topics, _signals = {}, _warned = {} }, Bus)
end

function Bus:_signal(topic: string)
	local signal = self._signals[topic]
	if not signal then
		if self._topics[topic] == nil and not self._warned[topic] then
			self._warned[topic] = true
			warn("[Bus] topic not declared in Api.Topics: " .. topic)
		end
		signal = Signal.new()
		self._signals[topic] = signal
	end
	return signal
end

function Bus:Publish(topic: string, player: any, detail: { [string]: any }?)
	self:_signal(topic):Fire(player, detail or {})
end

function Bus:Subscribe(topic: string, fn: (any, { [string]: any }) -> ())
	return self:_signal(topic):Connect(fn)
end

return Bus
