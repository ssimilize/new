--[[
	Store screen (C3). Params: { tab? = "food" | "decor" | "passes" | "gems" | "codes" }.

	Food: the four flavours, buy ×1 / ×10 / ×50 (Shop.BuyFood).
	Decor: Config.Decor.List and pen themes (Shop.BuyDecor / Shop.BuyTheme), owned counts
	from profile.Shop.
	Passes: Config.Monetization.Passes, owned from session.Monetization.passes, bought with
	MarketplaceService:PromptGamePassPurchase; after PromptGamePassPurchaseFinished the
	client calls Monetization.RefreshPasses. Id 0 shows "Coming soon".
	Gems: developer products (PromptProductPurchase); totems are server-wide.
	Codes: a TextBox → Quests.Redeem.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local Icon = require(UI.Components.Icon)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local M = Config.Monetization

local TABS = { "food", "decor", "passes", "gems", "codes" }

local PRICE_ICON = { coins = "coin", gems = "gem", friendship = "friendship", token = "token", stardust = "stardust", treats = "treat" }

-- The first (only) currency in a price table: returns key, amount.
local function priceOf(price)
	if type(price) ~= "table" then
		return nil, 0
	end
	for _, key in { "coins", "gems", "friendship", "token", "stardust", "treats" } do
		if price[key] then
			return key, price[key]
		end
	end
	return nil, 0
end

local PRODUCT_TEXT = {
	starterPack = "Crystal Egg, 300 gems and a Hay Bale. Once per account.",
	totemRain = "Summons Rain for everyone on this server.",
	totemThunder = "Summons a Thunderstorm for everyone on this server.",
	totemStarfall = "Summons a Starfall for everyone on this server.",
	ranchPass = "Unlocks the premium track of this season's Ranch Pass.",
}

return {
	Name = "Store",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Store",
			Color = C.Orange,
			Size = UDim2.fromOffset(1040, 520),
			OnClose = function()
				ctx.Router:Close("Store")
			end,
		})
		local coinsPill = Widgets.Pill({ Icon = "coin", Text = "0", Parent = panel.HeaderRight })
		coinsPill.Root.LayoutOrder = 1
		local gemsPill = Widgets.Pill({ Icon = "gem", Text = "0", Parent = panel.HeaderRight })
		gemsPill.Root.LayoutOrder = 2

		local tab = "food"
		local decorMode = "decor"
		local isOpen = false
		local bag = Util.bag()
		local lifetime = Util.bag()
		local codeText = ""
		local refresh

		local tabs = Widgets.Tabs({
			Tabs = {
				{ id = "food", text = "Food", width = 150 },
				{ id = "decor", text = "Decor", width = 150 },
				{ id = "passes", text = "Passes", width = 150 },
				{ id = "gems", text = "Gems", width = 150 },
				{ id = "codes", text = "Codes", width = 150 },
			},
			Selected = tab,
			Parent = panel.Body,
			OnChanged = function(id)
				tab = id
				if refresh then
					refresh()
				end
			end,
		})
		local content = New("Frame", {
			Name = "Content",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 54),
			Size = UDim2.new(1, 0, 1, -54),
			Parent = panel.Body,
		})

		local function currency()
			return ctx.Store:Get("profile.Currency") or {}
		end
		local function balance(key: string, event: string?): number
			local cur = currency()
			if key == "token" then
				local tokens = cur.tokens
				return if type(tokens) == "table" and event then (tokens[event] or 0) else 0
			end
			local value = cur[key]
			return if type(value) == "number" then value else 0
		end

		-- Purchases -------------------------------------------------------------------------------

		local function promptPass(pass)
			if pass.gamePassId == 0 then
				ctx:Toast("Coming soon", "info")
				return
			end
			local ok, err = pcall(function()
				MarketplaceService:PromptGamePassPurchase(ctx.Player, pass.gamePassId)
			end)
			if not ok then
				ctx:Toast("Purchase unavailable right now", "error")
				warn("[Store] PromptGamePassPurchase failed: " .. tostring(err))
			end
		end

		local function promptProduct(product)
			if product.productId == 0 then
				ctx:Toast("Coming soon", "info")
				return
			end
			local ok, err = pcall(function()
				MarketplaceService:PromptProductPurchase(ctx.Player, product.productId)
			end)
			if not ok then
				ctx:Toast("Purchase unavailable right now", "error")
				warn("[Store] PromptProductPurchase failed: " .. tostring(err))
			end
		end

		lifetime.add(MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _gamePassId, wasPurchased)
			if player ~= ctx.Player or not wasPurchased then
				return
			end
			local ok = Util.request(ctx, "Monetization.RefreshPasses")
			if ok then
				ctx:Toast("Pass unlocked. Thank you!", "success")
			end
		end))
		lifetime.add(panel.Root.Destroying:Connect(function()
			lifetime.clean()
		end))

		-- Tabs --------------------------------------------------------------------------------------

		local function drawFood()
			local row = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Parent = content,
			}, { Create.List("x", 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top) })
			local price = Config.Economy.FoodPrice
			local coins = balance("coins")
			local owned = currency().food or {}
			for i, f in Config.Food.List do
				local card = Util.card({ Size = UDim2.fromOffset(238, 370), LayoutOrder = i, Parent = row })
				New("Frame", {
					BackgroundColor3 = Theme.Food(f.id),
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 12),
					Size = UDim2.fromOffset(70, 70),
					Parent = card,
				}, { Create.Round(), Create.Stroke(3), Create.Shade(0.2) })
				Util.text({
					Text = f.name,
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body + 2,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(0, 88),
					Size = UDim2.new(1, 0, 0, 26),
					Parent = card,
				})
				Util.text({
					Text = string.format("You have %s · %d coins each", Format.short(owned[f.id] or 0), price),
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(6, 116),
					Size = UDim2.new(1, -12, 0, 40),
					Parent = card,
				})
				for j, amount in { 1, 10, 50 } do
					local cost = amount * price
					Button.new({
						Text = string.format("×%d  %s", amount, Format.short(cost)),
						Icon = Icon.new("coin", 22),
						Color = C.Green,
						Size = UDim2.new(1, -24, 0, 52),
						TextSize = Theme.TextSize.Body,
						Position = UDim2.fromOffset(12, 160 + (j - 1) * 64),
						Disabled = coins < cost,
						Parent = card,
						OnClick = function()
							if balance("coins") < cost then
								ctx:Toast("Not enough coins", "error")
								return
							end
							local ok = Util.requestOnce(ctx, "Shop.BuyFood", { flavor = f.id, amount = amount })
							if ok then
								ctx:Toast(string.format("+%d %s", amount, f.name), "success")
							end
						end,
					})
				end
			end
		end

		local function buyButton(parent, price, event, owned: boolean?, onBuy)
			local key, amount = priceOf(price)
			if owned then
				Util.text({
					Text = "Owned ✓",
					Font = Theme.Fonts.Display,
					TextColor3 = C.Green,
					TextXAlignment = Enum.TextXAlignment.Center,
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -8),
					Size = UDim2.new(1, -16, 0, 46),
					Parent = parent,
				})
				return
			end
			local affordable = key == nil or balance(key, event) >= amount
			Button.new({
				Text = if key then Format.short(amount) else "Free",
				Icon = if key then Icon.new(PRICE_ICON[key] or "coin", 22) else nil,
				Color = C.Green,
				Size = UDim2.new(1, -16, 0, 46),
				TextSize = Theme.TextSize.Body,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Disabled = not affordable,
				Parent = parent,
				OnClick = function()
					if key and balance(key, event) < amount then
						ctx:Toast("Not enough " .. (if key == "token" then "tokens" else key), "error")
						return
					end
					onBuy()
				end,
			})
		end

		local function drawDecor()
			local toggles = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 44),
				Parent = content,
			}, { Create.List("x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
			for i, spec in { { id = "decor", text = "Decor" }, { id = "themes", text = "Pen themes" } } do
				Button.new({
					Text = spec.text,
					Color = if decorMode == spec.id then C.Blue else C.Gray,
					Size = UDim2.fromOffset(150, 44),
					TextSize = Theme.TextSize.Body,
					LayoutOrder = i,
					Parent = toggles,
					OnClick = function()
						decorMode = spec.id
						refresh()
					end,
				})
			end
			Util.text({
				Text = "Place decor from the Ranch screen. Each piece cheers up the monsters in its pen.",
				TextColor3 = C.TextMuted,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				TextWrapped = false,
				LayoutOrder = 3,
				Parent = toggles,
			})
			local grid = Widgets.Scroll({
				Cell = Vector2.new(182, 206),
				Padding = 10,
				Position = UDim2.fromOffset(0, 50),
				Size = UDim2.new(1, 0, 1, -50),
				Parent = content,
			})
			local shop = ctx.Store:Get("profile.Shop") or {}
			if decorMode == "themes" then
				local themes = shop.themes or {}
				for i, t in Config.Decor.PenThemes do
					if t.rebirth then
						continue -- Rebirth biomes are earned, never sold
					end
					local cell = Util.card({ LayoutOrder = i, Parent = grid })
					New("Frame", {
						BackgroundColor3 = Color3.fromHex(t.ground),
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, 10),
						Size = UDim2.fromOffset(110, 70),
						Parent = cell,
					}, {
						Create.Corner(10),
						Create.Stroke(5, Color3.fromHex(t.fence)),
					})
					Util.text({
						Text = t.name,
						Font = Theme.Fonts.Display,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.fromOffset(4, 88),
						Size = UDim2.new(1, -8, 0, 24),
						Parent = cell,
					})
					if t.event then
						local chip = Widgets.Chip({ Text = "EVENT", Color = C.Token, Parent = cell })
						chip.Position = UDim2.fromOffset(8, 8)
					end
					local owned = t.price == nil or themes[t.id] == true
					buyButton(cell, t.price, t.event, owned, function()
						local ok = Util.requestOnce(ctx, "Shop.BuyTheme", { theme = t.id })
						if ok then
							ctx:Toast(t.name .. " unlocked!", "success")
						end
					end)
				end
				return
			end
			local decorOwned = shop.decor or {}
			for i, d in Config.Decor.List do
				local cell = Util.card({ LayoutOrder = i, Parent = grid })
				New("Frame", {
					BackgroundColor3 = Color3.fromHex(d.color),
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 10),
					Size = UDim2.fromOffset(64, 64),
					Rotation = 8,
					Parent = cell,
				}, { Create.Corner(14), Create.Stroke(3), Create.Shade(0.2) })
				Util.text({
					Text = d.name,
					Font = Theme.Fonts.Display,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(4, 80),
					Size = UDim2.new(1, -8, 0, 24),
					Parent = cell,
				})
				Util.text({
					Text = string.format("Mood +%d · Owned %d", d.mood or 0, decorOwned[d.id] or 0),
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(4, 104),
					Size = UDim2.new(1, -8, 0, 40),
					Parent = cell,
				})
				if d.event then
					local chip = Widgets.Chip({ Text = "EVENT", Color = C.Token, Parent = cell })
					chip.Position = UDim2.fromOffset(8, 8)
				elseif d.set == "beach" then
					local chip = Widgets.Chip({ Text = "BEACH", Color = C.Blue, Parent = cell })
					chip.Position = UDim2.fromOffset(8, 8)
				end
				buyButton(cell, d.price, d.event, false, function()
					local ok = Util.requestOnce(ctx, "Shop.BuyDecor", { decor = d.id })
					if ok then
						ctx:Toast(d.name .. " bought! Place it from the Ranch screen.", "success")
					end
				end)
			end
		end

		local function robuxButton(parent, price: number, id: number, onClick)
			Button.new({
				Text = if id == 0 then "Coming soon" else string.format("R$ %d", price),
				Color = if id == 0 then C.Gray else C.Green,
				Size = UDim2.new(1, -16, 0, 48),
				TextSize = Theme.TextSize.Body,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Parent = parent,
				OnClick = onClick,
			})
		end

		local function drawPasses()
			local grid = Widgets.Scroll({ Cell = Vector2.new(234, 176), Padding = 10, Parent = content })
			local owned = ctx.Store:Get("session.Monetization.passes") or {}
			for i, pass in M.Passes do
				local cell = Util.card({ LayoutOrder = i, Parent = grid })
				Util.text({
					Text = pass.name,
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body + 1,
					Position = UDim2.fromOffset(12, 8),
					Size = UDim2.new(1, -24, 0, 26),
					Parent = cell,
				})
				Util.text({
					Text = pass.desc,
					TextColor3 = C.TextMuted,
					TextYAlignment = Enum.TextYAlignment.Top,
					Position = UDim2.fromOffset(12, 38),
					Size = UDim2.new(1, -24, 0, 70),
					Parent = cell,
				})
				if owned[pass.key] == true then
					Util.text({
						Text = "Owned ✓",
						Font = Theme.Fonts.Display,
						TextColor3 = C.Green,
						TextXAlignment = Enum.TextXAlignment.Center,
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -8),
						Size = UDim2.new(1, -16, 0, 48),
						Parent = cell,
					})
				else
					robuxButton(cell, pass.price, pass.gamePassId, function()
						promptPass(pass)
					end)
				end
			end
		end

		local function productIcon(product)
			if product.key == "ranchPass" then
				return Icon.new("star", 40)
			elseif product.handler == "Weather.Totem" then
				return Icon.new("token", 40)
			end
			local first = product.grant and product.grant[1]
			if first and first.kind == "egg" and first.id then
				return MonsterIcon.egg(first.id, 40)
			end
			return Icon.new("gem", 40)
		end

		local function drawGems()
			local grid = Widgets.Scroll({ Cell = Vector2.new(234, 180), Padding = 10, Parent = content })
			local once = ctx.Store:Get("profile.Monetization.once") or {}
			local pass = ctx.Store:Get("profile.Quests.pass")
			for i, product in M.Products do
				local cell = Util.card({ LayoutOrder = i, Parent = grid })
				local icon = productIcon(product)
				icon.Position = UDim2.fromOffset(10, 10)
				icon.Parent = cell
				Util.text({
					Text = product.name,
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body + 1,
					Position = UDim2.fromOffset(58, 14),
					Size = UDim2.new(1, -66, 0, 30),
					Parent = cell,
				})
				local desc = PRODUCT_TEXT[product.key]
				if not desc and product.grant then
					local parts = {}
					for _, item in product.grant do
						table.insert(parts, Util.rewardText(item))
					end
					desc = table.concat(parts, " + ") .. (if product.key:match("^gems") then " gems" else "")
				end
				Util.text({
					Text = desc or "",
					TextColor3 = C.TextMuted,
					TextYAlignment = Enum.TextYAlignment.Top,
					Position = UDim2.fromOffset(12, 58),
					Size = UDim2.new(1, -24, 0, 60),
					Parent = cell,
				})
				local bought = (product.oncePerAccount and once[product.key] == true)
					or (
						product.key == "ranchPass"
						and type(pass) == "table"
						and pass.premium == true
						and pass.season == Config.Quests.PassAt(ctx:Now()).season
					)
				if bought then
					Util.text({
						Text = "Owned ✓",
						Font = Theme.Fonts.Display,
						TextColor3 = C.Green,
						TextXAlignment = Enum.TextXAlignment.Center,
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -8),
						Size = UDim2.new(1, -16, 0, 48),
						Parent = cell,
					})
				else
					robuxButton(cell, product.price, product.productId, function()
						promptProduct(product)
					end)
				end
			end
		end

		local function drawCodes()
			local card = Util.card({
				Title = "Redeem a code",
				Size = UDim2.fromOffset(620, 300),
				Position = UDim2.new(0.5, -310, 0, 10),
				Parent = content,
			})
			Util.text({
				Text = "Codes are posted in our group and on social media. Each code works once per account.",
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(16, 40),
				Size = UDim2.new(1, -32, 0, 44),
				Parent = card,
			})
			local box = New("TextBox", {
				Text = codeText,
				PlaceholderText = "Enter code",
				ClearTextOnFocus = false,
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Header,
				TextColor3 = C.Text,
				PlaceholderColor3 = C.Gray,
				BackgroundColor3 = C.Panel,
				Position = UDim2.fromOffset(16, 96),
				Size = UDim2.new(1, -32, 0, 58),
				Parent = card,
			}, { Create.Corner(12), Create.Stroke(3) })
			box:GetPropertyChangedSignal("Text"):Connect(function()
				if #box.Text > 30 then
					box.Text = string.sub(box.Text, 1, 30)
				end
				codeText = box.Text
			end)
			local redeem
			local function submit()
				local code = string.upper((string.gsub(box.Text, "%s", "")))
				if code == "" then
					ctx:Toast("Enter a code first", "error")
					return
				end
				redeem:SetDisabled(true)
				local ok, res = Util.requestOnce(ctx, "Quests.Redeem", { code = code })
				redeem:SetDisabled(false)
				if ok then
					codeText = ""
					box.Text = ""
					local parts = {}
					if type(res) == "table" and type(res.rewards) == "table" then
						for _, item in res.rewards do
							table.insert(parts, Util.rewardText(item))
						end
					end
					ctx:Toast(if #parts > 0 then "Code redeemed! + " .. table.concat(parts, ", ") else "Code redeemed!", "reward")
				end
			end
			redeem = Button.new({
				Text = "Redeem",
				Color = C.Green,
				Size = UDim2.fromOffset(240, 58),
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 176),
				Parent = card,
				OnClick = submit,
			})
			box.FocusLost:Connect(function(enterPressed)
				if enterPressed then
					task.spawn(submit)
				end
			end)
		end

		local function draw()
			if not isOpen then
				return
			end
			coinsPill:SetText(Format.short(balance("coins")))
			gemsPill:SetText(Format.short(balance("gems")))
			if tab == "codes" and content:FindFirstChild("Card") and content:FindFirstChild("Card"):FindFirstChildOfClass("TextBox") then
				-- Don't rebuild the codes card while typing (it would drop keyboard focus).
				return
			end
			Util.clear(content)
			if tab == "decor" then
				drawDecor()
			elseif tab == "passes" then
				drawPasses()
			elseif tab == "gems" then
				drawGems()
			elseif tab == "codes" then
				drawCodes()
			else
				drawFood()
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function(params)
				isOpen = true
				bag.clean()
				if type(params) == "table" and table.find(TABS, params.tab) then
					tabs:Select(params.tab)
				end
				for _, path in { "profile.Currency", "profile.Shop", "session.Monetization", "profile.Monetization", "profile.Quests.pass" } do
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
