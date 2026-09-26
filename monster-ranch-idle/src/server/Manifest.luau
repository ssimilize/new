--[[
	Manifest: the systems plugged into the server kernel.

	A system is built and tested on its own (see docs/DEVELOPMENT_PLAN.md) and becomes part
	of the game only when its folder name is listed here. Order does not matter: the kernel
	sorts by each system's declared Dependencies. Remove a line to unplug a system; any
	client request for its actions then returns "NotAvailable".
]]

return {
	Systems = {
		-- S1 · Economy core
		"Currency",
		"Progression",
		"Rewards",
		"Settings",
		-- S2 · Monsters
		"Monsters",
		-- S3 · Ranch & eggs
		"Eggs",
		"Shop",
		"Ranch",
		"WelcomeBack",
		-- S4 · Adventure
		"Expeditions",
		"Boss",
		-- S5 · Social & world
		"Breeding",
		"Weather",
		"Social",
		"Trade",
		"Plots",
		"Leaderboards",
		"Clubs",
		"Market",
		"PriceHistory",
		-- S6 · Live-ops & money
		"Monetization",
		"Quests",
		"HallOfFame",
		"Events",
		-- 1.4 · Rebirth + Spring Bloom
		"Rebirth",
		"EggHunt",
		-- 1.5 · Showtime
		"Accessories",
		"Contests",
		-- 2.0 · Light & Void
		"SkyIslands",
		"Riding",
		"Surf",
		-- 2.1 · Arena & Raids
		"Arena",
		"Raids",
		-- 3.0 · Year Two
		"Racing",
		"TradingHub",
		"Workshop",
		-- Glow-up · daily login streak + offline reminders
		"LoginStreak",
		"Reminders",
		-- 3.3 · Endgame (Ranch Mastery, Line Mastery, Star Shard shop, Mythic Ladder)
		"Mastery",
		-- Glow-up L · emotes and tricks, gifts, invites, group reward, Premium perks, VIP balcony
		"Community",
		"Gifts",
		-- Glow-up T · a monster at your side
		"Companions",
		-- Glow-up O · Codex milestones that pay
		"Codex",
		-- C1 · World geometry (Studio-tested)
		"World",
	},
}
