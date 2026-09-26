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
  Audio/init.luau, Voices.luau   sound kit and monster voices (§5 Audio)
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
| `ctx:SaveNow(player) -> ok` | save now and wait (before a cross-server write that must not get ahead of the profile) |
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
| `loc`, `pen` | `"barn"`/`"pen"`, 0..6 | set only by Ranch (pen 6 since 3.2) |
| `busy` | false or `"expedition"`/`"breeding"`/`"trade"` | busy monsters can't be sold, fused, placed or traded |
| `name` | string | "" = use the form name |
| `locked` | boolean | player lock (can't sell or fuse) |
| `born`, `gen` | number | |
| `acc` | {[slot]: accessoryId}? | worn accessories (1.5). Set only by Accessories through `Monsters:SetAccessory`; `Monsters:Remove` strips it (the detail of `MonsterRemoved` carries it) and `Monsters:Insert` clears it, so accessories never travel with a traded, listed or retired monster |

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
- **Boss**: `Boss:State() -> global table`, `:RegisterDamageModifier(key, fn(player) -> pct)`. Uses `Expeditions:GetSquad`. Publishes `BossJoined`, `BossEnded`; fires `Boss.Result`, and to every player on the server `Boss.Starting { bossId, startsAt }` when the lobby opens (`Config.Boss.LobbySeconds` before the start) and `Boss.Started { bossId, startsAt, endsAt }` when the fight goes live.

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
- **Monetization**: `Monetization:HasPass(player, key) -> bool`, `:RegisterProduct(handlerKey, fn(player, product, receiptInfo) -> bool)`, `:RegisterProductCheck(handlerKey, fn(player, product) -> (bool, reason?))`, `:CanBuy(player, productKey) -> (bool, reason?)`, `:WatchAd(player, placement) -> bool` (yields; enforces daily caps), `:AdsLeft(player, placement) -> n`, `:PaidRandomAllowed(player) -> bool`. ProcessReceipt is idempotent (private `receipts`). Publishes `PassesChanged`, `RateModifiersChanged`, `Purchase`, `AdWatched`.
  - **Purchases always deliver.** Clients ask `Monetization.CanBuy { product }` before a product prompt; it refuses a once-per-account product already bought and whatever a handler's check refuses (the Ranch Pass outside a season, or a second one in a season). A receipt that arrives anyway is never left unprocessed: a repeat once-per-account product pays `Config.Monetization.GemValue(price)` gems (best gem-pack rate; receipt recorded with `fallback = "gems"`), and the Ranch Pass is banked in `profile.Quests.passCredit` for the next season.
  - **VIP Rancher** (pass `vip`): +4 h jar cap (Ranch), `Monetization.ClaimVipCrate` (one crate per UTC day, missed days don't stack; `Config.Monetization.VipCrate` rolled by `Logic/Vip.RollCrate`, seeded by userId and day; the fixed gift where paid random items are restricted; contents arrive as `Rewards.Granted`), and a gold [VIP] chat tag: the server lists owners in `global.Monetization.vip`, the client's `ChatTags` controller prefixes their messages through `TextChatService.OnIncomingMessage` (dormant under the legacy chat).
- **Quests**: tutorial (`Config.Quests.Tutorial`), dailies, achievements, codes, Ranch Pass handler `Quests.RanchPass` and its product check (`Config.Quests.PassOnSale(now)`, `NextSeason(now)`). Sends onboarding funnel steps through `ctx.Analytics.Onboarding`.
- **HallOfFame**: `HallOfFame:GetLegacy(player, element) -> pct`, `:UpgradeLevel(player, id) -> n`, `:Statues(player) -> { Appearance }`. In `Start()` registers: Ranch rate modifier `legacy` and jar bonus `jar_cap`, Eggs speed `incubator_speed`, Monsters mood floor, Boss damage `boss_power`, Breeding per-day `daily_breed`, Expeditions loot `expedition_loot`.

### 1.4: Rebirth, EggHunt
- **Rebirth**: `Rebirth:Stars(player) -> n`, `:SkillLevel(player, id)`, `:SkillEffect(player, id, key)`, `:Heirlooms(player)`. `Rebirth.Rebirth { keep }` runs in one step with no yields and calls the owners' reset hooks: `Ranch:ResetForRebirth(player, theme?)`, `Expeditions:ResetForRebirth(player)`, `Shop:GrantTheme(player, themeId)`, `Monsters:Remove(..., "rebirth")`. In `Start()` registers: Ranch rate multiplier `rebirth_stars` (new: `Ranch:RegisterRateMultiplier(key, fn(player) -> factor)`, multiplied into every pen's rate), Ranch rate modifier and jar bonus `rebirth_skill`, Eggs speed, Breeding per-day, Expeditions loot and Boss damage `rebirth_skill`. From `Config.Rebirth.ThirdTraitStars` stars it adds a 3rd visible trait to every monster (`Monsters:AddVisibleTrait`). Publishes `Rebirthed`. `Shop.BuyEgg` checks an egg's `rebirths` through `Rebirth:Stars`.
- **EggHunt**: `EggHunt.Find { spot }` (Spring Bloom). Round maths in `Logic/EggHunt` (`Round(now)`, `SpotsFor(round)`, deterministic on every server); the server checks the player's character stands within `Config.EggHunt.Reach` of the spot. Publishes `EggFound` and `global.EggHunt`.

### 1.5: Accessories, Contests
- **Accessories**: `Accessories:Add(player, id, n?)` (Rewards kind `accessory`), `:Count(player, id)`, `:Collection(player)`. Storage is `profile.Accessories.owned`; worn items are `Monster.acc`. Returns items to storage on `MonsterRemoved`. Publishes `AccessoryGained`. Prices use gems or the new `ribbons` currency (Contest Ribbons, a Currency key and a Rewards kind).
- **Contests**: clock-driven shows (`Config.Contests.Show(now)`, `ThemeFor(show)`, `JudgeScore(acc, theme)`); per-server state in `global.Contests`, votes in server memory only. Actions `Contests.Enter/Withdraw/Vote`. Prizes through `Rewards:Grant`. Publishes `ContestEntered`, `ContestVoted`, `ContestPlaced`.

### 2.0: SkyIslands, Riding, Surf
- **Elements**: `Config.Elements` has a third group, the Light/Void pair (triangle "C"): each beats the other and is neutral to the rest. Nothing else changes: `Elements.Multiplier` reads `beats`.
- **SkyIslands**: `SkyIslands.Collect { crystal }` (wind crystals on the floating islands in `Config.World.Sky`, built by World/Build under `Workspace.World.Sky`). Per-player respawn timers in `profile.SkyIslands.taken`, a daily cap, and a character distance check. Travel is client-side (launch/return pads). Publishes `CrystalCollected`.
- **Riding**: `Riding.Mount { id }` / `Riding.Dismount`. `global.Riding.riders` tells every client which mount to draw under each rider; `session.Riding.speed` is the rider's walk speed (`Config.Riding.SpeedFor`). Dismounts when the monster leaves, becomes busy, or the player leaves. Publishes `Mounted`. `MonsterModel.Build` takes `opts.scale` (mounts are 1.8×).
- **Surf**: `Surf.Start` → seed; `Surf.Finish { run, inputs }` replays the lane changes with `Logic/Surf.Simulate` (the client never reports a score). Wall-clock checks against the simulated run; Seashells through `Events:Grant`. Publishes `SurfRun`.

### 2.1: Arena, Raids
- **Arena**: cross-server records through `ctx.Services.Arena` (`Get`, atomic `Update`, `Index`, `Near`); one record per player `{ userId, name, rating, team, wins, losses, updatedAt }`. Fighters are normalized (`Logic/Arena.Normalize`: species, form and look only; rarity, level and stars fixed by `Config.Arena.Normal`), fights run in BattleSim, ratings move by Elo for both sides. Bots fill the candidate list. Actions `Arena.SetDefense/Refresh/Attack/ClaimWeekly`. Publishes `ArenaBattle`.
- **Raids**: per-server lobbies in `global.Raids.lobbies` (monster ids stay server-side), up to 4 players × 2 Adults against a raid boss and adds (BattleSim with `maxAllies = 8`; bosses use the new `hpMult` record field). Every member gets `Raids.Result` with the replay. Actions `Raids.Open/Join/Leave/Launch`. Publishes `RaidFinished`.
- **BattleSim** records accept `look` (drawn instead of the record's own appearance) and `hpMult`; `opts.maxAllies` raises the ally cap.

### 3.0: Racing, TradingHub, Workshop
- **Regions** may carry `opensAt` (a new region every quarter): `Regions.IsOpen(region, now)` gates Expeditions on top of the unlock level.
- **Racing**: `Racing.Start { id }` → `{ race, day, speed, ghosts }`; the client builds the same track (`Logic/Racing.Track(Rng.seed("racing", day))`) and steps `Logic/Racing.Step` locally; `Racing.Finish { race, inputs = { { t, a } } }` is replayed with `Logic/Racing.Simulate` (wall-clock checked). `Racing:CupPoints(player)` feeds the `racing` leaderboard. Publishes `RaceFinished`.
- **TradingHub**: one codebase, two places. `Config.TradingHub.Mode(Services.PlaceId, Services.PlaceMode)` is `"hub"` on the Trading Hub place (or with Workspace attribute `PlaceMode = "hub"`). On the hub, Plots assigns nothing and World builds `Config.TradingHub.World`. `global.TradingHub = { mode, ads, refreshedAt }`.
  ```lua
  Services.Teleport = { ToPlace(player, placeId) -> ok, err?, ToServer(player, placeId, jobId) -> ok, err? }
  Services.HubBoard = { Post(ad, ttl) -> ok, Remove(id) -> ok, List(limit) -> ok, { ad } }  -- newest first
  ```
  Actions `TradingHub.Travel/Return/Post/Remove/Refresh/Meet`. Publishes `HubTravel`, `HubAdPosted`.
- **Workshop**: designs are records in `Services.Designs`:
  ```lua
  Services.Designs = {
    Create(record) -> ok            -- fails if the id exists; adds it to the recent feed
    Get(id) -> ok, record?
    Update(id, transform) -> ok, record?   -- atomic
    Index(id, likes) -> ok          -- OrderedDataStore for the Top gallery
    Top(count) -> ok, { id }        Recent(count) -> ok, { id }
  }
  ```
  A worn design is stored on the monster as `"ugc:<designId>:<shape>:<RRGGBB>:<RRGGBB>"` (`Config.Accessories.Encode`); `Config.Accessories.Resolve(id)` returns a catalogue item or a design definition, so MonsterModel, the Wardrobe and the Contest judge handle both. Taking a design off goes through `Accessories:Return`, which hands `ugc:` ids to the Workshop (`Accessories:RegisterReturn`). Actions `Workshop.Create/Browse/Like/Report/Buy/Equip/Claim`. Publishes `DesignPublished`, `DesignBought`.

### 3.0.1: go live
- **Events** may list `reruns = { { startsAt, endsAt } }`; `Events.Active(now)` returns the event with the running window's dates.
- **Places**: `Services.Places.List() -> ok, { { name, placeId } }`. TradingHub resolves the target place by `Config.TradingHub.PlaceNames` (pins in `PlaceIds` win). The hub place is built from `hub.project.json` (Workspace attribute `PlaceMode = "hub"`).
- **Teleport**: `ToPlace` / `ToServer` retry transient `TeleportInitFailed` results twice.
- **Designs** adds `Owe(userId, n)`, `Collect(userId) -> ok, n` (royalty ledger) and `Flag(id)`, `Unflag(id)`, `Flagged(count) -> ok, { id }` (moderation feed). The Workshop caches records for `CacheSeconds` and lists for `ListCacheSeconds`.
- **Players** adds `RankInGroup(player, groupId) -> number`.

### 3.1: Club Wars
- **Clubs** records gain `warPoints`, `lastWar = { week, points }`, member `war` / `lastWar` and `banner`. War points come from `Config.Clubs.War.sources` (bus topics) through the pending buffer, capped per member per day (`profile.Clubs.war`).
  ```lua
  Services.Clubs.IndexWar(week, clubId, points) -> ok
  Services.Clubs.TopWar(week, count) -> ok, { { id, points } }   -- highest first
  ```
  `global.Clubs.ladder = { week, at, rows }`. `Clubs.ClaimWar` pays last week's league (or Champion, top 3 of `TopWar`) once per member who scored. `Clubs.SetBanner { design }` needs `Workshop:Copy`.

### 3.2: Level 70, Raid 3, languages, controllers
- **Level cap:** `Config.Unlocks.LevelCaps = { { level, from } }` are dated steps (60, then 70 from Sat 11 Mar 2028). `Unlocks.MaxLevelAt(now)` is the cap in force, read by Progression and the HUD. `Unlocks.MaxLevel` (70) is the all-time ceiling.
- **Level 70 unlocks:** `incubator_4` (62), `pen_6` (66), `squad_5` (70). `Economy.Incubators.maxSlots = 5` (4 earned + the pass) and `Economy.Pens.max = 6`.
- **Squad size:** `Regions.SquadSize = { base = 3, steps = { { unlock, size } } }`. `Expeditions:SquadSize` is `base` raised by each unlocked step. `BattleSim.MaxAllies = 5`; Raids pass `maxAllies = 8`.
- **Raids** may carry `opensAt` (closed to everyone until then, `Config.Raids.IsOpen`) and `unlock` (the raid's own Ranch Level key, `Config.Raids.UnlockFor`, default `Raids.Unlock`). Open checks both for the host; Join checks the unlock for each joiner.
- **Settings:** `profile.Settings.language` is `"auto" | "en" | "es" | "pt"`, set with `Settings.SetLanguage { language }`.
- **Locale** (`src/shared/Locale`, `docs/LOCALIZATION.md`):
  ```lua
  Locale.Translate(lang, text) -> text          -- exact or {n} template; pieces translated too
  Locale.Explain(lang, text) -> (text?, missing) -- what stays English (coverage specs)
  Locale.Pick(setting, localeId) -> "en" | "es" | "pt"
  ```
  English is the source language in code. Nothing but the client's `Localize` controller calls `Translate`.

### 3.3: Mastery (endgame)
- **Mastery** (design and numbers in `Config/Mastery`'s header, rules in `Logic/Mastery`): actions `Mastery.Reroll { id, slot }`, `Mastery.Buy { item }`, `Mastery.Equip { kind, item }` (`item = ""` takes it off). Public: `AddXP`, `AddLinePoints`, `RanchLevel`, `LineTier`, `WeekPoints` (the `mastery` leaderboard), `PerkEffect`.
- Progression publishes `RanchXPOverflow` for Ranch XP earned at the cap (it used to be dropped). `MonsterRemoved` carries `line` and `rarity`; `StageCleared`, `ArenaBattle` and `RaidFinished` carry the fighting `squad`.
- HallOfFame gains `SpendStarShards(player, amount, reason) -> boolean` and `AddStarShards(player, amount, reason)`. Monsters gains `RegisterAppearanceDecorator(key, fn(player, record, appearance))`; Mastery sets `appearance.aura` (a `Config/Vfx` `Mastery` key) and `Visuals/Vfx` draws it (kind `mastery`, off on other plots in low graphics, <= `Budget.mastery` live particles).
- `global.Mastery.here["u" .. userId] = { flourish, title, plinth }`: Nameplates show the title and flourish, World styles the statue pedestals.

### Glow-up L: Community, Gifts
- **Community**: actions `Community.Trick { id, trick }` (own pen monster, cooldown; event `Community.Trick` to everyone, drawn by World), `ClaimGroup` (once per account, `Config.Quests.GroupId` ≠ 0), `ClaimPremium` (once per UTC day), `Balcony { enter }` (VIP up, anyone down; a patrol moves non-VIP characters off the deck). Invites: a first join with launch data `invite:<userId>` from a friend rewards the invitee and mails the inviter (kind `invite`, weekly cap at collection). State `profile.Community`, `global.Community.premium`. Public: `Community:IsPremium(player)`. Optional adapters with a live fallback on the Player object: `Services.Players.JoinData`, `Services.Players.IsPremium`, `Services.Characters.Position/MoveTo`.
- **Gifts**: `Gifts.Prepare { to, kind, item, amount } -> token` then `Gifts.Send { token }`; `Gifts.PassTarget { to }` + product handler / check `Gifts.RanchPass` (product `ranchPassGift`, `gift = true`: never listed in the Store grid). Delivery through the Market mailbox. Publishes `GiftSent`.
- **Market** (additions): `Market:RegisterMail(kind, fn(player, entry) -> done)` (in Start) and `Market:Send(owner, userId, entry) -> deliveredNow` (saved outbox task first, then `MailAdd`). Other systems' mail kinds are handed to their handler on collection; `false` keeps the entry for the next sync.
- **Quests**: `Quests:GrantPass(player) -> boolean` (a gifted pass: premium now, else banked). **Accessories**: `:Stored(player, id)`, `:Take(player, id)`.
- **Client**: controller `Community` (HUD Emotes / Friends buttons, G and D-pad down, emotes through the character's Animate `PlayEmote`, balcony pad prompts on parts with attribute `VipPad`); screens `EmoteWheel`, `Friends`; `World.PlayTrick(owner, id, trickId)`, `World.NearestOwn(position, range)`; `MonsterAnimator.HasState(state)`; Nameplates show VIP gold names and a Premium badge.

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

Controllers: `Hud`, `Notifications`, `Hatchery` (C2) · `Tutorial`, `Broadcasts`, `TradeRequests` (C3) · `World`, `Weather`, `Interaction` (C1) · `Localize`, `Gamepad` (3.2) · `Soundscape` (audio) · `ChatTags` (VIP chat tag) · `Celebrate`, `Stampede` (glow-up).

- **Layers:** `ctx.UI.Hud`, `Screens`, `Overlay`, `Top` and `Feedback` (glow-up), in that drawing order. `Feedback` holds the feedback queue, flying rewards and the Stampede banner, so feedback is never hidden behind the popup it is about.
- **Feedback queue (`UI/Components/Toasts`):** toasts and reward cards share one stack above the bottom bar. `Toasts.show(text, kind, seconds?)` (`ctx:Toast`), `Toasts.push(gui, seconds?) -> dismiss()`, `Toasts.dismiss(gui)`. At most 4 items; they pop in, shrink out, and a repeated toast refreshes the one showing.
- **Celebrate (glow-up):** one API for every reward that lands and every celebration. Sizes `small | medium | big | huge` come from `Logic/Celebration` (`Size(items, income)`, `CoinSize`, `GemSize`, `Plan(size, low)`, `TickKey`).
  ```lua
  Celebrate:Reward(items, { from?, size?, minSize?, hold?, label? }) -> size  -- fly to the HUD counters
  Celebrate:Hold({ "coins" | "gems" | "food" }) -> handle     -- before a request; handle:Release(kind?, seconds?)
  Celebrate:Play(size)                    -- shower + confetti (big+), camera shake + FOV kick (huge), rumble, sound
  Celebrate:CountUp(label, from, to, size, format) -> stop
  Celebrate:Shockwave(gui, color?)  ·  Celebrate:Slam(gui, color?)  ·  Celebrate:Flourish(gui?)
  Celebrate:Moment(key, fn, { settle?, flourish?, at? })  -- hold an in-world moment while the world is covered
  Celebrate:IsCovered() -> boolean  ·  Celebrate:Pending() -> number
  ```
  `from` is a GuiObject, a world position (BasePart, Vector3, CFrame; projected through the camera) or a Feedback-layer `Vector2`. "Covered" means a Router screen is open, a `UI/Focus` modal is up, or the hatch reveal is showing. Low graphics keeps the counters and a short "+N" cue and drops swarms, shake, FOV kick, shockwaves and sparkles. New sound keys: `CoinTick1`..`CoinTick5`, `GemTick`, `ItemPop`, `Whoosh`, `StarUp`, `CelebrateBig`, `CelebrateHuge`, `StampedeSoon`.
- **Hud counters (glow-up):** `Hud:HoldCounter(kind)`, `:ReleaseCounter(kind, seconds?)`, `:PulseCounter(kind)` for `coins`, `gems`, `food`; `Hud:GetTarget` also returns `coins`, `gems`, `food` and `level`.
- **Stampede (glow-up):** `Boss.Starting` and `Boss.Started` show a banner on the Feedback layer to everyone (Join opens the Boss screen when unlocked) and play `StampedeSoon` / `BossHorn`. `Stampede:Banner() -> GuiObject?`. The HUD's Stampede card glows and shows a badge while the fight is in its lobby or live.

- **Localize (3.2):** watches every TextLabel / TextButton (and TextBox placeholder) under the PlayerGui and the Workspace. It keeps the English a text object was given (`Localize:Source(obj)`) and shows `Locale.Translate` of it. A longer translation is shrunk to no more than the English's room (not below 75 %). Opt out with the attribute `Localize = false`. It is first in the client Manifest.
- **Gamepad (3.2):** dormant until the last input comes from a pad.
  - **Scope:** the topmost `UI/Focus` modal, else the open Router screen. It gets `SelectionGroup` with `Stop` edges. The cursor goes to the last or first control, level-triggered every frame.
  - **Buttons:** B runs the scope's own close; LB/RB call `Widgets.Tabs` `:Step(±1)` (found with `Widgets.FindTabs(root)`); Y opens Monsters. A is never bound.
  - **Minigames:** a screen root with a string attribute `GamepadLegend` hides the cursor, and the screen reads the pad itself (Racing, Surf).
  - **Modal cards** (Dialog, InsetPopup, hatch reveal, evolution popup) call `Focus.push(root, close?)` while open.

Client bus topics (free-form, client only): `"Weather.Lightning"` `(strength 0..1)` published by Weather at each lightning flash (Soundscape times thunder to it); `"Tutorial.Arrow"` `(target: string?)` where the HUD exposes targets `incubator`, `jar`, `shop`, `monster`, `expeditions`, `weather`; `"World.FocusPlot"` `(plotIndex)`; `"Hud.Flash"` `(buttonName)`; `"Vfx.Burst"` `(name, { id }?)` where World takes `monsterLevelUp` (MonsterDetail) and `rebirth` (Rebirth). World plays every moment burst through `Celebrate:Moment`, so a burst fired under a screen or popup waits until the view clears.

### UI kit
`UI/Theme`, `UI/Create` (`New`, `Corner`, `Stroke`, `TextStroke`, `Padding`, `List`, `Grid`, `Shade`, `Text`), `UI/Anim` (`popIn`, `pulse`, `shake` (rotates inside list/grid layouts, which own Position), `countUp` (returns `stop()`), `bob`, `tween`), `UI/Layers`, `UI/Focus` (3.2: `push`, `remove`, `top`, `isShown`, `Changed`). `Router:Root(name)` returns a built screen's root. Components: `Button`, `Panel`, `Icon`, `Widgets` (`Pill`, `Bar`, `Chip`, `RarityChip`, `ElementChip`, `MutationChip`, `VariantChip`, `Scroll`, `List`, `Tabs`, `Countdown`, `Amount`), `Toasts`, `MonsterIcon` (`new`, `egg`, `silhouette`, `card`), `Shine` (`attach`: the Epic+ rarity glint). `UI/Art`: `Portraits` and `Icons` are packed art sheets generated by `tools/ui/atlas.py`, read through `Sheet` (`portrait`, `icon`, `find`); every lookup is nil until a sheet id is uploaded, so components keep their procedural drawing. Design size is 1100 × 560 (landscape phone); every tap target is at least 44 px.

### Visuals (art swap point)
- `Visuals/MonsterModel.Build(appearance, opts) -> Model` (contract in the file header). `opts.look` forces a 3D monster's texture look (Hall of Fame statues pass `"golden"`).
- `Visuals/MeshMonster`: 3D monsters (a published skinned mesh per form, rig data in `Visuals/MeshMonsters/<form>`), used by `MonsterModel.Build` when `Has(form)`. `Build(appearance, size, anchored, look?)`, `Pose(model, clip, t, loop)`, `BoneCFrame(model, bone)` (the current pose in Root space, from the rest chain and the last Transforms), `Slot(model, slot)` / `Attach(model, weld, slot)` / `Follow(model)` (accessories ride a Weld whose C0 follows the slot's bone; MonsterAnimator calls `Follow` after each `Pose`), `SetMeshSource(fn?)` (tests). The tap target is an invisible `Hit` box (World raycasts `Body` or `Hit`).
- `Visuals/MonsterLooks`: Golden / Rainbow / Shadow on 3D monsters as recoloured textures. `For(appearance)`, `Apply(mesh, form, look, textureId)` (never yields; one EditableImage per form and look, at most 8, least recently used dropped), `Recolor(look, pixels, width, height)` (pure, RGBA8), `SetBackend(fake?)` (tests). Without the EditableImage API the normal texture stays (one warn).
- `Visuals/EggModel.Build(eggType, opts) -> Model` (`opts.anchored`, `size`, `tint`, `vfx`), `SetCrack(model, 0..3)` (the hatch cracks), `SetReady(model, ready)` (World's READY glow), `Has(eggType)`. The shared egg mesh, a painted texture per egg, ornaments and crack overlays come from `tools/blender/eggs.py`; their ids live in `Visuals/EggAssets` and an egg without them is the placeholder. Egg sparkles are `Vfx.AttachEgg` (`Config.Vfx.Eggs`, `EggReady`).
- `Visuals/MonsterAnimator.new(model) -> animator` with `:Play(state)` (`idle|walk|happy|eat|attack|hurt|sleep`), `:SetBase(cframe)`, `:Destroy()`. One shared RenderStepped loop drives every animator. Owned by C1.
- World pools monster models by appearance, worn accessories included; Plots rebuilds a plot when a monster's `acc` changes.

### Particle effects (Vfx)
- Data: `Config/Vfx` holds every effect as emitter specs (keys and engine rules in its header): `Auras[element]`, `Mutations[id]`, `Variants.shiny/.rainbow`, `Rarity[rarityId]` (epic and up: a faint ground glow), `Landmarks[hubId | "skyGate"]`, `Bursts[name]` (`hatch`, `evolve`, `monsterLevelUp`, `ranchLevelUp`, `rebirth`, `coins`, `hearts`). Sprite ids are the GENERATED `Config/VfxSprites` (`[name] = { color, grey? }`, names from `art/vfx/SPRITES.md`, made with `tools/vfx`); a sprite not uploaded yet just skips its emitters.
- Runtime: `Visuals/Vfx` - `AttachMonster(model, appearance)`, `SetOwned(model, owned)`, `AttachLandmark(instance, id)`, `Burst(name, cframeOrPosition, { color?, scale?, elements? }?)` (pooled, `:Emit`), `SetQuality(low)`, `Clear(target)`, `Count(target)`. `MonsterModel.Build` attaches effects on the mesh and placeholder paths alike (`opts.vfx == false` skips: ViewportMonster, statues). The `Landmarks` controller attaches the hub buildings (on their Body, which World/Dress keeps) and the Sky Gate portal; World marks pen monsters own / other plot, routes `lowGraphics` to `SetQuality` and fires the moment bursts.
- Rules (`Vfx.spec` enforces them): daylight LightEmission 0.15 - 0.3 (portal cores may glow more), Size and Transparency are NumberSequences that fade in fast and out slow, live particles (rate x max lifetime) <= 8 per aura, <= 12 with two mutations, <= 60 per landmark. Low graphics: other plots' auras and glows off, mutation / variant / landmark rates and bursts halved.

### Audio
- **Data:** `Config/Sounds` maps every key to a plain id string or a table `{ id, volume?, pitch? = n | { min, max }, group? = "Effects"|"UI"|"Music"|"Ambience"|"Voice", cooldown?, maxConcurrent?, duck?, looped? }` (header has the defaults). An empty id is a placeholder: nothing is created or played, so the game is silent until ids are filled in, and a key lights up the moment it gets one. `Logic/Audio` holds the pure rules (entry resolution, toggle → group volumes, pitch picks, coin streak pitch, voice pitch, hatch / music fallback chains, ambience beds) and is unit-tested.
- **Kit (`client/Audio`):** `Attach` (from `ClientKernel.new`) makes SoundGroups `Music`, `Effects`, `UI`, `Ambience`, `Voice` under SoundService. Settings: Music and Ambience follow the `music` toggle, Effects, UI and Voice follow `sfx`. `Play(key, opts?)` is a pooled one-shot (`maxConcurrent` copies, oldest restarted; `cooldown`; pitch range) and positional with `opts.at` (Vector3 / part / attachment / model → an Attachment on `Workspace.AudioEmitters`, InverseTapered rolloff). Also `Chain(keys)` (first filled key), `Streak(key)` (a semitone higher per quick repeat, for coin ticks), `SetLoop(key, level, at?)` / `SetMusic(chain)` (crossfaded loops), `Duck` (a table entry's `duck` dips music under a sting), `Preload("UI")` (guarded `ContentProvider:PreloadAsync`), and `Override(key?)` for auditioning. `ctx:Sound(key, opts?)` is `Audio.Play`. Every `Button` clicks (`Sound` prop: another key or `false`; a disabled press plays `Locked`), `Widgets.Tabs` play `UITab`, the Router plays `UIOpen` / `UIClose`, error toasts play `Error`, a `*.Buy` through `StoreKit.request` plays `Purchase`.
- **Voices (`client/Audio/Voices`):** one family per Species archetype (`Voice<Archetype>`), pitched by stage, size and a fixed per-line offset (hash of the line id). `Cry(modelOrRecord, kind)` for `hatch` (Hatchery), `evolve` (Notifications), `levelUp`, `pet`, `happy` (World; happy is rate-limited per monster and overall); World `Track`s pen monsters and Soundscape asks `Chatter` for the closest few (3 within 50 studs, 1 within 28 with lowGraphics).
- **Soundscape controller:** twice a second derives the context — battle (a `BattleReplay` in UI.Top, or the Arena / Raids / Racing screen), Stampede (Boss screen), Sky Islands (`SkyIslands.IsOnIslands()`), hub (inside `World.HubRadius`), night and weather (`global.Weather`), event (`Events.ActiveId`) — and sets music (`Logic/Audio.MusicChain`: battle > Stampede > Sky Islands > event theme > hub > night > day, falling back to `MusicRanch`) and ambience beds (birds by day, crickets at night, wind up high, rain; a positional fountain loop at `World.Fountain`). One-shots: `RainStart`, `Thunder` just after each `"Weather.Lightning"`, `WindGust` on the islands.
- **Sound Check (Studio only):** when `RunService:IsStudio()`, Soundscape registers the `SoundCheck` screen (not in the Manifest) and a "Sound Check" button: every key by kind with its group, id or "empty", Play / Stop (voices at Baby / Teen / Adult pitch), and buttons that preview each music context (`Soundscape.Preview`).

### Photo mode
- **Screen `PhotoMode`** (non-modal; the HUD's 📷 under the gear, P, or D-pad up while nothing is open) and **controller `PhotoMode`**: the screen's Open / Close start and end a session (`PhotoMode:Begin(api)` / `:End()`), so every exit path restores the game the same way.
- A session hides our layers (except the toast lane and the pad legend), every other ScreenGui and BillboardGui, avatar name tags and the core GUI, takes the camera (Scriptable) and hands back its CameraType, CameraSubject, CFrame, Focus and FieldOfView; Lighting gets `PhotoModeColor` / `PhotoModeBloom` / `PhotoModeDepth`. Movement keys and sticks are sunk through ContextActionService only during a session.
- Camera maths are pure (`Logic/PhotoRig`), tuning and content in `Config/Photo` (required directly, like `Config/Vfx`). Low graphics skips heavy filters, bloom and depth of field; reduced motion snaps the camera and drops the shutter flash.
- `World:OwnMonstersNear(position, radius) -> { { model, animator } }` feeds Pose (`:Play("trick")`, else `"happy"`). CaptureService members are feature-checked (`PhotoMode:Capabilities()`); the photo button, Save and Share only show where they exist.

## 6. State shapes (binding)

These are the exact replicated shapes. Server systems must produce them; client screens read them. Arrays have fixed lengths where noted, and use `false` for empty values.

```lua
profile.Currency   = { coins, gems, stardust, friendship, treats, tokens = { [eventId] = n }, food = { sweet, spicy, savory, sour } }
profile.Progression = { level, xp }                     -- xp toward next level: Config.Unlocks.XPToNext(level); cap Unlocks.MaxLevelAt(now)
profile.Settings   = { music, sfx, lowGraphics, hideBroadcasts, language }   -- language (3.2): "auto" | "en" | "es" | "pt"
profile.Monsters   = { list = { [id] = Monster }, codex = { [lineId] = { forms = { [formId] = true }, variants = { normal|golden|rainbow = true }, count } }, nextId, grown }

profile.Eggs = {
  list = { [eggId] = { type = eggType, source = string, t = unix } },   -- eggId = "e<n>"
  slots = { [1..5] = { egg = eggId|false, type = eggType|"starter"|false, startedAt, endsAt } }, -- always 5 entries (4 before 3.2)
  nextId, pity = { starlit, royal }, hatched,
}
session.Eggs = { slotCount, speed }                     -- usable slots (1..5); total speed-up fraction

profile.Shop  = { window, bought = { [eggType] = n }, decor = { [decorId] = n }, themes = { [themeId] = true }, freeEggDay }
global.Shop   = { window, endsAt, stock = { [eggType] = n } } -- n = -1 means unlimited; only eggs purchasable now

profile.Ranch = {
  pens = { [1..owned] = { capacity, jarTier, jar, jarAt, monsters = { id }, decor = { decorId }, theme } },   -- owned ≤ 6
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
session.Expeditions = { slotCount, squadSize, caravan = CaravanLobby|false }   -- squadSize 3..5
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
  passCredit,                                            -- Ranch Passes paid for, banked for the next open season
}

profile.Monetization = { ads = { day, counts = { [placement] = n } }, once = { [productKey] = true }, vip = { day, opened } }   -- receipts: private; v2 adds vip
session.Monetization = { passes = { [passKey] = boolean }, paidRandomAllowed }
global.Monetization  = { vip = { ["u" .. userId] = true } }   -- VIP Rancher owners in this server (chat tags)

profile.HallOfFame = { entries = { { appearance, retiredAt, rarity, element } }, legacy = { [element] = pct }, upgrades = { [upgradeId] = level } }  -- newest first, ≤ 100
```

## 7. Shared formats fixed ahead of parallel work

### BattleReplay (produced by `Logic/BattleSim`, returned by `Expeditions.Fight`, drawn by the Expeditions screen)
```lua
BattleReplay = {
  win = boolean, turns = number, seed = number,
  units = { {                                   -- allies first, then enemies
    key = "a1".."a5" | "e1".."e5", side = "ally"|"enemy", slot = number,   -- up to "a8" in raids (maxAllies)
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
`Config.Quests.Seasons = { { season, name, startsAt, endsAt, xpPerTier, xpPerDaily, xpPerAchievement, tiers = { { free = { Reward }, premium = { Reward } } } } }`. The season in effect is `Config.Quests.PassAt(now)` (the latest one that has started), on the server and the client; `Config.Quests.Pass` still points at season 1 for old call sites. Claim with `Quests.ClaimPass { tier, track }`. Tier `n` needs pass XP ≥ `n × xpPerTier`. A player whose saved pass is from an older season gets a fresh pass on join.

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
  MailAdd(userId, entry) -> ok                   -- atomic append; skips an entry.id it has seen
  MailPeek(userId) -> ok, { entry }              -- fresh read, nothing removed
  MailAck(userId, { entryId }) -> ok             -- removes applied entries (ids remembered)
}
Services.PriceHistory = { Get(key) -> ok, record?, Update(key, transform) -> ok, record? }
```
Every call can fail (`ok == false`); systems must fail the action politely
("The market is busy. Try again") and never lose or duplicate an item.

Mail entry: `{ id, kind = "coins", amount, listing, key, price, name? }` (a sale, id `sale:<listing>`) or
`{ id, kind = "item", itemKind = "monster" | "egg", item = record, listing, reason }` (ids `return:<listing>`,
`bought:<listing>`). Ids are deterministic, so a retried delivery is skipped by the mailbox.

**Failure safety (after review).** Every cross-server step saves its intent first: the system
adds a task to the player's private `outbox` (`list` holding the escrowed item, `settle` holding
the charge, `close`), calls `ctx:SaveNow(player)`, then writes, then settles the task. An outcome
that is unknown (the write may have landed) is settled by a fresh read (an `Update` whose
transform writes nothing); if that fails too, the task stays saved and is settled on the next
sync, on any server, after a crash or a rejoin. Mail is collected in two phases (peek → apply and
remember ids → SaveNow → ack). See the header of `Systems/Market/init.luau`.

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
