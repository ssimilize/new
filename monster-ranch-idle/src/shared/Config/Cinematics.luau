--[[
	Cinematics (glow-up N): tuning for the camera director and the in-world hatch, evolution,
	star-up and level-up shots. Required directly (like Config/Vfx and Config/Photo), not listed in
	Config/init. The maths that reads it is Logic/Cinematic (unit-tested in Cinematic.spec).

	Camera: framing a subject `height` studs tall so it fills `fill` of the screen height, from
	`pitch` degrees above it, on the side the player's camera already looks from, `minDistance` ..
	`maxDistance` studs away. `glideIn` / `glideOut` seconds (reduced motion cuts instead).
	`visibleRange`: an incubator or pen monster further than this from the camera (or off screen)
	gets the 2D fallback instead of a shot.

	Hatch (index = rarity 1 Common .. 6 Mythic): `wobble` seconds of wobbling before the burst,
	`amplitude` degrees at the end of it, `frequency` wobbles per second, `burst` scale of the
	hatch burst. Three cracks land at `cracks` fractions of the wobble. `beamsFrom` rarity and up
	gets light beams; `pulseFrom` rarity and up tints the world for a moment (a ColorCorrection the
	shot owns, destroyed after). Montage beats (Hatch All) scale every time by `montageScale`,
	capped at `montageMax` seconds per egg.
]]

return {
	Camera = {
		fov = 70,
		fill = 0.42,
		pitch = 16,
		minDistance = 7,
		maxDistance = 28,
		lookUp = 0.45, -- the look point sits this fraction of the subject's height above its base
		glideIn = 0.7,
		glideOut = 0.5,
		visibleRange = 110,
	},

	Hatch = {
		wobble = { 1, 1.5, 2, 2.6, 3.2, 4 },
		amplitude = { 7, 9, 11, 14, 17, 22 },
		frequency = { 3, 3.4, 3.8, 4.2, 4.8, 5.4 },
		burst = { 1, 1.1, 1.25, 1.45, 1.7, 2 },
		cracks = { 0.35, 0.65, 0.9 },
		beamsFrom = 6,
		pulseFrom = 6,
		reveal = 1.6, -- seconds the monster hops out and cries before the summary card
		montageScale = 0.45,
		montageMax = 1.6,
		montageReveal = 0.8,
		pulse = { tint = "#FFD9F4", saturation = 0.25, brightness = 0.08, seconds = 1.4 }, -- mythic: the world blushes
	},

	Evolve = {
		glow = 0.7, -- turns white
		spin = 1.6, -- spins up inside the vortex while the two forms pulse through each other
		flash = 0.25,
		land = 1.2, -- the new form lands and cries
		vortexEvery = 0.3, -- seconds between vortex bursts (pooled Vfx.Bursts.evolveVortex)
		spinTurns = 4, -- turns per second at full speed
	},

	Spotlight = { -- star-up and level-up: a short look at the monster after the screen closes
		hold = 1.4,
	},
}
