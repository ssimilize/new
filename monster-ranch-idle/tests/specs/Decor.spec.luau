-- Glow-up Z: build your ranch. The piece catalogue and its art budget, the pure placement rules in
-- Logic/DecorLayout (bounds, keep-outs, pen rails, overlaps, rotation, caps by level, migration),
-- and Systems/Decor: the starter set, Decor.Save (take from / return to storage, replication on
-- global.Plots), exploits (unowned, out of bounds, over cap, overlapping, bad payloads, spam) and the
-- move of old pen-slot decor onto the layout with its mood aura kept.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Art = t.Shared("Config.DecorArt")
	local Layout = t.Shared("Logic.DecorLayout")
	local L = Config.Decor.Layout

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Ranch", "Plots", "Decor" }

	local function boot()
		return TestKernel.new({ systems = SYSTEMS })
	end

	local function e(id, x, z, rot)
		return { id = id, x = x, z = z, rot = rot or 0 }
	end

	-- A free outdoor spot row along the plot's back (z = -25 grid = -50 studs), clear of pens.
	local function row(id, n)
		local list = {}
		for i = 1, n do
			table.insert(list, e(id, -30 + (i - 1) * 3, -25))
		end
		return list
	end

	describe("Decor catalogue", function()
		it("has 60+ new pieces, every one parts-only within the budget, with a mesh slot", function()
			local new, models = 0, {}
			for _, def in Config.Decor.List do
				if (def.mood or 0) == 0 then
					new += 1
				end
				expect(Art.Models[def.model] ~= nil).toBe(true)
				models[def.model] = true
				expect(def.mesh).toBe("")
				expect(type(def.size[1]) == "number" and type(def.size[2]) == "number").toBe(true)
				local pieces = Art.Pieces(def)
				expect(#pieces >= 1 and #pieces <= L.maxParts).toBe(true)
				if def.light then
					local glows = false
					for _, piece in pieces do
						glows = glows or piece.glow == true
					end
					expect(glows).toBe(true)
				end
				if def.kind == "toy" then
					expect(def.spot).toBe("toy")
				end
				expect(def.price ~= nil).toBe(true)
			end
			expect(new >= 60).toBe(true)
		end)

		it("has a free starter set, an event set per event and earnable pieces in every kind", function()
			local starter, byEvent, free = 0, {}, {}
			for _, def in Config.Decor.List do
				if def.starter then
					starter += 1
					expect(def.price.coins ~= nil).toBe(true)
				end
				if def.event then
					byEvent[def.event] = (byEvent[def.event] or 0) + 1
					expect(def.price.token ~= nil).toBe(true)
				elseif def.price.coins or def.price.friendship then
					free[def.kind] = true
				end
			end
			expect(starter >= 6).toBe(true)
			for _, eventId in { "frostfall", "springbloom", "lunarlanterns", "summersplash", "harvestmoon" } do
				expect((byEvent[eventId] or 0) >= 5).toBe(true)
			end
			for _, kind in { "fence", "path", "light", "water", "plant", "seat", "arch", "statue", "toy", "fun" } do
				expect(free[kind]).toBe(true)
			end
		end)
	end)

	describe("DecorLayout", function()
		it("scales the piece cap with Ranch Level from 20 to 80", function()
			expect(Layout.Cap(1)).toBe(20)
			expect(Layout.Cap(9)).toBe(20)
			expect(Layout.Cap(10)).toBe(30)
			expect(Layout.Cap(35)).toBe(50)
			expect(Layout.Cap(60)).toBe(80)
			expect(Layout.Cap(70)).toBe(80)
		end)

		it("turns footprints in 45° steps", function()
			local fence = Config.Decor.ById.rail_fence -- 4 x 1
			local hx, hz = Layout.Half(fence, 0)
			expect(hx).toBe(2)
			expect(hz).toBe(0.5)
			hx, hz = Layout.Half(fence, 2)
			expect(hx).toBe(0.5)
			expect(hz).toBe(2)
			hx, hz = Layout.Half(fence, 1)
			expect(math.abs(hx - 5 / (2 * math.sqrt(2))) < 1e-9).toBe(true)
			expect(hx).toBe(hz)
			expect(Layout.Half(fence, 4)).toBe(2)
		end)

		it("keeps pieces inside the plot and off the aisle, gate, pad, barn, statues and garden", function()
			expect(Layout.Check(e("barrel", -30, -25))).toBeNil()
			expect(Layout.Check(e("barrel", 37, -25))).toBe("That spot is outside your ranch")
			expect(Layout.Check(e("barrel", 0, 28))).toBe("That spot is outside your ranch")
			expect(Layout.Check(e("barrel", 0, -1))).toBe("That spot is blocked") -- the aisle
			expect(Layout.Check(e("barrel", -32, -1))).toBe("That spot is blocked") -- incubator pad
			expect(Layout.Check(e("barrel", 29, 21))).toBe("That spot is blocked") -- barn
			expect(Layout.Check(e("barrel", -15, 22))).toBe("That spot is blocked") -- statue row
			expect(Layout.Check(e("barrel", 21, 22))).toBe("That spot is blocked") -- garden
			expect(Layout.Check(e("nope", 0, 0))).toBe("That decor doesn't exist")
		end)

		it("allows a pen's free floor but not its rails or prop spots", function()
			-- Pen 1 is centred at (-38, -24) studs = (-19, -12) grid, 34 x 28.
			local inside = e("swing_set", -22, -15, 1)
			expect(Layout.Check(inside)).toBeNil()
			expect(Layout.PenOf(inside)).toBe(1)
			expect(Layout.Check(e("barrel", -19, -19))).toBe("Keep decor clear of the pen fences") -- on the rail
			expect(Layout.Check(e("barrel", -19, -11))).toBe("That spot is blocked") -- the habitat spot
			expect(Layout.PenOf(e("barrel", -30, -25))).toBeNil()
		end)

		it("rotation can make a piece fit or not", function()
			-- A 6 x 2 swing set whose long side runs along z crosses pen 1's back rail at this spot.
			expect(Layout.Check(e("swing_set", -22, -18, 0))).toBeNil()
			expect(Layout.Check(e("swing_set", -22, -18, 2))).toBe("Keep decor clear of the pen fences")
		end)

		it("finds overlaps, but flat paths only meet flat pieces", function()
			local a, b = e("barrel", -30, -25), e("barrel", -30, -25)
			expect(Layout.Overlaps(a, b)).toBe(true)
			expect(Layout.Overlaps(e("barrel", -30, -25), e("barrel", -29, -25))).toBe(false) -- touching
			expect(Layout.Overlaps(e("stone_path", -30, -25), e("park_bench", -30, -25))).toBe(false)
			expect(Layout.Overlaps(e("stone_path", -30, -25), e("brick_path", -29, -25))).toBe(true)
			local problems = Layout.Problems({ a, b, e("barrel", 0, 0) })
			expect(problems[1]).toBe("Decorations can't overlap")
			expect(problems[3]).toBe("That spot is blocked")
		end)

		it("validates ownership, the cap and every piece", function()
			local list = row("barrel", 3)
			expect(Layout.Validate(list, 1, { barrel = 3 })).toBe(true)
			local ok, err = Layout.Validate(list, 1, { barrel = 2 })
			expect(ok).toBe(false)
			expect(err).toBe("You don't own enough of that decor")
			local many = {}
			for i = 1, 21 do
				table.insert(many, e("barrel", -34 + ((i - 1) % 11) * 3, if i > 11 then -23 else -26))
			end
			ok, err = Layout.Validate(many, 1, { barrel = 30 })
			expect(ok).toBe(false)
			expect(err).toContain("up to 20")
			expect(Layout.Validate(many, 10, { barrel = 30 })).toBe(true)
			local index
			ok, err, index = Layout.Validate({ list[1], e("barrel", 0, 0) }, 1, { barrel = 2 })
			expect(err).toBe("That spot is blocked")
			expect(index).toBe(2)
		end)

		it("moves old pen slots onto the layout inside the same pen", function()
			local placed, leftover = Layout.Migrate({ [1] = { "hay_bale", "lantern", "fountain" }, [4] = { "tide_pool" } }, {})
			expect(#placed).toBe(4)
			expect(#leftover).toBe(0)
			for _, entry in placed do
				expect(Layout.Check(entry)).toBeNil()
			end
			expect(Layout.PenOf(placed[1])).toBe(1)
			expect(Layout.PenOf(placed[4])).toBe(4)
			expect(Layout.Validate(placed, 1, { hay_bale = 1, lantern = 1, fountain = 1, tide_pool = 1 })).toBe(true)
			expect(Layout.PenDecor(placed, 1, 3)).toEqual({ "fountain", "lantern", "hay_bale" })
		end)
	end)

	describe("Decor system", function()
		it("grants the starter set once", function()
			local h = boot()
			local p = h:Join()
			expect(h:Section(p, "Shop").decor.picket_fence).toBe(Config.Decor.ById.picket_fence.starter)
			expect(h:Section(p, "Decor").starter).toBe(true)
			local again = h:Rejoin(p)
			expect(h:Section(again, "Shop").decor.picket_fence).toBe(Config.Decor.ById.picket_fence.starter)
		end)

		it("saves a layout from storage, replicates it and returns removed pieces", function()
			local h = boot()
			local p = h:Join()
			local other = h:Join()
			local Shop = h:System("Shop")
			Shop:AddDecor(p, "swing_set", 1)
			local layout = { e("swing_set", -22, -15, 1), e("park_bench", -30, -25, 0) }
			expect(h:Call(p, "Decor.Save", { layout = layout }).count).toBe(2)
			expect(Shop:DecorCount(p, "swing_set")).toBe(0)
			expect(Shop:DecorCount(p, "park_bench")).toBe(Config.Decor.ById.park_bench.starter - 1)
			expect(h:Client(p).profile.Decor.layout).toEqual(layout)
			h:Advance(Config.Social.PlotRefreshSeconds + 1)
			local plot = h:System("Plots"):GetPlot(p)
			expect(h:Client(other).global.Plots[plot].layout).toEqual(layout)
			expect(h:System("Decor"):Layout(p)).toEqual(layout)

			-- Moving a piece keeps the count; removing puts it back in storage.
			h:Advance(3)
			h:Call(p, "Decor.Save", { layout = { e("swing_set", -30, -24, 0) } })
			expect(Shop:DecorCount(p, "swing_set")).toBe(0)
			expect(Shop:DecorCount(p, "park_bench")).toBe(Config.Decor.ById.park_bench.starter)
			h:Advance(3)
			h:Call(p, "Decor.Save", { layout = {} })
			expect(Shop:DecorCount(p, "swing_set")).toBe(1)

			-- A rejoin keeps the layout.
			h:Advance(3)
			h:Call(p, "Decor.Save", { layout = { e("swing_set", -30, -24, 3) } })
			local back = h:Rejoin(p)
			expect(h:Section(back, "Decor").layout).toEqual({ e("swing_set", -30, -24, 3) })
		end)

		it("refuses unowned pieces, bad spots, overlaps, the cap, bad payloads and spam", function()
			local h = boot()
			local p = h:Join()
			local Shop = h:System("Shop")
			expect(h:Reject(p, "Decor.Save", { layout = { e("garden_fountain", -30, -25) } })).toBe("You don't own enough of that decor")
			h:Advance(3)
			local fences = Config.Decor.ById.picket_fence.starter
			expect(h:Reject(p, "Decor.Save", { layout = row("picket_fence", fences + 1) })).toBe("You don't own enough of that decor")
			h:Advance(3)
			expect(h:Reject(p, "Decor.Save", { layout = { e("barrel", 36, -25) } })).toBe("You don't own enough of that decor")
			Shop:AddDecor(p, "barrel", 40)
			h:Advance(3)
			expect(h:Reject(p, "Decor.Save", { layout = { e("barrel", 37, -25) } })).toBe("That spot is outside your ranch")
			h:Advance(3)
			expect(h:Reject(p, "Decor.Save", { layout = { e("barrel", 0, 0) } })).toBe("That spot is blocked")
			h:Advance(3)
			expect(h:Reject(p, "Decor.Save", { layout = { e("barrel", -30, -25), e("barrel", -30, -25) } })).toBe(
				"Decorations can't overlap"
			)
			h:Advance(3)
			local many = {}
			for i = 1, 21 do
				table.insert(many, e("barrel", -34 + ((i - 1) % 11) * 3, if i > 11 then -23 else -26))
			end
			expect(h:Reject(p, "Decor.Save", { layout = many })).toContain("up to 20")
			expect(Shop:DecorCount(p, "barrel")).toBe(40) -- failures change nothing
			expect(h:Section(p, "Decor").layout).toEqual({})
			h:Advance(3)
			h:Reject(p, "Decor.Save", { layout = { e("barrel", -30, -25, 8) } })
			h:Advance(3)
			h:Reject(p, "Decor.Save", { layout = { { id = "barrel", x = 1.5, z = 0, rot = 0 } } })
			h:Advance(3)
			h:Reject(p, "Decor.Save", { layout = { { id = "not_a_piece", x = 0, z = 0, rot = 0 } } })
			h:Advance(3)
			h:Reject(p, "Decor.Save", { layout = "all of it" })
			-- A higher level lifts the cap.
			h:Section(p, "Progression").level = 10
			h:Advance(3)
			expect(h:Call(p, "Decor.Save", { layout = many }).count).toBe(21)
			-- Spamming saves is rate-limited.
			h:Advance(3)
			local rejected = false
			for _ = 1, 4 do
				local response = h:Invoke(p, "Decor.Save", { layout = many })
				rejected = rejected or response.ok == false
			end
			expect(rejected).toBe(true)
		end)

		it("moves old pen-slot decor onto the layout and keeps its mood aura", function()
			local h = boot()
			local p = h:Join()
			local Shop = h:System("Shop")
			Shop:AddDecor(p, "hay_bale", 1)
			Shop:AddDecor(p, "lantern", 1)
			h:Call(p, "Ranch.PlaceDecor", { decor = "hay_bale", pen = 1 })
			h:Advance(2)
			h:Call(p, "Ranch.PlaceDecor", { decor = "lantern", pen = 1 })
			expect(#h:Section(p, "Ranch").pens[1].decor).toBe(2)
			h:Section(p, "Decor").migrated = false -- a save from before glow-up Z
			local back = h:Rejoin(p)
			expect(h:Section(back, "Ranch").pens[1].decor).toEqual({})
			local layout = h:Section(back, "Decor").layout
			expect(#layout).toBe(2)
			expect(Layout.PenOf(layout[1])).toBe(1)
			expect(h:System("Decor"):PenDecor(back, 1)).toEqual({ "lantern", "hay_bale" })
			expect(h:System("Shop"):DecorCount(back, "hay_bale")).toBe(0)
			-- Migration runs once.
			local again = h:Rejoin(back)
			expect(#h:Section(again, "Decor").layout).toBe(2)
		end)
	end)
end
