--[[
	Codex (C2): every species line, grouped by element, then hybrids and (while the event
	runs, or once found) event lines. Discovered forms are drawn in colour, undiscovered
	ones as silhouettes. Header shows species found and form completion %.
	Tap a line: its three stages and adult branches (with diets), variants found, how many
	were hatched, and hybrid recipe hints from Config.Breeding.Hybrids.
	Data: profile.Monsters.codex[lineId] = { forms = { [formId] = true }, variants, count },
	      profile.Breeding.discovered[lineId].
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Appearance = require(Shared.Logic.Appearance)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)
local Tiles = require(UI.Components.Tiles)
local MasteryBadge = require(script.Parent.Parts.MasteryBadge)

local New = Create.New
local C = Theme.Colors
local Species = Config.Species

local Codex = { Name = "Codex" }

local SILHOUETTE = Color3.fromHex("#3B3350")

local function silhouetteOf(ap, size: number): Frame
	local icon = MonsterIcon.new(ap, size)
	for _, d in icon:GetDescendants() do
		if d:IsA("Frame") then
			d.BackgroundColor3 = SILHOUETTE
		end
	end
	return icon
end

-- All forms of a line as { stage, form } in path order.
local function formsOf(def): { { stage: number, form: any } }
	local list = { { stage = 1, form = def.forms[1] }, { stage = 2, form = def.forms[2] } }
	for _, adult in def.forms[3] do
		table.insert(list, { stage = 3, form = adult })
	end
	return list
end

local function capitalize(s: string): string
	return (string.gsub(s, "^%l", string.upper))
end

function Codex.Build(ctx)
	local store = ctx.Store
	local selectedLine: string? = nil
	local cardsByLine = {} -- lineId -> card (for cheap selection highlight)

	local panel = Panel.new({
		Title = "Codex",
		Color = C.Blue,
		Size = UDim2.fromOffset(980, 490),
		OnClose = function()
			ctx.Router:Close("Codex")
		end,
	})
	local summary = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Body,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		TextWrapped = false,
		LayoutOrder = 1,
		Parent = panel.HeaderRight,
	})
	local list = Widgets.List({ Size = UDim2.fromOffset(628, 400), Padding = 8, Parent = panel.Body })
	local detail = Tiles.card({ Position = UDim2.fromOffset(640, 0), Size = UDim2.fromOffset(304, 400), Parent = panel.Body })
	local detailBody = Widgets.List({ Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), Padding = 6, Parent = detail })

	local function codexOf(lineId: string)
		return StoreKit.asTable(StoreKit.tbl(store, "profile.Monsters.codex")[lineId])
	end

	local function isShown(def): boolean
		if def.event then
			return def.event == StoreKit.activeEvent() or next(StoreKit.asTable(codexOf(def.id).forms)) ~= nil
		end
		return true
	end

	local function groups()
		local out = {}
		for _, el in Config.Elements.List do
			table.insert(out, { id = el.id, title = el.name, element = el.id, lines = {} })
		end
		local hybrids = { id = "hybrid", title = "Hybrids", lines = {} }
		local event = { id = "event", title = "Event", lines = {} }
		local byId = {}
		for _, g in out do
			byId[g.id] = g
		end
		for _, def in Species.Lines do
			if isShown(def) then
				if def.event then
					table.insert(event.lines, def)
				elseif def.hybrid then
					table.insert(hybrids.lines, def)
				else
					local g = byId[def.elements[1]]
					if g then
						table.insert(g.lines, def)
					end
				end
			end
		end
		table.insert(out, hybrids)
		if #event.lines > 0 then
			table.insert(out, event)
		end
		return out
	end

	local function bestSeenForm(def, forms)
		local best
		for _, entry in formsOf(def) do
			if forms[entry.form.id] then
				best = entry
			end
		end
		return best
	end

	local function renderDetail()
		Tiles.clear(detailBody)
		local def = selectedLine and Species.ById[selectedLine]
		if not def then
			Tiles.label({
				Text = "Tap a species to see its evolutions.",
				TextSize = Theme.TextSize.Body,
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, -12, 0, 80),
				Parent = detailBody,
			})
			return
		end
		local entry = codexOf(def.id)
		local forms = StoreKit.asTable(entry.forms)
		local found = next(forms) ~= nil
		local first = def.forms[1]
		Tiles.label({
			Text = if found then first.name .. " line" else "??? line",
			TextSize = Theme.TextSize.Header - 2,
			Size = UDim2.new(1, -12, 0, 28),
			LayoutOrder = 1,
			Parent = detailBody,
		})
		local chips = Tiles.row({ Size = UDim2.new(1, -12, 0, 28), LayoutOrder = 2, Parent = detailBody }, 6)
		for i, el in def.elements do
			Widgets.ElementChip(el, chips).LayoutOrder = i
		end
		if def.hybrid then
			Widgets.Chip({ Text = "HYBRID", Color = C.Purple, LayoutOrder = 5, Parent = chips })
		end
		if def.event then
			Widgets.Chip({ Text = "EVENT", Color = C.Blue, LayoutOrder = 6, Parent = chips })
		end
		if found then
			MasteryBadge.chip(ctx, def.id, chips, 7) -- 3.3: Line Mastery tier
		end

		-- Stages and branches
		local path = New("Frame", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -12, 0, 0),
			LayoutOrder = 3,
			Parent = detailBody,
		}, { Create.Grid(Vector2.new(86, 112), 6) })
		for i, item in formsOf(def) do
			local seen = forms[item.form.id] == true
			local cell = Tiles.frame({ Size = UDim2.fromOffset(86, 112), LayoutOrder = i, Parent = path })
			local ap = Appearance.Preview(def.id, item.stage, item.form.id)
			local icon = if seen then MonsterIcon.new(ap, 72) else silhouetteOf(ap, 72)
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.Position = UDim2.new(0.5, 0, 0, 0)
			icon.Parent = cell
			local stageName = Config.Economy.Stages[item.stage].name
			local diet = if item.form.diet then " · " .. capitalize(item.form.diet) else ""
			Tiles.label({
				Text = (if seen then item.form.name else "???") .. "\n" .. stageName .. diet,
				TextSize = Theme.TextSize.Small - 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 72),
				Size = UDim2.new(1, 0, 0, 38),
				Parent = cell,
			})
		end
		if Species.IsBranching(def.id) then
			Tiles.label({
				Text = "Teens pick their adult form by the food they eat most.",
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				Size = UDim2.new(1, -12, 0, 38),
				LayoutOrder = 4,
				Parent = detailBody,
			})
		end

		-- Variants and counts
		local variants = StoreKit.asTable(entry.variants)
		local vrow = Tiles.row({ Size = UDim2.new(1, -12, 0, 28), LayoutOrder = 5, Parent = detailBody }, 6)
		for i, v in { { "normal", "Normal", C.Gray }, { "golden", "Golden", Color3.fromHex("#E0A915") }, { "rainbow", "Rainbow", C.Pink } } do
			local has = variants[v[1]] == true or variants[i - 1] == true
			local chip = Widgets.Chip({
				Text = (if has then "✔ " else "") .. v[2],
				Color = if has then v[3] else C.Line,
				LayoutOrder = i,
				Parent = vrow,
			})
			chip.BackgroundTransparency = if has then 0 else 0.3
		end
		Tiles.label({
			Text = string.format(
				"Owned %s · forms %d / %d",
				Format.commas(tonumber(entry.count) or 0),
				(function()
					local n = 0
					for _, item in formsOf(def) do
						if forms[item.form.id] then
							n += 1
						end
					end
					return n
				end)(),
				#formsOf(def)
			),
			TextSize = Theme.TextSize.Small + 1,
			TextColor3 = C.TextMuted,
			Size = UDim2.new(1, -12, 0, 22),
			LayoutOrder = 6,
			Parent = detailBody,
		})

		-- Hybrid recipes
		local hints = {}
		local discovered = StoreKit.tbl(store, "profile.Breeding.discovered")
		if def.hybrid then
			for pair, lineId in Config.Breeding.Hybrids do
				if lineId == def.id then
					local a, b = string.match(pair, "^(%w+)%+(%w+)$")
					local ea, eb = Config.Elements.ById[a or ""], Config.Elements.ById[b or ""]
					table.insert(hints, string.format("Breed a %s and a %s monster.", if ea then ea.name else a, if eb then eb.name else b))
				end
			end
		else
			local element = def.elements[1]
			for pair, lineId in Config.Breeding.Hybrids do
				local a, b = string.match(pair, "^(%w+)%+(%w+)$")
				if a == element or b == element then
					local other = if a == element then b else a
					local od = Config.Elements.ById[other or ""]
					local hybrid = Species.ById[lineId]
					local known = discovered[lineId] == true or next(StoreKit.asTable(codexOf(lineId).forms)) ~= nil
					table.insert(
						hints,
						string.format(
							"+ %s → %s",
							if od then od.name else other,
							if known and hybrid then hybrid.forms[1].name else "???"
						)
					)
				end
			end
			table.sort(hints)
		end
		if #hints > 0 then
			Tiles.label({
				Text = (if def.hybrid then "How to get it" else "Hybrid recipes") .. "\n" .. table.concat(hints, "\n"),
				TextSize = Theme.TextSize.Small,
				TextYAlignment = Enum.TextYAlignment.Top,
				Size = UDim2.new(1, -12, 0, 20 * (#hints + 1) + 4),
				LayoutOrder = 7,
				Parent = detailBody,
			})
		end
	end

	local function highlight()
		for lineId, card in cardsByLine do
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if lineId == selectedLine then C.Blue else C.Ink
				stroke.Thickness = if lineId == selectedLine then 5 else Theme.Stroke.Card
			end
		end
	end

	local function refresh()
		Tiles.clear(list)
		table.clear(cardsByLine)
		local totalForms, seenForms, totalLines, seenLines = 0, 0, 0, 0
		for gi, g in groups() do
			if #g.lines > 0 then
				local found = 0
				for _, def in g.lines do
					if next(StoreKit.asTable(codexOf(def.id).forms)) ~= nil then
						found += 1
					end
				end
				local header = Tiles.row({ Size = UDim2.new(1, -12, 0, 30), LayoutOrder = gi * 2 - 1, Parent = list }, 8)
				if g.element then
					Widgets.ElementChip(g.element, header).LayoutOrder = 1
				else
					Widgets.Chip({ Text = g.title, Color = if g.id == "event" then C.Blue else C.Purple, LayoutOrder = 1, Parent = header })
				end
				Tiles.label({
					Text = string.format("%d / %d found", found, #g.lines),
					TextSize = Theme.TextSize.Small + 1,
					TextColor3 = C.TextMuted,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, 26),
					TextWrapped = false,
					LayoutOrder = 2,
					Parent = header,
				})
				local grid = New("Frame", {
					BackgroundTransparency = 1,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, -12, 0, 0),
					LayoutOrder = gi * 2,
					Parent = list,
				}, { Create.Grid(Vector2.new(112, 130), 8) })
				for li, def in g.lines do
					local forms = StoreKit.asTable(codexOf(def.id).forms)
					local all = formsOf(def)
					local seen = 0
					for _, item in all do
						if forms[item.form.id] then
							seen += 1
						end
					end
					totalForms += #all
					seenForms += seen
					totalLines += 1
					if seen > 0 then
						seenLines += 1
					end
					local card = Tiles.card({ Name = def.id, LayoutOrder = li, Parent = grid })
					cardsByLine[def.id] = card
					local best = bestSeenForm(def, forms)
					local icon
					if best then
						local ok, ap = pcall(Appearance.Preview, def.id, best.stage, best.form.id)
						icon = if ok then MonsterIcon.new(ap, 84) else MonsterIcon.silhouette(def.id, 84)
					else
						icon = MonsterIcon.silhouette(def.id, 84)
					end
					icon.AnchorPoint = Vector2.new(0.5, 0)
					icon.Position = UDim2.new(0.5, 0, 0, 4)
					icon.Parent = card
					Tiles.label({
						Text = if best then def.forms[1].name else "???",
						TextSize = Theme.TextSize.Small + 1,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.fromOffset(0, 88),
						Size = UDim2.new(1, 0, 0, 20),
						Parent = card,
					})
					Tiles.label({
						Text = string.format("%d / %d", seen, #all),
						TextSize = Theme.TextSize.Small - 1,
						TextColor3 = if seen == #all then C.Green else C.TextMuted,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.fromOffset(0, 108),
						Size = UDim2.new(1, 0, 0, 18),
						Parent = card,
					})
					Tiles.tap(card, function()
						selectedLine = def.id
						highlight()
						renderDetail()
					end)
				end
			end
		end
		local pct = if totalForms > 0 then seenForms / totalForms else 0
		summary.Text = string.format("Species %d / %d · %s complete", seenLines, totalLines, Format.percent(pct))
		highlight()
		renderDetail()
	end

	local watch = StoreKit.watch(store, { "profile.Monsters.codex", "profile.Breeding.discovered" }, function()
		refresh()
	end)

	return {
		Root = panel.Root,
		Open = function()
			watch.Start()
		end,
		Close = function()
			watch.Stop()
		end,
	}
end

return Codex
