--[[
	Sound ids, played by the client Audio kit (src/client/Audio) through ctx:Sound(key).

	An entry is either a plain id string or a table:
	  Key = "rbxassetid://<id>"
	  Key = {
	    id = "rbxassetid://<id>",
	    ids = { "rbxassetid://<a>", "rbxassetid://<b>" },  -- variations: one at random per play,
	                                   -- never the same twice in a row (id, if set, joins them)
	    volume = 0.6,                  -- 0..1 before the group volume (default 0.6, loops 0.5)
	    pitch = { 0.95, 1.05 },        -- PlaybackSpeed range picked per play, or one number
	    group = "Effects",             -- "Effects" | "UI" | "Music" | "Ambience" | "Voice"
	    cooldown = 0.05,               -- seconds before the same key plays again
	    maxConcurrent = 4,             -- copies playing at once; the oldest is restarted
	    duck = 0.5,                    -- a sting: music dips by this much for a moment
	    duckHold = 1.4,                -- seconds the dip lasts (long stings hold it longer)
	    looped = false,                -- default: true for the Music and Ambience groups
	    scatter = { min = 4, max = 12 },  -- a bed of one-shots: one variation every min..max s at a
	                                   -- random spot around the camera (Soundscape birds, crickets)
	  }
	Everything but id (or ids) is optional. Without `group`, keys starting with Music / Ambience / Voice
	go to that group, the UI keys (Logic/Audio.UIKeys) to UI, and everything else to Effects.
	Music and Ambience keys loop unless `looped = false` or they scatter.

	Ids (2026-09-26): licensed Pro Sound Effects and APM tracks from the Creator Store, curated per
	slot and load-checked in Studio; stings and music are APM.

	An empty id is a placeholder: playing it does nothing and creates nothing, so the game is
	silent-safe and a key lights up the moment its id is filled in. Chains fall back through
	empty ids (Logic/Audio): a missing night theme plays MusicRanch, a missing HatchEpic plays
	HatchRare, and so on. Audition every key in Studio with the Sound Check screen (Studio only).

	Music contexts (Logic/Audio.MusicChain): raid > racing > battle > Stampede > Sky Islands >
	event theme > hub > ranch night > ranch day. Event themes are Logic/Audio.EventMusic[eventId].
	Voices: one family per Species archetype (Voice<Archetype>), pitched per monster.
]]

return {
	-- UI (kept quiet: they fire on every press) ------------------------------------------
	ButtonClick = { id = "rbxassetid://9112751731", volume = 0.35, pitch = { 0.96, 1.04 }, cooldown = 0.04 },
	UIOpen = { id = "rbxassetid://9119668788", volume = 0.3, cooldown = 0.1 },
	UIClose = { id = "rbxassetid://9113863445", volume = 0.25, cooldown = 0.1 },
	UITab = { id = "rbxassetid://9119976507", volume = 0.3, pitch = { 0.97, 1.03 }, cooldown = 0.05 },
	Purchase = { id = "rbxassetid://9125485591", volume = 0.3, cooldown = 0.2 }, -- a 4.5 s desk bell
	Locked = { id = "rbxassetid://9114143457", volume = 0.35, cooldown = 0.2 },
	Error = { id = "rbxassetid://9119715399", volume = 0.35, cooldown = 0.3 },

	-- Rewards -------------------------------------------------------------------------
	CoinCollect = { id = "rbxassetid://9125537253", volume = 0.5, pitch = { 0.97, 1.05 }, cooldown = 0.08 },
	CoinTick = { id = "rbxassetid://9125540235", volume = 0.35, cooldown = 0.03, maxConcurrent = 6 }, -- Audio.Streak climbs its pitch
	Gem = { id = "rbxassetid://9126073303", volume = 0.5, cooldown = 0.15 },
	StarUp = { id = "rbxassetid://9125644323", volume = 0.55, duck = 0.4 },
	LevelUp = { id = "rbxassetid://1840295985", volume = 0.5, duck = 0.8, duckHold = 6 }, -- ranch level-up: APM brass flourish
	QuestComplete = { id = "rbxassetid://9119802022", volume = 0.5, duck = 0.35, cooldown = 0.5 },
	TradeDone = { id = "rbxassetid://9119643158", volume = 0.45, duck = 0.35 },

	-- Hatching (stings climb with rarity; a Golden or Rainbow sting plays over the rarity's)
	EggCrack = { id = "rbxassetid://9113958797", volume = 0.6, pitch = { 0.95, 1.05 } },
	HatchCommon = { id = "rbxassetid://9113263649", volume = 0.5 },
	HatchUncommon = { id = "rbxassetid://9116421238", volume = 0.5 },
	HatchRare = { id = "rbxassetid://9116395089", volume = 0.55, duck = 0.3 },
	HatchEpic = { id = "rbxassetid://9116384485", volume = 0.6, duck = 0.45, duckHold = 2.5 },
	HatchLegendary = { id = "rbxassetid://9113122866", volume = 0.6, duck = 0.6, duckHold = 4 },
	HatchMythic = { id = "rbxassetid://9113785968", volume = 0.6, duck = 0.7, duckHold = 4.5 },
	HatchGolden = { id = "rbxassetid://9114369623", volume = 0.55, duck = 0.5, duckHold = 3 },
	HatchRainbow = { id = "rbxassetid://9116379771", volume = 0.55, duck = 0.65, duckHold = 3.5 },
	Evolve = { id = "rbxassetid://9116425491", volume = 0.6, duck = 0.6, duckHold = 3.5 },

	-- Moments -------------------------------------------------------------------------
	Rebirth = { id = "rbxassetid://9113122760", volume = 0.6, duck = 0.7, duckHold = 5 },
	Mutation = { id = "rbxassetid://9119901174", volume = 0.5, duck = 0.3 },

	-- Fights --------------------------------------------------------------------------
	Hit = { id = "rbxassetid://9113854411", volume = 0.45, pitch = { 0.9, 1.1 }, maxConcurrent = 3 },
	Crit = { id = "rbxassetid://9116385087", volume = 0.55, pitch = { 0.95, 1.05 } },
	KO = { id = "rbxassetid://9119197896", volume = 0.5 },
	Heal = { id = "rbxassetid://9120296573", volume = 0.4, cooldown = 0.2 },
	Victory = { id = "rbxassetid://1837762472", volume = 0.5, duck = 0.85, duckHold = 6 }, -- APM "Victory Dance" sting
	Defeat = { id = "rbxassetid://9113887244", volume = 0.5, duck = 0.6 },
	BossHorn = { id = "rbxassetid://9114819248", volume = 0.5, duck = 0.5, duckHold = 3 },

	-- Weather one-shots ---------------------------------------------------------------
	WeatherStart = { id = "rbxassetid://9125641038", volume = 0.35, cooldown = 1 },
	RainStart = { id = "rbxassetid://9118033973", volume = 0.4, cooldown = 2 },
	Thunder = { id = "rbxassetid://9120016245", volume = 0.6, pitch = { 0.85, 1.1 }, cooldown = 1, maxConcurrent = 2 },
	WindGust = { id = "rbxassetid://9120697819", volume = 0.3, pitch = { 0.9, 1.1 }, cooldown = 3, group = "Ambience", looped = false },

	-- World ---------------------------------------------------------------------------
	JarCollect = { id = "rbxassetid://9113849579", volume = 0.5, pitch = { 0.95, 1.05 }, cooldown = 0.08 },
	Pet = { id = "rbxassetid://9113985007", volume = 0.45, pitch = { 0.95, 1.08 }, cooldown = 0.2 },
	Eat = { id = "rbxassetid://9113138343", volume = 0.45, pitch = { 0.92, 1.08 }, cooldown = 0.15 },
	FootstepSoft = { id = "rbxassetid://9120062559", volume = 0.25, pitch = { 0.9, 1.1 }, cooldown = 0.12 },
	Teleport = { id = "rbxassetid://9125634964", volume = 0.5, cooldown = 1 },
	PortalHum = { id = "rbxassetid://9116420454", volume = 0.35, group = "Ambience", looped = true }, -- Audio.LoopAt from Landmarks

	-- Music (loops; crossfaded by context) --------------------------------------------
	MusicRanch = "rbxassetid://9043298889", -- ranch by day, and the fallback for every other context
	MusicRanchNight = "rbxassetid://1835327258",
	MusicHub = "rbxassetid://1839929351",
	MusicSkyIslands = "rbxassetid://9039607561",
	MusicBattle = "rbxassetid://1838632983", -- BattleReplay, Arena
	MusicStampede = "rbxassetid://1843011412",
	MusicRaid = "rbxassetid://9042561311",
	MusicRacing = "rbxassetid://1839952683",
	MusicFrostfall = "rbxassetid://1842955066",
	MusicLunarLanterns = "rbxassetid://1845962816",
	MusicSpringBloom = "rbxassetid://9043503493",
	MusicSummerSplash = "rbxassetid://1838922550",
	MusicHarvestMoon = "rbxassetid://97250135397412",

	-- Ambience: true loops, and scatter beds of short one-shots ------------------------
	AmbienceBirds = {
		ids = { "rbxassetid://9114623079", "rbxassetid://9117236709" },
		volume = 0.35,
		pitch = { 0.9, 1.12 },
		scatter = { min = 3, max = 9 },
	},
	AmbienceCrickets = {
		ids = { "rbxassetid://9113618682", "rbxassetid://9113618926", "rbxassetid://9119531613" },
		volume = 0.3,
		pitch = { 0.9, 1.1 },
		scatter = { min = 1.5, max = 5 },
	},
	AmbienceWind = { id = "rbxassetid://9116432106", volume = 0.4 },
	AmbienceRain = { id = "rbxassetid://9118034034", volume = 0.45 },
	AmbienceFountain = { id = "rbxassetid://9116611237", volume = 0.5 }, -- positional, at the plaza fountain
	AmbienceHubCrowd = { id = "rbxassetid://9114012848", volume = 0.18 }, -- the plaza, kept low

	-- Monster voices: one family per Species archetype, three variations each ---------
	VoiceBlob = { -- squeaky
		ids = { "rbxassetid://9125994317", "rbxassetid://9114123174", "rbxassetid://9119236198" },
		volume = 0.5,
		cooldown = 0.1,
		maxConcurrent = 3,
	},
	VoiceFox = { -- purr
		ids = { "rbxassetid://9113984654", "rbxassetid://9113984526", "rbxassetid://9113984803" },
		volume = 0.5,
		cooldown = 0.1,
		maxConcurrent = 3,
	},
	VoiceBunny = { -- chirpy
		ids = { "rbxassetid://9117236405", "rbxassetid://9114279576", "rbxassetid://9113608373" },
		volume = 0.45,
		cooldown = 0.1,
		maxConcurrent = 3,
	},
	VoiceMoth = { -- hoot
		ids = { "rbxassetid://9114017276", "rbxassetid://9117181540", "rbxassetid://9113097167" },
		volume = 0.45,
		cooldown = 0.1,
		maxConcurrent = 3,
	},
	VoiceSlug = { -- bubbly
		ids = { "rbxassetid://9112751804", "rbxassetid://9112752692", "rbxassetid://9113537810" },
		volume = 0.5,
		cooldown = 0.1,
		maxConcurrent = 3,
	},
	VoiceBug = { -- buzz
		ids = { "rbxassetid://9114506407", "rbxassetid://9113618250", "rbxassetid://9114869907" },
		volume = 0.4,
		cooldown = 0.1,
		maxConcurrent = 3,
	},
	VoiceGolem = { -- rumble
		ids = { "rbxassetid://9113857459", "rbxassetid://9117356884", "rbxassetid://9119634882" },
		volume = 0.55,
		cooldown = 0.1,
		maxConcurrent = 3,
	},
	VoiceSprite = { -- fairy
		ids = { "rbxassetid://9114292248", "rbxassetid://9120296433", "rbxassetid://9125540645" },
		volume = 0.45,
		cooldown = 0.1,
		maxConcurrent = 3,
	},
}
