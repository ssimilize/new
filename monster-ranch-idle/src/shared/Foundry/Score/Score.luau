--!strict
-- Score: adaptive music as data (SO2 Score Director).
--
--   local Score = require("../Score/Score")
--   local s = Score.new(adapter, score, sink)          -- score: packages/Score/scores/<game>.json
--   s:update({ zone = "hub", phase = "night", weather = "rain", intensity = 0.4 }, dt)
--   s:stinger("GuildRank.Up")                          -- or adapter.emit("GuildRank.Up") (stingers subscribe)
--   s:state()  s:stats()  s:stop()
--   Score.validate(score) -> { problem }        Score.pick(score, context) -> (theme?, index?)
--   Score.band(score, intensity) -> 1 | 2 | 3   Score.nextBar(anchor, barLength, t) -> t'
--   Score.barLength(theme) -> seconds           Score.windows(score, from, to) -> { window }
--
-- The package never creates Instances. It calls
--   sink({ op = "play" | "stop" | "fade" | "stinger" | "duck", layer, sound, volume, at, ... })
-- and the game's own audio system owns every Sound. `at` is the world time (adapter.now()) the
-- command belongs to: a theme change or layer entry emitted a frame after its bar still carries the
-- bar's time, so the sink can seek a stem by (now - at). Extra fields: `group` (always "Music"),
-- `time` (fade seconds), `theme`, `loop` (play), `key` and `priority` (stinger), `silence = true`
-- (a stop that opens a silence window). `volume` never includes the Music group volume
-- (score.groups.Music is the game's SoundGroup level) or the duck (a separate "duck" command
-- carries the bed multiplier, 1 = no duck).
--
-- Themes: the FIRST theme (file order) whose `when` matches the context plays; no match = no music.
--   `when` keys name context fields (zone, phase, weather, or any other the game passes, e.g. an
--   event id or a mode flag). A value is a string, a list of strings (any of), { not = { ... } } or
--   a boolean (true = the context field is true; false = it is not true).
-- Layers: every layer of a theme starts together on the theme's first bar (a layer silent in the
--   current band starts at volume 0, so stems stay in sync) and moves by "fade" when the intensity
--   band changes. Bands: intensity < bands[1] low, < bands[2] mid, else high (default 0.34, 0.67).
-- Bars: bar length = beatsPerBar * 60 / bpm. A theme's bar clock is anchored at the adapter time
--   it started. Theme changes and band changes are queued for the next bar boundary of the playing
--   theme and committed at exactly that time, whatever the frame rate. Starting from no music
--   (first update, after "no theme", after a silence window) is immediate.
-- Handoff (optional `handoff = { mode = "sequential", fadeOut, fadeIn }`): theme changes are NOT
--   quantized and never overlap. A per-frame fader over the update's dt (nil dt = the adapter
--   time since the last update): the playing theme fades from its level to 0 (fade to volume 0
--   over level x fadeOut, `at` = now - dt, since this frame's dt already counts), then stops
--   (time 0) and the wanted theme plays, fading in over fadeIn. A change back while fading out
--   fades the same theme up again. A theme with no cast layer is silence. Band changes still wait
--   for the bar. Without `handoff` nothing changes: crossfade on the bar.
-- Stingers: fired by adapter events (`on`) or s:stinger(key). A stinger is refused inside its own
--   cooldown, or while a stinger of HIGHER priority still holds; otherwise it plays and ducks the
--   bed to (1 - duck) for `hold` seconds. An empty sound is skipped (silent-safe, counted).
-- Silence: candidate windows come from world-time slots of length minGap + windowSeconds + J
--   (J = jitter = minGap): slot k draws its start in [k L, k L + J] from Contract.Rng seeded by
--   (seed, k), so every client sees the same windows and two windows are never closer than minGap.
--   A window is taken only when music has played for afterMinutes since it last started, the
--   context is not in a `never` state and the slot's `chance` roll passes; entering a `never` state
--   during a window ends it at once.

local Contract = require("../Contract/Contract")

export type Sink = (cmd: { [string]: any }) -> ()

local Score = {}

local Methods = {}
Methods.__index = Methods

Score.DEFAULT_CROSSFADE = 2
Score.DEFAULT_BANDS = { 0.34, 0.67 }
Score.DUCK_ATTACK = 0.08 -- seconds, sent as `time` on a duck-down
Score.DUCK_RELEASE = 0.8 -- seconds, sent as `time` on a duck release
Score.GROUP = "Music"
Score.EPS = 1e-9

local TWO32 = 4294967296
local TOP_KEYS = {
	game = true,
	seed = true,
	notes = true,
	crossfade = true,
	handoff = true,
	bands = true,
	themes = true,
	stingers = true,
	silence = true,
	groups = true,
}
local THEME_KEYS = { id = true, bpm = true, beatsPerBar = true, crossfade = true, when = true, layers = true, notes = true }
local LAYER_KEYS = { id = true, sound = true, volume = true, desc = true, search = true, origin = true }
local STINGER_KEYS = {
	id = true,
	on = true,
	sound = true,
	volume = true,
	duck = true,
	hold = true,
	priority = true,
	cooldown = true,
	desc = true,
	search = true,
	origin = true,
}
local SILENCE_KEYS = { minGap = true, afterMinutes = true, windowSeconds = true, never = true, chance = true }
local HANDOFF_KEYS = { mode = true, fadeOut = true, fadeIn = true }

-- helpers ------------------------------------------------------------------------------------

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function fnv(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (bit32.lshift(h, 24) + h * 403) % TWO32
	end
	return h
end
Score.hash = fnv

local function isAsset(s: string): boolean
	return string.match(s, "^rbxassetid://%d+$") ~= nil
end

-- A Vault record key (foundry/tools/vault/records.py safe_key): a leading letter or digit, then
-- letters, digits and . _ / @ + # -, with at least one "/". A URL ("://") is never one.
local function isVaultKey(s: string): boolean
	return string.find(s, "/", 1, true) ~= nil and string.match(s, "^[%w][%w%._/@%+#%-]*$") ~= nil
end

-- conditions ---------------------------------------------------------------------------------

local function matchOne(cond: any, value: any): boolean
	if type(cond) == "boolean" then
		if cond then
			return value == true
		end
		return value ~= true
	end
	if type(cond) == "string" then
		return value == cond
	end
	if type(cond) == "table" then
		if cond["not"] ~= nil then
			for _, v in cond["not"] do
				if v == value then
					return false
				end
			end
			return true
		end
		for _, v in cond do
			if v == value then
				return true
			end
		end
	end
	return false
end

-- Does a `when` (or one `never` entry) match the context? nil / {} matches everything.
function Score.when(cond: any, context: any): boolean
	if cond == nil then
		return true
	end
	local ctx = context or {}
	for k, v in cond do
		if not matchOne(v, ctx[k]) then
			return false
		end
	end
	return true
end

local function neverList(never: any): { any }
	if never == nil then
		return {}
	end
	if type(never) == "table" and #never > 0 then
		return never
	end
	return { never }
end

-- Is the context in one of the silence section's `never` states?
function Score.never(score: any, context: any): boolean
	local sil = score.silence
	if sil == nil then
		return true -- no silence section: silence never happens
	end
	for _, cond in neverList(sil.never) do
		if Score.when(cond, context) then
			return true
		end
	end
	return false
end

-- validation ---------------------------------------------------------------------------------

local function unknownKeys(where: string, t: any, allowed: { [string]: boolean }, p: { string })
	local names = {}
	for k in t do
		if not allowed[k] then
			table.insert(names, tostring(k))
		end
	end
	table.sort(names)
	for _, k in names do
		table.insert(p, `{where}: unknown key {k}`)
	end
end

local function checkCond(where: string, cond: any, p: { string })
	if type(cond) ~= "table" then
		table.insert(p, `{where} must be an object`)
		return
	end
	if #cond > 0 then
		table.insert(p, `{where} must be an object of context keys, not a list`)
		return
	end
	for k, v in cond do
		local at = `{where}.{tostring(k)}`
		if type(k) ~= "string" or k == "" then
			table.insert(p, `{where}: keys must be context field names`)
		elseif k == "intensity" then
			table.insert(p, `{at}: intensity picks layers by band, not themes`)
		elseif type(v) == "string" then
			if v == "" then
				table.insert(p, `{at} must not be empty`)
			end
		elseif type(v) == "boolean" then
			-- a flag
		elseif type(v) == "table" then
			local list = v
			if v["not"] ~= nil then
				list = v["not"]
				for kk in v do
					if kk ~= "not" then
						table.insert(p, `{at}: a not-condition has only the key "not"`)
					end
				end
				if type(list) ~= "table" then
					table.insert(p, `{at}.not must be a list of strings`)
					continue
				end
			end
			if #list == 0 then
				table.insert(p, `{at} must list at least one value`)
			end
			for _, s in list do
				if type(s) ~= "string" or s == "" then
					table.insert(p, `{at} values must be non-empty strings`)
					break
				end
			end
		else
			table.insert(p, `{at} must be a string, a list of strings, a not-list or a boolean`)
		end
	end
end

local function checkSound(where: string, s: any, p: { string })
	if type(s) ~= "string" then
		table.insert(p, `{where} must be a string`)
	elseif s ~= "" and not isAsset(s) and not isVaultKey(s) then
		table.insert(p, `{where} {s} must be empty, an rbxassetid://<digits> or a Vault key`)
	end
end

local function checkRange(where: string, v: any, lo: number, hi: number, p: { string }, required: boolean?)
	if v == nil then
		if required then
			table.insert(p, `{where} is required`)
		end
		return
	end
	if not isNumber(v) or v < lo or v > hi then
		table.insert(p, `{where} must be a number in {lo}..{hi}`)
	end
end

function Score.validate(score: any): { string }
	local p: { string } = {}
	if type(score) ~= "table" then
		return { "score must be a table" }
	end
	unknownKeys("score", score, TOP_KEYS, p)
	if type(score.game) ~= "string" or score.game == "" then
		table.insert(p, "game must be a non-empty string")
	end
	if score.seed ~= nil and not isNumber(score.seed) then
		table.insert(p, "seed must be a number")
	end
	checkRange("crossfade", score.crossfade, 0, 60, p)
	if score.handoff ~= nil then
		local h = score.handoff
		if type(h) ~= "table" then
			table.insert(p, "handoff must be an object")
		else
			unknownKeys("handoff", h, HANDOFF_KEYS, p)
			if h.mode ~= "sequential" then
				table.insert(p, 'handoff.mode must be "sequential"')
			end
			checkRange("handoff.fadeOut", h.fadeOut, 0, 60, p, true)
			checkRange("handoff.fadeIn", h.fadeIn, 0, 60, p, true)
		end
	end
	if score.bands ~= nil then
		local b = score.bands
		if type(b) ~= "table" or #b ~= 2 or not isNumber(b[1]) or not isNumber(b[2]) or not (0 < b[1] and b[1] < b[2] and b[2] <= 1) then
			table.insert(p, "bands must be [mid, high] with 0 < mid < high <= 1")
		end
	end
	-- groups: the Score owns the Music group only (the Soundscape owns Ambience)
	if type(score.groups) ~= "table" then
		table.insert(p, "groups must be { Music = volume }")
	else
		for k, v in score.groups do
			if k ~= "Music" then
				table.insert(p, `groups.{tostring(k)}: the Score owns only the Music group`)
			elseif not isNumber(v) or v < 0 or v > 1 then
				table.insert(p, "groups.Music must be a number in 0..1")
			end
		end
		if score.groups.Music == nil then
			table.insert(p, "groups.Music is required")
		end
	end
	-- themes
	local themes = score.themes
	if type(themes) ~= "table" or #themes == 0 then
		table.insert(p, "themes must be a non-empty list")
	else
		local ids: { [string]: boolean } = {}
		for i, th in themes do
			local w = `themes[{i}]`
			if type(th) ~= "table" then
				table.insert(p, `{w} must be an object`)
				continue
			end
			unknownKeys(w, th, THEME_KEYS, p)
			if type(th.id) ~= "string" or th.id == "" or string.find(th.id, "/", 1, true) then
				table.insert(p, `{w}.id must be a non-empty string without "/"`)
			elseif ids[th.id] then
				table.insert(p, `{w}: duplicate theme id {th.id}`)
			else
				ids[th.id] = true
			end
			checkRange(`{w}.bpm`, th.bpm, 20, 400, p, true)
			if not isNumber(th.beatsPerBar) or th.beatsPerBar ~= math.floor(th.beatsPerBar) or th.beatsPerBar < 1 or th.beatsPerBar > 16 then
				table.insert(p, `{w}.beatsPerBar must be a whole number in 1..16`)
			end
			checkRange(`{w}.crossfade`, th.crossfade, 0, 60, p)
			if th.when ~= nil then
				checkCond(`{w}.when`, th.when, p)
			end
			if type(th.layers) ~= "table" or #th.layers == 0 then
				table.insert(p, `{w}.layers must be a non-empty list`)
			else
				local lids: { [string]: boolean } = {}
				for j, l in th.layers do
					local lw = `{w}.layers[{j}]`
					if type(l) ~= "table" then
						table.insert(p, `{lw} must be an object`)
						continue
					end
					unknownKeys(lw, l, LAYER_KEYS, p)
					if type(l.id) ~= "string" or l.id == "" then
						table.insert(p, `{lw}.id must be a non-empty string`)
					elseif lids[l.id] then
						table.insert(p, `{lw}: duplicate layer id {l.id}`)
					else
						lids[l.id] = true
					end
					checkSound(`{lw}.sound`, l.sound, p)
					local v = l.volume
					if type(v) ~= "table" or #v ~= 3 then
						table.insert(p, `{lw}.volume must be [low, mid, high]`)
					else
						local any = false
						for b = 1, 3 do
							if not isNumber(v[b]) or v[b] < 0 or v[b] > 10 then
								table.insert(p, `{lw}.volume[{b}] must be a number in 0..10`)
							elseif v[b] > 0 then
								any = true
							end
						end
						if not any then
							table.insert(p, `{lw}.volume is 0 in every band: the layer can never be heard`)
						end
					end
				end
			end
		end
	end
	-- stingers
	if score.stingers ~= nil then
		if type(score.stingers) ~= "table" then
			table.insert(p, "stingers must be a list")
		else
			local keys: { [string]: boolean } = {}
			for i, st in score.stingers do
				local w = `stingers[{i}]`
				if type(st) ~= "table" then
					table.insert(p, `{w} must be an object`)
					continue
				end
				unknownKeys(w, st, STINGER_KEYS, p)
				if type(st.on) ~= "string" or st.on == "" then
					table.insert(p, `{w}.on must name an event`)
				end
				if st.id ~= nil and (type(st.id) ~= "string" or st.id == "") then
					table.insert(p, `{w}.id must be a non-empty string`)
				end
				local key = st.id or st.on
				if type(key) == "string" then
					if keys[key] then
						table.insert(p, `{w}: duplicate stinger key {key} (give one an id)`)
					end
					keys[key] = true
				end
				checkSound(`{w}.sound`, st.sound, p)
				checkRange(`{w}.duck`, st.duck, 0, 1, p, true)
				checkRange(`{w}.hold`, st.hold, 0, 120, p, true)
				if not isNumber(st.priority) then
					table.insert(p, `{w}.priority must be a number`)
				end
				checkRange(`{w}.cooldown`, st.cooldown, 0, 3600, p, true)
				checkRange(`{w}.volume`, st.volume, 0, 10, p)
			end
		end
	end
	-- silence
	local sil = score.silence
	if sil ~= nil then
		if type(sil) ~= "table" then
			table.insert(p, "silence must be an object")
		else
			unknownKeys("silence", sil, SILENCE_KEYS, p)
			if not isNumber(sil.minGap) or sil.minGap <= 0 then
				table.insert(p, "silence.minGap must be a number > 0 (seconds)")
			end
			if not isNumber(sil.windowSeconds) or sil.windowSeconds <= 0 then
				table.insert(p, "silence.windowSeconds must be a number > 0")
			end
			checkRange("silence.afterMinutes", sil.afterMinutes, 0, 1440, p, true)
			checkRange("silence.chance", sil.chance, 0, 1, p)
			if sil.never ~= nil then
				local list = neverList(sil.never)
				for i, cond in list do
					local w = if list == sil.never then `silence.never[{i}]` else "silence.never"
					checkCond(w, cond, p)
					if type(cond) == "table" and next(cond) == nil then
						table.insert(p, `{w} is empty and matches every state: silence could never happen`)
					end
				end
			end
		end
	end
	return p
end

-- pure queries -------------------------------------------------------------------------------

function Score.barLength(theme: any): number
	return theme.beatsPerBar * 60 / theme.bpm
end

-- The first bar boundary at or after t of a bar clock anchored at `anchor`.
function Score.nextBar(anchor: number, barLength: number, t: number): number
	if t <= anchor then
		return anchor
	end
	local k = math.ceil((t - anchor) / barLength - 1e-7)
	return anchor + k * barLength
end

function Score.band(score: any, intensity: any): number
	local b = score.bands or Score.DEFAULT_BANDS
	local i = if isNumber(intensity) then math.clamp(intensity, 0, 1) else 0
	if i >= b[2] then
		return 3
	elseif i >= b[1] then
		return 2
	end
	return 1
end

function Score.pick(score: any, context: any): (any, number?)
	for i, th in score.themes do
		if Score.when(th.when, context) then
			return th, i
		end
	end
	return nil, nil
end

local function seedOf(score: any): number
	if isNumber(score.seed) then
		return math.floor(math.abs(score.seed)) % TWO32
	end
	return fnv(tostring(score.game or "score"))
end

local function slotLength(sil: any): number
	return sil.minGap * 2 + sil.windowSeconds
end

-- The candidate window of silence slot k: { slot, start, stop, chosen }. Pure and deterministic.
function Score.window(score: any, k: number): any
	local sil = score.silence
	local L = slotLength(sil)
	local rng = Contract.Rng.new(fnv(`{seedOf(score)}:silence:{k}`))
	local u = rng:next() * sil.minGap
	local roll = rng:next()
	local start = k * L + u
	return { slot = k, start = start, stop = start + sil.windowSeconds, chosen = roll < (sil.chance or 1) }
end

-- Every chosen candidate window that overlaps [from, to].
function Score.windows(score: any, from: number, to: number): { any }
	local out = {}
	if score.silence == nil then
		return out
	end
	local L = slotLength(score.silence)
	for k = math.floor(from / L), math.floor(to / L) do
		local w = Score.window(score, k)
		if w.chosen and w.stop > from and w.start <= to then
			table.insert(out, w)
		end
	end
	return out
end

-- runtime ------------------------------------------------------------------------------------

function Score.new(adapter: Contract.Adapter, score: any, sink: Sink)
	local problems = Contract.check(adapter)
	assert(#problems == 0, "Score.new: " .. table.concat(problems, "; "))
	local sp = Score.validate(score)
	assert(#sp == 0, "Score.new: invalid score: " .. table.concat(sp, "; "))
	assert(type(sink) == "function", "Score.new: sink must be a function")
	local self: any = setmetatable({
		adapter = adapter,
		score = score,
		sink = sink,
		context = {},
		band = 1,
		current = nil, -- { theme, index, anchor, bar, band, volumes = { [layerId] = v } }
		pending = nil, -- { index = themeIndex | 0 (no music), at }
		pendingBand = nil, -- { band, at }
		silence = nil, -- { untilAt, slot }
		decidedSlot = nil,
		musicSince = nil,
		duckLevel = 1,
		active = nil, -- { key, priority, untilAt }
		lastFired = {},
		stingers = {},
		disconnect = {},
		stopped = false,
		seq = if score.handoff then { level = 0, dir = 0 } else nil, -- the sequential handoff's fader
		lastNow = nil,
		counts = {
			themeChanges = 0,
			bandChanges = 0,
			stingersPlayed = 0,
			refusedCooldown = 0,
			refusedPriority = 0,
			missingSounds = 0,
			silences = 0,
			silencesCut = 0,
		},
	}, Methods)
	for _, st in score.stingers or {} do
		local key = st.id or st.on
		self.stingers[key] = st
		table.insert(
			self.disconnect,
			adapter.on(st.on, function(_payload)
				self:stinger(key)
			end)
		)
	end
	return self
end

local function send(self: any, cmd: { [string]: any })
	cmd.group = Score.GROUP
	self.sink(cmd)
end

local function fadeOf(self: any, theme: any): number
	return theme.crossfade or self.score.crossfade or Score.DEFAULT_CROSSFADE
end

local pickIndex: (any, any) -> number?

local function layerName(theme: any, layer: any): string
	return theme.id .. "/" .. layer.id
end

local function stopCurrent(self: any, at: number, silence: boolean?, time: number?)
	local cur = self.current
	if not cur then
		return
	end
	local fade = if time ~= nil then time else fadeOf(self, cur.theme)
	for _, layer in cur.theme.layers do
		if layer.sound ~= "" then
			send(self, {
				op = "stop",
				layer = layerName(cur.theme, layer),
				sound = layer.sound,
				at = at,
				time = fade,
				theme = cur.theme.id,
				silence = silence,
			})
		end
	end
	self.current = nil
	self.pendingBand = nil
end

local function startTheme(self: any, index: number, at: number)
	local theme = self.score.themes[index]
	local fade = if self.seq then self.score.handoff.fadeIn else fadeOf(self, theme)
	if self.seq then
		self.seq.level, self.seq.dir = 0, 1
	end
	local volumes = {}
	for _, layer in theme.layers do
		local v = layer.volume[self.band]
		volumes[layer.id] = v
		if layer.sound == "" then
			self.counts.missingSounds += 1
		else
			send(self, {
				op = "play",
				layer = layerName(theme, layer),
				sound = layer.sound,
				volume = v,
				at = at,
				time = fade,
				loop = true,
				theme = theme.id,
			})
		end
	end
	self.current = { theme = theme, index = index, anchor = at, bar = Score.barLength(theme), band = self.band, volumes = volumes }
	if self.musicSince == nil then
		self.musicSince = at
	end
end

local function commitTheme(self: any, index: number, at: number)
	stopCurrent(self, at)
	self.counts.themeChanges += 1
	if index > 0 then
		startTheme(self, index, at)
	else
		self.musicSince = nil
	end
end

local function commitBand(self: any, band: number, at: number)
	local cur = self.current
	if not cur then
		return
	end
	self.counts.bandChanges += 1
	for _, layer in cur.theme.layers do
		local v = layer.volume[band]
		if v ~= cur.volumes[layer.id] then
			cur.volumes[layer.id] = v
			if layer.sound ~= "" then
				send(self, {
					op = "fade",
					layer = layerName(cur.theme, layer),
					sound = layer.sound,
					volume = v,
					at = at,
					time = fadeOf(self, cur.theme),
					theme = cur.theme.id,
				})
			end
		end
	end
	cur.band = band
end

local function setDuck(self: any, level: number, at: number, time: number)
	if math.abs(level - self.duckLevel) > Score.EPS then
		self.duckLevel = level
		send(self, { op = "duck", volume = level, at = at, time = time })
	end
end

local function cast(theme: any): boolean
	for _, layer in theme.layers do
		if layer.sound ~= "" then
			return true
		end
	end
	return false
end

-- The theme index the context picks. Under a sequential handoff a theme with no cast layer is
-- silence (nil), so a change away from it never waits on a fade.
pickIndex = function(self: any, ctx: any): number?
	local theme, index = Score.pick(self.score, ctx)
	if self.seq and theme and not cast(theme) then
		return nil
	end
	return index
end

-- The earliest queued event due at or before t: (kind, at) or nil.
local function nextDue(self: any, t: number): (string?, number)
	local kind, at = nil, math.huge
	local function consider(k: string, when: number?)
		if when ~= nil and when <= t + Score.EPS and when < at then
			kind, at = k, when
		end
	end
	if self.silence then
		consider("silenceEnd", self.silence.untilAt)
	else
		if self.pending then
			consider("theme", self.pending.at)
		end
		if self.pendingBand then
			consider("band", self.pendingBand.at)
		end
		local sil = self.score.silence
		if sil and self.current then
			local k = math.floor(t / slotLength(sil))
			if self.decidedSlot ~= k then
				local w = Score.window(self.score, k)
				consider("silenceStart", w.start)
			end
		end
	end
	if self.active then
		consider("release", self.active.untilAt)
	end
	return kind, at
end

-- Commit every queued event due by time t, in time order.
local function advance(self: any, t: number)
	for _ = 1, 1000 do
		local kind, at = nextDue(self, t)
		if kind == nil then
			return
		elseif kind == "theme" then
			local index = self.pending.index
			self.pending = nil
			commitTheme(self, index, at)
		elseif kind == "band" then
			local band = self.pendingBand.band
			self.pendingBand = nil
			commitBand(self, band, at)
		elseif kind == "release" then
			self.active = nil
			setDuck(self, 1, at, Score.DUCK_RELEASE)
		elseif kind == "silenceStart" then
			local sil = self.score.silence
			local k = math.floor(t / slotLength(sil))
			self.decidedSlot = k
			local w = Score.window(self.score, k)
			-- music must have been playing (continuously, since musicSince) when the window opens
			local since = self.musicSince or math.huge
			local played = at - since
			local fresh = at + Score.EPS >= self.current.anchor
			if w.chosen and fresh and t < w.stop and played >= sil.afterMinutes * 60 - Score.EPS and not Score.never(self.score, self.context) then
				self.counts.silences += 1
				self.silence = { untilAt = w.stop, slot = k }
				self.pending = nil
				stopCurrent(self, at, true)
				if self.seq then
					self.seq.level, self.seq.dir = 0, 0
				end
			end
		elseif kind == "silenceEnd" then
			self.silence = nil
			self.musicSince = nil
			local index = pickIndex(self, self.context)
			if index then
				startTheme(self, index, at)
			end
		end
	end
	error("Score: event loop did not settle (a bar length of 0?)")
end

-- Look at the newest context and queue what it asks for.
local function evaluate(self: any, now: number)
	local ctx = self.context
	self.band = Score.band(self.score, ctx.intensity)
	if self.silence then
		if Score.never(self.score, ctx) then
			-- a never-state began inside the window: the window ends now
			self.counts.silencesCut += 1
			self.silence.untilAt = now
		end
		return
	end
	local _, index = Score.pick(self.score, ctx)
	local cur = self.current
	if cur == nil then
		self.pending = nil
		if index then
			startTheme(self, index, now)
			self.counts.themeChanges += 1
		end
		return
	end
	local want = index or 0
	if want == cur.index then
		self.pending = nil
	elseif self.pending == nil or self.pending.index ~= want then
		self.pending = { index = want, at = Score.nextBar(cur.anchor, cur.bar, now) }
	end
	if self.band == cur.band then
		self.pendingBand = nil
	elseif self.pendingBand == nil or self.pendingBand.band ~= self.band then
		self.pendingBand = { band = self.band, at = Score.nextBar(cur.anchor, cur.bar, now) }
	end
end

-- Every cast layer of the playing theme, faded to `level` of its band volume over `time`.
local function fadeLayers(self: any, level: number, at: number, time: number)
	local cur = self.current
	for _, layer in cur.theme.layers do
		if layer.sound ~= "" then
			send(self, {
				op = "fade",
				layer = layerName(cur.theme, layer),
				sound = layer.sound,
				volume = cur.volumes[layer.id] * level,
				at = at,
				time = time,
				theme = cur.theme.id,
			})
		end
	end
end

-- The sequential handoff: a per-frame fader over dt. A change starts now (not on the bar): the
-- playing theme fades out from its level (dt counted in this frame, so the ramp starts at
-- now - dt), and once it reaches 0 it stops and the wanted theme starts, fading in over fadeIn.
-- A change back while fading out fades the same theme up again from where it is.
local function evaluateSequential(self: any, now: number, dt: number)
	local ctx = self.context
	local h = self.score.handoff
	local seq = self.seq
	self.band = Score.band(self.score, ctx.intensity)
	self.pending = nil
	if self.silence then
		if Score.never(self.score, ctx) then
			self.counts.silencesCut += 1
			self.silence.untilAt = now
		end
		return
	end
	local want = pickIndex(self, ctx) or 0
	local cur = self.current
	local curIndex = if cur then cur.index else 0
	if want ~= curIndex then
		self.pendingBand = nil
		if cur and seq.level > 0 then
			if seq.dir ~= -1 then
				seq.dir = -1
				fadeLayers(self, 0, now - dt, seq.level * h.fadeOut)
			end
			seq.level = if h.fadeOut > 0 then math.max(0, seq.level - dt / h.fadeOut) else 0
			if seq.level > 0 then
				return
			end
		end
		self.counts.themeChanges += 1
		stopCurrent(self, now, nil, 0)
		seq.level, seq.dir = 0, 0
		if want > 0 then
			startTheme(self, want, now)
		else
			self.musicSince = nil
		end
		return
	end
	if cur == nil then
		return
	end
	if seq.level < 1 then
		if seq.dir ~= 1 then
			seq.dir = 1
			fadeLayers(self, 1, now - dt, (1 - seq.level) * h.fadeIn)
		end
		seq.level = if h.fadeIn > 0 then math.min(1, seq.level + dt / h.fadeIn) else 1
	end
	if seq.dir ~= 1 or self.band == cur.band then
		self.pendingBand = nil
	elseif self.pendingBand == nil or self.pendingBand.band ~= self.band then
		self.pendingBand = { band = self.band, at = Score.nextBar(cur.anchor, cur.bar, now) }
	end
end

function Methods.update(self: any, context: any, dt: number?)
	if self.stopped then
		return
	end
	assert(dt == nil or (isNumber(dt) and dt >= 0), "Score:update: dt must be a number >= 0")
	local now = self.adapter.now()
	local step = if dt ~= nil then dt else math.max(0, now - (self.lastNow or now))
	self.lastNow = now
	advance(self, now)
	self.context = if type(context) == "table" then context else {}
	if self.seq then
		evaluateSequential(self, now, step)
	else
		evaluate(self, now)
	end
	advance(self, now)
end

function Methods.stinger(self: any, key: string): boolean
	if self.stopped then
		return false
	end
	local st = self.stingers[key]
	if st == nil then
		self.adapter.log("warn", `Score: no stinger {key}`)
		return false
	end
	local now = self.adapter.now()
	advance(self, now)
	if st.sound == "" then
		self.counts.missingSounds += 1
		return false
	end
	local last = self.lastFired[key]
	if last ~= nil and now - last < st.cooldown - Score.EPS then
		self.counts.refusedCooldown += 1
		return false
	end
	local active = self.active
	if active and now < active.untilAt and active.priority > st.priority then
		self.counts.refusedPriority += 1
		return false
	end
	self.lastFired[key] = now
	self.counts.stingersPlayed += 1
	send(self, { op = "stinger", key = key, sound = st.sound, volume = st.volume or 1, at = now, priority = st.priority })
	self.active = { key = key, priority = st.priority, untilAt = now + st.hold }
	setDuck(self, 1 - st.duck, now, Score.DUCK_ATTACK)
	advance(self, now)
	return true
end

function Methods.state(self: any)
	local cur = self.current
	local pending: any = nil
	if self.pending then
		pending = if self.pending.index > 0 then self.score.themes[self.pending.index].id else false
	end
	return {
		theme = cur and cur.theme.id or nil,
		band = cur and cur.band or self.band,
		anchor = cur and cur.anchor or nil,
		pending = pending, -- a theme id, false (music ends at the bar) or nil
		pendingAt = self.pending and self.pending.at or nil,
		duck = self.duckLevel,
		stinger = self.active and self.active.key or nil,
		silent = self.silence ~= nil,
		silenceUntil = self.silence and self.silence.untilAt or nil,
		musicSince = self.musicSince,
	}
end

function Methods.stats(self: any)
	return table.clone(self.counts)
end

function Methods.stop(self: any)
	if self.stopped then
		return
	end
	local now = self.adapter.now()
	stopCurrent(self, now)
	self.stopped = true
	for _, d in self.disconnect do
		d()
	end
	self.disconnect = {}
end

return Score
