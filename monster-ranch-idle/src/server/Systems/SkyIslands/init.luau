--[[
	SkyIslands (update 2.0): wind crystals on the floating islands. Rules and spots live in
	Config/SkyIslands; the islands themselves in Config.World.Sky (built by World/Build).

	Save section (profile.SkyIslands):
	  taken = { [crystalIndex as string] = unix }  -- when this player last collected it
	  day   = number                               -- UTC day of `count`
	  count = number                               -- crystals collected today (≤ DailyCap)
	  total = number                               -- all time

	SkyIslands.Collect { crystal } checks: Sky Islands unlocked, the crystal has respawned for
	this player, the daily cap, and that the player's character stands within Reach studs.
	It pays one Loot roll through Rewards and publishes CrystalCollected.
	Travel between the hub and the islands is client-side (launch/return pads).
]]

local SkyIslands = {
	Name = "SkyIslands",
	Dependencies = { "Progression", "Rewards" },
}

SkyIslands.Profile = {
	Version = 1,
	Default = function()
		return { taken = {}, day = 0, count = 0, total = 0 }
	end,
}

local ctx
local Config -- Config.SkyIslands
local Progression, Rewards

local function characterPosition(player)
	local ok, position = pcall(function()
		return player.Character.HumanoidRootPart.Position
	end)
	return if ok then position else nil
end

local function distance(a, b): number
	return math.sqrt((a.X - b[1]) ^ 2 + (a.Y - b[2]) ^ 2 + (a.Z - b[3]) ^ 2)
end

local function roll()
	local weights = {}
	for i, entry in Config.Loot do
		weights[i] = entry.weight
	end
	return table.clone(Config.Loot[ctx.Rng:Weighted(weights)].item)
end

local function collect(player, index: number)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	Progression:Require(player, Config.Unlock)
	local spot = Config.Crystals[index]
	local now = ctx:Now()
	local key = tostring(index)
	local last = s.taken[key] or 0
	if now - last < Config.RespawnSeconds then
		ctx:Fail("That crystal is still recharging")
	end
	if s.day ~= ctx:Day() then
		s.day = ctx:Day()
		s.count = 0
	end
	if s.count >= Config.DailyCap then
		ctx:Fail("The winds are calm. Come back tomorrow for more crystals!")
	end
	local position = characterPosition(player)
	if not position or distance(position, spot) > Config.Reach then
		ctx:Fail("Get closer to the crystal")
	end
	s.taken[key] = now
	s.count += 1
	s.total += 1
	ctx:Dirty(player)
	local granted = Rewards:Grant(player, { roll() }, "sky_crystal")
	ctx.Bus:Publish("CrystalCollected", player, { crystal = index })
	return { rewards = granted, nextAt = now + Config.RespawnSeconds }
end

function SkyIslands.Init(context)
	ctx = context
	Config = ctx.Config.SkyIslands
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")
	ctx.Net:Handle("SkyIslands.Collect", function(player, payload)
		return collect(player, payload.crystal)
	end)
end

function SkyIslands.PlayerAdded(player, _info)
	-- Forget timers that have long expired so the save stays small.
	local s = ctx:Section(player)
	local now = ctx:Now()
	for key, at in s.taken do
		if now - at >= Config.RespawnSeconds then
			s.taken[key] = nil
			ctx:Dirty(player, "taken", key)
		end
	end
end

return SkyIslands
