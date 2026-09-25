--[[
	Feature flags and live event switches. Flip these to turn content on or off without
	unplugging systems. `ActiveEvent` overrides the event calendar (Config/Events): an event
	id forces it, false turns events off, nil follows the calendar.
]]

return {
	ActiveEvent = nil :: (string | boolean)?, -- nil = calendar; "frostfall" forces it; false = none
	Trading = true,
	Caravans = true,
	RewardedAds = true,
	GlobalBroadcasts = true,
	TutorialScriptedRain = true,
	DebugCommands = false, -- enables the Debug.* actions in Studio only
}
