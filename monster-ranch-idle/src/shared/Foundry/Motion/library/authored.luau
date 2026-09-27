--!strict
-- Clips the Motion library authors itself (no game had them): the `sell` work loop and the
-- `emote.clap` / `emote.startle` crowd emotes. Authored in Guildhall's conventions (degrees
-- and studs for the 0.55 chibi R15; a hanging limb swings FORWARD with rx > 0; knees bend with
-- rx < 0, elbows with rx > 0; RightShoulder rz > 0 / LeftShoulder rz < 0 lift the arms out;
-- Waist rx < 0 leans forward; Neck rx > 0 looks up; ry > 0 turns left), with anticipation and
-- follow-through, every keyframe keying every joint the clip uses (missing = rest), upper body
-- only so they layer over `walk`. Written as Guildhall-style keyframes and converted, so the
-- same clip can be handed back to ClientAnim with Convert.toGuildhall.

local Convert = require("../Convert")

local function clip(id: string, length: number, loop: boolean, priority: string, frames: { any }, markers: { any }?): any
	local joints = {}
	for _, f in frames do
		for j in f[2] do
			joints[j] = true
		end
	end
	local kfs = {}
	for _, f in frames do
		local poses = table.clone(f[2])
		for j in joints do
			if poses[j] == nil then
				poses[j] = {}
			end
		end
		table.insert(kfs, { t = f[1], poses = poses, ease = f[3] })
	end
	if loop then
		table.insert(kfs, { t = length, poses = kfs[1].poses })
	end
	local doc = Convert.fromGuildhall({
		id = id,
		kind = "rig",
		length = length,
		loop = loop,
		priority = priority,
		ease = "sineInOut",
		keyframes = kfs,
		markers = markers,
	})
	doc.meta = { source = "foundry", author = "CH2 Motion Lab" }
	return doc
end

local clips = {}

do -- sell: a stallholder offers a good, takes the coin, drops it in the till, chats. 3 s loop.
	local ready = {
		Waist = { rx = -4 },
		Neck = { rx = -5 },
		RightShoulder = { rx = 30, rz = -4 },
		RightElbow = { rx = 60 },
		RightWrist = {},
		LeftShoulder = { rx = 30, rz = 4 },
		LeftElbow = { rx = 60 },
	}
	local offer = {
		Waist = { rx = -9, ry = -4 },
		Neck = { rx = 0, ry = -6 },
		RightShoulder = { rx = 72, rz = -6 },
		RightElbow = { rx = 18 },
		RightWrist = { rx = -18 },
		LeftShoulder = { rx = 28, rz = 6 },
		LeftElbow = { rx = 58 },
	}
	local till = {
		Waist = { rx = -12, ry = 10 },
		Neck = { rx = -14, ry = 12 },
		RightShoulder = { rx = 40, rz = 10 },
		RightElbow = { rx = 70 },
		RightWrist = { rx = 10 },
		LeftShoulder = { rx = 45, rz = 12 },
		LeftElbow = { rx = 55 },
	}
	local talk = {
		Waist = { rx = -2, ry = 2 },
		Neck = { rx = 4, ry = 0 },
		RightShoulder = { rx = 34, rz = 16 },
		RightElbow = { rx = 86 },
		RightWrist = { rz = 20 },
		LeftShoulder = { rx = 26, rz = -4 },
		LeftElbow = { rx = 50 },
	}
	table.insert(clips, clip("sell", 3.0, true, "Action", {
		{ 0, ready, "quadIn" },
		{ 0.35, table.clone(ready), "backOut" },
		{ 0.8, offer },
		{ 1.3, till, "quadOut" },
		{ 2.1, talk },
		{ 2.6, table.clone(talk), "sineInOut" },
	}, {
		{ t = 0.35, name = "pickup" },
		{ t = 1.45, name = "drop" },
		{ t = 2.1, name = "talk" },
	}))
end

do -- emote.clap: arms apart (anticipation), three claps, a settle. One-shot, 1.6 s.
	local apart = {
		Waist = { rx = 2 },
		Neck = { rx = 6 },
		RightShoulder = { rx = 55, rz = 30 },
		RightElbow = { rx = 60 },
		LeftShoulder = { rx = 55, rz = -30 },
		LeftElbow = { rx = 60 },
	}
	local together = {
		Waist = { rx = 0 },
		Neck = { rx = 4 },
		RightShoulder = { rx = 62, rz = -8 },
		RightElbow = { rx = 72 },
		LeftShoulder = { rx = 62, rz = 8 },
		LeftElbow = { rx = 72 },
	}
	table.insert(clips, clip("emote.clap", 1.6, false, "Action", {
		{ 0, {}, "quadOut" },
		{ 0.2, apart, "quadIn" },
		{ 0.35, together, "quadOut" },
		{ 0.5, apart, "quadIn" },
		{ 0.65, together, "quadOut" },
		{ 0.8, apart, "quadIn" },
		{ 0.95, together, "backOut" },
		{ 1.25, { Neck = { rx = 2 }, RightShoulder = { rx = 8 }, LeftShoulder = { rx = 8 } }, "sineOut" },
		{ 1.6, {} },
	}, {
		{ t = 0.35, name = "hit" },
		{ t = 0.65, name = "hit" },
		{ t = 0.95, name = "hit" },
	}))
end

do -- emote.startle: a flinch back from a flash or a bang, a held breath, a settle. 1.2 s.
	table.insert(clips, clip("emote.startle", 1.2, false, "Action", {
		{ 0, {}, "quadIn" },
		{ 0.08, { Waist = { rx = -3 }, Neck = { rx = -2 }, Root = { y = -0.02 } }, "quadOut" },
		{
			0.22,
			{
				Root = { y = 0.08 },
				Waist = { rx = 10 },
				Neck = { rx = 12 },
				RightShoulder = { rx = 40, rz = 35 },
				RightElbow = { rx = 90 },
				LeftShoulder = { rx = 40, rz = -35 },
				LeftElbow = { rx = 90 },
			},
			"sineInOut",
		},
		{
			0.55,
			{
				Root = { y = 0.05 },
				Waist = { rx = 7 },
				Neck = { rx = 8 },
				RightShoulder = { rx = 35, rz = 28 },
				RightElbow = { rx = 80 },
				LeftShoulder = { rx = 35, rz = -28 },
				LeftElbow = { rx = 80 },
			},
			"sineOut",
		},
		{ 0.9, { Waist = { rx = 2 }, Neck = { rx = -3 }, RightShoulder = { rx = 6 }, LeftShoulder = { rx = 6 } }, "sineInOut" },
		{ 1.2, {} },
	}, { { t = 0.22, name = "swish" } }))
end

return clips
