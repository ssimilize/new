--[[
	Leaderboards screen: the weekly boards from global.Leaderboards (see the Leaderboards
	server system and Config.Leaderboards).

	One tab per board, and a "This server" / "Everywhere" switch. Shows last week's
	champion and their title for the selected board, the top rows, the reset countdown,
	and the player's own place on this server. Open params: { board = boardId? }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Logic.Format)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Icon = require(UI.Components.Icon)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Boards = Config.Leaderboards

local Leaderboards = { Name = "Leaderboards" }

-- Formats a board value for display.
function Leaderboards.formatValue(board, value: number): string
	if board.format == "weight" then
		return Format.weight(value / Boards.WeightScale)
	elseif board.format == "stage" then
		return "Stage " .. tostring(value)
	elseif board.format == "count" then
		return Format.commas(value) .. (if board.unit then " " .. board.unit else "")
	end
	return Format.short(value)
end

local MEDALS = { Color3.fromHex("#F5C542"), Color3.fromHex("#C9D1D9"), Color3.fromHex("#D08A4E") }

function Leaderboards.Build(ctx)
	local store = ctx.Store
	local panel = Panel.new({
		Title = "Leaderboards",
		Color = Color3.fromHex("#D49A12"),
		Size = UDim2.fromOffset(860, 480),
		OnClose = function()
			ctx.Router:Close("Leaderboards")
		end,
	})

	local selected = Boards.Boards[1].id
	local scope = "server"
	local render

	local tabList = {}
	for _, board in Boards.Boards do
		-- Short labels at an even width so every board fits in one row (6 boards since 3.0).
		table.insert(
			tabList,
			{ id = board.id, text = board.short or board.name, width = math.floor((812 - 8 * (#Boards.Boards - 1)) / #Boards.Boards) }
		)
	end
	local tabs = Widgets.Tabs({
		Tabs = tabList,
		Selected = selected,
		Parent = panel.Body,
		OnChanged = function(id)
			selected = id
			render()
		end,
	})

	-- Left column: champion card, scope switch, countdown, your place.
	local side = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(0, 250, 1, -54),
		Parent = panel.Body,
	}, { Create.List("y", 8) })

	local champCard = Util.card({ Size = UDim2.new(1, 0, 0, 118), LayoutOrder = 1, Parent = side })
	local trophy = Icon.new("trophy", 40)
	trophy.Position = UDim2.fromOffset(10, 10)
	trophy.Parent = champCard
	local champTitle = Util.text({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Body,
		Position = UDim2.fromOffset(58, 8),
		Size = UDim2.new(1, -64, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Parent = champCard,
	})
	local champName = Util.text({
		Text = "",
		TextSize = Theme.TextSize.Body,
		Position = UDim2.fromOffset(58, 32),
		Size = UDim2.new(1, -64, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Parent = champCard,
	})
	Util.text({
		Text = "Last week's #1 everywhere wears this title for a week.",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(10, 62),
		Size = UDim2.new(1, -20, 0, 48),
		Parent = champCard,
	})

	local scopeTabs = Widgets.Tabs({
		Tabs = { { id = "server", text = "This server", width = 121 }, { id = "global", text = "Everywhere", width = 121 } },
		Selected = scope,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = side,
		OnChanged = function(id)
			scope = id
			render()
		end,
	})
	scopeTabs.Root.LayoutOrder = 2

	local resetLabel = Util.text({
		Text = "",
		TextSize = Theme.TextSize.Small + 1,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 3,
		Parent = side,
	})
	local youCard = Util.card({ Size = UDim2.new(1, 0, 0, 74), LayoutOrder = 4, Parent = side })
	local youLabel = Util.text({
		Text = "",
		TextSize = Theme.TextSize.Body,
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 1, -12),
		Parent = youCard,
	})

	-- Right: the rows.
	local list = Widgets.List({
		Position = UDim2.fromOffset(262, 54),
		Size = UDim2.new(1, -262, 1, -54),
		Padding = 6,
		Parent = panel.Body,
	})
	local empty = Util.text({
		Text = "",
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(262, 140),
		Size = UDim2.new(1, -262, 0, 60),
		Visible = false,
		Parent = panel.Body,
	})

	local function state()
		local G = store:Get("global.Leaderboards")
		return if type(G) == "table" then G else {}
	end

	local function makeRow(rank: number, row, board, isMe: boolean)
		local frame = New("Frame", {
			Name = "Row" .. rank,
			BackgroundColor3 = if isMe then Color3.fromHex("#FFE9A8") else C.Card,
			Size = UDim2.new(1, -8, 0, 40),
			LayoutOrder = rank,
			Parent = list,
		}, { Create.Corner(10), Create.Stroke(2, if isMe then C.Gold else C.Line, 0.3) })
		local medal = New("Frame", {
			BackgroundColor3 = MEDALS[rank] or C.Gray,
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.fromOffset(6, 5),
			Parent = frame,
		}, { Create.Round(), Create.Stroke(2) })
		Create.Text({
			Text = tostring(rank),
			TextSize = Theme.TextSize.Small + 1,
			Size = UDim2.fromScale(1, 1),
			Parent = medal,
		})
		local name = if isMe then "You" else tostring(row.name or "Rancher")
		if type(row.label) == "string" and row.label ~= "" then
			name ..= " · " .. row.label
		end
		Util.text({
			Text = name,
			Font = if isMe then Theme.Fonts.Display else Theme.Fonts.Body,
			Position = UDim2.fromOffset(46, 0),
			Size = UDim2.new(1, -200, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Parent = frame,
		})
		Util.text({
			Text = Leaderboards.formatValue(board, tonumber(row.value) or 0),
			Font = Theme.Fonts.Display,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(1, -150, 0, 0),
			Size = UDim2.new(0, 140, 1, 0),
			Parent = frame,
		})
	end

	local lastKey = ""
	function render()
		local G = state()
		local board = Boards.ById[selected]
		if not board then
			return
		end
		local me = ctx.Player.UserId

		-- Champion
		local champ = G.champions and G.champions[selected]
		champTitle.Text = board.title
		if type(champ) == "table" then
			champName.Text = if champ.userId == me then "You! Nice work." else tostring(champ.name or "Rancher")
		else
			champName.Text = "No champion yet"
		end

		-- Rows (rebuilt only when they change; the state refreshes every few seconds)
		local rows = if scope == "server" then (G.server and G.server[selected]) else (G.global and G.global[selected])
		rows = if type(rows) == "table" then rows else {}
		local parts = { selected, scope }
		for _, r in rows do
			table.insert(parts, tostring(r.userId) .. ":" .. tostring(r.value) .. ":" .. tostring(r.name) .. ":" .. tostring(r.label))
		end
		local key = table.concat(parts, "|")
		if key ~= lastKey then
			lastKey = key
			Util.clear(list)
			for rank, r in rows do
				makeRow(rank, r, board, r.userId == me)
			end
		end
		if #rows == 0 then
			empty.Visible = true
			if scope == "global" and (tonumber(G.globalAt) or 0) == 0 then
				empty.Text = "Loading the global board…"
			else
				empty.Text = "Nobody is on this board yet this week. Be the first!"
			end
		else
			empty.Visible = false
		end

		-- You
		local mine, myRank = nil, nil
		for rank, r in (G.server and G.server[selected]) or {} do
			if r.userId == me then
				mine, myRank = r, rank
			end
		end
		if mine then
			youLabel.Text = string.format("You: %s\n#%d on this server", Leaderboards.formatValue(board, tonumber(mine.value) or 0), myRank)
		else
			youLabel.Text = "You're not on this board yet."
		end
	end

	local bag = Util.bag()
	local stopCountdown

	return {
		Root = panel.Root,
		Open = function(params)
			if type(params) == "table" and Boards.ById[params.board] and params.board ~= selected then
				selected = params.board
				tabs:Select(selected)
			end
			lastKey = ""
			bag.clean()
			bag.add(store:Observe("global.Leaderboards", function()
				render()
			end))
			render()
			if stopCountdown then
				stopCountdown()
			end
			stopCountdown = Widgets.Countdown(resetLabel, function()
				return tonumber(state().endsAt)
			end, function(left)
				return "New week in " .. Format.duration(left)
			end)
		end,
		Close = function()
			bag.clean()
			if stopCountdown then
				stopCountdown()
				stopCountdown = nil
			end
		end,
	}
end

return Leaderboards
