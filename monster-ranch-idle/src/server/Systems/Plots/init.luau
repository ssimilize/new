--[[
	Plots (S5): the six public ranch plots on a server and what other players see on them.

	Global state (global.Plots): always 6 entries (Config.World plots); an empty plot has userId = 0.
	  { userId, name, level, likes,
	    pens = { { theme, decor = { decorId }, monsters = { { id, appearance } }, capacity, jarTier } },
	    statues = { Appearance },
	    incubators = { { type, endsAt } },
	    garden = { tier, plots = { { flavor, readyAt } } } | false }   -- glow-up R (Ranch:PublicGarden)

	A player gets the lowest free plot when they become ready (bus PlayerReady) and frees it when
	they leave. Plot contents are rebuilt from other systems' public APIs:
	  Progression:GetLevel · Social:GetLikes · Ranch:PublicPens + Monsters:Appearance ·
	  HallOfFame:Statues · Eggs:PublicSlots   (everything except Monsters/Progression is optional)
	Rebuilds are triggered by PlotChanged, PenChanged, MonsterChanged (visible fields only),
	MonsterCreated, MonsterRemoved, LevelUp, Retired, EggHatched and EggAdded, and throttled to
	at most one per Config.Social.PlotRefreshSeconds per player (a late change is never lost:
	a trailing rebuild is scheduled).

	On the Trading Hub place (Config.TradingHub.Mode, update 3.0) nobody gets a plot.

	Public API:
	  Plots:GetPlot(player) -> 1..6 | nil   (nil when the server has more players than plots)
	  Plots:Refresh(player)                 -- throttled rebuild
	  Plots:Public(player) -> PublicPlot    -- glow-up Y: built now (Visits snapshots)
]]

local Plots = {
	Name = "Plots",
	Dependencies = { "Monsters", "Progression" },
	OptionalDependencies = { "Social", "Ranch", "HallOfFame", "Eggs" },
}

local PLOT_COUNT = 6

local ctx
local Config
local Monsters, Progression

local plotOf = {} -- [player] = index
local owners = {} -- [index] = player
local lastBuiltAt = {} -- [player] = unix seconds
local pending = {} -- [player] = true while a trailing rebuild is scheduled

-- Monster fields that change how a monster looks on a plot.
local VISIBLE_FIELDS = {
	line = true,
	stage = true,
	form = true,
	rarity = true,
	variant = true,
	muts = true,
	weight = true,
	name = true,
	lv = true,
	stars = true,
	loc = true,
	pen = true,
	busy = true,
	acc = true, -- worn accessories are drawn on the monster
}

local function emptyPlot()
	return { userId = 0, name = "", level = 0, likes = 0, pens = {}, statues = {}, incubators = {}, garden = false }
end

-- Calls an optional system's method; returns nil if the system is absent or the call fails.
local function optional(systemName: string, method: string, ...: any)
	local system = ctx:GetSystem(systemName)
	if not system or type(system[method]) ~= "function" then
		return nil
	end
	local ok, result = pcall(system[method], system, ...)
	if not ok then
		warn(string.format("[Plots] %s:%s failed: %s", systemName, method, tostring(result)))
		return nil
	end
	return result
end

local function buildPens(player)
	local pens = {}
	for _, pen in optional("Ranch", "PublicPens", player) or {} do
		local monsters = {}
		for _, id in pen.monsters or {} do
			local appearance = Monsters:Appearance(player, id)
			if appearance then
				table.insert(monsters, { id = id, appearance = appearance })
			end
		end
		table.insert(pens, {
			theme = pen.theme or false,
			decor = table.clone(pen.decor or {}),
			monsters = monsters,
			-- Glow-up R: upgrades are drawn on the pen (Controllers/Pens).
			capacity = tonumber(pen.capacity) or Config.Economy.Pens.startCapacity,
			jarTier = tonumber(pen.jarTier) or 1,
		})
	end
	return pens
end

local function buildPlot(player)
	local statues = {}
	for i, appearance in optional("HallOfFame", "Statues", player) or {} do
		if i > Config.Social.PlotMaxStatues then
			break
		end
		table.insert(statues, appearance)
	end
	local incubators = {}
	for _, slot in optional("Eggs", "PublicSlots", player) or {} do
		table.insert(incubators, { type = slot.type, endsAt = slot.endsAt or 0 })
	end
	return {
		userId = player.UserId,
		name = player.DisplayName or player.Name,
		level = Progression:GetLevel(player),
		likes = optional("Social", "GetLikes", player) or 0,
		pens = buildPens(player),
		statues = statues,
		incubators = incubators,
		garden = optional("Ranch", "PublicGarden", player) or false, -- glow-up R
	}
end

local function rebuild(player)
	local index = plotOf[player]
	if not index then
		return
	end
	lastBuiltAt[player] = ctx:Now()
	ctx:Global()[index] = buildPlot(player)
	ctx:DirtyGlobal(index)
end

local function assign(player)
	if plotOf[player] then
		return
	end
	-- The Trading Hub place (3.0) has no ranch plots.
	if Config.TradingHub.Mode(ctx.Services.PlaceId, ctx.Services.PlaceMode) == "hub" then
		return
	end
	for index = 1, PLOT_COUNT do
		if not owners[index] then
			owners[index] = player
			plotOf[player] = index
			rebuild(player)
			return
		end
	end
	warn(string.format("[Plots] no free plot for %s", tostring(player.Name)))
end

-- Public API ------------------------------------------------------------------------------

function Plots:GetPlot(player): number?
	return plotOf[player]
end

function Plots:Refresh(player)
	if not plotOf[player] or pending[player] then
		return
	end
	local wait = (lastBuiltAt[player] or -math.huge) + Config.Social.PlotRefreshSeconds - ctx:Now()
	if wait <= 0 then
		rebuild(player)
		return
	end
	pending[player] = true
	ctx:After(wait, function()
		pending[player] = nil
		rebuild(player)
	end)
end

-- Glow-up Y: a fresh public plot record for any ready player (the ranch snapshot), built from the
-- same public APIs as global.Plots; works on the hub place and while the player is leaving.
function Plots:Public(player)
	return buildPlot(player)
end

-- Lifecycle ---------------------------------------------------------------------------------

function Plots.Init(context)
	ctx = context
	Config = ctx.Config
	Monsters = ctx:GetSystem("Monsters")
	Progression = ctx:GetSystem("Progression")
	-- Fresh module state (tests boot many kernels in one process).
	table.clear(plotOf)
	table.clear(owners)
	table.clear(lastBuiltAt)
	table.clear(pending)

	local global = ctx:Global()
	for index = 1, PLOT_COUNT do
		global[index] = emptyPlot()
	end
	ctx:DirtyGlobal()

	ctx.Bus:Subscribe("PlayerReady", function(player)
		assign(player)
	end)

	local function refresh(player)
		if player then
			Plots:Refresh(player)
		end
	end
	for _, topic in { "PlotChanged", "PenChanged", "MonsterCreated", "MonsterRemoved", "LevelUp", "Retired", "EggHatched", "EggAdded" } do
		ctx.Bus:Subscribe(topic, refresh)
	end
	ctx.Bus:Subscribe("MonsterChanged", function(player, detail)
		if detail.fields == nil then
			refresh(player)
			return
		end
		for _, field in detail.fields do
			if VISIBLE_FIELDS[field] then
				refresh(player)
				return
			end
		end
	end)
end

function Plots.PlayerRemoving(player)
	local index = plotOf[player]
	plotOf[player] = nil
	lastBuiltAt[player] = nil
	pending[player] = nil
	if index then
		owners[index] = nil
		ctx:Global()[index] = emptyPlot()
		ctx:DirtyGlobal(index)
	end
end

return Plots
