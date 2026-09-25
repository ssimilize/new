--[[
	Api: THE CONTRACT between client and server, and between systems.

	Everything that crosses the network is declared here first. Server systems implement
	actions with `ctx.Net:Handle(name, handler)`; the kernel refuses to register an action
	that is not declared here, validates every payload against its schema before the
	handler runs, and rate-limits per player. Client code calls `ctx.Net:Request(name, payload)`.

	Naming: "<OwnerSystem>.<Verb>". The owner prefix must equal the system's Name; the
	kernel enforces it, so two teams can never implement the same action.

	Responses: every request returns { ok = true, data = any } or { ok = false, err = string }.
	If the owning system is not plugged in, the response is { ok = false, err = "NotAvailable" }.

	Changing this file is a contract change: announce it to every workstream.
]]

local T = require(script.Parent.T)
local Config = require(script.Parent.Parent.Config)

local Api = {}

-- Reusable validators -------------------------------------------------------------
local id = T.id
local slot = T.integer(1, 8)
local flavor = T.enum(Config.Food.Ids)
local eggType = T.key(Config.Eggs.ById)
local regionId = T.key(Config.Regions.ById)
local stage = T.integer(1, Config.Regions.MaxStages)
local duration = T.enum({ "900", "3600", "14400", "28800" }) -- sent as strings (see note below)
local squad = T.array(id, 4, 1)

-- NOTE on numbers used as keys: expedition durations are sent as strings ("3600") so they
-- can be used as enum values; handlers convert with tonumber().

--[[
	Actions (client → server). Fields:
	  schema  validator for the payload (T.none when there is no payload)
	  rate    max calls per second per player (token bucket, burst = rate × 2, min burst 2)
	  returns human-readable description of `data` on success (documentation only)
]]
Api.Actions = {
	-- Settings (S1) ---------------------------------------------------------------
	["Settings.Set"] = {
		schema = T.struct({ key = T.enum({ "music", "sfx", "lowGraphics", "hideBroadcasts" }), value = T.boolean }),
		rate = 4,
		returns = "nil",
	},

	-- Monsters (S2) ---------------------------------------------------------------
	["Monsters.Rename"] = { schema = T.struct({ id = id, name = T.string(20) }), rate = 1, returns = "{ name: string } (filtered)" },
	["Monsters.SetLocked"] = { schema = T.struct({ id = id, locked = T.boolean }), rate = 5, returns = "nil" },
	["Monsters.Feed"] = {
		schema = T.struct({ id = id, flavor = flavor, amount = T.optional(T.integer(1, 10)) }),
		rate = 8,
		returns = "{ meals: number, mood: number }",
	},
	["Monsters.LevelUp"] = { schema = T.struct({ id = id, times = T.integer(1, 10) }), rate = 8, returns = "{ lv: number }" },
	["Monsters.Grow"] = { schema = T.struct({ id = id }), rate = 4, returns = "{ growEndsAt: number }" },
	["Monsters.StarUp"] = { schema = T.struct({ id = id, fodder = id }), rate = 2, returns = "{ stars: number }" },
	["Monsters.Sell"] = { schema = T.struct({ ids = T.array(id, 50, 1) }), rate = 2, returns = "{ coins: number, sold: number }" },

	-- Hall of Fame (S2) -------------------------------------------------------------
	["HallOfFame.Retire"] = { schema = T.struct({ id = id }), rate = 1, returns = "{ stardust: number, legacy: number }" },
	["HallOfFame.BuyUpgrade"] = {
		schema = T.struct({ upgrade = T.key(Config.HallOfFame.UpgradeById) }),
		rate = 2,
		returns = "{ level: number }",
	},

	-- Eggs & incubators (S3) --------------------------------------------------------
	["Eggs.Place"] = { schema = T.struct({ egg = id, slot = slot }), rate = 6, returns = "{ endsAt: number }" },
	["Eggs.PlaceAuto"] = { schema = T.none, rate = 2, returns = "{ placed: number }  -- fills empty slots with the best eggs" },
	["Eggs.Hatch"] = {
		schema = T.struct({ slot = slot, starter = T.optional(T.enum(Config.Eggs.Starter.lines)) }),
		rate = 6,
		returns = "{ monster: Monster }  -- `starter` picks the starter egg's line",
	},
	["Eggs.HatchAll"] = { schema = T.none, rate = 2, returns = "{ monsters: { Monster } }" },
	["Eggs.HatchRush"] = { schema = T.struct({ slot = slot }), rate = 1, returns = "{ endsAt: number }  -- rewarded ad" },

	-- Shop (S3) ---------------------------------------------------------------------
	["Shop.BuyEgg"] = {
		schema = T.struct({ egg = eggType, amount = T.integer(1, Config.Eggs.MaxBuyPerRequest) }),
		rate = 4,
		returns = "{ eggs: { string } }",
	},
	["Shop.BuyFood"] = { schema = T.struct({ flavor = flavor, amount = T.integer(1, 100) }), rate = 4, returns = "nil" },
	["Shop.BuyDecor"] = { schema = T.struct({ decor = T.key(Config.Decor.ById) }), rate = 2, returns = "nil" },
	["Shop.BuyTheme"] = { schema = T.struct({ theme = T.key(Config.Decor.PenThemeById) }), rate = 2, returns = "nil" },
	["Shop.ClaimFreeEgg"] = { schema = T.none, rate = 1, returns = "{ egg: string }  -- rewarded ad" },

	-- Ranch (S3) --------------------------------------------------------------------
	["Ranch.Collect"] = { schema = T.struct({ pen = T.integer(1, 5) }), rate = 10, returns = "{ coins: number }" },
	["Ranch.CollectAll"] = { schema = T.none, rate = 4, returns = "{ coins: number }" },
	["Ranch.Assign"] = { schema = T.struct({ id = id, pen = T.integer(0, 5) }), rate = 10, returns = "nil  -- pen 0 = barn" },
	["Ranch.BuyPen"] = { schema = T.none, rate = 1, returns = "{ pen: number }" },
	["Ranch.Upgrade"] = {
		schema = T.struct({ target = T.enum({ "capacity", "jar", "incubatorSpeed", "barn", "garden" }), pen = T.optional(T.integer(1, 5)) }),
		rate = 2,
		returns = "{ level: number }",
	},
	["Ranch.PlaceDecor"] = {
		schema = T.struct({ decor = T.key(Config.Decor.ById), pen = T.integer(0, 5) }),
		rate = 3,
		returns = "nil  -- pen 0 = take back to storage",
	},
	["Ranch.SetPenTheme"] = {
		schema = T.struct({ pen = T.integer(1, 5), theme = T.key(Config.Decor.PenThemeById) }),
		rate = 2,
		returns = "nil",
	},
	["Ranch.Plant"] = { schema = T.struct({ plot = T.integer(1, 8), flavor = flavor }), rate = 6, returns = "{ readyAt: number }" },
	["Ranch.Harvest"] = {
		schema = T.struct({ plot = T.optional(T.integer(1, 8)) }),
		rate = 6,
		returns = "{ food: { [flavor]: number } }  -- nil plot = all",
	},

	-- Welcome Back (S3) ------------------------------------------------------------
	["WelcomeBack.Claim"] = { schema = T.struct({ double = T.boolean }), rate = 1, returns = "{ coins: number }" },

	-- Expeditions (S4) ------------------------------------------------------------
	["Expeditions.SetSquad"] = { schema = T.struct({ ids = squad }), rate = 4, returns = "nil" },
	["Expeditions.Fight"] = {
		schema = T.struct({ region = regionId, stage = stage, retry = T.optional(T.boolean) }),
		rate = 1,
		returns = "{ win: boolean, replay: BattleReplay, rewards: { Reward } }",
	},
	["Expeditions.Start"] = {
		schema = T.struct({ slot = T.integer(1, 4), region = regionId, stage = stage, duration = duration, squad = squad }),
		rate = 3,
		returns = "{ endsAt: number }",
	},
	["Expeditions.Claim"] = { schema = T.struct({ slot = T.integer(1, 4) }), rate = 3, returns = "{ rewards: { Reward } }" },
	["Expeditions.ClaimAll"] = { schema = T.none, rate = 2, returns = "{ rewards: { Reward } }" },
	["Expeditions.Recall"] = {
		schema = T.struct({ slot = T.integer(1, 4) }),
		rate = 2,
		returns = "{ rewards: { Reward } }  -- partial loot, no duration bonus",
	},
	["Expeditions.OpenCaravan"] = {
		schema = T.struct({ region = regionId, stage = stage, duration = T.enum({ "14400", "28800" }) }),
		rate = 1,
		returns = "{ caravan: string }",
	},
	["Expeditions.JoinCaravan"] = { schema = T.struct({ caravan = id, slot = T.integer(1, 4), squad = squad }), rate = 2, returns = "nil" },
	["Expeditions.LeaveCaravan"] = { schema = T.struct({ caravan = id }), rate = 2, returns = "nil" },
	["Expeditions.LaunchCaravan"] = { schema = T.struct({ caravan = id }), rate = 1, returns = "{ endsAt: number }" },

	-- Boss (S4) -------------------------------------------------------------------
	["Boss.Join"] = { schema = T.none, rate = 1, returns = "nil" },
	["Boss.Cheer"] = { schema = T.struct({ taps = T.integer(1, Config.Boss.MaxTapsPerRequest) }), rate = 3, returns = "{ cheer: number }" },

	-- Breeding (S5) ---------------------------------------------------------------
	["Breeding.Start"] = { schema = T.struct({ pod = T.integer(1, 2), a = id, b = id }), rate = 2, returns = "{ endsAt: number }" },
	["Breeding.Claim"] = {
		schema = T.struct({ pod = T.integer(1, 2) }),
		rate = 2,
		returns = "{ monster: Monster, hybridDiscovered: boolean }",
	},
	["Breeding.Cancel"] = { schema = T.struct({ pod = T.integer(1, 2) }), rate = 1, returns = "nil  -- fee is not refunded" },

	-- Social (S5) ------------------------------------------------------------------
	["Social.Pet"] = { schema = T.struct({ owner = T.userId, id = id }), rate = 4, returns = "{ friendship: number, left: number }" },
	["Social.Like"] = { schema = T.struct({ owner = T.userId }), rate = 2, returns = "{ likes: number }" },

	-- Trade (S5) ------------------------------------------------------------------
	["Trade.Request"] = { schema = T.struct({ target = T.userId }), rate = 1, returns = "nil" },
	["Trade.Respond"] = { schema = T.struct({ from = T.userId, accept = T.boolean }), rate = 2, returns = "nil" },
	["Trade.SetOffer"] = {
		schema = T.struct({ items = T.array(T.struct({ kind = T.enum({ "monster", "egg" }), id = id }), Config.Social.Trade.maxItems) }),
		rate = 4,
		returns = "nil",
	},
	["Trade.SetReady"] = { schema = T.struct({ ready = T.boolean }), rate = 4, returns = "nil" },
	["Trade.Confirm"] = { schema = T.none, rate = 2, returns = "nil" },
	["Trade.Cancel"] = { schema = T.none, rate = 2, returns = "nil" },

	-- Quests (S6) -----------------------------------------------------------------
	["Quests.ClaimDaily"] = { schema = T.struct({ index = T.integer(1, 5) }), rate = 2, returns = "{ rewards: { Reward } }" },
	["Quests.ClaimAchievement"] = { schema = T.struct({ id = id }), rate = 2, returns = "{ rewards: { Reward } }" },
	["Quests.Ack"] = { schema = T.struct({ step = id }), rate = 2, returns = "nil  -- acknowledges an `ack` tutorial step" },
	["Quests.ClaimPass"] = {
		schema = T.struct({ tier = T.integer(1, 100), track = T.enum({ "free", "premium" }) }),
		rate = 3,
		returns = "{ rewards: { Reward } }",
	},
	["Quests.Redeem"] = { schema = T.struct({ code = T.string(30, 1) }), rate = 1, returns = "{ rewards: { Reward } }" },

	-- Monetization (S6) ------------------------------------------------------------
	["Monetization.RefreshPasses"] = {
		schema = T.none,
		rate = 0.2,
		returns = "{ passes: { [key]: boolean } }  -- after a client purchase prompt closes",
	},
}

--[[
	Events (server → client). `payload` documents the table shape.
	Clients listen with ctx.Net:On(name, fn). Anything the client must never miss
	(e.g. the Welcome Back summary) is in replicated state instead of an event.
]]
Api.Events = {
	["Kernel.Notify"] = "{ text: string, kind: 'info'|'success'|'error'|'reward' }",
	["Rewards.Granted"] = "{ source: string, items: { Reward } }",
	["Progression.LevelUp"] = "{ level: number, unlocks: { string } }",
	["Eggs.Hatched"] = "{ slot: number, monster: Monster, egg: string }",
	["Monsters.Evolved"] = "{ id: string, fromForm: string, toForm: string, stage: number }",
	["Weather.Mutated"] = "{ id: string, mutation: string, result: 'added'|'combined' }",
	["Boss.Result"] = "{ rank: number, share: number, damage: number, rewards: { Reward }, egg: boolean }",
	["Social.Broadcast"] = "{ kind: string, text: string, userId: number, appearance: Appearance? }",
	["Trade.Incoming"] = "{ from: number, name: string }",
	["Trade.Completed"] = "{ received: { { kind: string, appearance: Appearance? } } }",
	["Quests.StepDone"] = "{ step: string, rewards: { Reward } }",
	["HallOfFame.Retired"] = "{ appearance: Appearance, stardust: number }",
}

--[[
	Replicated state (read-only on the client). Root paths:
	  profile.<SystemName>.*   the player's own save section of each system
	  session.<SystemName>.*   per-player data that is not saved
	  global.<SystemName>.*    server-wide data, the same for every player

	Declared roots per system (the kernel only lets a system write under its own name):
]]
Api.State = {
	profile = {
		Currency = "{ coins, gems, stardust, friendship, treats, tokens = { [eventId]: n }, food = { sweet, spicy, savory, sour } }",
		Progression = "{ level, xp }",
		Settings = "{ music, sfx, lowGraphics, hideBroadcasts }",
		Monsters = "{ list = { [id]: Monster }, codex = { [lineId]: { forms = { [formId]: true }, variants = { [n]: true }, count } }, nextId }",
		HallOfFame = "{ entries = { Statue }, legacy = { [element]: pct }, upgrades = { [upgradeId]: level }, starShards }",
		Eggs = "{ list = { [id]: { type, source, t } }, slots = { { egg: id|false, type: string|false, startedAt, endsAt } }, nextId, pity = { starlit, royal } }",
		Shop = "{ window, bought = { [eggType]: n }, decor = { [decorId]: n owned }, themes = { [themeId]: true } }",
		Ranch = "{ pens = { Pen }, incubatorTier, barnTier, garden = { tier, plots = { { flavor|false, readyAt } } } }",
		Expeditions = "{ cleared = { [regionId]: highestStage }, slots = { Slot }, squad = { id } }",
		Breeding = "{ pods = { Pod }, daily = { day, counts = { [monsterId]: n } }, discovered = { [lineId]: true } }",
		Social = "{ day, petsGiven, likesGiven = { ['u'..userId]: true }, likes }",
		Quests = "{ tutorial = { step, progress }, daily = { day, list = { { id, progress, claimed } } }, achievements = { [id]: { progress, claimed } }, codes = { [code]: true } }",
		Monetization = "{ ads = { day, counts = { [placement]: n } }, once = { [productKey]: true } }",
		Leaderboards = "{ week, stampede }  -- this week's Stampede damage",
		Events = "{ event, day, earned, login }  -- event tokens earned today (daily cap)",
	},
	session = {
		Eggs = "{ slotCount, speed }",
		Ranch = "{ income, rates = { [pen]: coinsPerSec }, caps = { [pen]: seconds }, capacity, used }",
		Breeding = "{ podCount, breedsPerDay }",
		Monetization = "{ passes = { [passKey]: boolean }, paidRandomAllowed: boolean }",
		Social = "{ friendBoost: number, friendsHere: number }",
		WelcomeBack = "{ pending: boolean, awaySeconds, coins, items = { { kind, text, icon? } } }",
		Trade = "{ status: 'none'|'outgoing'|'incoming'|'open'|'countdown', partner = { userId, name }, mine = TradeSide, theirs = TradeSide, endsAt }",
		Expeditions = "{ caravan = { id, host, region, stage, duration, members = { { userId, name } } }? }",
		Boss = "{ joined: boolean, damage, cheer }",
	},
	global = {
		Shop = "{ window, endsAt, stock = { [eggType]: n } }",
		Weather = "{ id, endsAt, nextRollAt, night: boolean, phaseEndsAt, summonedBy: string? }",
		Boss = "{ state: 'idle'|'lobby'|'active', bossId, startsAt, endsAt, hp, maxHp, board = { { userId, name, damage } } }",
		Plots = "{ ['1'..'6' as numbers]: PublicPlot }  -- array of 6",
		Expeditions = "{ caravans = { [caravanId]: CaravanLobby } }",
		Events = "{ id: string|false, name, endsAt, token = { name, glyph, color } | false }  -- the running seasonal event",
		Leaderboards = "{ week, endsAt, server = { [boardId]: { Row } }, global = { [boardId]: { Row } }, champions = { [boardId]: { userId, name } | false }, globalAt }  -- Row = { userId, name, value, label? }",
	},
}

--[[
	Bus topics (server-side, system ↔ system). Publish with ctx.Bus:Publish(topic, player, detail).
	`detail` is always a table so new fields can be added without breaking subscribers.
	Quests and Analytics subscribe to most of these.
]]
Api.Topics = {
	PlayerReady = "(player, { firstJoin: boolean, awaySeconds: number })",
	PlayerLeaving = "(player, {})",
	CurrencyChanged = "(player, { currency: string, delta: number, reason: string, balance: number })",
	RanchXP = "(player, { amount: number, reason: string })",
	LevelUp = "(player, { level: number })",
	MonsterCreated = "(player, { id: string, source: 'hatch'|'breed'|'trade'|'reward'|'starter' })",
	MonsterRemoved = "(player, { id: string, reason: 'sell'|'retire'|'fuse'|'trade' })",
	MonsterChanged = "(player, { id: string, fields: { string }? })",
	MonsterFed = "(player, { id: string, flavor: string })",
	MonsterLeveled = "(player, { id: string, lv: number })",
	MonsterEvolved = "(player, { id: string, stage: number, form: string })",
	EggAdded = "(player, { id: string, type: string, source: string })",
	EggBought = "(player, { type: string, amount: number })",
	EggHatched = "(player, { id: string, egg: string, rarity: number, variant: number })",
	JarCollected = "(player, { coins: number })",
	PenChanged = "(player, { pen: number })",
	StageCleared = "(player, { region: string, stage: number, first: boolean })",
	ExpeditionStarted = "(player, { slot: number, duration: number })",
	ExpeditionClaimed = "(player, { slot: number, duration: number })",
	BossJoined = "(player, {})",
	BossEnded = "(nil, { bossId: string, won: boolean })",
	BossDamage = "(player, { damage: number, rank: number })  -- per participant when a Stampede ends",
	Bred = "(player, { id: string, hybrid: boolean, discovery: boolean })",
	Mutated = "(player, { id: string, mutation: string })",
	WeatherChanged = "(nil, { id: string })",
	Retired = "(player, { rarity: number, element: string })",
	PetGiven = "(player, { owner: number })",
	PetReceived = "(player, { from: number, id: string })",
	TradeCompleted = "(player, { partner: number })",
	PassesChanged = "(player, { passes: { [key]: boolean } })",
	AdWatched = "(player, { placement: string })",
	Purchase = "(player, { product: string, robux: number })",
	RateModifiersChanged = "(player, {})",
	WelcomeItem = "(player, { kind: string, text: string, icon: string? })",
	PlotChanged = "(player, {})",
}

-- Shared shapes (documentation) -----------------------------------------------------
Api.Shapes = {
	Reward = "{ kind: 'coins'|'gems'|'food'|'treats'|'stardust'|'friendship'|'token'|'egg'|'xp'|'decor'|'monster', id: string?, amount: number, rarity: number? }",
	Monster = "see ARCHITECTURE.md → Monster record",
	Appearance = "see Logic/Appearance.luau",
	BattleReplay = "see Logic/BattleSim.luau",
}

return Api
