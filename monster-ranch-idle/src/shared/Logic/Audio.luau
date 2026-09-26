--[[
	Audio: the pure rules behind the client Audio kit (src/client/Audio), kept here so they are
	unit-tested without a Roblox runtime. Nothing in this module touches an Instance.

	  Audio.Resolve(key, entry) -> spec?        a Config.Sounds entry (string or table) with every
	                                            default filled in; nil for an unknown key
	      spec = { key, id, empty, volume, pitchMin, pitchMax, group, cooldown, maxConcurrent,
	               duck, looped }   looped defaults to true for the Music and Ambience groups
	  Audio.GroupOf(key) -> group               the default group of a key (see Config/Sounds)
	  Audio.GroupVolumes(settings) -> { [group] = 0..1 }   Music and Ambience follow the Music
	                                            toggle; Effects, UI and Voice follow Sound effects
	  Audio.PickPitch(spec, r01) -> number      PlaybackSpeed for one play
	  Audio.StreakPitch(count) -> number        count 1 = 1.0, one semitone higher per repeat (cap)
	  Audio.Hash(text) -> 0..1                  deterministic (FNV-1a)
	  Audio.VoiceKey(archetype) -> "Voice<Archetype>"
	  Audio.VoicePitch({ line, stage, height }) -> number   smaller and younger = higher; each
	                                            line gets its own fixed offset from its id
	  Audio.HatchChain(rarity, variant) -> { key }          first key with an id wins
	  Audio.MusicChain(state) -> { key }        state = { battle, stampede, sky, hub, night, event }
	  Audio.Beds(state) -> { [key] = 0..1 }     ambience targets; state = { night, weather, sky }
	  Audio.Kind(key) -> string                 the Sound Check heading a key is listed under
	  Audio.First(sounds, chain) -> key?        the first key in chain whose id is filled in
]]

local Config = require(script.Parent.Parent.Config)

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
	local id = if type(entry.id) == "string" then entry.id else ""
	local group = if table.find(Audio.Groups, entry.group) then entry.group else Audio.GroupOf(key)
	local looped = if type(entry.looped) == "boolean" then entry.looped else group == "Music" or group == "Ambience"
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
		empty = id == "",
		volume = math.clamp(number(entry.volume, if looped then DEFAULTS.loopVolume else DEFAULTS.volume), 0, 10),
		pitchMin = math.max(0.05, math.min(pitchMin, pitchMax)),
		pitchMax = math.max(0.05, math.max(pitchMin, pitchMax)),
		group = group,
		cooldown = math.max(0, number(entry.cooldown, DEFAULTS.cooldown)),
		maxConcurrent = math.max(1, math.floor(number(entry.maxConcurrent, if looped then 1 else DEFAULTS.maxConcurrent))),
		duck = math.clamp(number(entry.duck, 0), 0, 1),
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
	return stage * size * (1 + offset)
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
	if state.battle then
		return { "MusicBattle" }
	end
	if state.stampede then
		return { "MusicStampede", "MusicBattle" }
	end
	local chain = {}
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
	local weather = if type(state.weather) == "string" then state.weather else "clear"
	local rain = RAIN[weather] or 0
	local calm = rain == 0 and not state.sky and not QUIET_BIRDS[weather]
	return {
		AmbienceBirds = if calm and not state.night then 1 else 0,
		AmbienceCrickets = if calm and state.night then 1 else 0,
		AmbienceWind = if state.sky then 1 else (WINDY[weather] or 0),
		-- Above the clouds the rain is below you: keep a hint of it.
		AmbienceRain = if state.sky then rain * 0.35 else rain,
	}
end

local KINDS = {
	{ "UI", { "ButtonClick", "UIOpen", "UIClose", "UITab", "Purchase", "Locked", "Error" } },
	{ "Rewards", { "CoinCollect", "CoinTick", "Gem", "StarUp", "LevelUp", "QuestComplete", "TradeDone" } },
	{ "Hatching", { "EggCrack", "Evolve" } },
	{ "Fights", { "Hit", "Crit", "KO", "Victory", "Defeat", "BossHorn" } },
	{ "Weather", { "WeatherStart", "RainStart", "Thunder", "WindGust" } },
	{ "World", { "JarCollect", "Pet", "Eat", "FootstepSoft" } },
}
local KIND_OF = {}
for _, kind in KINDS do
	for _, key in kind[2] do
		KIND_OF[key] = kind[1]
	end
end
Audio.KindOrder = { "UI", "Rewards", "Hatching", "Fights", "Weather", "World", "Music", "Ambience", "Voices", "Other" }

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

return Audio
