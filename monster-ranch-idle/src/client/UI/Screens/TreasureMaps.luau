--[[
	TreasureMaps screen (update 3.13 · Wild things): map pieces and Treasure Maps. Opened from the
	"Maps" button in the Expeditions header; no HUD button, no world building.

	Left card   the pieces: four quarter tiles fill as pieces arrive (four make a map), pieces
	            waiting beyond that, where pieces drop, and the squad in use.
	Right       the held maps (at most Config.TreasureMaps.MaxMaps) as parchment cards: the
	            region, a drawn X, the guardian's power (Logic/TreasureMaps.Preview), the chest's
	            rewards (Logic/TreasureMaps.ChestPreview + the decor chance) and "Dig"
	            (TreasureMaps.Dig → the replay on the battle stage, Parts/Battle → the chest).
	Locked below Ranch Level 23 (a lock overlay).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local MapLogic = require(Shared.Logic.TreasureMaps)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local StoreKit = require(UI.Components.StoreKit)
local Icon = require(UI.Components.Icon)
local Util = require(script.Parent.Parts.Util)
local Battle = require(script.Parent.Parts.Battle)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.TreasureMaps

local PARCHMENT = Color3.fromHex("#EAD3A0")
local INK = Color3.fromHex("#5A3A1C")
local RED_X = Color3.fromHex("#D0342C")

return {
	Name = "TreasureMaps",
	Build = function(ctx)
		local store = ctx.Store
		local panel = Panel.new({
			Title = "Treasure Maps",
			Color = Color3.fromHex("#A0703D"),
			Size = UDim2.fromOffset(960, 520),
			OnClose = function()
				ctx.Router:Close("TreasureMaps")
			end,
		})

		local isOpen = false
		local viewer = nil
		local body = New("Frame", { Name = "MapsBody", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })

		local draw

		local function state()
			local s = StoreKit.tbl(store, "profile.TreasureMaps")
			local maps = {}
			for _, m in (if type(s.maps) == "table" then s.maps else {}) do
				if type(m) == "table" and Config.Regions.ById[m.region] then
					table.insert(maps, m)
				end
			end
			return { pieces = tonumber(s.pieces) or 0, maps = maps }
		end

		local function squad(): { string }
			local e = StoreKit.tbl(store, "profile.Expeditions")
			local list = StoreKit.monsters(store)
			local out = {}
			for _, id in (if type(e.squad) == "table" then e.squad else {}) do
				if list[id] then
					table.insert(out, id)
				end
			end
			return out
		end

		local function line(parent, name: string, text: string, y: number, props)
			local merged = {
				Name = name,
				Text = text,
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(16, y),
				Size = UDim2.new(1, -32, 0, 26),
				Parent = parent,
			}
			for k, v in props or {} do
				merged[k] = v
			end
			return Util.text(merged)
		end

		-- Dig ------------------------------------------------------------------------------------
		local function dig(map)
			if #squad() == 0 then
				ctx:Toast("Pick a squad on the Expeditions screen first", "info")
				return
			end
			local ok, res = Util.requestOnce(ctx, "TreasureMaps.Dig", { map = map.id })
			if not ok or type(res) ~= "table" then
				return
			end
			if viewer then
				viewer.Destroy()
			end
			local region = Config.Regions.ById[res.region or map.region]
			viewer = Battle.play(ctx, {
				replay = res.replay,
				win = res.win == true,
				rewards = res.rewards,
				title = string.format("Treasure Map · %s", if region then region.name else tostring(map.region)),
				stage = res.region or map.region,
				winText = "Treasure found!",
				loseText = "The guardian won. Your map is safe: try again any time",
				onClose = function()
					viewer = nil
					if draw then
						draw()
					end
				end,
			})
			draw()
		end

		-- Layout --------------------------------------------------------------------------------
		local function drawPieces(st)
			local card = Util.card({
				Name = "Pieces",
				Title = "Map pieces",
				Size = UDim2.new(0, 300, 1, 0),
				Parent = body,
			})
			local have = math.min(st.pieces, Cfg.PiecesPerMap)
			local grid = New("Frame", {
				Name = "Quarters",
				BackgroundColor3 = Color3.fromHex("#C9B48A"),
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 44),
				Size = UDim2.fromOffset(150, 110),
				Parent = card,
			}, { Create.Corner(UDim.new(0, 10)), Create.Stroke(2) })
			for i = 1, Cfg.PiecesPerMap do
				local col, row = (i - 1) % 2, (i - 1) // 2
				local tile = New("Frame", {
					Name = "Quarter" .. i,
					BackgroundColor3 = if i <= have then PARCHMENT else Color3.fromHex("#8E7A58"),
					BackgroundTransparency = if i <= have then 0 else 0.5,
					Position = UDim2.new(col * 0.5, 4, row * 0.5, 4),
					Size = UDim2.new(0.5, -8, 0.5, -8),
					Parent = grid,
				}, { Create.Corner(UDim.new(0, 6)) })
				tile:SetAttribute("Filled", i <= have)
				if i <= have then
					New("Frame", {
						BackgroundColor3 = INK,
						Size = UDim2.fromScale(0.6, 0.06),
						Position = UDim2.fromScale(0.2, 0.5),
						Rotation = if col == 0 then -15 else 15,
						Parent = tile,
					})
				end
			end
			line(card, "PieceCount", string.format("Pieces: %d/%d", have, Cfg.PiecesPerMap), 164, {
				TextXAlignment = Enum.TextXAlignment.Center,
				Font = Theme.Fonts.Display,
			})
			local waiting = st.pieces - have
			if waiting > 0 then
				line(card, "Waiting", string.format("Waiting pieces: %d", waiting), 192, {
					TextXAlignment = Enum.TextXAlignment.Center,
					TextColor3 = C.TextMuted,
					TextSize = Theme.TextSize.Small,
				})
			end
			line(card, "Where", "Pieces turn up on expeditions, bounties, fishing trips and digs. Four make a map.", 222, {
				TextWrapped = true,
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				Size = UDim2.new(1, -32, 0, 60),
			})
			line(card, "Hold", string.format("You can hold %d maps at once.", Cfg.MaxMaps), 290, {
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
			})
			local ids = squad()
			line(
				card,
				"Squad",
				if #ids > 0
					then string.format("Your Expeditions squad: %d monsters", #ids)
					else "Pick a squad on the Expeditions screen first",
				330,
				{ TextWrapped = true, Size = UDim2.new(1, -32, 0, 44), TextColor3 = if #ids > 0 then C.Text else C.TextMuted }
			)
			Button.new({
				Name = "Squad",
				Text = "Squad",
				Color = C.Blue,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 16, 1, -14),
				Size = UDim2.new(1, -32, 0, 50),
				Parent = card,
				OnClick = function()
					ctx.Router:Open("Expeditions", { tab = "stages" })
				end,
			})
		end

		local function drawMap(parent, map, i: number)
			local region = Config.Regions.ById[map.region]
			local preview = MapLogic.Preview(map)
			local card = New("Frame", {
				Name = "Map" .. i,
				BackgroundColor3 = PARCHMENT,
				Size = UDim2.new(1 / Cfg.MaxMaps, -8, 1, 0),
				LayoutOrder = i,
				Parent = parent,
			}, { Create.Corner(UDim.new(0, 14)), Create.Stroke(2) })
			Util.text({
				Name = "Region",
				Text = if region then region.name else map.region,
				Font = Theme.Fonts.Display,
				TextColor3 = INK,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(8, 8),
				Size = UDim2.new(1, -16, 0, 44),
				Parent = card,
			})
			-- The map drawing: a dashed trail to a red X.
			local art = New("Frame", {
				Name = "Chart",
				BackgroundColor3 = Color3.fromHex("#F3E2B8"),
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 56),
				Size = UDim2.new(1, -32, 0, 86),
				Parent = card,
			}, { Create.Corner(UDim.new(0, 8)) })
			for d = 0, 3 do
				New("Frame", {
					BackgroundColor3 = INK,
					Size = UDim2.fromScale(0.1, 0.05),
					Position = UDim2.fromScale(0.1 + d * 0.13, 0.7 - d * 0.1),
					Rotation = -20,
					Parent = art,
				})
			end
			for _, r in { 45, -45 } do
				New("Frame", {
					Name = "X",
					BackgroundColor3 = RED_X,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.74, 0.34),
					Size = UDim2.new(0, 36, 0, 7),
					Rotation = r,
					Parent = art,
				})
			end
			Util.text({
				Name = "GuardianPower",
				Text = string.format("Guardian power %s", Format.short(preview.power)),
				TextColor3 = INK,
				TextSize = Theme.TextSize.Small,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(8, 148),
				Size = UDim2.new(1, -16, 0, 22),
				Parent = card,
			})
			Util.text({
				Name = "Stage",
				Text = string.format("Stage %d", map.stage),
				TextColor3 = INK,
				TextSize = Theme.TextSize.Small,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(8, 170),
				Size = UDim2.new(1, -16, 0, 20),
				Parent = card,
			})
			Util.rewardRow(MapLogic.ChestPreview(map), card, {
				Position = UDim2.fromOffset(10, 196),
				Size = UDim2.new(1, -20, 0, 34),
				IconSize = 22,
				Align = Enum.HorizontalAlignment.Center,
			})
			Util.text({
				Name = "DecorChance",
				Text = string.format("%s chance of a rare decor piece", Format.percent(Cfg.DecorChance)),
				TextColor3 = INK,
				TextWrapped = true,
				TextSize = Theme.TextSize.Small,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(8, 236),
				Size = UDim2.new(1, -16, 0, 40),
				Parent = card,
			})
			Button.new({
				Name = "Dig",
				Text = "Dig",
				Color = C.Orange,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -12),
				Size = UDim2.new(1, -24, 0, 50),
				Parent = card,
				OnClick = function()
					dig(map)
				end,
			})
		end

		local function drawMaps(st)
			local card = Util.card({
				Name = "Maps",
				Title = string.format("Your maps: %d/%d", #st.maps, Cfg.MaxMaps),
				Position = UDim2.fromOffset(316, 0),
				Size = UDim2.new(1, -316, 1, 0),
				Parent = body,
			})
			if #st.maps == 0 then
				line(card, "Empty", "No maps yet. Collect four pieces to make one.", 60, {
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextColor3 = C.TextMuted,
					Size = UDim2.new(1, -32, 0, 60),
				})
				local big = Icon.new("treasure_map", 96)
				big.AnchorPoint = Vector2.new(0.5, 0)
				big.Position = UDim2.new(0.5, 0, 0, 140)
				big.Parent = card
				return
			end
			local row = New("Frame", {
				Name = "MapRow",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 42),
				Size = UDim2.new(1, -24, 1, -54),
				Parent = card,
			}, { Create.List("x", 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top) })
			for i, map in st.maps do
				drawMap(row, map, i)
			end
		end

		function draw()
			if not isOpen then
				return
			end
			Util.clear(body)
			local st = state()
			drawPieces(st)
			drawMaps(st)
			if not Util.unlocked(ctx, Cfg.Unlock) then
				Util.lockOverlay(body, Util.unlockText(Cfg.Unlock))
			end
		end

		local watch = StoreKit.watch(store, { "profile.TreasureMaps", "profile.Expeditions.squad", "profile.Progression" }, function()
			draw()
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
