--[[
	EggHunt (update 1.4, Spring Bloom): painted eggs hidden around the Market Square while
	the event runs. Rules and spots live in Config/EggHunt; round maths in Logic/EggHunt.

	Save section (profile.EggHunt):
	  round = number        -- the round `found` belongs to
	  found = { spotIndex } -- eggs this player found in `round`
	  day   = number        -- UTC day of `finds`
	  finds = number        -- eggs found today (≤ Config.DailyFinds)
	  total = number        -- eggs found, all time

	Global state (global.EggHunt): { active, round, endsAt, spots = { spotIndex } }
	  active = false (and no spots) when the hunt's event is not running. Refreshed every 5 s.

	EggHunt.Find { spot } checks, in order: the event runs, the spot hides an egg this round,
	the player has not found it yet, the daily cap, and that the player's character stands
	within Config.Reach studs of it. It pays Config.Reward event tokens (+ RoundBonus for the
	last egg of the round) and publishes EggFound.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.EggHunt)

local EggHunt = {
	Name = "EggHunt",
	Dependencies = { "Currency" },
}

EggHunt.Profile = {
	Version = 1,
	Default = function()
		return { round = 0, found = {}, day = 0, finds = 0, total = 0 }
	end,
}

local ctx
local Config -- Config.EggHunt

local function running(): boolean
	return ctx.Config.Events.ActiveId(ctx:Now()) == Config.Event
end

local function publish()
	local g = ctx:Global()
	local active = running()
	local round, endsAt = Logic.Round(ctx:Now())
	if not active then
		round, endsAt = 0, 0
	end
	if g.active == active and g.round == round then
		return
	end
	g.active = active
	g.round = round
	g.endsAt = endsAt
	g.spots = if active then Logic.SpotsFor(round) else {}
	ctx:DirtyGlobal()
end

-- Resets the player's round and day counters when they are stale.
local function sync(player, s, round: number)
	if s.round ~= round then
		s.round = round
		s.found = {}
		ctx:Dirty(player, "round")
		ctx:Dirty(player, "found")
	end
	local today = ctx:Day()
	if s.day ~= today then
		s.day = today
		s.finds = 0
		ctx:Dirty(player, "day")
		ctx:Dirty(player, "finds")
	end
end

local function characterPosition(player)
	local ok, position = pcall(function()
		return player.Character.HumanoidRootPart.Position
	end)
	return if ok then position else nil
end

local function find(player, spot: number)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	if not running() then
		ctx:Fail("The egg hunt isn't on right now")
	end
	publish()
	local g = ctx:Global()
	if not table.find(g.spots, spot) then
		ctx:Fail("There's no egg there right now. New eggs hide every 20 minutes!")
	end
	sync(player, s, g.round)
	if table.find(s.found, spot) then
		ctx:Fail("You already found that egg")
	end
	if s.finds >= Config.DailyFinds then
		ctx:Fail("You've found all the eggs you can today. Come back tomorrow!")
	end
	local position = characterPosition(player)
	if not position or Logic.Distance(position, Config.Spots[spot]) > Config.Reach then
		ctx:Fail("Get closer to the egg")
	end

	table.insert(s.found, spot)
	s.finds += 1
	s.total += 1
	ctx:Dirty(player)
	local tokens = Config.Reward
	local complete = #s.found >= #g.spots
	if complete then
		tokens += Config.RoundBonus
	end
	ctx:GetSystem("Currency"):Add(player, "token." .. Config.Event, tokens, "event_egghunt")
	ctx.Bus:Publish("EggFound", player, { spot = spot, round = g.round, complete = complete })
	return { tokens = tokens, found = #s.found, left = #g.spots - #s.found, complete = complete }
end

function EggHunt.Init(context)
	ctx = context
	Config = ctx.Config.EggHunt
	ctx.Net:Handle("EggHunt.Find", function(player, payload)
		return find(player, payload.spot)
	end)
	local g = ctx:Global()
	g.active, g.round, g.endsAt, g.spots = false, -1, 0, {}
	publish()
end

function EggHunt.Start()
	ctx:Every(5, publish)
end

function EggHunt.PlayerAdded(player, _info)
	local s = ctx:Section(player)
	local g = ctx:Global()
	if g.active then
		sync(player, s, g.round)
	end
end

return EggHunt
