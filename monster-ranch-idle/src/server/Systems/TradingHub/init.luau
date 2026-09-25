--[[
	TradingHub (update 3.0 · Year Two): the cross-server Trading Hub place and its Trade Board.
	Rules and layout: Config/TradingHub.

	The same server code runs on both places; this system decides the mode
	(Config.TradingHub.Mode(Services.PlaceId, Services.PlaceMode)) and publishes it. On the
	hub, Plots hands out no ranch plots and World builds the hub layout instead of the map.

	Cross-server data: the Trade Board (ctx.Services.HubBoard), ads from every hub server
	  Ad = { id, userId, name, jobId, offer = { Offer }, wants = { wantId }, note, postedAt, expiresAt }
	  Offer = { kind = "monster", appearance } | { kind = "egg", egg = eggType }
	An ad is removed when its poster posts again, removes it, completes a trade or leaves.

	Global state (global.TradingHub):
	  mode       "main" | "hub"
	  ads        { Ad + here: boolean }   -- newest first; `here` = the poster is on this server
	  refreshedAt
	Session (session.TradingHub): { ad: adId | false, postedAt }

	Actions:
	  TradingHub.Travel                  -- main place → a hub server (profile saved first)
	  TradingHub.Return                  -- hub → the main place
	  TradingHub.Post { items = { { kind, id } }, wants, note }   -- hub only
	  TradingHub.Remove                  -- your ad
	  TradingHub.Refresh                 -- re-reads the board now
	  TradingHub.Meet { ad } -> { here = true, userId } | { teleporting = true }
	    here: the client sends Trade.Request { target = userId }; otherwise you are teleported
	    to the poster's hub server.
	Publishes HubTravel (player, { to = "hub"|"main"|"server" }) and HubAdPosted (player, {}).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Appearance = require(Shared.Logic.Appearance)

local TradingHub = {
	Name = "TradingHub",
	Dependencies = { "Progression", "Monsters" },
	OptionalDependencies = { "Eggs" },
}

local ctx
local Config -- Config.TradingHub
local Progression, Monsters, Eggs

local mode = "main"
local myAd = {} -- [player] = adId
local lastPost = {} -- [player] = unix
local nextAd = 0
local reading = false

local function global()
	return ctx:Global()
end

local function isHub(): boolean
	return mode == "hub"
end

-- Board --------------------------------------------------------------------------------

local function readBoard()
	local board = ctx.Services.HubBoard
	if not board or reading then
		return false
	end
	reading = true
	local ok, ads = board.List(Config.BoardSize)
	reading = false
	if not ok then
		return false
	end
	local G = global()
	local list = {}
	local now = ctx:Now()
	for _, ad in ads do
		if type(ad) == "table" and (tonumber(ad.expiresAt) or 0) > now then
			local copy = table.clone(ad)
			copy.here = ad.jobId == ctx.Services.JobId
			table.insert(list, copy)
		end
	end
	G.ads = list
	G.refreshedAt = now
	ctx:DirtyGlobal()
	return true
end

local function removeAd(player)
	local id = myAd[player]
	if not id then
		return
	end
	myAd[player] = nil
	local board = ctx.Services.HubBoard
	if board then
		board.Remove(id)
	end
	local G = global()
	for i, ad in G.ads do
		if ad.id == id then
			table.remove(G.ads, i)
			ctx:DirtyGlobal()
			break
		end
	end
	if ctx:IsReady(player) then
		local sess = ctx:Session(player)
		sess.ad = false
		ctx:DirtySession(player)
	end
end

-- Actions ------------------------------------------------------------------------------

-- The target place's id: a pinned Config id, else the universe place with that name (the main
-- place also falls back to "any place that isn't the hub"). Found ids are cached.
local resolved = {} -- [which] = placeId
local function placeId(which: string): number
	local pinned = Config.PlaceIds[which]
	if pinned and pinned ~= 0 then
		return pinned
	end
	if resolved[which] then
		return resolved[which]
	end
	local places = ctx.Services.Places
	local ok, list = false, {}
	if places then
		ok, list = places.List()
	end
	if ok then
		local want = string.lower(Config.PlaceNames[which] or "")
		local hubName = string.lower(Config.PlaceNames.Hub)
		local fallback = nil
		for _, place in list do
			local name = string.lower(tostring(place.name))
			if name == want then
				resolved[which] = place.placeId
				return place.placeId
			end
			if which == "Main" and name ~= hubName and place.placeId ~= ctx.Services.PlaceId and not fallback then
				fallback = place.placeId
			end
		end
		if fallback then
			resolved[which] = fallback
			return fallback
		end
	end
	ctx:Fail(if which == "Hub" then "The Trading Hub isn't open yet" else "Couldn't find your ranch. Try again!")
	return 0
end

local function travel(player)
	if isHub() then
		ctx:Fail("You're already in the Trading Hub")
	end
	Progression:Require(player, Config.Unlock)
	local target = placeId("Hub")
	ctx:SaveNow(player)
	local ok, err = ctx.Services.Teleport.ToPlace(player, target)
	if not ok then
		ctx:Fail("Couldn't reach the Trading Hub (" .. tostring(err) .. "). Try again!")
	end
	ctx.Bus:Publish("HubTravel", player, { to = "hub" })
	return { teleporting = true }
end

local function goBack(player)
	if not isHub() then
		ctx:Fail("You're already on your ranch")
	end
	local target = placeId("Main")
	removeAd(player)
	ctx:SaveNow(player)
	local ok, err = ctx.Services.Teleport.ToPlace(player, target)
	if not ok then
		ctx:Fail("Couldn't get back to your ranch (" .. tostring(err) .. "). Try again!")
	end
	ctx.Bus:Publish("HubTravel", player, { to = "main" })
	return { teleporting = true }
end

local function offerOf(player, item)
	if item.kind == "monster" then
		local m = Monsters:Get(player, item.id)
		if not m then
			ctx:Fail("That monster doesn't exist")
		end
		if m.locked then
			ctx:Fail(Appearance.Of(m).name .. " is locked. Unlock it to trade it")
		end
		return { kind = "monster", appearance = Appearance.Of(m) }
	end
	if not Eggs then
		ctx:Fail("Eggs can't be traded here")
	end
	local egg = Eggs:Get(player, item.id)
	if not egg then
		ctx:Fail("That egg doesn't exist")
	end
	return { kind = "egg", egg = egg.type }
end

local function post(player, items, wants, note: number)
	if not isHub() then
		ctx:Fail("Post ads from the Trading Hub")
	end
	Progression:Require(player, Config.Unlock)
	local now = ctx:Now()
	if lastPost[player] and now - lastPost[player] < Config.PostCooldown then
		ctx:Fail(string.format("Wait %d seconds before posting again", Config.PostCooldown - (now - lastPost[player])))
	end
	local seen = {}
	local offer = {}
	for _, item in items do
		local key = item.kind .. ":" .. item.id
		if seen[key] then
			ctx:Fail("You listed the same thing twice")
		end
		seen[key] = true
		table.insert(offer, offerOf(player, item))
	end
	local tags = {}
	for _, w in wants do
		if not table.find(tags, w) then
			table.insert(tags, w)
		end
	end
	removeAd(player)
	nextAd += 1
	local ad = {
		id = string.format("%s-%d-%d", string.sub(ctx.Services.JobId, 1, 24), player.UserId, nextAd),
		userId = player.UserId,
		name = player.DisplayName or player.Name,
		jobId = ctx.Services.JobId,
		offer = offer,
		wants = tags,
		note = note,
		postedAt = now,
		expiresAt = now + Config.AdSeconds,
	}
	local board = ctx.Services.HubBoard
	if not board or not board.Post(ad, Config.AdSeconds) then
		ctx:Fail("The Trade Board is busy. Try again in a moment")
	end
	myAd[player] = ad.id
	lastPost[player] = now
	local sess = ctx:Session(player)
	sess.ad = ad.id
	sess.postedAt = now
	ctx:DirtySession(player)
	readBoard()
	ctx.Bus:Publish("HubAdPosted", player, {})
	return { ad = ad.id }
end

local function meet(player, adId: string)
	if not isHub() then
		ctx:Fail("Meet traders in the Trading Hub")
	end
	local target = nil
	for _, ad in global().ads do
		if ad.id == adId then
			target = ad
			break
		end
	end
	if not target then
		ctx:Fail("That ad is gone. Refresh the board!")
	end
	if target.userId == player.UserId then
		ctx:Fail("That's your own ad")
	end
	if target.jobId == ctx.Services.JobId then
		return { here = true, userId = target.userId }
	end
	local ok, err = ctx.Services.Teleport.ToServer(player, placeId("Hub"), target.jobId)
	if not ok then
		ctx:Fail("Couldn't join that server (" .. tostring(err) .. ")")
	end
	ctx.Bus:Publish("HubTravel", player, { to = "server" })
	return { teleporting = true }
end

-- Lifecycle ----------------------------------------------------------------------------

function TradingHub.Init(context)
	ctx = context
	Config = ctx.Config.TradingHub
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	Eggs = ctx:GetSystem("Eggs")
	table.clear(myAd)
	table.clear(lastPost)
	table.clear(resolved)
	nextAd = 0
	reading = false
	mode = Config.Mode(ctx.Services.PlaceId, ctx.Services.PlaceMode)

	local G = global()
	G.mode = mode
	G.ads = {}
	G.refreshedAt = 0
	ctx:DirtyGlobal()

	ctx.Net:Handle("TradingHub.Travel", travel)
	ctx.Net:Handle("TradingHub.Return", goBack)
	ctx.Net:Handle("TradingHub.Post", function(player, payload)
		return post(player, payload.items, payload.wants, payload.note)
	end)
	ctx.Net:Handle("TradingHub.Remove", function(player)
		removeAd(player)
		return {}
	end)
	ctx.Net:Handle("TradingHub.Refresh", function()
		if not readBoard() then
			ctx:Fail("The Trade Board is busy. Try again in a moment")
		end
		return { ads = #global().ads }
	end)
	ctx.Net:Handle("TradingHub.Meet", function(player, payload)
		return meet(player, payload.ad)
	end)

	ctx.Bus:Subscribe("TradeCompleted", function(player)
		removeAd(player)
	end)
	-- Every server shows the board (the main place's Trading Hub building previews it).
	ctx:Every(Config.RefreshSeconds, function()
		readBoard()
	end)
end

function TradingHub.PlayerAdded(player)
	local sess = ctx:Session(player)
	sess.ad = false
	sess.postedAt = 0
	ctx:DirtySession(player)
end

function TradingHub.PlayerRemoving(player)
	removeAd(player)
	lastPost[player] = nil
end

-- The place mode, for Plots and World (they must not hand out plots on the hub).
function TradingHub:Mode(): string
	return mode
end

return TradingHub
