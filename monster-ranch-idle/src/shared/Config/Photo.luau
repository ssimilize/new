--[[
	Photo: tuning and content for photo mode (client PhotoMode controller + PhotoMode screen).

	Required directly (require(Shared.Config.Photo)), like Config/Vfx: nothing on the server reads it.

	  Camera    free-camera limits around the spot the player entered photo mode from. Angles in
	            degrees, distances in studs, speeds per second (keys / sticks) or per pixel (drags).
	  Filters   { id, name, brightness?, contrast?, saturation?, tint?, bloom?, heavy? } shown as a
	            ColorCorrectionEffect (+ a BloomEffect when `bloom` is set). `heavy` presets are
	            skipped in low graphics, and low graphics never turns bloom on.
	  Frames    { id, name } drawn by the PhotoMode screen from the UI kit.
	  Stickers  particle sprite names (Config/VfxSprites); names not uploaded yet are left out.
	  Depth     DepthOfFieldEffect values; a tap focuses on what is under it.
	  PoseRadius  own pen monsters within this many studs of the camera's focus strike a pose.
]]

return {
	Camera = {
		radius = 60, -- how far the focus point may wander from where photo mode began
		minHeight = -1.5, -- focus height relative to that spot
		maxHeight = 24,
		minDistance = 4,
		maxDistance = 45,
		startDistance = 16,
		minPitch = -8,
		maxPitch = 80,
		orbitPerPixel = 0.3, -- degrees per pixel of drag
		orbitSpeed = 110, -- degrees per second at full stick / key
		panPerPixel = 0.0025, -- studs per pixel, times the camera distance
		panSpeed = 18,
		zoomSpeed = 1.8, -- distance doubles or halves in ~0.5 s at full trigger / key
		wheelStep = 0.12,
		collisionMargin = 0.6,
		smoothing = 14, -- 0 snaps (reduced motion always snaps)
		deadzone = 0.15,
	},

	Filters = {
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

	Frames = {
		{ id = "none", name = "No frame" },
		{ id = "polaroid", name = "Polaroid" },
		{ id = "vignette", name = "Vignette" },
		{ id = "badge", name = "Ranch badge" },
	},

	Stickers = { "heart", "star5", "star", "prism", "petal", "leaf", "snowflake", "bubble", "confetti", "flame" },
	MaxStickers = 24,

	Depth = {
		farIntensity = 0.45,
		nearIntensity = 0.35,
		focusDistance = 16, -- until the first tap
		minRadius = 2,
		maxRadius = 30,
		radiusShare = 0.3, -- in-focus radius as a share of the focus distance
		maxFocus = 200,
	},

	PoseRadius = 45,
}
