--[[
	WelcomeBack (S3): the "while you were away" summary shown when a player returns.

	Session (session.WelcomeBack):
	  { pending: boolean, awaySeconds, coins, items = { { kind, text, icon? } } }
	The client opens the Welcome Back screen whenever `pending` is true.

	During a join, other systems publish `WelcomeItem` from their PlayerAdded hooks
	("3 eggs ready to hatch", "1 monster grew up", …). They are buffered per player and, on
	PlayerReady, combined with the offline coin-jar total from Ranch:JarTotal. The summary is
	only shown after at least Economy.WelcomeBackMinSeconds away and when there is something
	to show. While it is pending, Ranch's Auto-Collect pass holds off so the claim (and its
	optional ×2 ad) pays the whole offline haul.

	Actions:
	  WelcomeBack.Claim { double }   collects every jar (×2 after Monetization:WatchAd(player,
	                                 "welcomeDouble")) and clears `pending`.
	No public API; no save data.
]]

local WelcomeBack = {
	Name = "WelcomeBack",
	Dependencies = { "Ranch" },
	OptionalDependencies = { "Monetization" },
}

local ctx
local Config
local Ranch

local buffered = {} -- [player] = { item } collected while the player is joining
local claiming = {} -- [player] = true while the ×2 ad is showing

local function setPending(player, value: boolean)
	local sess = ctx:Session(player)
	sess.pending = value
	Ranch:HoldAutoCollect(player, value)
	ctx:DirtySession(player)
end

local function watchAd(player, placement: string)
	local M = ctx:GetSystem("Monetization")
	if not M or not Config.Flags.RewardedAds then
		ctx:Fail("Ads aren't available")
	end
	if M.CanWatchAd then
		local ok, why = M:CanWatchAd(player, placement)
		if not ok then
			ctx:Fail(why or "Ads aren't available")
		end
	elseif M.AdsLeft and M:AdsLeft(player, placement) <= 0 then
		ctx:Fail("No more ads today. Come back tomorrow!")
	end
	if not M:WatchAd(player, placement) then
		ctx:Fail("The ad didn't finish")
	end
end

function WelcomeBack.Init(context)
	ctx = context
	Config = ctx.Config
	Ranch = ctx:GetSystem("Ranch")

	ctx.Bus:Subscribe("WelcomeItem", function(player, detail)
		if player == nil or ctx:IsReady(player) or type(detail) ~= "table" or type(detail.text) ~= "string" then
			return -- only the join summary is collected; mid-session items are toasts elsewhere
		end
		local list = buffered[player]
		if not list then
			list = {}
			buffered[player] = list
		end
		table.insert(list, { kind = tostring(detail.kind or "info"), text = detail.text, icon = detail.icon })
	end)

	ctx.Bus:Subscribe("PlayerReady", function(player, info)
		local items = buffered[player] or {}
		buffered[player] = nil
		local sess = ctx:Session(player)
		if not sess then
			return
		end
		local away = info.awaySeconds or 0
		local coins = Ranch:JarTotal(player)
		if away >= Config.Economy.WelcomeBackMinSeconds and (coins > 0 or #items > 0) then
			sess.awaySeconds = away
			sess.coins = coins
			sess.items = items
			setPending(player, true)
		end
	end)

	ctx.Net:Handle("WelcomeBack.Claim", function(player, payload)
		local sess = ctx:Session(player)
		if not sess.pending then
			ctx:Fail("Nothing to claim")
		end
		if claiming[player] then
			ctx:Fail("An ad is already playing")
		end
		if payload.double then
			claiming[player] = true
			local ok, err = pcall(watchAd, player, "welcomeDouble")
			claiming[player] = nil
			if not ok then
				error(err, 0) -- re-raise the player-facing failure
			end
			-- The ad yields: a second request may have claimed meanwhile.
			sess = ctx:Session(player)
			if not sess or not sess.pending then
				ctx:Fail("Nothing to claim")
			end
		end
		setPending(player, false)
		local coins = Ranch:CollectAll(player, if payload.double then 2 else 1)
		return { coins = coins }
	end)
end

function WelcomeBack.PlayerAdded(player, _info)
	local sess = ctx:Session(player)
	sess.pending = false
	sess.awaySeconds = 0
	sess.coins = 0
	sess.items = {}
	ctx:DirtySession(player)
end

function WelcomeBack.PlayerRemoving(player)
	buffered[player] = nil
	claiming[player] = nil
end

return WelcomeBack
