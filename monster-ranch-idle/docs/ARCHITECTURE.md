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
- **Titan** (glow-up TT): scheduled, cross-server titan invasions on top of Boss. `Config.Titan.Schedule` is fixed dates (unix seconds); every server computes the same lobby/active window on its own clock (`Logic/Titan.Window`), so no messaging is needed for the schedule itself. The fight's HP is one pool shared by every server: `ctx.Services.Titan` (`Adapters.Roblox`: one MemoryStore hash map entry per schedule slot, keyed by its `startsAt`, expiring a day after its last write - a DataStore key would throttle every server writing it every few seconds) with `Get(key) -> (ok, record)` and `Update(key, transform) -> (ok, result)` (atomic `UpdateAsync`). Reports run off the scheduler's thread (`Services.Spawn`): the scheduler calls timers inline and must never wait on the network. Every `Config.Titan.ReportSeconds` each server folds its damage into the record with one `Update` (also recording its player count, keyed by `ctx.Services.JobId`, pruned after `StaleServerSeconds` and capped at `MaxServersListed` so the item stays small); if unreachable the server keeps fighting on a cached estimate (`Logic/Titan.Reconcile`) and retries. The titan falls once any server's view of the pool reads empty, or retreats if `Duration` runs out first (`Logic/Titan.Outcome`); every server reaches the same answer once it can reach the pool. `Titan:State() -> global table`, `:RegisterDamageModifier(key, fn(player) -> pct)`. Publishes `TitanJoined`, `TitanEnded`, `TitanDamage`; fires `Titan.Result`, and to every player `Titan.Starting` / `Titan.Started` (same shapes as Boss's). Rewards: everyone who joined and dealt damage (`Logic/Titan.Helped`) or cheered gets the usual participation rewards, fallen or retreated; a fallen titan adds a guaranteed Titan Egg for everyone who dealt damage (never a rank or chance roll, P5). The Stampede skips any period that overlaps an invasion (`Logic/Titan.Overlaps`, checked by Boss when its lobby would open), so the two giants never share the arena. VERIFY in a live server: MemoryStore request units with many servers in one invasion.

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

### Glow-up T: Companions, animated mounts
- **Companions** (rules `Logic/Companions`, tuning `Config/Companions`): action `Companions.Set { ids }` (≤ `MaxSlots`; each id own, not busy, not the ridden mount; at most `Slots` = 1, `VipSlots` = 3 with the `vip` pass). Save `profile.Companions = { ids }`, version 2 (v1 `{ id }` migrated). `global.Companions.walkers["u" .. userId] = { { id, appearance } }` (Monsters:Appearance, so a Mastery aura shows); pruned on `MonsterRemoved`, busy (`MonsterChanged`), `Mounted`; `PassesChanged` re-publishes; a lost pass keeps the save and draws the first slot. Public: `Companions:Of(player)`, `:Slots(player)`. Cosmetic only: no economy or battle effect.
- **Riding** gains `Riding:MountOf(player) -> monsterId?`.
- **Client:** controller `Companions` (follow, LOD, HUD badge; `PoseSubjects(position, radius, found)` feeds `World:OwnMonstersNear`, so photo mode's Pose reaches companions; `StateOf(userId, index)`, `ModelOf`, `Count` for tests), controller `Mounts` (poses every rider's welded `Mount`: walk / idle / hop from the root part's measured speed; `StateOf(userId)`, `SpeedOf(userId)`), `Visuals/Gait` (`new(model)`, `:Step(state, dt, speed) -> bob`, `:Play("trick"|"happy") -> boolean`, `:State()`: authored clips for a model its caller moves, walk clip rate from `Logic/Companions.ClipRate`), `UI/Screens/Parts/WalkToggle` (MonsterDetail's "Walk with me" / "Stop walking"; a full list drops its first entry).

### Glow-up R: Pens that grow
- **Data / rules:** `Config/Pens` (fence tiers by `jarTier`, `Upgrades` by `capacity`, `Themes[penThemeId]` = floor / rail materials + signature props, `Habitats[elementId]`, `Props[id]` = pieces + `spot` + `mesh`/`texture`/`meshSize`, `Garden`, `Budget`), `Logic/Pens` (`Fence`, `Upgrades`, `Theme`, `Dominant`, `Plan`, `Pieces`, `PartCount`, `CropStage`, `GardenKey`), unit-tested in `Pens.spec`.
- **Replication:** `global.Plots[i].pens[p]` gains `capacity`, `jarTier`; `global.Plots[i].garden` (`Ranch:PublicGarden`). Ranch publishes `PlotChanged` on `Ranch.Plant`, `Ranch.Harvest` and the garden upgrade (rain growth does not; the owner reads `profile.Ranch.garden`).
- **Client:** controller `Pens` (depends on World; handles Plots updates one deferred step after World paints theme colours) draws through `Visuals/PenDress`. It restyles each owned pen's `Floor` / `Rail*` / `Post*` in place and builds `Plot<i>.Pens.Pen<p>.Dress` (Model; attrs `FenceTier`, `Theme`, `Habitat`) and `Plot<i>.Garden`. All parts anchored, CanCollide / CanQuery / CanTouch / CastShadow off. Locked pens get their materials back and lose the Dress.
- **Spots for monster behaviour (contract):** under `Pen<p>.Dress`, a prop's anchor part carries `PropId`, `PenSpot` = `"food"` (trough) | `"water"` (pond, tide pool) | `"shelter"` (hut, shade tree, grove, shrooms, shards) | `"bed"` (hay nest, lava rocks, storm pad, boulders, sun shrine), and on the habitat `Habitat = elementId`. Its Position is the spot centre on the floor; every spot stays inside the pen floor. Garden beds: `GardenBed`, `CropStage` 0..4, `Flavor`; ready beds have a `Ready` glow part.
- `Pens.Stats() -> { builds, gardenBuilds, parts }` for tests.

### Glow-up O: Codex milestones, Codex Museum, Hall of Fame plaza
- **Codex**: action `Codex.Claim { milestone }` (rate 2; fails "That milestone doesn't exist", "Already claimed", "Find N more forms first"). Milestones come from `Logic/Codex.Milestones()` (built from Species / Eggs / Regions / Elements + `Config/Codex`); discoveries stay in `profile.Monsters.codex`, read through the new `Monsters:Codex(player)` (read-only). State `profile.Codex = { claimed, owed }` (badges private). Public: `Codex:Claimed(player)`, `:ClaimableCount(player)`. Publishes `CodexClaimed`.
- **Mastery** gains `Mastery:GrantItem(player, itemId, equipIfEmpty?) -> boolean`; `Config/Mastery` appends `Config.Codex.Items` (titles, aura `aura_codex_crown` -> `Config/Vfx` `Mastery.codexCrown`) to its Rewards, so Codex titles and the aura are equipped and shown like any Mastery cosmetic (one aura per monster).
- **Badges adapter**: `ctx.Services.Badges.Award(userId, badgeId) -> boolean` (`Adapters.Roblox` wraps `BadgeService:AwardBadge` in a pcall; may yield, so Codex calls it through `Services.Spawn`). Absent (tests) = badges skipped; a failed award is retried on the next join.
- **HallOfFame**: `global.HallOfFame.plaza["u" .. userId] = { slot, name, appearance, rarity }`, the best statue (`Logic/Museum.BestStatue`) of each player on the server, at most `Config.Codex.Plaza.max`, refreshed on join and retire, removed on leave (a waiting player takes the freed slot).
- **Client**: controllers `CodexMuseum` (walk-in hall, `Logic/Museum.Layout` / `Plan` / `newPool`, `Stats()` for tests) and `FamePlaza` (`Stats()`); both skip the hub place. The Codex screen takes `{ tab = "milestones" }`. `Config.World.CodexGrounds` keeps scenery off both grounds.

### Glow-up LR: Live races, racing gear
- **LiveRace** (`Config/LiveRace`, `Logic/LiveRace`): up to `MaxRiders` (6) riders race their mounts round the world track. One heat at a time: `idle -> lobby (LobbySeconds, or FullSeconds once full) -> countdown (3-2-1-GO) -> running -> podium (PodiumSeconds) -> idle`; under `MinPlayers` (2) human riders, ghosts from Monster Racing (`Config.Racing`) fill the field. Actions `LiveRace.Join {} -> { heat, lane }` (must be riding an Adult), `LiveRace.Leave {}`, `LiveRace.Progress { heat, x, z, drift } -> { accepted, x, z, progress, lap, meter, finished }` (the server projects the report onto the centreline and refuses one that leaves the track or moves farther than `Logic.Allowed` permits: a strike, snapped back; `MaxStrikes` disqualifies), `LiveRace.Jump { heat } -> { ok }`, `LiveRace.Boost { heat } -> { meter, seconds }`. Checkpoints credit in order from the accepted distance only, so a lap cut short or run backwards never counts. Pays through `Racing:Award` (the same daily cap and Cup points as 2D racing; `Racing:Award(player, { place, time, finished, live, riders }) -> { rewards, cup }`; a rider still racing when the heat ends is paid like the last reward row). `LiveRace:Heat() -> heat record`, `LiveRace:IsRacing(player) -> boolean`.
- **RaceGear**: cosmetic saddles, trails and banners (`Config.LiveRace.Gear`, `GearKinds`), earned from milestones (`races`, `live`, `podiums`, `wins`, `duels`; subscribes to `RaceFinished`) and shown on the mount. Action `RaceGear.Equip { kind, item }` (`item = ""` takes the kind off). Public: `RaceGear:Grant(player, id) -> boolean`, `RaceGear:Equipped(player)`.
- **Client**: controller `LiveRace` (`Visuals/RaceTrack` draws the decorative track; the local rider is driven by the same `Logic.NewRider` / `StepRider` prediction used for the 2D Racing screen's runner, its root part anchored and moved by script — a rail, not free physics, since the server checks distance by projection, not collision; a self-contained chase camera, saved and restored like `CameraDirector`; jump/boost keys and gamepad; drawing racing gear on every mount from `global.RaceGear.here`). The `Racing` screen's lobby offers "Join Live Race" (while riding an Adult) alongside the existing 2D fallback (kept for Low quality, a busy track, and tests).

### Glow-up Q: Bond
- **Bond** (numbers in `Config/Bond`, rules in `Logic/Bond`): action `Bond.Care { id, kind }` (kind `pet|brush|play`; own pen monster, each kind off its per-monster cooldown, `minGap` between cares) -> `{ hearts, points, gained, learned }`. Save `profile.Bond = { list = { [monsterId] = { pts, pet?, brush?, play? } }, cares }` (v1, `Migrate` = `Logic/Bond.Sanitize`). Global `global.Bond.here["u" .. userId] = { best, plates }`. Public: `Bond:Hearts(player, id)`, `Bond:Points(player, id)`. Topic `BondRaised`. Bond is keyed by monster id and deleted on `MonsterRemoved`, so it never travels with a trade; it never decays.
- **Ranch** gains `RegisterMonsterRateModifier(key, fn(player, monster) -> pct)`: an additive bonus on one monster's own coin rate (Bond's "bond", at most +5%).
- **Community**: a trick with a `bond` field (`Config/Bond.Tricks`, merged into `Config.Community.TrickById` but not `Tricks`) needs that many hearts on the monster; the emote wheel is unchanged.
- **Client**: controller `Care`, screen `Care` (non-modal, `{ id }`); `World.OwnTapHandler(id) -> handled` (set by Care; an own-monster tap falls back to MonsterDetail without it), `World.PlayCare(id, state, hearts) -> Model?`, `World.MonsterModel(owner, id) -> Model?`; `Screens/Parts/BondBadge`.

### Glow-up U: The Stampede, live
- **Boss** adds `global.Boss.squads = { { userId, looks = { { line, form, stage, rarity, variant } } } }` (render-only, no monster ids): filled on `Boss.Join` in join order, at most `Config.Boss.Arena.squadPlayers` players and `squadPerPlayer` looks each, cleared when the next lobby opens. Damage, HP, cheer and rewards are unchanged.
- **Place**: `Config.World.StampedeArena = { center = { x, z }, radius }` (east of the Expedition Gate), also in `World.Scenery.keepOut`. Tuning in `Config.Boss.Arena`; pure rules in `Logic/StampedeArena` (`Rings`, `Pick`, `AttackOffset`, `Crossed`, `newPacer`, `Approach`, `MaxMonsters`).
- **Client**: controller `StampedeArena` draws the arena, the giant (`MonsterModel.Build` at `bossScale`), every squad in rings, cheer bolts and the loot fountain from replicated state, plus a stacked `ColorCorrectionEffect` "StampedeStorm" in Lighting during the lobby and fight (the Weather and Sky controllers never write it; it is destroyed when it fades out). Public: `StampedeArena:Live() -> boolean` (Soundscape plays `MusicStampede` meanwhile), `StampedeArena:Fountain(payload, done(rewarded)) -> boolean` (Broadcasts hands it `Boss.Result` first; `true` = it will call `done` once, after the fountain), `StampedeArena.Stats()` (tests). Its HUD buttons Cheer (sends `Boss.Cheer`) and "To the arena" (`Boss.Join` if unlocked, then moves the character) show only with no screen open.
- **Client (Titan, glow-up TT)**: controller `TitanInvasion` is event-driven (`Titan.Starting`/`Titan.Started` open the banner; state polling only drives the bar, the giant and cleanup, so closing the banner never reopens it on its own). Draws one stationary giant at the same arena spot (`Config.Titan.Arena.bossScale`, its own "TitanStorm" effect); no squads or cheer bolts (scope cut - see the packet report). The banner doubles as the shared bar: `global.Titan.hp/maxHp` and "{servers} · {players} fighting". `Titan.Result` is handled by `Broadcasts` (its own popup; no in-world fountain for the titan). Public: `TitanInvasion:Stats() -> { phase, giant: boolean, storm: number }` (tests).

### Glow-up X: Postcards from expeditions
- **Postcards** (numbers/scenes in `Config/Postcards`, rules in `Logic/Postcards`): a card is recorded on `ExpeditionClaimed` (region, stage, squad, loot; `ExpeditionClaimed` now also carries `region`, `stage`, `squad`, `loot`), never changing the reward. `profile.Postcards` (v1): `cards = { [cardId]: Card }`, `seq`, `day`/`sent`/`to` (daily send caps), `totalSent`, `totalReceived`, `recv` (private, dedup for received mail). `Card = { id, n, region, stage, at, line, hero, squad = { SlimAppearance }, loot, fav, from, sent = { userId } }`. Album keeps newest `perRegion` non-favourites per region + up to `maxFavourites` favourites, capped overall at `maxTotal` (`Logic/Postcards.Trim`, oldest non-favourite drops first). Actions: `Postcards.Favourite { card, on } -> { fav, kept }`, `Postcards.Send { card, to } -> { left }` (send uses `Gifts:Gate` for the sender/friend checks, its own `Config.Postcards.Send` daily cap counted through `Logic/Community.DailyLeft`, at most `maxSentPerCard` friends per card). Public: `Postcards:Album(player) -> { Card }` (newest first), `Postcards:Record(player, detail) -> Card?`.
- **Gifts** gains `Gifts:Gate(player, to) -> (ok, why?, need?)`: the sender-eligibility (`"level"|"play"|"account"`) and friend (`"friend"`) checks shared with Postcards, without the gift daily caps.
- **Market mail**: kind `"postcard"` (`{ id = "postcard:<senderId>:<cardId>", kind, card, from, fromName }`), registered by `Postcards.Start`; delivered once per mail id, a malformed card is dropped, arrives as "From `<name>`" (or "A friend").
- **Client**: controller `Postcards` (queues a new own postcard as a card dialog: Flip, ★, Send, Album, dismiss; friends already-seen cards never pop up again) and `Parts/PostcardView` (`.new(card, opts)` draws the front as one ViewportFrame — sky gradient, a per-region backdrop from `Config.Postcards.Scenes`, the squad's real `MonsterModel.Build`s posed happy/cheer/sit — and the back as loot/date/sender; `.tile(card, opts)` is the album's static, non-viewport card). Screen `Album` (`{ region? }`, opened from Expeditions' Album button or a postcard's own Album button): tabs per region with a postcard, tiles redraw from data, tap opens the live card, ★ toggles favourite from the grid.

### Glow-up W: Titanic, numbered limited editions
- **Titanic** (`Config/Titanic`, rules in `Logic/Titanic`): the size tier above Huge. One draw still decides Huge, so glow-up W split the old 1% Huge roll instead of adding a second one — `MonsterGen.RollSize(rng, lineId) -> (weight, titanic)` replaces `RollWeight` (kept as a thin wrapper) and every seeded roll after it is unchanged. A roll below `Titanic.Chance` (well under `HugeChance`) is Titanic: 2.2×-2.5× the line's average weight, record flag `titanic = true`, `Appearance.Of` field `titanic`. Looks only — `Logic/Titanic.SizeMult(appearance, inPen?)` (Scale ≈ 3×, `PenScale` 2.2× inside a pen so it stays inside the fence; `MonsterModel.Build(appearance, { inPen = true })` from `World.acquireModel`), `Logic/Audio.VoicePitch` takes it lower (`Titanic.CryPitch`), `Config/Vfx.Titanic` is its aura (within `Budget.titanic`), `Config.Titanic.Celebration` is the Hatchery's bigger reveal. Never rolled by breeding (a given `weight` skips the draw) or on a forced spec (`spec.titanic`, for grants/tests). No stat, coin-rate or sell-price change (`Formulas` ignore it). `TITANIC` chip via `UI/Screens/Parts/ShowpieceChips`.
- **Editions** (`Config/Editions`, rules in `Logic/Editions`, system `Systems/Editions`, depends on `Monsters`): every `Config.Species` line tagged `event` is a limited line. A monster of that line created by a minting source (`Config.Editions.Sources`: `hatch`, `reward`) is marked `ltd = lineId`, `ltdOf = size` on `MonsterCreated`, then numbered off a spawned task against an atomic counter: `ctx.Services.Editions.Claim(editionId, size) -> ok, n?` if present, else `ctx.Services.DataStore:Update("Edition_" .. id, Logic.Claim)` (the profile store), `Config.Editions.Attempts` tries per pass. A store that is down leaves the monster granted and `ltdNo = nil` (pending): retried every `Config.Editions.RetrySeconds` for players on this server and on every join, so it is never lost or numbered twice; a claim whose outcome is unknown burns a number (a gap) rather than risking a duplicate. Full edition: the claim returns no number, `ltd`/`ltdOf` are cleared (ordinary monster from then on, this server remembers via `soldOut`). Bred, traded, bought and listed monsters keep all three fields as copied by `Monsters:Insert` — a number is minted once and travels with the record, never re-minted on arrival. Public: `Editions:Pending(player) -> number`, `Editions:NumberPending(player) -> number` (numbers everyone pending now, returns remaining). Subscribes `MonsterCreated`; no actions, events, state roots or bus topics of its own. `Editions.Label(m) -> "#37/500"?` and the `LIMITED` chip (pending) via `ShowpieceChips`; pen nameplate tag via client controller `EditionPlates` (own plot, low graphics; billboard at the model's feet from `global.Plots[].pens[].monsters[].appearance`).
- **Editions adapter**: `ctx.Services.Editions.Claim(editionId, size) -> ok, n?` — `Adapters.Roblox` keeps one counter per edition in the `MonsterRanch_Editions_v1` DataStore and claims with `UpdateAsync` (atomic across servers; the same rule as `Logic/Editions.Claim`; a full edition writes nothing). It is nil when that store can't be opened, and then Editions falls back to `Services.DataStore:Update("Edition_" .. id, ...)` (the profile store). `MockAdapters` has no Editions adapter (the fallback is what the default tests run); `tests/specs/Editions.spec.luau` builds a `MockAdapters.network()`-backed fake for its cross-server specs.
- Fair (P5): every limited line is earnable for free (an event egg bought with tokens or coins, checked by `Editions.spec`), never gated behind Robux; Titanic odds are shown with every egg's odds (`EggShop`).

### Glow-up Y: Visits (likes that pay, the crown, ranch visits, Ranch of the Week)
- **Data / rules:** `Config/Visits` (like rewards + daily caps, the like gate `Config.Visits.Gate`, crown look, snapshot limits, showcase / stage world spots, `Visits.Visit.teleportWaitSeconds`), `Logic/Visits` (`Build`, `Sanitize`, `Fit`, `Encode`/`Size`, `Leader` (crown, ties by earliest), `Monsters` (a snapshot's showiest, for the stage)), unit-tested in `Visits.spec`.
- **Likes that pay:** `Social.Like` (a gate on this server) now also publishes `RanchLiked`, which Visits pays from — the liker and the owner once per pair per UTC day, gated by `Logic/Community.GiftGate` (Ranch Level, play time, account age; same shape as the Gifts gate) so a fresh alt can't farm rewards, and capped separately per day for likers and owners. A liker who fails the gate still likes (Social's counter, the crown and the weekly board are unaffected). `Social:AddLike` credits a snapshot like's mailed reward to the owner's `likes` counter.
- **The crown:** counted likes received on this server today (module state; a UTC day resets it) crown the leading ranch's plot (`global.Visits.crown = { userId, plot, likes, name }`, ties go to whoever reached the count first); a new holder gets a toast. Drawn client-side over the plot's gate, live (the client re-reads the plot on every `global.Plots` / `global.Visits` change) and spinning every frame.
- **Visiting:** `Visits.Visit { userId, snapshot? }` on a Roblox friend: on this server → their plot number; on another server of the universe (optional `Services.Ranches.Locate` + `Services.Teleport.ToServer`) → a teleport; offline, a full server, or asked again with `snapshot = true` → their saved snapshot (`Services.Ranches.Load`) into `session.Visits.showcase`, drawn only for the visitor by `Visuals/RanchShowcase` at `Config.Visits.Showcase` near the hub. `Visits.Like` on an open showcase snapshot pays the visitor and mails the owner (`Market:Send`, kind `Config.Visits.Likes.mailKind`) so their reward and weekly count land on their next join or sync, wherever they are. `Visits.Leave` closes it.
- **Snapshots:** built from `Plots:Public(player)` (new public method, same shape as `global.Plots`) plus each pen monster's `Bond:Hearts` for the best-friends list; sanitised and trimmed to `Config.Visits.Snapshot.maxBytes` (monsters dropped from the fullest pen first, then best friends, then decor) before saving. Saved on `PlayerRemoving` and every `Snapshot.saveSeconds` while playing, skipped when unchanged (`Logic/Visits.Encode` as the change key).
- **Ranch of the Week:** the weekly board `ranchlikes` (`Config.Leaderboards`, `Visits:WeekLikes`) ranks likes received; every `Stage.refreshSeconds` each server re-reads last week's #1 (`Services.Leaderboards.Top`), loads their snapshot and publishes `global.Visits.stage = { week, userId, name, likes, monsters }` (showiest monsters, `Logic/Visits.Monsters`) for the hub stage.
- **Ranches adapter** (`Adapters.Roblox`; nil when its store can't be opened, and then visits, saves and the stage are off while the crown and likes-that-pay on this server still work):
  ```lua
  ctx.Services.Ranches = {
    Save(userId, snap) -> ok                    -- SetAsync on MonsterRanch_Ranches_v1, key "u"..userId, tagged with the userId
    Load(userId) -> ok, snap?                   -- GetAsync
    Locate(userId) -> ok, { placeId, jobId }?   -- TeleportService:GetPlayerPlaceInstanceAsync (nil = not playing here)
  }
  ```
  A save that errors or returns false is tried again at the next save point. `MockAdapters` has none (the specs install a network-backed fake).
  Ranch visits also use the existing `Services.Players.IsFriendsWith`, `Services.Teleport.ToServer` and `Services.Leaderboards.Top`.
- **Public API:** `Visits:WeekLikes(player)`, `Visits:Crown() -> userId?`, `Visits:SaveSnapshot(player) -> boolean`.
- **Client:** controller `Visits` (crown model + spin, the Visiting Showcase bar (Like / Go there / Leave), the Ranch of the Week stage, models built only near the camera), `Visuals/RanchShowcase.Build(snap, origin, opts?) -> (Model, stats)` (a compact ranch drawn with the real `PenDress` plan). Friends screen row "Visit ranch" (`ctx:GetController("Visits").Visit(userId, name)`).

### Glow-up Z: Build your ranch (free decor placement)
- **Data**: `Config/Decor` (60+ pieces plus the pre-glow-up-Z mood set, `Layout` tuning: `grid`, cap by
  Ranch Level, `keepOut` rects, pen `penInset`/`penOutset`/`propClear`, `legacySpots` for migration,
  night `lights`, LOD distances), `Config/DecorArt` (`Models[modelId](a, b, def) -> { piece }`, parts
  only, `maxParts` budget; a piece with a non-empty `mesh` id draws as one part instead, the art swap
  point). Pieces carry `kind` (tray tab), `spot = "toy"` (pen monsters play there, like `Config.Pens`
  spots), `light` (lit at night), `starter` (free copies granted once), `event`/`set` (Store grouping).
- **Rules** (`Logic/DecorLayout`, pure, unit-tested): `Cap(level)`, `Half(def, rot)`, `Check(entry)`,
  `Overlaps`, `Problems(list)` (placement mode's red), `Validate(list, level, available)`,
  `PenOf(entry)`, `PenDecor(list, pen, perPen)` (mood pieces standing in a pen, Config.Decor.PerPen
  best first), `FreeSpot`, `Migrate(pens, list)` (old `Ranch` pen-slot decor onto the layout at the old
  slot spots or the nearest free spot), `Clean`, `Same`.
- **Decor** (server, depends on Progression + Shop, optionally Ranch): save `profile.Decor = { layout
  = { { id, x, z, rot } }, migrated, starter }` (plot-local grid units, `rot` 0..7 × 45°). On
  `PlayerReady`: grants the starter set once (`Shop:AddDecor`), then moves any old `Ranch` pen-slot
  decor onto the layout once (`Ranch:TakePenDecor`; leftovers return to storage). Action `Decor.Save
  { layout }` re-validates ownership (storage + already placed), bounds/overlaps/pen-rails and the
  cap, taking/returning `Shop` decor to match; failures change nothing. Public: `Decor:Layout(player)`,
  `:PenDecor(player, pen)`, `:Placed(player, decorId)`. Publishes `PlotChanged`.
- **Ranch** gains `Ranch:TakePenDecor(player) -> { [pen]: { decorId } }` (empties the old pen slots for
  the migration) and reads the Decor layout's `PenDecor` into its mood-aura pass alongside any
  remaining pen-slot decor.
- **Replication**: `global.Plots[i].layout = { { id, x, z, rot } }` (`Decor:Layout`, `Plots` optional
  dependency).
- **Client**: controller `Decor` (draws every plot's layout with `Visuals/DecorModel`, diffed by key;
  own plot full detail, other plots drop `small` parts past `farDistance` and stop drawing past
  `hideDistance`; night lights on `light` pieces, a pooled few nearest the camera) and its placement
  mode (`Decor.Enter/Exit`, a draft copy of the layout, `Add/Select/MoveTo/Nudge/Rotate/Remove/Undo`,
  `Save` posts `Decor.Save`; touch, mouse and gamepad input; hides the HUD and looks down on the own
  plot). Screen `Decorate` (non-modal; tray tabs by `kind`, Rotate/Remove/Undo, Save/leave) opened from
  the HUD's 🔨 button and the Ranch screen's "Build your ranch" (which replaces the old per-pen decor
  picker; `Ranch.PlaceDecor` still exists for the migration path).

### Glow-up DR: Deep Reef and swimming mounts
- **Data (`Config/Regions`, `Config/Species`, `Config/Eggs`)**: region `"reef"` (order 8, `unlock = "region_reef"` at Ranch Level 64, `opensAt` Sat 1 Jul 2028 15:00 UTC), gated the same way as every other region (`Regions.IsOpen`; no new server system). Three Tide lines (Finnip, Glowray, Shellkin), each `swims = true`, hatch only from the new Reef Egg (`pool = "reef"`); Codex element/egg/region milestone tracks come for free from the existing content-driven rules (`Logic/Codex`).
- **`Config/DeepReef`** (client-only content, like Codex Museum / Fame Plaza: no state, actions or bus topics): `Dock` / `Area` / `Props` / `Counts` (placeholder geometry inputs for `Visuals/ReefBuild`), `Swim` (tuning for `Logic/Swim`), `Swimmers` + `DeepReef.Swims(lineId) -> boolean` (true for a line with `swims = true` or already listed here — every Tide-adjacent line since 1.1's Coral Depths), `Light` (the underwater `ColorCorrectionEffect` + Atmosphere override, and the `Ambience_<layer>` switches it turns off while inside), `Life` (kelp / bubbles / fish / light shaft budgets, `max` / `maxLow`).
- **`Logic/Swim`** (pure, unit-tested in `Swim.spec`): `Inside`, `Clamp`, `Speed(riding, swims, rideSpeed, cfg)` (a swimmer mount rides at `rideSpeed × mountFactor`, never below `speed × mountMin`; a non-swimmer mount gives no boost), `Target` (stick/keys flat, ascend/descend, camera pitch follow when swimming forward, idle buoyancy), `Approach`, `Step` (eases velocity, moves, clamps, kills velocity into a wall), `Heading`, `Tilt`, `Bob`, `ClipSpeed` (a mount's walk clip slowed into strokes).
- **Client:** controller `DeepReef` (depends on `Weather`) builds the Dive Dock and the Area once (main place only, via `Visuals/ReefBuild`) and layers `Visuals/ReefLife` (kelp sway, vent bubbles, fish schools, static light shafts, rebuilt on a `Quality` change) onto it. The Dive pad teleports in, sets the humanoid `PlatformStand` + `AutoRotate false`, calls `Weather.Hold(true)` and switches off the Sky / Critters ambience layers before applying its own light; the Return pad (Surface Bell) and a respawn undo all of it (`Weather.Hold(false)` lets Weather's own `RenderStepped` step re-apply everything next frame). While swimming, a Heartbeat steps `Logic/Swim` from `Humanoid.MoveDirection`, Space/Ctrl (or the triggers) for ascend/descend and the camera's pitch, and writes the root part's CFrame directly. The Reef Gate portal opens Expeditions on `{ region = "reef" }`, same as the Sky Gate. Public: `DeepReef.IsInside() -> boolean` (Soundscape's `reef` state); `Config.DeepReef.Swims` is what `Controllers/Mounts` reads to give a mounted swimmer's gait the slowed "strokes" clip instead of a walk inside `Logic/Swim.Inside`'s bounds (mounts pose only; the swim controller above moves and tilts the rider). `DeepReef.spec` (data), `DeepReefClient.spec` (dive, swim, mount a swimmer, gate, and swim home with every override restored).

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
| `Codex` | C2 | `{ tab? = "species"|"milestones" }` (glow-up O) |
| `Expeditions` | C3 | `{ region? }` |
| `Breeding` | C3 | — |
| `Trade` | C3 | — |
| `Boss` | C3 | — |
| `HallOfFame` | C3 | — |
| `Quests` | C3 | `{ tab? }` |
| `Store` | C3 | `{ tab? = "food"|"decor"|"passes"|"gems"|"codes" }` |
| `Settings` | C3 | — |
| `Decorate` | glow-up Z | — (non-modal; placement mode's toolbar and tray) |

Controllers: `Hud`, `Notifications`, `Hatchery` (C2) · `Tutorial`, `Broadcasts`, `TradeRequests` (C3) · `World`, `Weather`, `Interaction` (C1) · `Localize`, `Gamepad` (3.2) · `Soundscape` (audio) · `ChatTags` (VIP chat tag) · `Celebrate`, `Stampede`, `PhotoMode`, `DailyLogin`, `Community` (glow-up) · `CameraDirector`, `Cinematics` (glow-up N) · `Sky`, `Lamplight`, `SceneryMotion`, `Critters` (ambience).
Controllers: `Hud`, `Notifications`, `Hatchery` (C2) · `Tutorial`, `Broadcasts`, `TradeRequests` (C3) · `World`, `Weather`, `Interaction` (C1) · `Localize`, `Gamepad` (3.2) · `Soundscape` (audio) · `ChatTags` (VIP chat tag) · `Celebrate`, `Stampede`, `StampedeArena`, `PhotoMode`, `DailyLogin`, `Community` (glow-up) · `Sky`, `Lamplight`, `SceneryMotion`, `Critters` (ambience).
Controllers: `Hud`, `Notifications`, `Hatchery` (C2) · `Tutorial`, `Broadcasts`, `TradeRequests` (C3) · `World`, `Weather`, `Interaction` (C1) · `Localize`, `Gamepad` (3.2) · `Soundscape` (audio) · `ChatTags` (VIP chat tag) · `Celebrate`, `Stampede`, `PhotoMode`, `DailyLogin`, `Community` (glow-up) · `Sky`, `Lamplight`, `SceneryMotion`, `Critters` (ambience) · `Decor` (glow-up Z: plot decor + placement mode).

- **Layers:** `ctx.UI.Hud`, `Screens`, `Overlay`, `Top` and `Feedback` (glow-up), in that drawing order. `Feedback` holds the feedback queue, flying rewards and the Stampede banner, so feedback is never hidden behind the popup it is about.
- **Feedback queue (`UI/Components/Toasts`):** toasts and reward cards share one stack above the bottom bar. `Toasts.show(text, kind, seconds?)` (`ctx:Toast`), `Toasts.push(gui, seconds?) -> dismiss()`, `Toasts.dismiss(gui)`. At most 4 items; they pop in, shrink out, and a repeated toast refreshes the one showing.
- **Celebrate (glow-up):** one API for every reward that lands and every celebration. Sizes `small | medium | big | huge` come from `Logic/Celebration` (`Size(items, income)`, `CoinSize`, `GemSize`, `Plan(size, low)`, `TickKey`).
  ```lua
  Celebrate:Reward(items, { from?, size?, minSize?, hold?, label? }) -> size  -- fly to the HUD counters
  Celebrate:Hold({ "coins" | "gems" | "food" }) -> handle     -- before a request; handle:Release(kind?, seconds?)
  Celebrate:Play(size, { sound? })        -- shower + confetti (big+), camera shake + FOV kick (huge), rumble, sound
  Celebrate:CountUp(label, from, to, size, format) -> stop
  Celebrate:Shockwave(gui, color?)  ·  Celebrate:Slam(gui, color?)  ·  Celebrate:Flourish(gui?)
  Celebrate:Moment(key, fn, { settle?, flourish?, at? })  -- hold an in-world moment while the world is covered
  Celebrate:IsCovered() -> boolean  ·  Celebrate:Pending() -> number
  ```
  `from` is a GuiObject, a world position (BasePart, Vector3, CFrame; projected through the camera) or a Feedback-layer `Vector2`. "Covered" means a Router screen is open, a `UI/Focus` modal is up, the hatch reveal (or the in-world hatch) is showing, or a CameraDirector shot has the camera. Low graphics keeps the counters and a short "+N" cue and drops swarms, shake, FOV kick, shockwaves and sparkles. New sound keys: `CoinTick1`..`CoinTick5`, `GemTick`, `ItemPop`, `Whoosh`, `StarUp`, `CelebrateBig`, `CelebrateHuge`, `StampedeSoon`.
- **Hud counters (glow-up):** `Hud:HoldCounter(kind)`, `:ReleaseCounter(kind, seconds?)`, `:PulseCounter(kind)` for `coins`, `gems`, `food`; `Hud:GetTarget` also returns `coins`, `gems`, `food` and `level`.
- **Stampede (glow-up):** `Boss.Starting` and `Boss.Started` show a banner on the Feedback layer to everyone (Join opens the Boss screen when unlocked) and play `StampedeSoon` / `BossHorn`. `Stampede:Banner() -> GuiObject?`. The HUD's Stampede card glows and shows a badge while the fight is in its lobby or live.

- **Localize (3.2):** watches every TextLabel / TextButton (and TextBox placeholder) under the PlayerGui and the Workspace. It keeps the English a text object was given (`Localize:Source(obj)`) and shows `Locale.Translate` of it. A longer translation is shrunk to no more than the English's room (not below 75 %). Opt out with the attribute `Localize = false`. It is first in the client Manifest.
- **Gamepad (3.2):** dormant until the last input comes from a pad.
  - **Scope:** the topmost `UI/Focus` modal, else the open Router screen. It gets `SelectionGroup` with `Stop` edges. The cursor goes to the last or first control, level-triggered every frame.
  - **Buttons:** B runs the scope's own close; LB/RB call `Widgets.Tabs` `:Step(±1)` (found with `Widgets.FindTabs(root)`); Y opens Monsters. A is never bound.
  - **Minigames:** a screen root with a string attribute `GamepadLegend` hides the cursor, and the screen reads the pad itself (Racing, Surf).
  - **Modal cards** (Dialog, InsetPopup, hatch reveal, evolution popup) call `Focus.push(root, close?)` while open.

Client bus topics (free-form, client only): `"Weather.Lightning"` `(strength 0..1)` published by Weather at each lightning flash (Soundscape times thunder to it); `"Tutorial.Arrow"` `(target: string?)` where the HUD exposes targets `incubator`, `jar`, `shop`, `monster`, `expeditions`, `weather`; `"World.FocusPlot"` `(plotIndex)`; `"Hud.Flash"` `(buttonName)`; `"Vfx.Burst"` `(name, { id }?)` where World takes `monsterLevelUp` and `monsterStarUp` (MonsterDetail; both first offered to `Cinematics:Spotlight`) and `rebirth` (Rebirth). World plays every moment burst through `Celebrate:Moment`, so a burst fired under a screen or popup waits until the view clears.

### UI kit
`UI/Theme`, `UI/Create` (`New`, `Corner`, `Stroke`, `TextStroke`, `Padding`, `List`, `Grid`, `Shade`, `Text`), `UI/Anim` (`popIn`, `pulse`, `shake` (rotates inside list/grid layouts, which own Position), `countUp` (returns `stop()`), `bob`, `tween`), `UI/Layers`, `UI/Focus` (3.2: `push`, `remove`, `top`, `isShown`, `Changed`). `Router:Root(name)` returns a built screen's root. Components: `Button`, `Panel`, `Icon`, `Widgets` (`Pill`, `Bar`, `Chip`, `RarityChip`, `ElementChip`, `MutationChip`, `VariantChip`, `Scroll`, `List`, `Tabs`, `Countdown`, `Amount`), `Toasts`, `MonsterIcon` (`new`, `egg`, `silhouette`, `card`), `Shine` (`attach`: the Epic+ rarity glint). `UI/Art`: `Portraits` and `Icons` are packed art sheets generated by `tools/ui/atlas.py`, read through `Sheet` (`portrait`, `icon`, `find`); every lookup is nil until a sheet id is uploaded, so components keep their procedural drawing. Design size is 1100 × 560 (landscape phone); every tap target is at least 44 px.

### Visuals (art swap point)
- `Visuals/MonsterModel.Build(appearance, opts) -> Model` (contract in the file header). `opts.look` forces a 3D monster's texture look (Hall of Fame statues pass `"golden"`).
- `Visuals/MeshMonster`: 3D monsters (a published skinned mesh per form, rig data in `Visuals/MeshMonsters/<form>`), used by `MonsterModel.Build` when `Has(form)`. `Build(appearance, size, anchored, look?)`, `Pose(model, clip, t, loop)`, `BoneCFrame(model, bone)` (the current pose in Root space, from the rest chain and the last Transforms), `Slot(model, slot)` / `Attach(model, weld, slot)` / `Follow(model)` (accessories ride a Weld whose C0 follows the slot's bone; MonsterAnimator calls `Follow` after each `Pose`), `SetMeshSource(fn?)` (tests). The tap target is an invisible `Hit` box (World raycasts `Body` or `Hit`).
- `Visuals/MonsterLooks`: Golden / Rainbow / Shadow on 3D monsters as recoloured textures. `For(appearance)`, `Apply(mesh, form, look, textureId)` (never yields; one EditableImage per form and look, at most 8, least recently used dropped), `Recolor(look, pixels, width, height)` (pure, RGBA8), `SetBackend(fake?)` (tests). Without the EditableImage API the normal texture stays (one warn).
- `Visuals/EggModel.Build(eggType, opts) -> Model` (`opts.anchored`, `size`, `tint`, `vfx`), `SetCrack(model, 0..3)` (the hatch cracks), `SetReady(model, ready)` (World's READY glow), `Has(eggType)`. The shared egg mesh, a painted texture per egg, ornaments and crack overlays come from `tools/blender/eggs.py`; their ids live in `Visuals/EggAssets` and an egg without them is the placeholder. Egg sparkles are `Vfx.AttachEgg` (`Config.Vfx.Eggs`, `EggReady`).
- `Visuals/MonsterAnimator.new(model) -> animator` with `:Play(state)` (`idle|walk|happy|eat|attack|hurt|sleep`, plus `sit|trick|faint` and glow-up S `shake|shiver`), `:SetBase(cframe)`, `:Destroy()`. One shared RenderStepped loop drives every animator. Owned by C1.
- World pools monster models by appearance, worn accessories included; Plots rebuilds a plot when a monster's `acc` changes.

### Particle effects (Vfx)
- Data: `Config/Vfx` holds every effect as emitter specs (keys and engine rules in its header): `Auras[element]`, `Mutations[id]`, `Variants.shiny/.rainbow`, `Rarity[rarityId]` (epic and up: a faint ground glow), `Landmarks[hubId | "skyGate"]`, `Bursts[name]` (`hatch`, `evolve`, `monsterLevelUp`, `ranchLevelUp`, `rebirth`, `coins`, `hearts`). Sprite ids are the GENERATED `Config/VfxSprites` (`[name] = { color, grey? }`, names from `art/vfx/SPRITES.md`, made with `tools/vfx`); a sprite not uploaded yet just skips its emitters.
- Runtime: `Visuals/Vfx` - `AttachMonster(model, appearance)`, `SetOwned(model, owned)`, `AttachLandmark(instance, id)`, `Burst(name, cframeOrPosition, { color?, scale?, elements? }?)` (pooled, `:Emit`), `SetQuality(low)`, `Clear(target)`, `Count(target)`. `MonsterModel.Build` attaches effects on the mesh and placeholder paths alike (`opts.vfx == false` skips: ViewportMonster, statues). The `Landmarks` controller attaches the hub buildings (on their Body, which World/Dress keeps) and the Sky Gate portal; World marks pen monsters own / other plot, routes `lowGraphics` to `SetQuality` and fires the moment bursts.
- Rules (`Vfx.spec` enforces them): daylight LightEmission 0.15 - 0.3 (portal cores may glow more), Size and Transparency are NumberSequences that fade in fast and out slow, live particles (rate x max lifetime) <= 8 per aura, <= 12 with two mutations, <= 60 per landmark. Low graphics: other plots' auras and glows off, mutation / variant / landmark rates and bursts halved.

### Audio
- **Data:** `Config/Sounds` maps every key to a plain id string or a table `{ id? , ids? = { variations }, volume?, pitch? = n | { min, max }, group? = "Effects"|"UI"|"Music"|"Ambience"|"Voice", cooldown?, maxConcurrent?, duck?, duckHold?, looped?, scatter? = { min, max } }` (header has the defaults). Ids are licensed Pro Sound Effects / APM Creator Store assets; `ids` plays a random variation, never the same twice in a row. An empty id is a placeholder: nothing is created or played, so the game is silent until ids are filled in, and a key lights up the moment it gets one. `Logic/Audio` holds the pure rules (entry resolution, toggle → group volumes, pitch picks, coin streak pitch, voice pitch, hatch / music fallback chains, ambience beds) and is unit-tested.
- **Kit (`client/Audio`):** `Attach` (from `ClientKernel.new`) makes SoundGroups `Music`, `Effects`, `UI`, `Ambience`, `Voice` under SoundService. Settings: Music and Ambience follow the `music` toggle, Effects, UI and Voice follow `sfx`. `Play(key, opts?)` is a pooled one-shot (`maxConcurrent` copies, oldest restarted; `cooldown`; pitch range) and positional with `opts.at` (Vector3 / part / attachment / model → an Attachment on `Workspace.AudioEmitters`, InverseTapered rolloff). Also `Chain(keys)` (first filled key), `Streak(key)` (a semitone higher per quick repeat, for coin ticks), `SetLoop(key, level, at?)` / `SetMusic(chain)` (crossfaded loops; a `scatter` key is instead a bed of one-shots at random spots around the camera), `LoopAt(key, instance)` (a positional loop at a landmark, gone with it), `Duck` (a table entry's `duck` dips music under a sting), `Preload("UI")` (guarded `ContentProvider:PreloadAsync`), and `Override(key?)` for auditioning. `ctx:Sound(key, opts?)` is `Audio.Play`. Every `Button` clicks (`Sound` prop: another key or `false`; a disabled press plays `Locked`), `Widgets.Tabs` play `UITab`, the Router plays `UIOpen` / `UIClose`, error toasts play `Error`, a `*.Buy` through `StoreKit.request` plays `Purchase`.
- **Voices (`client/Audio/Voices`):** one family per Species archetype (`Voice<Archetype>`), pitched by stage, size and a fixed per-line offset (hash of the line id). `Cry(modelOrRecord, kind)` for `hatch` (Hatchery), `evolve` (Notifications), `levelUp`, `pet`, `happy` (World; happy is rate-limited per monster and overall); World `Track`s pen monsters and Soundscape asks `Chatter` for the closest few (3 within 50 studs, 1 within 28 with lowGraphics).
- **Soundscape controller:** twice a second derives the context — battle (a `BattleReplay` in UI.Top, or the Arena screen), Stampede (Boss screen), Sky Islands (`SkyIslands.IsOnIslands()`), hub (inside `World.HubRadius`), night and weather (`global.Weather`), event (`Events.ActiveId`) — and sets music (`Logic/Audio.MusicChain`: raid (Raids screen) > racing (Racing screen) > battle > Stampede > Sky Islands > event theme > hub > night > day, falling back to `MusicRanch`) and ambience beds (birds by day and crickets at night as scatter beds, wind up high, rain, a low crowd in the hub; a positional fountain loop at `World.Fountain`). One-shots: `RainStart`, `Thunder` just after each `"Weather.Lightning"`, `WindGust` on the islands. Elsewhere: Landmarks hums `PortalHum` at raidPortal, hubPortal and the Sky Gate; SkyIslands plays `Teleport` on the fly pads; `Rebirth`, `Mutation` (the mutation card) and `Heal` (BattleReplay heal / regen).
- **Sound Check (Studio only):** when `RunService:IsStudio()`, Soundscape registers the `SoundCheck` screen (not in the Manifest) and a "Sound Check" button: every key by kind with its group, id or "empty", Play / Stop (voices at Baby / Teen / Adult pitch), and buttons that preview each music context (`Soundscape.Preview`).

### Living pens (glow-up S)
- **Data and rules:** `Config/PenLife` (required directly, like `Config/Vfx`): `Base` day-roll weights, `Traits[traitKey]` tendencies (every `Config/Traits` key has one; multipliers plus flags `seekFood`, `nightOwl`, `earlyBird`, `showOff`, `greeter`, `weatherproof`, `weatherLover`, `stargazer`, `edge`, `pace`), `Hold` seconds per action, `Weather[id]` reactions (`wet`, `cold`, `sunny` + `bask`, `shelter`), greet / gather / show-off / chase / motion / think / bubble numbers. `Logic/PenLife` holds the pure decisions and pen maths (pen-local studs): `TraitIds`, `Tendency`, `Asleep`, `Weight`, `Choose`, `Hold`, `IdleState`, `Onset`, `Bubble`, `BubbleAllowed`, `Clamp`, `RandomPoint`, `FencePoint`, `NearFence`, `PileSlot`, `Ring`, `Separation`, `Avoid`, `Steer`, `FleePoint`, `PickMate`, `TurnYaw`, `ThinkRate`.
- **Brain (`Visuals/PenBrain`):** World attaches it in `Start` (`PenBrain.Attach(ctx, { views, area, penModel, plotFrame, own })`), its 0.2 s loop's `tickWander` is `PenBrain.Tick(os.clock())`, and `Destroy` calls `PenBrain.Detach()`. The brain reads World's entries (`id, plot, pen, owner, model, animator, margin, alive, nextAt`) and keeps its own mind per entry (swept within 5 s once World marks the entry `alive = false`). `entry.nextAt` is the next decision time; the brain holds it at `math.huge` while it steers a walk, and anything else that sets it (e.g. `World.PlayTrick`, a care gesture) takes the monster back. Own monsters use their record's traits (the hidden one from stage 3); other plots are neutral unless World puts a `traits` list on the entry.
- **Perf knob:** `PenBrain.SetThinkRate(plotIndex?, rate 0..1)` (nil = every plot) multiplies the built-in rate: full within 90 studs of the camera, half to 180, a quarter to 250, none beyond (the animator is paused there too), × 0.35 off screen.
- **Pen spots:** any BasePart or Model with the string attribute `PenSpot = "shelter" | "food" | "water" | "bed"` under the pen's model (`Workspace.World.Plots.PlotN.Pens.PenM`) or directly in World's plot folder (`WorldClient.PlotN`) and standing on that pen's floor is used: `shelter` in storms, `food` for gluttons and hoarders, `bed` as the night pile. Parts that collide, `Decor_*` pieces and parts with `PenObstacle = true` are avoided. Without spots: the nearest corner (shelter), eating in place, a back corner (pile). Rescanned every ~6 s per pen.
- **MonsterAnimator additions:** a walker turns toward its heading at `SetTurnRates(walk, face)` radians per second (7 / 4 by default) and slows while facing away; `MoveTo` while walking only retargets (the cycle keeps its time); `:FaceToward(position)`, `:SetPace(k)`, `:GetSpeed()`; states `shake` (once) and `shiver` (loops), procedural over idle on 3D monsters.
- **Mood bubbles (`Visuals/MoodBubbles`):** pooled BillboardGuis in the PlayerGui (`Localize = false`), `Pop(model, kind, now)` for `sleep | love | food | music | wet`, within 70 studs of the camera, at most 6 (2 with lowGraphics, and then only `love`), 5 s per monster, none during photo mode.
- **Debug / tests:** `PenBrain.Describe(model) -> { action, moment?, traits, walking }?`, `PenBrain.Stats() -> { [action]: count }`, `PenBrain.Count() -> number`.

### Photo mode
- **Screen `PhotoMode`** (non-modal; the HUD's 📷 under the gear, P, or D-pad up while nothing is open) and **controller `PhotoMode`**: the screen's Open / Close start and end a session (`PhotoMode:Begin(api)` / `:End()`), so every exit path restores the game the same way.
- A session hides our layers (except the toast lane and the pad legend), every other ScreenGui and BillboardGui, avatar name tags and the core GUI, takes the camera (Scriptable) and hands back its CameraType, CameraSubject, CFrame, Focus and FieldOfView; Lighting gets `PhotoModeColor` / `PhotoModeBloom` / `PhotoModeDepth`. Movement keys and sticks are sunk through ContextActionService only during a session.
- Camera maths are pure (`Logic/PhotoRig`), tuning and content in `Config/Photo` (required directly, like `Config/Vfx`). Low graphics skips heavy filters, bloom and depth of field; reduced motion snaps the camera and drops the shutter flash.
- `World:OwnMonstersNear(position, radius) -> { { model, animator } }` feeds Pose (`:Play("trick")`, else `"happy"`). CaptureService members are feature-checked (`PhotoMode:Capabilities()`); the photo button, Save and Share only show where they exist.

### Quality levels and performance (glow-up P)
- **One level for every visual:** `client/Visuals/Quality` - `Level()` (1 low, 2 medium, 3 high), `Id()`, `IsLow()`, `Choice()`, `AutoLevel()`, `Changed` (Signal(level, previous)), `SetChoice`, `SetAuto`, `Stats`. Every former `Settings.lowGraphics` reader (Vfx, MonsterAnimator, World, Sky, Weather, Lamplight, SceneryMotion, Critters, Soundscape, PhotoMode, Celebrate) reads `Quality.IsLow()` / `Quality.Changed`; new visuals must too. Sky's depth of field is High only.
- **Choice:** `Settings.SetGraphics { graphics = "auto" | "high" | "low" }` writes `graphics` and sets `lowGraphics = (graphics == "low")`. `Logic/Quality.Choice(settings)`: `lowGraphics == true` is Low whatever `graphics` says, so pre-P saves that chose low graphics stay Low. The Settings screen's Graphics row (it replaced the Low graphics toggle) cycles Auto → High → Low and shows "Auto · <level>".
- **Reduced motion is not a level.** `UI/Anim.enabled` still follows only `lowGraphics` (Broadcasts), i.e. the player's explicit Low. Auto dropping to Low cuts effects, detail and swarm sizes (Celebrate halves showers and confetti) but never menu, toast or camera motion; PhotoMode's reduced motion reads the saved flag, its heavy filters / bloom / depth follow `IsLow()`.
- **Auto stepper** (`Controllers/Quality`, rules in `Logic/Quality`, numbers in `Config/Quality.Auto`): RenderStepped dt into a 4 s window, median evaluated once a second; step down after 3 bad evaluations, up after 20 good ones, 8 s cooldown, a gap between each level's down and the next level's up threshold, and `upAfter` doubles (to 240 s) when a level is lost within 60 s of climbing to it. Ignored: the first 10 s, 2.5 s after `Router.Opened` or a 60-stud character jump, single frames over 250 ms. The Lune harness steps 0.1 s frames, so a client spec that runs past ~22 s of client time is at Auto Low; pin `Settings.SetGraphics "high"` in a spec that asserts full-quality visuals after that.
- **Particle budget** (`Visuals/Vfx`, `Logic/ParticleBudget`, `Config/Quality.Particles`): `Vfx.StartBudget()` (the Quality controller) runs `Vfx.BudgetPass()` every 0.5 s: live particles = Σ Rate × mean Lifetime of enabled Vfx emitters in the Workspace; the local player's own monsters are never cut; the rest are scaled together to 0.5, then kinds are switched off in `dropOrder`, and restored when demand falls (the plan depends only on demand, so it cannot flap). Bursts share a per-second particle allowance per level. Not counted: Weather's and SceneryFx's emitters (they have their own low-graphics scaling).
- **Distance LOD** (`Config/Quality.Lod`, `Logic/Quality.PenCap / Band / EffectsOn / AnimInterval`): World draws another plot's pens with a cap by level and distance band (re-checked once a second; `MAX_PER_PEN` for the own plot) and marks its animators `SetOwn(false)`; MonsterAnimator's shared loop picks each model's update interval by level, distance, own/other and whether it is behind the camera (0.2 s), paused beyond 250 studs; Vfx's pass turns off auras, rarity glows and mastery on another plot's monsters beyond `effectsDistance`.
- **Perf overlay:** Studio only (`RunService:IsStudio()`), shown while `Config.Quality.Overlay.enabled` or the Workspace attribute `PerfOverlay` is true: median frame ms, level (choice), live particles, animators updated last frame.
- **StreamingEnabled (still off in both project files).** Made tolerant: `Visuals/SceneryIndex` re-indexes when Scenery children come and go; Critters re-scans pens / rails / fountain and Lamplight re-collects its sources when `World.Hub` / `World.Plots` descendants change (1 s debounce, `Visuals/Streaming`); Landmarks has no WaitForChild timeouts and retries a building whose Body arrives late; `World/Build` makes every World model `ModelStreamingMode = Atomic`. World already falls back to `Config.World` positions for a missing plot or pen. **Before turning it on, the lead must, in Studio:** set `Workspace.StreamingEnabled` in `default.project.json` (and decide for `hub.project.json`), pick `StreamingTargetRadius` ≥ 300 and `StreamingMinRadius` ≥ 120 (plots are 240+ studs apart), and check: the hub buildings' lamps and effects appear when walking in, pen floors under monsters (the client draws monsters from state even where the floor has not streamed: they may hover until it does), the Sky Gate portal effect after flying up, coin jars on the own plot, taps on other plots' monsters, EggHunt eggs and Riding/Surf pads. **Not made safe (other owners' controllers; each looks parts up once at start):** `Interaction` (hub and ranch prompts built from `World` at Start), `Leaderboards` (the board's Body, `WaitForChild` 30 s), `Showtime` (the stage's Body, 30 s), `Community` (VIP pads scanned once from `Hub:GetDescendants()`), `SkyIslands` (the Sky folder wired once). The fix is the same pattern (`Visuals/Streaming.OnChild` / `WatchTree`). Raycast taps simply miss parts that are streamed out.

### Cinematics (glow-up N: camera shots)
- **CameraDirector** (controller): `Play(shot)` queues `{ position, height, run = fn(handle)?, hold?, onDone = fn(ran)? }`; one shot at a time, framed by `Logic/Cinematic.Frame` (`Config/Cinematics.Camera`), glide in / out (a cut with reduced motion: lowGraphics, `UI/Anim.enabled == false`, `GuiService.ReducedMotionEnabled`). The handle has `Wait(s) -> skipped`, `Skipped()`, `Frame(position, height, seconds?)`, `reduced`, `low`. `Skip()` (any tap: a full-screen catcher in UI.Top, or A / B / Space / Return), `Stop()` (cut back now, drop the queue), `IsBusy()`, `CanStart()` (no PhotoMode, no Router screen, no Focus modal, not riding: a `Mount` under the HumanoidRootPart). A screen, PhotoMode or a mount mid-shot cuts back; `PhotoMode:Begin` calls `Stop()` first. It saves and restores CameraType, CameraSubject, CFrame, Focus and FieldOfView (CameraType last), hides the HUD layer and shows letterbox bars meanwhile.
- **Cinematics** (controller): `Hatch(entries, onDone) -> boolean` (Hatchery hands over each batch; an open Incubators screen is closed for the shot and reopened by `ReopenAfterHatch()` when the last card closes), `ClaimNew(monster)` (a form not in `profile.Monsters.codex` yet, once per form, robust to the codex patch landing before the event), `TakeEvolve(payload, showCard)` (Notifications, before its card), `Evolved(payload)` (World's evolve moment), `Spotlight(id, burst)` (World's monsterLevelUp / monsterStarUp moments), `Played()` (counts). World helpers: `World:OwnMonster(id, still?) -> { model, animator }?`, `World:IncubatorEgg(eggType, slot, taken?) -> (CFrame?, Model?)`.
- Plans are pure (`Logic/Cinematic`: `HatchPlan`, `Wobble`, `MontageOrder`, `EvolveAt`, `EvolveLength`, `IsNewForm`), tuning in `Config/Cinematics` (required directly). New bursts in `Config/Vfx.Bursts`: `evolveVortex`, `shinyShower`, `starUp`. Shot parts live in `Workspace.Cinematic`, the Mythic tint is a `CinematicPulse` ColorCorrectionEffect; both are gone when the shot ends. World's own egg / monster models are hidden with `LocalTransparencyModifier` during a shot and given back.

### Battle stage (glow-up V: fights in 3D)
- **`UI/Screens/Parts/Battle`** is the one entry point every caller of a BattleReplay (§7) uses: `Battle.play(ctx, opts)` where `opts` are the 2D viewer's (`replay, win, rewards, title, winText?, loseText?, retryText?, onRetry?, nextText?, onNext?, onClose?`) plus `stage` (a `Config.Regions` id, `"arena"` or `"raid"`; picks the `Config/BattleStage` theme). Returns `{ Destroy() }`, same as the 2D viewer. `Battle.Mode(ctx, opts) -> "3d" | "2d", reason` and `Battle.SetMode(mode?)` (tests: force a mode, `nil` = choose) are exposed for specs.
- **Choosing 3D or 2D** (`Logic/BattleStage.Choose`, pure): 2D when the `CameraDirector` isn't free for a stage shot (`CanStart(true)`, a screen being open does not block it, but PhotoMode / a Focus modal / riding do), when Quality is Low and the replay has more than `Config.BattleStage.fallback.lowMaxUnits` fighters (allies + enemies), or when the median frame (`Quality.Stats`) is slower than `fallback.maxFrameMs`. `Parts/BattleStage` itself hands over to the 2D viewer if the shot cannot start or the stage fails to build (a caught error), or if the camera is taken back mid-fight (shows the result on a plain backdrop instead).
- **`Parts/BattleStage.play(ctx, opts, fallback)`** draws the fight through one `CameraDirector` stage shot (`shot.stage = true`): the attacker's clip + a lunge, an element bolt (`Config/VfxSprites`) to the target, a hurt flinch + hit flash + spark, floating numbers (crits bigger; heals green; shields, stuns), KO'd fighters faint, HP bars over heads, callouts for specials and element multipliers — the same event handling as the 2D viewer (`Logic/BattleStage.Apply/Floater/Attacks/Hurts`). Camera cuts from `Logic/BattleStage.Shots` (wide at the first event and periodically after, over-the-shoulder on a crit / special / big hit, close-up on the finishing blow, never closer than `camera.minCut`; a cut under reduced motion). Tap toggles 2x speed; Skip fast-forwards the state and shows the shared result card (`Parts/BattleResult`) over the stage: winners cheer (a voice cry), Victory / Defeat sting, `Celebrate:Play` on a win with rewards.
- **`Visuals/BattleArena`** is the stage in the world (`Workspace.BattleStage`, far outside the map at `Config.BattleStage.origin`): a floor disc + rim, a ring of backdrop panels, a few themed props (`Config.BattleStage.themes`; every prop has a `mesh` id field, "" = the parts shown), two lights (none on Low). Fighters are pooled `MonsterModel.Build` + `MonsterAnimator` (`BattleArena.Pooled/Live/Flush`; a parked model waits 20s for the next same-look fight, then is destroyed, ≤ 12 pooled). Placement (`Logic/BattleStage.Row/Placement`) seats allies at `x < 0` and enemies at `x > 0`, several per row, a boss centred behind its row and bigger (`Logic/BattleStage.Size`, clamped `scale.min..max`, ×`scale.boss`). Bolts, floating numbers and hit sparks are pooled and capped (`Logic/BattleStage.Caps/Limiter`: a live count and a per-second rate, halved and sparks off on Low; a capped bolt or spark is simply not drawn, the hit still lands; a capped number recycles the oldest one for a crit/KO/special, else drops). `arena:Counts()` and `BattleArena.Live()/Pooled()` are for tests.
- **Wired into** Expeditions, Arena and Raids (`Battle.play` replacing their old direct `Parts/BattleReplay.play` calls); the 2D viewer is otherwise unchanged and stays the fallback. `BattleStage.spec` (pure: `Choose`, `Placement` for 1-8 allies + a boss, pace/shots, `Limiter`, caps, state/floaters), `BattleStageClient.spec` (a stage fight, an Arena match and a Raid played through the real client in 3D and forced to 2D, skip, cleanup, `BattleArena` caps).

### Ambience layers (sky, light and a world that moves)
- **Data:** `Config/Ambience` (layer switches, sky ids, clouds per weather, sun rays, depth of field, golden hour, lights, scenery motion, critters, every count as `max` / `maxLow`); the particle looks are `Config/Vfx.Scenery` (`campfire`, `windmill`, `fountain`; same spec keys and daylight rules as every effect, budget `Vfx.Budget.scenery` = 45 live per item). Pure rules: `Logic/Ambience` (`Night`, `GoldenHour`, `Clouds`, `SunRays`, `Enabled`, `Cap`, `Nearest`, `Scared`, `Sway`), unit-tested in `Ambience.spec`.
- **Switches:** every layer is a boolean in `Config.Ambience.Layers` (`sky`, `clouds`, `sunRays`, `depthOfField`, `goldenHour`, `weatherSprites`, `lights`, `campfires`, `fountain`, `windmills`, `sway`, `butterflies`, `fireflies`, `birds`, `fish`). For a live Studio A/B, a boolean attribute on Lighting `Ambience_<layer>` overrides it (`weatherSprites` is read once, at Weather's build).
- **Sky controller:** a Sky (the place's own if it has one; skybox faces only when all six ids are filled, else Roblox's default), Terrain Clouds (per weather, blended, shaded at night), `AmbienceSunRays`, `AmbienceDepthOfField` (far haze only) and `AmbienceGoldenHour` (a second ColorCorrection stacked on Weather's, warm through dusk and dawn). 5 updates a second, writes on change. lowGraphics: no clouds, sun rays or depth of field. The day/dusk/night mood itself stays with the Weather controller.
- **Weather sprites:** the Weather controller's rain, snow, pollen and starfall emitters take the droplet, snowflake, petal and star sprites (grey twins, so each look keeps its colours).
- **Lamplight controller:** door lamps (hub buildings and barns), window spill (a SurfaceLight on each hub building's front), campfires (flicker), crystals and the fountain. Off by day; twice a second `Logic/Ambience.Night(ClockTime)` scales brightness and only the 12 nearest within 220 studs are enabled (5 with lowGraphics). No shadows. There are no lantern or street-lamp parts in the world yet.
- **SceneryMotion controller:** pooled `Visuals/SceneryFx` holders moved once a second to the nearest campfires (4, low 2) and windmills (3, low 0), the fountain's water while within 240 studs, and a CFrame sway about the base on the 10 nearest trees and bushes at 20 Hz (none in lowGraphics; restored exactly when they leave the set). lowGraphics halves every scenery rate. Windmill sails cannot turn: the mesh is one piece.
- **Critters controller:** pooled parts near the camera, picked once a second and moved 30 times a second: butterflies by day (8, flowers / sunflowers / pen floors), fireflies at night (16, low 5), birds by day on birdhouses and pen rails that scatter from a running player (4), fish in the fountain basin (3). lowGraphics: fireflies only.
- `Visuals/SceneryIndex` indexes `Workspace.World.Scenery` by kind when it arrives (and again, debounced, when its parts stream in or out), for all three. The low counts (`maxLow`) apply at the Low quality level (`Visuals/Quality.IsLow()`, glow-up P).

## 6. State shapes (binding)

These are the exact replicated shapes. Server systems must produce them; client screens read them. Arrays have fixed lengths where noted, and use `false` for empty values.

```lua
profile.Currency   = { coins, gems, stardust, friendship, treats, tokens = { [eventId] = n }, food = { sweet, spicy, savory, sour } }
profile.Progression = { level, xp }                     -- xp toward next level: Config.Unlocks.XPToNext(level); cap Unlocks.MaxLevelAt(now)
profile.Settings   = { music, sfx, lowGraphics, hideBroadcasts, language, graphics }   -- language (3.2): "auto" | "en" | "es" | "pt"; graphics (glow-up P): "auto" | "high" | "low"
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

global.Boss  = { state = "idle"|"lobby"|"active", bossId, startsAt, endsAt, hp, maxHp, participants, board = { { userId, name, damage } }, squads = { { userId, looks } } }  -- board: top 10; squads: glow-up U
session.Boss = { joined, damage, cheer }                 -- cheer 0..1
global.Titan  = { state = "idle"|"lobby"|"active"|"fallen"|"retreated", titanId, startsAt, endsAt, hp, maxHp, servers, players, participants, poolOk, board }  -- hp/maxHp/servers/players: the SHARED pool; board: this server's top 10 (glow-up TT)
session.Titan = { joined, damage, cheer }                -- cheer 0..1

profile.Breeding = { pods = { [1..2] = { state = "idle"|"running", a = id|false, b = id|false, startedAt, endsAt, seed } }, daily = { day, counts = { [monsterId] = n } }, discovered = { [lineId] = true } }
session.Breeding = { podCount, breedsPerDay }

global.Weather = { id, startedAt, endsAt, nextRollAt, night, phaseEndsAt, summonedBy = string|false }

profile.Social = { day, petsGiven, likesGiven = { ["u" .. userId] = true }, likes }
session.Social = { friendBoost, friendsHere }

global.Plots = { [1..6] = {                              -- always 6 entries; empty plot has userId = 0
  userId, name, level, likes,
  pens = { { theme, decor = { decorId }, monsters = { { id, appearance } }, capacity, jarTier } },   -- capacity, jarTier: glow-up R
  statues = { Appearance },
  incubators = { { type, endsAt } },
  garden = { tier, plots = { { flavor = string|false, readyAt } } } | false,   -- glow-up R; false on an empty plot
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
- `Ranch:PublicPens(player) -> { { theme, decor = { decorId }, monsters = { id }, capacity, jarTier } }` and (glow-up R) `Ranch:PublicGarden(player) -> { tier, plots = { { flavor, readyAt } } }?`
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
