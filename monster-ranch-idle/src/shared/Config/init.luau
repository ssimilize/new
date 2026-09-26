--[[
	Config: all game content and tuning numbers, as plain data.

	Designers edit these tables; systems read them. Nothing in Config may require
	Roblox services or runtime state. Colours are hex strings so the same data works
	on the server, the client and in Lune tests.
]]

local Config = {
	Rarities = require(script.Rarities),
	Elements = require(script.Elements),
	Species = require(script.Species),
	Traits = require(script.Traits),
	Mutations = require(script.Mutations),
	Weather = require(script.Weather),
	Eggs = require(script.Eggs),
	Food = require(script.Food),
	Economy = require(script.Economy),
	Unlocks = require(script.Unlocks),
	Regions = require(script.Regions),
	Boss = require(script.Boss),
	Breeding = require(script.Breeding),
	HallOfFame = require(script.HallOfFame),
	Rebirth = require(script.Rebirth),
	Accessories = require(script.Accessories),
	Contests = require(script.Contests),
	Decor = require(script.Decor),
	Quests = require(script.Quests),
	Monetization = require(script.Monetization),
	Social = require(script.Social),
	Leaderboards = require(script.Leaderboards),
	Events = require(script.Events),
	EggHunt = require(script.EggHunt),
	SkyIslands = require(script.SkyIslands),
	Riding = require(script.Riding),
	Surf = require(script.Surf),
	Arena = require(script.Arena),
	Raids = require(script.Raids),
	Racing = require(script.Racing),
	TradingHub = require(script.TradingHub),
	Workshop = require(script.Workshop),
	Clubs = require(script.Clubs),
	Market = require(script.Market),
	World = require(script.World),
	Sounds = require(script.Sounds),
	Flags = require(script.Flags),
	LoginStreak = require(script.LoginStreak),
	Reminders = require(script.Reminders),
	Mastery = require(script.Mastery), -- 3.3 endgame
	-- Glow-up L: emotes and tricks, gifts, invites, group reward, Premium perks, VIP balcony
	Community = require(script.Community),
	Ambience = require(script.Ambience),
	Companions = require(script.Companions), -- glow-up T: a monster at your side
	Quality = require(script.Quality), -- glow-up P: automatic quality levels, particle budget, distance LOD
	-- Glow-up R: pens that grow (fence tiers, upgrade props, theme props, habitats, Feed Garden)
	Pens = require(script.Pens),
	-- Glow-up O: Codex milestones, the Codex Museum and the Hall of Fame plaza
	Codex = require(script.Codex),
}

return Config
