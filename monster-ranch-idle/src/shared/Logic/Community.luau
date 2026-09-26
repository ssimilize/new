--[[
	Logic/Community (glow-up L): pure rules for gifts, invites and the VIP balcony. No Roblox
	APIs, so everything here is unit-tested in Lune (Community.spec).

	  Community.Week(day) -> number                      UTC week number (weeks start on Monday)
	  Community.ParseInvite(launchData, prefix) -> userId?  "invite:123" (or a table with LaunchData)
	  Community.InviteData(userId, prefix) -> string        the launch data an invite carries
	  Community.GiftGate(state, cfg) -> (ok, reason?, value?)  sender gates, see below
	  Community.DailyLeft(counts, cfg, friendKey?) -> (left, leftForFriend)
	  Community.InDeck(position, cfg) -> boolean          is { x, y, z } on or above the VIP deck
]]

local Community = {}

-- 1 Jan 1970 was a Thursday: shifting by 3 days makes every week start on Monday.
function Community.Week(day: number): number
	return math.floor((day + 3) / 7)
end

function Community.InviteData(userId: number, prefix: string): string
	return prefix .. tostring(math.floor(userId))
end

-- The inviter's user id from a join's launch data, or nil when it isn't one of our invites.
function Community.ParseInvite(launchData: any, prefix: string): number?
	if type(launchData) == "table" then
		launchData = launchData.LaunchData
	end
	if type(launchData) ~= "string" or #launchData > 64 then
		return nil
	end
	if string.sub(launchData, 1, #prefix) ~= prefix then
		return nil
	end
	local digits = string.sub(launchData, #prefix + 1)
	if not string.match(digits, "^%d+$") or #digits > 15 then
		return nil
	end
	local userId = tonumber(digits)
	return if userId and userId > 0 then userId else nil
end

--[[
	Sender gates, cheapest first. state = { level, playSeconds, accountDays? } (accountDays nil when
	unknown). Returns true, or false with a reason key and the number it needs:
	  "level" (level needed), "play" (seconds still to play), "account" (days still to wait).
]]
function Community.GiftGate(state, cfg): (boolean, string?, number?)
	if (tonumber(state.level) or 0) < cfg.minLevel then
		return false, "level", cfg.minLevel
	end
	local played = tonumber(state.playSeconds) or 0
	if played < cfg.minPlaySeconds then
		return false, "play", cfg.minPlaySeconds - played
	end
	local days = tonumber(state.accountDays)
	if days ~= nil and days < cfg.minAccountDays then
		return false, "account", cfg.minAccountDays - days
	end
	return true, nil, nil
end

-- Gifts left today overall and for one friend. counts = { sent, to = { [friendKey] = n } }.
function Community.DailyLeft(counts, cfg, friendKey: string?): (number, number)
	local sent = tonumber(counts and counts.sent) or 0
	local left = math.max(0, cfg.perDay - sent)
	if not friendKey then
		return left, left
	end
	local to = counts and counts.to
	local friend = tonumber(type(to) == "table" and to[friendKey]) or 0
	return left, math.min(left, math.max(0, cfg.perFriendPerDay - friend))
end

-- The deck's box: its floor footprint, from a little below the floor up to 30 studs above it.
function Community.InDeck(position: { number }, cfg): boolean
	local x, y, z = position[1], position[2], position[3]
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return false
	end
	local cx, cz = cfg.deck[1], cfg.deck[3]
	local hx, hz = cfg.deckSize[1] / 2 + 1, cfg.deckSize[2] / 2 + 1
	local floor = cfg.deck[2] + cfg.height
	return math.abs(x - cx) <= hx and math.abs(z - cz) <= hz and y >= floor - 1.5 and y <= floor + 30
end

return Community
