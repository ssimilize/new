--!nonstrict
-- part of guildhall (see init.luau); generated with it, do not edit
return {
	{
		ease = "sineInOut",
		format = "motion.clip/1",
		id = "sit.up",
		length = 1,
		loop = false,
		markers = {
			{
				name = "rise",
				t = 0.6,
			},
		},
		meta = {
			file = "AnimLibrary/Config.luau",
			source = "guildhall",
		},
		priority = "Action",
		rig = "r15",
		tracks = {
			{
				joint = "LeftElbow",
				keys = {
					{
						t = 0,
						value = {
							rx = 40,
						},
					},
					{
						ease = "quadIn",
						t = 0.3,
						value = {
							rx = 30,
						},
					},
					{
						ease = "quadOut",
						t = 0.6,
						value = {
							rx = 20,
						},
					},
					{
						t = 0.82,
						value = {},
					},
					{
						t = 1,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftHip",
				keys = {
					{
						t = 0,
						value = {
							rx = 90,
							rz = -4,
						},
					},
					{
						ease = "quadIn",
						t = 0.3,
						value = {
							rx = 90,
							rz = -4,
						},
					},
					{
						ease = "quadOut",
						t = 0.6,
						value = {
							rx = 45,
							rz = -2,
						},
					},
					{
						t = 0.82,
						value = {
							rx = -2,
						},
					},
					{
						t = 1,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftKnee",
				keys = {
					{
						t = 0,
						value = {
							rx = -90,
						},
					},
					{
						ease = "quadIn",
						t = 0.3,
						value = {
							rx = -90,
						},
					},
					{
						ease = "quadOut",
						t = 0.6,
						value = {
							rx = -50,
						},
					},
					{
						t = 0.82,
						value = {},
					},
					{
						t = 1,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftShoulder",
				keys = {
					{
						t = 0,
						value = {
							rx = 30,
							rz = -4,
						},
					},
					{
						ease = "quadIn",
						t = 0.3,
						value = {
							rx = 40,
							rz = -4,
						},
					},
					{
						ease = "quadOut",
						t = 0.6,
						value = {
							rx = 20,
							rz = -6,
						},
					},
					{
						t = 0.82,
						value = {
							rz = -3,
						},
					},
					{
						t = 1,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "Neck",
				keys = {
					{
						t = 0,
						value = {
							rx = 0,
						},
					},
					{
						ease = "quadIn",
						t = 0.3,
						value = {
							rx = 8,
						},
					},
					{
						ease = "quadOut",
						t = 0.6,
						value = {
							rx = 4,
						},
					},
					{
						t = 0.82,
						value = {
							rx = 2,
						},
					},
					{
						t = 1,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightElbow",
				keys = {
					{
						t = 0,
						value = {
							rx = 40,
						},
					},
					{
						ease = "quadIn",
						t = 0.3,
						value = {
							rx = 30,
						},
					},
					{
						ease = "quadOut",
						t = 0.6,
						value = {
							rx = 20,
						},
					},
					{
						t = 0.82,
						value = {},
					},
					{
						t = 1,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightHip",
				keys = {
					{
						t = 0,
						value = {
							rx = 90,
							rz = 4,
						},
					},
					{
						ease = "quadIn",
						t = 0.3,
						value = {
							rx = 90,
							rz = 4,
						},
					},
					{
						ease = "quadOut",
						t = 0.6,
						value = {
							rx = 45,
							rz = 2,
						},
					},
					{
						t = 0.82,
						value = {
							rx = -2,
						},
					},
					{
						t = 1,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightKnee",
				keys = {
					{
						t = 0,
						value = {
							rx = -90,
						},
					},
					{
						ease = "quadIn",
						t = 0.3,
						value = {
							rx = -90,
						},
					},
					{
						ease = "quadOut",
						t = 0.6,
						value = {
							rx = -50,
						},
					},
					{
						t = 0.82,
						value = {},
					},
					{
						t = 1,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightShoulder",
				keys = {
					{
						t = 0,
						value = {
							rx = 30,
							rz = 4,
						},
					},
					{
						ease = "quadIn",
						t = 0.3,
						value = {
							rx = 40,
							rz = 4,
						},
					},
					{
						ease = "quadOut",
						t = 0.6,
						value = {
							rx = 20,
							rz = 6,
						},
					},
					{
						t = 0.82,
						value = {
							rz = 3,
						},
					},
					{
						t = 1,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "Root",
				keys = {
					{
						t = 0,
						value = {
							y = -1,
						},
					},
					{
						ease = "quadIn",
						t = 0.3,
						value = {
							y = -0.98,
						},
					},
					{
						ease = "quadOut",
						t = 0.6,
						value = {
							y = -0.35,
						},
					},
					{
						t = 0.82,
						value = {
							y = 0.04,
						},
					},
					{
						t = 1,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "Waist",
				keys = {
					{
						t = 0,
						value = {
							rx = -4,
						},
					},
					{
						ease = "quadIn",
						t = 0.3,
						value = {
							rx = -28,
						},
					},
					{
						ease = "quadOut",
						t = 0.6,
						value = {
							rx = -18,
						},
					},
					{
						t = 0.82,
						value = {
							rx = 4,
						},
					},
					{
						t = 1,
						value = {},
					},
				},
				kind = "pose",
			},
		},
	},
	{
		ease = "sineInOut",
		format = "motion.clip/1",
		id = "door.enter",
		length = 1.3,
		loop = false,
		markers = {
			{
				name = "push",
				t = 0.45,
			},
			{
				name = "inside",
				t = 1.2,
			},
		},
		meta = {
			file = "AnimLibrary/Config.luau",
			source = "guildhall",
		},
		priority = "Action",
		rig = "r15",
		tracks = {
			{
				joint = "LeftHip",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.2,
						value = {},
					},
					{
						ease = "quadOut",
						t = 0.45,
						value = {
							rx = -15,
						},
					},
					{
						t = 0.75,
						value = {
							rx = 25,
						},
					},
					{
						t = 1.05,
						value = {
							rx = -12,
						},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftKnee",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.2,
						value = {},
					},
					{
						ease = "quadOut",
						t = 0.45,
						value = {
							rx = -20,
						},
					},
					{
						t = 0.75,
						value = {
							rx = -10,
						},
					},
					{
						t = 1.05,
						value = {
							rx = -22,
						},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftShoulder",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.2,
						value = {},
					},
					{
						ease = "quadOut",
						t = 0.45,
						value = {},
					},
					{
						t = 0.75,
						value = {
							rx = 15,
							rz = -4,
						},
					},
					{
						t = 1.05,
						value = {
							rx = 12,
							rz = -4,
						},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "Neck",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.2,
						value = {
							rx = 8,
						},
					},
					{
						ease = "quadOut",
						t = 0.45,
						value = {
							rx = -4,
						},
					},
					{
						t = 0.75,
						value = {
							rx = -12,
						},
					},
					{
						t = 1.05,
						value = {
							rx = -6,
						},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightElbow",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.2,
						value = {
							rx = 40,
						},
					},
					{
						ease = "quadOut",
						t = 0.45,
						value = {
							rx = 15,
						},
					},
					{
						t = 0.75,
						value = {
							rx = 30,
						},
					},
					{
						t = 1.05,
						value = {},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightHip",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.2,
						value = {},
					},
					{
						ease = "quadOut",
						t = 0.45,
						value = {
							rx = 25,
						},
					},
					{
						t = 0.75,
						value = {
							rx = -15,
						},
					},
					{
						t = 1.05,
						value = {
							rx = 20,
						},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightKnee",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.2,
						value = {},
					},
					{
						ease = "quadOut",
						t = 0.45,
						value = {
							rx = -10,
						},
					},
					{
						t = 0.75,
						value = {
							rx = -25,
						},
					},
					{
						t = 1.05,
						value = {
							rx = -8,
						},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightShoulder",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.2,
						value = {
							rx = 20,
							rz = 6,
						},
					},
					{
						ease = "quadOut",
						t = 0.45,
						value = {
							rx = 72,
							rz = 5,
						},
					},
					{
						t = 0.75,
						value = {
							rx = 20,
							rz = 4,
						},
					},
					{
						t = 1.05,
						value = {
							rx = -10,
							rz = 4,
						},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "Root",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.2,
						value = {},
					},
					{
						ease = "quadOut",
						t = 0.45,
						value = {
							y = 0.05,
							z = -0.35,
						},
					},
					{
						t = 0.75,
						value = {
							y = -0.08,
							z = -0.9,
						},
					},
					{
						t = 1.05,
						value = {
							y = 0.02,
							z = -1.4,
						},
					},
					{
						t = 1.3,
						value = {
							z = -1.8,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Waist",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.2,
						value = {},
					},
					{
						ease = "quadOut",
						t = 0.45,
						value = {
							rx = -8,
						},
					},
					{
						t = 0.75,
						value = {
							rx = -18,
						},
					},
					{
						t = 1.05,
						value = {
							rx = -10,
						},
					},
					{
						t = 1.3,
						value = {
							rx = -4,
						},
					},
				},
				kind = "pose",
			},
		},
	},
	{
		ease = "sineInOut",
		format = "motion.clip/1",
		id = "door.exit",
		length = 1.3,
		loop = false,
		markers = {
			{
				name = "appear",
				t = 0.05,
			},
			{
				name = "footstep",
				t = 0.7,
			},
		},
		meta = {
			file = "AnimLibrary/Config.luau",
			source = "guildhall",
		},
		priority = "Action",
		rig = "r15",
		tracks = {
			{
				joint = "LeftHip",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.35,
						value = {
							rx = 25,
						},
					},
					{
						ease = "quadOut",
						t = 0.7,
						value = {
							rx = -12,
						},
					},
					{
						t = 0.95,
						value = {},
					},
					{
						t = 1.15,
						value = {},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftKnee",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.35,
						value = {
							rx = -10,
						},
					},
					{
						ease = "quadOut",
						t = 0.7,
						value = {
							rx = -20,
						},
					},
					{
						t = 0.95,
						value = {},
					},
					{
						t = 1.15,
						value = {},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftShoulder",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.35,
						value = {
							rx = -15,
							rz = -4,
						},
					},
					{
						ease = "quadOut",
						t = 0.7,
						value = {
							rx = 15,
							rz = -4,
						},
					},
					{
						t = 0.95,
						value = {},
					},
					{
						t = 1.15,
						value = {},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "Neck",
				keys = {
					{
						t = 0,
						value = {
							rx = -10,
						},
					},
					{
						t = 0.35,
						value = {
							rx = -6,
						},
					},
					{
						ease = "quadOut",
						t = 0.7,
						value = {
							rx = 4,
						},
					},
					{
						t = 0.95,
						value = {
							rx = 6,
							ry = 20,
						},
					},
					{
						t = 1.15,
						value = {
							rx = 3,
							ry = -14,
						},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightHip",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.35,
						value = {
							rx = -15,
						},
					},
					{
						ease = "quadOut",
						t = 0.7,
						value = {
							rx = 22,
						},
					},
					{
						t = 0.95,
						value = {},
					},
					{
						t = 1.15,
						value = {},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightKnee",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.35,
						value = {
							rx = -22,
						},
					},
					{
						ease = "quadOut",
						t = 0.7,
						value = {
							rx = -8,
						},
					},
					{
						t = 0.95,
						value = {},
					},
					{
						t = 1.15,
						value = {},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightShoulder",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.35,
						value = {
							rx = 15,
							rz = 4,
						},
					},
					{
						ease = "quadOut",
						t = 0.7,
						value = {
							rx = -15,
							rz = 4,
						},
					},
					{
						t = 0.95,
						value = {},
					},
					{
						t = 1.15,
						value = {},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "Root",
				keys = {
					{
						t = 0,
						value = {
							y = -0.05,
							z = 1.6,
						},
					},
					{
						t = 0.35,
						value = {
							y = 0.03,
							z = 1,
						},
					},
					{
						ease = "quadOut",
						t = 0.7,
						value = {
							y = 0,
							z = 0.35,
						},
					},
					{
						t = 0.95,
						value = {
							y = 0.03,
						},
					},
					{
						t = 1.15,
						value = {},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "Waist",
				keys = {
					{
						t = 0,
						value = {
							rx = -12,
						},
					},
					{
						t = 0.35,
						value = {
							rx = -10,
						},
					},
					{
						ease = "quadOut",
						t = 0.7,
						value = {
							rx = -3,
						},
					},
					{
						t = 0.95,
						value = {
							ry = 6,
						},
					},
					{
						t = 1.15,
						value = {
							ry = -3,
						},
					},
					{
						t = 1.3,
						value = {},
					},
				},
				kind = "pose",
			},
		},
	},
	{
		ease = "sineInOut",
		format = "motion.clip/1",
		id = "walk.tired",
		length = 1.3,
		loop = true,
		markers = {
			{
				name = "footstep",
				t = 0,
			},
			{
				name = "footstep",
				t = 0.65,
			},
		},
		meta = {
			file = "AnimLibrary/Config.luau",
			source = "guildhall",
		},
		priority = "Movement",
		rig = "r15",
		tracks = {
			{
				joint = "LeftAnkle",
				keys = {
					{
						ease = "quadOut",
						t = 0,
						value = {
							rx = 8,
						},
					},
					{
						t = 0.325,
						value = {
							rx = 12,
						},
					},
					{
						ease = "quadOut",
						t = 0.65,
						value = {
							rx = -4,
						},
					},
					{
						t = 0.975,
						value = {
							rx = 0,
						},
					},
					{
						t = 1.3,
						value = {
							rx = 8,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftElbow",
				keys = {
					{
						ease = "quadOut",
						t = 0,
						value = {
							rx = 8,
						},
					},
					{
						t = 0.325,
						value = {
							rx = 6,
						},
					},
					{
						ease = "quadOut",
						t = 0.65,
						value = {
							rx = 4,
						},
					},
					{
						t = 0.975,
						value = {
							rx = 6,
						},
					},
					{
						t = 1.3,
						value = {
							rx = 8,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftHip",
				keys = {
					{
						ease = "quadOut",
						t = 0,
						value = {
							rx = -12,
						},
					},
					{
						t = 0.325,
						value = {
							rx = 8,
						},
					},
					{
						ease = "quadOut",
						t = 0.65,
						value = {
							rx = 15,
						},
					},
					{
						t = 0.975,
						value = {
							rx = 0,
						},
					},
					{
						t = 1.3,
						value = {
							rx = -12,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftKnee",
				keys = {
					{
						ease = "quadOut",
						t = 0,
						value = {
							rx = -16,
						},
					},
					{
						t = 0.325,
						value = {
							rx = -30,
						},
					},
					{
						ease = "quadOut",
						t = 0.65,
						value = {
							rx = -8,
						},
					},
					{
						t = 0.975,
						value = {
							rx = -6,
						},
					},
					{
						t = 1.3,
						value = {
							rx = -16,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftShoulder",
				keys = {
					{
						ease = "quadOut",
						t = 0,
						value = {
							rx = 6,
							rz = -3,
						},
					},
					{
						t = 0.325,
						value = {
							rz = -3,
						},
					},
					{
						ease = "quadOut",
						t = 0.65,
						value = {
							rx = -6,
							rz = -3,
						},
					},
					{
						t = 0.975,
						value = {
							rz = -3,
						},
					},
					{
						t = 1.3,
						value = {
							rx = 6,
							rz = -3,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Neck",
				keys = {
					{
						ease = "quadOut",
						t = 0,
						value = {
							rx = -14,
						},
					},
					{
						t = 0.325,
						value = {
							rx = -12,
						},
					},
					{
						ease = "quadOut",
						t = 0.65,
						value = {
							rx = -14,
						},
					},
					{
						t = 0.975,
						value = {
							rx = -12,
						},
					},
					{
						t = 1.3,
						value = {
							rx = -14,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightAnkle",
				keys = {
					{
						ease = "quadOut",
						t = 0,
						value = {
							rx = -4,
						},
					},
					{
						t = 0.325,
						value = {
							rx = 0,
						},
					},
					{
						ease = "quadOut",
						t = 0.65,
						value = {
							rx = 8,
						},
					},
					{
						t = 0.975,
						value = {
							rx = 12,
						},
					},
					{
						t = 1.3,
						value = {
							rx = -4,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightElbow",
				keys = {
					{
						ease = "quadOut",
						t = 0,
						value = {
							rx = 4,
						},
					},
					{
						t = 0.325,
						value = {
							rx = 6,
						},
					},
					{
						ease = "quadOut",
						t = 0.65,
						value = {
							rx = 8,
						},
					},
					{
						t = 0.975,
						value = {
							rx = 6,
						},
					},
					{
						t = 1.3,
						value = {
							rx = 4,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightHip",
				keys = {
					{
						ease = "quadOut",
						t = 0,
						value = {
							rx = 15,
						},
					},
					{
						t = 0.325,
						value = {
							rx = 0,
						},
					},
					{
						ease = "quadOut",
						t = 0.65,
						value = {
							rx = -12,
						},
					},
					{
						t = 0.975,
						value = {
							rx = 8,
						},
					},
					{
						t = 1.3,
						value = {
							rx = 15,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightKnee",
				keys = {
					{
						ease = "quadOut",
						t = 0,
						value = {
							rx = -8,
						},
					},
					{
						t = 0.325,
						value = {
							rx = -6,
						},
					},
					{
						ease = "quadOut",
						t = 0.65,
						value = {
							rx = -16,
						},
					},
					{
						t = 0.975,
						value = {
							rx = -30,
						},
					},
					{
						t = 1.3,
						value = {
							rx = -8,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightShoulder",
				keys = {
					{
						ease = "quadOut",
						t = 0,
						value = {
							rx = -6,
							rz = 3,
						},
					},
					{
						t = 0.325,
						value = {
							rz = 3,
						},
					},
					{
						ease = "quadOut",
						t = 0.65,
						value = {
							rx = 6,
							rz = 3,
						},
					},
					{
						t = 0.975,
						value = {
							rz = 3,
						},
					},
					{
						t = 1.3,
						value = {
							rx = -6,
							rz = 3,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Root",
				keys = {
					{
						ease = "quadOut",
						t = 0,
						value = {
							y = -0.12,
						},
					},
					{
						t = 0.325,
						value = {
							y = -0.04,
						},
					},
					{
						ease = "quadOut",
						t = 0.65,
						value = {
							y = -0.12,
						},
					},
					{
						t = 0.975,
						value = {
							y = -0.04,
						},
					},
					{
						t = 1.3,
						value = {
							y = -0.12,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Waist",
				keys = {
					{
						ease = "quadOut",
						t = 0,
						value = {
							rx = -14,
							ry = -3,
							rz = 2,
						},
					},
					{
						t = 0.325,
						value = {
							rx = -12,
						},
					},
					{
						ease = "quadOut",
						t = 0.65,
						value = {
							rx = -14,
							ry = 3,
							rz = -2,
						},
					},
					{
						t = 0.975,
						value = {
							rx = -12,
						},
					},
					{
						t = 1.3,
						value = {
							rx = -14,
							ry = -3,
							rz = 2,
						},
					},
				},
				kind = "pose",
			},
		},
	},
	{
		ease = "sineInOut",
		format = "motion.clip/1",
		id = "walk.proud",
		length = 0.95,
		loop = true,
		markers = {
			{
				name = "footstep",
				t = 0,
			},
			{
				name = "footstep",
				t = 0.475,
			},
		},
		meta = {
			file = "AnimLibrary/Config.luau",
			source = "guildhall",
		},
		priority = "Movement",
		rig = "r15",
		tracks = {
			{
				joint = "LeftAnkle",
				keys = {
					{
						t = 0,
						value = {
							rx = 12,
						},
					},
					{
						t = 0.2375,
						value = {
							rx = 10,
						},
					},
					{
						t = 0.475,
						value = {
							rx = -12,
						},
					},
					{
						t = 0.7125,
						value = {
							rx = 4,
						},
					},
					{
						t = 0.95,
						value = {
							rx = 12,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftElbow",
				keys = {
					{
						t = 0,
						value = {
							rx = 16,
						},
					},
					{
						t = 0.2375,
						value = {
							rx = 10,
						},
					},
					{
						t = 0.475,
						value = {
							rx = 6,
						},
					},
					{
						t = 0.7125,
						value = {
							rx = 10,
						},
					},
					{
						t = 0.95,
						value = {
							rx = 16,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftHip",
				keys = {
					{
						t = 0,
						value = {
							rx = -24,
						},
					},
					{
						t = 0.2375,
						value = {
							rx = 14,
						},
					},
					{
						t = 0.475,
						value = {
							rx = 26,
						},
					},
					{
						t = 0.7125,
						value = {
							rx = 0,
						},
					},
					{
						t = 0.95,
						value = {
							rx = -24,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftKnee",
				keys = {
					{
						t = 0,
						value = {
							rx = -16,
						},
					},
					{
						t = 0.2375,
						value = {
							rx = -48,
						},
					},
					{
						t = 0.475,
						value = {
							rx = -4,
						},
					},
					{
						t = 0.7125,
						value = {
							rx = -4,
						},
					},
					{
						t = 0.95,
						value = {
							rx = -16,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftShoulder",
				keys = {
					{
						t = 0,
						value = {
							rx = 30,
							rz = -6,
						},
					},
					{
						t = 0.2375,
						value = {
							rz = -6,
						},
					},
					{
						t = 0.475,
						value = {
							rx = -30,
							rz = -6,
						},
					},
					{
						t = 0.7125,
						value = {
							rz = -6,
						},
					},
					{
						t = 0.95,
						value = {
							rx = 30,
							rz = -6,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Neck",
				keys = {
					{
						t = 0,
						value = {
							rx = 6,
						},
					},
					{
						t = 0.2375,
						value = {
							rx = 7,
						},
					},
					{
						t = 0.475,
						value = {
							rx = 6,
						},
					},
					{
						t = 0.7125,
						value = {
							rx = 7,
						},
					},
					{
						t = 0.95,
						value = {
							rx = 6,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightAnkle",
				keys = {
					{
						t = 0,
						value = {
							rx = -12,
						},
					},
					{
						t = 0.2375,
						value = {
							rx = 4,
						},
					},
					{
						t = 0.475,
						value = {
							rx = 12,
						},
					},
					{
						t = 0.7125,
						value = {
							rx = 10,
						},
					},
					{
						t = 0.95,
						value = {
							rx = -12,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightElbow",
				keys = {
					{
						t = 0,
						value = {
							rx = 6,
						},
					},
					{
						t = 0.2375,
						value = {
							rx = 10,
						},
					},
					{
						t = 0.475,
						value = {
							rx = 16,
						},
					},
					{
						t = 0.7125,
						value = {
							rx = 10,
						},
					},
					{
						t = 0.95,
						value = {
							rx = 6,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightHip",
				keys = {
					{
						t = 0,
						value = {
							rx = 26,
						},
					},
					{
						t = 0.2375,
						value = {
							rx = 0,
						},
					},
					{
						t = 0.475,
						value = {
							rx = -24,
						},
					},
					{
						t = 0.7125,
						value = {
							rx = 14,
						},
					},
					{
						t = 0.95,
						value = {
							rx = 26,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightKnee",
				keys = {
					{
						t = 0,
						value = {
							rx = -4,
						},
					},
					{
						t = 0.2375,
						value = {
							rx = -4,
						},
					},
					{
						t = 0.475,
						value = {
							rx = -16,
						},
					},
					{
						t = 0.7125,
						value = {
							rx = -48,
						},
					},
					{
						t = 0.95,
						value = {
							rx = -4,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightShoulder",
				keys = {
					{
						t = 0,
						value = {
							rx = -30,
							rz = 6,
						},
					},
					{
						t = 0.2375,
						value = {
							rz = 6,
						},
					},
					{
						t = 0.475,
						value = {
							rx = 30,
							rz = 6,
						},
					},
					{
						t = 0.7125,
						value = {
							rz = 6,
						},
					},
					{
						t = 0.95,
						value = {
							rx = -30,
							rz = 6,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Root",
				keys = {
					{
						t = 0,
						value = {
							y = -0.02,
						},
					},
					{
						t = 0.2375,
						value = {
							y = 0.12,
						},
					},
					{
						t = 0.475,
						value = {
							y = -0.02,
						},
					},
					{
						t = 0.7125,
						value = {
							y = 0.12,
						},
					},
					{
						t = 0.95,
						value = {
							y = -0.02,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Waist",
				keys = {
					{
						t = 0,
						value = {
							rx = 6,
							ry = -6,
						},
					},
					{
						t = 0.2375,
						value = {
							rx = 7,
						},
					},
					{
						t = 0.475,
						value = {
							rx = 6,
							ry = 6,
						},
					},
					{
						t = 0.7125,
						value = {
							rx = 7,
						},
					},
					{
						t = 0.95,
						value = {
							rx = 6,
							ry = -6,
						},
					},
				},
				kind = "pose",
			},
		},
	},
	{
		ease = "sineInOut",
		format = "motion.clip/1",
		id = "walk.carry",
		length = 1,
		loop = true,
		markers = {
			{
				name = "footstep",
				t = 0,
			},
			{
				name = "footstep",
				t = 0.5,
			},
		},
		meta = {
			file = "AnimLibrary/Config.luau",
			source = "guildhall",
		},
		priority = "Movement",
		rig = "r15",
		tracks = {
			{
				joint = "LeftAnkle",
				keys = {
					{
						t = 0,
						value = {
							rx = 10,
						},
					},
					{
						t = 0.25,
						value = {
							rx = 10,
						},
					},
					{
						t = 0.5,
						value = {
							rx = -8,
						},
					},
					{
						t = 0.75,
						value = {
							rx = 2,
						},
					},
					{
						t = 1,
						value = {
							rx = 10,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftElbow",
				keys = {
					{
						t = 0,
						value = {
							rx = 70,
						},
					},
					{
						t = 0.25,
						value = {
							rx = 70,
						},
					},
					{
						t = 0.5,
						value = {
							rx = 70,
						},
					},
					{
						t = 0.75,
						value = {
							rx = 70,
						},
					},
					{
						t = 1,
						value = {
							rx = 70,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftHip",
				keys = {
					{
						t = 0,
						value = {
							rx = -18,
						},
					},
					{
						t = 0.25,
						value = {
							rx = 10,
						},
					},
					{
						t = 0.5,
						value = {
							rx = 20,
						},
					},
					{
						t = 0.75,
						value = {
							rx = 0,
						},
					},
					{
						t = 1,
						value = {
							rx = -18,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftKnee",
				keys = {
					{
						t = 0,
						value = {
							rx = -18,
						},
					},
					{
						t = 0.25,
						value = {
							rx = -40,
						},
					},
					{
						t = 0.5,
						value = {
							rx = -6,
						},
					},
					{
						t = 0.75,
						value = {
							rx = -6,
						},
					},
					{
						t = 1,
						value = {
							rx = -18,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftShoulder",
				keys = {
					{
						t = 0,
						value = {
							rx = 55,
							rz = 10,
						},
					},
					{
						t = 0.25,
						value = {
							rx = 58,
							rz = 10,
						},
					},
					{
						t = 0.5,
						value = {
							rx = 55,
							rz = 10,
						},
					},
					{
						t = 0.75,
						value = {
							rx = 58,
							rz = 10,
						},
					},
					{
						t = 1,
						value = {
							rx = 55,
							rz = 10,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Neck",
				keys = {
					{
						t = 0,
						value = {
							rx = 2,
						},
					},
					{
						t = 0.25,
						value = {
							rx = 2,
						},
					},
					{
						t = 0.5,
						value = {
							rx = 2,
						},
					},
					{
						t = 0.75,
						value = {
							rx = 2,
						},
					},
					{
						t = 1,
						value = {
							rx = 2,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightAnkle",
				keys = {
					{
						t = 0,
						value = {
							rx = -8,
						},
					},
					{
						t = 0.25,
						value = {
							rx = 2,
						},
					},
					{
						t = 0.5,
						value = {
							rx = 10,
						},
					},
					{
						t = 0.75,
						value = {
							rx = 10,
						},
					},
					{
						t = 1,
						value = {
							rx = -8,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightElbow",
				keys = {
					{
						t = 0,
						value = {
							rx = 70,
						},
					},
					{
						t = 0.25,
						value = {
							rx = 70,
						},
					},
					{
						t = 0.5,
						value = {
							rx = 70,
						},
					},
					{
						t = 0.75,
						value = {
							rx = 70,
						},
					},
					{
						t = 1,
						value = {
							rx = 70,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightHip",
				keys = {
					{
						t = 0,
						value = {
							rx = 20,
						},
					},
					{
						t = 0.25,
						value = {
							rx = 0,
						},
					},
					{
						t = 0.5,
						value = {
							rx = -18,
						},
					},
					{
						t = 0.75,
						value = {
							rx = 10,
						},
					},
					{
						t = 1,
						value = {
							rx = 20,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightKnee",
				keys = {
					{
						t = 0,
						value = {
							rx = -6,
						},
					},
					{
						t = 0.25,
						value = {
							rx = -6,
						},
					},
					{
						t = 0.5,
						value = {
							rx = -18,
						},
					},
					{
						t = 0.75,
						value = {
							rx = -40,
						},
					},
					{
						t = 1,
						value = {
							rx = -6,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightShoulder",
				keys = {
					{
						t = 0,
						value = {
							rx = 55,
							rz = -10,
						},
					},
					{
						t = 0.25,
						value = {
							rx = 58,
							rz = -10,
						},
					},
					{
						t = 0.5,
						value = {
							rx = 55,
							rz = -10,
						},
					},
					{
						t = 0.75,
						value = {
							rx = 58,
							rz = -10,
						},
					},
					{
						t = 1,
						value = {
							rx = 55,
							rz = -10,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Root",
				keys = {
					{
						t = 0,
						value = {
							y = -0.06,
						},
					},
					{
						t = 0.25,
						value = {
							y = 0.05,
						},
					},
					{
						t = 0.5,
						value = {
							y = -0.06,
						},
					},
					{
						t = 0.75,
						value = {
							y = 0.05,
						},
					},
					{
						t = 1,
						value = {
							y = -0.06,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Waist",
				keys = {
					{
						t = 0,
						value = {
							rx = 5,
							ry = -3,
						},
					},
					{
						t = 0.25,
						value = {
							rx = 5,
						},
					},
					{
						t = 0.5,
						value = {
							rx = 5,
							ry = 3,
						},
					},
					{
						t = 0.75,
						value = {
							rx = 5,
						},
					},
					{
						t = 1,
						value = {
							rx = 5,
							ry = -3,
						},
					},
				},
				kind = "pose",
			},
		},
	},
	{
		ease = "sineInOut",
		format = "motion.clip/1",
		id = "idle.look",
		length = 5,
		loop = true,
		meta = {
			file = "AnimLibrary/Config.luau",
			source = "guildhall",
		},
		priority = "Idle",
		rig = "r15",
		tracks = {
			{
				joint = "LeftElbow",
				keys = {
					{
						t = 0,
						value = {
							rx = 8,
						},
					},
					{
						t = 0.5,
						value = {
							rx = 8,
						},
					},
					{
						ease = "backOut",
						t = 1.3,
						value = {
							rx = 8,
						},
					},
					{
						t = 2.1,
						value = {
							rx = 8,
						},
					},
					{
						t = 2.8,
						value = {
							rx = 8,
						},
					},
					{
						ease = "quadIn",
						t = 3.7,
						value = {
							rx = 8,
						},
					},
					{
						ease = "quadOut",
						t = 4.4,
						value = {
							rx = 8,
						},
					},
					{
						t = 5,
						value = {
							rx = 8,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftHip",
				keys = {
					{
						t = 0,
						value = {
							rz = -2,
						},
					},
					{
						t = 0.5,
						value = {
							rz = -2,
						},
					},
					{
						ease = "backOut",
						t = 1.3,
						value = {
							rz = -2,
						},
					},
					{
						t = 2.1,
						value = {
							rz = -2,
						},
					},
					{
						t = 2.8,
						value = {
							rz = -2,
						},
					},
					{
						ease = "quadIn",
						t = 3.7,
						value = {
							rz = -2,
						},
					},
					{
						ease = "quadOut",
						t = 4.4,
						value = {
							rz = -2,
						},
					},
					{
						t = 5,
						value = {
							rz = -2,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftKnee",
				keys = {
					{
						t = 0,
						value = {
							rx = -6,
						},
					},
					{
						t = 0.5,
						value = {
							rx = -6,
						},
					},
					{
						ease = "backOut",
						t = 1.3,
						value = {
							rx = -6,
						},
					},
					{
						t = 2.1,
						value = {
							rx = -6,
						},
					},
					{
						t = 2.8,
						value = {
							rx = -6,
						},
					},
					{
						ease = "quadIn",
						t = 3.7,
						value = {
							rx = -6,
						},
					},
					{
						ease = "quadOut",
						t = 4.4,
						value = {
							rx = -6,
						},
					},
					{
						t = 5,
						value = {
							rx = -6,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftShoulder",
				keys = {
					{
						t = 0,
						value = {
							rz = -4,
						},
					},
					{
						t = 0.5,
						value = {
							rz = -4,
						},
					},
					{
						ease = "backOut",
						t = 1.3,
						value = {
							rz = -4,
						},
					},
					{
						t = 2.1,
						value = {
							rz = -4,
						},
					},
					{
						t = 2.8,
						value = {
							rz = -4,
						},
					},
					{
						ease = "quadIn",
						t = 3.7,
						value = {
							rz = -4,
						},
					},
					{
						ease = "quadOut",
						t = 4.4,
						value = {
							rz = -4,
						},
					},
					{
						t = 5,
						value = {
							rz = -4,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Neck",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.5,
						value = {
							ry = -6,
						},
					},
					{
						ease = "backOut",
						t = 1.3,
						value = {
							rx = 3,
							ry = 34,
						},
					},
					{
						t = 2.1,
						value = {
							rx = 4,
							ry = 30,
						},
					},
					{
						t = 2.8,
						value = {
							rx = 6,
							ry = -30,
						},
					},
					{
						ease = "quadIn",
						t = 3.7,
						value = {
							rx = 5,
							ry = -26,
						},
					},
					{
						ease = "quadOut",
						t = 4.4,
						value = {
							ry = 3,
						},
					},
					{
						t = 5,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightElbow",
				keys = {
					{
						t = 0,
						value = {
							rx = 8,
						},
					},
					{
						t = 0.5,
						value = {
							rx = 8,
						},
					},
					{
						ease = "backOut",
						t = 1.3,
						value = {
							rx = 8,
						},
					},
					{
						t = 2.1,
						value = {
							rx = 8,
						},
					},
					{
						t = 2.8,
						value = {
							rx = 120,
						},
					},
					{
						ease = "quadIn",
						t = 3.7,
						value = {
							rx = 118,
						},
					},
					{
						ease = "quadOut",
						t = 4.4,
						value = {
							rx = 8,
						},
					},
					{
						t = 5,
						value = {
							rx = 8,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightHip",
				keys = {
					{
						t = 0,
						value = {
							rz = 4,
						},
					},
					{
						t = 0.5,
						value = {
							rz = 4,
						},
					},
					{
						ease = "backOut",
						t = 1.3,
						value = {
							rz = 4,
						},
					},
					{
						t = 2.1,
						value = {
							rz = 4,
						},
					},
					{
						t = 2.8,
						value = {
							rz = 4,
						},
					},
					{
						ease = "quadIn",
						t = 3.7,
						value = {
							rz = 4,
						},
					},
					{
						ease = "quadOut",
						t = 4.4,
						value = {
							rz = 4,
						},
					},
					{
						t = 5,
						value = {
							rz = 4,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightShoulder",
				keys = {
					{
						t = 0,
						value = {
							rz = 4,
						},
					},
					{
						t = 0.5,
						value = {
							rz = 4,
						},
					},
					{
						ease = "backOut",
						t = 1.3,
						value = {
							rz = 4,
						},
					},
					{
						t = 2.1,
						value = {
							rz = 4,
						},
					},
					{
						t = 2.8,
						value = {
							rx = 100,
							rz = 20,
						},
					},
					{
						ease = "quadIn",
						t = 3.7,
						value = {
							rx = 98,
							rz = 20,
						},
					},
					{
						ease = "quadOut",
						t = 4.4,
						value = {
							rz = 2,
						},
					},
					{
						t = 5,
						value = {
							rz = 4,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Waist",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.5,
						value = {},
					},
					{
						ease = "backOut",
						t = 1.3,
						value = {
							ry = 10,
						},
					},
					{
						t = 2.1,
						value = {
							ry = 9,
						},
					},
					{
						t = 2.8,
						value = {
							ry = -8,
						},
					},
					{
						ease = "quadIn",
						t = 3.7,
						value = {
							ry = -7,
						},
					},
					{
						ease = "quadOut",
						t = 4.4,
						value = {},
					},
					{
						t = 5,
						value = {},
					},
				},
				kind = "pose",
			},
		},
	},
	{
		ease = "sineInOut",
		format = "motion.clip/1",
		id = "idle.fidget",
		length = 4,
		loop = true,
		markers = {
			{
				name = "tap",
				t = 2.9,
			},
			{
				name = "tap",
				t = 3.2,
			},
		},
		meta = {
			file = "AnimLibrary/Config.luau",
			source = "guildhall",
		},
		priority = "Idle",
		rig = "r15",
		tracks = {
			{
				joint = "LeftKnee",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.8,
						value = {
							rx = -2,
						},
					},
					{
						ease = "backOut",
						t = 1.4,
						value = {},
					},
					{
						t = 1.6,
						value = {},
					},
					{
						t = 1.8,
						value = {},
					},
					{
						t = 2,
						value = {},
					},
					{
						ease = "quadOut",
						t = 2.5,
						value = {},
					},
					{
						t = 2.9,
						value = {},
					},
					{
						t = 3.05,
						value = {},
					},
					{
						t = 3.2,
						value = {},
					},
					{
						t = 3.4,
						value = {},
					},
					{
						t = 4,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "LeftShoulder",
				keys = {
					{
						t = 0,
						value = {
							rz = -4,
						},
					},
					{
						t = 0.8,
						value = {
							rz = -4,
						},
					},
					{
						ease = "backOut",
						t = 1.4,
						value = {
							rz = -4,
						},
					},
					{
						t = 1.6,
						value = {
							rz = -4,
						},
					},
					{
						t = 1.8,
						value = {
							rz = -4,
						},
					},
					{
						t = 2,
						value = {
							rz = -4,
						},
					},
					{
						ease = "quadOut",
						t = 2.5,
						value = {
							rz = -4,
						},
					},
					{
						t = 2.9,
						value = {
							rz = -4,
						},
					},
					{
						t = 3.05,
						value = {
							rz = -4,
						},
					},
					{
						t = 3.2,
						value = {
							rz = -4,
						},
					},
					{
						t = 3.4,
						value = {
							rz = -4,
						},
					},
					{
						t = 4,
						value = {
							rz = -4,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Neck",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.8,
						value = {},
					},
					{
						ease = "backOut",
						t = 1.4,
						value = {
							rx = -8,
							rz = -4,
						},
					},
					{
						t = 1.6,
						value = {
							rx = -8,
							rz = -4,
						},
					},
					{
						t = 1.8,
						value = {
							rx = -8,
							rz = -4,
						},
					},
					{
						t = 2,
						value = {
							rx = -8,
							rz = -4,
						},
					},
					{
						ease = "quadOut",
						t = 2.5,
						value = {},
					},
					{
						t = 2.9,
						value = {},
					},
					{
						t = 3.05,
						value = {},
					},
					{
						t = 3.2,
						value = {},
					},
					{
						t = 3.4,
						value = {},
					},
					{
						t = 4,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightAnkle",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.8,
						value = {},
					},
					{
						ease = "backOut",
						t = 1.4,
						value = {},
					},
					{
						t = 1.6,
						value = {},
					},
					{
						t = 1.8,
						value = {},
					},
					{
						t = 2,
						value = {},
					},
					{
						ease = "quadOut",
						t = 2.5,
						value = {},
					},
					{
						t = 2.9,
						value = {
							rx = -22,
						},
					},
					{
						t = 3.05,
						value = {},
					},
					{
						t = 3.2,
						value = {
							rx = -22,
						},
					},
					{
						t = 3.4,
						value = {},
					},
					{
						t = 4,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightElbow",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.8,
						value = {},
					},
					{
						ease = "backOut",
						t = 1.4,
						value = {
							rx = 140,
						},
					},
					{
						t = 1.6,
						value = {
							rx = 128,
						},
					},
					{
						t = 1.8,
						value = {
							rx = 145,
						},
					},
					{
						t = 2,
						value = {
							rx = 130,
						},
					},
					{
						ease = "quadOut",
						t = 2.5,
						value = {},
					},
					{
						t = 2.9,
						value = {},
					},
					{
						t = 3.05,
						value = {},
					},
					{
						t = 3.2,
						value = {},
					},
					{
						t = 3.4,
						value = {},
					},
					{
						t = 4,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightKnee",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.8,
						value = {
							rx = -10,
						},
					},
					{
						ease = "backOut",
						t = 1.4,
						value = {
							rx = -10,
						},
					},
					{
						t = 1.6,
						value = {
							rx = -10,
						},
					},
					{
						t = 1.8,
						value = {
							rx = -10,
						},
					},
					{
						t = 2,
						value = {
							rx = -10,
						},
					},
					{
						ease = "quadOut",
						t = 2.5,
						value = {},
					},
					{
						t = 2.9,
						value = {},
					},
					{
						t = 3.05,
						value = {},
					},
					{
						t = 3.2,
						value = {},
					},
					{
						t = 3.4,
						value = {},
					},
					{
						t = 4,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "RightShoulder",
				keys = {
					{
						t = 0,
						value = {
							rz = 4,
						},
					},
					{
						t = 0.8,
						value = {
							rz = 4,
						},
					},
					{
						ease = "backOut",
						t = 1.4,
						value = {
							rx = 60,
							rz = 62,
						},
					},
					{
						t = 1.6,
						value = {
							rx = 60,
							rz = 62,
						},
					},
					{
						t = 1.8,
						value = {
							rx = 60,
							rz = 62,
						},
					},
					{
						t = 2,
						value = {
							rx = 60,
							rz = 62,
						},
					},
					{
						ease = "quadOut",
						t = 2.5,
						value = {
							rz = 3,
						},
					},
					{
						t = 2.9,
						value = {
							rz = 4,
						},
					},
					{
						t = 3.05,
						value = {
							rz = 4,
						},
					},
					{
						t = 3.2,
						value = {
							rz = 4,
						},
					},
					{
						t = 3.4,
						value = {
							rz = 4,
						},
					},
					{
						t = 4,
						value = {
							rz = 4,
						},
					},
				},
				kind = "pose",
			},
			{
				joint = "Root",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.8,
						value = {
							rz = -2,
							x = -0.05,
						},
					},
					{
						ease = "backOut",
						t = 1.4,
						value = {
							rz = -2,
							x = -0.05,
						},
					},
					{
						t = 1.6,
						value = {
							rz = -2,
							x = -0.05,
						},
					},
					{
						t = 1.8,
						value = {
							rz = -2,
							x = -0.05,
						},
					},
					{
						t = 2,
						value = {
							rz = -2,
							x = -0.05,
						},
					},
					{
						ease = "quadOut",
						t = 2.5,
						value = {
							rz = 1,
							x = 0.03,
						},
					},
					{
						t = 2.9,
						value = {
							rz = 1,
							x = 0.03,
						},
					},
					{
						t = 3.05,
						value = {
							rz = 1,
							x = 0.03,
						},
					},
					{
						t = 3.2,
						value = {
							rz = 1,
							x = 0.03,
						},
					},
					{
						t = 3.4,
						value = {
							x = 0.01,
						},
					},
					{
						t = 4,
						value = {},
					},
				},
				kind = "pose",
			},
			{
				joint = "Waist",
				keys = {
					{
						t = 0,
						value = {},
					},
					{
						t = 0.8,
						value = {
							rz = 2,
						},
					},
					{
						ease = "backOut",
						t = 1.4,
						value = {
							rz = 2,
						},
					},
					{
						t = 1.6,
						value = {
							rz = 2,
						},
					},
					{
						t = 1.8,
						value = {
							rz = 2,
						},
					},
					{
						t = 2,
						value = {
							rz = 2,
						},
					},
					{
						ease = "quadOut",
						t = 2.5,
						value = {
							rz = -1,
						},
					},
					{
						t = 2.9,
						value = {},
					},
					{
						t = 3.05,
						value = {},
					},
					{
						t = 3.2,
						value = {},
					},
					{
						t = 3.4,
						value = {},
					},
					{
						t = 4,
						value = {},
					},
				},
				kind = "pose",
			},
		},
	},
}
