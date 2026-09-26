--[[
	Voices: monster cries on top of the Audio kit. One voice family per Species archetype
	(Config.Sounds Voice<Archetype>), pitched by Logic/Audio.VoicePitch: younger and smaller
	monsters sound higher, and every line keeps its own small fixed offset (hash of its id).

	  Voices.Cry(target, kind) -> Sound?
	      target = a monster Model (pen monster: Line / Stage / Height attributes; positional)
	             or a monster record { line, stage, weight? } (not positional: menus, popups)
	      kind   = "hatch" | "evolve" | "levelUp" | "pet" | "happy" | "chatter"
	      "happy" and "chatter" are rate-limited per monster and overall.
	  Voices.Track(model) / Voices.Untrack(model)   pen monsters that may chatter (World)
	  Voices.Chatter(listener, count, range) -> n   soft chatter from at most `count` tracked
	      monsters within `range` studs of listener (closest first); call about once a second
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Logic = require(ReplicatedStorage.Shared.Logic.Audio)
local Audio = require(script.Parent)

local Voices = {}

-- volume and pitch multipliers per kind; `every` = seconds before the same monster repeats it,
-- `gap` = seconds before any monster may use it again.
local KINDS = {
	hatch = { volume = 1, pitch = 1 },
	evolve = { volume = 1, pitch = 0.96 },
	levelUp = { volume = 0.85, pitch = 1.06 },
	pet = { volume = 0.8, pitch = 1.08 },
	happy = { volume = 0.5, pitch = 1.04, every = 8, gap = 1.5, far = 55 },
	chatter = { volume = 0.3, pitch = 1, every = 9, gap = 0.8, far = 45 },
}

local lastByModel = setmetatable({}, { __mode = "k" }) -- [model] = { [kind] = t }
local lastByKind = {}
local tracked = setmetatable({}, { __mode = "k" })
local nextChatter = setmetatable({}, { __mode = "k" })

local function voiceInfo(target: any)
	if typeof(target) == "Instance" then
		local line = target:GetAttribute("Line")
		return {
			line = line,
			stage = target:GetAttribute("Stage"),
			height = target:GetAttribute("Height"),
		}, target
	elseif type(target) == "table" and type(target.line) == "string" then
		local def = Config.Species.ById[target.line]
		local height = nil
		-- Records carry weight, not size: scale the family's reference height by the cube root of
		-- how heavy this one is for its line.
		if def and type(target.weight) == "number" and type(def.weight) == "number" and def.weight > 0 and target.weight > 0 then
			height = 3 * (target.weight / def.weight) ^ (1 / 3)
		end
		return { line = target.line, stage = target.stage, height = height }, nil
	end
	return nil, nil
end

function Voices.Key(line: string?): string
	local def = if type(line) == "string" then Config.Species.ById[line] else nil
	return Logic.VoiceKey(def and def.archetype)
end

function Voices.Cry(target: any, kind: string): Sound?
	local tuning = KINDS[kind] or KINDS.happy
	local info, model = voiceInfo(target)
	if not info then
		return nil
	end
	local key = Voices.Key(info.line)
	if not Audio.Filled(key) or Audio.Muted("Voice") then
		return nil
	end
	local t = os.clock()
	if tuning.gap and t - (lastByKind[kind] or -math.huge) < tuning.gap then
		return nil
	end
	local byModel = nil
	if model and tuning.every then
		byModel = lastByModel[model] or {}
		lastByModel[model] = byModel
		if t - (byModel[kind] or -math.huge) < tuning.every then
			return nil
		end
	end
	local sound = Audio.Play(key, {
		at = model,
		pitch = Logic.VoicePitch(info) * tuning.pitch,
		volume = tuning.volume,
		near = 6,
		far = tuning.far or 70,
	})
	if sound then
		lastByKind[kind] = t
		if byModel then
			byModel[kind] = t
		end
	end
	return sound
end

function Voices.Track(model: Model)
	tracked[model] = true
end

function Voices.Untrack(model: Model)
	tracked[model] = nil
end

function Voices.Chatter(listener: Vector3?, count: number, range: number): number
	if not listener or count <= 0 or Audio.Muted("Voice") then
		return 0
	end
	local near = {}
	for model in tracked do
		if model.Parent then
			local line = model:GetAttribute("Line")
			if Audio.Filled(Voices.Key(line)) then
				local distance = (model:GetPivot().Position - listener).Magnitude
				if distance <= range then
					table.insert(near, { model = model, distance = distance })
				end
			end
		end
	end
	table.sort(near, function(a, b)
		return a.distance < b.distance
	end)
	local t = os.clock()
	local played = 0
	for i = 1, math.min(count, #near) do
		local model = near[i].model
		local due = nextChatter[model]
		if not due then
			-- First sight: stagger so a pen does not all speak at once.
			nextChatter[model] = t + 2 + math.random() * 8
		elseif t >= due then
			nextChatter[model] = t + 8 + math.random() * 10
			if Voices.Cry(model, "chatter") then
				played += 1
			end
		end
	end
	return played
end

return Voices
