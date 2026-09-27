--[[
	FightLoot (R2 titan squads): the loot fountain a fallen giant sprays out, shared by
	Controllers/StampedeArena and Controllers/TitanInvasion. Purely the visual: a coin burst (and
	a hatch sparkle if the payload carries an egg) at the giant's position, then the reward kit
	(Controllers/Celebrate) flies the granted items to the HUD. Each caller decides `big` from its
	own domain rules (Boss: top-3 rank; Titan: everyone who helped gets the guaranteed egg).

	FightLoot.Fire(Vfx, kit, pos: Vector3, opts)
	    opts = { rewards: {...}?, egg: boolean?, eggColor: Color3?, big: boolean? }
]]

local FightLoot = {}

function FightLoot.Fire(Vfx, kit, pos: Vector3, opts)
	Vfx.Burst("coins", pos, { scale = 3 })
	if opts.egg then
		Vfx.Burst("hatch", pos, { scale = 2, color = opts.eggColor })
	end
	if kit and type(opts.rewards) == "table" then
		kit:Reward(opts.rewards, { from = pos, minSize = if opts.big then "big" else nil })
	end
end

return FightLoot
