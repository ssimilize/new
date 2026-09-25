--[[
	Leaderboards (S5): weekly boards per server and global, and nameplate titles for last
	week's global winners (design §11). Boards are listed in Config.Leaderboards.

	Values come from other systems' public APIs (all optional dependencies):
	  heaviest    heaviest monster owned (Monsters:All), kg × WeightScale, label = its name
	  codex       forms discovered (Monsters:CodexCount)
	  stampede    Stampede damage dealt this week (BossDamage topic, saved here)
	  halloffame  monsters retired (HallOfFame:RetiredCount)
	  stage       highest global stage index cleared (Expeditions:Cleared + Regions.GlobalIndex)
	  racing      Racing Cup points this week (Racing:CupPoints, 3.0)

	Save section (profile.Leaderboards): { week, stampede }  -- stampede resets each week

	Global state (global.Leaderboards):
	  week, endsAt
	  server    = { [boardId] = { { userId, name, value, label? } } }  -- everyone here, live
	  global    = { [boardId] = { { userId, name, value } } }          -- this week, all servers
	  champions = { [boardId] = { userId, name } | false }             -- last week's #1
	  globalAt  = unix time of the last successful global read (0 = never)

	Global IO goes through ctx.Services.Leaderboards (OrderedDataStores keyed per board and
	week). Values are submitted when they change, at most every GlobalRefresh seconds, and
	when a player leaves. Reads run in ctx.Services.Spawn so they never block the kernel.

	Public API:
	  Leaderboards:Value(player, boardId) -> (value, label?)
	  Leaderboards:Titles(userId) -> { boardId }   -- boards this user won last week
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)

local Leaderboards = {
	Name = "Leaderboards",
	Dependencies = {},
	OptionalDependencies = { "Monsters", "Boss", "HallOfFame", "Expeditions", "Racing" },
}

Leaderboards.Profile = {
	Version = 1,
	Default = function()
		return { week = 0, stampede = 0 }
	end,
}

local ctx
local Config
local Boards

local submitted = {} -- [player] = { [boardId] = value } submitted for the current week
local busy = { global = false, champions = false }

-- Helpers ---------------------------------------------------------------------------------

local function displayName(player): string
	return player.DisplayName or player.Name
end

local function currentWeek(): number
	return Boards.Week(ctx:Now())
end

local function section(player)
	local s = ctx:Section(player)
	if s and s.week ~= currentWeek() then
		s.week = currentWeek()
		s.stampede = 0
		ctx:Dirty(player)
	end
	return s
end

local function heaviest(player): (number, string?)
	local Monsters = ctx:GetSystem("Monsters")
	if not Monsters then
		return 0, nil
	end
	local best, name = 0, nil
	for _, m in Monsters:All(player) or {} do
		local w = tonumber(m.weight) or 0
		if w > best then
			best = w
			name = Formulas.DisplayName(m)
		end
	end
	return math.floor(best * Boards.WeightScale + 0.5), name
end

local function highestStage(player): number
	local Expeditions = ctx:GetSystem("Expeditions")
	if not Expeditions then
		return 0
	end
	local best = 0
	for _, region in Config.Regions.List do
		local cleared = Expeditions:Cleared(player, region.id)
		if cleared > 0 then
			best = math.max(best, Config.Regions.GlobalIndex(region.id, cleared))
		end
	end
	return best
end

local VALUES = {
	heaviest = heaviest,
	codex = function(player)
		local Monsters = ctx:GetSystem("Monsters")
		return if Monsters then Monsters:CodexCount(player) else 0
	end,
	stampede = function(player)
		local s = section(player)
		return if s then math.floor(s.stampede) else 0
	end,
	halloffame = function(player)
		local HallOfFame = ctx:GetSystem("HallOfFame")
		return if HallOfFame then HallOfFame:RetiredCount(player) else 0
	end,
	stage = highestStage,
	racing = function(player)
		local Racing = ctx:GetSystem("Racing")
		return if Racing then Racing:CupPoints(player) else 0
	end,
}

local function global()
	return ctx:Global()
end

local function sortRows(rows)
	table.sort(rows, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.userId < b.userId
	end)
	while #rows > Boards.Rows do
		table.remove(rows)
	end
	return rows
end

-- Week rollover: clears this week's lists and re-reads last week's winners.
local function checkWeek(): boolean
	local G = global()
	local week = currentWeek()
	if G.week == week then
		return false
	end
	G.week = week
	G.endsAt = Boards.WeekEndsAt(week)
	for _, board in Boards.Boards do
		G.global[board.id] = {}
	end
	G.globalAt = 0
	table.clear(submitted)
	ctx:DirtyGlobal()
	return true
end

-- Per-server boards ---------------------------------------------------------------------

local function refreshServer()
	local G = global()
	for _, board in Boards.Boards do
		local rows = {}
		for _, player in ctx:Players() do
			local value, label = Leaderboards:Value(player, board.id)
			if value > 0 then
				table.insert(rows, { userId = player.UserId, name = displayName(player), value = value, label = label or false })
			end
		end
		G.server[board.id] = sortRows(rows)
	end
	ctx:DirtyGlobal("server")
end

-- Global boards ---------------------------------------------------------------------------

local function submit(player)
	local service = ctx.Services.Leaderboards
	if not service then
		return
	end
	local week = currentWeek()
	submitted[player] = submitted[player] or {}
	local sent = submitted[player]
	for _, board in Boards.Boards do
		local value = Leaderboards:Value(player, board.id)
		if value > 0 and sent[board.id] ~= value then
			if service.Submit(Boards.Key(board.id, week), player.UserId, value) then
				sent[board.id] = value
			end
		end
	end
end

local function nameFor(userId: number): string
	local online = ctx:PlayerByUserId(userId)
	if online then
		return displayName(online)
	end
	local name = ctx.Services.Players.NameOf and ctx.Services.Players.NameOf(userId)
	return if type(name) == "string" then name else "Rancher"
end

local function readTop(key: string, count: number)
	local list = ctx.Services.Leaderboards.Top(key, count)
	if not list then
		return nil
	end
	local rows = {}
	for _, entry in list do
		table.insert(rows, { userId = entry.userId, name = nameFor(entry.userId), value = entry.value })
	end
	return rows
end

local function refreshGlobal()
	if busy.global or not ctx.Services.Leaderboards then
		return
	end
	busy.global = true
	ctx.Services.Spawn(function()
		for _, player in ctx:Players() do
			submit(player)
		end
		local week = currentWeek()
		local G = global()
		local okAll = true
		for _, board in Boards.Boards do
			local rows = readTop(Boards.Key(board.id, week), Boards.Rows)
			if rows and G.week == week then
				G.global[board.id] = rows
			else
				okAll = false
			end
		end
		if okAll then
			G.globalAt = ctx:Now()
		end
		ctx:DirtyGlobal("global")
		ctx:DirtyGlobal("globalAt")
		busy.global = false
	end)
end

local function refreshChampions()
	if busy.champions or not ctx.Services.Leaderboards then
		return
	end
	busy.champions = true
	ctx.Services.Spawn(function()
		local last = currentWeek() - 1
		local G = global()
		for _, board in Boards.Boards do
			local rows = readTop(Boards.Key(board.id, last), 1)
			if rows then
				local top = rows[1]
				G.champions[board.id] = if top then { userId = top.userId, name = top.name } else false
			end
		end
		ctx:DirtyGlobal("champions")
		busy.champions = false
	end)
end

-- Public API --------------------------------------------------------------------------------

function Leaderboards:Value(player, boardId: string): (number, string?)
	local fn = VALUES[boardId]
	if not fn then
		return 0, nil
	end
	local value, label = fn(player)
	return math.max(0, math.floor(tonumber(value) or 0)), label
end

function Leaderboards:Titles(userId: number): { string }
	local list = {}
	for _, board in Boards.Boards do
		local champ = global().champions[board.id]
		if type(champ) == "table" and champ.userId == userId then
			table.insert(list, board.id)
		end
	end
	return list
end

-- Lifecycle ---------------------------------------------------------------------------------

function Leaderboards.Init(context)
	ctx = context
	Config = ctx.Config
	Boards = Config.Leaderboards

	local G = global()
	G.week = -1
	G.endsAt = 0
	G.server, G.global, G.champions = {}, {}, {}
	for _, board in Boards.Boards do
		G.server[board.id] = {}
		G.global[board.id] = {}
		G.champions[board.id] = false
	end
	G.globalAt = 0
	checkWeek()

	ctx.Bus:Subscribe("BossDamage", function(player, detail)
		local s = section(player)
		local damage = tonumber(detail and detail.damage) or 0
		if s and damage > 0 then
			s.stampede += math.floor(damage)
			ctx:Dirty(player, "stampede")
		end
	end)
end

function Leaderboards.Start()
	ctx:Every(Boards.ServerRefresh, function()
		if checkWeek() then
			refreshChampions()
			refreshGlobal()
		end
		refreshServer()
	end)
	ctx:Every(Boards.GlobalRefresh, refreshGlobal)
	ctx:Every(Boards.ChampionRefresh, refreshChampions)
	refreshChampions()
	refreshGlobal()
end

function Leaderboards.PlayerAdded(player)
	section(player)
	refreshServer()
end

function Leaderboards.PlayerRemoving(player)
	-- Read the values now, while every section is still loaded; the writes can yield.
	local values = {}
	for _, board in Boards.Boards do
		values[board.id] = Leaderboards:Value(player, board.id)
	end
	local sent = submitted[player] or {}
	submitted[player] = nil
	local service = ctx.Services.Leaderboards
	if not service then
		return
	end
	local week = currentWeek()
	ctx.Services.Spawn(function()
		for boardId, value in values do
			if value > 0 and sent[boardId] ~= value then
				service.Submit(Boards.Key(boardId, week), player.UserId, value)
			end
		end
	end)
end

return Leaderboards
