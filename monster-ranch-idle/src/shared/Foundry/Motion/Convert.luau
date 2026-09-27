--!strict
-- Convert: game clips <-> ClipDoc, each direction exact.
--
--   Convert.fromGuildhall(clip) -> doc     Guildhall ClientAnim clip (kind rig | procedural)
--   Convert.toGuildhall(doc) -> clip       deep-equal to the clip it came from
--   Convert.fromRanch(name, clip, boneNames, opts?) -> doc
--       clip = { fps, frames, data = base64 text | buffer } (MeshMonsters/<form>.clips.<name>,
--       MeshMonsterClips/<form>.clips.<name>); opts = { loop?, form?, source? }
--   Convert.toRanch(doc) -> { fps, frames, data = buffer }    byte-exact buffer
--   Convert.ranchText(doc) -> the base64 text as the module wrote it (line width and
--       trailing newline kept in doc.meta.text), so even the source text round-trips.
--   Convert.equal(a, b) -> ok, where   deep equality, naming the first difference
--
-- Guildhall rig keyframes become one pose track per joint (sorted by joint name); a keyframe's
-- ease rides on each of its keys. A keyframe with no poses at all is kept in
-- meta.emptyKeys; clip fields Motion has no slot for are kept in meta.extra; a clip whose
-- `loop` was absent (not false) says so in meta.loopUnset.

local Base64 = require("./Base64")

local Convert = {}
local FORMAT = "motion.clip/1"

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

local KNOWN = { id = true, kind = true, length = true, loop = true, priority = true, ease = true, keyframes = true, channels = true, markers = true }
local CHANNEL_KNOWN = { target = true, prop = true, ease = true, keys = true }

function Convert.fromGuildhall(clip: any): any
	assert(type(clip) == "table" and type(clip.id) == "string", "fromGuildhall: not a clip")
	local doc: any = {
		format = FORMAT,
		id = clip.id,
		length = clip.length,
		loop = clip.loop == true,
		rig = if clip.kind == "procedural" then "parts" else "r15",
		priority = clip.priority,
		ease = clip.ease,
		markers = deepCopy(clip.markers),
		tracks = {},
	}
	local meta: any = { source = "guildhall" }
	if clip.loop == nil then
		meta.loopUnset = true
	end
	local extra = {}
	for k, v in clip do
		if not KNOWN[k] then
			extra[k] = deepCopy(v)
		end
	end
	if next(extra) ~= nil then
		meta.extra = extra
	end
	if clip.kind == "procedural" then
		for _, ch in clip.channels do
			local tr: any = { kind = "pose", joint = ch.target, prop = ch.prop, ease = ch.ease, keys = deepCopy(ch.keys) }
			for k, v in ch do
				if not CHANNEL_KNOWN[k] then
					tr.extra = tr.extra or {}
					tr.extra[k] = deepCopy(v)
				end
			end
			table.insert(doc.tracks, tr)
		end
	else
		local byJoint: { [string]: any } = {}
		local names = {}
		local empty = {}
		for _, kf in clip.keyframes do
			if next(kf.poses) == nil then
				table.insert(empty, { t = kf.t, ease = kf.ease })
			end
			for joint, pose in kf.poses do
				local tr = byJoint[joint]
				if tr == nil then
					tr = { kind = "pose", joint = joint, keys = {} }
					byJoint[joint] = tr
					table.insert(names, joint)
				end
				table.insert(tr.keys, { t = kf.t, value = deepCopy(pose), ease = kf.ease })
			end
		end
		table.sort(names)
		for _, n in names do
			table.sort(byJoint[n].keys, function(a, b)
				return a.t < b.t
			end)
			table.insert(doc.tracks, byJoint[n])
		end
		if #empty > 0 then
			meta.emptyKeys = empty
		end
	end
	doc.meta = meta
	return doc
end

function Convert.toGuildhall(doc: any): any
	local meta = doc.meta or {}
	local clip: any = {
		id = doc.id,
		kind = if doc.rig == "parts" then "procedural" else "rig",
		length = doc.length,
		priority = doc.priority,
		ease = doc.ease,
		markers = deepCopy(doc.markers),
	}
	if not meta.loopUnset then
		clip.loop = doc.loop
	end
	for k, v in meta.extra or {} do
		clip[k] = deepCopy(v)
	end
	if doc.rig == "parts" then
		clip.channels = {}
		for _, tr in doc.tracks do
			local ch: any = { target = tr.joint, prop = tr.prop, ease = tr.ease, keys = deepCopy(tr.keys) }
			for k, v in tr.extra or {} do
				ch[k] = deepCopy(v)
			end
			table.insert(clip.channels, ch)
		end
		return clip
	end
	assert(doc.rig == "r15", "toGuildhall: a " .. tostring(doc.rig) .. " clip has no Guildhall form")
	local byT: { [number]: any } = {}
	local times = {}
	local function frameAt(t: number, ease: string?): any
		local kf = byT[t]
		if kf == nil then
			kf = { t = t, poses = {}, ease = ease }
			byT[t] = kf
			table.insert(times, t)
		end
		return kf
	end
	for _, tr in doc.tracks do
		for _, k in tr.keys do
			frameAt(k.t, k.ease).poses[tr.joint] = deepCopy(k.value)
		end
	end
	for _, e in meta.emptyKeys or {} do
		frameAt(e.t, e.ease)
	end
	table.sort(times)
	clip.keyframes = {}
	for _, t in times do
		table.insert(clip.keyframes, byT[t])
	end
	return clip
end

-- The Ranch -------------------------------------------------------------------------------

local function textShape(text: string): any
	local body = if string.sub(text, 1, 1) == "\n" then string.sub(text, 2) else text
	local first = string.match(body, "^([^\n]*)\n")
	return {
		wrap = if first then #first else 0,
		lead = string.sub(text, 1, 1) == "\n",
		trail = string.sub(text, -1) == "\n",
		pad = string.find(text, "=", 1, true) ~= nil,
	}
end

function Convert.fromRanch(name: string, clip: any, boneNames: { string }, opts: any?): any
	local o = opts or {}
		local buf: buffer, meta: any = nil :: any, { source = "ranch", form = o.form, file = o.source }
	if type(clip.data) == "string" then
		buf = Base64.decode(clip.data)
		meta.text = textShape(clip.data)
	else
		buf = clip.data
	end
	local frames, fps = clip.frames, clip.fps
	return {
		format = FORMAT,
		id = name,
		length = (frames - 1) / fps,
		loop = o.loop == true,
		rig = "bones",
		tracks = {
			{
				kind = "sampled",
				fps = fps,
				frames = frames,
				bones = table.clone(boneNames),
				encoding = "f32le-b64",
				layout = "qx,qy,qz,qw,px,py,pz",
				data = Base64.encode(buf),
			},
		},
		meta = meta,
	}
end

function Convert.toRanch(doc: any): any
	assert(doc.rig == "bones", "toRanch: a " .. tostring(doc.rig) .. " clip has no Ranch form")
	local tr = doc.tracks[1]
	return { fps = tr.fps, frames = tr.frames, data = Base64.decode(tr.data) }
end

-- ranchText(doc) -> the module's base64 text: wrapped at meta.text.wrap, with its leading /
-- trailing newline and "=" padding as it was (the modules wrap at a fixed width).
function Convert.ranchText(doc: any): string
	local s = doc.tracks[1].data
	local shape = (doc.meta or {}).text or { wrap = 0 }
	if shape.pad == false then
		s = string.gsub(s, "=", "")
	end
	local w = shape.wrap or 0
	if w > 0 then
		local lines = {}
		for i = 1, #s, w do
			table.insert(lines, string.sub(s, i, i + w - 1))
		end
		s = table.concat(lines, "\n")
	end
	if shape.lead then
		s = "\n" .. s
	end
	if shape.trail then
		s ..= "\n"
	end
	return s
end

-- equal(a, b) -> true | false, "<path>: <a> vs <b>"
function Convert.equal(a: any, b: any, path: string?): (boolean, string?)
	local p = path or "clip"
	if type(a) ~= type(b) then
		return false, `{p}: {typeof(a)} vs {typeof(b)}`
	end
	if type(a) == "buffer" then
		if buffer.len(a) ~= buffer.len(b) then
			return false, `{p}: {buffer.len(a)} bytes vs {buffer.len(b)}`
		end
		for i = 0, buffer.len(a) - 1 do
			if buffer.readu8(a, i) ~= buffer.readu8(b, i) then
				return false, `{p}: byte {i} differs`
			end
		end
		return true, nil
	end
	if type(a) ~= "table" then
		if a ~= b then
			return false, `{p}: {tostring(a)} vs {tostring(b)}`
		end
		return true, nil
	end
	for k, v in a do
		local ok, why = Convert.equal(v, b[k], p .. "." .. tostring(k))
		if not ok then
			return false, why
		end
	end
	for k, v in b do
		if a[k] == nil then
			return false, `{p}.{tostring(k)}: missing vs {tostring(v)}`
		end
	end
	return true, nil
end

return Convert
