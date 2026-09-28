--!strict
-- Example marker bindings for Monster Ranch's townsfolk (ranch hands, visitors). Refs are the
-- Ranch's sound and Vfx names where they exist (CelebrateBig, EggCrack, hatch); "proposed"
-- ones are for the Foley Binder (SO3) to add.
return {
	["foot.l"] = { sound = "StepDirt", volume = 0.3, pitch = { 0.9, 1.1 }, note = "proposed" },
	["foot.r"] = { sound = "StepDirt", volume = 0.3, pitch = { 0.9, 1.1 }, note = "proposed" },
	hit = { sound = "HammerHit", volume = 0.7, note = "proposed: fence mending (hammer loop)" },
	pickup = { sound = "Pop", volume = 0.5, note = "proposed" },
	drop = { sound = "CoinDrop", volume = 0.6, note = "proposed: the market stall (sell loop)" },
	talk = { sound = "Chatter", volume = 0.25, chance = 0.4, note = "proposed" },
	swish = { fx = "dustPuff", note = "proposed: the startle emote kicks up dust" },
}
