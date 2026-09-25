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

	-- Rebirth (1.4) ---------------------------------------------------------------------
	["Rebirth.Rebirth"] = {
		schema = T.struct({ keep = T.array(id, Config.Rebirth.MaxHeirlooms, 1) }),
		rate = 0.5,
		returns = "{ stars: number, stardust: number, kept: number, theme: string }",
	},
	["Rebirth.BuySkill"] = {
		schema = T.struct({ skill = T.key(Config.Rebirth.SkillById) }),
		rate = 4,
		returns = "{ level: number }",
	},

	-- Accessories (1.5, Showtime) -------------------------------------------------------
	["Accessories.Buy"] = {
		schema = T.struct({ accessory = T.key(Config.Accessories.ById) }),
		rate = 3,
		returns = "{ owned: number }",
	},
	["Accessories.Equip"] = {
		schema = T.struct({ id = id, accessory = T.key(Config.Accessories.ById) }),
		rate = 6,
		returns = "{ slot: string, previous: string|false }",
	},
	["Accessories.Unequip"] = {
		schema = T.struct({ id = id, slot = T.enum(Config.Accessories.Slots) }),
		rate = 6,
		returns = "{ accessory: string }",
	},

	-- Monster Contests (1.5, Showtime) -------------------------------------------------
	["Contests.Enter"] = { schema = T.struct({ id = id }), rate = 2, returns = "{ entries: number }  -- again = switch monster" },
	["Contests.Withdraw"] = { schema = T.none, rate = 2, returns = "nil" },
	["Contests.Vote"] = {
		schema = T.struct({ entry = T.integer(1, Config.Contests.MaxEntries), stars = T.integer(1, 5) }),
		rate = 4,
		returns = "{ stars: number }  -- again = change your vote",
	},

	-- Arena (2.1) -------------------------------------------------------------------------
	["Arena.SetDefense"] = {
		schema = T.struct({ ids = T.array(id, Config.Arena.TeamSize, Config.Arena.TeamSize) }),
		rate = 1,
		returns = "{ rating: number }",
	},
	["Arena.Refresh"] = { schema = T.none, rate = 0.5, returns = "{ candidates: number }" },
	["Arena.Attack"] = {
		schema = T.struct({
			candidate = T.integer(1, Config.Arena.Candidates),
			ids = T.array(id, Config.Arena.TeamSize, Config.Arena.TeamSize),
		}),
		rate = 1,
		returns = "{ replay: BattleReplay, win, delta, rating, tier, rewards }",
	},
	["Arena.ClaimWeekly"] = { schema = T.none, rate = 1, returns = "{ tier: string, rewards: { Reward } }" },

	-- Raids (2.1) -------------------------------------------------------------------------
	["Raids.Open"] = {
		schema = T.struct({ raid = T.key(Config.Raids.ById), ids = T.array(id, Config.Raids.PerPlayer, 1) }),
		rate = 1,
		returns = "{ lobby: string }",
	},
	["Raids.Join"] = {
		schema = T.struct({ lobby = T.string(12, 2), ids = T.array(id, Config.Raids.PerPlayer, 1) }),
		rate = 1,
		returns = "{ members: number }",
	},
	["Raids.Leave"] = { schema = T.none, rate = 1, returns = "nil" },
	["Raids.Launch"] = { schema = T.none, rate = 0.5, returns = "{ win: boolean }  -- every member also gets Raids.Result" },

	-- Surf Shack (2.0, Summer Splash) ----------------------------------------------------
	["Surf.Start"] = { schema = T.none, rate = 0.5, returns = "{ run: number, seed: number, duration: number }" },
	["Surf.Finish"] = {
		schema = T.struct({
			run = T.integer(1),
			inputs = T.array(
				T.struct({ t = T.number(0, Config.Surf.Duration), lane = T.integer(1, Config.Surf.Lanes) }),
				Config.Surf.MaxInputs
			),
		}),
		rate = 1,
		returns = "{ score, shells, hits, survived, tokens, best }",
	},

	-- Racing (3.0) ------------------------------------------------------------------------
	["Racing.Start"] = {
		schema = T.struct({ id = id }),
		rate = 0.5,
		returns = "{ race: number, day: number, speed: number, ghosts: { { name, time } }, maxSeconds: number }",
	},
	["Racing.Finish"] = {
		schema = T.struct({
			race = T.integer(1),
			inputs = T.array(
				T.struct({ t = T.number(0, Config.Racing.MaxSeconds), a = T.enum({ "jump", "boost" }) }),
				Config.Racing.MaxInputs
			),
		}),
		rate = 1,
		returns = "{ time, finished, place, stumbles, rewards: { Reward }, cup, best, bestToday }",
	},

	-- Trading Hub (3.0) -------------------------------------------------------------------
	["TradingHub.Travel"] = { schema = T.none, rate = 0.5, returns = "{ teleporting: true }" },
	["TradingHub.Return"] = { schema = T.none, rate = 0.5, returns = "{ teleporting: true }" },
	["TradingHub.Post"] = {
		schema = T.struct({
			items = T.array(T.struct({ kind = T.enum({ "monster", "egg" }), id = id }), Config.TradingHub.MaxOffer, 1),
			wants = T.array(T.key(Config.TradingHub.WantsById), Config.TradingHub.MaxWants),
			note = T.integer(1, #Config.TradingHub.Notes),
		}),
		rate = 0.5,
		returns = "{ ad: string }",
	},
	["TradingHub.Remove"] = { schema = T.none, rate = 1, returns = "{}" },
	["TradingHub.Refresh"] = { schema = T.none, rate = 0.5, returns = "{ ads: number }" },
	["TradingHub.Meet"] = {
		schema = T.struct({ ad = T.string(80, 1) }),
		rate = 1,
		returns = "{ here: true, userId: number } | { teleporting: true }",
	},

	-- Workshop (3.0) ---------------------------------------------------------------------
	["Workshop.Create"] = {
		schema = T.struct({
			name = T.string(Config.Workshop.NameMax * 4),
			shape = T.key(Config.Accessories.ShapeSlots),
			color = T.enum(Config.Workshop.Palette),
			color2 = T.enum(Config.Workshop.Palette),
		}),
		rate = 0.5,
		returns = "{ design: string }",
	},
	["Workshop.Browse"] = { schema = T.struct({ tab = T.enum({ "top", "new", "mine" }) }), rate = 1, returns = "{ count: number }" },
	["Workshop.Like"] = { schema = T.struct({ design = T.string(40, 3) }), rate = 2, returns = "{ likes: number }" },
	["Workshop.Report"] = { schema = T.struct({ design = T.string(40, 3) }), rate = 1, returns = "{ hidden: boolean }" },
	["Workshop.Buy"] = { schema = T.struct({ design = T.string(40, 3) }), rate = 1, returns = "{ owned: number }" },
	["Workshop.Equip"] = { schema = T.struct({ id = id, design = T.string(40, 3) }), rate = 2, returns = "{ slot: string }" },
	["Workshop.Claim"] = { schema = T.none, rate = 0.5, returns = "{ ribbons: number }" },
	["Workshop.ModQueue"] = { schema = T.none, rate = 0.5, returns = "{ count: number }" },
	["Workshop.Moderate"] = {
		schema = T.struct({ design = T.string(40, 3), verdict = T.enum({ "restore", "remove" }) }),
		rate = 2,
		returns = "{ verdict: string }",
	},

	-- Riding (2.0) ------------------------------------------------------------------------
	["Riding.Mount"] = { schema = T.struct({ id = id }), rate = 2, returns = "{ speed: number }" },
	["Riding.Dismount"] = { schema = T.none, rate = 2, returns = "nil" },

	-- Sky Islands (2.0) -----------------------------------------------------------------
	["SkyIslands.Collect"] = {
		schema = T.struct({ crystal = T.integer(1, #Config.SkyIslands.Crystals) }),
		rate = 2,
		returns = "{ rewards: { Reward }, nextAt: number }",
	},

	-- Egg hunt (1.4, Spring Bloom) -----------------------------------------------------
	["EggHunt.Find"] = {
		schema = T.struct({ spot = T.integer(1, #Config.EggHunt.Spots) }),
		rate = 2,
		returns = "{ tokens: number, found: number, left: number, complete: boolean }",
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

	-- Clubs (S5, update 1.2) ------------------------------------------------------------
	["Clubs.Create"] = {
		schema = T.struct({
			name = T.string(40, 1),
			tag = T.string(8, 1),
			color = T.integer(1, #Config.Clubs.Colors),
			emblem = T.key(Config.Clubs.EmblemById),
			open = T.boolean,
		}),
		rate = 0.2,
		returns = "{ id: string }  -- the new club's code; costs Config.Clubs.CreateCost",
	},
	["Clubs.Join"] = { schema = T.struct({ code = T.string(12, 1) }), rate = 0.5, returns = "{ id, name }" },
	["Clubs.JoinPlayer"] = {
		schema = T.struct({ userId = T.userId }),
		rate = 0.5,
		returns = "{ id, name }  -- an open club of a player here",
	},
	["Clubs.Leave"] = { schema = T.none, rate = 0.5, returns = "nil" },
	["Clubs.Kick"] = { schema = T.struct({ userId = T.userId }), rate = 1, returns = "nil" },
	["Clubs.SetRole"] = {
		schema = T.struct({ userId = T.userId, role = T.enum({ "owner", "officer", "member" }) }),
		rate = 1,
		returns = "nil  -- owner only; 'owner' hands the club over",
	},
	["Clubs.Settings"] = {
		schema = T.struct({
			open = T.optional(T.boolean),
			color = T.optional(T.integer(1, #Config.Clubs.Colors)),
			emblem = T.optional(T.key(Config.Clubs.EmblemById)),
		}),
		rate = 1,
		returns = "nil",
	},
	["Clubs.ClaimGoal"] = { schema = T.struct({ goal = T.key(Config.Clubs.GoalById) }), rate = 2, returns = "{ rewards: { Reward } }" },
	["Clubs.AttackBoss"] = { schema = T.none, rate = 1, returns = "{ damage: number, hp: number }" },
	["Clubs.ClaimBoss"] = { schema = T.none, rate = 1, returns = "{ rewards: { Reward } }" },
	["Clubs.ClaimWar"] = { schema = T.none, rate = 1, returns = "{ league: string, rewards: { Reward } }" },
	["Clubs.SetBanner"] = {
		schema = T.struct({ design = T.string(40) }),
		rate = 1,
		returns = "{ banner: { design, name, shape, color, color2 } | false }",
	},
	["Clubs.Refresh"] = { schema = T.none, rate = 0.2, returns = "nil  -- re-reads (and writes) your club now" },

	-- Market (S5, update 1.3) · see Config/Market and ARCHITECTURE §8 -------------------
	["Market.List"] = {
		schema = T.struct({
			kind = T.enum({ "monster", "egg" }),
			id = id,
			price = T.integer(Config.Market.MinPrice, Config.Market.MaxPrice),
			club = T.optional(T.boolean),
		}),
		rate = 1,
		returns = "{ listing: Listing }  -- the item leaves your profile (escrow)",
	},
	["Market.Cancel"] = {
		schema = T.struct({ listing = T.string(40, 1) }),
		rate = 2,
		returns = "{ returned: boolean }  -- false: it went to your mailbox",
	},
	["Market.Buy"] = {
		schema = T.struct({ listing = T.string(40, 1), price = T.integer(Config.Market.MinPrice, Config.Market.MaxPrice) }),
		rate = 2,
		returns = "{ kind: string, id: string }  -- the new monster or egg id; `price` must match the listing",
	},
	["Market.Browse"] = {
		schema = T.struct({
			kind = T.optional(T.enum({ "monster", "egg" })),
			key = T.optional(T.string(40, 3)),
			sort = T.optional(T.enum({ "price", "-price", "new" })),
			club = T.optional(T.boolean),
			page = T.optional(T.integer(1, 50)),
		}),
		rate = 3,
		returns = "{ listings: { Listing }, page: number, more: boolean }",
	},
	["Market.Mine"] = { schema = T.none, rate = 2, returns = "{ listings: { Listing } }" },
	["Market.Collect"] = { schema = T.none, rate = 1, returns = "{ coins: number, items: { { kind, id } }, left: number }" },
	["PriceHistory.Get"] = {
		schema = T.struct({ key = T.string(40, 3) }),
		rate = 3,
		returns = "{ key, days = { { day, count, low, high, avg } }, last: number?, suggest: number? }  -- oldest day first; club sales excluded",
	},

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
	["Raids.Result"] = "{ raid: string, replay: BattleReplay, win: boolean, rewards: { Reward } }",
	["Market.MailCollected"] = "{ coins: number, items: { { kind, id } }, sold: { { key, price, proceeds, name? } }, returned: number }",
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
		Currency = "{ coins, gems, stardust, friendship, treats, ribbons, tokens = { [eventId]: n }, food = { sweet, spicy, savory, sour } }",
		Progression = "{ level, xp }",
		Settings = "{ music, sfx, lowGraphics, hideBroadcasts }",
		Monsters = "{ list = { [id]: Monster }, codex = { [lineId]: { forms = { [formId]: true }, variants = { [n]: true }, count } }, nextId }",
		HallOfFame = "{ entries = { Statue }, legacy = { [element]: pct }, upgrades = { [upgradeId]: level }, starShards }",
		Rebirth = "{ stars, skills = { [skillId]: level }, lastAt, dust }",
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
		EggHunt = "{ round, found = { spotIndex }, day, finds, total }",
		Accessories = "{ owned = { [accessoryId]: n } }  -- in storage; worn ones are Monster.acc",
		Contests = "{ shows, wins, podiums, best, votes }",
		SkyIslands = "{ taken = { [crystalIndex as string]: unix }, day, count, total }",
		Surf = "{ best, runs }",
		Racing = "{ day, rewarded, week, cup, races, wins, best, bestDay, bestToday }",
		Workshop = "{ designs = { designId }, made = { week, n }, copies = { [designId]: { n, name, shape, slot, color, color2, creatorName } }, liked = { [designId]: true }, next }",
		Arena = "{ defense = { id }, attempts = { day, n }, week, bestTier, lastTier, claimed }",
		Raids = "{ day, rewarded, wins, runs }",
		Market = "{ listings = { listingId }, stats = { sold, bought, earned, spent } }",
		Clubs = "{ id: string|false, claimed = { week, goals = { [goalId]: true }, boss }, attacks = { day, n }, war = { day, n, claimed } }",
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
		Clubs = "{ club: ClubView | false }  -- see Systems/Clubs header",
		Market = "{ mail = { coins, items } }  -- mail waiting that could not be collected yet (e.g. ranch full)",
		Contests = "{ entered: monsterId|false, votes = { [entryIndex]: stars } }  -- this show",
		Riding = "{ mount: monsterId|false, speed: number }",
		Raids = "{ lobby: string|false }",
		TradingHub = "{ ad: adId|false, postedAt }",
		Workshop = "{ tab: 'top'|'new'|'mine', gallery = { { id, name, creatorName, shape, slot, color, color2, likes, copies, mine, liked } }, moderator: boolean, queue = { view + reports, creatorId } }",
		Arena = "{ rating, tier, attemptsLeft, candidates = { { name, rating, bot, done, team = { { line, form, look } } } } }",
	},
	global = {
		Shop = "{ window, endsAt, stock = { [eggType]: n } }",
		Weather = "{ id, endsAt, nextRollAt, night: boolean, phaseEndsAt, summonedBy: string? }",
		Boss = "{ state: 'idle'|'lobby'|'active', bossId, startsAt, endsAt, hp, maxHp, board = { { userId, name, damage } } }",
		Plots = "{ ['1'..'6' as numbers]: PublicPlot }  -- array of 6",
		Expeditions = "{ caravans = { [caravanId]: CaravanLobby } }",
		Events = "{ id: string|false, name, endsAt, token = { name, glyph, color } | false }  -- the running seasonal event",
		EggHunt = "{ active: boolean, round, endsAt, spots = { spotIndex } }  -- eggs hidden this round (Config.EggHunt.Spots)",
		Raids = "{ lobbies = { [lobbyId]: { id, raid, host, hostName, expiresAt, members = { { userId, name, power } } } } }",
		TradingHub = "{ mode: 'main'|'hub', ads = { { id, userId, name, jobId, here, offer = { { kind, appearance?, egg? } }, wants = { wantId }, note, postedAt, expiresAt } }, refreshedAt }",
		Riding = "{ riders = { ['u'..userId]: { appearance, speed } } }",
		Contests = "{ state: 'idle'|'entry'|'runway'|'results', show, theme, endsAt, nextAt, entries = { { userId, name, appearance } }, current, results = { { userId, name, appearance, score, votes, rank } } }",
		Clubs = "{ here = { ['u'..userId]: { clubId, tag, color, emblem, name, open, banner } }, ladder = { week, at, rows = { { rank, clubId, name, tag, color, emblem, points } } } }",
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
	MonsterRemoved = "(player, { id: string, reason: 'sell'|'retire'|'fuse'|'trade'|'market'|'rebirth', acc: { [slot]: accessoryId }? })",
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
	Rebirthed = "(player, { stars: number, dust: number, kept: number })",
	EggFound = "(player, { spot: number, round: number, complete: boolean })",
	AccessoryGained = "(player, { id: string, amount: number, source: 'shop'|'reward' })",
	CrystalCollected = "(player, { crystal: number })",
	Mounted = "(player, { id: string, speed: number })",
	SurfRun = "(player, { score: number, shells: number })",
	RaceFinished = "(player, { place: number, time: number, day: number, cup: number })",
	HubTravel = "(player, { to: 'hub'|'main'|'server' })",
	HubAdPosted = "(player, {})",
	DesignPublished = "(player, { design: string })",
	DesignBought = "(player, { design: string, creator: number })",
	ArenaBattle = "(player, { won: boolean, rating: number })",
	RaidFinished = "(player, { raid: string, win: boolean })",
	ContestEntered = "(player, { show: number, theme: string })",
	ContestVoted = "(player, {})",
	ContestPlaced = "(player, { rank: number, entries: number, theme: string, score: number })",
	PetGiven = "(player, { owner: number })",
	PetReceived = "(player, { from: number, id: string })",
	TradeCompleted = "(player, { partner: number })",
	PassesChanged = "(player, { passes: { [key]: boolean } })",
	AdWatched = "(player, { placement: string })",
	Purchase = "(player, { product: string, robux: number })",
	RateModifiersChanged = "(player, {})",
	WelcomeItem = "(player, { kind: string, text: string, icon: string? })",
	PlotChanged = "(player, {})",
	ClubJoined = "(player, { club: string })",
	ClubWarClaimed = "(player, { league: string, week: number })",
	MarketListed = "(player, { listing: string, key: string, price: number, club: boolean })",
	MarketBought = "(player, { listing: string, key: string, kind: string, price: number, club: boolean })",
	MarketSold = "(nil, { listing, key, kind, price, proceeds, buyer, seller, club })  -- on the buyer's server",
}

-- Shared shapes (documentation) -----------------------------------------------------
Api.Shapes = {
	Reward = "{ kind: 'coins'|'gems'|'food'|'treats'|'stardust'|'ribbons'|'friendship'|'token'|'egg'|'xp'|'decor'|'monster'|'accessory', id: string?, amount: number, rarity: number? }",
	Monster = "see ARCHITECTURE.md → Monster record",
	Listing = "see ARCHITECTURE.md §8 → Listing (client view)",
	Appearance = "see Logic/Appearance.luau",
	BattleReplay = "see Logic/BattleSim.luau",
}

return Api
