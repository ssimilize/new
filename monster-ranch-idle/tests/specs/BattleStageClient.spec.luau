--[[
	BattleStageClient (glow-up V): the 3D battle stage played through the real client
	(ClientHarness) - a stage fight (Expeditions), an Arena match and a Raid, each forced to the
	3D stage and to the 2D fallback, skip, and cleanup (nothing left behind, BattleArena.Live()
	back to 0). Caps and placement are unit-tested directly on Visuals/BattleArena.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Tuning = t.Shared("Config.BattleStage")

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

	local function battleModule(c)
		return c:require(c.clientFolder.UI.Screens.Parts.Battle)
	end

	local function root(c)
		return c.kernel.UI.Top:FindFirstChild("BattleReplay")
	end

	local function is3D(c): boolean
		return root(c) ~= nil and root(c):GetAttribute("Stage3D") == true
	end

	describe("stage fight (Expeditions)", function()
		it("draws the 3D stage, skips, and cleans up", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 20)
			local ids = adults(h, p, { "wyrmlet", "lumipup", "zappip" }, 3, 30, 2)
			h:Call(p, "Expeditions.SetSquad", { ids = ids })
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local Battle = battleModule(c)
			Battle.SetMode("3d")
			local BattleArena = c:require(c.clientFolder.Visuals.BattleArena)

			local screen = c:Open("Expeditions")
			c:Advance(0.5)
			c:Click(c:Button("Fight stage 1", screen))
			c:Advance(0.3)
			expect(is3D(c)).toBe(true)
			expect(BattleArena.Live()).toBe(1)

			c:Click(c:Button("Skip ▸▸", c.kernel.UI.Top))
			c:Advance(1)
			expect(c:HasText("cleared", c.kernel.UI.Top) or c:HasText("fainted", c.kernel.UI.Top)).toBe(true)
			c:Click(c:Button("Continue", c.kernel.UI.Top))
			c:Advance(1)

			expect(root(c)).toBeNil()
			expect(BattleArena.Live()).toBe(0)
			Battle.SetMode(nil)
			expectClean(c)
		end)

		it("falls back to the 2D viewer when forced", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 20)
			local ids = adults(h, p, { "wyrmlet", "lumipup", "zappip" }, 3, 30, 2)
			h:Call(p, "Expeditions.SetSquad", { ids = ids })
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local Battle = battleModule(c)
			Battle.SetMode("2d")
			local BattleArena = c:require(c.clientFolder.Visuals.BattleArena)

			local screen = c:Open("Expeditions")
			c:Advance(0.5)
			c:Click(c:Button("Fight stage 1", screen))
			c:Advance(0.3)
			expect(root(c) ~= nil).toBe(true)
			expect(is3D(c)).toBe(false)
			expect(BattleArena.Live()).toBe(0) -- the 2D viewer never touches the world
			expect(root(c):FindFirstChild("a1", true) ~= nil).toBe(true)

			c:Click(c:Button("Skip ▸▸", c.kernel.UI.Top))
			c:Advance(1)
			c:Click(c:Button("Continue", c.kernel.UI.Top))
			c:Advance(1)
			expect(root(c)).toBeNil()
			Battle.SetMode(nil)
			expectClean(c)
		end)
	end)

	describe("Arena match", function()
		it("draws the 3D stage for a normalized fight and cleans up", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 20)
			local ids = adults(h, p, { "wyrmlet", "lumipup", "zappip" }, 3, 30, 2)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local Battle = battleModule(c)
			Battle.SetMode("3d")
			local BattleArena = c:require(c.clientFolder.Visuals.BattleArena)

			local screen = c:Open("Arena")
			c:Advance(0.5)
			c:Click(c:Button("Defense", screen))
			c:Advance(0.5)
			c:Click(screen:FindFirstChild("SetDefense", true))
			c:Advance(0.5)
			pickMany(c, ids)

			c:Click(c:Button("Battle", screen))
			c:Advance(0.5)
			c:Click(screen:FindFirstChild("FindOpponents", true))
			c:Advance(1)
			local row = screen:FindFirstChild("Opponent1", true)
			expect(row ~= nil).toBe(true)
			c:Click(row:FindFirstChild("Fight"))
			c:Advance(0.5)
			pickMany(c, ids)

			expect(is3D(c)).toBe(true)
			expect(BattleArena.Live()).toBe(1)
			c:Click(c:Button("Skip ▸▸", c.kernel.UI.Top))
			c:Advance(1)
			c:Click(c:Button("Continue", c.kernel.UI.Top))
			c:Advance(1)
			expect(root(c)).toBeNil()
			expect(BattleArena.Live()).toBe(0)
			Battle.SetMode(nil)
			expectClean(c)
		end)
	end)

	describe("Raid", function()
		it("draws every ally and the bigger boss in 3D for both members, then cleans up", function()
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
			local BattleA = battleModule(ca)
			local BattleB = battleModule(cb)
			BattleA.SetMode("3d")
			BattleB.SetMode("3d")
			local ArenaA = ca:require(ca.clientFolder.Visuals.BattleArena)
			local ArenaB = cb:require(cb.clientFolder.Visuals.BattleArena)

			local sa = ca:Open("Raids")
			ca:Advance(0.5)
			ca:Click(sa:FindFirstChild("Raid_titan", true):FindFirstChild("OpenLobby"))
			ca:Advance(0.5)
			pickMany(ca, aIds)

			local sb = cb:Open("Raids")
			cb:Advance(1)
			local lobbyId = h:Session(a, "Raids").lobby
			local card = sb:FindFirstChild("Lobby_" .. lobbyId, true)
			cb:Click(card:FindFirstChild("JoinRaid", true))
			cb:Advance(0.5)
			pickMany(cb, bIds)

			ca:Advance(1)
			ca:Click(sa:FindFirstChild("StartRaid", true))
			ca:Advance(1)
			cb:Advance(1)

			expect(is3D(ca)).toBe(true)
			expect(is3D(cb)).toBe(true)
			expect(ArenaA.Live()).toBe(1)
			expect(ArenaB.Live()).toBe(1)

			ca:Click(ca:Button("Skip ▸▸", ca.kernel.UI.Top))
			ca:Advance(1)
			cb:Click(cb:Button("Skip ▸▸", cb.kernel.UI.Top))
			cb:Advance(1)
			ca:Click(ca:Button("Continue", ca.kernel.UI.Top))
			cb:Click(cb:Button("Continue", cb.kernel.UI.Top))
			ca:Advance(1)
			cb:Advance(1)

			expect(root(ca)).toBeNil()
			expect(root(cb)).toBeNil()
			expect(ArenaA.Live()).toBe(0)
			expect(ArenaB.Live()).toBe(0)
			BattleA.SetMode(nil)
			BattleB.SetMode(nil)
			expectClean(ca)
			expectClean(cb)
		end)
	end)

	describe("Visuals/BattleArena caps and cleanup (unit)", function()
		it("builds with the quality-selected caps and frees everything on Destroy", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local BattleArena = c:require(c.clientFolder.Visuals.BattleArena)

			local live = BattleArena.new({ theme = Tuning.themes.default, units = {}, placement = {}, low = false })
			live:Build()
			local counts = live:Counts()
			expect(counts.limits.bolts.live).toBe(Tuning.caps.bolts.live)
			expect(counts.limits.numbers.live).toBe(Tuning.caps.numbers.live)
			expect(counts.limits.sparks.live).toBe(Tuning.caps.sparks.live)
			expect(BattleArena.Live()).toBe(1)
			live:Destroy()
			expect(BattleArena.Live()).toBe(0)

			local low = BattleArena.new({ theme = Tuning.themes.default, units = {}, placement = {}, low = true })
			low:Build()
			expect(low:Counts().limits.sparks.live).toBe(0) -- no sparks on Low
			expect(low:Counts().limits.bolts.live <= Tuning.caps.bolts.live).toBe(true)
			low:Destroy()
			expect(BattleArena.Live()).toBe(0)
			expectClean(c)
		end)
	end)
end
