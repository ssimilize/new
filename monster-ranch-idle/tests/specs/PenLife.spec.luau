--[[
	PenLife (glow-up S, living pens): Logic/PenLife and Config/PenLife as pure unit tests. Trait
	tendencies, night and day, weather reactions, greetings at the fence, chase pairing, pen bounds,
	separation and steering maths. The client side (PenBrain in World) is PenLifeClient.spec.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local Config = t.Shared("Config")
	local Cfg = t.Shared("Config.PenLife")
	local PenLife = t.Shared("Logic.PenLife")

	local function day(extra)
		local s = { night = false, weather = "clear", lowGraphics = false, hasMate = true }
		for k, v in extra or {} do
			s[k] = v
		end
		return s
	end

	-- How often each action comes up over an even sweep of rolls (deterministic).
	local function share(tendency, s, N: number?)
		local n = N or 400
		local counts = {}
		for k = 0, n - 1 do
			local action = PenLife.Choose(tendency, s, (k + 0.5) / n)
			counts[action] = (counts[action] or 0) + 1
		end
		for key, value in counts do
			counts[key] = value / n
		end
		return counts
	end

	describe("PenLife data", function()
		it("gives every real trait a tendency and names no trait that does not exist", function()
			for _, trait in Config.Traits.List do
				expect(type(Cfg.Traits[trait.key])).toBe("table")
			end
			for key in Cfg.Traits do
				expect(Config.Traits.ByKey[key] ~= nil).toBe(true)
			end
		end)

		it("has a reaction for every weather and a hold for every action", function()
			for _, weather in Config.Weather.List do
				expect(type(Cfg.Weather[weather.id])).toBe("table")
			end
			for _, action in PenLife.Actions do
				if action ~= "wander" and action ~= "chase" then
					expect(Cfg.Hold[action] ~= nil).toBe(true)
				end
			end
			for kind, icon in Cfg.Bubbles.icons do
				expect(type(kind)).toBe("string")
				expect(#icon > 0).toBe(true)
			end
		end)
	end)

	describe("Trait tendencies", function()
		it("merges traits over the neutral base, by id or by key", function()
			local neutral = PenLife.Tendency({})
			for key, value in Cfg.Base do
				expect(neutral[key]).toBe(value)
			end
			local byKey = PenLife.Tendency({ "glutton" })
			local byId = PenLife.Tendency({ Config.Traits.ByKey.glutton.id })
			expect(byKey.eat).toBeNear(Cfg.Base.eat * 3.2, 1e-9)
			expect(byId.eat).toBe(byKey.eat)
			expect(byKey.eatLong).toBeNear(1.8, 1e-9)
			expect(byKey.seekFood).toBe(true)
			expect(PenLife.Tendency({ 999, "nope" }).eat).toBe(Cfg.Base.eat)
		end)

		it("shows the hidden trait only once it is revealed (Adult)", function()
			local record = { traits = { 1, 2 }, hidden = 19, stage = 2 }
			expect(#PenLife.TraitIds(record)).toBe(2)
			record.stage = 3
			local ids = PenLife.TraitIds(record)
			expect(#ids).toBe(3)
			expect(ids[3]).toBe(19)
			expect(#PenLife.TraitIds(nil)).toBe(0)
		end)

		it("makes gluttons eat, lazy ones nap, brawlers spar and shy ones hug the fence", function()
			local s = day()
			local neutral = share(PenLife.Tendency({}), s)
			local glutton = share(PenLife.Tendency({ "glutton" }), s)
			local lazy = share(PenLife.Tendency({ "hearty" }), s)
			local brawny = share(PenLife.Tendency({ "brawny" }), s)
			local show = share(PenLife.Tendency({ "show_off" }), s)
			local cheerful = share(PenLife.Tendency({ "cheerful" }), s)
			expect(glutton.eat > neutral.eat * 2).toBe(true)
			expect((lazy.nap or 0) + (lazy.sit or 0) > ((neutral.nap or 0) + (neutral.sit or 0)) * 2).toBe(true)
			expect((brawny.spar or 0) > (neutral.spar or 0) * 5).toBe(true)
			expect((show.trick or 0) > (neutral.trick or 0) * 2).toBe(true)
			expect((cheerful.chase or 0) > (neutral.chase or 0) * 2).toBe(true)
			expect(PenLife.Tendency({ "lucky_paw" }).edge > PenLife.Tendency({}).edge * 4).toBe(true)
			-- Glutton meals last longer.
			local t = PenLife.Tendency({ "glutton" })
			expect(PenLife.Hold("eat", t, 0.5)).toBeNear(PenLife.Hold("eat", nil, 0.5) * 1.8, 1e-9)
		end)

		it("has a visible difference for every trait against the neutral monster", function()
			local neutral = PenLife.Tendency({})
			for key in Cfg.Traits do
				local tendency = PenLife.Tendency({ key })
				local differs = false
				for field, value in tendency do
					if field ~= "keys" and neutral[field] ~= value then
						differs = true
					end
				end
				expect(differs).toBe(true)
			end
		end)
	end)

	describe("Night and day", function()
		it("sends everyone to the pile at night except night owls", function()
			local night = { night = true, weather = "clear", hasMate = true, dawnIn = 300 }
			local neutral = PenLife.Tendency({})
			local owl = PenLife.Tendency({ "night_owl" })
			expect(PenLife.Asleep(neutral, night)).toBe(true)
			expect(PenLife.Choose(neutral, night, 0.3)).toBe("sleep")
			expect(PenLife.Asleep(owl, night)).toBe(false)
			for k = 0, 99 do
				local action = PenLife.Choose(owl, night, (k + 0.5) / 100)
				expect(action ~= "sleep" and action ~= "nap" and action ~= "chase").toBe(true)
			end
			expect(PenLife.Asleep(neutral, day())).toBe(false)
		end)

		it("wakes early birds before dawn and lets stargazers sit up", function()
			local bee = PenLife.Tendency({ "busy_bee" })
			expect(PenLife.Asleep(bee, { night = true, dawnIn = Cfg.EarlyBirdLead + 30 })).toBe(true)
			expect(PenLife.Asleep(bee, { night = true, dawnIn = Cfg.EarlyBirdLead - 1 })).toBe(false)
			expect(PenLife.Asleep(PenLife.Tendency({}), { night = true, dawnIn = 1 })).toBe(true)
			local gazer = PenLife.Tendency({ "stargazer" })
			local night = { night = true, dawnIn = 300 }
			expect(PenLife.Choose(gazer, night, 0.1)).toBe("stargaze")
			expect(PenLife.Choose(gazer, night, 0.9)).toBe("sleep")
		end)
	end)

	describe("Weather", function()
		it("shelters in a storm unless weatherproof or a weather lover", function()
			local storm = day({ weather = "thunderstorm" })
			expect(PenLife.Weight(PenLife.Tendency({}), storm, "shelter")).toBe(Cfg.ShelterWeight)
			expect(share(PenLife.Tendency({}), storm).shelter > 0.4).toBe(true)
			expect(PenLife.Weight(PenLife.Tendency({ "tough_hide" }), storm, "shelter")).toBe(0)
			expect(PenLife.Weight(PenLife.Tendency({ "weather_magnet" }), storm, "shelter")).toBe(0)
			expect(PenLife.Weight(PenLife.Tendency({}), storm, "chase")).toBe(0)
			-- The weather lover dances instead.
			local lover = share(PenLife.Tendency({ "weather_magnet" }), storm)
			expect(lover.cheer > 0.2).toBe(true)
			expect(PenLife.Weight(PenLife.Tendency({}), day(), "shelter")).toBe(0)
		end)

		it("shivers in the snow, basks in the sun by day and shakes off the rain when it starts", function()
			local neutral = PenLife.Tendency({})
			local tough = PenLife.Tendency({ "tough_hide" })
			local snow = day({ weather = "snow" })
			expect(PenLife.Weight(neutral, snow, "shiver")).toBe(Cfg.ShiverWeight)
			expect(PenLife.IdleState(neutral, snow)).toBe("shiver")
			expect(PenLife.IdleState(tough, snow)).toBe("idle")
			expect(PenLife.IdleState(neutral, day())).toBe("idle")
			expect(PenLife.Weight(neutral, day({ weather = "heatwave" }), "bask") > PenLife.Weight(neutral, day(), "bask")).toBe(true)
			expect(PenLife.Weight(neutral, day({ night = true }), "bask")).toBe(0)
			expect(PenLife.Weight(neutral, day({ weather = "rain" }), "bask")).toBe(0)
			expect(PenLife.Onset(neutral, "clear", "rain")).toBe("shake")
			expect(PenLife.Onset(neutral, "rain", "thunderstorm")).toBe(nil)
			expect(PenLife.Onset(neutral, "rain", "rain")).toBe(nil)
			expect(PenLife.Onset(tough, "clear", "rain")).toBe(nil)
			expect(PenLife.WeatherOf("no-such").wet).toBe(nil)
		end)
	end)

	describe("Chase and mates", function()
		it("only chases with a free pen-mate, by day, outside low graphics", function()
			local cheerful = PenLife.Tendency({ "cheerful" })
			expect(PenLife.Weight(cheerful, day(), "chase") > 0).toBe(true)
			expect(PenLife.Weight(cheerful, day({ lowGraphics = true }), "chase")).toBe(0)
			expect(PenLife.Weight(cheerful, day({ hasMate = false }), "chase")).toBe(0)
			expect(PenLife.Weight(cheerful, day({ hasMate = false }), "social")).toBe(0)
			expect(share(cheerful, day({ lowGraphics = true })).chase).toBe(nil)
		end)

		it("picks a free mate other than itself", function()
			local free = { true, false, true, true }
			for k = 0, 9 do
				local mate = PenLife.PickMate(4, 3, free, k / 10)
				expect(mate == 1 or mate == 4).toBe(true)
			end
			expect(PenLife.PickMate(4, 1, { true, false, false, false }, 0.5)).toBe(nil)
			expect(PenLife.PickMate(1, 1, { true }, 0.5)).toBe(nil)
		end)

		it("flees away from the chaser and stays inside the pen, breaking sideways when cornered", function()
			local fx, fz = PenLife.FleePoint(0, 0, -3, 0, 17, 14, 2, 9)
			expect(fx).toBeNear(9, 1e-9)
			expect(fz).toBeNear(0, 1e-9)
			-- Pinned to the +x fence by a chaser on its left: it breaks along the fence.
			local cx, cz = PenLife.FleePoint(14.5, 0, 12, 0, 17, 14, 2, 9)
			expect(math.abs(cx) <= 15 and math.abs(cz) <= 12).toBe(true)
			expect(math.abs(cz) > 4).toBe(true)
		end)
	end)

	describe("Pen maths", function()
		it("keeps wander targets on the pen floor, and shy ones by the fence", function()
			for a = 0, 4 do
				for b = 0, 4 do
					local x, z = PenLife.RandomPoint(a / 4.001, b / 4.001, 0.9, 17, 14, 2.5, 0.12)
					expect(math.abs(x) <= 14.5 + 1e-9 and math.abs(z) <= 11.5 + 1e-9).toBe(true)
					local ex, ez = PenLife.RandomPoint(a / 4.001, b / 4.001, 0, 17, 14, 2.5, 0.85)
					expect(math.abs(ex) <= 14.5 + 1e-9 and math.abs(ez) <= 11.5 + 1e-9).toBe(true)
					-- On (or within a fifth of) one side's band.
					expect(math.abs(ex) >= 14.5 * 0.8 - 1e-9 or math.abs(ez) >= 11.5 * 0.8 - 1e-9).toBe(true)
				end
			end
			local cx, cz = PenLife.Clamp(40, -40, 17, 14, 2)
			expect(cx).toBe(15)
			expect(cz).toBe(-12)
			-- A pen smaller than the margin still has a middle.
			local sx, sz = PenLife.Clamp(5, 5, 1, 1, 3)
			expect(sx).toBe(0.5)
			expect(sz).toBe(0.5)
		end)

		it("greets at the fence nearest the owner, spread along it", function()
			local x1, z1 = PenLife.FencePoint(40, 3, 17, 14, 2, 1, 2.6)
			expect(x1).toBe(15)
			expect(z1).toBe(3)
			local x2, z2 = PenLife.FencePoint(40, 3, 17, 14, 2, 2, 2.6)
			local x3, z3 = PenLife.FencePoint(40, 3, 17, 14, 2, 3, 2.6)
			expect(x2).toBe(15)
			expect(x3).toBe(15)
			expect(z2).toBeNear(0.4, 1e-9)
			expect(z3).toBeNear(5.6, 1e-9)
			local bx, bz = PenLife.FencePoint(2, -30, 17, 14, 2, 9, 2.6)
			expect(bz).toBe(-12)
			expect(math.abs(bx) <= 15).toBe(true)
			expect(PenLife.NearFence(20, 0, 17, 14, 9)).toBe(true)
			expect(PenLife.NearFence(30, 0, 17, 14, 9)).toBe(false)
			expect(PenLife.NearFence(0, 0, 17, 14, 9)).toBe(false)
			expect(PenLife.NearFence(10, 13, 17, 14, 3)).toBe(true)
		end)

		it("pushes overlapping pen-mates apart and leaves distant ones alone", function()
			local xs, zs, rs = { 0, 1, 20 }, { 0, 0, 0 }, { 1, 1, 1 }
			local dx, dz = PenLife.Separation(0, 0, xs, zs, rs, 3, 1, 1, 1.1)
			expect(dx < 0).toBe(true)
			expect(dz).toBeNear(0, 1e-9)
			local fx, fz = PenLife.Separation(20, 0, xs, zs, rs, 3, 3, 1, 1.1)
			expect(fx).toBe(0)
			expect(fz).toBe(0)
			-- Exactly on top of each other: still split.
			local cx, cz = PenLife.Separation(0, 0, { 0, 0 }, { 0, 0 }, { 1, 1 }, 2, 1, 1, 1)
			expect(cx * cx + cz * cz > 0.5).toBe(true)
			-- Decor circles push out, and not from afar.
			local ax = PenLife.Avoid(2, 0, { 0 }, { 0 }, { 1.5 }, 1, 1)
			expect(ax > 0).toBe(true)
			local bx, bz = PenLife.Avoid(9, 0, { 0 }, { 0 }, { 1.5 }, 1, 1)
			expect(bx).toBe(0)
			expect(bz).toBe(0)
		end)

		it("steers a leg toward the goal, bending round pushes, never past the goal", function()
			local wx, wz = PenLife.Steer(0, 0, 10, 0, 0, 0, 0, 0, 3)
			expect(wx).toBeNear(3, 1e-9)
			expect(wz).toBeNear(0, 1e-9)
			local gx, gz = PenLife.Steer(0, 0, 1, 0, 0, 0, 0, 0, 3)
			expect(gx).toBe(1)
			expect(gz).toBe(0)
			local bx, bz = PenLife.Steer(0, 0, 10, 0, 0, 1, 0, 0, 3)
			expect(bz > 0).toBe(true)
			expect(bx * bx + bz * bz).toBeNear(9, 1e-6)
			-- A push straight against the goal side-steps instead of stopping.
			local sx, sz = PenLife.Steer(0, 0, 10, 0, 0, 0, -0.4, 0, 3)
			expect(sx * sx + sz * sz).toBeNear(9, 1e-6)
		end)

		it("heaps the night pile with no two slots on the same spot", function()
			local seen = {}
			for i = 1, 10 do
				local x, z = PenLife.PileSlot(i, 1.5)
				for _, other in seen do
					expect((other[1] - x) ^ 2 + (other[2] - z) ^ 2 > 0.8).toBe(true)
				end
				table.insert(seen, { x, z })
			end
			local x, z = PenLife.PileSlot(1, 1.5)
			expect(x).toBe(0)
			expect(z).toBe(0)
			local rx, rz = PenLife.Ring(1, 4, 3)
			expect(rx).toBeNear(3, 1e-9)
			expect(rz).toBeNear(0, 1e-9)
		end)

		it("turns the short way round, at most the step", function()
			expect(PenLife.TurnYaw(0, 1, 0.25)).toBeNear(0.25, 1e-9)
			expect(PenLife.TurnYaw(0, -1, 0.25)).toBeNear(-0.25, 1e-9)
			expect(PenLife.TurnYaw(0, 0.1, 0.25)).toBe(0.1)
			-- From just left of behind to just right of behind: through the back, not the front.
			local yaw = PenLife.TurnYaw(3, -3, 0.2)
			expect(yaw).toBeNear(3.2, 1e-9)
		end)
	end)

	describe("Think rate and bubbles", function()
		it("thinks less far away and off screen, and follows the knob", function()
			local th = Cfg.Think
			expect(PenLife.ThinkRate(10, true)).toBe(1)
			expect(PenLife.ThinkRate(th.near + 1, true)).toBe(0.5)
			expect(PenLife.ThinkRate(th.mid + 1, true)).toBe(0.25)
			expect(PenLife.ThinkRate(th.far + 1, true)).toBe(0)
			expect(PenLife.ThinkRate(10, false)).toBeNear(th.offScreen, 1e-9)
			expect(PenLife.ThinkRate(10, true, 0.5)).toBe(0.5)
			expect(PenLife.ThinkRate(10, true, 0)).toBe(0)
			expect(PenLife.ThinkRate(10, true, 7)).toBe(1)
		end)

		it("picks a bubble per action and keeps only essentials on low graphics", function()
			expect(PenLife.Bubble("sleep")).toBe("sleep")
			expect(PenLife.Bubble("eat")).toBe("food")
			expect(PenLife.Bubble("greet")).toBe("love")
			expect(PenLife.Bubble("chase")).toBe("music")
			expect(PenLife.Bubble("shake")).toBe("wet")
			expect(PenLife.Bubble("wander")).toBe(nil)
			for kind in Cfg.Bubbles.icons do
				expect(PenLife.BubbleAllowed(kind, false, 0, 6)).toBe(true)
				expect(PenLife.BubbleAllowed(kind, false, 6, 6)).toBe(false)
				expect(PenLife.BubbleAllowed(kind, true, 0, 2)).toBe(Cfg.Bubbles.essential[kind] == true)
			end
			expect(PenLife.BubbleAllowed(nil, false, 0, 6)).toBe(false)
		end)
	end)
end
