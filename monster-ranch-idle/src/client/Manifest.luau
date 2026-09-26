--[[
	Client manifest: controllers (always-running client systems) and screens (menus opened
	by the Router) plugged into the client kernel. Same rule as the server: build it, test
	it, then add one line here to plug it in.
]]

return {
	Controllers = {
		-- 3.2 · first, so every text any other controller builds is shown translated
		"Localize",
		-- Glow-up P · the quality level every visual reads (before the controllers that read it)
		"Quality",
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
		"ChatTags",
		-- 1.4 · Spring Bloom
		"EggHunt",
		-- 1.5 · Showtime
		"Showtime",
		-- 2.0 · Light & Void
		"SkyIslands",
		"Riding",
		-- Glow-up T · companions at your side, animated mounts
		"Companions",
		"Mounts",
		-- 3.2 · Frostbite Glacier
		"Gamepad",
		-- Particle effects (Visuals/Vfx): landmark ambience
		"Landmarks",
		-- Audio (client/Audio): music, ambience beds, monster chatter; Sound Check in Studio
		"Soundscape",
		-- Glow-up: celebrations that travel, the moment queue, the Stampede call
		"Celebrate",
		"Stampede",
		-- Photo mode: free camera, filters, frames, stickers, CaptureService
		"PhotoMode",
		-- Glow-up · daily streak auto-open + reminder opt-in
		"DailyLogin",
		-- Glow-up L: emote wheel, Friends button, VIP balcony pads
		"Community",
		-- Ambience (Config/Ambience): sky and clouds, dusk lights, scenery that moves, ambient life
		"Sky",
		"Lamplight",
		"SceneryMotion",
		"Critters",
		-- Glow-up R: pens that grow and the Feed Garden (Config/Pens, Visuals/PenDress)
		"Pens",
		-- Glow-up O: the walk-in Codex Museum and the Hall of Fame plaza
		"CodexMuseum",
		"FamePlaza",
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
		-- Photo mode (non-modal; opened by the HUD camera button, P or D-pad up)
		"PhotoMode",
		-- Glow-up · daily login streak
		"LoginStreak",
		-- 3.3 · Endgame
		"Mastery",
		-- Glow-up L · emotes and tricks, gifts, invites, community rewards
		"EmoteWheel",
		"Friends",
	},
}
