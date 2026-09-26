--[[
	LevelSeventy (update 3.2): the Ranch Level cap rises from 60 to 70 when Frostbite Glacier
	opens, with incubator 4 (Lv 62), pen 6 (Lv 66) and squad size 5 (Lv 70). Covers the
	date-gated cap, the unlocks, the 5-slot Eggs save and its migration, pen 6 and rebirth,
	squads of 5 in stage fights, the Stampede and caravans, the plot layout and the exploits.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Formulas = t.Shared("Logic.Formulas")
	local BattleSim = t.Shared("Logic.BattleSim")
	local Unlocks, Economy, Regions, World = Config.Unlocks, Config.Economy, Config.Regions, Config.World

	local CAP_AT = Unlocks.LevelCaps[2].from
	local AFTER = CAP_AT + 3600

	local function fakeMonetization(passes)
		local m = { passes = passes or {} }
		function m:HasPass(_player, key)
			return self.passes[key] == true
		end
		function m:WatchAd()
			return true
		end
		function m:PaidRandomAllowed()
			return true
		end
		return m
	end

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
		expect(P:GetLevel(p)).toBe(level)
	end

	local function adults(h, p, n: number, rarity: number?)
		local ids = {}
		local lines = { "cindlet", "bubblin", "mossbun", "zappip", "lumipup", "wyrmlet" }
		for i = 1, n do
			local m = h:System("Monsters"):Create(p, {
				line = lines[(i - 1) % #lines + 1],
				rarity = rarity or 4,
				stage = 3,
				traits = { 3, 4 },
				hidden = 5,
			}, "test", true)
			m.lv = 40
			table.insert(ids, m.id)
		end
		return ids
	end

	describe("Level 70 · the date-gated cap", function()
		it("keeps the cap at 60 before 11 Mar 2028 and raises it to 70 at that instant", function()
			expect(Unlocks.MaxLevel).toBe(70)
			expect(Unlocks.MaxLevelAt(0)).toBe(60)
			expect(Unlocks.MaxLevelAt(CAP_AT - 1)).toBe(60)
			expect(Unlocks.MaxLevelAt(CAP_AT)).toBe(70)
			expect(Unlocks.MaxLevelAt(CAP_AT + 365 * 86400)).toBe(70)
			-- Same instant as the Frostbite Glacier region.
			expect(CAP_AT).toBe(Regions.ById.glacier.opensAt)
		end)

		it("holds XP at 0 at Level 60 before the date, then levels on to 61+ after it", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression" }, startTime = CAP_AT - 7200 })
			local p = h:Join()
			local P = h:System("Progression")
			local s = h:Section(p, "Progression")
			levelTo(h, p, 60)
			P:AddXP(p, Unlocks.XPToNext(60) * 3, "test")
			expect(s.level).toBe(60)
			expect(s.xp).toBe(0)
			expect(#h:Events(p, "Progression.LevelUp")).toBe(59)

			h:Advance(7200) -- the cap rises
			P:AddXP(p, 100, "test")
			expect(s.level).toBe(60)
			expect(s.xp).toBe(100) -- a capped player simply starts earning toward 61
			P:AddXP(p, Unlocks.XPToNext(60) - 100 + Unlocks.XPToNext(61) + 5, "test")
			expect(s.level).toBe(62)
			expect(s.xp).toBe(5)
			local last = h:LastEvent(p, "Progression.LevelUp")
			expect(last.payload.level).toBe(62)
			expect(last.payload.unlocks).toEqual({ "incubator_4" })

			levelTo(h, p, 70)
			P:AddXP(p, Unlocks.XPToNext(70) * 2, "test")
			expect(s.level).toBe(70)
			expect(s.xp).toBe(0)
		end)

		it("lists incubator 4, pen 6 and squad size 5 at 62 / 66 / 70 with names", function()
			expect(Unlocks.At(62)).toEqual({ "incubator_4" })
			expect(Unlocks.At(66)).toEqual({ "pen_6" })
			expect(Unlocks.At(70)).toEqual({ "squad_5" })
			expect(Unlocks.Names.incubator_4).toBe("Incubator 4")
			expect(Unlocks.Names.pen_6).toBe("Pen 6")
			expect(Unlocks.Names.squad_5).toBe("Squad size 5")
			for key, level in Unlocks.Features do
				expect(level <= Unlocks.MaxLevel).toBe(true)
				if level > 1 then
					expect(type(Unlocks.Names[key])).toBe("string")
				end
			end
		end)
	end)

	describe("Level 70 · incubators", function()
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Ranch" }

		it("earns a 4th incubator at 62 and a 5th with the pass, and refuses a 5th without it", function()
			local money = fakeMonetization()
			local h = TestKernel.new({ systems = SYSTEMS, stubs = { Monetization = money }, startTime = AFTER })
			local p = h:Join()
			local Eggs = h:System("Eggs")
			expect(#h:Section(p, "Eggs").slots).toBe(5)
			levelTo(h, p, 61)
			expect(h:Session(p, "Eggs").slotCount).toBe(3)
			levelTo(h, p, 62)
			expect(h:Session(p, "Eggs").slotCount).toBe(4)
			expect(Eggs:SlotCount(p)).toBe(4)

			local ids = Eggs:Add(p, "meadow", "test", 2)
			h:Call(p, "Eggs.Place", { egg = ids[1], slot = 4 })
			h:Advance(1)
			expect(h:Reject(p, "Eggs.Place", { egg = ids[2], slot = 5 })).toContain("locked")

			money.passes.extraIncubator = true
			h.kernel.Bus:Publish("PassesChanged", p, { passes = money.passes })
			expect(h:Session(p, "Eggs").slotCount).toBe(5)
			h:Advance(1)
			h:Call(p, "Eggs.Place", { egg = ids[2], slot = 5 })
			expect(h:Client(p).profile.Eggs.slots[5].egg).toBe(ids[2])
			expect(#Eggs:PublicSlots(p)).toBe(3) -- starter, slot 4 and slot 5
			expect(h:Reject(p, "Eggs.Place", { egg = ids[2], slot = 6 })).toContain("locked")
		end)

		it("migrates a 4-slot save: no egg lost, the running slot keeps its egg and timer", function()
			local h = TestKernel.new({ systems = SYSTEMS, stubs = { Monetization = fakeMonetization() }, startTime = AFTER })
			local userId = 4242
			local startedAt, endsAt = AFTER - 600, AFTER + 3000
			h.adapters.store["player_" .. userId] = {
				v = 1,
				data = {
					_meta = {
						created = AFTER - 86400 * 400,
						lastSeen = AFTER - 60,
						joins = 40,
						playSeconds = 9999,
						versions = { Eggs = 1 },
					},
					Progression = { level = 60, xp = 0 },
					Eggs = {
						list = { e7 = { type = "grove", source = "shop", t = AFTER - 900 } },
						slots = {
							{ egg = "e5", type = "meadow", startedAt = startedAt, endsAt = endsAt },
							{ egg = "e6", type = "grove", startedAt = startedAt, endsAt = AFTER - 5 },
							{ egg = false, type = false, startedAt = 0, endsAt = 0 },
							{ egg = false, type = false, startedAt = 0, endsAt = 0 },
						},
						nextId = 8,
						pity = { starlit = 3, royal = 1 },
						hatched = 12,
					},
				},
			}
			local p = h:Join(userId, "Veteran")
			local s = h:Section(p, "Eggs")
			expect(#s.slots).toBe(5)
			expect(s.slots[1]).toEqual({ egg = "e5", type = "meadow", startedAt = startedAt, endsAt = endsAt })
			expect(s.slots[2].egg).toBe("e6")
			expect(s.slots[2].endsAt).toBe(AFTER - 5)
			expect(s.slots[5]).toEqual({ egg = false, type = false, startedAt = 0, endsAt = 0 })
			expect(s.list.e7.type).toBe("grove")
			expect(s.nextId).toBe(8)
			expect(s.pity).toEqual({ starlit = 3, royal = 1 })
			expect(s.hatched).toBe(12)
			expect(h.kernel.Data:Get(p)._meta.versions.Eggs).toBe(2)
			expect(#h:Client(p).profile.Eggs.slots).toBe(5)
			-- The ready egg still hatches from its slot.
			local data = h:Call(p, "Eggs.Hatch", { slot = 2 })
			expect(data.monster ~= nil).toBe(true)
		end)
	end)

	describe("Level 70 · pen 6", function()
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Ranch", "Expeditions", "Breeding", "Rebirth" }

		it("is locked below 66, buyable at 66, holds monsters and resets on rebirth", function()
			expect(Economy.Pens.max).toBe(6)
			expect(Economy.Pens.unlocks[6]).toBe("pen_6")
			expect(Economy.Pens.buyCost[6]).toBe(10000000000)
			local h = TestKernel.new({ systems = SYSTEMS, stubs = { Monetization = fakeMonetization() }, startTime = AFTER })
			local p = h:Join()
			local Currency = h:System("Currency")
			levelTo(h, p, 65)
			Currency:Add(p, "coins", 2e10, "test")
			for n = 2, 5 do
				expect(h:Call(p, "Ranch.BuyPen").pen).toBe(n)
				h:Advance(1)
			end
			-- Exploit: a 6th pen below Level 66, and a monster into a pen not owned yet.
			expect(h:Reject(p, "Ranch.BuyPen")).toBe("Unlocks at Ranch Level 66")
			local m = h:System("Monsters"):Create(p, { line = "cindlet", rarity = 2, traits = { 3, 4 }, hidden = 5 }, "test", true)
			h:Advance(1)
			expect(h:Reject(p, "Ranch.Assign", { id = m.id, pen = 6 })).toContain("don't own")
			h:Advance(1)
			expect(h:Reject(p, "Ranch.Assign", { id = m.id, pen = 7 })).toBe("BadRequest")

			levelTo(h, p, 66)
			h:Advance(1)
			local before = Currency:Balance(p, "coins")
			expect(h:Call(p, "Ranch.BuyPen").pen).toBe(6)
			expect(before - Currency:Balance(p, "coins")).toBe(Economy.Pens.buyCost[6])
			expect(#h:Client(p).profile.Ranch.pens).toBe(6)
			h:Advance(1)
			expect(h:Reject(p, "Ranch.BuyPen")).toBe("You already own every pen")
			h:Call(p, "Ranch.Assign", { id = m.id, pen = 6 })
			expect(h:System("Ranch"):PenOf(p, m.id)).toBe(6)
			expect(h:System("Monsters"):Get(p, m.id).pen).toBe(6)
			h:Advance(1)
			h:Call(p, "Ranch.Collect", { pen = 6 })

			-- Rebirth takes pen 6 away with the others; it can be bought again later.
			Currency:Add(p, "coins", Config.Rebirth.CoinsNeeded(0), "test")
			h:Advance(1)
			h:Call(p, "Rebirth.Rebirth", { keep = { m.id } })
			expect(#h:Section(p, "Ranch").pens).toBe(1)
			expect(h:System("Monsters"):Get(p, m.id).pen ~= 6).toBe(true)
		end)
	end)

	describe("Level 70 · squad size 5", function()
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Expeditions", "Boss" }

		local function boot(startTime: number?)
			return TestKernel.new({ systems = SYSTEMS, stubs = { Monetization = fakeMonetization() }, startTime = startTime or AFTER })
		end

		it("grows the squad 3 → 4 → 5 at Levels 35 and 70 and refuses 5 below 70", function()
			local h = boot()
			local p = h:Join()
			local E = h:System("Expeditions")
			local ids = adults(h, p, 5)
			expect(E:SquadSize(p)).toBe(3)
			levelTo(h, p, 34)
			expect(E:SquadSize(p)).toBe(3)
			levelTo(h, p, 35)
			expect(E:SquadSize(p)).toBe(4)
			expect(h:Client(p).session.Expeditions.squadSize).toBe(4)
			levelTo(h, p, 69)
			expect(E:SquadSize(p)).toBe(4)
			expect(h:Reject(p, "Expeditions.SetSquad", { ids = ids })).toBe("A squad has at most 4 monsters")
			levelTo(h, p, 70)
			h:Advance(1)
			expect(E:SquadSize(p)).toBe(5)
			expect(h:Client(p).session.Expeditions.squadSize).toBe(5)
			h:Call(p, "Expeditions.SetSquad", { ids = ids })
			expect(E:GetSquad(p)).toEqual(ids)
			local total = 0
			for _, id in ids do
				total += Formulas.MonsterPower(h:System("Monsters"):Get(p, id))
			end
			expect(E:SquadPower(p)).toBeNear(total)
			h:Advance(1)
			expect(h:Invoke(p, "Expeditions.SetSquad", { ids = { ids[1], ids[2], ids[3], ids[4], ids[5], "m99" } }).err).toBe("BadRequest")
		end)

		it("fights a stage with 5 allies and returns a replay with a1..a5", function()
			local h = boot()
			local p = h:Join()
			levelTo(h, p, 70)
			local ids = adults(h, p, 5, 5)
			h:Call(p, "Expeditions.SetSquad", { ids = ids })
			h:Advance(1)
			local data = h:Call(p, "Expeditions.Fight", { region = "meadow", stage = 1 })
			local keys = {}
			for _, u in data.replay.units do
				if u.side == "ally" then
					table.insert(keys, u.key)
				end
			end
			expect(keys).toEqual({ "a1", "a2", "a3", "a4", "a5" })
			expect(data.win).toBe(true)
		end)

		it("starts timed expeditions and joins caravans with 5 only from Level 70", function()
			local h = boot()
			local host, guest = h:Join(), h:Join()
			levelTo(h, host, 70)
			levelTo(h, guest, 69)
			local hostIds, guestIds = adults(h, host, 5), adults(h, guest, 5)
			h:Section(host, "Expeditions").cleared.meadow = 5
			h:Section(guest, "Expeditions").cleared.meadow = 5
			h:Call(host, "Expeditions.SetSquad", { ids = hostIds })
			h:Call(guest, "Expeditions.SetSquad", { ids = { guestIds[1], guestIds[2], guestIds[3] } })
			h:Advance(1)
			local id = h:Call(host, "Expeditions.OpenCaravan", { region = "meadow", stage = 5, duration = "14400" }).caravan
			local lobby = h:Client(host).global.Expeditions.caravans[id]
			expect(lobby.members[1].power).toBeNear(h:System("Expeditions"):SquadPower(host))
			h:Advance(1)
			expect(h:Reject(guest, "Expeditions.JoinCaravan", { caravan = id, slot = 1, squad = guestIds })).toBe(
				"A squad has at most 4 monsters"
			)
			h:Advance(1)
			h:Call(
				guest,
				"Expeditions.JoinCaravan",
				{ caravan = id, slot = 1, squad = { guestIds[1], guestIds[2], guestIds[3], guestIds[4] } }
			)
			h:Call(host, "Expeditions.LeaveCaravan", { caravan = id })

			-- A timed run with 5 (a solo slot) at 70; the Lv 69 guest is capped at 4.
			h:Advance(2)
			h:Call(host, "Expeditions.Start", { slot = 1, region = "meadow", stage = 5, duration = "900", squad = hostIds })
			expect(#h:Section(host, "Expeditions").slots[1].squad).toBe(5)
		end)

		it("sends all 5 into the Stampede with the power of 5", function()
			local Period = Config.Boss.Period
			local START = CAP_AT + 10 * Period
			local h = boot(START - 100)
			local p = h:Join()
			levelTo(h, p, 70)
			local ids = adults(h, p, 5)
			h:Call(p, "Expeditions.SetSquad", { ids = ids })
			h:Advance(100 - Config.Boss.LobbySeconds + 1)
			h:Call(p, "Boss.Join")
			local joined
			for _, entry in h.adapters.log.analytics do
				if entry.name == "boss_join" then
					joined = entry
				end
			end
			expect(joined ~= nil).toBe(true)
			expect(joined.value).toBeNear(h:System("Expeditions"):SquadPower(p))
			local four = 0
			for i = 1, 4 do
				four += Formulas.MonsterPower(h:System("Monsters"):Get(p, ids[i]))
			end
			expect(joined.value > four).toBe(true)
		end)
	end)

	describe("Level 70 · BattleSim ally cap", function()
		local function records(n: number)
			local list = {}
			for i = 1, n do
				table.insert(list, {
					id = "m" .. i,
					line = "cindlet",
					form = Config.Species.ById.cindlet.forms[3][1].id,
					rarity = 3,
					stage = 3,
					lv = 30,
					stars = 1,
					traits = { 3, 4 },
					hidden = 5,
				})
			end
			return list
		end

		local function allyKeys(replay)
			local keys = {}
			for _, u in replay.units do
				if u.side == "ally" then
					table.insert(keys, u.key)
				end
			end
			return keys
		end

		it("fields 5 allies by default and keeps the Raids and Arena sizes", function()
			expect(BattleSim.MaxAllies).toBe(5)
			local enemies = BattleSim.BuildEnemies("meadow", 3, 7)
			local replay = BattleSim.Simulate(records(7), enemies, 7)
			expect(allyKeys(replay)).toEqual({ "a1", "a2", "a3", "a4", "a5" })
			-- Raids pass maxAllies = 8 explicitly; the Arena sends teams of 3.
			local raid = BattleSim.Simulate(records(8), enemies, 7, { maxAllies = Config.Raids.MaxPlayers * Config.Raids.PerPlayer })
			expect(#allyKeys(raid)).toBe(8)
			local arena = BattleSim.Simulate(records(Config.Arena.TeamSize), records(Config.Arena.TeamSize), 7)
			expect(#allyKeys(arena)).toBe(3)
		end)
	end)

	describe("Level 70 · plot layout", function()
		-- Footprints { x1, z1, x2, z2 } in plot-local studs.
		local function box(name: string, cx: number, cz: number, w: number, d: number)
			return { name = name, x1 = cx - w / 2, z1 = cz - d / 2, x2 = cx + w / 2, z2 = cz + d / 2 }
		end

		local function footprints()
			local list = {}
			for i, o in World.PenOffsets do
				table.insert(list, box("pen " .. i, o[1], o[3], World.PenSize[1], World.PenSize[2]))
			end
			local io = World.IncubatorOffset
			table.insert(list, box("incubator pad", io[1], io[3], World.IncubatorPadSize, World.IncubatorPadSize))
			local bo = World.BarnOffset
			table.insert(list, box("barn", bo[1], bo[3], World.BarnSize[1], World.BarnSize[3]))
			-- The barn door opens toward plot-local -z: keep room to stand in front of it.
			table.insert(list, box("barn door", bo[1], bo[3] - World.BarnSize[3] / 2 - 2, 6, 4))
			local go = World.GardenOffset
			table.insert(list, box("garden", go[1], go[3], World.GardenSize[1], World.GardenSize[2]))
			local so, row = World.StatueRowOffset, World.StatueRow
			local length = (row.count - 1) * row.spacing
			table.insert(list, box("statue row", so[1] + length / 2, so[3], length + row.pedestal, row.pedestal))
			-- The gate posts on the front edge (see World/Build.luau).
			table.insert(list, box("gate", World.PlotSize[1] / 2 - 2, 0, 2, 18))
			return list
		end

		it("has a pen spot for every pen and no two pieces overlap or leave the plot", function()
			expect(#World.PenOffsets).toBe(Economy.Pens.max)
			local list = footprints()
			local hx, hz = World.PlotSize[1] / 2, World.PlotSize[2] / 2
			local problems = {}
			for _, a in list do
				if a.x1 < -hx or a.x2 > hx or a.z1 < -hz or a.z2 > hz then
					table.insert(problems, a.name .. " leaves the plot")
				end
			end
			for i = 1, #list do
				for j = i + 1, #list do
					local a, b = list[i], list[j]
					if a.x1 < b.x2 and b.x1 < a.x2 and a.z1 < b.z2 and b.z1 < a.z2 then
						table.insert(problems, a.name .. " overlaps " .. b.name)
					end
				end
			end
			expect(table.concat(problems, "; ")).toBe("")
		end)
	end)
end
