--!strict
-- Lamplighter (LT2): practical lights - lamps, lanterns, torches, braziers, forges and lit
-- windows. Game-neutral, pure logic; the game's sink owns the Instances.
--
--   local Lamplighter = require("../Lamplighter/Lamplighter")
--   local env = Lamplighter.lifeEnv(life, almanac)            -- or { almanac = alm } / { hour = fn }
--   local lamps = Lamplighter.new(adapter, fixtures, env, require("./rules/guildhall"))
--   local r = lamps:solve(adapter.now(), camera)            -- camera = {pos, look?, fov?, aspect?}
--   -- r.lights: give these a real Light (r.lights[i].shadows says whether it casts shadows)
--   -- r.decals: a ground light decal instead;  r.glow: emissive glow only
--
-- LT1 Lighting Director owns global looks (Lighting, Atmosphere, grading); this package owns
-- every practical light. See README.md for the rules fields and the fixture shape.

local Almanac = require("../Almanac/Almanac")
local Contract = require("../Contract/Contract")
local Flicker = require("./Flicker")
local Kinds = require("./Kinds")
local Windows = require("./Windows")

local Lamplighter = {}
Lamplighter.Kinds = Kinds
Lamplighter.Flicker = Flicker
Lamplighter.Windows = Windows
Lamplighter.hash = Almanac.hash

local TWO32 = 4294967296
local EPS = 1e-9

export type Vec = { x: number, y: number, z: number }
export type Camera = { pos: Vec, look: Vec?, fov: number?, aspect: number? }
export type Fixture = {
	id: string,
	kind: string,
	pos: Vec,
	facing: Vec?,
	building: string?,
	place: string?,
	mask: string?,
	schedule: string?,
	tags: { string }?,
	seed: number?,
	scheduleSeed: number?,
	onSeed: number?,
	offSeed: number?,
}
export type Entry = {
	id: string,
	kind: string,
	pos: Vec,
	facing: Vec?,
	light: string,
	angle: number?,
	level: number,
	flicker: number,
	brightness: number,
	range: number,
	colour: { number },
	emissive: number,
	distance: number,
	onScreen: boolean,
	score: number,
	shadows: boolean,
	decal: { size: number, alpha: number }?,
	panes: { string }?,
}

Lamplighter.DEFAULTS = {
	id = "default",
	seed = 0,
	budgetKind = "activeLights",
	shadowBudgetKind = "shadowLights",
	decalBudgetKind = "lightDecals",
	lights = { 6, 16, 32 },
	shadows = { 0, 1, 2 },
	decals = { 8, 16, 32 },
	radius = 240,
	shadowRadius = 80,
	decalRadius = 160,
	priority = "weighted",
	tourFirst = false,
	squaredNearest = false,
	flat = false,
	offscreen = 0.25,
	screenMargin = 10,
	hysteresis = 0.25,
	minLevel = 0.001,
	lamps = { mode = "switch", on = { 17.5, 18.5 }, off = { 5.5, 6.5 }, fade = 1.5 },
	lamplighter = { role = "lamplighter", activity = "light", from = 18, seconds = 420, late = { 18.5, 19.5 } },
	windows = {
		schedules = { default = { on = { 18.0, 19.3 }, off = { 5.4, 6.6 } } },
		order = {},
		stagger = { 0, 20 },
		fade = 1.6,
	},
}

local LIGHT_TYPES = { point = true, spot = true, surface = true }
local SWITCHES = { night = true, always = true, windows = true }

local function num(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function unit(...: any): number
	return Kinds.mix(Almanac.hash(...)) / TWO32
end
Lamplighter.unit = unit

local function shallow(t: any): any
	local out = {}
	if type(t) == "table" then
		for k, v in t do
			out[k] = v
		end
	end
	return out
end

local function mergeMap(base: any, over: any): any
	local out = shallow(base)
	if type(over) == "table" then
		for k, v in over do
			out[k] = v
		end
	end
	return out
end

-- merge(rules) -> the rules with every default filled: kinds merge field by field over the kit
-- (Kinds.KINDS), flickers / masks / window schedules by id, lamps / lamplighter / windows by field.
function Lamplighter.merge(rules: any): any
	local r = type(rules) == "table" and rules or {}
	local D = Lamplighter.DEFAULTS
	local out: any = {}
	for k, v in D do
		out[k] = v
	end
	for k, v in r do
		out[k] = v
	end
	out.lamps = mergeMap(D.lamps, r.lamps)
	out.lamplighter = mergeMap(D.lamplighter, r.lamplighter)
	local w = mergeMap(D.windows, r.windows)
	w.schedules = mergeMap(D.windows.schedules, type(r.windows) == "table" and r.windows.schedules or nil)
	w.masks = mergeMap(Kinds.MASKS, type(r.windows) == "table" and r.windows.masks or nil)
	out.windows = w
	out.flickers = mergeMap(Kinds.FLICKERS, r.flickers)
	local kinds = {}
	for id, k in Kinds.KINDS do
		kinds[id] = shallow(k)
	end
	if type(r.kinds) == "table" then
		for id, k in r.kinds do
			if type(k) == "table" then
				kinds[id] = mergeMap(kinds[id], k)
			else
				kinds[id] = k
			end
		end
	end
	out.kinds = kinds
	return out
end

local function hourRange(v: any): boolean
	return type(v) == "table" and num(v[1]) and num(v[2]) and v[1] >= 0 and v[1] <= 24 and v[2] >= 0 and v[2] <= 24
end

local function qualityList(v: any, name: string, problems: { string }, required: boolean)
	if v == nil and not required then
		return
	end
	if type(v) ~= "table" or #v ~= 3 then
		table.insert(problems, `{name} must list three numbers (quality low, medium, high)`)
		return
	end
	for i = 1, 3 do
		if not num(v[i]) or v[i] < 0 or v[i] ~= math.floor(v[i]) then
			table.insert(problems, `{name}[{i}] must be a whole number >= 0`)
		end
	end
end

-- colour(kind) -> r, g, b in 0..1: kind.colour (hex) when set, else kind.kelvin.
function Lamplighter.colour(kind: any): (number, number, number)
	if type(kind.colour) == "string" then
		local r, g, b = Kinds.hex(kind.colour)
		if r and g and b then
			return r / 255, g / 255, b / 255
		end
	end
	local r, g, b = Kinds.kelvin(kind.kelvin or 2700)
	return r / 255, g / 255, b / 255
end

-- validate(rules) -> { problem } (on the merged rules, so a partial game file is fine).
function Lamplighter.validate(rules: any): { string }
	local p: { string } = {}
	if rules ~= nil and type(rules) ~= "table" then
		return { "rules must be a table" }
	end
	local r = Lamplighter.merge(rules)
	if type(r.id) ~= "string" or r.id == "" then
		table.insert(p, "id must be a non-empty string")
	end
	if not (num(r.seed) or type(r.seed) == "string") then
		table.insert(p, "seed must be a number or a string")
	end
	for _, key in { "budgetKind", "shadowBudgetKind", "decalBudgetKind" } do
		if type(r[key]) ~= "string" then
			table.insert(p, `{key} must be a string`)
		end
	end
	qualityList(r.lights, "lights", p, true)
	qualityList(r.shadows, "shadows", p, true)
	qualityList(r.decals, "decals", p, true)
	for _, key in { "radius", "shadowRadius", "decalRadius", "hysteresis", "offscreen", "screenMargin", "minLevel" } do
		if not num(r[key]) or r[key] < 0 then
			table.insert(p, `{key} must be a number >= 0`)
		end
	end
	if num(r.radius) and r.radius <= 0 then
		table.insert(p, "radius must be > 0")
	end
	if num(r.offscreen) and r.offscreen > 1 then
		table.insert(p, "offscreen must be in [0, 1] (the score share of a fixture off screen)")
	end
	if r.priority ~= "weighted" and r.priority ~= "nearest" then
		table.insert(p, `priority must be "weighted" or "nearest", got {tostring(r.priority)}`)
	end
	if type(r.tourFirst) ~= "boolean" then
		table.insert(p, `tourFirst must be a boolean, got {tostring(r.tourFirst)}`)
	end
	if type(r.squaredNearest) ~= "boolean" then
		table.insert(p, `squaredNearest must be a boolean, got {tostring(r.squaredNearest)}`)
	elseif r.squaredNearest and (r.priority ~= "nearest" or r.hysteresis ~= 0 or r.tourFirst) then
		table.insert(p, `squaredNearest needs priority "nearest", hysteresis 0 and tourFirst false`)
	end
	local L = r.lamps
	if L.mode ~= "switch" and L.mode ~= "curve" then
		table.insert(p, `lamps.mode must be "switch" or "curve", got {tostring(L.mode)}`)
	end
	if not hourRange(L.on) then
		table.insert(p, "lamps.on must be {from, to} hours in [0, 24]")
	end
	if not hourRange(L.off) then
		table.insert(p, "lamps.off must be {from, to} hours in [0, 24]")
	end
	if not num(L.fade) or L.fade < 0 then
		table.insert(p, "lamps.fade must be seconds >= 0")
	end
	local LL = r.lamplighter
	if type(LL.role) ~= "string" or type(LL.activity) ~= "string" then
		table.insert(p, "lamplighter.role and lamplighter.activity must be strings (Life role and activity ids)")
	end
	if not num(LL.from) or LL.from < 0 or LL.from >= 24 then
		table.insert(p, "lamplighter.from must be an hour in [0, 24)")
	end
	if not num(LL.seconds) or LL.seconds <= 0 then
		table.insert(p, "lamplighter.seconds must be > 0 (how long after `from` the route is sampled)")
	end
	if not hourRange(LL.late) then
		table.insert(p, "lamplighter.late must be {from, to} hours (unreached lamplighter lamps)")
	end
	-- flickers
	local fids = {}
	for id in r.flickers do
		table.insert(fids, id)
	end
	table.sort(fids)
	for _, id in fids do
		for _, msg in Flicker.problems(id, r.flickers[id]) do
			table.insert(p, msg)
		end
	end
	-- kinds
	local kids = {}
	for id in r.kinds do
		table.insert(kids, id)
	end
	table.sort(kids)
	for _, id in kids do
		local k = r.kinds[id]
		local pre = `kinds.{id}`
		if type(k) ~= "table" then
			table.insert(p, pre .. " must be a table")
			continue
		end
		if not num(k.brightness) or k.brightness < 0 then
			table.insert(p, pre .. ".brightness must be a number >= 0")
		end
		if not num(k.range) or k.range <= 0 then
			table.insert(p, pre .. ".range must be a number > 0")
		end
		if k.colour ~= nil then
			local cr = if type(k.colour) == "string" then Kinds.hex(k.colour) else nil
			if cr == nil then
				table.insert(p, pre .. ".colour must be \"#RRGGBB\"")
			end
		elseif not num(k.kelvin) or k.kelvin < 1000 or k.kelvin > 40000 then
			table.insert(p, pre .. ".kelvin must be 1000..40000 (or set colour)")
		end
		if not LIGHT_TYPES[k.light] then
			table.insert(p, pre .. `.light must be point, spot or surface, got {tostring(k.light)}`)
		end
		if k.flicker ~= nil and r.flickers[k.flicker] == nil then
			table.insert(p, pre .. `.flicker names an unknown profile '{tostring(k.flicker)}'`)
		end
		if not num(k.decal) or k.decal < 0 then
			table.insert(p, pre .. ".decal must be studs >= 0 (0 = no decal)")
		end
		for _, key in { "decalAlpha", "emissive" } do
			if k[key] ~= nil and (not num(k[key]) or k[key] < 0 or k[key] > 1) then
				table.insert(p, pre .. `.{key} must be in [0, 1]`)
			end
		end
		if k.weight ~= nil and (not num(k.weight) or k.weight <= 0) then
			table.insert(p, pre .. ".weight must be > 0")
		end
		if not SWITCHES[k.switch] then
			table.insert(p, pre .. `.switch must be night, always or windows, got {tostring(k.switch)}`)
		end
		for _, key in { "on", "off" } do
			if k[key] ~= nil and not hourRange(k[key]) then
				table.insert(p, pre .. `.{key} must be \{from, to} hours`)
			end
		end
	end
	-- windows
	local W = r.windows
	if type(W.schedules) ~= "table" or type(W.schedules.default) ~= "table" then
		table.insert(p, "windows.schedules.default is required")
	end
	local sids = {}
	for id in W.schedules or {} do
		table.insert(sids, id)
	end
	table.sort(sids)
	for _, id in sids do
		local s = W.schedules[id]
		if type(s) ~= "table" or not hourRange(s.on) or not hourRange(s.off) then
			table.insert(p, `windows.schedules.{id} needs on and off hour ranges`)
		else
			for _, key in { "sleep", "wake" } do
				if s[key] ~= nil and not hourRange(s[key]) then
					table.insert(p, `windows.schedules.{id}.{key} must be an hour range`)
				end
			end
		end
	end
	for i, name in W.order or {} do
		if type(W.schedules) == "table" and W.schedules[name] == nil then
			table.insert(p, `windows.order[{i}] '{tostring(name)}' has no schedule`)
		end
	end
	if type(W.stagger) ~= "table" or not num(W.stagger[1]) or not num(W.stagger[2]) or W.stagger[1] < 0 or W.stagger[2] < W.stagger[1] then
		table.insert(p, "windows.stagger must be {lo, hi} seconds with 0 <= lo <= hi")
	end
	local mids = {}
	for id in W.masks do
		table.insert(mids, id)
	end
	table.sort(mids)
	for _, id in mids do
		local m = W.masks[id]
		local pre = `windows.masks.{id}`
		if type(m) ~= "table" or type(m.size) ~= "table" or not num(m.size[1]) or not num(m.size[2]) or m.size[1] < 8 or m.size[2] < 8 then
			table.insert(p, pre .. ".size must be {w, h} pixels >= 8")
			continue
		end
		if type(m.panes) ~= "table" or #m.panes == 0 then
			table.insert(p, pre .. ".panes must list at least one pane")
			continue
		end
		local seen = {}
		for i, pane in m.panes do
			local pp = pre .. `.panes[{i}]`
			if type(pane) ~= "table" or type(pane.id) ~= "string" then
				table.insert(p, pp .. " needs a string id")
				continue
			end
			if seen[pane.id] then
				table.insert(p, pp .. ` repeats id '{pane.id}'`)
			end
			seen[pane.id] = true
			if not (num(pane.x) and num(pane.y) and num(pane.w) and num(pane.h)) or pane.w <= 0 or pane.h <= 0 then
				table.insert(p, pp .. " needs x, y and positive w, h")
			elseif pane.x < 0 or pane.y < 0 or pane.x + pane.w > m.size[1] or pane.y + pane.h > m.size[2] then
				table.insert(p, pp .. ` '{pane.id}' falls outside the {m.size[1]}x{m.size[2]} canvas`)
			end
			if pane.bars ~= nil and pane.bars ~= "cross" and pane.bars ~= "vertical" and pane.bars ~= "none" then
				table.insert(p, pp .. ".bars must be cross, vertical or none")
			end
		end
	end
	return p
end

-- -- instances --------------------------------------------------------------------------------

local Methods = {}
Methods.__index = Methods

local function vecOk(v: any): boolean
	return type(v) == "table" and num(v.x) and num(v.y) and num(v.z)
end

local function fixtureProblems(fixtures: any, r: any): { string }
	local p = {}
	if type(fixtures) ~= "table" then
		return { "fixtures must be a list" }
	end
	local seen = {}
	for i, f in fixtures do
		local pre = `fixtures[{i}]`
		if type(f) ~= "table" or type(f.id) ~= "string" or f.id == "" then
			table.insert(p, pre .. " needs a string id")
			continue
		end
		pre = `fixture '{f.id}'`
		if seen[f.id] then
			table.insert(p, pre .. " is listed twice")
		end
		seen[f.id] = true
		local k = r.kinds[f.kind]
		if type(k) ~= "table" then
			table.insert(p, pre .. ` has unknown kind '{tostring(f.kind)}'`)
			continue
		end
		if not vecOk(f.pos) then
			table.insert(p, pre .. " needs pos = {x, y, z}")
		end
		if f.facing ~= nil and not vecOk(f.facing) then
			table.insert(p, pre .. " facing must be {x, y, z}")
		end
		if f.seed ~= nil and not num(f.seed) then
			table.insert(p, pre .. " seed must be a number")
		end
		for _, key in { "scheduleSeed", "onSeed", "offSeed" } do
			local v = f[key]
			if v ~= nil and not (num(v) and v >= 0 and v <= 1) then
				table.insert(p, pre .. ` {key} must be a number in 0..1`)
			end
		end
		if k.switch == "windows" then
			if type(f.building) ~= "string" then
				table.insert(p, pre .. " is a window and needs its building (a Life place id)")
			end
			if f.mask ~= nil and r.windows.masks[f.mask] == nil then
				table.insert(p, pre .. ` names unknown mask '{tostring(f.mask)}'`)
			end
			if f.schedule ~= nil and r.windows.schedules[f.schedule] == nil then
				table.insert(p, pre .. ` names unknown window schedule '{tostring(f.schedule)}'`)
			end
		end
	end
	return p
end

-- new(adapter, fixtures, env, rules?) -> an instance; errors listing every problem.
--   env = { almanac?, hour?(t), dayLengthSeconds?, occupied?(placeId, t), routeTimes?(t) }
function Lamplighter.new(adapter: Contract.Adapter, fixtures: { Fixture }, env: any, rules: any?): any
	local ap = Contract.check(adapter)
	if #ap > 0 then
		error("Lamplighter: bad adapter: " .. table.concat(ap, "; "), 2)
	end
	local rp = Lamplighter.validate(rules)
	if #rp > 0 then
		error("Lamplighter: bad rules: " .. table.concat(rp, "; "), 2)
	end
	local r = Lamplighter.merge(rules)
	local fp = fixtureProblems(fixtures, r)
	if #fp > 0 then
		error("Lamplighter: bad fixtures: " .. table.concat(fp, "; "), 2)
	end
	local e = env or {}
	if type(e) ~= "table" then
		error("Lamplighter: env must be a table", 2)
	end
	local alm = e.almanac
	if alm ~= nil and (type(alm) ~= "table" or type(alm.at) ~= "function") then
		error("Lamplighter: env.almanac must be an Almanac instance", 2)
	end
	if alm == nil and type(e.hour) ~= "function" then
		error("Lamplighter: env needs an almanac (Almanac.new) or an hour(t) function", 2)
	end
	for _, key in { "hour", "occupied", "routeTimes" } do
		if e[key] ~= nil and type(e[key]) ~= "function" then
			error(`Lamplighter: env.{key} must be a function`, 2)
		end
	end
	local dayLength = e.dayLengthSeconds
	if dayLength == nil and alm ~= nil and type(alm.rules) == "function" then
		dayLength = alm:rules().dayLengthSeconds
	end
	if dayLength ~= nil and (not num(dayLength) or dayLength <= 0) then
		error("Lamplighter: env.dayLengthSeconds must be > 0", 2)
	end
	if r.lamps.mode == "switch" and dayLength == nil then
		error("Lamplighter: lamps.mode 'switch' needs the day length (env.almanac or env.dayLengthSeconds)", 2)
	end
	local list = {}
	for _, f in fixtures do
		local k = r.kinds[f.kind]
		local cr, cg, cb = Lamplighter.colour(k)
		local rec: any = {
			f = f,
			id = f.id,
			kind = k,
			kindId = f.kind,
			colour = { cr, cg, cb },
			seed = f.seed or (Kinds.mix(Almanac.hash(r.seed, "flicker", f.id)) % 100000) / 100,
			-- a game that already draws its own switch hours passes its 0..1 draws (onSeed,
			-- offSeed; windows: scheduleSeed per building) so every fixture keeps its hours
			u1 = f.onSeed or unit(r.seed, "on", f.id),
			u2 = f.offSeed or unit(r.seed, "off", f.id),
			profile = k.flicker and r.flickers[k.flicker] or nil,
		}
		if k.switch == "windows" then
			local building = f.building :: string
			rec.bseed = f.scheduleSeed or unit(r.seed, "window", building)
			rec.schedule = r.windows.schedules[Windows.scheduleFor(f, r.windows)]
			local mask = f.mask and r.windows.masks[f.mask] or nil
			local panes = {}
			if mask then
				for _, pane in mask.panes do
					table.insert(panes, pane.id)
				end
			else
				panes = { "1" }
			end
			rec.panes = panes
			rec.delays = {}
			local s = r.windows.stagger
			for i, pid in panes do
				rec.delays[i] = s[1] + (s[2] - s[1]) * unit(r.seed, "pane", building, pid)
			end
		end
		table.insert(list, rec)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	local byId = {}
	for _, rec in list do
		byId[rec.id] = rec
	end
	local self: any = setmetatable({
		_adapter = adapter,
		_rules = r,
		_env = e,
		_alm = alm,
		_sph = dayLength and dayLength / 24 or nil,
		_list = list,
		_by = byId,
		_prev = { lights = {}, shadows = {}, decals = {} },
		_hourBase = nil,
	}, Methods)
	return self
end

function Methods.rules(self: any): any
	return self._rules
end

function Methods.fixtures(self: any): { any }
	local out = {}
	for _, rec in self._list do
		table.insert(out, rec.f)
	end
	return out
end

-- reset() forgets the previous solve (hysteresis starts fresh; e.g. after a camera cut).
function Methods.reset(self: any)
	self._prev = { lights = {}, shadows = {}, decals = {} }
end

-- caps() -> { lights, shadows, decals }: min(adapter.budget(kind), rules list[quality]).
function Methods.caps(self: any): { lights: number, shadows: number, decals: number }
	local r = self._rules
	local q = math.clamp(math.floor(self._adapter.quality()), 1, 3)
	local function cap(budgetKind: string, list: { number }): number
		local c = list[q]
		local b = self._adapter.budget(budgetKind)
		if num(b) then
			c = math.min(c, math.max(0, math.floor(b :: number)))
		end
		return c
	end
	local lights = cap(r.budgetKind, r.lights)
	return {
		lights = lights,
		shadows = math.min(lights, cap(r.shadowBudgetKind, r.shadows)),
		decals = cap(r.decalBudgetKind, r.decals),
	}
end

-- hour(t): env.hour when given, else the Almanac's hour (one snapshot, then linear in t).
function Methods.hour(self: any, t: number): number
	local e = self._env
	if e.hour then
		return e.hour(t) % 24
	end
	local base = self._hourBase
	if base == nil or self._sph == nil or math.abs(t - base.t) > 3600 then
		base = { t = t, h = self._alm:at(t).hour }
		self._hourBase = base
	end
	if self._sph == nil then
		return self._alm:at(t).hour
	end
	return (base.h + (t - base.t) / self._sph) % 24
end

local function smooth(x: number, from: number, to: number): number
	if to == from then
		return if x >= to then 1 else 0
	end
	local p = math.clamp((x - from) / (to - from), 0, 1)
	return p * p * (3 - 2 * p)
end

-- Monster Ranch Logic/Ambience.Night: 0 by day .. 1 at night, smoothstep through the ranges.
function Lamplighter.night(hour: number, on: { number }, off: { number }): number
	local c = hour % 24
	if c >= off[1] and c <= off[2] then
		return 1 - smooth(c, off[1], off[2])
	elseif c >= on[1] and c <= on[2] then
		return smooth(c, on[1], on[2])
	elseif c > off[2] and c < on[1] then
		return 0
	end
	return 1
end

-- panes(id, t) -> { paneId } lit at t, and the pane count. Pane k is lit iff the building's
-- schedule was lit and (with env.occupied) it was occupied at t - delay(k).
function Methods.panes(self: any, id: string, t: number): ({ string }, number)
	local rec = self._by[id]
	assert(rec and rec.panes, `Lamplighter.panes: '{id}' is not a window fixture`)
	local occ = self._env.occupied
	local building = rec.f.building
	local lit = {}
	for i, pid in rec.panes do
		local tt = t - rec.delays[i]
		if Windows.scheduleLit(self:hour(tt), rec.bseed, rec.schedule) and (occ == nil or occ(building, tt)) then
			table.insert(lit, pid)
		end
	end
	return lit, #rec.panes
end

-- switchOn(id, t) -> the time this fixture switched (or will switch) on in the night around t,
-- and how: "route" (the lamplighter reached it), "late" (a lamplighter lamp the route missed),
-- "schedule" (its seeded hour), or nil for kinds that do not switch at an hour.
function Methods.switchOn(self: any, id: string, t: number): (number?, string?)
	local rec = self._by[id]
	assert(rec, `Lamplighter.switchOn: unknown fixture '{tostring(id)}'`)
	local k, r = rec.kind, self._rules
	if k.switch ~= "night" or r.lamps.mode ~= "switch" then
		return nil, nil
	end
	local hour = self:hour(t)
	local off = Windows.pickIn(k.off or r.lamps.off, rec.u2)
	local LL = r.lamplighter
	local routeFn = self._env.routeTimes
	if k.lamplighter and routeFn then
		if Windows.inWindow(hour, LL.from, off) then
			local times = routeFn(t)
			local at = times and times[rec.f.place or rec.id]
			if at then
				return at, "route"
			end
		end
		local on = Windows.pickIn(LL.late, rec.u1)
		return t - ((hour - on) % 24) * self._sph, "late"
	end
	local on = Windows.pickIn(k.on or r.lamps.on, rec.u1)
	return t - ((hour - on) % 24) * self._sph, "schedule"
end

-- level(id, t) -> 0..1: how lit the fixture is (fades in and out; panes lit share for windows).
function Methods.level(self: any, id: string, t: number): number
	local rec = self._by[id]
	assert(rec, `Lamplighter.level: unknown fixture '{tostring(id)}'`)
	local k, r = rec.kind, self._rules
	if k.switch == "always" then
		return 1
	end
	if k.switch == "windows" then
		local lit, n = self:panes(id, t)
		return #lit / n
	end
	local hour = self:hour(t)
	if r.lamps.mode == "curve" then
		return Lamplighter.night(hour, k.on or r.lamps.on, k.off or r.lamps.off)
	end
	local sph = self._sph
	local off = Windows.pickIn(k.off or r.lamps.off, rec.u2)
	local onAt, how = self:switchOn(id, t)
	if onAt == nil then
		return 0
	end
	local since = t - onAt
	if how == "route" then
		if since < 0 then
			return 0
		end
	else
		local on = Windows.pickIn(if how == "late" then r.lamplighter.late else (k.on or r.lamps.on), rec.u1)
		if not Windows.inWindow(hour, on, off) then
			return 0
		end
	end
	local untilOff = ((off - hour) % 24) * sph
	local fade = r.lamps.fade
	if fade <= 0 then
		return 1
	end
	return math.clamp(math.min(since / fade, untilOff / fade), 0, 1)
end

-- flicker(id, t) -> the fixture's brightness multiplier at t (1 for steady kinds).
function Methods.flicker(self: any, id: string, t: number): number
	local rec = self._by[id]
	assert(rec, `Lamplighter.flicker: unknown fixture '{tostring(id)}'`)
	return Flicker.value(rec.profile, rec.seed, rec.id, t)
end

-- The camera's view cone: half the diagonal field of view (radians), or nil without a look.
local function viewHalf(camera: any): number?
	if camera.look == nil then
		return nil
	end
	local fov = math.rad(camera.fov or 70)
	local aspect = camera.aspect or 16 / 9
	return math.atan(math.tan(fov / 2) * math.sqrt(1 + aspect * aspect))
end

-- solve(t, camera?) -> { t, hour, lights, decals, glow, caps, stats }
-- Every fixture lit at t is in exactly one of lights (a real Light; `shadows` on the best few),
-- decals (a ground pool instead) or glow (emissive only). Hysteresis: last solve's picks keep
-- their slot until a challenger beats them by `rules.hysteresis`.
function Methods.solve(self: any, t: number, camera: Camera?): any
	if not num(t) then
		error("Lamplighter.solve: t must be a finite number, got " .. tostring(t), 2)
	end
	local r = self._rules
	local caps = self:caps()
	local cam: any = camera
	if cam ~= nil and not vecOk(cam.pos) then
		error("Lamplighter.solve: camera.pos must be {x, y, z}", 2)
	end
	local half = cam and viewHalf(cam) or nil
	local margin = math.rad(r.screenMargin)
	local look = cam and cam.look
	local ll = look and math.sqrt(look.x * look.x + look.y * look.y + look.z * look.z) or 0
	local on: { any } = {}
	local fixtures = #self._list
	for _, rec in self._list do
		local level, litPanes
		if rec.panes then
			local lit, n = self:panes(rec.id, t)
			level, litPanes = #lit / n, lit
		else
			level = self:level(rec.id, t)
		end
		if level <= r.minLevel then
			continue
		end
		local k = rec.kind
		local f = rec.f
		local fl = Flicker.value(rec.profile, rec.seed, rec.id, t)
		-- view: 1 inside the cone, easing to rules.offscreen over screenMargin degrees outside
		-- it (continuous, so a slow pan never flips a score); a camera inside the fixture's own
		-- range sees its pool whichever way it looks.
		local d, d2, onScreen, view = 0, 0, true, 1
		if cam then
			local dx, dy, dz = f.pos.x - cam.pos.x, f.pos.y - cam.pos.y, f.pos.z - cam.pos.z
			local full = math.sqrt(dx * dx + dy * dy + dz * dz)
			d2 = if r.flat then dx * dx + dz * dz else dx * dx + dy * dy + dz * dz
			d = if r.flat then math.sqrt(dx * dx + dz * dz) else full
			if half and ll > EPS and full > EPS and d > k.range then
				local c = math.clamp((dx * look.x + dy * look.y + dz * look.z) / (full * ll), -1, 1)
				local ang = math.acos(c)
				onScreen = ang <= half + margin
				if ang > half then
					local u = if margin > 0 then math.clamp((ang - half) / margin, 0, 1) else 1
					view = 1 + (r.offscreen - 1) * u
				end
			end
		end
		local score
		if r.priority == "nearest" then
			score = -d
		else
			local fall = k.range / (k.range + d)
			score = (k.weight or 1) * k.brightness * level * fall * fall * view
		end
		local entry: any = {
			id = rec.id,
			kind = rec.kindId,
			pos = f.pos,
			facing = f.facing,
			light = k.light,
			angle = k.angle,
			level = level,
			flicker = fl,
			brightness = k.brightness * level * fl,
			range = k.range,
			colour = rec.colour,
			emissive = math.clamp((k.emissive or 1) * level * fl, 0, 1),
			distance = d,
			distance2 = d2,
			onScreen = onScreen,
			score = score,
			shadows = false,
		}
		if litPanes then
			entry.panes = litPanes
		end
		table.insert(on, entry)
	end

	local prev = self._prev
	local h = r.hysteresis
	local function boosted(e: any, set: { [string]: boolean }): number
		if not set[e.id] then
			return e.score
		end
		if r.priority == "nearest" then
			return e.score / (1 + h) -- a shorter effective distance (scores are -d)
		end
		return e.score * (1 + h)
	end
	-- tier(e) (optional) ranks before the score: a higher tier always wins, hysteresis included.
	local function rank(list: { any }, set: { [string]: boolean }, tier: ((any) -> number)?)
		local key, tiers = {}, {}
		for _, e in list do
			key[e] = boosted(e, set)
			tiers[e] = if tier then tier(e) else 0
		end
		table.sort(list, function(a, b)
			if tiers[a] ~= tiers[b] then
				return tiers[a] > tiers[b]
			end
			if key[a] ~= key[b] then
				return key[a] > key[b]
			end
			return a.id < b.id
		end)
	end

	-- real lights
	local cands = {}
	local r2 = r.radius * r.radius
	for _, e in on do
		local inside = if r.squaredNearest then e.distance2 <= r2 else e.distance <= r.radius
		if inside and e.brightness > 0 then
			table.insert(cands, e)
		end
	end
	if r.squaredNearest then
		-- rules.squaredNearest: squared distance, radius compared squared, fixture order into the
		-- host sort and no tie-break: Monster Ranch Logic.Nearest choice for choice, ties included.
		table.sort(cands, function(a, b)
			return a.distance2 < b.distance2
		end)
	else
		-- rules.tourFirst: fixtures on the lamplighter's tour (kind.lamplighter) outrank every other
		-- fixture for a real light; the score (and hysteresis) orders each tier.
		local tourTier = if r.tourFirst
			then function(e: any): number
				return if self._by[e.id].kind.lamplighter then 1 else 0
			end
			else nil
		rank(cands, prev.lights, tourTier)
	end
	local lights, taken = {}, {}
	for i = 1, math.min(caps.lights, #cands) do
		lights[i] = cands[i]
		taken[cands[i].id] = true
	end
	-- shadows among them
	local shadowCands = {}
	for _, e in lights do
		if self._by[e.id].kind.shadows and e.distance <= r.shadowRadius then
			table.insert(shadowCands, e)
		end
	end
	rank(shadowCands, prev.shadows)
	local shadowSet = {}
	for i = 1, math.min(caps.shadows, #shadowCands) do
		shadowCands[i].shadows = true
		shadowSet[shadowCands[i].id] = true
	end
	-- decals instead of a light
	local decalCands = {}
	for _, e in on do
		local k = self._by[e.id].kind
		if not taken[e.id] and k.decal > 0 and e.distance <= r.decalRadius and e.onScreen then
			table.insert(decalCands, e)
		end
	end
	rank(decalCands, prev.decals)
	local decals, decalSet = {}, {}
	for i = 1, math.min(caps.decals, #decalCands) do
		local e = decalCands[i]
		local k = self._by[e.id].kind
		e.decal = { size = k.decal, alpha = math.clamp((k.decalAlpha or 0.5) * e.level * e.flicker, 0, 1) }
		decals[i] = e
		decalSet[e.id] = true
	end
	local glow = {}
	for _, e in on do
		if not taken[e.id] and not decalSet[e.id] then
			table.insert(glow, e)
		end
	end
	-- changes against the previous solve (for stability specs and telemetry)
	local changed = 0
	for id in prev.lights do
		if not taken[id] then
			changed += 1
		end
	end
	for id in taken do
		if not prev.lights[id] then
			changed += 1
		end
	end
	self._prev = { lights = taken, shadows = shadowSet, decals = decalSet }
	local shadows = 0
	for _ in shadowSet do
		shadows += 1
	end
	return {
		t = t,
		hour = self:hour(t),
		lights = lights,
		decals = decals,
		glow = glow,
		caps = caps,
		stats = {
			fixtures = fixtures,
			on = #on,
			candidates = #cands,
			lights = #lights,
			shadows = shadows,
			decals = #decals,
			glow = #glow,
			changed = changed,
		},
	}
end

-- -- Life -------------------------------------------------------------------------------------

-- lifeEnv(life, almanac, opts?) -> env: the Almanac clock, occupied(placeId, t) from Life (an
-- agent inside the place), and routeTimes(t): when Life's lamplighter first reaches each place
-- with its `activity` on the evening around t (sampled every `step` s from `from` for
-- `seconds`, refined to `precision` s, cached per evening).
--   opts = { role?, activity?, from?, seconds?, step? = 1, precision? = 0.05 } (defaults from
--   rules.lamplighter when opts.rules is given, else Lamplighter.DEFAULTS.lamplighter)
function Lamplighter.lifeEnv(life: any, almanac: any, opts: any?): any
	assert(type(life) == "table" and type(life.at) == "function", "Lamplighter.lifeEnv: life must be a Life instance")
	assert(type(almanac) == "table" and type(almanac.at) == "function", "Lamplighter.lifeEnv: almanac must be an Almanac instance")
	local o = opts or {}
	local LL = Lamplighter.merge(o.rules).lamplighter
	local role = o.role or LL.role
	local activity = o.activity or LL.activity
	local from = o.from or LL.from
	local seconds = o.seconds or LL.seconds
	local step = o.step or 1
	local precision = o.precision or 0.05
	local dayLength = almanac:rules().dayLengthSeconds
	local sph = dayLength / 24

	local occCache: { [number]: { [string]: boolean } } = {}
	local occN = 0
	local function occupiedAt(tq: number): { [string]: boolean }
		local set = occCache[tq]
		if set then
			return set
		end
		if occN >= 256 then
			table.clear(occCache)
			occN = 0
		end
		set = {}
		for _, a in life:at(tq) do
			if not a.visible and a.place then
				set[a.place] = true
			end
		end
		occCache[tq] = set
		occN += 1
		return set
	end

	local routeCache: { [number]: { [string]: number } } = {}
	local routeN = 0
	local function agentAt(id: string, t: number): any
		for _, a in life:at(t) do
			if a.id == id then
				return a
			end
		end
		return nil
	end
	local function route(eve: number): { [string]: number }
		local lighter
		for _, a in life:at(eve) do
			if a.role == role then
				lighter = a.id
				break
			end
		end
		local times = {}
		if lighter == nil then
			return times
		end
		local prevT = eve
		local s = eve
		while s <= eve + seconds do
			local a = agentAt(lighter, s)
			if a and a.activity == activity and a.place and times[a.place] == nil then
				local place = a.place
				local lo, hi = prevT, s
				while hi - lo > precision do
					local mid = (lo + hi) / 2
					local m = agentAt(lighter, mid)
					if m and m.activity == activity and m.place == place then
						hi = mid
					else
						lo = mid
					end
				end
				times[place] = hi
			end
			prevT = s
			s += step
		end
		return times
	end

	return {
		almanac = almanac,
		dayLengthSeconds = dayLength,
		occupied = function(placeId: string, t: number): boolean
			return occupiedAt(math.floor(t))[placeId] == true
		end,
		routeTimes = function(t: number): { [string]: number }
			local hour = almanac:at(t).hour
			local eve = t - ((hour - from) % 24) * sph
			local key = math.floor(eve * 1000 + 0.5) / 1000
			local times = routeCache[key]
			if times == nil then
				if routeN >= 8 then
					table.clear(routeCache)
					routeN = 0
				end
				times = route(key)
				routeCache[key] = times
				routeN += 1
			end
			return times
		end,
	}
end

return Lamplighter
