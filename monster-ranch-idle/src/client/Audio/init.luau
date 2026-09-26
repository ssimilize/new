--[[
	Audio: the client sound kit. ctx:Sound(key, opts?) plays through it; the Soundscape controller
	drives music and ambience with it; Audio/Voices adds monster cries on top.

	Entries come from Config.Sounds (string or table, resolved by Logic/Audio). Empty ids are
	placeholders: every call on one returns nil and creates nothing.

	  Audio.Attach(store, sounds)       once per client (ClientKernel.new): SoundGroups Music, Effects,
	                                    UI, Ambience and Voice under SoundService, their volumes from
	                                    profile.Settings (music / sfx), one Heartbeat for fades
	  Audio.Play(key, opts?) -> Sound?  a one-shot from the key's pool (maxConcurrent copies; when all
	                                    play, the oldest restarts). Respects cooldown, picks a pitch
	                                    in the key's range, ducks the music for a sting (spec.duck).
	      opts = { at = Vector3 | BasePart | Attachment | Model?, pitch = mult?, volume = mult?,
	               near = studs?, far = studs? }   `at` makes it positional (InverseTapered rolloff)
	  Audio.Chain(keys, opts?) -> Sound?   plays the first key whose id is filled in
	  Audio.Streak(key, opts?) -> Sound?   repeats within STREAK_WINDOW climb a semitone each (coin ticks)
	  Audio.Stop(key)                   stops every copy (and a loop at once)
	  Audio.SetLoop(key, level, at?)    a looping layer faded toward level (0..1); `at` = Vector3
	                                    for a positional bed. 0 fades it out and stops it.
	  Audio.SetMusic(chain) -> key?     crossfades to the first filled key of chain (nil = silence)
	  Audio.Override(key?)              Sound Check: this loop alone at full, every other music
	                                    and ambience loop faded out; nil gives control back
	  Audio.Duck(depth, hold?)          dips the music group by depth for hold seconds
	  Audio.Preload(group)              ContentProvider:PreloadAsync on the group's filled keys (guarded)
	  Audio.Spec(key) -> spec?          the resolved entry (Logic/Audio.Resolve)
	  Audio.Filled(key) -> boolean      its id is not empty
	  Audio.Muted(group) -> boolean     its toggle is off
	  Audio.Keys() -> { key }           every key, sorted
	  Audio.Playing(key) -> boolean
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Logic = require(ReplicatedStorage.Shared.Logic.Audio)

local Audio = {}

local STREAK_WINDOW = 0.9 -- seconds between repeats that keep a streak climbing
local MUSIC_FADE = 2.5 -- seconds for a full crossfade
local BED_FADE = 3
local DUCK_ATTACK = 8 -- per second
local DUCK_RELEASE = 0.9
local NEAR, FAR = 10, 90

local store = nil
local sounds = {}
local specs = {}
local groups = {} -- [name] = SoundGroup
local volumes = Logic.GroupVolumes(nil)
local pools = {} -- [key] = { flat = { entry }, spatial = { entry }, lastAt }
local loops = {} -- [key] = { sound, level, target, at }
local streaks = {} -- [key] = { count, lastAt }
local folder: Folder? = nil
local carrier: BasePart? = nil
local musicKey: string? = nil
local override: string? = nil
local duck = { level = 0, depth = 0, untilAt = 0 }

local function now(): number
	return os.clock()
end

function Audio.Spec(key: string)
	local cached = specs[key]
	if cached == nil then
		cached = Logic.Resolve(key, sounds[key]) or false
		specs[key] = cached
	end
	return cached or nil
end

function Audio.Filled(key: string): boolean
	local spec = Audio.Spec(key)
	return spec ~= nil and not spec.empty
end

function Audio.Muted(group: string): boolean
	return (volumes[group] or 0) <= 0
end

function Audio.Keys(): { string }
	local keys = {}
	for key in sounds do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Instances -----------------------------------------------------------------------------------

local function poolFolder(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "AudioPool"
		f.Parent = SoundService
		folder = f
	end
	return folder :: Folder
end

-- Positional sounds sit on Attachments of one invisible anchored part at the origin, so an
-- attachment's Position is its world position.
local function emitterCarrier(): BasePart
	if not carrier or not carrier.Parent then
		local part = Instance.new("Part")
		part.Name = "AudioEmitters"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.CFrame = CFrame.new()
		part.Parent = workspace
		carrier = part
	end
	return carrier :: BasePart
end

local function newSound(spec, spatial: boolean)
	local sound = Instance.new("Sound")
	sound.Name = spec.key
	sound.SoundId = spec.id
	sound.Volume = spec.volume
	sound.Looped = spec.looped
	sound.SoundGroup = groups[spec.group]
	local attachment = nil
	if spatial then
		attachment = Instance.new("Attachment")
		attachment.Name = spec.key
		attachment.Parent = emitterCarrier()
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = NEAR
		sound.RollOffMaxDistance = FAR
		sound.Parent = attachment
	else
		sound.Parent = poolFolder()
	end
	return { sound = sound, attachment = attachment, startedAt = -math.huge }
end

local function alive(entry): boolean
	return entry.sound.Parent ~= nil and (entry.attachment == nil or entry.attachment.Parent ~= nil)
end

local function acquire(key: string, spec, spatial: boolean)
	local pool = pools[key]
	if not pool then
		pool = { flat = {}, spatial = {}, lastAt = -math.huge }
		pools[key] = pool
	end
	local list = if spatial then pool.spatial else pool.flat
	local oldest = nil
	for i = #list, 1, -1 do
		local entry = list[i]
		if not alive(entry) then
			table.remove(list, i)
		elseif not entry.sound.Playing then
			return entry
		elseif not oldest or entry.startedAt < oldest.startedAt then
			oldest = entry
		end
	end
	if #list < spec.maxConcurrent or not oldest then
		local entry = newSound(spec, spatial)
		table.insert(list, entry)
		return entry
	end
	oldest.sound:Stop()
	return oldest
end

local function positionOf(at: any): Vector3?
	local kind = typeof(at)
	if kind == "Vector3" then
		return at
	elseif kind == "Instance" then
		if at:IsA("BasePart") then
			return at.Position
		elseif at:IsA("Attachment") then
			return at.WorldPosition
		elseif at:IsA("Model") and at.Parent then
			return at:GetPivot().Position
		end
	end
	return nil
end

-- One-shots --------------------------------------------------------------------------------------

function Audio.Play(key: string, opts: any?): Sound?
	local spec = Audio.Spec(key)
	if not spec or spec.empty or Audio.Muted(spec.group) then
		return nil
	end
	opts = if type(opts) == "table" then opts else {}
	local pool = pools[key]
	local t = now()
	if pool and t - pool.lastAt < spec.cooldown then
		return nil
	end
	local position = nil
	if opts.at ~= nil then
		position = positionOf(opts.at)
		if not position then
			return nil -- the thing it came from is gone
		end
	end
	local entry = acquire(key, spec, position ~= nil)
	pools[key].lastAt = t
	local sound = entry.sound
	sound.Looped = false
	sound.PlaybackSpeed = Logic.PickPitch(spec, math.random()) * (tonumber(opts.pitch) or 1)
	sound.Volume = spec.volume * (tonumber(opts.volume) or 1)
	if entry.attachment and position then
		entry.attachment.Position = position
		sound.RollOffMinDistance = tonumber(opts.near) or NEAR
		sound.RollOffMaxDistance = tonumber(opts.far) or FAR
	end
	entry.startedAt = t
	sound.TimePosition = 0
	sound:Play()
	if spec.duck > 0 then
		Audio.Duck(spec.duck, 1.4)
	end
	return sound
end

function Audio.Chain(keys: { string }, opts: any?): Sound?
	local key = Logic.First(sounds, keys)
	return if key then Audio.Play(key, opts) else nil
end

function Audio.Streak(key: string, opts: any?): Sound?
	local t = now()
	local streak = streaks[key]
	if not streak or t - streak.lastAt > STREAK_WINDOW then
		streak = { count = 0, lastAt = t }
		streaks[key] = streak
	end
	local o = if type(opts) == "table" then table.clone(opts) else {}
	o.pitch = (tonumber(o.pitch) or 1) * Logic.StreakPitch(streak.count + 1)
	local sound = Audio.Play(key, o)
	if sound then
		streak.count += 1
		streak.lastAt = t
	end
	return sound
end

function Audio.Playing(key: string): boolean
	local loop = loops[key]
	if loop and loop.sound.Playing then
		return true
	end
	local pool = pools[key]
	for _, list in if pool then { pool.flat, pool.spatial } else {} do
		for _, entry in list do
			if alive(entry) and entry.sound.Playing then
				return true
			end
		end
	end
	return false
end

function Audio.Stop(key: string)
	local pool = pools[key]
	for _, list in if pool then { pool.flat, pool.spatial } else {} do
		for _, entry in list do
			if alive(entry) then
				entry.sound:Stop()
			end
		end
	end
	local loop = loops[key]
	if loop then
		loop.target = 0
		loop.level = 0
		loop.sound.Volume = 0
		loop.sound:Stop()
	end
end

function Audio.Duck(depth: number, hold: number?)
	depth = math.clamp(tonumber(depth) or 0, 0, 1)
	local untilAt = now() + (tonumber(hold) or 1.2)
	if depth >= duck.depth or now() >= duck.untilAt then
		duck.depth = depth
	end
	duck.untilAt = math.max(duck.untilAt, untilAt)
end

-- Loops ------------------------------------------------------------------------------------------

function Audio.SetLoop(key: string, level: number, at: Vector3?)
	local loop = loops[key]
	if not loop then
		local spec = Audio.Spec(key)
		if not spec or spec.empty or (tonumber(level) or 0) <= 0 then
			return
		end
		local entry = newSound(spec, at ~= nil)
		entry.sound.Looped = true
		entry.sound.Volume = 0
		if entry.attachment and at then
			entry.attachment.Position = at
			entry.sound.RollOffMinDistance = 12
			entry.sound.RollOffMaxDistance = 70
		end
		loop = { sound = entry.sound, attachment = entry.attachment, level = 0, target = 0, spec = spec }
		loops[key] = loop
	end
	loop.target = math.clamp(tonumber(level) or 0, 0, 1)
	if at and loop.attachment then
		loop.attachment.Position = at
	end
end

function Audio.SetMusic(chain: { string }?): string?
	local key = if chain then Logic.First(sounds, chain) else nil
	if key ~= musicKey then
		if musicKey then
			Audio.SetLoop(musicKey, 0)
		end
		musicKey = key
	end
	if key then
		Audio.SetLoop(key, 1)
	end
	return key
end

function Audio.Music(): string?
	return musicKey
end

function Audio.Override(key: string?)
	if override and override ~= key and loops[override] and override ~= musicKey then
		loops[override].target = 0
	end
	override = key
	if key then
		Audio.SetLoop(key, 1)
	end
end

local function isBackground(spec): boolean
	return spec.group == "Music" or spec.group == "Ambience"
end

local function stepLoops(dt: number)
	for key, loop in loops do
		local spec = loop.spec
		local target = loop.target
		if override and isBackground(spec) then
			target = if key == override then 1 else 0
		end
		if Audio.Muted(spec.group) then
			target = 0
		end
		local rate = dt / (if spec.group == "Music" then MUSIC_FADE else BED_FADE)
		local level = loop.level
		if level < target then
			level = math.min(target, level + rate)
		elseif level > target then
			level = math.max(target, level - rate)
		end
		loop.level = level
		local sound = loop.sound
		if not sound.Parent then
			loops[key] = nil
			continue
		end
		local volume = spec.volume * level
		if math.abs(sound.Volume - volume) > 0.002 then
			sound.Volume = volume
		end
		if level > 0 and not sound.Playing then
			sound:Play()
		elseif level <= 0 and sound.Playing then
			sound:Stop()
		end
	end
end

local function stepGroups(dt: number)
	local t = now()
	local target = if t < duck.untilAt then duck.depth else 0
	if duck.level < target then
		duck.level = math.min(target, duck.level + DUCK_ATTACK * dt)
	elseif duck.level > target then
		duck.level = math.max(target, duck.level - DUCK_RELEASE * dt)
	end
	for name, group in groups do
		local base = volumes[name] or 0
		if name == "Music" then
			base *= 1 - duck.level
		elseif name == "Ambience" then
			base *= 1 - duck.level * 0.5
		end
		if math.abs(group.Volume - base) > 0.002 then
			group.Volume = base
		end
	end
end

-- Boot -------------------------------------------------------------------------------------------

function Audio.Preload(group: string)
	local list = {}
	for key in sounds do
		local spec = Audio.Spec(key)
		if spec and not spec.empty and spec.group == group then
			table.insert(list, acquire(key, spec, false).sound)
		end
	end
	if #list == 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		if not ok then
			warn("[Audio] preload failed: " .. tostring(err))
		end
	end)
end

function Audio.Attach(newStore, soundTable)
	if store == newStore then
		return
	end
	store = newStore
	sounds = if type(soundTable) == "table" then soundTable else {}
	table.clear(specs)
	for _, name in Logic.Groups do
		local group = SoundService:FindFirstChild(name)
		if not (group and group:IsA("SoundGroup")) then
			group = Instance.new("SoundGroup")
			group.Name = name
			group.Parent = SoundService
		end
		group.Volume = volumes[name]
		groups[name] = group
	end
	store:Observe("profile.Settings", function(settings)
		volumes = Logic.GroupVolumes(settings)
	end)
	RunService.Heartbeat:Connect(function(dt)
		stepGroups(dt)
		stepLoops(dt)
	end)
end

-- Test and Sound Check hook: the id table changed at runtime (resolved specs are cached).
function Audio.Refresh()
	table.clear(specs)
end

return Audio
