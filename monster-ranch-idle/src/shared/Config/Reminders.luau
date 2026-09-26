--[[
	Reminders (glow-up): opt-in Roblox Experience Notifications for offline players.

	OFF until the owner fills SecretName and at least one template id (docs/GO_LIVE.md §5):
	  SecretName  name of the Open Cloud API key stored as an experience secret
	              (Creator Hub → Secrets), read with HttpService:GetSecret on the server
	  Templates   notification message ids from Creator Hub → Engagement → Notifications,
	              one per reminder kind; an empty id turns that kind off

	Kinds (planned when an opted-in player leaves, see Logic/Reminders):
	  egg         every incubating egg is ready to hatch
	  expedition  every running expedition is back
	  stampede    the first Stampede at least Stampede.minAwaySeconds after leaving (players who
	              have joined one before)
	  streak      a streak with no shield breaks at the end of the UTC day; sent hoursLeft before

	Delivery: planned items wait in a MemoryStore sorted map keyed by due time; every running
	server polls it and leases an item before sending, so two servers never send the same one.
	A player gets at most MaxPerDay reminders per UTC day, MinGapSeconds apart, never inside
	the quiet hours of a rough local time guessed from the player's country (Offsets; countries
	missing there get no quiet-hours rule). Nothing is sent to a player who is online.
]]

local Reminders = {}

Reminders.SecretName = "" -- e.g. "notifications_key"; "" = feature off
Reminders.Templates = {
	egg = "",
	expedition = "",
	stampede = "",
	streak = "",
}
Reminders.Kinds = { "egg", "expedition", "stampede", "streak" }

Reminders.Url = "https://apis.roblox.com/cloud/v2/users/%d/notifications"

Reminders.MaxPerDay = 2
Reminders.MinGapSeconds = 4 * 3600
Reminders.MaxPlanned = 3 -- items planned per departure (soonest first)
Reminders.MinAwaySeconds = 30 * 60 -- nothing is due sooner than this after leaving
Reminders.ExpireSeconds = 12 * 3600 -- a reminder not sent by then is dropped
Reminders.PollSeconds = 30
Reminders.LeaseSeconds = 60
Reminders.BatchSize = 10
Reminders.MaxTries = 3

Reminders.Stampede = { minAwaySeconds = 3 * 3600, leadSeconds = 5 * 60 }
Reminders.Streak = { minStreak = 2, hoursLeft = 4 }

-- Quiet hours in the player's rough local time: [start, stop) wraps midnight.
Reminders.Quiet = { start = 22, stop = 8 }

-- Rough standard-time UTC offsets (hours) by Roblox country code. Daylight saving is ignored;
-- a big country gets its most populous zone.
Reminders.Offsets = {
	US = -6,
	CA = -5,
	MX = -6,
	BR = -3,
	AR = -3,
	CL = -4,
	CO = -5,
	PE = -5,
	VE = -4,
	EC = -5,
	GT = -6,
	DO = -4,
	PR = -4,
	UY = -3,
	PY = -4,
	BO = -4,
	CR = -6,
	PA = -5,
	GB = 0,
	IE = 0,
	PT = 0,
	ES = 1,
	FR = 1,
	DE = 1,
	IT = 1,
	NL = 1,
	BE = 1,
	CH = 1,
	AT = 1,
	PL = 1,
	CZ = 1,
	SE = 1,
	NO = 1,
	DK = 1,
	FI = 2,
	GR = 2,
	RO = 2,
	UA = 2,
	ZA = 2,
	EG = 2,
	TR = 3,
	RU = 3,
	SA = 3,
	AE = 4,
	IN = 5.5,
	TH = 7,
	VN = 7,
	ID = 7,
	PH = 8,
	MY = 8,
	SG = 8,
	CN = 8,
	TW = 8,
	HK = 8,
	JP = 9,
	KR = 9,
	AU = 10,
	NZ = 12,
}

function Reminders.Enabled(): boolean
	if Reminders.SecretName == "" then
		return false
	end
	for _, id in Reminders.Templates do
		if id ~= "" then
			return true
		end
	end
	return false
end

return Reminders
