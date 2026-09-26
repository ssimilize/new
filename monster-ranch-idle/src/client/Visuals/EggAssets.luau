--[[
	EggAssets: the published egg art (tools/blender/eggs.py). Written by that tool: re-running it
	keeps the ids and refreshes the ornament offsets; `python tools/blender/eggs.py ids ids.json`
	records new ids. An empty id means "not published yet": EggModel draws its placeholder egg
	(or leaves the ornament / crack / paint off) until it is set.

	meshes     shell = the smooth egg, gem = the Crystal Egg's faceted egg (1 x 1.3 x 1 studs)
	shapes     eggs drawn on a mesh other than the shell
	textures   one painted texture per Config.Eggs id
	ornaments  a small mesh for a few eggs; offset = its centre from the egg's centre, in egg
	           widths (Roblox axes, front -Z); every ornament shares the swatch texture
	cracks     the hatch crack overlays, stages 1-3 (transparent images on the egg's own mesh)
	painted    the Spring Bloom hunt's white paint over a tinted shell (transparent image)
]]

return {
	meshes = {
		shell = "",
		gem = "",
	},
	shapes = {
		crystal = "gem",
	},
	textures = {
		meadow = "",
		grove = "",
		crystal = "",
		royal = "",
		starlit = "",
		stampede = "",
		frostfall = "",
		pearl = "",
		lantern = "",
		celestial = "",
		bloom = "",
		sky = "",
		splash = "",
		raid = "",
		harvest = "",
		dunes = "",
		glacier = "",
		leviathan = "",
	},
	ornaments = {
		royal = { mesh = "", texture = "", offset = { 0.0225, 0.5944, -0.0393 } },
		harvest = { mesh = "", texture = "", offset = { 0.0506, 0.6901, -0.0224 } },
		bloom = { mesh = "", texture = "", offset = { 0, 0.6308, -0.1246 } },
		sky = { mesh = "", texture = "", offset = { 0, 0.1871, 0.0726 } },
		glacier = { mesh = "", texture = "", offset = { 0.0049, 0.7, 0.0005 } },
	},
	cracks = { "", "", "" },
	painted = "",
}
