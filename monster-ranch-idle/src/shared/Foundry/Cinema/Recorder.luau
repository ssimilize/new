--!strict
-- Recorder: records camera samples at N Hz, simplifies them (Ramer-Douglas-Peucker) and exports
-- path.json, the camera path format Shot Rig and Reels read (schema:
-- foundry/tools/cinema/path.schema.json; the Python twin is foundry/tools/cinema/path.py).
--
--   local rec = Recorder.new({ hz = 30 })
--   rec.push(t, { position = Vec3, lookAt = Vec3, fov = number }) -> accepted
--       t in seconds, increasing; a sample earlier than the next 1/hz slot is skipped (so a 60 fps
--       frame loop records 30 samples a second), a late frame resets the slot (no bursts)
--   rec.samples() -> { { t, position, lookAt, fov } }   rec.clear()
--
--   Recorder.simplify(samples, tolerance, fovTolerance?) -> kept samples, kept indices
--       RDP with the synchronised distance: a sample is kept when its position or look target is
--       more than `tolerance` studs, or its fov more than `fovTolerance` degrees (default 0.5),
--       from the straight TIME-interpolation between the samples kept either side of it, so the
--       timing survives as well as the shape. The first and last samples are always kept.
--   Recorder.export(samples, meta) -> doc      meta = { game?, hz?, tolerance?, fovTolerance?, rawCount? }
--   Recorder.fromDoc(doc) -> samples, problems
--   Recorder.toJson(doc) -> string            deterministic (sorted keys, %.12g numbers)

local Vec = require("./Vec")

type Vec3 = Vec.Vec3

export type Sample = { t: number, position: Vec3, lookAt: Vec3, fov: number }

local Recorder = {}

Recorder.FORMAT = "foundry.cinema.path"
Recorder.VERSION = 1
Recorder.DEFAULT_FOV_TOLERANCE = 0.5

local fin = Vec.finiteNumber

export type Rec = {
	push: (t: number, s: any) -> boolean,
	samples: () -> { Sample },
	clear: () -> (),
	hz: number,
}

function Recorder.new(opts: any?): Rec
	local o = opts or {}
	local hz = o.hz or 30
	assert(fin(hz) and hz > 0 and hz <= 240, "Recorder.new: hz must be in (0, 240]")
	local period = 1 / hz
	local list: { Sample } = {}
	local due: number? = nil
	local lastT = -math.huge
	local rec = {} :: any
	rec.hz = hz
	rec.push = function(t: number, s: any): boolean
		if not fin(t) or t <= lastT then
			return false
		end
		if due ~= nil and t + 1e-9 < due then
			return false
		end
		local p, l = Vec.of(s and s.position), Vec.of(s and s.lookAt)
		local fov = s and s.fov
		if not (p and l and fin(fov)) then
			return false
		end
		table.insert(list, { t = t, position = p, lookAt = l, fov = fov })
		lastT = t
		local nextDue = (due or t) + period
		if nextDue <= t then
			nextDue = t + period
		end
		due = nextDue
		return true
	end
	rec.samples = function()
		return table.clone(list)
	end
	rec.clear = function()
		table.clear(list)
		due = nil
		lastT = -math.huge
	end
	return rec :: Rec
end

-- simplify -----------------------------------------------------------------------------------

local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

-- The worst normalised error of sample i against the time-interpolation of a..b (1 = at tolerance).
local function errorAt(s: { Sample }, a: number, b: number, i: number, tol: number, fovTol: number): number
	local A, Bs, P = s[a], s[b], s[i]
	local span = Bs.t - A.t
	local k = if span > 0 then (P.t - A.t) / span else 0
	local px = lerp(A.position.x, Bs.position.x, k)
	local py = lerp(A.position.y, Bs.position.y, k)
	local pz = lerp(A.position.z, Bs.position.z, k)
	local lx = lerp(A.lookAt.x, Bs.lookAt.x, k)
	local ly = lerp(A.lookAt.y, Bs.lookAt.y, k)
	local lz = lerp(A.lookAt.z, Bs.lookAt.z, k)
	local ax, ay, az = P.position.x - px, P.position.y - py, P.position.z - pz
	local bx, by, bz = P.lookAt.x - lx, P.lookAt.y - ly, P.lookAt.z - lz
	-- products, not ^2: the Python twin (foundry/tools/cinema/path.py) must agree bit for bit
	local dp = math.sqrt(ax * ax + ay * ay + az * az)
	local dl = math.sqrt(bx * bx + by * by + bz * bz)
	local df = math.abs(P.fov - lerp(A.fov, Bs.fov, k))
	local e = math.max(dp / tol, dl / tol)
	return math.max(e, df / fovTol)
end

function Recorder.simplify(samples: { Sample }, tolerance: number, fovTolerance: number?): ({ Sample }, { number })
	assert(fin(tolerance) and tolerance > 0, "Recorder.simplify: tolerance must be > 0 studs")
	local fovTol = fovTolerance or Recorder.DEFAULT_FOV_TOLERANCE
	assert(fin(fovTol) and fovTol > 0, "Recorder.simplify: fovTolerance must be > 0 degrees")
	local n = #samples
	if n <= 2 then
		local idx = {}
		for i = 1, n do
			table.insert(idx, i)
		end
		return table.clone(samples), idx
	end
	local keep = table.create(n, false)
	keep[1], keep[n] = true, true
	local stack = { { 1, n } }
	while #stack > 0 do
		local seg = table.remove(stack) :: { number }
		local a, b = seg[1], seg[2]
		local worst, at = 0, 0
		for i = a + 1, b - 1 do
			local e = errorAt(samples, a, b, i, tolerance, fovTol)
			if e > worst then
				worst, at = e, i
			end
		end
		if worst > 1 then
			keep[at] = true
			table.insert(stack, { a, at })
			table.insert(stack, { at, b })
		end
	end
	local out, idx = {}, {}
	for i = 1, n do
		if keep[i] then
			table.insert(out, samples[i])
			table.insert(idx, i)
		end
	end
	return out, idx
end

-- path.json --------------------------------------------------------------------------------------

local function round(v: number): number
	-- 1e-4 stud / degree / second: small files, far below anything a camera can show
	return math.floor(v * 10000 + 0.5) / 10000
end

function Recorder.export(samples: { Sample }, meta: any?): any
	local m = meta or {}
	local list = {}
	for _, s in ipairs(samples) do
		table.insert(list, {
			t = round(s.t),
			pos = { round(s.position.x), round(s.position.y), round(s.position.z) },
			look = { round(s.lookAt.x), round(s.lookAt.y), round(s.lookAt.z) },
			fov = round(s.fov),
		})
	end
	local t0 = if #samples > 0 then samples[1].t else 0
	local t1 = if #samples > 0 then samples[#samples].t else 0
	return {
		format = Recorder.FORMAT,
		version = Recorder.VERSION,
		game = m.game,
		hz = m.hz,
		simplified = m.tolerance ~= nil,
		tolerance = m.tolerance,
		fovTolerance = if m.tolerance ~= nil then (m.fovTolerance or Recorder.DEFAULT_FOV_TOLERANCE) else nil,
		rawCount = m.rawCount or #samples,
		duration = round(t1 - t0),
		samples = list,
	}
end

function Recorder.fromDoc(doc: any): ({ Sample }, { string })
	local problems = {}
	local out: { Sample } = {}
	if type(doc) ~= "table" then
		return out, { "path doc must be an object" }
	end
	if doc.format ~= Recorder.FORMAT then
		table.insert(problems, `format must be "{Recorder.FORMAT}", got {tostring(doc.format)}`)
	end
	if doc.version ~= Recorder.VERSION then
		table.insert(problems, `version must be {Recorder.VERSION}, got {tostring(doc.version)}`)
	end
	if type(doc.samples) ~= "table" then
		table.insert(problems, "samples must be a list")
		return out, problems
	end
	local last = -math.huge
	for i, s in ipairs(doc.samples) do
		local p, l = Vec.of(s.pos), Vec.of(s.look)
		if not (fin(s.t) and p and l and fin(s.fov)) then
			table.insert(problems, `samples[{i}] needs t, pos [x,y,z], look [x,y,z] and fov`)
		elseif s.t <= last then
			table.insert(problems, `samples[{i}] t {s.t} is not after {last}`)
		else
			last = s.t
			table.insert(out, { t = s.t, position = p :: Vec3, lookAt = l :: Vec3, fov = s.fov })
		end
	end
	return out, problems
end

-- a small deterministic JSON writer (the package cannot use HttpService) -------------------------

local function encode(v: any, out: { string })
	local ty = type(v)
	if v == nil then
		table.insert(out, "null")
	elseif ty == "boolean" then
		table.insert(out, if v then "true" else "false")
	elseif ty == "number" then
		assert(fin(v), "Recorder.toJson: non-finite number")
		if v == math.floor(v) and math.abs(v) < 1e15 then
			table.insert(out, string.format("%d", v))
		else
			table.insert(out, string.format("%.12g", v))
		end
	elseif ty == "string" then
		local s = string.gsub(v, '[%c"\\]', function(c: string): string
			if c == '"' then
				return '\\"'
			elseif c == "\\" then
				return "\\\\"
			elseif c == "\n" then
				return "\\n"
			elseif c == "\t" then
				return "\\t"
			end
			return string.format("\\u%04x", string.byte(c))
		end)
		table.insert(out, '"' .. s .. '"')
	elseif ty == "table" then
		if #v > 0 or next(v) == nil then
			table.insert(out, "[")
			for i, x in ipairs(v) do
				if i > 1 then
					table.insert(out, ",")
				end
				encode(x, out)
			end
			table.insert(out, "]")
		else
			local keys = {}
			for k in v do
				table.insert(keys, tostring(k))
			end
			table.sort(keys)
			table.insert(out, "{")
			for i, k in ipairs(keys) do
				if i > 1 then
					table.insert(out, ",")
				end
				encode(k, out)
				table.insert(out, ":")
				encode(v[k], out)
			end
			table.insert(out, "}")
		end
	else
		error("Recorder.toJson: cannot encode a " .. ty)
	end
end

function Recorder.toJson(doc: any): string
	local out = {}
	encode(doc, out)
	return table.concat(out)
end

return Recorder
