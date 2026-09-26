--[[
	Bond (glow-up Q): caring for your own monsters. Tuning only: rules in Logic/Bond, the server
	in Systems/Bond, the gestures in Controllers/Care and Screens/Care.

	Fairness (pillar P5): bond never goes down. Nothing decays while a player is away, nothing is
	for sale, and the bonus is small and income-only (never fights). A care gesture always plays;
	each kind just adds bond at most once per monster every `cooldown` seconds.

	Bond belongs to the monster on this ranch: it resets when the monster leaves (sold, retired,
	fused, traded, listed on the Market). A traded monster arrives with a new id and no bond, so
	bond can't be raised on one account and sold on another.
]]

local Bond = {}

-- The three care gestures. `state` is the MonsterAnimator reaction (fallback while missing).
Bond.Kinds = {
	{ id = "pet", name = "Pet", hint = "Press and hold on it", glyph = "🤚", state = "happy", fallback = "happy" },
	{ id = "brush", name = "Brush", hint = "Drag back and forth across it", glyph = "✨", state = "sit", fallback = "happy" },
	{ id = "play", name = "Play", hint = "Tap each time it bounces", glyph = "🎾", state = "trick", fallback = "happy" },
}
Bond.KindById = {}
Bond.KindIds = {}
for _, kind in Bond.Kinds do
	Bond.KindById[kind.id] = kind
	table.insert(Bond.KindIds, kind.id)
end

Bond.cooldown = 4 * 3600 -- seconds before one kind adds bond to the same monster again
Bond.minGap = 3 -- seconds between two bond-adding cares from one player (a gesture takes ~5 s)
Bond.MaxHearts = 10

-- Bond points needed for each heart (cumulative). One care = 1 point, so three kinds a visit:
-- 3 hearts on day one, 10 hearts after a couple of weeks of casual care.
Bond.HeartAt = { 1, 3, 6, 10, 15, 21, 28, 36, 45, 55 }

-- Income: +incomeStep of that monster's own coin rate per heartsPerStep hearts, capped. Never
-- touches stats, power or battles.
Bond.Income = { heartsPerStep = 2, step = 0.01, max = 0.05 }

Bond.NameplateHearts = 7 -- a nameplate over the monster in the pen from this many hearts
Bond.BestFriends = 3 -- top-bond monsters shown at the ranch gate
Bond.MaxPlates = 12 -- nameplates per ranch (highest bond first)

-- Tricks a monster learns from its hearts. Community.Trick plays them (everyone sees it) and
-- refuses them below `bond`; the Care menu lists them, the emote wheel does not.
Bond.Tricks = {
	{ id = "sit", name = "Sit", state = "sit", fallback = "happy", glyph = "🐾", bond = 3 },
	{ id = "playdead", name = "Play dead", state = "faint", fallback = "sleep", glyph = "💤", bond = 6 },
	{ id = "showoff", name = "Show off", state = "attack", fallback = "trick", glyph = "🌟", bond = 9 },
}

-- Gestures (client). Times in seconds, distances in screen pixels.
Bond.Gesture = {
	holdSeconds = 4, -- Pet: total press-and-hold time (and the pad / keyboard hold version of all three)
	strokes = 8, -- Brush: back-and-forth strokes
	strokePixels = 40, -- a stroke must travel this far before it turns
	strokeGap = 0.1, -- seconds between two counted strokes
	beat = 0.75, -- Play: the monster bounces every beat
	window = 0.3, -- a tap this close to a bounce counts
	taps = 6, -- Play: on-beat taps
}

return Bond
