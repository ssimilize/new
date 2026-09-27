-- Glow-up TT: the titan invasion live in the world, driven through the real client
-- (ClientHarness): the banner (heads-up then the shared bar), the giant, and cleanup after.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")

	local Cfg = Config.Titan
	local A = Cfg.Arena
	local SLOT = Cfg.Schedule[1].startsAt
	local BOOT_MARGIN = 50
	local BOOT = SLOT - Cfg.LobbySeconds - BOOT_MARGIN
	local TO_LOBBY = BOOT_MARGIN + 1

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function fighter(h)
		local p = h:Join()
		h:Section(p, "Progression").level = 4
		local M = h:System("Monsters")
		local ids = {}
		for i = 1, 3 do
			local m = M:Create(p, { line = "cindlet", rarity = 5, stage = 3, traits = { 3, 4 }, hidden = 5 }, "test", true)
			m.lv = 20
			ids[i] = m.id
		end
		h:Call(p, "Expeditions.SetSquad", { ids = ids })
		return h:Rejoin(p)
	end

	local function models(f): number
		local n = 0
		for _, child in f:GetChildren() do
			if child:IsA("Model") then
				n += 1
			end
		end
		return n
	end

	describe("Titan invasion client", function()
		it("shows the banner then the shared bar, draws the giant, and cleans up after it falls", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = BOOT })
			local p = fighter(h)
			local c = ClientHarness.new(h, p)
			local Titan = c:require(c.clientFolder.Controllers.TitanInvasion)
			local game = c.world.game
			local Lighting = game:GetService("Lighting")
			local T = h:System("Titan")

			c:Advance(TO_LOBBY)
			expect(T:State().state).toBe("lobby")
			expect(c:HasText("The Titan is coming!", c.kernel.UI.Feedback)).toBe(true)
			c:Click(c:Button("Join", c.kernel.UI.Feedback))
			c:Advance(1)
			expect(c:Store("session.Titan").joined).toBe(true)

			c:Advance(Cfg.LobbySeconds)
			expect(T:State().state).toBe("active")
			c:Advance(1)
			expect(c:HasText("The Titan is here!", c.kernel.UI.Feedback)).toBe(true)
			expect(Titan:Stats().giant).toBe(true)
			expect(Titan:Stats().storm > 0).toBe(true)
			expect(Lighting:FindFirstChild("TitanStorm") ~= nil).toBe(true)

			-- Defeat: the giant falls, the banner stays a moment, then everything is cleaned up.
			local network = h.adapters and h.adapters.network
			if network then
				network.titan[tostring(SLOT)] = { hp = 0, servers = {} }
			end
			c:Advance(Cfg.ReportSeconds + 1)
			expect(T:State().state).toBe("fallen")
			c:Advance(0.2)
			expect(Titan:Stats().phase).toBe("ending")

			c:Advance(A.fallSeconds + A.leaveSeconds + 1)
			expect(Titan:Stats().giant).toBe(false)
			expect(Titan:Stats().phase).toBe("off")
			expect(Lighting:FindFirstChild("TitanStorm")).toBe(nil)
		end)

		it("gives a player who arrives mid-invasion the banner and Join, then Cheer", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = SLOT + 60 })
			local T = h:System("Titan")
			expect(T:State().state).toBe("active")
			local p = fighter(h)
			local c = ClientHarness.new(h, p) -- after Titan.Starting / Titan.Started went out
			local Titan = c:require(c.clientFolder.Controllers.TitanInvasion)
			local Workspace = c.world.game:GetService("Workspace")
			local centre = Config.World.StampedeArena.center
			c:Advance(0.5)
			local feedback = c.kernel.UI.Feedback
			expect(c:HasText("The Titan is here!", feedback)).toBe(true)
			c:Click(c:Button("Join", feedback))
			c:Advance(1)
			expect(c:Store("session.Titan").joined).toBe(true)
			expect(c:Button("Join", feedback)).toBe(nil)
			-- R2 titan squads: your joined squad draws in a ring round the giant.
			c.character:PivotTo(t.Roblox.CFrame.new(t.Roblox.Vector3.new(centre[1], 0, centre[2])))
			c:Advance(1)
			local folder = Workspace:FindFirstChild("TitanInvasion")
			expect(folder ~= nil).toBe(true)
			local gTitan = c:Store("global.Titan")
			expect(#(gTitan.squads or {})).toBe(1)
			expect(Titan:Stats().squad).toBe(3)
			expect(models(folder)).toBe(4) -- 3 squad monsters + the giant

			local cheer = c:Button("Cheer", feedback)
			expect(cheer ~= nil).toBe(true)
			for _ = 1, 20 do
				c:Click(cheer)
			end
			expect(Titan:Stats().bolts).toBe(A.boltsPerSecond)
			c:Advance(1)
			expect((tonumber(c:Store("session.Titan").cheer) or 0) > 0).toBe(true)
			expect(Titan:Stats().bolts).toBe(0) -- landed and back in the pool

			-- Found in Studio 2026-09-26: the HP fill was the banner's own purple (a full bar read as
			-- empty), the banner sat on top of open screens, and "1 servers" showed.
			local banner = feedback:FindFirstChild("TitanBanner")
			local fill
			for _, d in banner:GetDescendants() do
				if d:IsA("Frame") and d.Parent and d.Parent:IsA("Frame") and d.Parent.Parent == banner and d.Size.Y.Scale == 1 then
					fill = d
				end
			end
			expect(fill ~= nil).toBe(true)
			expect(fill.BackgroundColor3 == banner.BackgroundColor3).toBe(false)
			local counted = false
			for _, d in banner:GetDescendants() do
				if d:IsA("TextLabel") and d.Text:match("^Fighting: %d+ · Servers: %d+$") then
					counted = true
				end
			end
			expect(counted).toBe(true)
			expect(banner.Visible).toBe(true)
			c:Open("Monsters")
			c:Advance(0.2)
			expect(banner.Visible).toBe(false)
			c:Close("Monsters")
			c:Advance(0.2)
			expect(banner.Visible).toBe(true)
			expect(c.world.errors).toEqual({})
		end)

		it("plays the fall and the loot fountain for a joined player, then cleans up after it", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = SLOT + 60 })
			local T = h:System("Titan")
			expect(T:State().state).toBe("active")
			local p = fighter(h)
			local c = ClientHarness.new(h, p)
			local Titan = c:require(c.clientFolder.Controllers.TitanInvasion)
			local Workspace = c.world.game:GetService("Workspace")
			local centre = Config.World.StampedeArena.center

			c:Advance(0.5)
			c:Request("Titan.Join")
			c:Advance(1)
			expect(c:Store("session.Titan").joined).toBe(true)
			c.character:PivotTo(t.Roblox.CFrame.new(t.Roblox.Vector3.new(centre[1], 0, centre[2])))
			c:Advance(0.5)
			local folder = Workspace:FindFirstChild("TitanInvasion")

			-- Defeat: the shared pool reads empty, the giant falls, the loot fountain plays at the
			-- arena before the result popup (Broadcasts hands Titan.Result to :Fountain first).
			local network = h.adapters and h.adapters.network
			if network then
				network.titan[tostring(SLOT)] = { hp = 0, servers = {} }
			end
			c:Advance(Cfg.ReportSeconds + 1)
			expect(T:State().state).toBe("fallen")
			expect(c:HasText("The titan falls!", c.kernel.UI.Top)).toBe(false) -- waits for the fountain
			c:Advance(A.fallSeconds + A.fountainSeconds + 0.5)
			expect(c:HasText("The titan falls!", c.kernel.UI.Top)).toBe(true)
			c:Click(c:Button("Nice!", c.kernel.UI.Top))

			c:Advance(A.leaveSeconds + A.storm.fade + 1)
			local stats = Titan:Stats()
			expect(stats.phase).toBe("off")
			expect(stats.giant).toBe(false)
			expect(stats.squad).toBe(0)
			expect(models(folder)).toBe(0)
			expect(c:Problems()).toEqual({})
		end)
	end)
end
