--[[
	MotionMarkers (Foundry wave 1f): the Foundry Motion package's markers beside the monsters' bone
	clips (rules.Motion["monster-ranch"]: foot.l / foot.r on walk, hit on attack, as phases of the
	clip's length per Species archetype). Data only: nothing plays on a marker yet.

	  - A booted client wires them at Quality Init: MonsterAnimator.Markers gives exactly what
	    Motion.markers gives on the rules' phases scaled by the clip length, for every archetype.
	  - The read is a no-op: an animator walking, attacking, getting hurt and idling moves its model
	    bit-for-bit the same with the Motion package (and Markers read every frame) as without it.
	  - Without the Motion package it warns once and Markers is {}; NotAdopted gives its reasons.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Appearance = t.Shared("Logic.Appearance")
	local Vector3, CFrame = t.Roblox.Vector3, t.Roblox.CFrame

	local WARNING = "Foundry Motion package is not vendored"

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function boot(removePackage: boolean)
		local h = TestKernel.new({ systems = allSystems() })
		local c = ClientHarness.new(h, h:Join(9301, "Walker"), { noBoot = true })
		if removePackage then
			c.world.game:GetService("ReplicatedStorage").Shared.Foundry.Motion:Destroy()
		end
		c:Boot()
		c:Advance(1)
		return c, c:require(c.clientFolder.Visuals.MonsterAnimator)
	end

	local function warnings(c): number
		local n = 0
		for _, w in c.world.warnings do
			if string.find(w, WARNING, 1, true) then
				n += 1
			end
		end
		return n
	end

	local function bits(x: number): string
		return string.pack("<d", x)
	end

	local function vec(v): string
		return bits(v.X) .. bits(v.Y) .. bits(v.Z)
	end

	-- trace(c, Anim, readMarkers) -> one string per frame: state, the pivot's position and two
	-- transformed points (its rotation), and every part's size and position, all to the bit.
	local function trace(c, Anim, readMarkers: boolean): { string }
		local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
		local line = Config.Species.Lines[1]
		-- The animator rolls its walk phase and hue offset from math.random: the same seed both runs.
		math.randomseed(1901)
		local model = MonsterModel.Build(Appearance.Preview(line.id, 1))
		local camera = c.world.game:GetService("Workspace").CurrentCamera
		model.Parent = c.world.game:GetService("Workspace")
		local base = camera.CFrame * CFrame.new(0, 0, -12)
		local anim = Anim.new(model)
		anim:SetBase(base)
		local out = {}
		local clipT = 0
		local function frames(n: number)
			for _ = 1, n do
				c:Advance(1 / 30)
				if readMarkers then
					Anim.Markers(line.archetype, "walk", 0.8, clipT, clipT + 1 / 30, true)
					Anim.Markers(line.archetype, "attack", 0.8, clipT, clipT + 1 / 30, false)
				end
				clipT += 1 / 30
				local cf = model:GetPivot()
				local row = { anim:GetState(), vec(cf.Position), vec(cf * Vector3.new(0.3, 0.7, 1.1)), vec(cf * Vector3.new(1, 0, 0)) }
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						table.insert(row, d.Name .. vec(d.Size) .. vec(d.Position))
					end
				end
				table.insert(out, table.concat(row, "|"))
			end
		end
		frames(10)
		anim:MoveTo((base * CFrame.new(4, 0, -3)).Position)
		frames(45)
		anim:Play("attack")
		frames(25)
		anim:Play("hurt")
		frames(20)
		anim:Play("sit")
		frames(15)
		anim:Destroy()
		model:Destroy()
		return out
	end

	describe("Motion markers beside the bone clips", function()
		it("are wired at Init and equal Motion.markers on the rules' phases for every archetype", function()
			local c, Anim = boot(false)
			expect(warnings(c)).toBe(0)
			local foundry = c.kernel.Foundry
			local Motion = foundry.packages.Motion
			local ranch = foundry.rules.Motion["monster-ranch"]
			expect(ranch.phase).toBe(true)
			local archetypes = {}
			for _, line in Config.Species.Lines do
				archetypes[line.archetype] = true
			end
			local checked = 0
			for arch in archetypes do
				expect({ arch, ranch.archetypes[arch] ~= nil }).toEqual({ arch, true })
				for _, clip in { "walk", "attack" } do
					for _, length in { 20 / 30, 24 / 30, 1, 12 / 15 } do
						local markers = {}
						for _, p in ranch.archetypes[arch][clip] or {} do
							table.insert(markers, { t = p.t * length, name = p.name })
						end
						local doc = { length = length, loop = clip == "walk", markers = markers }
						for _, step in { { 0, length }, { 0.1, 0.5 }, { length * 0.9, length * 2.3 }, { 0.3, 0.3 } } do
							local want = Motion.markers(doc, step[1], step[2])
							local got = Anim.Markers(arch, clip, length, step[1], step[2])
							expect(got).toEqual(want)
							checked += 1
						end
					end
				end
			end
			expect(checked).toBe(8 * 2 * 4 * 4)
			local walk = Anim.Markers("fox", "walk", 0.8, 0, 0.8, true)
			expect(#walk).toBe(2)
			expect({ walk[1].name, walk[2].name }).toEqual({ "foot.l", "foot.r" })
			expect(#Anim.Markers("moth", "walk", 0.8, 0, 0.8, true)).toBe(0) -- floats: no feet
			expect(#Anim.Markers("fox", "idle", 2, 0, 2, true)).toBe(0)
			for key, why in Anim.NotAdopted do
				expect({ key, #why >= 20 }).toEqual({ key, true })
			end
			expect(#c:Problems()).toBe(0)
		end)

		it("change nothing: an animator moves bit-for-bit the same with and without the package", function()
			local cA, AnimA = boot(false)
			local with = trace(cA, AnimA, true)
			local cB, AnimB = boot(true)
			local without = trace(cB, AnimB, false)
			expect(#with).toBe(115)
			expect(#without).toBe(#with)
			local differ = 0
			for i, row in with do
				if row ~= without[i] then
					differ += 1
				end
			end
			expect(differ).toBe(0)
			local distinct, seen = 0, {}
			for _, row in with do
				if not seen[row] then
					seen[row] = true
					distinct += 1
				end
			end
			expect(distinct).toBeGreaterThan(100) -- it really moves: 108 distinct frames of 115
			expect(#cA:Problems()).toBe(0)
			expect(#cB:Problems({ WARNING })).toBe(0)
		end)

		it("without the Motion package warns once and gives no markers", function()
			local c, Anim = boot(true)
			expect(Anim.UseMotion(c.kernel.Foundry)).toBe(false)
			expect(#Anim.Markers("fox", "walk", 0.8, 0, 0.8, true)).toBe(0)
			expect(#Anim.Markers("golem", "attack", 0.8, 0, 0.8, false)).toBe(0)
			expect(warnings(c)).toBe(1)
			expect(#c:Problems({ WARNING })).toBe(0)
		end)
	end)
end
