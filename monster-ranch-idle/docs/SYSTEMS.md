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
| Clubs | S5 | 🔌 | `Clubs.spec`, `ClubWars.spec` | 3.1: Club Wars (war points from raids / racing / Stampedes, weekly ladder across servers, leagues and Champions, ClaimWar), Workshop banners. 1.2: clubs of ≤ 30 across servers (`Services.Clubs`, atomic Update), roles, weekly goals + club boss, batched sync every 60 s + Messaging refresh; rules in `Record.luau` |
| Market | S5 | 🔌 | `Market.spec` | 1.3: listings with escrow across servers (`Services.Market`), 8% tax (4% club post), one winner per sale, two-phase deduplicated mailbox; every cross-server step saves an intent task first (`ctx:SaveNow`) so crashes and lost replies never duplicate or lose items or coins |
| PriceHistory | S5 | 🔌 | `PriceHistory.spec` | 1.3: daily buckets per item key (`Logic/PriceHistory`), `PriceHistory.Get` with a suggested price, retried writes; club sales excluded |
| Events | S6 | 🔌 | `LunarLanterns.spec`, `GoLive.spec` | 3.0.1: `reruns` windows (Frostfall returns). 1.2: event calendar (`Config/Events`, `Flags.ActiveEvent` override), `global.Events`, event tokens for play with a daily cap |
| Leaderboards | S5 | 🔌 | `Leaderboards.spec` | 6 weekly boards (heaviest, codex, stampede, halloffame, stage, racing since 3.0): live per-server rows, global rows via `Services.Leaderboards` (OrderedDataStore per board per week), last week's #1 → nameplate title; weeks start Saturday 15:00 UTC |
| Monetization | S6 | 🔌 | `Monetization.spec` | pass cache on join + live/RefreshPasses, idempotent ProcessReceipt (private `receipts`, newest 200), `RegisterProduct` handlers, oncePerAccount, capped rewarded ads (UTC-day reset), paid-random policy (fails closed) |
| Quests | S6 | 🔌 | `Quests.spec` | tutorial state machine + onboarding funnel + scripted rain (optional Weather), deterministic dailies, achievements, codes (expiry, group), Ranch Pass (season window, `Quests.RanchPass` product) |
| HallOfFame | S6 | 🔌 | `HallOfFame.spec` | retire → statue, legacy (capped per element), Stardust + Star Shards, upgrades; providers for Ranch, Eggs, Monsters, Boss, Breeding, Expeditions |
| Rebirth | S6 | 🔌 | `Rebirth.spec` | 1.4: Ranch Rebirth (Lv 40, coins in hand), Heirlooms, unkept monsters → Stardust, resets via Ranch/Expeditions hooks, Rebirth Stars (coin multiplier), biome themes, 3rd trait at 3 stars; Stardust skill tree through the provider hooks |
| EggHunt | S6 | 🔌 | `SpringBloom.spec` | 1.4: Spring Bloom hub egg hunt, 20-minute rounds on the unix clock (same spots on every server), proximity-checked finds, round bonus, daily cap |
| Accessories | S6 | 🔌 | `Showtime.spec` | 1.5: 39 accessories in 4 slots, buy (gems / Contest Ribbons), equip / swap / unequip, storage; stripped from monsters that leave the ranch and returned to storage |
| Contests | S6 | 🔌 | `Showtime.spec` | 1.5: Monster Contests every 10 minutes on the unix clock (same theme on every server): entry → runway votes (1–5 ★) → results; score = 70% votes + 30% theme judge (judge alone when nobody votes); ribbons, gems and stats |
| SkyIslands | S5 | 🔌 | `LightAndVoid.spec` | 2.0: 13 wind crystals on 5 floating islands, 1 h per-player respawn, daily cap 60, distance-checked, one Loot roll each (coins, treats, Stardust or a Sky Egg) |
| Riding | S5 | 🔌 | `LightAndVoid.spec` | 2.0: mount any Adult (Lv 16); speed from species SPD and rarity; riders replicated in `global.Riding`; dismount on busy / removed / leave |
| Surf | S6 | 🔌 | `LightAndVoid.spec` | 2.0: Summer Splash surfing; seeded course, server replays lane changes to score; Seashells through the event's daily cap |
| Arena | S5 | 🔌 | `ArenaRaids.spec` | 2.1: async PvP with normalized stats, defense snapshots across servers (`Services.Arena`), Elo for both sides, bots fill in, 5 battles a day, weekly tier rewards |
| Raids | S5 | 🔌 | `ArenaRaids.spec` | 2.1: 4-player raid lobbies (2 Adults each), Stormcrag Titan and Umbral Wyrm, Raid Egg for the raid-only lines, 3 rewarded wins a day |
| Racing | S5 | 🔌 | `YearTwo.spec` | 3.0: daily seeded track, fixed-step sim shared with the client, server replays jump/boost moves, 3 ghosts from the track's par, 10 paid races a day, Racing Cup points (weekly `racing` board) |
| TradingHub | S5 | 🔌 | `YearTwo.spec`, `GoLive.spec` | 3.0.1: places found by name, hub place from `hub.project.json`, teleport retry. 3.0: Trading Hub place mode (`Config.TradingHub.Mode`), Travel / Return teleports, cross-server Trade Board (`Services.HubBoard`), Meet here (trade request) or on the poster's server (teleport); no plots on the hub |
| Workshop | S6 | 🔌 | `YearTwo.spec`, `GoLive.spec` | 3.0.1: record / list cache, royalty ledger, moderation queue (Review). 3.0: player-made accessories (catalogue shape + palette colours + filtered name), cross-server designs (`Services.Designs`), copies for ribbons, royalties, likes, reports hide; worn designs encoded in `Monster.acc` |
| World (geometry) | C1 | 🔌 | Studio + ClientHarness | `Systems/World` + `Build.luau`: ground, paths, plaza + fountain, the hub buildings of `Config.World.Hub` + the leaderboard board (HubId/Screen), the Sky Islands (2.0), 6 plots (PlotId) with 5 fenced pens (PenIndex), incubator pad, barn, gate; ~380 parts |

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
| Screens: Wardrobe, Contests (Showtime) · controller: Showtime | C3 | 🔌 | 1.5: dress-up with a live 3D preview, owned / shop tabs; show phases, entry, runway stars, podium; Showtime Stage in the hub shows the walking monster; MonsterDetail Style button; accessory placeholders in `Visuals/MonsterModel` |
| Screen: Surf · controllers: SkyIslands, Riding | C3 | 🔌 | 2.0: launch / return pads, Sky Gate, wind crystals; mounts under every rider, rider speed and hip height, Get off button, Ride on the monster screen; 3-lane surfing screen; Surf Shack and Sky Islands geometry; Light/Void monster touches and Beach Day / pollen-style weather |
| Screens: Arena, Raids | C3 | 🔌 | 2.1: Battle / Defense / Rewards tabs; raid list and server lobbies; both play fights in Parts/BattleReplay; Champions Arena and Raid Portal buildings |
| Screens: Racing, TradingHub, Workshop | C3 | 🔌 | 3.0: side-view race with Jump / Boost and a ghost strip; Trade Board / My ad (hub) or board preview + Travel (ranch); Design / Gallery / My copies; Racetrack, Trading Hub portal and Workshop buildings; Expeditions region tabs with opening dates |
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
