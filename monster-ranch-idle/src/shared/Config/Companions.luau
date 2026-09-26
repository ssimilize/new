--[[
	Companions (glow-up T): one of your monsters walks beside you (three with VIP Rancher) in the
	hub, on the Sky Islands and on every ranch, and every player sees it. Purely cosmetic: a
	companion earns nothing, fights nothing and stays in its pen's income as before.

	Server rules (Systems/Companions): Slots / VipSlots, VipPass. Follow tuning (client,
	Controllers/Companions through Logic/Companions) is in studs and seconds; the gait numbers
	are shared with the animated mounts (Controllers/Mounts).
]]

local Companions = {}

Companions.Slots = 1 -- everyone
Companions.VipSlots = 3 -- VIP Rancher (Config.Monetization pass key below)
Companions.VipPass = "vip"
Companions.MaxSlots = 3 -- the largest of the two: the save and Companions.Set never hold more

-- Formation: the first companion trots at the owner's side, the rest spread into a small V
-- behind. Offsets are in the owner's space (x right, z behind), before the monster's size.
Companions.Formation = {
	{ x = 3.2, z = 1.2 },
	{ x = -3.2, z = 2.6 },
	{ x = 1.8, z = 4.8 },
}
Companions.SizeSpread = 0.35 -- extra spacing per stud of monster height past 3 studs

-- Follow
Companions.StartWalk = 1.6 -- studs from its spot before it sets off
Companions.StopWalk = 0.35 -- ...and when it counts as arrived
Companions.Gain = 3.2 -- speed = distance × Gain (eases in as it arrives), capped below
Companions.MinSpeed = 8
Companions.CatchUp = 1.35 -- max speed = owner speed × CatchUp (never below MinSpeed)
Companions.MaxSpeed = 48
Companions.TurnRate = 10 -- facing smoothing (1/s)
Companions.SitAfter = 2.5 -- the owner stood still this long: sit
Companions.HopSeconds = 0.55 -- a hop when the owner jumps
Companions.HopHeight = 1.6 -- × monster height / 3
Companions.JumpSpeed = 7 -- owner rising faster than this (studs/s) is a jump
Companions.TeleportDistance = 45 -- further than this from its spot: appear beside the owner
Companions.OwnerJump = 30 -- the owner moved this far in one frame: they teleported
Companions.GroundProbe = 8 -- raycast down from this high above the owner's feet...
Companions.GroundDepth = 18 -- ...this far
Companions.WallPad = 1.2 -- a spot behind a wall is pulled back this far towards the owner

-- Phones first: other players' companions within DrawDistance, nearest first, at most
-- MaxOthers (MaxOthersLow in low graphics). Far ones update at FarHz.
Companions.DrawDistance = 140
Companions.MaxOthers = 9
Companions.MaxOthersLow = 3
Companions.NearDistance = 60
Companions.FarHz = 10
Companions.PickEvery = 0.5 -- seconds between re-picking who is drawn

-- Gait (companions and mounts): a walk cycle covers Stride × height studs, so the clip plays
-- speed / (Stride × height) cycles a second, clamped to MinRate..MaxRate × its authored speed.
Companions.Stride = 2.2
Companions.MinRate = 0.5
Companions.MaxRate = 2.6
Companions.MoveSpeed = 1.2 -- below this (studs/s) a monster or mount counts as standing
Companions.Smoothing = 8 -- a mount's measured speed eases towards the true one (1/s)
-- MeshMonster.Pose eases every clip switch (its BLEND), so idle ↔ walk ↔ hop never snaps.

return Companions
