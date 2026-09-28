--[[
	ServerFoundry: the server realm's kernel.Foundry (see Shared.Kernel.FoundryAdapter for the
	shape). Main.server builds it before kernel:Start(), so every ctx.Foundry is the same table:

	  kernel.Foundry = ServerFoundry.new({
	    folder = ReplicatedStorage.Shared:FindFirstChild("Foundry"), requireModule = require,
	    Bus = kernel.Bus, serverTime = function() return workspace:GetServerTimeNow() end,
	    verbose = kernel.Verbose,
	  })

	now()      serverTime(): the world clock the clients read (GetServerTimeNow), not
	           kernel.Clock (os.time, whole seconds, for saves, resets and offline progress)
	quality()  deps.quality() when given, else 3: the server draws nothing, so budgets that
	           vary by quality take their high value here
	on / emit  the server Bus carries (player, detail). emit(topic, payload) publishes
	           (payload.player, payload); on(topic, fn) hands fn the detail, and when a player
	           was published, a copy of it with `player` set. on returns a disconnect function.
]]

local FoundryAdapter = require(game:GetService("ReplicatedStorage").Shared.Kernel.FoundryAdapter)

local ServerFoundry = {}

ServerFoundry.QUALITY = 3

function ServerFoundry.new(deps)
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
		return ServerFoundry.QUALITY
	end

	local function on(topic: string, fn: (any) -> ()): () -> ()
		local conn = bus:Subscribe(topic, function(player, detail)
			local payload = detail
			if player ~= nil then
				payload = table.clone(if type(detail) == "table" then detail else {})
				payload.player = player
			end
			fn(payload)
		end)
		return function()
			conn:Disconnect()
		end
	end

	local function emit(topic: string, payload: any?)
		local player = if type(payload) == "table" then payload.player else nil
		bus:Publish(topic, player, payload)
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

return ServerFoundry
