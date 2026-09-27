--[[
	ClientFoundry: the client realm's kernel.Foundry (see Shared.Kernel.FoundryAdapter for the
	shape). ClientKernel.new builds it, and every controller and screen ctx carries it:

	  self.Foundry = ClientFoundry.new({
	    folder = ReplicatedStorage.Shared:FindFirstChild("Foundry"), requireModule = require,
	    Bus = self.Bus, serverTime = function() return workspace:GetServerTimeNow() end,
	    quality = Quality.Level,
	  })

	now()      serverTime(): the same clock as ctx:Now() (GetServerTimeNow)
	quality()  Visuals/Quality.Level() (1 low, 2 medium, 3 high); 2 when it cannot answer
	on / emit  the client Bus carries whatever was published: emit(topic, payload) publishes
	           the one payload, on(topic, fn) hands fn the first value. on returns a disconnect
	           function.
]]

local FoundryAdapter = require(game:GetService("ReplicatedStorage").Shared.Kernel.FoundryAdapter)

local ClientFoundry = {}

ClientFoundry.QUALITY = 2

function ClientFoundry.new(deps)
	local bus = deps.Bus

	local function now(): number
		local st = deps.serverTime
		if type(st) == "function" then
			return st()
		end
		return 0
	end

	local function quality(): number
		local q = deps.quality
		if type(q) == "function" then
			local ok, v = pcall(q)
			if ok and type(v) == "number" then
				return v
			end
		end
		return ClientFoundry.QUALITY
	end

	local function on(topic: string, fn: (any) -> ()): () -> ()
		local conn = bus:Subscribe(topic, function(payload)
			fn(payload)
		end)
		return function()
			conn:Disconnect()
		end
	end

	local function emit(topic: string, payload: any?)
		bus:Publish(topic, payload)
	end

	return FoundryAdapter.build({
		folder = deps.folder,
		requireModule = deps.requireModule,
		on = on,
		emit = emit,
		now = now,
		quality = quality,
		warn = deps.warn,
		print = deps.print,
		verbose = deps.verbose,
	})
end

return ClientFoundry
