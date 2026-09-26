--[[
	CodexMilestones (glow-up O): the Codex screen's Milestones tab. One card per milestone
	(Logic/Codex), grouped Collection · Elements · Eggs · Regions: a portrait (UI art sheet, else the
	procedural icon; a silhouette until a form of the track is found), a progress bar, the rewards
	and a Claim button (Codex.Claim). Claimable cards sort first inside their group.

	  local tracks = CodexMilestones.new(ctx, parent, size)
	  tracks.Refresh()   -- redraw from profile.Codex + profile.Monsters.codex
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Appearance = require(Shared.Logic.Appearance)
local Logic = require(Shared.Logic.Codex)

local UI = script.Parent.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Widgets = require(UI.Components.Widgets)
local Button = require(UI.Components.Button)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)
local Tiles = require(UI.Components.Tiles)
local Sheet = require(UI.Art.Sheet)

local New = Create.New
local C = Theme.Colors

local CodexMilestones = {}

local GROUPS = {
	{ kind = "total", title = "Collection" },
	{ kind = "element", title = "Elements" },
	{ kind = "egg", title = "Eggs" },
	{ kind = "region", title = "Regions" },
}

local function titleOf(m): string
	if m.kind == "total" then
		return if m.all then "Complete the Codex" else string.format("Find %d forms", m.need)
	elseif m.kind == "element" then
		local el = Config.Elements.ById[m.key]
		local name = if el then el.name else m.key
		return if m.all then string.format("Every %s form", name) else string.format("Find %d %s forms", m.need, name)
	elseif m.kind == "egg" then
		local egg = Config.Eggs.ById[m.key]
		return string.format("Every form a %s can hatch", if egg then egg.name else m.key)
	end
	local region = Config.Regions.ById[m.key]
	return string.format("Every form met in %s", if region then region.name else m.key)
end

-- The last found form of the track (its portrait), or the first form as a silhouette.
local function portraitOf(m, found, size: number): GuiObject
	local formId
	for _, id in m.forms do
		if found[id] then
			formId = id
		end
	end
	if formId then
		local art = Sheet.portrait(formId, { Size = UDim2.fromOffset(size, size) })
		if art then
			return art
		end
		local info = Config.Species.FormById[formId]
		local ok, ap = pcall(Appearance.Preview, info.line.id, info.stage, formId)
		if ok then
			return MonsterIcon.new(ap, size)
		end
	end
	local info = Config.Species.FormById[m.forms[1]]
	return MonsterIcon.silhouette(info.line.id, size)
end

function CodexMilestones.new(ctx, parent: Instance, size: UDim2)
	local store = ctx.Store
	local list = Widgets.List({ Name = "Milestones", Size = size, Padding = 8, Parent = parent })
	local busy = false
	local api = { Root = list }

	local function claim(m)
		if busy then
			return
		end
		busy = true
		local ok = StoreKit.request(ctx, "Codex.Claim", { milestone = m.id })
		busy = false
		if ok then
			ctx:Sound("StarUp")
			for _, itemId in m.items do
				local item = Config.Mastery.ItemById[itemId]
				if item and item.kind == "title" then
					ctx:Toast(string.format("New title: %s", item.name), "reward")
				elseif item and item.kind == "aura" then
					ctx:Toast(string.format("New aura: %s", item.name), "reward")
				end
			end
			api.Refresh()
		end
	end

	local function card(m, found, claimed, order: number, grid: Instance)
		local have, need = Logic.Progress(m, found)
		local done = have >= need
		local root = Tiles.card({ Name = m.id, Size = UDim2.fromOffset(456, 96), LayoutOrder = order, Parent = grid })
		local icon = portraitOf(m, found, 64)
		icon.Position = UDim2.fromOffset(8, 16)
		icon.Parent = root
		Tiles.label({
			Text = titleOf(m),
			TextSize = Theme.TextSize.Small + 1,
			Position = UDim2.fromOffset(80, 6),
			Size = UDim2.fromOffset(250, 24),
			Parent = root,
		})
		Widgets.Bar({
			Value = have / need,
			Text = string.format("%d / %d", have, need),
			Color = if done then C.Green else C.Blue,
			Position = UDim2.fromOffset(80, 34),
			Size = UDim2.fromOffset(250, 20),
			Parent = root,
		})
		local rewards = Tiles.row({ Position = UDim2.fromOffset(80, 60), Size = UDim2.fromOffset(250, 28), Parent = root }, 6)
		if m.gems > 0 then
			Widgets.Chip({ Text = string.format("+%d gems", m.gems), Color = C.Purple, LayoutOrder = 1, Parent = rewards })
		end
		for i, itemId in m.items do
			local item = Config.Mastery.ItemById[itemId]
			if item then
				Widgets.Chip({
					Text = if item.kind == "aura" then "Aura" else "Title",
					Color = if item.kind == "aura" then C.Pink else C.Orange,
					LayoutOrder = 1 + i,
					Parent = rewards,
				})
			end
		end
		if claimed then
			local chip = Widgets.Chip({ Text = "Claimed", Color = C.Green, Height = 32, Parent = root })
			chip.Position = UDim2.fromOffset(348, 32)
		else
			local b = Button.new({
				Name = "Claim",
				Text = "Claim",
				Color = if done then C.Green else C.Gray,
				Size = UDim2.fromOffset(104, 48),
				Disabled = not done,
				OnClick = function()
					claim(m)
				end,
			})
			b.Root.Position = UDim2.fromOffset(340, 24)
			b.Root.Parent = root
			if done then
				Tiles.badge(b.Root):Set("!")
			end
		end
	end

	function api.Refresh()
		Tiles.clear(list)
		local found = Logic.Found(StoreKit.tbl(store, "profile.Monsters.codex"))
		local claimed = StoreKit.tbl(store, "profile.Codex.claimed")
		local order = 0
		for _, group in GROUPS do
			local items = {}
			for _, m in Logic.Milestones() do
				if m.kind == group.kind then
					table.insert(items, m)
				end
			end
			-- Claimable first, then in progress, then claimed; ties keep the content order.
			local function rank(m): number
				if claimed[m.id] then
					return 2
				end
				return if Logic.IsDone(m, found) then 0 else 1
			end
			table.sort(items, function(a, b)
				local ra, rb = rank(a), rank(b)
				if ra ~= rb then
					return ra < rb
				end
				return a.order < b.order
			end)
			order += 1
			Tiles.label({
				Text = group.title,
				TextSize = Theme.TextSize.Body,
				Size = UDim2.new(1, -12, 0, 28),
				LayoutOrder = order,
				Parent = list,
			})
			order += 1
			local grid = New("Frame", {
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, -12, 0, 0),
				LayoutOrder = order,
				Parent = list,
			}, { Create.Grid(Vector2.new(456, 96), 8) })
			for i, m in items do
				card(m, found, claimed[m.id] ~= nil, i, grid)
			end
		end
	end

	return api
end

return CodexMilestones
