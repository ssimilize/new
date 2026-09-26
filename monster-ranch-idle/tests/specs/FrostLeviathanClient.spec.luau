--[[
	FrostLeviathanClient (update 3.2): the Raids screen with raid 3 played through the real
	client (ClientHarness). Before 11 Mar 2028 the Frost Leviathan card shows its date and no
	Open lobby button; after it, a host opens a lobby, a second player joins, the host starts
	and both players watch the result.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local LEV = Config.Raids.ById.leviathan

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

	local function adults(h, p, lines)
		local ids = {}
		for _, line in lines do
			local m = h:System("Monsters"):Create(p, { line = line, rarity = 6, stage = 3 }, "test", true)
			m.lv, m.stars = 60, 5
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

	describe("Frost Leviathan client", function()
		it("shows the date before 11 Mar 2028, then two players raid the Leviathan", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = LEV.opensAt - 3600 })
			local a = h:Join(7101, "Host")
			local b = h:Join(7102, "Friend")
			levelTo(h, a, 60)
			levelTo(h, b, 60)
			local aIds = adults(h, a, { "nullkit", "hollowisp" })
			local bIds = adults(h, b, { "thornbolt", "pollenpuff" })
			local ca = ClientHarness.new(h, a)
			local cb = ClientHarness.new(h, b)
			ca:Advance(1)
			cb:Advance(1)

			-- Before the date: three raids listed, the Leviathan shows its date and no Open.
			local sa = ca:Open("Raids")
			ca:Advance(0.5)
			for _, raid in Config.Raids.List do
				expect(sa:FindFirstChild("Raid_" .. raid.id, true) ~= nil).toBe(true)
			end
			local card = sa:FindFirstChild("Raid_leviathan", true)
			expect(card:FindFirstChild("OpenLobby")).toBeNil()
			expect(card:FindFirstChild("Gate").Text).toBe("Opens on 11 Mar 2028")
			expect(ca:HasText("Boss Lv 55 · win: Leviathan Egg", card)).toBe(true)
			expect(sa:FindFirstChild("Raid_titan", true):FindFirstChild("OpenLobby") ~= nil).toBe(true)
			ca:Close("Raids")
			ca:Advance(0.5)

			-- After the date: the host opens a lobby, a friend joins, the host starts.
			h.adapters.setTime(LEV.opensAt + 60)
			ca:Advance(1)
			cb:Advance(1)
			sa = ca:Open("Raids")
			ca:Advance(0.5)
			card = sa:FindFirstChild("Raid_leviathan", true)
			expect(card:FindFirstChild("Gate")).toBeNil()
			ca:Click(card:FindFirstChild("OpenLobby"))
			ca:Advance(0.5)
			pickMany(ca, aIds)
			local lobbyId = h:Session(a, "Raids").lobby
			expect(type(lobbyId)).toBe("string")
			expect(h:Client(a).global.Raids.lobbies[lobbyId].raid).toBe("leviathan")

			local sb = cb:Open("Raids")
			cb:Advance(1)
			local lobbyCard = sb:FindFirstChild("Lobby_" .. lobbyId, true)
			expect(lobbyCard ~= nil).toBe(true)
			expect(cb:HasText("Frost Leviathan · 1/4", lobbyCard)).toBe(true)
			cb:Click(lobbyCard:FindFirstChild("JoinRaid", true))
			cb:Advance(0.5)
			pickMany(cb, bIds)
			expect(h:Session(b, "Raids").lobby).toBe(lobbyId)

			ca:Advance(1)
			ca:Click(sa:FindFirstChild("StartRaid", true))
			ca:Advance(1)
			cb:Advance(1)
			for _, c in { ca, cb } do
				local replay = c.kernel.UI.Top:FindFirstChild("BattleReplay")
				expect(replay ~= nil).toBe(true)
				expect(c:HasText("Raid · Frost Leviathan", replay)).toBe(true)
			end
			expect(h:Section(a, "Raids").runs).toBe(1)
			expect(h:Section(b, "Raids").runs).toBe(1)
			expect(h:LastEvent(b, "Raids.Result").payload.raid).toBe("leviathan")
			expectClean(ca)
			expectClean(cb)
		end)

		it("shows the unlock level to a player below Level 60 instead of Open or Join", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = LEV.opensAt + 60 })
			local a = h:Join(7201, "Host")
			local low = h:Join(7202, "Low")
			levelTo(h, a, 60)
			levelTo(h, low, 30)
			local ids = adults(h, a, { "nullkit" })
			h:Call(a, "Raids.Open", { raid = "leviathan", ids = ids })
			local c = ClientHarness.new(h, low)
			c:Advance(1)
			local s = c:Open("Raids")
			c:Advance(1)
			local card = s:FindFirstChild("Raid_leviathan", true)
			expect(card:FindFirstChild("OpenLobby")).toBeNil()
			expect(card:FindFirstChild("Gate").Text).toBe("Unlocks at Ranch Level 60")
			expect(s:FindFirstChild("Raid_titan", true):FindFirstChild("OpenLobby") ~= nil).toBe(true)
			expect(s:FindFirstChild("JoinRaid", true)).toBeNil()
			expect(s:FindFirstChild("JoinLocked", true).Text).toBe("Unlocks at Ranch Level 60")
			expectClean(c)
		end)
	end)
end
