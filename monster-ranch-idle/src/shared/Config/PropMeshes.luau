--[[
	PropMeshes: generated meshes for part-built props (Visuals/PropMesh swaps them in, the parts stay
	as the fallback). Made 2026-09-26 with Roblox's own generator from text prompts
	(tools/rbxgen/batches/props_decor.json, props_reef.json, props_battle.json), reviewed on the
	batch sheets (art/rbxgen/review_props_*.png, local: art/rbxgen is ignored) and published from Studio.
	The decor pieces after the first ten (2026-10-02) are Meshy models from Codex concepts instead:
	tools/meshy/props/make.py, then tools/blender/export_static.py; `make.py ids` writes their rows.

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
		hay_bale = m(115889349919944, 108641000549850),
		gift_pile = m(82430498899619, 90724041652517),
		flower_bed = m(128160293509905, 110300618002826),
		golden_statue = m(98461621898478, 96991173996316),
		haunted_tree = m(82164900528161, 72150465476632),
		jack_o_lantern = m(98596658539312, 78554298486599),
		moon_gate = m(93420122042657, 102614672051528),
		wood_crate = m(78245218689924, 135107952584440),
		water_trough = m(109720944117386, 83417547303874),
		lantern = m(96074163682518, 123590887549188),
		scratch_post = m(93761300476719, 121989472083355),
		slide = m(121742075931857, 125539239123914),
		palm_tree = m(135662705920536, 106584386431999),
		fountain = m(129478731195855, 131796955227719),
		cherry_tree = m(99909294516387, 82019113088468),
		pine_tree = m(132354311770244, 112845623715836),
		oak_tree = m(99753120784981, 119559834019279),
		garden_lantern = m(100061545177649, 104325764245471),
		shell_pile = m(119340938171084, 95460824635335),
		round_bush = m(102088519841710, 81955922666925),
		wood_lamp = m(126158234840940, 80849096706751),
		rainbow_arch = m(125061757044235, 106494995042627),
		tide_pool = m(122583468143301, 72214492714752),
		sandcastle = m(98761046781005, 96678557607831),
		beach_umbrella = m(101894121284354, 133494501248612),
		crystal_cluster = m(93642050802309, 139681630443374),
		snow_globe = m(102338084845816, 129858099535176),
		tiki_torch = m(72025932862002, 91215324899101),
		paper_lantern = m(100190867136397, 79408480007796),
		bloom_arch = m(104750357458604, 121219489392597),
		barrel = m(111470350755857, 137552334855173),
		bird_bath = m(130707862532800, 115481059895260),
		crystal_lamp = m(102384988077083, 79515938440456),
		beach_ball = m(132830495651283, 106302498783587),
		climbing_tower = m(105809259084080, 118998937974193),
		bouncy_mushroom = m(88746355454789, 103786536809019),
		mailbox = m(125641342089765, 108604936697957),
		lily_pond = m(104220319417282, 103248183311705),
		park_bench = m(109956368041528, 122978186798182),
		pirate_chest = m(85401653990857, 130343504132238),
		picnic_table = m(122318584810370, 140130271973845),
		frosty_pine = m(119003159321337, 122851821229741),
		hay_cart = m(110491521632864, 113374614630903),
		signpost = m(101070131343242, 110380874449525),
		seesaw = m(80599852962446, 99551741668712),
		rose_arch = m(137668360137784, 88639198755089),
		potted_plant = m(139428188715536, 112000895796650),
		stone_arch = m(135806851792344, 117858479444782),
		pumpkin_patch = m(117724575437279, 81378307520365),
		swing_set = m(120524943517928, 112940796417402),
		torch_post = m(74368634906250, 102075979631678),
		stone_bench = m(87414962221085, 76756095351919),
		street_lamp = m(74552143840184, 91246586698654),
		tulip_patch = m(110422061150199, 137662811407922),
		tire_swing = m(140462779560837, 76427300982213),
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
