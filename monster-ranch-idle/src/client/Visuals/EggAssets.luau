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
		shell = "rbxassetid://118160674470912",
		gem = "rbxassetid://76088076217589",
	},
	shapes = {
		crystal = "gem",
	},
	textures = {
		meadow = "rbxassetid://73760712441384",
		grove = "rbxassetid://109024707888677",
		crystal = "rbxassetid://138453906297980",
		royal = "rbxassetid://116318616024072",
		starlit = "rbxassetid://117170530080097",
		stampede = "rbxassetid://139376529939199",
		frostfall = "rbxassetid://103434300241131",
		pearl = "rbxassetid://131920635758521",
		lantern = "rbxassetid://96382555718867",
		celestial = "rbxassetid://129355723949727",
		bloom = "rbxassetid://109390201494893",
		sky = "rbxassetid://123256031309487",
		splash = "rbxassetid://94831258385000",
		raid = "rbxassetid://72344320505577",
		harvest = "rbxassetid://124580127425302",
		dunes = "rbxassetid://96913911151127",
		glacier = "rbxassetid://120914925398637",
		leviathan = "rbxassetid://104125614974582",
		titan = "rbxassetid://96978102499663",
		reef = "rbxassetid://108889858128500",
	},
	ornaments = {
		royal = { mesh = "rbxassetid://96045268961641", texture = "rbxassetid://107952246798424", offset = { 0.0225, 0.5944, -0.0393 } },
		harvest = { mesh = "rbxassetid://72699994276831", texture = "rbxassetid://107952246798424", offset = { 0.0506, 0.6901, -0.0224 } },
		bloom = { mesh = "rbxassetid://119648881048261", texture = "rbxassetid://107952246798424", offset = { 0, 0.6308, -0.1246 } },
		sky = { mesh = "rbxassetid://79915657077588", texture = "rbxassetid://107952246798424", offset = { 0, 0.1871, 0.0726 } },
		glacier = { mesh = "rbxassetid://133024558412740", texture = "rbxassetid://107952246798424", offset = { 0.0049, 0.7, 0.0005 } },
	},
	cracks = { "rbxassetid://128839912356336", "rbxassetid://80106067358826", "rbxassetid://95690557075867" },
	painted = "rbxassetid://74542715250244",
}
