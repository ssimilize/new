--[[
	PROTOTYPE part library, written by write_library.py from capture.luau (do not edit by hand).
	Per species: `turn` (yaw that faces the pet to -Z), `body` (its body box over its largest
	dimension) and per locus the generated part: mesh + texture ids, `offset` from the body centre
	in body half-sizes, `scale` (size in the part's own axes over the body's largest dimension).
	`face` pieces ride on their own body (Assembler). All made with Roblox's generate_mesh
	(explicit segmentation), 2026-09-25; the prompts are in README.md.
]]

return {
	cat = {
		turn = 3.1416,
		body = { 0.9343, 0.8771, 1 },
		parts = {
			body = {
				mesh = "rbxassetid://118789962214933",
				texture = "rbxassetid://103185204495288",
				offset = { 0, 0, 0 },
				scale = { 0.9343, 0.8771, 1 },
			},
			ears = {
				mesh = "rbxassetid://98071377080071",
				texture = "rbxassetid://135913125903938",
				offset = { -0.0006, 0.8984, 0.0052 },
				scale = { 1.0117, 0.5058, 0.2105 },
			},
			tail = {
				mesh = "rbxassetid://130076490944443",
				texture = "rbxassetid://71425232125215",
				offset = { -0.0011, -0.3121, 1.2043 },
				scale = { 0.7785, 0.4712, 0.4133 },
			},
			legs = {
				mesh = "rbxassetid://73636132485493",
				texture = "rbxassetid://117579122085905",
				offset = { 0.0016, -1.0795, 0.2022 },
				scale = { 0.7248, 0.2846, 0.7242 },
			},
		},
	},
	chick = {
		turn = 3.1416,
		body = { 0.985, 1, 0.9257 },
		parts = {
			body = {
				mesh = "rbxassetid://139122399645087",
				texture = "rbxassetid://104276353939501",
				offset = { 0, 0, 0 },
				scale = { 0.985, 1, 0.9257 },
			},
			face = {
				mesh = "rbxassetid://115630058278402",
				texture = "rbxassetid://96114312344696",
				offset = { 0.0034, 0.0482, -1.0065 },
				scale = { 0.3275, 0.2137, 0.1439 },
			},
			ears = {
				mesh = "rbxassetid://71997689070326",
				texture = "rbxassetid://92800580972699",
				offset = { 0.0462, 1.1153, -0.0773 },
				scale = { 0.3119, 0.3288, 0.156 },
			},
			legs = {
				mesh = "rbxassetid://71523102575151",
				texture = "rbxassetid://128307781606613",
				offset = { 0.0027, -1.022, -0.3248 },
				scale = { 0.7378, 0.294, 0.4456 },
			},
			back = {
				mesh = "rbxassetid://126023708100795",
				texture = "rbxassetid://96183276838992",
				offset = { 0.0009, -0.2465, -0.0456 },
				scale = { 1.2969, 0.3402, 0.4344 },
			},
		},
	},
	corgi = {
		turn = 3.1416,
		body = { 0.7905, 0.8887, 1 },
		parts = {
			body = {
				mesh = "rbxassetid://134336317535426",
				texture = "rbxassetid://97465724959419",
				offset = { 0, 0, 0 },
				scale = { 0.7905, 0.8887, 1 },
			},
			ears = {
				mesh = "rbxassetid://116540840722448",
				texture = "rbxassetid://78918233372050",
				offset = { 0.0011, 1, -0.1059 },
				scale = { 0.9511, 0.5076, 0.1752 },
			},
			tail = {
				mesh = "rbxassetid://101753947771831",
				texture = "rbxassetid://78508585917797",
				offset = { -0.0016, -0.6628, 1.1448 },
				scale = { 0.586, 0.3599, 0.3745 },
			},
			legs = {
				mesh = "rbxassetid://114337869981156",
				texture = "rbxassetid://73444351940655",
				offset = { -0.0008, -0.8291, 0.1375 },
				scale = { 0.5798, 0.2893, 0.6078 },
			},
		},
	},
	dog = {
		turn = 3.1416,
		body = { 0.6976, 1, 0.9949 },
		parts = {
			body = {
				mesh = "rbxassetid://122206991444841",
				texture = "rbxassetid://113352116964961",
				offset = { 0, 0, 0 },
				scale = { 0.6976, 1, 0.9949 },
			},
			ears = {
				mesh = "rbxassetid://135204519461565",
				texture = "rbxassetid://92593961607689",
				offset = { 0, 0.3435, -0.151 },
				scale = { 1.1744, 0.4775, 0.4582 },
			},
			tail = {
				mesh = "rbxassetid://117104571285341",
				texture = "rbxassetid://100119850482475",
				offset = { 0.0023, -0.4797, 1.0714 },
				scale = { 0.4701, 0.1411, 0.2036 },
			},
			legs = {
				mesh = "rbxassetid://81196949322043",
				texture = "rbxassetid://86279294646442",
				offset = { 0.0033, -0.9676, 0.2326 },
				scale = { 0.5036, 0.1564, 0.675 },
			},
		},
	},
	dragon = {
		turn = 0,
		body = { 0.7413, 0.9934, 1 },
		parts = {
			body = {
				mesh = "rbxassetid://85177132054105",
				texture = "rbxassetid://124300258643266",
				offset = { 0, 0, 0 },
				scale = { 0.7413, 0.9934, 1 },
			},
			ears = {
				mesh = "rbxassetid://85871047522248",
				texture = "rbxassetid://77436052128956",
				offset = { -0.0011, 1.0113, 0.3728 },
				scale = { 0.8464, 0.2717, 0.2375 },
			},
			tail = {
				mesh = "rbxassetid://123003435302084",
				texture = "rbxassetid://77368005288149",
				offset = { 0.0007, -0.5207, 0.6909 },
				scale = { 0.2449, 0.3235, 0.1154 },
			},
			legs = {
				mesh = "rbxassetid://98430609685029",
				texture = "rbxassetid://101718082164947",
				offset = { 0.005, -0.9137, 0.1283 },
				scale = { 0.4673, 0.2053, 0.5294 },
			},
			back = {
				mesh = "rbxassetid://111471633975810",
				texture = "rbxassetid://134150049979070",
				offset = { -0.0001, -0.2104, 0.042 },
				scale = { 0.9801, 0.2012, 0.2532 },
			},
		},
	},
	tiger = {
		turn = -1.5708,
		body = { 0.8993, 0.8767, 1 },
		parts = {
			body = {
				mesh = "rbxassetid://122293601728169",
				texture = "rbxassetid://84858731032610",
				offset = { 0, 0, 0 },
				scale = { 1, 0.8767, 0.8993 },
			},
			ears = {
				mesh = "rbxassetid://88180044098355",
				texture = "rbxassetid://89964631007996",
				offset = { 0.0753, 0.8387, -0.0385 },
				scale = { 1.1631, 0.3686, 0.1683 },
			},
			tail = {
				mesh = "rbxassetid://96758631829531",
				texture = "rbxassetid://138510774159914",
				offset = { 0.0354, -1.1736, 1.0126 },
				scale = { 0.4896, 0.2566, 0.1404 },
			},
			legs = {
				mesh = "rbxassetid://121439142773150",
				texture = "rbxassetid://112166659959116",
				offset = { 0.0406, -1.2137, 0.0218 },
				scale = { 0.6563, 0.3804, 0.606 },
			},
		},
	},
}
