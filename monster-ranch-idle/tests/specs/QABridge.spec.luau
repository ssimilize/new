--[[
	QABridge + MemoryStores: the Studio-only QA tools. The in-memory DataStoreService stand-in the
	adapters use on QA_MemoryProfiles, and the server bridge's commands (write commands refused
	unless the session runs on memory stores, so a check can never change a real save).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local MemoryStores = t.Server("Kernel.MemoryStores")
	local QABridge = t.Server("Kernel.QABridge")

	describe("MemoryStores", function()
		it("keeps DataStore values, updates atomically and never shares tables", function()
			local service = MemoryStores.new()
			local store = service:GetDataStore("A")
			expect(service:GetDataStore("A")).toBe(store)
			local record = { n = 1 }
			store:SetAsync("k", record)
			record.n = 2
			expect(store:GetAsync("k").n).toBe(1)
			expect(store:UpdateAsync("k", function(current)
				current.n += 5
				return current
			end).n).toBe(6)
			expect(store:UpdateAsync("k", function()
				return nil -- no write
			end)).toBeNil()
			expect(store:GetAsync("k").n).toBe(6)
			expect(store:IncrementAsync("count", 3)).toBe(3)
			store:RemoveAsync("k")
			expect(store:GetAsync("k")).toBeNil()
		end)

		it("sorts an ordered store into pages", function()
			local board = MemoryStores.new():GetOrderedDataStore("LB")
			for i = 1, 5 do
				board:SetAsync("u" .. i, i * 10)
			end
			local pages = board:GetSortedAsync(false, 2)
			local first = pages:GetCurrentPage()
			expect(#first).toBe(2)
			expect(first[1].key).toBe("u5")
			expect(first[2].value).toBe(40)
			expect(pages.IsFinished).toBe(false)
			pages:AdvanceToNextPageAsync()
			pages:AdvanceToNextPageAsync()
			expect(pages:GetCurrentPage()[1].key).toBe("u1")
			expect(pages.IsFinished).toBe(true)
		end)
	end)

	describe("the server bridge", function()
		local function boot(qa: boolean)
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Settings" } })
			h.adapters.QA = qa
			local p = h:Join()
			return h, p
		end

		it("reads players, sections and globals on any session", function()
			local h, p = boot(false)
			local players = QABridge.Run(h.kernel, "players")
			expect(players.ok).toBe(true)
			expect(players.result[1].userId).toBe(p.UserId)
			local section = QABridge.Run(h.kernel, "section", { userId = p.UserId, system = "Progression" })
			expect(section.result.level).toBe(1)
			expect(QABridge.Run(h.kernel, "nope").ok).toBe(false)
		end)

		it("refuses every write unless the session runs on memory stores", function()
			local h, p = boot(false)
			for _, command in { "set", "call", "system", "titan", "config" } do
				local r = QABridge.Run(h.kernel, command, { userId = p.UserId })
				expect(r.ok).toBe(false)
				expect(r.err).toContain("QA_MemoryProfiles")
			end
			expect(h:Section(p, "Progression").level).toBe(1)
		end)

		it("sets a save field, calls an action and schedules a titan on a QA session", function()
			local h, p = boot(true)
			local set = QABridge.Run(h.kernel, "set", { userId = p.UserId, path = { "Progression", "level" }, value = 64 })
			expect(set.ok).toBe(true)
			expect(h:Section(p, "Progression").level).toBe(64)

			local call =
				QABridge.Run(h.kernel, "call", { userId = p.UserId, action = "Settings.SetGraphics", payload = { graphics = "low" } })
			expect(call.ok).toBe(true)
			expect(call.result.ok).toBe(true)

			local schedule = Config.Titan.Schedule
			local before = #schedule
			local titan = QABridge.Run(h.kernel, "titan", { seconds = 30 })
			expect(titan.ok).toBe(true)
			expect(#schedule).toBe(before + 1)
			expect(schedule[#schedule].startsAt).toBe(titan.result)
			table.remove(schedule) -- shared Config: leave it as it was
		end)
	end)
end
