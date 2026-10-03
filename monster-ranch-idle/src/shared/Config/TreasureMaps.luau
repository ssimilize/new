--[[
	Treasure Maps (update 3.13 · Wild things). From Ranch Level 23 (Unlocks "treasure_maps") map
	pieces drop from the ranch's adventures; PiecesPerMap pieces join into a Treasure Map by
	themselves. A map marks an X in one of the player's open expedition regions (a region that is
	open, unlocked and has a cleared stage) and a guardian stands on it: a wave of that region's
	enemies (Logic/BattleSim.BuildEnemies of a cleared stage), scaled to GuardianMult × the stage's
	recommended power, fought as a boss. Reached from the "Maps" button in the Expeditions header;
	no world building. Rules in Logic/TreasureMaps, the server in Systems/TreasureMaps.

	Drops (only once unlocked; each roll on the map's own seeded stream, never ctx.Rng):
	  expedition  Drops.expedition per claimed expedition (Expeditions claims)
	  bounty      BountyPieces, guaranteed, on an Expedition Bounty's first win
	  fishing     Drops.fishing per fish caught at the Fishing Pond
	  dig         Drops.dig per find tile at the Dig Site
	Rewards kind "map_piece" also adds pieces (TreasureMaps:AddPieces).

	Holding: at most MaxMaps maps; pieces past that wait (at most PieceCap held).

	Digging (TreasureMaps.Dig { map }): one fight with the Expeditions squad; a win opens the chest
	and uses the map, a loss keeps it (retry any time, no cost). The chest (rolled from the map's
	seed): ChestSeconds of ranch income in coins (+ ChestSecondsPerRegion per region order past the
	first), ChestGems (+ ChestGemsPerRegion), the region's egg, and a DecorChance of one map-only
	decor piece (Decor, never sold).
]]

local TreasureMaps = {}

TreasureMaps.Unlock = "treasure_maps"
TreasureMaps.Source = "treasure" -- Rewards source (reward card "Rewards · Treasure")

TreasureMaps.PiecesPerMap = 4
TreasureMaps.MaxMaps = 3
TreasureMaps.PieceCap = 12

TreasureMaps.Drops = {
	expedition = 0.03,
	fishing = 0.02,
	dig = 0.05,
}
TreasureMaps.BountyPieces = 1

-- The guardian.
TreasureMaps.GuardianMult = 1.3 -- × the stage's recommended power
TreasureMaps.StageSpread = 4 -- the map's stage: the highest cleared stage or up to this many below it

-- The chest.
TreasureMaps.ChestSeconds = 2400
TreasureMaps.ChestSecondsPerRegion = 600
TreasureMaps.ChestGems = 25
TreasureMaps.ChestGemsPerRegion = 5
TreasureMaps.DecorChance = 0.25
TreasureMaps.Decor = { "pirate_chest", "old_anchor", "treasure_globe" } -- Config/Decor, map-only

return TreasureMaps
