--[[
	DigSite screen (update 3.11 · Seasons & secrets): the Dig Site. Opened from the "Dig" prompt on the
	sand pit's tool rack (Controllers/Interaction); no HUD button.

	Left: the Grid × Grid field (TextButtons Tile_<n>, n = 1..Grid² row by row). Covered tiles are
	sand; a dug tile shows its find or its hint (Hot! / Warm / Cool / Cold = how close the nearest
	buried find is). Right: free digs and shovels, taps left, the last tap's news and rewards,
	Start a dig (DigSite.Start) and a Fossils button (the Codex's Fossils tab).

	The open dig is read from profile.DigSite.open (what was dug so far; the layout never reaches
	the client), so closing and reopening the screen resumes it. When a dig ends the screen keeps
	its field on show, with the finds left buried marked, until the next dig starts.
	Test hooks: each tile carries Dug (bool) and Kind attributes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DigLogic = require(Shared.Logic.DigSite)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.DigSite

local TILE = 70
local GAP = 6

local SAND = Color3.fromHex("#E8CF96")
local KIND_COLORS = {
	piece = Color3.fromHex("#EFE6D2"),
	amber = Color3.fromHex("#F2A93B"),
	relic = Color3.fromHex("#B8643A"),
	egg = Color3.fromHex("#FFD98A"),
}
local HEAT_COLORS = {
	Color3.fromHex("#E5484D"), -- 1: Hot!
	Color3.fromHex("#F08A4B"), -- 2: Warm
	Color3.fromHex("#9ED8F0"), -- 3: Cool
	Color3.fromHex("#4F8FD6"), -- 4+: Cold
}

local function fossilName(id): string
	local def = Cfg.ById[id]
	return if def then def.name else "Fossil"
end

local function pieceName(id): string
	local def = Cfg.PieceById[id]
	return if def then def.name else "Piece"
end

-- The short label on a dug tile.
local function tileLabel(entry): string
	if entry.kind == "piece" then
		return pieceName(entry.piece)
	elseif entry.kind == "amber" then
		return "Amber"
	elseif entry.kind == "relic" then
		return "Relic"
	elseif entry.kind == "egg" then
		return "Egg"
	end
	return DigLogic.HintText(tonumber(entry.hint) or 0)
end

-- The news line for one tap's result.
local function findText(res): string
	local find = res.find
	if type(find) ~= "table" then
		local hint = tonumber(res.hint) or 0
		if hint <= 0 then
			return "Nothing here"
		end
		return string.format("Nothing here · %s", DigLogic.HintText(hint))
	end
	if find.kind == "piece" then
		if find.duplicate then
			return string.format("%s · %s again: +%d Amber", fossilName(find.fossil), pieceName(find.piece), find.amount or 0)
		elseif find.complete then
			return string.format("Fossil complete: %s! Its skeleton display is in your decor", fossilName(find.fossil))
		end
		return string.format("New fossil piece: %s · %s", fossilName(find.fossil), pieceName(find.piece))
	elseif find.kind == "amber" then
		return string.format("You found %d Amber!", find.amount or 0)
	elseif find.kind == "relic" then
		local d = Config.Decor.ById[find.id]
		return string.format("You found a relic: %s!", if d then d.name else "Relic")
	end
	local egg = Config.Eggs.ById[find.id]
	return string.format("You found an egg: %s!", if egg then egg.name else "Egg")
end

return {
	Name = "DigSite",
	Build = function(ctx)
		local store = ctx.Store
		local panel = Panel.new({
			Title = "Dig Site",
			Color = C.Orange,
			Size = UDim2.fromOffset(900, 500),
			OnClose = function()
				ctx.Router:Close("DigSite")
			end,
		})

		local isOpen = false
		local busy = false
		local last = nil -- the last tap's result
		local finished = nil -- { tiles = { [t]: entry }, missed = { [t]: true } } of the dig that just ended

		local body = New("Frame", { Name = "DigBody", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })

		local draw

		local function section()
			return StoreKit.tbl(store, "profile.DigSite")
		end

		local function digsLeft(s): number
			local used = if tonumber(s.day) == Util.day(ctx) then tonumber(s.digs) or 0 else 0
			return math.max(0, Cfg.FreeDigs - used)
		end

		local function openDig(s)
			local open = s.open
			if type(open) == "table" and tonumber(open.id) then
				return open
			end
			return nil
		end

		local function byTile(list): { [number]: any }
			local out = {}
			for _, entry in StoreKit.asTable(list) do
				if type(entry) == "table" and tonumber(entry.t) then
					out[tonumber(entry.t) :: number] = entry
				end
			end
			return out
		end

		local function startDig()
			if busy then
				return
			end
			busy = true
			local ok = Util.requestOnce(ctx, "DigSite.Start")
			busy = false
			if ok then
				finished = nil
				last = nil
			end
			draw()
		end

		local function tap(open, tile: number)
			if busy then
				return
			end
			busy = true
			local before = byTile(open.tiles)
			local ok, res = Util.requestOnce(ctx, "DigSite.Tap", { dig = open.id, tile = tile })
			busy = false
			if ok and type(res) == "table" then
				last = res
				if res.done then
					local entry = { t = res.tile, hint = if res.find then nil else res.hint }
					if type(res.find) == "table" then
						for k, v in res.find do
							entry[k] = v
						end
					end
					before[res.tile] = entry
					local missed = {}
					for _, t in StoreKit.asTable(res.missed) do
						missed[t] = true
					end
					finished = { tiles = before, missed = missed }
				end
			end
			draw()
		end

		local function drawGrid(tiles: { [number]: any }, missed: { [number]: boolean }, open)
			local grid = New("Frame", {
				Name = "DigGrid",
				BackgroundColor3 = Color3.fromHex("#CDAE6E"),
				Position = UDim2.fromOffset(6, 6),
				Size = UDim2.fromOffset(Cfg.Grid * (TILE + GAP) + GAP, Cfg.Grid * (TILE + GAP) + GAP),
				Parent = body,
			}, { Create.Corner(14), Create.Stroke(3) })
			for n = 1, Cfg.Tiles do
				local row, col = (n - 1) // Cfg.Grid, (n - 1) % Cfg.Grid
				local entry = tiles[n]
				local color, text = SAND, ""
				if entry then
					if entry.kind then
						color = KIND_COLORS[entry.kind] or SAND
					else
						local hint = math.max(1, tonumber(entry.hint) or 4)
						color = HEAT_COLORS[math.min(hint, #HEAT_COLORS)]
					end
					text = tileLabel(entry)
				elseif missed[n] then
					text = "Missed"
				end
				local button = New("TextButton", {
					Name = "Tile_" .. n,
					Text = text,
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Small,
					TextWrapped = true,
					TextColor3 = C.Ink,
					AutoButtonColor = open ~= nil and entry == nil,
					BackgroundColor3 = color,
					BackgroundTransparency = if entry or missed[n] then 0 else 0.1,
					Position = UDim2.fromOffset(GAP + col * (TILE + GAP), GAP + row * (TILE + GAP)),
					Size = UDim2.fromOffset(TILE, TILE),
					Parent = grid,
				}, { Create.Corner(10), Create.Stroke(if missed[n] then 3 else 2, if missed[n] then C.Red else nil) })
				button:SetAttribute("Dug", entry ~= nil)
				button:SetAttribute("Kind", if entry then entry.kind or "hint" else "")
				if open and not entry then
					button.Activated:Connect(function()
						tap(open, n)
					end)
				end
			end
		end

		function draw()
			if not isOpen then
				return
			end
			Util.clear(body)
			local s = section()
			local open = openDig(s)
			local tiles, missed = {}, {}
			if open then
				tiles = byTile(open.tiles)
				finished = nil
			elseif finished then
				tiles, missed = finished.tiles, finished.missed
			end
			drawGrid(tiles, missed, open)

			local left = digsLeft(s)
			local shovels = tonumber(s.shovels) or 0
			local card = Util.card({
				Name = "DigCard",
				Title = "Dig for fossils",
				Position = UDim2.fromOffset(410, 0),
				Size = UDim2.new(1, -410, 1, 0),
				Parent = body,
			})
			Util.text({
				Name = "Digs",
				Text = string.format("Free digs today: %d / %d · Shovels: %d", left, Cfg.FreeDigs, shovels),
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(16, 44),
				Size = UDim2.new(1, -32, 0, 26),
				Parent = card,
			})
			Util.text({
				Name = "Taps",
				Text = if open
					then string.format("Taps left: %d / %d", tonumber(open.left) or 0, Cfg.Taps)
					else "Tap a tile to dig. Empty tiles tell you how close the nearest find is: Hot!, Warm, Cool or Cold.",
				TextSize = if open then Theme.TextSize.Body else Theme.TextSize.Small,
				TextColor3 = if open then C.Text else C.TextMuted,
				TextWrapped = true,
				Position = UDim2.fromOffset(16, 74),
				Size = UDim2.new(1, -32, 0, 48),
				Parent = card,
			})
			if last then
				Util.text({
					Name = "DigNews",
					Text = findText(last),
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					TextWrapped = true,
					Position = UDim2.fromOffset(16, 126),
					Size = UDim2.new(1, -32, 0, 56),
					Parent = card,
				})
				if type(last.rewards) == "table" and #last.rewards > 0 then
					Util.rewardRow(last.rewards, card, {
						Position = UDim2.fromOffset(16, 184),
						Size = UDim2.new(1, -32, 0, 36),
					})
				end
			end
			if not open and finished then
				local lost = 0
				for _ in finished.missed do
					lost += 1
				end
				Util.text({
					Name = "DigDone",
					Text = if lost > 0
						then string.format("Dig finished · %d finds stayed buried (marked)", lost)
						else "Dig finished · you found everything!",
					TextSize = Theme.TextSize.Small,
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					Position = UDim2.fromOffset(16, 226),
					Size = UDim2.new(1, -32, 0, 44),
					Parent = card,
				})
			end
			Button.new({
				Name = "Fossils",
				Text = "Fossils",
				Color = C.Purple,
				Size = UDim2.fromOffset(150, 50),
				Position = UDim2.new(1, -166, 0, 280),
				Parent = card,
				OnClick = function()
					if ctx.Router:Has("Codex") then
						ctx.Router:Open("Codex", { tab = "fossils" })
					end
				end,
			})
			if not open then
				local canDig = left > 0 or shovels > 0
				Button.new({
					Name = "StartDig",
					Text = if left > 0 then "Start a dig" elseif shovels > 0 then "Dig with a shovel" else "No digs left today",
					Color = if canDig then C.Green else C.Gray,
					Disabled = not canDig,
					Size = UDim2.fromOffset(300, 64),
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -16),
					Parent = card,
					OnClick = function()
						if canDig then
							startDig()
						end
					end,
				})
			end
			if not Util.unlocked(ctx, Cfg.Unlock) then
				Util.lockOverlay(body, Util.unlockText(Cfg.Unlock))
			end
		end

		local watch = StoreKit.watch(store, { "profile.DigSite", "profile.Progression" }, function()
			if not busy then
				draw()
			end
		end)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				watch.Start()
				draw()
			end,
			Close = function()
				isOpen = false
				watch.Stop()
			end,
		}
	end,
}
