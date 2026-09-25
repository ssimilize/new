--[[
	Workshop screen (update 3.0 · Year Two): accessories designed by players.

	Design   pick a shape (its slot comes with it), two palette colours and a name, then
	         Publish (Workshop.Create, SubmitCost ribbons; you get the first copy).
	Gallery  Top / New / Mine (Workshop.Browse → session.Workshop.gallery): Like, Buy a copy
	         (CopyPrice), Report. "Collect" pays your royalties (Workshop.Claim).
	Review   moderators only (3.0.1): designs hidden by reports (Workshop.ModQueue), each with
	         Restore / Remove (Workshop.Moderate).
	Copies   your stored copies (profile.Workshop.copies): Wear → Monsters pick mode →
	         Workshop.Equip. Take them off in the Wardrobe as usual.
	Opened from the Workshop in the hub and from the Wardrobe.

	Reads: profile.Workshop, session.Workshop, profile.Currency.ribbons, profile.Progression.level.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Workshop
local Acc = Config.Accessories

-- Shapes grouped by slot, in catalogue order.
local SHAPES = {}
do
	local seen = {}
	for _, slot in Acc.Slots do
		for _, a in Acc.List do
			if a.slot == slot and Acc.ShapeSlots[a.shape] == slot and not seen[a.shape] then
				seen[a.shape] = true
				table.insert(SHAPES, a.shape)
			end
		end
	end
end

local function shapeLabel(shape: string): string
	local def = Acc.Resolve(Acc.Encode("x", shape, "#FFFFFF", "#FFFFFF"))
	return if def then string.sub(def.name, 8) else shape
end

local function swatch(color: string, color2: string, size: number, parent: Instance)
	return New("Frame", {
		Name = "Swatch",
		BackgroundColor3 = Color3.fromHex(color),
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	}, { Create.Round(), Create.Stroke(math.max(2, size // 12), Color3.fromHex(color2)) })
end

return {
	Name = "Workshop",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Accessory Workshop",
			Color = C.Pink,
			Size = UDim2.fromOffset(1000, 500),
			OnClose = function()
				ctx.Router:Close("Workshop")
			end,
		})
		local ribbonPill = Widgets.Pill({ Icon = "ribbon", Text = "0", Parent = panel.HeaderRight })
		ribbonPill.Root.LayoutOrder = 1

		local isOpen = false
		local bag = Util.bag()
		local refresh
		local tab = "design"
		local draft = { shape = SHAPES[1], color = Cfg.Palette[5], color2 = Cfg.Palette[3], name = "" }
		local reviewing = false -- moderators: the gallery shows the review queue

		Widgets.Tabs({
			Tabs = { { id = "design", text = "Design" }, { id = "gallery", text = "Gallery" }, { id = "copies", text = "My copies" } },
			Selected = tab,
			Parent = panel.Body,
			OnChanged = function(id)
				tab = id
				if id == "gallery" and #(StoreKit.tbl(ctx.Store, "session.Workshop").gallery or {}) == 0 then
					Util.request(ctx, "Workshop.Browse", { tab = "new" })
				end
				refresh()
			end,
		})
		local content = New("Frame", {
			Name = "WorkshopContent",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 52),
			Size = UDim2.new(1, 0, 1, -52),
			Parent = panel.Body,
		})

		-- Design -------------------------------------------------------------------------------
		local function drawDesign()
			local left = Util.card({ Title = "Shape", Size = UDim2.new(0, 470, 1, 0), Parent = content })
			local shapes = Widgets.Scroll({
				Position = UDim2.fromOffset(8, 40),
				Size = UDim2.new(1, -16, 1, -48),
				Cell = Vector2.new(104, 40),
				Padding = 6,
				Parent = left,
			})
			for i, shape in SHAPES do
				Button.new({
					Name = "Shape_" .. shape,
					Text = shapeLabel(shape),
					Color = if draft.shape == shape then C.Orange else C.Gray,
					TextSize = Theme.TextSize.Small - 2,
					Size = UDim2.fromOffset(104, 40),
					LayoutOrder = i,
					Parent = shapes,
					OnClick = function()
						draft.shape = shape
						refresh()
					end,
				})
			end

			local right = Util.card({
				Title = string.format("%s · %s slot", shapeLabel(draft.shape), Acc.SlotNames[Acc.ShapeSlots[draft.shape]]),
				Position = UDim2.fromOffset(480, 0),
				Size = UDim2.new(1, -480, 1, 0),
				Parent = content,
			})
			local preview = swatch(draft.color, draft.color2, 76, right)
			preview.Position = UDim2.fromOffset(16, 44)
			for row, key in { "color", "color2" } do
				local line = New("Frame", {
					Name = if key == "color" then "MainColor" else "TrimColor",
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(104, 40 + (row - 1) * 46),
					Size = UDim2.new(1, -112, 0, 40),
					Parent = right,
				}, { Create.List("x", 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
				for i, hex in Cfg.Palette do
					local b = New("TextButton", {
						Name = "Color" .. i,
						Text = "",
						AutoButtonColor = false,
						BackgroundColor3 = Color3.fromHex(hex),
						Size = UDim2.fromOffset(if draft[key] == hex then 26 else 20, if draft[key] == hex then 26 else 20),
						LayoutOrder = i,
						Parent = line,
					}, { Create.Round(), Create.Stroke(if draft[key] == hex then 3 else 1) })
					b.MouseButton1Click:Connect(function()
						draft[key] = hex
						refresh()
					end)
				end
			end
			local box = New("TextBox", {
				Name = "DesignName",
				Text = draft.name,
				PlaceholderText = "Name your design",
				ClearTextOnFocus = false,
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				TextColor3 = C.Text,
				PlaceholderColor3 = C.TextMuted,
				BackgroundColor3 = C.Card,
				Position = UDim2.fromOffset(16, 150),
				Size = UDim2.new(1, -32, 0, 48),
				Parent = right,
			}, { Create.Corner(Theme.Radius.Button), Create.Stroke(Theme.Stroke.Button), Create.Padding(0, 12, 0, 12) })
			box.FocusLost:Connect(function()
				draft.name = box.Text
			end)
			local made = StoreKit.tbl(ctx.Store, "profile.Workshop.made")
			local left_ = Cfg.PerWeek
			if made.week == Config.Leaderboards.Week(ctx:Now()) then
				left_ = math.max(0, Cfg.PerWeek - (tonumber(made.n) or 0))
			end
			Util.text({
				Text = string.format(
					"Publishing costs %d ribbons (%d left this week). You get the first copy and %d ribbons every time someone buys one.",
					Cfg.SubmitCost.ribbons,
					left_,
					Cfg.Royalty
				),
				TextColor3 = C.TextMuted,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(16, 208),
				Size = UDim2.new(1, -32, 0, 60),
				Parent = right,
			})
			local unlocked = Util.unlocked(ctx, Cfg.Unlock)
			Button.new({
				Name = "Publish",
				Text = if unlocked then string.format("Publish · %d ribbons", Cfg.SubmitCost.ribbons) else Util.unlockText(Cfg.Unlock),
				Color = if unlocked then C.Green else C.Gray,
				Disabled = not unlocked,
				Size = UDim2.fromOffset(320, 58),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -12),
				Parent = right,
				OnClick = function()
					draft.name = box.Text
					local ok = Util.requestOnce(ctx, "Workshop.Create", {
						name = draft.name,
						shape = draft.shape,
						color = draft.color,
						color2 = draft.color2,
					})
					if ok then
						ctx:Toast("Published! Your first copy is in My copies", "success")
						draft.name = ""
						refresh()
					end
				end,
			})
		end

		-- Gallery ------------------------------------------------------------------------------
		local function drawGallery()
			local sess = StoreKit.tbl(ctx.Store, "session.Workshop")
			local bar = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 44),
				Parent = content,
			}, { Create.List("x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
			for i, t in { { "top", "Top" }, { "new", "New" }, { "mine", "Mine" } } do
				Button.new({
					Name = "Gallery_" .. t[1],
					Text = t[2],
					Color = if sess.tab == t[1] and not reviewing then C.Orange else C.Blue,
					TextSize = Theme.TextSize.Small,
					Size = UDim2.fromOffset(120, 40),
					LayoutOrder = i,
					Parent = bar,
					OnClick = function()
						reviewing = false
						Util.requestOnce(ctx, "Workshop.Browse", { tab = t[1] })
						refresh()
					end,
				})
			end
			if sess.moderator == true then
				Button.new({
					Name = "Gallery_review",
					Text = "Review",
					Color = if reviewing then C.Orange else C.Red,
					TextSize = Theme.TextSize.Small,
					Size = UDim2.fromOffset(120, 40),
					LayoutOrder = 4,
					Parent = bar,
					OnClick = function()
						reviewing = true
						Util.requestOnce(ctx, "Workshop.ModQueue")
						refresh()
					end,
				})
			end
			Button.new({
				Name = "ClaimRoyalties",
				Text = "Collect royalties",
				Color = C.Gold,
				TextSize = Theme.TextSize.Small,
				Size = UDim2.fromOffset(220, 40),
				LayoutOrder = 9,
				Parent = bar,
				OnClick = function()
					local ok, res = Util.requestOnce(ctx, "Workshop.Claim")
					if ok and type(res) == "table" then
						ctx:Toast(
							if (res.ribbons or 0) > 0
								then string.format("+%d ribbons from your designs!", res.ribbons)
								else "No royalties yet",
							"info"
						)
					end
				end,
			})
			local grid = Widgets.Scroll({
				Name = "Designs",
				Position = UDim2.fromOffset(0, 52),
				Size = UDim2.new(1, 0, 1, -52),
				Cell = Vector2.new(232, 150),
				Padding = 8,
				Parent = content,
			})
			local gallery = if type(sess.gallery) == "table" then sess.gallery else {}
			if reviewing then
				gallery = if type(sess.queue) == "table" then sess.queue else {}
			end
			if #gallery == 0 then
				Util.text({
					Text = if reviewing then "Nothing to review." else "Nothing here yet. Design something!",
					TextColor3 = C.TextMuted,
					Size = UDim2.fromOffset(400, 40),
					Parent = grid,
				})
			end
			for i, d in gallery do
				local card = New("Frame", {
					Name = "Design_" .. tostring(d.id),
					BackgroundColor3 = if d.mine then C.Gold else C.PanelDeep,
					LayoutOrder = i,
					Parent = grid,
				}, { Create.Corner(10) })
				local sw = swatch(d.color or "#FFFFFF", d.color2 or "#FFFFFF", 48, card)
				sw.Position = UDim2.fromOffset(10, 10)
				Util.text({
					Text = tostring(d.name),
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Small,
					Position = UDim2.fromOffset(66, 8),
					Size = UDim2.new(1, -74, 0, 22),
					Parent = card,
				})
				Util.text({
					Text = string.format(
						"%s · by %s\n♥ %d · %d copies",
						shapeLabel(d.shape or ""),
						tostring(d.creatorName),
						d.likes or 0,
						d.copies or 0
					),
					TextColor3 = C.TextMuted,
					TextSize = Theme.TextSize.Small - 2,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					Position = UDim2.fromOffset(66, 30),
					Size = UDim2.new(1, -74, 0, 44),
					Parent = card,
				})
				local row = New("Frame", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 8, 1, -8),
					Size = UDim2.new(1, -16, 0, 40),
					Parent = card,
				}, { Create.List("x", 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
				if reviewing then
					for j, verdict in { { "restore", "Restore", C.Green }, { "remove", "Remove", C.Red } } do
						Button.new({
							Name = "Mod_" .. verdict[1],
							Text = verdict[2],
							Color = verdict[3],
							TextSize = Theme.TextSize.Small - 2,
							Size = UDim2.fromOffset(100, 38),
							LayoutOrder = j,
							Parent = row,
							OnClick = function()
								Util.requestOnce(ctx, "Workshop.Moderate", { design = d.id, verdict = verdict[1] })
							end,
						})
					end
					Util.text({
						Text = string.format("%d reports", d.reports or 0),
						TextColor3 = C.Red,
						TextSize = Theme.TextSize.Small - 2,
						Size = UDim2.fromOffset(80, 38),
						LayoutOrder = 3,
						Parent = row,
					})
					continue
				end
				Button.new({
					Name = "Like",
					Text = "♥",
					Color = if d.liked then C.Gray else C.Pink,
					Disabled = d.liked == true,
					TextSize = Theme.TextSize.Small,
					Size = UDim2.fromOffset(48, 38),
					LayoutOrder = 1,
					Parent = row,
					OnClick = function()
						Util.requestOnce(ctx, "Workshop.Like", { design = d.id })
					end,
				})
				Button.new({
					Name = "BuyCopy",
					Text = string.format("Buy %d", Cfg.CopyPrice.ribbons),
					Color = C.Green,
					TextSize = Theme.TextSize.Small - 2,
					Size = UDim2.fromOffset(100, 38),
					LayoutOrder = 2,
					Parent = row,
					OnClick = function()
						local ok = Util.requestOnce(ctx, "Workshop.Buy", { design = d.id })
						if ok then
							ctx:Toast(tostring(d.name) .. " is in My copies", "success")
						end
					end,
				})
				if not d.mine then
					Button.new({
						Name = "Report",
						Text = "!",
						Color = C.Gray,
						TextSize = Theme.TextSize.Small,
						Size = UDim2.fromOffset(40, 38),
						LayoutOrder = 3,
						Parent = row,
						OnClick = function()
							local ok = Util.requestOnce(ctx, "Workshop.Report", { design = d.id })
							if ok then
								ctx:Toast("Thanks. Our moderators will take a look", "info")
							end
						end,
					})
				end
			end
		end

		-- Copies -------------------------------------------------------------------------------
		local function drawCopies()
			local copies = StoreKit.tbl(ctx.Store, "profile.Workshop.copies")
			local ids = {}
			for id, copy in copies do
				if type(copy) == "table" and (tonumber(copy.n) or 0) > 0 then
					table.insert(ids, id)
				end
			end
			table.sort(ids)
			local list = Widgets.List({ Name = "Copies", Size = UDim2.fromScale(1, 1), Padding = 8, Parent = content })
			if #ids == 0 then
				Util.text({
					Text = "No spare copies. Buy some in the Gallery or publish your own!",
					TextColor3 = C.TextMuted,
					Size = UDim2.new(1, 0, 0, 40),
					Parent = list,
				})
			end
			for i, id in ids do
				local copy = copies[id]
				local row = New("Frame", {
					Name = "Copy_" .. id,
					BackgroundColor3 = C.PanelDeep,
					Size = UDim2.new(1, -6, 0, 70),
					LayoutOrder = i,
					Parent = list,
				}, { Create.Corner(10) })
				local sw = swatch(copy.color or "#FFFFFF", copy.color2 or "#FFFFFF", 50, row)
				sw.Position = UDim2.fromOffset(10, 10)
				Util.text({
					Text = string.format(
						"%s ×%d\n%s · %s slot",
						tostring(copy.name),
						copy.n,
						shapeLabel(copy.shape or ""),
						Acc.SlotNames[copy.slot] or "?"
					),
					TextWrapped = true,
					Position = UDim2.fromOffset(72, 6),
					Size = UDim2.new(1, -260, 1, -12),
					Parent = row,
				})
				Button.new({
					Name = "Wear",
					Text = "Wear",
					Color = C.Green,
					TextSize = Theme.TextSize.Small,
					Size = UDim2.fromOffset(150, 48),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Parent = row,
					OnClick = function()
						Util.pick(ctx, {
							title = "Who wears " .. tostring(copy.name) .. "?",
							max = 1,
							filter = function(m)
								return m.busy ~= "trade"
							end,
							returnTo = "Workshop",
							onPick = function(picked)
								local ok = Util.requestOnce(ctx, "Workshop.Equip", { id = picked[1], design = id })
								if ok then
									ctx:Toast(tostring(copy.name) .. " looks great!", "success")
								end
							end,
						})
					end,
				})
			end
		end

		local function draw()
			if not isOpen then
				return
			end
			ribbonPill:SetText(tostring(StoreKit.balance(ctx.Store, "ribbons")))
			Util.clear(content)
			if tab == "gallery" then
				drawGallery()
			elseif tab == "copies" then
				drawCopies()
			else
				drawDesign()
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in { "profile.Workshop", "session.Workshop", "profile.Currency.ribbons", "profile.Progression.level" } do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				refresh()
			end,
			Close = function()
				isOpen = false
				bag.clean()
			end,
		}
	end,
}
