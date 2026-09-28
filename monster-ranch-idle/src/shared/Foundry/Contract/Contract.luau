--!strict
-- Contract: the only way a Foundry package touches its game.
--
-- Packages are game-neutral logic. They never read a game's kernel, services or config
-- directly; each game passes an Adapter (built once per kernel) into a package's `new`.
-- Runtime systems that own Instances stay in each game's repo under its own kernel and
-- call packages for the logic (agreed with the Worldsmith session, 2026-09-26).
--
--   local Contract = require("../Contract/Contract")
--   local adapter = Contract.mock({ game = "fixture" })   -- specs
--   local problems = Contract.check(adapter)              -- {} when complete
--   local rng = Contract.Rng.new(1234)                    -- same numbers in Lune and Roblox

export type Level = "info" | "warn" | "error"

export type Rng = {
	next: (self: Rng) -> number, -- [0, 1)
	int: (self: Rng, lo: number, hi: number) -> number, -- inclusive
	pick: <T>(self: Rng, list: { T }) -> T,
	state: (self: Rng) -> number,
}

export type Adapter = {
	game: string, -- profile id
	now: () -> number, -- shared world clock in seconds; identical on every client
	rng: (seed: number) -> Rng, -- seeded generator (use Contract.Rng unless the game has its own)
	log: (level: Level, msg: string, data: any?) -> (),
	budget: (kind: string) -> number?, -- cap for a budget kind at the active quality level; nil = unlimited
	quality: () -> number, -- 1 low, 2 medium, 3 high
	on: (event: string, fn: (payload: any) -> ()) -> () -> (), -- subscribe; returns disconnect
	emit: (event: string, payload: any?) -> (),
	tag: (inst: any, system: string) -> (), -- mark an instance as spent by `system` (<prefix>System, Budget Lens)
}

local Contract = {}

-- Rng --------------------------------------------------------------------------------------
-- mulberry32 in exact 32-bit integer arithmetic (16-bit halves for the multiply), so a seed
-- gives the same stream under Lune and in Roblox.

local TWO32 = 4294967296

local function imul(a: number, b: number): number
	local aHi, aLo = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bHi, bLo = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	local mid = bit32.band(aHi * bLo + aLo * bHi, 0xFFFF)
	return (aLo * bLo + mid * 65536) % TWO32
end

local RngMethods = {}
RngMethods.__index = RngMethods

function RngMethods.next(self: any): number
	local a = (self._s + 0x6D2B79F5) % TWO32
	self._s = a
	local t = imul(bit32.bxor(a, bit32.rshift(a, 15)), bit32.bor(a, 1))
	t = bit32.bxor(t, (t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % TWO32)
	return bit32.bxor(t, bit32.rshift(t, 14)) / TWO32
end

function RngMethods.int(self: any, lo: number, hi: number): number
	return lo + math.floor(self:next() * (hi - lo + 1))
end

function RngMethods.pick(self: any, list: { any }): any
	assert(#list > 0, "Rng:pick on an empty list")
	return list[self:int(1, #list)]
end

function RngMethods.state(self: any): number
	return self._s
end

Contract.Rng = {
	new = function(seed: number): Rng
		assert(type(seed) == "number", "Rng.new needs a number seed")
		local s = math.floor(math.abs(seed)) % TWO32
		return (setmetatable({ _s = s }, RngMethods) :: any) :: Rng
	end,
}

-- check ------------------------------------------------------------------------------------

local FIELDS: { [string]: string } = {
	game = "string",
	now = "function",
	rng = "function",
	log = "function",
	budget = "function",
	quality = "function",
	on = "function",
	emit = "function",
	tag = "function",
}

function Contract.check(adapter: any): { string }
	local problems = {}
	if type(adapter) ~= "table" then
		return { "adapter must be a table" }
	end
	local names = {}
	for k in FIELDS do
		table.insert(names, k)
	end
	table.sort(names)
	for _, k in names do
		if type(adapter[k]) ~= FIELDS[k] then
			table.insert(problems, `adapter.{k} must be a {FIELDS[k]}, got {typeof(adapter[k])}`)
		end
	end
	return problems
end

-- mock -------------------------------------------------------------------------------------
-- A complete in-memory adapter for specs: a manual clock, an event bus, collected logs,
-- a budget table and recorded tags.

export type Mock = Adapter & {
	advance: (dt: number) -> (),
	setQuality: (q: number) -> (),
	logs: { { level: Level, msg: string, data: any? } },
	tags: { { inst: any, owner: string } },
	emitted: { { event: string, payload: any? } },
}

function Contract.mock(opts: { game: string?, t0: number?, quality: number?, budgets: { [string]: number }? }?): Mock
	local o = opts or {}
	local t = o.t0 or 0
	local q = o.quality or 3
	local budgets = o.budgets or {}
	local handlers: { [string]: { (any) -> () } } = {}
	local m: any = {
		game = o.game or "fixture",
		logs = {},
		tags = {},
		emitted = {},
	}
	m.now = function()
		return t
	end
	m.advance = function(dt: number)
		t += dt
	end
	m.rng = function(seed: number)
		return Contract.Rng.new(seed)
	end
	m.log = function(level: Level, msg: string, data: any?)
		table.insert(m.logs, { level = level, msg = msg, data = data })
	end
	m.budget = function(kind: string)
		return budgets[kind]
	end
	m.quality = function()
		return q
	end
	m.setQuality = function(v: number)
		q = v
	end
	m.on = function(event: string, fn: (any) -> ())
		handlers[event] = handlers[event] or {}
		table.insert(handlers[event], fn)
		return function()
			local list = handlers[event]
			if not list then
				return
			end
			for i = #list, 1, -1 do
				if list[i] == fn then
					table.remove(list, i)
				end
			end
		end
	end
	m.emit = function(event: string, payload: any?)
		table.insert(m.emitted, { event = event, payload = payload })
		for _, fn in table.clone(handlers[event] or {}) do
			fn(payload)
		end
	end
	m.tag = function(inst: any, owner: string)
		table.insert(m.tags, { inst = inst, owner = owner })
	end
	return m :: Mock
end

return Contract
