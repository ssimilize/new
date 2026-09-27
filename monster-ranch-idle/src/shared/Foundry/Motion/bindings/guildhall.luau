--!strict
-- Example marker bindings for Guildhall (Markers binding format: { [marker] = { sound?, fx?,
-- volume?, pitch?, chance?, note? } }). Refs are Guildhall names the Foley Binder (SO3) and the
-- FX presets resolve; the ones marked "proposed" do not exist in the game yet.
return {
	["foot.l"] = { sound = "step.grass", volume = 0.35, pitch = { 0.92, 1.08 }, note = "proposed: a step bank per ground" },
	["foot.r"] = { sound = "step.grass", volume = 0.35, pitch = { 0.92, 1.08 }, note = "proposed" },
	hit = { sound = "sfx.anvil_hit", fx = "ambient.forge_sparks", volume = 0.8, note = "hammer / anvil_strike / saw: hit" },
	swish = { sound = "sfx.swish", volume = 0.5, note = "proposed" },
	pickup = { sound = "sfx.pickup", volume = 0.6, note = "proposed" },
	drop = { sound = "sfx.coin", volume = 0.6, note = "sell: the coin into the till (proposed)" },
	talk = { sound = "voice.murmur", volume = 0.3, chance = 0.5, note = "proposed: a murmur bank" },
	brush = { sound = "sfx.broom", volume = 0.4, note = "Guildhall sweep's own marker (proposed sound)" },
	puff = { fx = "ambient.chimney_puff", note = "bellows_pump" },
}
