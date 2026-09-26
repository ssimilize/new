--[[
	Postcards (glow-up X, client): the postcard that arrives with a claimed expedition.

	Watches profile.Postcards.cards. A new card of your own (not one a friend sent: the server's
	toast announces those) is queued and shown as a card dialog on the Top layer, one at a time:
	Flip turns it over (loot, date), ★ keeps it for good, Send picks a Roblox friend
	(Postcards.Send), Album opens the Album screen on its region, ✕ dismisses it. Cards already
	in the album when the game loads never pop up.

	Public:
	  Postcards:Show(card, { fromAlbum? })   opens one card now (the Album screen's tiles)
	  Postcards:Current() -> { card, view, dialog }?
	  Postcards:Pending() -> number          cards queued behind the open one
	  Postcards:PickFriend(cardId)           the friend picker for Send
	  Postcards.FriendSource                 tests: fn() -> { { userId, name, online } } instead of GetFriendsAsync
]]

local Players = game:GetService("Players")

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Widgets = require(UI.Components.Widgets)
local Dialog = require(UI.Screens.Parts.Dialog)
local Util = require(UI.Screens.Parts.Util)
local PostcardView = require(UI.Screens.Parts.PostcardView)

local New = Create.New
local C = Theme.Colors

local Postcards = { Name = "Postcards", Dependencies = {} }

Postcards.FriendSource = nil

local ctx
local seen = {} -- [cardId] = true: cards already known (shown, queued or there at load)
local queue = {} -- cards waiting behind the open one
local current = nil -- { card, view, dialog }
local picker = nil

local function cards()
	return ctx.Store:Get("profile.Postcards.cards") or {}
end

local function fetchFriends()
	if Postcards.FriendSource then
		return Postcards.FriendSource()
	end
	local list = {}
	pcall(function()
		local pages = Players:GetFriendsAsync(ctx.Player.UserId)
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
		return string.lower(a.name) < string.lower(b.name)
	end)
	return list
end

local function showNext()
	if current or #queue == 0 then
		return
	end
	local card = table.remove(queue, 1)
	-- It may have dropped out of the album (or been replaced) since it was queued.
	local live = cards()[card.id]
	Postcards:Show(live or card)
end

function Postcards:Show(card, opts: { fromAlbum: boolean? }?)
	local options = opts or {}
	if current then
		current.dialog.Close()
	end
	local entry = { card = card }
	local own = card.from == false
	local buttons = {
		{
			Text = "Flip",
			Color = C.Blue,
			OnClick = function()
				entry.view:Flip()
				ctx:Sound("Whoosh")
				return false
			end,
		},
	}
	if own then
		table.insert(buttons, {
			Text = "Send",
			Color = C.Pink,
			OnClick = function()
				Postcards:PickFriend(card.id)
				return false
			end,
		})
	end
	if not options.fromAlbum then
		table.insert(buttons, {
			Text = "Album",
			Color = C.Orange,
			OnClick = function()
				ctx.Router:Open("Album", { region = card.region })
			end,
		})
	end
	entry.dialog = Dialog.show(ctx.UI.Top, {
		Title = if own then "A postcard from your squad" else "A postcard from a friend",
		Color = C.Orange,
		Size = Vector2.new(640, 488),
		Build = function(content)
			local holder = New("Frame", {
				Name = "CardHolder",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(584, 316),
				LayoutOrder = 2,
				Parent = content,
			})
			entry.view = PostcardView.new(card, { Size = UDim2.fromScale(1, 1), Parent = holder })
			local fav = card.fav == true -- never write into the Store's own table
			local star
			star = Button.new({
				Name = "Keep",
				Text = if card.fav then "★" else "☆",
				Color = if card.fav then C.Gold else C.Gray,
				Size = UDim2.fromOffset(46, 46),
				Position = UDim2.fromOffset(6, 6),
				ZIndex = 8,
				Parent = holder,
				OnClick = function()
					local ok, res = Util.request(ctx, "Postcards.Favourite", { card = card.id, on = not fav })
					if ok then
						fav = res.fav
						star:SetText(if res.fav then "★" else "☆")
						star:SetColor(if res.fav then C.Gold else C.Gray)
						ctx:Toast(if res.fav then "Kept in your album for good" else "This postcard can drop out of the album now", "info")
					end
				end,
			})
		end,
		Buttons = buttons,
		OnClose = function()
			if entry.view then
				entry.view:Destroy()
			end
			if current == entry then
				current = nil
			end
			showNext()
		end,
	})
	current = entry
	ctx:Sound("ItemPop")
	return entry
end

function Postcards:Current()
	return current
end

function Postcards:Pending(): number
	return #queue
end

function Postcards:PickFriend(cardId: string)
	if picker then
		picker.Close()
	end
	local friends = fetchFriends()
	picker = Dialog.show(ctx.UI.Top, {
		Title = "Send to a friend",
		Color = C.Pink,
		Size = Vector2.new(520, 420),
		ZIndex = 60,
		Build = function(content, close)
			if #friends == 0 then
				Util.text({
					Text = "No Roblox friends found. Postcards go to Roblox friends only.",
					Size = UDim2.new(1, -20, 0, 60),
					LayoutOrder = 1,
					Parent = content,
				})
				return
			end
			Util.text({
				Text = "They'll find it in their album, even if they're offline.",
				TextSize = Theme.TextSize.Small,
				Size = UDim2.new(1, -20, 0, 24),
				LayoutOrder = 1,
				Parent = content,
			})
			local list = Widgets.List({ Size = UDim2.new(1, -8, 0, 280), Padding = 6, Parent = content })
			list.LayoutOrder = 2
			for i, friend in friends do
				Button.new({
					Name = "Friend_" .. tostring(friend.userId),
					Text = friend.name,
					Color = if friend.online then C.Green else C.Blue,
					Size = UDim2.new(1, -16, 0, 48),
					TextSize = Theme.TextSize.Body,
					LayoutOrder = i,
					Parent = list,
					OnClick = function()
						local ok, res = Util.requestOnce(ctx, "Postcards.Send", { card = cardId, to = friend.userId })
						if ok then
							ctx:Toast(string.format("Postcard sent to %s! %d left today", friend.name, res.left), "success")
							close()
						end
					end,
				}).Root
					:SetAttribute("Localize", false)
			end
		end,
		OnClose = function()
			picker = nil
		end,
	})
end

local function scan(value)
	local fresh = {}
	for id, card in value or {} do
		if not seen[id] then
			seen[id] = true
			if card.from == false then
				table.insert(fresh, card)
			end
		end
	end
	table.sort(fresh, function(a, b)
		return (a.n or 0) < (b.n or 0)
	end)
	for _, card in fresh do
		table.insert(queue, card)
	end
	showNext()
end

function Postcards.Init(context)
	ctx = context
	table.clear(seen)
	table.clear(queue)
	current, picker = nil, nil
end

function Postcards.Start()
	ctx.Store:WhenReady(function()
		for id in cards() do
			seen[id] = true
		end
		ctx.Store:Observe("profile.Postcards.cards", scan)
	end)
end

return Postcards
