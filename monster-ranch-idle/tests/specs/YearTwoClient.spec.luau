--[[
	YearTwoClient (update 3.0): Racing, the Trading Hub and the Workshop played through the
	real client (ClientHarness), plus the Expeditions region tabs with an opening date.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")

	local LAUNCH = Config.Regions.ById.dunes.opensAt

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

	local function adult(h, p, line: string, rarity: number?)
		return h:System("Monsters"):Create(p, { line = line, rarity = rarity or 4, stage = 3 }, "test", true)
	end

	-- Monsters pick mode: tap each monster; confirm when several can be picked.
	local function pick(c, ids: { string }, confirm: boolean)
		expect(c.kernel.Router:Current()).toBe("Monsters")
		local screen = c:Screen("Monsters")
		for _, id in ids do
			local cell = screen:FindFirstChild(id, true)
			expect(cell ~= nil).toBe(true)
			c:Click(cell:FindFirstChild("Tap"))
			c:Advance(0.2)
		end
		if confirm then
			c:Click(c:Button(string.format("Confirm (%d)", #ids), screen))
		end
		c:Advance(1)
	end

	describe("Racing client", function()
		it("picks a racer, runs the track with Jump and Boost and shows the server's result", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = LAUNCH + 3600 })
			local p = h:Join()
			levelTo(h, p, 16)
			local m = adult(h, p, "zappip", 5)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Racing")
			c:Advance(0.5)
			expect(c:HasText("Today's ghosts", screen)).toBe(true)
			c:Click(screen:FindFirstChild("PickRacer", true))
			c:Advance(0.5)
			pick(c, { m.id }, false)
			expect(c.kernel.Router:Current()).toBe("Racing")
			expect(screen:FindFirstChild("Track", true) ~= nil).toBe(true)
			expect(screen:FindFirstChild("Racer", true) ~= nil).toBe(true)
			-- Hop and boost along until the finish.
			for i = 1, 200 do
				if screen:FindFirstChild("RaceResult", true) then
					break
				end
				local jump = screen:FindFirstChild("Jump", true)
				if jump and i % 2 == 0 then
					c:Click(jump)
				end
				local boost = screen:FindFirstChild("Boost", true)
				if boost and i % 5 == 0 then
					c:Click(boost)
				end
				c:Advance(0.45, 0.05)
			end
			expect(screen:FindFirstChild("RaceResult", true) ~= nil).toBe(true)
			expect(c:HasText("place", screen)).toBe(true)
			expect(h:Section(p, "Racing").races).toBe(1)
			c:Click(screen:FindFirstChild("RaceDone", true))
			c:Advance(0.5)
			expect(c:HasText("Races: 1", screen)).toBe(true)
			c:Close("Racing")
			expectClean(c)
		end)
	end)

	describe("Trading Hub client", function()
		it("posts an ad in the hub and a trader on the same server starts a trade from it", function()
			local h = TestKernel.new({ systems = allSystems(), placeMode = "hub" })
			local a = h:Join(8001, "Ann")
			local b = h:Join(8002, "Ben")
			levelTo(h, a, 8)
			levelTo(h, b, 8)
			for _, x in { a, b } do
				h.kernel.Data:Get(x)._meta.playSeconds = 3600 -- trading needs 30 minutes of play
			end
			local m = adult(h, a, "lumipup", 5)
			local ca = ClientHarness.new(h, a)
			local cb = ClientHarness.new(h, b)
			ca:Advance(1)
			cb:Advance(1)
			expect(ca.world.workspace.World:GetAttribute("PlaceMode")).toBe("hub")
			expect(ca.world.workspace.World.Hub.Buildings:FindFirstChild("tradeBoard") ~= nil).toBe(true)
			expect(#ca.world.workspace.World.Plots:GetChildren()).toBe(0)

			local sa = ca:Open("TradingHub")
			ca:Advance(0.5)
			expect(ca:IsShown(sa:FindFirstChild("BackToRanch", true))).toBe(true)
			ca:Click(ca:Button("My ad", sa))
			ca:Advance(0.5)
			ca:Click(sa:FindFirstChild("PickOffer", true))
			ca:Advance(0.5)
			pick(ca, { m.id }, true)
			expect(ca.kernel.Router:Current()).toBe("TradingHub")
			ca:Click(sa:FindFirstChild("Want_mythic", true))
			ca:Click(sa:FindFirstChild("PostAd", true))
			ca:Advance(1)
			expect(h:Session(a, "TradingHub").ad ~= false).toBe(true)
			expect(sa:FindFirstChild("Ad1", true) ~= nil).toBe(true)

			local sb = cb:Open("TradingHub")
			cb:Advance(1)
			local ad = sb:FindFirstChild("Ad1", true)
			expect(ad ~= nil).toBe(true)
			expect(cb:HasText("on this server", ad)).toBe(true)
			expect(cb:HasText("Mythic", ad)).toBe(true)
			cb:Click(ad:FindFirstChild("Meet", true))
			cb:Advance(1)
			expect(h:Session(b, "Trade").status).toBe("outgoing")
			expectClean(ca)
			expectClean(cb)
		end)

		it("previews the board from the ranch and offers the trip", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			expect(c.world.workspace.World.Hub.Buildings:FindFirstChild("hubPortal") ~= nil).toBe(true)
			local screen = c:Open("TradingHub")
			c:Advance(0.5)
			expect(c:IsShown(screen:FindFirstChild("BackToRanch", true))).toBe(false)
			expect(c:HasText("No ads yet", screen)).toBe(true)
			expect(c:HasText("Unlocks at Ranch Level 8", screen)).toBe(true)
			expectClean(c)
		end)
	end)

	describe("Workshop client", function()
		it("designs, publishes and dresses a monster in a player-made accessory", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 12)
			h:System("Currency"):Add(p, "ribbons", 100, "test")
			local m = adult(h, p, "zappip")
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Workshop")
			c:Advance(0.5)
			c:Click(screen:FindFirstChild("Shape_crown", true))
			c:Advance(0.3)
			c:Click(screen:FindFirstChild("MainColor", true):FindFirstChild("Color10"))
			c:Advance(0.3)
			c:Type(screen:FindFirstChild("DesignName", true), "Violet Crown")
			c:Click(screen:FindFirstChild("Publish", true))
			c:Advance(1)
			local copies = h:Section(p, "Workshop").copies
			local id = next(copies)
			expect(copies[id].name).toBe("Violet Crown")
			expect(copies[id].color).toBe(Config.Workshop.Palette[10])

			c:Click(c:Button("Gallery", screen))
			c:Advance(1)
			expect(screen:FindFirstChild("Design_" .. id, true) ~= nil).toBe(true)
			c:Click(c:Button("My copies", screen))
			c:Advance(0.5)
			c:Click(screen:FindFirstChild("Copy_" .. id, true):FindFirstChild("Wear", true))
			c:Advance(0.5)
			pick(c, { m.id }, false)
			expect(h:System("Monsters"):Get(p, m.id).acc.head).toBe(
				Config.Accessories.Encode(id, "crown", Config.Workshop.Palette[10], Config.Workshop.Palette[3])
			)
			-- The Wardrobe shows it by its name.
			c:Close("Workshop")
			local wardrobe = c:Open("Wardrobe", { id = m.id })
			c:Advance(0.5)
			expect(c:HasText("Violet Crown", wardrobe)).toBe(true)
			expectClean(c)
		end)
	end)

	describe("Workshop moderation client", function()
		it("lets a moderator restore a reported design from the Review queue (3.0.1)", function()
			local W = Config.Workshop
			local h = TestKernel.new({ systems = allSystems() })
			local maker = h:Join(8101, "Maker")
			levelTo(h, maker, 12)
			h:System("Currency"):Add(maker, "ribbons", 100, "test")
			local id =
				h:Call(maker, "Workshop.Create", { name = "Odd Hat", shape = "cap", color = W.Palette[1], color2 = W.Palette[2] }).design
			for i = 1, W.ReportsToHide do
				h:Call(h:Join(8200 + i), "Workshop.Report", { design = id })
			end
			table.insert(W.Moderators, 8300)
			local ok, err = pcall(function()
				local mod = h:Join(8300, "Mod")
				local c = ClientHarness.new(h, mod)
				c:Advance(1)
				local screen = c:Open("Workshop")
				c:Advance(0.5)
				c:Click(c:Button("Gallery", screen))
				c:Advance(1)
				c:Click(screen:FindFirstChild("Gallery_review", true))
				c:Advance(1)
				local card = screen:FindFirstChild("Design_" .. id, true)
				expect(card ~= nil).toBe(true)
				expect(c:HasText("3 reports", card)).toBe(true)
				c:Click(card:FindFirstChild("Mod_restore", true))
				c:Advance(1)
				expect(h:Session(mod, "Workshop").queue[1]).toBeNil()
				expect(c:HasText("Nothing to review.", screen)).toBe(true)
				expectClean(c)
			end)
			table.remove(W.Moderators)
			if not ok then
				error(err, 0)
			end
		end)
	end)

	describe("Club Wars client (3.1)", function()
		it("shows the league, the ladder and a banner picked from Workshop designs", function()
			local War = Config.Clubs.War
			local h = TestKernel.new({ systems = allSystems(), startTime = War.startsAt + 3600 })
			local p = h:Join(8501, "Captain")
			levelTo(h, p, 30)
			h:System("Currency"):Add(p, "coins", 1e6, "test")
			h:System("Currency"):Add(p, "ribbons", 100, "test")
			local clubId = h:Call(p, "Clubs.Create", { name = "Race Crew", tag = "RACE", color = 3, emblem = "bolt", open = true }).id
			h:Advance(2)
			local design = h:Call(p, "Workshop.Create", {
				name = "Crew Flag",
				shape = "cape",
				color = Config.Workshop.Palette[4],
				color2 = Config.Workshop.Palette[1],
			}).design
			for _ = 1, 30 do
				h.kernel.Bus:Publish("RaidFinished", p, { raid = "titan", win = true })
			end
			h:System("Clubs"):Flush()
			h:System("Clubs"):RefreshLadder()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Clubs")
			c:Advance(0.5)
			c:Click(c:Button("Club Wars", screen))
			c:Advance(0.5)
			expect(c:HasText("Bronze league · 150 war points", screen)).toBe(true)
			expect(c:HasText("to Silver", screen)).toBe(true)
			local ladder = screen:FindFirstChild("Ladder", true)
			expect(c:HasText("1. [RACE] Race Crew · 150", ladder)).toBe(true)
			expect(screen:FindFirstChild("ClaimWar", true) ~= nil).toBe(true)

			c:Click(c:Button("Settings", screen))
			c:Advance(0.5)
			c:Click(screen:FindFirstChild("Banner_" .. design, true))
			c:Advance(1)
			expect(c:Store("session.Clubs.club").banner.name).toBe("Crew Flag")
			expect(c:HasText("Banner: Crew Flag", screen)).toBe(true)
			expect(clubId ~= nil).toBe(true)
			expectClean(c)
		end)
	end)

	describe("Expeditions region tabs", function()
		it("shows a region's opening date until it opens", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = LAUNCH - 86400 })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Expeditions")
			c:Advance(0.5)
			expect(c:HasText("Dunes · 11 Dec", screen:FindFirstChild("Region_dunes", true))).toBe(true)
			expect(c:HasText("Sky · Lv 45", screen:FindFirstChild("Region_sky", true))).toBe(true)
			c:Click(screen:FindFirstChild("Region_dunes", true))
			c:Advance(0.5)
			expect(c:HasText("Mirage Dunes opens on 11 Dec 2027", screen)).toBe(true)
			expectClean(c)
		end)
	end)
end
