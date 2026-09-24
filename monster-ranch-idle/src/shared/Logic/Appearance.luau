--[[
	Appearance: the public, render-only view of a monster. This is what other players see
	(ranch plots, trades, broadcasts) and what the Visuals builders consume. It never
	contains ids that grant ownership.
]]

local Config = require(script.Parent.Parent.Config)
local Formulas = require(script.Parent.Formulas)

local Species = Config.Species

local Appearance = {}

export type Appearance = {
	line: string,
	form: string,
	stage: number,
	rarity: number,
	variant: number,
	muts: { string },
	weight: number,
	name: string,
	elements: { string },
	archetype: string,
	lv: number,
	stars: number,
}

function Appearance.Of(m): Appearance
	local def = Species.ById[m.line]
	return {
		line = m.line,
		form = m.form,
		stage = m.stage,
		rarity = m.rarity,
		variant = m.variant or 0,
		muts = table.clone(m.muts or {}),
		weight = m.weight,
		name = Formulas.DisplayName(m),
		elements = table.clone(def.elements),
		archetype = def.archetype,
		lv = m.lv or 1,
		stars = m.stars or 1,
	}
end

-- A minimal appearance for previews (codex silhouettes, shop odds, breeding outcomes).
function Appearance.Preview(lineId: string, stage: number?, formId: string?, rarity: number?, variant: number?)
	local def = Species.ById[lineId]
	local s = stage or 1
	local form = Species.Form(lineId, s, formId)
	return {
		line = lineId,
		form = form.id,
		stage = s,
		rarity = rarity or 1,
		variant = variant or 0,
		muts = {},
		weight = def.weight,
		name = form.name,
		elements = table.clone(def.elements),
		archetype = def.archetype,
		lv = 1,
		stars = 1,
	}
end

return Appearance
