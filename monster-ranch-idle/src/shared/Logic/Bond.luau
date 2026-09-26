--[[
	Logic/Bond (glow-up Q): pure rules for monster bond, shared by Systems/Bond, the Care screen
	and the cards. No Roblox APIs, so everything here is unit-tested in Lune (Bond.spec).

	  Bond.Hearts(points, cfg) -> 0..MaxHearts
	  Bond.Progress(points, cfg) -> (hearts, into, need)   points into the next heart (need 0 at max)
	  Bond.IncomePct(hearts, cfg) -> fraction              the monster's own coin-rate bonus
	  Bond.Ready(entry, kind, now, cfg) -> (ready, secondsLeft)   entry = the monster's bond record
	  Bond.TricksAt(hearts, cfg) -> { trick }              tricks learned at this many hearts
	  Bond.Best(list, n, cfg) -> { { id, points, hearts } }   top bond first (points, then id)
	  Bond.Sanitize(section, cfg, validId?) -> section     repairs a saved section (migration)

	Gestures: Bond.Gesture.new(kind, cfg, hold?) -> gesture. Feed it inputs with a clock the caller
	owns (seconds), read :Progress() (0..1) and :Done(). `hold` = the gamepad / keyboard version:
	any kind is a press-and-hold. A gesture never fails; it only ends by finishing or being stopped.
	  gesture:Down(t, x?)  gesture:Up(t)  gesture:Move(t, x)  gesture:Tap(t)  gesture:Step(t)
	  gesture:Beat(t) -> number   0..1 phase of Play's bounce (1 = on the beat)
]]

local Bond = {}

function Bond.Hearts(points: number?, cfg): number
	local p = tonumber(points) or 0
	local hearts = 0
	for i, need in cfg.HeartAt do
		if p >= need then
			hearts = i
		else
			break
		end
	end
	return math.min(hearts, cfg.MaxHearts)
end

function Bond.Progress(points: number?, cfg): (number, number, number)
	local p = tonumber(points) or 0
	local hearts = Bond.Hearts(p, cfg)
	if hearts >= cfg.MaxHearts or hearts >= #cfg.HeartAt then
		return hearts, 0, 0
	end
	local base = if hearts > 0 then cfg.HeartAt[hearts] else 0
	return hearts, p - base, cfg.HeartAt[hearts + 1] - base
end

function Bond.IncomePct(hearts: number?, cfg): number
	local h = math.max(0, math.floor(tonumber(hearts) or 0))
	local income = cfg.Income
	return math.min(income.max, math.floor(h / income.heartsPerStep) * income.step)
end

function Bond.Ready(entry, kind: string, now: number, cfg): (boolean, number)
	local last = if type(entry) == "table" then tonumber(entry[kind]) or 0 else 0
	if last <= 0 then
		return true, 0
	end
	local left = last + cfg.cooldown - now
	if left <= 0 then
		return true, 0
	end
	return false, left
end

function Bond.TricksAt(hearts: number?, cfg): { any }
	local h = tonumber(hearts) or 0
	local list = {}
	for _, trick in cfg.Tricks do
		if h >= trick.bond then
			table.insert(list, trick)
		end
	end
	return list
end

function Bond.Best(list, n: number, cfg): { { id: string, points: number, hearts: number } }
	local rows = {}
	for id, entry in if type(list) == "table" then list else {} do
		local points = if type(entry) == "table" then tonumber(entry.pts) or 0 else 0
		local hearts = Bond.Hearts(points, cfg)
		if type(id) == "string" and hearts >= 1 then
			table.insert(rows, { id = id, points = points, hearts = hearts })
		end
	end
	table.sort(rows, function(a, b)
		if a.points ~= b.points then
			return a.points > b.points
		end
		return a.id < b.id
	end)
	while #rows > n do
		table.remove(rows)
	end
	return rows
end

-- Keeps only well-formed entries: string ids (that validId accepts), whole points within the
-- last heart, and care times for known kinds.
function Bond.Sanitize(section, cfg, validId: ((string) -> boolean)?)
	local out = { list = {}, cares = 0 }
	if type(section) ~= "table" then
		return out
	end
	out.cares = math.max(0, math.floor(tonumber(section.cares) or 0))
	local maxPoints = cfg.HeartAt[#cfg.HeartAt]
	for id, entry in if type(section.list) == "table" then section.list else {} do
		if type(id) == "string" and type(entry) == "table" and (validId == nil or validId(id)) then
			local clean = { pts = math.clamp(math.floor(tonumber(entry.pts) or 0), 0, maxPoints) }
			for _, kind in cfg.KindIds do
				local t = tonumber(entry[kind])
				if t and t > 0 then
					clean[kind] = math.floor(t)
				end
			end
			out.list[id] = clean
		end
	end
	return out
end

-- Gestures ------------------------------------------------------------------------------------

local Gesture = {}
Gesture.__index = Gesture
Bond.Gesture = Gesture

function Gesture.new(kind: string, cfg, hold: boolean?)
	local g = cfg.Gesture
	return setmetatable({
		kind = kind,
		cfg = g,
		hold = hold == true or kind == "pet",
		startedAt = nil,
		down = false,
		downAt = 0,
		held = 0,
		strokes = 0,
		dir = 0,
		anchor = nil,
		lastStroke = -math.huge,
		taps = 0,
		lastTapBeat = -1,
	}, Gesture)
end

function Gesture:_start(t: number)
	if not self.startedAt then
		self.startedAt = t
	end
end

function Gesture:Step(t: number)
	self:_start(t)
	if self.down and self.hold then
		self.held += math.max(0, t - self.downAt)
		self.downAt = t
	end
end

function Gesture:Down(t: number, x: number?)
	self:Step(t)
	self.down = true
	self.downAt = t
	self.anchor = x
	self.dir = 0
	if not self.hold and self.kind == "play" then
		self:Tap(t)
	end
end

function Gesture:Up(t: number)
	self:Step(t)
	self.down = false
	self.anchor = nil
end

-- Brush: a stroke counts each time the pointer turns round after travelling strokePixels.
function Gesture:Move(t: number, x: number)
	self:Step(t)
	if self.hold or self.kind ~= "brush" or not self.down then
		return
	end
	if not self.anchor then
		self.anchor = x
		return
	end
	local delta = x - self.anchor
	if math.abs(delta) < self.cfg.strokePixels then
		if self.dir ~= 0 and delta * self.dir < 0 then
			self.anchor = x -- a small wiggle back: measure the next stroke from here
		end
		return
	end
	local dir = if delta > 0 then 1 else -1
	if dir ~= self.dir and t - self.lastStroke >= self.cfg.strokeGap then
		self.strokes += 1
		self.lastStroke = t
		self.dir = dir
	end
	self.anchor = x
end

function Gesture:Beat(t: number): number
	local start = self.startedAt or t
	local phase = ((t - start) % self.cfg.beat) / self.cfg.beat
	return 1 - math.min(phase, 1 - phase) * 2
end

-- Play: a tap within `window` seconds of a bounce counts, once per bounce.
function Gesture:Tap(t: number)
	self:Step(t)
	if self.hold or self.kind ~= "play" then
		return
	end
	local elapsed = t - (self.startedAt or t)
	local beat = math.floor(elapsed / self.cfg.beat + 0.5)
	if beat < 1 or beat == self.lastTapBeat then
		return
	end
	if math.abs(elapsed - beat * self.cfg.beat) <= self.cfg.window then
		self.taps += 1
		self.lastTapBeat = beat
	end
end

function Gesture:Progress(): number
	if self.hold then
		return math.clamp(self.held / self.cfg.holdSeconds, 0, 1)
	elseif self.kind == "brush" then
		return math.clamp(self.strokes / self.cfg.strokes, 0, 1)
	end
	return math.clamp(self.taps / self.cfg.taps, 0, 1)
end

function Gesture:Done(): boolean
	return self:Progress() >= 1
end

return Bond
