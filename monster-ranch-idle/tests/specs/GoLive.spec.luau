-- Update 3.0.1 · Go live: Frostfall returns (event reruns), the Trading Hub finds its places by
-- name (and the hub place builds in hub mode), and the Workshop's budget, royalty ledger and
-- moderation queue.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, MockAdapters = t.TestKernel, t.MockAdapters
	local Config = t.Shared("Config")
	local Events = Config.Events
	local W = Config.Workshop
	local Hub = Config.TradingHub

	local FROST = Events.ById.frostfall
	local RERUN = FROST.reruns[1]

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	describe("Frostfall returns", function()
		it("runs again in its Year 2 window with the same id, token and content", function()
			expect(RERUN.startsAt).toBe(1829142000) -- Sat 18 Dec 2027, 15:00 UTC
			expect(RERUN.endsAt - RERUN.startsAt).toBe(28 * 86400)
			expect(Events.ActiveId(RERUN.startsAt - 1)).toBeNil()
			local e = Events.Active(RERUN.startsAt + 3600)
			expect(e.id).toBe("frostfall")
			expect(e.endsAt).toBe(RERUN.endsAt)
			expect(FROST.endsAt < RERUN.startsAt).toBe(true) -- the definition itself is untouched
			expect(Events.Active(FROST.startsAt + 3600).endsAt).toBe(FROST.endsAt)
			expect(Events.Next(Config.Regions.ById.dunes.opensAt).startsAt).toBe(RERUN.startsAt)
			expect(table.find(Config.Species.Pools.frostfall, "tinselkit") ~= nil).toBe(true)
			expect(#Config.Species.Pools.frostfall).toBe(4)
		end)

		it("sells the Frostfall Egg for Snowflakes again and redeems FROSTFALL27", function()
			local systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Events", "Quests" }
			local h = TestKernel.new({ systems = systems, startTime = RERUN.startsAt + 3600 })
			local p = h:Join()
			expect(h:Client(p).global.Events.id).toBe("frostfall")
			expect(h:Client(p).global.Events.endsAt).toBe(RERUN.endsAt)
			local before = h:Section(p, "Currency").tokens.frostfall or 0
			h:Call(p, "Quests.Redeem", { code = "frostfall27" })
			expect(h:Section(p, "Currency").tokens.frostfall).toBe(before + 150)
			h:System("Currency"):Add(p, "token.frostfall", 1000, "test")
			local bought = h:Call(p, "Shop.BuyEgg", { egg = "frostfall", amount = 1 })
			expect(#bought.eggs).toBe(1)
			local after = TestKernel.new({ systems = systems, startTime = RERUN.endsAt + 3600 })
			local q = after:Join()
			after:System("Currency"):Add(q, "token.frostfall", 1000, "test")
			expect(after:Reject(q, "Shop.BuyEgg", { egg = "frostfall", amount = 1 })).toBeTruthy()
			expect(after:Reject(q, "Quests.Redeem", { code = "FROSTFALL27" })).toBeTruthy()
		end)
	end)

	describe("Trading Hub go-live", function()
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Plots", "Trade", "TradingHub" }

		it("builds the hub place in hub mode from its own project file", function()
			local fs = require("@lune/fs")
			local serde = require("@lune/serde")
			local hub = serde.decode("json", fs.readFile(t.Root .. "/hub.project.json"))
			local main = serde.decode("json", fs.readFile(t.Root .. "/default.project.json"))
			expect(hub.tree.Workspace["$attributes"].PlaceMode).toBe("hub")
			expect(main.tree.Workspace["$attributes"]).toBeNil()
			-- Everything else is the same game.
			hub.tree.Workspace["$attributes"] = nil
			hub.name = main.name
			expect(hub).toEqual(main)
			expect(Hub.Mode(123, "hub")).toBe("hub")
			expect(Hub.Mode(123, nil)).toBe("main")
		end)

		it("finds both places by name in the universe, and says so when it can't", function()
			local net = MockAdapters.network()
			local main = TestKernel.new({ systems = SYSTEMS, network = net })
			local hub = TestKernel.new({ systems = SYSTEMS, network = net, placeMode = "hub" })
			local places = {
				{ name = "Monster Ranch Idle", placeId = 111 },
				{ name = "Trading Hub", placeId = 222 },
			}
			main.adapters.places = places
			hub.adapters.places = places
			local p = main:Join()
			local q = hub:Join()
			levelTo(main, p, 8)
			net.placesDown = true
			expect(main:Reject(p, "TradingHub.Travel")).toBe("The Trading Hub isn't open yet")
			net.placesDown = false
			main:Advance(4)
			main:Call(p, "TradingHub.Travel")
			expect(net.teleports[#net.teleports].placeId).toBe(222)
			hub:Call(q, "TradingHub.Return")
			expect(net.teleports[#net.teleports].placeId).toBe(111)
			-- Renamed start place: Return still finds a place that isn't the hub.
			local h2 = TestKernel.new({ systems = SYSTEMS, network = net, placeMode = "hub" })
			h2.adapters.places = { { name = "Trading Hub", placeId = 222 }, { name = "Monster Ranch: Winter", placeId = 333 } }
			local r = h2:Join()
			h2:Call(r, "TradingHub.Return")
			expect(net.teleports[#net.teleports].placeId).toBe(333)
			-- A pinned id wins.
			Hub.PlaceIds.Hub = 999
			local ok, err = pcall(function()
				main:Advance(4)
				main:Call(p, "TradingHub.Travel")
			end)
			Hub.PlaceIds.Hub = 0
			if not ok then
				error(err, 0)
			end
			expect(net.teleports[#net.teleports].placeId).toBe(999)
		end)
	end)

	describe("Workshop go-live", function()
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Accessories", "Workshop" }

		local function setup(net, userId: number, name: string)
			local h = TestKernel.new({ systems = SYSTEMS, network = net })
			local p = h:Join(userId, name)
			levelTo(h, p, 12)
			h:System("Currency"):Add(p, "ribbons", 400, "test")
			return h, p
		end

		local function design(h, p, name: string)
			local id = h:Call(p, "Workshop.Create", { name = name, shape = "crown", color = W.Palette[4], color2 = W.Palette[6] }).design
			h:Advance(3)
			return id
		end

		it("caches design records and lists so browsing stays inside the DataStore budget", function()
			local net = MockAdapters.network()
			local s1, maker = setup(net, 9101, "Maker")
			for i = 1, 3 do
				design(s1, maker, "Design " .. i)
			end
			local s2, fan = setup(net, 9102, "Fan")
			local reads = net.designReads
			s2:Call(fan, "Workshop.Browse", { tab = "new" })
			expect(#s2:Session(fan, "Workshop").gallery).toBe(3)
			expect(net.designReads - reads).toBe(3)
			s2:Advance(2)
			s2:Call(fan, "Workshop.Browse", { tab = "new" })
			local other = s2:Join(9103, "Other")
			s2:Call(other, "Workshop.Browse", { tab = "new" })
			expect(net.designReads - reads).toBe(3) -- everyone on the server shares the cache
			s2:Advance(W.CacheSeconds + 1)
			s2:Call(fan, "Workshop.Browse", { tab = "new" })
			expect(net.designReads - reads).toBe(6)
		end)

		it("keeps royalties in the designer's ledger and pays them in one claim", function()
			local net = MockAdapters.network()
			local s1, maker = setup(net, 9201, "Maker")
			local a = design(s1, maker, "Alpha Crown")
			local b = design(s1, maker, "Beta Crown")
			local s2, fan = setup(net, 9202, "Fan")
			s2:Call(fan, "Workshop.Buy", { design = a })
			s2:Advance(2)
			s2:Call(fan, "Workshop.Buy", { design = b })
			s2:Advance(2)
			s1:Call(maker, "Workshop.Buy", { design = a }) -- your own copies earn nothing
			expect(net.royalties[9201]).toBe(2 * W.Royalty)
			local ribbons = s1:Section(maker, "Currency").ribbons
			expect(s1:Call(maker, "Workshop.Claim").ribbons).toBe(2 * W.Royalty)
			expect(s1:Section(maker, "Currency").ribbons).toBe(ribbons + 2 * W.Royalty)
			expect(net.royalties[9201]).toBeNil()
			s1:Advance(3)
			expect(s1:Call(maker, "Workshop.Claim").ribbons).toBe(0)
			expect(net.designs[a].earned).toBe(W.Royalty) -- stats still count per design
		end)

		it("queues reported designs for moderators, who restore or remove them", function()
			local net = MockAdapters.network()
			local h, maker = setup(net, 9301, "Maker")
			local good = design(h, maker, "Nice Crown")
			local bad = design(h, maker, "Other Crown")
			for _, id in { good, bad } do
				for i = 1, W.ReportsToHide do
					local r = h:Join(9400 + i + (if id == bad then 10 else 0))
					h:Call(r, "Workshop.Report", { design = id })
				end
			end
			expect(net.reported).toEqual({ good, bad })
			expect(h:Reject(maker, "Workshop.ModQueue")).toBe("Only moderators can do that")

			table.insert(W.Moderators, 9500)
			local ok, err = pcall(function()
				local mod = h:Join(9500, "Mod")
				expect(h:Session(mod, "Workshop").moderator).toBe(true)
				h:Call(mod, "Workshop.ModQueue")
				local queue = h:Session(mod, "Workshop").queue
				expect(#queue).toBe(2)
				expect(queue[1].reports).toBe(W.ReportsToHide)
				h:Call(mod, "Workshop.Moderate", { design = good, verdict = "restore" })
				h:Call(mod, "Workshop.Moderate", { design = bad, verdict = "remove" })
				expect(#h:Session(mod, "Workshop").queue).toBe(0)
			end)
			table.remove(W.Moderators)
			if not ok then
				error(err, 0)
			end
			expect(#net.reported).toBe(0)
			expect(net.designs[good].hidden).toBe(false)
			expect(#net.designs[good].reports).toBe(0)
			expect(net.designs[bad].removed).toBe(true)
			expect(net.designs[bad].name).toBe("Removed design")
			local fan = h:Join(9600, "Fan")
			levelTo(h, fan, 12)
			h:System("Currency"):Add(fan, "ribbons", 100, "test")
			h:Call(fan, "Workshop.Browse", { tab = "new" })
			local ids = {}
			for _, v in h:Session(fan, "Workshop").gallery do
				table.insert(ids, v.id)
			end
			expect(ids).toEqual({ good })
			expect(h:Reject(fan, "Workshop.Buy", { design = bad })).toBe("That design isn't available")
		end)

		it("also accepts moderators by group rank", function()
			local net = MockAdapters.network()
			local h = TestKernel.new({ systems = SYSTEMS, network = net })
			W.ModeratorGroup.id = 4242
			h.adapters.ranks[9701] = { [4242] = 250 }
			h.adapters.ranks[9702] = { [4242] = 10 }
			local staff = h:Join(9701)
			local member = h:Join(9702)
			W.ModeratorGroup.id = 0
			expect(h:Session(staff, "Workshop").moderator).toBe(true)
			expect(h:Session(member, "Workshop").moderator).toBe(false)
		end)
	end)
end
