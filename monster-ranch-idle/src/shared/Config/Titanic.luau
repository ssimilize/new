--[[
	Titanic (glow-up W): the size tier above Huge. Rules in Logic/Titanic, the roll in
	MonsterGen.RollSize, the record flag `titanic = true`.

	A Titanic is rolled by the same draw that rolls Huge (MonsterGen.RollSize), so adding the tier
	moved no other roll: a draw below Chance is Titanic, below HugeChance is Huge. It comes from
	hatches and granted monsters (never from breeding: bred weights are inherited). Titanic is
	looks only: size, aura, a deeper cry and a chip. No stat, coin rate or power reads it.
]]

local Titanic = {}

Titanic.HugeChance = 0.01 -- a Huge weight roll (1.8×–2.0× the line's average weight)
Titanic.Chance = 0.0005 -- 1 in 2,000 hatches (a twentieth of the Huge rolls)

Titanic.WeightMult = { 2.2, 2.5 } -- kg vs the line's average (the breeding ratio range tops out at 2.5)

-- Model size multiplier (instead of the weight's cube root, which stops at 1.3×). Pens cap it so a
-- Titanic stays inside its fence (a 3× adult is ~9 studs wide; pen fences leave ~7 studs of
-- room from the pen centre); cards, the hatch reveal, the Codex and showcases use the full size.
Titanic.Scale = 3
Titanic.PenScale = 2.2

Titanic.CryPitch = 0.8 -- × the monster's voice pitch: a deeper cry
Titanic.Celebration = "huge" -- Celebrate size played on a Titanic hatch reveal

Titanic.Color = "#E8436F" -- chip colour

return Titanic
