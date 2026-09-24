-- S6 HallOfFame: retire rules, legacy caps, statues, Stardust upgrades and provider registration.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Formulas = t.Shared("Logic.Formulas")
	local HOF = Config.HallOfFame

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Monetization", "Quests", "HallOfFame" }

	-- Stubs that record what HallOfFame registers with them.
	local function providerStubs()
		local reg = {}
		local function recorder(system: string)
			return function(_self, key, fn)
				reg[system .. "." .. key] = fn
			end
		end
		local stubs = {
			Ranch = { RegisterRateModifier = recorder("Ranch"), RegisterJarBonus = recorder("Ranch") },
			Eggs = { RegisterSpeedProvider = recorder("Eggs") },
			Boss = { RegisterDamageModifier = recorder("Boss") },
			Breeding = { RegisterBreedsPerDayBonus = recorder("Breeding") },
			Expeditions = { RegisterLootModifier = recorder("Expeditions") },
		}
		return stubs, reg
	end

	local function boot(withStubs: boolean?)
		local stubs, reg = providerStubs()
		local h = TestKernel.new({ systems = SYSTEMS, stubs = if withStubs == false then {} else stubs })
		return h, reg
	end

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function adult(h, p, line: string, rarity: number)
		local m = h:System("Monsters"):Create(p, { line = line, rarity = rarity, stage = 3, traits = { 3, 4 }, hidden = 5 }, "test", true)
		m.lv = Formulas.LevelCap(m)
		return m
	end

	local function ready(withStubs: boolean?)
		local h, reg = boot(withStubs)
		local p = h:Join()
		levelTo(h, p, 20)
		h:System("Monsters"):Create(p, { line = "mossbun", rarity = 1 }, "test", true) -- keeper
		return h, p, reg
	end

	local function topicLog(h, topic: string)
		local seen = {}
		h.kernel.Bus:Subscribe(topic, function(_player, detail)
			table.insert(seen, detail)
		end)
		return seen
	end

	describe("HallOfFame retire", function()
		it("turns a capped Adult into a statue, legacy and Stardust", function()
			local h, p = ready()
			local m = adult(h, p, "cindlet", 3)
			local retired = topicLog(h, "Retired")
			local rates = topicLog(h, "RateModifiersChanged")
			local removed = topicLog(h, "MonsterRemoved")
			local xpBefore = h:Section(p, "Progression").xp
			local levelBefore = h:Section(p, "Progression").level

			local data = h:Call(p, "HallOfFame.Retire", { id = m.id })
			local rare = Config.Rarities.List[3]
			expect(data.stardust).toBe(rare.stardust)
			expect(data.legacy).toBeNear(rare.legacyPct)
			expect(h:Section(p, "Currency").stardust).toBe(rare.stardust)
			expect(h:System("Monsters"):Get(p, m.id)).toBeNil()
			expect(removed[1].reason).toBe("retire")

			local s = h:Section(p, "HallOfFame")
			expect(#s.entries).toBe(1)
			expect(s.entries[1].rarity).toBe(3)
			expect(s.entries[1].element).toBe("ember")
			expect(s.entries[1].appearance.line).toBe("cindlet")
			expect(s.entries[1].retiredAt).toBe(h.adapters.Clock.Now())
			expect(s.starShards).toBe(HOF.StarShardsPerRetire[3])
			expect(h:System("HallOfFame"):GetLegacy(p, "ember")).toBeNear(0.03)
			expect(h:System("HallOfFame"):GetLegacy(p, "tide")).toBe(0)

			expect(retired[1].rarity).toBe(3)
			expect(retired[1].element).toBe("ember")
			expect(#rates).toBe(1)
			local gainedXP = h:Section(p, "Progression").level > levelBefore or h:Section(p, "Progression").xp > xpBefore
			expect(gainedXP).toBe(true)
			local ev = h:LastEvent(p, "HallOfFame.Retired").payload
			expect(ev.stardust).toBe(rare.stardust)
			expect(ev.appearance.line).toBe("cindlet")
			expect(h:Section(p, "Quests").achievements.retire_1.progress).toBe(1)

			local client = h:Client(p)
			expect(client.profile.HallOfFame.entries[1].rarity).toBe(3)
			expect(client.profile.HallOfFame.legacy.ember).toBeNear(0.03)
			expect(client.profile.Currency.stardust).toBe(rare.stardust)
		end)

		it("enforces unlock, stage, level cap, busy, locked and keep-one rules", function()
			local h = boot()
			local p = h:Join()
			local M = h:System("Monsters")
			local m = adult(h, p, "cindlet", 2)
			M:Create(p, { line = "mossbun", rarity = 1 }, "test", true)
			expect(h:Reject(p, "HallOfFame.Retire", { id = m.id })).toBe("Unlocks at Ranch Level 20")
			levelTo(h, p, 20)
			h:Advance(2)

			local baby = M:Create(p, { line = "bubblin", rarity = 1 }, "test", true)
			baby.lv = Formulas.LevelCap(baby)
			expect(h:Reject(p, "HallOfFame.Retire", { id = baby.id })).toBe("Only Adults can retire")
			expect(h:Reject(p, "HallOfFame.Retire", { id = "m999" })).toBe("That monster doesn't exist")
			h:Advance(2)

			m.lv = Formulas.LevelCap(m) - 1
			expect(h:Reject(p, "HallOfFame.Retire", { id = m.id })).toContain(string.format("Reach level %d", Formulas.LevelCap(m)))
			m.lv = Formulas.LevelCap(m)
			M:SetBusy(p, m.id, "expedition")
			expect(h:Reject(p, "HallOfFame.Retire", { id = m.id })).toContain("is busy")
			h:Advance(2)
			M:SetBusy(p, m.id, false)
			m.locked = true
			expect(h:Reject(p, "HallOfFame.Retire", { id = m.id })).toContain("Unlock it first")
			m.locked = false
			expect(M:Get(p, m.id)).toBeTruthy()

			-- Keep at least one monster on the ranch.
			local h2 = boot()
			local q = h2:Join()
			levelTo(h2, q, 20)
			local only = adult(h2, q, "cindlet", 1)
			expect(h2:Reject(q, "HallOfFame.Retire", { id = only.id })).toContain("at least one")
		end)

		it("adds legacy to every element of a hybrid and caps each element", function()
			local h, p = ready()
			local HallOfFame = h:System("HallOfFame")
			local hybrid = adult(h, p, "steamling", 2)
			h:Call(p, "HallOfFame.Retire", { id = hybrid.id })
			expect(HallOfFame:GetLegacy(p, "ember")).toBeNear(0.02)
			expect(HallOfFame:GetLegacy(p, "tide")).toBeNear(0.02)

			local steps = math.ceil(HOF.LegacyCapPerElement / Config.Rarities.List[6].legacyPct) + 1
			local last
			for _ = 1, steps do
				h:Advance(1)
				local mythic = adult(h, p, "cindlet", 6)
				last = h:Call(p, "HallOfFame.Retire", { id = mythic.id })
			end
			expect(HallOfFame:GetLegacy(p, "ember")).toBe(HOF.LegacyCapPerElement)
			expect(last.legacy).toBe(0)
			expect(last.stardust).toBe(Config.Rarities.List[6].stardust) -- Stardust still pays at the cap
			expect(HallOfFame:GetLegacy(p, "tide")).toBeNear(0.02)
		end)

		it("keeps the newest 100 entries and returns the newest statues", function()
			local h, p = ready()
			local s = h:Section(p, "HallOfFame")
			for i = 1, HOF.MaxEntries do
				s.entries[i] = { appearance = { line = "old" .. i }, retiredAt = 0, rarity = 1, element = "tide" }
			end
			local m = adult(h, p, "cindlet", 1)
			h:Call(p, "HallOfFame.Retire", { id = m.id })
			expect(#s.entries).toBe(HOF.MaxEntries)
			expect(s.entries[1].appearance.line).toBe("cindlet")
			expect(s.entries[HOF.MaxEntries].appearance.line).toBe("old" .. (HOF.MaxEntries - 1))
			local statues = h:System("HallOfFame"):Statues(p)
			expect(#statues).toBe(HOF.MaxStatues)
			expect(statues[1].line).toBe("cindlet")
			expect(statues[2].line).toBe("old1")
		end)
	end)

	describe("HallOfFame upgrades", function()
		it("buys levels with Stardust up to the max", function()
			local h, p = ready()
			local C = h:System("Currency")
			local HallOfFame = h:System("HallOfFame")
			local def = HOF.UpgradeById.jar_cap
			expect(h:Reject(p, "HallOfFame.BuyUpgrade", { upgrade = "jar_cap" })).toBe("Not enough Stardust")
			local total = 0
			for _, c in def.cost do
				total += c
			end
			C:Add(p, "stardust", total + 5, "test")
			local rates = topicLog(h, "RateModifiersChanged")
			for level = 1, def.maxLevel do
				h:Advance(1)
				expect(h:Call(p, "HallOfFame.BuyUpgrade", { upgrade = "jar_cap" }).level).toBe(level)
			end
			expect(#rates).toBe(def.maxLevel)
			expect(C:Balance(p, "stardust")).toBe(5)
			expect(HallOfFame:UpgradeLevel(p, "jar_cap")).toBe(def.maxLevel)
			h:Advance(1)
			expect(h:Reject(p, "HallOfFame.BuyUpgrade", { upgrade = "jar_cap" })).toContain("already maxed")
			expect(h:Client(p).profile.HallOfFame.upgrades.jar_cap).toBe(def.maxLevel)
		end)

		it("needs the Hall of Fame unlock", function()
			local h = boot()
			local p = h:Join()
			h:System("Currency"):Add(p, "stardust", 1000, "test")
			expect(h:Reject(p, "HallOfFame.BuyUpgrade", { upgrade = "mood_floor" })).toBe("Unlocks at Ranch Level 20")
		end)
	end)

	describe("HallOfFame providers", function()
		it("registers with every plugged-in system and reports upgrade effects", function()
			local h, p, reg = ready()
			for _, key in
				{
					"Ranch.legacy",
					"Ranch.jar_cap",
					"Eggs.incubator_speed",
					"Boss.boss_power",
					"Breeding.daily_breed",
					"Expeditions.expedition_loot",
				}
			do
				expect(type(reg[key])).toBe("function")
			end
			expect(reg["Ranch.legacy"](p, { "ember", "tide" })).toBe(0)
			expect(reg["Ranch.jar_cap"](p)).toBe(0)

			local s = h:Section(p, "HallOfFame")
			s.legacy.ember, s.legacy.tide = 0.05, 0.12
			s.upgrades = { jar_cap = 2, incubator_speed = 3, boss_power = 1, daily_breed = 2, expedition_loot = 4 }
			expect(reg["Ranch.legacy"](p, { "ember", "tide" })).toBeNear(0.12)
			expect(reg["Ranch.legacy"](p, { "gloom" })).toBe(0)
			expect(reg["Ranch.jar_cap"](p)).toBe(1800)
			expect(reg["Eggs.incubator_speed"](p)).toBeNear(0.15)
			expect(reg["Boss.boss_power"](p)).toBeNear(0.05)
			expect(reg["Breeding.daily_breed"](p)).toBe(2)
			expect(reg["Expeditions.expedition_loot"](p)).toBeNear(0.2)
			expect(reg["Eggs.incubator_speed"]({ UserId = 1 })).toBe(0) -- unknown player
		end)

		it("raises the monster mood floor with Happy Ranch", function()
			local h, p = ready()
			local M = h:System("Monsters")
			local m = adult(h, p, "cindlet", 1)
			M:AddMood(p, m.id, -1000)
			expect(m.mood).toBeLessThan(HOF.UpgradeById.mood_floor.effect.moodFloor)
			h:System("Currency"):Add(p, "stardust", HOF.UpgradeById.mood_floor.cost[1], "test")
			h:Call(p, "HallOfFame.BuyUpgrade", { upgrade = "mood_floor" })
			M:AddMood(p, m.id, -1000)
			expect(m.mood).toBe(HOF.UpgradeById.mood_floor.effect.moodFloor)
		end)

		it("boots without any optional system", function()
			local h, p = ready(false)
			local m = adult(h, p, "cindlet", 1)
			expect(h:Call(p, "HallOfFame.Retire", { id = m.id }).stardust).toBe(Config.Rarities.List[1].stardust)
		end)
	end)
end
