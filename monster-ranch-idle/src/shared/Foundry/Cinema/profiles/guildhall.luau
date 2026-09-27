--!strict
-- Guildhall Idle's camera language. Numbers transcribed from the game (read-only), 2026-09-27:
--   god    src/systems/GodCamera/Config.luau (+ data/world.json "camera", which lays pitchDeg,
--          fovDeg, bands and snapSeconds over it): pitch 52, FOV 20, bands 110/200/320 x
--          0.85..1.15, 4 snaps of 90 degrees offset 45, 0.35 s cubicInOut.
--   focus  src/systems/DayNight/Config.luau `dof` (geometry) + data/lighting.json keyframes[1].dof
--          (intensities, since K1) read by DayNight Logic.dofFor (the tilt-shift): look quality
--          low drops dof, medium scales x0.8, high x1 -> Contract levels { 0, 0.8, 1 }.
--   rails, moments, photo   PROPOSED by the Foundry (Guildhall has no rails or photo mode yet);
--          moment events come from the Reactions catalogue, and each needs the payload to carry a
--          world `position` (the director drops a moment whose payload has none).
-- tests/Profiles.spec.luau compares every number here with the game's files when they exist.

return {
	game = "guildhall",
	kind = "god",
	god = {
		pitch = 52,
		fov = 20,
		bands = { 110, 200, 320 },
		defaultBand = 2,
		fineMin = 0.85,
		fineMax = 1.15,
		yawSnaps = 4,
		yawOffset = 45,
		snapSeconds = 0.35,
		snapEase = "cubicInOut",
	},
	focus = {
		fadeFrom = 232,
		offAt = 262,
		radiusRatio = 0.035,
		minRadius = 4,
		maxRadius = 50,
		maxFocus = 200,
		nearIntensity = 0.75,
		farIntensity = 1,
		widen = true,
		quality = { 0, 0.8, 1 },
	},
	rails = {
		-- a finished building: from the default view, a quarter turn and a push into the near band
		reveal = {
			id = "reveal",
			duration = 3.2,
			ease = "sineInOut",
			fov = 20,
			orbit = {
				{ yaw = 45, pitch = 52, distance = 200 },
				{ yaw = 75, pitch = 47, distance = 140 },
				{ yaw = 105, pitch = 42, distance = 100 },
			},
		},
		-- a rank up: a slow half orbit high over the town, ending back on the default view
		flyover = {
			id = "flyover",
			duration = 6,
			ease = "sineInOut",
			fov = 20,
			orbit = {
				{ yaw = -135, pitch = 58, distance = 300 },
				{ yaw = -45, pitch = 55, distance = 280 },
				{ yaw = 45, pitch = 52, distance = 200 },
			},
		},
	},
	moments = {
		{ id = "building", on = "Construction.Finished", rail = "reveal", priority = 2, cooldown = 20, anchor = "position" },
		{ id = "star", on = "Stars.Landed", rail = "reveal", priority = 3, cooldown = 30, anchor = "position" },
		{ id = "rank", on = "GuildRank.Up", rail = "flyover", priority = 5, cooldown = 60, anchor = "position" },
	},
	photo = {
		fov = 20,
		bounds = {
			radius = 120,
			minHeight = 0,
			maxHeight = 40,
			minDistance = 93.5,
			maxDistance = 368,
			startDistance = 200,
			minPitch = 20,
			maxPitch = 80,
		},
		grades = {
			{ id = "natural", name = "Natural" },
		},
	},
}
