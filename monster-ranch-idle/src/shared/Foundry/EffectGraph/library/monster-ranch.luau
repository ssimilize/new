--!nonstrict
-- generated from packages/EffectGraph/graphs/monster-ranch.json by
-- `foundry vfx export --write`; edit the JSON, not this file
return {
	{
		schema = "foundry.effect/1",
		id = "Auras.ember",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						3,
						0,
					},
					Lifetime = {
						0.5,
						0.8,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					Rate = 4,
					Rotation = {
						-10,
						10,
					},
					Size = {
						{
							0,
							0.35,
						},
						{
							0.4,
							0.5,
						},
						{
							1,
							0.1,
						},
					},
					Speed = {
						1,
						2,
					},
					SpreadAngle = {
						35,
						35,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.12,
							0.05,
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
				},
				anchor = "feet",
				nightGlow = 1,
				sprite = "flame",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						2.5,
						0,
					},
					Lifetime = {
						1,
						1.4,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 3,
					Size = {
						{
							0,
							0.18,
						},
						{
							1,
							0.05,
						},
					},
					Speed = {
						0.5,
						1.2,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 1,
				sprite = "ember",
				filled = {
					"night",
					"transparency",
				},
			},
		},
		tags = {
			"Auras",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Auras",
			key = "ember",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Auras.gloom",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.5,
						0,
					},
					Color = "#9168D0",
					Drag = 0.4,
					Lifetime = {
						1.8,
						2.4,
					},
					LightEmission = 0.15,
					LightInfluence = 0.3,
					Rate = 1.5,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-25,
						25,
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
						0.6,
						1.2,
					},
					SpreadAngle = {
						20,
						20,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "feet",
				tinted = true,
				nightGlow = 0.5,
				sprite = "wisp",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#C9A8FF",
					Lifetime = {
						1.2,
						1.8,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 2,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.2,
						0.5,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "glow",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Auras",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Auras",
			key = "gloom",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Auras.light",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE9A8",
					Lifetime = {
						0.8,
						1.2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 3,
					Rotation = {
						0,
						45,
					},
					RotSpeed = {
						-30,
						30,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF6D6",
					Lifetime = {
						1.5,
						2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					LockedToPart = true,
					Rate = 1,
					Size = {
						{
							0,
							1.6,
						},
						{
							0.3,
							2.4,
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
							1,
						},
						{
							0.3,
							0.75,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "core",
				tinted = true,
				nightGlow = 1,
				sprite = "glow",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Auras",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Auras",
			key = "light",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Auras.spark",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Lifetime = {
						0.15,
						0.25,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					LockedToPart = true,
					Rate = 3,
					Rotation = {
						-40,
						40,
					},
					Shape = "Sphere",
					Size = {
						{
							0,
							0.5,
						},
						{
							1,
							0.4,
						},
					},
					Speed = 0,
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
							0.6,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 1,
				sprite = "bolt",
				filled = {
					"night",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-6,
						0,
					},
					Lifetime = {
						0.4,
						0.7,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 3,
					Size = {
						{
							0,
							0.14,
						},
						{
							1,
							0.04,
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
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 1,
				sprite = "ember",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
		},
		tags = {
			"Auras",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Auras",
			key = "spark",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Auras.sprout",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-0.8,
						0,
					},
					Drag = 0.6,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.8,
					Rate = 1.5,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-90,
						90,
					},
					Size = 0.35,
					Speed = {
						0.5,
						1,
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
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 0,
				sprite = "leaf",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-0.6,
						0,
					},
					Drag = 0.6,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.8,
					Rate = 1,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-120,
						120,
					},
					Size = 0.25,
					Speed = {
						0.4,
						0.8,
					},
					SpreadAngle = {
						70,
						70,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "head",
				nightGlow = 0,
				sprite = "petal",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
		},
		tags = {
			"Auras",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Auras",
			key = "sprout",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Auras.stone",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.4,
						0,
					},
					Drag = 0.8,
					Lifetime = {
						1.6,
						2.2,
					},
					LightEmission = 0.15,
					LightInfluence = 0.8,
					Rate = 1.5,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-60,
						60,
					},
					Size = {
						{
							0,
							0.15,
						},
						{
							0.3,
							0.25,
						},
						{
							1,
							0.2,
						},
					},
					Speed = {
						0.6,
						1.2,
					},
					SpreadAngle = {
						50,
						50,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "feet",
				nightGlow = 0,
				sprite = "pebble",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E6D9C8",
					Drag = 1,
					Lifetime = {
						1,
						1.5,
					},
					LightEmission = 0.15,
					LightInfluence = 0.8,
					Rate = 1,
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
							1,
						},
					},
					Speed = {
						0.5,
						1,
					},
					SpreadAngle = {
						80,
						80,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.6,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "feet",
				tinted = true,
				nightGlow = 0,
				sprite = "puff",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Auras",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Auras",
			key = "stone",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Auras.tide",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-8,
						0,
					},
					Lifetime = {
						0.8,
						1.1,
					},
					LightEmission = 0.2,
					LightInfluence = 0.6,
					Orientation = "VelocityParallel",
					Rate = 2.5,
					Size = {
						{
							0,
							0.3,
						},
						{
							1,
							0.22,
						},
					},
					Speed = {
						0.3,
						0.8,
					},
					SpreadAngle = {
						40,
						40,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 0.4,
				sprite = "droplet",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						1.2,
						0,
					},
					Color = "#9FD7FF",
					Drag = 0.5,
					Lifetime = {
						1.6,
						2.2,
					},
					LightEmission = 0.2,
					LightInfluence = 0.5,
					Rate = 2,
					Size = {
						{
							0,
							0.15,
						},
						{
							0.3,
							0.3,
						},
						{
							1,
							0.35,
						},
					},
					Speed = {
						0.3,
						0.6,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 0.5,
				sprite = "bubble",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
		},
		tags = {
			"Auras",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Auras",
			key = "tide",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Auras.void",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Lifetime = {
						2,
						2.6,
					},
					LightEmission = 0.2,
					LightInfluence = 0.3,
					LockedToPart = true,
					Rate = 0.6,
					RotSpeed = {
						-120,
						-80,
					},
					Size = {
						{
							0,
							0.3,
						},
						{
							0.3,
							1.4,
						},
						{
							1,
							0.2,
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
							0.4,
						},
						{
							1,
							1,
						},
					},
					ZOffset = -1,
				},
				anchor = "core",
				nightGlow = 1,
				sprite = "voidswirl",
				filled = {
					"night",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#3B3470",
					Lifetime = {
						1,
						1.4,
					},
					LightEmission = 0.15,
					LightInfluence = 0.3,
					Rate = 2,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-60,
						60,
					},
					Shape = "Sphere",
					ShapeInOut = "Inward",
					ShapeStyle = "Surface",
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
						0.8,
						1.2,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 0.5,
				sprite = "wisp",
				filled = {
					"night",
				},
			},
			{
				id = "e3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#5CE1E6",
					Lifetime = {
						1,
						1.4,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 1.5,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.2,
						0.5,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "glow",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Auras",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Auras",
			key = "void",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Bursts.coins",
		kind = "burst",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-45,
						0,
					},
					Lifetime = {
						0.8,
						1.2,
					},
					LightEmission = 0.2,
					LightInfluence = 0.3,
					RotSpeed = {
						-200,
						200,
					},
					Size = {
						{
							0,
							0.7,
						},
						{
							1,
							0.45,
						},
					},
					Speed = {
						14,
						24,
					},
					SpreadAngle = {
						35,
						35,
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
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				emit = 24,
				nightGlow = 0,
				sprite = "coin",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Bursts",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Bursts",
			key = "coins",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Bursts.evolve",
		kind = "burst",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF6D6",
					Lifetime = {
						0.8,
						1.1,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Size = {
						{
							0,
							0.4,
						},
						{
							0.3,
							1,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						6,
						10,
					},
					SpreadAngle = {
						5,
						5,
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
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				box = {
					3,
					1,
					3,
				},
				emit = 14,
				tinted = true,
				nightGlow = 1,
				sprite = "glow",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFFFFF",
					Lifetime = {
						0.5,
						0.5,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							0.5,
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
							1,
						},
						{
							0.05,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 0.5,
				},
				emit = 1,
				tinted = true,
				nightGlow = 0.8,
				sprite = "ring",
				filled = {
					"night",
				},
			},
			{
				id = "e3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE9A0",
					Lifetime = {
						1.2,
						1.2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					RotSpeed = {
						90,
						90,
					},
					Size = 7,
					Speed = 0.01,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0.2,
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
				},
				emit = 1,
				tinted = true,
				nightGlow = 1,
				sprite = "rune",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Bursts",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Bursts",
			key = "evolve",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Bursts.evolveVortex",
		kind = "burst",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFFFFF",
					Lifetime = {
						0.6,
						0.8,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					RotSpeed = {
						-360,
						360,
					},
					Size = {
						{
							0,
							0.3,
						},
						{
							0.3,
							0.9,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						5,
						8,
					},
					SpreadAngle = {
						12,
						12,
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
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				box = {
					3,
					0.5,
					3,
				},
				emit = 5,
				tinted = true,
				nightGlow = 0.5,
				sprite = "wisp",
				takesColor = true,
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFFFFF",
					Lifetime = {
						0.5,
						0.5,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							0.5,
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
							1,
						},
						{
							0.05,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 0.5,
				},
				emit = 1,
				tinted = true,
				nightGlow = 0.8,
				sprite = "ring",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Bursts",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Bursts",
			key = "evolveVortex",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Bursts.hatch",
		kind = "burst",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFFFFF",
					Drag = 4,
					Lifetime = {
						0.6,
						0.9,
					},
					LightEmission = 0.2,
					LightInfluence = 0.6,
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
							2.5,
						},
					},
					Speed = {
						4,
						7,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.05,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				emit = 10,
				tinted = true,
				nightGlow = 0,
				sprite = "puff",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFFFFF",
					Lifetime = {
						0.5,
						0.5,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							0.5,
						},
						{
							1,
							9,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.05,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 0.5,
				},
				emit = 1,
				tinted = true,
				nightGlow = 0.8,
				sprite = "ring",
				filled = {
					"night",
				},
			},
			{
				id = "e3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-10,
						0,
					},
					Lifetime = {
						0.8,
						1.1,
					},
					LightEmission = 0.25,
					LightInfluence = 0.2,
					RotSpeed = {
						-180,
						180,
					},
					Size = {
						{
							0,
							0.3,
						},
						{
							0.2,
							0.7,
						},
						{
							1,
							0.3,
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
							1,
						},
						{
							0.05,
							0,
						},
						{
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				emit = 6,
				nightGlow = 0.8,
				sprite = "star5",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e4",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF6D6",
					Drag = 2,
					Lifetime = {
						0.7,
						1,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
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
							1,
							0,
						},
					},
					Speed = {
						3,
						6,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				emit = 12,
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				takesColor = true,
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Bursts",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Bursts",
			key = "hatch",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Bursts.hearts",
		kind = "burst",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						3,
						0,
					},
					Drag = 2,
					Lifetime = {
						1,
						1.4,
					},
					LightEmission = 0.2,
					LightInfluence = 0.3,
					Size = {
						{
							0,
							0.9,
						},
						{
							1,
							0.4,
						},
					},
					Speed = {
						4,
						7,
					},
					SpreadAngle = {
						40,
						40,
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
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				emit = 10,
				nightGlow = 0,
				sprite = "heart",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Bursts",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Bursts",
			key = "hearts",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Bursts.monsterLevelUp",
		kind = "burst",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-12,
						0,
					},
					Lifetime = {
						0.8,
						1.1,
					},
					LightEmission = 0.25,
					LightInfluence = 0.2,
					RotSpeed = {
						-180,
						180,
					},
					Size = {
						{
							0,
							0.3,
						},
						{
							0.2,
							0.6,
						},
						{
							1,
							0.3,
						},
					},
					Speed = {
						5,
						8,
					},
					SpreadAngle = {
						45,
						45,
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
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				emit = 8,
				nightGlow = 0.8,
				sprite = "star5",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFD447",
					Lifetime = {
						0.5,
						0.5,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							0.5,
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
							1,
						},
						{
							0.05,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 0.5,
				},
				emit = 1,
				tinted = true,
				nightGlow = 0.8,
				sprite = "ring",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Bursts",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Bursts",
			key = "monsterLevelUp",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Bursts.ranchLevelUp",
		kind = "burst",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFD447",
					Lifetime = {
						0.5,
						0.5,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							0.5,
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
							1,
						},
						{
							0.05,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 0.5,
				},
				emit = 1,
				tinted = true,
				nightGlow = 0.8,
				sprite = "ring",
				filled = {
					"night",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-18,
						0,
					},
					Color = {
						{
							0,
							"#FF5A5A",
						},
						{
							0.2,
							"#FFB547",
						},
						{
							0.4,
							"#FFE14D",
						},
						{
							0.6,
							"#62BF55",
						},
						{
							0.8,
							"#4FB6F2",
						},
						{
							1,
							"#B07CFF",
						},
					},
					Drag = 1,
					Lifetime = {
						1.5,
						2.2,
					},
					LightEmission = 0.2,
					LightInfluence = 0.6,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-300,
						300,
					},
					Size = 0.45,
					Speed = {
						10,
						16,
					},
					SpreadAngle = {
						50,
						50,
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
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				emit = 30,
				tinted = true,
				nightGlow = 0,
				sprite = "confetti",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-14,
						0,
					},
					Lifetime = {
						1,
						1.3,
					},
					LightEmission = 0.25,
					LightInfluence = 0.2,
					RotSpeed = {
						-180,
						180,
					},
					Size = {
						{
							0,
							0.3,
						},
						{
							0.2,
							0.8,
						},
						{
							1,
							0.3,
						},
					},
					Speed = {
						8,
						12,
					},
					SpreadAngle = {
						40,
						40,
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
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				emit = 8,
				nightGlow = 0.8,
				sprite = "star5",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Bursts",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Bursts",
			key = "ranchLevelUp",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Bursts.rebirth",
		kind = "burst",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E6DDFF",
					Lifetime = {
						1.2,
						1.6,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
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
							1,
							0,
						},
					},
					Speed = {
						8,
						14,
					},
					SpreadAngle = {
						8,
						8,
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
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				box = {
					4,
					1,
					4,
				},
				emit = 30,
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#B9A7FF",
					Lifetime = {
						0.5,
						0.5,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							0.5,
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
							1,
						},
						{
							0.05,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 0.5,
				},
				emit = 1,
				tinted = true,
				nightGlow = 0.8,
				sprite = "ring",
				filled = {
					"night",
				},
			},
			{
				id = "e3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						4,
						0,
					},
					Lifetime = {
						0.5,
						0.8,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					Size = {
						{
							0,
							0.6,
						},
						{
							0.5,
							0.9,
						},
						{
							1,
							0.1,
						},
					},
					Speed = {
						3,
						5,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				emit = 8,
				nightGlow = 1,
				sprite = "flame",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Bursts",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Bursts",
			key = "rebirth",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Bursts.shinyShower",
		kind = "burst",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-12,
						0,
					},
					Color = "#FFE38A",
					Lifetime = {
						1,
						1.4,
					},
					LightEmission = 0.3,
					LightInfluence = 0.2,
					RotSpeed = {
						-180,
						180,
					},
					Size = {
						{
							0,
							0.3,
						},
						{
							0.2,
							0.6,
						},
						{
							1,
							0.3,
						},
					},
					Speed = {
						1,
						3,
					},
					SpreadAngle = {
						30,
						30,
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
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				box = {
					4,
					0.5,
					4,
				},
				emit = 16,
				tinted = true,
				nightGlow = 0.8,
				sprite = "star5",
				takesColor = true,
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
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
							"#FF5A5A",
						},
						{
							0.2,
							"#FFB547",
						},
						{
							0.4,
							"#FFE14D",
						},
						{
							0.6,
							"#62BF55",
						},
						{
							0.8,
							"#4FB6F2",
						},
						{
							1,
							"#B07CFF",
						},
					},
					Lifetime = {
						1.2,
						1.6,
					},
					LightEmission = 0.2,
					LightInfluence = 0.3,
					RotSpeed = {
						-240,
						240,
					},
					Size = {
						{
							0,
							0.4,
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
						40,
						40,
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
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				box = {
					4,
					0.5,
					4,
				},
				emit = 12,
				tinted = true,
				nightGlow = 0,
				sprite = "confetti",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Bursts",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Bursts",
			key = "shinyShower",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Bursts.starUp",
		kind = "burst",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-12,
						0,
					},
					Lifetime = {
						0.8,
						1.1,
					},
					LightEmission = 0.25,
					LightInfluence = 0.2,
					RotSpeed = {
						-180,
						180,
					},
					Size = {
						{
							0,
							0.3,
						},
						{
							0.2,
							0.7,
						},
						{
							1,
							0.3,
						},
					},
					Speed = {
						6,
						9,
					},
					SpreadAngle = {
						50,
						50,
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
							0.7,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 1,
				},
				emit = 12,
				nightGlow = 0.8,
				sprite = "star5",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFB547",
					Lifetime = {
						0.5,
						0.5,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					Size = {
						{
							0,
							0.5,
						},
						{
							1,
							9,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.05,
							0.1,
						},
						{
							1,
							1,
						},
					},
					ZOffset = 0.5,
				},
				emit = 1,
				tinted = true,
				nightGlow = 0.8,
				sprite = "ring",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Bursts",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Bursts",
			key = "starUp",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "EggReady",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFD98A",
					Lifetime = {
						1.4,
						1.6,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 1.2,
					Size = {
						{
							0,
							2.4,
						},
						{
							0.5,
							3.1,
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
							1,
						},
						{
							0.35,
							0.72,
						},
						{
							1,
							1,
						},
					},
					ZOffset = -1,
				},
				anchor = "core",
				tinted = true,
				nightGlow = 1,
				sprite = "glow",
				filled = {
					"night",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						1.4,
						0,
					},
					Color = "#FFE9A8",
					Lifetime = {
						0.9,
						1.3,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 2.4,
					RotSpeed = {
						-90,
						90,
					},
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0.1,
						},
						{
							0.3,
							0.34,
						},
						{
							1,
							0,
						},
					},
					Speed = 0.5,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"transparency",
				},
			},
		},
		tags = {
			"EggReady",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "EggReady",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Eggs.celestial",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#D6CCFF",
					Lifetime = {
						0.6,
						0.9,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 1.5,
					RotSpeed = {
						-60,
						60,
					},
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0,
						},
						{
							0.35,
							0.32,
						},
						{
							1,
							0,
						},
					},
					Speed = 0.05,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.25,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#B9A7FF",
					Lifetime = {
						1.4,
						1.8,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 0.5,
					RotSpeed = {
						-90,
						90,
					},
					Size = {
						{
							0,
							0.18,
						},
						{
							1,
							0.06,
						},
					},
					Speed = {
						0.4,
						0.7,
					},
					SpreadAngle = {
						40,
						40,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "head",
				tinted = true,
				nightGlow = 0.8,
				sprite = "star5",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
		},
		tags = {
			"Eggs",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Eggs",
			key = "celestial",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Eggs.crystal",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E8F9FF",
					Lifetime = {
						0.6,
						0.9,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 2,
					RotSpeed = {
						-60,
						60,
					},
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0,
						},
						{
							0.35,
							0.36,
						},
						{
							1,
							0,
						},
					},
					Speed = 0.05,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.25,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Lifetime = {
						0.7,
						1,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 0.5,
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0,
						},
						{
							0.4,
							0.3,
						},
						{
							1,
							0,
						},
					},
					Speed = 0.05,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 1,
				sprite = "prism",
				filled = {
					"night",
					"transparency",
				},
			},
		},
		tags = {
			"Eggs",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Eggs",
			key = "crystal",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Eggs.frostfall",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-0.7,
						0,
					},
					Color = "#DDF3FF",
					Lifetime = {
						1.8,
						2.4,
					},
					LightEmission = 0.2,
					LightInfluence = 0.3,
					Rate = 0.9,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-40,
						40,
					},
					Size = {
						{
							0,
							0.2,
						},
						{
							1,
							0.12,
						},
					},
					Speed = {
						0.3,
						0.6,
					},
					SpreadAngle = {
						70,
						70,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "head",
				tinted = true,
				nightGlow = 0.6,
				sprite = "snowflake",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
		},
		tags = {
			"Eggs",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Eggs",
			key = "frostfall",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Eggs.glacier",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-0.7,
						0,
					},
					Color = "#DDF3FF",
					Lifetime = {
						1.8,
						2.4,
					},
					LightEmission = 0.2,
					LightInfluence = 0.3,
					Rate = 0.9,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-40,
						40,
					},
					Size = {
						{
							0,
							0.2,
						},
						{
							1,
							0.12,
						},
					},
					Speed = {
						0.3,
						0.6,
					},
					SpreadAngle = {
						70,
						70,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "head",
				tinted = true,
				nightGlow = 0.6,
				sprite = "snowflake",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFFFFF",
					Lifetime = {
						0.6,
						0.9,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 1,
					RotSpeed = {
						-60,
						60,
					},
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0,
						},
						{
							0.35,
							0.26,
						},
						{
							1,
							0,
						},
					},
					Speed = 0.05,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.25,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Eggs",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Eggs",
			key = "glacier",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Eggs.leviathan",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						1.2,
						0,
					},
					Color = "#BFEFFF",
					Lifetime = {
						1.2,
						1.6,
					},
					LightEmission = 0.2,
					LightInfluence = 0.4,
					Rate = 1,
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0.08,
						},
						{
							1,
							0.16,
						},
					},
					Speed = 0.2,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 0.5,
				sprite = "bubble",
				filled = {
					"night",
					"transparency",
				},
			},
		},
		tags = {
			"Eggs",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Eggs",
			key = "leviathan",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Eggs.raid",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						1.6,
						0,
					},
					Lifetime = {
						0.9,
						1.3,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 1.2,
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0.14,
						},
						{
							1,
							0.03,
						},
					},
					Speed = 0.3,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 1,
				sprite = "ember",
				filled = {
					"night",
					"transparency",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#F5C630",
					Lifetime = {
						0.6,
						0.9,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 0.8,
					RotSpeed = {
						-60,
						60,
					},
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0,
						},
						{
							0.35,
							0.26,
						},
						{
							1,
							0,
						},
					},
					Speed = 0.05,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.25,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Eggs",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Eggs",
			key = "raid",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Eggs.royal",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFD447",
					Lifetime = {
						0.6,
						0.9,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 1.6,
					RotSpeed = {
						-60,
						60,
					},
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0,
						},
						{
							0.35,
							0.34,
						},
						{
							1,
							0,
						},
					},
					Speed = 0.05,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.25,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Eggs",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Eggs",
			key = "royal",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Eggs.stampede",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						1.6,
						0,
					},
					Lifetime = {
						0.9,
						1.3,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 1.2,
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0.14,
						},
						{
							1,
							0.03,
						},
					},
					Speed = 0.3,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 1,
				sprite = "ember",
				filled = {
					"night",
					"transparency",
				},
			},
		},
		tags = {
			"Eggs",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Eggs",
			key = "stampede",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Eggs.starlit",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE680",
					Lifetime = {
						0.6,
						0.9,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 1.8,
					RotSpeed = {
						-60,
						60,
					},
					Shape = "Sphere",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							0,
						},
						{
							0.35,
							0.32,
						},
						{
							1,
							0,
						},
					},
					Speed = 0.05,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.25,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Eggs",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Eggs",
			key = "starlit",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Landmarks.arena",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#D9C4A6",
					Lifetime = {
						1.5,
						2.2,
					},
					LightEmission = 0.15,
					LightInfluence = 0.8,
					Rate = 2,
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
						0.5,
						1.2,
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
							0.2,
							0.55,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					-0.5,
					0,
				},
				box = {
					26,
					1,
					26,
				},
				tinted = true,
				nightGlow = 0,
				sprite = "puff",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						1.5,
						0,
					},
					Lifetime = {
						1.2,
						1.8,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 3,
					Size = {
						{
							0,
							0.3,
						},
						{
							1,
							0.1,
						},
					},
					Speed = {
						1,
						2,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0.5,
					0,
				},
				box = {
					26,
					1,
					26,
				},
				nightGlow = 1,
				sprite = "ember",
				filled = {
					"night",
					"transparency",
				},
			},
		},
		tags = {
			"Landmarks",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Landmarks",
			key = "arena",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Landmarks.championsArena",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#D9C4A6",
					Lifetime = {
						1.5,
						2.2,
					},
					LightEmission = 0.15,
					LightInfluence = 0.8,
					Rate = 2,
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
						0.5,
						1.2,
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
							0.2,
							0.55,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					-0.5,
					0,
				},
				box = {
					26,
					1,
					26,
				},
				tinted = true,
				nightGlow = 0,
				sprite = "puff",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						1.5,
						0,
					},
					Lifetime = {
						1.2,
						1.8,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 3,
					Size = {
						{
							0,
							0.3,
						},
						{
							1,
							0.1,
						},
					},
					Speed = {
						1,
						2,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0.5,
					0,
				},
				box = {
					26,
					1,
					26,
				},
				nightGlow = 1,
				sprite = "ember",
				filled = {
					"night",
					"transparency",
				},
			},
		},
		tags = {
			"Landmarks",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Landmarks",
			key = "championsArena",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Landmarks.eggShop",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF1B3",
					Lifetime = {
						0.8,
						1.2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 3,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.6,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.2,
						0.5,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0.3,
					-0.52,
				},
				box = {
					20,
					3,
					1,
				},
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Landmarks",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Landmarks",
			key = "eggShop",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Landmarks.gate",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#D8FF7A",
					Drag = 0.5,
					Lifetime = {
						2.5,
						3.5,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 3,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.35,
						},
						{
							0.7,
							0.3,
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
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0,
					-0.55,
				},
				box = {
					22,
					16,
					6,
				},
				tinted = true,
				nightGlow = 1,
				sprite = "glow",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Landmarks",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Landmarks",
			key = "gate",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Landmarks.hallOfFame",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFD447",
					Lifetime = {
						1,
						1.4,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 4,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.6,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					-0.2,
					-0.6,
				},
				box = {
					20,
					8,
					3,
				},
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Landmarks",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Landmarks",
			key = "hallOfFame",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Landmarks.hubPortal",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#6FD0FF",
					EmissionDirection = "Front",
					Lifetime = {
						3,
						3,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					Rate = 0.45,
					RotSpeed = {
						60,
						90,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.25,
							4.4,
						},
						{
							1,
							4.800000000000001,
						},
					},
					Speed = 0.02,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.25,
							0.6,
						},
						{
							0.75,
							0.6,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					-0.27,
					-0.5,
				},
				tinted = true,
				nightGlow = 1,
				sprite = "swirl",
				filled = {
					"night",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#BDEBFF",
					Lifetime = {
						1.5,
						2,
					},
					LightEmission = 0.8,
					LightInfluence = 0,
					Rate = 1,
					Size = {
						{
							0,
							1.2000000000000002,
						},
						{
							0.5,
							2.8000000000000003,
						},
						{
							1,
							2.4000000000000004,
						},
					},
					Speed = 0,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.3,
							0.6,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					-0.27,
					-0.52,
				},
				bright = true,
				tinted = true,
				nightGlow = 1,
				sprite = "glow",
				filled = {
					"night",
				},
			},
			{
				id = "e3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#9FD7FF",
					Drag = 0.3,
					Lifetime = {
						2.5,
						3.5,
					},
					LightEmission = 0.2,
					LightInfluence = 0.5,
					Rate = 3,
					Size = {
						{
							0,
							0.3,
						},
						{
							0.3,
							0.7,
						},
						{
							1,
							0.8,
						},
					},
					Speed = {
						1.5,
						2.5,
					},
					SpreadAngle = {
						15,
						15,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					-0.5,
					-0.5,
				},
				box = {
					10,
					1,
					3,
				},
				tinted = true,
				nightGlow = 0.5,
				sprite = "bubble",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
			{
				id = "e4",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E6F6FF",
					Lifetime = {
						0.8,
						1.2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 3,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.8,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0,
					-0.5,
				},
				box = {
					12,
					14,
					2,
				},
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Landmarks",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Landmarks",
			key = "hubPortal",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Landmarks.raidPortal",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#8F7BFF",
					EmissionDirection = "Front",
					Lifetime = {
						3,
						3,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					Rate = 0.45,
					RotSpeed = {
						60,
						90,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.25,
							5.5,
						},
						{
							1,
							6,
						},
					},
					Speed = 0.02,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.25,
							0.6,
						},
						{
							0.75,
							0.6,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0.05,
					-0.5,
				},
				tinted = true,
				nightGlow = 1,
				sprite = "swirl",
				filled = {
					"night",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#B9A7FF",
					Lifetime = {
						1.5,
						2,
					},
					LightEmission = 0.8,
					LightInfluence = 0,
					Rate = 1,
					Size = {
						{
							0,
							1.5,
						},
						{
							0.5,
							3.5,
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
							1,
						},
						{
							0.3,
							0.6,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0.05,
					-0.52,
				},
				bright = true,
				tinted = true,
				nightGlow = 1,
				sprite = "glow",
				filled = {
					"night",
				},
			},
			{
				id = "e3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.8,
						0,
					},
					Color = "#6B5BD6",
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.15,
					LightInfluence = 0.3,
					Rate = 4,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-25,
						25,
					},
					Size = {
						{
							0,
							1.5,
						},
						{
							1,
							3.5,
						},
					},
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
							0.2,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					-0.5,
					-0.5,
				},
				box = {
					12,
					1,
					3,
				},
				tinted = true,
				nightGlow = 0.5,
				sprite = "wisp",
				filled = {
					"night",
				},
			},
			{
				id = "e4",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#B9A7FF",
					EmissionDirection = "Front",
					Lifetime = {
						1.2,
						1.2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					Rate = 0.33,
					Size = {
						{
							0,
							3,
						},
						{
							1,
							10,
						},
					},
					Speed = 0.02,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.1,
							0.45,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0.05,
					-0.53,
				},
				tinted = true,
				nightGlow = 0.8,
				sprite = "ring",
				filled = {
					"night",
				},
			},
			{
				id = "e5",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#C9B8FF",
					Lifetime = {
						1.2,
						1.8,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 3,
					RotSpeed = {
						-40,
						40,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.7,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1.5,
						2.5,
					},
					SpreadAngle = {
						15,
						15,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					-0.3,
					-0.2,
				},
				box = {
					13,
					1,
					6,
				},
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Landmarks",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Landmarks",
			key = "raidPortal",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Landmarks.showStage",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-1.5,
						0,
					},
					EmissionDirection = "Bottom",
					Drag = 0.4,
					Lifetime = {
						3,
						4,
					},
					LightEmission = 0.15,
					LightInfluence = 0.8,
					Rate = 4,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-120,
						120,
					},
					Size = 0.5,
					Speed = {
						0.2,
						0.5,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					1.5,
					0,
				},
				box = {
					18,
					1,
					12,
				},
				nightGlow = 0,
				sprite = "petal",
				filled = {
					"night",
					"transparency",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-1.5,
						0,
					},
					Color = {
						{
							0,
							"#FF5A5A",
						},
						{
							0.2,
							"#FFB547",
						},
						{
							0.4,
							"#FFE14D",
						},
						{
							0.6,
							"#62BF55",
						},
						{
							0.8,
							"#4FB6F2",
						},
						{
							1,
							"#B07CFF",
						},
					},
					EmissionDirection = "Bottom",
					Drag = 0.4,
					Lifetime = {
						3,
						4,
					},
					LightEmission = 0.2,
					LightInfluence = 0.6,
					Rate = 3,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-180,
						180,
					},
					Size = 0.4,
					Speed = {
						0.2,
						0.5,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					1.5,
					0,
				},
				box = {
					18,
					1,
					12,
				},
				tinted = true,
				nightGlow = 0,
				sprite = "confetti",
				filled = {
					"night",
					"transparency",
				},
			},
			{
				id = "e3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF1C9",
					Lifetime = {
						2,
						2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 0.5,
					Size = 6,
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
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0.5,
					-0.3,
				},
				tinted = true,
				nightGlow = 1,
				sprite = "glow",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Landmarks",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Landmarks",
			key = "showStage",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Landmarks.skyGate",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#BFE3FF",
					EmissionDirection = "Front",
					Lifetime = {
						3,
						3,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					Rate = 0.45,
					RotSpeed = {
						50,
						80,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.25,
							4.2,
						},
						{
							1,
							4.6,
						},
					},
					Speed = 0.02,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.25,
							0.55,
						},
						{
							0.75,
							0.55,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0,
					-0.09,
				},
				tinted = true,
				nightGlow = 1,
				sprite = "swirl",
				filled = {
					"night",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#EAF6FF",
					Lifetime = {
						1.5,
						2,
					},
					LightEmission = 0.7,
					LightInfluence = 0,
					Rate = 1,
					Size = {
						{
							0,
							1,
						},
						{
							0.5,
							2.8,
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
							1,
						},
						{
							0.3,
							0.6,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0,
					-0.1,
				},
				bright = true,
				tinted = true,
				nightGlow = 1,
				sprite = "glow",
				filled = {
					"night",
				},
			},
			{
				id = "e3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFFFFF",
					Lifetime = {
						0.8,
						1.2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 3,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.7,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0,
					-0.1,
				},
				box = {
					6,
					10,
					1,
				},
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e4",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-0.5,
						0,
					},
					Color = "#E8FFF0",
					EmissionDirection = "Front",
					Drag = 0.5,
					Lifetime = {
						2.5,
						3.5,
					},
					LightEmission = 0.2,
					LightInfluence = 0.6,
					Rate = 1.2,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-90,
						90,
					},
					Size = 0.5,
					Speed = {
						0.5,
						1,
					},
					SpreadAngle = {
						40,
						40,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0,
					-0.1,
				},
				box = {
					6,
					10,
					1,
				},
				tinted = true,
				nightGlow = 0,
				sprite = "leaf",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
		},
		tags = {
			"Landmarks",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Landmarks",
			key = "skyGate",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Landmarks.starAltar",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#B9A7FF",
					Lifetime = {
						3,
						3,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Orientation = "VelocityPerpendicular",
					Rate = 0.4,
					RotSpeed = {
						30,
						30,
					},
					Size = 7,
					Speed = 0.01,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.25,
							0.4,
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
				},
				anchor = {
					0,
					-0.49,
					-0.85,
				},
				tinted = true,
				nightGlow = 1,
				sprite = "rune",
				filled = {
					"night",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE9A0",
					Lifetime = {
						1.5,
						2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 4,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.6,
						},
						{
							1,
							0,
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
							1,
						},
						{
							0.1,
							0,
						},
						{
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0.5,
					0,
				},
				box = {
					10,
					1,
					10,
				},
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Landmarks",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Landmarks",
			key = "starAltar",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Landmarks.surfShack",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-20,
						0,
					},
					Lifetime = {
						0.8,
						1.1,
					},
					LightEmission = 0.2,
					LightInfluence = 0.6,
					Orientation = "VelocityParallel",
					Rate = 5,
					Size = 0.45,
					Speed = {
						4,
						6,
					},
					SpreadAngle = {
						25,
						25,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					-0.5,
					-0.6,
				},
				box = {
					14,
					1,
					3,
				},
				nightGlow = 0.4,
				sprite = "droplet",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#BFEFFF",
					Drag = 0.3,
					Lifetime = {
						2,
						3,
					},
					LightEmission = 0.2,
					LightInfluence = 0.5,
					Rate = 2,
					Size = {
						{
							0,
							0.2,
						},
						{
							0.3,
							0.5,
						},
						{
							1,
							0.6,
						},
					},
					Speed = {
						1,
						2,
					},
					SpreadAngle = {
						20,
						20,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					-0.5,
					-0.6,
				},
				box = {
					14,
					1,
					3,
				},
				tinted = true,
				nightGlow = 0.5,
				sprite = "bubble",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
		},
		tags = {
			"Landmarks",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Landmarks",
			key = "surfShack",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Landmarks.workshop",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.5,
						0.3,
						0,
					},
					Color = "#CFCFCF",
					Lifetime = {
						3,
						4,
					},
					LightEmission = 0.15,
					LightInfluence = 0.8,
					Rate = 1.5,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-20,
						20,
					},
					Size = {
						{
							0,
							1,
						},
						{
							1,
							4,
						},
					},
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
							1,
						},
						{
							0.15,
							0.5,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0.3,
					0.7,
					0.2,
				},
				tinted = true,
				nightGlow = 0,
				sprite = "puff",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-2,
						0,
					},
					Lifetime = {
						0.8,
						1.2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 2,
					Size = {
						{
							0,
							0.25,
						},
						{
							1,
							0.05,
						},
					},
					Speed = {
						2,
						4,
					},
					SpreadAngle = {
						25,
						25,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0.3,
					0.7,
					0.2,
				},
				nightGlow = 1,
				sprite = "ember",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
		},
		tags = {
			"Landmarks",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Landmarks",
			key = "workshop",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mastery.aurora",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.3,
						0,
					},
					Color = {
						{
							0,
							"#5BE3A0",
						},
						{
							0.5,
							"#6FA8FF",
						},
						{
							1,
							"#B07CFF",
						},
					},
					Lifetime = {
						2,
						2.8,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					Rate = 1,
					Rotation = {
						0,
						45,
					},
					RotSpeed = {
						-20,
						20,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.1,
						0.3,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 0.5,
				sprite = "wisp",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mastery",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mastery",
			key = "aurora",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mastery.bounty",
		kind = "loop",
		layers = {
			{
				id = "e1",
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
							"#FFD34D",
						},
						{
							1,
							"#FF4A3D",
						},
					},
					Lifetime = {
						0.9,
						1.4,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					Rate = 1.6,
					Rotation = {
						0,
						45,
					},
					RotSpeed = {
						-20,
						20,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.1,
						0.3,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 0.8,
				sprite = "star5",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mastery",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mastery",
			key = "bounty",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mastery.championsCrown",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.55,
						0,
					},
					Color = {
						{
							0,
							"#FF7AC8",
						},
						{
							0.5,
							"#F5C630",
						},
						{
							1,
							"#FF7AC8",
						},
					},
					Lifetime = {
						1.2,
						1.8,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					Rate = 1.6,
					Rotation = {
						0,
						45,
					},
					RotSpeed = {
						-20,
						20,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.1,
						0.3,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 0.8,
				sprite = "star5",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mastery",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mastery",
			key = "championsCrown",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mastery.codexCrown",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.5,
						0,
					},
					Color = {
						{
							0,
							"#8FD3FF",
						},
						{
							0.5,
							"#F2C230",
						},
						{
							1,
							"#FF7AC8",
						},
					},
					Lifetime = {
						1.2,
						1.8,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					Rate = 1.5,
					Rotation = {
						0,
						45,
					},
					RotSpeed = {
						-20,
						20,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.1,
						0.3,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 0.8,
				sprite = "star5",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mastery",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mastery",
			key = "codexCrown",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mastery.comet",
		kind = "loop",
		layers = {
			{
				id = "e1",
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
							"#FFE08A",
						},
						{
							1,
							"#FF8A3D",
						},
					},
					Lifetime = {
						1.5,
						2.2,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					Rate = 1.2,
					Rotation = {
						0,
						45,
					},
					RotSpeed = {
						-20,
						20,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.1,
						0.3,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 0.8,
				sprite = "star5",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mastery",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mastery",
			key = "comet",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mastery.gold",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.4,
						0,
					},
					Color = "#F2C230",
					Lifetime = {
						1,
						1.6,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					Rate = 1.5,
					Rotation = {
						0,
						45,
					},
					RotSpeed = {
						-20,
						20,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.1,
						0.3,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mastery",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mastery",
			key = "gold",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mastery.mythic",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.5,
						0,
					},
					Color = {
						{
							0,
							"#FF7AA2",
						},
						{
							1,
							"#E8436F",
						},
					},
					Lifetime = {
						1.2,
						1.8,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					Rate = 1.5,
					Rotation = {
						0,
						45,
					},
					RotSpeed = {
						-20,
						20,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.1,
						0.3,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 0.8,
				sprite = "star5",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mastery",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mastery",
			key = "mythic",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mastery.mythicFlame",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.6,
						0,
					},
					Color = "#FF6FA0",
					Lifetime = {
						1,
						1.6,
					},
					LightEmission = 0.3,
					LightInfluence = 0.2,
					Rate = 1.5,
					Size = {
						{
							0,
							0.3,
						},
						{
							0.3,
							0.5,
						},
						{
							1,
							0.1,
						},
					},
					Speed = {
						0.4,
						0.8,
					},
					SpreadAngle = {
						25,
						25,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "feet",
				nightGlow = 1,
				sprite = "flame",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mastery",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mastery",
			key = "mythicFlame",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mastery.starlight",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.2,
						0,
					},
					Color = "#CFE8FF",
					Lifetime = {
						1.2,
						1.8,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					Rate = 1.5,
					Rotation = {
						0,
						45,
					},
					RotSpeed = {
						-20,
						20,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.1,
						0.3,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mastery",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mastery",
			key = "starlight",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.blossom",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-0.8,
						0,
					},
					Drag = 0.6,
					Lifetime = {
						1.6,
						2.2,
					},
					LightEmission = 0.15,
					LightInfluence = 0.8,
					Rate = 1,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-120,
						120,
					},
					Size = 0.25,
					Speed = {
						0.5,
						1,
					},
					SpreadAngle = {
						80,
						80,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "head",
				nightGlow = 0,
				sprite = "petal",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "blossom",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.charged",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Lifetime = {
						0.12,
						0.2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					LockedToPart = true,
					Rate = 4,
					Rotation = {
						-40,
						40,
					},
					Shape = "Sphere",
					Size = {
						{
							0,
							0.4,
						},
						{
							1,
							0.3,
						},
					},
					Speed = 0,
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
							0.6,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 1,
				sprite = "bolt",
				filled = {
					"night",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFE14D",
					Lifetime = {
						0.5,
						0.8,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 1,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.3,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						1,
						2,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "charged",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.frosted",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-0.8,
						0,
					},
					Lifetime = {
						1.6,
						2.2,
					},
					LightEmission = 0.2,
					LightInfluence = 0.5,
					Rate = 1,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-45,
						45,
					},
					Size = 0.25,
					Speed = {
						0.2,
						0.5,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 0.6,
				sprite = "snowflake",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "frosted",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.frozen",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-0.8,
						0,
					},
					Lifetime = {
						1.5,
						2,
					},
					LightEmission = 0.2,
					LightInfluence = 0.5,
					Rate = 0.8,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-45,
						45,
					},
					Size = 0.25,
					Speed = {
						0.2,
						0.5,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 0.6,
				sprite = "snowflake",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#CFF3FF",
					Lifetime = {
						1.6,
						1.8,
					},
					LightEmission = 0.2,
					LightInfluence = 0.5,
					Rate = 0.25,
					Size = {
						{
							0,
							0.15,
						},
						{
							0.3,
							0.3,
						},
						{
							1,
							0.3,
						},
					},
					Speed = {
						0.2,
						0.4,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 0.5,
				sprite = "bubble",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "frozen",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.glow",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.4,
						0,
					},
					Color = "#FFB547",
					Lifetime = {
						1,
						1.4,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 1.5,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.35,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.2,
						0.5,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "glow",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "glow",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.pearl",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.8,
						0,
					},
					Color = "#F3EEE2",
					Lifetime = {
						1.4,
						1.8,
					},
					LightEmission = 0.2,
					LightInfluence = 0.5,
					Rate = 0.8,
					Size = {
						{
							0,
							0.12,
						},
						{
							0.3,
							0.28,
						},
						{
							1,
							0.3,
						},
					},
					Speed = {
						0.2,
						0.5,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 0.5,
				sprite = "bubble",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFFFFF",
					Lifetime = {
						0.8,
						1.1,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 0.6,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.2,
						0.5,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "pearl",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.plasma",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#C06BFF",
					Lifetime = {
						0.3,
						0.5,
					},
					LightEmission = 0.3,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#C06BFF",
					Lifetime = {
						1,
						1.4,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 1,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.2,
						0.5,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "glow",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "plasma",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.prismatic",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Lifetime = {
						0.9,
						1.2,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					Rate = 1,
					RotSpeed = {
						-40,
						40,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 1,
				sprite = "prism",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FF5A5A",
						},
						{
							0.2,
							"#FFB547",
						},
						{
							0.4,
							"#FFE14D",
						},
						{
							0.6,
							"#62BF55",
						},
						{
							0.8,
							"#4FB6F2",
						},
						{
							1,
							"#B07CFF",
						},
					},
					Lifetime = {
						0.8,
						1.1,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 0.8,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.2,
						0.5,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "prismatic",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.scorched",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#5A4A42",
					Lifetime = {
						1.4,
						2,
					},
					LightEmission = 0.15,
					LightInfluence = 0.6,
					Rate = 0.8,
					Rotation = {
						0,
						360,
					},
					Size = {
						{
							0,
							0.3,
						},
						{
							1,
							1.1,
						},
					},
					Speed = {
						0.8,
						1.4,
					},
					SpreadAngle = {
						15,
						15,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.5,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "head",
				tinted = true,
				nightGlow = 0,
				sprite = "puff",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						2,
						0,
					},
					Lifetime = {
						0.8,
						1.1,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 0.5,
					Size = {
						{
							0,
							0.14,
						},
						{
							1,
							0.04,
						},
					},
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
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 1,
				sprite = "ember",
				filled = {
					"night",
					"transparency",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "scorched",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.shadow",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.4,
						0,
					},
					Color = "#3A2D55",
					Drag = 0.4,
					Lifetime = {
						1.6,
						2.2,
					},
					LightEmission = 0.15,
					LightInfluence = 0.3,
					Rate = 1,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-25,
						25,
					},
					Size = {
						{
							0,
							0.5,
						},
						{
							1,
							1.3,
						},
					},
					Speed = {
						0.5,
						1,
					},
					SpreadAngle = {
						25,
						25,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.35,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "feet",
				tinted = true,
				nightGlow = 0.5,
				sprite = "wisp",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "shadow",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.soaked",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-12,
						0,
					},
					Lifetime = {
						0.6,
						0.9,
					},
					LightEmission = 0.2,
					LightInfluence = 0.6,
					Orientation = "VelocityParallel",
					Rate = 1.5,
					Size = 0.22,
					Speed = 0,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				nightGlow = 0.4,
				sprite = "droplet",
				filled = {
					"night",
					"transparency",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "soaked",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.starstruck",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Lifetime = {
						1,
						1.4,
					},
					LightEmission = 0.25,
					LightInfluence = 0.2,
					Rate = 0.8,
					RotSpeed = {
						-60,
						60,
					},
					Size = {
						{
							0,
							0.1,
						},
						{
							0.3,
							0.35,
						},
						{
							1,
							0.1,
						},
					},
					Speed = {
						0.4,
						0.8,
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
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "head",
				nightGlow = 0.8,
				sprite = "star5",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFF6D6",
					Lifetime = {
						0.8,
						1.1,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 0.8,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.2,
						0.5,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "starstruck",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.sunkissed",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFB347",
					Lifetime = {
						1.6,
						2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					LockedToPart = true,
					Rate = 0.5,
					Size = {
						{
							0,
							1.4,
						},
						{
							0.3,
							2,
						},
						{
							1,
							2.3,
						},
					},
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
							1,
							1,
						},
					},
				},
				anchor = "core",
				tinted = true,
				nightGlow = 1,
				sprite = "glow",
				filled = {
					"night",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFD08A",
					Lifetime = {
						0.8,
						1.1,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 1,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.2,
						0.5,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "sunkissed",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Mutations.tropical",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-0.8,
						0,
					},
					Drag = 0.6,
					Lifetime = {
						1.6,
						2.2,
					},
					LightEmission = 0.15,
					LightInfluence = 0.8,
					Rate = 0.6,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-120,
						120,
					},
					Size = 0.25,
					Speed = {
						0.5,
						1,
					},
					SpreadAngle = {
						80,
						80,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "head",
				nightGlow = 0,
				sprite = "petal",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-12,
						0,
					},
					Color = "#2EC4B6",
					Lifetime = {
						0.6,
						0.8,
					},
					LightEmission = 0.2,
					LightInfluence = 0.6,
					Orientation = "VelocityParallel",
					Rate = 1,
					Size = 0.2,
					Speed = 0,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 0.4,
				sprite = "droplet",
				filled = {
					"night",
					"transparency",
				},
			},
		},
		tags = {
			"Mutations",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Mutations",
			key = "tropical",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Rarity.epic",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#A259E0",
					Lifetime = {
						2,
						2,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					LockedToPart = true,
					Orientation = "VelocityPerpendicular",
					Rate = 0.5,
					Size = {
						{
							0,
							2.6,
						},
						{
							1,
							3,
						},
					},
					Speed = 0.01,
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
							1,
							1,
						},
					},
				},
				anchor = "feet",
				tinted = true,
				nightGlow = 1,
				offset = {
					0,
					0.15,
					0,
				},
				sprite = "glow",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Rarity",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Rarity",
			key = "epic",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Rarity.legendary",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E99A10",
					Lifetime = {
						2,
						2,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					LockedToPart = true,
					Orientation = "VelocityPerpendicular",
					Rate = 0.5,
					Size = {
						{
							0,
							2.6,
						},
						{
							1,
							3,
						},
					},
					Speed = 0.01,
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
							1,
							1,
						},
					},
				},
				anchor = "feet",
				tinted = true,
				nightGlow = 1,
				offset = {
					0,
					0.15,
					0,
				},
				sprite = "glow",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Rarity",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Rarity",
			key = "legendary",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Rarity.mythic",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E8436F",
					Lifetime = {
						2,
						2,
					},
					LightEmission = 0.25,
					LightInfluence = 0,
					LockedToPart = true,
					Orientation = "VelocityPerpendicular",
					Rate = 0.5,
					Size = {
						{
							0,
							2.6,
						},
						{
							1,
							3,
						},
					},
					Speed = 0.01,
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
							1,
							1,
						},
					},
				},
				anchor = "feet",
				tinted = true,
				nightGlow = 1,
				offset = {
					0,
					0.15,
					0,
				},
				sprite = "glow",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Rarity",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Rarity",
			key = "mythic",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Scenery.campfire",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						1,
						0,
					},
					Lifetime = {
						0.5,
						0.8,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 7,
					Rotation = {
						-10,
						10,
					},
					Size = {
						{
							0,
							0.6,
						},
						{
							0.3,
							1.3,
						},
						{
							1,
							0.2,
						},
					},
					Speed = {
						2,
						3,
					},
					SpreadAngle = {
						10,
						10,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0,
						},
						{
							0.75,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					-0.15,
					0,
				},
				box = {
					1,
					0.3,
					1,
				},
				nightGlow = 1,
				sprite = "flame",
				filled = {
					"night",
					"spread",
					"transparency",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.6,
						0.5,
						0.3,
					},
					Lifetime = {
						1.2,
						1.8,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 3,
					RotSpeed = {
						-90,
						90,
					},
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
						3,
						5,
					},
					SpreadAngle = {
						25,
						25,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					-0.1,
					0,
				},
				box = {
					1.2,
					0.3,
					1.2,
				},
				nightGlow = 1,
				sprite = "ember",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0.8,
						0.3,
						0.4,
					},
					Color = "#9A9A9A",
					Drag = 0.3,
					Lifetime = {
						3,
						4,
					},
					LightEmission = 0.15,
					LightInfluence = 1,
					Rate = 1.5,
					Rotation = {
						0,
						360,
					},
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
							3.2,
						},
					},
					Speed = {
						2,
						2.5,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.55,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0.15,
					0,
				},
				box = {
					0.8,
					0.2,
					0.8,
				},
				tinted = true,
				nightGlow = 0,
				sprite = "puff",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Scenery",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Scenery",
			key = "campfire",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Scenery.fountain",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-24,
						0,
					},
					Color = "#CFEFFF",
					Lifetime = {
						0.9,
						1.1,
					},
					LightEmission = 0.2,
					LightInfluence = 0.6,
					Orientation = "VelocityParallel",
					Rate = 16,
					Size = {
						{
							0,
							0.35,
						},
						{
							1,
							0.2,
						},
					},
					Speed = {
						10,
						12,
					},
					SpreadAngle = {
						8,
						8,
					},
					Transparency = {
						{
							0,
							0.6,
						},
						{
							0.1,
							0.1,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0.5,
					0,
				},
				box = {
					0.8,
					0.2,
					0.8,
				},
				tinted = true,
				nightGlow = 0.4,
				host = "BowlWater",
				sprite = "droplet",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						-30,
						0,
					},
					Color = "#BFE9FF",
					Lifetime = {
						0.6,
						0.7,
					},
					LightEmission = 0.2,
					LightInfluence = 0.6,
					Orientation = "VelocityParallel",
					Rate = 18,
					Shape = "Cylinder",
					ShapeInOut = "Outward",
					ShapeStyle = "Surface",
					Size = 0.3,
					Speed = {
						1,
						1.5,
					},
					Transparency = {
						{
							0,
							0.5,
						},
						{
							0.1,
							0.15,
						},
						{
							1,
							0.6,
						},
					},
				},
				anchor = {
					0,
					0,
					0,
				},
				box = {
					7.2,
					0.2,
					7.2,
				},
				tinted = true,
				nightGlow = 0.4,
				host = "BowlWater",
				sprite = "droplet",
				filled = {
					"night",
				},
			},
			{
				id = "e3",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E6F7FF",
					Lifetime = {
						1.6,
						1.6,
					},
					LightEmission = 0.2,
					LightInfluence = 0.5,
					Orientation = "VelocityPerpendicular",
					Rate = 1.2,
					Size = {
						{
							0,
							1,
						},
						{
							1,
							5,
						},
					},
					Speed = 0.02,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.15,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0.5,
					0,
				},
				box = {
					18,
					0.1,
					18,
				},
				tinted = true,
				nightGlow = 0.8,
				host = "Water",
				sprite = "ring",
				filled = {
					"night",
				},
			},
			{
				id = "e4",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E8F7FF",
					Lifetime = {
						1.5,
						2.2,
					},
					LightEmission = 0.15,
					LightInfluence = 1,
					Rate = 3,
					RotSpeed = {
						-20,
						20,
					},
					Shape = "Cylinder",
					ShapeStyle = "Surface",
					Size = {
						{
							0,
							1,
						},
						{
							1,
							2.5,
						},
					},
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
							0.3,
							0.75,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0.5,
					0,
				},
				box = {
					8,
					0.2,
					8,
				},
				tinted = true,
				nightGlow = 0,
				host = "Water",
				sprite = "puff",
				filled = {
					"night",
				},
			},
		},
		tags = {
			"Scenery",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Scenery",
			key = "fountain",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Scenery.windmill",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						3,
						-0.4,
						1.5,
					},
					Color = "#9BCB6A",
					Lifetime = {
						4,
						6,
					},
					LightEmission = 0.15,
					LightInfluence = 1,
					Rate = 0.8,
					Rotation = {
						0,
						360,
					},
					RotSpeed = {
						-120,
						120,
					},
					Size = 0.5,
					Speed = {
						1,
						2,
					},
					SpreadAngle = {
						180,
						180,
					},
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0.22,
					0,
				},
				box = {
					10,
					6,
					10,
				},
				tinted = true,
				nightGlow = 0,
				sprite = "leaf",
				filled = {
					"night",
					"spread",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						1.5,
						0.2,
						0.6,
					},
					Color = "#F4E7C8",
					Lifetime = {
						3,
						4,
					},
					LightEmission = 0.2,
					LightInfluence = 1,
					Rate = 1.2,
					Size = 0.3,
					Speed = {
						0.3,
						0.6,
					},
					SpreadAngle = {
						180,
						180,
					},
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
							1,
							1,
						},
					},
				},
				anchor = {
					0,
					0,
					0,
				},
				box = {
					12,
					8,
					12,
				},
				tinted = true,
				nightGlow = 0,
				sprite = "puff",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Scenery",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Scenery",
			key = "windmill",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Titanic",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#E8436F",
					Lifetime = {
						2.2,
						2.6,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					LockedToPart = true,
					Orientation = "VelocityPerpendicular",
					Rate = 0.6,
					Size = {
						{
							0,
							1.2,
						},
						{
							1,
							3.4,
						},
					},
					Speed = 0.01,
					Transparency = {
						{
							0,
							1,
						},
						{
							0.2,
							0.4,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "feet",
				tinted = true,
				nightGlow = 0.8,
				offset = {
					0,
					0.1,
					0,
				},
				sprite = "ring",
				filled = {
					"night",
				},
			},
			{
				id = "e2",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Acceleration = {
						0,
						0.8,
						0,
					},
					Color = {
						{
							0,
							"#FFD447",
						},
						{
							1,
							"#E8436F",
						},
					},
					Lifetime = {
						1,
						1.4,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 1.5,
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
						},
						{
							1,
							0,
						},
					},
					Speed = {
						0.2,
						0.5,
					},
					SpreadAngle = {
						180,
						180,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 0.8,
				sprite = "star5",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Titanic",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Titanic",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Variants.rainbow",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = {
						{
							0,
							"#FF5A5A",
						},
						{
							0.2,
							"#FFB547",
						},
						{
							0.4,
							"#FFE14D",
						},
						{
							0.6,
							"#62BF55",
						},
						{
							0.8,
							"#4FB6F2",
						},
						{
							1,
							"#B07CFF",
						},
					},
					Lifetime = {
						0.8,
						1.2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 2,
					Rotation = {
						0,
						45,
					},
					RotSpeed = {
						-30,
						30,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Variants",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Variants",
			key = "rainbow",
		},
	},
	{
		schema = "foundry.effect/1",
		id = "Variants.shiny",
		kind = "loop",
		layers = {
			{
				id = "e1",
				kind = "emitter",
				at = 0,
				duration = 0,
				props = {
					Color = "#FFD447",
					Lifetime = {
						0.8,
						1.2,
					},
					LightEmission = 0.3,
					LightInfluence = 0,
					Rate = 2,
					Rotation = {
						0,
						45,
					},
					RotSpeed = {
						-30,
						30,
					},
					Size = {
						{
							0,
							0,
						},
						{
							0.3,
							0.4,
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
							0.7,
							0.2,
						},
						{
							1,
							1,
						},
					},
				},
				anchor = "body",
				tinted = true,
				nightGlow = 1,
				sprite = "star",
				filled = {
					"night",
					"spread",
				},
			},
		},
		tags = {
			"Variants",
		},
		source = {
			game = "monster-ranch",
			path = "C:/Users/sim/Documents/foundry-mirrors/monster-ranch/monster-ranch-idle/src/shared/Config/Vfx.luau",
			format = "specsets",
			table = "Variants",
			key = "shiny",
		},
	},
}
