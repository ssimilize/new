--[[
	Album (glow-up X): the postcards your squads sent home, and the ones friends sent you.
	Opened from the Expeditions screen's Album button and a new postcard's Album button.
	Params: { region? } picks the region tab.

	Tabs: All, then every region with a postcard. The grid shows static tiles (PostcardView.tile:
	a sky gradient, portraits, the region stamp; never a live viewport). Tapping a tile opens the
	live card through the Postcards controller; ★ on a tile keeps it for good.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Postcards)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local Util = require(script.Parent.Parts.Util)
local PostcardView = require(script.Parent.Parts.PostcardView)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Postcards

local Album = { Name = "Album" }

function Album.Build(ctx)
	local panel = Panel.new({
		Title = "Postcard Album",
		Color = C.Orange,
		Size = UDim2.fromOffset(1060, 530),
		OnClose = function()
			ctx.Router:Close("Album")
		end,
	})

	local region = "all"
	local isOpen = false
	local tabs = nil
	local tabsKey = ""
	local bag = Util.bag()
	local refresh

	local tabRow = New("Frame", {
		Name = "TabRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = panel.Body,
	})
	local count = Util.text({
		Name = "Count",
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 52),
		Size = UDim2.new(0.6, 0, 0, 22),
		Parent = panel.Body,
	})
	local hint = Util.text({
		Name = "Hint",
		Text = "★ keeps a postcard for good. The oldest others make room for new ones.",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(8, 52),
		Size = UDim2.new(0.62, 0, 0, 22),
		Parent = panel.Body,
	})
	hint.TextWrapped = false
	local grid = Widgets.Scroll({
		Name = "Cards",
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 1, -80),
		Cell = Vector2.new(236, 176),
		Padding = 12,
		Parent = panel.Body,
	})
	local empty = Util.text({
		Name = "Empty",
		Text = "No postcards yet. Send a squad on an expedition and they'll write home!",
		Position = UDim2.fromOffset(40, 160),
		Size = UDim2.new(1, -80, 0, 60),
		Visible = false,
		Parent = panel.Body,
	})

	local function cards()
		return ctx.Store:Get("profile.Postcards.cards") or {}
	end

	local function buildTabs()
		local present = {}
		for _, card in cards() do
			present[card.region] = true
		end
		local list = { { id = "all", text = "All", width = 90 } }
		local key = "all"
		for _, r in Config.Regions.List do
			if present[r.id] then
				table.insert(list, { id = r.id, text = r.short, width = 108 })
				key ..= "," .. r.id
			end
		end
		if region ~= "all" and not present[region] then
			region = "all"
		end
		if key == tabsKey and tabs then
			return
		end
		tabsKey = key
		if tabs then
			tabs.Root:Destroy()
		end
		tabs = Widgets.Tabs({
			Tabs = list,
			Selected = region,
			Size = UDim2.new(1, 0, 0, 44),
			Parent = tabRow,
			OnChanged = function(id)
				region = id
				refresh()
			end,
		})
	end

	function refresh()
		if not isOpen then
			return
		end
		buildTabs()
		Util.clear(grid)
		local all = cards()
		local list = Logic.Sorted(all, if region == "all" then nil else region)
		local total = #Logic.Sorted(all)
		count.Text = string.format("Postcards %d / %d · Kept ★ %d / %d", total, Cfg.maxTotal, Logic.Favourites(all), Cfg.maxFavourites)
		empty.Visible = total == 0
		for i, card in list do
			local tile = PostcardView.tile(card, { Size = UDim2.fromOffset(236, 176), LayoutOrder = i, Parent = grid })
			local open = New("TextButton", {
				Name = "Open",
				Text = "",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 6,
				Parent = tile,
			})
			open.Activated:Connect(function()
				ctx:GetController("Postcards"):Show(card, { fromAlbum = true })
			end)
			Button.new({
				Name = "Keep",
				Text = if card.fav then "★" else "☆",
				Color = if card.fav then C.Gold else C.Gray,
				Size = UDim2.fromOffset(44, 44),
				Position = UDim2.fromOffset(6, 6),
				ZIndex = 8,
				Parent = tile,
				OnClick = function()
					Util.request(ctx, "Postcards.Favourite", { card = card.id, on = not card.fav })
				end,
			})
		end
	end
	bag.add(ctx.Store:Observe("profile.Postcards.cards", Util.debounce(refresh)))

	return {
		Root = panel.Root,
		Open = function(params)
			isOpen = true
			region = if params and type(params.region) == "string" then params.region else "all"
			tabsKey = "" -- rebuild so the tab shows the picked region
			refresh()
		end,
		Close = function()
			isOpen = false
		end,
	}
end

return Album
