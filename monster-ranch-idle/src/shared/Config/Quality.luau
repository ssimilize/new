--[[
	Config/Quality (glow-up P, "smooth on every phone"): the automatic quality levels, what each
	level costs, and how far other players' ranches stay detailed. Read by Logic/Quality and
	Logic/ParticleBudget (pure, unit-tested in Quality.spec), the client Quality module and
	controller, Visuals/Vfx (the particle budget), MonsterAnimator and World (distance LOD).

	Levels are ranked 1 = low, 2 = medium, 3 = high. The player's Graphics choice (Settings) is
	"auto" (the default: the Auto stepper below picks), "high" or "low" (pinned). The saved
	lowGraphics flag still means an explicit Low (and reduced motion); see Logic/Quality.Choice.
]]

local Quality = {}

Quality.Levels = {
	{ id = "low", name = "Low" },
	{ id = "medium", name = "Medium" },
	{ id = "high", name = "High" },
}
Quality.Rank = { low = 1, medium = 2, high = 3 }

-- The Settings choices, in the order the Settings button cycles them.
Quality.Choices = { "auto", "high", "low" }

--[[
	The Auto stepper. Frame times (ms) are kept for `window` seconds; once a second the median of
	that window is compared with the current level's thresholds. It steps down after `downAfter`
	bad evaluations in a row and up after `upAfter` good ones, never within `cooldown` seconds of
	the last step. Nothing is measured for `warmup` seconds after joining, for `hold` seconds after
	a screen opens or the character teleports, or on a single frame longer than `hitchMs`.
	Anti-flap: stepping down again within `relapse` seconds of stepping up doubles `upAfter` for
	that level (up to `upAfterMax`), so a phone that only just manages a level stops retrying it.
]]
Quality.Auto = {
	start = 3, -- the level a fresh session starts at
	warmup = 10,
	window = 4,
	minSamples = 20, -- fewer frames than this in the window = no verdict
	hitchMs = 250,
	hold = 2.5,
	teleportStuds = 60, -- a root part that jumps this far in one frame = a teleport
	down = { [3] = 24, [2] = 30 }, -- median ms above which the level steps down (≈ 42 / 33 fps)
	up = { [1] = 21, [2] = 18 }, -- median ms below which the level steps up (≈ 48 / 55 fps)
	downAfter = 3,
	upAfter = 20,
	upAfterMax = 240,
	relapse = 60,
	cooldown = 8,
}

--[[
	Particle budget (Visuals/Vfx): live particles = Σ Rate × mean Lifetime over every enabled
	emitter Vfx attached (monsters, eggs, landmarks). The local player's own monsters are never
	cut. Over budget, every other kind is first scaled down together to `minScale`, then whole
	kinds are switched off in `dropOrder` (first = cut first) until the rest fits; under budget
	again, they come back. Bursts (:Emit) share a per-second particle allowance.
]]
Quality.Particles = {
	budget = { [1] = 150, [2] = 320, [3] = 600 },
	burstsPerSecond = { [1] = 60, [2] = 140, [3] = 260 },
	minScale = 0.5,
	dropOrder = { "rarity", "variant", "egg", "mutation", "landmark", "aura", "mastery" },
	tick = 0.5, -- seconds between budget passes
}

--[[
	Distance LOD for other players' plots (World, MonsterAnimator, Vfx). Distances are studs from
	the camera to the plot's centre (World) or the monster (animator, effects). The local player's
	own plot always draws every monster (World's MAX_PER_PEN) at full animation rate.
	  penCap[level] = { near, mid, far }   monsters drawn per pen on another plot, by distance band
	  bands[level]  = { mid, far }         where the mid and far bands start
	  effectsDistance[level]               beyond this, another plot's monsters show no auras,
	                                       rarity glows or mastery effects
	  animInterval                         seconds between animation updates by band; offScreen
	                                       applies to models behind the camera (any plot)
]]
Quality.Lod = {
	-- Plots sit 240-290 studs from the plaza and 240+ from each other (Config.World.Plots): at High
	-- a neighbour is "mid", the far side of the map "far".
	penCap = { [1] = { 5, 3, 1 }, [2] = { 8, 5, 2 }, [3] = { 10, 8, 4 } },
	bands = { [1] = { 120, 260 }, [2] = { 150, 300 }, [3] = { 200, 360 } },
	effectsDistance = { [1] = 0, [2] = 200, [3] = 320 },
	animInterval = {
		near = { [1] = 1 / 15, [2] = 0, [3] = 0 },
		mid = { [1] = 1 / 12, [2] = 1 / 15, [3] = 1 / 20 },
		far = { [1] = 1 / 8, [2] = 1 / 10, [3] = 1 / 12 },
		offScreen = 0.2,
	},
	animMid = 90, -- studs: the animator's mid band (own and other plots alike)
	animFar = 160, -- studs: another plot's monster beyond this is "far"
	animPause = 250, -- studs: no updates at all beyond this
	behindMargin = 8, -- studs behind the camera plane that still count as on screen
}

-- The Studio-only perf overlay (frame time, level, live particles, animated models). Never
-- shown in a live server: it needs RunService:IsStudio(), then this flag or the Workspace
-- attribute PerfOverlay = true (set it in Studio's Properties while playing).
Quality.Overlay = { enabled = false, refresh = 0.5 }

return Quality
