-- Photo mode's pure camera maths (Logic/PhotoRig) and the Config/Photo content it runs on.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local PhotoRig = t.Shared("Logic.PhotoRig")
	local Photo = t.Shared("Config.Photo")
	local VfxSprites = t.Shared("Config.VfxSprites")
	local CAM = Photo.Camera

	local function near(a: number, b: number, eps: number?)
		if math.abs(a - b) > (eps or 1e-6) then
			error(string.format("expected %s to be close to %s", tostring(a), tostring(b)), 2)
		end
	end

	describe("PhotoRig", function()
		it("orbits with a clamped pitch and a wrapped yaw", function()
			local rig = PhotoRig.new(CAM, 170, 10, 12)
			PhotoRig.Orbit(rig, CAM, 30, 500)
			near(rig.yaw, -160)
			expect(rig.pitch).toBe(CAM.maxPitch)
			PhotoRig.Orbit(rig, CAM, 0, -1000)
			expect(rig.pitch).toBe(CAM.minPitch)
		end)

		it("zooms within its distance limits and ignores bad factors", function()
			local rig = PhotoRig.new(CAM, 0, 20, 10)
			PhotoRig.Zoom(rig, CAM, 0.5)
			near(rig.distance, 5)
			PhotoRig.Zoom(rig, CAM, 0.01)
			expect(rig.distance).toBe(CAM.minDistance)
			PhotoRig.Zoom(rig, CAM, 1000)
			expect(rig.distance).toBe(CAM.maxDistance)
			PhotoRig.Zoom(rig, CAM, 0 / 0)
			PhotoRig.Zoom(rig, CAM, -2)
			expect(rig.distance).toBe(CAM.maxDistance)
		end)

		it("pans relative to the view and never leaves its radius or height band", function()
			local rig = PhotoRig.new(CAM, 0, 20, 10)
			PhotoRig.Pan(rig, CAM, 2, 0, 3) -- yaw 0 looks along -Z: right is +X
			near(rig.x, 2)
			near(rig.z, -3)
			rig.x, rig.z = 0, 0
			rig.yaw = 90 -- the eye on +X looking along -X: forward is -X, right is -Z
			PhotoRig.Pan(rig, CAM, 1, 0, 4)
			near(rig.x, -4)
			near(rig.z, -1)
			PhotoRig.Pan(rig, CAM, 0, 1000, 1000)
			near(math.sqrt(rig.x * rig.x + rig.z * rig.z), CAM.radius, 1e-4)
			expect(rig.y).toBe(CAM.maxHeight)
			PhotoRig.Pan(rig, CAM, 0, -1000, 0)
			expect(rig.y).toBe(CAM.minHeight)
		end)

		it("places the eye from yaw, pitch and distance, and back again", function()
			local rig = PhotoRig.new(CAM, 0, 0, 10)
			local x, y, z = PhotoRig.Eye(rig)
			near(x, 0)
			near(y, 0)
			near(z, 10)
			local back = PhotoRig.FromOffset(CAM, 6, 8, -6)
			local ex, ey, ez = PhotoRig.Eye(back)
			near(ex, 6, 1e-4)
			near(ey, 8, 1e-4)
			near(ez, -6, 1e-4)
			local fallback = PhotoRig.FromOffset(CAM, 0, 0, 0)
			expect(fallback.distance).toBe(CAM.startDistance)
		end)

		it("cycles with wrap-around and skips what is not allowed", function()
			expect(PhotoRig.Cycle(4, 4, 1)).toBe(1)
			expect(PhotoRig.Cycle(4, 1, -1)).toBe(4)
			expect(PhotoRig.Cycle(4, 1, 1, function(i)
				return i ~= 2
			end)).toBe(3)
			expect(PhotoRig.Cycle(4, 2, 1, function()
				return false
			end)).toBe(2)
			expect(PhotoRig.Cycle(0, 3, 1)).toBe(3)
		end)

		it("tells taps from drags, rescales sticks and sizes the focus band", function()
			expect(PhotoRig.IsTap(4, 0.1)).toBe(true)
			expect(PhotoRig.IsTap(40, 0.1)).toBe(false)
			expect(PhotoRig.IsTap(2, 2)).toBe(false)
			expect(PhotoRig.Deadzone(0.1, 0.15)).toBe(0)
			near(PhotoRig.Deadzone(1, 0.15), 1)
			near(PhotoRig.Deadzone(-0.575, 0.15), -0.5)
			expect(PhotoRig.FocusRadius(Photo.Depth, 1)).toBe(Photo.Depth.minRadius)
			expect(PhotoRig.FocusRadius(Photo.Depth, 1000)).toBe(Photo.Depth.maxRadius)
			near(PhotoRig.FocusRadius(Photo.Depth, 20), 20 * Photo.Depth.radiusShare)
		end)
	end)

	describe("Config.Photo", function()
		it("has unique filters and frames with names, and heavy filters are the bloom ones", function()
			local seen = {}
			for _, list in { Photo.Filters, Photo.Frames } do
				for _, def in list do
					expect(seen[def.id]).toBe(nil)
					seen[def.id] = true
					expect(type(def.name) == "string" and #def.name > 0).toBe(true)
				end
			end
			expect(#Photo.Filters >= 7).toBe(true)
			expect(Photo.Filters[1].heavy).toBe(nil) -- the first filter must always be allowed
			for _, def in Photo.Filters do
				if def.heavy then
					expect(def.bloom ~= nil).toBe(true)
				end
				if def.tint then
					expect(string.match(def.tint, "^#%x%x%x%x%x%x$") ~= nil).toBe(true)
				end
			end
		end)

		it("offers stickers that are uploaded sprites", function()
			local uploaded = 0
			for _, name in Photo.Stickers do
				if VfxSprites[name] then
					uploaded += 1
				end
			end
			expect(uploaded >= 5).toBe(true)
			expect(VfxSprites.heart ~= nil).toBe(true)
		end)
	end)
end
