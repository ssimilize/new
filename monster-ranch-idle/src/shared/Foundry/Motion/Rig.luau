--!strict
-- Rig: the skeleton a clip plays on, as data, and forward kinematics over it.
--
--   local rig = Rig.r15("chibi", "average", 0.55)    -- Atelier's townsfolk body (CH1)
--   local rig = Rig.bones(require(MeshMonsters.fox))  -- a Ranch form: bones + rest cframes
--   local world = Rig.fk(rig, Motion.sample(clip, t)) -- name -> { pos = {x,y,z}, rot = Mat }
--
-- R15 (Atelier Bodies): parts sit at their layout positions with no rest rotation; a Motor6D's
-- C0 / C1 are the joint point relative to part0 / part1, and part1 = part0 * C0 * T * C1^-1
-- with T = CFrame.new(x, y, z) * CFrame.Angles(rx, ry, rz) from the clip pose (degrees; the
-- translations are studs, as Guildhall authors them for its 0.55 rig).
-- Bones (Ranch MeshMonsters/<form>): bone.cframe = { px, py, pz, qx, qy, qz, qw } relative to
-- its parent (0 = the mesh); world = parent * rest * T with T = the sampled { x..qw }, and
-- the positions scaled by the rig's scale like MeshMonster.Pose does.

local Bodies = require("../Atelier/Bodies")
local M = require("./Math")

local Rig = {}

export type Frame = { pos: { number }, rot: { number } }

local function vsub(a: { number }, b: { number }): { number }
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function vscale(a: { number }, k: number): { number }
	return { a[1] * k, a[2] * k, a[3] * k }
end

-- r15(template, build, scale) -> rig. template / build: names in Atelier Bodies or tables.
function Rig.r15(template: any, build: any?, scale: number?): any
	local tpl = if type(template) == "string" then Bodies.templates[template] else template
	assert(type(tpl) == "table", "Rig.r15: unknown template " .. tostring(template))
	local b = if type(build) == "string" then Bodies.builds[build] else build
	if type(build) == "string" then
		assert(b ~= nil, "Rig.r15: unknown build " .. build)
	end
	local k = scale or 1
	local parts, joints = Bodies.layout(tpl, b or {})
	local outParts = {}
	for name, p in parts do
		outParts[name] = { pos = vscale(p.pos, k), size = vscale(p.size, k), round = p.round }
	end
	local list = {}
	for _, j in Bodies.JOINTS do
		local at = vscale(joints[j.name].at, k)
		table.insert(list, {
			name = j.name,
			part0 = j.part0,
			part1 = j.part1,
			at = at,
			c0 = vsub(at, outParts[j.part0].pos),
			c1 = vsub(at, outParts[j.part1].pos),
		})
	end
	return { kind = "r15", scale = k, root = "HumanoidRootPart", parts = outParts, joints = list }
end

-- bones(formModule, scale?) -> rig from a Ranch form module ({ bones = { {name, parent, cframe} } }).
function Rig.bones(form: any, scale: number?): any
	local list = {}
	for i, b in form.bones do
		table.insert(list, { name = b.name, parent = b.parent, cframe = table.clone(b.cframe), index = i })
	end
	return { kind = "bones", scale = scale or 1, bones = list }
end

-- leg(rig, side) -> upper, lower lengths (studs) of a leg, for foot planting.
function Rig.leg(rig: any, side: string): (number, number)
	local hip, knee, ankle
	for _, j in rig.joints do
		if j.name == side .. "Hip" then
			hip = j.at
		elseif j.name == side .. "Knee" then
			knee = j.at
		elseif j.name == side .. "Ankle" then
			ankle = j.at
		end
	end
	assert(hip and knee and ankle, "Rig.leg: the rig has no " .. side .. " leg")
	return hip[2] - knee[2], knee[2] - ankle[2]
end

local function poseTransform(p: any): ({ number }, { number })
	if p == nil then
		return { 0, 0, 0 }, table.clone(M.IDENTITY) :: any
	end
	if p.qw ~= nil then
		return { p.x or 0, p.y or 0, p.z or 0 }, M.fromQuat({ x = p.qx or 0, y = p.qy or 0, z = p.qz or 0, w = p.qw })
	end
	return { p.x or 0, p.y or 0, p.z or 0 }, M.anglesDeg(p.rx or 0, p.ry or 0, p.rz or 0)
end

-- compose(parent frame, local pos, local rot) -> world frame
local function compose(f: Frame, pos: { number }, rot: { number }): Frame
	local p = M.apply(f.rot, pos)
	return { pos = { f.pos[1] + p[1], f.pos[2] + p[2], f.pos[3] + p[3] }, rot = M.mul(f.rot, rot) }
end

-- fk(rig, pose, root?) -> { [part or bone name] = Frame } in rig space.
function Rig.fk(rig: any, pose: { [string]: any }?, root: Frame?): { [string]: Frame }
	local P = pose or {}
	local out: { [string]: Frame } = {}
	local I = table.clone(M.IDENTITY) :: any
	if rig.kind == "r15" then
		local r = rig.parts[rig.root].pos
		out[rig.root] = root or { pos = { r[1], r[2], r[3] }, rot = I }
		-- joints are listed parent-first (Atelier Bodies.JOINTS)
		for _, j in rig.joints do
			local f0 = out[j.part0]
			assert(f0, "Rig.fk: joint " .. j.name .. " comes before its parent part " .. j.part0)
			local tp, tr = poseTransform(P[j.name])
			local a = compose(f0, j.c0, I)
			local b = compose(a, tp, tr)
			out[j.part1] = compose(b, { -j.c1[1], -j.c1[2], -j.c1[3] }, I)
		end
		return out
	end
	local k = rig.scale or 1
	local base: Frame = root or { pos = { 0, 0, 0 }, rot = I }
	for _, b in rig.bones do
		local parent = if b.parent == 0 then base else out[rig.bones[b.parent].name]
		assert(parent, "Rig.fk: bone " .. b.name .. " comes before its parent")
		local c = b.cframe
		local rest = compose(parent, { c[1] * k, c[2] * k, c[3] * k }, M.fromQuat({ x = c[4], y = c[5], z = c[6], w = c[7] }))
		local tp, tr = poseTransform(P[b.name])
		out[b.name] = compose(rest, vscale(tp, k), tr)
	end
	return out
end

return Rig
