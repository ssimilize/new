--!strict
-- Face sets: eyes, brows and mouths as part-built face pieces on the Head (sphere-mesh eyes
-- with a glint, block brows, a mouth, cheek blush, like the Guildhall chibi face), plus the
-- id of the matching procedural face TEXTURE (`foundry atelier faces` draws every one with
-- PIL, for when decals can be uploaded). Part names match the Guildhall face layer (EyeR,
-- EyeL, GlintR, GlintL, BrowR, BrowL, Mouth, BlushR, BlushL) so its blink and expression code
-- keeps working on Atelier bodies.
--
-- Numbers are chibi template units on the Head (centre origin, front at z = -1.05).

local Faces = {}

-- eyes: size of one eye (x, y, depth), how far out from the middle, lift; `glint` = white dot
Faces.eyes = {
	round = { size = { 0.34, 0.5, 0.14 }, x = 0.44, y = -0.1, glint = true },
	wide = { size = { 0.42, 0.5, 0.14 }, x = 0.48, y = -0.1, glint = true },
	narrow = { size = { 0.38, 0.26, 0.12 }, x = 0.44, y = -0.08, glint = false },
	dot = { size = { 0.22, 0.26, 0.12 }, x = 0.4, y = -0.1, glint = false },
	sleepy = { size = { 0.38, 0.2, 0.12 }, x = 0.44, y = -0.14, glint = false },
	big = { size = { 0.5, 0.62, 0.16 }, x = 0.48, y = -0.12, glint = true },
	almond = { size = { 0.4, 0.34, 0.13 }, x = 0.45, y = -0.08, glint = true, tilt = 8 },
}
Faces.eyeOrder = { "round", "wide", "narrow", "dot", "sleepy", "big", "almond" }

-- brows: size, lift above the eye, roll (degrees the INNER end drops); `none` draws nothing
Faces.brows = {
	straight = { size = { 0.4, 0.09, 0.1 }, y = 0.3, roll = 0 },
	arched = { size = { 0.42, 0.08, 0.1 }, y = 0.34, roll = -10 },
	thick = { size = { 0.46, 0.15, 0.1 }, y = 0.3, roll = 0 },
	thin = { size = { 0.38, 0.05, 0.1 }, y = 0.32, roll = -4 },
	angled = { size = { 0.42, 0.1, 0.1 }, y = 0.28, roll = 14 },
	worried = { size = { 0.4, 0.08, 0.1 }, y = 0.32, roll = -16 },
	none = false,
}
Faces.browOrder = { "straight", "arched", "thick", "thin", "angled", "worried", "none" }

-- mouths: size, x shift, roll
Faces.mouths = {
	smile = { size = { 0.3, 0.11, 0.08 }, dx = 0, roll = 0 },
	grin = { size = { 0.5, 0.15, 0.08 }, dx = 0, roll = 0 },
	small = { size = { 0.18, 0.08, 0.08 }, dx = 0, roll = 0 },
	flat = { size = { 0.32, 0.06, 0.08 }, dx = 0, roll = 0, block = true },
	open = { size = { 0.26, 0.22, 0.08 }, dx = 0, roll = 0 },
	smirk = { size = { 0.3, 0.09, 0.08 }, dx = 0.08, roll = 10 },
	pout = { size = { 0.2, 0.12, 0.1 }, dx = 0, roll = 0 },
}
Faces.mouthOrder = { "smile", "grin", "small", "flat", "open", "smirk", "pout" }

-- The texture id a face field names (a file `<id>.png` drawn by `foundry atelier faces`).
function Faces.textureId(eyes: string, brows: string, mouth: string): string
	return `{eyes}-{brows}-{mouth}`
end

-- Every problem with a face set { eyes = {...}, brows = {...}, mouths = {...}, blush = 0..1 }.
function Faces.checkSet(where: string, set: any): { string }
	local problems = {}
	if type(set) ~= "table" then
		return { `{where}: a face set must be a table` }
	end
	for key, lib in { eyes = Faces.eyes, brows = Faces.brows, mouths = Faces.mouths } do
		local list = set[key]
		if type(list) ~= "table" or #list == 0 then
			table.insert(problems, `{where}: {key} must be a non-empty list`)
		else
			for _, id in list do
				if lib[id] == nil then
					table.insert(problems, `{where}: unknown {key} style {tostring(id)}`)
				end
			end
		end
	end
	if set.blush ~= nil and (type(set.blush) ~= "number" or set.blush < 0 or set.blush > 1) then
		table.insert(problems, `{where}: blush must be a chance 0..1`)
	end
	return problems
end

-- The face as wardrobe-style parts (attach Head, colour slots eye / glint / hair / mouth / blush).
function Faces.parts(face: any): { any }
	local out = {}
	local e = Faces.eyes[face.eyes] or Faces.eyes.round
	local tilt = e.tilt or 0
	for _, side in { { "R", 1 }, { "L", -1 } } do
		local s, k = side[1], side[2]
		table.insert(out, {
			name = "Eye" .. s,
			attach = "Head",
			shape = "Ball",
			size = e.size,
			offset = { e.x * k, e.y, -0.95 },
			rot = { 0, 0, -tilt * k },
			color = "eye",
			face = "eye",
		})
		if e.glint then
			table.insert(out, {
				name = "Glint" .. s,
				attach = "Head",
				shape = "Ball",
				size = { e.size[1] * 0.38, e.size[1] * 0.38, 0.06 },
				offset = { e.x * k + 0.06, e.y + e.size[2] * 0.24, -1.03 },
				color = "glint",
				face = "glint",
				minQuality = "medium",
			})
		end
		local b = Faces.brows[face.brows]
		if b then
			table.insert(out, {
				name = "Brow" .. s,
				attach = "Head",
				shape = "Block",
				size = b.size,
				offset = { e.x * k, e.y + b.y + e.size[2] * 0.25, -0.94 },
				rot = { 0, 0, b.roll * k },
				color = "hair",
				face = "brow",
				minQuality = "medium",
			})
		end
		if face.blush then
			table.insert(out, {
				name = "Blush" .. s,
				attach = "Head",
				shape = "Ball",
				size = { 0.36, 0.16, 0.06 },
				offset = { 0.72 * k, -0.38, -0.75 },
				rot = { 0, -35 * k, 0 },
				color = "blush",
				face = "blush",
				minQuality = "high",
			})
		end
	end
	local m = Faces.mouths[face.mouth] or Faces.mouths.smile
	table.insert(out, {
		name = "Mouth",
		attach = "Head",
		shape = if m.block then "Block" else "Ball",
		size = m.size,
		offset = { m.dx, -0.52, -0.92 },
		rot = { 0, 0, m.roll },
		color = "mouth",
		face = "mouth",
	})
	return out
end

return Faces
