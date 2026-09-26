--[[
	PostcardsClient (glow-up X): the postcard played through the real client (ClientHarness).
	An expedition comes back, the postcard pops up with the squad's line, flips to the loot, goes
	to a friend through the picker, and the Album opens on its region with a static tile that
	reopens the card and a ★ that keeps it. Cards already in the album at load never pop up.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Postcards")

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

	local function befriend(h, a, b)
		h.adapters.friends[a] = h.adapters.friends[a] or {}
		h.adapters.friends[a][b] = true
		h.adapters.friends[b] = h.adapters.friends[b] or {}
		h.adapters.friends[b][a] = true
	end

	local function boot()
		local h = TestKernel.new({ systems = allSystems() })
		local p = h:Join(9601, "Ana")
		h:Section(p, "Quests").tutorial.step = #Config.Quests.Tutorial + 1
		h:System("Progression"):AddXP(p, 1e6, "test")
		h.kernel.Data:Get(p)._meta.playSeconds = Config.Community.Gifts.minPlaySeconds + 60
		local ids = {}
		for i = 1, 3 do
			local m = h:System("Monsters")
				:Create(p, { line = ({ "cindlet", "bubblin", "mossbun" })[i], rarity = 2, stage = 3 }, "test", true)
			table.insert(ids, m.id)
		end
		local c = ClientHarness.new(h, p)
		c:Advance(1)
		return h, p, c, ids
	end

	local function count(cards): number
		local n = 0
		for _ in cards or {} do
			n += 1
		end
		return n
	end

	describe("Postcards client", function()
		it("shows the postcard from a claimed expedition, flips it, sends it and opens the album", function()
			local h, p, c, ids = boot()
			local bo = h:Join(9602, "Bo")
			befriend(h, 9601, 9602)
			local controller = c.kernel:GetController("Postcards")
			controller.FriendSource = function()
				return { { userId = 9602, name = "Bo", online = true } }
			end
			expect(controller:Current()).toBe(nil)

			local ok = c:Request("Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "900", squad = ids })
			expect(ok).toBe(true)
			h:Section(p, "Expeditions").slots[1].endsAt = h.adapters.Clock.Now()
			c:Advance(2)
			local claimed, res = c:Request("Expeditions.Claim", { slot = 1 })
			expect(claimed).toBe(true)
			expect(#res.rewards > 0).toBe(true)
			c:Advance(1)

			-- The card pops up with the squad in its diorama and the handwritten line.
			local current = controller:Current()
			expect(current ~= nil).toBe(true)
			local card = c:Store("profile.Postcards.cards").c1
			local root = current.dialog.Root
			expect(c:IsShown(root)).toBe(true)
			local line = string.format(Logic.LineText(card.line, Config.Postcards), card.hero)
			expect(c:HasText(line, root)).toBe(true)
			expect(c:HasText("Whispering Meadow", root)).toBe(true)
			local diorama = root:FindFirstChild("Diorama", true)
			expect(diorama ~= nil and diorama:IsA("ViewportFrame")).toBe(true)
			local models = 0
			for _, d in diorama:GetDescendants() do
				if d:IsA("Model") and d.Parent and d.Parent:IsA("WorldModel") then
					models += 1
				end
			end
			expect(models).toBe(3)

			-- Flip: the back lists the loot.
			c:Click(c:Button("Flip", root))
			c:Advance(0.5)
			expect(current.view:IsFront()).toBe(false)
			expect(c:HasText("We brought home", root)).toBe(true)
			c:Click(c:Button("Flip", root))
			expect(current.view:IsFront()).toBe(true)

			-- ★ keeps it.
			c:Click(c:Button("☆", root))
			c:Advance(1)
			expect(h:Section(p, "Postcards").cards.c1.fav).toBe(true)

			-- Send to a friend through the picker.
			c:Click(c:Button("Send", root))
			c:Advance(0.5)
			local friendButton = c.kernel.UI.Top:FindFirstChild("Friend_9602", true)
			expect(friendButton ~= nil).toBe(true)
			c:Click(friendButton)
			c:Advance(1)
			expect(h:Section(p, "Postcards").totalSent).toBe(1)
			h:System("Market"):Sync(bo)
			local got = h:Section(bo, "Postcards").cards
			expect(count(got)).toBe(1)
			expect(got.c1.from).toBe("Ana")

			-- Album: closes the card, opens on the region, a static tile reopens it.
			c:Click(c:Button("Album", root))
			c:Advance(1)
			expect(controller:Current()).toBe(nil)
			local album = c:Screen("Album")
			expect(album ~= nil and c:IsShown(album)).toBe(true)
			local tile = album:FindFirstChild("Tile_c1", true)
			expect(tile ~= nil).toBe(true)
			expect(album:FindFirstChildWhichIsA("ViewportFrame", true)).toBe(nil)
			c:Click(tile:FindFirstChild("Open"))
			c:Advance(0.5)
			current = controller:Current()
			expect(current ~= nil).toBe(true)
			expect(c:Button("Album", current.dialog.Root)).toBe(nil) -- already in the album
			current.dialog.Close()
			c:Advance(0.5)
			expect(controller:Current()).toBe(nil)
			expectClean(c)
		end)

		it("never pops up the cards already in the album at load, and shows a friend's without a pop-up", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join(9611, "Cy")
			h:Section(p, "Quests").tutorial.step = #Config.Quests.Tutorial + 1
			local m = h:System("Monsters"):Create(p, { line = "cindlet", rarity = 1, stage = 1 }, "test", true)
			h:System("Postcards"):Record(p, { region = "coral", stage = 1, squad = { m.id }, loot = {} })
			local again = h:Rejoin(p, 60) -- a later session: the card is part of the loaded album
			local c = ClientHarness.new(h, again)
			c:Advance(1)
			local controller = c.kernel:GetController("Postcards")
			expect(controller:Current()).toBe(nil)
			-- A friend's postcard arrives by mail: a toast, no pop-up.
			h:System("Market"):Send(nil, 9611, {
				id = "postcard:77:c1",
				kind = "postcard",
				card = { region = "coral", stage = 1, squad = { { line = "bubblin", form = "bubblin", stage = 1 } }, loot = {} },
				from = 77,
				fromName = "Dee",
			})
			h:System("Market"):Sync(again)
			c:Advance(1)
			expect(controller:Current()).toBe(nil)
			expect(count(c:Store("profile.Postcards.cards"))).toBe(2)
			local album = c:Open("Album", { region = "coral" })
			c:Advance(0.5)
			expect(c:HasText("From Dee", album)).toBe(true)
			expect(c:HasText("Postcards 2 / ", album)).toBe(true)
			expectClean(c)
		end)
	end)
end
