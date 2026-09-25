-- S4: Expeditions system (stage fights, timed expeditions, caravans).
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Regions = Config.Regions

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Expeditions" }

	-- Boots the kernel with an Eggs stub (records egg rewards) and optional Monetization.
	local function boot(options: { [string]: any }?)
		local opts = options or {}
		local eggs = {}
		local stubs = {
			Eggs = {
				Add = function(_, player, eggType, source, amount)
					table.insert(eggs, { userId = player.UserId, egg = eggType, source = source, amount = amount or 1 })
					return {}
				end,
			},
		}
		if opts.monetization then
			stubs.Monetization = opts.monetization
		end
		if opts.weather then
			stubs.Weather = opts.weather
		end
		local h = TestKernel.new({ systems = SYSTEMS, stubs = stubs })
		local topics = {}
		for _, topic in { "StageCleared", "ExpeditionStarted", "ExpeditionClaimed", "WelcomeItem", "RanchXP" } do
			topics[topic] = {}
			h.kernel.Bus:Subscribe(topic, function(player, detail)
				table.insert(topics[topic], { player = player, detail = detail })
			end)
		end
		return h, eggs, topics
	end

	local function setLevel(h, p, level: number)
		h:Section(p, "Progression").level = level
	end

	-- Creates `n` adult monsters of `line` at `lv` and returns their ids.
	local function team(h, p, n: number, spec: { [string]: any }?)
		local M = h:System("Monsters")
		local ids = {}
		for i = 1, n do
			local s = spec or {}
			local m = M:Create(p, {
				line = s.line or ({ "cindlet", "bubblin", "mossbun", "zappip" })[(i - 1) % 4 + 1],
				rarity = s.rarity or 3,
				stage = s.stage or 3,
				traits = s.traits or { 3, 4 },
				hidden = s.hidden or 5,
			}, "test", true) -- force: ignore capacity providers leaked by other specs
			m.lv = s.lv or 30
			table.insert(ids, m.id)
		end
		return ids
	end

	local function sumKind(list, kind: string, id: string?): number
		local n = 0
		for _, r in list do
			if r.kind == kind and (id == nil or r.id == id) then
				n += r.amount
			end
		end
		return n
	end

	describe("Expeditions squads", function()
		it("sets the default squad and validates size, duplicates and ownership", function()
			local h = boot()
			local p = h:Join()
			local other = h:Join()
			local ids = team(h, p, 4)
			team(h, other, 6) -- the other ranch owns m1..m6
			expect(h:Reject(p, "Expeditions.SetSquad", { ids = ids })).toContain("at most 3")
			expect(h:Reject(p, "Expeditions.SetSquad", { ids = { ids[1], ids[1] } })).toContain("only be picked once")
			expect(h:Reject(p, "Expeditions.SetSquad", { ids = { "m999" } })).toContain("doesn't exist")
			-- Ids are per ranch: the other player's m6 doesn't exist on this ranch.
			expect(h:Reject(p, "Expeditions.SetSquad", { ids = { "m6" } })).toContain("doesn't exist")
			-- 3.2: squads reach 5 at Ranch Level 70, so the schema refuses 6 ids.
			expect(h:Invoke(p, "Expeditions.SetSquad", { ids = { "m1", "m2", "m3", "m4", "m5", "m6" } }).err).toBe("BadRequest")
			h:Call(p, "Expeditions.SetSquad", { ids = { ids[1], ids[2], ids[3] } })
			local E = h:System("Expeditions")
			expect(E:GetSquad(p)).toEqual({ ids[1], ids[2], ids[3] })
			expect(E:SquadPower(p)).toBeGreaterThan(0)
			expect(h:Client(p).profile.Expeditions.squad).toEqual({ ids[1], ids[2], ids[3] })
			setLevel(h, p, Config.Unlocks.Features.squad_4)
			h:Advance(1)
			h:Call(p, "Expeditions.SetSquad", { ids = ids })
			expect(#E:GetSquad(p)).toBe(4)
		end)

		it("drops sold monsters from the squad", function()
			local h = boot()
			local p = h:Join()
			local ids = team(h, p, 3)
			h:Call(p, "Expeditions.SetSquad", { ids = ids })
			h:Call(p, "Monsters.Sell", { ids = { ids[2] } })
			expect(h:Section(p, "Expeditions").squad).toEqual({ ids[1], ids[3] })
		end)
	end)

	describe("Expeditions.Fight", function()
		it("wins a stage, pays the first clear once and publishes StageCleared", function()
			local h, _, topics = boot()
			local p = h:Join()
			h:Call(p, "Expeditions.SetSquad", { ids = team(h, p, 3) })
			local res = h:Call(p, "Expeditions.Fight", { region = "meadow", stage = 1 })
			expect(res.win).toBe(true)
			expect(res.replay.win).toBe(true)
			expect(#res.replay.units).toBe(3 + Regions.WaveSize)
			expect(#res.replay.events <= 400).toBe(true)
			expect(sumKind(res.rewards, "coins")).toBe(math.floor(100 * 1.10 ^ 1))
			expect(h:System("Expeditions"):Cleared(p, "meadow")).toBe(1)
			expect(h:Client(p).profile.Expeditions.cleared.meadow).toBe(1)
			expect(topics.StageCleared[1].detail.first).toBe(true)
			expect(topics.RanchXP[#topics.RanchXP].detail.amount).toBe(Config.Unlocks.XP.stageClearBase + 1)
			h:Advance(1)
			local again = h:Call(p, "Expeditions.Fight", { region = "meadow", stage = 1 })
			expect(again.win).toBe(true)
			expect(#again.rewards).toBe(0)
			expect(topics.StageCleared[2].detail.first).toBe(false)
		end)

		it("refuses locked regions, skipped stages, empty and busy squads", function()
			local h = boot()
			local p = h:Join()
			expect(h:Reject(p, "Expeditions.Fight", { region = "meadow", stage = 1 })).toContain("Pick a squad")
			local ids = team(h, p, 3)
			h:Call(p, "Expeditions.SetSquad", { ids = ids })
			h:Advance(1)
			expect(h:Reject(p, "Expeditions.Fight", { region = "coral", stage = 1 })).toContain("Ranch Level 10")
			h:Advance(1)
			expect(h:Reject(p, "Expeditions.Fight", { region = "meadow", stage = 3 })).toContain("Clear stage 1 first")
			h:Advance(1)
			expect(h:Invoke(p, "Expeditions.Fight", { region = "meadow", stage = Regions.MaxStages + 1 }).err).toBe("BadRequest")
			h:Advance(1)
			expect(h:Reject(p, "Expeditions.Fight", { region = "meadow", stage = 21 })).toContain("doesn't exist")
			h:System("Monsters"):SetBusy(p, ids[2], "breeding")
			expect(h:Reject(p, "Expeditions.Fight", { region = "meadow", stage = 1 })).toContain("is busy")
			h:Advance(1)
			h:System("Monsters"):SetBusy(p, ids[2], false)
			h:Call(p, "Expeditions.Fight", { region = "meadow", stage = 1 })
			-- Fights are rate-limited (1/s, burst 2).
			local tooFast = 0
			for _ = 1, 3 do
				if h:Invoke(p, "Expeditions.Fight", { region = "meadow", stage = 1 }).err == "TooFast" then
					tooFast += 1
				end
			end
			expect(tooFast).toBeAtLeast(1)
		end)

		it("offers the ad retry only right after a loss, with +20% stats", function()
			local ads = {}
			local adResult = false
			local h = boot({
				monetization = {
					HasPass = function()
						return false
					end,
					WatchAd = function(_, _player, placement)
						table.insert(ads, placement)
						return adResult
					end,
				},
			})
			local p = h:Join()
			-- A lone baby against the stage 10 boss always loses.
			h:Call(p, "Expeditions.SetSquad", { ids = team(h, p, 1, { stage = 1, rarity = 1, lv = 1, line = "mossbun" }) })
			h:Section(p, "Expeditions").cleared.meadow = 9
			expect(h:Reject(p, "Expeditions.Fight", { region = "meadow", stage = 10, retry = true })).toContain("just lost")
			h:Advance(1)
			local lost = h:Call(p, "Expeditions.Fight", { region = "meadow", stage = 10 })
			expect(lost.win).toBe(false)
			expect(lost.replay.units[2].boss).toBe(true)
			h:Advance(1)
			expect(h:Reject(p, "Expeditions.Fight", { region = "meadow", stage = 10, retry = true })).toContain("ad")
			h:Advance(1)
			-- The failed ad used up the retry.
			expect(h:Reject(p, "Expeditions.Fight", { region = "meadow", stage = 10, retry = true })).toContain("just lost")
			h:Advance(1)
			local plain = h:Call(p, "Expeditions.Fight", { region = "meadow", stage = 10 })
			adResult = true
			h:Advance(1)
			local boosted = h:Call(p, "Expeditions.Fight", { region = "meadow", stage = 10, retry = true })
			expect(ads).toEqual({ "stageRetry", "stageRetry" })
			expect(boosted.replay.units[1].maxHp).toBeGreaterThan(plain.replay.units[1].maxHp)
		end)

		it("says retries are unavailable without Monetization", function()
			local h = boot()
			local p = h:Join()
			h:Call(p, "Expeditions.SetSquad", { ids = team(h, p, 1, { stage = 1, rarity = 1, lv = 1, line = "mossbun" }) })
			h:Section(p, "Expeditions").cleared.meadow = 9
			expect(h:Call(p, "Expeditions.Fight", { region = "meadow", stage = 10 }).win).toBe(false)
			h:Advance(1)
			expect(h:Reject(p, "Expeditions.Fight", { region = "meadow", stage = 10, retry = true })).toContain("aren't available")
		end)
	end)

	describe("Timed expeditions", function()
		it("runs the full cycle: start, busy lock, claim, free", function()
			local h, _, topics = boot()
			local p = h:Join()
			local ids = team(h, p, 3)
			local M = h:System("Monsters")
			local res = h:Call(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "900", squad = ids })
			expect(res.endsAt).toBe(h.adapters.Clock.Now() + 900)
			expect(M:Get(p, ids[1]).busy).toBe("expedition")
			expect(topics.ExpeditionStarted[1].detail.duration).toBe(900)
			local client = h:Client(p)
			expect(client.profile.Expeditions.slots[1].state).toBe("running")
			expect(client.profile.Expeditions.slots[1].region).toBe("meadow")
			expect(client.session.Expeditions.slotCount).toBe(1)
			-- Busy monsters can't be sold, reused or fought with.
			expect(h:Reject(p, "Monsters.Sell", { ids = { ids[1] } })).toContain("busy")
			h:Call(p, "Expeditions.SetSquad", { ids = ids })
			expect(h:Reject(p, "Expeditions.Fight", { region = "meadow", stage = 1 })).toContain("busy")
			expect(h:Reject(p, "Expeditions.Start", { slot = 2, region = "meadow", stage = 1, duration = "900", squad = ids })).toContain(
				"locked"
			)
			setLevel(h, p, 6)
			h:Advance(1)
			expect(h:Reject(p, "Expeditions.Start", { slot = 2, region = "meadow", stage = 1, duration = "900", squad = ids })).toContain(
				"busy"
			)
			expect(h:Reject(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "900", squad = ids })).toContain(
				"already exploring"
			)
			expect(h:Reject(p, "Expeditions.Claim", { slot = 1 })).toContain("Still exploring")
			expect(h:Reject(p, "Expeditions.Claim", { slot = 2 })).toContain("Nothing to claim")
			h:Advance(900)
			local coinsBefore = h:Section(p, "Currency").coins
			local claim = h:Call(p, "Expeditions.Claim", { slot = 1 })
			local per = Regions.LootPerMinute(1)
			expect(sumKind(claim.rewards, "coins")).toBe(math.floor(per.coins * 15))
			expect(h:Section(p, "Currency").coins - coinsBefore).toBe(math.floor(per.coins * 15))
			expect(sumKind(claim.rewards, "food")).toBe(math.floor(per.food * 15))
			expect(M:Get(p, ids[1]).busy).toBe(false)
			expect(h:Section(p, "Expeditions").slots[1].state).toBe("idle")
			expect(topics.ExpeditionClaimed[1].detail.slot).toBe(1)
			expect(topics.RanchXP[#topics.RanchXP].detail.amount).toBe(math.floor(Config.Unlocks.XP.expeditionPerMinute * 15))
			expect(h:Reject(p, "Expeditions.Claim", { slot = 1 })).toContain("Nothing to claim")
		end)

		it("only farms cleared stages (stage 1 is always open)", function()
			local h = boot()
			local p = h:Join()
			local ids = team(h, p, 3)
			expect(h:Reject(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 2, duration = "900", squad = ids })).toContain(
				"Clear this stage"
			)
			expect(h:Reject(p, "Expeditions.Start", { slot = 1, region = "ember", stage = 1, duration = "900", squad = ids })).toContain(
				"Ranch Level 18"
			)
			expect(h:Reject(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "60", squad = ids })).toBe(
				"BadRequest"
			)
			expect(
				h:Reject(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "900", squad = { ids[1], ids[1] } })
			).toContain("only be picked once")
			expect(h:Reject(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "900", squad = { "m77" } })).toContain(
				"doesn't exist"
			)
			h:Section(p, "Expeditions").cleared.meadow = 4
			h:Advance(1)
			h:Call(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 4, duration = "900", squad = ids })
		end)

		it("finishes offline and announces it on rejoin", function()
			local h, eggs, topics = boot()
			local p = h:Join()
			local ids = team(h, p, 3)
			h:Call(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "14400", squad = ids })
			local p2 = h:Rejoin(p, 4 * 3600)
			local welcome = topics.WelcomeItem[#topics.WelcomeItem]
			expect(welcome.player).toBe(p2)
			expect(welcome.detail.text).toBe("1 expedition finished")
			expect(h:System("Monsters"):Get(p2, ids[1]).busy).toBe("expedition")
			local claim = h:Call(p2, "Expeditions.Claim", { slot = 1 })
			local per = Regions.LootPerMinute(1)
			expect(sumKind(claim.rewards, "coins")).toBe(math.floor(per.coins * 240 * Regions.DurationBonus[14400]))
			expect(sumKind(claim.rewards, "food", "sweet")).toBeGreaterThan(0)
			expect(sumKind(claim.rewards, "egg")).toBe(#eggs > 0 and eggs[1].amount or 0)
			expect(h:System("Monsters"):Get(p2, ids[1]).busy).toBe(false)
			-- A second rejoin doesn't announce it again.
			local count = #topics.WelcomeItem
			h:Rejoin(p2, 60)
			expect(#topics.WelcomeItem).toBe(count)
		end)

		it("repairs stale busy tags on join", function()
			local h = boot()
			local p = h:Join()
			local ids = team(h, p, 2)
			h:System("Monsters"):SetBusy(p, ids[1], "expedition") -- no running slot owns it
			local p2 = h:Rejoin(p, 10)
			expect(h:System("Monsters"):Get(p2, ids[1]).busy).toBe(false)
		end)

		it("recalls early with proportional loot and no duration bonus", function()
			local h = boot()
			local p = h:Join()
			local ids = team(h, p, 3)
			h:Call(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "28800", squad = ids })
			h:Advance(600)
			local res = h:Call(p, "Expeditions.Recall", { slot = 1 })
			expect(sumKind(res.rewards, "coins")).toBe(math.floor(Regions.LootPerMinute(1).coins * 10))
			expect(h:System("Monsters"):Get(p, ids[1]).busy).toBe(false)
			expect(h:Reject(p, "Expeditions.Recall", { slot = 1 })).toContain("isn't exploring")
		end)

		it("claims everything that is back in one call", function()
			local h, eggs = boot()
			local p = h:Join()
			setLevel(h, p, 15)
			h:Advance(1)
			local ids = team(h, p, 3)
			h:Call(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "900", squad = { ids[1] } })
			h:Call(p, "Expeditions.Start", { slot = 2, region = "meadow", stage = 1, duration = "900", squad = { ids[2] } })
			h:Call(p, "Expeditions.Start", { slot = 3, region = "meadow", stage = 1, duration = "28800", squad = { ids[3] } })
			expect(h:Reject(p, "Expeditions.ClaimAll")).toContain("No expeditions")
			h:Advance(901)
			local res = h:Call(p, "Expeditions.ClaimAll")
			expect(sumKind(res.rewards, "coins")).toBe(2 * math.floor(Regions.LootPerMinute(1).coins * 15))
			expect(h:Section(p, "Expeditions").slots[3].state).toBe("running")
			expect(#eggs).toBe(sumKind(res.rewards, "egg") > 0 and 1 or 0)
		end)

		it("adds Lucky Paw (max 3), Treasure Nose and registered loot modifiers", function()
			local h = boot()
			local p = h:Join()
			local E = h:System("Expeditions")
			local paws = team(h, p, 4, { traits = { 8, 3 }, hidden = 5 })
			expect(E:LootBonus(p, paws)).toBeNear(0.08 * 3)
			local nose = team(h, p, 1, { line = "drizzlet", traits = { 3, 4 } })
			expect(E:LootBonus(p, { paws[1], nose[1] })).toBeNear(0.08 + 0.1)
			E:RegisterLootModifier("test", function()
				return 0.05
			end)
			expect(E:LootBonus(p, { nose[1] })).toBeNear(0.15)
			h:Call(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "900", squad = { paws[1], nose[1] } })
			h:Advance(900)
			local res = h:Call(p, "Expeditions.Claim", { slot = 1 })
			local base = Regions.LootPerMinute(1).coins * 15
			expect(sumKind(res.rewards, "coins")).toBe(math.floor(base * (1 + 0.08 + 0.1 + 0.05)))
		end)

		it("counts slots from unlocks and the Explorer pass", function()
			local h = boot({
				monetization = {
					HasPass = function(_, _player, key)
						return key == "explorer"
					end,
					WatchAd = function()
						return false
					end,
				},
			})
			local p = h:Join()
			local E = h:System("Expeditions")
			expect(E:SlotCount(p)).toBe(2)
			setLevel(h, p, 15)
			expect(E:SlotCount(p)).toBe(4)
			expect(h:Client(p).session.Expeditions.slotCount).toBe(2)
			h.kernel.Bus:Publish("LevelUp", p, { level = 15 })
			expect(h:Client(p).session.Expeditions.slotCount).toBe(4)
			expect(h:Client(p).session.Expeditions.squadSize).toBe(3)
		end)
	end)

	describe("Caravans", function()
		local function crew(h, n: number)
			local players = {}
			for i = 1, n do
				local p = h:Join()
				setLevel(h, p, 8)
				h:Section(p, "Expeditions").cleared.meadow = 5
				local ids = team(h, p, 3)
				h:Call(p, "Expeditions.SetSquad", { ids = ids })
				players[i] = { player = p, ids = ids }
			end
			h:Advance(1)
			return players
		end

		it("opens, joins, launches and pays the bonus and shared chest", function()
			local h, eggs = boot()
			local c = crew(h, 3)
			local host, p2, p3 = c[1].player, c[2].player, c[3].player
			local open = h:Call(host, "Expeditions.OpenCaravan", { region = "meadow", stage = 5, duration = "14400" })
			local id = open.caravan
			expect(h:Client(p2).global.Expeditions.caravans[id].hostName).toBe(host.DisplayName)
			expect(h:Client(host).session.Expeditions.caravan.id).toBe(id)
			expect(h:Reject(host, "Expeditions.OpenCaravan", { region = "meadow", stage = 5, duration = "14400" })).toContain(
				"already in a caravan"
			)
			expect(h:Reject(host, "Expeditions.LaunchCaravan", { caravan = id })).toContain("at least 2")
			-- The host's reserved slot can't be used for a solo run.
			expect(h:Reject(host, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "900", squad = c[1].ids })).toContain(
				"saved for your caravan"
			)
			-- Other players' monster ids are refused (the host owns m4, p2 only m1..m3).
			team(h, host, 1)
			expect(h:Reject(p2, "Expeditions.JoinCaravan", { caravan = id, slot = 1, squad = { "m4" } })).toContain("doesn't exist")
			h:Advance(1)
			h:Call(p2, "Expeditions.JoinCaravan", { caravan = id, slot = 1, squad = c[2].ids })
			expect(h:Reject(p2, "Expeditions.JoinCaravan", { caravan = id, slot = 1, squad = c[2].ids })).toContain(
				"already in this caravan"
			)
			expect(#h:Client(p2).session.Expeditions.caravan.members).toBe(2)
			expect(h:Reject(p2, "Expeditions.LaunchCaravan", { caravan = id })).toContain("Only the host")
			h:Call(p3, "Expeditions.JoinCaravan", { caravan = id, slot = 1, squad = c[3].ids })
			expect(#h:Client(host).session.Expeditions.caravan.members).toBe(3)
			-- p3 leaves the server: removed from the lobby.
			h:Leave(p3)
			expect(#h:Client(host).session.Expeditions.caravan.members).toBe(2)

			local launch = h:Call(host, "Expeditions.LaunchCaravan", { caravan = id })
			expect(launch.endsAt).toBe(h.adapters.Clock.Now() + 14400)
			expect(h:Section(p2, "Expeditions").slots[1].caravan).toBe(id)
			expect(h:System("Monsters"):Get(p2, c[2].ids[1]).busy).toBe("expedition")
			local view = h:Client(host)
			expect(view.global.Expeditions.caravans[id]).toBeNil()
			expect(view.session.Expeditions.caravan).toBe(false)

			h:Advance(14400)
			local res = h:Call(host, "Expeditions.Claim", { slot = 1 })
			local g = Regions.GlobalIndex("meadow", 5)
			local base = Regions.LootPerMinute(g).coins * 240 * Regions.DurationBonus[14400]
			expect(sumKind(res.rewards, "coins")).toBe(math.floor(base * (1 + Regions.Caravan.lootBonus)))
			local chestEggs = 0
			for _, e in eggs do
				if e.userId == host.UserId and e.egg == "grove" then
					chestEggs += e.amount
				end
			end
			expect(chestEggs).toBeAtLeast(1)
			expect(sumKind(res.rewards, "egg", "grove")).toBeAtLeast(1)
		end)

		it("gates caravans behind the unlock and the host's cleared stage", function()
			local h = boot()
			local c = crew(h, 2)
			setLevel(h, c[1].player, 7)
			expect(h:Reject(c[1].player, "Expeditions.OpenCaravan", { region = "meadow", stage = 1, duration = "14400" })).toContain(
				"Ranch Level 8"
			)
			setLevel(h, c[1].player, 8)
			h:Advance(1)
			expect(h:Reject(c[1].player, "Expeditions.OpenCaravan", { region = "meadow", stage = 6, duration = "14400" })).toContain(
				"Clear this stage"
			)
			h:Advance(1)
			expect(h:Invoke(c[1].player, "Expeditions.OpenCaravan", { region = "meadow", stage = 1, duration = "900" }).err).toBe(
				"BadRequest"
			)
			h:Advance(1)
			expect(h:Reject(c[2].player, "Expeditions.JoinCaravan", { caravan = "c999", slot = 1, squad = c[2].ids })).toContain("closed")
		end)

		it("closes when the host leaves or the lobby expires", function()
			local h = boot()
			local c = crew(h, 3)
			local id = h:Call(c[1].player, "Expeditions.OpenCaravan", { region = "meadow", stage = 2, duration = "28800" }).caravan
			h:Call(c[2].player, "Expeditions.JoinCaravan", { caravan = id, slot = 1, squad = c[2].ids })
			h:Leave(c[1].player)
			local view = h:Client(c[2].player)
			expect(view.global.Expeditions.caravans[id]).toBeNil()
			expect(view.session.Expeditions.caravan).toBe(false)
			-- p2 is free to host now; its lobby expires if nobody launches it.
			local id2 = h:Call(c[2].player, "Expeditions.OpenCaravan", { region = "meadow", stage = 5, duration = "14400" }).caravan
			h:Call(c[3].player, "Expeditions.JoinCaravan", { caravan = id2, slot = 1, squad = c[3].ids })
			h:Advance(1)
			h:Call(c[3].player, "Expeditions.LeaveCaravan", { caravan = id2 })
			expect(h:Reject(c[3].player, "Expeditions.LeaveCaravan", { caravan = id2 })).toContain("not in that caravan")
			h:Advance(Regions.Caravan.lobbySeconds + 1)
			expect(h:Client(c[2].player).global.Expeditions.caravans[id2]).toBeNil()
			expect(h:Reject(c[2].player, "Expeditions.LaunchCaravan", { caravan = id2 })).toContain("closed")
		end)

		it("drops members who are no longer ready at launch", function()
			local h = boot()
			local c = crew(h, 3)
			local id = h:Call(c[1].player, "Expeditions.OpenCaravan", { region = "meadow", stage = 3, duration = "14400" }).caravan
			h:Call(c[2].player, "Expeditions.JoinCaravan", { caravan = id, slot = 1, squad = c[2].ids })
			h:Call(c[3].player, "Expeditions.JoinCaravan", { caravan = id, slot = 1, squad = c[3].ids })
			-- p3 sends its squad elsewhere after joining.
			h:System("Monsters"):SetBusy(c[3].player, c[3].ids[1], "breeding")
			h:Call(c[1].player, "Expeditions.LaunchCaravan", { caravan = id })
			expect(h:Section(c[2].player, "Expeditions").slots[1].state).toBe("running")
			expect(h:Section(c[3].player, "Expeditions").slots[1].state).toBe("idle")
		end)
	end)
end
