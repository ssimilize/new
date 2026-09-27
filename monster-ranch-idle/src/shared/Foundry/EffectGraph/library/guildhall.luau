--!nonstrict
-- generated from packages/EffectGraph/graphs/guildhall.json by
-- `foundry vfx export --write`; edit the JSON, not this file
return {
	{
		schema = "foundry.effect/1",
		id = "sawdust",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-28,
						0,
					},
					Color = "#D9B98A",
					Drag = 1.5,
					Lifetime = {
						0.5,
						0.9,
					},
					LightInfluence = 1,
					RotSpeed = {
						-380,
						380,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.20800000000000002,
						},
						{
							1,
							0.128,
						},
					},
					Speed = {
						4,
						9,
					},
					SpreadAngle = {
						55,
						55,
					},
				},
				emit = 12,
				sprite = "chip",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E6D3B0",
					Drag = 2,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.9,
						1.4,
					},
					LightInfluence = 1,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.5,
						},
						{
							1,
							1.6,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
					Transparency = {
						{
							0,
							0.45,
						},
						{
							0.7,
							0.67,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1.1199999999999999,
				},
				emit = 3,
				minQuality = "medium",
				sprite = "smoke_puff",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "stone_dust",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#B8B2A6",
					Drag = 2,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.9,
						1.4,
					},
					LightInfluence = 1,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.8,
						},
						{
							1,
							2.4,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
					Transparency = {
						{
							0,
							0.45,
						},
						{
							0.7,
							0.67,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1.68,
				},
				emit = 6,
				sprite = "smoke_puff",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-42,
						0,
					},
					Color = "#9A948A",
					Lifetime = {
						0.5,
						0.9,
					},
					LightInfluence = 1,
					RotSpeed = {
						-380,
						380,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.26,
						},
						{
							1,
							0.16000000000000003,
						},
					},
					Speed = {
						6,
						10,
					},
					SpreadAngle = {
						55,
						55,
					},
				},
				emit = 6,
				minQuality = "medium",
				sprite = "chip",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "ore_glint",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FFF6D0",
						},
						{
							1,
							"#FFD27A",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Sphere",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.9,
						},
						{
							0.8,
							0.9,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.5,
						1.5,
					},
					SpreadAngle = {
						180,
						180,
					},
				},
				emit = 5,
				box = {
					2,
					2,
					2,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p2",
				kind = "light",
				at = 0,
				duration = 0.3,
				props = {
					Brightness = 1.5,
					Color = "#FFE0A0",
					Range = 6,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "fish_splash_ring",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#D8F2FF",
					Lifetime = 0.6,
					LightEmission = 0.6,
					LightInfluence = 0.4,
					Size = {
						{
							0,
							0.4,
						},
						{
							1,
							6,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.25,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 4.199999999999999,
				},
				emit = 1,
				sprite = "shockwave_ring",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-35,
						0,
					},
					Color = "#E4F6FF",
					Lifetime = {
						0.5,
						0.9,
					},
					LightInfluence = 1,
					RotSpeed = 0,
					Rotation = 0,
					Size = {
						{
							0,
							0.26,
						},
						{
							1,
							0.16000000000000003,
						},
					},
					Speed = {
						6,
						10,
					},
					SpreadAngle = {
						25,
						25,
					},
				},
				emit = 10,
				sprite = "chip",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0.2,
				duration = 0,
				props = {
					Color = "#BFE8FF",
					Lifetime = 0.9,
					LightEmission = 0.6,
					LightInfluence = 0.4,
					Size = {
						{
							0,
							0.4,
						},
						{
							1,
							9,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.25,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 6.3,
				},
				emit = 1,
				minQuality = "medium",
				sprite = "shockwave_ring",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "herb_sparkle",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						2,
						0,
					},
					Color = {
						{
							0,
							"#D8FFB0",
						},
						{
							1,
							"#5AD65A",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.5,
						},
						{
							0.8,
							0.5,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				emit = 10,
				sprite = "sparkle_twinkle",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.4,
						-8,
						0,
					},
					Color = "#6FB84A",
					Lifetime = {
						0.8,
						1.2,
					},
					LightInfluence = 1,
					RotSpeed = {
						-380,
						380,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.26,
						},
						{
							1,
							0.16000000000000003,
						},
					},
					Speed = {
						2,
						5,
					},
					SpreadAngle = {
						55,
						55,
					},
				},
				emit = 5,
				minQuality = "medium",
				sprite = "chip",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "hide_scraps",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-42,
						0,
					},
					Color = {
						{
							0,
							"#C79A6A",
						},
						{
							1,
							"#A0764A",
						},
					},
					Lifetime = {
						0.5,
						0.9,
					},
					LightInfluence = 1,
					RotSpeed = {
						-380,
						380,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.28600000000000003,
						},
						{
							1,
							0.17600000000000002,
						},
					},
					Speed = {
						5,
						9,
					},
					SpreadAngle = {
						55,
						55,
					},
				},
				emit = 8,
				sprite = "chip",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E8DCC4",
					Drag = 2,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.9,
						1.4,
					},
					LightInfluence = 1,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.4,
						},
						{
							1,
							1.2,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
					Transparency = {
						{
							0,
							0.45,
						},
						{
							0.7,
							0.67,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 0.84,
				},
				emit = 3,
				minQuality = "medium",
				sprite = "smoke_puff",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "anvil_sparks",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-40,
						0,
					},
					Color = {
						{
							0,
							"#FFE08A",
						},
						{
							0.5,
							"#FF9A2E",
						},
						{
							1,
							"#FF4A12",
						},
					},
					Lifetime = {
						0.3,
						0.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0.25,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						10,
						18,
					},
					SpreadAngle = {
						70,
						70,
					},
					Texture = "rbxasset://textures/particles/fire_sparks_main.dds",
				},
				emit = 22,
			},
			{
				id = "p2",
				kind = "light",
				at = 0,
				duration = 0.15,
				props = {
					Brightness = 3,
					Color = "#FF9A4A",
					Range = 10,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "molten_pour",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-20,
						0,
					},
					Color = {
						{
							0,
							"#FFE7A0",
						},
						{
							0.5,
							"#FFA03A",
						},
						{
							1,
							"#E0400C",
						},
					},
					Lifetime = {
						0.4,
						0.7,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0.6,
						},
						{
							1,
							0.2,
						},
					},
					Speed = {
						2,
						4,
					},
					SpreadAngle = {
						15,
						15,
					},
					Texture = "rbxasset://textures/particles/fire_main.dds",
				},
				emit = 8,
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-42,
						0,
					},
					Color = "#FFB04A",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					RotSpeed = {
						-380,
						380,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.156,
						},
						{
							1,
							0.096,
						},
					},
					Speed = {
						4,
						8,
					},
					SpreadAngle = {
						55,
						55,
					},
					Texture = "rbxasset://textures/particles/fire_sparks_main.dds",
				},
				emit = 8,
				minQuality = "medium",
			},
			{
				id = "p3",
				kind = "light",
				at = 0,
				duration = 0.4,
				props = {
					Brightness = 2.5,
					Color = "#FF7A2A",
					Range = 10,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "gem_glint",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FFFFFF",
						},
						{
							1,
							"#9AE8FF",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Sphere",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							1.1,
						},
						{
							0.8,
							1.1,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0,
						1,
					},
					SpreadAngle = {
						180,
						180,
					},
					ZOffset = 0.77,
				},
				emit = 6,
				box = {
					1.2,
					1.2,
					1.2,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p2",
				kind = "light",
				at = 0,
				duration = 0.25,
				props = {
					Brightness = 2,
					Color = "#BFF4FF",
					Range = 6,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "feather_puff",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.4,
						-4,
						0,
					},
					Color = "#F4EFE4",
					Drag = 2,
					Lifetime = {
						1.2,
						1.8,
					},
					LightInfluence = 1,
					RotSpeed = {
						-200,
						200,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.5,
					Speed = {
						3,
						6,
					},
					SpreadAngle = {
						80,
						80,
					},
					Squash = 0.6,
				},
				emit = 8,
				sprite = "feather",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "seed_scatter",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-42,
						0,
					},
					Color = "#7A5A2A",
					Lifetime = {
						0.5,
						0.9,
					},
					LightInfluence = 1,
					RotSpeed = {
						-380,
						380,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.156,
						},
						{
							1,
							0.096,
						},
					},
					Speed = {
						4,
						8,
					},
					SpreadAngle = {
						40,
						40,
					},
				},
				emit = 12,
				sprite = "chip",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "harvest_pop",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-42,
						0,
					},
					Color = {
						{
							0,
							"#E8C040",
						},
						{
							1,
							"#8BD34A",
						},
					},
					Lifetime = {
						0.5,
						0.9,
					},
					LightInfluence = 1,
					RotSpeed = {
						-380,
						380,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.312,
						},
						{
							1,
							0.192,
						},
					},
					Speed = {
						5,
						9,
					},
					SpreadAngle = {
						55,
						55,
					},
				},
				emit = 10,
				sprite = "chip",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF2A0",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.5,
						},
						{
							0.8,
							0.5,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				emit = 5,
				minQuality = "medium",
				sprite = "sparkle_twinkle",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "dust_kick",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#CDB58E",
						},
						{
							1,
							"#A8916E",
						},
					},
					Drag = 2,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.9,
						1.4,
					},
					LightInfluence = 1,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						0,
						360,
					},
					Shape = "Disc",
					Size = {
						{
							0,
							0.8,
						},
						{
							1,
							2.2,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						80,
						80,
					},
					Transparency = {
						{
							0,
							0.45,
						},
						{
							0.7,
							0.67,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1.54,
				},
				emit = 6,
				box = {
					1.6,
					0.2,
					1.6,
				},
				sprite = "smoke_puff",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "coin_snatch",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-42,
						0,
					},
					Color = {
						{
							0,
							"#FFE070",
						},
						{
							1,
							"#E0A100",
						},
					},
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 0.3,
					LightInfluence = 0.5,
					RotSpeed = {
						-380,
						380,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.39,
						},
						{
							1,
							0.24,
						},
					},
					Speed = {
						6,
						10,
					},
					SpreadAngle = {
						25,
						25,
					},
				},
				emit = 6,
				sprite = "chip",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF3B0",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.5,
						},
						{
							0.8,
							0.5,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				emit = 4,
				sprite = "sparkle_twinkle",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "enchant_flash",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#B08CFF",
						},
						{
							1,
							"#4DE1FF",
						},
					},
					Lifetime = 0.5,
					LightEmission = 1,
					LightInfluence = 0,
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.5,
						},
						{
							1,
							4,
						},
					},
					Speed = 0,
					Texture = "rbxasset://textures/particles/explosion01_implosion_main.dds",
					Transparency = {
						{
							0,
							0.2,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 2.8,
				},
				emit = 2,
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#D8B8FF",
					Drag = 2,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.4,
						},
						{
							0.8,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						4,
						8,
					},
					SpreadAngle = {
						180,
						180,
					},
				},
				emit = 16,
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "light",
				at = 0,
				duration = 0.3,
				props = {
					Brightness = 2.5,
					Color = "#A070FF",
					Range = 10,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 5,
	},
	{
		schema = "foundry.effect/1",
		id = "potion_pop",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						2,
						0,
					},
					Color = {
						{
							0,
							"#C8FF9A",
						},
						{
							1,
							"#4AC04A",
						},
					},
					Lifetime = {
						0.6,
						1,
					},
					LightEmission = 0.6,
					LightInfluence = 0.3,
					Size = {
						{
							0,
							0.3,
						},
						{
							1,
							0.6,
						},
					},
					Speed = {
						3,
						6,
					},
					SpreadAngle = {
						30,
						30,
					},
					Transparency = {
						{
							0,
							0.2,
						},
						{
							0.8,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 10,
				sprite = "glow_soft",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E8FFE0",
					Drag = 2,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.9,
						1.4,
					},
					LightInfluence = 1,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.4,
						},
						{
							1,
							1.2,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
					Transparency = {
						{
							0,
							0.45,
						},
						{
							0.7,
							0.67,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 0.84,
				},
				emit = 2,
				minQuality = "medium",
				sprite = "smoke_puff",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "trap_snap",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-42,
						0,
					},
					Color = "#6A4A2A",
					Lifetime = {
						0.5,
						0.9,
					},
					LightInfluence = 1,
					RotSpeed = {
						-380,
						380,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.23399999999999999,
						},
						{
							1,
							0.144,
						},
					},
					Speed = {
						5,
						8,
					},
					SpreadAngle = {
						55,
						55,
					},
				},
				emit = 6,
				sprite = "chip",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#BFA884",
					Drag = 2,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.9,
						1.4,
					},
					LightInfluence = 1,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.5,
						},
						{
							1,
							1.4,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
					Transparency = {
						{
							0,
							0.45,
						},
						{
							0.7,
							0.67,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 0.9799999999999999,
				},
				emit = 3,
				minQuality = "medium",
				sprite = "smoke_puff",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "wisp_catch",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#7AF0FF",
					Lifetime = 0.6,
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							1.4,
						},
						{
							1,
							0,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.1,
						},
						{
							1,
							0.8,
						},
					},
					ZOffset = 0.9799999999999999,
				},
				emit = 1,
				sprite = "glow_soft",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#BFFBFF",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.4,
						},
						{
							0.8,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						-5,
						-2,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				emit = 14,
				box = {
					3,
					3,
					3,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "light",
				at = 0,
				duration = 0.3,
				props = {
					Brightness = 2,
					Color = "#7AF0FF",
					Range = 8,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "craft_pop",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF6C8",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.6,
						},
						{
							0.8,
							0.6,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				emit = 8,
				sprite = "sparkle_twinkle",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE7A0",
					Lifetime = 0.35,
					LightEmission = 0.6,
					LightInfluence = 0.4,
					Size = {
						{
							0,
							0.4,
						},
						{
							1,
							3,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.25,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 2.0999999999999996,
				},
				emit = 1,
				minQuality = "medium",
				sprite = "shockwave_ring",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "flour_puff",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#F6F0E2",
					Drag = 2,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.9,
						1.4,
					},
					LightInfluence = 1,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.6,
						},
						{
							1,
							1.8,
						},
					},
					Speed = {
						1,
						2.5,
					},
					SpreadAngle = {
						70,
						70,
					},
					Transparency = {
						{
							0,
							0.45,
						},
						{
							0.7,
							0.67,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1.26,
				},
				emit = 5,
				sprite = "smoke_puff",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "leaf_shake",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.5,
						-3,
						0,
					},
					Color = {
						{
							0,
							"#8BB33F",
						},
						{
							1,
							"#5E8A2A",
						},
					},
					Lifetime = {
						1.5,
						2.5,
					},
					LightInfluence = 1,
					RotSpeed = {
						-200,
						200,
					},
					Rotation = {
						0,
						360,
					},
					Shape = "Sphere",
					Size = 0.55,
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 10,
				offset = {
					0,
					4,
					0,
				},
				box = {
					3,
					3,
					3,
				},
				sprite = "leaf",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "ember_pop",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						2,
						0,
					},
					Color = {
						{
							0,
							"#FFD27A",
						},
						{
							1,
							"#FF6A1A",
						},
					},
					Drag = 1,
					Lifetime = {
						0.6,
						1.1,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0.2,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						4,
						9,
					},
					SpreadAngle = {
						40,
						40,
					},
					Texture = "rbxasset://textures/particles/fire_sparks_main.dds",
				},
				emit = 14,
			},
			{
				id = "p2",
				kind = "light",
				at = 0,
				duration = 0.25,
				props = {
					Brightness = 2,
					Color = "#FF8A3A",
					Range = 8,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "prayer_chime",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FFF6C8",
						},
						{
							1,
							"#FFD24A",
						},
					},
					Drag = 3,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.6,
						},
						{
							0.8,
							0.6,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						4,
						7,
					},
					SpreadAngle = {
						180,
						10,
					},
				},
				emit = 16,
				sprite = "sparkle_twinkle",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0.1,
				duration = 0,
				props = {
					Acceleration = {
						0,
						4,
						0,
					},
					Color = "#FFE89A",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.4,
						},
						{
							0.8,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				emit = 8,
				minQuality = "medium",
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "light",
				at = 0,
				duration = 0.4,
				props = {
					Brightness = 2,
					Color = "#FFF0C0",
					Range = 10,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "constellation_flash",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FFFFFF",
						},
						{
							1,
							"#9EC8FF",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						1.2,
						1.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Box",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							1.2,
						},
						{
							0.8,
							1.2,
						},
						{
							1,
							0,
						},
					},
					Speed = 0,
					SpreadAngle = {
						70,
						70,
					},
				},
				emit = 7,
				offset = {
					0,
					6,
					0,
				},
				box = {
					5,
					2,
					5,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p2",
				kind = "light",
				at = 0,
				duration = 0.4,
				props = {
					Brightness = 1.5,
					Color = "#9EC8FF",
					Range = 12,
				},
				offset = {
					0,
					6,
					0,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "familiar_summon",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#C08CFF",
						},
						{
							1,
							"#4DE1FF",
						},
					},
					Lifetime = 1,
					LightEmission = 1,
					LightInfluence = 0,
					RotSpeed = {
						120,
						160,
					},
					Rotation = {
						0,
						360,
					},
					Size = 5,
					Speed = 0,
					Texture = "rbxasset://textures/particles/forcefield_vortex_main.dds",
					Transparency = {
						{
							0,
							1,
						},
						{
							0.3,
							0.3,
						},
						{
							0.7,
							0.3,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 3.5,
				},
				emit = 1,
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#D8B8FF",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.5,
						},
						{
							0.8,
							0.5,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						-6,
						-3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				emit = 24,
				box = {
					5,
					5,
					5,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0.5,
				duration = 0,
				props = {
					Color = "#D8C8FF",
					Drag = 2,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.9,
						1.4,
					},
					LightInfluence = 1,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							1,
						},
						{
							1,
							3,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
					Transparency = {
						{
							0,
							0.45,
						},
						{
							0.7,
							0.67,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 2.0999999999999996,
				},
				emit = 6,
				minQuality = "medium",
				sprite = "smoke_puff",
			},
			{
				id = "p4",
				kind = "light",
				at = 0,
				duration = 0.8,
				props = {
					Brightness = 3,
					Color = "#A070FF",
					Range = 14,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 9,
	},
	{
		schema = "foundry.effect/1",
		id = "stealth_puff",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#6A5A86",
						},
						{
							1,
							"#A89CC0",
						},
					},
					Drag = 3,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.9,
						1.4,
					},
					LightEmission = 0.1,
					LightInfluence = 0.6,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							1,
						},
						{
							1,
							3.5,
						},
					},
					Speed = {
						2,
						5,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							0.45,
						},
						{
							0.7,
							0.67,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 2.4499999999999997,
				},
				emit = 10,
				sprite = "smoke_puff",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#B8A8D8",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.3,
						},
						{
							0.8,
							0.3,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				emit = 5,
				minQuality = "high",
				sprite = "sparkle_twinkle",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "slayer_skull_poof",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#C0484A",
						},
						{
							1,
							"#6A3048",
						},
					},
					Drag = 3,
					Lifetime = {
						0.9,
						1.4,
					},
					LightEmission = 0.15,
					LightInfluence = 0.6,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							1,
						},
						{
							1,
							3,
						},
					},
					Speed = {
						2,
						4,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							0.45,
						},
						{
							0.7,
							0.67,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 2.0999999999999996,
				},
				emit = 8,
				sprite = "cloud_soft",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FF7A5A",
						},
						{
							1,
							"#A01010",
						},
					},
					Drag = 2,
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0.25,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						5,
						9,
					},
					SpreadAngle = {
						180,
						180,
					},
					Texture = "rbxasset://textures/particles/fire_sparks_main.dds",
				},
				emit = 12,
				minQuality = "medium",
			},
			{
				id = "p3",
				kind = "light",
				at = 0,
				duration = 0.3,
				props = {
					Brightness = 2.5,
					Color = "#FF3A3A",
					Range = 10,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 6,
	},
	{
		schema = "foundry.effect/1",
		id = "map_unfurl_sparkle",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE08A",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Box",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.5,
						},
						{
							0.8,
							0.5,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						2,
						5,
					},
					SpreadAngle = {
						80,
						80,
					},
				},
				emit = 12,
				box = {
					3,
					0.2,
					2,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-10,
						0,
					},
					Color = "#E8D8A8",
					Drag = 1.5,
					Lifetime = {
						0.5,
						0.9,
					},
					LightInfluence = 1,
					RotSpeed = {
						-380,
						380,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.28600000000000003,
						},
						{
							1,
							0.17600000000000002,
						},
					},
					Speed = {
						3,
						6,
					},
					SpreadAngle = {
						55,
						55,
					},
				},
				emit = 6,
				minQuality = "medium",
				sprite = "chip",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "smelter_glow",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FFC46A",
						},
						{
							0.5,
							"#FF7A2A",
						},
						{
							1,
							"#B8320C",
						},
					},
					Lifetime = {
						0.6,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 6,
					Shape = "Disc",
					Size = {
						{
							0,
							1.2,
						},
						{
							1,
							0.3,
						},
					},
					Speed = {
						1,
						2,
					},
					SpreadAngle = {
						10,
						10,
					},
					Texture = "rbxasset://textures/particles/fire_main.dds",
					Transparency = {
						{
							0,
							0.2,
						},
						{
							0.7,
							0.5,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 0.84,
				},
				box = {
					1.2,
					0.2,
					1.2,
				},
			},
			{
				id = "p2",
				kind = "light",
				at = 0,
				duration = 0,
				props = {
					Brightness = 2,
					Color = "#FF7A2A",
					Flicker = {
						amount = 0.25,
						rate = 5,
					},
					Range = 12,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "bubbling_cauldron",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						1,
						0,
					},
					Color = {
						{
							0,
							"#C8FF7A",
						},
						{
							1,
							"#4AC04A",
						},
					},
					Lifetime = {
						0.8,
						1.2,
					},
					LightEmission = 0.6,
					LightInfluence = 0.3,
					Rate = 8,
					Shape = "Disc",
					Size = {
						{
							0,
							0.25,
						},
						{
							1,
							0.55,
						},
					},
					Speed = {
						1,
						2,
					},
					SpreadAngle = {
						15,
						15,
					},
					Transparency = {
						{
							0,
							0.2,
						},
						{
							0.8,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				box = {
					1.6,
					0.2,
					1.6,
				},
				sprite = "glow_soft",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E8FFE0",
					Lifetime = {
						1.5,
						2.2,
					},
					LightInfluence = 1,
					Rate = 2,
					RotSpeed = {
						-20,
						20,
					},
					Size = {
						{
							0,
							0.8,
						},
						{
							1,
							2.2,
						},
					},
					Speed = {
						1,
						2,
					},
					SpreadAngle = {
						10,
						10,
					},
					Transparency = {
						{
							0,
							0.6,
						},
						{
							0.7,
							0.76,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1.54,
				},
				minQuality = "medium",
				offset = {
					0,
					0.8,
					0,
				},
				sprite = "cloud_soft",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "rune_orbit",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#B08CFF",
						},
						{
							1,
							"#4DE1FF",
						},
					},
					Lifetime = {
						1.2,
						1.8,
					},
					LightEmission = 1,
					LightInfluence = 0,
					LockedToPart = true,
					Rate = 5,
					RotSpeed = {
						60,
						120,
					},
					Rotation = {
						0,
						360,
					},
					Shape = "Cylinder",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0.8,
						},
						{
							1,
							0,
						},
					},
					Speed = 0.4,
					Texture = "rbxasset://textures/particles/explosion01_implosion_main.dds",
					Transparency = {
						{
							0,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				offset = {
					0,
					1.5,
					0,
				},
				box = {
					3.5,
					0.2,
					3.5,
				},
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						1.5,
						0,
					},
					Color = "#D8B8FF",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						1,
						1.5,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 4,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.3,
						},
						{
							0.8,
							0.3,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				minQuality = "medium",
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "light",
				at = 0,
				duration = 0,
				props = {
					Brightness = 1.2,
					Color = "#9A7CFF",
					Flicker = {
						amount = 0.2,
						rate = 3,
					},
					Range = 8,
				},
				minQuality = "high",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "holy_motes",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						1.2,
						0,
					},
					Color = {
						{
							0,
							"#FFF6D0",
						},
						{
							1,
							"#FFD24A",
						},
					},
					Lifetime = {
						1.5,
						2.2,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 6,
					Shape = "Cylinder",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.45,
						},
						{
							0.8,
							0.45,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.5,
						1.5,
					},
					SpreadAngle = {
						10,
						10,
					},
				},
				box = {
					3,
					0.2,
					3,
				},
				sprite = "sparkle",
			},
			{
				id = "p2",
				kind = "light",
				at = 0,
				duration = 0,
				props = {
					Brightness = 1,
					Color = "#FFF0C0",
					Range = 8,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "stardust",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-0.5,
						0,
					},
					Color = {
						{
							0,
							"#FFFFFF",
						},
						{
							1,
							"#9EC8FF",
						},
					},
					EmissionDirection = "Bottom",
					Lifetime = {
						2,
						3,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 5,
					Shape = "Box",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.35,
						},
						{
							0.8,
							0.35,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.2,
						0.6,
					},
				},
				offset = {
					0,
					6,
					0,
				},
				box = {
					6,
					1,
					6,
				},
				sprite = "sparkle",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "ley_wisp",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.6,
						0,
					},
					Color = {
						{
							0,
							"#BFFBFF",
						},
						{
							1,
							"#3FC8FF",
						},
					},
					Lifetime = {
						3,
						4.5,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 2,
					RotSpeed = {
						-40,
						40,
					},
					Shape = "Sphere",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.6,
						},
						{
							0.8,
							0.6,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.5,
						1.2,
					},
					SpreadAngle = {
						180,
						180,
					},
				},
				box = {
					4,
					4,
					4,
				},
				sprite = "glow_soft",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#DFFFFF",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.6,
						1,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 4,
					Shape = "Sphere",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.25,
						},
						{
							0.8,
							0.25,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				minQuality = "medium",
				box = {
					4,
					4,
					4,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "light",
				at = 0,
				duration = 0,
				props = {
					Brightness = 1,
					Color = "#7AF0FF",
					Flicker = {
						amount = 0.3,
						rate = 1.5,
					},
					Range = 8,
				},
				minQuality = "high",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "steam_puff",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.3,
						0.8,
						0,
					},
					Color = "#FFFFFF",
					Lifetime = {
						1.5,
						2.5,
					},
					LightInfluence = 1,
					Rate = 3,
					RotSpeed = {
						-25,
						25,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.8,
						},
						{
							1,
							2.6,
						},
					},
					Speed = {
						1.5,
						2.5,
					},
					SpreadAngle = {
						12,
						12,
					},
					Transparency = {
						{
							0,
							0.55,
						},
						{
							0.6,
							0.75,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1.8199999999999998,
				},
				sprite = "cloud_soft",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "brew_foam",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF3D0",
					Lifetime = {
						0.8,
						1.2,
					},
					LightInfluence = 0.8,
					Rate = 6,
					Shape = "Disc",
					Size = {
						{
							0,
							0.2,
						},
						{
							1,
							0.4,
						},
					},
					Speed = {
						0.5,
						1.2,
					},
					SpreadAngle = {
						20,
						20,
					},
					Transparency = {
						{
							0,
							0.3,
						},
						{
							0.8,
							0.5,
						},
						{
							1,
							1,
						},
					},
				},
				box = {
					1.4,
					0.2,
					1.4,
				},
				sprite = "glow_soft",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E8C060",
					Lifetime = {
						1.5,
						2,
					},
					LightInfluence = 1,
					Rate = 1,
					Size = {
						{
							0,
							0.6,
						},
						{
							1,
							1.8,
						},
					},
					Speed = {
						0.8,
						1.5,
					},
					Transparency = {
						{
							0,
							0.75,
						},
						{
							0.7,
							0.85,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1.26,
				},
				minQuality = "high",
				sprite = "cloud_soft",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "kiln_embers",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.4,
						2,
						0,
					},
					Color = "#FFB04A",
					Lifetime = {
						1,
						1.8,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 6,
					Size = {
						{
							0,
							0.15,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						2,
						5,
					},
					SpreadAngle = {
						25,
						25,
					},
					Texture = "rbxasset://textures/particles/fire_sparks_main.dds",
				},
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.6,
						0.5,
						0,
					},
					Color = "#4A4A4A",
					Lifetime = {
						2.5,
						3.5,
					},
					LightInfluence = 1,
					Rate = 2,
					Size = {
						{
							0,
							1,
						},
						{
							1,
							3,
						},
					},
					Speed = {
						1.5,
						2.5,
					},
					Transparency = {
						{
							0,
							0.6,
						},
						{
							0.7,
							0.76,
						},
						{
							1,
							1,
						},
					},
				},
				minQuality = "medium",
				offset = {
					0,
					2,
					0,
				},
				sprite = "cloud_soft",
			},
			{
				id = "p3",
				kind = "light",
				at = 0,
				duration = 0,
				props = {
					Brightness = 1.5,
					Color = "#FF7A2A",
					Flicker = {
						amount = 0.3,
						rate = 6,
					},
					Range = 10,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "water_sprinkle",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-30,
						0,
					},
					Color = "#CFEFFF",
					Lifetime = {
						0.5,
						0.7,
					},
					LightInfluence = 0.8,
					Rate = 20,
					Size = {
						{
							0,
							0.14,
						},
						{
							1,
							0.08,
						},
					},
					Speed = {
						5,
						7,
					},
					SpreadAngle = {
						20,
						20,
					},
					Texture = "rbxasset://textures/particles/SquareParticle.png",
					Transparency = {
						{
							0,
							0.2,
						},
						{
							1,
							0.7,
						},
					},
				},
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "pollen",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.3,
						0.1,
						0,
					},
					Color = "#FFF2A0",
					Lifetime = {
						5,
						8,
					},
					LightEmission = 0.6,
					LightInfluence = 0.4,
					Rate = 10,
					Shape = "Box",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.18,
						},
						{
							0.8,
							0.18,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.2,
						0.6,
					},
					SpreadAngle = {
						180,
						180,
					},
				},
				box = {
					100,
					12,
					100,
				},
				sprite = "sparkle",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "autumn_leaves",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						1.2,
						-1,
						0.3,
					},
					Color = {
						{
							0,
							"#E08A2A",
						},
						{
							0.5,
							"#C8502A",
						},
						{
							1,
							"#A8782A",
						},
					},
					EmissionDirection = "Bottom",
					Lifetime = {
						6,
						9,
					},
					LightInfluence = 1,
					Rate = 12,
					RotSpeed = {
						-180,
						180,
					},
					Rotation = {
						0,
						360,
					},
					Shape = "Box",
					Size = 0.65,
					Speed = {
						1,
						2,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.9,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				box = {
					110,
					1,
					110,
				},
				sprite = "leaf",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 6,
	},
	{
		schema = "foundry.effect/1",
		id = "snowfall_light",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.5,
						0,
						0,
					},
					Color = "#FFFFFF",
					EmissionDirection = "Bottom",
					Lifetime = {
						7,
						9,
					},
					LightInfluence = 1,
					Rate = 25,
					RotSpeed = {
						-60,
						60,
					},
					Shape = "Box",
					Size = 0.2,
					Speed = {
						1.5,
						2.5,
					},
					SpreadAngle = {
						10,
						10,
					},
					Transparency = {
						{
							0,
							0.15,
						},
						{
							0.85,
							0.25,
						},
						{
							1,
							1,
						},
					},
				},
				box = {
					120,
					1,
					120,
				},
				sprite = "cloud_soft",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 5,
	},
	{
		schema = "foundry.effect/1",
		id = "quest_depart_confetti",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-16,
						0,
					},
					Color = "#FF4D6D",
					Drag = 1.6,
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.35,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.45,
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 18,
				sprite = "confetti_tumble",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0.05,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-16,
						0,
					},
					Color = "#FFD23F",
					Drag = 1.6,
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.35,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.45,
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 18,
				sprite = "confetti_tumble",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0.1,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-16,
						0,
					},
					Color = "#3FC8B0",
					Drag = 1.6,
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.35,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.45,
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 18,
				sprite = "confetti_tumble",
			},
			{
				id = "p4",
				kind = "emitter",
				at = 0.15,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-16,
						0,
					},
					Color = "#FFFFFF",
					Drag = 1.6,
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.35,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.45,
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 12,
				minQuality = "medium",
				sprite = "confetti_tumble",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 8,
	},
	{
		schema = "foundry.effect/1",
		id = "homecoming_fanfare",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-9,
						0,
					},
					Color = {
						{
							0,
							"#FFFFFF",
						},
						{
							0.25,
							"#FFD24A",
						},
						{
							1,
							"#FF9A1F",
						},
					},
					Drag = 2.2,
					Lifetime = {
						1.1,
						1.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							1.1,
						},
						{
							1,
							0.2,
						},
					},
					Speed = {
						16,
						24,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.75,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 45,
				offset = {
					0,
					12,
					0,
				},
				sprite = "sparkle",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFD76A",
					Lifetime = 0.5,
					LightEmission = 0.6,
					LightInfluence = 0.4,
					Size = {
						{
							0,
							0.4,
						},
						{
							1,
							12,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.25,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 7,
				},
				emit = 1,
				minQuality = "medium",
				sprite = "shockwave_ring",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0.2,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-16,
						0,
					},
					Color = "#FFD23F",
					Drag = 1.6,
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.35,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.45,
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 16,
				sprite = "confetti_tumble",
			},
			{
				id = "p4",
				kind = "emitter",
				at = 0.25,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-16,
						0,
					},
					Color = "#FF4D6D",
					Drag = 1.6,
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.35,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.45,
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 16,
				minQuality = "medium",
				sprite = "confetti_tumble",
			},
			{
				id = "p5",
				kind = "light",
				at = 0,
				duration = 0.5,
				props = {
					Brightness = 4,
					Color = "#FFCF8A",
					Range = 30,
				},
				offset = {
					0,
					12,
					0,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 14,
		lifetime = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "recruit_sparkle",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						4,
						0,
					},
					Color = {
						{
							0,
							"#FFF6C8",
						},
						{
							1,
							"#FFD24A",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						1,
						1.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Cylinder",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.55,
						},
						{
							0.8,
							0.55,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						2,
						5,
					},
					SpreadAngle = {
						15,
						15,
					},
				},
				emit = 24,
				box = {
					2.5,
					0.2,
					2.5,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE7A0",
					Lifetime = 0.5,
					LightEmission = 0.6,
					LightInfluence = 0.4,
					Size = {
						{
							0,
							0.4,
						},
						{
							1,
							6,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.25,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 4.199999999999999,
				},
				emit = 1,
				minQuality = "medium",
				sprite = "shockwave_ring",
			},
			{
				id = "p3",
				kind = "light",
				at = 0,
				duration = 0.5,
				props = {
					Brightness = 2.5,
					Color = "#FFE7A0",
					Range = 10,
				},
				minQuality = "medium",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 6,
	},
	{
		schema = "foundry.effect/1",
		id = "land_reveal_puff",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#F4F1EA",
					Drag = 2.5,
					Lifetime = {
						1.2,
						1.8,
					},
					LightEmission = 0.1,
					LightInfluence = 0.7,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						0,
						360,
					},
					Shape = "Box",
					Size = {
						{
							0,
							3,
						},
						{
							1,
							8,
						},
					},
					Speed = {
						2,
						6,
					},
					SpreadAngle = {
						60,
						60,
					},
					Transparency = {
						{
							0,
							0.2,
						},
						{
							0.6,
							0.6,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 5.6,
				},
				emit = 16,
				box = {
					8,
					1,
					8,
				},
				sprite = "cloud_soft",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF6C8",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Box",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.6,
						},
						{
							0.8,
							0.6,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				emit = 10,
				minQuality = "medium",
				box = {
					8,
					1,
					8,
				},
				sprite = "sparkle_twinkle",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 10,
	},
	{
		schema = "foundry.effect/1",
		id = "road_paint_dust",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#CDB58E",
					Drag = 2,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.9,
						1.4,
					},
					LightInfluence = 1,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						0,
						360,
					},
					Shape = "Box",
					Size = {
						{
							0,
							0.8,
						},
						{
							1,
							2,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
					Transparency = {
						{
							0,
							0.45,
						},
						{
							0.7,
							0.67,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1.4,
				},
				emit = 5,
				box = {
					3,
					0.3,
					3,
				},
				sprite = "smoke_puff",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-42,
						0,
					},
					Color = "#8A7458",
					Lifetime = {
						0.5,
						0.9,
					},
					LightInfluence = 1,
					RotSpeed = {
						-380,
						380,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.20800000000000002,
						},
						{
							1,
							0.128,
						},
					},
					Speed = {
						3,
						6,
					},
					SpreadAngle = {
						55,
						55,
					},
				},
				emit = 5,
				minQuality = "medium",
				sprite = "chip",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "homecoming_fireworks",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-9,
						0,
					},
					Color = {
						{
							0,
							"#FFFFFF",
						},
						{
							0.25,
							"#FFD24A",
						},
						{
							1,
							"#FFB347",
						},
					},
					Drag = 2.2,
					Lifetime = {
						1.2,
						1.7,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							1.1,
						},
						{
							1,
							0.2,
						},
					},
					Speed = {
						18,
						26,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.75,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 40,
				offset = {
					0,
					16,
					0,
				},
				sprite = "sparkle",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0.45,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-9,
						0,
					},
					Color = {
						{
							0,
							"#FFFFFF",
						},
						{
							0.25,
							"#FFE9A8",
						},
						{
							1,
							"#E7B75A",
						},
					},
					Drag = 2.2,
					Lifetime = {
						1.1,
						1.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							1,
						},
						{
							1,
							0.2,
						},
					},
					Speed = {
						16,
						24,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.75,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 36,
				minQuality = "medium",
				offset = {
					4,
					20,
					2,
				},
				sprite = "sparkle",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0.9,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-9,
						0,
					},
					Color = {
						{
							0,
							"#FFFFFF",
						},
						{
							0.3,
							"#FFC86B",
						},
						{
							1,
							"#FF9A1F",
						},
					},
					Drag = 2.2,
					Lifetime = {
						1,
						1.5,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0.9,
						},
						{
							1,
							0.15,
						},
					},
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.75,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 30,
				minQuality = "high",
				offset = {
					-4,
					18,
					-2,
				},
				sprite = "sparkle",
			},
			{
				id = "p4",
				kind = "light",
				at = 0,
				duration = 0.5,
				props = {
					Brightness = 4,
					Color = "#FFCF8A",
					Range = 30,
				},
				minQuality = "medium",
				offset = {
					0,
					17,
					0,
				},
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 10,
		lifetime = 3.4,
	},
	{
		schema = "foundry.effect/1",
		id = "moment.party_home",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-9,
						0,
					},
					Color = {
						{
							0,
							"#FFFFFF",
						},
						{
							0.3,
							"#FFE08A",
						},
						{
							1,
							"#FFB347",
						},
					},
					Drag = 2.4,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						1.1,
						1.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							1.3,
						},
						{
							1,
							0.35,
						},
					},
					Speed = {
						15,
						22,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.7,
							0.25,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 34,
				offset = {
					0,
					13,
					0,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0.05,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-16,
						0,
					},
					Color = "#FFD23F",
					Drag = 1.6,
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.35,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.45,
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 18,
				sprite = "confetti_tumble",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0.12,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-16,
						0,
					},
					Color = "#E8577A",
					Drag = 1.6,
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.35,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.45,
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 16,
				minQuality = "medium",
				sprite = "confetti_tumble",
			},
			{
				id = "p4",
				kind = "emitter",
				at = 0.18,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-16,
						0,
					},
					Color = "#4FB8A8",
					Drag = 1.6,
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.35,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.45,
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 14,
				minQuality = "medium",
				sprite = "confetti_tumble",
			},
			{
				id = "p5",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE7A0",
					Lifetime = 0.9,
					LightEmission = 0.8,
					LightInfluence = 0.2,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							1.6,
						},
						{
							0.3,
							11.2,
						},
						{
							1,
							16,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							0.05,
						},
						{
							0.45,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "medium",
				offset = {
					0,
					0.25,
					0,
				},
				sprite = "shockwave_ring",
			},
			{
				id = "p6",
				kind = "light",
				at = 0,
				duration = 0.6,
				props = {
					Brightness = 4,
					Color = "#FFCF8A",
					Range = 32,
				},
				offset = {
					0,
					13,
					0,
				},
				minQuality = "medium",
			},
			{
				id = "p7",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF1C8",
					Lifetime = 0.7,
					LightEmission = 1,
					LightInfluence = 0,
					RotSpeed = {
						-20,
						20,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							4.8,
						},
						{
							0.25,
							16,
						},
						{
							1,
							19.2,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.1,
						},
						{
							0.5,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					13,
					0,
				},
				sprite = "light_rays",
			},
			{
				id = "p8",
				kind = "emitter",
				at = 0.45,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-9,
						0,
					},
					Color = {
						{
							0,
							"#FFFFFF",
						},
						{
							0.3,
							"#FFD0E0",
						},
						{
							1,
							"#E8577A",
						},
					},
					Drag = 2.4,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						1.1,
						1.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							1.3,
						},
						{
							1,
							0.35,
						},
					},
					Speed = {
						15,
						22,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.7,
							0.25,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 24,
				minQuality = "high",
				offset = {
					0,
					17,
					0,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p9",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-34,
						0,
					},
					Color = "#FFFFFF",
					Drag = 0.6,
					FlipbookFramerate = {
						14,
						22,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						1.2,
						1.7,
					},
					LightEmission = 0.15,
					LightInfluence = 0.6,
					Size = 0.9,
					Speed = {
						10.4,
						16,
					},
					SpreadAngle = {
						28,
						28,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 10,
				minQuality = "high",
				offset = {
					0,
					1,
					0,
				},
				sprite = "coin_spin",
			},
			{
				id = "cue",
				kind = "sound",
				at = 0,
				duration = 0,
				props = {
					Cue = "event.party_home",
				},
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 30,
		lifetime = 3.2,
	},
	{
		schema = "foundry.effect/1",
		id = "moment.level_up",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFD98A",
					Lifetime = 1.8,
					LightEmission = 1,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					RotSpeed = {
						40,
						55,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							3.8500000000000005,
						},
						{
							0.2,
							7,
						},
						{
							1,
							7.5600000000000005,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0.1,
						},
						{
							0.7,
							0.25,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				offset = {
					0,
					0.3,
					0,
				},
				sprite = "rune_ring",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						5,
						0,
					},
					Color = {
						{
							0,
							"#FFF6DE",
						},
						{
							1,
							"#FFD27A",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						1,
						1.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Cylinder",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.55,
						},
						{
							0.8,
							0.55,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						2,
						5,
					},
					SpreadAngle = {
						12,
						12,
					},
				},
				emit = 18,
				box = {
					2.6,
					0.2,
					2.6,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE3A0",
					Lifetime = 1.4,
					LightEmission = 1,
					LightInfluence = 0,
					Orientation = "FacingCameraWorldUp",
					Size = {
						{
							0,
							1.7999999999999998,
						},
						{
							0.15,
							3,
						},
						{
							1,
							2.4000000000000004,
						},
					},
					Speed = 0,
					Squash = 2.6,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.12,
							0.2,
						},
						{
							0.6,
							0.45,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "medium",
				offset = {
					0,
					4.5,
					0,
				},
				sprite = "glow_soft",
			},
			{
				id = "p4",
				kind = "light",
				at = 0,
				duration = 0.8,
				props = {
					Brightness = 2.5,
					Color = "#FFE0A0",
					Range = 12,
				},
				offset = {
					0,
					2,
					0,
				},
				minQuality = "medium",
			},
			{
				id = "p5",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-6,
						0,
					},
					Color = "#FFE9A8",
					Drag = 3,
					Lifetime = {
						1.1,
						1.6,
					},
					LightEmission = 0.5,
					LightInfluence = 0.2,
					RotSpeed = {
						-60,
						60,
					},
					Rotation = {
						-25,
						25,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.12,
							0.96,
						},
						{
							0.3,
							0.8,
						},
						{
							1,
							0.5599999999999999,
						},
					},
					Speed = {
						5.3999999999999995,
						9,
					},
					SpreadAngle = {
						60,
						60,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.75,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 6,
				minQuality = "high",
				offset = {
					0,
					2.5,
					0,
				},
				sprite = "star",
			},
			{
				id = "p6",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF3D0",
					Lifetime = 0.6,
					LightEmission = 1,
					LightInfluence = 0,
					RotSpeed = {
						-20,
						20,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							1.7999999999999998,
						},
						{
							0.25,
							6,
						},
						{
							1,
							7.199999999999999,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.1,
						},
						{
							0.5,
							0.4,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 5.039999999999999,
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					2.5,
					0,
				},
				sprite = "light_rays",
			},
			{
				id = "cue",
				kind = "sound",
				at = 0,
				duration = 0,
				props = {
					Cue = "event.levelup",
				},
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 18,
		lifetime = 2.2,
	},
	{
		schema = "foundry.effect/1",
		id = "moment.build_done",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#EADBBB",
						},
						{
							1,
							"#CDB892",
						},
					},
					Drag = 2.6,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						1.2,
						1.8,
					},
					LightInfluence = 1,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						0,
						360,
					},
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							2,
						},
						{
							1,
							6,
						},
					},
					Speed = {
						5,
						9,
					},
					SpreadAngle = {
						10,
						10,
					},
					Transparency = {
						{
							0,
							0.45,
						},
						{
							0.7,
							0.67,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 5,
				},
				emit = 16,
				offset = {
					0,
					1.2,
					0,
				},
				box = {
					9,
					0.6,
					9,
				},
				sprite = "smoke_puff",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0.1,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-16,
						0,
					},
					Color = "#FFD23F",
					Drag = 1.6,
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.35,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.45,
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 18,
				sprite = "confetti_tumble",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0.15,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-16,
						0,
					},
					Color = "#E8577A",
					Drag = 1.6,
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.35,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.45,
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 14,
				minQuality = "medium",
				sprite = "confetti_tumble",
			},
			{
				id = "p4",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#F1E4C6",
					Lifetime = 0.8,
					LightEmission = 0.8,
					LightInfluence = 0.2,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							1.8,
						},
						{
							0.3,
							12.6,
						},
						{
							1,
							18,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							0.05,
						},
						{
							0.45,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "medium",
				offset = {
					0,
					0.25,
					0,
				},
				sprite = "shockwave_ring",
			},
			{
				id = "p5",
				kind = "emitter",
				at = 0.35,
				duration = 0,
				props = {
					Acceleration = {
						0.6,
						-5,
						0,
					},
					Color = {
						{
							0,
							"#FFE7A3",
						},
						{
							1,
							"#F2B35A",
						},
					},
					Drag = 0.8,
					EmissionDirection = "Bottom",
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2.2,
						2.8,
					},
					LightEmission = 0.35,
					LightInfluence = 0.2,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Shape = "Box",
					Size = 0.6,
					Speed = {
						0.5,
						2,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 18,
				minQuality = "medium",
				offset = {
					0,
					14,
					0,
				},
				box = {
					9,
					1,
					9,
				},
				sprite = "confetti_tumble",
			},
			{
				id = "p6",
				kind = "light",
				at = 0,
				duration = 0.6,
				props = {
					Brightness = 3,
					Color = "#FFE7B0",
					Range = 20,
				},
				offset = {
					0,
					6,
					0,
				},
				minQuality = "medium",
			},
			{
				id = "p7",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FFF6DE",
						},
						{
							1,
							"#FFD27A",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Box",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.8,
						},
						{
							0.8,
							0.8,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				emit = 16,
				minQuality = "high",
				offset = {
					0,
					5,
					0,
				},
				box = {
					9,
					9,
					9,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p8",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF1C8",
					Lifetime = 0.7,
					LightEmission = 1,
					LightInfluence = 0,
					RotSpeed = {
						-20,
						20,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							3.5999999999999996,
						},
						{
							0.25,
							12,
						},
						{
							1,
							14.399999999999999,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.1,
						},
						{
							0.5,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					10,
					0,
				},
				sprite = "light_rays",
			},
			{
				id = "cue",
				kind = "sound",
				at = 0,
				duration = 0,
				props = {
					Cue = "event.construction_done",
				},
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 32,
		lifetime = 3.2,
	},
	{
		schema = "foundry.effect/1",
		id = "moment.upgrade",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFD98A",
					Lifetime = 2.2,
					LightEmission = 1,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					RotSpeed = {
						40,
						55,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							7.15,
						},
						{
							0.2,
							13,
						},
						{
							1,
							14.040000000000001,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0.1,
						},
						{
							0.7,
							0.25,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				offset = {
					0,
					0.3,
					0,
				},
				sprite = "rune_ring",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						4,
						0,
					},
					Color = {
						{
							0,
							"#FFF6DE",
						},
						{
							1,
							"#FFD27A",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						1.2,
						1.8,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Cylinder",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.7,
						},
						{
							0.8,
							0.7,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						3,
						7,
					},
					SpreadAngle = {
						10,
						10,
					},
				},
				emit = 22,
				box = {
					9,
					0.2,
					9,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FFF3D0",
						},
						{
							1,
							"#FFC86B",
						},
					},
					FlipbookFramerate = 14,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					Lifetime = 1.6,
					LightEmission = 1,
					LightInfluence = 0,
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							4,
						},
						{
							0.3,
							11,
						},
						{
							1,
							13,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.25,
						},
						{
							0.75,
							0.4,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 7,
				},
				emit = 1,
				minQuality = "medium",
				offset = {
					0,
					6,
					0,
				},
				sprite = "magic_swirl",
			},
			{
				id = "p4",
				kind = "light",
				at = 0,
				duration = 0.9,
				props = {
					Brightness = 3,
					Color = "#FFD98A",
					Range = 18,
				},
				offset = {
					0,
					5,
					0,
				},
				minQuality = "medium",
			},
			{
				id = "p5",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-6,
						0,
					},
					Color = "#FFE9A8",
					Drag = 3,
					Lifetime = {
						1.1,
						1.6,
					},
					LightEmission = 0.5,
					LightInfluence = 0.2,
					RotSpeed = {
						-60,
						60,
					},
					Rotation = {
						-25,
						25,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.12,
							1.2,
						},
						{
							0.3,
							1,
						},
						{
							1,
							0.7,
						},
					},
					Speed = {
						7.199999999999999,
						12,
					},
					SpreadAngle = {
						60,
						60,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.75,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 8,
				minQuality = "high",
				offset = {
					0,
					8,
					0,
				},
				sprite = "star",
			},
			{
				id = "p6",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE3A0",
					Lifetime = 1.6,
					LightEmission = 1,
					LightInfluence = 0,
					Orientation = "FacingCameraWorldUp",
					Size = {
						{
							0,
							3,
						},
						{
							0.15,
							5,
						},
						{
							1,
							4,
						},
					},
					Speed = 0,
					Squash = 2.6,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.12,
							0.2,
						},
						{
							0.6,
							0.45,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					8,
					0,
				},
				sprite = "glow_soft",
			},
			{
				id = "cue",
				kind = "sound",
				at = 0,
				duration = 0,
				props = {
					Cue = "event.construction_done",
				},
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 26,
		lifetime = 2.6,
	},
	{
		schema = "foundry.effect/1",
		id = "moment.charter",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE3A0",
					Lifetime = 3.5,
					LightEmission = 1,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					RotSpeed = {
						40,
						55,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							24.200000000000003,
						},
						{
							0.2,
							44,
						},
						{
							1,
							47.52,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0.1,
						},
						{
							0.7,
							0.25,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				offset = {
					0,
					0.3,
					0,
				},
				sprite = "rune_ring",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						3,
						0,
					},
					Color = {
						{
							0,
							"#FFF6DE",
						},
						{
							1,
							"#FFD27A",
						},
					},
					Lifetime = {
						2.5,
						3.5,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Box",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.45,
						},
						{
							0.8,
							0.45,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.5,
						1.5,
					},
					SpreadAngle = {
						25,
						25,
					},
				},
				emit = 50,
				box = {
					70,
					2,
					70,
				},
				sprite = "dust_mote",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF1C8",
					Lifetime = 1.6,
					LightEmission = 0.8,
					LightInfluence = 0.2,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							9,
						},
						{
							0.3,
							62.99999999999999,
						},
						{
							1,
							90,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							0.05,
						},
						{
							0.45,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "medium",
				offset = {
					0,
					0.25,
					0,
				},
				sprite = "shockwave_ring",
			},
			{
				id = "p4",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE9B8",
					Lifetime = 3,
					LightEmission = 1,
					LightInfluence = 0,
					Orientation = "FacingCameraWorldUp",
					Size = {
						{
							0,
							7.199999999999999,
						},
						{
							0.15,
							12,
						},
						{
							1,
							9.600000000000001,
						},
					},
					Speed = 0,
					Squash = 2.6,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.12,
							0.2,
						},
						{
							0.6,
							0.45,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "medium",
				offset = {
					0,
					20,
					0,
				},
				sprite = "glow_soft",
			},
			{
				id = "p5",
				kind = "light",
				at = 0,
				duration = 1.6,
				props = {
					Brightness = 6,
					Color = "#FFE0A0",
					Range = 60,
				},
				offset = {
					0,
					10,
					0,
				},
				minQuality = "medium",
			},
			{
				id = "p6",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF6DE",
					Lifetime = 1.4,
					LightEmission = 1,
					LightInfluence = 0,
					RotSpeed = {
						-20,
						20,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							12,
						},
						{
							0.25,
							40,
						},
						{
							1,
							48,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.1,
						},
						{
							0.5,
							0.4,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 7,
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					16,
					0,
				},
				sprite = "light_rays",
			},
			{
				id = "p7",
				kind = "emitter",
				at = 0.6,
				duration = 0,
				props = {
					Acceleration = {
						2.5,
						-1.2,
						1,
					},
					Color = {
						{
							0,
							"#FFE4EC",
						},
						{
							1,
							"#F4B6C8",
						},
					},
					Drag = 0.5,
					Lifetime = {
						3,
						4,
					},
					LightInfluence = 0.8,
					RotSpeed = {
						-160,
						160,
					},
					Rotation = {
						0,
						360,
					},
					Shape = "Box",
					Size = 0.9,
					Speed = {
						2,
						5,
					},
					SpreadAngle = {
						60,
						60,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.1,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 40,
				minQuality = "high",
				offset = {
					0,
					6,
					0,
				},
				box = {
					60,
					4,
					60,
				},
				sprite = "petal",
			},
			{
				id = "p8",
				kind = "emitter",
				at = 0.4,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FFF6DE",
						},
						{
							1,
							"#FFD27A",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Box",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							1.2,
						},
						{
							0.8,
							1.2,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				emit = 30,
				minQuality = "high",
				offset = {
					0,
					4,
					0,
				},
				box = {
					60,
					8,
					60,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "cue",
				kind = "sound",
				at = 0,
				duration = 0,
				props = {
					Cue = "event.rankup",
				},
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 60,
		lifetime = 4.5,
	},
	{
		schema = "foundry.effect/1",
		id = "moment.purchase",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-34,
						0,
					},
					Color = "#FFFFFF",
					Drag = 0.6,
					FlipbookFramerate = {
						14,
						22,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						1.2,
						1.7,
					},
					LightEmission = 0.15,
					LightInfluence = 0.6,
					Size = 0.9,
					Speed = {
						9.75,
						15,
					},
					SpreadAngle = {
						28,
						28,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 12,
				offset = {
					0,
					0.5,
					0,
				},
				sprite = "coin_spin",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FFF6DE",
						},
						{
							1,
							"#FFD27A",
						},
					},
					Drag = 2,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.6,
						},
						{
							0.8,
							0.6,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						3,
						7,
					},
					SpreadAngle = {
						180,
						180,
					},
				},
				emit = 14,
				offset = {
					0,
					2,
					0,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE9B8",
					Lifetime = 0.5,
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							1,
						},
						{
							0.2,
							7,
						},
						{
							1,
							9,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 6.3,
				},
				emit = 1,
				minQuality = "medium",
				offset = {
					0,
					2,
					0,
				},
				sprite = "glow_core",
			},
			{
				id = "p4",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFD98A",
					Lifetime = 0.7,
					LightEmission = 0.8,
					LightInfluence = 0.2,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							1,
						},
						{
							0.3,
							7,
						},
						{
							1,
							10,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							0.05,
						},
						{
							0.45,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "medium",
				offset = {
					0,
					0.25,
					0,
				},
				sprite = "shockwave_ring",
			},
			{
				id = "p5",
				kind = "light",
				at = 0,
				duration = 0.5,
				props = {
					Brightness = 3,
					Color = "#FFD98A",
					Range = 16,
				},
				offset = {
					0,
					2,
					0,
				},
				minQuality = "medium",
			},
			{
				id = "p6",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-6,
						0,
					},
					Color = "#FFE9A8",
					Drag = 3,
					Lifetime = {
						1.1,
						1.6,
					},
					LightEmission = 0.5,
					LightInfluence = 0.2,
					RotSpeed = {
						-60,
						60,
					},
					Rotation = {
						-25,
						25,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.12,
							0.96,
						},
						{
							0.3,
							0.8,
						},
						{
							1,
							0.5599999999999999,
						},
					},
					Speed = {
						6,
						10,
					},
					SpreadAngle = {
						60,
						60,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.75,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 6,
				minQuality = "high",
				offset = {
					0,
					2,
					0,
				},
				sprite = "star",
			},
			{
				id = "p7",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF3D0",
					Lifetime = 0.5,
					LightEmission = 1,
					LightInfluence = 0,
					RotSpeed = {
						-20,
						20,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							2.4,
						},
						{
							0.25,
							8,
						},
						{
							1,
							9.6,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.1,
						},
						{
							0.5,
							0.4,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 6.72,
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					2,
					0,
				},
				sprite = "light_rays",
			},
			{
				id = "cue",
				kind = "sound",
				at = 0,
				duration = 0,
				props = {
					Cue = "ui.toast.success",
				},
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 20,
		lifetime = 2.2,
	},
	{
		schema = "foundry.effect/1",
		id = "moment.achievement",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-6,
						0,
					},
					Color = {
						{
							0,
							"#FFFFFF",
						},
						{
							1,
							"#FFD27A",
						},
					},
					Drag = 3,
					Lifetime = {
						1.1,
						1.6,
					},
					LightEmission = 0.5,
					LightInfluence = 0.2,
					RotSpeed = {
						-60,
						60,
					},
					Rotation = {
						-25,
						25,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.12,
							1.32,
						},
						{
							0.3,
							1.1,
						},
						{
							1,
							0.77,
						},
					},
					Speed = {
						8.4,
						14,
					},
					SpreadAngle = {
						60,
						60,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.75,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 12,
				offset = {
					0,
					3,
					0,
				},
				sprite = "star",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FFF6DE",
						},
						{
							1,
							"#FFD27A",
						},
					},
					Drag = 2.5,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.6,
						},
						{
							0.8,
							0.6,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						4,
						9,
					},
					SpreadAngle = {
						180,
						180,
					},
				},
				emit = 12,
				offset = {
					0,
					3,
					0,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0.1,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-16,
						0,
					},
					Color = "#FFD23F",
					Drag = 1.6,
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.35,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.45,
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 16,
				minQuality = "medium",
				sprite = "confetti_tumble",
			},
			{
				id = "p4",
				kind = "emitter",
				at = 0.15,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-16,
						0,
					},
					Color = "#7D4A7A",
					Drag = 1.6,
					FlipbookFramerate = {
						10,
						18,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.35,
					RotSpeed = {
						-480,
						480,
					},
					Rotation = {
						0,
						360,
					},
					Size = 0.45,
					Speed = {
						14,
						22,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 14,
				minQuality = "medium",
				sprite = "confetti_tumble",
			},
			{
				id = "p5",
				kind = "light",
				at = 0,
				duration = 0.6,
				props = {
					Brightness = 3,
					Color = "#FFE0A0",
					Range = 18,
				},
				offset = {
					0,
					3,
					0,
				},
				minQuality = "medium",
			},
			{
				id = "p6",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF3D0",
					Lifetime = 0.7,
					LightEmission = 1,
					LightInfluence = 0,
					RotSpeed = {
						-20,
						20,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							3.5999999999999996,
						},
						{
							0.25,
							12,
						},
						{
							1,
							14.399999999999999,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.1,
						},
						{
							0.5,
							0.4,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 7,
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					3,
					0,
				},
				sprite = "light_rays",
			},
			{
				id = "p7",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE7A0",
					Lifetime = 0.8,
					LightEmission = 0.8,
					LightInfluence = 0.2,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							1.2000000000000002,
						},
						{
							0.3,
							8.399999999999999,
						},
						{
							1,
							12,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							0.05,
						},
						{
							0.45,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					0.25,
					0,
				},
				sprite = "shockwave_ring",
			},
			{
				id = "cue",
				kind = "sound",
				at = 0,
				duration = 0,
				props = {
					Cue = "event.rankup",
				},
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 24,
		lifetime = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "ambient.chimney_smoke",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.5,
						0.3,
						0.15,
					},
					Color = {
						{
							0,
							"#F4EFE6",
						},
						{
							1,
							"#C9C6CF",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						4,
						6,
					},
					LightInfluence = 1,
					Rate = 1.4,
					RotSpeed = {
						-12,
						12,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							1.2,
						},
						{
							1,
							5,
						},
					},
					Speed = {
						1.6,
						2.4,
					},
					SpreadAngle = {
						8,
						8,
					},
					Transparency = {
						{
							0,
							0.35,
						},
						{
							0.6,
							0.6,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 3.5,
				},
				sprite = "smoke_puff",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.6,
						0.2,
						0.1,
					},
					Color = "#E8E4EA",
					Lifetime = {
						3,
						4.5,
					},
					LightInfluence = 1,
					Rate = 0.9,
					RotSpeed = {
						-20,
						20,
					},
					Size = {
						{
							0,
							0.6,
						},
						{
							1,
							2.6,
						},
					},
					Speed = {
						2,
						3,
					},
					SpreadAngle = {
						5,
						5,
					},
					Transparency = {
						{
							0,
							0.65,
						},
						{
							0.6,
							0.8,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1.8199999999999998,
				},
				minQuality = "medium",
				sprite = "cloud_soft",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.4,
						0.5,
						0,
					},
					Color = {
						{
							0,
							"#FFD27A",
						},
						{
							1,
							"#FF7A2A",
						},
					},
					Lifetime = {
						1,
						1.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 0.6,
					Size = {
						{
							0,
							0.22,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						2,
						4,
					},
					SpreadAngle = {
						15,
						15,
					},
				},
				minQuality = "high",
				sprite = "ember",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "ambient.forge_sparks",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-14,
						0,
					},
					Color = {
						{
							0,
							"#FFF0B0",
						},
						{
							0.4,
							"#FFB04A",
						},
						{
							1,
							"#FF5A1A",
						},
					},
					Drag = 0.8,
					Lifetime = {
						0.5,
						1.1,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 9,
					Size = {
						{
							0,
							0.32,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						5,
						10,
					},
					SpreadAngle = {
						30,
						30,
					},
				},
				sprite = "ember",
			},
			{
				id = "p2",
				kind = "light",
				at = 0,
				duration = 0,
				props = {
					Brightness = 2,
					Color = "#FF8A3A",
					Flicker = {
						amount = 0.35,
						rate = 8,
					},
					Range = 12,
				},
				minQuality = "medium",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.4,
						0.4,
						0,
					},
					Color = "#5A5250",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						2.2,
						3,
					},
					LightInfluence = 1,
					Rate = 1,
					Size = {
						{
							0,
							1,
						},
						{
							1,
							3.2,
						},
					},
					Speed = {
						1.5,
						2.5,
					},
					Transparency = {
						{
							0,
							0.6,
						},
						{
							0.6,
							0.75,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 2.2399999999999998,
				},
				minQuality = "high",
				offset = {
					0,
					1.5,
					0,
				},
				sprite = "smoke_puff",
			},
			{
				id = "cue",
				kind = "sound",
				at = 0,
				duration = 0,
				props = {
					Cue = "loop.forge",
				},
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 4,
	},
	{
		schema = "foundry.effect/1",
		id = "ambient.lantern_glow",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFC86B",
					Lifetime = 2.5,
					LightEmission = 1,
					LightInfluence = 0,
					LockedToPart = true,
					Rate = 0.8,
					Size = {
						{
							0,
							2.6,
						},
						{
							0.5,
							2.9,
						},
						{
							1,
							2.6,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.45,
						},
						{
							0.8,
							0.45,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 2.03,
				},
				sprite = "glow_soft",
			},
			{
				id = "p2",
				kind = "light",
				at = 0,
				duration = 0,
				props = {
					Brightness = 1.4,
					Color = "#FFB85A",
					Flicker = {
						amount = 0.15,
						rate = 2.5,
					},
					Range = 10,
				},
				minQuality = "medium",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE6B0",
					Lifetime = {
						1.5,
						2.5,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 1.2,
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.18,
						},
						{
							0.8,
							0.18,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.3,
						0.8,
					},
					SpreadAngle = {
						180,
						180,
					},
				},
				minQuality = "high",
				box = {
					1.6,
					1.6,
					1.6,
				},
				sprite = "dust_mote",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "ambient.window_glow",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "light",
				at = 0,
				duration = 0,
				props = {
					Brightness = 0.9,
					Color = "#FFB866",
					Flicker = {
						amount = 0.06,
						rate = 1.5,
					},
					Range = 6.5,
				},
				minQuality = "medium",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFC37A",
					Lifetime = 3,
					LightEmission = 1,
					LightInfluence = 0,
					LockedToPart = true,
					Rate = 0.4,
					Size = 1.2,
					Speed = 0,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.3,
							0.75,
						},
						{
							0.7,
							0.75,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 0.84,
				},
				sprite = "glow_soft",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "ambient.fireflies",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.2,
						0.15,
						-0.1,
					},
					Color = "#E6FF8A",
					Drag = 0.3,
					Lifetime = {
						4,
						7,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 5,
					Shape = "Box",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.35,
						},
						{
							0.45,
							0.12,
						},
						{
							0.7,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.3,
						1,
					},
					SpreadAngle = {
						180,
						180,
					},
				},
				offset = {
					0,
					2.5,
					0,
				},
				box = {
					80,
					6,
					80,
				},
				sprite = "ember",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#C8F070",
					Lifetime = {
						4,
						6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 2,
					Shape = "Box",
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							1.4,
						},
						{
							0.6,
							0.5,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.3,
						0.8,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = 0.55,
				},
				minQuality = "medium",
				offset = {
					0,
					2.5,
					0,
				},
				box = {
					80,
					6,
					80,
				},
				sprite = "glow_soft",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#F4FFC8",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.8,
						1.3,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 3,
					Shape = "Box",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.3,
						},
						{
							0.8,
							0.3,
						},
						{
							1,
							0,
						},
					},
					Speed = 0.2,
				},
				minQuality = "high",
				offset = {
					0,
					2.5,
					0,
				},
				box = {
					80,
					6,
					80,
				},
				sprite = "sparkle_twinkle",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 6,
	},
	{
		schema = "foundry.effect/1",
		id = "ambient.leaves",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						1.3,
						-0.9,
						0.4,
					},
					Color = {
						{
							0,
							"#E8A03A",
						},
						{
							1,
							"#C8642A",
						},
					},
					EmissionDirection = "Bottom",
					Lifetime = {
						6,
						9,
					},
					LightInfluence = 1,
					Rate = 6,
					RotSpeed = {
						-150,
						150,
					},
					Rotation = {
						0,
						360,
					},
					Shape = "Box",
					Size = 0.7,
					Speed = {
						0.8,
						1.6,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.05,
							0,
						},
						{
							0.9,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				offset = {
					0,
					14,
					0,
				},
				box = {
					100,
					1,
					100,
				},
				sprite = "leaf",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						1.1,
						-0.8,
						0.6,
					},
					Color = {
						{
							0,
							"#D8C04A",
						},
						{
							1,
							"#A89A3A",
						},
					},
					EmissionDirection = "Bottom",
					Lifetime = {
						6,
						9,
					},
					LightInfluence = 1,
					Rate = 4,
					RotSpeed = {
						-200,
						200,
					},
					Rotation = {
						0,
						360,
					},
					Shape = "Box",
					Size = 0.6,
					Speed = {
						0.8,
						1.6,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.05,
							0,
						},
						{
							0.9,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				minQuality = "medium",
				offset = {
					0,
					14,
					0,
				},
				box = {
					100,
					1,
					100,
				},
				sprite = "leaf",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						1.4,
						-1,
						0.2,
					},
					Color = {
						{
							0,
							"#B8483A",
						},
						{
							1,
							"#8A3A2A",
						},
					},
					EmissionDirection = "Bottom",
					Lifetime = {
						6,
						9,
					},
					LightInfluence = 1,
					Rate = 3,
					RotSpeed = {
						-180,
						180,
					},
					Rotation = {
						0,
						360,
					},
					Shape = "Box",
					Size = 0.65,
					Speed = {
						0.8,
						1.6,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.05,
							0,
						},
						{
							0.9,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				minQuality = "high",
				offset = {
					0,
					14,
					0,
				},
				box = {
					100,
					1,
					100,
				},
				sprite = "leaf",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 7,
	},
	{
		schema = "foundry.effect/1",
		id = "ambient.pollen",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.35,
						0.12,
						0.1,
					},
					Color = "#FFF0A8",
					Lifetime = {
						5,
						8,
					},
					LightEmission = 0.7,
					LightInfluence = 0.3,
					Rate = 9,
					Shape = "Box",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.22,
						},
						{
							0.8,
							0.22,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.2,
						0.6,
					},
					SpreadAngle = {
						180,
						180,
					},
				},
				offset = {
					0,
					4,
					0,
				},
				box = {
					100,
					10,
					100,
				},
				sprite = "dust_mote",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						1,
						-0.4,
						0.3,
					},
					Color = {
						{
							0,
							"#FFF4F6",
						},
						{
							1,
							"#F6C8D4",
						},
					},
					EmissionDirection = "Bottom",
					Lifetime = {
						6,
						9,
					},
					LightInfluence = 1,
					Rate = 1.5,
					RotSpeed = {
						-120,
						120,
					},
					Rotation = {
						0,
						360,
					},
					Shape = "Box",
					Size = 0.45,
					Speed = {
						0.5,
						1,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.1,
							0.1,
						},
						{
							0.85,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				minQuality = "medium",
				offset = {
					0,
					10,
					0,
				},
				box = {
					100,
					1,
					100,
				},
				sprite = "petal",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF6D0",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.8,
						1.2,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 3,
					Shape = "Box",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.25,
						},
						{
							0.8,
							0.25,
						},
						{
							1,
							0,
						},
					},
					Speed = 0.2,
				},
				minQuality = "high",
				offset = {
					0,
					4,
					0,
				},
				box = {
					100,
					8,
					100,
				},
				sprite = "sparkle_twinkle",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 6,
	},
	{
		schema = "foundry.effect/1",
		id = "ui.sparkle",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FFF6DE",
						},
						{
							1,
							"#FFD27A",
						},
					},
					Drag = 3,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.6,
						},
						{
							0.8,
							0.6,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						2,
						5,
					},
					SpreadAngle = {
						180,
						180,
					},
				},
				emit = 8,
				sprite = "sparkle_twinkle",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF6DE",
					Lifetime = 0.45,
					LightEmission = 1,
					LightInfluence = 0,
					Rotation = {
						-15,
						15,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							2.2,
						},
						{
							1,
							0,
						},
					},
					Speed = 0,
					ZOffset = 1.54,
				},
				emit = 1,
				minQuality = "medium",
				sprite = "sparkle",
			},
			{
				id = "p3",
				kind = "light",
				at = 0,
				duration = 0.25,
				props = {
					Brightness = 1.5,
					Color = "#FFF0C8",
					Range = 6,
				},
				minQuality = "high",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "ui.coin",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-34,
						0,
					},
					Color = "#FFFFFF",
					Drag = 0.6,
					FlipbookFramerate = {
						14,
						22,
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "Loop",
					FlipbookStartRandom = true,
					Lifetime = {
						1.2,
						1.7,
					},
					LightEmission = 0.15,
					LightInfluence = 0.6,
					Size = 0.9,
					Speed = {
						7.15,
						11,
					},
					SpreadAngle = {
						28,
						28,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.85,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 5,
				offset = {
					0,
					0.3,
					0,
				},
				sprite = "coin_spin",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE9A8",
					Drag = 3,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.45,
						},
						{
							0.8,
							0.45,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						2,
						4,
					},
					SpreadAngle = {
						180,
						180,
					},
				},
				emit = 5,
				minQuality = "medium",
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "light",
				at = 0,
				duration = 0.25,
				props = {
					Brightness = 1.5,
					Color = "#FFD98A",
					Range = 6,
				},
				minQuality = "high",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "ui.star",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-6,
						0,
					},
					Color = {
						{
							0,
							"#FFFFFF",
						},
						{
							1,
							"#FFD27A",
						},
					},
					Drag = 3,
					Lifetime = {
						1.1,
						1.6,
					},
					LightEmission = 0.5,
					LightInfluence = 0.2,
					RotSpeed = {
						-60,
						60,
					},
					Rotation = {
						-25,
						25,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.12,
							1.08,
						},
						{
							0.3,
							0.9,
						},
						{
							1,
							0.63,
						},
					},
					Speed = {
						4.8,
						8,
					},
					SpreadAngle = {
						60,
						60,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.75,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 4,
				offset = {
					0,
					1,
					0,
				},
				sprite = "star",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FFF6DE",
						},
						{
							1,
							"#FFD27A",
						},
					},
					Drag = 3,
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.5,
						},
						{
							0.8,
							0.5,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						2,
						5,
					},
					SpreadAngle = {
						180,
						180,
					},
				},
				emit = 6,
				minQuality = "medium",
				offset = {
					0,
					1,
					0,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF3D0",
					Lifetime = 0.45,
					LightEmission = 1,
					LightInfluence = 0,
					RotSpeed = {
						-20,
						20,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							1.05,
						},
						{
							0.25,
							3.5,
						},
						{
							1,
							4.2,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.1,
						},
						{
							0.5,
							0.4,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 2.94,
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					1,
					0,
				},
				sprite = "light_rays",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "moment.rare_loot.common",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#D8D2C4",
					Lifetime = 1.8,
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							1,
						},
						{
							0.2,
							3.7,
						},
						{
							1,
							2.4,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.3,
						},
						{
							0.6,
							0.45,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 2.59,
				},
				emit = 1,
				offset = {
					0,
					0.8,
					0,
				},
				sprite = "glow_soft",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						3,
						0,
					},
					Color = {
						{
							0,
							"#FFFFFF",
						},
						{
							1,
							"#D8D2C4",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						1,
						1.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Cylinder",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.5,
						},
						{
							0.8,
							0.5,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						2,
						4,
					},
					SpreadAngle = {
						12,
						12,
					},
				},
				emit = 8,
				box = {
					1.8,
					0.2,
					1.8,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#D8D2C4",
					Lifetime = 1.8,
					LightEmission = 1,
					LightInfluence = 0,
					Orientation = "FacingCameraWorldUp",
					Size = {
						{
							0,
							1.38,
						},
						{
							0.15,
							2.3,
						},
						{
							1,
							1.8399999999999999,
						},
					},
					Speed = 0,
					Squash = 2.6,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.12,
							0.2,
						},
						{
							0.6,
							0.45,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "medium",
				offset = {
					0,
					5,
					0,
				},
				sprite = "glow_soft",
			},
			{
				id = "p4",
				kind = "light",
				at = 0,
				duration = 1,
				props = {
					Brightness = 1.7,
					Color = "#D8D2C4",
					Range = 11,
				},
				offset = {
					0,
					2,
					0,
				},
				minQuality = "medium",
			},
			{
				id = "p5",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#D8D2C4",
					Lifetime = 0.9,
					LightEmission = 0.8,
					LightInfluence = 0.2,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							0.6000000000000001,
						},
						{
							0.3,
							4.199999999999999,
						},
						{
							1,
							6,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							0.05,
						},
						{
							0.45,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					0.25,
					0,
				},
				sprite = "shockwave_ring",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 7,
		lifetime = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "moment.rare_loot.uncommon",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#6CC08A",
					Lifetime = 1.8,
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							1,
						},
						{
							0.2,
							4.4,
						},
						{
							1,
							2.8,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.3,
						},
						{
							0.6,
							0.45,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 3.08,
				},
				emit = 1,
				offset = {
					0,
					0.8,
					0,
				},
				sprite = "glow_soft",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						4,
						0,
					},
					Color = {
						{
							0,
							"#E4FFE8",
						},
						{
							1,
							"#6CC08A",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						1,
						1.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Cylinder",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.55,
						},
						{
							0.8,
							0.55,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						2,
						5,
					},
					SpreadAngle = {
						12,
						12,
					},
				},
				emit = 11,
				box = {
					1.8,
					0.2,
					1.8,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#6CC08A",
					Lifetime = 1.8,
					LightEmission = 1,
					LightInfluence = 0,
					Orientation = "FacingCameraWorldUp",
					Size = {
						{
							0,
							1.68,
						},
						{
							0.15,
							2.8,
						},
						{
							1,
							2.2399999999999998,
						},
					},
					Speed = 0,
					Squash = 2.6,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.12,
							0.2,
						},
						{
							0.6,
							0.45,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "medium",
				offset = {
					0,
					7,
					0,
				},
				sprite = "glow_soft",
			},
			{
				id = "p4",
				kind = "light",
				at = 0,
				duration = 1,
				props = {
					Brightness = 2.2,
					Color = "#6CC08A",
					Range = 14,
				},
				offset = {
					0,
					2,
					0,
				},
				minQuality = "medium",
			},
			{
				id = "p5",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#6CC08A",
					Lifetime = 0.9,
					LightEmission = 0.8,
					LightInfluence = 0.2,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							0.8,
						},
						{
							0.3,
							5.6,
						},
						{
							1,
							8,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							0.05,
						},
						{
							0.45,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					0.25,
					0,
				},
				sprite = "shockwave_ring",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 10,
		lifetime = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "moment.rare_loot.rare",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#5B8FD9",
					Lifetime = 1.8,
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							1,
						},
						{
							0.2,
							5.1,
						},
						{
							1,
							3.2,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.3,
						},
						{
							0.6,
							0.45,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 3.5699999999999994,
				},
				emit = 1,
				offset = {
					0,
					0.8,
					0,
				},
				sprite = "glow_soft",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						5,
						0,
					},
					Color = {
						{
							0,
							"#E0ECFF",
						},
						{
							1,
							"#5B8FD9",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						1,
						1.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Cylinder",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.6000000000000001,
						},
						{
							0.8,
							0.6000000000000001,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						2,
						6,
					},
					SpreadAngle = {
						12,
						12,
					},
				},
				emit = 14,
				box = {
					1.8,
					0.2,
					1.8,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#5B8FD9",
					Lifetime = 1.8,
					LightEmission = 1,
					LightInfluence = 0,
					Orientation = "FacingCameraWorldUp",
					Size = {
						{
							0,
							1.9799999999999998,
						},
						{
							0.15,
							3.3,
						},
						{
							1,
							2.64,
						},
					},
					Speed = 0,
					Squash = 2.6,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.12,
							0.2,
						},
						{
							0.6,
							0.45,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "medium",
				offset = {
					0,
					9,
					0,
				},
				sprite = "glow_soft",
			},
			{
				id = "p4",
				kind = "light",
				at = 0,
				duration = 1,
				props = {
					Brightness = 2.7,
					Color = "#5B8FD9",
					Range = 17,
				},
				offset = {
					0,
					2,
					0,
				},
				minQuality = "medium",
			},
			{
				id = "p5",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#5B8FD9",
					Lifetime = 0.9,
					LightEmission = 0.8,
					LightInfluence = 0.2,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							1,
						},
						{
							0.3,
							7,
						},
						{
							1,
							10,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							0.05,
						},
						{
							0.45,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					0.25,
					0,
				},
				sprite = "shockwave_ring",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 13,
		lifetime = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "moment.rare_loot.epic",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#B07BE0",
					Lifetime = 1.8,
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							1,
						},
						{
							0.2,
							5.8,
						},
						{
							1,
							3.6,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.3,
						},
						{
							0.6,
							0.45,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 4.06,
				},
				emit = 1,
				offset = {
					0,
					0.8,
					0,
				},
				sprite = "glow_soft",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						6,
						0,
					},
					Color = {
						{
							0,
							"#F2E4FF",
						},
						{
							1,
							"#B07BE0",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						1,
						1.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Cylinder",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.65,
						},
						{
							0.8,
							0.65,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						2,
						7,
					},
					SpreadAngle = {
						12,
						12,
					},
				},
				emit = 17,
				box = {
					1.8,
					0.2,
					1.8,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#B07BE0",
					Lifetime = 1.8,
					LightEmission = 1,
					LightInfluence = 0,
					Orientation = "FacingCameraWorldUp",
					Size = {
						{
							0,
							2.28,
						},
						{
							0.15,
							3.8,
						},
						{
							1,
							3.04,
						},
					},
					Speed = 0,
					Squash = 2.6,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.12,
							0.2,
						},
						{
							0.6,
							0.45,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "medium",
				offset = {
					0,
					11,
					0,
				},
				sprite = "glow_soft",
			},
			{
				id = "p4",
				kind = "light",
				at = 0,
				duration = 1,
				props = {
					Brightness = 3.2,
					Color = "#B07BE0",
					Range = 20,
				},
				offset = {
					0,
					2,
					0,
				},
				minQuality = "medium",
			},
			{
				id = "p5",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#B07BE0",
					Lifetime = 0.9,
					LightEmission = 0.8,
					LightInfluence = 0.2,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							1.2000000000000002,
						},
						{
							0.3,
							8.399999999999999,
						},
						{
							1,
							12,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							0.05,
						},
						{
							0.45,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					0.25,
					0,
				},
				sprite = "shockwave_ring",
			},
			{
				id = "p6",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#F2E4FF",
					Lifetime = 0.8,
					LightEmission = 1,
					LightInfluence = 0,
					RotSpeed = {
						-20,
						20,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							3.9,
						},
						{
							0.25,
							13,
						},
						{
							1,
							15.6,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.1,
						},
						{
							0.5,
							0.4,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 7,
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					2.5,
					0,
				},
				sprite = "light_rays",
			},
			{
				id = "cue",
				kind = "sound",
				at = 0,
				duration = 0,
				props = {
					Cue = "event.star_landed",
				},
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 16,
		lifetime = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "moment.rare_loot.legendary",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#F2A93B",
					Lifetime = 1.8,
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							1,
						},
						{
							0.2,
							6.5,
						},
						{
							1,
							4,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.3,
						},
						{
							0.6,
							0.45,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 4.55,
				},
				emit = 1,
				offset = {
					0,
					0.8,
					0,
				},
				sprite = "glow_soft",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						7,
						0,
					},
					Color = {
						{
							0,
							"#FFF3D0",
						},
						{
							1,
							"#F2A93B",
						},
					},
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						1,
						1.6,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Shape = "Cylinder",
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.7,
						},
						{
							0.8,
							0.7,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						2,
						8,
					},
					SpreadAngle = {
						12,
						12,
					},
				},
				emit = 20,
				box = {
					1.8,
					0.2,
					1.8,
				},
				sprite = "sparkle_twinkle",
			},
			{
				id = "p3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#F2A93B",
					Lifetime = 1.8,
					LightEmission = 1,
					LightInfluence = 0,
					Orientation = "FacingCameraWorldUp",
					Size = {
						{
							0,
							2.5799999999999996,
						},
						{
							0.15,
							4.3,
						},
						{
							1,
							3.44,
						},
					},
					Speed = 0,
					Squash = 2.6,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.12,
							0.2,
						},
						{
							0.6,
							0.45,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "medium",
				offset = {
					0,
					13,
					0,
				},
				sprite = "glow_soft",
			},
			{
				id = "p4",
				kind = "light",
				at = 0,
				duration = 1,
				props = {
					Brightness = 3.7,
					Color = "#F2A93B",
					Range = 23,
				},
				offset = {
					0,
					2,
					0,
				},
				minQuality = "medium",
			},
			{
				id = "p5",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#F2A93B",
					Lifetime = 0.9,
					LightEmission = 0.8,
					LightInfluence = 0.2,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							1.4000000000000001,
						},
						{
							0.3,
							9.799999999999999,
						},
						{
							1,
							14,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							0.05,
						},
						{
							0.45,
							0.3,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					0.25,
					0,
				},
				sprite = "shockwave_ring",
			},
			{
				id = "p6",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF3D0",
					Lifetime = 0.8,
					LightEmission = 1,
					LightInfluence = 0,
					RotSpeed = {
						-20,
						20,
					},
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							4.5,
						},
						{
							0.25,
							15,
						},
						{
							1,
							18,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							0.1,
						},
						{
							0.5,
							0.4,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 7,
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					2.5,
					0,
				},
				sprite = "light_rays",
			},
			{
				id = "p7",
				kind = "beam",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FFF3D0",
						},
						{
							1,
							"#F2A93B",
						},
					},
					FaceCamera = true,
					LightEmission = 1,
					LightInfluence = 0,
					Attachment0 = {
						0,
						0.2,
						0,
					},
					Attachment1 = {
						0,
						26,
						0,
					},
					TextureLength = 1,
					TextureMode = "Stretch",
					TextureSpeed = 0.35,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.12,
							0.6,
						},
						{
							0.5,
							0.68,
						},
						{
							1,
							1,
						},
					},
					Width0 = 3.2,
					Width1 = 1.4400000000000002,
				},
				minQuality = "high",
				sprite = "light_shaft",
			},
			{
				id = "p8",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-6,
						0,
					},
					Color = {
						{
							0,
							"#FFFFFF",
						},
						{
							1,
							"#F2A93B",
						},
					},
					Drag = 3,
					Lifetime = {
						1.1,
						1.6,
					},
					LightEmission = 0.5,
					LightInfluence = 0.2,
					RotSpeed = {
						-60,
						60,
					},
					Rotation = {
						-25,
						25,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.12,
							0.96,
						},
						{
							0.3,
							0.8,
						},
						{
							1,
							0.5599999999999999,
						},
					},
					Speed = {
						6,
						10,
					},
					SpreadAngle = {
						60,
						60,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.75,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 8,
				minQuality = "high",
				offset = {
					0,
					2,
					0,
				},
				sprite = "star",
			},
			{
				id = "cue",
				kind = "sound",
				at = 0,
				duration = 0,
				props = {
					Cue = "event.star_landed",
				},
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 19,
		lifetime = 2,
	},
	{
		schema = "foundry.effect/1",
		id = "moment.reveal",
		kind = "moment",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0.25,
				duration = 0,
				props = {
					Acceleration = {
						0,
						1.5,
						0,
					},
					Color = "#F1E4C6",
					Drag = 1.5,
					Lifetime = {
						0.8,
						1.4,
					},
					LightInfluence = 0.6,
					Shape = "Box",
					Size = {
						{
							0,
							0.2,
						},
						{
							0.3,
							0.45,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1.5,
						3.5,
					},
					SpreadAngle = {
						25,
						25,
					},
					Transparency = {
						{
							0,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 14,
				offset = {
					0,
					0.3,
					0,
				},
				box = {
					8,
					0.4,
					8,
				},
				sprite = "dust_mote",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0.6,
				duration = 0,
				props = {
					Color = "#F1E4C6",
					Lifetime = 0.9,
					LightEmission = 0.3,
					LightInfluence = 0.5,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							1,
						},
						{
							0.3,
							7,
						},
						{
							1,
							10,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							0.35,
						},
						{
							0.5,
							0.6,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 1,
				minQuality = "high",
				offset = {
					0,
					0.2,
					0,
				},
				sprite = "shockwave_ring",
			},
			{
				id = "cue",
				kind = "sound",
				at = 0,
				duration = 0,
				props = {
					Cue = "ui.toast.success",
				},
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 12,
		lifetime = 1.8,
	},
	{
		schema = "foundry.effect/1",
		id = "ui.heart",
		kind = "burst",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						2,
						0,
					},
					Color = {
						{
							0,
							"#FF9AB0",
						},
						{
							1,
							"#E8577A",
						},
					},
					Drag = 3,
					Lifetime = {
						1.1,
						1.6,
					},
					LightEmission = 0.5,
					LightInfluence = 0.2,
					RotSpeed = {
						-60,
						60,
					},
					Rotation = {
						-25,
						25,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.12,
							0.96,
						},
						{
							0.3,
							0.8,
						},
						{
							1,
							0.5599999999999999,
						},
					},
					Speed = {
						2.4,
						4,
					},
					SpreadAngle = {
						25,
						25,
					},
					Transparency = {
						{
							0,
							0,
						},
						{
							0.75,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				emit = 3,
				offset = {
					0,
					1.5,
					0,
				},
				sprite = "heart",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE0EA",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.5,
						0.9,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.4,
						},
						{
							0.8,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				emit = 4,
				minQuality = "medium",
				offset = {
					0,
					1.5,
					0,
				},
				sprite = "sparkle_twinkle",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
	{
		schema = "foundry.effect/1",
		id = "ambient.tavern_music",
		kind = "loop",
		layers = {
			{
				id = "p1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.4,
						0.3,
						0,
					},
					Color = {
						{
							0,
							"#FFF1C8",
						},
						{
							1,
							"#FFC86B",
						},
					},
					Lifetime = {
						2.5,
						3.5,
					},
					LightEmission = 0.6,
					LightInfluence = 0.3,
					Rate = 0.8,
					RotSpeed = {
						-30,
						30,
					},
					Rotation = {
						-20,
						20,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.15,
							0.9,
						},
						{
							0.8,
							0.8,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						1.8,
					},
					SpreadAngle = {
						25,
						25,
					},
					Transparency = {
						{
							0,
							0.1,
						},
						{
							0.8,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				sprite = "music_note",
			},
			{
				id = "p2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						1,
						0,
					},
					Color = "#FFE9A8",
					FlipbookLayout = "Grid4x4",
					FlipbookMode = "OneShot",
					Lifetime = {
						0.8,
						1.2,
					},
					LightEmission = 1,
					LightInfluence = 0,
					Rate = 1.2,
					Size = {
						{
							0,
							0,
						},
						{
							0.2,
							0.3,
						},
						{
							0.8,
							0.3,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						70,
						70,
					},
				},
				minQuality = "medium",
				sprite = "sparkle_twinkle",
			},
		},
		tags = {},
		source = {
			game = "guildhall",
			path = "src/systems/VfxLibrary/Config.luau",
			format = "clientfx",
		},
		cost = 3,
	},
}
