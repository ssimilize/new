--[[
	Client manifest: controllers (always-running client systems) and screens (menus opened
	by the Router) plugged into the client kernel. Same rule as the server: build it, test
	it, then add one line here to plug it in.
]]

return {
	Controllers = {
		-- C2 · HUD & core
		"Hud",
		"Notifications",
		"Hatchery",
		-- C1 · World
		"World",
		"Weather",
		"Interaction",
		-- C3 · Adventure & social
		"Tutorial",
		"Broadcasts",
		"TradeRequests",
	},
	Screens = {
		-- C2 · Ranch & monsters
		"EggShop",
		"Incubators",
		"Monsters",
		"MonsterDetail",
		"Ranch",
		"WelcomeBack",
		"Codex",
		-- C3 · Adventure & social
		"Expeditions",
		"Breeding",
		"Trade",
		"Boss",
		"HallOfFame",
		"Quests",
		"Store",
		"Settings",
	},
}
