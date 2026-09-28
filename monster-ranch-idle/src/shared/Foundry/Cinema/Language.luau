--!strict
-- Language: a game's camera language as data, and `frame(target, zoomBand)` -> the pose that
-- camera would take. Two kinds:
--
--   god   a near-orthographic orbit camera over a focus on the ground (Guildhall GodCamera):
--         profile.god = { pitch, fov, bands = {studs...}, defaultBand, fineMin, fineMax,
--                         yawSnaps, yawOffset, snapSeconds?, snapEase? }
--         distance = bands[band] * fine; the camera sits `pitch` degrees above the horizon on the
--         `yaw` side of the focus (yaw 0 = +Z side, looking toward -Z; snaps at
--         yawOffset + k * 360 / yawSnaps).
--   rig   a third-person framing rig (Monster Ranch CameraDirector / Logic/Cinematic.Frame):
--         profile.rig = { fov, pitch, lookUp, minDistance, maxDistance, bands = {fill...},
--                         defaultBand, defaultHeight }
--         a subject `height` studs tall fills `bands[band]` of the screen height, seen from
--         `pitch` degrees above its look point, on the side the current camera (`from`) is on.
--
--   local lang = Language.new(profile)
--   lang.frame(target, zoom?, opts?) -> Pose
--       target  god: a Vec3 focus (y defaults to 0) or { position = Vec3 }
--               rig: { position = base Vec3, height = studs?, from = camera Vec3? } or a Vec3
--       zoom    a band index, { band, fine } (god), or nil for the profile's defaultBand
--       opts    { yaw = degrees } or { snap = 0..yawSnaps-1 } (god); { yaw = degrees } (rig)
--   Pose = { position, lookAt, look (unit), fov, distance, yaw, pitch, band, fine }

local Vec = require("./Vec")

type Vec3 = Vec.Vec3

export type Pose = {
	position: Vec3,
	lookAt: Vec3,
	look: Vec3,
	fov: number,
	distance: number,
	yaw: number,
	pitch: number,
	band: number,
	fine: number,
}

local Language = {}

local RAD = math.pi / 180
local fin = Vec.finiteNumber

local function need(problems: { string }, cond: boolean, msg: string)
	if not cond then
		table.insert(problems, msg)
	end
end

local function increasing(list: any, lo: number, hi: number): boolean
	if type(list) ~= "table" or #list == 0 then
		return false
	end
	local last = -math.huge
	for _, v in ipairs(list) do
		if not fin(v) or v <= last or v <= lo or v > hi then
			return false
		end
		last = v
	end
	return true
end

-- validate(profile) -> { problem strings }, empty when the profile is usable.
function Language.validate(p: any): { string }
	local problems = {}
	if type(p) ~= "table" then
		return { "profile must be a table" }
	end
	need(problems, type(p.game) == "string", "profile.game must be a string")
	if p.kind == "god" then
		local g = p.god
		if type(g) ~= "table" then
			table.insert(problems, "profile.god must be a table for kind 'god'")
			return problems
		end
		need(problems, fin(g.pitch) and g.pitch > 0 and g.pitch < 90, "god.pitch must be in (0, 90) degrees")
		need(problems, fin(g.fov) and g.fov >= 1 and g.fov <= 120, "god.fov must be in [1, 120]")
		need(problems, increasing(g.bands, 0, 1e5), "god.bands must be a strictly increasing list of positive studs")
		local n = type(g.bands) == "table" and #g.bands or 0
		need(problems, fin(g.defaultBand) and g.defaultBand >= 1 and g.defaultBand <= n and g.defaultBand % 1 == 0, "god.defaultBand must be a band index")
		need(problems, fin(g.fineMin) and fin(g.fineMax) and g.fineMin > 0 and g.fineMin <= 1 and g.fineMax >= 1, "god.fineMin <= 1 <= god.fineMax, both > 0")
		need(problems, fin(g.yawSnaps) and g.yawSnaps >= 1 and g.yawSnaps % 1 == 0, "god.yawSnaps must be a whole number >= 1")
		need(problems, fin(g.yawOffset), "god.yawOffset must be a number (degrees)")
	elseif p.kind == "rig" then
		local r = p.rig
		if type(r) ~= "table" then
			table.insert(problems, "profile.rig must be a table for kind 'rig'")
			return problems
		end
		need(problems, fin(r.fov) and r.fov >= 1 and r.fov <= 120, "rig.fov must be in [1, 120]")
		need(problems, fin(r.pitch) and r.pitch > -90 and r.pitch < 90, "rig.pitch must be in (-90, 90) degrees")
		need(problems, fin(r.lookUp) and r.lookUp >= 0 and r.lookUp <= 1, "rig.lookUp must be in [0, 1]")
		need(problems, fin(r.minDistance) and fin(r.maxDistance) and r.minDistance > 0 and r.maxDistance >= r.minDistance, "rig.minDistance <= rig.maxDistance, both > 0")
		local okBands = type(r.bands) == "table" and #r.bands > 0
		if okBands then
			for _, f in ipairs(r.bands) do
				if not (fin(f) and f > 0 and f <= 1) then
					okBands = false
				end
			end
		end
		need(problems, okBands, "rig.bands must be a list of screen fills in (0, 1]")
		local n = type(r.bands) == "table" and #r.bands or 0
		need(problems, fin(r.defaultBand) and r.defaultBand >= 1 and r.defaultBand <= n and r.defaultBand % 1 == 0, "rig.defaultBand must be a band index")
		need(problems, fin(r.defaultHeight) and r.defaultHeight > 0, "rig.defaultHeight must be > 0 studs")
	else
		table.insert(problems, "profile.kind must be 'god' or 'rig', got " .. tostring(p.kind))
	end
	return problems
end

-- The god camera's formulas (Guildhall GodCamera Logic.orbit / Logic.lookVector) -------------

function Language.orbit(focus: Vec3, pitchDeg: number, yawDeg: number, distance: number): Vec3
	local p, y = pitchDeg * RAD, yawDeg * RAD
	local h = math.cos(p) * distance
	return { x = focus.x + h * math.sin(y), y = focus.y + math.sin(p) * distance, z = focus.z + h * math.cos(y) }
end

function Language.lookVector(pitchDeg: number, yawDeg: number): Vec3
	local p, y = pitchDeg * RAD, yawDeg * RAD
	return { x = -math.cos(p) * math.sin(y), y = -math.sin(p), z = -math.cos(p) * math.cos(y) }
end

-- The yaws of a god profile's snaps, in order (unwrapped).
function Language.snapYaws(god: any): { number }
	local out = {}
	for k = 0, god.yawSnaps - 1 do
		table.insert(out, god.yawOffset + k * 360 / god.yawSnaps)
	end
	return out
end

-- The distance range one band covers (studs), god kind.
function Language.bandRange(god: any, band: number): (number, number)
	local b = god.bands[band]
	return b * god.fineMin, b * god.fineMax
end

-- The rig's distance for a subject `height` tall at screen `fill` (Cinematic.Frame's formula).
function Language.rigDistance(rig: any, height: number, fill: number): number
	local h = math.max(height, 0.5)
	return math.clamp(h / fill / (2 * math.tan(rig.fov * RAD / 2)), rig.minDistance, rig.maxDistance)
end

local function targetPoint(target: any): Vec3?
	local v = Vec.of(target)
	if v then
		return v
	end
	if type(target) == "table" then
		local p = target.position
		if type(p) == "table" then
			local x, y, z = p.x or p[1], p.y or p[2] or 0, p.z or p[3]
			if fin(x) and fin(y) and fin(z) then
				return { x = x, y = y, z = z }
			end
		end
		-- a ground point { x, z } (y = 0)
		if fin(target.x) and fin(target.z) and target.y == nil then
			return { x = target.x, y = 0, z = target.z }
		end
	end
	return nil
end

local function frameGod(p: any, target: any, zoom: any, opts: any): Pose
	local g = p.god
	local focus = targetPoint(target)
	assert(focus, "Language.frame: target must be a Vec3 or { position = Vec3 }")
	local band, fine = g.defaultBand, 1
	if type(zoom) == "number" then
		band = zoom
	elseif type(zoom) == "table" then
		band = zoom.band or g.defaultBand
		fine = zoom.fine or 1
	end
	band = math.clamp(math.floor(band + 0.5), 1, #g.bands)
	fine = math.clamp(fine, g.fineMin, g.fineMax)
	local yaw = g.yawOffset
	if opts and fin(opts.yaw) then
		yaw = opts.yaw
	elseif opts and fin(opts.snap) then
		yaw = g.yawOffset + opts.snap * 360 / g.yawSnaps
	end
	local distance = g.bands[band] * fine
	return {
		position = Language.orbit(focus, g.pitch, yaw, distance),
		lookAt = focus,
		look = Language.lookVector(g.pitch, yaw),
		fov = g.fov,
		distance = distance,
		yaw = yaw,
		pitch = g.pitch,
		band = band,
		fine = fine,
	}
end

local function frameRig(p: any, target: any, zoom: any, opts: any): Pose
	local r = p.rig
	local base = targetPoint(target)
	assert(base, "Language.frame: target must be a Vec3 or { position = Vec3, height?, from? }")
	local height = (type(target) == "table" and fin(target.height)) and target.height or r.defaultHeight
	local band = r.defaultBand
	if type(zoom) == "number" then
		band = zoom
	elseif type(zoom) == "table" and zoom.band then
		band = zoom.band
	end
	band = math.clamp(math.floor(band + 0.5), 1, #r.bands)
	local h = math.max(height, 0.5)
	local lookAt = { x = base.x, y = base.y + h * r.lookUp, z = base.z }
	local distance = Language.rigDistance(r, height, r.bands[band])
	local dx, dz
	if opts and fin(opts.yaw) then
		dx, dz = math.sin(opts.yaw * RAD), math.cos(opts.yaw * RAD)
	else
		local from = type(target) == "table" and Vec.of(target.from) or nil
		dx, dz = 0, 1
		if from then
			dx, dz = from.x - lookAt.x, from.z - lookAt.z
		end
		local flat = math.sqrt(dx * dx + dz * dz)
		if flat < 1e-3 then
			dx, dz, flat = 0, 1, 1
		end
		dx, dz = dx / flat, dz / flat
	end
	local pitch = r.pitch * RAD
	local across = distance * math.cos(pitch)
	local position = { x = lookAt.x + dx * across, y = lookAt.y + distance * math.sin(pitch), z = lookAt.z + dz * across }
	return {
		position = position,
		lookAt = lookAt,
		look = Vec.norm(Vec.sub(lookAt, position)),
		fov = r.fov,
		distance = distance,
		yaw = math.deg(math.atan2(dx, dz)),
		pitch = r.pitch,
		band = band,
		fine = 1,
	}
end

export type Lang = {
	profile: any,
	kind: string,
	frame: (target: any, zoom: any?, opts: any?) -> Pose,
	bands: () -> number,
}

function Language.new(profile: any): Lang
	local problems = Language.validate(profile)
	if #problems > 0 then
		error("Cinema.Language: bad profile: " .. table.concat(problems, "; "), 2)
	end
	local lang = {} :: any
	lang.profile = profile
	lang.kind = profile.kind
	lang.frame = function(target: any, zoom: any?, opts: any?): Pose
		if profile.kind == "god" then
			return frameGod(profile, target, zoom, opts)
		end
		return frameRig(profile, target, zoom, opts)
	end
	lang.bands = function(): number
		return if profile.kind == "god" then #profile.god.bands else #profile.rig.bands
	end
	return lang :: Lang
end

return Language
