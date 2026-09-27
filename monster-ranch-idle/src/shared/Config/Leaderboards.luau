--[[
	Weekly leaderboards (design §11). Each board has a per-server view (live, everyone on
	this server) and a global view (every server, stored in OrderedDataStores keyed by
	week). The week's #1 on each global board gets that board's nameplate title for the
	whole following week.

	period: "week" (the default) or "season" (3.8: the "arena" board runs for a whole arena
	season, Logic/Arena.SeasonAt, keyed arena_s<N>, and has no weekly champion or title).
	Leaderboards.Weekly lists the weekly boards only (the Leaderboards screen and hub board).

	short: the tab label (the full name is shown on the board).
	format: how values are shown. Values are stored as whole numbers; weights are stored in
	hundredths of a kilogram (see WeightScale).
]]

local Leaderboards = {}

Leaderboards.Boards = {
	{ id = "heaviest", name = "Heaviest Monster", short = "Heaviest", title = "Heavyweight Champ", format = "weight", color = "#F2A93B" },
	{ id = "codex", name = "Codex", title = "Master Collector", format = "count", unit = "forms", color = "#4FB6F2" },
	{ id = "stampede", name = "Stampede Damage", short = "Stampede", title = "Stampede Hero", format = "short", color = "#E5484D" },
	{ id = "halloffame", name = "Hall of Fame", title = "Living Legend", format = "count", unit = "statues", color = "#8B6AD8" },
	{ id = "stage", name = "Highest Stage", short = "Stage", title = "Trailblazer", format = "stage", color = "#43B649" },
	-- Update 3.0: Racing Cup points from this week's races (Config.Racing.CupPoints).
	{ id = "racing", name = "Racing Cup", short = "Racing", title = "Speed Demon", format = "count", unit = "pts", color = "#FF8A3D" },
	-- Update 3.3: Mythic Ladder points earned this week (Config.Mastery; Mastery:WeekPoints).
	{ id = "mastery", name = "Mastery", title = "Grand Master", format = "count", unit = "pts", color = "#E8436F" },
	-- Glow-up Y: likes received this week (Visits:WeekLikes); last week's #1 stands on the hub stage.
	{
		id = "ranchlikes",
		name = "Ranch of the Week",
		short = "Likes",
		title = "Ranch of the Week",
		format = "count",
		unit = "likes",
		color = "#FF6FA8",
	},
	-- Update 3.9: Expedition Bounties defeated this week (Expeditions:BountyCount).
	{
		id = "bounties",
		name = "Bounty Hunter",
		short = "Bounties",
		title = "Bounty Hunter",
		format = "count",
		unit = "bounties",
		color = "#C8553D",
	},
	-- Update 3.10: the heaviest fish caught at the Fishing Pond this week (Fishing:WeekBest).
	{
		id = "fishing",
		name = "Biggest Catch",
		short = "Fishing",
		title = "Master Angler",
		format = "weight",
		color = "#3FA7D6",
	},
	-- Update 3.8: arena rating this arena season (Arena:SeasonRating). Shown in the Arena screen.
	{ id = "arena", name = "Arena Season", short = "Arena", format = "count", color = "#FF7AC8", period = "season" },
}

Leaderboards.ById = {}
Leaderboards.Weekly = {}
for i, board in Leaderboards.Boards do
	board.order = i
	board.period = board.period or "week"
	Leaderboards.ById[board.id] = board
	if board.period == "week" then
		table.insert(Leaderboards.Weekly, board)
	end
end

-- Weeks start on Saturday at 15:00 UTC (10:00 ET in winter), with the weekly update.
Leaderboards.WeekAnchor = 1789830000 -- Saturday 19 Sep 2026, 15:00 UTC (week 0)
Leaderboards.WeekSeconds = 7 * 24 * 3600

Leaderboards.ServerRefresh = 10 -- seconds between per-server board rebuilds
Leaderboards.GlobalRefresh = 300 -- seconds between global submits and top-list reads
Leaderboards.ChampionRefresh = 1800 -- seconds between reads of last week's winners
Leaderboards.Rows = 10 -- rows shown per board
Leaderboards.WeightScale = 100 -- heaviest-monster values are kg × 100

function Leaderboards.Week(now: number): number
	return math.floor((now - Leaderboards.WeekAnchor) / Leaderboards.WeekSeconds)
end

function Leaderboards.WeekEndsAt(week: number): number
	return Leaderboards.WeekAnchor + (week + 1) * Leaderboards.WeekSeconds
end

-- The DataStore key for one board in one period: a week, or an arena season for season boards.
function Leaderboards.Key(boardId: string, n: number): string
	local board = Leaderboards.ById[boardId]
	if board and board.period == "season" then
		return boardId .. "_s" .. tostring(n)
	end
	return boardId .. "_w" .. tostring(n)
end

return Leaderboards
