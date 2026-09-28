--!strict
-- PhotoMode: the photo mode state machine. It owns no Instances: every effect on the world is a
-- command handed to the game's sink, and the game (which owns the camera, the UI and the
-- post-processing) carries it out.
--
--   local pm = PhotoMode.new(adapter, cfg, sink)
--   cfg = {
--     bounds = { radius, minHeight, maxHeight, minDistance, maxDistance, startDistance,
--                minPitch, maxPitch },          -- Monster Ranch Config.Photo.Camera's shape
--     grades = { { id, name, brightness?, contrast?, saturation?, tint?, bloom?, heavy? } },
--     fov = number,                             -- the photo camera's field of view
--     focus = Focus curve?,                     -- depth of field (nil = none)
--   }
--
-- States: "off" -> enter -> "orbit" <-> "free" ; capture -> "capturing" -> captured -> back ;
-- exit from any state but "off". PhotoMode.TRANSITIONS[state][action] is the whole table; an
-- action a state does not allow returns false, changes nothing and emits nothing.
--
--   orbit mode   turn(dYaw, dPitch) orbits the focus; move(right, up, forward) pans the focus
--   free mode    turn looks around from the eye (the focus swings round it); move flies the eye
--   both         zoom(factor) scales the focus distance; the FOCUS stays within `radius` of the
--                anchor (flat) and minHeight..maxHeight above it; pitch and distance clamp
--
-- Commands (sink):
--   { kind = "takeCamera", anchor }                       enter
--   { kind = "pose", position, lookAt, fov }              after every change of view
--   { kind = "grade", id, preset, bloom }                 enter, grade(); bloom false at quality 1
--   { kind = "dof", enabled, focusDistance, inFocusRadius, nearIntensity, farIntensity }
--   { kind = "hideUI", hidden }                           hideUI()
--   { kind = "capture", pose, grade, uiHidden }           capture()
--   { kind = "captured", ok, ref }                        captured()
--   { kind = "restore" }                                  exit: give the camera, UI and look back

local Focus = require("./Focus")
local Vec = require("./Vec")

type Vec3 = Vec.Vec3

local PhotoMode = {}

PhotoMode.STATES = table.freeze({ "off", "orbit", "free", "capturing" })
PhotoMode.ACTIONS = table.freeze({ "enter", "exit", "mode", "turn", "move", "zoom", "grade", "hideUI", "focus", "capture", "captured" })

-- [state][action] = the state after it (the same state for in-place actions). "mode" goes to the
-- mode it names and "captured" back to the mode capture left, so both are marked "*".
PhotoMode.TRANSITIONS = table.freeze({
	off = table.freeze({ enter = "orbit" }),
	orbit = table.freeze({
		exit = "off",
		mode = "*",
		turn = "orbit",
		move = "orbit",
		zoom = "orbit",
		grade = "orbit",
		hideUI = "orbit",
		focus = "orbit",
		capture = "capturing",
	}),
	free = table.freeze({
		exit = "off",
		mode = "*",
		turn = "free",
		move = "free",
		zoom = "free",
		grade = "free",
		hideUI = "free",
		focus = "free",
		capture = "capturing",
	}),
	capturing = table.freeze({ exit = "off", captured = "*" }),
})

local fin = Vec.finiteNumber

function PhotoMode.validate(cfg: any): { string }
	local problems = {}
	if type(cfg) ~= "table" then
		return { "photo config must be a table" }
	end
	local b = cfg.bounds
	if type(b) ~= "table" then
		table.insert(problems, "photo.bounds must be a table")
	else
		for _, k in { "radius", "minHeight", "maxHeight", "minDistance", "maxDistance", "startDistance", "minPitch", "maxPitch" } do
			if not fin(b[k]) then
				table.insert(problems, `photo.bounds.{k} must be a number`)
			end
		end
		if #problems == 0 then
			if b.radius < 0 then
				table.insert(problems, "photo.bounds.radius must be >= 0")
			end
			if b.maxHeight < b.minHeight then
				table.insert(problems, "photo.bounds.minHeight <= maxHeight")
			end
			if not (b.minDistance > 0 and b.maxDistance >= b.minDistance) then
				table.insert(problems, "photo.bounds: 0 < minDistance <= maxDistance")
			end
			if not (b.minPitch >= -89 and b.maxPitch <= 89 and b.minPitch <= b.maxPitch) then
				table.insert(problems, "photo.bounds: -89 <= minPitch <= maxPitch <= 89")
			end
		end
	end
	if type(cfg.grades) ~= "table" or #cfg.grades == 0 then
		table.insert(problems, "photo.grades must list at least one preset")
	else
		local seen: { [string]: boolean } = {}
		local light = 0
		for i, g in ipairs(cfg.grades) do
			if type(g) ~= "table" or type(g.id) ~= "string" or type(g.name) ~= "string" then
				table.insert(problems, `photo.grades[{i}] needs an id and a name`)
			else
				if seen[g.id] then
					table.insert(problems, `photo.grades: duplicate id {g.id}`)
				end
				seen[g.id] = true
				if not g.heavy then
					light += 1
				end
			end
		end
		if light == 0 then
			table.insert(problems, "photo.grades: at least one preset must not be heavy (low quality)")
		end
	end
	if not (fin(cfg.fov) and cfg.fov >= 1 and cfg.fov <= 120) then
		table.insert(problems, "photo.fov must be in [1, 120]")
	end
	if cfg.focus ~= nil then
		for _, p in ipairs(Focus.validate(cfg.focus)) do
			table.insert(problems, "photo." .. p)
		end
	end
	return problems
end

local function wrapYaw(yaw: number): number
	local r = yaw % 360
	return if r > 180 then r - 360 else r
end

-- The eye's offset from the focus (Monster Ranch PhotoRig.Eye).
local function eyeOffset(yaw: number, pitch: number, distance: number): Vec3
	local y, p = math.rad(yaw), math.rad(pitch)
	local flat = math.cos(p) * distance
	return { x = math.sin(y) * flat, y = math.sin(p) * distance, z = math.cos(y) * flat }
end

export type Photo = {
	state: () -> string,
	enter: (anchor: Vec3, from: Vec3?) -> boolean,
	exit: () -> boolean,
	mode: (name: string) -> boolean,
	turn: (dYaw: number, dPitch: number) -> boolean,
	move: (right: number, up: number, forward: number) -> boolean,
	zoom: (factor: number) -> boolean,
	grade: (step: number | string) -> boolean,
	hideUI: (on: boolean?) -> boolean,
	focus: (distance: number?) -> boolean,
	capture: () -> boolean,
	captured: (ok: boolean, ref: any?) -> boolean,
	pose: () -> any?,
	allowed: (action: string) -> boolean,
	gradeId: () -> string,
	rig: () -> any?,
}

function PhotoMode.new(adapter: any, cfg: any, sink: (any) -> ()): Photo
	local problems = PhotoMode.validate(cfg)
	if #problems > 0 then
		error("Cinema.PhotoMode: bad config: " .. table.concat(problems, "; "), 2)
	end
	local B = cfg.bounds
	local state = "off"
	local resume = "orbit" -- the mode capture returns to
	local anchor: Vec3 = { x = 0, y = 0, z = 0 }
	local rig = { x = 0, y = 0, z = 0, yaw = 0, pitch = 20, distance = B.startDistance }
	local gradeIndex = 1
	local uiHidden = false
	local focusDistance: number? = nil

	local function send(cmd: any)
		local ok, err = pcall(sink, cmd)
		if not ok then
			adapter.log("error", "Cinema.PhotoMode: sink failed", { kind = cmd.kind, err = tostring(err) })
		end
	end

	local function allowed(action: string): boolean
		local row = PhotoMode.TRANSITIONS[state]
		return row ~= nil and row[action] ~= nil
	end

	local function refuse(action: string): boolean
		adapter.log("info", "Cinema.PhotoMode: action not allowed", { state = state, action = action })
		return false
	end

	local function clampRig()
		local flat = math.sqrt(rig.x * rig.x + rig.z * rig.z)
		if flat > B.radius then
			local k = if flat > 0 then B.radius / flat else 0
			rig.x, rig.z = rig.x * k, rig.z * k
		end
		rig.y = math.clamp(rig.y, B.minHeight, B.maxHeight)
		rig.pitch = math.clamp(rig.pitch, B.minPitch, B.maxPitch)
		rig.distance = math.clamp(rig.distance, B.minDistance, B.maxDistance)
		rig.yaw = wrapYaw(rig.yaw)
	end

	local function focusPoint(): Vec3
		return { x = anchor.x + rig.x, y = anchor.y + rig.y, z = anchor.z + rig.z }
	end

	local function currentPose(): any
		local f = focusPoint()
		return {
			position = Vec.add(f, eyeOffset(rig.yaw, rig.pitch, rig.distance)),
			lookAt = f,
			fov = cfg.fov,
			yaw = rig.yaw,
			pitch = rig.pitch,
			distance = rig.distance,
		}
	end

	local function emitPose()
		local p = currentPose()
		send({ kind = "pose", position = p.position, lookAt = p.lookAt, fov = p.fov })
	end

	local function emitDof()
		if cfg.focus == nil then
			return
		end
		local d = Focus.dof(cfg.focus, focusDistance or rig.distance, adapter.quality())
		send({
			kind = "dof",
			enabled = d.enabled,
			focusDistance = d.focusDistance,
			inFocusRadius = d.inFocusRadius,
			nearIntensity = d.nearIntensity,
			farIntensity = d.farIntensity,
		})
	end

	local function low(): boolean
		return adapter.quality() <= 1
	end

	local function gradeOk(i: number): boolean
		local g = cfg.grades[i]
		return g ~= nil and not (g.heavy and low())
	end

	local function emitGrade()
		if not gradeOk(gradeIndex) then
			gradeIndex = 1
			while not gradeOk(gradeIndex) do
				gradeIndex += 1
			end
		end
		local g = cfg.grades[gradeIndex]
		send({ kind = "grade", id = g.id, preset = g, bloom = g.bloom ~= nil and not low() })
	end

	local pm = {} :: any

	pm.state = function()
		return state
	end
	pm.allowed = allowed
	pm.gradeId = function()
		return cfg.grades[gradeIndex].id
	end
	pm.rig = function()
		if state == "off" then
			return nil
		end
		return table.clone(rig)
	end
	pm.pose = function()
		if state == "off" then
			return nil
		end
		return currentPose()
	end

	-- enter(anchor, from?): `from` is where the player's camera was; the photo camera starts there
	-- (as an orbit around the anchor), or at startDistance behind the anchor without it.
	pm.enter = function(at: Vec3, from: Vec3?): boolean
		if not allowed("enter") then
			return refuse("enter")
		end
		local a = Vec.of(at)
		if not a then
			adapter.log("warn", "Cinema.PhotoMode: enter needs an anchor Vec3", nil)
			return false
		end
		anchor = a
		rig = { x = 0, y = 0, z = 0, yaw = 0, pitch = 20, distance = B.startDistance }
		local f = Vec.of(from)
		if f then
			local off = Vec.sub(f, a)
			local len = Vec.length(off)
			if len > 1e-3 then
				rig.yaw = math.deg(math.atan2(off.x, off.z))
				rig.pitch = math.deg(math.asin(math.clamp(off.y / len, -1, 1)))
				rig.distance = len
			end
		end
		clampRig()
		focusDistance = nil
		uiHidden = false
		state = "orbit"
		resume = "orbit"
		send({ kind = "takeCamera", anchor = a })
		emitGrade()
		emitDof()
		emitPose()
		return true
	end

	pm.exit = function(): boolean
		if not allowed("exit") then
			return refuse("exit")
		end
		state = "off"
		if uiHidden then
			uiHidden = false
			send({ kind = "hideUI", hidden = false })
		end
		send({ kind = "restore" })
		return true
	end

	pm.mode = function(name: string): boolean
		if not allowed("mode") then
			return refuse("mode")
		end
		if name ~= "orbit" and name ~= "free" then
			adapter.log("warn", "Cinema.PhotoMode: unknown mode", { mode = name })
			return false
		end
		state = name
		return true
	end

	pm.turn = function(dYaw: number, dPitch: number): boolean
		if not allowed("turn") then
			return refuse("turn")
		end
		if not (fin(dYaw) and fin(dPitch)) then
			return false
		end
		if state == "free" then
			-- look around from the eye: keep the eye, swing the focus
			local eye = Vec.add(focusPoint(), eyeOffset(rig.yaw, rig.pitch, rig.distance))
			rig.yaw += dYaw
			rig.pitch += dPitch
			clampRig()
			local f = Vec.sub(eye, eyeOffset(rig.yaw, rig.pitch, rig.distance))
			rig.x, rig.y, rig.z = f.x - anchor.x, f.y - anchor.y, f.z - anchor.z
		else
			rig.yaw += dYaw
			rig.pitch += dPitch
		end
		clampRig()
		emitPose()
		return true
	end

	-- right / up / forward in studs relative to the view (forward flattened), PhotoRig.Pan's basis.
	pm.move = function(right: number, up: number, forward: number): boolean
		if not allowed("move") then
			return refuse("move")
		end
		if not (fin(right) and fin(up) and fin(forward)) then
			return false
		end
		local y = math.rad(rig.yaw)
		local rx, rz, fx, fz = math.cos(y), -math.sin(y), -math.sin(y), -math.cos(y)
		rig.x += rx * right + fx * forward
		rig.z += rz * right + fz * forward
		rig.y += up
		clampRig()
		emitPose()
		return true
	end

	pm.zoom = function(factor: number): boolean
		if not allowed("zoom") then
			return refuse("zoom")
		end
		if not (fin(factor) and factor > 0) then
			return false
		end
		rig.distance *= factor
		clampRig()
		emitPose()
		if focusDistance == nil then
			emitDof()
		end
		return true
	end

	-- grade(step) cycles by +-step (skipping heavy presets at quality 1); grade(id) picks one.
	pm.grade = function(step: number | string): boolean
		if not allowed("grade") then
			return refuse("grade")
		end
		local n = #cfg.grades
		if type(step) == "string" then
			for i, g in ipairs(cfg.grades) do
				if g.id == step then
					if not gradeOk(i) then
						adapter.log("info", "Cinema.PhotoMode: preset skipped at low quality", { id = step })
						return false
					end
					gradeIndex = i
					emitGrade()
					return true
				end
			end
			adapter.log("warn", "Cinema.PhotoMode: unknown grade", { id = step })
			return false
		end
		if not fin(step) or step == 0 then
			return false
		end
		local i = gradeIndex
		for _ = 1, n do
			i = ((i - 1 + step) % n) + 1
			if gradeOk(i) then
				break
			end
		end
		gradeIndex = i
		emitGrade()
		return true
	end

	pm.hideUI = function(on: boolean?): boolean
		if not allowed("hideUI") then
			return refuse("hideUI")
		end
		if on == nil then
			uiHidden = not uiHidden
		else
			uiHidden = on
		end
		send({ kind = "hideUI", hidden = uiHidden })
		return true
	end

	-- focus(distance): pin the focus plane (a tap on the subject); focus(nil) follows the orbit.
	pm.focus = function(distance: number?): boolean
		if not allowed("focus") then
			return refuse("focus")
		end
		if distance ~= nil and not (fin(distance) and distance >= 0) then
			return false
		end
		focusDistance = distance
		emitDof()
		return true
	end

	pm.capture = function(): boolean
		if not allowed("capture") then
			return refuse("capture")
		end
		resume = state
		state = "capturing"
		send({ kind = "capture", pose = currentPose(), grade = cfg.grades[gradeIndex].id, uiHidden = uiHidden })
		return true
	end

	pm.captured = function(ok: boolean, ref: any?): boolean
		if not allowed("captured") then
			return refuse("captured")
		end
		state = resume
		send({ kind = "captured", ok = ok == true, ref = ref })
		return true
	end

	return pm :: Photo
end

return PhotoMode
