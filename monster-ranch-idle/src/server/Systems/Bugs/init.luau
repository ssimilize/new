--[[
	Bugs (update 3.13 · Wild things): the Bug Catching Meadow west of the Market Square. Rules:
	Config/Bugs and Logic/Bugs. Opened from the meadow signpost's "Catch bugs" prompt
	(Controllers/BugMeadow).

	Save section (profile.Bugs, version 1):
	  day, swings           -- free swings used today (UTC day)
	  n                     -- swings ever (the swing id)
	  secret                -- PRIVATE: mixed into every swing's seed
	  lure                  -- swings left with the honey lure's weights
	  jar = { [bugId]: n }  -- bugs held (sold for coins)
	  log = { [bugId]: n }  -- the Bug Log: caught ever
	  total                 -- bugs caught ever

	The open swing lives in memory only (one per player, one-shot): { id, bug, path, startedAt }.

	Actions:
	  Bugs.Start {} -> { id, path = { delay, duration, twist, freq, bob, phase, total }, left, lure }
	    Uses one of today's swings; seed = Logic/Bugs.Seed(userId, day, swing n, secret). The bug is
	    rolled here (season via Logic/Seasons.At(now), night via the Weather night phase, the lure's
	    weights while it lasts) and only the path goes to the client. A new Start replaces an open swing.
	  Bugs.Submit { id, t } -> { caught, bug?, rarity?, first, left }
	    t = seconds since the start. The id must be the open swing's; the server clock must have
	    reached t (ClockGrace slack) and be within the path's time + LateSeconds. Caught when the
	    replayed path had the bug in the net at t (Logic/Bugs.Hit); a miss still used the swing.
	  Bugs.Lure {} -> { lure }   spends LureHoney honey (Apiary:SpendAnyHoney), lure = LureSwings
	  Bugs.Sell { bug, amount } -> { coins }   coins = the bug's `coins` seconds of ranch income each

	Public API:
	  Bugs:Caught(player) -> { [bugId]: number }   caught ever (a copy)
	  Bugs:SpeciesCaught(player) -> number         kinds in the Bug Log (Codex Bug Log milestones)

	Publishes BugCaught (player, { bug, rarity }) for each catch (weekly goal bugs_15; the Museum's
	Insect Hall fills itself from it).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Bugs)
local Seasons = require(Shared.Logic.Seasons)

local Bugs = {
	Name = "Bugs",
	Dependencies = { "Progression", "Rewards" },
	OptionalDependencies = { "Apiary" },
}

local function normalize(s)
	if type(s) ~= "table" then
		s = {}
	end
	local function num(v): number
		return if type(v) == "number" and v == v then math.max(0, math.floor(v)) else 0
	end
	local function counts(v)
		local out = {}
		if type(v) == "table" then
			for id, n in v do
				if type(id) == "string" and type(n) == "number" and n == n and n >= 1 then
					out[id] = math.floor(n)
				end
			end
		end
		return out
	end
	s.day = num(s.day)
	s.swings = num(s.swings)
	s.n = num(s.n)
	s.secret = num(s.secret)
	s.lure = num(s.lure)
	s.jar = counts(s.jar)
	s.log = counts(s.log)
	s.total = num(s.total)
	return s
end

Bugs.Profile = {
	Version = 1,
	Private = { "secret" },
	Default = function()
		return { day = 0, swings = 0, n = 0, secret = 0, lure = 0, jar = {}, log = {}, total = 0 }
	end,
	Migrate = function(section, _fromVersion)
		return normalize(section)
	end,
}

local ctx
local Cfg -- Config.Bugs
local Progression, Rewards
local Apiary -- optional (found in Start)

local open = {} -- [player] = { id, bug, path, startedAt }

local function mustSection(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

local function sync(player, s)
	local day = ctx:Day()
	if s.day ~= day then
		s.day = day
		s.swings = 0
		ctx:Dirty(player)
	end
end

-- Public API ---------------------------------------------------------------------------

function Bugs:Caught(player): { [string]: number }
	local s = ctx:Section(player)
	return if s then table.clone(s.log) else {}
end

function Bugs:SpeciesCaught(player): number
	local s = ctx:Section(player)
	return if s then Logic.Species(s.log) else 0
end

-- Actions ------------------------------------------------------------------------------

local function start(player)
	local s = mustSection(player)
	Progression:Require(player, Cfg.Unlock)
	sync(player, s)
	if s.swings >= Cfg.FreeSwings then
		ctx:Fail("No swings left today. Come back tomorrow")
	end
	if s.secret == 0 then
		s.secret = ctx.Rng:Int(1, 2 ^ 30)
	end
	s.swings += 1
	s.n += 1
	local lured = s.lure > 0
	if lured then
		s.lure -= 1
	end
	ctx:Dirty(player)
	local now = ctx:Now()
	local seed = Logic.Seed(player.UserId, s.day, s.swings, s.secret)
	local def = Logic.Roll(seed, Seasons.At(now).id, Logic.Night(now), lured)
	local path = Logic.Path(seed, def.rarity)
	open[player] = { id = s.n, bug = def.id, path = path, startedAt = ctx.Clock.Precise() }
	return { id = s.n, path = path, left = Cfg.FreeSwings - s.swings, lure = s.lure }
end

local function submit(player, payload)
	local s = mustSection(player)
	local swing = open[player]
	if not swing or swing.id ~= payload.id then
		ctx:Fail("That bug has flown off. Swing again!")
	end
	open[player] = nil
	local t = payload.t
	local elapsed = ctx.Clock.Precise() - swing.startedAt
	if elapsed + Cfg.ClockGrace < t then
		ctx:Fail("That swing was too quick")
	end
	if elapsed > swing.path.total + Cfg.LateSeconds then
		ctx:Fail("That bug has flown off. Swing again!")
	end
	sync(player, s)
	local left = Cfg.FreeSwings - s.swings
	if not Logic.Hit(swing.path, t) then
		return { caught = false, first = false, left = left }
	end
	local def = Cfg.ById[swing.bug]
	local first = (s.log[def.id] or 0) == 0
	s.log[def.id] = (s.log[def.id] or 0) + 1
	s.jar[def.id] = math.min(Cfg.MaxJar, (s.jar[def.id] or 0) + 1)
	s.total += 1
	ctx:Dirty(player)
	ctx.Bus:Publish("BugCaught", player, { bug = def.id, rarity = def.rarity })
	return { caught = true, bug = def.id, rarity = def.rarity, first = first, left = left }
end

local function lure(player)
	local s = mustSection(player)
	Progression:Require(player, Cfg.Unlock)
	if not Apiary then
		ctx:Fail("You need an Apiary for honey lures")
	end
	if s.lure > 0 then
		ctx:Fail("Your honey lure is still working")
	end
	if not Apiary:SpendAnyHoney(player, Cfg.LureHoney) then
		ctx:Fail(string.format("You need %d honey for a lure", Cfg.LureHoney))
	end
	s.lure = Cfg.LureSwings
	ctx:Dirty(player, "lure")
	return { lure = s.lure }
end

local function sell(player, payload)
	local s = mustSection(player)
	local have = s.jar[payload.bug] or 0
	if have < payload.amount then
		ctx:Fail("You don't have that many bugs")
	end
	s.jar[payload.bug] = if have - payload.amount > 0 then have - payload.amount else nil
	ctx:Dirty(player, "jar")
	local seconds = Logic.Value(payload.bug) * payload.amount
	local granted = Rewards:Grant(player, { { kind = "coins", seconds = seconds, amount = 0 } }, Cfg.Source)
	local coins = 0
	for _, item in granted do
		if item.kind == "coins" then
			coins += item.amount
		end
	end
	return { coins = coins }
end

-- Lifecycle ----------------------------------------------------------------------------

function Bugs.Init(context)
	ctx = context
	Cfg = ctx.Config.Bugs
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")
	table.clear(open)

	ctx.Net:Handle("Bugs.Start", function(player)
		return start(player)
	end)
	ctx.Net:Handle("Bugs.Submit", submit)
	ctx.Net:Handle("Bugs.Lure", function(player)
		return lure(player)
	end)
	ctx.Net:Handle("Bugs.Sell", sell)
end

function Bugs.Start()
	Apiary = ctx:GetSystem("Apiary")
end

function Bugs.PlayerAdded(player)
	local s = ctx:Section(player)
	if not s then
		return
	end
	normalize(s)
	for id in s.jar do
		if not Cfg.ById[id] then
			s.jar[id] = nil
		end
	end
	sync(player, s)
	ctx:Dirty(player)
end

function Bugs.PlayerRemoving(player)
	open[player] = nil
end

return Bugs
