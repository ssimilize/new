-- Update 3.0 · Year Two: a new region every quarter (Mirage Dunes now, Frostbite Glacier on its
-- date), Monster Racing, the cross-server Trading Hub place (two hub servers share the Trade
-- Board) and the Workshop's player-made accessories (shared design store, royalties).
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, MockAdapters = t.TestKernel, t.MockAdapters
	local Config = t.Shared("Config")
	local Format = t.Shared("Logic.Format")
	local Rng = t.Shared("Logic.Rng")
	local RaceLogic = t.Shared("Logic.Racing")
	local RC = Config.Racing
	local W = Config.Workshop
	local Hub = Config.TradingHub

	local LAUNCH = Config.Regions.ById.dunes.opensAt
	local AFTER = LAUNCH + 3600

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function adult(h, p, line: string, rarity: number?)
		return h:System("Monsters"):Create(p, { line = line, rarity = rarity or 3, stage = 3 }, "test", true)
	end

	-- Plays a race well: jump just before each hurdle, boost whenever ready.
	local function autoplay(track, speed: number)
		local inputs = {}
		local state = RaceLogic.New(speed)
		for _ = 1, math.ceil(RC.MaxSeconds / RC.Step) do
			local h = track.hurdles[state.nextHurdle]
			local reach = speed * (if state.boost > 0 then RC.BoostMult else 1) * RC.JumpSeconds * 0.5
			if h and h - state.x <= reach and state.air <= 0 then
				table.insert(inputs, { t = state.t, a = "jump" })
			end
			if state.stamina >= RC.BoostCost and state.boost <= 0 then
				table.insert(inputs, { t = state.t, a = "boost" })
			end
			if RaceLogic.Step(track, state, inputs) then
				break
			end
		end
		return inputs, state.t
	end

	describe("A new region every quarter", function()
		it("opens Mirage Dunes on launch day and Frostbite Glacier a quarter later", function()
			local R = Config.Regions
			expect(Format.date(LAUNCH)).toBe("11 Dec 2027")
			expect(Format.date(R.ById.glacier.opensAt)).toBe("11 Mar 2028")
			expect(R.IsOpen("dunes", LAUNCH - 1)).toBe(false)
			expect(R.IsOpen("dunes", LAUNCH)).toBe(true)
			expect(R.IsOpen("meadow", 0)).toBe(true)
			expect(R.NextOpening(AFTER).id).toBe("glacier")
			expect(R.NextOpening(R.ById.glacier.opensAt)).toBeNil()
			expect(R.ById.glacier.opensAt - LAUNCH).toBe(91 * 86400)
			for _, id in { "dunes", "glacier" } do
				local r = R.ById[id]
				expect(Config.Eggs.ById[id].pool).toBe(id)
				-- Three lines at launch, and a fourth from update 3.3 (Pitling, Rimebug).
				local launch = 0
				for _, lineId in Config.Species.Pools[id] do
					if Config.Species.ById[lineId].added == "3.0" then
						launch += 1
					end
				end
				expect(launch).toBe(3)
				expect(#Config.Species.Pools[id]).toBe(4)
				for _, boss in r.bosses do
					expect(Config.Species.FormById[boss.form].line.id).toBe(boss.line)
				end
				for _, line in r.enemyLines do
					expect(Config.Species.ById[line] ~= nil).toBe(true)
				end
			end
		end)

		it("keeps a region closed until its date, then gates it by level", function()
			local h = TestKernel.new({
				systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Expeditions" },
				startTime = LAUNCH - 3600,
			})
			local p = h:Join()
			levelTo(h, p, 60)
			expect(h:Reject(p, "Expeditions.Fight", { region = "dunes", stage = 1 })).toBe("Mirage Dunes opens on 11 Dec 2027")
			h.adapters.setTime(AFTER)
			local low = h:Join()
			expect(h:Reject(low, "Expeditions.Fight", { region = "dunes", stage = 1 })).toBe("Mirage Dunes unlocks at Ranch Level 50")
			expect(h:Reject(p, "Expeditions.Fight", { region = "glacier", stage = 1 })).toBe("Frostbite Glacier opens on 11 Mar 2028")
			-- Open and unlocked: the only thing missing now is a squad.
			h:Advance(2)
			expect(h:Reject(p, "Expeditions.Fight", { region = "dunes", stage = 1 }) ~= "Mirage Dunes opens on 11 Dec 2027").toBe(true)
		end)
	end)

	describe("Monster Racing", function()
		it("builds the same track every time and replays moves the same way", function()
			local a = RaceLogic.Track(Rng.seed("racing", 800))
			local b = RaceLogic.Track(Rng.seed("racing", 800))
			expect(a).toEqual(b)
			expect(#a.hurdles > 0).toBe(true)
			for _, x in a.hurdles do
				expect(x > RC.StartClear and x < RC.Length).toBe(true)
			end
			local lazy = RaceLogic.Simulate(a, 15, {})
			expect(lazy.stumbles).toBe(#a.hurdles)
			local inputs, t15 = autoplay(a, 15)
			local good = RaceLogic.Simulate(a, 15, inputs)
			expect(good.stumbles).toBe(0)
			expect(good.time).toBe(t15)
			expect(good.time < lazy.time).toBe(true)
			expect(RaceLogic.Par(a)).toBe(t15) -- par is exactly this run at ParSpeed
			-- A faster monster finishes sooner with the same skill.
			local fastInputs = autoplay(a, 20)
			expect(RaceLogic.Simulate(a, 20, fastInputs).time < good.time).toBe(true)
			expect(RaceLogic.Valid({ { t = 2, a = "jump" }, { t = 1, a = "boost" } })).toBe(false)
			expect(RaceLogic.Valid({ { t = 1, a = "fly" } })).toBe(false)
			local ghosts = RaceLogic.Ghosts(a, 800)
			expect(#ghosts).toBe(#RC.GhostPace)
			expect(RaceLogic.Place(0, ghosts)).toBe(1)
			expect(RaceLogic.Place(999, ghosts)).toBe(4)
		end)

		it("races an Adult against the ghosts, pays places and Cup points, and caps paid races", function()
			local h = TestKernel.new({
				systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Quests", "Racing", "Leaderboards" },
				startTime = AFTER,
			})
			local p = h:Join()
			local m = adult(h, p, "zappip", 6)
			expect(h:Reject(p, "Racing.Start", { id = m.id })).toBe("Unlocks at Ranch Level 16")
			levelTo(h, p, 16)
			local baby = h:System("Monsters"):Create(p, { line = "zappip", rarity = 2 }, "test", true)
			expect(h:Reject(p, "Racing.Start", { id = baby.id })).toBe("Only Adults can race")
			h:Advance(4)

			local start = h:Call(p, "Racing.Start", { id = m.id })
			expect(start.speed).toBe(Config.Riding.SpeedFor(m) * RC.SpeedScale)
			local track = RaceLogic.Track(Rng.seed("racing", start.day))
			local inputs, time = autoplay(track, start.speed)
			-- Too fast on the wall clock: rejected.
			expect(h:Reject(p, "Racing.Finish", { race = start.race, inputs = inputs })).toBe("That race finished too quickly")

			local ribbons0 = h:Section(p, "Currency").ribbons
			h:Advance(4)
			start = h:Call(p, "Racing.Start", { id = m.id })
			h:Advance(time)
			local res = h:Call(p, "Racing.Finish", { race = start.race, inputs = inputs })
			expect(res.finished).toBe(true)
			expect(res.time).toBe(time)
			expect(res.place).toBe(1) -- a Mythic Zappip with clean jumps beats every ghost
			expect(res.cup).toBe(RC.CupPoints[1])
			expect(h:Section(p, "Currency").ribbons - ribbons0).toBe(RC.PlaceRewards[1][1].amount)
			local s = h:Section(p, "Racing")
			expect(s.wins).toBe(1)
			expect(s.best).toBe(time)
			expect(s.bestToday).toBe(time)
			expect(h:System("Racing"):CupPoints(p)).toBe(RC.CupPoints[1])
			expect(h:System("Leaderboards"):Value(p, "racing")).toBe(RC.CupPoints[1])
			expect(h:Section(p, "Quests").achievements.race_win_10.progress).toBe(1)

			-- Standing still: last place, and after the daily cap no more rewards.
			for _ = 2, RC.RewardedPerDay do
				local r = h:Call(p, "Racing.Start", { id = m.id })
				h:Advance(RC.MaxSeconds)
				h:Call(p, "Racing.Finish", { race = r.race, inputs = {} })
			end
			expect(h:Section(p, "Racing").rewarded).toBe(RC.RewardedPerDay)
			local r = h:Call(p, "Racing.Start", { id = m.id })
			h:Advance(RC.MaxSeconds)
			local late = h:Call(p, "Racing.Finish", { race = r.race, inputs = {} })
			expect(late.place).toBe(4)
			expect(#late.rewards).toBe(0)
			expect(late.cup).toBe(0)
			-- A new week resets the Cup.
			h:Advance(7 * 86400)
			expect(h:System("Racing"):CupPoints(p)).toBe(0)
		end)
	end)

	describe("Trading Hub", function()
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Quests", "Plots", "Trade", "TradingHub" }

		it("travels to the hub place and back, and gives nobody a plot there", function()
			local main = TestKernel.new({ systems = SYSTEMS })
			local net = MockAdapters.network()
			local hub = TestKernel.new({ systems = SYSTEMS, placeMode = "hub", network = net })
			local p = main:Join()
			expect(main:Reject(p, "TradingHub.Travel")).toBe("Unlocks at Ranch Level 8")
			levelTo(main, p, 8)
			main:Advance(4)
			expect(main:Reject(p, "TradingHub.Travel")).toBe("The Trading Hub isn't open yet")
			expect(main:Reject(p, "TradingHub.Return")).toBe("You're already on your ranch")
			main:Advance(4)
			Hub.PlaceIds.Hub, Hub.PlaceIds.Main = 222, 111
			local ok, err = pcall(function()
				expect(main:Call(p, "TradingHub.Travel").teleporting).toBe(true)
				local q = hub:Join()
				expect(hub:Client(q).global.TradingHub.mode).toBe("hub")
				expect(hub:System("Plots"):GetPlot(q)).toBeNil()
				hub:Call(q, "TradingHub.Return")
				expect(net.teleports[#net.teleports].placeId).toBe(111)
			end)
			Hub.PlaceIds.Hub, Hub.PlaceIds.Main = 0, 0
			if not ok then
				error(err, 0)
			end
			expect(main:Client(p).global.TradingHub.mode).toBe("main")
			expect(main:System("Plots"):GetPlot(p) ~= nil).toBe(true)
		end)

		it("shares ads across hub servers and meets traders here or on their server", function()
			local net = MockAdapters.network()
			local s1 = TestKernel.new({ systems = SYSTEMS, placeMode = "hub", network = net })
			local s2 = TestKernel.new({ systems = SYSTEMS, placeMode = "hub", network = net })
			local ann = s1:Join(6001, "Ann")
			local ben = s2:Join(6002, "Ben")
			local cal = s1:Join(6003, "Cal")
			for _, x in { { s1, ann }, { s2, ben }, { s1, cal } } do
				levelTo(x[1], x[2], 8)
			end
			local m = adult(s1, ann, "lumipup", 5)
			local egg = s1:System("Eggs"):Add(ann, "crystal", "test")[1]
			local posted = s1:Call(ann, "TradingHub.Post", {
				items = { { kind = "monster", id = m.id }, { kind = "egg", id = egg } },
				wants = { "mythic", "light" },
				note = 3,
			})
			expect(s1:Session(ann, "TradingHub").ad).toBe(posted.ad)
			expect(s1:Reject(ann, "TradingHub.Post", { items = { { kind = "monster", id = m.id } }, wants = {}, note = 1 })).toBe(
				"Wait 30 seconds before posting again"
			)

			s2:Call(ben, "TradingHub.Refresh")
			local ads = s2:Client(ben).global.TradingHub.ads
			expect(#ads).toBe(1)
			expect(ads[1].name).toBe("Ann")
			expect(ads[1].here).toBe(false)
			expect(ads[1].offer[1].appearance.line).toBe("lumipup")
			expect(ads[1].offer[2].egg).toBe("crystal")
			expect(ads[1].wants).toEqual({ "mythic", "light" })
			Hub.PlaceIds.Hub = 222
			local res = s2:Call(ben, "TradingHub.Meet", { ad = posted.ad })
			Hub.PlaceIds.Hub = 0
			expect(res.teleporting).toBe(true)
			local tp = net.teleports[#net.teleports]
			expect(tp.userId).toBe(6002)
			expect(tp.jobId).toBe(s1.adapters.JobId)

			s1:Call(cal, "TradingHub.Refresh")
			local here = s1:Call(cal, "TradingHub.Meet", { ad = posted.ad })
			expect(here.here).toBe(true)
			expect(here.userId).toBe(6001)
			expect(s1:Reject(ann, "TradingHub.Meet", { ad = posted.ad })).toBe("That's your own ad")
			expect(s1:Section(ann, "Quests").achievements.hub_ad.progress).toBe(1)

			-- Leaving takes the ad down on every server.
			s1:Leave(ann)
			s2:Advance(Hub.RefreshSeconds + 1)
			expect(#s2:Client(ben).global.TradingHub.ads).toBe(0)
		end)

		it("only posts from the hub and survives a board outage", function()
			local net = MockAdapters.network()
			local main = TestKernel.new({ systems = SYSTEMS, network = net })
			local hub = TestKernel.new({ systems = SYSTEMS, placeMode = "hub", network = net })
			local a = main:Join()
			local b = hub:Join()
			levelTo(main, a, 8)
			levelTo(hub, b, 8)
			local ma = adult(main, a, "zappip")
			local mb = adult(hub, b, "zappip")
			expect(main:Reject(a, "TradingHub.Post", { items = { { kind = "monster", id = ma.id } }, wants = {}, note = 1 })).toBe(
				"Post ads from the Trading Hub"
			)
			net.hubDown = true
			expect(hub:Reject(b, "TradingHub.Post", { items = { { kind = "monster", id = mb.id } }, wants = {}, note = 1 })).toBe(
				"The Trade Board is busy. Try again in a moment"
			)
			net.hubDown = false
			hub:Call(b, "TradingHub.Post", { items = { { kind = "monster", id = mb.id } }, wants = {}, note = 1 })
			-- The ranch's portal previews the same board.
			main:Call(a, "TradingHub.Refresh")
			expect(#main:Client(a).global.TradingHub.ads).toBe(1)
			-- Ads expire.
			hub:Advance(Hub.AdSeconds + Hub.RefreshSeconds)
			expect(#hub:Client(b).global.TradingHub.ads).toBe(0)
		end)
	end)

	describe("Workshop", function()
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Quests", "Accessories", "Shop", "Workshop" }

		local function design(h, p, name: string, shape: string?)
			return h:Call(p, "Workshop.Create", {
				name = name,
				shape = shape or "tophat",
				color = W.Palette[5],
				color2 = W.Palette[3],
			}).design
		end

		it("publishes a design, wears it and takes it off again", function()
			local net = MockAdapters.network()
			local h = TestKernel.new({ systems = SYSTEMS, network = net })
			local p = h:Join(7101, "Maker")
			local Currency = h:System("Currency")
			Currency:Add(p, "ribbons", 200, "test")
			local args = { name = "Sunny Topper", shape = "tophat", color = W.Palette[5], color2 = W.Palette[3] }
			expect(h:Reject(p, "Workshop.Create", args)).toBe("Unlocks at Ranch Level 12")
			levelTo(h, p, 12)
			h:Advance(2)
			expect(h:Reject(p, "Workshop.Create", { name = "badword hat", shape = "tophat", color = W.Palette[1], color2 = W.Palette[1] })).toBe(
				"That name isn't allowed"
			)
			h:Advance(2)
			expect(h:Reject(p, "Workshop.Create", { name = "ab", shape = "tophat", color = W.Palette[1], color2 = W.Palette[1] })).toBe(
				"Names must be 3 to 20 characters"
			)
			h:Advance(2)
			local id = h:Call(p, "Workshop.Create", args).design
			expect(id).toBe("7101x1")
			expect(h:Section(p, "Currency").ribbons).toBe(200 - W.SubmitCost.ribbons)
			expect(net.designs[id].slot).toBe("head")
			expect(h:Section(p, "Workshop").copies[id].n).toBe(1)
			expect(h:Section(p, "Quests").achievements.design_first.progress).toBe(1)

			local m = adult(h, p, "zappip")
			h:Call(p, "Workshop.Equip", { id = m.id, design = id })
			local worn = h:System("Monsters"):Get(p, m.id).acc.head
			expect(worn).toBe(Config.Accessories.Encode(id, "tophat", W.Palette[5], W.Palette[3]))
			local def = Config.Accessories.Resolve(worn)
			expect(def.ugc).toBe(true)
			expect(def.shape).toBe("tophat")
			expect(def.color).toBe(W.Palette[5])
			expect(h:Section(p, "Workshop").copies[id].n).toBe(0)
			expect(h:Reject(p, "Workshop.Equip", { id = m.id, design = id })).toBe("You don't have a spare copy of that design")
			-- The Contest judge counts it like any worn accessory (tags from its shape).
			local theme = Config.Contests.Themes[1]
			expect(Config.Contests.JudgeScore({ head = worn }, theme) > Config.Contests.JudgeScore({}, theme)).toBe(true)

			-- Swapping in a catalogue item returns the design to storage.
			h:System("Accessories"):Add(p, "sprout_cap", 1)
			h:Call(p, "Accessories.Equip", { id = m.id, accessory = "sprout_cap" })
			expect(h:Section(p, "Workshop").copies[id].n).toBe(1)
			h:Call(p, "Workshop.Equip", { id = m.id, design = id })
			expect(h:Section(p, "Accessories").owned.sprout_cap).toBe(1)
			h:Call(p, "Accessories.Unequip", { id = m.id, slot = "head" })
			expect(h:Section(p, "Workshop").copies[id].n).toBe(1)
			-- Selling the monster gives the copy back too.
			h:Call(p, "Workshop.Equip", { id = m.id, design = id })
			h:System("Monsters"):Remove(p, m.id, "sell")
			expect(h:Section(p, "Workshop").copies[id].n).toBe(1)
		end)

		it("sells copies on another server, pays royalties, counts likes and hides reported designs", function()
			local net = MockAdapters.network()
			local s1 = TestKernel.new({ systems = SYSTEMS, network = net })
			local s2 = TestKernel.new({ systems = SYSTEMS, network = net })
			local maker = s1:Join(7201, "Maker")
			local fan = s2:Join(7202, "Fan")
			for _, x in { { s1, maker }, { s2, fan } } do
				levelTo(x[1], x[2], 12)
				x[1]:System("Currency"):Add(x[2], "ribbons", 400, "test")
			end
			local id = design(s1, maker, "Cool Crown", "crown")
			s1:Advance(3)
			design(s1, maker, "Second One")
			s1:Advance(3)
			design(s1, maker, "Third One")
			s1:Advance(3)
			expect(s1:Reject(maker, "Workshop.Create", { name = "Fourth", shape = "cap", color = W.Palette[1], color2 = W.Palette[2] })).toBe(
				"You can publish 3 designs a week"
			)

			s2:Call(fan, "Workshop.Browse", { tab = "new" })
			local gallery = s2:Session(fan, "Workshop").gallery
			expect(#gallery).toBe(3)
			expect(gallery[3].id).toBe(id) -- newest first
			expect(gallery[3].creatorName).toBe("Maker")
			s2:Call(fan, "Workshop.Like", { design = id })
			expect(s2:Reject(fan, "Workshop.Like", { design = id })).toBe("You already like that design")
			s2:Call(fan, "Workshop.Browse", { tab = "top" })
			expect(s2:Session(fan, "Workshop").gallery[1].id).toBe(id)

			local before = s2:Section(fan, "Currency").ribbons
			expect(s2:Call(fan, "Workshop.Buy", { design = id }).owned).toBe(1)
			s2:Advance(2)
			s2:Call(fan, "Workshop.Buy", { design = id })
			expect(s2:Section(fan, "Currency").ribbons).toBe(before - 2 * W.CopyPrice.ribbons)
			expect(s2:Section(fan, "Workshop").copies[id].name).toBe("Cool Crown")
			expect(net.designs[id].copies).toBe(2)

			local ribbons = s1:Section(maker, "Currency").ribbons
			expect(s1:Call(maker, "Workshop.Claim").ribbons).toBe(2 * W.Royalty)
			expect(s1:Section(maker, "Currency").ribbons).toBe(ribbons + 2 * W.Royalty)
			s1:Advance(3)
			expect(s1:Call(maker, "Workshop.Claim").ribbons).toBe(0) -- paid once

			-- Reports from three players hide it from everyone else's gallery.
			for i = 1, W.ReportsToHide do
				local r = s2:Join(7300 + i)
				s2:Call(r, "Workshop.Report", { design = id })
			end
			expect(net.designs[id].hidden).toBe(true)
			s2:Advance(3)
			s2:Call(fan, "Workshop.Browse", { tab = "new" })
			for _, v in s2:Session(fan, "Workshop").gallery do
				expect(v.id ~= id).toBe(true)
			end
			expect(s2:Reject(fan, "Workshop.Buy", { design = id })).toBe("That design isn't available")
			-- Copies already bought still work.
			local m = adult(s2, fan, "zappip")
			s2:Call(fan, "Workshop.Equip", { id = m.id, design = id })
			expect(s2:System("Monsters"):Get(fan, m.id).acc.head ~= nil).toBe(true)
		end)
	end)
end
