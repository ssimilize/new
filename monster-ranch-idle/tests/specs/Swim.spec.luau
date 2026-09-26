-- Deep Reef swimming: the pure maths (Logic/Swim), run against Config.DeepReef.Swim / .Area.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local Swim = t.Shared("Logic.Swim")
	local Config = t.Shared("Config")
	local Cfg = Config.DeepReef.Swim
	local Area = Config.DeepReef.Area

	local function near(a: number, b: number, eps: number?)
		if math.abs(a - b) > (eps or 1e-6) then
			error(string.format("expected %s to be close to %s", tostring(a), tostring(b)), 2)
		end
	end

	local c = Area.center

	describe("Swim.Inside / Clamp", function()
		it("is inside within the radius, the sand and the surface, with slack outside them", function()
			expect(Swim.Inside(c[1], c[2], c[3], Area)).toBe(true)
			expect(Swim.Inside(c[1] + Area.radius + 40, c[2], c[3], Area)).toBe(false)
			expect(Swim.Inside(c[1], Area.floorY - 10, c[3], Area)).toBe(false)
			expect(Swim.Inside(c[1], Area.surfaceY + 10, c[3], Area)).toBe(false)
			expect(Swim.Inside(c[1], Area.floorY - 1, c[3], Area, 2)).toBe(true)
			expect(Swim.Inside(c[1] + Area.radius + 1, c[2], c[3], Area, 2)).toBe(true)
		end)

		it("clamps to the sand, the surface and the edge, flagging what it hit", function()
			local x, y, z, hitY, hitEdge = Swim.Clamp(c[1], Area.floorY - 20, c[3], Area, 3)
			expect(y).toBe(Area.floorY + 3)
			expect(hitY).toBe(true)
			expect(hitEdge).toBe(false)

			x, y, z, hitY, hitEdge = Swim.Clamp(c[1], Area.surfaceY + 20, c[3], Area, 3)
			expect(y).toBe(Area.surfaceY - 3)
			expect(hitY).toBe(true)

			local far = c[1] + Area.radius + 100
			x, y, z, hitY, hitEdge = Swim.Clamp(far, c[2], c[3], Area, 3)
			expect(hitEdge).toBe(true)
			local dx, dz = x - c[1], z - c[3]
			near(math.sqrt(dx * dx + dz * dz), Area.radius - 3, 1e-4)

			-- Well inside: nothing is clamped.
			local midY = (Area.floorY + Area.surfaceY) / 2
			x, y, z, hitY, hitEdge = Swim.Clamp(c[1] + 5, midY, c[3] - 5, Area, 3)
			expect(hitY).toBe(false)
			expect(hitEdge).toBe(false)
			expect(x).toBe(c[1] + 5)
			expect(z).toBe(c[3] - 5)
		end)
	end)

	describe("Swim.Speed", function()
		it("swims on foot at the base speed and a swimmer mount faster, never below the minimum", function()
			expect(Swim.Speed(false, false, nil, Cfg)).toBe(Cfg.speed)
			expect(Swim.Speed(true, false, 40, Cfg)).toBe(Cfg.speed) -- riding a non-swimmer: no boost
			expect(Swim.Speed(true, true, 40, Cfg)).toBe(40 * Cfg.mountFactor)
			expect(Swim.Speed(true, true, 1, Cfg)).toBe(Cfg.speed * Cfg.mountMin)
			expect(Swim.Speed(true, true, 40, Cfg) > Cfg.speed).toBe(true)
		end)
	end)

	describe("Swim.Target", function()
		it("normalises a diagonal move, floats gently with no input, and follows the camera pitch", function()
			-- Swimming (even with a level camera) follows the look, not the idle buoyancy.
			local tx, ty, tz = Swim.Target(1, 1, 0, 0, Cfg.speed, Cfg)
			near(math.sqrt(tx * tx + tz * tz), Cfg.speed, 1e-4)
			near(ty, 0)

			tx, ty, tz = Swim.Target(0, 0, 0, 0, Cfg.speed, Cfg)
			expect(tx).toBe(0)
			expect(tz).toBe(0)
			near(ty, Cfg.buoyancy)

			tx, ty, tz = Swim.Target(0, 0, 1, 0, Cfg.speed, Cfg)
			near(ty, Cfg.vertical)
			tx, ty, tz = Swim.Target(0, 0, -1, 0, Cfg.speed, Cfg)
			near(ty, -Cfg.vertical)

			-- Moving forward with no vertical input: the camera's pitch nudges vertical speed.
			tx, ty, tz = Swim.Target(0, 1, 0, 0.5, Cfg.speed, Cfg)
			near(ty, 0.5 * Cfg.pitchFollow * Cfg.speed)
		end)
	end)

	describe("Swim.Step / Heading / Tilt / Bob", function()
		it("eases toward the target, moves, and stops dead into a wall", function()
			local state = { x = c[1], y = c[2], z = c[3], vx = 0, vy = 0, vz = 0 }
			for _ = 1, 240 do
				Swim.Step(state, 0, 0, Cfg.speed, 1 / 30, Cfg, Area)
			end
			near(state.vz, Cfg.speed, 0.5)
			-- Long enough to reach the far edge and stop advancing past its margin.
			for _ = 1, 600 do
				Swim.Step(state, 0, 0, Cfg.speed, 1 / 30, Cfg, Area)
			end
			local dx, dz = state.x - c[1], state.z - c[3]
			near(math.sqrt(dx * dx + dz * dz), Area.radius - Cfg.margin, 0.5)
		end)

		it("faces the way it swims and keeps the last heading when nearly still", function()
			near(Swim.Heading(0, -5, 0), 0) -- straight -Z (forward) is yaw 0
			near(Swim.Heading(5, 0, 0), -math.pi / 2, 1e-4) -- swimming toward +X turns to face it
			expect(Swim.Heading(0.01, 0.01, 1.23)).toBe(1.23) -- too slow to turn: keeps the old heading
		end)

		it("leans into the swim and noses up or down; sits level at zero speed", function()
			expect(Swim.Tilt(0, 0, 0, 0, Cfg.tilt)).toBe(0)
			local level = Swim.Tilt(0, 0, Cfg.speed, Cfg.speed, Cfg.tilt)
			near(level, -math.rad(Cfg.tilt), 1e-4) -- swimming flat-out forward: full forward lean
			local climbing = Swim.Tilt(0, Cfg.speed, 0, Cfg.speed, Cfg.tilt)
			expect(climbing > level).toBe(true) -- climbing noses up relative to level swimming
		end)

		it("bobs like a sine wave while idle", function()
			near(Swim.Bob(0, Cfg.bob), 0)
			near(Swim.Bob(Cfg.bob.period / 4, Cfg.bob), Cfg.bob.amplitude, 1e-4)
			near(Swim.Bob(Cfg.bob.period / 2, Cfg.bob), 0, 1e-4)
		end)

		it("slows a mount's walk clip into strokes", function()
			expect(Swim.ClipSpeed(10, Cfg)).toBe(10 * Cfg.clipRate)
			expect(Swim.ClipSpeed(0, Cfg)).toBe(0)
		end)
	end)
end
