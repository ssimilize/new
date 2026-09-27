--!strict
-- Monster Ranch Idle's camera language. Numbers transcribed from the game (read-only, the
-- r2-integration worktree), 2026-09-27:
--   rig    src/shared/Config/Cinematics.luau `Camera`, read by Logic/Cinematic.Frame (the
--          CameraDirector's shots): FOV 70, a subject fills 0.42 of the screen height, pitch 16,
--          7..28 studs, look point 0.45 of the height up, glide 0.7 in / 0.5 out (smootherstep).
--          Gameplay itself runs on Roblox's default follow camera (FOV 70); the Foundry does not
--          replace it. defaultHeight (a monster with no height) is the Foundry's choice.
--   focus  src/shared/Config/Photo.luau `Depth` as client PhotoMode applyDepth +
--          PhotoRig.FocusRadius apply it: no fade, no widening; low graphics turns it off.
--   photo  Config/Photo `Camera` (bounds) and `Filters` (grades, verbatim, same order); PhotoMode
--          keeps the player's field of view (70).
--   rails, moments   PROPOSED by the Foundry: event names from the Reactions catalogue; each needs
--          the payload to carry a world `position` (CameraDirector's glide stays the game's own).
-- tests/Profiles.spec.luau compares every number here with the game's files when they exist.

return {
	game = "monster-ranch",
	kind = "rig",
	rig = {
		fov = 70,
		pitch = 16,
		lookUp = 0.45,
		minDistance = 7,
		maxDistance = 28,
		bands = { 0.42 },
		defaultBand = 1,
		defaultHeight = 4,
		glideIn = 0.7,
		glideOut = 0.5,
		ease = "smoother",
		visibleRange = 110,
	},
	focus = {
		radiusRatio = 0.3,
		minRadius = 2,
		maxRadius = 30,
		maxFocus = 200,
		nearIntensity = 0.35,
		farIntensity = 0.45,
		widen = false,
		quality = { 0, 1, 1 },
	},
	rails = {
		-- a monster in the spotlight: a low arc round it, pushing in a little
		spotlight = {
			id = "spotlight",
			duration = 2.4,
			ease = "smoother",
			orbit = {
				{ yaw = 0, pitch = 16, distance = 14, lookUp = 2, fov = 70 },
				{ yaw = 35, pitch = 14, distance = 11, lookUp = 2, fov = 64 },
				{ yaw = 70, pitch = 12, distance = 9, lookUp = 2, fov = 60 },
			},
		},
		-- a hatch: rise from pad height to the usual framing
		hatch = {
			id = "hatch",
			duration = 3,
			ease = "sineInOut",
			orbit = {
				{ yaw = -20, pitch = 4, distance = 12, lookUp = 1.5, fov = 60 },
				{ yaw = 0, pitch = 10, distance = 13, lookUp = 1.8, fov = 66 },
				{ yaw = 20, pitch = 16, distance = 14, lookUp = 1.8, fov = 70 },
			},
		},
	},
	moments = {
		{ id = "hatch", on = "Eggs.Hatched", rail = "hatch", priority = 5, cooldown = 4, anchor = "position" },
		{ id = "evolve", on = "Monsters.Evolved", rail = "spotlight", priority = 6, cooldown = 6, anchor = "position" },
		{ id = "levelUp", on = "Monsters.LevelUp", rail = "spotlight", priority = 1, cooldown = 20, anchor = "position" },
	},
	photo = {
		fov = 70,
		bounds = {
			radius = 60,
			minHeight = -1.5,
			maxHeight = 24,
			minDistance = 4,
			maxDistance = 45,
			startDistance = 16,
			minPitch = -8,
			maxPitch = 80,
		},
		grades = {
			{ id = "natural", name = "Natural" },
			{ id = "warm", name = "Warm", brightness = 0.02, contrast = 0.08, saturation = 0.12, tint = "#FFE7C9" },
			{ id = "cool", name = "Cool", contrast = 0.06, saturation = 0.02, tint = "#D9E8FF" },
			{
				id = "dreamy",
				name = "Dreamy",
				brightness = 0.06,
				contrast = -0.08,
				saturation = 0.1,
				tint = "#FFE9F5",
				bloom = { intensity = 0.9, size = 40, threshold = 0.85 },
				heavy = true,
			},
			{ id = "vivid", name = "Vivid", contrast = 0.16, saturation = 0.45, bloom = { intensity = 0.3, size = 20, threshold = 1.3 } },
			{ id = "noir", name = "Noir", brightness = -0.02, contrast = 0.3, saturation = -1 },
			{ id = "vintage", name = "Vintage", brightness = 0.03, contrast = -0.06, saturation = -0.35, tint = "#F2DCB3" },
		},
	},
}
