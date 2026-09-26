--[[
	PurchasesClient: the Store delivers what it sells, driven through the real client.
	  - the Starter Pack card lists every item its config grants, and shows Owned once bought;
	  - the Ranch Pass can't be bought outside a season and says when the next goes on sale;
	  - VIP Rancher owners open a daily crate from the VIP card (odds shown first), which
	    arrives as the usual reward card, with a Store badge while it waits;
	  - the ChatTags controller stays dormant without TextChatService callbacks (the mock) and
	    tags VIP owners only.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local M = Config.Monetization

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

	-- Temporarily gives config items real ids; always restored.
	local function withIds(passIds: { [string]: number }, productIds: { [string]: number }, fn)
		local saved = {}
		for key, id in passIds do
			saved["pass." .. key] = M.PassByKey[key].gamePassId
			M.PassByKey[key].gamePassId = id
		end
		for key, id in productIds do
			saved["product." .. key] = M.ProductByKey[key].productId
			M.ProductByKey[key].productId = id
		end
		local ok, err = pcall(fn)
		for key in passIds do
			M.PassByKey[key].gamePassId = saved["pass." .. key]
		end
		for key in productIds do
			M.ProductByKey[key].productId = saved["product." .. key]
		end
		if not ok then
			error(err, 0)
		end
	end

	local function cardWith(c, root, text: string)
		for _, d in c:Descendants(root) do
			if d:IsA("TextLabel") and string.find(d.Text, text, 1, true) and c:IsShown(d) then
				return d.Parent
			end
		end
		return nil
	end

	-- Whether the HUD Store button's badge is up (nil when the button has none).
	local function storeBadge(c)
		for _, d in c:Descendants() do
			if d.Name == "Store" and d:IsA("GuiButton") then
				local badge = d:FindFirstChild("Badge")
				if badge then
					return badge.Visible
				end
			end
		end
		return nil
	end

	describe("Store: products deliver what they list", function()
		it("lists every Starter Pack item from config and shows Owned once bought", function()
			withIds({}, { starterPack = 7702 }, function()
				local h = TestKernel.new({ systems = allSystems() })
				local p = h:Join(7701)
				local c = ClientHarness.new(h, p)
				c:Advance(1)
				local screen = c:Open("Store", { tab = "gems" })
				c:Advance(0.5)
				local card = cardWith(c, screen, "Once per account")
				assert(card, "no Starter Pack card")
				local text = ""
				for _, s in c:Texts(card) do
					text ..= s .. "\n"
				end
				for _, item in M.ProductByKey.starterPack.grant do
					local name
					if item.kind == "egg" then
						name = Config.Eggs.ById[item.id].name
					elseif item.kind == "decor" then
						name = Config.Decor.ById[item.id].name
					elseif item.kind == "accessory" then
						name = Config.Accessories.ById[item.id].name
					elseif item.kind == "gems" then
						name = string.format("%d gems", item.amount)
					end
					assert(name, "unexpected Starter Pack item kind " .. item.kind)
					expect(text).toContain(name)
				end
				-- (The client loads its own Config, so the product shows "Coming soon" here.)
				expect(c:HasText("Owned", card)).toBe(false)

				h.adapters._processReceipt({ PlayerId = 7701, ProductId = 7702, PurchaseId = "sp1", CurrencySpent = 99 })
				c:Advance(1)
				card = cardWith(c, screen, "Once per account")
				expect(c:HasText("Owned", card)).toBe(true)
				expect(#c:Buttons(card)).toBe(0)
				expectClean(c)
			end)
		end)

		it("disables the Ranch Pass outside a season, with when the next goes on sale", function()
			withIds({}, { ranchPass = 7703 }, function()
				local S1 = Config.Quests.Seasons[1]
				local h = TestKernel.new({ systems = allSystems(), startTime = S1.startsAt - 3 * 86400 })
				local p = h:Join(7704)
				local c = ClientHarness.new(h, p)
				c:Advance(1)
				local screen = c:Open("Store", { tab = "gems" })
				c:Advance(0.5)
				expect(c:HasText("On sale in", screen)).toBe(true)
				local card = cardWith(c, screen, "Ranch Pass")
				assert(card, "no Ranch Pass card")
				expect(c:Button("R$", card)).toBeNil()

				-- The Quests screen agrees.
				c:Open("Quests", { tab = "pass" })
				c:Advance(0.5)
				expect(c:HasText("Pass on sale in", c:Screen("Quests"))).toBe(true)
				expectClean(c)
			end)
		end)
	end)

	describe("VIP Rancher crate", function()
		it("opens today's crate from the VIP card, once, with odds shown", function()
			withIds({ vip = 7710 }, {}, function()
				local h = TestKernel.new({ systems = allSystems() })
				h.adapters.ownedPasses[7711] = { [7710] = true }
				local p = h:Join(7711)
				local c = ClientHarness.new(h, p)
				c:Advance(1)
				expect(storeBadge(c)).toBe(true)

				local screen = c:Open("Store", { tab = "passes" })
				c:Advance(0.5)
				c:Click(c:Button("Crate odds", screen))
				c:Advance(0.5)
				local dialog = cardWith(c, nil, "Each crate holds")
				assert(dialog, "no crate odds dialog")
				local shown = c:Texts(dialog)
				local pcts = 0
				for _, s in shown do
					if string.match(s, "^%d+%%$") then
						pcts += 1
					end
				end
				expect(pcts).toBe(#M.VipCrate.table)

				local before = #h:Events(p, "Rewards.Granted")
				c:Click(c:Button("Open VIP crate", screen))
				c:Advance(1)
				local events = h:Events(p, "Rewards.Granted")
				expect(#events).toBe(before + 1)
				expect(events[#events].payload.source).toBe(M.VipCrate.source)
				expect(c:HasText("Opened today", screen)).toBe(true)
				expect(c:Button("Open VIP crate", screen)).toBeNil()
				expect(storeBadge(c)).toBe(false)
				expectClean(c)
			end)
		end)

		it("shows no crate button to players without the pass", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join(7712)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Store", { tab = "passes" })
			c:Advance(0.5)
			expect(c:Button("Open VIP crate", screen)).toBeNil()
			expect(c:Button("Crate odds", screen) ~= nil).toBe(true)
			expectClean(c)
		end)
	end)

	describe("VIP chat tag", function()
		it("stays dormant in the mock and tags only VIP owners", function()
			withIds({ vip = 7720 }, {}, function()
				local h = TestKernel.new({ systems = allSystems() })
				h.adapters.ownedPasses[7721] = { [7720] = true }
				local vip = h:Join(7721)
				local other = h:Join(7722)
				local c = ClientHarness.new(h, other)
				c:Advance(1)
				local tags = c.kernel:GetController("ChatTags")
				expect(tags:Installed()).toBe(false)
				expect(tags:PrefixFor(vip.UserId, "Vip:")).toContain(M.VipChatTag.text)
				expect(tags:PrefixFor(other.UserId, "Other:")).toBe("Other:")
				expectClean(c)
			end)
		end)
	end)
end
