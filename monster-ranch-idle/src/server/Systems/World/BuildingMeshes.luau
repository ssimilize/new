--[[
	World/BuildingMeshes: the Meshy models that dress the placeholder buildings (Dress.luau), by
	building id: a World.Hub id, or "barn" for every plot's barn. Written by
	`tools/blender/export_static.py ids`; a building missing here keeps its placeholder boxes.

	A building comes in pieces, each its own mesh with its own 1024 px texture (Roblox's cap), so a
	big building is not stuck with one texture's worth of detail. size: the whole building's box
	(x wide, y tall, z deep) at 1 unit tall; offset: each piece's box centre from the building's.
]]

return {
	eggShop = {
		size = { 1.14365, 1, 0.88677 },
		parts = {
			{ mesh = "rbxassetid://114517396159210", texture = "rbxassetid://98629054174285", offset = { 0.25867, -0.29294, 0.04111 } },
			{ mesh = "rbxassetid://70391017360350", texture = "rbxassetid://71724367498428", offset = { 0.27294, 0.02355, -0.22315 } },
			{ mesh = "rbxassetid://107840837751467", texture = "rbxassetid://116202997263479", offset = { 0.27013, 0.00736, 0.14207 } },
			{ mesh = "rbxassetid://119415173110680", texture = "rbxassetid://99794451322231", offset = { -0.17568, -0.27217, -0.27322 } },
			{ mesh = "rbxassetid://95920990542935", texture = "rbxassetid://95975429951157", offset = { -0.16667, -0.25533, 0.09428 } },
			{ mesh = "rbxassetid://112853320531622", texture = "rbxassetid://110478276486460", offset = { -0.17304, 0.18824, -0.22822 } },
			{ mesh = "rbxassetid://90701981148560", texture = "rbxassetid://136079996188620", offset = { -0.17838, 0.14584, 0.10689 } },
		},
	},
	feedStore = {
		size = { 1.24441, 1, 0.93282 },
		parts = {
			{ mesh = "rbxassetid://112334590147779", texture = "rbxassetid://81635945251710", offset = { 0.10644, -0.20102, -0.16553 } },
			{ mesh = "rbxassetid://74197572385029", texture = "rbxassetid://72551896286372", offset = { 0.13972, 0.09519, -0.06271 } },
			{ mesh = "rbxassetid://120181359859811", texture = "rbxassetid://81478723351467", offset = { 0.10045, -0.21635, 0.10715 } },
			{ mesh = "rbxassetid://77831573471553", texture = "rbxassetid://103970007056301", offset = { -0.03394, 0.00953, 0.12274 } },
			{ mesh = "rbxassetid://82909372926511", texture = "rbxassetid://106016097045312", offset = { -0.08896, -0.19962, -0.26897 } },
			{ mesh = "rbxassetid://104910860529101", texture = "rbxassetid://117293282858188", offset = { -0.0895, -0.19269, 0.11346 } },
			{ mesh = "rbxassetid://109145365411794", texture = "rbxassetid://112064545324319", offset = { -0.17509, 0.24196, -0.02038 } },
			{ mesh = "rbxassetid://75043087117381", texture = "rbxassetid://74245387230956", offset = { -0.06979, 0.18857, 0.12445 } },
		},
	},
	barn = {
		size = { 0.983, 1, 1.16492 },
		parts = {
			{ mesh = "rbxassetid://88995898735132", texture = "rbxassetid://129894644029626", offset = { -0.00051, -0.18377, -0.1388 } },
			{ mesh = "rbxassetid://112899467342522", texture = "rbxassetid://96238997377016", offset = { -0.00012, 0.21911, -0.04311 } },
			{ mesh = "rbxassetid://74907921078363", texture = "rbxassetid://124393051129287", offset = { 0.00052, -0.19277, 0.11004 } },
			{ mesh = "rbxassetid://94946849268686", texture = "rbxassetid://127509091866856", offset = { 4e-05, 0.22545, 0.03045 } },
		},
	},
	trading = {
		size = { 1.13725, 1, 0.99816 },
		parts = {
			{ mesh = "rbxassetid://99841454604083", texture = "rbxassetid://107816897355026", offset = { 0.24692, -0.31554, -0.00905 } },
			{ mesh = "rbxassetid://119634966486325", texture = "rbxassetid://125206311210061", offset = { 0.25392, 0.13543, -0.23152 } },
			{ mesh = "rbxassetid://129894091397858", texture = "rbxassetid://83422694541764", offset = { 0.2605, 0.07833, 0.2072 } },
			{ mesh = "rbxassetid://79639769064860", texture = "rbxassetid://85170081996842", offset = { -0.25114, -0.01538, -0.29031 } },
			{ mesh = "rbxassetid://99054019839784", texture = "rbxassetid://79670839546345", offset = { -0.26547, -0.31809, 0.13876 } },
			{ mesh = "rbxassetid://126592482338058", texture = "rbxassetid://108272592950700", offset = { -0.22977, 0.08235, 0.16349 } },
		},
	},
	gate = {
		size = { 1.05339, 1, 0.28803 },
		parts = {
			{ mesh = "rbxassetid://114034089608541", texture = "rbxassetid://95295476636335", offset = { 0.24937, -0.2412, -0.00948 } },
			{ mesh = "rbxassetid://96690315465368", texture = "rbxassetid://87260533784669", offset = { 0.24297, 0.19961, 0.00059 } },
			{ mesh = "rbxassetid://122234038378594", texture = "rbxassetid://112924720006809", offset = { -0.24443, -0.25172, -0.00905 } },
			{ mesh = "rbxassetid://79712660504278", texture = "rbxassetid://114528541740286", offset = { -0.24088, 0.20898, -0.00013 } },
		},
	},
	hallOfFame = {
		size = { 0.96805, 1, 1.13622 },
		parts = {
			{ mesh = "rbxassetid://138315817095157", texture = "rbxassetid://120060587824933", offset = { 0.00046, -0.21122, -0.31986 } },
			{ mesh = "rbxassetid://83948503451854", texture = "rbxassetid://125988860547441", offset = { -0.00016, 0.22228, -0.27539 } },
			{ mesh = "rbxassetid://115318586679722", texture = "rbxassetid://111988625984715", offset = { 0.00048, -0.28441, 0.19119 } },
			{ mesh = "rbxassetid://112220408281061", texture = "rbxassetid://104179458510622", offset = { 0.21741, 0.15526, 0.18789 } },
			{ mesh = "rbxassetid://94367631915668", texture = "rbxassetid://119800196383687", offset = { -0.22011, 0.13482, 0.18767 } },
		},
	},
	arena = {
		size = { 1.66784, 1, 1.6612 },
		parts = {
			{ mesh = "rbxassetid://96478195636626", texture = "rbxassetid://118258384767193", offset = { 0.37838, -0.24875, -0.29752 } },
			{ mesh = "rbxassetid://122808275023364", texture = "rbxassetid://104784155074567", offset = { 0.37386, 0.19242, -0.31336 } },
			{ mesh = "rbxassetid://97967249573055", texture = "rbxassetid://91496640031708", offset = { 0.38177, -0.27194, 0.42345 } },
			{ mesh = "rbxassetid://113946736683131", texture = "rbxassetid://96453636972841", offset = { 0.37288, 0.22526, 0.41544 } },
			{ mesh = "rbxassetid://119912401902146", texture = "rbxassetid://98990745465878", offset = { -0.39305, -0.25302, -0.31371 } },
			{ mesh = "rbxassetid://71768927671060", texture = "rbxassetid://113235371881713", offset = { -0.37093, 0.18922, -0.35251 } },
			{ mesh = "rbxassetid://98413345931850", texture = "rbxassetid://111314572714254", offset = { -0.39623, -0.27193, 0.42191 } },
			{ mesh = "rbxassetid://101968952190486", texture = "rbxassetid://97482932560168", offset = { -0.37199, 0.22417, 0.41305 } },
		},
	},
	market = {
		size = { 1.27164, 1, 1.07153 },
		parts = {
			{ mesh = "rbxassetid://86515563332846", texture = "rbxassetid://120505365861297", offset = { 0.22737, 0.00057, -0.30731 } },
			{ mesh = "rbxassetid://97872486289882", texture = "rbxassetid://84891584465139", offset = { 0.24836, -0.23993, 0.13961 } },
			{ mesh = "rbxassetid://108674802331478", texture = "rbxassetid://116256001406944", offset = { 0.16928, 0.17532, 0.16254 } },
			{ mesh = "rbxassetid://104486450333267", texture = "rbxassetid://93789797882825", offset = { -0.28021, 0.00117, -0.30514 } },
			{ mesh = "rbxassetid://120993951280846", texture = "rbxassetid://99061746648787", offset = { -0.3005, -0.23884, 0.13921 } },
			{ mesh = "rbxassetid://96786853350306", texture = "rbxassetid://94383081939531", offset = { -0.29295, 0.18132, 0.13525 } },
		},
	},
	starAltar = {
		size = { 1.24631, 1, 1.37749 },
		parts = {
			{ mesh = "rbxassetid://79816756079926", texture = "rbxassetid://83687303232545", offset = { -9e-05, -0.0024, -0.27881 } },
			{ mesh = "rbxassetid://89229502378759", texture = "rbxassetid://79384910046458", offset = { 0, 0.0062, 0.37394 } },
		},
	},
	showStage = {
		size = { 1.32209, 1, 0.77788 },
		parts = {
			{ mesh = "rbxassetid://80817131478543", texture = "rbxassetid://95952106359034", offset = { 0.26054, -0.23681, -0.01125 } },
			{ mesh = "rbxassetid://126319512120339", texture = "rbxassetid://115372049947374", offset = { 0.29528, 0.16979, 0.23765 } },
			{ mesh = "rbxassetid://79967535016598", texture = "rbxassetid://94257315012841", offset = { -0.26396, -0.25661, -0.01142 } },
			{ mesh = "rbxassetid://93811212267146", texture = "rbxassetid://96945420092368", offset = { -0.29951, 0.17141, 0.23742 } },
		},
	},
	surfShack = {
		size = { 1.00507, 1, 0.83556 },
		parts = {
			{ mesh = "rbxassetid://81944924342561", texture = "rbxassetid://134237373993243", offset = { 0.17754, -0.32369, -0.02386 } },
			{ mesh = "rbxassetid://76881863205884", texture = "rbxassetid://134131424630988", offset = { 0.22133, 0.11721, -0.18382 } },
			{ mesh = "rbxassetid://85643462916483", texture = "rbxassetid://140298869490815", offset = { 0.23585, 0.06913, 0.15654 } },
			{ mesh = "rbxassetid://140722640704166", texture = "rbxassetid://101036006459549", offset = { -0.17382, -0.32177, -0.02383 } },
			{ mesh = "rbxassetid://110411541437207", texture = "rbxassetid://125404099341686", offset = { -0.22301, 0.10714, -0.18329 } },
			{ mesh = "rbxassetid://126099786313235", texture = "rbxassetid://73655002073948", offset = { -0.22705, 0.07569, 0.15541 } },
		},
	},
	clubPlaza = {
		size = { 0.96761, 1, 0.75571 },
		parts = {
			{ mesh = "rbxassetid://84147380184059", texture = "rbxassetid://136179955573152", offset = { 0, -0.35525, -0.02705 } },
			{ mesh = "rbxassetid://101519376554710", texture = "rbxassetid://86176748912330", offset = { 0.1836, 0.1237, -0.00956 } },
			{ mesh = "rbxassetid://91388848794631", texture = "rbxassetid://90937390841174", offset = { -0.22988, 0.00617, 2e-05 } },
		},
	},
	championsArena = {
		size = { 1.55442, 1, 1.54552 },
		parts = {
			{ mesh = "rbxassetid://104986196708303", texture = "rbxassetid://128003719338869", offset = { 0.34892, -0.2515, -0.34386 } },
			{ mesh = "rbxassetid://118401012873121", texture = "rbxassetid://89137206985857", offset = { 0.35717, 0.18164, -0.38033 } },
			{ mesh = "rbxassetid://76922081319995", texture = "rbxassetid://90175063914625", offset = { 0.34499, -0.27818, 0.34612 } },
			{ mesh = "rbxassetid://86816757511519", texture = "rbxassetid://98259762532827", offset = { 0.36241, 0.10232, 0.3531 } },
			{ mesh = "rbxassetid://137029917133310", texture = "rbxassetid://89920817244604", offset = { -0.35372, -0.24643, -0.34709 } },
			{ mesh = "rbxassetid://109338187502833", texture = "rbxassetid://130930657969552", offset = { -0.36013, 0.18241, -0.38168 } },
			{ mesh = "rbxassetid://77308606482135", texture = "rbxassetid://100198949791716", offset = { -0.34901, -0.28009, 0.35089 } },
			{ mesh = "rbxassetid://111773210607171", texture = "rbxassetid://77487902366928", offset = { -0.3603, 0.10204, 0.34687 } },
		},
	},
	raidPortal = {
		size = { 0.9744, 1, 0.91585 },
		parts = {
			{ mesh = "rbxassetid://102424730788653", texture = "rbxassetid://71255913768663", offset = { 0, -0.38932, 0 } },
			{ mesh = "rbxassetid://104431853198545", texture = "rbxassetid://134495459755351", offset = { 0.22605, 0.08395, -0.00153 } },
			{ mesh = "rbxassetid://137904704912608", texture = "rbxassetid://81328111735245", offset = { -0.22734, 0.08638, -0.00122 } },
		},
	},
	racetrack = {
		size = { 1.33774, 1, 0.60862 },
		parts = {
			{ mesh = "rbxassetid://94867953790907", texture = "rbxassetid://116909417398534", offset = { 0.36228, -0.33177, -0.14188 } },
			{ mesh = "rbxassetid://79931413263411", texture = "rbxassetid://119581444300167", offset = { 0.36682, -0.32513, 0.09065 } },
			{ mesh = "rbxassetid://85127302465045", texture = "rbxassetid://120426002512532", offset = { 0.34952, -0.04019, 0.02288 } },
			{ mesh = "rbxassetid://129807863581001", texture = "rbxassetid://133391419768923", offset = { 0.37414, 0.27063, 0.01234 } },
			{ mesh = "rbxassetid://125742666254314", texture = "rbxassetid://102525693298755", offset = { -0.05813, -0.33175, -0.02658 } },
			{ mesh = "rbxassetid://113750655342876", texture = "rbxassetid://99222400073068", offset = { -0.46112, -0.34014, -1e-05 } },
			{ mesh = "rbxassetid://108997524762207", texture = "rbxassetid://139624931941397", offset = { 0.0063, 0.11908, 0.01235 } },
			{ mesh = "rbxassetid://134092891756265", texture = "rbxassetid://96261724458263", offset = { -0.37228, -0.02925, 0.023 } },
		},
	},
	hubPortal = {
		size = { 0.53465, 1, 0.53568 },
		parts = {
			{ mesh = "rbxassetid://81381013637974", texture = "rbxassetid://81150567739293", offset = { 0.12114, -0.29632, 0.00268 } },
			{ mesh = "rbxassetid://114732939279317", texture = "rbxassetid://125106915098679", offset = { -0.12487, -0.28765, 0.00268 } },
			{ mesh = "rbxassetid://102172528918552", texture = "rbxassetid://91353854875888", offset = { 0, -0.03149, 0 } },
			{ mesh = "rbxassetid://132910061868957", texture = "rbxassetid://128818804209520", offset = { 0.00011, 0.28434, -0.00044 } },
		},
	},
	workshop = {
		size = { 1.04369, 1, 0.95164 },
		parts = {
			{ mesh = "rbxassetid://81134772567123", texture = "rbxassetid://126510446428431", offset = { 0.19318, -0.31787, -0.02168 } },
			{ mesh = "rbxassetid://87784173241026", texture = "rbxassetid://77755228608720", offset = { 0.24279, 0.1411, -0.28443 } },
			{ mesh = "rbxassetid://75610881230353", texture = "rbxassetid://75900774173136", offset = { 0.22393, 0.09033, 0.13743 } },
			{ mesh = "rbxassetid://79882348350664", texture = "rbxassetid://122208601763642", offset = { -0.22555, -0.28141, -0.20259 } },
			{ mesh = "rbxassetid://92565404923109", texture = "rbxassetid://100095929129117", offset = { -0.18768, 0.13515, -0.16607 } },
			{ mesh = "rbxassetid://139245343469524", texture = "rbxassetid://82544509849959", offset = { -0.23449, -0.27205, 0.21141 } },
			{ mesh = "rbxassetid://88217014377415", texture = "rbxassetid://71335464003730", offset = { -0.17846, 0.14457, 0.21336 } },
		},
	},
}
