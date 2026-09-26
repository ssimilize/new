--[[
	Friends (glow-up L): gifts, invites and community rewards. Opened from the HUD's Friends button.

	  Gifts    your Roblox friends (Players:GetFriendsAsync, online first) on the left; pick one,
	           then an egg from storage, food (5 at a time), decor or an accessory from storage on
	           the right. Send → Gifts.Prepare → a confirm dialog that says what leaves, who gets
	           it, that gifts can't be undone and how many are left today → Gifts.Send. "Ranch Pass
	           for <name>" picks the friend (Gifts.PassTarget), asks Monetization.CanBuy and prompts
	           the ranchPassGift product. Delivery is by mailbox, so offline friends get it later.
	  Invite   "Invite friends" (SocialService:PromptGameInvite with launch data "invite:<userId>")
	           and what both players get (Config.Community.Invites).
	  Rewards  "Join our group" (only while Config.Quests.GroupId ~= 0), the Premium daily egg and
	           the VIP Rancher perks with the balcony.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Community)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)
local Dialog = require(script.Parent.Parts.Dialog)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Community
local G = Cfg.Gifts

local FOOD_STEP = 5

local Friends = { Name = "Friends" }

-- Every friend of the local player (online first, then by name). Empty when the call fails.
local function fetchFriends(userId: number)
	local list = {}
	pcall(function()
		local pages = Players:GetFriendsAsync(userId)
		while true do
			for _, info in pages:GetCurrentPage() do
				table.insert(list, { userId = info.Id, name = info.DisplayName or info.Username, online = info.IsOnline == true })
			end
			if pages.IsFinished or #list >= 200 then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	table.sort(list, function(a, b)
		if a.online ~= b.online then
			return a.online
		end
		return tostring(a.name) < tostring(b.name)
	end)
	return list
end

local function itemName(kind: string, item: string, amount: number): string
	if kind == "egg" then
		local def = Config.Eggs.ById[item]
		return if def then def.name else "Egg"
	elseif kind == "food" then
		local def = Config.Food.ById[item]
		return string.format("%d × %s", amount, if def then def.name else item)
	elseif kind == "decor" then
		local def = Config.Decor.ById[item]
		return if def then def.name else item
	end
	local def = Config.Accessories.ById[item]
	return if def then def.name else item
end

function Friends.Build(ctx)
	local store = ctx.Store
	local panel = Panel.new({
		Title = "Friends",
		Color = C.Blue,
		Size = UDim2.fromOffset(900, 480),
		OnClose = function()
			ctx.Router:Close("Friends")
		end,
	})
	local tabs
	local content = New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		Parent = panel.Body,
	})
	local bag = Util.bag()
	local friends = nil -- fetched once per session
	local picked = nil -- { userId, name }

	local function me(): number
		return ctx.Player.UserId
	end

	local function row(
		parent: Instance,
		order: number,
		text: string,
		buttonText: string?,
		color: Color3?,
		onClick: (() -> ())?,
		disabled: boolean?
	)
		local card = Util.card({ Size = UDim2.new(1, -8, 0, 64), LayoutOrder = order, Parent = parent })
		Util.text({
			Text = text,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, if buttonText then -190 else -28, 1, 0),
			Parent = card,
		})
		if buttonText then
			Button.new({
				Text = buttonText,
				Color = color or C.Green,
				Disabled = disabled,
				Size = UDim2.fromOffset(160, 48),
				TextSize = Theme.TextSize.Small + 1,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Parent = card,
				OnClick = onClick,
			})
		end
		return card
	end

	-- Gifts ------------------------------------------------------------------------------------

	local function send(kind: string, item: string, amount: number)
		if not picked then
			return
		end
		local target = picked
		local ok, prep = Util.requestOnce(ctx, "Gifts.Prepare", { to = target.userId, kind = kind, item = item, amount = amount })
		if not ok or type(prep) ~= "table" then
			return
		end
		local who = if type(prep.name) == "string" then prep.name else target.name
		Dialog.confirm(ctx.UI.Top, {
			Title = string.format("Send to %s?", who),
			Text = string.format(
				"%s leaves your ranch for good. Gifts can't be undone. Gifts left today: %d",
				itemName(prep.kind, prep.item, prep.amount),
				prep.left
			),
			ConfirmText = "Send gift",
			ConfirmColor = C.Green,
			OnConfirm = function()
				local sent = Util.requestOnce(ctx, "Gifts.Send", { token = prep.token })
				if sent then
					ctx:Toast(string.format("Gift sent to %s!", who), "success")
				end
			end,
		})
	end

	local function giftPass()
		local product = Config.Monetization.ProductByKey[Cfg.PassGift.product]
		if not picked or not product or product.productId == 0 then
			ctx:Toast("Coming soon", "info")
			return
		end
		if not Util.requestOnce(ctx, "Gifts.PassTarget", { to = picked.userId }) then
			return
		end
		if not Util.requestOnce(ctx, "Monetization.CanBuy", { product = product.key }) then
			return
		end
		local ok = pcall(function()
			game:GetService("MarketplaceService"):PromptProductPurchase(ctx.Player, product.productId)
		end)
		if not ok then
			ctx:Toast("Purchase unavailable right now", "error")
		end
	end

	local function drawItems(parent: Instance)
		Util.clear(parent)
		local list = Widgets.List({ Parent = parent, Padding = 8 })
		if not picked then
			Util.text({ Text = "Pick a friend to send a gift", Size = UDim2.new(1, -8, 0, 40), Parent = list })
			return
		end
		local level = StoreKit.level(store)
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		if level < G.minLevel then
			row(list, nextOrder(), string.format("Gifts unlock at Ranch Level %d", G.minLevel))
		end
		local sent = StoreKit.tbl(store, "profile.Gifts")
		local left = Logic.DailyLeft(if sent.day == Util.day(ctx) then sent else {}, G)
		row(list, nextOrder(), string.format("Gifts left today: %d", left))
		row(list, nextOrder(), string.format("Ranch Pass for %s", picked.name), "Gift R$", C.Orange, giftPass)

		local eggs = StoreKit.tbl(store, "profile.Eggs.list")
		local eggIds = {}
		for id in eggs do
			table.insert(eggIds, id)
		end
		table.sort(eggIds)
		for _, id in eggIds do
			local record = eggs[id]
			if type(record) == "table" then
				row(list, nextOrder(), itemName("egg", tostring(record.type), 1), "Send", C.Pink, function()
					send("egg", id, 1)
				end)
			end
		end
		for _, food in Config.Food.List do
			local have = StoreKit.balance(store, "food." .. food.id)
			if have > 0 then
				local amount = math.min(FOOD_STEP, have, G.maxFood)
				row(list, nextOrder(), itemName("food", food.id, amount), "Send", C.Orange, function()
					send("food", food.id, amount)
				end)
			end
		end
		for id, n in StoreKit.tbl(store, "profile.Shop.decor") do
			if type(n) == "number" and n > 0 and Config.Decor.ById[id] then
				row(list, nextOrder(), itemName("decor", id, 1), "Send", C.Green, function()
					send("decor", id, 1)
				end)
			end
		end
		for id, n in StoreKit.tbl(store, "profile.Accessories.owned") do
			if type(n) == "number" and n > 0 and Config.Accessories.ById[id] then
				row(list, nextOrder(), itemName("accessory", id, 1), "Send", C.Purple, function()
					send("accessory", id, 1)
				end)
			end
		end
	end

	local function drawGifts()
		local left = New("Frame", {
			Name = "FriendList",
			BackgroundTransparency = 1,
			Size = UDim2.new(0.38, -6, 1, 0),
			Parent = content,
		})
		local right = New("Frame", {
			Name = "Items",
			BackgroundTransparency = 1,
			Position = UDim2.new(0.38, 6, 0, 0),
			Size = UDim2.new(0.62, -6, 1, 0),
			Parent = content,
		})
		local list = Widgets.List({ Parent = left, Padding = 6 })
		if friends == nil then
			friends = fetchFriends(me())
		end
		if #friends == 0 then
			Util.text({
				Text = "No friends to show yet. Invite some from the Invite tab!",
				TextWrapped = true,
				Size = UDim2.new(1, -8, 0, 64),
				Parent = list,
			})
		end
		for i, friend in friends do
			local b = Button.new({
				Text = friend.name,
				Color = if picked and picked.userId == friend.userId then C.Orange elseif friend.online then C.Green else C.Gray,
				Size = UDim2.new(1, -8, 0, 46),
				TextSize = Theme.TextSize.Small + 1,
				LayoutOrder = i,
				Parent = list,
				OnClick = function()
					picked = friend
					Util.clear(content)
					drawGifts()
				end,
			})
			b.Label:SetAttribute("Localize", false)
		end
		drawItems(right)
	end

	-- Invite -----------------------------------------------------------------------------------

	local function invite()
		local ok, err = pcall(function()
			local social = game:GetService("SocialService")
			if not social:CanSendGameInviteAsync(ctx.Player) then
				ctx:Toast("Invites aren't available on this account", "info")
				return
			end
			local options = Instance.new("ExperienceInviteOptions")
			options.PromptMessage = "Come raise monsters on my ranch!"
			options.LaunchData = Logic.InviteData(me(), Cfg.Invites.launchPrefix)
			social:PromptGameInvite(ctx.Player, options)
		end)
		if not ok then
			ctx:Toast("Invites aren't available right now", "info")
			warn("[Friends] invite failed: " .. tostring(err))
		end
	end

	local function drawInvite()
		local list = Widgets.List({ Parent = content, Padding = 8 })
		row(list, 1, "Invite your Roblox friends to play together.", "Invite friends", C.Blue, invite)
		row(
			list,
			2,
			string.format(
				"When a friend joins for the first time from your invite, you both get a gift. Up to %d gifts for you each week.",
				Cfg.Invites.weeklyCap
			)
		)
		local community = StoreKit.tbl(store, "profile.Community")
		row(list, 3, string.format("Friends who joined from your invites: %d", tonumber(community.invitesTotal) or 0))
	end

	-- Rewards ----------------------------------------------------------------------------------

	local function drawRewards()
		local list = Widgets.List({ Parent = content, Padding = 8 })
		local community = StoreKit.tbl(store, "profile.Community")
		if (tonumber(Config.Quests.GroupId) or 0) ~= 0 then
			local claimed = community.group == true
			row(
				list,
				1,
				"Join our Roblox group for a Crystal Egg and 50 gems!",
				if claimed then "Claimed ✓" else "Claim",
				C.Green,
				function()
					Util.requestOnce(ctx, "Community.ClaimGroup")
				end,
				claimed
			)
		end
		local premium = StoreKit.tbl(store, "global.Community.premium")["u" .. me()] == true
		local claimedToday = community.premiumDay == Util.day(ctx)
		row(
			list,
			2,
			"Roblox Premium members get a free Grove Egg every day.",
			if claimedToday then "Claimed ✓" else "Claim",
			C.Purple,
			function()
				Util.requestOnce(ctx, "Community.ClaimPremium")
			end,
			not premium or claimedToday
		)
		local vip = StoreKit.hasPass(store, Cfg.VipBalcony.pass)
		row(
			list,
			3,
			"VIP Rancher: the VIP Balcony by the plaza, a gold name, a daily crate and a chat tag.",
			if vip then "Go to balcony" else "See VIP",
			C.Gold,
			function()
				if vip then
					if Util.requestOnce(ctx, "Community.Balcony", { enter = true }) then
						ctx.Router:Close("Friends")
					end
				else
					ctx.Router:Open("Store", { tab = "passes" })
				end
			end
		)
	end

	local DRAW = { gifts = drawGifts, invite = drawInvite, rewards = drawRewards }

	local function redraw()
		Util.clear(content)
		local draw = DRAW[tabs.Selected] or drawGifts
		draw()
	end

	tabs = Widgets.Tabs({
		Parent = panel.Body,
		Tabs = { { id = "gifts", text = "Gifts" }, { id = "invite", text = "Invite" }, { id = "rewards", text = "Rewards" } },
		OnChanged = function()
			redraw()
		end,
	})

	local debounced = Util.debounce(redraw)
	return {
		Root = panel.Root,
		Open = function(params)
			if type(params) == "table" and DRAW[params.tab] then
				tabs:Select(params.tab)
			else
				redraw()
			end
			bag.clean()
			for _, path in { "profile.Gifts", "profile.Community", "profile.Eggs.list", "global.Community", "session.Monetization" } do
				bag.add(store:Observe(path, debounced))
			end
		end,
		Close = function()
			bag.clean()
		end,
	}
end

return Friends
