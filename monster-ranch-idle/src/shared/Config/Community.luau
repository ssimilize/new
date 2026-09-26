--[[
	Community (glow-up L): the emote and trick wheel, gifts to friends, friend invites, the
	"Join our group" reward, Roblox Premium perks and the VIP balcony. Tuning only: the rules are
	in Systems/Community, Systems/Gifts and Logic/Community.

	Fairness: gifts are one-way and can't be undone, so the confirm step says exactly what leaves
	and who gets it; nothing a player receives can be asked back. Gates stop fresh alt accounts
	from funnelling items: Ranch Level, play time, account age, and daily caps.
]]

local Community = {}

-- Player emotes: Roblox's own default character emotes, played by the character's Animate
-- script (the same animations as the /e chat commands). `anim` is the Animate emote name.
Community.Emotes = {
	{ id = "wave", name = "Wave", anim = "wave", glyph = "👋" },
	{ id = "point", name = "Point", anim = "point", glyph = "👉" },
	{ id = "cheer", name = "Cheer", anim = "cheer", glyph = "🎉" },
	{ id = "laugh", name = "Laugh", anim = "laugh", glyph = "😆" },
	{ id = "dance1", name = "Dance 1", anim = "dance", glyph = "💃" },
	{ id = "dance2", name = "Dance 2", anim = "dance2", glyph = "🕺" },
	{ id = "dance3", name = "Dance 3", anim = "dance3", glyph = "🎶" },
}

-- Monster tricks: the nearest monster in one of your pens plays `state` (MonsterAnimator), or
-- `fallback` while the animator has no such state yet. Everyone on the server sees it.
Community.Tricks = {
	{ id = "trick", name = "Trick", state = "trick", fallback = "happy", glyph = "✨" },
	{ id = "hop", name = "Happy hop", state = "happy", glyph = "💖" },
	{ id = "snack", name = "Snack time", state = "eat", glyph = "🍎" },
}
Community.TrickById = {}
for _, trick in Community.Tricks do
	Community.TrickById[trick.id] = trick
end
-- Glow-up Q: tricks a monster learns from bond hearts (Config.Bond.Tricks, field `bond`). They
-- share TrickById so Community.Trick and World.PlayTrick take them; the emote wheel lists only
-- Community.Tricks, and the Care screen lists these.
for _, trick in require(script.Parent.Bond).Tricks do
	Community.TrickById[trick.id] = trick
end
Community.TrickCooldown = 3 -- seconds between two tricks from one player
Community.TrickRange = 45 -- studs: the client picks the nearest own pen monster within this

-- Gifts: eggs from storage, food, decor and accessories to a Roblox friend, delivered through
-- the Market mailbox (so offline friends get them on their next join).
Community.Gifts = {
	minLevel = 10, -- the sender's Ranch Level (same as the Market)
	minPlaySeconds = 2 * 3600, -- the sender's total play time in this game
	minAccountDays = 7, -- the sender's Roblox account age
	perDay = 5, -- gifts sent per UTC day
	perFriendPerDay = 2, -- gifts to one friend per UTC day
	maxFood = 25, -- food in one gift
	confirmSeconds = 60, -- how long a confirm step stays valid
	kinds = { "egg", "food", "decor", "accessory" },
}

-- "Buy a Ranch Pass for a friend" (developer product `ranchPassGift`, Config.Monetization).
-- The friend is picked first and stays picked for `targetSeconds`. A friend who already has
-- this season's pass gets it saved for the next season (Quests), never a second copy.
Community.PassGift = { product = "ranchPassGift", targetSeconds = 10 * 60 }

-- Invites: SocialService invite with launch data "invite:<userId>". A friend who joins for the
-- first time from it gets `inviteeReward`; the inviter gets `inviterReward` by mail, at most
-- `weeklyCap` times per UTC week (Monday start).
Community.Invites = {
	launchPrefix = "invite:",
	inviteeReward = { { kind = "egg", id = "grove", amount = 1 }, { kind = "gems", amount = 25 } },
	inviterReward = { { kind = "egg", id = "grove", amount = 1 }, { kind = "gems", amount = 25 } },
	weeklyCap = 3,
}

-- "Join our group": once per account for members of Config.Quests.GroupId. The row stays hidden
-- (and the claim refuses) while GroupId is 0; docs/GO_LIVE.md has the owner's step.
Community.Group = {
	reward = { { kind = "egg", id = "crystal", amount = 1 }, { kind = "gems", amount = 50 } },
}

-- Roblox Premium members: one free Grove Egg a day (the free-egg ad's egg, without the ad)
-- and a small Premium badge on their nameplate. Kept modest on purpose.
Community.Premium = {
	daily = { { kind = "egg", id = "grove", amount = 1 } },
	badge = "Premium",
	badgeColor = "#E8E8E8",
}

-- VIP balcony: a raised deck beside the plaza (between the Feed Store and the Showtime Stage).
-- The pad on the ground takes VIP Rancher owners up; the server moves anyone else who ends up
-- on the deck back down. Placeholder geometry that World/Dress can dress later.
Community.VipBalcony = {
	pass = "vip",
	deck = { 60, 0, -66 }, -- deck centre on the ground plane
	deckSize = { 20, 14 }, -- x, z
	height = 14, -- deck floor above the ground
	pad = { 52, 0, -50 }, -- the ground pad (prompt)
	exit = { 40, 3, -40 }, -- where leaving (or being moved off) puts a character
	patrolSeconds = 2,
	nameColor = "#FFC83D", -- VIP name colour on nameplates (the VIP chat tag's gold)
}

return Community
