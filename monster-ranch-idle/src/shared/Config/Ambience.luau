--[[
	Ambience: the sky, the dusk lights, scenery that moves and ambient life, as data. Read by the
	client controllers Sky, Lamplight, SceneryMotion and Critters (docs/ARCHITECTURE.md "Ambience
	layers"); the pure maths is Logic/Ambience. The particle looks of the scenery effects live
	in Config/Vfx (Vfx.Scenery), with the same spec keys and daylight rules as every other effect.

	Layers: every layer can be switched off here for a Studio A/B look, or live, without a restart,
	with a boolean attribute on Lighting named "Ambience_<layer>" (false = off, true = on, unset =
	this table): game.Lighting:SetAttribute("Ambience_clouds", false) from the client command bar.

	Counts are "max nearby, full graphics" / "max nearby, lowGraphics"; everything is picked round
	the camera, so a far corner of the map costs nothing.
]]

local Ambience = {}

Ambience.Layers = {
	sky = true, -- the Sky object (skybox ids below, sun, moon and stars)
	clouds = true, -- Terrain Clouds, cover and density per weather
	sunRays = true, -- SunRaysEffect by day
	depthOfField = true, -- faint haze on the far distance (never in lowGraphics)
	goldenHour = true, -- a warm tint through dusk and dawn
	weatherSprites = true, -- rain, snow, pollen and starfall use the Vfx sprites (Weather controller)
	lights = true, -- lamps on doors, window spill, campfires, crystals, fountain (Lamplight)
	campfires = true, -- flames, embers and smoke
	fountain = true, -- water jets, the falling curtain, ripples and mist
	windmills = true, -- leaves and dust blowing past the sails
	sway = true, -- the nearest trees and bushes sway in the wind
	butterflies = true,
	fireflies = true,
	birds = true,
	fish = true,
}

--[[
	Sky. Every skybox id "" keeps Roblox's own default sky (the one a fresh Sky object has). To use
	a softer cartoon sky, paste the six faces of a Creator Store skybox here (all six, or none).
]]
Ambience.Sky = {
	skyboxBk = "",
	skyboxDn = "",
	skyboxFt = "",
	skyboxLf = "",
	skyboxRt = "",
	skyboxUp = "",
	sunTexture = "", -- "" keeps the default sun
	moonTexture = "", -- "" keeps the default moon
	sunAngularSize = 16,
	moonAngularSize = 9,
	starCount = 2500,
}

-- Terrain Clouds per weather id (Config.Weather); a weather not listed uses `clear`. Cover and
-- density blend over a few seconds like the rest of the weather. At night the colour is darkened
-- by `nightShade` (the engine lights clouds by the sun, this only keeps them from glowing).
Ambience.Clouds = {
	blend = 3, -- seconds, exponential time constant
	nightShade = 0.55,
	byWeather = {
		clear = { cover = 0.5, density = 0.25, color = "#FFFFFF" },
		rain = { cover = 0.82, density = 0.62, color = "#C9D2DC" },
		thunderstorm = { cover = 0.9, density = 0.8, color = "#A3ABB8" },
		heatwave = { cover = 0.2, density = 0.12, color = "#FFF1DD" },
		snow = { cover = 0.78, density = 0.5, color = "#F1F6FF" },
		bloodmoon = { cover = 0.55, density = 0.35, color = "#FFB7AE" },
		starfall = { cover = 0.3, density = 0.15, color = "#F1E9FF" },
		lanternnight = { cover = 0.35, density = 0.2, color = "#FFD9C4" },
		pollenstorm = { cover = 0.55, density = 0.3, color = "#FFE9F2" },
		beachday = { cover = 0.4, density = 0.18, color = "#FFFFFF" },
		aurora = { cover = 0.25, density = 0.15, color = "#E6FFF6" },
	},
}

-- SunRaysEffect: intensity by weather (a weather not listed uses `default`); zero at night.
Ambience.SunRays = {
	default = 0.06,
	spread = 0.75,
	byWeather = { rain = 0, thunderstorm = 0, snow = 0.02, bloodmoon = 0.02, heatwave = 0.1, beachday = 0.09 },
}

-- DepthOfFieldEffect: only the far distance softens (the play camera sits ~40 studs from the
-- player); never in lowGraphics.
Ambience.DepthOfField = { farIntensity = 0.12, focusDistance = 150, inFocusRadius = 130, nearIntensity = 0 }

-- A warm ColorCorrection (its own effect, on top of the Weather controller's) that peaks at
-- `peak` and fades out towards `from` and `to` (Lighting.ClockTime hours).
Ambience.GoldenHour = {
	dusk = { from = 15.5, peak = 18, to = 20.5 },
	dawn = { from = 4, peak = 6.5, to = 9 },
	tint = "#FFCF9C",
	saturation = 0.08,
	brightness = 0.02,
}

--[[
	Lamplight: lights that come on through dusk (`on` hours, 0 -> 1) and go out through dawn
	(`off` hours, 1 -> 0). Only the `max` nearest within `radius` studs of the camera are enabled
	(`maxLow` with lowGraphics); none cast shadows. Campfire lights flicker.
]]
Ambience.Lights = {
	on = { 16.5, 18.5 },
	off = { 5.5, 7.5 },
	radius = 220,
	max = 12,
	maxLow = 5,
	update = 0.5, -- seconds between picks
	kinds = {
		door = { color = "#FFC27A", brightness = 1.4, range = 18 }, -- a porch lamp over each door
		window = { color = "#FFD59A", brightness = 0.8, range = 16, angle = 70 }, -- spill from the front
		campfire = { color = "#FF9A45", brightness = 2, range = 18, flicker = 0.25 },
		crystals = { color = "#B79BFF", brightness = 0.9, range = 10 },
		fountain = { color = "#9FDFFF", brightness = 1.1, range = 20 },
	},
}

--[[
	Scenery that moves. Effects (Config/Vfx.Scenery) sit on a small pool of emitter holders that
	move to the nearest items once a second, so there are never more than `max` of each.
	Windmills: the mesh is one piece (sails included), so the sails cannot turn; leaves and dust
	blow past them instead.
]]
Ambience.Scenery = {
	pick = 1, -- seconds between nearest-item picks
	campfire = { max = 4, maxLow = 2, radius = 150 },
	windmill = { max = 3, maxLow = 0, radius = 200, at = 0.72 }, -- at: height of the sails (x size)
	fountain = { radius = 240 },
	-- Sway: a slow rock about the base, only for the nearest few (trees, then bushes).
	sway = {
		max = 10,
		maxLow = 0,
		radius = 90,
		rate = 20, -- updates per second
		kinds = {
			oak = { angle = 0.9, speed = 0.55 },
			oakLight = { angle = 0.9, speed = 0.6 },
			pine = { angle = 0.6, speed = 0.5 },
			blossom = { angle = 1, speed = 0.6 },
			bush = { angle = 1.6, speed = 0.9 },
		},
	},
}

--[[
	Ambient life: small pooled parts near the camera. `max` / `maxLow` as above.
	Butterflies by day and fireflies at night gather at flowers, sunflowers and pen floors; birds
	perch on birdhouses and pen rails and scatter when the player runs within `scare` studs; fish
	circle in the fountain basin.
]]
Ambience.Critters = {
	pick = 1,
	rate = 30, -- movement updates per second
	butterflies = {
		max = 8,
		maxLow = 0,
		radius = 80,
		colors = { "#FFB547", "#FF8FC8", "#8FD3FF", "#FFF07A", "#C9A2FF" },
	},
	fireflies = { max = 16, maxLow = 5, radius = 70, color = "#E8FF7A" },
	birds = {
		max = 4,
		maxLow = 0,
		radius = 90,
		scare = 12,
		scareSpeed = 10, -- studs per second: walking past is fine, running scatters them
		colors = { "#6E8FD6", "#D96A4A", "#8A6A4E", "#F2D35B" },
	},
	fish = { max = 3, maxLow = 0, radius = 120, colors = { "#FF8A3D", "#FFFFFF", "#FFC23D" } },
}

return Ambience
