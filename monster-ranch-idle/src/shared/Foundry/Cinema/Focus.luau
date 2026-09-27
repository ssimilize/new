--!strict
-- Focus: a depth-of-field curve by zoom. `zoom` is the camera's distance to its subject (studs),
-- the number Roblox's DepthOfFieldEffect needs (FocusDistance is measured from the camera).
--
--   curve = {
--     radiusRatio, minRadius, maxRadius,   in-focus radius = clamp(zoom * radiusRatio (+ widen), min, max)
--     maxFocus,                            FocusDistance cap (Roblox: 200)
--     nearIntensity, farIntensity,         full-strength intensities (0..1)
--     widen = bool?,                       past maxFocus, grow the radius by the gap so the subject
--                                          (behind the capped focus plane) stays sharp
--     fadeFrom = studs?, offAt = studs?,   fade the effect out between them (nil = never fades)
--     quality = { [1|2|3] = multiplier }?  per Contract quality level (1 low .. 3 high); nil = 1
--   }
--   Focus.dof(curve, zoom, quality?) -> { enabled, focusDistance, inFocusRadius, nearIntensity, farIntensity }
--       quality = a Contract level 1..3; nil = the curve's top level (full strength).
--   Focus.subjectSharp(dof, zoom) -> boolean   the subject at `zoom` sits inside the in-focus band
--   Focus.check(curve, zooms, quality?) -> { problem strings }   every zoom keeps its subject sharp
--       and every value stays inside Roblox's caps
--
-- Transcribes Guildhall DayNight Logic.dofFor (widen = true, fade 232..262) and Monster Ranch
-- PhotoMode's applyDepth + PhotoRig.FocusRadius (widen = false, no fade).

local Vec = require("./Vec")

export type Dof = {
	enabled: boolean,
	focusDistance: number,
	inFocusRadius: number,
	nearIntensity: number,
	farIntensity: number,
}

local Focus = {}

-- Roblox DepthOfFieldEffect property ranges.
Focus.CAPS = table.freeze({ focusDistance = 200, inFocusRadius = 50 })

local fin = Vec.finiteNumber

function Focus.validate(c: any): { string }
	local problems = {}
	if type(c) ~= "table" then
		return { "focus curve must be a table" }
	end
	local function need(cond: boolean, msg: string)
		if not cond then
			table.insert(problems, msg)
		end
	end
	need(fin(c.radiusRatio) and c.radiusRatio >= 0, "focus.radiusRatio must be >= 0")
	need(fin(c.minRadius) and fin(c.maxRadius) and c.minRadius >= 0 and c.maxRadius >= c.minRadius, "focus.minRadius <= focus.maxRadius")
	need(fin(c.maxRadius) and c.maxRadius <= Focus.CAPS.inFocusRadius, "focus.maxRadius must be <= 50 (Roblox cap)")
	need(fin(c.maxFocus) and c.maxFocus > 0 and c.maxFocus <= Focus.CAPS.focusDistance, "focus.maxFocus must be in (0, 200] (Roblox cap)")
	need(fin(c.nearIntensity) and c.nearIntensity >= 0 and c.nearIntensity <= 1, "focus.nearIntensity must be in [0, 1]")
	need(fin(c.farIntensity) and c.farIntensity >= 0 and c.farIntensity <= 1, "focus.farIntensity must be in [0, 1]")
	if c.fadeFrom ~= nil or c.offAt ~= nil then
		need(fin(c.fadeFrom) and fin(c.offAt) and c.offAt > c.fadeFrom, "focus.fadeFrom < focus.offAt (or neither)")
	end
	if c.quality ~= nil then
		local ok = type(c.quality) == "table"
		if ok then
			for lvl = 1, 3 do
				local q = c.quality[lvl]
				if not (fin(q) and q >= 0) then
					ok = false
				end
			end
		end
		need(ok, "focus.quality must give a multiplier >= 0 for levels 1, 2 and 3")
	end
	return problems
end

local function qualityMul(c: any, quality: number?): number
	if type(c.quality) ~= "table" then
		return 1
	end
	local lvl = if quality == nil then 3 else math.clamp(math.floor(quality + 0.5), 1, 3)
	return c.quality[lvl] or 0
end

function Focus.dof(c: any, zoom: number, quality: number?): Dof
	local d = math.max(0, if fin(zoom) then zoom else 0)
	local fade = 1
	if fin(c.fadeFrom) and fin(c.offAt) then
		fade = math.clamp((c.offAt - d) / math.max(1e-6, c.offAt - c.fadeFrom), 0, 1)
	end
	local s = fade * qualityMul(c, quality)
	local focus = math.clamp(d, 0, c.maxFocus)
	local widen = if c.widen then math.max(0, d - focus) else 0
	local out: Dof = {
		enabled = s > 1e-3,
		focusDistance = focus,
		inFocusRadius = math.clamp(d * c.radiusRatio + widen, c.minRadius, c.maxRadius),
		nearIntensity = math.clamp(c.nearIntensity * s, 0, 1),
		farIntensity = math.clamp(c.farIntensity * s, 0, 1),
	}
	if not out.enabled then
		out.nearIntensity, out.farIntensity = 0, 0
	end
	return out
end

-- A disabled effect blurs nothing, so its subject is sharp by definition.
function Focus.subjectSharp(dof: Dof, zoom: number): boolean
	if not dof.enabled then
		return true
	end
	return math.abs(zoom - dof.focusDistance) <= dof.inFocusRadius + 1e-9
end

function Focus.check(c: any, zooms: { number }, quality: number?): { string }
	local problems = Focus.validate(c)
	if #problems > 0 then
		return problems
	end
	for _, z in ipairs(zooms) do
		local d = Focus.dof(c, z, quality)
		if not Focus.subjectSharp(d, z) then
			table.insert(
				problems,
				string.format(
					"zoom %.2f: subject %.2f studs from the focus plane at %.2f, outside the in-focus radius %.2f",
					z,
					math.abs(z - d.focusDistance),
					d.focusDistance,
					d.inFocusRadius
				)
			)
		end
		if d.focusDistance > Focus.CAPS.focusDistance or d.inFocusRadius > Focus.CAPS.inFocusRadius then
			table.insert(problems, string.format("zoom %.2f: values past Roblox's caps", z))
		end
		if d.nearIntensity < 0 or d.nearIntensity > 1 or d.farIntensity < 0 or d.farIntensity > 1 then
			table.insert(problems, string.format("zoom %.2f: intensity outside [0, 1]", z))
		end
	end
	return problems
end

-- The zooms a Language profile's camera can take, for Focus.check: each god band sampled across
-- its fine range (`steps` + 1 points), or each rig band at subject heights from `heights`.
function Focus.zoomsFor(profile: any, steps: number?, heights: { number }?): { number }
	local out = {}
	local n = steps or 16
	if profile.kind == "god" then
		local g = profile.god
		for _, b in ipairs(g.bands) do
			for i = 0, n do
				table.insert(out, b * (g.fineMin + (g.fineMax - g.fineMin) * i / n))
			end
		end
	else
		local r = profile.rig
		local tan = 2 * math.tan(math.rad(r.fov) / 2)
		for _, fill in ipairs(r.bands) do
			for _, h in ipairs(heights or { 0.5, 1, 2, 4, 8, 16, 32 }) do
				table.insert(out, math.clamp(math.max(h, 0.5) / fill / tan, r.minDistance, r.maxDistance))
			end
		end
	end
	return out
end

return Focus
