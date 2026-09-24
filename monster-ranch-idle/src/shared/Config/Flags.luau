--[[
	Feature flags and live event switches. Flip these to turn content on or off without
	unplugging systems. `ActiveEvent` is the id of the running seasonal event, or nil.
]]

return {
	ActiveEvent = nil :: string?, -- e.g. "frostfall"
	Trading = true,
	Caravans = true,
	RewardedAds = true,
	GlobalBroadcasts = true,
	TutorialScriptedRain = true,
	DebugCommands = false, -- enables the Debug.* actions in Studio only
}
