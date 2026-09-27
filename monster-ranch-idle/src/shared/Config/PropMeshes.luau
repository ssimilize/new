--[[
	PropMeshes: generated meshes for part-built props (Visuals/PropMesh swaps them in, the parts stay
	as the fallback). Made 2026-09-26 with Roblox's own generator from text prompts
	(tools/rbxgen/batches/props_decor.json, props_reef.json, props_battle.json), reviewed on the
	batch sheets (art/rbxgen/review_props_*.png, local: art/rbxgen is ignored) and published from Studio.

	Entry: { mesh, texture, turn = degrees?, scale = factor? } (see PropMesh.Replace for the fit).
	  decor    by Config.Decor id: replaces every piece of the placed item.
	  reef     by Config.DeepReef.Props key: replaces the parts whose names start with one of
	           `replace` (every part but the invisible body when there is no list), so the pads, the
	           portal, the pool and the bell's rope to the surface stay as they are.
	  battle   by BattleStage prop kind: replaces the whole prop (every region's theme uses it).
]]

local function m(mesh: number, texture: number, extra: { [string]: any }?)
	local entry = { mesh = "rbxassetid://" .. mesh, texture = "rbxassetid://" .. texture }
	for k, v in extra or {} do
		entry[k] = v
	end
	return entry
end

return {
	decor = {
		garden_fountain = m(138104993844248, 81065689150996),
		little_windmill = m(93023187214279, 73043837092308),
		monster_statue = m(77623190448041, 110748591305188),
		moon_bridge = m(129022164470449, 70815041152700),
		splash_pool = m(102721137588662, 72354480653431),
		stone_well = m(121267409001134, 126230825051476),
		star_obelisk = m(110775031209615, 130040758174973),
		stone_lion = m(120388945068475, 107121567569788),
		scarecrow = m(109519144700549, 106617185475349),
		snowman = m(96046401939514, 100008578626822),
	},
	reef = {
		dock = m(139979672781371, 81270367723585, { replace = { "Plank", "Post" } }),
		bell = m(101421212336569, 92601497922139, { replace = { "Bell" } }),
		gate = m(80586859315720, 130734641774480, { replace = { "PostL", "PostR", "Lintel", "Crust" } }),
		ruins = m(109472369269618, 108238774487462),
		giantClam = m(112498529975816, 85207412779142),
	},
	battle = {
		rock = m(137427785228455, 131028026745929),
		tree = m(91929786856087, 108341017588830),
		crystal = m(129597709547566, 100097960769508),
		pillar = m(139077890548052, 115524689504420),
		coral = m(83747016035351, 105662001972116),
		cactus = m(115109636619436, 108603600518686),
		spike = m(94920639898448, 75021412731613),
		mushroom = m(89306253416138, 98064290095502),
		torch = m(104325065662967, 120375207129137),
		banner = m(136261666269548, 104937029612468),
	},
}
