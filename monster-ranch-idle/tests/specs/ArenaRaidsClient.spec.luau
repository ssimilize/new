--[[
	ArenaRaidsClient (update 2.1): the Arena and Raids screens played through the real client
	(ClientHarness), including the Monsters pick mode and the battle replay.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function expectClean(c)
		local problems = c:Problems()
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function adults(h, p, lines, rarity, lv, stars)
		local ids = {}
		for _, line in lines do
			local m = h:System("Monsters"):Create(p, { line = line, rarity = rarity, stage = 3 }, "test", true)
			m.lv, m.stars = lv, stars
			table.insert(ids, m.id)
		end
		return ids
	end

	-- In Monsters pick mode: tap each monster, then confirm.
	local function pickMany(c, ids: { string })
		expect(c.kernel.Router:Current()).toBe("Monsters")
		local screen = c:Screen("Monsters")
		for _, id in ids do
			local cell = screen:FindFirstChild(id, true)
			expect(cell ~= nil).toBe(true)
			c:Click(cell:FindFirstChild("Tap"))
			c:Advance(0.2)
		end
		c:Click(c:Button(string.format("Confirm (%d)", #ids), screen))
		c:Advance(1)
	end

	describe("Arena client", function()
		it("sets a defense team and fights a bot through the replay", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 20)
			local ids = adults(h, p, { "wyrmlet", "lumipup", "zappip" }, 3, 30, 2)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Arena")
			c:Advance(0.5)
			c:Click(c:Button("Defense", screen))
			c:Advance(0.5)
			c:Click(screen:FindFirstChild("SetDefense", true))
			c:Advance(0.5)
			pickMany(c, ids)
			local saved = table.clone(h:Section(p, "Arena").defense)
			table.sort(saved)
			local want = table.clone(ids)
			table.sort(want)
			expect(saved).toEqual(want) -- pick mode returns them in list order

			c:Click(c:Button("Battle", screen))
			c:Advance(0.5)
			c:Click(screen:FindFirstChild("FindOpponents", true))
			c:Advance(1)
			local row = screen:FindFirstChild("Opponent1", true)
			expect(row ~= nil).toBe(true)
			c:Click(row:FindFirstChild("Fight"))
			c:Advance(0.5)
			pickMany(c, ids)
			expect(c.kernel.UI.Top:FindFirstChild("BattleReplay") ~= nil).toBe(true)
			expect(h:Section(p, "Arena").attempts.n).toBe(1)
			c:Click(c:Button("Skip ▸▸", c.kernel.UI.Top)) -- not a bare "Skip": a title like "vs Sky Skipper" matches it
			c:Advance(1)
			expect(c:HasText("Rating", c.kernel.UI.Top)).toBe(true)
			expectClean(c)
		end)
	end)

	describe("Raids client", function()
		it("opens a lobby, a second player joins, and both watch the raid", function()
			local h = TestKernel.new({ systems = allSystems() })
			local a = h:Join(7001, "Host")
			local b = h:Join(7002, "Friend")
			levelTo(h, a, 30)
			levelTo(h, b, 30)
			local aIds = adults(h, a, { "wyrmlet", "titanling" }, 6, 60, 5)
			local bIds = adults(h, b, { "wyrmlet", "titanling" }, 6, 60, 5)
			local ca = ClientHarness.new(h, a)
			local cb = ClientHarness.new(h, b)
			ca:Advance(1)
			cb:Advance(1)

			local sa = ca:Open("Raids")
			ca:Advance(0.5)
			ca:Click(sa:FindFirstChild("Raid_titan", true):FindFirstChild("OpenLobby"))
			ca:Advance(0.5)
			pickMany(ca, aIds)
			local lobbyId = h:Session(a, "Raids").lobby
			expect(type(lobbyId)).toBe("string")

			local sb = cb:Open("Raids")
			cb:Advance(1)
			local card = sb:FindFirstChild("Lobby_" .. lobbyId, true)
			expect(card ~= nil).toBe(true)
			cb:Click(card:FindFirstChild("JoinRaid", true))
			cb:Advance(0.5)
			pickMany(cb, bIds)
			expect(h:Session(b, "Raids").lobby).toBe(lobbyId)

			ca:Advance(1)
			ca:Click(sa:FindFirstChild("StartRaid", true))
			ca:Advance(1)
			cb:Advance(1)
			expect(ca.kernel.UI.Top:FindFirstChild("BattleReplay") ~= nil).toBe(true)
			expect(cb.kernel.UI.Top:FindFirstChild("BattleReplay") ~= nil).toBe(true)
			expect(h:Section(a, "Raids").runs).toBe(1)
			expect(h:Section(b, "Raids").runs).toBe(1)
			expectClean(ca)
			expectClean(cb)
		end)
	end)
end
