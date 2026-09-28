--[[
	Audio: the pure rules behind the client Audio kit (src/client/Audio), kept here so they are
	unit-tested without a Roblox runtime. Nothing in this module touches an Instance.

	  Audio.Resolve(key, entry) -> spec?        a Config.Sounds entry (string or table) with every
	                                            default filled in; nil for an unknown key
	      spec = { key, id, ids, empty, volume, pitchMin, pitchMax, group, cooldown, maxConcurrent,
	               duck, duckHold, looped, scatter? = { min, max } }
	      ids = every variation (`ids` list, then `id`), id = the first; looped defaults to true for
	      the Music and Ambience groups unless the entry scatters
	  Audio.PickId(spec, lastId?, r01) -> id    a random variation, never lastId twice in a row
	  Audio.ScatterDelay(spec, r01) -> seconds  the gap before a scatter bed's next one-shot
	  Audio.GroupOf(key) -> group               the default group of a key (see Config/Sounds)
	  Audio.GroupVolumes(settings) -> { [group] = 0..1 }   Music and Ambience follow the Music
	                                            toggle; Effects, UI and Voice follow Sound effects
	  Audio.PickPitch(spec, r01) -> number      PlaybackSpeed for one play
	  Audio.StreakPitch(count) -> number        count 1 = 1.0, one semitone higher per repeat (cap)
	  Audio.Hash(text) -> 0..1                  deterministic (FNV-1a)
	  Audio.VoiceKey(archetype) -> "Voice<Archetype>"
	  Audio.VoicePitch({ line, stage, height, titanic? }) -> number   smaller and younger = higher (a Titanic lower); each
	                                            line gets its own fixed offset from its id
	  Audio.HatchChain(rarity, variant) -> { key }          first key with an id wins
	  Audio.MusicChain(state) -> { key }        state = { raid, racing, battle, stampede, sky, hub,
	                                            night, event }
	  Audio.Beds(state) -> { [key] = 0..1 }     ambience targets; state = { night, weather, sky, hub }
	  Audio.Kind(key) -> string                 the Sound Check heading a key is listed under
	  Audio.First(sounds, chain) -> key?        the first key in chain whose id is filled in

	The Foundry path (adoption lane 1d): the Soundscape controller decides music and beds with the
	vendored Score and Soundscape packages, handed in (this module never requires Shared.Foundry).
	MusicChain and Beds stay as the fallback when a package is not vendored; the compat spec
	(tests/specs/SoundCompat.spec) proves both paths equal against a frozen copy (tests/runtime/OldAudio).
	  Audio.MusicThemes / Audio.BedLayers       the rules as data (theme order = chain order)
	  Audio.ScoreDef() -> score                 MusicThemes as a packages/Score score
	  Audio.ScapeDef() -> scape                 BedLayers as a packages/Soundscape scape
	  Audio.ScoreChain(Score, score, state) -> { key }   MusicChain, walked with Score.when
	  Audio.FoundrySound(Score, Soundscape, adapter) -> runner?, err?
	      runner.Music(state) -> { key }        the chain for Audio.SetMusic
	      runner.Beds(state, dt?) -> beds, fountain   Beds' levels and the fountain loop's level,
	                                            from a live Soundscape instance's play/fade/stop
]]

local Config = require(script.Parent.Parent.Config)
local Titanic = require(script.Parent.Titanic)

local Audio = {}

Audio.Groups = { "Music", "Ambience", "Effects", "UI", "Voice" }

-- Group volume at full settings; the key's own volume multiplies it.
Audio.GroupBase = { Music = 0.5, Ambience = 0.6, Effects = 0.8, UI = 0.6, Voice = 0.7 }

-- Which saved toggle each group follows. Ambience is a background bed like music, so muting music
-- for your own playlist also quiets the birds; voices are one-shot effects like hatch stings.
Audio.GroupFollows = { Music = "music", Ambience = "music", Effects = "sfx", UI = "sfx", Voice = "sfx" }

Audio.UIKeys = { ButtonClick = true, UIOpen = true, UIClose = true, UITab = true, Purchase = true, Locked = true, Error = true }

-- Event id -> theme key. Events.spec-style coverage lives in Audio.spec (every event has one).
Audio.EventMusic = {
	frostfall = "MusicFrostfall",
	lunarlanterns = "MusicLunarLanterns",
	springbloom = "MusicSpringBloom",
	summersplash = "MusicSummerSplash",
	harvestmoon = "MusicHarvestMoon",
}

Audio.STREAK_STEP = 1 -- semitones per repeat
Audio.STREAK_MAX = 12 -- repeats before the pitch stops climbing (one octave)

local DEFAULTS = { volume = 0.6, loopVolume = 0.5, cooldown = 0.05, maxConcurrent = 4 }

function Audio.GroupOf(key: string): string
	if string.sub(key, 1, 5) == "Music" then
		return "Music"
	elseif string.sub(key, 1, 8) == "Ambience" then
		return "Ambience"
	elseif string.sub(key, 1, 5) == "Voice" then
		return "Voice"
	elseif Audio.UIKeys[key] then
		return "UI"
	end
	return "Effects"
end

local function number(value: any, default: number): number
	return if type(value) == "number" and value == value then value else default
end

function Audio.Resolve(key: string, entry: any)
	if type(entry) == "string" then
		entry = { id = entry }
	elseif type(entry) ~= "table" then
		return nil
	end
	local ids = {}
	for _, v in if type(entry.ids) == "table" then entry.ids else {} do
		if type(v) == "string" and v ~= "" and not table.find(ids, v) then
			table.insert(ids, v)
		end
	end
	if type(entry.id) == "string" and entry.id ~= "" and not table.find(ids, entry.id) then
		table.insert(ids, entry.id)
	end
	local id = ids[1] or ""
	local scatter = nil
	if type(entry.scatter) == "table" then
		local min = math.max(0.5, number(entry.scatter.min or entry.scatter[1], 4))
		scatter = { min = min, max = math.max(min, number(entry.scatter.max or entry.scatter[2], min * 3)) }
	end
	local group = if table.find(Audio.Groups, entry.group) then entry.group else Audio.GroupOf(key)
	local looped = if type(entry.looped) == "boolean" then entry.looped else scatter == nil and (group == "Music" or group == "Ambience")
	local pitchMin, pitchMax = 1, 1
	if type(entry.pitch) == "number" then
		pitchMin, pitchMax = entry.pitch, entry.pitch
	elseif type(entry.pitch) == "table" then
		pitchMin = number(entry.pitch[1] or entry.pitch.min, 1)
		pitchMax = number(entry.pitch[2] or entry.pitch.max, pitchMin)
	end
	return {
		key = key,
		id = id,
		ids = ids,
		empty = id == "",
		scatter = scatter,
		volume = math.clamp(number(entry.volume, if looped then DEFAULTS.loopVolume else DEFAULTS.volume), 0, 10),
		pitchMin = math.max(0.05, math.min(pitchMin, pitchMax)),
		pitchMax = math.max(0.05, math.max(pitchMin, pitchMax)),
		group = group,
		cooldown = math.max(0, number(entry.cooldown, DEFAULTS.cooldown)),
		maxConcurrent = math.max(1, math.floor(number(entry.maxConcurrent, if looped then 1 else DEFAULTS.maxConcurrent))),
		duck = math.clamp(number(entry.duck, 0), 0, 1),
		duckHold = math.max(0, number(entry.duckHold, 1.4)),
		looped = looped,
	}
end

function Audio.GroupVolumes(settings: any): { [string]: number }
	local out = {}
	for _, group in Audio.Groups do
		local toggle = Audio.GroupFollows[group]
		local on = type(settings) ~= "table" or settings[toggle] ~= false
		out[group] = if on then Audio.GroupBase[group] else 0
	end
	return out
end

function Audio.PickPitch(spec, r01: number): number
	return spec.pitchMin + (spec.pitchMax - spec.pitchMin) * math.clamp(r01, 0, 1)
end

function Audio.PickId(spec, lastId: string?, r01: number): string
	local ids = spec.ids or {}
	local n = #ids
	if n <= 1 then
		return ids[1] or spec.id or ""
	end
	local last = table.find(ids, lastId)
	if not last then
		return ids[math.clamp(math.floor(r01 * n) + 1, 1, n)]
	end
	-- Pick among the other n - 1, so the same variation never plays twice in a row.
	local pick = math.clamp(math.floor(r01 * (n - 1)) + 1, 1, n - 1)
	return ids[if pick >= last then pick + 1 else pick]
end

function Audio.ScatterDelay(spec, r01: number): number
	local scatter = spec.scatter or { min = 4, max = 12 }
	return scatter.min + (scatter.max - scatter.min) * math.clamp(r01, 0, 1)
end

function Audio.StreakPitch(count: number): number
	local steps = math.clamp(math.floor(count) - 1, 0, Audio.STREAK_MAX)
	return 2 ^ (steps * Audio.STREAK_STEP / 12)
end

function Audio.Hash(text: string): number
	local h = 2166136261
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		-- × the FNV prime (2^24 + 403) mod 2^32, without leaving exact double range.
		h = (bit32.lshift(h, 24) + h * 403) % 4294967296
	end
	return h / 4294967295
end

function Audio.VoiceKey(archetype: string?): string
	local a = if type(archetype) == "string" and archetype ~= "" then archetype else "blob"
	return "Voice" .. string.upper(string.sub(a, 1, 1)) .. string.sub(a, 2)
end

local STAGE_PITCH = { 1.22, 1.1, 1 }
local REF_HEIGHT = 3 -- studs; a monster this tall speaks at its family's pitch
local LINE_SPREAD = 0.06 -- ± per line

function Audio.VoicePitch(info): number
	info = if type(info) == "table" then info else {}
	local stage = STAGE_PITCH[info.stage] or 1
	local height = number(info.height, REF_HEIGHT)
	local size = if height > 0 then math.clamp((REF_HEIGHT / height) ^ 0.3, 0.8, 1.25) else 1
	local offset = if type(info.line) == "string" then (Audio.Hash(info.line) * 2 - 1) * LINE_SPREAD else 0
	return stage * size * (1 + offset) * Titanic.CryPitch(info)
end

function Audio.HatchChain(rarity: number?, variant: number?): { string }
	local chain = {}
	if variant == 2 then
		table.insert(chain, "HatchRainbow")
		table.insert(chain, "HatchGolden")
	elseif variant == 1 then
		table.insert(chain, "HatchGolden")
	end
	local r = math.clamp(math.floor(number(rarity, 1)), 1, Config.Rarities.Count)
	for i = r, 1, -1 do
		local def = Config.Rarities.Get(i)
		if def then
			table.insert(chain, "Hatch" .. string.upper(string.sub(def.id, 1, 1)) .. string.sub(def.id, 2))
		end
	end
	return chain
end

function Audio.MusicChain(state): { string }
	state = if type(state) == "table" then state else {}
	if state.raid then
		return { "MusicRaid", "MusicBattle" }
	end
	if state.racing then
		return { "MusicRacing", "MusicBattle" }
	end
	if state.battle then
		return { "MusicBattle" }
	end
	if state.stampede then
		return { "MusicStampede", "MusicBattle" }
	end
	local chain = {}
	if state.reef then -- glow-up DR: under water in the Deep Reef
		table.insert(chain, "MusicReef")
	end
	if state.sky then
		table.insert(chain, "MusicSkyIslands")
	end
	local theme = if type(state.event) == "string" then Audio.EventMusic[state.event] else nil
	if theme then
		table.insert(chain, theme)
	end
	if state.hub and not state.sky then
		table.insert(chain, "MusicHub")
	end
	if state.night then
		table.insert(chain, "MusicRanchNight")
	end
	table.insert(chain, "MusicRanch")
	return chain
end

local RAIN = { rain = 1, thunderstorm = 1 }
local WINDY = { snow = 0.5, pollenstorm = 0.6, thunderstorm = 0.4 }
local QUIET_BIRDS = { snow = true, bloodmoon = true }

function Audio.Beds(state): { [string]: number }
	state = if type(state) == "table" then state else {}
	if state.reef then
		-- Glow-up DR: under water nothing from up top carries; only the reef's own bed.
		return {
			AmbienceBirds = 0,
			AmbienceCrickets = 0,
			AmbienceWind = 0,
			AmbienceRain = 0,
			AmbienceHubCrowd = 0,
			AmbienceReef = 1,
		}
	end
	local weather = if type(state.weather) == "string" then state.weather else "clear"
	local rain = RAIN[weather] or 0
	local calm = rain == 0 and not state.sky and not QUIET_BIRDS[weather]
	return {
		AmbienceBirds = if calm and not state.night then 1 else 0,
		AmbienceCrickets = if calm and state.night then 1 else 0,
		AmbienceWind = if state.sky then 1 else (WINDY[weather] or 0),
		-- Above the clouds the rain is below you: keep a hint of it.
		AmbienceRain = if state.sky then rain * 0.35 else rain,
		AmbienceHubCrowd = if state.hub and not state.sky then 1 - rain * 0.5 else 0,
		AmbienceReef = 0,
	}
end

local KINDS = {
	{ "UI", { "ButtonClick", "UIOpen", "UIClose", "UITab", "Purchase", "Locked", "Error" } },
	{ "Rewards", { "CoinCollect", "CoinTick", "Gem", "StarUp", "LevelUp", "QuestComplete", "TradeDone" } },
	{ "Hatching", { "EggCrack", "Evolve" } },
	{ "Moments", { "Rebirth", "Mutation" } },
	{ "Fights", { "Hit", "Crit", "KO", "Heal", "Victory", "Defeat", "BossHorn" } },
	{ "Weather", { "WeatherStart", "RainStart", "Thunder", "WindGust" } },
	{ "World", { "JarCollect", "Pet", "Eat", "FootstepSoft", "Teleport", "PortalHum" } },
}
local KIND_OF = {}
for _, kind in KINDS do
	for _, key in kind[2] do
		KIND_OF[key] = kind[1]
	end
end
Audio.KindOrder = { "UI", "Rewards", "Hatching", "Moments", "Fights", "Weather", "World", "Music", "Ambience", "Voices", "Other" }

function Audio.Kind(key: string): string
	if KIND_OF[key] then
		return KIND_OF[key]
	elseif string.sub(key, 1, 5) == "Hatch" then
		return "Hatching"
	elseif string.sub(key, 1, 5) == "Music" then
		return "Music"
	elseif string.sub(key, 1, 8) == "Ambience" then
		return "Ambience"
	elseif string.sub(key, 1, 5) == "Voice" then
		return "Voices"
	end
	return "Other"
end

function Audio.First(sounds, chain: { string }): string?
	for _, key in chain do
		local spec = Audio.Resolve(key, sounds[key])
		if spec and not spec.empty then
			return key
		end
	end
	return nil
end

-- The Foundry path --------------------------------------------------------------------------------

-- MusicChain as Score themes, in chain order. `keys` is what a matching theme adds to the chain
-- (Audio.First plays the first filled one, so an empty id falls through as before); `final` ends
-- the chain there (the combat contexts, and the ranch theme, which matches everything).
Audio.MusicThemes = {
	{ id = "raid", when = { raid = true }, keys = { "MusicRaid", "MusicBattle" }, final = true },
	{ id = "racing", when = { racing = true }, keys = { "MusicRacing", "MusicBattle" }, final = true },
	{ id = "battle", when = { battle = true }, keys = { "MusicBattle" }, final = true },
	{ id = "stampede", when = { stampede = true }, keys = { "MusicStampede", "MusicBattle" }, final = true },
	{ id = "reef", when = { reef = true }, keys = { "MusicReef" } },
	{ id = "sky", when = { sky = true }, keys = { "MusicSkyIslands" } },
}
do
	local events = {}
	for event in Audio.EventMusic do
		table.insert(events, event)
	end
	table.sort(events)
	for _, event in events do
		table.insert(Audio.MusicThemes, { id = event, when = { event = event }, keys = { Audio.EventMusic[event] } })
	end
end
table.insert(Audio.MusicThemes, { id = "hub", when = { hub = true, sky = false }, keys = { "MusicHub" } })
table.insert(Audio.MusicThemes, { id = "ranchNight", when = { phase = "night" }, keys = { "MusicRanchNight" } })
table.insert(Audio.MusicThemes, { id = "ranch", keys = { "MusicRanch" }, final = true })

local THEME_OF = {}
for _, theme in Audio.MusicThemes do
	THEME_OF[theme.id] = theme
end

local SCORE_FLAGS = { "raid", "racing", "battle", "stampede", "reef", "sky", "hub" }

-- MusicChain reads its state by truthiness; Score.when compares flags with `true`.
function Audio.ScoreContext(state)
	state = if type(state) == "table" then state else {}
	local context = {
		phase = if state.night then "night" else "day",
		event = if type(state.event) == "string" then state.event else nil,
	}
	for _, flag in SCORE_FLAGS do
		context[flag] = if state[flag] then true else false
	end
	return context
end

function Audio.ScoreDef()
	local themes = {}
	for _, theme in Audio.MusicThemes do
		table.insert(themes, {
			id = theme.id,
			bpm = 120, -- nominal: the Ranch crossfades without a bar grid (the kit fades, not the Score)
			beatsPerBar = 4,
			when = theme.when,
			layers = { { id = "track", sound = "", volume = { 1, 1, 1 }, origin = "Config/Sounds." .. theme.keys[1] } },
		})
	end
	return { game = "monster-ranch", themes = themes, groups = { Music = Audio.GroupBase.Music } }
end

function Audio.ScoreChain(Score, score, state): { string }
	local context = Audio.ScoreContext(state)
	local chain = {}
	for _, theme in score.themes do
		if Score.when(theme.when, context) then
			local def = THEME_OF[theme.id]
			for _, key in def.keys do
				table.insert(chain, key)
			end
			if def.final then
				break
			end
		end
	end
	return chain
end

-- Beds as a scape. The areas are the controller's own flags (SkyIslands, DeepReef, the hub
-- radius), so the listener sits in flag space: x = hub, y = sky, z = reef, each 0 or 1, and each
-- area's box holds exactly the points with its flag at 1. Priorities and masks give Beds'
-- precedence: the reef silences everything above it, the islands the hub and the ranch; the hub
-- plays over the ranch. A level here is Beds' 0..1 level (the kit multiplies the key's volume).
local RAINY = { "rain", "thunderstorm" }
local QUIET = { "rain", "thunderstorm", "snow", "bloodmoon" }

Audio.ScapeZones = {
	{ id = "reef", shape = { type = "box", center = { 0.5, 0.5, 1 }, size = { 3, 3, 1 } }, priority = 30 },
	{ id = "sky", shape = { type = "box", center = { 0.5, 1, 0.5 }, size = { 3, 1, 3 } }, priority = 20 },
	{ id = "hub", shape = { type = "box", center = { 1, 0.5, 0.5 }, size = { 1, 3, 3 } }, priority = 10, mask = false },
	{ id = "ranch", shape = { type = "world" }, priority = 0 },
}

Audio.BedLayers = {
	{ zone = "reef", sound = "AmbienceReef", volume = 1 },
	{ zone = "sky", sound = "AmbienceWind", volume = 1 },
	-- Above the clouds the rain is below you: keep a hint of it.
	{ zone = "sky", sound = "AmbienceRain", when = { weather = RAINY }, volume = 0.35 },
	{ zone = "hub", sound = "AmbienceHubCrowd", when = { weather = { ["not"] = RAINY } }, volume = 1 },
	{ zone = "hub", sound = "AmbienceHubCrowd", when = { weather = RAINY }, volume = 0.5 },
	{ zone = "ranch", sound = "AmbienceBirds", when = { phase = "day", weather = { ["not"] = QUIET } }, volume = 1 },
	{ zone = "ranch", sound = "AmbienceCrickets", when = { phase = "night", weather = { ["not"] = QUIET } }, volume = 1 },
	{ zone = "ranch", sound = "AmbienceWind", when = { weather = "snow" }, volume = 0.5 },
	{ zone = "ranch", sound = "AmbienceWind", when = { weather = "pollenstorm" }, volume = 0.6 },
	{ zone = "ranch", sound = "AmbienceWind", when = { weather = "thunderstorm" }, volume = 0.4 },
	{ zone = "ranch", sound = "AmbienceRain", when = { weather = RAINY }, volume = 1 },
	-- The fountain's positional loop (the controller places it at Config.World.Fountain).
	{ zone = "ranch", sound = "AmbienceFountain", volume = 1 },
}

function Audio.ScapeDef()
	return { game = "monster-ranch", zones = Audio.ScapeZones, beds = Audio.BedLayers, groups = { Ambience = Audio.GroupBase.Ambience } }
end

function Audio.ScapeListener(state): { number }
	state = if type(state) == "table" then state else {}
	return { if state.hub then 1 else 0, if state.sky then 1 else 0, if state.reef then 1 else 0 }
end

function Audio.ScapeContext(state)
	state = if type(state) == "table" then state else {}
	return { phase = if state.night then "night" else "day", weather = if type(state.weather) == "string" then state.weather else "clear" }
end

function Audio.FoundrySound(Score, Soundscape, adapter)
	local score, scape = Audio.ScoreDef(), Audio.ScapeDef()
	local problems = Score.validate(score)
	for _, problem in Soundscape.validate(scape) do
		table.insert(problems, problem)
	end
	if #problems > 0 then
		return nil, table.concat(problems, "; ")
	end
	local levels = {} -- [key] = the level the scape plays it at (nil: stopped)
	local ok, instance = pcall(Soundscape.new, adapter, scape, function(cmd)
		if cmd.op == "play" or cmd.op == "fade" then
			levels[cmd.cue] = cmd.volume
		elseif cmd.op == "stop" then
			levels[cmd.cue] = nil
		end
	end)
	if not ok then
		return nil, tostring(instance)
	end
	local runner = {}
	function runner.Music(state): { string }
		return Audio.ScoreChain(Score, score, state)
	end
	function runner.Beds(state, dt: number?)
		instance:update(Audio.ScapeListener(state), dt, Audio.ScapeContext(state))
		-- Beds' own constructor order, so the kit sees its SetLoop calls in the same order.
		return {
			AmbienceBirds = levels.AmbienceBirds or 0,
			AmbienceCrickets = levels.AmbienceCrickets or 0,
			AmbienceWind = levels.AmbienceWind or 0,
			AmbienceRain = levels.AmbienceRain or 0,
			AmbienceHubCrowd = levels.AmbienceHubCrowd or 0,
			AmbienceReef = levels.AmbienceReef or 0,
		},
			levels.AmbienceFountain or 0
	end
	return runner
end

return Audio
