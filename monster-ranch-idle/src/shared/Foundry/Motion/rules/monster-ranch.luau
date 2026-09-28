--!strict
-- Monster Ranch: markers beside the monsters' bone clips. The clips themselves stay the Blender
-- generator's output (tools/blender/rig_<rig>.py, MeshMonsterClips/<form>); Motion never rewrites
-- them. A form's clip lengths differ by form, so a marker's `t` here is a PHASE (0 <= t < 1, a
-- fraction of the clip's length): the game scales it by the clip's length ((frames - 1) / fps,
-- which is the generator's n / fps, so a phase is the generator's own f / n).
--
-- The game reads it as ctx.Foundry.rules.Motion["monster-ranch"] (the package's `rules` folder;
-- `tables/<game>` is the `motion table` ClipDoc list and is not used by the Ranch).
--
-- Keyed by Config/Species `archetype`; fox is rigged by rig_quadruped.py. Where each phase comes
-- from (the generator functions on Ranch main f1dab15):
--   walk (loop), foot.l / foot.r: the moment a foot plants.
--     fox     trot, diagonal pairs: lift = max(0, -cos(ph + p)) returns to 0 at ph + p = 3pi/2;
--             thigh.L + upperarm.R (p = pi) plant at 0.25, thigh.R + upperarm.L (p = 0) at 0.75
--     blob    waddle: step = max(0, sin(ph + p)) returns to 0 at ph + p = pi; foot.L (p = 0) plants
--             at 0.5, foot.R (p = pi) at 0 (= 1, the lap wrap)
--     bunny   one hop per loop, both feet land together at t = 0.8 (air = pulse(t, 0.2, 0.8))
--     golem   legs +-22 * sin(ph); lowest bob (both feet down) at 0.25 and 0.75; leg.L forward
--             (-22 deg) at 0.25, leg.R forward at 0.75
--     bug     tripods +-28 * sin(ph); the tripod with leg L.1 finishes its forward swing at 0.25,
--             the one with R.1 at 0.75
--     moth, sprite (float) and slug (no legs) have no footfalls.
--   attack (once), hit: the peak of the generator's `hit` ramp, ramp(t, a, b) reaching 1 at b:
--     fox, blob, bunny 0.48; bug, golem, slug 0.5; moth, sprite 0.52.
--
-- Data only: nothing in the Ranch plays a sound or effect on these yet (MonsterAnimator.Markers
-- is a read with no caller). Names are from Markers.NAMES.

local function feet(l: number, r: number): { any }
	return { { t = l, name = "foot.l" }, { t = r, name = "foot.r" } }
end

local function hit(t: number): { any }
	return { { t = t, name = "hit" } }
end

return {
	phase = true, -- every t below is a fraction of the clip's length
	archetypes = {
		fox = { walk = feet(0.25, 0.75), attack = hit(0.48) },
		blob = { walk = feet(0.5, 0), attack = hit(0.48) },
		bunny = { walk = feet(0.8, 0.8), attack = hit(0.48) },
		golem = { walk = feet(0.25, 0.75), attack = hit(0.5) },
		bug = { walk = feet(0.25, 0.75), attack = hit(0.5) },
		slug = { attack = hit(0.5) },
		moth = { attack = hit(0.52) },
		sprite = { attack = hit(0.52) },
	},
}
