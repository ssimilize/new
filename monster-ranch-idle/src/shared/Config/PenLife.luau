--[[
	Config/PenLife (glow-up S, living pens): how pen monsters behave, as data. Required directly
	(like Config/Vfx and Config/Photo), read by Logic/PenLife (the pure decisions) and
	Visuals/PenBrain (the client brain that World drives).

	Traits: `Traits[traitKey]` is that trait's tendency, merged over `Base` by Logic/PenLife.Tendency.
	Multipliers (1 = neutral) scale the weight of an action in the day roll:
	  wander eat sit nap cheer trick spar chase social idle
	Other keys:
	  eatLong      eat takes this many times longer (Gluttons linger at the trough)
	  seekFood     walks to the pen's food spot to eat (else eats where it stands)
	  edge         0..1 chance a wander target hugs the fence (shy ones keep to the edge)
	  pace         walking speed multiplier
	  nightOwl     stays up after dark while the others sleep
	  earlyBird    wakes `EarlyBirdLead` seconds before dawn
	  showOff      poses (trick / cheer) when a player walks past the fence
	  greeter      runs to the fence for any visitor, not only the owner
	  weatherproof never shakes off rain, shivers or shelters
	  weatherLover dances (cheer) in any weather instead of hiding from it
	  stargazer    at night it sits up looking at the sky instead of sleeping (half the time)
	Every trait in Config/Traits has an entry (Logic/PenLife.spec checks it); `{}` is neutral.

	Hidden traits only show once they are revealed (stage 3, like the Monster screen).
]]

local PenLife = {}

-- The neutral monster: day-roll weights before trait multipliers.
PenLife.Base = {
	wander = 46,
	eat = 12,
	sit = 7,
	nap = 3,
	cheer = 9,
	trick = 3,
	spar = 0.5, -- every monster shadow-boxes once in a while; brawlers a lot
	chase = 4,
	social = 4,
	idle = 12,
	eatLong = 1,
	edge = 0.12,
	pace = 1,
}

PenLife.Traits = {
	speedy_grower = { wander = 1.4, idle = 0.6, pace = 1.15 }, -- restless
	glutton = { eat = 3.2, eatLong = 1.8, seekFood = true },
	tough_hide = { weatherproof = true, wander = 1.1 },
	brawny = { spar = 12, trick = 1.3 }, -- shadow-boxes (the attack clip)
	hearty = { nap = 3, sit = 2.2, wander = 0.7 }, -- the lazy one
	swift = { pace = 1.3, chase = 1.8, wander = 1.2 },
	cheerful = { cheer = 2, chase = 3, social = 1.5 }, -- starts games of chase
	lucky_paw = { edge = 0.85, eat = 1.3, cheer = 0.6, chase = 0.3 }, -- shy: sniffs along the fence
	hoarder = { eat = 1.6, sit = 1.6, seekFood = true }, -- sits by the food
	night_owl = { nightOwl = true, nap = 1.8 }, -- up all night, naps by day
	charmer = { greeter = true, cheer = 1.4, social = 1.3 },
	busy_bee = { earlyBird = true, wander = 1.3, sit = 0.4, nap = 0.3 },
	fertile = { social = 3 }, -- sits beside its pen-mates
	weather_magnet = { weatherLover = true, cheer = 1.3 },
	show_off = { showOff = true, trick = 2.5, cheer = 1.3 },
	boss_brawler = { spar = 16 },
	firstborn = { cheer = 1.2, social = 1.3 },
	golden_heart = { greeter = true, social = 1.4 },
	stargazer = { stargazer = true },
	ancient_blood = { sit = 1.6, wander = 0.75, chase = 0.5 }, -- calm and stately
}

-- How long each action holds before the next decision (seconds, { min, max }).
PenLife.Hold = {
	eat = { 2.5, 4.5 },
	sit = { 5, 9 },
	nap = { 7, 12 },
	cheer = { 2, 3 },
	trick = { 2, 3 },
	spar = { 1.6, 2.4 },
	idle = { 2, 4 },
	social = { 5, 8 },
	afterWalk = { 1.2, 3.5 },
	sleep = { 10, 18 },
	shake = { 1.2, 1.8 },
	shiver = { 2.5, 4 },
	bask = { 7, 12 },
	shelter = { 6, 10 },
	greet = { 2.5, 3.5 },
	gather = { 3, 4 },
	chase = { 4.5, 7 },
	pose = { 2, 2.5 },
}

-- Weather reactions by Config.Weather id. wet: shake off rain now and then; cold: shiver;
-- sunny: bask (daytime only); shelter: head for the hut / trees (PenSpot "shelter") or a corner.
PenLife.Weather = {
	rain = { wet = true },
	thunderstorm = { wet = true, shelter = true },
	snow = { cold = true },
	heatwave = { sunny = true, bask = 3 },
	beachday = { sunny = true, bask = 2.5 },
	clear = { sunny = true, bask = 1 },
	pollenstorm = {},
	bloodmoon = {},
	starfall = { stars = true },
	aurora = { stars = true },
	lanternnight = {},
}
PenLife.BaskWeight = 6 -- day-roll weight of "bask" at bask = 1 (scaled by the weather's bask)
PenLife.ShelterWeight = 150 -- day-roll weight of "shelter" in a storm (the rest still plays a little)
PenLife.ShiverWeight = 30 -- "shiver" joins the roll in the cold; idle then becomes a shiver too
PenLife.WetShakeChance = 0.18 -- after each action in the rain
PenLife.WeatherDanceWeight = 20 -- weatherLover's extra cheer weight during any weather but clear

-- Night: every monster heads for the pile (the "bed" spot, else a corner) and sleeps there.
PenLife.NightStagger = { 0.5, 6 } -- seconds: they do not all go to bed at once
PenLife.DawnStagger = { 0.5, 5 }
PenLife.EarlyBirdLead = 45 -- seconds before dawn an early bird wakes
PenLife.PileSpacing = 1.5 -- studs per ring step (scaled by the monster's margin)
PenLife.StargazeChance = 0.5

-- Moments.
PenLife.Greet = {
	arriveRadius = 70, -- the owner's character within this of the plot centre = "at the ranch"
	leaveRadius = 110, -- must have gone past this to arrive again
	awaySeconds = 20, -- and been away this long
	spacing = 2.6, -- studs between greeters along the fence
	cooldown = 30,
}
PenLife.Gather = { delay = 1.2, radius = 3.2, seconds = 6 } -- after a hatch or an evolve
PenLife.ShowOff = { range = 9, cooldown = 14, minSpeed = 3 } -- a player moving within `range` of the fence
PenLife.Chase = { minDistance = 4, fleeDistance = 9, chaserPace = 1.35, runnerPace = 1.2, catch = 1.6 }

-- Motion.
PenLife.Motion = {
	separation = 1.1, -- keep this many margins apart
	separationPile = 0.7,
	obstaclePad = 1, -- studs added round a decor part
	arrive = 0.6, -- studs from the goal counts as there
	legSeconds = 2, -- a steering leg is this many think intervals long
	stuckSeconds = 9, -- a walk that has not arrived by then gives up
	turnRate = 7, -- radians per second (MonsterAnimator turns toward its heading at this rate)
	faceRate = 4, -- turning in place to look at something
}

-- Think rates (the brain runs on World's 0.2 s loop). A plot's rate is the product of its
-- distance band, whether it is on screen and PenBrain.SetThinkRate (the perf packet's knob).
PenLife.Think = {
	interval = 0.2,
	near = 90, -- full rate within this of the camera
	mid = 180, -- half rate within this
	far = 250, -- a quarter within this; beyond it the animator is paused too, so no thinking
	offScreen = 0.35, -- multiplier for a plot behind the camera
	spotRescan = 6, -- seconds between PenSpot scans of a pen
	playerScan = 0.4, -- seconds between reads of the players' positions (show-offs, greets)
}

-- Mood bubbles: pooled BillboardGuis popped over a monster for a moment.
PenLife.Bubbles = {
	icons = { sleep = "💤", love = "❤", food = "🍖", music = "♪", wet = "💧" },
	essential = { love = true }, -- still shown with lowGraphics
	seconds = 1.8,
	range = 70, -- only within this of the camera
	max = 6,
	maxLow = 2,
	cooldown = 5, -- per monster
}

return PenLife
