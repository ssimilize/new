-- S5 Plots: plot assignment and freeing, the public plot view and refresh throttling.
-- Ranch, Eggs and HallOfFame are stubbed; Social is real (likes).
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")

	local function boot(withStubs)
		local env = { pens = {}, slots = {}, statues = {}, penCalls = 0 }
		local stubs = nil
		if withStubs ~= false then
			stubs = {
				Ranch = {
					PublicPens = function(_, player)
						env.penCalls += 1
						return env.pens[player.UserId] or {}
					end,
					RegisterRateModifier = function() end,
				},
				Eggs = {
					PublicSlots = function(_, player)
						return env.slots[player.UserId] or {}
					end,
				},
				HallOfFame = {
					Statues = function(_, player)
						return env.statues[player.UserId] or {}
					end,
				},
			}
		end
		local h = TestKernel.new({
			systems = { "Currency", "Progression", "Rewards", "Monsters", "Social", "Plots" },
			stubs = stubs,
		})
		return h, env
	end

	local function plots(h)
		return h.kernel.State:GlobalRoot("Plots")
	end

	describe("Plots", function()
		it("always publishes six plots and hands out the lowest free one", function()
			local h = boot()
			expect(#plots(h)).toBe(6)
			for _, plot in plots(h) do
				expect(plot.userId).toBe(0)
			end
			local P = h:System("Plots")
			local a, b, c = h:Join(nil, "Ann"), h:Join(nil, "Ben"), h:Join(nil, "Cal")
			expect(P:GetPlot(a)).toBe(1)
			expect(P:GetPlot(b)).toBe(2)
			expect(P:GetPlot(c)).toBe(3)
			local view = h:Client(a).global.Plots
			expect(#view).toBe(6)
			expect(view[2].userId).toBe(b.UserId)
			expect(view[2].name).toBe("Ben")
			expect(view[2].level).toBe(1)
			expect(view[4].userId).toBe(0)

			h:Leave(b)
			expect(P:GetPlot(b)).toBeNil()
			expect(plots(h)[2].userId).toBe(0)
			expect(h:Client(a).global.Plots[2].userId).toBe(0)
			local d = h:Join(nil, "Dee")
			expect(P:GetPlot(d)).toBe(2)
			for _ = 1, 3 do
				h:Join()
			end
			local extra = h:Join()
			expect(P:GetPlot(extra)).toBeNil()
			expect(#plots(h)).toBe(6)
		end)

		it("shows pens with monster appearances, statues, incubators, level and likes", function()
			local h, env = boot()
			local owner, visitor = h:Join(nil, "Owner"), h:Join()
			local M = h:System("Monsters")
			local m = M:Create(owner, { line = "cindlet", rarity = 4, variant = 1 }, "test", true)
			env.pens[owner.UserId] = { { theme = "meadow", decor = { "hay_bale" }, monsters = { m.id, "m404" } } }
			env.slots[owner.UserId] = { { type = "grove", endsAt = 123 } }
			local statues = {}
			for i = 1, 20 do
				statues[i] = { line = "cindlet", rarity = 5, i = i }
			end
			env.statues[owner.UserId] = statues
			h:System("Plots"):Refresh(owner)
			h:Advance(Config.Social.PlotRefreshSeconds)
			local plot = h:Client(visitor).global.Plots[1]
			expect(plot.userId).toBe(owner.UserId)
			expect(#plot.pens).toBe(1)
			expect(plot.pens[1].theme).toBe("meadow")
			expect(plot.pens[1].decor).toEqual({ "hay_bale" })
			expect(#plot.pens[1].monsters).toBe(1) -- unknown ids are skipped
			expect(plot.pens[1].monsters[1].id).toBe(m.id)
			expect(plot.pens[1].monsters[1].appearance.variant).toBe(1)
			expect(#plot.statues).toBe(Config.Social.PlotMaxStatues)
			expect(plot.incubators).toEqual({ { type = "grove", endsAt = 123 } })

			h:Call(visitor, "Social.Like", { owner = owner.UserId })
			h:Advance(Config.Social.PlotRefreshSeconds)
			expect(h:Client(visitor).global.Plots[1].likes).toBe(1)

			h:System("Progression"):AddXP(owner, 1000, "test")
			h:Advance(Config.Social.PlotRefreshSeconds)
			expect(h:Client(visitor).global.Plots[1].level).toBe(h:System("Progression"):GetLevel(owner))
		end)

		it("throttles rebuilds to one per interval and ignores invisible changes", function()
			local h, env = boot()
			local p = h:Join()
			local M = h:System("Monsters")
			local m = M:Create(p, { line = "cindlet", rarity = 1 }, "test", true)
			h:Advance(2 * Config.Social.PlotRefreshSeconds + 1) -- let the creation's rebuilds settle
			local before = env.penCalls
			M:AddMood(p, m.id, -5) -- mood is not visible on a plot
			expect(env.penCalls).toBe(before)
			for i = 1, 5 do
				m.lv = i + 1
				M:Changed(p, m.id, { "lv" })
			end
			expect(env.penCalls).toBe(before + 1) -- immediate rebuild
			h:Advance(Config.Social.PlotRefreshSeconds)
			expect(env.penCalls).toBe(before + 2) -- one trailing rebuild for the burst
			h:Advance(10)
			expect(env.penCalls).toBe(before + 2)
			h.kernel.Bus:Publish("EggAdded", p, { id = "e1", type = "meadow", source = "test" })
			expect(env.penCalls).toBe(before + 3)
		end)

		it("works without the optional systems", function()
			local h = boot(false)
			local p = h:Join(nil, "Solo")
			local plot = h:Client(p).global.Plots[1]
			expect(plot.userId).toBe(p.UserId)
			expect(plot.pens).toEqual({})
			expect(plot.statues).toEqual({})
			expect(plot.incubators).toEqual({})
			expect(plot.likes).toBe(0)
		end)
	end)
end
