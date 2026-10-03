--[[
	Strays (update 3.13 · Wild things): Stray Monsters. While the owner is online, a stray of an
	existing line wanders onto their plot every Config.Strays.Interval seconds (slots on the server
	clock with a per-player offset, like Systems/Tourists) and stays Config.Strays.Stay seconds.
	Rules: Logic/Strays; tuning: Config/Strays. The client walks it on the plot
	(Controllers/Strays); its "Befriend" prompt opens the minigame (UI/Screens/Strays).

	Each stray (line, rarity, hidden mood per round) is seeded per (userId, slot) with the save's
	private secret, so the client can neither reroll nor peek; the night odds (Logic/WeatherRoll
	.Phase at its arrival) roll the rarity better. A slot missed while away is simply gone: there
	are no offline strays (a stray whose stay is still on when the owner joins is there).

	Save section (profile.Strays), version 1:
	  secret                 PRIVATE: mixed into every stray's seed
	  tried                  the last slot whose stray was tried (one attempt per stray; -1 = none)
	  seen                   the last slot whose stray was counted as met (-1 = none)
	  day, adopted           strays adopted on UTC `day` (Config.Strays.DailyCap a day)
	  met = { [lineId]: n }      strays met per line (the Codex Stray Log)
	  friends = { [lineId]: n }  strays befriended per line
	  total                  strays befriended ever
	Session (session.Strays): { unlocked, nextAt, left, stray = false | { slot, line, rarity,
	  arriveAt, leavesAt, tried } }   never the mood

	Actions:
	  Strays.Start { slot } -> { slot, line, rarity, favourite, hints = { string } }
	    Uses the stray's one attempt (asking again while it is open returns the same hints).
	    Refuses: locked, no such stray here now, already tried, daily cap, barn full.
	  Strays.Submit { slot, choices = { "wait" | flavourId } x Rounds } -> { befriended, correct,
	    answers = { "wait" | flavourId }, id?, line, rarity, gene? }
	    One-shot. Each treat costs Config.Strays.TreatCost food of its flavour (all or nothing,
	    refused before anything is used when short). Need right answers befriend: the stray joins
	    as an Adult of its line and rarity (Monsters:Create, source "stray") with one stat gene
	    raised a grade (Logic/Strays.GeneBonus); else it runs off.

	Public API: Strays:Current(player) -> { slot, line, rarity, arriveAt, leavesAt }?
	Bus: publishes StrayBefriended (player, { line, rarity }) (the weekly goal strays_3).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Strays)
local WeatherRoll = require(Shared.Logic.WeatherRoll)
local Rng = require(Shared.Logic.Rng)
local Genetics = require(Shared.Logic.Genetics)

local Strays = {
	Name = "Strays",
	Dependencies = { "Progression", "Currency", "Monsters" },
}

Strays.Profile = {
	Version = 1,
	Private = { "secret" },
	Default = function()
		return { secret = 0, tried = -1, seen = -1, day = 0, adopted = 0, met = {}, friends = {}, total = 0 }
	end,
}

local TICK = 5

local ctx
local Cfg
local Progression, Currency, Monsters
local open = {} -- [player] = { slot, line, rarity, mood }

local function mustSection(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

-- Dirties the named keys only: dirtying the whole section would replicate the private secret.
local function dirty(player, ...: string)
	for _, key in { ... } do
		ctx:Dirty(player, key)
	end
end

local function unlocked(player): boolean
	return Progression:IsUnlocked(player, Cfg.Unlock)
end

local function ensureSecret(s)
	if s.secret == 0 then
		s.secret = ctx.Rng:Int(1, 2 ^ 30)
	end
end

local function syncDay(player, s)
	local day = ctx:Day()
	if s.day ~= day then
		s.day = day
		s.adopted = 0
		dirty(player, "day", "adopted")
	end
end

-- The stray of `slot` for this player, with its mood (server only).
local function strayOf(player, s, slot: number)
	ensureSecret(s)
	local pool = Logic.Pool(function(key)
		return Progression:IsUnlocked(player, key)
	end)
	local night = WeatherRoll.Phase(Logic.ArriveAt(player.UserId, slot))
	local stray = Logic.Roll(Logic.Seed(player.UserId, slot, s.secret), pool, night)
	if stray then
		stray.slot = slot
	end
	return stray
end

-- The stray on the plot now (nil when locked or none).
local function current(player, s)
	if not unlocked(player) then
		return nil
	end
	local slot = Logic.Slot(player.UserId, ctx:Now())
	if ctx:Now() >= Logic.LeavesAt(player.UserId, slot) then
		return nil
	end
	return strayOf(player, s, slot)
end

local function refresh(player, announce: boolean)
	local s, sess = ctx:Section(player), ctx:Session(player)
	if not s or not sess then
		return
	end
	syncDay(player, s)
	local stray = current(player, s)
	local view = false
	if stray then
		if s.seen ~= stray.slot then
			s.seen = stray.slot
			s.met[stray.line] = (s.met[stray.line] or 0) + 1
			dirty(player, "seen", "met")
			if announce then
				ctx:Notify(player, string.format("A stray %s is wandering near your gate!", Logic.Name(stray.line)), "info")
			end
		end
		view = {
			slot = stray.slot,
			line = stray.line,
			rarity = stray.rarity,
			arriveAt = Logic.ArriveAt(player.UserId, stray.slot),
			leavesAt = Logic.LeavesAt(player.UserId, stray.slot),
			tried = s.tried == stray.slot,
		}
	end
	local isOpen = unlocked(player)
	local nextAt = Logic.ArriveAt(player.UserId, Logic.Slot(player.UserId, ctx:Now()) + 1)
	local left = math.max(0, Cfg.DailyCap - s.adopted)
	local old = sess.stray
	local same = (old == false and view == false)
		or (type(old) == "table" and type(view) == "table" and old.slot == view.slot and old.tried == view.tried and old.line == view.line)
	if not same or sess.unlocked ~= isOpen or sess.nextAt ~= nextAt or sess.left ~= left then
		sess.stray, sess.unlocked, sess.nextAt, sess.left = view, isOpen, nextAt, left
		ctx:DirtySession(player)
	end
end

-- Public API ------------------------------------------------------------------------------------

function Strays:Current(player)
	local s = ctx:Section(player)
	local stray = s and current(player, s)
	if not stray then
		return nil
	end
	return {
		slot = stray.slot,
		line = stray.line,
		rarity = stray.rarity,
		arriveAt = Logic.ArriveAt(player.UserId, stray.slot),
		leavesAt = Logic.LeavesAt(player.UserId, stray.slot),
	}
end

-- Actions -----------------------------------------------------------------------------------------

local function checkRoom(player, s)
	syncDay(player, s)
	if s.adopted >= Cfg.DailyCap then
		ctx:Fail(string.format("You've befriended %d strays today. More tomorrow!", Cfg.DailyCap))
	end
	if Monsters:Count(player) >= Monsters:Capacity(player) then
		ctx:Fail("Your barn is full")
	end
end

local function hintsOf(run)
	local hints = {}
	for i, want in run.mood do
		hints[i] = Logic.Hint(want)
	end
	return {
		slot = run.slot,
		line = run.line,
		rarity = run.rarity,
		favourite = Logic.Favourite(run.line),
		hints = hints,
	}
end

local function start(player, payload)
	local s = mustSection(player)
	Progression:Require(player, Cfg.Unlock)
	local run = open[player]
	if run and run.slot == payload.slot then
		return hintsOf(run)
	end
	local stray = current(player, s)
	if not stray or stray.slot ~= payload.slot then
		ctx:Fail("That stray has wandered off")
	end
	if s.tried == stray.slot then
		ctx:Fail("You already tried to befriend this stray")
	end
	checkRoom(player, s)
	s.tried = stray.slot
	dirty(player, "tried")
	open[player] = { slot = stray.slot, line = stray.line, rarity = stray.rarity, mood = stray.mood }
	refresh(player, false)
	return hintsOf(open[player])
end

local function submit(player, payload)
	local s = mustSection(player)
	local run = open[player]
	if not run or run.slot ~= payload.slot then
		ctx:Fail("That stray has wandered off")
	end
	for _, c in payload.choices do
		if c ~= "wait" and not ctx.Config.Food.ById[c] then
			ctx:Fail("That treat doesn't exist")
		end
	end
	local correct = Logic.Score(run.mood, payload.choices)
	local friend = Logic.Befriended(correct)
	if friend then
		checkRoom(player, s)
	end
	local cost = Logic.Cost(payload.choices)
	if next(cost) ~= nil then
		Currency:Charge(player, cost, "stray")
	end
	open[player] = nil
	local out = {
		befriended = friend,
		correct = correct,
		answers = table.clone(run.mood),
		line = run.line,
		rarity = run.rarity,
	}
	if friend then
		local rng = Rng.new(Rng.seed("stray-adopt", player.UserId, run.slot, s.secret))
		local genes, stat = Logic.GeneBonus(Genetics.Roll(rng), rng)
		local record, err = Monsters:Create(player, { line = run.line, rarity = run.rarity, stage = 3, genes = genes }, "stray")
		if not record then
			ctx:Fail(err or "Your barn is full")
		end
		s.adopted += 1
		s.total += 1
		s.friends[run.line] = (s.friends[run.line] or 0) + 1
		dirty(player, "adopted", "total", "friends")
		out.id = record.id
		out.gene = stat
		ctx.Bus:Publish("StrayBefriended", player, { line = run.line, rarity = run.rarity })
	end
	refresh(player, false)
	return out
end

-- Lifecycle ---------------------------------------------------------------------------------------

function Strays.Init(context)
	ctx = context
	Cfg = ctx.Config.Strays
	Progression = ctx:GetSystem("Progression")
	Currency = ctx:GetSystem("Currency")
	Monsters = ctx:GetSystem("Monsters")
	open = {}

	ctx.Net:Handle("Strays.Start", start)
	ctx.Net:Handle("Strays.Submit", submit)

	ctx.Bus:Subscribe("LevelUp", function(player)
		if player and ctx:Section(player) then
			refresh(player, true)
		end
	end)

	ctx:Every(TICK, function()
		for _, player in ctx:Players() do
			refresh(player, true)
		end
	end)
end

function Strays.PlayerAdded(player)
	local s = ctx:Section(player)
	if not s then
		return
	end
	-- Drops anything a damaged save left behind.
	for _, key in { "met", "friends" } do
		if type(s[key]) ~= "table" then
			s[key] = {}
		end
		for line, n in s[key] do
			if not ctx.Config.Species.ById[line] or type(n) ~= "number" then
				s[key][line] = nil
			end
		end
	end
	s.tried = tonumber(s.tried) or -1
	s.seen = tonumber(s.seen) or -1
	s.adopted = tonumber(s.adopted) or 0
	s.total = tonumber(s.total) or 0
	ensureSecret(s)
	dirty(player, "tried", "seen", "day", "adopted", "met", "friends", "total")
	refresh(player, false)
end

function Strays.PlayerRemoving(player)
	open[player] = nil
end

return Strays
