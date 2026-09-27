--[[
	DigSite (update 3.11 · Seasons & secrets): the Dig Site on every plot. Rules: Config/DigSite and
	Logic/DigSite. Opened from the sand pit's "Dig" prompt (Controllers/Interaction).

	Save section (profile.DigSite):
	  day, digs             -- free digs used today (UTC day)
	  shovels               -- shovels owned (one extra dig each)
	  n                     -- digs started ever (the dig number in the seed; also the dig id)
	  secret                -- PRIVATE: mixed into every dig's seed so the client can't work a layout out
	  open                  -- false, or the dig in progress: { id, left, tiles = { { t, hint?, kind?, fossil?, piece?, id?, amount?, duplicate? } } }
	                           (only what was dug up; the layout itself is never stored or sent)
	  pieces = { [fossilId]: { [pieceId]: true } }   -- fossil pieces owned
	  total                 -- digs finished ever

	Actions:
	  DigSite.Start {} -> { dig, left, tiles, digs, shovels, resumed }
	    Resumes the open dig for free; otherwise spends a free dig, else a shovel.
	  DigSite.Tap { dig, tile } -> { tile, find?, hint, left, done, rewards, missed? }
	    find = { kind, fossil?, piece?, duplicate?, complete?, id?, amount? }; hint = distance to the
	    nearest find still buried (0 = none). When the dig ends, missed = the tiles of finds left behind.

	Public API:
	  DigSite:AddShovels(player, n) -> number        new shovel count (Rewards kind "shovel", the Merchant)
	  DigSite:FossilsComplete(player) -> number      fossils with all four pieces (Codex Fossils milestones)

	Publishes FossilFound (player, { fossil, piece, complete }) for every new piece and
	DigFinished (player, { finds }) when a dig ends (the weekly goal dig_10).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.DigSite)

local DigSite = {
	Name = "DigSite",
	Dependencies = { "Progression", "Rewards" },
}

DigSite.Profile = {
	Version = 1,
	Private = { "secret" },
	Default = function()
		return {
			day = 0,
			digs = 0,
			shovels = 0,
			n = 0,
			secret = 0,
			open = false,
			pieces = {},
			total = 0,
		}
	end,
}

local ctx
local Cfg -- Config.DigSite
local Progression, Rewards

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
		s.digs = 0
		ctx:Dirty(player)
	end
end

local function layoutOf(player, s)
	return Logic.Layout(Logic.Seed(player.UserId, s.open.id, s.secret))
end

local function foundSet(open): { [number]: boolean }
	local found = {}
	for _, entry in open.tiles do
		if entry.kind then
			found[entry.t] = true
		end
	end
	return found
end

-- Public API ---------------------------------------------------------------------------

function DigSite:AddShovels(player, n: number): number
	local s = ctx:Section(player)
	if not s then
		return 0
	end
	if type(n) == "number" and n == n then
		s.shovels = math.clamp(s.shovels + math.max(0, math.floor(n)), 0, Cfg.MaxShovels)
		ctx:Dirty(player, "shovels")
	end
	return s.shovels
end

function DigSite:FossilsComplete(player): number
	local s = ctx:Section(player)
	return if s then Logic.Fossils(s.pieces) else 0
end

-- Actions ------------------------------------------------------------------------------

local function view(s, resumed: boolean)
	return {
		dig = s.open.id,
		left = s.open.left,
		tiles = s.open.tiles,
		digs = math.max(0, Cfg.FreeDigs - s.digs),
		shovels = s.shovels,
		resumed = resumed,
	}
end

local function start(player)
	local s = mustSection(player)
	Progression:Require(player, Cfg.Unlock)
	sync(player, s)
	if s.open then
		return view(s, true)
	end
	if s.digs < Cfg.FreeDigs then
		s.digs += 1
	elseif s.shovels > 0 then
		s.shovels -= 1
	else
		ctx:Fail("No digs left today. Use a shovel or come back tomorrow")
	end
	if s.secret == 0 then
		s.secret = ctx.Rng:Int(1, 2 ^ 30)
	end
	s.n += 1
	s.open = { id = s.n, left = Cfg.Taps, tiles = {} }
	ctx:Dirty(player)
	return view(s, false)
end

-- Pays one find; returns the find's client view and the granted rewards.
local function pay(player, s, find)
	local out: { [string]: any } = { kind = find.kind }
	local items = {}
	if find.kind == "piece" then
		out.fossil, out.piece = find.fossil, find.piece
		local have = s.pieces[find.fossil]
		if type(have) ~= "table" then
			have = {}
			s.pieces[find.fossil] = have
		end
		if have[find.piece] then
			out.duplicate = true
			out.amount = Cfg.DuplicateAmber
			table.insert(items, { kind = "amber", amount = Cfg.DuplicateAmber })
		else
			have[find.piece] = true
			out.complete = Logic.Complete(have)
			if out.complete then
				table.insert(items, { kind = "decor", id = Cfg.ById[find.fossil].decor, amount = 1 })
			end
			ctx.Bus:Publish("FossilFound", player, { fossil = find.fossil, piece = find.piece, complete = out.complete })
		end
		ctx:Dirty(player, "pieces")
	elseif find.kind == "amber" then
		out.amount = find.amount
		table.insert(items, { kind = "amber", amount = find.amount })
	elseif find.kind == "relic" then
		out.id = find.id
		table.insert(items, { kind = "decor", id = find.id, amount = 1 })
	else
		out.id = find.id
		table.insert(items, { kind = "egg", id = find.id, amount = 1 })
	end
	local granted = if #items > 0 then Rewards:Grant(player, items, Cfg.Source) else {}
	return out, granted
end

local function tap(player, payload)
	local s = mustSection(player)
	local open = s.open
	if not open or open.id ~= payload.dig then
		ctx:Fail("That dig is over. Start a new one!")
	end
	for _, entry in open.tiles do
		if entry.t == payload.tile then
			ctx:Fail("You already dug there")
		end
	end
	local finds = layoutOf(player, s)
	local hit
	for _, f in finds do
		if f.tile == payload.tile then
			hit = f
		end
	end
	local entry: { [string]: any } = { t = payload.tile }
	local find, rewards = nil, {}
	if hit then
		find, rewards = pay(player, s, hit)
		for k, v in find do
			entry[k] = v
		end
	end
	table.insert(open.tiles, entry)
	open.left -= 1
	local found = foundSet(open)
	local hint = Logic.Hint(finds, found, payload.tile)
	if not hit then
		entry.hint = hint
	end
	local done = open.left <= 0 or Logic.Hint(finds, found, 1) == 0
	local missed = nil
	if done then
		missed = {}
		local n = 0
		for _, f in finds do
			if found[f.tile] then
				n += 1
			else
				table.insert(missed, f.tile)
			end
		end
		s.open = false
		s.total += 1
		ctx.Bus:Publish("DigFinished", player, { finds = n })
	end
	ctx:Dirty(player)
	return {
		tile = payload.tile,
		find = find,
		hint = hint,
		left = math.max(0, open.left),
		done = done,
		rewards = rewards,
		missed = missed,
	}
end

-- Lifecycle ----------------------------------------------------------------------------

function DigSite.Init(context)
	ctx = context
	Cfg = ctx.Config.DigSite
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")

	ctx.Net:Handle("DigSite.Start", function(player)
		return start(player)
	end)
	ctx.Net:Handle("DigSite.Tap", tap)
end

function DigSite.PlayerAdded(player)
	local s = ctx:Section(player)
	if not s then
		return
	end
	-- Drops anything a damaged save left behind.
	if type(s.pieces) ~= "table" then
		s.pieces = {}
	end
	for id, have in s.pieces do
		if not Cfg.ById[id] or type(have) ~= "table" then
			s.pieces[id] = nil
		end
	end
	local open = s.open
	if open and (type(open) ~= "table" or type(open.tiles) ~= "table" or type(open.id) ~= "number" or open.id > s.n) then
		s.open = false
	end
	sync(player, s)
	ctx:Dirty(player)
end

return DigSite
