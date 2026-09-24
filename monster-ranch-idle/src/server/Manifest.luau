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
		-- S6 · Live-ops & money
		"Monetization",
		"Quests",
		"HallOfFame",
		-- C1 · World geometry (Studio-tested)
		"World",
	},
}
