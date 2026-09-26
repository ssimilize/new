--[[
	Cinematic (glow-up N): the pure maths of the camera director and the in-world hatch and
	evolution shots (plain numbers, no Roblox types). Used by Controllers/CameraDirector and
	Controllers/Cinematics, tuned by Config/Cinematics, unit-tested in Cinematic.spec.

	  Cinematic.Frame(cam, sx, sy, sz, height, fx, fy, fz) -> ex, ey, ez, lx, ly, lz
	      the eye and look point that frame a subject standing at (sx, sy, sz), `height` studs tall,
	      seen from the side the current camera (fx, fy, fz) is on. cam = Config.Cinematics.Camera.
	  Cinematic.Ease(a) -> number            smootherstep 0..1 (a glide)
	  Cinematic.HatchPlan(hatch, rarity, variant, montage) -> plan
	      { wobble, amplitude, frequency, cracks = { t1, t2, t3 }, burst, beams, pulse, shiny,
	        reveal }  (seconds from the start of the wobble; hatch = Config.Cinematics.Hatch)
	  Cinematic.Wobble(plan, t) -> degrees    the egg's tilt t seconds in (grows to amplitude)
	  Cinematic.MontageOrder(list) -> { index }   indices of { rarity, variant } entries, rarest
	      last (Rainbow above Golden above plain within a rarity), otherwise in hatch order
	  Cinematic.EvolveAt(evolve, t) -> state  { phase = "glow"|"spin"|"flash"|"land"|"done",
	      glow 0..1, spin (turns per second), new (true: the new form shows), flash 0..1 }
	  Cinematic.EvolveLength(evolve) -> seconds
	  Cinematic.IsNewForm(codex, line, form) -> boolean   not yet in profile.Monsters.codex
]]

local Cinematic = {}

local rad, tan, sqrt, clamp, max, min, sin, floor = math.rad, math.tan, math.sqrt, math.clamp, math.max, math.min, math.sin, math.floor

function Cinematic.Frame(cam, sx: number, sy: number, sz: number, height: number, fx: number, _fy: number, fz: number)
	local h = max(height, 0.5)
	local lx, ly, lz = sx, sy + h * cam.lookUp, sz
	-- Distance at which `h` fills `fill` of the vertical field of view.
	local distance = clamp(h / cam.fill / (2 * tan(rad(cam.fov) / 2)), cam.minDistance, cam.maxDistance)
	-- Keep the player's side: the flat direction from the subject to the camera.
	local dx, dz = fx - lx, fz - lz
	local flat = sqrt(dx * dx + dz * dz)
	if flat < 1e-3 then
		dx, dz, flat = 0, 1, 1
	end
	dx, dz = dx / flat, dz / flat
	local pitch = rad(cam.pitch)
	local across = distance * math.cos(pitch)
	local ex, ey, ez = lx + dx * across, ly + distance * sin(pitch), lz + dz * across
	return ex, ey, ez, lx, ly, lz
end

function Cinematic.Ease(a: number): number
	local x = clamp(a, 0, 1)
	return x * x * x * (x * (x * 6 - 15) + 10)
end

local function pick(list, rarity: number)
	return list[clamp(rarity, 1, #list)]
end

function Cinematic.HatchPlan(hatch, rarity: number?, variant: number?, montage: boolean?)
	local r = floor(tonumber(rarity) or 1)
	local v = tonumber(variant) or 0
	local scale = if montage then hatch.montageScale else 1
	local wobble = pick(hatch.wobble, r) * scale
	if montage then
		wobble = min(wobble, hatch.montageMax)
	end
	local cracks = {}
	for i, at in hatch.cracks do
		cracks[i] = wobble * at
	end
	return {
		wobble = wobble,
		amplitude = pick(hatch.amplitude, r),
		frequency = pick(hatch.frequency, r),
		cracks = cracks,
		burst = pick(hatch.burst, r),
		beams = r >= hatch.beamsFrom,
		pulse = r >= hatch.pulseFrom,
		shiny = v == 1 or v == 2,
		reveal = if montage then hatch.montageReveal else hatch.reveal,
	}
end

function Cinematic.Wobble(plan, t: number): number
	if t <= 0 or plan.wobble <= 0 then
		return 0
	end
	local a = min(t / plan.wobble, 1)
	-- Grows from a nervous twitch to the full rock; each crack is felt as a jolt in the growth.
	local strength = 0.15 + 0.85 * a * a
	return plan.amplitude * strength * sin(t * plan.frequency * math.pi * 2)
end

local function variantRank(variant: any): number
	local v = tonumber(variant) or 0
	return if v == 2 then 2 elseif v == 1 then 1 else 0
end

function Cinematic.MontageOrder(list: { { rarity: number?, variant: number? } }): { number }
	local order = {}
	for i in list do
		table.insert(order, i)
	end
	table.sort(order, function(a, b)
		local ra, rb = tonumber(list[a].rarity) or 1, tonumber(list[b].rarity) or 1
		if ra ~= rb then
			return ra < rb
		end
		local va, vb = variantRank(list[a].variant), variantRank(list[b].variant)
		if va ~= vb then
			return va < vb
		end
		return a < b
	end)
	return order
end

function Cinematic.EvolveAt(evolve, at: number)
	local t = max(at, 0)
	local glowEnd = evolve.glow
	local spinEnd = glowEnd + evolve.spin
	local flashEnd = spinEnd + evolve.flash
	local landEnd = flashEnd + evolve.land
	if t < glowEnd then
		return { phase = "glow", glow = t / glowEnd, spin = 0, new = false, flash = 0 }
	elseif t < spinEnd then
		local a = (t - glowEnd) / evolve.spin
		-- The forms swap faster and faster: 2 swaps a second rising to 12, the new one lingering more.
		local rate = 2 + 10 * a * a
		local phase = (t - glowEnd) * rate
		local showNew = (phase % 1) < 0.25 + 0.5 * a
		return { phase = "spin", glow = 1, spin = evolve.spinTurns * a, new = showNew, flash = 0 }
	elseif t < flashEnd then
		local a = (t - spinEnd) / evolve.flash
		return { phase = "flash", glow = 1, spin = evolve.spinTurns, new = true, flash = 1 - a * 0.3 }
	elseif t < landEnd then
		local a = (t - flashEnd) / evolve.land
		return { phase = "land", glow = max(0, 1 - a * 2), spin = 0, new = true, flash = max(0, 0.7 - a * 2) }
	end
	return { phase = "done", glow = 0, spin = 0, new = true, flash = 0 }
end

function Cinematic.EvolveLength(evolve): number
	return evolve.glow + evolve.spin + evolve.flash + evolve.land
end

function Cinematic.IsNewForm(codex: any, line: any, form: any): boolean
	if type(line) ~= "string" or type(form) ~= "string" then
		return false
	end
	local entry = type(codex) == "table" and codex[line]
	local forms = type(entry) == "table" and entry.forms
	return not (type(forms) == "table" and forms[form] == true)
end

return Cinematic
