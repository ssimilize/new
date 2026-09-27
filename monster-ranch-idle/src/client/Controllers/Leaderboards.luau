--[[
	Leaderboards controller: the in-world board (champion nameplates are drawn by the
	Nameplates controller).

	· Board: draws a SurfaceGui on Workspace.World.Hub.Buildings.leaderboard.Body (built by
	  the World system) and cycles through the global boards every CYCLE seconds. The
	  per-server board is shown instead while the global one has no rows yet.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Streaming = require(script.Parent.Parent.Visuals.Streaming)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local LeaderboardScreen = require(UI.Screens.Leaderboards)

local New = Create.New
local C = Theme.Colors
local Boards = Config.Leaderboards

local CYCLE = 8
local BOARD_ROWS = 5

local Leaderboards = {
	Name = "Leaderboards",
	Dependencies = {},
}

local ctx
local boardGui = nil
local boardTitle, boardScope, boardRows = nil, nil, {}
local boardIndex = 1
local cycleToken = 0
local connections = {}

local function state()
	local G = ctx.Store:Get("global.Leaderboards")
	return if type(G) == "table" then G else {}
end

-- Board ---------------------------------------------------------------------------------

local function buildBoard(body: BasePart)
	local gui = New("SurfaceGui", {
		Name = "BoardGui",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0,
		Parent = body,
	})
	local bg = New("Frame", {
		BackgroundColor3 = Color3.fromHex("#1F2B24"),
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	}, { Create.Padding(20, 30, 20, 30) })
	boardTitle = Create.Text({
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		TextColor3 = C.Gold,
		Size = UDim2.fromScale(1, 0.18),
		Parent = bg,
	})
	boardScope = Create.Text({
		Text = "",
		TextScaled = true,
		TextColor3 = C.White,
		Position = UDim2.fromScale(0, 0.18),
		Size = UDim2.fromScale(1, 0.09),
		Parent = bg,
	})
	table.clear(boardRows)
	for i = 1, BOARD_ROWS do
		local row = New("Frame", {
			BackgroundTransparency = if i % 2 == 0 then 1 else 0.85,
			BackgroundColor3 = C.White,
			Position = UDim2.fromScale(0, 0.3 + (i - 1) * 0.14),
			Size = UDim2.fromScale(1, 0.13),
			Parent = bg,
		})
		local name = Create.Text({
			Text = "",
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromScale(0.02, 0.05),
			Size = UDim2.fromScale(0.64, 0.9),
			Parent = row,
		})
		local value = Create.Text({
			Text = "",
			TextScaled = true,
			TextColor3 = C.Gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromScale(0.68, 0.05),
			Size = UDim2.fromScale(0.3, 0.9),
			Parent = row,
		})
		boardRows[i] = { name = name, value = value }
	end
	boardGui = gui
end

local function drawBoard()
	if not boardGui or not boardGui.Parent then
		return
	end
	local G = state()
	local board = Boards.Boards[boardIndex]
	local rows = G.global and G.global[board.id]
	local scopeText = "This week · everywhere"
	if type(rows) ~= "table" or #rows == 0 then
		rows = G.server and G.server[board.id]
		scopeText = "This week · this server"
	end
	rows = if type(rows) == "table" then rows else {}
	boardTitle.Text = board.name
	boardScope.Text = scopeText
	for i, slot in boardRows do
		local r = rows[i]
		if r then
			slot.name.Text = string.format("%d. %s", i, tostring(r.name or "Rancher"))
			slot.value.Text = LeaderboardScreen.formatValue(board, tonumber(r.value) or 0)
		else
			slot.name.Text = if i == 1 then "Be the first!" else ""
			slot.value.Text = ""
		end
	end
end

-- Lifecycle -------------------------------------------------------------------------------

function Leaderboards.Init(context)
	ctx = context
end

-- The board (Workspace.World.Hub.Buildings.leaderboard.Body) may stream in long after Start,
-- and can stream out and back in later: each arrival gets a fresh SurfaceGui and cycle loop.
local function onBody(body: Instance)
	if not body:IsA("BasePart") then
		return
	end
	buildBoard(body)
	drawBoard()
	cycleToken += 1
	local token = cycleToken
	task.spawn(function()
		while token == cycleToken and boardGui and boardGui.Parent do
			task.wait(CYCLE)
			if token ~= cycleToken then
				return
			end
			boardIndex = boardIndex % #Boards.Boards + 1
			drawBoard()
		end
	end)
end

local function onLeaderboardBuilding(board: Instance)
	table.insert(connections, Streaming.OnChild(board, "Body", onBody))
end

function Leaderboards.Start()
	ctx.Store:Observe("global.Leaderboards", drawBoard)

	task.spawn(function()
		local world = workspace:WaitForChild("World", 60)
		if not world then
			return
		end
		table.insert(
			connections,
			Streaming.OnChild(world, "Hub", function(hub)
				table.insert(
					connections,
					Streaming.OnChild(hub, "Buildings", function(buildings)
						table.insert(connections, Streaming.OnChild(buildings, "leaderboard", onLeaderboardBuilding))
					end)
				)
			end)
		)
	end)
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function Leaderboards.Destroy()
	cycleToken += 1
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if boardGui then
		boardGui:Destroy()
		boardGui = nil
	end
end

return Leaderboards
