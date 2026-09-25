# System Status Board

Status: ⬜ not started · 🟨 in progress · 🟩 built and tested · 🔌 plugged in (in Manifest)

## Server systems

| System | Workstream | Status | Spec | Notes |
|---|---|---|---|---|
| Kernel (lifecycle, Data, Net, State, Bus, Scheduler) | K | 🟩 | `Kernel.spec` | session-locked DataStore, validation, rate limits |
| Currency | S1 | 🔌 | `Economy.spec` | |
| Progression | S1 | 🔌 | `Economy.spec` | |
| Rewards | S1 | 🔌 | `Economy.spec` | |
| Settings | S1 | 🔌 | `Kernel.spec` | |
| Monsters | S2 | 🔌 | `Economy.spec` | growth, feeding, levels, stars, codex |
| Eggs | S3 | 🔌 | `Eggs.spec`, `RanchLogic.spec` | starter egg, 4 slots (unlocks + Extra Incubator pass), speed providers (cap 0.75, fixed at placement), Starlit pity / Royal lucky meter (`Logic/EggRoll`), Hatch Rush ad, offline-ready eggs → WelcomeItem; `Room()` for trade/shop caps |
| Shop | S3 | 🔌 | `Shop.spec`, `RanchLogic.spec` | deterministic global restock (`Logic/Restock`), per-player allowance per window, unlocks, event eggs, paid-random gate (Monetization → Policy fallback), storage cap, food, decor, themes, daily free egg ad |
| Ranch | S3 | 🔌 | `Ranch.spec`, `RanchLogic.spec` | pens + jars (`Logic/Jar`, settle-on-change, offline at saved rates), modifiers/jar bonuses, passes (doubleCoins, vip, bigBarn, autoCollect), assign/busy auto-removal + return, upgrades, decor mood aura, themes, garden (rain ×2) |
| WelcomeBack | S3 | 🔌 | `WelcomeBack.spec` | buffers join WelcomeItems, ≥ 5 min away summary, claim ×1 / ×2 (ad); holds Auto-Collect until claimed |
| Expeditions | S4 | 🔌 | `Expeditions.spec`, `BattleSim.spec` | stage fights (`Logic/BattleSim`), timed runs + offline finish (`Logic/Loot`), caravans; optional Monetization (explorer, stageRetry ad), Weather (night) |
| Boss | S4 | 🔌 | `Boss.spec` | Stampede schedule, cheer (≤ `Boss.MaxTapsPerSecond`), rewards; needs Expeditions; optional Weather (bossDamage) |
| Breeding | S5 | 🔌 | `Breeding.spec` | pods (+pass), daily limits, seeded roll via `Logic/Breeding`, offline WelcomeItem, hybrid discovery → `Bred` |
| Weather | S5 | 🔌 | `Weather.spec` | clock-aligned rolls + day/night (`Logic/WeatherRoll`), pen mutations, totems (queued behind running weather), heatwave egg speed, tutorial guarantee |
| Social | S5 | 🔌 | `Social.spec` | friend boost (`friends` rate modifier), pets/likes, server + global broadcasts (MessagingService) |
| Trade | S5 | 🔌 | `Trade.spec` | request → offer → ready → confirm countdown; atomic swap with capacity/egg caps, rollback, private log |
| Plots | S5 | 🔌 | `Plots.spec` | 6 public plots, lowest free on PlayerReady, throttled rebuilds (≤ 1 / 2 s) |
| Clubs | S5 | 🔌 | `Clubs.spec` | 1.2: clubs of ≤ 30 across servers (`Services.Clubs`, atomic Update), roles, weekly goals + club boss, batched sync every 60 s + Messaging refresh; rules in `Record.luau` |
| Market | S5 | 🔌 | `Market.spec` | 1.3: listings with escrow across servers (`Services.Market`), 8% tax (4% club post), one winner per sale, two-phase deduplicated mailbox; every cross-server step saves an intent task first (`ctx:SaveNow`) so crashes and lost replies never duplicate or lose items or coins |
| PriceHistory | S5 | 🔌 | `PriceHistory.spec` | 1.3: daily buckets per item key (`Logic/PriceHistory`), `PriceHistory.Get` with a suggested price, retried writes; club sales excluded |
| Events | S6 | 🔌 | `LunarLanterns.spec` | 1.2: event calendar (`Config/Events`, `Flags.ActiveEvent` override), `global.Events`, event tokens for play with a daily cap |
| Leaderboards | S5 | 🔌 | `Leaderboards.spec` | 5 weekly boards (heaviest, codex, stampede, halloffame, stage): live per-server rows, global rows via `Services.Leaderboards` (OrderedDataStore per board per week), last week's #1 → nameplate title; weeks start Saturday 15:00 UTC |
| Monetization | S6 | 🔌 | `Monetization.spec` | pass cache on join + live/RefreshPasses, idempotent ProcessReceipt (private `receipts`, newest 200), `RegisterProduct` handlers, oncePerAccount, capped rewarded ads (UTC-day reset), paid-random policy (fails closed) |
| Quests | S6 | 🔌 | `Quests.spec` | tutorial state machine + onboarding funnel + scripted rain (optional Weather), deterministic dailies, achievements, codes (expiry, group), Ranch Pass (season window, `Quests.RanchPass` product) |
| HallOfFame | S6 | 🔌 | `HallOfFame.spec` | retire → statue, legacy (capped per element), Stardust + Star Shards, upgrades; providers for Ranch, Eggs, Monsters, Boss, Breeding, Expeditions |
| Rebirth | S6 | 🔌 | `Rebirth.spec` | 1.4: Ranch Rebirth (Lv 40, coins in hand), Heirlooms, unkept monsters → Stardust, resets via Ranch/Expeditions hooks, Rebirth Stars (coin multiplier), biome themes, 3rd trait at 3 stars; Stardust skill tree through the provider hooks |
| EggHunt | S6 | 🔌 | `SpringBloom.spec` | 1.4: Spring Bloom hub egg hunt, 20-minute rounds on the unix clock (same spots on every server), proximity-checked finds, round bonus, daily cap |
| World (geometry) | C1 | 🔌 | Studio | `Systems/World` + `Build.luau`: ground, paths, plaza + fountain, the hub buildings of `Config.World.Hub` + the leaderboard board (HubId/Screen), 6 plots (PlotId) with 5 fenced pens (PenIndex), incubator pad, barn, gate; ~380 parts |

## Client

| Piece | Workstream | Status | Notes |
|---|---|---|---|
| ClientKernel, Store, NetClient, Router, Layers | K | 🟩 | |
| UI kit (Theme, Create, Anim, Button, Panel, Icon, Widgets, Toasts, MonsterIcon) | K | 🟩 | |
| Visuals: MonsterModel, EggModel | K | 🟩 | procedural placeholders |
| Visuals: MonsterAnimator | C1 | 🔌 | one shared RenderStepped; idle/walk/happy/eat/attack/hurt/sleep + egg `wobble`; distance pause > 250 studs; rainbow/prismatic hue cycling |
| Controllers: World, Weather, Interaction | C1 | 🔌 | need Workspace.World (server `World` system) |
| Controllers: Hud, Notifications, Hatchery | C2 | 🔌 | lint/selene/rojo clean. `Hud:GetTarget(name)`, `Hud:Flash(name)`, bus `Hud.Flash`; Notifications auto-opens WelcomeBack; `Hatchery:IsShowing()` |
| Screens: EggShop, Incubators, Monsters, MonsterDetail, Ranch, WelcomeBack, Codex | C2 | 🔌 | lint/selene/rojo clean. Monsters pick mode per §5 (returnTo opens before `onPick`; cancel returns without it). New C2 components: `StoreKit`, `Tiles`, `InsetPopup`, `StatBar`, `ViewportMonster` |
| Controllers: Tutorial, Broadcasts, TradeRequests | C3 | 🔌 | lint/selene/rojo clean. Broadcasts also shows the `Boss.Result` popup and maps `Settings.lowGraphics` → `Anim.enabled` |
| Screens: Expeditions, Breeding, Trade, Boss, HallOfFame, Quests, Store, Settings | C3 | 🔌 | helpers in `UI/Screens/Parts/` (Util, Dialog, BattleReplay); needs C2 `Monsters` pick mode; lazy `Logic/BattleSim` + `Logic/Breeding` with local fallbacks |
| Screen: Market · component: PriceChart | C3 | 🔌 | 1.3: Browse / Sell / My listings / Club post, price chart, mail toast; HUD Market button (Settings moved to a gear by the level bar) |
| Screen: Clubs · controller: Nameplates | C3 | 🔌 | 1.2: create / join / members / goals / boss / settings; Club Plaza building + HUD button; nameplates show club tags and champion titles |
| Screen: Rebirth · controller: EggHunt | C3 | 🔌 | 1.4: rebirth requirements / keep / reset / gain, Heirloom pick + confirm, skill tree; Star Altar in the hub and a Hall of Fame link; hunt eggs with pick-up prompts; Pollen Storm particles in the Weather controller |
| Screen + controller: Leaderboards | C3 | 🔌 | board tabs, server/everywhere switch, champion card, reset countdown; controller draws the Market Square board (SurfaceGui) and champion nameplates |

## Studio test pass (not yet done)

Client code and the World geometry run in Lune through `tests/runtime/RobloxMock` (see `Client.spec.luau`): every controller boots, every screen opens, every button is clicked, and every Instance property set is checked against Roblox's API database. What the mock cannot show is rendering, physics, input feel and real networking, so Studio still needs a first pass:

- [ ] Join: starter egg in slot 1, hatch reveal, starter walks into pen 1, character spawns on its own plot
- [ ] HUD on a phone-sized emulator (tap targets, safe area, overlays not colliding)
- [ ] Every hub prompt opens its screen; Monsters pick mode round-trips from Expeditions, Breeding, Trade, Ranch and Hall of Fame
- [ ] Coin jar billboards count up and collect; weather visuals and day/night change with `global.Weather`
- [ ] Two-player test: trade, petting, likes, caravan, Stampede
- [ ] Leave and rejoin after a few minutes: Welcome Back appears with offline coins

## Launch checklist

- [ ] Real `gamePassId` / `productId` values in `Config/Monetization.luau`
- [ ] AdService flow verified in a live server (see `Kernel/Adapters.luau`)
- [ ] `Config.Quests.GroupId` set; codes reviewed
- [ ] Studio API access enabled and DataStore name final (`MonsterRanch_Profiles_v1`)
- [ ] Market DataStores (`MonsterRanch_Market_v1`, `MonsterRanch_Mail_v1`, `MonsterRanch_Prices_v1`) and MemoryStore browse maps (`mk_*`) checked in live servers: quotas, `GetRangeAsync` paging, listing expiry
- [ ] Clubs DataStore (`MonsterRanch_Clubs_v1`) and the `Clubs` MessagingService topic checked across two live servers
- [ ] Leaderboard OrderedDataStores (`LB_<board>_w<week>`) checked in a live server, and `Config.Leaderboards.WeekAnchor` lined up with the Saturday update time
- [ ] Sound ids in `Config/Sounds.luau`; art swapped in `Visuals/*` and `UI/Theme.Images`
- [ ] Analytics funnel checked in the Creator Dashboard
