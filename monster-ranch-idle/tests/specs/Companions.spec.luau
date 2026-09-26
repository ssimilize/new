-- Glow-up T: companions. Companions.Set (own, not busy, not ridden, slot count by VIP), the
-- replicated walkers list and its upkeep (sold, retired, traded, listed, busy, mounted, a new
-- look), leaving, the v1 → v2 save migration and the pure rules in Logic/Companions.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Companions")
	local Cfg = Config.Companions

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Riding", "Companions" }

	local function boot(startTime)
		local vip = {}
		local h = TestKernel.new({
			systems = SYSTEMS,
			startTime = startTime,
			stubs = {
				Monetization = {
					HasPass = function(_, player, key)
						return key == Cfg.VipPass and vip[player.UserId] == true
					end,
				},
			},
		})
		return h, vip
	end

	local function monster(h, p, stage)
		return h:System("Monsters"):Create(p, { line = "zappip", rarity = 3, stage = stage or 3 }, "test", true)
	end

	local function walkers(h, p, viewer)
		return h:Client(viewer or p).global.Companions.walkers["u" .. p.UserId]
	end

	describe("Companions", function()
		it("sets a companion that everyone on the server sees, and sends it home", function()
			local h = boot()
			local p = h:Join()
			local other = h:Join()
			local m = monster(h, p)
			expect(walkers(h, p)).toBeNil()
			local data = h:Call(p, "Companions.Set", { ids = { m.id } })
			expect(data.ids).toEqual({ m.id })
			expect(h:Section(p, "Companions").ids).toEqual({ m.id })
			expect(h:Client(p).profile.Companions.ids).toEqual({ m.id })
			local seen = walkers(h, p, other)
			expect(#seen).toBe(1)
			expect(seen[1].id).toBe(m.id)
			expect(seen[1].appearance.line).toBe("zappip")
			expect(seen[1].appearance.form).toBe(m.form)
			h:Advance(1)
			h:Call(p, "Companions.Set", { ids = {} })
			expect(walkers(h, p, other)).toBeNil()
			expect(h:Section(p, "Companions").ids).toEqual({})
		end)

		it("validates ownership, duplicates, busy and ridden monsters", function()
			local h = boot()
			local p = h:Join()
			local thief = h:Join()
			local m = monster(h, p)
			local b = monster(h, p)
			expect(h:Reject(thief, "Companions.Set", { ids = { m.id } })).toBe("That monster doesn't exist")
			expect(h:Reject(p, "Companions.Set", { ids = { "m999" } })).toBe("That monster doesn't exist")
			h:Advance(1)
			expect(h:Reject(p, "Companions.Set", { ids = { m.id, m.id } })).toBe("Pick each monster once")
			h:System("Monsters"):SetBusy(p, b.id, "expedition")
			h:Advance(1)
			expect(h:Reject(p, "Companions.Set", { ids = { b.id } })).toBe("That monster is busy")
			h:System("Monsters"):SetBusy(p, b.id, "trade")
			h:Advance(1)
			expect(h:Reject(p, "Companions.Set", { ids = { b.id } })).toBe("That monster is busy")
			-- Riding needs Ranch Level 16.
			h:System("Progression"):AddXP(p, 1e7, "test")
			h:Call(p, "Riding.Mount", { id = m.id })
			h:Advance(1)
			expect(h:Reject(p, "Companions.Set", { ids = { m.id } })).toBe("You're riding that monster")
			-- The schema caps the list at MaxSlots.
			local ids = {}
			for i = 1, Cfg.MaxSlots + 1 do
				ids[i] = "m" .. i
			end
			h:Advance(1)
			expect(h:Invoke(p, "Companions.Set", { ids = ids }).ok).toBe(false)
			expect(walkers(h, p)).toBeNil()
		end)

		it("gives VIP Ranchers three slots and everyone else one", function()
			local h, vip = boot()
			local p = h:Join()
			local a, b, c = monster(h, p), monster(h, p, 1), monster(h, p, 2)
			expect(h:Reject(p, "Companions.Set", { ids = { a.id, b.id } })).toBe(
				string.format("Walk with up to %d monsters with VIP Rancher", Cfg.VipSlots)
			)
			vip[p.UserId] = true
			h:Advance(1)
			h:Call(p, "Companions.Set", { ids = { a.id, b.id, c.id } })
			local list = walkers(h, p)
			expect(#list).toBe(3)
			expect(list[2].id).toBe(b.id)
			expect(h:System("Companions"):Slots(p)).toBe(3)
			-- The pass goes away (a refund): the save keeps all three, one is drawn.
			vip[p.UserId] = nil
			local p2 = h:Rejoin(p, 60)
			expect(h:Section(p2, "Companions").ids).toEqual({ a.id, b.id, c.id })
			expect(#walkers(h, p2)).toBe(1)
			expect(walkers(h, p2)[1].id).toBe(a.id)
		end)

		it("drops a companion that is sold, retired, traded away, listed, busy or mounted", function()
			local h, vip = boot()
			local p = h:Join()
			vip[p.UserId] = true
			local M = h:System("Monsters")
			local a, b, c = monster(h, p), monster(h, p), monster(h, p)
			h:Call(p, "Companions.Set", { ids = { a.id, b.id, c.id } })
			M:Remove(p, b.id, "retire")
			expect(h:Section(p, "Companions").ids).toEqual({ a.id, c.id })
			expect(#walkers(h, p)).toBe(2)
			M:Remove(p, c.id, "market")
			expect(h:Section(p, "Companions").ids).toEqual({ a.id })
			M:SetBusy(p, a.id, "trade")
			expect(h:Section(p, "Companions").ids).toEqual({})
			expect(walkers(h, p)).toBeNil()
			M:SetBusy(p, a.id, false)
			h:Advance(1)
			h:Call(p, "Companions.Set", { ids = { a.id } })
			h:System("Progression"):AddXP(p, 1e7, "test")
			h:Call(p, "Riding.Mount", { id = a.id })
			expect(h:Section(p, "Companions").ids).toEqual({})
			expect(walkers(h, p)).toBeNil()
		end)

		it("re-sends a companion's look only when it changes", function()
			local h = boot()
			local p = h:Join()
			local M = h:System("Monsters")
			local a = monster(h, p)
			h:Call(p, "Companions.Set", { ids = { a.id } })
			local before = walkers(h, p)[1].appearance
			M:AddMood(p, a.id, 5)
			expect(walkers(h, p)[1].appearance).toEqual(before)
			M:AddMutation(p, a.id, Config.Mutations.List[1].id)
			local after = walkers(h, p)[1].appearance
			expect(#after.muts).toBe(1)
			expect(Logic.Signature(after) ~= Logic.Signature(before)).toBe(true)
		end)

		it("clears the walkers entry when the player leaves and restores it on rejoin", function()
			local h = boot()
			local p = h:Join()
			local other = h:Join()
			local a = monster(h, p)
			h:Call(p, "Companions.Set", { ids = { a.id } })
			h:Leave(p)
			h:Advance(1)
			expect(walkers(h, p, other)).toBeNil()
			local p2 = h:Join(p.UserId, p.Name)
			expect(walkers(h, p2, other)[1].id).toBe(a.id)
		end)

		it("migrates a v1 single-companion save and drops monsters that are gone", function()
			local h = boot()
			local userId = 5151
			h.adapters.store["player_" .. userId] = {
				v = 1,
				data = {
					_meta = { created = 0, lastSeen = 0, joins = 3, playSeconds = 600, versions = { Companions = 1, Monsters = 1 } },
					Monsters = {
						list = {
							m1 = {
								id = "m1",
								line = "zappip",
								stage = 3,
								form = Config.Species.ById.zappip.forms[3],
								rarity = 2,
								variant = 0,
								muts = {},
								traits = { 1, 2 },
								hidden = 3,
								weight = 4,
								lv = 1,
								stars = 1,
								mood = 50,
								meals = {},
								growEndsAt = 0,
								loc = "barn",
								pen = 0,
								busy = false,
								name = "",
								locked = false,
								born = 0,
								gen = 1,
							},
						},
						codex = {},
						nextId = 2,
						grown = 0,
					},
					Companions = { id = "m1" },
				},
			}
			local p = h:Join(userId, "Walker")
			expect(h:Section(p, "Companions").ids).toEqual({ "m1" })
			expect(h:Section(p, "Companions").id).toBeNil()
			expect(h.kernel.Data:Get(p)._meta.versions.Companions).toBe(2)
			expect(walkers(h, p)[1].id).toBe("m1")

			expect(Logic.Migrate({ id = false }, 1)).toEqual({ ids = {} })
			expect(Logic.Migrate({ ids = { "m1", "m1", 7, "m2", "m3", "m4" } }, 2)).toEqual({ ids = { "m1", "m2", "m3" } })
			-- A saved id whose monster is gone is pruned on join.
			local gone = h:Join(5152, "Gone")
			h:Section(gone, "Companions").ids = { "m44" }
			local back = h:Rejoin(gone, 5)
			expect(h:Section(back, "Companions").ids).toEqual({})
		end)
	end)

	describe("Logic.Companions", function()
		it("walks, eases in, sits after a still moment and hops", function()
			expect(Logic.State("idle", Cfg.StartWalk + 0.1, 0, 0)).toBe("walk")
			expect(Logic.State("walk", Cfg.StopWalk + 0.05, 0, 0)).toBe("walk")
			expect(Logic.State("idle", Cfg.StopWalk + 0.05, 0, 0)).toBe("idle")
			expect(Logic.State("idle", 0, Cfg.SitAfter, 0)).toBe("sit")
			expect(Logic.State("sit", 5, Cfg.SitAfter + 3, 0)).toBe("walk")
			expect(Logic.State("walk", 5, 0, 0.2)).toBe("hop")
			expect(Logic.Speed(0.5, 16)).toBe(0.5 * Cfg.Gain)
			expect(Logic.Speed(100, 16)).toBe(16 * Cfg.CatchUp)
			expect(Logic.Speed(100, 1000)).toBe(Cfg.MaxSpeed)
			expect(Logic.Speed(100, 0)).toBe(Cfg.MinSpeed)
		end)

		it("scales the walk clip with speed and size, within limits", function()
			local slow = Logic.ClipRate(4, 3, 1)
			local fast = Logic.ClipRate(12, 3, 1)
			expect(fast > slow).toBe(true)
			expect(Logic.ClipRate(12, 6, 1) < fast).toBe(true)
			expect(Logic.ClipRate(1000, 3, 1)).toBe(Cfg.MaxRate)
			expect(Logic.ClipRate(0.01, 3, 1)).toBe(Cfg.MinRate)
			expect(Logic.Gait(0, false)).toBe("idle")
			expect(Logic.Gait(20, false)).toBe("walk")
			expect(Logic.Gait(20, true)).toBe("hop")
		end)

		it("spreads a V, picks the nearest within range and gives slots", function()
			local x1 = Logic.Spot(1, 3)
			local x2 = Logic.Spot(2, 3)
			expect(x1 * x2 < 0).toBe(true) -- one each side
			local bigX = Logic.Spot(1, 9)
			expect(math.abs(bigX) > math.abs(x1)).toBe(true)
			local picked = Logic.Pick(
				{ { distance = 50, k = "c" }, { distance = 5, k = "a" }, { distance = 500, k = "far" }, { distance = 9, k = "b" } },
				2,
				100
			)
			expect(#picked).toBe(2)
			expect(picked[1].k).toBe("a")
			expect(picked[2].k).toBe("b")
			expect(#Logic.Pick({ { distance = 500 } }, 5, 100)).toBe(0)
			expect(Logic.Slots(false)).toBe(Cfg.Slots)
			expect(Logic.Slots(true)).toBe(Cfg.VipSlots)
			expect(Cfg.MaxSlots >= Cfg.VipSlots and Cfg.MaxSlots >= Cfg.Slots).toBe(true)
		end)
	end)
end
