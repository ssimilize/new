--!strict
-- Procedural: the life layered over any clip, as pure functions of time, a per-character seed
-- and the inputs a game hands in. Each returns pose OFFSETS ({ [joint] = { rx?, ry?, rz?, x?,
-- y?, z? } }, degrees and studs) that Motion.add puts on top of a sampled clip. No state:
-- the same seed and time give every client the same breath, the same blink.
--
--   Procedural.breathe(t, seed, cfg?, tier?)       chest rise, head steadying, shoulder lift
--   Procedural.breatheAt(t, phase, cfg?, tier?)    the same with the crowd phase handed in
--   Procedural.blink(t, seed, cfg?) -> open 0..1   seeded blink times (never closer than minGap)
--   Procedural.blinkOpen(since, dur, double?)      one blink's openness (own blink schedules)
--   Procedural.lookAt(target, cfg?)                Neck + a share of Waist, clamped to limits
--   Procedural.lookAngles(target, cfg?) -> yaw?, pitch?   the clamped angles, unsplit
--   Procedural.footPlant(rig, ground, place, cfg?) root drop + hip/knee/ankle bends so both
--                                                  feet meet uneven ground
--   Procedural.lean(motion, cfg?)                  bank into turns, pitch with speed/accel
--   Procedural.tier(dist, fovDeg?, quality?, lod?) near | mid | far | off
--   Procedural.due(frame, tier, seed, lod?)        is this rig updated this frame
--   Procedural.compose(t, seed, tier, inputs, cfg?) -> offsets, face   every layer the tier allows
--
-- The numbers default to Guildhall AnimLibrary Config.life / Config.face (read 2026-09-27) and
-- the LOD rules are its roblox/Life.luau as data: near = everything, mid = no shoulder lift
-- and no foot planting, far = breath and lean only, off = nothing. A game passes its own cfg.

local M = require("./Math")

local Procedural = {}

Procedural.DEFAULTS = table.freeze({
	breath = table.freeze({ period = 3.4, chest = 1.1, shoulder = 0.012 }),
	lean = table.freeze({ bank = 1.1, maxBank = 9, speed = 0.55, accel = 0.35, maxPitch = 7 }),
	look = table.freeze({ maxYaw = 55, maxPitch = 22, behind = 50, waistShare = 0.2 }),
	blink = table.freeze({ minGap = 2.2, maxGap = 5.5, dur = 0.16, double = 0.18 }),
	feet = table.freeze({ maxLift = 0.45, maxDrop = 0.6, maxKnee = 110 }),
})

Procedural.LOD = table.freeze({
	-- apparent distance (studs as a refFov camera sees them) -> tier, scaled per quality
	near = 55,
	mid = 90,
	far = 150,
	refFov = 70,
	scale = table.freeze({ high = 1, medium = 0.7, low = 0 }),
	every = table.freeze({ near = 1, mid = 3, far = 8, off = 20 }),
	layers = table.freeze({
		near = table.freeze({ breathe = true, shoulders = true, blink = true, look = true, lean = true, feet = true }),
		mid = table.freeze({ breathe = true, blink = true, look = true, lean = true }),
		far = table.freeze({ breathe = true, lean = true }),
		off = table.freeze({}),
	}),
})

local function cfgOf(cfg: any, key: string): any
	return (cfg and cfg[key]) or Procedural.DEFAULTS[key]
end

-- phase(seed) -> 0..1, desyncs a crowd
function Procedural.phase(seed: number): number
	return M.hash01(seed, 1)
end

function Procedural.breathe(t: number, seed: number, cfg: any?, tier: string?): { [string]: any }
	return Procedural.breatheAt(t, Procedural.phase(seed), cfg, tier)
end

-- breatheAt(t, phase, cfg?, tier?): breathe with the crowd phase (0..1) handed in, for a game
-- that draws its per-rig phases from its own hash (Guildhall: Logic.hash01(seed, 77)).
function Procedural.breatheAt(t: number, phase: number, cfg: any?, tier: string?): { [string]: any }
	local b = cfgOf(cfg, "breath")
	local s = math.sin(2 * math.pi * (t / b.period + phase))
	local out: { [string]: any } = {
		Waist = { rx = s * b.chest },
		Neck = { rx = -s * b.chest * 0.5 },
	}
	if tier == nil or tier == "near" then
		local lift = (s * 0.5 + 0.5) * b.shoulder
		out.LeftShoulder = { y = lift }
		out.RightShoulder = { y = lift }
	end
	return out
end

-- Blink k of a character starts in slot k (slot = (minGap + maxGap) / 2 s) at a seeded point
-- of its first slot - minGap seconds, so two blinks are always minGap..maxGap apart.
function Procedural.blinkStart(seed: number, k: number, cfg: any?): (number, boolean)
	local b = cfgOf(cfg, "blink")
	local slot = (b.minGap + b.maxGap) / 2
	local start = k * slot + M.hash01(seed, 100 + k) * (slot - b.minGap)
	return start, M.hash01(seed, 2000 + k) < b.double
end

-- blinkOpen(since, dur, double) -> eye openness 0 (shut) .. 1 (open), `since` seconds into a
-- blink: shut fast (35 %), open slower; a double blink shuts twice with a short gap. Exposed
-- for a game that schedules its own blinks (Guildhall keeps a per-rig gap sequence).
local function openAt(since: number, dur: number, double: boolean?): number
	local s = since
	if s < 0 then
		return 1
	end
	if double then
		if s >= dur and s < dur * 1.25 then
			return 1
		elseif s >= dur * 1.25 then
			s -= dur * 1.25
		end
	end
	if s >= dur then
		return 1
	end
	local p = s / dur
	if p < 0.35 then
		return 1 - p / 0.35
	end
	return (p - 0.35) / 0.65
end

Procedural.blinkOpen = openAt

function Procedural.blink(t: number, seed: number, cfg: any?): number
	local b = cfgOf(cfg, "blink")
	local slot = (b.minGap + b.maxGap) / 2
	local k = math.floor(t / slot)
	local open = 1
	for j = k - 1, k do
		if j >= 0 then
			local start, double = Procedural.blinkStart(seed, j, cfg)
			open = math.min(open, openAt(t - start, b.dur, double))
		end
	end
	return open
end

-- lookAngles(target, cfg?) -> yaw, pitch (degrees, clamped to the head's limits) toward
-- target = { x, y, z } in the rig's frame, or nil, nil when it is too far behind to turn
-- toward; yaw > 0 turns left, pitch > 0 looks up. A game that smooths the angles before it
-- splits them between Neck and Waist (Guildhall's look springs) takes these.
function Procedural.lookAngles(target: any, cfg: any?): (number?, number?)
	local l = cfgOf(cfg, "look")
	local x, y, z = target.x or target[1] or 0, target.y or target[2] or 0, target.z or target[3] or 0
	local yaw = math.deg(math.atan2(-x, -z))
	if math.abs(yaw) > l.maxYaw + l.behind then
		return nil, nil
	end
	local flat = math.sqrt(x * x + z * z)
	local pitch = math.deg(math.atan2(y, math.max(flat, 1e-6)))
	return M.clamp(yaw, -l.maxYaw, l.maxYaw), M.clamp(pitch, -l.maxPitch, l.maxPitch)
end

-- lookAt(target, cfg?) -> offsets toward target = { x, y, z } in the rig's frame (x right,
-- y up, -z forward). Too far behind -> {} (the head does not snap round).
function Procedural.lookAt(target: any, cfg: any?): { [string]: any }
	local l = cfgOf(cfg, "look")
	local yaw, pitch = Procedural.lookAngles(target, cfg)
	if yaw == nil or pitch == nil then
		return {}
	end
	return {
		Neck = { rx = pitch, ry = yaw * (1 - l.waistShare) },
		Waist = { ry = yaw * l.waistShare },
	}
end

-- A leg shortened by d from its straight length: hip swing forward, knee bend, ankle back to
-- flat (degrees; knee negative = bend, the R15 convention).
local function legBend(a: number, b: number, d: number, maxKnee: number): (number, number, number)
	local L = a + b
	local want = M.clamp(L - d, math.abs(a - b) + 1e-4, L)
	local interior = math.deg(math.acos(M.clamp((a * a + b * b - want * want) / (2 * a * b), -1, 1)))
	local bend = math.min(180 - interior, maxKnee)
	-- recompute the reachable length for the clamped bend so hip and ankle stay consistent
	local kr = math.rad(180 - bend)
	want = math.sqrt(a * a + b * b - 2 * a * b * math.cos(kr))
	local hip = math.deg(math.acos(M.clamp((a * a + want * want - b * b) / (2 * a * want), -1, 1)))
	return hip, -bend, bend - hip
end

local function legLengths(rig: any, side: string): (number, number)
	local hip, knee, ankle
	for _, j in rig.joints do
		if j.name == side .. "Hip" then
			hip = j.at
		elseif j.name == side .. "Knee" then
			knee = j.at
		elseif j.name == side .. "Ankle" then
			ankle = j.at
		end
	end
	return hip[2] - knee[2], knee[2] - ankle[2]
end

-- footPlant(rig, ground, place, cfg?) -> offsets.
--   rig    Motion.Rig.r15(...) (leg lengths and hip spacing come from it)
--   ground (x, z) -> y, the world's ground height
--   place  { x, y, z, yaw? } the character's root on the ground plane (y = where it stands),
--          yaw in degrees (0 faces -z)
-- The root drops to the lower foot (at most maxDrop studs); the higher foot's leg bends to
-- meet its ground (at most maxLift studs, knee at most maxKnee degrees).
function Procedural.footPlant(rig: any, ground: (number, number) -> number, place: any, cfg: any?): { [string]: any }
	local f = cfgOf(cfg, "feet")
	local yaw = math.rad(place.yaw or 0)
	local c, s = math.cos(yaw), math.sin(yaw)
	local h = {}
	for _, side in { "Left", "Right" } do
		local ankle
		for _, j in rig.joints do
			if j.name == side .. "Ankle" then
				ankle = j.at
			end
		end
		assert(ankle, "footPlant: the rig has no " .. side .. "Ankle")
		local wx = place.x + ankle[1] * c + ankle[3] * s
		local wz = place.z - ankle[1] * s + ankle[3] * c
		h[side] = ground(wx, wz) - place.y
	end
	local drop = M.clamp(math.min(h.Left, h.Right), -f.maxDrop, f.maxLift)
	local out: { [string]: any } = { Root = { y = drop } }
	for _, side in { "Left", "Right" } do
		local a, b = legLengths(rig, side)
		local d = M.clamp(h[side] - drop, 0, f.maxLift)
		if d > 1e-6 then
			local hip, knee, ankle = legBend(a, b, d, f.maxKnee)
			out[side .. "Hip"] = { rx = hip }
			out[side .. "Knee"] = { rx = knee }
			out[side .. "Ankle"] = { rx = ankle }
		end
	end
	return out
end

-- lean(motion, cfg?) -> Root offsets. motion = { speed (studs/s), yawRate (rad/s, + = left),
-- accel (studs/s^2 forward) }. Bank and pitch are clamped to maxBank / maxPitch.
function Procedural.lean(motion: any, cfg: any?): { [string]: any }
	local l = cfgOf(cfg, "lean")
	local speed = motion.speed or 0
	local bank = M.clamp((motion.yawRate or 0) * speed * l.bank, -l.maxBank, l.maxBank)
	local pitch = -M.clamp(speed * l.speed + (motion.accel or 0) * l.accel, -l.maxPitch, l.maxPitch)
	return { Root = { rx = pitch, rz = bank } }
end

-- tier(dist, fovDeg?, quality?, lod?) -> "near" | "mid" | "far" | "off". dist is the real
-- camera distance; a narrow lens brings things in (apparent distance at refFov).
function Procedural.tier(dist: number, fovDeg: number?, quality: string?, lod: any?): string
	local L = lod or Procedural.LOD
	local f = M.clamp(fovDeg or L.refFov, 1, 120)
	local apparent = dist * math.tan(math.rad(f / 2)) / math.tan(math.rad(L.refFov / 2))
	local k = L.scale[quality or "high"]
	if k == nil then
		k = 1
	end
	if k <= 0 then
		return "off"
	end
	if apparent <= L.near * k then
		return "near"
	elseif apparent <= L.mid * k then
		return "mid"
	elseif apparent <= L.far * k then
		return "far"
	end
	return "off"
end

-- due(frame, tier, seed, lod?) -> this rig updates on this frame (every[tier] frames,
-- offset by the seed so a crowd spreads its updates).
function Procedural.due(frame: number, tier: string, seed: number, lod: any?): boolean
	local L = lod or Procedural.LOD
	if tier == "off" then
		return false
	end
	local every = L.every[tier] or 1
	return (frame + math.floor(M.hash01(seed, 7) * every)) % every == 0
end

local function merge(into: { [string]: any }, add: { [string]: any })
	for joint, off in add do
		local p = into[joint] or {}
		for k, v in off do
			p[k] = (p[k] or 0) + v
		end
		into[joint] = p
	end
end

-- compose(t, seed, tier, inputs, cfg?, lod?) -> offsets, face
--   inputs = { motion?, lookTarget?, rig?, ground?, place? } (a missing input skips its layer)
--   face = { open = 0..1 } when the tier blinks, else {}
function Procedural.compose(t: number, seed: number, tier: string, inputs: any, cfg: any?, lod: any?): ({ [string]: any }, { [string]: any })
	local L = lod or Procedural.LOD
	local on = L.layers[tier] or {}
	local out: { [string]: any } = {}
	local face: { [string]: any } = {}
	local i = inputs or {}
	if on.breathe then
		merge(out, Procedural.breathe(t, seed, cfg, if on.shoulders then "near" else "mid"))
	end
	if on.lean and i.motion then
		merge(out, Procedural.lean(i.motion, cfg))
	end
	if on.look and i.lookTarget then
		merge(out, Procedural.lookAt(i.lookTarget, cfg))
	end
	if on.feet and i.rig and i.ground and i.place then
		merge(out, Procedural.footPlant(i.rig, i.ground, i.place, cfg))
	end
	if on.blink then
		face.open = Procedural.blink(t, seed, cfg)
	end
	return out, face
end

return Procedural
