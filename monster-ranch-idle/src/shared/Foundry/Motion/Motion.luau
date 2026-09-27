--!strict
-- Motion (CH2 Motion Lab): one clip format for both kinds of rig, and the pure functions that
-- play it. Game-neutral: no Roblox services; a game's player sets Motor6D / Bone transforms
-- from what `sample` returns.
--
--   local Motion = require("../Motion/Motion")
--   local problems = Motion.validate(doc)                 -- {} when the ClipDoc is sound
--   local pose = Motion.sample(doc, t, loop?)             -- joint -> transform (see below)
--   local mix = Motion.blend(poseA, poseB, 0.3)
--   local body = Motion.layer({ { pose = walk }, { pose = wave, mask = "upper" } })
--   local events = Motion.markers(doc, t0, t1, loop?)    -- markers crossed in (t0, t1]
--   Motion.Convert.fromGuildhall(clip) / toGuildhall(doc) / fromRanch(...) / toRanch(doc)
--   Motion.Procedural.*   breathe, blink, lookAt, footPlant, lean, LOD rules
--   Motion.Library        work loops, emotes, role and reaction maps
--
-- ClipDoc (JSON, and the same shape as a Luau table; schema: foundry/tools/motion/clip.schema.json)
--   { format = "motion.clip/1", id, length, loop, rig = "r15" | "parts" | "bones",
--     priority?, ease?, markers? = { { t, name } }, meta?,
--     tracks = { PoseTrack | SampledTrack } }
--   PoseTrack    { kind = "pose", joint, prop?, ease?, keys = { { t, value, ease? } } }
--       r15:   value = { x?, y?, z?, rx?, ry?, rz? } (studs, degrees; missing = 0), no prop
--       parts: joint = a descendant name, prop = offset | rotation | scale | transparency |
--              brightness, value = number or { x?, y?, z? }
--       A key's ease shapes the segment FROM it (key ease, else track ease, else clip ease,
--       else linear), as Guildhall's ClientAnim does.
--   SampledTrack { kind = "sampled", fps, frames, bones = { name }, encoding = "f32le-b64",
--                  layout = "qx,qy,qz,qw,px,py,pz", data = base64 }
--       frame-major: frame f, bone i at byte ((f * #bones) + i - 1) * 28 (the Ranch buffer).
--
-- sample output: r15 -> { [joint] = { x, y, z, rx, ry, rz } }; parts -> { [target] = { [prop]
-- = v } }; bones -> { [bone] = { x, y, z, qx, qy, qz, qw } }. A joint absent from a clip is
-- absent from its samples, so an upper-body clip layers over a walk.

local Ease = require("./Ease")
local M = require("./Math")
local Base64 = require("./Base64")

local Motion = {}
Motion.FORMAT = "motion.clip/1"
Motion.Ease = Ease
Motion.Math = M

local POSE_KEYS = { x = true, y = true, z = true, rx = true, ry = true, rz = true }
local PROPS: { [string]: string } = {
	offset = "vector",
	rotation = "vector",
	scale = "scale",
	transparency = "number",
	brightness = "number",
}
Motion.PROPS = table.freeze(table.clone(PROPS))
Motion.RIGS = table.freeze({ r15 = true, parts = true, bones = true })
Motion.PRIORITIES = table.freeze({ "Core", "Idle", "Movement", "Action", "Action2", "Action3", "Action4" })
local BYTES_PER_BONE = 28

-- Masks for layer(): which R15 joints a layer may drive.
Motion.MASKS = table.freeze({
	upper = table.freeze({
		Waist = true, Neck = true,
		LeftShoulder = true, LeftElbow = true, LeftWrist = true,
		RightShoulder = true, RightElbow = true, RightWrist = true,
	}),
	lower = table.freeze({
		Root = true,
		LeftHip = true, LeftKnee = true, LeftAnkle = true,
		RightHip = true, RightKnee = true, RightAnkle = true,
	}),
	arms = table.freeze({
		LeftShoulder = true, LeftElbow = true, LeftWrist = true,
		RightShoulder = true, RightElbow = true, RightWrist = true,
	}),
	head = table.freeze({ Neck = true }),
})

Motion.b64decode = Base64.decode
Motion.b64encode = Base64.encode

----------------------------------------------------------------------------------------
-- validate
----------------------------------------------------------------------------------------

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isVector(v: any): boolean
	if type(v) ~= "table" then
		return false
	end
	for k, c in v do
		if (k ~= "x" and k ~= "y" and k ~= "z") or not isNum(c) then
			return false
		end
	end
	return true
end

local function checkValue(where: string, doc: any, tr: any, v: any, errs: { string })
	if doc.rig == "r15" then
		if type(v) ~= "table" then
			table.insert(errs, where .. ": a pose value must be a table of x y z rx ry rz")
			return
		end
		for k, c in v do
			if not POSE_KEYS[k] then
				table.insert(errs, where .. ": unknown pose component '" .. tostring(k) .. "'")
			elseif not isNum(c) then
				table.insert(errs, where .. ": " .. tostring(k) .. " must be a finite number")
			end
		end
		return
	end
	local kind = PROPS[tr.prop]
	if kind == "vector" and not isVector(v) then
		table.insert(errs, where .. ": " .. tr.prop .. " needs { x?, y?, z? }")
	elseif kind == "number" and not isNum(v) then
		table.insert(errs, where .. ": " .. tr.prop .. " needs a number")
	elseif kind == "scale" and not (isNum(v) or isVector(v)) then
		table.insert(errs, where .. ": scale needs a number or { x?, y?, z? }")
	end
end

-- validate(doc) -> problems ({} = sound). Every problem names where it is.
function Motion.validate(doc: any): { string }
	local errs: { string } = {}
	if type(doc) ~= "table" then
		return { "clip: not a table" }
	end
	local id = if type(doc.id) == "string" then doc.id else "?"
	local function bad(msg: string)
		table.insert(errs, id .. ": " .. msg)
	end
	if doc.format ~= Motion.FORMAT then
		bad("format must be '" .. Motion.FORMAT .. "', got " .. tostring(doc.format))
	end
	if type(doc.id) ~= "string" or doc.id == "" then
		bad("id must be a non-empty string")
	end
	if not isNum(doc.length) or doc.length < 0 then
		bad("length must be a number >= 0")
	end
	if type(doc.loop) ~= "boolean" then
		bad("loop must be true or false")
	end
	if not Motion.RIGS[doc.rig] then
		bad("rig must be r15, parts or bones, got " .. tostring(doc.rig))
	end
	if doc.ease ~= nil and not Ease.isEasing(doc.ease) then
		bad("unknown clip ease '" .. tostring(doc.ease) .. "'")
	end
	if doc.priority ~= nil and table.find(Motion.PRIORITIES, doc.priority) == nil and type(doc.priority) ~= "number" then
		bad("unknown priority '" .. tostring(doc.priority) .. "'")
	end
	local length = if isNum(doc.length) then doc.length else 0
	if type(doc.tracks) ~= "table" then
		bad("tracks must be a list")
	else
		local seen: { [string]: boolean } = {}
		for i, tr in doc.tracks do
			local w = `track {i}`
			if type(tr) ~= "table" then
				bad(w .. ": not a table")
				continue
			end
			if tr.kind == "pose" then
				if doc.rig == "bones" then
					bad(w .. ": a bones clip holds sampled tracks only")
				end
				if type(tr.joint) ~= "string" or tr.joint == "" then
					bad(w .. ": joint must be a name")
				end
				w = `track {i} ({tr.joint})`
				local key = tostring(tr.joint) .. "/" .. tostring(tr.prop)
				if doc.rig == "r15" then
					if tr.prop ~= nil then
						bad(w .. ": an r15 track has no prop")
					end
					if seen[key] then
						bad(w .. ": joint keyed by two tracks")
					end
				elseif PROPS[tr.prop] == nil then
					bad(w .. ": unknown prop '" .. tostring(tr.prop) .. "'")
				end
				seen[key] = true
				if tr.ease ~= nil and not Ease.isEasing(tr.ease) then
					bad(w .. ": unknown ease '" .. tostring(tr.ease) .. "'")
				end
				if type(tr.keys) ~= "table" or #tr.keys == 0 then
					bad(w .. ": keys must be a non-empty list")
					continue
				end
				local last = -math.huge
				for k, key in tr.keys do
					local kw = `{w} key {k}`
					if type(key) ~= "table" or not isNum(key.t) then
						bad(kw .. ": t must be a number")
						continue
					end
					if key.t <= last then
						bad(kw .. ": t=" .. key.t .. " is out of order (keys must strictly increase)")
					end
					last = key.t
					if key.t < 0 or key.t > length + 1e-9 then
						bad(kw .. ": t=" .. key.t .. " is outside 0.." .. length)
					end
					if key.ease ~= nil and not Ease.isEasing(key.ease) then
						bad(kw .. ": unknown ease '" .. tostring(key.ease) .. "'")
					end
					checkValue(id .. ": " .. kw, doc, tr, key.value, errs)
				end
			elseif tr.kind == "sampled" then
				if doc.rig ~= "bones" then
					bad(w .. ": sampled tracks belong to a bones clip")
				end
				if not isNum(tr.fps) or tr.fps <= 0 then
					bad(w .. ": fps must be > 0")
				end
				if not isNum(tr.frames) or tr.frames < 1 or tr.frames % 1 ~= 0 then
					bad(w .. ": frames must be a whole number >= 1")
				end
				if type(tr.bones) ~= "table" or #tr.bones == 0 then
					bad(w .. ": bones must list the bone names")
				end
				if tr.encoding ~= "f32le-b64" or tr.layout ~= "qx,qy,qz,qw,px,py,pz" then
					bad(w .. ": encoding must be f32le-b64 with layout qx,qy,qz,qw,px,py,pz")
				end
				if type(tr.data) ~= "string" then
					bad(w .. ": data must be a base64 string")
				elseif isNum(tr.frames) and type(tr.bones) == "table" then
					local want = tr.frames * #tr.bones * BYTES_PER_BONE
					local got = buffer.len(Motion.b64decode(tr.data))
					if got ~= want then
						bad(`{w}: data holds {got} bytes, {tr.frames} frames x {#tr.bones} bones x 28 = {want}`)
					end
				end
				if isNum(tr.fps) and isNum(tr.frames) and isNum(doc.length) and tr.fps > 0 then
					local want = (tr.frames - 1) / tr.fps
					if math.abs(want - doc.length) > 1e-6 then
						bad(`{w}: length {doc.length} does not match (frames - 1) / fps = {want}`)
					end
				end
			else
				bad(w .. ": kind must be pose or sampled, got " .. tostring(tr.kind))
			end
		end
	end
	if doc.markers ~= nil then
		if type(doc.markers) ~= "table" then
			bad("markers must be a list")
		else
			for i, m in doc.markers do
				if type(m) ~= "table" or type(m.name) ~= "string" or m.name == "" or not isNum(m.t) then
					bad(`marker {i}: needs a name and a number t`)
				elseif m.t < 0 or m.t > length + 1e-9 then
					bad(`marker {i} ({m.name}): t={m.t} is outside 0..{length}`)
				end
			end
		end
	end
	return errs
end

----------------------------------------------------------------------------------------
-- sampling (pose tracks: exactly Guildhall ClientAnim's compile + sampleTrack)
----------------------------------------------------------------------------------------

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end
Motion.deepCopy = deepCopy

local function fullPose(p: any): { [string]: number }
	return { x = p.x or 0, y = p.y or 0, z = p.z or 0, rx = p.rx or 0, ry = p.ry or 0, rz = p.rz or 0 }
end

local function lerpValue(a: any, b: any, w: number): any
	if type(a) == "number" and type(b) == "number" then
		return a + (b - a) * w
	end
	if type(a) == "table" and type(b) == "table" then
		if a.qw ~= nil and b.qw ~= nil then
			local q = M.slerp({ x = a.qx, y = a.qy, z = a.qz, w = a.qw }, { x = b.qx, y = b.qy, z = b.qz, w = b.qw }, w)
			return {
				x = a.x + (b.x - a.x) * w,
				y = a.y + (b.y - a.y) * w,
				z = a.z + (b.z - a.z) * w,
				qx = q.x,
				qy = q.y,
				qz = q.z,
				qw = q.w,
			}
		end
		local out = {}
		for k, av in a do
			local bv = b[k]
			out[k] = if bv == nil then deepCopy(av) else lerpValue(av, bv, w)
		end
		for k, bv in b do
			if a[k] == nil then
				out[k] = deepCopy(bv)
			end
		end
		return out
	end
	return deepCopy(if w < 0.5 then a else b)
end
Motion.lerp = lerpValue

type Key = { t: number, value: any, ease: string }

local function compileTrack(doc: any, tr: any): { Key }
	local clipEase = doc.ease or "linear"
	local keys: { Key } = {}
	if doc.rig == "r15" then
		for _, k in tr.keys do
			table.insert(keys, { t = k.t, value = fullPose(k.value), ease = k.ease or tr.ease or clipEase })
		end
		return keys
	end
	local anyVector = false
	for _, k in tr.keys do
		if type(k.value) == "table" then
			anyVector = true
		end
	end
	for _, k in tr.keys do
		local v = k.value
		if PROPS[tr.prop] == "vector" then
			v = { x = v.x or 0, y = v.y or 0, z = v.z or 0 }
		elseif PROPS[tr.prop] == "scale" then
			if type(v) == "number" then
				if anyVector then
					v = { x = v, y = v, z = v }
				end
			else
				v = { x = v.x or 1, y = v.y or 1, z = v.z or 1 }
			end
		end
		table.insert(keys, { t = k.t, value = v, ease = k.ease or tr.ease or clipEase })
	end
	return keys
end

local function sampleKeys(keys: { Key }, t: number, length: number, loop: boolean): any
	local n = #keys
	if n == 1 then
		return deepCopy(keys[1].value)
	end
	local first, last = keys[1], keys[n]
	if t < first.t or t > last.t then
		if not loop then
			return deepCopy(if t < first.t then first.value else last.value)
		end
		local span = (first.t + length) - last.t
		if span <= 0 then
			return deepCopy(first.value)
		end
		local lt = if t > last.t then t - last.t else t + length - last.t
		return lerpValue(last.value, first.value, Ease.ease(last.ease, lt / span))
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if keys[mid].t <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local a, b = keys[lo], keys[hi]
	if t >= b.t then
		return deepCopy(b.value)
	end
	return lerpValue(a.value, b.value, Ease.ease(a.ease, (t - a.t) / (b.t - a.t)))
end

-- localTime(doc, t, loop?) -> clip time: loops wrap, one-shots clamp.
function Motion.localTime(doc: any, t: number, loop: boolean?): number
	local lp = if loop == nil then doc.loop == true else loop
	local length = doc.length
	if lp then
		if length <= 0 then
			return 0
		end
		local r = t % length
		return if r ~= r then 0 else r
	end
	return math.clamp(t, 0, length)
end

local decoded: { [any]: buffer } = setmetatable({}, { __mode = "k" }) :: any

local function trackBuffer(tr: any): buffer
	local b = decoded[tr]
	if b == nil then
		b = Motion.b64decode(tr.data)
		decoded[tr] = b
	end
	return b
end

-- frame(track, f) -> { [bone] = { x, y, z, qx, qy, qz, qw } } for a whole frame index.
function Motion.frame(tr: any, f: number): { [string]: any }
	local data = trackBuffer(tr)
	local count = #tr.bones
	local out = {}
	for i, name in tr.bones do
		local a = ((f * count) + (i - 1)) * BYTES_PER_BONE
		out[name] = {
			qx = buffer.readf32(data, a),
			qy = buffer.readf32(data, a + 4),
			qz = buffer.readf32(data, a + 8),
			qw = buffer.readf32(data, a + 12),
			x = buffer.readf32(data, a + 16),
			y = buffer.readf32(data, a + 20),
			z = buffer.readf32(data, a + 24),
		}
	end
	return out
end

-- The Ranch's MeshMonster.Pose timing: span = frames - 1, loops wrap on the span (the last
-- frame repeats the first), one-shots hold the last frame.
local function sampleSampled(tr: any, t: number, loop: boolean): { [string]: any }
	local span = tr.frames - 1
	if span <= 0 then
		return Motion.frame(tr, 0)
	end
	local f = t * tr.fps
	f = if loop then f % span else math.clamp(f, 0, span)
	local f0 = math.floor(f)
	local f1 = math.min(f0 + 1, span)
	local alpha = f - f0
	local a = Motion.frame(tr, f0)
	if alpha == 0 then
		return a
	end
	local b = Motion.frame(tr, f1)
	local out = {}
	for name, v in a do
		out[name] = lerpValue(v, b[name], alpha)
	end
	return out
end

-- sample(doc, t, loop?) -> pose at play time t (loop defaults to doc.loop).
function Motion.sample(doc: any, t: number, loop: boolean?): { [string]: any }
	local lp = if loop == nil then doc.loop == true else loop
	local out: { [string]: any } = {}
	if doc.rig == "bones" then
		for _, tr in doc.tracks do
			if tr.kind == "sampled" then
				for name, v in sampleSampled(tr, t, lp) do
					out[name] = v
				end
			end
		end
		return out
	end
	local lt = Motion.localTime(doc, t, lp)
	for _, tr in doc.tracks do
		local v = sampleKeys(compileTrack(doc, tr), lt, doc.length, lp)
		if doc.rig == "parts" then
			local slot = out[tr.joint]
			if not slot then
				slot = {}
				out[tr.joint] = slot
			end
			slot[tr.prop] = v
		else
			out[tr.joint] = v
		end
	end
	return out
end

-- blend(a, b, w): per component a + (b - a) * w (quaternions slerp), w clamped to 0..1. A
-- joint present in only one pose is taken from that pose ("no opinion", not "rest").
function Motion.blend(a: { [string]: any }?, b: { [string]: any }?, w: number): { [string]: any }
	return lerpValue(a or {}, b or {}, math.clamp(w, 0, 1))
end

local function rest(like: any): any
	if like.qw ~= nil then
		return { x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1 }
	end
	return fullPose({})
end

-- layer({ { pose, weight?, mask? } ... }) -> pose. Layers apply in list order: each drives
-- the joints it has AND its mask allows (mask = a MASKS name, a set { [joint] = true } or a
-- list of joint names; nil = every joint), blended over what is below by its weight. A
-- joint nothing below drives blends from rest. `upper` over `walk`: wave the arms, keep
-- walking.
function Motion.layer(layers: { any }): { [string]: any }
	local out: { [string]: any } = {}
	for i, l in layers do
		local mask = l.mask
		if type(mask) == "string" then
			local m = Motion.MASKS[mask]
			assert(m ~= nil, "Motion.layer: unknown mask '" .. mask .. "' on layer " .. i)
			mask = m
		elseif type(mask) == "table" and mask[1] ~= nil then
			local set = {}
			for _, j in mask do
				set[j] = true
			end
			mask = set
		end
		local w = math.clamp(if type(l.weight) == "number" then l.weight else 1, 0, 1)
		if w > 0 and type(l.pose) == "table" then
			for joint, p in l.pose do
				if mask == nil or mask[joint] then
					local v = if p.qw ~= nil then p else fullPose(p)
					out[joint] = lerpValue(out[joint] or rest(v), v, w)
				end
			end
		end
	end
	return out
end

-- add(base, offsets) -> base with procedural offsets added per component (degrees / studs):
-- how a Procedural layer goes on top of a sampled clip.
function Motion.add(base: { [string]: any }, offsets: { [string]: any }): { [string]: any }
	local out = deepCopy(base)
	for joint, off in offsets do
		local p = out[joint] or fullPose({})
		for k, v in off do
			if POSE_KEYS[k] then
				p[k] = (p[k] or 0) + v
			end
		end
		out[joint] = p
	end
	return out
end

Motion.Markers = require("./Markers")
Motion.markers = Motion.Markers.crossed
Motion.Convert = require("./Convert")
Motion.Procedural = require("./Procedural")
Motion.Rig = require("./Rig")
Motion.Library = require("./library/Library")

-- new(adapter, opts?) -> a small player facade over the pure functions, logging through the
-- Contract adapter: player.markers(doc, t0, t1) emits "Motion.Marker" events with bindings.
function Motion.new(adapter: any, opts: any?): any
	local Contract = require("../Contract/Contract")
	local problems = Contract.check(adapter)
	assert(#problems == 0, "Motion.new: " .. table.concat(problems, "; "))
	local o = opts or {}
	local self = { adapter = adapter, bindings = o.bindings or {} }
	function self.markers(doc: any, t0: number, t1: number, loop: boolean?): { any }
		local events = Motion.Markers.bind(Motion.Markers.crossed(doc, t0, t1, loop), self.bindings)
		for _, e in events do
			adapter.emit("Motion.Marker", e)
		end
		return events
	end
	return self
end

return Motion
