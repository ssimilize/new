--[[
	Titanic (glow-up W): pure rules for the size tier above Huge (Config.Titanic).

	  Titanic.Is(m) -> boolean                         record or appearance (`titanic == true`)
	  Titanic.Classify(roll01) -> "titanic"|"huge"|nil the size tier of MonsterGen.RollSize's draw
	  Titanic.WeightMult(tier, r01) -> number?         kg multiplier for a tier (nil = normal curve)
	  Titanic.SizeMult(appearance, inPen?) -> number   model size multiplier from weight or tier
	  Titanic.Odds() -> { huge, titanic }              per-hatch chances shown with egg odds
	  Titanic.CryPitch(info) -> number                 voice pitch multiplier (deeper when Titanic)
]]

local Config = require(script.Parent.Parent.Config)

local Cfg = Config.Titanic

local Titanic = {}

function Titanic.Is(m): boolean
	return type(m) == "table" and m.titanic == true
end

function Titanic.Classify(roll01: number): string?
	if roll01 < Cfg.Chance then
		return "titanic"
	elseif roll01 < Cfg.HugeChance then
		return "huge"
	end
	return nil
end

function Titanic.WeightMult(tier: string?, r01: number): number?
	if tier == "titanic" then
		return Cfg.WeightMult[1] + (Cfg.WeightMult[2] - Cfg.WeightMult[1]) * r01
	elseif tier == "huge" then
		return 1.8 + 0.2 * r01
	end
	return nil
end

-- Weight scale is a cube root (heavy monsters are bigger, not absurd), clamped 0.8×–1.3×. A
-- Titanic replaces it with Scale, or PenScale inside a pen so it never clips through the fence.
function Titanic.SizeMult(appearance, inPen: boolean?): number
	if Titanic.Is(appearance) then
		return if inPen then math.min(Cfg.PenScale, Cfg.Scale) else Cfg.Scale
	end
	local def = type(appearance) == "table" and Config.Species.ById[appearance.line]
	local avg = if def then def.weight else 1
	local w = if type(appearance) == "table" and type(appearance.weight) == "number" then appearance.weight else avg
	return math.clamp((w / avg) ^ (1 / 3), 0.8, 1.3)
end

-- Huge here is the Huge-but-not-Titanic share, so the two chances add up to HugeChance.
function Titanic.Odds(): { huge: number, titanic: number }
	return { huge = Cfg.HugeChance - Cfg.Chance, titanic = Cfg.Chance }
end

function Titanic.CryPitch(info): number
	return if type(info) == "table" and info.titanic == true then Cfg.CryPitch else 1
end

return Titanic
