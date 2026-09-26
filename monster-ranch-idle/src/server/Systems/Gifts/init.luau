--[[
	Gifts (glow-up L): send an egg from storage, food, a decor piece or an accessory to a Roblox
	friend, and buy a friend a Ranch Pass. Tuning in Config.Community.Gifts / .PassGift, pure
	gates in Logic/Community.

	Delivery is the Market mailbox (Market:Send / Market:RegisterMail), so a friend on another
	server or offline gets the gift on their next join, and a crash can repeat a delivery (the
	entry id dedups it) but never lose one. Gifts are one-way and can't be undone; nothing is
	asked in return, so a gift can't be used to scam.

	Anti-funnel gates (fresh alt accounts can't feed a main): the sender needs Ranch Level
	`minLevel`, `minPlaySeconds` of play in this game and a Roblox account `minAccountDays` old,
	and sends at most `perDay` gifts a UTC day, `perFriendPerDay` to one friend. The recipient
	must be the sender's Roblox friend (checked on the server at both steps).

	Two steps: Gifts.Prepare checks everything and returns a token for the confirm dialog (what
	leaves, who gets it, gifts left); Gifts.Send spends the token (valid `confirmSeconds`), checks
	again, takes the item out of the profile and mails it.

	Save section (profile.Gifts), version 1:
	  day, sent, to = { ['u'..userId] = n }     -- today's counters (UTC day)
	  totalSent, totalReceived
	  seq                                        -- private: gift id counter
	  passTarget = { userId, name, at } | false  -- private: the friend a Ranch Pass gift goes to

	Mail entry: { id = "gift:<sender>:<seq>" | "passgift:<purchaseId>", kind = "gift",
	              gift = { kind = "egg"|"food"|"decor"|"accessory"|"pass", id?, amount }, from, fromName }

	Actions: Gifts.Prepare { to, kind, item, amount }, Gifts.Send { token }, Gifts.PassTarget { to }.
	Product: handler "Gifts.RanchPass" (+ its CanBuy check: a friend picked, a season on sale).
	Bus: publishes GiftSent.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Community)
local Format = require(Shared.Logic.Format)

local Gifts = {
	Name = "Gifts",
	Dependencies = { "Currency", "Progression", "Rewards", "Market" },
	OptionalDependencies = { "Eggs", "Shop", "Accessories", "Monetization", "Quests" },
}

Gifts.Profile = {
	Version = 1,
	Default = function()
		return { day = 0, sent = 0, to = {}, totalSent = 0, totalReceived = 0, seq = 0, passTarget = false }
	end,
	Private = { "seq", "passTarget" },
}

local ctx
local Config, Cfg
local Currency, Progression, Rewards, Market

local pending = {} -- [player] = { token, to, name, kind, item, amount, expiresAt }
local tokens = 0

-- Helpers -------------------------------------------------------------------------------------

local function section(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

local function displayName(player): string
	return player.DisplayName or player.Name
end

local function today(player, s)
	local day = ctx:Day()
	if s.day ~= day then
		s.day = day
		s.sent = 0
		s.to = {}
		ctx:Dirty(player, "day")
		ctx:Dirty(player, "sent")
		ctx:Dirty(player, "to")
	end
end

-- The Roblox account's age in days, or nil when the player object can't say (tests).
local function accountDays(player): number?
	local ok, age = pcall(function()
		return player.AccountAge
	end)
	return if ok and type(age) == "number" then age else nil
end

local function checkSender(player)
	local meta = ctx:Meta(player)
	local ok, why, need = Logic.GiftGate({
		level = Progression:GetLevel(player),
		playSeconds = meta and meta.playSeconds or 0,
		accountDays = accountDays(player),
	}, Cfg)
	if ok then
		return
	end
	if why == "level" then
		ctx:Fail(string.format("Gifts unlock at Ranch Level %d", need))
	elseif why == "play" then
		ctx:Fail(string.format("You can send gifts after %s more play time", Format.duration(need or 0)))
	else
		ctx:Fail("Your Roblox account is too new to send gifts")
	end
end

local function checkLimits(player, s, to: number)
	today(player, s)
	local left, forFriend = Logic.DailyLeft(s, Cfg, "u" .. to)
	if left <= 0 then
		ctx:Fail(string.format("You've sent all %d gifts for today. More tomorrow!", Cfg.perDay))
	end
	if forFriend <= 0 then
		ctx:Fail("You can send this friend more gifts tomorrow")
	end
	return left
end

local function isFriend(player, to: number): boolean
	local players = ctx.Services.Players
	local ok, result = pcall(players.IsFriendsWith, player, to)
	return ok and result == true
end

local function nameOf(to: number): string | false
	local online = ctx:PlayerByUserId(to)
	if online then
		return displayName(online)
	end
	local players = ctx.Services.Players
	local ok, name = pcall(function()
		return players.NameOf and players.NameOf(to)
	end)
	return if ok and type(name) == "string" then name else false
end

-- Does the player hold the item (egg id / flavor / decor id / accessory id) right now?
local function checkItem(player, kind: string, item: string, amount: number)
	if kind == "egg" then
		local Eggs = ctx:GetSystem("Eggs")
		if not Eggs or not Eggs:Get(player, item) then
			ctx:Fail("Only eggs in storage can be sent")
		end
	elseif kind == "food" then
		if not table.find(Config.Food.Ids, item) then
			ctx:Fail("That food doesn't exist")
		end
		if Currency:Balance(player, "food." .. item) < amount then
			ctx:Fail("You don't have that much food")
		end
	elseif kind == "decor" then
		local Shop = ctx:GetSystem("Shop")
		if not Config.Decor.ById[item] or not Shop or Shop:DecorCount(player, item) <= 0 then
			ctx:Fail("You don't have that decor in storage")
		end
	elseif kind == "accessory" then
		local Accessories = ctx:GetSystem("Accessories")
		local stored = if Accessories and Config.Accessories.ById[item] then Accessories:Stored(player, item) else 0
		if not Config.Accessories.ById[item] or stored <= 0 then
			ctx:Fail("You don't have that accessory in storage")
		end
	else
		ctx:Fail("That can't be sent as a gift")
	end
end

-- Takes the item out of the profile; returns the gift record the friend receives.
local function takeItem(player, kind: string, item: string, amount: number)
	if kind == "egg" then
		local record = ctx:GetSystem("Eggs"):Remove(player, item)
		return if record then { kind = "egg", id = record.type, amount = 1 } else nil
	elseif kind == "food" then
		local ok = Currency:Spend(player, { ["food." .. item] = amount }, "gift")
		return if ok then { kind = "food", id = item, amount = amount } else nil
	elseif kind == "decor" then
		local ok = ctx:GetSystem("Shop"):TakeDecor(player, item)
		return if ok then { kind = "decor", id = item, amount = 1 } else nil
	elseif kind == "accessory" then
		local ok = ctx:GetSystem("Accessories"):Take(player, item)
		return if ok then { kind = "accessory", id = item, amount = 1 } else nil
	end
	return nil
end

-- Everything that must hold at both steps. Yields (the friendship check), so the cheap checks
-- run first and the item is checked again after the yield.
local function checkAll(player, to: number, kind: string, item: string, amount: number): number
	if to == player.UserId then
		ctx:Fail("You can't send a gift to yourself")
	end
	checkSender(player)
	local s = section(player)
	checkLimits(player, s, to)
	checkItem(player, kind, item, amount)
	if not isFriend(player, to) then
		ctx:Fail("You can only send gifts to your Roblox friends")
	end
	s = section(player)
	local left = checkLimits(player, s, to)
	checkItem(player, kind, item, amount)
	return left
end

-- Actions -------------------------------------------------------------------------------------

local function prepare(player, payload)
	local kind, item = payload.kind, payload.item
	local amount = if kind == "food" then payload.amount else 1
	local left = checkAll(player, payload.to, kind, item, amount)
	tokens += 1
	local token = string.format("g%d-%d", player.UserId % 1000000, tokens)
	local name = nameOf(payload.to)
	pending[player] = {
		token = token,
		to = payload.to,
		name = name,
		kind = kind,
		item = item,
		amount = amount,
		expiresAt = ctx:Now() + Cfg.confirmSeconds,
	}
	return { token = token, name = name, kind = kind, item = item, amount = amount, left = left }
end

local function send(player, payload)
	local p = pending[player]
	if not p or p.token ~= payload.token then
		ctx:Fail("That gift expired. Try again")
	end
	pending[player] = nil -- spent before anything yields: one confirm sends one gift
	if ctx:Now() > p.expiresAt then
		ctx:Fail("That gift expired. Try again")
	end
	checkAll(player, p.to, p.kind, p.item, p.amount)
	local s = section(player)
	local gift = takeItem(player, p.kind, p.item, p.amount)
	if not gift then
		ctx:Fail("You don't have that any more")
	end
	today(player, s)
	s.sent += 1
	s.to["u" .. p.to] = (s.to["u" .. p.to] or 0) + 1
	s.totalSent += 1
	s.seq += 1
	ctx:Dirty(player, "sent")
	ctx:Dirty(player, "to")
	ctx:Dirty(player, "totalSent")
	Market:Send(player, p.to, {
		id = string.format("gift:%d:%d", player.UserId, s.seq),
		kind = "gift",
		gift = gift,
		from = player.UserId,
		fromName = displayName(player),
	})
	ctx:RequestSave(player)
	ctx.Bus:Publish("GiftSent", player, { kind = gift.kind, to = p.to })
	ctx.Analytics.Custom(player, "GiftSent", 1, { kind = gift.kind })
	local left = Logic.DailyLeft(s, Cfg)
	return { left = left }
end

local function passTarget(player, payload)
	local to = payload.to
	if to == player.UserId then
		ctx:Fail("Pick a friend to send the Ranch Pass to")
	end
	section(player)
	if not isFriend(player, to) then
		ctx:Fail("You can only send gifts to your Roblox friends")
	end
	local s = section(player)
	local name = nameOf(to)
	s.passTarget = { userId = to, name = name, at = ctx:Now() }
	return { name = name }
end

-- Receiving -----------------------------------------------------------------------------------

local VALID = {
	egg = function(id)
		return Config.Eggs.ById[id] ~= nil
	end,
	food = function(id)
		return table.find(Config.Food.Ids, id) ~= nil
	end,
	decor = function(id)
		return Config.Decor.ById[id] ~= nil
	end,
	accessory = function(id)
		return Config.Accessories.ById[id] ~= nil
	end,
	pass = function()
		return true
	end,
}

-- Market mail of kind "gift". true = done (removed from the mailbox), false = keep for later.
local function receive(player, entry): boolean
	local s = ctx:Section(player)
	local gift = type(entry.gift) == "table" and entry.gift or nil
	local check = gift and VALID[gift.kind]
	if not s or not gift or not check or not check(gift.id) then
		if s then
			warn("[Gifts] dropping a malformed gift " .. tostring(entry.id))
		end
		return s ~= nil
	end
	local amount = math.clamp(math.floor(tonumber(gift.amount) or 1), 1, Cfg.maxFood)
	local from = if type(entry.fromName) == "string" then entry.fromName else "A friend"
	if gift.kind == "pass" then
		local Quests = ctx:GetSystem("Quests")
		if not Quests or not Quests:GrantPass(player) then
			return false
		end
		ctx:Notify(player, string.format("%s gave you a Ranch Pass!", from), "reward")
	else
		if gift.kind == "egg" then
			local Eggs = ctx:GetSystem("Eggs")
			if not Eggs or Eggs:Room(player) < amount then
				return false -- egg storage full: it waits in the mailbox
			end
		end
		Rewards:Grant(player, { { kind = gift.kind, id = gift.id, amount = amount } }, "gift")
		ctx:Notify(player, string.format("%s sent you a gift!", from), "reward")
	end
	s.totalReceived += 1
	ctx:Dirty(player, "totalReceived")
	return true
end

-- Ranch Pass gift (developer product) ------------------------------------------------------

local function freshTarget(s)
	local t = s and s.passTarget
	if type(t) ~= "table" or type(t.userId) ~= "number" then
		return nil
	end
	if ctx:Now() - (tonumber(t.at) or 0) > Config.Community.PassGift.targetSeconds then
		return nil
	end
	return t
end

local function canBuyPassGift(player, _product): (boolean, string?)
	local s = ctx:Section(player)
	if not s then
		return false, "Your ranch is still loading"
	end
	if not Config.Quests.PassOnSale(ctx:Now()) then
		return false, "The Ranch Pass isn't on sale right now"
	end
	if not freshTarget(s) then
		return false, "Pick a friend to send the Ranch Pass to"
	end
	return true, nil
end

local function onPassGift(player, _product, receiptInfo): boolean
	local s = ctx:Section(player)
	if not s then
		return false
	end
	local target = freshTarget(s)
	if not target then
		-- The friend was never picked or the pick went stale: the pass is the buyer's own.
		local Quests = ctx:GetSystem("Quests")
		return Quests ~= nil and Quests:GrantPass(player)
	end
	local purchaseId = tostring(receiptInfo and receiptInfo.PurchaseId or (s.seq + 1))
	Market:Send(player, target.userId, {
		id = "passgift:" .. purchaseId,
		kind = "gift",
		gift = { kind = "pass", amount = 1 },
		from = player.UserId,
		fromName = displayName(player),
	})
	s.passTarget = false
	s.totalSent += 1
	ctx:Dirty(player, "totalSent")
	local name = if type(target.name) == "string" then target.name else "your friend"
	ctx:Notify(player, string.format("Your Ranch Pass gift is on its way to %s!", name), "success")
	ctx.Bus:Publish("GiftSent", player, { kind = "pass", to = target.userId })
	return true
end

-- Public API ----------------------------------------------------------------------------------

function Gifts:SentToday(player): number
	local s = ctx:Section(player)
	return if s and s.day == ctx:Day() then s.sent else 0
end

-- Lifecycle -----------------------------------------------------------------------------------

function Gifts.Init(context)
	ctx = context
	Config = ctx.Config
	Cfg = Config.Community.Gifts
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")
	Market = ctx:GetSystem("Market")
	table.clear(pending)
	tokens = 0

	ctx.Net:Handle("Gifts.Prepare", prepare)
	ctx.Net:Handle("Gifts.Send", send)
	ctx.Net:Handle("Gifts.PassTarget", passTarget)
end

function Gifts.Start()
	Market:RegisterMail("gift", receive)
	local Monetization = ctx:GetSystem("Monetization")
	if Monetization then
		Monetization:RegisterProduct("Gifts.RanchPass", onPassGift)
		Monetization:RegisterProductCheck("Gifts.RanchPass", canBuyPassGift)
	end
end

function Gifts.PlayerRemoving(player)
	pending[player] = nil
end

return Gifts
