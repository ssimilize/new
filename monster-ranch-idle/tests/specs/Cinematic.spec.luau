-- Glow-up N: the pure maths of the camera director and the in-world hatch and evolution
-- (Logic/Cinematic) and the Config/Cinematics tuning it runs on.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local Cinematic = t.Shared("Logic.Cinematic")
	local Tuning = t.Shared("Config.Cinematics")
	local CAM, HATCH, EVOLVE = Tuning.Camera, Tuning.Hatch, Tuning.Evolve

	local function near(a: number, b: number, eps: number?)
		if math.abs(a - b) > (eps or 1e-6) then
			error(string.format("expected %s to be close to %s", tostring(a), tostring(b)), 2)
		end
	end

	describe("Cinematic framing", function()
		it("frames from the side the camera is on, at the tuned pitch, within the distance limits", function()
			local ex, ey, ez, lx, ly, lz = Cinematic.Frame(CAM, 10, 2, -5, 4, 10, 30, 40)
			near(lx, 10)
			near(ly, 2 + 4 * CAM.lookUp)
			near(lz, -5)
			near(ex, 10) -- the camera is straight down +Z from the subject, so the eye stays there
			expect(ez > lz).toBe(true)
			local dx, dy, dz = ex - lx, ey - ly, ez - lz
			local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
			expect(distance >= CAM.minDistance - 1e-6 and distance <= CAM.maxDistance + 1e-6).toBe(true)
			near(math.deg(math.asin(dy / distance)), CAM.pitch, 1e-4)
		end)

		it("backs off for bigger subjects and clamps tiny and huge ones", function()
			local function distance(height)
				local ex, ey, ez, lx, ly, lz = Cinematic.Frame(CAM, 0, 0, 0, height, 0, 0, 50)
				return math.sqrt((ex - lx) ^ 2 + (ey - ly) ^ 2 + (ez - lz) ^ 2)
			end
			expect(distance(6) > distance(4)).toBe(true)
			near(distance(0.1), CAM.minDistance)
			near(distance(500), CAM.maxDistance)
		end)

		it("still frames when the camera stands right above the subject", function()
			local ex, _, ez = Cinematic.Frame(CAM, 3, 0, 3, 3, 3, 40, 3)
			expect(ex == ex and ez == ez).toBe(true) -- not NaN
			expect(ex ~= 3 or ez ~= 3).toBe(true)
		end)

		it("eases from 0 to 1 smoothly and clamps outside", function()
			near(Cinematic.Ease(0), 0)
			near(Cinematic.Ease(0.5), 0.5)
			near(Cinematic.Ease(1), 1)
			near(Cinematic.Ease(-2), 0)
			near(Cinematic.Ease(3), 1)
			local last = 0
			for i = 1, 20 do
				local v = Cinematic.Ease(i / 20)
				expect(v >= last).toBe(true)
				last = v
			end
		end)
	end)

	describe("Cinematic hatch plans", function()
		it("wobbles about 1 s for Common up to 4 s for Mythic, harder the rarer", function()
			near(Cinematic.HatchPlan(HATCH, 1, 0).wobble, 1)
			near(Cinematic.HatchPlan(HATCH, 6, 0).wobble, 4)
			for r = 2, 6 do
				local a, b = Cinematic.HatchPlan(HATCH, r - 1, 0), Cinematic.HatchPlan(HATCH, r, 0)
				expect(b.wobble > a.wobble).toBe(true)
				expect(b.amplitude > a.amplitude).toBe(true)
				expect(b.burst > a.burst).toBe(true)
			end
		end)

		it("lands three cracks in order inside the wobble", function()
			for r = 1, 6 do
				local plan = Cinematic.HatchPlan(HATCH, r, 0)
				expect(#plan.cracks).toBe(3)
				expect(plan.cracks[1] > 0).toBe(true)
				expect(plan.cracks[1] < plan.cracks[2] and plan.cracks[2] < plan.cracks[3]).toBe(true)
				expect(plan.cracks[3] < plan.wobble).toBe(true)
			end
		end)

		it("gives only Mythic the light beams and the world tint, and Golden or Rainbow the shower", function()
			for r = 1, 5 do
				local plan = Cinematic.HatchPlan(HATCH, r, 0)
				expect(plan.beams).toBe(false)
				expect(plan.pulse).toBe(false)
				expect(plan.shiny).toBe(false)
			end
			local mythic = Cinematic.HatchPlan(HATCH, 6, 0)
			expect(mythic.beams).toBe(true)
			expect(mythic.pulse).toBe(true)
			expect(Cinematic.HatchPlan(HATCH, 1, 1).shiny).toBe(true)
			expect(Cinematic.HatchPlan(HATCH, 1, 2).shiny).toBe(true)
		end)

		it("keeps montage beats short and clamps odd rarities", function()
			for r = 1, 6 do
				local full, quick = Cinematic.HatchPlan(HATCH, r, 0), Cinematic.HatchPlan(HATCH, r, 0, true)
				expect(quick.wobble < full.wobble).toBe(true)
				expect(quick.wobble <= HATCH.montageMax).toBe(true)
				expect(quick.reveal <= full.reveal).toBe(true)
			end
			near(Cinematic.HatchPlan(HATCH, 99, 0).wobble, 4)
			near(Cinematic.HatchPlan(HATCH, nil, nil).wobble, 1)
		end)

		it("wobbles from a twitch up to the full amplitude", function()
			local plan = Cinematic.HatchPlan(HATCH, 4, 0)
			near(Cinematic.Wobble(plan, 0), 0)
			local early, late = 0, 0
			for i = 0, 200 do
				local tt = plan.wobble * i / 200
				local v = math.abs(Cinematic.Wobble(plan, tt))
				expect(v <= plan.amplitude + 1e-6).toBe(true)
				if tt < plan.wobble * 0.25 then
					early = math.max(early, v)
				elseif tt > plan.wobble * 0.75 then
					late = math.max(late, v)
				end
			end
			expect(late > early * 2).toBe(true)
		end)

		it("orders a montage rarest last, Rainbow over Golden over plain, else in hatch order", function()
			local list = {
				{ rarity = 3, variant = 0 },
				{ rarity = 1, variant = 0 },
				{ rarity = 3, variant = 2 },
				{ rarity = 6, variant = 0 },
				{ rarity = 3, variant = 1 },
				{ rarity = 1, variant = 0 },
			}
			expect(Cinematic.MontageOrder(list)).toEqual({ 2, 6, 1, 5, 3, 4 })
			expect(Cinematic.MontageOrder({})).toEqual({})
		end)
	end)

	describe("Cinematic evolution", function()
		it("glows, spins while the forms swap, flashes, lands, and ends on the new form", function()
			local total = Cinematic.EvolveLength(EVOLVE)
			local phases, swaps, last = {}, 0, nil
			local seen = {}
			for i = 0, 400 do
				local s = Cinematic.EvolveAt(EVOLVE, total * i / 400 - 1e-9)
				if not seen[s.phase] then
					seen[s.phase] = true
					table.insert(phases, s.phase)
				end
				if last ~= nil and s.new ~= last then
					swaps += 1
				end
				last = s.new
				expect(s.glow >= 0 and s.glow <= 1).toBe(true)
			end
			expect(phases).toEqual({ "glow", "spin", "flash", "land" })
			expect(swaps >= 6).toBe(true)
			expect(Cinematic.EvolveAt(EVOLVE, 0).new).toBe(false)
			local done = Cinematic.EvolveAt(EVOLVE, total + 0.01)
			expect(done.phase).toBe("done")
			expect(done.new).toBe(true)
			expect(Cinematic.EvolveAt(EVOLVE, EVOLVE.glow + EVOLVE.spin + 0.01).flash > 0.5).toBe(true)
		end)

		it("spins faster through the spin phase", function()
			local a = Cinematic.EvolveAt(EVOLVE, EVOLVE.glow + EVOLVE.spin * 0.2)
			local b = Cinematic.EvolveAt(EVOLVE, EVOLVE.glow + EVOLVE.spin * 0.9)
			expect(b.spin > a.spin).toBe(true)
		end)
	end)

	describe("Cinematic discovery", function()
		it("calls a form new until the codex has it", function()
			local codex = { cindlet = { forms = { cindlet = true }, variants = {}, count = 1 } }
			expect(Cinematic.IsNewForm(codex, "cindlet", "cindlet")).toBe(false)
			expect(Cinematic.IsNewForm(codex, "cindlet", "kindlefox")).toBe(true)
			expect(Cinematic.IsNewForm(codex, "bubblin", "bubblin")).toBe(true)
			expect(Cinematic.IsNewForm(nil, "bubblin", "bubblin")).toBe(true)
			expect(Cinematic.IsNewForm(codex, nil, "x")).toBe(false)
		end)
	end)
end
