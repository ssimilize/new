--[[
	Stray Monsters (update 3.13 · Wild things): tuning. Rules in Logic/Strays, the server in
	Systems/Strays, the wandering stray in Controllers/Strays, the befriend minigame in
	UI/Screens/Strays.

	  Unlock       feature key (Config.Unlocks.Features.strays, Ranch Level 10)
	  Interval     seconds between stray arrivals (slots on the server clock, offset per player)
	  Stay         seconds a stray stays before it wanders off
	  Rounds       rounds of the befriend minigame; Need of them right befriends the stray
	  DailyCap     strays adopted per UTC day
	  TreatCost    food of the chosen flavour one "Offer treat" costs
	  Odds / NightOdds   rarity odds (percent by Config.Rarities index), by day and at night
	               (Logic/WeatherRoll.Phase at the stray's arrival)
	  WaitChance   chance each round's hidden mood wants waiting (else its favourite treat)
	  Favourite    element -> the food flavour its strays love (a line's FIRST element counts)
	  World        plot-local studs (the plot faces +x, the gate at x ~ 70): where a stray
	               wanders on the middle aisle, clear of the tourists' walk (z -2) and the
	               Guestbook stand (68, 16)
]]

local Strays = {}

Strays.Unlock = "strays"
Strays.Interval = 45 * 60
Strays.Stay = 20 * 60
Strays.Rounds = 3
Strays.Need = 2
Strays.DailyCap = 3
Strays.TreatCost = 1

Strays.Odds = { 62, 28, 9, 1, 0, 0 }
Strays.NightOdds = { 40, 34, 19, 6, 1, 0 }

Strays.WaitChance = 0.4

Strays.Favourite = {
	ember = "spicy",
	tide = "sour",
	sprout = "sweet",
	spark = "sour",
	gloom = "savory",
	stone = "savory",
	light = "sweet",
	void = "spicy",
}

-- The honest hint each mood shows the player (the treat hint names the favourite flavour).
Strays.WaitHint = "It looks nervous... maybe just wait quietly"
Strays.TreatHints = {
	sweet = "It sniffs the air... something sweet?",
	spicy = "It sniffs the air... something spicy?",
	savory = "It sniffs the air... something hearty?",
	sour = "It sniffs the air... something zingy?",
}

Strays.World = {
	from = { 50, -5 }, -- the wander path's ends (plot-local x, z)
	to = { 62, -5 },
	speed = 3, -- studs a second
	pause = 3, -- seconds it stops at each end
	promptDistance = 12,
}

return Strays
