--[[
	Sound ids, played by the client Audio kit (src/client/Audio) through ctx:Sound(key).

	An entry is either a plain id string or a table:
	  Key = "rbxassetid://<id>"
	  Key = {
	    id = "rbxassetid://<id>",
	    volume = 0.6,                  -- 0..1 before the group volume (default 0.6, loops 0.5)
	    pitch = { 0.95, 1.05 },        -- PlaybackSpeed range picked per play, or one number
	    group = "Effects",             -- "Effects" | "UI" | "Music" | "Ambience" | "Voice"
	    cooldown = 0.05,               -- seconds before the same key plays again
	    maxConcurrent = 4,             -- copies playing at once; the oldest is restarted
	    duck = 0.5,                    -- a sting: music dips by this much for a moment
	    looped = false,                -- default: true for the Music and Ambience groups
	  }
	Everything but id is optional. Without `group`, keys starting with Music / Ambience / Voice
	go to that group, the UI keys (Logic/Audio.UIKeys) to UI, and everything else to Effects.
	Music and Ambience keys loop unless `looped = false`.

	An empty id is a placeholder: playing it does nothing and creates nothing, so the game is
	silent-safe and a key lights up the moment its id is filled in. Chains fall back through
	empty ids (Logic/Audio): a missing night theme plays MusicRanch, a missing HatchEpic plays
	HatchRare, and so on. Audition every key in Studio with the Sound Check screen (Studio only).

	Music contexts (Logic/Audio.MusicChain): battle > Stampede > Sky Islands > event theme >
	hub > ranch night > ranch day. Event themes are Logic/Audio.EventMusic[eventId].
	Voices: one family per Species archetype (Voice<Archetype>), pitched per monster.
]]

return {
	-- UI ------------------------------------------------------------------------------
	ButtonClick = { id = "", volume = 0.5, pitch = { 0.96, 1.04 }, cooldown = 0.04 },
	UIOpen = { id = "", volume = 0.45, cooldown = 0.1 },
	UIClose = { id = "", volume = 0.4, cooldown = 0.1 },
	UITab = { id = "", volume = 0.45, pitch = { 0.97, 1.03 }, cooldown = 0.05 },
	Purchase = { id = "", volume = 0.6, cooldown = 0.2 },
	Locked = { id = "", volume = 0.5, cooldown = 0.2 },
	Error = { id = "", volume = 0.5, cooldown = 0.3 },

	-- Rewards -------------------------------------------------------------------------
	CoinCollect = { id = "", volume = 0.6, pitch = { 0.97, 1.05 }, cooldown = 0.08 },
	CoinTick = { id = "", volume = 0.4, cooldown = 0.03, maxConcurrent = 6 }, -- Audio.Streak climbs its pitch
	Gem = { id = "", volume = 0.6, cooldown = 0.15 },
	StarUp = { id = "", volume = 0.7, duck = 0.4 },
	LevelUp = { id = "", volume = 0.7, duck = 0.55 },
	QuestComplete = { id = "", volume = 0.65, duck = 0.35, cooldown = 0.5 },
	TradeDone = { id = "", volume = 0.65, duck = 0.35 },

	-- Hatching (stings climb with rarity; a Golden or Rainbow sting plays over the rarity's)
	EggCrack = { id = "", volume = 0.7, pitch = { 0.95, 1.05 } },
	HatchCommon = { id = "", volume = 0.6 },
	HatchUncommon = { id = "", volume = 0.6 },
	HatchRare = { id = "", volume = 0.65, duck = 0.3 },
	HatchEpic = { id = "", volume = 0.7, duck = 0.45 },
	HatchLegendary = { id = "", volume = 0.75, duck = 0.6 },
	HatchMythic = { id = "", volume = 0.8, duck = 0.7 },
	HatchGolden = { id = "", volume = 0.7, duck = 0.5 },
	HatchRainbow = { id = "", volume = 0.75, duck = 0.65 },
	Evolve = { id = "", volume = 0.75, duck = 0.6 },

	-- Fights --------------------------------------------------------------------------
	Hit = { id = "", volume = 0.55, pitch = { 0.9, 1.1 }, maxConcurrent = 3 },
	Crit = { id = "", volume = 0.65, pitch = { 0.95, 1.05 } },
	KO = { id = "", volume = 0.6 },
	Victory = { id = "", volume = 0.7, duck = 0.7 },
	Defeat = { id = "", volume = 0.6, duck = 0.6 },
	BossHorn = { id = "", volume = 0.75, duck = 0.5 },

	-- Weather one-shots ---------------------------------------------------------------
	WeatherStart = { id = "", volume = 0.5, cooldown = 1 },
	RainStart = { id = "", volume = 0.45, cooldown = 2 },
	Thunder = { id = "", volume = 0.7, pitch = { 0.85, 1.1 }, cooldown = 1, maxConcurrent = 2 },
	WindGust = { id = "", volume = 0.35, pitch = { 0.9, 1.1 }, cooldown = 3, group = "Ambience", looped = false },

	-- World ---------------------------------------------------------------------------
	JarCollect = { id = "", volume = 0.55, pitch = { 0.95, 1.05 }, cooldown = 0.08 },
	Pet = { id = "", volume = 0.5, pitch = { 0.95, 1.08 }, cooldown = 0.2 },
	Eat = { id = "", volume = 0.5, pitch = { 0.92, 1.08 }, cooldown = 0.15 },
	FootstepSoft = { id = "", volume = 0.25, pitch = { 0.9, 1.1 }, cooldown = 0.12 },

	-- Music (loops; crossfaded by context) --------------------------------------------
	MusicRanch = "", -- ranch by day, and the fallback for every other context
	MusicRanchNight = "",
	MusicHub = "",
	MusicSkyIslands = "",
	MusicBattle = "", -- BattleReplay, Arena, Raids, Racing
	MusicStampede = "",
	MusicFrostfall = "",
	MusicLunarLanterns = "",
	MusicSpringBloom = "",
	MusicSummerSplash = "",
	MusicHarvestMoon = "",

	-- Ambience beds (loops) -----------------------------------------------------------
	AmbienceBirds = "",
	AmbienceCrickets = "",
	AmbienceWind = "",
	AmbienceRain = "",
	AmbienceFountain = { id = "", volume = 0.6 }, -- positional, at the plaza fountain

	-- Monster voices: one family per Species archetype --------------------------------
	VoiceBlob = { id = "", volume = 0.55, cooldown = 0.1, maxConcurrent = 3 },
	VoiceFox = { id = "", volume = 0.55, cooldown = 0.1, maxConcurrent = 3 },
	VoiceBunny = { id = "", volume = 0.55, cooldown = 0.1, maxConcurrent = 3 },
	VoiceMoth = { id = "", volume = 0.55, cooldown = 0.1, maxConcurrent = 3 },
	VoiceSlug = { id = "", volume = 0.55, cooldown = 0.1, maxConcurrent = 3 },
	VoiceBug = { id = "", volume = 0.55, cooldown = 0.1, maxConcurrent = 3 },
	VoiceGolem = { id = "", volume = 0.6, cooldown = 0.1, maxConcurrent = 3 },
	VoiceSprite = { id = "", volume = 0.5, cooldown = 0.1, maxConcurrent = 3 },

	-- Celebrations and the Stampede call (Controllers/Celebrate, Controllers/Stampede) --------
	-- CoinTick1..5 are the coin tick at rising pitch: a stream of landing coins climbs them
	-- (Logic/Celebration.TickKey). Keep their ids equal to CoinTick's.
	CoinTick1 = { id = "", volume = 0.4, pitch = 1, cooldown = 0.03, maxConcurrent = 4 },
	CoinTick2 = { id = "", volume = 0.4, pitch = 1.06, cooldown = 0.03, maxConcurrent = 4 },
	CoinTick3 = { id = "", volume = 0.4, pitch = 1.12, cooldown = 0.03, maxConcurrent = 4 },
	CoinTick4 = { id = "", volume = 0.4, pitch = 1.19, cooldown = 0.03, maxConcurrent = 4 },
	CoinTick5 = { id = "", volume = 0.4, pitch = 1.26, cooldown = 0.03, maxConcurrent = 4 },
	GemTick = { id = "", volume = 0.45, pitch = { 0.98, 1.06 }, cooldown = 0.05, maxConcurrent = 3 },
	ItemPop = { id = "", volume = 0.5, pitch = { 0.96, 1.04 }, cooldown = 0.1 },
	Whoosh = { id = "", volume = 0.4, pitch = { 0.95, 1.08 }, cooldown = 0.15 },
	CelebrateBig = { id = "", volume = 0.65, duck = 0.5, cooldown = 0.5 },
	CelebrateHuge = { id = "", volume = 0.75, duck = 0.7, cooldown = 1 },
	StampedeSoon = { id = "", volume = 0.6, duck = 0.4, cooldown = 5 },

	-- Photo mode (PhotoMode controller + screen) ----------------------------------------
	PhotoShutter = { id = "", volume = 0.6, cooldown = 0.3, group = "UI" }, -- a photo is taken
	PhotoSticker = { id = "", volume = 0.45, pitch = { 0.94, 1.08 }, cooldown = 0.06, group = "UI" }, -- a sticker lands
	PhotoPose = { id = "", volume = 0.5, cooldown = 0.5 }, -- monsters strike a pose
}
