--[[
	Celebrate (glow-up: moments): celebration sizes (Logic/Celebration), the one feedback queue
	(toasts + reward cards on the Feedback layer), the layout-safe shake, the moment queue that
	holds in-world bursts while a screen or popup covers the world, rewards that fly into the
	HUD counters, and the Stampede call — through the real client (ClientHarness).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Celebration = t.Shared("Logic.Celebration")
	local Format = t.Shared("Logic.Format")

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
		local problems = c:Problems({ "Infinite yield possible" })
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	local function boot(options: { [string]: any }?)
		local h = TestKernel.new({ systems = allSystems(), startTime = options and options.startTime })
		local p = h:Join()
		local c = ClientHarness.new(h, p)
		c:Advance(1)
		return h, p, c
	end

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function liveItems(c)
		local list = {}
		for _, child in c.kernel.UI.Feedback.Toasts:GetChildren() do
			if child:IsA("GuiObject") and child:GetAttribute("Leaving") ~= true then
				table.insert(list, child)
			end
		end
		return list
	end

	local function pillText(c, name: string): string
		local root = c.kernel:GetController("Hud"):GetTarget(name)
		for _, child in root:GetChildren() do
			if child:IsA("TextLabel") then
				return child.Text
			end
		end
		return ""
	end

	local function flyingIcons(c): number
		local n = 0
		for _, child in c.kernel.UI.Feedback.Celebrate:GetChildren() do
			if child:IsA("Frame") and child.ZIndex == 6 and child.Name ~= "Sparkle" then
				n += 1
			end
		end
		return n
	end

	describe("Celebration sizes", function()
		it("judges coins against income and gems and items by steps", function()
			expect(Celebration.CoinSize(40, 0)).toBe("small")
			expect(Celebration.CoinSize(1000, 100)).toBe("small") -- 10 s of income
			expect(Celebration.CoinSize(1000, 5)).toBe("medium") -- 200 s
			expect(Celebration.CoinSize(100000, 100)).toBe("big") -- 1000 s
			expect(Celebration.CoinSize(400000, 100)).toBe("huge") -- over an hour
			expect(Celebration.GemSize(5)).toBe("small")
			expect(Celebration.GemSize(10)).toBe("medium")
			expect(Celebration.GemSize(60)).toBe("big")
			expect(Celebration.GemSize(300)).toBe("huge")
			expect(Celebration.Size({ { kind = "coins", amount = 10 }, { kind = "egg", id = "meadow", amount = 1 } }, 1)).toBe("medium")
			expect(Celebration.Size({ { kind = "gems", amount = 300 }, { kind = "coins", amount = 10 } }, 1)).toBe("huge")
			expect(Celebration.Size({}, 1)).toBe("small")
			expect(Celebration.Max("big", "medium")).toBe("big")
			expect(Celebration.Max(nil, "huge")).toBe("huge")
		end)

		it("plans bigger moments for bigger sizes and strips motion in low graphics", function()
			local small, big, huge = Celebration.Plan("small"), Celebration.Plan("big"), Celebration.Plan("huge")
			expect(big.icons).toBeGreaterThan(small.icons)
			expect(huge.countTime).toBeGreaterThan(big.countTime)
			expect(big.countTime).toBeGreaterThan(small.countTime)
			expect(small.shower).toBe(0)
			expect(big.shower).toBeGreaterThan(0)
			expect(big.confetti).toBeGreaterThan(0)
			expect(big.shake).toBe(0)
			expect(huge.shake).toBeGreaterThan(0)
			expect(huge.fov).toBeGreaterThan(0)
			local low = Celebration.Plan("huge", true)
			expect(low.icons).toBe(0)
			expect(low.shower + low.confetti + low.shake + low.fov).toBe(0)
			expect(low.countTime).toBeGreaterThan(0)
			expect(low.sound).toBe(huge.sound)
		end)

		it("climbs the coin tick over a stream and a streak, within five steps", function()
			expect(Celebration.TickKey(1, 10, 1)).toBe("CoinTick1")
			expect(Celebration.TickKey(10, 10, 1)).toBe("CoinTick5")
			expect(Celebration.TickKey(1, 10, 3)).toBe("CoinTick3")
			expect(Celebration.TickKey(10, 10, 9)).toBe("CoinTick5")
			expect(Celebration.TickKey(1, 1, 1)).toBe("CoinTick1")
			for i = 1, 5 do
				expect(Config.Sounds["CoinTick" .. i]).toBe("")
			end
			for _, key in { "GemTick", "ItemPop", "Whoosh", "StarUp", "CelebrateBig", "CelebrateHuge", "StampedeSoon", "BossHorn" } do
				expect(Config.Sounds[key] ~= nil).toBe(true)
			end
		end)
	end)

	describe("Feedback queue", function()
		it("stacks toasts and reward cards in one list above the popups", function()
			local h, p, c = boot()
			local UI = c.kernel.UI
			expect(UI.Feedback.ZIndex).toBeGreaterThan(UI.Top.ZIndex)
			expect(UI.Overlay:FindFirstChild("Toasts")).toBe(nil)
			expect(UI.Overlay:FindFirstChild("RewardFeed")).toBe(nil)
			c.kernel:Toast("Hello there", "info")
			h:System("Rewards"):Grant(p, { { kind = "gems", amount = 5 } }, "test")
			c:Advance(0.5)
			local items = liveItems(c)
			expect(#items).toBe(2)
			expect(items[1].Name).toBe("Toast")
			expect(items[2].Name).toBe("FeedCard")
			expectClean(c)
		end)

		it("refreshes a repeated toast, keeps at most four and lets them leave with motion", function()
			local _, _, c = boot()
			c.kernel:Toast("Not enough coins", "error")
			c.kernel:Toast("Not enough coins", "error")
			c:Advance(0.1)
			expect(#liveItems(c)).toBe(1)
			for i = 1, 6 do
				c.kernel:Toast("Message " .. i, "info")
			end
			c:Advance(0.05)
			expect(#liveItems(c)).toBe(4)
			local first = liveItems(c)[1]
			expect(c:HasText("Message 6", c.kernel.UI.Feedback)).toBe(true)
			-- Leaving: marked at once, shrunk by its UIScale, gone a moment later.
			c:Advance(2.6)
			expect(first:GetAttribute("Leaving")).toBe(true)
			expect(first:FindFirstChild("AnimScale") ~= nil).toBe(true)
			c:Advance(0.5)
			expect(#c.kernel.UI.Feedback.Toasts:GetChildren()).toBe(1) -- the list layout only
			expectClean(c)
		end)

		it("shakes a locked HUD button inside its layout by rotating it", function()
			local _, _, c = boot()
			local market = c.kernel:GetController("Hud"):GetTarget("Market")
			local position = market.Position
			c:Click(market)
			c:Advance(0.05)
			expect(market.Rotation ~= 0).toBe(true)
			expect(market.Position).toBe(position)
			c:Advance(0.5)
			expect(market.Rotation).toBe(0)
			expect(market:GetAttribute("AnimShaking")).toBe(nil)
			expectClean(c)
		end)
	end)

	describe("Moment queue", function()
		it("holds a moment while a screen is open and plays it once the view clears", function()
			local _, _, c = boot()
			local kit = c.kernel:GetController("Celebrate")
			local played = 0
			kit:Moment("test", function()
				played += 1
			end)
			c:Advance(0.6)
			expect(played).toBe(1)

			c:Open("Monsters")
			c:Advance(0.2)
			expect(kit:IsCovered()).toBe(true)
			for _ = 1, 3 do
				kit:Moment("again", function()
					played += 1
				end)
			end
			c:Advance(0.05)
			expect(#c.kernel.UI.Feedback.Celebrate:GetChildren()).toBeGreaterThan(0) -- the stand-in sparkle
			c:Advance(3)
			expect(played).toBe(1)
			expect(kit:Pending()).toBe(1) -- same key: one moment
			c:Close("Monsters")
			c:Advance(1.5)
			expect(played).toBe(2)
			expect(kit:Pending()).toBe(0)
			expectClean(c)
		end)

		it("holds the hatch burst under the hatch reveal until it is closed", function()
			local _, _, c = boot()
			c:Advance(9)
			local kit = c.kernel:GetController("Celebrate")
			local incubators = c:Open("Incubators")
			c:Click(c:Button("Choose!", incubators))
			c:Advance(0.5)
			local top = c.kernel.UI.Top
			c:Click(c:Button("Choose", top:FindFirstChild("Choices", true):FindFirstChild("mossbun")))
			c:Advance(5)
			expect(c.kernel:GetController("Hatchery"):IsShowing()).toBe(true)
			expect(kit:Pending()).toBe(1)
			c:Click(c:Button("Nice!", top))
			c:Advance(2)
			-- The Incubators screen still covers the ranch; the burst waits for it too.
			expect(kit:Pending()).toBe(if c.kernel.Router:Current() then 1 else 0)
			c:Close()
			c:Advance(2)
			expect(kit:Pending()).toBe(0)
			expectClean(c)
		end)
	end)

	describe("Rewards that travel", function()
		it("flies coins into the held counter, which counts up as they land", function()
			local h, p, c = boot()
			local before = c:Store("profile.Currency.coins")
			h:System("Rewards"):Grant(p, { { kind = "coins", amount = 5000 } }, "test")
			c:Advance(0.3)
			expect(flyingIcons(c)).toBeGreaterThan(0)
			expect(pillText(c, "coins")).toBe(Format.short(before))
			c:Advance(3)
			expect(pillText(c, "coins")).toBe(Format.short(before + 5000))
			expect(flyingIcons(c)).toBe(0)
			expect(#c.kernel.UI.Feedback.Celebrate:GetChildren()).toBe(0) -- every piece cleaned up
			expectClean(c)
		end)

		it("keeps the counter and a short cue but no swarm in low graphics", function()
			local h, p, c = boot()
			local Anim = c:require(c.clientFolder.UI.Anim)
			Anim.enabled = false
			local before = c:Store("profile.Currency.coins")
			h:System("Rewards"):Grant(p, { { kind = "coins", amount = 300 } }, "test")
			c:Advance(0.2)
			expect(flyingIcons(c)).toBe(0)
			expect(c.kernel.UI.Feedback.Celebrate:FindFirstChild("Amount") ~= nil).toBe(true)
			c:Advance(1.5)
			expect(pillText(c, "coins")).toBe(Format.short(before + 300))
			expect(#c.kernel.UI.Feedback.Celebrate:GetChildren()).toBe(0)
			expectClean(c)
		end)

		it("caps the flying icons and adds a shower, confetti, FOV kick and rumble for huge", function()
			local _, _, c = boot()
			c:UseGamepad(true)
			local kit = c.kernel:GetController("Celebrate")
			local camera = c.world.workspace.CurrentCamera
			local fov = camera.FieldOfView
			for _ = 1, 4 do
				kit:Reward({ { kind = "coins", amount = 1e9 }, { kind = "gems", amount = 1000 } })
			end
			c:Advance(0.2)
			expect(flyingIcons(c)).toBeAtLeast(1)
			expect(flyingIcons(c) <= 24).toBe(true)
			expect(camera.FieldOfView).toBeGreaterThan(fov)
			local motors = c.world.input.motors
			expect(motors ~= nil and motors.Gamepad1 ~= nil and motors.Gamepad1.Large > 0).toBe(true)
			c:Advance(4)
			expect(camera.FieldOfView).toBe(fov)
			expect(motors.Gamepad1.Large).toBe(0)
			expect(#c.kernel.UI.Feedback.Celebrate:GetChildren()).toBe(0)
			expectClean(c)
		end)

		it("holds a counter against Store updates until released, and survives Collect all", function()
			local h, p, c = boot()
			local Currency = h:System("Currency")
			local hud = c.kernel:GetController("Hud")
			local kit = c.kernel:GetController("Celebrate")
			-- A held counter ignores the Store until it is released.
			local hold = kit:Hold({ "coins" })
			local before = c:Store("profile.Currency.coins")
			Currency:Add(p, "coins", 777, "test")
			c:Advance(1)
			expect(pillText(c, "coins")).toBe(Format.short(before))
			hold:Release()
			c:Advance(1)
			expect(pillText(c, "coins")).toBe(Format.short(before + 777))
			c:Click(hud:GetTarget("jar"))
			c:Advance(3)
			expectClean(c)
		end)
	end)

	describe("Stampede call", function()
		it("announces the lobby and the horn to everyone with a banner and a HUD glow", function()
			local START = 1000000 * Config.Boss.Period
			local h, p, c = boot({ startTime = START - Config.Boss.LobbySeconds - 5 })
			local stampede = c.kernel:GetController("Stampede")
			expect(stampede:Banner()).toBe(nil)
			c:Advance(7)
			local banner = stampede:Banner()
			expect(banner ~= nil).toBe(true)
			expect(banner:IsDescendantOf(c.kernel.UI.Feedback)).toBe(true)
			expect(c:HasText("The Stampede is coming!", banner)).toBe(true)
			expect(c:Button("Join", banner)).toBe(nil) -- below the Boss unlock
			levelTo(h, p, Config.Unlocks.Levels and Config.Unlocks.Levels.boss or 4)
			c:Advance(Config.Boss.LobbySeconds)
			banner = stampede:Banner()
			expect(banner ~= nil).toBe(true)
			expect(c:HasText("The Stampede is here!", banner)).toBe(true)
			local card = c.kernel:GetController("Hud"):GetTarget("stampede")
			expect(c:HasText("STAMPEDE LIVE!", card)).toBe(true)
			expect(card:FindFirstChildOfClass("UIStroke").Color).toBe(t.Roblox.Color3.fromHex("#FFD447"))
			c:Click(c:Button("Join", banner))
			c:Advance(0.5)
			expect(c.kernel.Router:IsOpen("Boss")).toBe(true)
			expect(stampede:Banner()).toBe(nil)
			expectClean(c)
		end)
	end)
end
