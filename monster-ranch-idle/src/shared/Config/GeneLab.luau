--[[
	Gene Lab (update 3.10 · Ranch life). From Ranch Level 21 (Unlocks "gene_lab"), reached from
	Monster Detail (the Gene Lab button on the genes line) and the Breeding Barn's header.
	Logic/GeneLab holds the rules; Systems/GeneLab applies them.

	Tune: an Adult's weaker gene of one stat (the first when both are equal) gains +1 on a
	success. The roll is seeded by ("genelab", userId, monsterId, attempt), attempt being the
	player's saved attempt counter, so rejoining never rerolls.
	  CostPerStep  Stardust per tune: CostPerStep × (gene + 1), gene = the weaker gene's value
	  Chances      the success chance by the weaker gene's value, first row whose `max` fits
	  Cap          the Lab never raises a gene above Cap (9 and 10 only come from breeding surges)
	  DailyTunes   tunes (successes and failures) per UTC day
	A failure spends the Stardust and leaves the gene unchanged.

	Lock: LockShards Star Shards lock one stat on one Adult. Its next baby gets that parent's
	better gene of the stat for certain (surges still apply after). Breeding consumes the lock
	when it rolls the baby (Breeding.Claim); a cancelled pod keeps it. One lock per monster:
	locking another stat replaces it (no refund). A monster that leaves the ranch (trade, Market)
	loses its lock (Monsters:Insert clears it).
]]

local GeneLab = {}

GeneLab.Unlock = "gene_lab"
GeneLab.CostPerStep = 20
GeneLab.Cap = 8
GeneLab.DailyTunes = 5
GeneLab.LockShards = 5

GeneLab.Chances = {
	{ max = 4, chance = 0.9 },
	{ max = 6, chance = 0.6 },
	{ max = 7, chance = 0.35 },
}

return GeneLab
