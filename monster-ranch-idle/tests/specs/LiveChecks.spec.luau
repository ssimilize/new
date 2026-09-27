--[[
	R2-LAUNCH: Kernel/LiveChecks exercises the five VERIFY paths in Kernel/Adapters (Market
	browse/close, Arena rating paging, AdService availability, the hub Trade Board and Titan
	invasion pool) against MockAdapters, and the QABridge `livechecks` command's guard.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local MockAdapters = t.MockAdapters
	local LiveChecks = t.Server("Kernel.LiveChecks")
	local QABridge = t.Server("Kernel.QABridge")

	describe("LiveChecks.Run", function()
		it("passes every check and leaves nothing behind in the mock stores", function()
			local network = MockAdapters.network()
			local adapters = MockAdapters.new({ network = network })

			local report = LiveChecks.Run(adapters)

			for _, name in { "Market", "Arena", "Ads", "HubBoard", "Titan" } do
				expect(string.find(report, "[PASS] " .. name, 1, true) ~= nil).toBe(true)
			end
			expect(string.find(report, "[FAIL]", 1, true) == nil).toBe(true)

			-- HubBoard and Titan are fully self-cleaning: no LiveCheck_ key survives.
			for id in network.hubBoard do
				expect(string.find(id, "LiveCheck_", 1, true) == nil).toBe(true)
			end
			for key in network.titan do
				expect(string.find(key, "LiveCheck_", 1, true) == nil).toBe(true)
			end

			-- The Market probe was never in the public index, and is closed after; Arena
			-- is read-only, so no probe rating joins matchmaking.
			local browseOk, list = adapters.Market.Browse({ scope = "all", kind = "monster" })
			expect(browseOk).toBe(true)
			for _, l in list do
				expect(string.find(l.id, "LiveCheck_", 1, true) == nil).toBe(true)
			end
			expect(string.find(report, "found ours = true", 1, true) ~= nil).toBe(true)
		end)

		it("reports a [FAIL] line instead of throwing when a store is down", function()
			local network = MockAdapters.network()
			network.marketDown = true
			local adapters = MockAdapters.new({ network = network })

			local report = LiveChecks.Run(adapters)

			expect(string.find(report, "[FAIL] Market", 1, true) ~= nil).toBe(true)
			expect(string.find(report, "[PASS] Arena", 1, true) ~= nil).toBe(true)
		end)

		it("reports Titan unavailable rather than erroring when adapters.Titan is nil", function()
			local adapters = MockAdapters.new()
			adapters.Titan = nil
			local report = LiveChecks.Run(adapters)
			expect(string.find(report, "[FAIL] Titan", 1, true) ~= nil).toBe(true)
		end)
	end)

	describe("QABridge livechecks", function()
		local function kernelWith(isStudio: boolean, isOwnerServer: boolean?)
			local adapters = MockAdapters.new()
			adapters.IsStudio = isStudio
			adapters.IsOwnerServer = isOwnerServer or false
			return { Adapters = adapters }
		end

		it("runs in Studio", function()
			local result = QABridge.Run(kernelWith(true), "livechecks")
			expect(result.ok).toBe(true)
			expect(string.find(result.result, "[PASS] Market", 1, true) ~= nil).toBe(true)
		end)

		it("runs on the owner's private server", function()
			local result = QABridge.Run(kernelWith(false, true), "livechecks")
			expect(result.ok).toBe(true)
		end)

		it("is refused anywhere else", function()
			local result = QABridge.Run(kernelWith(false, false), "livechecks")
			expect(result.ok).toBe(false)
		end)
	end)
end
