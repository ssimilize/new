--[[
	Seasons (update 3.11 · Seasons & secrets): Ranch Seasons. The season itself is a pure function
	of time (Logic/Seasons.At, one per Leaderboards week), so every server and client agrees and
	nothing about it is saved except the last season each player saw. The seasonal rules live
	where they apply: Logic/Fishing (seasonal fish), Systems/Kitchen (seasonal recipes),
	Logic/Tourists (the favoured Appeal category), Systems/Shop (seasonal decor), Config/Weekly
	(season_fish_3). This system owns the arrival message and the Feed Garden bonus.

	Save section (profile.Seasons): { last = seasonId | "", carry = number }
	  last   the season this player last saw
	  carry  the fraction of a food the garden bonus still owes (so +25% of 5 pays 1, 1, 1, 2)

	Feed Garden: harvests of the season's flavour (Config.Seasons flavor) give GardenBonus more,
	through Ranch:RegisterHarvestHook (Ranch is optional: looked up in Start).

	Public API:
	  Seasons:Current() -> { id, index, startsAt, endsAt }

	Bus: publishes SeasonChanged (player, { season }) on join when the stored season differs and at
	the turnover for players online; WelcomeItem { kind = "season" } on a join after a turnover
	(never on a first join). Online players get a toast at the turnover.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Seasons)

local Seasons = {
	Name = "Seasons",
	Dependencies = {},
	OptionalDependencies = { "Ranch" },
}

Seasons.Profile = {
	Version = 1,
	Default = function()
		return { last = "", carry = 0 }
	end,
}

local ctx
local Rules -- Config.Seasons
local current = "" -- the season the last tick saw

-- The whole food a harvest of `flavor` earns on top of its yield; the fraction carries over.
local function gardenBonus(player, flavor: string): number
	local s = ctx:Section(player)
	if not s then
		return 0
	end
	local exact = Logic.GardenBonus(flavor, Logic.At(ctx:Now()).id, ctx.Config.Economy.Garden.yield)
	if exact <= 0 then
		return 0
	end
	local total = exact + (tonumber(s.carry) or 0)
	local whole = math.floor(total + 1e-9)
	s.carry = math.max(0, total - whole)
	ctx:Dirty(player, "carry")
	return whole
end

local function arrive(player, season: string, online: boolean)
	if online then
		ctx:Notify(player, Logic.ArriveText(season), "info")
	end
	ctx.Bus:Publish("SeasonChanged", player, { season = season })
end

local function tick()
	local now = Logic.At(ctx:Now()).id
	if now == current then
		return
	end
	current = now
	for _, player in ctx:Players() do
		local s = ctx:Section(player)
		if s and s.last ~= now then
			s.last = now
			ctx:Dirty(player, "last")
			arrive(player, now, true)
		end
	end
end

-- Public API ---------------------------------------------------------------------------

function Seasons:Current()
	return Logic.At(ctx:Now())
end

-- Lifecycle ----------------------------------------------------------------------------

function Seasons.Init(context)
	ctx = context
	Rules = ctx.Config.Seasons
	current = Logic.At(ctx:Now()).id
end

function Seasons.Start()
	local Ranch = ctx:GetSystem("Ranch")
	if Ranch and Ranch.RegisterHarvestHook then
		Ranch:RegisterHarvestHook("seasons", gardenBonus)
	end
	ctx:Every(Rules.TickSeconds, tick)
end

function Seasons.PlayerAdded(player)
	local s = ctx:Section(player)
	if not s then
		return
	end
	if type(s.last) ~= "string" then
		s.last = ""
	end
	if type(s.carry) ~= "number" or s.carry ~= s.carry then
		s.carry = 0
	end
	local now = Logic.At(ctx:Now()).id
	if s.last == now then
		return
	end
	local seen = s.last ~= "" and Rules.ById[s.last] ~= nil
	s.last = now
	ctx:Dirty(player, "last")
	if seen then
		ctx.Bus:Publish("WelcomeItem", player, { kind = "season", text = Logic.ArriveText(now) })
	end
	arrive(player, now, false)
end

return Seasons
