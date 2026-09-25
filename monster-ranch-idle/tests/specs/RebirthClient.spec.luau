--[[
	RebirthClient (update 1.4): the Rebirth screen, the skill tree and the Spring Bloom egg
	hunt, driven through the real client (ClientHarness) like a player would.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local R = Config.Rebirth

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

	-- Clicks the dialog button whose text is exactly `text` (the dialog's backdrop is a button
	-- too, and its title contains "Rebirth").
	local function clickDialogButton(c, text: string)
		local button
		for _, b in c:Buttons(c.kernel.UI.Top) do
			if ClientHarness.buttonText(b) == text then
				button = b
			end
		end
		if not button then
			error("no dialog button " .. text .. "; top shows: " .. table.concat(c:Texts(c.kernel.UI.Top), " | "), 2)
		end
		c:Click(button)
	end

	describe("Rebirth client", function()
		it("shows the locked screen before Ranch Level 40", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Rebirth")
			c:Advance(1)
			expect(c:HasText("Unlocks at Ranch Level 40", screen)).toBe(true)
			c:Close("Rebirth")
			expectClean(c)
		end)

		it("learns a skill and rebirths with two Heirlooms through the UI", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 40)
			local Monsters = h:System("Monsters")
			local keepA = Monsters:Create(p, { line = "cindlet", rarity = 3, stage = 3 }, "test", true)
			local keepB = Monsters:Create(p, { line = "bubblin", rarity = 2 }, "test", true)
			local gone = Monsters:Create(p, { line = "mossbun", rarity = 4, stage = 2 }, "test", true)
			local Currency = h:System("Currency")
			Currency:Add(p, "stardust", 100, "test")
			local c = ClientHarness.new(h, p)
			c:Advance(1)

			local screen = c:Open("Rebirth")
			c:Advance(1)
			expect(c:HasText("Stardust skill tree", screen)).toBe(true)
			expect(c:HasText("Golden Touch  0/5", screen)).toBe(true)
			expect(c:HasText("🔒 Learn Golden Touch", screen)).toBe(true)
			expect(c:HasText("🔒 Learn Deep Pockets", screen)).toBe(true)
			local rebirthButton = screen:FindFirstChild("RebirthButton", true)
			expect(c:HasText("Save up 50M coins", rebirthButton)).toBe(true)

			-- Skill tree: Golden Touch level 1.
			c:Click(screen:FindFirstChild("Skill_golden_touch", true):FindFirstChild("Buy"))
			c:Advance(1)
			expect(h:Section(p, "Rebirth").skills.golden_touch).toBe(1)
			expect(c:HasText("Golden Touch  1/5", screen)).toBe(true)

			-- Enough coins: pick two Heirlooms and confirm.
			Currency:Add(p, "coins", R.CoinsNeeded(0), "test")
			c:Advance(1)
			expect(c:HasText("Choose Heirlooms (up to 3)", rebirthButton)).toBe(true)
			c:Click(rebirthButton)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Monsters")
			local monsters = c:Screen("Monsters")
			for _, id in { keepA.id, keepB.id } do
				local cell = monsters:FindFirstChild(id, true)
				expect(cell ~= nil).toBe(true)
				c:Click(cell:FindFirstChild("Tap"))
				c:Advance(0.2)
			end
			c:Click(c:Button("Confirm (2)", monsters))
			c:Advance(1)
			expect(c:HasText("Rebirth for Rebirth Star 1?", c.kernel.UI.Top)).toBe(true)
			local dust = R.DustFor(h:Section(p, "Monsters").list[gone.id])
			expect(c:HasText(string.format("%d Stardust", dust), c.kernel.UI.Top) or dust == 0).toBe(true)
			clickDialogButton(c, "Rebirth")
			c:Advance(1)

			expect(h:Section(p, "Rebirth").stars).toBe(1)
			expect(h:Section(p, "Monsters").list[gone.id]).toBeNil()
			expect(h:Section(p, "Monsters").list[keepA.id] ~= nil).toBe(true)
			expect(h:Section(p, "Ranch").pens[1].theme).toBe("starfield")
			local screen2 = c:Open("Rebirth")
			c:Advance(1)
			expect(c:HasText("★ 1 Rebirth Star · coins ×1.5", screen2)).toBe(true)
			c:Close("Rebirth")

			-- The Hall of Fame links here.
			local hall = c:Open("HallOfFame")
			c:Advance(0.5)
			c:Click(hall:FindFirstChild("RebirthLink", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Rebirth")
			c:Close("Rebirth")
			expectClean(c)
		end)
	end)

	describe("Egg hunt client", function()
		it("draws this round's eggs and picks one up", function()
			local BLOOM = Config.Events.ById.springbloom
			local h = TestKernel.new({ systems = allSystems(), startTime = BLOOM.startsAt + 3600 })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(2)
			local spots = h:Client(p).global.EggHunt.spots
			local folder = c.world.workspace:FindFirstChild("EggHunt")
			expect(folder ~= nil).toBe(true)
			expect(#folder:GetChildren()).toBe(#spots)
			local egg = folder:FindFirstChild("HuntEgg" .. spots[1])
			expect(egg ~= nil).toBe(true)

			-- The server checks where the (server-side) character stands.
			local pos = Config.EggHunt.Spots[spots[1]]
			p.Character = { HumanoidRootPart = { Position = { X = pos[1], Y = pos[2], Z = pos[3] } } }
			local before = h:System("Currency"):Balance(p, "token.springbloom")
			c:Trigger(egg:FindFirstChild("PickUp", true))
			c:Advance(1)
			expect(h:System("Currency"):Balance(p, "token.springbloom")).toBe(before + Config.EggHunt.Reward)
			expect(folder:FindFirstChild("HuntEgg" .. spots[1])).toBeNil()
			expect(#folder:GetChildren()).toBe(#spots - 1)
			expectClean(c)
		end)
	end)
end
