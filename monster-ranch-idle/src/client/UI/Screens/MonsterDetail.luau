--[[
	MonsterDetail (C2): one monster (mock-detail). Params: { id }.

	  header   name · form, rarity / variant / stars chips, rename (Monsters.Rename),
	           lock toggle (Monsters.SetLocked)
	  left     rotating 3D portrait (ViewportMonster), element + mutation chips, stage,
	           weight (+ HUGE), mood, base coin rate, busy state
	  middle   level bar (lv / Formulas.LevelCap), stat bars (Formulas.Stats; bars show how far
	           each stat is from its value at this stage's level cap), power, traits (hidden
	           trait is "???" until Adult), Feed (flavour picker with owned food), Level up ×1 /
	           ×N (Economy.LevelCost), Grow (Formulas.CanGrow reason) or grow countdown
	  right    diet meter for this stage, evolution path with branches
	           (Species.AdultForDiet predicts the adult), Star Up (Monsters pick mode filtered
	           to the same line + rarity, then a confirm), Sell (confirm)
	Every number comes from Logic/Formulas and Config; nothing is stored.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local Appearance = require(Shared.Logic.Appearance)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Icon = require(UI.Components.Icon)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)
local Tiles = require(UI.Components.Tiles)
local StatBar = require(UI.Components.StatBar)
local InsetPopup = require(UI.Components.InsetPopup)
local ViewportMonster = require(UI.Components.ViewportMonster)
local MasteryBadge = require(script.Parent.Parts.MasteryBadge)
local WalkToggle = require(script.Parent.Parts.WalkToggle) -- glow-up T
local BondBadge = require(script.Parent.Parts.BondBadge)
local ShowpieceChips = require(script.Parent.Parts.ShowpieceChips) -- glow-up W

local New = Create.New
local C = Theme.Colors

local MonsterDetail = { Name = "MonsterDetail" }

local STATS = {
	{ key = "hp", label = "HP", color = C.Green },
	{ key = "atk", label = "ATK", color = Color3.fromHex("#E85F33") },
	{ key = "def", label = "DEF", color = Color3.fromHex("#94775A") },
	{ key = "spd", label = "SPD", color = Color3.fromHex("#F2C14E") },
	{ key = "luck", label = "Luck", color = C.Purple },
}
local BUSY_TEXT = {
	expedition = "Away on an expedition",
	breeding = "In the Breeding Barn",
	trade = "Offered in a trade",
}

local function capitalize(s: string): string
	return (string.gsub(s, "^%l", string.upper))
end

local function levelCost(m, times: number): ({ coins: number, treats: number }, number)
	local cap = Formulas.LevelCap(m)
	local lv = m.lv or 1
	local n = math.min(times, cap - lv)
	local coins, treats = 0, 0
	for i = 0, n - 1 do
		local c = Config.Economy.LevelCost(lv + i)
		coins += c.coins
		treats += c.treats
	end
	return { coins = coins, treats = treats }, math.max(0, n)
end

local function silhouetteOf(ap, size: number): Frame
	local icon = MonsterIcon.new(ap, size)
	for _, d in icon:GetDescendants() do
		if d:IsA("Frame") then
			d.BackgroundColor3 = Color3.fromHex("#3B3350")
		end
	end
	return icon
end

function MonsterDetail.Build(ctx)
	local store = ctx.Store
	local currentId: string? = nil
	local lastApSig = ""
	local stopGrow: (() -> ())? = nil

	local panel = Panel.new({
		Title = "Monster",
		Color = C.Purple,
		Size = UDim2.fromOffset(980, 490),
		OnClose = function()
			ctx.Router:Close("MonsterDetail")
		end,
	})
	local headerChips =
		Tiles.row({ AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 44), LayoutOrder = 1, Parent = panel.HeaderRight }, 6)
	local renameButton = Button.new({
		Text = "✎",
		Color = C.Blue,
		Size = UDim2.fromOffset(44, 44),
		TextSize = 22,
		LayoutOrder = 2,
		Parent = panel.HeaderRight,
	})
	local lockButton = Button.new({
		Text = "Lock",
		Color = C.Gray,
		Size = UDim2.fromOffset(84, 44),
		TextSize = 18,
		LayoutOrder = 3,
		Parent = panel.HeaderRight,
	})

	-- Update 1.5: dress this monster up in the Wardrobe.
	local styleButton = Button.new({
		Name = "Style",
		Text = "Style",
		Color = C.Pink,
		Size = UDim2.fromOffset(84, 44),
		TextSize = 18,
		LayoutOrder = 4,
		Parent = panel.HeaderRight,
	})

	-- Update 2.0: ride an Adult around the world (Riding.Mount / Riding.Dismount).
	local rideButton = Button.new({
		Name = "Ride",
		Text = "Ride",
		Color = C.Green,
		Size = UDim2.fromOffset(84, 44),
		TextSize = 18,
		LayoutOrder = 5,
		Parent = panel.HeaderRight,
	})

	-- Left: portrait ----------------------------------------------------------------
	local portrait = New("Frame", {
		Name = "Portrait",
		BackgroundColor3 = C.White, -- tinted by the element gradient below
		Size = UDim2.fromOffset(290, 300),
		ClipsDescendants = true,
		Parent = panel.Body,
	}, { Create.Corner(Theme.Radius.Card), Create.Stroke(Theme.Stroke.Card) })
	local portraitGradient = Instance.new("UIGradient")
	portraitGradient.Rotation = 90
	portraitGradient.Parent = portrait
	local vm = ViewportMonster.new({
		Size = UDim2.new(1, 0, 1, -30),
		Position = UDim2.fromOffset(0, 16),
		Spin = 0.5,
		ZIndex = 2,
		Parent = portrait,
	})
	local portraitChips =
		Tiles.row({ Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 26), ZIndex = 5, Parent = portrait }, 6)
	local portraitFoot = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Small + 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -6),
		Size = UDim2.new(1, -20, 0, 22),
		ZIndex = 5,
		Parent = portrait,
	})
	local portraitMood = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Small + 1,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -6),
		Size = UDim2.new(1, -20, 0, 22),
		ZIndex = 5,
		Parent = portrait,
	})
	local walkToggle = WalkToggle.new(ctx, portrait) -- glow-up T: "Walk with me"
	local leftInfo = Tiles.col({ Position = UDim2.fromOffset(4, 308), Size = UDim2.fromOffset(282, 92), Parent = panel.Body }, 2)
	local rateLabel =
		Tiles.label({ Text = "", TextSize = Theme.TextSize.Body, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = leftInfo })
	local powerLabel =
		Tiles.label({ Text = "", TextSize = Theme.TextSize.Body, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 2, Parent = leftInfo })
	local busyLabel = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Body,
		TextColor3 = C.Red,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 3,
		Parent = leftInfo,
	})

	-- Middle: level, stats, traits, actions -------------------------------------------
	local middle = Tiles.col({ Position = UDim2.fromOffset(306, 0), Size = UDim2.fromOffset(340, 400), Parent = panel.Body }, 6)
	local levelRow = Tiles.frame({ Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = middle })
	local levelLabel = Tiles.label({ Text = "", TextSize = Theme.TextSize.Body + 1, Size = UDim2.fromScale(0.6, 1), Parent = levelRow })
	local starsLabel = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Body,
		TextColor3 = C.Orange,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.4, 1),
		Parent = levelRow,
	})
	local levelBar = Widgets.Bar({ Color = C.Blue, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 2, Parent = middle })
	local statRows = {}
	for i, s in STATS do
		statRows[s.key] = StatBar.new({
			Label = s.label,
			Color = s.color,
			LabelWidth = 48,
			ValueWidth = 64,
			Height = 24,
			LayoutOrder = 2 + i,
			Parent = middle,
		})
	end
	local traitsRow = Tiles.row({ Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 10, Parent = middle }, 6)
	local actionRow = Tiles.row({ Size = UDim2.new(1, 0, 0, 54), LayoutOrder = 11, Parent = middle }, 8)
	local feedButton = Button.new({
		Text = "Feed",
		Color = C.Orange,
		Size = UDim2.fromOffset(96, 52),
		Icon = Icon.new("food", 22),
		LayoutOrder = 1,
		Parent = actionRow,
	})
	local lvOneCost = Tiles.frame({ AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24) })
	local lvOne = Button.new({
		Text = "Lv up",
		Color = C.Green,
		Size = UDim2.fromOffset(136, 52),
		TextSize = 18,
		Icon = lvOneCost,
		LayoutOrder = 2,
		Parent = actionRow,
	})
	lvOneCost.LayoutOrder = 3
	local lvTen =
		Button.new({ Text = "×10", Color = C.Green, Size = UDim2.fromOffset(92, 52), TextSize = 18, LayoutOrder = 3, Parent = actionRow })
	local costLabel = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 12,
		Parent = middle,
	})
	local growRow = Tiles.row({ Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 13, Parent = middle }, 8)
	local growButton =
		Button.new({ Text = "Grow up!", Color = C.Blue, Size = UDim2.fromOffset(170, 50), LayoutOrder = 1, Parent = growRow })
	local growReason = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(1, -180, 1, 0),
		LayoutOrder = 2,
		Parent = growRow,
	})

	-- Right: diet + evolution ----------------------------------------------------------
	local right = Tiles.card({ Position = UDim2.fromOffset(662, 0), Size = UDim2.fromOffset(282, 400), Parent = panel.Body })
	local rightCol = Tiles.col({ Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 1, -74), Parent = right }, 4)
	local dietTitle = Tiles.label({
		Text = "Diet this stage",
		TextSize = Theme.TextSize.Body,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 1,
		Parent = rightCol,
	})
	local dietRows = {}
	for i, flavor in Config.Food.List do
		dietRows[flavor.id] = StatBar.new({
			Label = capitalize(flavor.id),
			Color = Theme.Food(flavor.id),
			LabelWidth = 58,
			ValueWidth = 30,
			Height = 20,
			LayoutOrder = 1 + i,
			Parent = rightCol,
		})
	end
	Tiles.label({
		Text = "Evolution path",
		TextSize = Theme.TextSize.Body,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 10,
		Parent = rightCol,
	})
	local evoFrame = Tiles.frame({ Size = UDim2.new(1, 0, 0, 122), LayoutOrder = 11, Parent = rightCol })
	local evoText = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = 12,
		Parent = rightCol,
	})
	local rightButtons = Tiles.row({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0, 52),
		Parent = right,
	}, 8, Enum.HorizontalAlignment.Center)
	local starButton = Button.new({
		Text = "★ Star up",
		Color = C.Gold,
		TextSize = 18,
		Size = UDim2.fromOffset(140, 50),
		LayoutOrder = 1,
		Parent = rightButtons,
	})
	local sellButton = Button.new({
		Text = "Sell",
		Color = C.Red,
		TextSize = 18,
		Size = UDim2.fromOffset(110, 50),
		LayoutOrder = 2,
		Parent = rightButtons,
	})

	local popup = InsetPopup.new({ Parent = panel.Card, Title = "", Size = UDim2.fromOffset(460, 330) })

	-- Helpers -------------------------------------------------------------------------

	local function monster()
		return StoreKit.monster(store, currentId)
	end

	local refresh

	local function openFeed()
		local m = monster()
		if not m then
			return
		end
		popup:SetTitle("Feed " .. Formulas.DisplayName(m))
		popup:SetSize(UDim2.fromOffset(470, 340))
		local function render()
			local mm = monster()
			if not mm then
				popup:Hide()
				return
			end
			Tiles.clear(popup.Body)
			local list = Tiles.col({ Size = UDim2.fromScale(1, 1), Parent = popup.Body }, 6)
			local branching = mm.stage == 2 and Config.Species.IsBranching(mm.line)
			for i, flavor in Config.Food.List do
				local owned = StoreKit.balance(store, "food." .. flavor.id)
				local row = Tiles.frame({ Size = UDim2.new(1, 0, 0, 52), LayoutOrder = i, Parent = list })
				New("Frame", {
					BackgroundColor3 = Theme.Food(flavor.id),
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 0, 0.5, 0),
					Size = UDim2.fromOffset(28, 28),
					Parent = row,
				}, { Create.Round(), Create.Stroke(2) })
				local hint = ""
				if branching then
					for _, adult in Config.Species.ById[mm.line].forms[3] do
						if adult.diet == flavor.id then
							hint = " → " .. adult.name
						end
					end
				end
				Tiles.label({
					Text = string.format("%s ×%s%s", flavor.name, Format.short(owned), hint),
					TextSize = Theme.TextSize.Body,
					Position = UDim2.fromOffset(38, 0),
					Size = UDim2.new(1, -150, 1, 0),
					Parent = row,
				})
				local b = Button.new({
					Text = "Feed",
					Color = C.Orange,
					Size = UDim2.fromOffset(100, 46),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Parent = row,
					OnClick = function()
						local ok = StoreKit.request(ctx, "Monsters.Feed", { id = currentId, flavor = flavor.id, amount = 1 })
						if ok then
							ctx:Sound("Eat")
							render()
						end
					end,
				})
				b:SetDisabled(owned <= 0)
			end
			Button.new({
				Text = "Get more food",
				Color = C.Blue,
				Size = UDim2.fromOffset(200, 44),
				LayoutOrder = 10,
				Parent = list,
				OnClick = function()
					popup:Hide()
					if ctx.Router:Has("Store") then
						ctx.Router:Open("Store", { tab = "food" })
					else
						ctx:Toast("Coming soon", "info")
					end
				end,
			})
		end
		render()
		popup:Show()
	end

	local function confirm(title: string, text: string, actionText: string, color: Color3, fn: () -> ())
		popup:SetTitle(title)
		popup:SetSize(UDim2.fromOffset(460, 250))
		Tiles.clear(popup.Body)
		Tiles.label({
			Text = text,
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 90),
			Parent = popup.Body,
		})
		local row = Tiles.row(
			{ Position = UDim2.fromOffset(0, 110), Size = UDim2.new(1, 0, 0, 56), Parent = popup.Body },
			12,
			Enum.HorizontalAlignment.Center
		)
		Button.new({
			Text = "Cancel",
			Color = C.Gray,
			Size = UDim2.fromOffset(140, 50),
			LayoutOrder = 1,
			Parent = row,
			OnClick = function()
				popup:Hide()
			end,
		})
		Button.new({
			Text = actionText,
			Color = color,
			Size = UDim2.fromOffset(180, 52),
			LayoutOrder = 2,
			Parent = row,
			OnClick = function()
				popup:Hide()
				fn()
			end,
		})
		popup:Show()
	end

	local function openRename()
		local m = monster()
		if not m then
			return
		end
		popup:SetTitle("Rename")
		popup:SetSize(UDim2.fromOffset(460, 230))
		Tiles.clear(popup.Body)
		local box = New("TextBox", {
			Text = m.name or "",
			PlaceholderText = Formulas.FormName(m),
			ClearTextOnFocus = false,
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Button,
			TextColor3 = C.Text,
			PlaceholderColor3 = C.TextMuted,
			BackgroundColor3 = C.Card,
			Size = UDim2.new(1, 0, 0, 50),
			Parent = popup.Body,
		}, { Create.Corner(Theme.Radius.Button), Create.Stroke(Theme.Stroke.Button) })
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if #box.Text > 20 then
				box.Text = StoreKit.clip(box.Text, 20)
			end
		end)
		Button.new({
			Text = "Save",
			Color = C.Green,
			Size = UDim2.fromOffset(160, 50),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 70),
			Parent = popup.Body,
			OnClick = function()
				local text = string.gsub(box.Text, "^%s+", "")
				text = string.gsub(text, "%s+$", "")
				local ok = StoreKit.request(ctx, "Monsters.Rename", { id = currentId, name = text })
				if ok then
					popup:Hide()
				end
			end,
		})
		popup:Show()
	end

	local function startStarUp()
		local m = monster()
		if not m then
			return
		end
		local id = currentId
		local line, rarity = m.line, m.rarity
		local name = Formulas.DisplayName(m)
		ctx.Router:Open("Monsters", {
			pick = {
				title = string.format("Pick a %s %s to fuse", Theme.RarityName(rarity), Formulas.FormName({ line = line, stage = 1 })),
				max = 1,
				filter = function(other)
					return other.id ~= id and other.line == line and other.rarity == rarity and not other.busy and not other.locked
				end,
				returnTo = "MonsterDetail",
				returnParams = { id = id },
				onPick = function(ids)
					local fodder = StoreKit.monster(store, ids[1])
					local fodderName = if fodder then Formulas.DisplayName(fodder) else "that monster"
					confirm(
						"Star up",
						string.format("Fuse %s into %s? %s will be gone for good.", fodderName, name, fodderName),
						"Fuse ★",
						C.Orange,
						function()
							local ok, res = StoreKit.request(ctx, "Monsters.StarUp", { id = id, fodder = ids[1] })
							if ok then
								local kit = ctx:GetController("Celebrate")
								if kit then
									kit:Slam(starsLabel, C.Orange) -- plays StarUp
									kit:Play("medium")
								else
									ctx:Sound("StarUp")
								end
								ctx.Bus:Publish("Vfx.Burst", "monsterStarUp", { id = id }) -- World: in the pen once this screen closes
								ctx:Toast(
									string.format("%s is now ★%d!", name, type(res) == "table" and tonumber(res.stars) or 0),
									"success"
								)
							end
						end
					)
				end,
			},
		})
	end

	-- Render ----------------------------------------------------------------------------

	local function renderEvolution(m)
		Tiles.clear(evoFrame)
		local def = Config.Species.ById[m.line]
		local codex = StoreKit.asTable(StoreKit.tbl(store, "profile.Monsters.codex")[m.line])
		local forms = StoreKit.asTable(codex.forms)
		local predicted = if m.stage == 2 then Config.Species.AdultForDiet(m.line, m.meals) else nil
		local function node(stage: number, form, x: number, y: number, size: number)
			local current = (m.stage == stage and (stage < 3 or m.form == form.id))
			local seen = forms[form.id] or current or stage <= m.stage
			local holder = New("Frame", {
				BackgroundColor3 = if current then Color3.fromHex("#FFF1C7") else C.Card,
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(size, size),
				Parent = evoFrame,
			}, {
				Create.Corner(10),
				Create.Stroke(
					if current or (predicted and predicted.id == form.id) then 3 else 1.5,
					if current then C.Gold elseif predicted and predicted.id == form.id then C.Green else C.Line
				),
			})
			local ap = Appearance.Preview(m.line, stage, form.id, m.rarity, m.variant)
			local icon = if seen then MonsterIcon.new(ap, size - 8) else silhouetteOf(ap, size - 8)
			icon.Position = UDim2.fromOffset(4, 4)
			icon.Parent = holder
			if stage == 3 and predicted and predicted.id ~= form.id then
				holder.BackgroundTransparency = 0.4
			end
		end
		local function arrow(x: number, y: number)
			Tiles.label({
				Text = "›",
				TextSize = 26,
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(16, 30),
				Parent = evoFrame,
			})
		end
		node(1, def.forms[1], 0, 34, 56)
		arrow(58, 46)
		node(2, def.forms[2], 76, 30, 64)
		local adults = def.forms[3]
		if #adults == 1 then
			arrow(142, 46)
			node(3, adults[1], 162, 22, 76)
		else
			for i, adult in adults do
				local y = if #adults == 2 then (i - 1) * 62 else (i - 1) * 42
				arrow(142, y + 14)
				node(3, adult, 162, y, if #adults == 2 then 58 else 40)
			end
		end
		local parts = {}
		if #adults > 1 then
			for _, adult in adults do
				local name = if forms[adult.id] or (m.stage == 3 and m.form == adult.id) then adult.name else "???"
				table.insert(parts, string.format("%s → %s", capitalize(adult.diet or "any"), name))
			end
			evoText.Text = table.concat(parts, " · ")
				.. (if predicted then "\nHeading for: " .. (if forms[predicted.id] then predicted.name else "???") else "")
		else
			evoText.Text = if m.stage == 3 then "Fully grown" else "Grows into " .. (if forms[adults[1].id] then adults[1].name else "???")
		end
	end

	function refresh()
		local m = monster()
		if not m then
			if currentId and ctx.Router:IsOpen("MonsterDetail") then
				currentId = nil
				ctx.Router:Close("MonsterDetail")
			end
			return
		end
		local now = ctx:Now()
		local rarity = m.rarity or 1
		local stage = m.stage or 1
		local def = Config.Species.ById[m.line]
		local element = def.elements[1]

		-- Header
		panel:SetTitle(string.format("%s · %s", Formulas.DisplayName(m), Formulas.FormName(m)))
		panel:SetColor(Theme.Rarity(rarity))
		Tiles.clear(headerChips)
		Widgets.RarityChip(rarity, headerChips).LayoutOrder = 1
		local vchip = Widgets.VariantChip(m.variant or 0, headerChips)
		if vchip then
			vchip.LayoutOrder = 2
		end
		MasteryBadge.chip(ctx, m.line, headerChips, 3) -- 3.3: the line's mastery tier
		BondBadge.chip(ctx, currentId, headerChips, 4) -- glow-up Q: bond hearts
		ShowpieceChips.add(m, headerChips, 5) -- glow-up W: TITANIC, #37/500
		lockButton:SetText(if m.locked then "Locked" else "Lock")
		local ridingId = StoreKit.tbl(store, "session.Riding").mount
		rideButton:SetText(if ridingId == currentId then "Get off" else "Ride")
		rideButton:SetVisible(m.stage == 3)
		walkToggle:Refresh(currentId, m)
		lockButton:SetColor(if m.locked then C.Orange else C.Gray)

		-- Portrait
		local apSig = table.concat({
			m.form,
			stage,
			m.variant or 0,
			table.concat(StoreKit.asTable(m.muts), ","),
			m.weight or 0,
			if m.titanic == true then "T" else "",
		}, "|")
		if apSig ~= lastApSig then
			lastApSig = apSig
			local ok, ap = pcall(Appearance.Of, m)
			if ok then
				vm:SetAppearance(ap)
			end
		end
		portraitGradient.Color = ColorSequence.new(Theme.ElementLight(element), Theme.Element(element))
		Tiles.clear(portraitChips)
		for i, el in def.elements do
			Widgets.ElementChip(el, portraitChips).LayoutOrder = i
		end
		for i, mut in StoreKit.asTable(m.muts) do
			Widgets.MutationChip(mut, portraitChips).LayoutOrder = 5 + i
		end
		local sizeTag = ShowpieceChips.sizeTag(m)
		portraitFoot.Text = string.format(
			"%s · %s%s",
			Config.Economy.Stages[stage].name,
			Format.weight(tonumber(m.weight) or def.weight),
			if sizeTag == "TITANIC" then " · TITANIC" elseif sizeTag == "HUGE" then " · HUGE" else ""
		)
		portraitMood.Text = string.format("Mood %d", math.floor(tonumber(m.mood) or Config.Economy.Mood.start))
		rateLabel.Text = string.format("Base income %s coins/s", Format.short(math.floor(Formulas.CoinRate(m) * 10 + 0.5) / 10))
		local stats = Formulas.Stats(m)
		local power = Formulas.Power(stats)
		powerLabel.Text = string.format("Power %s · Sells for %s", Format.commas(power), Format.short(Formulas.SellPrice(m)))
		busyLabel.Text = if m.busy
			then (BUSY_TEXT[m.busy] or "Busy")
			else (if m.loc == "pen" then "Working in Pen " .. tostring(m.pen or "?") else "Resting in the barn")
		busyLabel.TextColor3 = if m.busy then C.Red else C.TextMuted

		-- Level + stats
		local cap = Formulas.LevelCap(m)
		local lv = m.lv or 1
		levelLabel.Text = string.format("Level %d / %d", lv, cap)
		starsLabel.Text = string.rep("★", m.stars or 1) .. string.rep("☆", math.max(0, Formulas.MaxStars(m) - (m.stars or 1)))
		levelBar:SetValue(lv / math.max(1, cap), true)
		local capped = table.clone(m)
		capped.lv = cap
		local maxStats = Formulas.Stats(capped)
		for _, s in STATS do
			local v = stats[s.key] or 0
			statRows[s.key]:Set(v / math.max(1, maxStats[s.key] or v), Format.commas(v), true)
		end

		-- Traits
		Tiles.clear(traitsRow)
		for i, tid in StoreKit.asTable(m.traits) do
			local t = Config.Traits.ById[tid]
			if t then
				local chip =
					Widgets.Chip({ Text = t.name, Color = C.Blue, TextSize = Theme.TextSize.Small, LayoutOrder = i, Parent = traitsRow })
				Tiles.tap(chip, function()
					ctx:Toast(t.name .. ": " .. t.desc, "info")
				end)
			end
		end
		local hidden = Config.Traits.ById[m.hidden or 0]
		if stage >= 3 and hidden then
			local chip = Widgets.Chip({
				Text = "Hidden · " .. hidden.name,
				Color = C.Purple,
				TextSize = Theme.TextSize.Small,
				LayoutOrder = 9,
				Parent = traitsRow,
			})
			Tiles.tap(chip, function()
				ctx:Toast(hidden.name .. ": " .. hidden.desc, "info")
			end)
		else
			local chip = Widgets.Chip({
				Text = "Hidden · ???",
				Color = C.Gray,
				TextSize = Theme.TextSize.Small,
				LayoutOrder = 9,
				Parent = traitsRow,
			})
			Tiles.tap(chip, function()
				ctx:Toast("The hidden trait shows when it grows into an Adult", "info")
			end)
		end

		-- Level up
		local oneCost, oneN = levelCost(m, 1)
		local tenCost, tenN = levelCost(m, 10)
		Tiles.clear(lvOneCost)
		if oneN > 0 then
			Tiles.cost({ coins = oneCost.coins }, lvOneCost, nil, { Color = C.White, TextSize = 17, IconSize = 20, Height = 24 })
			lvOne:SetText("Lv up")
			lvTen:SetText(string.format("×%d", tenN))
			costLabel.Text = string.format(
				"Lv up: %s coins + %d treats · ×%d: %s + %d",
				Format.short(oneCost.coins),
				oneCost.treats,
				tenN,
				Format.short(tenCost.coins),
				tenCost.treats
			)
		else
			lvOne:SetText(if stage < 3 then "Max for stage" else "Max level")
			lvTen:SetText("×0")
			costLabel.Text = if stage < 3 then "Grow it up to raise the level cap" else "Add stars to raise the level cap"
		end
		lvOne:SetDisabled(oneN <= 0 or not StoreKit.canAfford(store, oneCost))
		lvTen:SetDisabled(tenN <= 1 or not StoreKit.canAfford(store, (levelCost(m, 2))))

		-- Grow
		if stopGrow then
			stopGrow()
			stopGrow = nil
		end
		local growEndsAt = tonumber(m.growEndsAt) or 0
		if stage >= 3 then
			growButton:SetVisible(false)
			growReason.Text = "Adult · fully grown"
		elseif growEndsAt > 0 then
			growButton:SetVisible(true)
			growButton:SetDisabled(true)
			growButton:SetText("Growing " .. Format.clock(growEndsAt - now))
			growReason.Text = "Growing into a " .. Config.Economy.Stages[stage + 1].name
			stopGrow = Widgets.Countdown(growButton.Label, function()
				return growEndsAt
			end, function(left)
				return if left > 0 then "Growing " .. Format.clock(left) else "Almost…"
			end)
		else
			local can, why = Formulas.CanGrow(m)
			growButton:SetVisible(true)
			growButton:SetText("Grow up!")
			growButton:SetDisabled(not can or m.busy ~= nil and m.busy ~= false)
			growReason.Text = if m.busy then "Busy right now" elseif can then "Ready to grow!" else (why or "")
		end

		-- Diet
		local needed = Formulas.MealsNeeded(stage)
		local eaten = Formulas.MealsEaten(m)
		dietTitle.Text = if needed
			then string.format("Diet this stage · %d / %d meals", math.min(eaten, needed), needed)
			else "Diet · meals lift Mood"
		for _, flavor in Config.Food.List do
			local n = tonumber(StoreKit.asTable(m.meals)[flavor.id]) or 0
			dietRows[flavor.id]:Set(if needed then n / math.max(1, needed) else 0, tostring(n))
		end
		renderEvolution(m)

		-- Star up / sell
		local stars, maxStars = m.stars or 1, Formulas.MaxStars(m)
		starButton:SetText(if stars >= maxStars then "Max ★" else string.format("★ Up %d/%d", stars, maxStars))
		starButton:SetDisabled(stars >= maxStars or (m.busy ~= nil and m.busy ~= false))
		sellButton:SetDisabled(m.locked == true or (m.busy ~= nil and m.busy ~= false))
	end

	-- Buttons ---------------------------------------------------------------------------

	feedButton:SetOnClick(openFeed)
	renameButton:SetOnClick(openRename)
	rideButton:SetOnClick(function()
		local m = monster()
		if not m then
			return
		end
		local riding = StoreKit.tbl(store, "session.Riding").mount
		if riding == currentId then
			StoreKit.request(ctx, "Riding.Dismount")
		elseif m.stage ~= 3 then
			ctx:Toast("Only Adults are big enough to ride", "info")
		else
			local ok = StoreKit.request(ctx, "Riding.Mount", { id = currentId })
			if ok then
				ctx.Router:Close("MonsterDetail")
			end
		end
	end)
	styleButton:SetOnClick(function()
		if currentId and ctx.Router:Has("Wardrobe") then
			ctx.Router:Open("Wardrobe", { id = currentId })
		end
	end)
	lockButton:SetOnClick(function()
		local m = monster()
		if m then
			StoreKit.request(ctx, "Monsters.SetLocked", { id = currentId, locked = not m.locked })
		end
	end)
	local function levelUp(times: number)
		local id = currentId
		if StoreKit.request(ctx, "Monsters.LevelUp", { id = id, times = times }) then
			-- A shockwave from the level bar now; the in-world stars wait until this screen closes.
			local kit = ctx:GetController("Celebrate")
			if kit then
				kit:Shockwave(levelBar.Root, C.Blue)
				ctx:Sound("LevelUp")
			end
			ctx.Bus:Publish("Vfx.Burst", "monsterLevelUp", { id = id }) -- World: stars at the pen monster
		end
	end
	lvOne:SetOnClick(function()
		levelUp(1)
	end)
	lvTen:SetOnClick(function()
		local m = monster()
		if m then
			local _, n = levelCost(m, 10)
			if n > 0 then
				levelUp(n)
			end
		end
	end)
	growButton:SetOnClick(function()
		local ok = StoreKit.request(ctx, "Monsters.Grow", { id = currentId })
		if ok then
			ctx:Toast("Growing up! Check back soon.", "success")
		end
	end)
	starButton:SetOnClick(function()
		local m = monster()
		if not m then
			return
		end
		local any = false
		for oid, other in StoreKit.monsters(store) do
			if
				oid ~= currentId
				and type(other) == "table"
				and other.line == m.line
				and other.rarity == m.rarity
				and not other.busy
				and not other.locked
			then
				any = true
				break
			end
		end
		if not any then
			ctx:Toast(
				string.format("You need another %s %s to fuse", Theme.RarityName(m.rarity), Formulas.FormName({ line = m.line, stage = 1 })),
				"info"
			)
			return
		end
		startStarUp()
	end)
	sellButton:SetOnClick(function()
		local m = monster()
		if not m then
			return
		end
		local id = currentId
		confirm(
			"Sell",
			string.format("Sell %s for %s coins?", Formulas.DisplayName(m), Format.short(Formulas.SellPrice(m))),
			"Sell",
			C.Red,
			function()
				local ok, res = StoreKit.request(ctx, "Monsters.Sell", { ids = { id } })
				if ok then
					ctx:Toast(string.format("Sold for %s coins", Format.short(type(res) == "table" and tonumber(res.coins) or 0)), "reward")
					currentId = nil
					ctx.Router:Open("Monsters")
				end
			end
		)
	end)

	local watch = StoreKit.watch(store, { "profile.Monsters", "profile.Currency", "session.Riding", "profile.Companions" }, function()
		refresh()
	end)

	return {
		Root = panel.Root,
		Open = function(params)
			local id = type(params) == "table" and params.id or nil
			if type(id) ~= "string" or not StoreKit.monster(store, id) then
				ctx:Toast("That monster is gone", "error")
				ctx.Router:Close("MonsterDetail")
				return
			end
			if id ~= currentId then
				lastApSig = ""
			end
			currentId = id
			popup:Hide()
			refresh()
			watch.Start()
		end,
		Close = function()
			watch.Stop()
			popup:Hide()
			if stopGrow then
				stopGrow()
				stopGrow = nil
			end
		end,
	}
end

return MonsterDetail
