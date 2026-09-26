--[[
	Wardrobe screen (update 1.5 · Showtime): dress a monster up in accessories.

	Left: a live 3D preview of the monster (ViewportMonster, accessories included) and a
	"Pick a monster" button (Monsters pick mode). Middle: the four slots with what is worn
	(Take off → Accessories.Unequip); tapping a slot filters the list. Right: Owned
	(Wear → Accessories.Equip) and Shop (Buy → Accessories.Buy, gems or Contest Ribbons).

	Open with { id = monsterId } (MonsterDetail's Style button, the Showtime screen).
	Reads: profile.Accessories.owned, profile.Monsters.list, profile.Currency (gems, ribbons),
	profile.Progression.level.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Sheet = require(UI.Art.Sheet)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local Icon = require(UI.Components.Icon)
local ViewportMonster = require(UI.Components.ViewportMonster)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Acc = Config.Accessories

return {
	Name = "Wardrobe",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Wardrobe",
			Color = C.Pink,
			Size = UDim2.fromOffset(1000, 500),
			OnClose = function()
				ctx.Router:Close("Wardrobe")
			end,
		})
		local gemPill = Widgets.Pill({ Icon = "gem", Text = "0", Parent = panel.HeaderRight })
		gemPill.Root.LayoutOrder = 1
		local ribbonPill = Widgets.Pill({ Icon = "ribbon", Text = "0", Parent = panel.HeaderRight })
		-- Update 3.0: player-made accessories.
		Button.new({
			Name = "OpenWorkshop",
			Text = "Workshop",
			Color = C.Purple,
			TextSize = Theme.TextSize.Small,
			Size = UDim2.fromOffset(140, 40),
			LayoutOrder = -1,
			Parent = panel.HeaderRight,
			OnClick = function()
				ctx.Router:Open("Workshop")
			end,
		})
		ribbonPill.Root.LayoutOrder = 2

		local isOpen = false
		local bag = Util.bag()
		local refresh
		local currentId: string? = nil
		local slot = "head"
		local tab = "owned"

		local function monster()
			local m = currentId and Util.monsters(ctx)[currentId]
			return if type(m) == "table" then m else nil
		end
		local function owned(): { [string]: number }
			local o = ctx.Store:Get("profile.Accessories.owned")
			return if type(o) == "table" then o else {}
		end

		-- Left: preview -----------------------------------------------------------------------
		local left = Util.card({ Size = UDim2.new(0, 280, 1, 0), Parent = panel.Body })
		local preview = ViewportMonster.new({
			Name = "Preview",
			Size = UDim2.new(1, -16, 1, -80),
			Position = UDim2.fromOffset(8, 8),
			Spin = 0.5,
			Parent = left,
		})
		local pickButton = Button.new({
			Name = "PickMonster",
			Text = "Pick a monster",
			Color = C.Blue,
			TextSize = Theme.TextSize.Small,
			Size = UDim2.new(1, -16, 0, 52),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Parent = left,
		})

		-- Middle: slots -----------------------------------------------------------------------
		local slotsCard =
			Util.card({ Title = "Wearing", Position = UDim2.fromOffset(290, 0), Size = UDim2.new(0, 250, 1, 0), Parent = panel.Body })
		local slotList =
			Widgets.List({ Position = UDim2.fromOffset(6, 38), Size = UDim2.new(1, -12, 1, -44), Padding = 6, Parent = slotsCard })

		-- Right: owned / shop -----------------------------------------------------------------
		local right = Util.card({ Position = UDim2.fromOffset(550, 0), Size = UDim2.new(1, -550, 1, 0), Parent = panel.Body })
		Widgets.Tabs({
			Tabs = { { id = "owned", text = "Owned" }, { id = "shop", text = "Shop" } },
			Selected = tab,
			Size = UDim2.new(1, -16, 0, 40),
			Position = UDim2.fromOffset(8, 8),
			Parent = right,
			OnChanged = function(id)
				tab = id
				refresh()
			end,
		})
		local grid = Widgets.Scroll({
			Cell = Vector2.new(126, 150),
			Padding = 6,
			Position = UDim2.fromOffset(6, 54),
			Size = UDim2.new(1, -12, 1, -60),
			Parent = right,
		})

		pickButton:SetOnClick(function()
			Util.pick(ctx, {
				title = "Pick a monster to dress up",
				max = 1,
				filter = function(m)
					return m.busy ~= "trade"
				end,
				returnTo = "Wardrobe",
				onPick = function(ids)
					currentId = ids[1]
					refresh()
				end,
			})
		end)

		local function priceButton(def, parent)
			local key, amount = next(def.price)
			local b = Button.new({
				Name = "Buy",
				Text = Format.short(amount),
				Icon = Icon.new(StoreKit.iconFor(key), 20),
				Color = C.Orange,
				TextSize = Theme.TextSize.Small,
				Size = UDim2.new(1, -12, 0, 38),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -6),
				Disabled = StoreKit.balance(ctx.Store, key) < amount,
				Parent = parent,
			})
			b:SetOnClick(function()
				local ok = Util.requestOnce(ctx, "Accessories.Buy", { accessory = def.id })
				if ok then
					ctx:Toast(def.name .. " is yours!", "success")
				end
			end)
		end

		local function accessoryCard(def, order: number)
			local card = New("Frame", {
				Name = "Acc_" .. def.id,
				BackgroundColor3 = C.PanelDeep,
				LayoutOrder = order,
				Parent = grid,
			}, { Create.Corner(10) })
			local art = Sheet.icon("acc_" .. def.id, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 4),
				Size = UDim2.fromOffset(50, 50),
				Parent = card,
			})
			if not art then
				New("Frame", {
					BackgroundColor3 = Color3.fromHex(def.color),
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 8),
					Size = UDim2.fromOffset(44, 44),
					Parent = card,
				}, { Create.Round(), Create.Stroke(3, Color3.fromHex(def.color2 or def.color)) })
			end
			Util.text({
				Text = def.name,
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Small,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(4, 54),
				Size = UDim2.new(1, -8, 0, 36),
				Parent = card,
			})
			return card
		end

		local function drawSlots(m)
			Util.clear(slotList)
			for i, s in Acc.Slots do
				local worn = m and type(m.acc) == "table" and m.acc[s] or nil
				local def = worn and Acc.Resolve(worn)
				if def and def.ugc then
					local copy = StoreKit.tbl(ctx.Store, "profile.Workshop.copies")[def.design]
					if type(copy) == "table" and type(copy.name) == "string" then
						def = table.clone(def)
						def.name = copy.name
					end
				end
				local row = New("TextButton", {
					Name = "Slot_" .. s,
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = if s == slot then C.Pink else C.PanelDeep,
					Size = UDim2.new(1, -4, 0, 80),
					LayoutOrder = i,
					Parent = slotList,
				}, { Create.Corner(10) })
				row.MouseButton1Click:Connect(function()
					slot = s
					refresh()
				end)
				Util.text({
					Text = Acc.SlotNames[s],
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Small,
					Position = UDim2.fromOffset(10, 4),
					Size = UDim2.new(1, -20, 0, 22),
					Parent = row,
				})
				Util.text({
					Text = if def then def.name else "Empty",
					TextColor3 = if def then C.Text else C.TextMuted,
					TextSize = Theme.TextSize.Small,
					Position = UDim2.fromOffset(10, 28),
					Size = UDim2.new(1, -110, 0, 44),
					Parent = row,
				})
				if def and currentId then
					local id = currentId
					Button.new({
						Name = "TakeOff",
						Text = "Take off",
						Color = C.Gray,
						TextSize = Theme.TextSize.Small,
						Size = UDim2.fromOffset(92, 40),
						AnchorPoint = Vector2.new(1, 1),
						Position = UDim2.new(1, -6, 1, -6),
						Parent = row,
						OnClick = function()
							Util.requestOnce(ctx, "Accessories.Unequip", { id = id, slot = s })
						end,
					})
				end
			end
		end

		local function drawGrid()
			Util.clear(grid)
			local have = owned()
			local order = 0
			for _, def in Acc.List do
				if def.slot == slot then
					local count = have[def.id] or 0
					if tab == "owned" and count > 0 then
						order += 1
						local card = accessoryCard(def, order)
						Util.text({
							Text = "×" .. count,
							TextColor3 = C.TextMuted,
							TextSize = Theme.TextSize.Small,
							Position = UDim2.fromOffset(8, 4),
							Size = UDim2.fromOffset(40, 18),
							Parent = card,
						})
						Button.new({
							Name = "Wear",
							Text = "Wear",
							Color = C.Green,
							TextSize = Theme.TextSize.Small,
							Size = UDim2.new(1, -12, 0, 38),
							AnchorPoint = Vector2.new(0.5, 1),
							Position = UDim2.new(0.5, 0, 1, -6),
							Disabled = currentId == nil,
							Parent = card,
							OnClick = function()
								if not currentId then
									ctx:Toast("Pick a monster first", "info")
									return
								end
								Util.requestOnce(ctx, "Accessories.Equip", { id = currentId, accessory = def.id })
							end,
						})
					elseif tab == "shop" and def.price then
						order += 1
						priceButton(def, accessoryCard(def, order))
					end
				end
			end
			if order == 0 then
				local grid2 = grid:FindFirstChildOfClass("UIGridLayout")
				if grid2 then
					grid2.CellSize = UDim2.fromOffset(380, 80)
				end
				Util.text({
					Text = if tab == "owned"
						then string.format(
							"No spare %s accessories. Get some in the Shop or from Monster Contests!",
							string.lower(Acc.SlotNames[slot])
						)
						else "Nothing for sale in this slot.",
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.fromOffset(380, 80),
					Parent = grid,
				})
			else
				local grid2 = grid:FindFirstChildOfClass("UIGridLayout")
				if grid2 then
					grid2.CellSize = UDim2.fromOffset(126, 150)
				end
			end
		end

		local lockOverlay = nil
		local shownKey = ""
		local function draw()
			if not isOpen then
				return
			end
			gemPill:SetText(Format.short(StoreKit.balance(ctx.Store, "gems")))
			ribbonPill:SetText(Format.short(StoreKit.balance(ctx.Store, "ribbons")))
			local m = monster()
			if currentId and not m then
				currentId = nil
			end
			local ap = Util.appearance(m)
			pickButton:SetText(if ap then ap.name .. " · change" else "Pick a monster")
			-- Rebuild the 3D preview only when the look changes.
			local key = ""
			if ap then
				local parts = { ap.form, tostring(ap.variant) }
				for _, s in Acc.Slots do
					table.insert(parts, if ap.acc then ap.acc[s] or "-" else "-")
				end
				key = table.concat(parts, "|")
			end
			if key ~= shownKey then
				shownKey = key
				if ap then
					preview:SetAppearance(ap)
				else
					preview:Clear()
				end
			end
			drawSlots(m)
			drawGrid()
			if lockOverlay then
				lockOverlay:Destroy()
				lockOverlay = nil
			end
			if not Util.unlocked(ctx, Acc.Unlock) then
				lockOverlay = Util.lockOverlay(panel.Body, Util.unlockText(Acc.Unlock))
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function(params)
				isOpen = true
				if type(params) == "table" and type(params.id) == "string" then
					currentId = params.id
				end
				bag.clean()
				for _, path in { "profile.Accessories", "profile.Monsters.list", "profile.Currency", "profile.Progression.level" } do
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
