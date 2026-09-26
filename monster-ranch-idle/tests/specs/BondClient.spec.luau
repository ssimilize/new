--[[
	BondClient (glow-up Q): the care gestures played through the real client (ClientHarness).
	A tap on an own pen monster opens the Care screen (World's own-tap hook); Pet is a press and
	hold, Brush a drag back and forth, Play taps on the bounce, and a gamepad holds A. Each
	finished gesture raises the monster's bond once per kind; on cooldown it still plays and asks
	nothing. Then the learned trick, the heart on the monster card, the ranch-gate best friends
	and the pen nameplate.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local RobloxMock = require("../runtime/RobloxMock")
	local Roblox = t.Roblox
	local Enum = Roblox.Enum
	local Config = t.Shared("Config")
	local Cfg = Config.Bond
	local G = Cfg.Gesture

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

	local function pointer(c, target, event: string, kind, x: number)
		local input = RobloxMock.newInput(c.world, {
			UserInputType = kind,
			UserInputState = if event == "InputBegan"
				then Enum.UserInputState.Begin
				elseif event == "InputEnded" then Enum.UserInputState.End
				else Enum.UserInputState.Change,
			Position = Roblox.Vector3.new(x, 200, 0),
		})
		RobloxMock.fire(target, event, input)
		c:Settle()
	end

	local function points(h, p, id): number
		local entry = h:Section(p, "Bond").list[id]
		return if entry then entry.pts else 0
	end

	local function boot()
		local h = TestKernel.new({ systems = allSystems() })
		local p = h:Join()
		h:Section(p, "Quests").tutorial.step = #Config.Quests.Tutorial + 1
		local Monsters = h:System("Monsters")
		local a = Monsters:Create(p, { line = "cindlet", rarity = 1 }, "reward", true)
		local b = Monsters:Create(p, { line = "cindlet", rarity = 1 }, "reward", true)
		local c = ClientHarness.new(h, p)
		c:Advance(2)
		return h, p, c, a.id, b.id
	end

	local function openCare(c, id)
		local world = c.kernel:GetController("World")
		expect(world.OwnTapHandler(id)).toBe(true)
		c:Advance(0.5)
		local root = c:Screen("Care")
		expect(root ~= nil and c:IsShown(root)).toBe(true)
		return root
	end

	describe("Bond client", function()
		it("pets, brushes and plays through the Care screen and sees the hearts go up", function()
			local h, p, c, id = boot()
			local root = openCare(c, id)
			expect(c:HasText("♡♡♡♡♡♡♡♡♡♡", root)).toBe(true)
			local pad = root:FindFirstChild("CarePad")

			-- Pet: press and hold on the pad over the monster.
			c:Click(root:FindFirstChild("Care_pet", true))
			expect(c:IsShown(pad)).toBe(true)
			expect(c:HasText("Press and hold on it", root)).toBe(true)
			pointer(c, pad, "InputBegan", Enum.UserInputType.MouseButton1, 300)
			c:Advance(G.holdSeconds + 0.5)
			pointer(c, pad, "InputEnded", Enum.UserInputType.MouseButton1, 300)
			c:Advance(1)
			expect(points(h, p, id)).toBe(1)
			expect(c:IsShown(pad)).toBe(false)
			expect(c:HasText("♥♡♡♡♡♡♡♡♡♡", root)).toBe(true)

			-- Brush: drag back and forth across it (touch).
			c:Advance(Cfg.minGap)
			c:Click(root:FindFirstChild("Care_brush", true))
			pointer(c, pad, "InputBegan", Enum.UserInputType.Touch, 200)
			for i = 1, G.strokes + 1 do
				c:Advance(0.2)
				pointer(c, pad, "InputChanged", Enum.UserInputType.Touch, if i % 2 == 1 then 200 + G.strokePixels * 2 else 200)
			end
			pointer(c, pad, "InputEnded", Enum.UserInputType.Touch, 200)
			c:Advance(1)
			expect(points(h, p, id)).toBe(2)

			-- Play: tap each time it bounces.
			c:Advance(Cfg.minGap)
			c:Click(root:FindFirstChild("Care_play", true))
			expect(c:IsShown(pad:FindFirstChild("Beat"))).toBe(true)
			for _ = 1, G.taps do
				c:Advance(G.beat)
				pointer(c, pad, "InputBegan", Enum.UserInputType.Touch, 300)
				pointer(c, pad, "InputEnded", Enum.UserInputType.Touch, 300)
			end
			c:Advance(1)
			expect(points(h, p, id)).toBe(3)
			expect(c:Store("profile.Bond.list")[id].pts).toBe(3)
			expect(c:HasText("♥♥♡♡♡♡♡♡♡♡", root)).toBe(true)

			-- On cooldown the gesture still plays, but asks the server nothing.
			c:Advance(Cfg.minGap)
			local before = #(c.requests or {})
			c:Click(root:FindFirstChild("Care_pet", true))
			pointer(c, pad, "InputBegan", Enum.UserInputType.MouseButton1, 300)
			c:Advance(G.holdSeconds + 0.5)
			pointer(c, pad, "InputEnded", Enum.UserInputType.MouseButton1, 300)
			c:Advance(1)
			for i = before + 1, #(c.requests or {}) do
				expect(c.requests[i] ~= "Bond.Care").toBe(true)
			end
			expect(points(h, p, id)).toBe(3)
			expect(c.failedRequests == nil or #c.failedRequests == 0).toBe(true)

			-- Stop leaves a gesture without bond.
			c:Click(root:FindFirstChild("Care_brush", true))
			c:Click(c:Button("Stop", root))
			expect(c:IsShown(pad)).toBe(false)
			c:Close("Care")
			expectClean(c)
		end)

		it("gives a gamepad the hold version of every gesture", function()
			local h, p, c, _, id = boot()
			c:UseGamepad(true)
			local root = openCare(c, id)
			c:Click(root:FindFirstChild("Care_play", true))
			expect(c:HasText("Hold the button to care", root)).toBe(true)
			c:_input(Enum.KeyCode.ButtonA, Enum.UserInputState.Begin, Enum.UserInputType.Gamepad1)
			c:Advance(G.holdSeconds + 0.5)
			c:_input(Enum.KeyCode.ButtonA, Enum.UserInputState.End, Enum.UserInputType.Gamepad1)
			c:Advance(1)
			expect(points(h, p, id)).toBe(1)
			c:Press("ButtonB")
			c:Advance(0.5)
			expectClean(c)
		end)

		it("shows learned tricks, the card heart, best friends at the gate and a nameplate", function()
			local h, p, c, id = boot()
			h:Section(p, "Bond").list[id] = { pts = Cfg.HeartAt[Cfg.NameplateHearts] - 1 }
			local root = openCare(c, id)
			c:Click(root:FindFirstChild("Care_brush", true))
			pointer(c, root.CarePad, "InputBegan", Enum.UserInputType.MouseButton1, 100)
			for i = 1, G.strokes + 1 do
				c:Advance(0.2)
				pointer(
					c,
					root.CarePad,
					"InputChanged",
					Enum.UserInputType.MouseMovement,
					if i % 2 == 1 then 100 + G.strokePixels * 2 else 100
				)
			end
			c:Advance(2)
			expect(h:System("Bond"):Hearts(p, id)).toBe(Cfg.NameplateHearts)
			-- Learned tricks play through Community.Trick; the last one is still locked.
			c:Advance(Config.Community.TrickCooldown)
			c:Click(root:FindFirstChild("Trick_sit", true))
			c:Advance(1)
			expect(c.failedRequests == nil or #c.failedRequests == 0).toBe(true)
			expect(c:HasText(string.format("Show off ♥%d", Cfg.Tricks[3].bond), root)).toBe(true)
			c:Close("Care")
			-- The heart on the monster card.
			local grid = c:Open("Monsters")
			c:Advance(0.5)
			expect(c:HasText("♥" .. Cfg.NameplateHearts, grid)).toBe(true)
			c:Close("Monsters")
			-- Best friends over the ranch gate and a nameplate over the pen monster.
			c:Advance(2)
			local gate, plate = nil, nil
			for _, gui in c:Descendants(c.playerGui) do
				if gui:IsA("BillboardGui") and string.sub(gui.Name, 1, 11) == "BestFriends" then
					gate = gui
				elseif gui:IsA("BillboardGui") and gui.Name == "BondPlate" then
					plate = gui
				end
			end
			expect(gate ~= nil).toBe(true)
			expect(c:HasText("Best friends", gate)).toBe(true)
			expect(plate ~= nil and plate.Adornee ~= nil).toBe(true)
			expectClean(c)
		end)
	end)
end
