--[[
	Postcards (glow-up X): every finished expedition writes home. Tuning and scenes in
	Config/Postcards, pure rules in Logic/Postcards, the card in UI/Components/PostcardView.

	A postcard is recorded when an expedition is claimed (bus topic ExpeditionClaimed, one per
	slot, carrying region, stage, squad and loot). It changes nothing about the rewards. Only the
	data to redraw it is kept: never a picture.

	Save section (profile.Postcards), version 1:
	  cards = { [cardId] = Card }   -- the album (map, so one change replicates one card)
	  seq                           -- the last card number (card ids are "c" .. seq)
	  day, sent, to = { ['u'..userId] = n }   -- today's sends (UTC day)
	  totalSent, totalReceived
	  recv = { mailId }             -- private: recent received mail ids (dedup)
	Card = { id, n, region, stage, at, line, hero, squad = { SlimAppearance }, loot = { Reward },
	         fav, from = senderName|false, sent = { userId } }   (Logic/Postcards)

	Album: newest `perRegion` non-favourites per region, favourites (≤ maxFavourites) for good,
	≤ `maxTotal` in all; the oldest non-favourite drops first (Logic/Postcards.Trim).

	Mail entry (Market mailbox, kind "postcard"):
	  { id = "postcard:<senderId>:<cardId>", kind = "postcard", card, from, fromName }
	Received once per id: a repeated delivery is dropped (recv), a malformed card is dropped.

	Actions: Postcards.Favourite { card, on }, Postcards.Send { card, to }.
	Sending uses Gifts' sender gates and friend check (Gifts:Gate) and its own daily caps
	(Config.Postcards.Send, counted like gifts by Logic/Community.DailyLeft).

	Public API: Postcards:Album(player) -> { Card } (newest first), Postcards:Record(player, detail) -> Card?
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Postcards)
local Community = require(Shared.Logic.Community)
local Format = require(Shared.Logic.Format)

local Postcards = {
	Name = "Postcards",
	Dependencies = { "Monsters", "Market", "Gifts" },
}

Postcards.Profile = {
	Version = 1,
	Default = function()
		return { cards = {}, seq = 0, day = 0, sent = 0, to = {}, totalSent = 0, totalReceived = 0, recv = {} }
	end,
	Migrate = function(section, fromVersion)
		return Logic.Migrate(section, fromVersion)
	end,
	Private = { "recv" },
}

local ctx
local Config, Cfg
local Monsters, Market, Gifts

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

-- Adds a card, then drops whatever the caps push out (never the new card while room is left).
local function add(player, s, card)
	s.seq += 1
	card.id = "c" .. s.seq
	card.n = s.seq
	s.cards[card.id] = card
	ctx:Dirty(player, "seq")
	ctx:Dirty(player, "cards", card.id)
	for _, id in Logic.Trim(s.cards, Cfg) do
		s.cards[id] = nil
		ctx:Dirty(player, "cards", id)
	end
end

-- Recording ---------------------------------------------------------------------------------

function Postcards:Record(player, detail)
	local s = ctx:Section(player)
	if not s or type(detail) ~= "table" or type(detail.region) ~= "string" or type(detail.squad) ~= "table" then
		return nil
	end
	local squad = {}
	for _, id in detail.squad do
		if #squad >= Cfg.maxMonsters then
			break
		end
		local ap = Monsters:Appearance(player, id)
		if ap then
			table.insert(squad, Logic.Slim(ap))
		end
	end
	if #squad == 0 then
		return nil
	end
	local rng = ctx.Rng
	local card = {
		region = detail.region,
		stage = tonumber(detail.stage) or 0,
		at = ctx:Now(),
		line = Logic.PickLine(detail.region, Cfg, function(n)
			return rng:Int(1, n)
		end),
		hero = squad[rng:Int(1, #squad)].name,
		squad = squad,
		loot = Logic.Summarise(detail.loot, Cfg.maxLoot),
		fav = false,
		from = false,
		sent = {},
	}
	add(player, s, card)
	return card
end

function Postcards:Album(player)
	local s = ctx:Section(player)
	return Logic.Sorted(s and s.cards)
end

-- Actions ----------------------------------------------------------------------------------

local function cardOf(s, id: string)
	local card = s.cards[id]
	if not card then
		ctx:Fail("That postcard isn't in your album")
	end
	return card
end

local function favourite(player, payload)
	local s = section(player)
	local card = cardOf(s, payload.card)
	if payload.on and not card.fav and Logic.Favourites(s.cards) >= Cfg.maxFavourites then
		ctx:Fail(string.format("You can keep %d favourites. Unstar one first", Cfg.maxFavourites))
	end
	card.fav = payload.on
	ctx:Dirty(player, "cards", card.id)
	if not card.fav then
		for _, id in Logic.Trim(s.cards, Cfg) do
			s.cards[id] = nil
			ctx:Dirty(player, "cards", id)
		end
	end
	return { fav = card.fav == true, kept = s.cards[card.id] ~= nil }
end

local function checkGate(player, to: number)
	local ok, why, need = Gifts:Gate(player, to)
	if ok then
		return
	end
	if why == "self" then
		ctx:Fail("You can't send a postcard to yourself")
	elseif why == "level" then
		ctx:Fail(string.format("Postcards to friends unlock at Ranch Level %d", need or 0))
	elseif why == "play" then
		ctx:Fail(string.format("You can send postcards after %s more play time", Format.duration(need or 0)))
	elseif why == "account" then
		ctx:Fail("Your Roblox account is too new to send postcards")
	else
		ctx:Fail("You can only send postcards to your Roblox friends")
	end
end

local function send(player, payload)
	local s = section(player)
	local card = cardOf(s, payload.card)
	if card.from ~= false then
		ctx:Fail("You can only send your own postcards")
	end
	local to = payload.to
	checkGate(player, to)
	s = section(player) -- the friend check can yield
	card = cardOf(s, payload.card)
	if table.find(card.sent, to) then
		ctx:Fail("You already sent this postcard to that friend")
	end
	if #card.sent >= Cfg.maxSentPerCard then
		ctx:Fail("This postcard has been sent to enough friends")
	end
	today(player, s)
	local left, forFriend = Community.DailyLeft(s, Cfg.Send, "u" .. to)
	if left <= 0 then
		ctx:Fail(string.format("You've sent all %d postcards for today. More tomorrow!", Cfg.Send.perDay))
	end
	if forFriend <= 0 then
		ctx:Fail("You can send this friend more postcards tomorrow")
	end
	s.sent += 1
	s.to["u" .. to] = (s.to["u" .. to] or 0) + 1
	s.totalSent += 1
	table.insert(card.sent, to)
	ctx:Dirty(player, "sent")
	ctx:Dirty(player, "to")
	ctx:Dirty(player, "totalSent")
	ctx:Dirty(player, "cards", card.id)
	local outgoing = table.clone(card)
	outgoing.sent, outgoing.fav, outgoing.id, outgoing.n = nil, nil, nil, nil
	Market:Send(player, to, {
		id = string.format("postcard:%d:%s", player.UserId, card.id),
		kind = "postcard",
		card = outgoing,
		from = player.UserId,
		fromName = displayName(player),
	})
	ctx:RequestSave(player)
	ctx.Analytics.Custom(player, "PostcardSent", 1, { region = card.region })
	return { left = left - 1 }
end

-- Receiving ---------------------------------------------------------------------------------

-- Market mail of kind "postcard". true = done (removed from the mailbox), false = keep for later.
local function receive(player, entry): boolean
	local s = ctx:Section(player)
	if not s then
		return false
	end
	local mailId = tostring(entry.id)
	if table.find(s.recv, mailId) then
		return true -- a repeated delivery
	end
	local card = Logic.Clean(entry.card, Config)
	if not card then
		warn("[Postcards] dropping a malformed postcard " .. mailId)
		return true
	end
	local from = if type(entry.fromName) == "string" and #entry.fromName > 0 then string.sub(entry.fromName, 1, 30) else "A friend"
	card.from = from
	card.fav = false
	card.sent = {}
	add(player, s, card)
	table.insert(s.recv, mailId)
	while #s.recv > Cfg.recvMemory do
		table.remove(s.recv, 1)
	end
	s.totalReceived += 1
	ctx:Dirty(player, "totalReceived")
	ctx:Notify(player, string.format("%s sent you a postcard!", from), "reward")
	return true
end

-- Every load: each card passes Logic.Clean and the caps (a lowered cap or a bad card never stays).
local function normalise(player, s)
	local cards = {}
	local changed = false
	for id, raw in s.cards do
		local card = Logic.Clean(raw, Config)
		if card and card.id == id then
			cards[id] = card
		else
			changed = true
		end
	end
	for _, id in Logic.Trim(cards, Cfg) do
		cards[id] = nil
		changed = true
	end
	s.cards = cards
	if type(s.recv) ~= "table" then
		s.recv = {}
	end
	if changed then
		ctx:Dirty(player, "cards")
	end
end

-- Lifecycle ---------------------------------------------------------------------------------

function Postcards.Init(context)
	ctx = context
	Config = ctx.Config
	Cfg = Config.Postcards
	Monsters = ctx:GetSystem("Monsters")
	Market = ctx:GetSystem("Market")
	Gifts = ctx:GetSystem("Gifts")

	ctx.Net:Handle("Postcards.Favourite", favourite)
	ctx.Net:Handle("Postcards.Send", send)

	ctx.Bus:Subscribe("ExpeditionClaimed", function(player, detail)
		if ctx:IsReady(player) then
			Postcards:Record(player, detail)
		end
	end)
end

function Postcards.Start()
	Market:RegisterMail("postcard", receive)
end

function Postcards.PlayerAdded(player)
	local s = ctx:Section(player)
	if s then
		normalise(player, s)
	end
end

return Postcards
