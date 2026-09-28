--!strict
-- Body templates and builds: the R15 part sizes a body starts from, the build multipliers that
-- make it slim / stout / lanky, and the layout that stacks the parts from the soles up and
-- places every Motor6D (joint names follow the R15 set, so every R15 clip drives the body).
--
-- Coordinates (template units, before `scale`): y up from the soles, -z is the FRONT, +x is the
-- body's own right. A template is sizes plus a few layout constants; `layout` derives positions,
-- so any build multiplier keeps the joints attached. The `chibi` template reproduces the
-- Guildhall AnimLibrary rig (0.55 scale chibi R15) to within 0.01 stud at the `average` build.

local Bodies = {}

-- R15 part -> size group (a build scales groups) and colour group (a palette slot paints it).
Bodies.PARTS = {
	{ name = "HumanoidRootPart", size = "Root", group = "root", paint = "hidden" },
	{ name = "LowerTorso", size = "LowerTorso", group = "torso", paint = "torso" },
	{ name = "UpperTorso", size = "UpperTorso", group = "torso", paint = "torso" },
	{ name = "Head", size = "Head", group = "head", paint = "skin" },
	{ name = "RightUpperArm", size = "UpperArm", group = "arms", paint = "sleeve" },
	{ name = "RightLowerArm", size = "LowerArm", group = "arms", paint = "sleeve" },
	{ name = "RightHand", size = "Hand", group = "hands", paint = "hands" },
	{ name = "LeftUpperArm", size = "UpperArm", group = "arms", paint = "sleeve" },
	{ name = "LeftLowerArm", size = "LowerArm", group = "arms", paint = "sleeve" },
	{ name = "LeftHand", size = "Hand", group = "hands", paint = "hands" },
	{ name = "RightUpperLeg", size = "UpperLeg", group = "legs", paint = "legs" },
	{ name = "RightLowerLeg", size = "LowerLeg", group = "legs", paint = "legs" },
	{ name = "RightFoot", size = "Foot", group = "feet", paint = "feet" },
	{ name = "LeftUpperLeg", size = "UpperLeg", group = "legs", paint = "legs" },
	{ name = "LeftLowerLeg", size = "LowerLeg", group = "legs", paint = "legs" },
	{ name = "LeftFoot", size = "Foot", group = "feet", paint = "feet" },
}

-- Joint name -> { part0, part1 } (ClientAnim.R15 names and parenting).
Bodies.JOINTS = {
	{ name = "Root", part0 = "HumanoidRootPart", part1 = "LowerTorso" },
	{ name = "Waist", part0 = "LowerTorso", part1 = "UpperTorso" },
	{ name = "Neck", part0 = "UpperTorso", part1 = "Head" },
	{ name = "RightShoulder", part0 = "UpperTorso", part1 = "RightUpperArm" },
	{ name = "RightElbow", part0 = "RightUpperArm", part1 = "RightLowerArm" },
	{ name = "RightWrist", part0 = "RightLowerArm", part1 = "RightHand" },
	{ name = "LeftShoulder", part0 = "UpperTorso", part1 = "LeftUpperArm" },
	{ name = "LeftElbow", part0 = "LeftUpperArm", part1 = "LeftLowerArm" },
	{ name = "LeftWrist", part0 = "LeftLowerArm", part1 = "LeftHand" },
	{ name = "RightHip", part0 = "LowerTorso", part1 = "RightUpperLeg" },
	{ name = "RightKnee", part0 = "RightUpperLeg", part1 = "RightLowerLeg" },
	{ name = "RightAnkle", part0 = "RightLowerLeg", part1 = "RightFoot" },
	{ name = "LeftHip", part0 = "LowerTorso", part1 = "LeftUpperLeg" },
	{ name = "LeftKnee", part0 = "LeftUpperLeg", part1 = "LeftLowerLeg" },
	{ name = "LeftAnkle", part0 = "LeftLowerLeg", part1 = "LeftFoot" },
}

-- Templates. `sizes` in studs at scale 1; `round` parts are ellipsoids (a sphere mesh).
Bodies.templates = {
	-- The chibi R15 (Guildhall AnimLibrary rig.hero / rig.villager): head a third of the height.
	chibi = {
		sizes = {
			Root = { 1.8, 2.0, 1.0 },
			LowerTorso = { 1.8, 0.55, 1.05 },
			UpperTorso = { 1.85, 1.2, 1.05 },
			Head = { 2.3, 2.1, 2.1 },
			UpperArm = { 0.62, 0.8, 0.62 },
			LowerArm = { 0.56, 0.7, 0.56 },
			Hand = { 0.66, 0.58, 0.66 },
			UpperLeg = { 0.8, 0.9, 0.8 },
			LowerLeg = { 0.72, 0.7, 0.72 },
			Foot = { 0.82, 0.32, 1.12 },
		},
		round = { Head = true, Hand = true },
		hipX = 0.45,
		footForward = -0.12,
		shoulderDrop = 0.25,
	},
	-- A taller cartoon R15: head about a fifth of the height, longer limbs (ranch folk).
	tall = {
		sizes = {
			Root = { 1.6, 2.0, 1.0 },
			LowerTorso = { 1.6, 0.6, 0.95 },
			UpperTorso = { 1.7, 1.5, 0.95 },
			Head = { 1.6, 1.6, 1.55 },
			UpperArm = { 0.5, 1.1, 0.5 },
			LowerArm = { 0.46, 1.0, 0.46 },
			Hand = { 0.52, 0.5, 0.52 },
			UpperLeg = { 0.66, 1.3, 0.66 },
			LowerLeg = { 0.6, 1.2, 0.6 },
			Foot = { 0.66, 0.3, 1.0 },
		},
		round = { Head = true, Hand = true },
		hipX = 0.4,
		footForward = -0.1,
		shoulderDrop = 0.22,
	},
}

-- Builds: per size group multipliers { x, y, z } (a number = all three). Missing groups are 1.
Bodies.builds = {
	average = {},
	slim = { torso = { 0.88, 1.02, 0.9 }, arms = { 0.88, 1.0, 0.88 }, legs = { 0.9, 1.04, 0.9 } },
	stout = { torso = { 1.18, 0.98, 1.16 }, arms = { 1.1, 0.96, 1.1 }, legs = { 1.1, 0.95, 1.1 }, hands = 1.06 },
	broad = { torso = { 1.22, 1.05, 1.08 }, arms = { 1.18, 1.04, 1.18 }, hands = 1.12, legs = { 1.06, 1.0, 1.06 } },
	lanky = { torso = { 0.92, 1.1, 0.92 }, arms = { 0.9, 1.12, 0.9 }, legs = { 0.9, 1.15, 0.9 } },
	round = { torso = { 1.25, 0.95, 1.3 }, arms = { 1.05, 0.95, 1.05 }, legs = { 1.05, 0.9, 1.05 }, head = 1.03 },
	sprout = {
		head = 0.95,
		torso = { 0.85, 0.8, 0.85 },
		arms = { 0.85, 0.78, 0.85 },
		hands = 0.85,
		legs = { 0.85, 0.72, 0.85 },
		feet = 0.85,
	},
}

local function mul3(v: { number }, m: any): { number }
	if m == nil then
		return { v[1], v[2], v[3] }
	end
	if type(m) == "number" then
		return { v[1] * m, v[2] * m, v[3] * m }
	end
	return { v[1] * m[1], v[2] * m[2], v[3] * m[3] }
end

-- Every problem with a template (missing sizes, bad numbers).
function Bodies.checkTemplate(name: string, t: any): { string }
	local problems = {}
	if type(t) ~= "table" or type(t.sizes) ~= "table" then
		return { `template {name}: needs a sizes table` }
	end
	for _, key in { "Root", "LowerTorso", "UpperTorso", "Head", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot" } do
		local s = t.sizes[key]
		if type(s) ~= "table" or #s ~= 3 then
			table.insert(problems, `template {name}: sizes.{key} must be {"{x, y, z}"}`)
		else
			for _, v in s do
				if type(v) ~= "number" or v <= 0 then
					table.insert(problems, `template {name}: sizes.{key} has a non-positive size`)
					break
				end
			end
		end
	end
	for _, k in { "hipX", "footForward", "shoulderDrop" } do
		if type(t[k]) ~= "number" then
			table.insert(problems, `template {name}: {k} must be a number`)
		end
	end
	return problems
end

-- Sizes and rest positions for a template under a build (template units, scale 1).
-- Returns parts[name] = { size = {x,y,z}, pos = {x,y,z}, ratio = {x,y,z} (size / template
-- size, for pieces attached to it), round = bool } and joints[name] = { part0, part1, at }.
function Bodies.layout(template: any, build: any): (any, any)
	local b = build or {}
	local s = {}
	local groupOf = {
		Root = "root",
		LowerTorso = "torso",
		UpperTorso = "torso",
		Head = "head",
		UpperArm = "arms",
		LowerArm = "arms",
		Hand = "hands",
		UpperLeg = "legs",
		LowerLeg = "legs",
		Foot = "feet",
	}
	for key, g in groupOf do
		s[key] = mul3(template.sizes[key], b[g])
	end
	-- the root spans the hips, its width follows the lower torso
	s.Root = { s.LowerTorso[1], template.sizes.Root[2], template.sizes.Root[3] }
	local wRatio = s.LowerTorso[1] / template.sizes.LowerTorso[1]
	local hipX = template.hipX * wRatio
	local footZ = template.footForward * (s.Foot[3] / template.sizes.Foot[3])

	local ankle = s.Foot[2] + 0.03
	local knee = ankle + s.LowerLeg[2]
	local hip = knee + s.UpperLeg[2]
	local lt = hip - 0.075 + s.LowerTorso[2] / 2
	local waist = lt + s.LowerTorso[2] / 2 - 0.025
	local ut = waist + s.UpperTorso[2] / 2
	local neck = waist + s.UpperTorso[2]
	local head = neck + s.Head[2] / 2
	local shoulder = neck - template.shoulderDrop
	local ua = shoulder - s.UpperArm[2] / 2 + 0.1
	local elbow = ua - s.UpperArm[2] / 2 + 0.05
	local la = elbow - s.LowerArm[2] / 2
	local wrist = la - s.LowerArm[2] / 2
	local hand = wrist - s.Hand[2] / 2 + 0.09
	local armX = s.UpperTorso[1] / 2 + s.UpperArm[1] / 2 + 0.015

	local pos = {
		HumanoidRootPart = { 0, lt + 0.25, 0 },
		LowerTorso = { 0, lt, 0 },
		UpperTorso = { 0, ut, 0 },
		Head = { 0, head, 0 },
		RightUpperArm = { armX, ua, 0 },
		RightLowerArm = { armX, la, 0 },
		RightHand = { armX, hand, 0 },
		LeftUpperArm = { -armX, ua, 0 },
		LeftLowerArm = { -armX, la, 0 },
		LeftHand = { -armX, hand, 0 },
		RightUpperLeg = { hipX, knee + s.UpperLeg[2] / 2, 0 },
		RightLowerLeg = { hipX, ankle + s.LowerLeg[2] / 2, 0 },
		RightFoot = { hipX, s.Foot[2] / 2, footZ },
		LeftUpperLeg = { -hipX, knee + s.UpperLeg[2] / 2, 0 },
		LeftLowerLeg = { -hipX, ankle + s.LowerLeg[2] / 2, 0 },
		LeftFoot = { -hipX, s.Foot[2] / 2, footZ },
	}
	local at = {
		Root = { 0, lt, 0 },
		Waist = { 0, waist, 0 },
		Neck = { 0, neck, 0 },
		RightShoulder = { armX, shoulder, 0 },
		RightElbow = { armX, elbow, 0 },
		RightWrist = { armX, wrist, 0 },
		LeftShoulder = { -armX, shoulder, 0 },
		LeftElbow = { -armX, elbow, 0 },
		LeftWrist = { -armX, wrist, 0 },
		RightHip = { hipX, hip, 0 },
		RightKnee = { hipX, knee, 0 },
		RightAnkle = { hipX, ankle, 0 },
		LeftHip = { -hipX, hip, 0 },
		LeftKnee = { -hipX, knee, 0 },
		LeftAnkle = { -hipX, ankle, 0 },
	}
	local parts = {}
	for _, p in Bodies.PARTS do
		local size = s[p.size]
		local base = template.sizes[p.size]
		parts[p.name] = {
			size = size,
			pos = pos[p.name],
			ratio = { size[1] / base[1], size[2] / base[2], size[3] / base[3] },
			round = (template.round or {})[p.size] == true,
			paint = p.paint,
		}
	end
	local joints = {}
	for _, j in Bodies.JOINTS do
		joints[j.name] = { part0 = j.part0, part1 = j.part1, at = at[j.name] }
	end
	return parts, joints
end

-- Height of the body's top (the head's crown) in template units.
function Bodies.height(parts: any): number
	local h = parts.Head
	return h.pos[2] + h.size[2] / 2
end

return Bodies
