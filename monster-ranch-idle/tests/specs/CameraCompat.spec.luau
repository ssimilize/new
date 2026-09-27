--[[
	CameraCompat (Foundry wave 1g): CameraDirector frames its shots with the Foundry's Cinema
	package (Cinema.profile("monster-ranch").rig, Cinema.Language, Cinema.Ease) exactly as it did
	with Config.Cinematics.Camera and Logic/Cinematic. The old controller survives only here,
	verbatim, as tests/runtime/OldCameraDirector.luau.

	  - The profile's rig equals Config.Cinematics.Camera, number for number.
	  - Cinema.Language's rig frame equals Logic/Cinematic.Frame bit for bit over a grid of subject
	    positions, heights (below the 0.5 floor, both distance clamps), camera sides (including
	    straight above) and zoom bands; Cinema.Ease "smoother" equals Cinematic.Ease bit for bit.
	  - Frame by frame: one booted client runs the old controller (Substitute), one the new one on
	    the package, one the new one with the package removed (the fallback). A scripted run of
	    shots (glides, re-framing, Look, a hold, a stage cut, a skip, reduced motion, a non-finite
	    height) records the camera (CFrame, Focus, FieldOfView, CameraType) every frame at dt 1/30;
	    the three recordings are equal, string for string at 17 significant digits.
]]

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Tuning = t.Shared("Config.Cinematics")
	local Cinematic = t.Shared("Logic.Cinematic")
	local Cinema = t.Shared("Foundry.Cinema.Cinema")
	local Vector3 = t.Roblox.Vector3
	local CFrame = t.Roblox.CFrame

	local CAM = Tuning.Camera
	local DT = 1 / 30
	-- The infinite-height shot leaves the camera at NaN for a few frames (in every run, old and
	-- new alike); Lamplight's package path (wave 1b) refuses a non-finite camera position then.
	-- That is Lamplight's, not this controller's, so it is filtered here.
	local NAN_CAMERA = "Lamplighter.solve: camera.pos must be"

	local function problems(c, allow: { string }): { string }
		local out = {}
		for _, p in c:Problems(allow) do
			if not string.find(p, NAN_CAMERA, 1, true) then
				table.insert(out, p)
			end
		end
		return out
	end

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function fmt(v: number): string
		return string.format("%.17g", v)
	end

	describe("the package's Ranch camera", function()
		it("profile.rig equals Config.Cinematics.Camera", function()
			local rig = Cinema.profile("monster-ranch").rig
			expect(rig.fov).toBe(CAM.fov)
			expect(rig.bands).toEqual({ CAM.fill })
			expect(rig.defaultBand).toBe(1)
			for _, k in { "pitch", "minDistance", "maxDistance", "lookUp", "glideIn", "glideOut", "visibleRange" } do
				expect({ k, rig[k] }).toEqual({ k, CAM[k] })
			end
			expect(rig.ease).toBe("smoother")
			expect(#Cinema.Language.validate(Cinema.profile("monster-ranch"))).toBe(0)
		end)

		it("Language's rig frame equals Logic/Cinematic.Frame bit for bit", function()
			local lang = Cinema.Language.new(Cinema.profile("monster-ranch"))
			local xs = { -317.25, -75, -3.3, 0, 0.001, 12.5, 88.125, 404 }
			local ys = { -6, 0, 3.7, 41.2 }
			local heights = { 0, 0.1, 0.49, 0.5, 0.5000001, 1, 2.2, 4, 7.3, 12, 16.5, 20, 33, 50, 80, 200, 5000 }
			-- camera offsets from the subject (dx, y, dz): every side, near, far, straight above
			local froms = {
				{ 0, 50, 0 },
				{ 0.0004, 9, -0.0003 },
				{ 0, 10, 20 },
				{ 20, 10, 0 },
				{ -14, 3, 14 },
				{ -60, 40, -2 },
				{ 3.1, -8, -95 },
				{ 250, 60, 190 },
			}
			local zooms = { false, 1, { band = 1 }, 1.4 }
			local n = 0
			for _, sx in xs do
				for _, sy in ys do
					for zi, sz in xs do
						if zi % 2 == 1 then
							for _, height in heights do
								for _, off in froms do
									local fx, fy, fz = sx + off[1], sy + off[2], sz + off[3]
									local want = { Cinematic.Frame(CAM, sx, sy, sz, height, fx, fy, fz) }
									for _, zoom in zooms do
										local pose = lang.frame({
											position = { x = sx, y = sy, z = sz },
											height = height,
											from = { x = fx, y = fy, z = fz },
										}, if zoom == false then nil else zoom)
										local got = {
											pose.position.x,
											pose.position.y,
											pose.position.z,
											pose.lookAt.x,
											pose.lookAt.y,
											pose.lookAt.z,
										}
										for i = 1, 6 do
											if got[i] ~= want[i] then
												error(
													`frame differs at ({sx}, {sy}, {sz}) h {height} from ({fx}, {fy}, {fz}) [{i}]: {fmt(
														want[i]
													)} vs {fmt(got[i])}`
												)
											end
										end
										-- the CFrame the controller builds from them
										local a =
											CFrame.lookAt(Vector3.new(want[1], want[2], want[3]), Vector3.new(want[4], want[5], want[6]))
										local b = CFrame.lookAt(Vector3.new(got[1], got[2], got[3]), Vector3.new(got[4], got[5], got[6]))
										if a ~= b then
											error(`CFrame differs at ({sx}, {sy}, {sz}) h {height}`)
										end
										n += 1
									end
								end
							end
						end
					end
				end
			end
			expect(n).toBe(8 * 4 * 4 * 17 * 8 * 4)
			print(`CameraCompat: {n} framings bit-equal`)
		end)

		it("Cinema.Ease smoother equals Cinematic.Ease bit for bit", function()
			local n = 0
			for i = -500, 1500 do
				local a = i / 997
				expect({ a, Cinema.Ease.apply("smoother", a) }).toEqual({ a, Cinematic.Ease(a) })
				n += 1
			end
			expect(n).toBe(2001)
		end)
	end)

	-- ─── Frame by frame ──────────────────────────────────────────────────────────────────

	local function cf(v): string
		local out = { v:GetComponents() }
		for i, x in out do
			out[i] = fmt(x)
		end
		return table.concat(out, ",")
	end

	local function snapshot(camera, director): string
		return `{cf(camera.CFrame)} | {cf(camera.Focus)} | {fmt(camera.FieldOfView)} | {tostring(camera.CameraType)} | {director:IsBusy()}`
	end

	-- The scripted shots: where the camera starts, the shot, frames to run, and per-frame actions.
	local function shots(director, c)
		local V = Vector3.new
		return {
			{
				from = V(40, 25, 60),
				shot = {
					position = V(10, 2, -5),
					height = 3,
					run = function(h)
						h:Wait(1)
						h:Frame(V(-20, 0, 14), 0.3)
						h:Wait(0.9)
						h:Frame(V(5, 1, 5), 25, 0.35)
						h:Wait(0.6)
						h:Look(V(30, 12, 30), V(5, 2, 5), 0.4)
						h:Wait(0.5)
						h:Frame(V(-7.5, 0.5, 2), 1.7)
						h:Wait(0.8)
					end,
				},
				frames = 170,
			},
			{ from = V(0, 50, 0), shot = { position = V(0, 0, 0), hold = 1.2 }, frames = 80 }, -- straight above, default height 4
			{ from = V(-30, 5, -30), shot = { position = V(12, -3, 40), height = 0.2, hold = 0.8 }, frames = 70 },
			{ from = V(100, 80, -60), shot = { position = V(-44, 6, 9), height = 200, hold = 0.8 }, frames = 70 },
			{
				from = V(8, 14, 33),
				shot = {
					position = V(3, 0, 3),
					height = 5,
					stage = true,
					run = function(h)
						h:Wait(0.5)
						h:Frame(V(9, 0, -2), 6, 0)
						h:Wait(0.4)
						h:Look(V(0, 8, 20), V(3, 3, 3), 0)
						h:Wait(0.3)
					end,
				},
				frames = 60,
			},
			{
				from = V(-18, 9, 22),
				shot = { position = V(-2, 1, 6), height = 2.5, hold = 3 },
				frames = 70,
				at = {
					[25] = function()
						director:Skip()
					end,
				},
			},
			{
				from = V(26, 16, -40),
				shot = {
					position = V(14, 0, -11),
					height = 4.4,
					run = function(h)
						h:Wait(0.4)
						h:Frame(V(1, 0, 1), math.huge, 0.3)
						h:Wait(0.4)
						h:Frame(V(2, 0, 2), 3)
						h:Wait(0.5)
					end,
				},
				frames = 90,
			},
			{
				from = V(-50, 30, 5),
				before = function()
					expect(c:Request("Settings.Set", { key = "reducedMotion", value = true })).toBe(true)
				end,
				shot = {
					position = V(0, 2, -20),
					height = 6,
					run = function(h)
						h:Wait(0.4)
						h:Frame(V(10, 0, -25), 2)
						h:Wait(0.4)
					end,
				},
				frames = 60,
			},
		}
	end

	-- mode: "old" (the verbatim old controller), "new" (on the package), "fallback" (package removed)
	local function record(mode: string): ({ string }, { boolean }, any, number)
		math.randomseed(20260927)
		local h = TestKernel.new({ systems = allSystems() })
		local c = ClientHarness.new(h, h:Join(), { noBoot = true })
		local controllers = c.clientFolder.Controllers
		local foundry = c.world.game:GetService("ReplicatedStorage").Shared.Foundry
		if mode == "old" then
			c:Substitute(controllers.CameraDirector, "tests/runtime/OldCameraDirector.luau")
		elseif mode == "fallback" then
			foundry.Cinema:Destroy()
		end
		c:Boot()
		-- count the package's frames and eases, so the "new" run is proven to run on it
		local calls = 0
		if mode == "new" then
			local lib = c:require(foundry.Cinema.Cinema)
			local newLang = lib.Language.new
			lib.Language.new = function(profile)
				local lang = newLang(profile)
				local frame = lang.frame
				lang.frame = function(...)
					calls += 1
					return frame(...)
				end
				return lang
			end
			local apply = lib.Ease.apply
			lib.Ease.apply = function(...)
				calls += 1
				return apply(...)
			end
		end
		c:Advance(1)
		local director = c.kernel:GetController("CameraDirector")
		local camera = c.world.workspace.CurrentCamera
		local frames, ran = {}, {}
		for i, s in shots(director, c) do
			if s.before then
				s.before()
			end
			c:Advance(DT, DT)
			camera.CFrame = CFrame.lookAt(s.from, s.from + (s.from - s.shot.position))
			local shot = table.clone(s.shot)
			shot.onDone = function(didRun)
				ran[i] = didRun
			end
			director:Play(shot)
			for f = 1, s.frames do
				if s.at and s.at[f] then
					s.at[f]()
				end
				c:Advance(DT, DT)
				table.insert(frames, snapshot(camera, director))
			end
			expect({ mode, i, director:IsBusy() }).toEqual({ mode, i, false })
		end
		return frames, ran, c, calls
	end

	local function compare(a: { string }, b: { string }, what: string)
		expect(#b).toBe(#a)
		for i = 1, #a do
			if a[i] ~= b[i] then
				error(`{what}: frame {i} differs\n--- old\n{a[i]}\n--- new\n{b[i]}`, 2)
			end
		end
	end

	describe("frame by frame against the old controller", function()
		it("the package path and the fallback move the camera exactly as the old controller did", function()
			local old, oldRan = record("old")
			expect(oldRan).toEqual({ true, true, true, true, true, true, true, true })
			-- the run moved the camera: many distinct frames
			local distinct = {}
			local count = 0
			for _, s in old do
				if not distinct[s] then
					distinct[s] = true
					count += 1
				end
			end
			expect(count > 200).toBe(true)

			local new, newRan, c, calls = record("new")
			compare(old, new, "package path")
			expect(newRan).toEqual(oldRan)
			expect(calls > 300).toBe(true)
			local director = c:require(c.clientFolder.Controllers.CameraDirector)
			local reasons = 0
			for key, why in director.NotAdopted do
				expect({ key, #why >= 20 }).toEqual({ key, true })
				reasons += 1
			end
			expect(reasons >= 5).toBe(true)
			for _, w in c.world.warnings do
				expect(string.find(w, "not vendored", 1, true)).toBe(nil)
			end
			expect(#problems(c, {})).toBe(0)
			new, c = nil, nil

			local fb, fbRan, fc = record("fallback")
			compare(old, fb, "fallback")
			expect(fbRan).toEqual(oldRan)
			local warned = 0
			for _, w in fc.world.warnings do
				if string.find(w, "Cinema package is not vendored", 1, true) then
					warned += 1
				end
			end
			expect(warned).toBe(1)
			expect(#problems(fc, { "not vendored" })).toBe(0)
			print(`CameraCompat: {#old} frames x 3 runs equal ({count} distinct camera states), {calls} package calls`)
		end)
	end)
end
