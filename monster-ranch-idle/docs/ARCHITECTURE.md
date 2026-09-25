# Architecture & Contracts

This document is the contract every workstream builds against. If you need something that isn't here, add it here first (and to `src/shared/Kernel/Api.luau` if it crosses the network), then tell the other workstreams.

## 1. Source layout (Rojo)

```
src/shared   → ReplicatedStorage.Shared
  Kernel/Api.luau        THE CONTRACT: actions, events, state paths, bus topics
  Kernel/T.luau          payload validators
  Kernel/Signal.luau
  Config/*.luau          all content and tuning (pure data)
  Logic/*.luau           pure rules, no Roblox APIs (unit-tested in Lune)
src/server   → ServerScriptService.Server
  Main.server.luau       boots the kernel
  Manifest.luau          systems plugged in
  Kernel/*               kernel (do not add game rules here)
  Systems/<Name>/init.luau  one folder per system
src/client   → StarterPlayer.StarterPlayerScripts.Client
  Main.client.luau       boots the client kernel
  Manifest.luau          controllers and screens plugged in
  Kernel/*               client kernel, Store, NetClient, Router
  Controllers/<Name>.luau  always-running client systems (HUD, World, …)
  UI/Theme, Create, Anim, Layers, Components/*   UI kit
  UI/Screens/<Name>.luau menus opened by the Router
  Visuals/*              placeholder 3D models and animation (art swap point)
tests/
  init.luau              runner (lune run tests)
  lint.luau              syntax check of every file (lune run tests/lint)
  runtime/*              Loader, MockAdapters, TestKernel, Expect
  specs/*.spec.luau      one spec file per system or logic module
```

## 2. Server system contract

```lua
local MySystem = {
	Name = "MySystem",                       -- == folder name == action prefix
	Dependencies = { "Currency" },           -- required; order + GetSystem access
	OptionalDependencies = { "Monetization" }, -- may be absent; look up lazily
}

MySystem.Profile = {                         -- only if the system saves data
	Version = 1,
	Default = function() return { ... } end, -- fresh section for new players
	Migrate = function(section, fromVersion) return section end, -- optional
	Private = { "log" },                     -- top-level keys never sent to clients
	Replicate = true,                        -- false = nothing sent to clients
}

function MySystem.Init(ctx) end               -- register actions, subscribe to topics
function MySystem.Start() end                 -- after every Init; register providers here
function MySystem.PlayerAdded(player, info) end -- profile loaded; info = { firstJoin, awaySeconds, lastSeen }
function MySystem.PlayerRemoving(player) end
function MySystem.BeforeSave(player) end      -- flush derived data into the section

-- Public API used by other systems: methods on the module table.
function MySystem:DoThing(player, ...) end

return MySystem
```

Rules:

1. **Own your data.** Only touch `ctx:Section(player)` (your own `profile.<Name>`), `ctx:Session(player)` and `ctx:Global()`. Anything else goes through another system's public API.
2. **Mark what changed.** After changing data, call `ctx:Dirty(player, "key", "sub")`, `ctx:DirtySession(player, …)` or `ctx:DirtyGlobal(…)`. The kernel sends the current value at flush time. Replicate arrays whole.
3. **Validate everything.** Payloads are schema-checked by the kernel, but ownership, affordability, unlocks and state (busy, locked, timers) are your job. Fail with `ctx:Fail("Player-facing message")`.
4. **Never trust client time.** Timers are `startedAt` / `endsAt` unix seconds from `ctx:Now()`.
5. **Optional dependencies are looked up lazily** (`ctx:GetSystem("X")` at call time, and it may return nil). Never cache them in `Init`. They don't affect start order, so they can point "upwards" without cycles.
6. **Cross-system reactions go through the Bus** (`ctx.Bus:Publish(topic, player, detail)`); topics are declared in `Api.Topics`.
7. **No Roblox services** except through `ctx.Services` (see `Kernel/Adapters.luau`). This keeps systems testable in Lune. The only exception is the `World` system, which builds geometry and is tested in Studio.
8. **Data shapes:** arrays are contiguous (use `false`, not `nil`, for empty slots); map keys are strings; never use digit-only string keys (user maps use `"u" .. userId`). No functions, Instances or Roblox types in saved or replicated data.

### ctx API (server)

| Member | Purpose |
|---|---|
| `ctx.Name`, `ctx.Config`, `ctx.Api` | identity, content, contract |
| `ctx.Net:Handle(action, fn(player, payload) -> data)` | implement an action from `Api.Actions` (prefix must be your Name) |
| `ctx.Net:Fire(player, event, payload)` / `FireAll` | send an event from `Api.Events` (prefix must be your Name or `Kernel`) |
| `ctx.Bus:Publish(topic, player, detail)` / `Subscribe(topic, fn(player, detail))` | system ↔ system events |
| `ctx:GetSystem(name)` / `ctx:HasSystem(name)` | declared dependencies only |
| `ctx:Section(player)` / `ctx:Session(player)` / `ctx:Global()` | your data |
| `ctx:Dirty(player, …)` / `DirtySession` / `DirtyGlobal` | replicate a path |
| `ctx:Meta(player)` | `{ created, lastSeen, joins, playSeconds }` (read-only) |
| `ctx:Players()` / `IsReady(player)` / `PlayerByUserId(id)` | ready players |
| `ctx:Now()` / `ctx:Day()` | unix seconds / UTC day number |
| `ctx:Every(seconds, fn)` / `ctx:After(seconds, fn)` | kernel-scheduled timers (deterministic in tests) |
| `ctx:Fail(message)` | abort the request with a player-facing message |
| `ctx:Notify(player, text, kind)` | toast (`info`, `success`, `error`, `reward`) |
| `ctx:RequestSave(player)` | save soon (after purchases and trades) |
| `ctx.Rng` | server RNG (`Logic/Rng`); use `Rng.new(seed)` for reproducible rolls |
| `ctx.Services` | adapters: `Players`, `Marketplace`, `Policy`, `Ads`, `Messaging`, `Text`, `Analytics`, `Leaderboards`, `Clubs`, `Workspace`, `Spawn`, `Wait` |
| `ctx.Analytics` | `Custom(player, name, value, fields)`, `Economy(...)`, `Onboarding(player, step, name)` |
| `ctx:Log(fmt, …)` | debug log (printed when the kernel is verbose) |

## 3. Records

### Monster record (`profile.Monsters.list[id]`)

| Field | Type | Notes |
|---|---|---|
| `id` | string | `"m<n>"`, assigned by Monsters |
| `line` | string | `Config.Species` line id |
| `stage` | 1..3 | Baby, Teen, Adult |
| `form` | string | current form id (adult branch when stage 3) |
| `rarity` | 1..6 | |
| `variant` | 0..2 | normal, golden, rainbow |
| `muts` | {string} | ≤ 2 mutation ids (combos count as one) |
| `traits` | {number, number} | visible trait ids |
| `hidden` | number | hidden trait id (effects apply from birth; shown to players at Adult) |
| `weight` | number | kg |
| `lv`, `stars` | number | stars 1..maxStars for rarity |
| `mood` | 0..100 | |
| `meals` | {[flavor]: n} | meals eaten in the current stage (reset on growth) |
| `growEndsAt` | number | 0 = not growing |
| `loc`, `pen` | `"barn"`/`"pen"`, 0..5 | set only by Ranch |
| `busy` | false or `"expedition"`/`"breeding"`/`"trade"` | busy monsters can't be sold, fused, placed or traded |
| `name` | string | "" = use the form name |
| `locked` | boolean | player lock (can't sell or fuse) |
| `born`, `gen` | number | |

All derived numbers (coin rate, stats, power, value, level cap, grow time) come from `Logic/Formulas.luau`. Never store them.

### Reward item

`{ kind, id?, amount, rarity?, seconds? }` where `kind` is `coins | gems | stardust | friendship | treats | food | token | xp | egg | decor | monster`. Grant with `Rewards:Grant(player, items, source)`.

### Appearance

The public render view of a monster (`Logic/Appearance.luau`). It is what other players, trades and broadcasts see, and what `Visuals` builds from.

## 4. Public APIs of every system

Signatures are fixed. Implement exactly these names; add new methods freely, but don't rename these.

### S1: Currency, Progression, Rewards, Settings (built, reference implementations)
- `Currency:Balance(player, key)`, `:Add(player, key, amount, reason)`, `:CanAfford(player, cost)`, `:Spend(player, cost, reason) -> bool`, `:Charge(player, cost, reason)`, `:NormalizeCost(price, eventId?)`. Keys: `coins gems stardust friendship treats food.<flavor> token.<event>`.
- `Progression:AddXP(player, n, reason)`, `:GetLevel(player)`, `:IsUnlocked(player, key)`, `:Require(player, key)`, `:UnlockLevel(key)`. Also listens to bus `RanchXP`.
- `Rewards:Grant(player, items, source, { silent?, multiplier? }) -> granted`.
- `Settings:Get(player, key)`.

### S2: Monsters (built)
`Create, Insert, Get, All, Count, Capacity, Remove, Available, SetBusy, SetLocation, Changed, AddMutation, AddMood, CoinRate, Stats, Appearance, RegisterCapacityProvider(fn(player)->n), RegisterMoodFloorProvider(fn(player)->n)`. See the header of `Systems/Monsters/init.luau`.

### S3: Eggs, Shop, Ranch, WelcomeBack
- **Eggs**: `Eggs:Add(player, eggType, source, amount?) -> {ids}`, `:Remove(player, id) -> record?`, `:Insert(player, record, source) -> id`, `:Get(player, id)`, `:Count(player)`, `:SlotCount(player)`, `:RegisterSpeedProvider(key, fn(player) -> fraction)` (0.1 = 10% faster; summed, capped at 0.75). Queries `Monetization:HasPass(player, "extraIncubator" | "luckyHatcher")`. Places the starter egg on first join. Publishes `EggAdded`, `EggHatched`, `RanchXP`; fires `Eggs.Hatched`.
- **Shop**: `Shop:AddDecor(player, id, n)`, `:TakeDecor(player, id) -> bool`, `:ReturnDecor(player, id)`, `:OwnsTheme(player, themeId) -> bool`. Global restock in `global.Shop`.
- **Ranch**: `Ranch:IncomePerSecond(player)`, `:PenOf(player, monsterId) -> 0..5`, `:MonstersInPens(player) -> { { id, pen } }`, `:CollectAll(player, multiplier?) -> coins`, `:JarTotal(player) -> coins`, `:RegisterRateModifier(key, fn(player, elements) -> additive pct)`, `:RegisterJarBonus(key, fn(player) -> seconds)`. Registers the Monsters capacity provider (barn + pens + Big Barn pass) and an Eggs speed provider (incubator tier). Takes monsters out of pens automatically when they become busy or are removed (listens to `MonsterChanged` and `MonsterRemoved`). Publishes `JarCollected`, `PlotChanged`, `PenChanged`.
- **WelcomeBack**: collects `WelcomeItem` topics during join, then writes `session.WelcomeBack`. `WelcomeBack.Claim { double }` collects every jar, doubled with the `welcomeDouble` ad.

### S4: Expeditions, Boss
- **Regions** (`Config/Regions`): read stage layout through `Regions.Stages(regionId)`, `Regions.Band(regionId, stage)` (main band or the `depths` band, with its unlock, levels, rarity, enemy lines and colours), `Regions.MaxStages` and `Regions.GlobalIndex(regionId, stage)`. See `docs/UPDATES.md` (1.1).
- **Expeditions**: `Expeditions:GetSquad(player) -> {ids}`, `:SquadPower(player) -> number`, `:Cleared(player, region) -> stage`, `:RegisterLootModifier(key, fn(player) -> pct)`. Uses `Logic/BattleSim` (deterministic, seeded) and `Logic/Loot`. Busy tag `"expedition"`. Caravans in `global.Expeditions.caravans` and `session.Expeditions`.
- **Boss**: `Boss:State() -> global table`, `:RegisterDamageModifier(key, fn(player) -> pct)`. Uses `Expeditions:GetSquad`. Publishes `BossJoined`, `BossEnded`; fires `Boss.Result`.

### S5: Breeding, Weather, Social, Trade, Plots
- **Breeding**: `Breeding:RegisterBreedsPerDayBonus(key, fn(player) -> n)`. Uses `Logic/Breeding` (`Outcomes(a, b)` for previews, `Roll(rng, a, b)`). Busy tag `"breeding"`. Queries `Monetization:HasPass(player, "breedingPod")`.
- **Weather**: `Weather:Current() -> { id, endsAt }`, `:IsNight()`, `:Trigger(weatherId, source, seconds?)`, `:GuaranteeMutation(player, mutationId) -> bool` (tutorial). Registers the `Weather.Totem` product handler with Monetization and a heatwave Eggs speed provider.
- **Social**: `Social:GetFriendBoost(player) -> pct`, `:Broadcast(kind, text, player?, appearance?, scope)`. Registers the Ranch rate modifier `friends`. Subscribes to `EggHatched`, `Bred`, `Mutated`, `WeatherChanged` for broadcasts.
- **Trade**: all `Trade.*` actions; atomic two-sided transfer through `Monsters:Remove/Insert` and `Eggs:Remove/Insert`; `ctx:RequestSave` for both players; private `log`.
- **Plots**: `Plots:GetPlot(player) -> 1..6`, `:Refresh(player)`. Publishes `global.Plots[i]` (see Api.State). Throttles refreshes (≤ 1 per 2 s per player).
- **Clubs** (1.2): `Clubs:ClubOf(player) -> clubId?`, `Clubs:Flush()`. Records through `ctx.Services.Clubs.Get/Update` (atomic); pure rules in `Systems/Clubs/Record.luau`. Subscribes to the goal topics in `Config.Clubs.Goals`; publishes `ClubJoined`. State: `session.Clubs.club`, `global.Clubs.here`.
- **Events** (1.2): `Events:Active() -> eventDef?`, `Events:Grant(player, amount, source) -> granted`. The calendar is `Config.Events` (`Active(now)`, `ActiveId(now)`); read the running event through it, never through `Flags.ActiveEvent` directly.
- **Leaderboards**: `Leaderboards:Value(player, boardId) -> (value, label?)`, `:Titles(userId) -> { boardId }`. Reads `Monsters:All`/`:CodexCount`, `HallOfFame:RetiredCount`, `Expeditions:Cleared` (all optional) and the `BossDamage` topic. Publishes `global.Leaderboards` (see Api.State); global IO through `ctx.Services.Leaderboards.Submit/Top` and `Services.Players.NameOf`, inside `Services.Spawn`.

### S6: Monetization, Quests, HallOfFame
- **Monetization**: `Monetization:HasPass(player, key) -> bool`, `:RegisterProduct(handlerKey, fn(player, product, receiptInfo) -> bool)`, `:WatchAd(player, placement) -> bool` (yields; enforces daily caps), `:AdsLeft(player, placement) -> n`, `:PaidRandomAllowed(player) -> bool`. ProcessReceipt is idempotent (private `receipts`). Publishes `PassesChanged`, `RateModifiersChanged`, `Purchase`, `AdWatched`.
- **Quests**: tutorial (`Config.Quests.Tutorial`), dailies, achievements, codes, Ranch Pass handler `Quests.RanchPass`. Sends onboarding funnel steps through `ctx.Analytics.Onboarding`.
- **HallOfFame**: `HallOfFame:GetLegacy(player, element) -> pct`, `:UpgradeLevel(player, id) -> n`, `:Statues(player) -> { Appearance }`. In `Start()` registers: Ranch rate modifier `legacy` and jar bonus `jar_cap`, Eggs speed `incubator_speed`, Monsters mood floor, Boss damage `boss_power`, Breeding per-day `daily_breed`, Expeditions loot `expedition_loot`.

### World (client workstream C1, server-side geometry)
- **World** (server): builds ground, plot floors, pen fences (collision), hub buildings and the spawn from `Config.World`. It uses `ctx.Services.Workspace`. It has no actions and is tested in Studio only.

### Provider pattern

When system A's number depends on system B (e.g. HallOfFame changes hatch speed), A exposes `RegisterXProvider(key, fn)` and B registers in its `Start()` (look up A lazily with `ctx:GetSystem`). A never depends on B.

## 5. Client contract

### Controllers (`src/client/Controllers/<Name>.luau`)
```lua
return {
	Name = "Hud",
	Dependencies = {},          -- other controllers
	Init = function(ctx) end,   -- build UI, connect Store observers
	Start = function() end,
}
```
`ctx` is documented at the top of `src/client/Kernel/ClientKernel.luau` and includes `Net`, `Store`, `Router`, `UI` layers, `Bus`, `Now`, `Toast` and `Sound`.

### Screens (`src/client/UI/Screens/<Name>.luau`)
```lua
return {
	Name = "EggShop",
	Build = function(ctx)
		local panel = Panel.new({ Title = "Egg Shop", Color = Theme.Colors.Pink, OnClose = function() ctx.Router:Close("EggShop") end })
		return { Root = panel.Root, Open = function(params) end, Close = function() end }
	end,
}
```

Canonical names (the HUD, world prompts and other screens open these):

| Name | Owner | Params |
|---|---|---|
| `EggShop` | C2 | — |
| `Incubators` | C2 | — |
| `Monsters` | C2 | `{ tab? }` or pick mode: `{ pick = { title, filter = fn(monster) -> bool, max = 1, onPick = fn({ ids }), returnTo = "ScreenName", returnParams } }` |
| `MonsterDetail` | C2 | `{ id }` |
| `Ranch` | C2 | `{ pen? }` |
| `WelcomeBack` | C2 | — (auto-opens when `session.WelcomeBack.pending`) |
| `Codex` | C2 | — |
| `Expeditions` | C3 | `{ region? }` |
| `Breeding` | C3 | — |
| `Trade` | C3 | — |
| `Boss` | C3 | — |
| `HallOfFame` | C3 | — |
| `Quests` | C3 | `{ tab? }` |
| `Store` | C3 | `{ tab? = "food"|"decor"|"passes"|"gems"|"codes" }` |
| `Settings` | C3 | — |

Controllers: `Hud`, `Notifications`, `Hatchery` (C2) · `Tutorial`, `Broadcasts`, `TradeRequests` (C3) · `World`, `Weather`, `Interaction` (C1).

Client bus topics (free-form, client only): `"Tutorial.Arrow"` `(target: string?)` where the HUD exposes targets `incubator`, `jar`, `shop`, `monster`, `expeditions`, `weather`; `"World.FocusPlot"` `(plotIndex)`; `"Hud.Flash"` `(buttonName)`.

### UI kit
`UI/Theme`, `UI/Create` (`New`, `Corner`, `Stroke`, `TextStroke`, `Padding`, `List`, `Grid`, `Shade`, `Text`), `UI/Anim` (`popIn`, `pulse`, `shake`, `countUp`, `bob`, `tween`), `UI/Layers`. Components: `Button`, `Panel`, `Icon`, `Widgets` (`Pill`, `Bar`, `Chip`, `RarityChip`, `ElementChip`, `MutationChip`, `VariantChip`, `Scroll`, `List`, `Tabs`, `Countdown`, `Amount`), `Toasts`, `MonsterIcon` (`new`, `egg`, `silhouette`, `card`). Design size is 1100 × 560 (landscape phone); every tap target is at least 44 px.

### Visuals (art swap point)
- `Visuals/MonsterModel.Build(appearance, opts) -> Model` (contract in the file header).
- `Visuals/EggModel.Build(eggType, opts) -> Model`.
- `Visuals/MonsterAnimator.new(model) -> animator` with `:Play(state)` (`idle|walk|happy|eat|attack|hurt|sleep`), `:SetBase(cframe)`, `:Destroy()`. One shared RenderStepped loop drives every animator. Owned by C1.

## 6. State shapes (binding)

These are the exact replicated shapes. Server systems must produce them; client screens read them. Arrays have fixed lengths where noted, and use `false` for empty values.

```lua
profile.Currency   = { coins, gems, stardust, friendship, treats, tokens = { [eventId] = n }, food = { sweet, spicy, savory, sour } }
profile.Progression = { level, xp }                     -- xp toward next level: Config.Unlocks.XPToNext(level)
profile.Settings   = { music, sfx, lowGraphics, hideBroadcasts }
profile.Monsters   = { list = { [id] = Monster }, codex = { [lineId] = { forms = { [formId] = true }, variants = { normal|golden|rainbow = true }, count } }, nextId, grown }

profile.Eggs = {
  list = { [eggId] = { type = eggType, source = string, t = unix } },   -- eggId = "e<n>"
  slots = { [1..4] = { egg = eggId|false, type = eggType|"starter"|false, startedAt, endsAt } }, -- always 4 entries
  nextId, pity = { starlit, royal }, hatched,
}
session.Eggs = { slotCount, speed }                     -- usable slots (1..4); total speed-up fraction

profile.Shop  = { window, bought = { [eggType] = n }, decor = { [decorId] = n }, themes = { [themeId] = true }, freeEggDay }
global.Shop   = { window, endsAt, stock = { [eggType] = n } } -- n = -1 means unlimited; only eggs purchasable now

profile.Ranch = {
  pens = { [1..owned] = { capacity, jarTier, jar, jarAt, monsters = { id }, decor = { decorId }, theme } },
  incubatorTier, barnTier,
  garden = { tier, plots = { [1..n] = { flavor = string|false, readyAt } } },
}
session.Ranch = { income, rates = { [pen] = coinsPerSec }, caps = { [pen] = seconds }, capacity, used }
-- client shows a live jar: min(jar + rate × (now − jarAt), rate × cap)

session.WelcomeBack = { pending, awaySeconds, coins, items = { { kind, text } } }

profile.Expeditions = {
  cleared = { [regionId] = highestStage },
  slots = { [1..4] = { state = "idle"|"running", region = string|false, stage, squad = { id }, startedAt, endsAt, duration, seed, caravan = string|false } },
  squad = { id },                                      -- the default squad (also used by the Stampede)
}
session.Expeditions = { slotCount, squadSize, caravan = CaravanLobby|false }
global.Expeditions  = { caravans = { [caravanId] = { id, host, hostName, region, stage, duration, members = { { userId, name, slot, power } }, expiresAt } } }

global.Boss  = { state = "idle"|"lobby"|"active", bossId, startsAt, endsAt, hp, maxHp, participants, board = { { userId, name, damage } } }  -- board: top 10
session.Boss = { joined, damage, cheer }                 -- cheer 0..1

profile.Breeding = { pods = { [1..2] = { state = "idle"|"running", a = id|false, b = id|false, startedAt, endsAt, seed } }, daily = { day, counts = { [monsterId] = n } }, discovered = { [lineId] = true } }
session.Breeding = { podCount, breedsPerDay }

global.Weather = { id, startedAt, endsAt, nextRollAt, night, phaseEndsAt, summonedBy = string|false }

profile.Social = { day, petsGiven, likesGiven = { ["u" .. userId] = true }, likes }
session.Social = { friendBoost, friendsHere }

global.Plots = { [1..6] = {                              -- always 6 entries; empty plot has userId = 0
  userId, name, level, likes,
  pens = { { theme, decor = { decorId }, monsters = { { id, appearance } } } },
  statues = { Appearance },
  incubators = { { type, endsAt } },
} }

session.Trade = {
  status = "none"|"outgoing"|"incoming"|"open"|"countdown",
  partner = { userId, name }|false,
  mine   = { items = { { kind, id, appearance = Appearance|false, egg = eggType|false } }, ready, confirmed },
  theirs = { items = …same…, ready, confirmed },
  endsAt,
}

profile.Quests = {
  tutorial = { step, progress },                         -- step indexes Config.Quests.Tutorial; step > #Tutorial = done
  daily = { day, list = { { id, progress, claimed } } },
  achievements = { [id] = { progress, claimed } },
  codes = { [CODE] = true },
  pass = { season, xp, premium, claimed = { free = { [tier] = true }, premium = { [tier] = true } } },
}

profile.Monetization = { ads = { day, counts = { [placement] = n } }, once = { [productKey] = true } }   -- receipts: private
session.Monetization = { passes = { [passKey] = boolean }, paidRandomAllowed }

profile.HallOfFame = { entries = { { appearance, retiredAt, rarity, element } }, legacy = { [element] = pct }, upgrades = { [upgradeId] = level } }  -- newest first, ≤ 100
```

## 7. Shared formats fixed ahead of parallel work

### BattleReplay (produced by `Logic/BattleSim`, returned by `Expeditions.Fight`, drawn by the Expeditions screen)
```lua
BattleReplay = {
  win = boolean, turns = number, seed = number,
  units = { {                                   -- allies first, then enemies
    key = "a1".."a4" | "e1".."e5", side = "ally"|"enemy", slot = number,
    name = string, appearance = Appearance, maxHp = number, boss = boolean,
  } },
  events = { {                                  -- in order; at most 400
    turn = number, actor = key, target = key | false,
    kind = "hit"|"crit"|"special"|"heal"|"shield"|"stun"|"stunned"|"faint"|"reflect"|"regen"|"miss",
    amount = number, hp = number,               -- target HP after the event (actor HP for regen)
    mult = number?,                             -- element multiplier when not 1 (1.5 / 0.7)
    skill = string?,                            -- Species.Skills id for "special"
  } },
}
```

### Breeding preview (`Logic/Breeding.Outcomes(a, b)`, pure, used by the Breeding screen)
```lua
{ species = { { line, pct, hybrid = boolean } }, rarity = { { rarity, pct } },
  mutationChance = number, seconds = number, fee = number, rainbowChance = number, goldenChance = number }
```
`Logic/Breeding.Roll(rng, a, b) -> MonsterGen spec` makes the actual roll.

### Extra public methods (added for the client-facing Plots view)
- `Ranch:PublicPens(player) -> { { theme, decor = { decorId }, monsters = { id } } }`
- `Eggs:PublicSlots(player) -> { { type, endsAt } }` (only filled slots)
- `Social:GetLikes(player) -> number`
- `Monsters:CodexCount(player) -> number` and `HallOfFame:RetiredCount(player) -> number` (for Leaderboards)
- `Eggs.Hatch { slot, starter? }`: `starter` is one of `Config.Eggs.Starter.lines` and only valid on the starter egg; `Eggs.HatchAll` skips the starter so the player always chooses.
- Client: the `Hud` controller exposes `Hud:GetTarget(name) -> GuiObject?` for the Tutorial arrow (`incubator`, `jar`, `shop`, `monster`, `expeditions`, `weather`, `quests`).

### Season pass
`Config.Quests.Pass = { season, startsAt, endsAt, xpPerTier, xpPerDaily, xpPerAchievement, tiers = { { free = { Reward }, premium = { Reward } } } }`. Claim with `Quests.ClaimPass { tier, track }`. Tier `n` needs pass XP ≥ `n × xpPerTier`.

## 8. Update 1.3 · Market Day contract (fixed before parallel work)

Three workstreams build against this section at the same time. Each owns only its own
files; shared files (`Api.luau`, `Config/Market.luau`, `Adapters.luau`, `MockAdapters.luau`,
both Manifests, docs) are changed by the integrator only.

| Workstream | Owns | Plugs in as |
|---|---|---|
| M1 · Market server | `src/server/Systems/Market/**`, `tests/specs/Market.spec.luau` | server system `Market` |
| M2 · Price history | `src/shared/Logic/PriceHistory.luau`, `src/server/Systems/PriceHistory/**`, `tests/specs/PriceHistory.spec.luau` | server system `PriceHistory` |
| M3 · Market client | `src/client/UI/Screens/Market.luau`, `src/client/UI/Components/PriceChart.luau`, the Market entry in `Controllers/Hud.luau`, `tests/specs/MarketClient.spec.luau` | screen `Market` |

### Listing record (server, `Services.Market`)
```lua
{
  id = string,                    -- "L" .. JobId-independent unique id (e.g. userId .. "-" .. counter .. "-" .. now)
  seller = userId, sellerName = string,
  kind = "monster" | "egg",
  item = record,                  -- the escrowed Monster record or egg record { type, source, t }
  key = Config.Market.ItemKey(kind, item),
  price = number,                 -- whole coins
  createdAt = unix, expiresAt = unix,   -- createdAt + Config.Market.DurationSeconds
  club = clubId | false,          -- club trading post listing (members of that club only)
  state = "open" | "sold" | "cancelled" | "expired",
  buyer = userId?, buyerName = string?, closedAt = unix?,
}
```
State only moves from `"open"` to one closed state, always inside `Services.Market.Update`
(atomic), which is what makes a sale happen at most once across all servers.

### Listing (client view, returned by Market.Browse / Market.Mine / Market.List)
```lua
{ id, seller, sellerName, kind, key, price, createdAt, expiresAt, club = boolean, mine = boolean, state,
  item = { appearance = Appearance | false, egg = eggType | false, name, rarity, variant, stage, lv,
           stars, weight, muts = { string }, traits = { traitId } } }   -- no hidden trait, no ids
```

### Adapters (`ctx.Services`)
```lua
Services.Market = {
  Create(listing) -> ok                          -- stores a new open listing (+ browse index)
  Get(id) -> ok, listing?
  Update(id, transform) -> ok, listing?          -- atomic; transform(current) returns new or nil
                                                 -- (no change); closed listings leave the index
  Browse({ scope = "all" | clubId, kind?, key?, sort = "price" | "-price" | "new" }) -> ok, { listing }
                                                 -- open listings without `item`; may include expired
                                                 -- ones (callers filter by expiresAt); ≤ 200 per kind
  MailAdd(userId, entry) -> ok                   -- atomic append
  MailTake(userId) -> ok, { entry }              -- atomic take-all
}
Services.PriceHistory = { Get(key) -> ok, record?, Update(key, transform) -> ok, record? }
```
Every call can fail (`ok == false`); systems must fail the action politely
("The market is busy. Try again") and never lose or duplicate an item.

Mail entry: `{ kind = "coins", amount, listing, key, price }` (a sale) or
`{ kind = "item", itemKind = "monster" | "egg", item = record, listing, reason = "expired" | "cancelled" }`.

### Flows (M1)
- **List:** unlock `market` (Lv 10); ≤ `MaxListings` open listings (`profile.Market.listings`);
  monster must exist, not be busy or locked; egg must be in storage (not incubating);
  club listings need a club (`Clubs:ClubOf`). Remove the item from the profile
  (`Monsters:Remove(p, id, "market")` / `Eggs:Remove`) → `Services.Market.Create`; if that fails,
  put the item straight back (`Insert`) and fail. Publish `MarketListed`; save soon.
- **Buy:** listing must be open, unexpired, not the buyer's own, the price must match, club
  listings need the buyer in that club, the buyer needs room (`Monsters:Capacity` / `Eggs:Room`)
  and the coins. Order: check → `Currency:Charge` → `Update(id, open → sold)`; if the update does
  not win (sold elsewhere, failure) refund the coins and fail. Then insert the item into the
  buyer (`Monsters:Insert(p, item, "market")` / `Eggs:Insert`), `MailAdd(seller, coins entry with
  Config.Market.Proceeds(price, club))`, publish `MarketBought` (buyer) and `MarketSold` (nil),
  save the buyer now. If `MailAdd` fails, keep the entry in a retry queue (never drop proceeds).
- **Cancel / expiry:** `Update(id, open → cancelled | expired)` by the seller; the item goes back
  to the profile if there is room, otherwise to the mailbox. The seller's server expires its
  players' own listings (checked on join and every `MailSyncSeconds`).
- **Mail:** collected for players on the server on join and every `MailSyncSeconds`
  (`MailTake`); coins added with reason `"market_sale"`, items inserted if there is room —
  items that don't fit go back with `MailAdd` and show in `session.Market.mail`.
  Fires `Market.MailCollected` when anything arrived.
- **Browse:** `Services.Market.Browse`, filtered by `expiresAt > now`, sorted, paged by
  `PageSize`; club scope = the player's club. A server may cache a browse result for
  `BrowseCacheSeconds`. `mine = listing.seller == player.UserId`.

### Price history (M2)
- `Logic/PriceHistory`: pure bucket math on a record `{ key, days = { { day, count, low, high, sum } } }`
  (UTC day numbers, oldest first, at most `Config.Market.HistoryDays`): `Add(record, price, day)`,
  `Series(record, today) -> { { day, count, low, high, avg } }` (days without sales omitted),
  `Last(record) -> price?`, `Suggest(record) -> price?` (recent average, for the sell screen).
- System `PriceHistory`: subscribes to `MarketSold` and writes `Services.PriceHistory.Update(key, …)`
  (failures are retried later, not dropped); `PriceHistory.Get { key }` returns `Series` + `last`,
  cached per key for 60 s. Public: `PriceHistory:Suggest(key) -> price?`.

### Client (M3)
- Screen `Market` with tabs: **Browse** (kind, species/egg filter, sort, pages, Buy with a confirm
  showing price and the price chart), **Sell** (pick a monster through `Monsters` pick mode or an
  egg from storage, price box, the tax and "you get" line, suggested price from
  `PriceHistory.Get`, "post to my club only" when in a club), **My listings** (cancel, time left),
  **Club post** (club scope browse; hidden when not in a club).
- `UI/Components/PriceChart`: `PriceChart.new({ Size, Parent }) -> { Root, SetSeries(days) }`,
  bars or a line from `{ { day, count, low, high, avg } }`, drawn with Frames only.
- Entry points: the HUD (make room in the left stack by moving Settings to a small gear button
  next to the level bar) and the `market` hub building (`Config.World.Hub`, screen `Market`).
- Show `Market.MailCollected` as a toast ("Your Blazefang sold for 12K!").
