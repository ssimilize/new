--[[
	Tourists (update 3.10 · Ranch life): Ranch Tourists on the server. Appeal scoring, stars and
	tips (Logic/Tourists), the visit cadence on the server clock, pay by stars, the offline cap and
	its Welcome Back line, the Guestbook cap, the unlock gate, the weekly goal and the Appeal stars
	on the Visits snapshot.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Tourists")
	local VisitsLogic = t.Shared("Logic.Visits")

	local Rules = Config.Tourists
	local HOUR = 3600

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Ranch", "Decor", "Tourists" }

	local function boot(level: number?, extra: { string }?)
		local systems = table.clone(SYSTEMS)
		for _, name in extra or {} do
			table.insert(systems, name)
		end
		local h = TestKernel.new({ systems = systems })
		local p = h:Join()
		levelTo(h, p, level or 11)
		h:Advance(Rules.Interval) -- the slot the unlock landed in passes quietly
		return h, p
	end

	-- Moves to just past this player's next tourist.
	local function nextVisit(h, p)
		local now = h.adapters.Clock.Now()
		h:Advance(Logic.NextAt(p.UserId, now) - now + 6)
	end

	local function layoutOf(kinds: { string }, count: number)
		local byKind = {}
		for _, d in Config.Decor.List do
			byKind[d.kind] = byKind[d.kind] or d.id
		end
		local list = {}
		for i = 1, count do
			local kind = kinds[(i - 1) % #kinds + 1]
			table.insert(list, { id = byKind[kind], x = i, z = 0, rot = 0 })
		end
		return list
	end

	describe("Appeal", function()
		it("scores an empty ranch low and a full one 100, with stars from the score", function()
			local empty = Logic.Appeal({ layout = {}, level = 11, pens = { { capacity = 6, count = 0 } }, rarities = {}, codex = 0 })
			expect(empty.score).toBeLessThan(10)
			expect(empty.stars).toBe(1)
			expect(empty.tip).toBe("Place more decor around your ranch")

			local full = Logic.Appeal({
				layout = layoutOf(Rules.Kinds, 40),
				level = 60,
				pens = table.create(Config.Economy.Pens.max, { capacity = 6, count = 6 }),
				rarities = { 6, 6, 6, 1 },
				codex = Rules.CodexFull,
			})
			expect(full.score).toBe(100)
			expect(full.stars).toBe(5)
			expect(full.tip).toBe("Tourists love your ranch!")
			for _, c in Rules.Categories do
				expect(full.parts[c.id]).toBe(1)
			end

			expect(Logic.Stars(0)).toBe(1)
			expect(Logic.Stars(19)).toBe(1)
			expect(Logic.Stars(20)).toBe(2)
			expect(Logic.Stars(59)).toBe(3)
			expect(Logic.Stars(80)).toBe(5)
		end)

		it("raises each category with its own input and tips the weakest one", function()
			local base = {
				layout = layoutOf(Rules.Kinds, 40),
				level = 20,
				pens = { { capacity = 6, count = 6 } },
				rarities = { 6, 6, 6 },
				codex = 60,
			}
			local a = Logic.Appeal(base)
			-- Pens are the weakest (one pen of six): "Fill your pens".
			expect(a.tip).toBe("Fill your pens")
			local more = table.clone(base)
			more.pens = table.create(6, { capacity = 6, count = 6 })
			expect(Logic.Appeal(more).score).toBeGreaterThan(a.score)
			-- Decor: the piece count counts up to the Ranch Level cap (20 at level 1-9).
			expect(Logic.Appeal({ layout = layoutOf({ "fun" }, 20), level = 1 }).parts.decor).toBe(1)
			expect(Logic.Appeal({ layout = layoutOf({ "fun" }, 20), level = 60 }).parts.decor).toBe(0.5)
			-- Variety names the first kind missing.
			local noWater = { "light", "plant", "seat", "path", "fence", "arch", "statue", "toy", "fun" }
			local v = Logic.Appeal({
				layout = layoutOf({ "light" }, 40),
				level = 60,
				pens = table.create(6, { capacity = 6, count = 6 }),
				rarities = { 6, 6, 6 },
				codex = 60,
			})
			expect(v.tip).toBe("Try a water piece")
			expect(Logic.Appeal({ layout = layoutOf(noWater, 40), level = 60 }).parts.variety).toBe(1)
			-- Rarity: the rarest three pen monsters.
			expect(Logic.Appeal({ rarities = { 1, 1, 6, 6, 6 } }).parts.rarity).toBe(1)
			expect(Logic.Appeal({ rarities = { 3 } }).parts.rarity).toBeNear(1 / 6, 0.001)
			-- Every tip and review line is a Config text (translated by the catalogues).
			for _, kind in Rules.Kinds do
				expect(type(Rules.KindTips[kind].text)).toBe("string")
			end
		end)

		it("picks reviews from the strongest and weakest category, the same for the same slot", function()
			local appeal = Logic.Appeal({ layout = layoutOf(Rules.Kinds, 40), level = 60, pens = {}, rarities = {}, codex = 0 })
			local r = Logic.Review(77, 1234, appeal, 5)
			expect(r.good).toBe("decor")
			expect(r.bad == "pens" or r.bad == "rarity" or r.bad == "codex").toBe(true)
			expect(Rules.Praise[r.good][r.gi].text ~= nil).toBe(true)
			expect(Rules.Gripes[r.bad][r.bi].text ~= nil).toBe(true)
			local again = Logic.Review(77, 1234, appeal, 5)
			expect(again.who).toBe(r.who)
			expect(again.gi).toBe(r.gi)
			local perfect = Logic.Appeal({
				layout = layoutOf(Rules.Kinds, 40),
				level = 60,
				pens = table.create(6, { capacity = 6, count = 6 }),
				rarities = { 6, 6, 6 },
				codex = 60,
			})
			expect(Logic.Review(77, 1, perfect, 5).bad).toBe(false)
			-- A bare ranch: nothing is worth praising (the strongest part is under PraiseMin), only a gripe.
			local bare = Logic.Appeal({ layout = {}, level = 30, pens = { { capacity = 6, count = 1 } }, rarities = { 1 }, codex = 2 })
			local low = Logic.Review(77, 9, bare, 5)
			expect(low.good).toBe(false)
			expect(low.gi).toBe(0)
			expect(Rules.Gripes[low.bad][low.bi].text ~= nil).toBe(true)
		end)

		it("pays more for more stars", function()
			expect(Logic.Pay(1, 1)[1].seconds).toBe(Rules.SecondsPerStar)
			expect(Logic.Pay(5, 1)[1].seconds).toBe(5 * Rules.SecondsPerStar)
			expect(Logic.Pay(3, 6)[1].seconds).toBe(18 * Rules.SecondsPerStar)
			expect(Logic.StarText(3)).toBe("★★★☆☆")
		end)
	end)

	describe("Visits", function()
		it("sends one tourist a slot while online, pays coins and writes the Guestbook", function()
			local h, p = boot()
			local s = h:Section(p, "Tourists")
			local before = s.count
			expect(h:Session(p, "Tourists").unlocked).toBe(true)
			expect(h:Session(p, "Tourists").nextAt).toBe(Logic.NextAt(p.UserId, h.adapters.Clock.Now()))
			local seen = {}
			h.kernel.Bus:Subscribe("TouristVisited", function(_, detail)
				table.insert(seen, detail.stars)
			end)
			local coins = h:Section(p, "Currency").coins
			nextVisit(h, p)
			expect(s.count).toBe(before + 1)
			expect(#seen).toBe(1)
			expect(seen[1]).toBe(h:Session(p, "Tourists").stars)
			expect(h:Section(p, "Currency").coins).toBeGreaterThan(coins)
			expect(#s.book).toBe(before + 1)
			expect(s.book[1].stars).toBe(seen[1])
			local walk = h.kernel.State:GlobalRoot("Tourists").walk["u" .. p.UserId]
			expect(walk ~= nil).toBe(true)
			-- The next one comes exactly one interval later, not before.
			h:Advance(Rules.Interval - 30)
			expect(s.count).toBe(before + 1)
			h:Advance(40)
			expect(s.count).toBe(before + 2)
		end)

		it("pays by the ranch's stars", function()
			local h, p = boot()
			local R = h:System("Rewards")
			local granted = {}
			local original = R.Grant
			R.Grant = function(self, player, items, source, opts)
				if source == "tourists" then
					table.insert(granted, items[1].seconds)
				end
				return original(self, player, items, source, opts)
			end
			nextVisit(h, p)
			R.Grant = original
			expect(granted[1]).toBe(Rules.SecondsPerStar * h:Session(p, "Tourists").stars)
		end)

		it("pays at most six tourists for time away, with one Welcome Back line", function()
			local h, p = boot()
			local count = h:Section(p, "Tourists").count
			local lines = {}
			h.kernel.Bus:Subscribe("WelcomeItem", function(_, detail)
				if detail.kind == "tourists" then
					table.insert(lines, detail.text)
				end
			end)
			local coins = h:Section(p, "Currency").coins
			local p2 = h:Rejoin(p, 3 * HOUR)
			expect(h:Section(p2, "Tourists").count).toBe(count + Rules.AwayMax)
			expect(#lines).toBe(1)
			expect(lines[1]).toBe("6 tourists visited while you were away")
			expect(h:Section(p2, "Currency").coins).toBeGreaterThan(coins)

			-- One slot away: one tourist, the singular line.
			local now = h.adapters.Clock.Now()
			local wait = Logic.NextAt(p2.UserId, now) - now + 5
			local p3 = h:Rejoin(p2, wait)
			expect(h:Section(p3, "Tourists").count).toBe(count + Rules.AwayMax + 1)
			expect(lines[2]).toBe("A tourist visited while you were away")
		end)

		it("keeps the newest 20 reviews", function()
			local h, p = boot()
			local before = h:Section(p, "Tourists").count
			for _ = 1, 4 do
				p = h:Rejoin(p, 2 * HOUR)
			end
			local s = h:Section(p, "Tourists")
			expect(s.count).toBe(before + 4 * Rules.AwayMax)
			expect(#s.book).toBe(Rules.BookSize)
			expect(s.book[1].at >= s.book[#s.book].at).toBe(true)
		end)

		it("sends nobody before Ranch Level 11 and owes nothing for locked time", function()
			local h, p = boot(10)
			expect(h:Session(p, "Tourists").unlocked).toBe(false)
			expect(h:System("Tourists"):Stars(p)).toBe(0)
			h:Advance(2 * Rules.Interval)
			expect(h:Section(p, "Tourists").count).toBe(0)
			p = h:Rejoin(p, 2 * HOUR)
			expect(h:Section(p, "Tourists").count).toBe(0)
			levelTo(h, p, 11)
			h:Advance(5)
			expect(h:Section(p, "Tourists").count).toBe(0)
			nextVisit(h, p)
			expect(h:Section(p, "Tourists").count).toBe(1)
			expect(h:System("Tourists"):Stars(p)).toBeGreaterThan(0)
		end)

		it("follows placed decor into the appeal", function()
			local h, p = boot()
			local before = h:Session(p, "Tourists").parts.decor
			h:System("Shop"):AddDecor(p, "lantern", 1)
			local x, z = t.Shared("Logic.DecorLayout").FreeSpot({}, "lantern", 0, 20)
			h:Call(p, "Decor.Save", { layout = { { id = "lantern", x = x, z = z, rot = 0 } } })
			h:Advance(1)
			expect(h:Session(p, "Tourists").parts.decor).toBeGreaterThan(before)
		end)
	end)

	describe("Around the game", function()
		it("counts toward the weekly goal", function()
			local def = Config.Weekly.ById.tourists_15
			expect(def.family).toBe("tourists")
			expect(def.unlock).toBe("tourists")
			expect(def.topic).toBe("TouristVisited")
			local h, p = boot(11, { "Weekly" })
			local w = h:Section(p, "Weekly")
			w.goals = { { id = "tourists_15", progress = 0 } }
			nextVisit(h, p)
			expect(w.goals[1].progress).toBe(1)
		end)

		it("shows the Appeal stars on the Visits snapshot", function()
			local snap = VisitsLogic.Build(Config, { userId = 5, name = "Ann", pens = {} }, {}, 100, 4)
			expect(snap.stars).toBe(4)
			expect(VisitsLogic.Build(Config, { userId = 5, name = "Ann", pens = {} }, {}, 100).stars).toBe(0)
			expect(VisitsLogic.Sanitize(Config, { userId = 5, stars = 99 }).stars).toBe(5)
		end)
	end)
end
