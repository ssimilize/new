--[[
	Client manifest: controllers (always-running client systems) and screens (menus opened
	by the Router) plugged into the client kernel. Same rule as the server: build it, test
	it, then add one line here to plug it in.
]]

return {
	Controllers = {
		-- 3.2 · first, so every text any other controller builds is shown translated
		"Localize",
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
		"Leaderboards",
		"Nameplates",
		-- 1.4 · Spring Bloom
		"EggHunt",
		-- 1.5 · Showtime
		"Showtime",
		-- 2.0 · Light & Void
		"SkyIslands",
		"Riding",
		-- 3.2 · Frostbite Glacier
		"Gamepad",
		-- Particle effects (Visuals/Vfx): landmark ambience
		"Landmarks",
		-- Glow-up: celebrations that travel, the moment queue, the Stampede call
		"Celebrate",
		"Stampede",
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
		"Leaderboards",
		"Clubs",
		-- M3 · Market Day (1.3)
		"Market",
		-- 1.4 · Rebirth + Spring Bloom
		"Rebirth",
		-- 1.5 · Showtime
		"Wardrobe",
		"Contests",
		-- 2.0 · Summer Splash
		"Surf",
		"Racing",
		"TradingHub",
		"Workshop",
		-- 2.1 · Arena & Raids
		"Arena",
		"Raids",
	},
}
