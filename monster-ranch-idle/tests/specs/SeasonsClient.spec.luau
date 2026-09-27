--[[
	SeasonsClient (update 3.11 · Ranch Seasons): the season through the real client
	(ClientHarness): the ground tint and the season's ambient particles, the HUD countdown chip to
	the next season, the Guestbook's favourite-category line, and the Kitchen's seasonal hints.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Seasons = t.Shared("Logic.Seasons")

	local SEPT_27 = 1790510400 -- Sunday 27 Sep 2026, 12:00 UTC: autumn
	local AUTUMN_ENDS = Seasons.At(SEPT_27).endsAt
	local HOUR = 3600

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

	local function boot(at: number)
		local h = TestKernel.new({ systems = allSystems(), startTime = at })
		local p = h:Join()
		local F = Config.Unlocks.Features
		levelTo(h, p, math.max(F.kitchen or 1, F.fishing or 1, F.tourists or 1))
		local c = ClientHarness.new(h, p)
		c:Advance(3)
		return h, p, c
	end

	local function emitterRates(c)
		local part = c.world.workspace:FindFirstChild("SeasonEmitter")
		expect(part ~= nil).toBe(true)
		local rates = {}
		for _, e in part:GetChildren() do
			rates[string.gsub(e.Name, "^Season_", "")] = e.Rate
		end
		return rates
	end

	local function expectGround(c, season: string)
		local world = c.world.workspace:FindFirstChild("World")
		local ground = world and world:FindFirstChild("Ground")
		expect(ground ~= nil).toBe(true)
		local want = c.globals.Color3.fromHex(Config.Seasons.ById[season].ground)
		local got = ground.Color
		expect(math.abs(got.R - want.R) + math.abs(got.G - want.G) + math.abs(got.B - want.B) < 1e-4).toBe(true)
	end

	describe("Ranch Seasons on the client", function()
		it("shows autumn: falling leaves, the autumn grass, the Winter chip, the Guestbook line and Kitchen hints", function()
			local h, p, c = boot(AUTUMN_ENDS - 3 * HOUR)
			local rates = emitterRates(c)
			expect(rates.leaves > 0).toBe(true)
			expect(rates.snow).toBe(0)
			expect(rates.petals).toBe(0)
			expectGround(c, "autumn")

			-- The HUD chip counts down to winter.
			local chips = c.kernel.UI.Hud:FindFirstChild("EventChips", true)
			expect(chips ~= nil).toBe(true)
			local winterChip = nil
			for _, chip in chips:GetChildren() do
				if chip:IsA("TextButton") and c:IsShown(chip) and chip:FindFirstChild("Label").Text == "Winter" then
					winterChip = chip
				end
			end
			expect(winterChip ~= nil).toBe(true)
			expect(string.match(winterChip:FindFirstChild("Time").Text, "^2:5%d:%d%d$") ~= nil).toBe(true)

			-- The Events screen lists the running season and the next one.
			local events = c:Open("Events")
			c:Advance(0.5)
			expect(events:FindFirstChild("Row_season:" .. Seasons.At(SEPT_27).startsAt, true) ~= nil).toBe(true)
			expect(events:FindFirstChild("Row_season:" .. AUTUMN_ENDS, true) ~= nil).toBe(true)
			c.kernel.Router:Close("Events")
			c:Advance(0.5)

			local book = c:Open("Guestbook")
			c:Advance(0.5)
			expect(book:FindFirstChild("SeasonLove", true).Text).toBe("This season tourists love: Variety")
			c.kernel.Router:Close("Guestbook")
			c:Advance(0.5)

			h:Section(p, "Fishing").fish = { maple_carp = 1, minnow = 1 }
			h:System("Currency"):Add(p, "food.savory", 10, "test")
			h:System("Currency"):Add(p, "food.spicy", 10, "test")
			-- The Kitchen's session fish count refreshes on a catch.
			h.kernel.Bus:Publish("FishCaught", p, { fish = "minnow", rarity = "common", weight = 0.1, seasonal = false })
			h:System("Fishing"):SpendFish(p, 0) -- marks the bucket dirty so the client sees it
			c:Advance(1)
			local kitchen = c:Open("Kitchen")
			c:Advance(0.5)
			local maple = kitchen:FindFirstChild("Recipe_maple_glazed_carp", true)
			expect(maple:FindFirstChild("SeasonHint", true).Text).toBe("In season: Autumn")
			local chowder = kitchen:FindFirstChild("Recipe_frost_chowder", true)
			expect(chowder:FindFirstChild("SeasonHint", true).Text).toBe("Back in Winter")
			expect(kitchen:FindFirstChild("Recipe_berry_pie", true):FindFirstChild("SeasonHint", true)).toBe(nil)
			-- Out of season: the Cook button does nothing.
			c:Click(chowder:FindFirstChild("Cook_frost_chowder", true))
			c:Advance(0.5)
			for _, slot in h:Section(p, "Kitchen").slots do
				expect(slot.recipe).toBe(false)
			end
			-- The recipe list redraws on every store change: find the card again.
			maple = kitchen:FindFirstChild("Recipe_maple_glazed_carp", true)
			c:Click(maple:FindFirstChild("Cook_maple_glazed_carp", true))
			c:Advance(0.5)
			expect(#(c.failedRequests or {})).toBe(0)
			expect(h:Section(p, "Kitchen").slots[1].recipe).toBe("maple_glazed_carp")
			expect(h:Section(p, "Fishing").fish.maple_carp).toBe(nil)
			expectClean(c)
		end)

		it("shows winter: snow, the winter grass and the winter recipe in season", function()
			local _, _, c = boot(AUTUMN_ENDS + HOUR)
			local rates = emitterRates(c)
			expect(rates.snow > 0).toBe(true)
			expect(rates.leaves).toBe(0)
			expectGround(c, "winter")
			local kitchen = c:Open("Kitchen")
			c:Advance(0.5)
			local chowder = kitchen:FindFirstChild("Recipe_frost_chowder", true)
			expect(chowder:FindFirstChild("SeasonHint", true).Text).toBe("In season: Winter")
			local book = c:Open("Guestbook")
			c:Advance(0.5)
			expect(book:FindFirstChild("SeasonLove", true).Text).toBe("This season tourists love: Rare monsters")
			expectClean(c)
		end)
	end)
end
