-- Update 3.1 · Club Wars + Lunar Lanterns: war points from raids, racing and Stampedes
-- (servers sharing one club store and ladder), leagues and Champions, club banners from the
-- Workshop, and the Lunar Lanterns rerun with its second dragon.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, MockAdapters = t.TestKernel, t.MockAdapters
	local Config = t.Shared("Config")
	local Cfg = Config.Clubs
	local War = Cfg.War

	local START = War.startsAt + 3600
	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Quests", "Accessories", "Workshop", "Clubs" }

	local function server(net, startTime)
		return TestKernel.new({ systems = SYSTEMS, network = net, startTime = startTime or START })
	end

	local function rancher(h, userId, name)
		local p = h:Join(userId, name)
		h:System("Progression"):AddXP(p, 1e6, "test")
		h:System("Currency"):Add(p, "coins", 1e6, "test")
		return p
	end

	local function create(h, p, tag: string)
		local id = h:Call(p, "Clubs.Create", { name = "Club " .. tag, tag = tag, color = 2, emblem = "moon", open = true }).id
		h:Advance(2)
		return id
	end

	local function publish(h, p, topic: string, detail)
		h.kernel.Bus:Publish(topic, p, detail)
	end

	local function flush(h)
		h:System("Clubs"):Flush()
	end

	describe("Club Wars", function()
		it("sorts weekly scores into leagues", function()
			expect(Cfg.League(0).id).toBe("bronze")
			expect(Cfg.League(599).id).toBe("bronze")
			expect(Cfg.League(600).id).toBe("silver")
			expect(Cfg.League(1500).id).toBe("gold")
			expect(Cfg.League(99999).id).toBe("diamond")
			expect(War.startsAt).toBe(1833375600) -- Sat 5 Feb 2028, 15:00 UTC
		end)

		it("scores raids, races and Stampedes for the club across servers, within a daily cap", function()
			local net = MockAdapters.network()
			local early = server(net, War.startsAt - 3600)
			local e = rancher(early, 5001, "Early")
			create(early, e, "ERLY")
			publish(early, e, "RaidFinished", { raid = "titan", win = true })
			flush(early)
			expect(early:Client(e).session.Clubs.club.war.open).toBe(false)
			expect(early:Client(e).session.Clubs.club.war.points).toBe(0)

			local s1, s2 = server(net), server(net)
			local a = rancher(s1, 5101, "Ann")
			local clubId = create(s1, a, "WAR")
			local b = rancher(s2, 5102, "Ben")
			s2:Call(b, "Clubs.Join", { code = clubId })
			publish(s1, a, "RaidFinished", { raid = "titan", win = true }) -- 25
			publish(s1, a, "RaidFinished", { raid = "titan", win = false }) -- 0
			publish(s2, b, "RaceFinished", { place = 1, cup = 3, time = 30, day = 1 }) -- 15
			publish(s2, b, "BossDamage", { damage = 50000, rank = 2 }) -- 5 + 10
			flush(s1)
			flush(s2)
			local record = net.clubs[clubId]
			expect(record.warPoints).toBe(55)
			expect(record.members.u5101.war).toBe(25)
			expect(record.members.u5102.war).toBe(30)
			local week = Config.Leaderboards.Week(START)
			expect(net.clubWars[week][clubId]).toBe(55)
			-- Daily cap: 150 per member per UTC day.
			for _ = 1, 10 do
				publish(s1, a, "RaidFinished", { raid = "wyrm", win = true })
			end
			flush(s1)
			expect(net.clubs[clubId].members.u5101.war).toBe(War.dailyCap)
			expect(s1:Client(a).session.Clubs.club.war.todayLeft).toBe(0)

			-- A second club, and the ladder every server reads.
			local c = rancher(s2, 5201, "Cy")
			local other = create(s2, c, "RIV")
			publish(s2, c, "RaidFinished", { raid = "titan", win = true })
			flush(s2)
			s1:System("Clubs"):RefreshLadder()
			local ladder = s1:Client(a).global.Clubs.ladder
			expect(#ladder.rows).toBe(2)
			expect(ladder.rows[1].clubId).toBe(clubId)
			expect(ladder.rows[1].tag).toBe("WAR")
			expect(ladder.rows[2].clubId).toBe(other)
			expect(ladder.rows[2].points).toBe(25)
		end)

		it("pays last week's league or Champion reward once, to members who scored", function()
			local net = MockAdapters.network()
			local h = server(net)
			local clubs = {}
			local owners = {}
			-- Four clubs; the lowest is not in the top 3.
			for i, points in { 1600, 900, 700, 30 } do
				local p = rancher(h, 6000 + i, "Owner" .. i)
				local id = create(h, p, "C" .. i)
				local raids = math.floor(points / 25)
				for _ = 1, math.min(raids, War.dailyCap // 25) do
					publish(h, p, "RaidFinished", { raid = "titan", win = true })
				end
				clubs[i], owners[i] = id, p
			end
			-- Club 1 needs more members to pass the daily cap.
			local helpers = {}
			for j = 1, 10 do
				local q = rancher(h, 6100 + j, "Helper" .. j)
				h:Call(q, "Clubs.Join", { code = clubs[1] })
				h:Advance(2)
				for _ = 1, 6 do
					publish(h, q, "RaidFinished", { raid = "titan", win = true })
				end
				helpers[j] = q
			end
			local lazy = rancher(h, 6200, "Lazy")
			h:Call(lazy, "Clubs.Join", { code = clubs[4] })
			flush(h)
			expect(net.clubs[clubs[1]].warPoints >= War.leagues[3].min).toBe(true) -- Gold
			expect(h:Reject(owners[1], "Clubs.ClaimWar")).toBe("Your club has no Club Wars result from last week")

			h:Advance(7 * 86400)
			flush(h)
			local lastWeek = Config.Leaderboards.Week(START)
			-- The stored record rolls on its next write; views and claims roll it on read.
			expect(h:Client(owners[1]).session.Clubs.club.war.last.week).toBe(lastWeek)

			local gems = h:Section(owners[4], "Currency").gems
			local res = h:Call(owners[4], "Clubs.ClaimWar")
			expect(res.league).toBe("bronze") -- 4th on the ladder: its league, not Champion
			expect(h:Section(owners[4], "Currency").gems).toBe(gems + War.leagues[1].reward[1].amount)
			expect(h:Reject(owners[4], "Clubs.ClaimWar")).toBe("You already claimed that")
			expect(h:Reject(lazy, "Clubs.ClaimWar")).toBe("Earn war points for your club to share its reward")
			local champ = h:Call(helpers[1], "Clubs.ClaimWar")
			expect(champ.league).toBe("champion")
			expect(h:Section(helpers[1], "Quests").achievements.club_war.progress).toBe(1)
			-- The view shows the result.
			local last = h:Client(owners[1]).session.Clubs.club.war.last
			expect(last.champion).toBe(true)
		end)

		it("hangs a Workshop design as the club banner (officers only, owned designs only)", function()
			local net = MockAdapters.network()
			local h = server(net)
			local owner = rancher(h, 7001, "Owner")
			local member = rancher(h, 7002, "Member")
			local clubId = create(h, owner, "BNR")
			h:Call(member, "Clubs.Join", { code = clubId })
			h:System("Currency"):Add(owner, "ribbons", 100, "test")
			local design = h:Call(owner, "Workshop.Create", {
				name = "Club Flag",
				shape = "cape",
				color = Config.Workshop.Palette[9],
				color2 = Config.Workshop.Palette[5],
			}).design
			h:Advance(2)
			expect(h:Reject(member, "Clubs.SetBanner", { design = design })).toBe("Own a copy of that design to use it as a banner")
			h:Call(owner, "Clubs.SetBanner", { design = design })
			expect(net.clubs[clubId].banner.name).toBe("Club Flag")
			expect(h:Client(member).session.Clubs.club.banner.color).toBe(Config.Workshop.Palette[9])
			expect(h:Client(owner).global.Clubs.here.u7001.banner.color2).toBe(Config.Workshop.Palette[5])
			h:System("Currency"):Add(member, "ribbons", 100, "test")
			h:Call(member, "Workshop.Buy", { design = design })
			h:Advance(2)
			expect(h:Reject(member, "Clubs.SetBanner", { design = design })).toBe("Only the owner and officers can change the banner")
			h:Call(owner, "Clubs.SetBanner", { design = "" })
			expect(net.clubs[clubId].banner).toBeNil()
		end)
	end)

	describe("Lunar Lanterns returns", function()
		it("runs again in February 2028 with a second Lantern Dragon, a code and Season 7", function()
			local Events = Config.Events
			local rerun = Events.ById.lunarlanterns.reruns[1]
			expect(rerun.startsAt).toBe(War.startsAt)
			local e = Events.Active(rerun.startsAt + 60)
			expect(e.id).toBe("lunarlanterns")
			expect(e.endsAt).toBe(1835190000)
			expect(Config.Species.AdultForDiet("lanternling", { sweet = 3 }).id).toBe("moonlitdragon")
			expect(Config.Species.AdultForDiet("lanternling", { spicy = 3 }).id).toBe("lanterndragon")
			expect(Config.Species.AdultForDiet("lanternling", nil).id).toBe("lanterndragon")
			local season = Config.Quests.PassAt(rerun.startsAt)
			expect(season.season).toBe(7)
			expect(Config.Quests.PassAt(1832166000 - 1).season).toBe(6)
			local h = TestKernel.new({
				systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Quests" },
				startTime = rerun.startsAt + 60,
			})
			local p = h:Join()
			h:Call(p, "Quests.Redeem", { code = "clubwars" })
			expect(h:Section(p, "Currency").tokens.lunarlanterns).toBe(150)
		end)
	end)
end
