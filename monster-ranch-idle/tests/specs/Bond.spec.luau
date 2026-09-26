-- Glow-up Q: bond hearts and care. Pure rules (hearts, cooldowns, income bonus, best friends,
-- save repair, the three gestures) in Logic/Bond; the Bond system's validation, cooldowns and
-- exploit cases (other players' monsters, barn monsters, spam, traded monsters), the income
-- bonus through Ranch, bond tricks through Community, the ranch-gate view and save migration.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Bond")
	local Cfg = Config.Bond
	local G = Cfg.Gesture

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Ranch", "Bond", "Community" }

	local function boot()
		return TestKernel.new({ systems = SYSTEMS })
	end

	local function monster(h, p)
		-- "reward" monsters go straight into the first pen with room.
		local m = h:System("Monsters"):Create(p, { line = "cindlet", rarity = 1 }, "reward", true)
		return m
	end

	local function care(h, p, id, kind)
		h:Advance(Cfg.minGap)
		return h:Call(p, "Bond.Care", { id = id, kind = kind })
	end

	local function reject(h, p, id, kind)
		h:Advance(Cfg.minGap)
		return h:Reject(p, "Bond.Care", { id = id, kind = kind })
	end

	-- Moves the clock without stepping every second (the cooldown is hours long).
	local function skip(h, seconds)
		h.adapters.advance(seconds)
		h:Advance(1)
	end

	describe("Logic/Bond", function()
		it("turns bond points into hearts 0..10 with progress to the next heart", function()
			expect(Logic.Hearts(0, Cfg)).toBe(0)
			expect(Logic.Hearts(Cfg.HeartAt[1], Cfg)).toBe(1)
			expect(Logic.Hearts(Cfg.HeartAt[3] - 1, Cfg)).toBe(2)
			expect(Logic.Hearts(Cfg.HeartAt[#Cfg.HeartAt] + 50, Cfg)).toBe(Cfg.MaxHearts)
			local hearts, into, need = Logic.Progress(Cfg.HeartAt[2] + 1, Cfg)
			expect(hearts).toBe(2)
			expect(into).toBe(1)
			expect(need).toBe(Cfg.HeartAt[3] - Cfg.HeartAt[2])
			local _, _, needAtMax = Logic.Progress(Cfg.HeartAt[#Cfg.HeartAt], Cfg)
			expect(needAtMax).toBe(0)
		end)

		it("pays +1% per 2 hearts, capped at +5%", function()
			expect(Logic.IncomePct(0, Cfg)).toBe(0)
			expect(Logic.IncomePct(1, Cfg)).toBe(0)
			expect(math.abs(Logic.IncomePct(2, Cfg) - 0.01) < 1e-9).toBe(true)
			expect(math.abs(Logic.IncomePct(7, Cfg) - 0.03) < 1e-9).toBe(true)
			expect(math.abs(Logic.IncomePct(10, Cfg) - 0.05) < 1e-9).toBe(true)
			expect(Logic.IncomePct(99, Cfg) <= Cfg.Income.max).toBe(true)
		end)

		it("keeps each kind on its own cooldown", function()
			local entry = { pts = 1, pet = 1000 }
			local ready, left = Logic.Ready(entry, "pet", 1000 + 60, Cfg)
			expect(ready).toBe(false)
			expect(left).toBe(Cfg.cooldown - 60)
			expect((Logic.Ready(entry, "brush", 1060, Cfg))).toBe(true)
			expect((Logic.Ready(entry, "pet", 1000 + Cfg.cooldown, Cfg))).toBe(true)
			expect((Logic.Ready(nil, "play", 5, Cfg))).toBe(true)
		end)

		it("learns tricks at their heart levels and ranks best friends", function()
			expect(#Logic.TricksAt(0, Cfg)).toBe(0)
			expect(#Logic.TricksAt(Cfg.MaxHearts, Cfg)).toBe(#Cfg.Tricks)
			local best = Logic.Best({ m1 = { pts = 3 }, m2 = { pts = 20 }, m3 = { pts = 3 }, m4 = { pts = 0 }, m5 = { pts = 1 } }, 3, Cfg)
			expect(#best).toBe(3)
			expect(best[1].id).toBe("m2")
			expect(best[2].id).toBe("m1") -- ties by id
			expect(best[3].id).toBe("m3")
		end)

		it("repairs a saved section (migration)", function()
			local fixed = Logic.Sanitize({
				list = { m1 = { pts = 9999, pet = 5, junk = 1, brush = "x" }, [3] = { pts = 2 }, m2 = "bad", m3 = { pts = -4 } },
				cares = -2,
			}, Cfg)
			expect(fixed.list.m1.pts).toBe(Cfg.HeartAt[#Cfg.HeartAt])
			expect(fixed.list.m1.pet).toBe(5)
			expect(fixed.list.m1.brush).toBe(nil)
			expect(fixed.list.m1.junk).toBe(nil)
			expect(fixed.list.m2).toBe(nil)
			expect(fixed.list.m3.pts).toBe(0)
			expect(fixed.cares).toBe(0)
			local count = 0
			for _ in fixed.list do
				count += 1
			end
			expect(count).toBe(2)
			expect(next(Logic.Sanitize(nil, Cfg).list)).toBe(nil)
		end)

		it("pets by holding, and never counts time spent not holding", function()
			local g = Logic.Gesture.new("pet", Cfg)
			g:Step(0)
			g:Down(0.5)
			g:Step(2.5)
			g:Up(2.5)
			g:Step(10) -- let go: no progress
			expect(math.abs(g:Progress() - 2 / G.holdSeconds) < 1e-6).toBe(true)
			g:Down(10)
			g:Step(10 + G.holdSeconds)
			expect(g:Done()).toBe(true)
		end)

		it("brushes by turning round after a long enough stroke", function()
			local g = Logic.Gesture.new("brush", Cfg)
			g:Down(0, 100)
			for i = 1, G.strokes - 1 do
				g:Move(i * 0.2, if i % 2 == 1 then 100 + G.strokePixels + 5 else 100)
			end
			expect(g:Done()).toBe(false)
			g:Move(50, 100 + G.strokePixels / 4) -- too short to count
			expect(g.strokes).toBe(G.strokes - 1)
			g:Move(51, if G.strokes % 2 == 1 then 100 + G.strokePixels * 2 else 100 - G.strokePixels * 2)
			expect(g:Done()).toBe(true)
			-- Moving without pressing does nothing.
			local idle = Logic.Gesture.new("brush", Cfg)
			idle:Move(0, 0)
			idle:Move(1, 500)
			expect(idle:Progress()).toBe(0)
		end)

		it("plays by tapping on the bounce, once per bounce", function()
			local g = Logic.Gesture.new("play", Cfg)
			g:Step(0)
			g:Tap(G.beat * 0.5) -- between bounces
			g:Tap(G.beat)
			g:Tap(G.beat + 0.05) -- same bounce again
			expect(g.taps).toBe(1)
			for i = 2, G.taps do
				g:Down(i * G.beat)
				g:Up(i * G.beat + 0.1)
			end
			expect(g:Done()).toBe(true)
			expect(g:Beat(0)).toBe(1)
		end)

		it("gives every kind a hold version for a gamepad or keyboard", function()
			for _, kind in Cfg.KindIds do
				local g = Logic.Gesture.new(kind, Cfg, true)
				g:Down(0)
				g:Step(G.holdSeconds)
				expect(g:Done()).toBe(true)
			end
		end)
	end)

	describe("Bond system", function()
		it("adds a heart for caring, once per kind per monster per cooldown", function()
			local h = boot()
			local p = h:Join()
			local m = monster(h, p)
			expect(h:System("Ranch"):PenOf(p, m.id) > 0).toBe(true)
			local first = care(h, p, m.id, "pet")
			expect(first.hearts).toBe(1)
			expect(first.points).toBe(1)
			expect(first.gained).toBe(true)
			expect(reject(h, p, m.id, "pet")).toContain("already loved that")
			expect(care(h, p, m.id, "brush").points).toBe(2)
			expect(care(h, p, m.id, "play").points).toBe(3)
			expect(h:Client(p).profile.Bond.list[m.id].pts).toBe(3)
			expect(h:System("Bond"):Hearts(p, m.id)).toBe(2)
			skip(h, Cfg.cooldown)
			expect(care(h, p, m.id, "pet").points).toBe(4)
			expect(h:Section(p, "Bond").cares).toBe(4)
			-- Another monster has its own cooldowns.
			local other = monster(h, p)
			expect(care(h, p, other.id, "pet").points).toBe(1)
		end)

		it("refuses other players' monsters, barn monsters, bad kinds and spam", function()
			local h = boot()
			local p = h:Join()
			local rival = h:Join()
			local mine = monster(h, p)
			monster(h, rival)
			monster(h, rival)
			local theirs = monster(h, rival) -- ids count per player: this one only exists for the rival
			expect(h:System("Monsters"):Get(p, theirs.id)).toBe(nil)
			expect(reject(h, p, theirs.id, "pet")).toContain("doesn't exist")
			expect(reject(h, p, "m999", "pet")).toContain("doesn't exist")
			h:Advance(2)
			expect(h:Reject(p, "Bond.Care", { id = mine.id, kind = "feed" }) ~= nil).toBe(true)
			-- Spam: a second bond-adding care inside minGap is refused, and so is a burst of requests.
			care(h, p, mine.id, "pet")
			h:Advance(1)
			expect(h:Reject(p, "Bond.Care", { id = mine.id, kind = "brush" })).toContain("moment")
			local refused = 0
			for _ = 1, 5 do
				if not h:Invoke(p, "Bond.Care", { id = mine.id, kind = "play" }).ok then
					refused += 1
				end
			end
			expect(refused).toBe(5)
			expect(h:Section(p, "Bond").list[mine.id].pts).toBe(1)
			-- A monster moved to the barn can't be cared for.
			local barn = monster(h, p)
			h:Advance(1)
			h:Call(p, "Ranch.Assign", { id = barn.id, pen = 0 })
			expect(reject(h, p, barn.id, "pet")).toContain("pens")
			expect(h:Section(p, "Bond").list[barn.id]).toBe(nil)
		end)

		it("forgets a monster that leaves, so traded monsters arrive with no bond", function()
			local h = boot()
			local seller = h:Join()
			local buyer = h:Join()
			local m = monster(h, seller)
			h:Section(seller, "Bond").list[m.id] = { pts = Cfg.HeartAt[9] }
			local Monsters = h:System("Monsters")
			local record = Monsters:Remove(seller, m.id, "trade")
			expect(record ~= nil).toBe(true)
			expect(h:Section(seller, "Bond").list[m.id]).toBe(nil)
			local arrived = Monsters:Insert(buyer, record, "trade")
			expect(h:System("Bond"):Hearts(buyer, arrived.id)).toBe(0)
			h:Call(buyer, "Ranch.Assign", { id = arrived.id, pen = 1 })
			expect(care(h, buyer, arrived.id, "pet").hearts).toBe(1)
			-- Retiring or selling forgets it too; nothing is refunded or carried.
			local pet = monster(h, seller)
			h:Section(seller, "Bond").list[pet.id] = { pts = 10 }
			Monsters:Remove(seller, pet.id, "retire")
			expect(h:Section(seller, "Bond").list[pet.id]).toBe(nil)
		end)

		it("keeps bond over a rejoin and drops entries of monsters that are gone", function()
			local h = boot()
			local p = h:Join()
			local m = monster(h, p)
			care(h, p, m.id, "pet")
			h:Section(p, "Bond").list.m404 = { pts = 30 }
			p = h:Rejoin(p, 3 * 24 * 3600) -- days away: no decay
			h:Advance(1)
			expect(h:Section(p, "Bond").list[m.id].pts).toBe(1)
			expect(h:Section(p, "Bond").list.m404).toBe(nil)
		end)

		it("repairs an older save section through Migrate", function()
			local h = boot()
			local fixed = h:System("Bond").Profile.Migrate({ list = { m1 = { pts = "3", play = 7 } }, cares = 2.5 }, 0)
			expect(fixed.list.m1.pts).toBe(3)
			expect(fixed.list.m1.play).toBe(7)
			expect(fixed.cares).toBe(2)
		end)

		it("adds +1% of that monster's own income per 2 hearts, capped at +5%", function()
			local h = boot()
			local p = h:Join()
			local m = monster(h, p)
			local base = h:Session(p, "Ranch").income
			expect(base > 0).toBe(true)
			local s = h:Section(p, "Bond")
			s.list[m.id] = { pts = Cfg.HeartAt[3] } -- 3 hearts
			care(h, p, m.id, "pet") -- to 4 hearts' threshold? only if it crosses; refresh either way
			h:System("Ranch"):Refresh(p)
			local hearts = h:System("Bond"):Hearts(p, m.id)
			local want = base * (1 + Logic.IncomePct(hearts, Cfg))
			expect(math.abs(h:Session(p, "Ranch").income - want) < 1e-6).toBe(true)
			s.list[m.id].pts = Cfg.HeartAt[#Cfg.HeartAt]
			h:System("Ranch"):Refresh(p)
			expect(math.abs(h:Session(p, "Ranch").income - base * 1.05) < 1e-6).toBe(true)
		end)

		it("teaches bond tricks: Community.Trick refuses them below their hearts", function()
			local h = boot()
			local p = h:Join()
			local m = monster(h, p)
			local sit = Config.Community.TrickById.sit
			expect(sit.bond).toBe(3)
			h:Advance(2)
			expect(h:Reject(p, "Community.Trick", { id = m.id, trick = "sit" })).toContain("bond hearts")
			h:Section(p, "Bond").list[m.id] = { pts = Cfg.HeartAt[3] - 1 }
			local result = care(h, p, m.id, "play")
			expect(result.hearts).toBe(3)
			expect(result.learned).toBe("sit")
			h:Advance(Config.Community.TrickCooldown)
			expect(h:Call(p, "Community.Trick", { id = m.id, trick = "sit" }).state).toBe("sit")
			-- The emote wheel's list is unchanged.
			for _, trick in Config.Community.Tricks do
				expect(trick.bond).toBe(nil)
			end
		end)

		it("shows the top three at the ranch gate and nameplates from high bond", function()
			local h = boot()
			local p = h:Join()
			local viewer = h:Join()
			local ids = {}
			for i = 1, 5 do
				ids[i] = monster(h, p).id
			end
			local s = h:Section(p, "Bond")
			s.list[ids[1]] = { pts = Cfg.HeartAt[Cfg.NameplateHearts] }
			s.list[ids[2]] = { pts = 2 }
			s.list[ids[3]] = { pts = 1 }
			care(h, p, ids[4], "pet") -- 1 point: ties with ids[3], ranked by id
			h:Advance(1)
			local here = h:Client(viewer).global.Bond.here["u" .. p.UserId]
			expect(here ~= nil).toBe(true)
			expect(#here.best).toBe(3)
			expect(here.best[1].id).toBe(ids[1])
			expect(here.best[1].hearts).toBe(Cfg.NameplateHearts)
			expect(type(here.best[1].form)).toBe("string")
			expect(#here.plates).toBe(1)
			expect(here.plates[1].id).toBe(ids[1])
			h:System("Monsters"):Remove(p, ids[1], "sell")
			h:Advance(1)
			here = h:Client(viewer).global.Bond.here["u" .. p.UserId]
			expect(#here.plates).toBe(0)
			expect(here.best[1].id).toBe(ids[2])
			h:Leave(p)
			h:Advance(1)
			expect(h:Client(viewer).global.Bond.here["u" .. p.UserId]).toBe(nil)
		end)
	end)
end
