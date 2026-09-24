-- Social tuning: petting, likes, broadcasts and trading.
local Social = {}

Social.PetsPerDay = 20
Social.PetMood = 10
Social.FriendshipPerPet = 1
Social.LikesPerDay = 10

-- Which events are announced, and where. "server" = this server, "global" = all servers.
Social.Broadcasts = {
	hatchRarity = { [4] = "server", [5] = "server", [6] = "global" },
	hatchVariant = { [1] = "server", [2] = "global" }, -- golden = server, rainbow = global
	hybridDiscovery = "server",
	hugeWeight = "server",
	aurora = "global",
	topic = "MonsterRanchBroadcast", -- MessagingService topic
}
Social.HugeWeightMult = 1.8 -- weight ≥ 1.8× species average counts as Huge

Social.Trade = {
	unlock = "trading",
	minPlaySeconds = 30 * 60,
	maxItems = 8,
	countdownSeconds = 5,
	requestTimeout = 30,
	logDays = 30,
	maxLogEntries = 50,
}

return Social
