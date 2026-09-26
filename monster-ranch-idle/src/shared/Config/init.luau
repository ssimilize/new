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
	-- Glow-up L: emotes and tricks, gifts, invites, group reward, Premium perks, VIP balcony
	Community = require(script.Community),
}

return Config
