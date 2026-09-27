--[[
	AmbienceCompat (Foundry wave 1b): the Lamplight and Critters controllers on the Foundry's
	Lamplighter and Wildlife packages look exactly as they did. The old controllers survive only
	here, verbatim, as tests/runtime/OldLamplight.luau and OldCritters.luau.

	  - The packages' Ranch rules equal Config.Ambience (lights, critters, drift curves, scare).
	  - Equal-distance ties at the light cap: the package (squaredNearest) picks what
	    Logic.Nearest picks, on a grid built to tie.
	  - Frame by frame: one booted client runs the old controllers (Substitute), one the new ones
	    on the packages, one the new ones with the packages removed (the fallback). A scripted
	    run (two full days at dt 1/30: normal then low graphics, the camera near and far, the
	    player running through the perches) records every light (on, brightness, colour, range,
	    angle) and every shown critter part (CFrame, transparency, colour, size) per frame; the
	    three recordings are equal, string for string at 17 significant digits.
]]

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Ambience")
	local Contract = t.Shared("Foundry.Contract.Contract")
	local Lamplighter = t.Shared("Foundry.Lamplighter.Lamplighter")
	local LampRules = t.Shared("Foundry.Lamplighter.rules.monster-ranch")
	local Wildlife = t.Shared("Foundry.Wildlife.Wildlife")
	local WildTable = t.Shared("Foundry.Wildlife.tables.monster-ranch")
	local Vector3 = t.Roblox.Vector3
	local CFrame = t.Roblox.CFrame

	local A = Config.Ambience
	local DT = 1 / 30
	local DAY_FRAMES = 1440 -- 24 game hours over 48 s

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	describe("the packages' Ranch rules", function()
		it("Lamplighter rules equal Config.Ambience.Lights", function()
			local L = A.Lights
			expect(LampRules.lamps.on).toEqual(L.on)
			expect(LampRules.lamps.off).toEqual(L.off)
			expect(LampRules.lamps.mode).toBe("curve")
			expect(LampRules.radius).toBe(L.radius)
			expect(LampRules.lights).toEqual({ L.maxLow, L.max, L.max })
			expect(LampRules.shadows).toEqual({ 0, 0, 0 })
			expect(LampRules.decals).toEqual({ 0, 0, 0 })
			expect(LampRules.priority).toBe("nearest")
			expect(LampRules.flat).toBe(true)
			expect(LampRules.hysteresis).toBe(0)
			expect(LampRules.squaredNearest).toBe(true)
			local n = 0
			for kind, k in L.kinds do
				local r = LampRules.kinds[kind]
				expect({ kind, r.colour, r.brightness, r.range, r.angle }).toEqual({ kind, k.color, k.brightness, k.range, k.angle })
				expect({ kind, r.flicker ~= "steady" }).toEqual({ kind, k.flicker ~= nil })
				n += 1
			end
			for _ in LampRules.kinds do
				n -= 1
			end
			expect(n).toBe(0)
			-- the one flicker profile is the old campfire sum, amount = Lights.kinds.campfire.flicker
			local f = Lamplighter.Kinds.FLICKERS.ranch
			expect(f.amount).toBe(L.kinds.campfire.flicker)
			expect({ f.rate, f.mode }).toEqual({ 1, "centered" })
			expect(f.terms).toEqual({ { 11, 0.5, 1 }, { 23.7, 0.3, 3 }, { 5.3, 0.2, 0 } })
		end)

		it("the Wildlife table equals Config.Ambience.Critters and the old controller's constants", function()
			local C = A.Critters
			local K = WildTable.kinds
			for ranch, kind in { butterflies = "butterfly", fireflies = "firefly", birds = "bird", fish = "fish" } do
				local e = C[ranch]
				expect({ ranch, K[kind].max }).toEqual({ ranch, { Logic.Cap(e, true), Logic.Cap(e, false), Logic.Cap(e, false) } })
				expect({ ranch, K[kind].radius }).toEqual({ ranch, e.radius })
				expect({ ranch, K[kind].colors }).toEqual({ ranch, e.colors or { e.color } })
			end
			expect(WildTable.dayNight).toEqual({ mode = "curve", on = A.Lights.on, off = A.Lights.off })
			expect({ K.bird.scare, K.bird.scareSpeed }).toEqual({ C.birds.scare, C.birds.scareSpeed })
			-- the literals of the old Critters controller (tests/runtime/OldCritters.luau)
			expect({ K.bird.fleeDistance, K.bird.returnAfter }).toEqual({ 25, { 6, 12 } })
			expect({ K.fish.edge, K.fish.depth }).toEqual({ 1.5, 0.05 })
			local bd, fd = K.butterfly.drift, K.firefly.drift
			expect({ bd.amp, bd.height, bd.bob, bd.freq, bd.phase }).toEqual({ 2.5, 1.2, 0.6, { 0.9, 1.7, 0.7 }, { 1, 1, 1.3 } })
			expect({ fd.amp, fd.height, fd.bob, fd.freq, fd.phase }).toEqual({ 3, 1.6, 1.1, { 0.31, 0.53, 0.27 }, { 1, 2, 1.7 } })
		end)

		it("Wildlife.night and Wildlife.scared equal Logic.Night and Logic.Scared bit for bit", function()
			local n = 0
			for i = 0, 24 * 400 do
				local c = i / 400
				expect(Wildlife.night(c, WildTable.dayNight.on, WildTable.dayNight.off)).toBe(Logic.Night(c, A.Lights.on, A.Lights.off))
				expect(Lamplighter.night(c, LampRules.lamps.on, LampRules.lamps.off)).toBe(Logic.Night(c, A.Lights.on, A.Lights.off))
				n += 1
			end
			for _, speed in { 0, 9.99, 10, 10.01, 30 } do
				for x = -15, 15, 0.25 do
					for z = -15, 15, 1.5 do
						local want = Logic.Scared({ X = 1.5, Z = -2 }, { X = x, Z = z }, speed, A.Critters.birds)
						expect(Wildlife.scared(1.5, -2, x, z, speed, WildTable.kinds.bird)).toBe(want)
						n += 1
					end
				end
			end
			expect(n).toBe(9601 + 5 * 121 * 21)
		end)

		it("equal-distance ties at the light cap pick what Logic.Nearest picks", function()
			-- every grid point holds three sources, so rings of exact ties straddle both caps
			local kinds = { "door", "window", "campfire", "crystals", "fountain" }
			local points, fixtures = {}, {}
			for i = 1, 75 do
				local g = (i - 1) // 3
				local x, z = (g % 5) * 5, (g // 5) * 5
				table.insert(points, { X = x, Z = z })
				table.insert(
					fixtures,
					{ id = string.format("s%05d", i), kind = kinds[(i - 1) % 5 + 1], pos = { x = x, y = 2, z = z }, seed = (i - 1) * 1.7 }
				)
			end
			local adapter = Contract.mock({ t0 = 0, quality = 3 })
			local lamps = Lamplighter.new(adapter, fixtures, {
				hour = function()
					return 23
				end,
			}, LampRules)
			local cases, ties = 0, 0
			for cx = -5, 25, 1.25 do
				for cz = -5, 25, 1.25 do
					for _, q in { 1, 2, 3 } do
						adapter.setQuality(q)
						local want = Logic.Nearest(points, cx, cz, A.Lights.radius, Logic.Cap(A.Lights, q == 1))
						local got = {}
						for i, e in lamps:solve(0, { pos = { x = cx, y = 40, z = cz } }).lights do
							got[i] = tonumber(string.sub(e.id, 2))
						end
						expect(got).toEqual(want)
						-- a tie at the cap: the last pick and the first left out are equally far
						local cap = #want
						local all = Logic.Nearest(points, cx, cz, A.Lights.radius, 1000)
						if all[cap + 1] then
							local a, b = points[all[cap]], points[all[cap + 1]]
							if (a.X - cx) ^ 2 + (a.Z - cz) ^ 2 == (b.X - cx) ^ 2 + (b.Z - cz) ^ 2 then
								ties += 1
							end
						end
						cases += 1
					end
				end
			end
			expect(cases).toBe(25 * 25 * 3)
			expect(ties > 100).toBe(true)
		end)
	end)

	-- ─── Frame by frame ──────────────────────────────────────────────────────────────

	local function fmt(v: number): string
		return string.format("%.17g", v)
	end

	local function colour(c): string
		return fmt(c.R) .. "," .. fmt(c.G) .. "," .. fmt(c.B)
	end

	local function snapshot(c, stats): string
		local ws = c.world.workspace
		local out = { fmt(c.world.game:GetService("Lighting").ClockTime) }
		local lights = ws:FindFirstChild("AmbienceLights")
		local on = 0
		if lights then
			for _, part in lights:GetChildren() do
				local l = part:GetChildren()[1]
				if l.Enabled then
					on += 1
				end
				local angle = if l:IsA("SurfaceLight") then fmt(l.Angle) else "-"
				table.insert(
					out,
					`L {part.Name} {l.Enabled} {fmt(l.Brightness)} {fmt(l.Range)} {angle} {colour(l.Color)} {fmt(part.Position.X)},{fmt(
						part.Position.Z
					)}`
				)
			end
		end
		local critters = ws:FindFirstChild("AmbienceCritters")
		local parts = 0
		if critters then
			for _, part in critters:GetChildren() do
				local cf = { part.CFrame:GetComponents() }
				for i, v in cf do
					cf[i] = fmt(v)
				end
				table.insert(out, `C {table.concat(cf, ",")} {fmt(part.Transparency)} {colour(part.Color)} {fmt(part.Size.X)}`)
				parts += 1
			end
		end
		stats.lit = math.max(stats.lit, on)
		stats.litFrames += if on > 0 then 1 else 0
		stats.critterFrames += if parts > 0 then 1 else 0
		stats.minParts = math.min(stats.minParts, parts)
		stats.maxParts = math.max(stats.maxParts, parts)
		return table.concat(out, "\n")
	end

	local function plant(c)
		local folder = c.Instance.new("Folder")
		folder.Name = "Scenery"
		local i = 0
		for _, row in { { "campfire", 6 }, { "flowers", 18 }, { "sunflowers", 6 }, { "birdhouse", 5 }, { "crystals", 3 } } do
			for _ = 1, row[2] do
				i += 1
				local part = c.Instance.new("Part")
				part.Name = row[1]
				part.Anchored = true
				part.Size = Vector3.new(4, 8, 4)
				part.CFrame = CFrame.new((i % 7) * 6 - 18, 4, 30 + math.floor(i / 7) * 6 - 12)
				part.Parent = folder
			end
		end
		folder.Parent = c.world.workspace:FindFirstChild("World")
	end

	-- mode: "old" (verbatim old controllers), "new" (on the packages), "fallback" (packages removed)
	local function record(mode: string): ({ string }, any, any)
		math.randomseed(20260927)
		local h = TestKernel.new({ systems = allSystems() })
		local c = ClientHarness.new(h, h:Join(), { noBoot = true })
		local controllers = c.clientFolder.Controllers
		if mode == "old" then
			c:Substitute(controllers.Lamplight, "tests/runtime/OldLamplight.luau")
			c:Substitute(controllers.Critters, "tests/runtime/OldCritters.luau")
		elseif mode == "fallback" then
			local foundry = c.world.game:GetService("ReplicatedStorage").Shared.Foundry
			foundry.Lamplighter:Destroy()
			foundry.Wildlife:Destroy()
		end
		c:Boot()
		c:Advance(1)
		plant(c)
		local lighting = c.world.game:GetService("Lighting")
		local camera = c.world.workspace.CurrentCamera
		local root = c.localPlayer.Character:FindFirstChild("HumanoidRootPart")
		local frames = {}
		local stats = { lit = 0, litFrames = 0, critterFrames = 0, minParts = math.huge, maxParts = 0 }
		for pass = 1, 2 do
			if pass == 2 then
				expect(c:Request("Settings.Set", { key = "lowGraphics", value = true })).toBe(true)
			end
			for f = 0, DAY_FRAMES - 1 do
				lighting.ClockTime = 24 * f / DAY_FRAMES
				-- far away for two game hours at dusk and two at noon
				local far = (f >= 1080 and f < 1200) or (f >= 660 and f < 720)
				camera.CFrame = if far then CFrame.new(2000, 20, 2030) else CFrame.new(0, 20, 30)
				-- the player runs back and forth through the perches by day (40 studs/s), else stands
				local x = if f >= 480 and f < 1000 then ((f % 60) / 60 * 2 - 1) * 40 else 60
				root.CFrame = CFrame.new(if (f // 60) % 2 == 0 then x else -x, 3, 30)
				c:Advance(DT, DT)
				table.insert(frames, snapshot(c, stats))
			end
		end
		return frames, stats, c
	end

	local function compare(a: { string }, b: { string }, what: string)
		expect(#b).toBe(#a)
		for i = 1, #a do
			if a[i] ~= b[i] then
				error(`{what}: frame {i} differs\n--- old\n{string.sub(a[i], 1, 1500)}\n--- new\n{string.sub(b[i], 1, 1500)}`, 2)
			end
		end
	end

	describe("frame by frame against the old controllers", function()
		it("the package path and the fallback draw exactly what the old controllers drew", function()
			local old, oldStats = record("old")
			-- the run covers lit nights, capped lights, critters by day and night, and birds leaving
			expect(oldStats.lit > 0 and oldStats.lit <= A.Lights.max).toBe(true)
			expect(oldStats.litFrames > 200).toBe(true)
			expect(oldStats.critterFrames > 1000).toBe(true)
			expect(oldStats.maxParts > oldStats.minParts).toBe(true)

			local new, newStats, c = record("new")
			compare(old, new, "package path")
			expect(newStats).toEqual(oldStats)
			local Lamplight = c:require(c.clientFolder.Controllers.Lamplight)
			local Critters = c:require(c.clientFolder.Controllers.Critters)
			for _, ctl in { Lamplight, Critters } do
				for key, why in ctl.NotAdopted do
					expect({ ctl.Name, key, #why >= 20 }).toEqual({ ctl.Name, key, true })
				end
			end
			expect(#c:Problems()).toBe(0)
			new, c = nil, nil

			local fb, fbStats, fc = record("fallback")
			compare(old, fb, "fallback")
			expect(fbStats).toEqual(oldStats)
			local warned = {}
			for _, w in fc.world.warnings do
				if string.find(w, "not vendored", 1, true) then
					table.insert(warned, w)
				end
			end
			expect(#warned).toBe(2)
			expect(#fc:Problems({ "not vendored" })).toBe(0)
			print(
				`AmbienceCompat: {#old} frames x 3 runs equal; most lights on {oldStats.lit}, lit frames {oldStats.litFrames}, critter frames {oldStats.critterFrames}, critter parts {oldStats.minParts}..{oldStats.maxParts}`
			)
		end)
	end)
end
