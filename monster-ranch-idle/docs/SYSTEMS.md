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
| Eggs | S3 | ⬜ | | |
| Shop | S3 | ⬜ | | |
| Ranch | S3 | ⬜ | | |
| WelcomeBack | S3 | ⬜ | | |
| Expeditions | S4 | 🟩 | `Expeditions.spec`, `BattleSim.spec` | stage fights (`Logic/BattleSim`), timed runs + offline finish (`Logic/Loot`), caravans; optional Monetization (explorer, stageRetry ad), Weather (night) |
| Boss | S4 | 🟩 | `Boss.spec` | Stampede schedule, cheer (≤ `Boss.MaxTapsPerSecond`), rewards; needs Expeditions; optional Weather (bossDamage) |
| Breeding | S5 | ⬜ | | |
| Weather | S5 | ⬜ | | |
| Social | S5 | ⬜ | | |
| Trade | S5 | ⬜ | | |
| Plots | S5 | ⬜ | | |
| Monetization | S6 | 🟩 | `Monetization.spec` | pass cache on join + live/RefreshPasses, idempotent ProcessReceipt (private `receipts`, newest 200), `RegisterProduct` handlers, oncePerAccount, capped rewarded ads (UTC-day reset), paid-random policy (fails closed) |
| Quests | S6 | 🟩 | `Quests.spec` | tutorial state machine + onboarding funnel + scripted rain (optional Weather), deterministic dailies, achievements, codes (expiry, group), Ranch Pass (season window, `Quests.RanchPass` product) |
| HallOfFame | S6 | 🟩 | `HallOfFame.spec` | retire → statue, legacy (capped per element), Stardust + Star Shards, upgrades; providers for Ranch, Eggs, Monsters, Boss, Breeding, Expeditions |
| World (geometry) | C1 | 🟩 | Studio | `Systems/World` + `Build.luau`: ground, paths, plaza + fountain, 6 hub buildings (HubId/Screen), 6 plots (PlotId) with 5 fenced pens (PenIndex), incubator pad, barn, gate; ~380 parts |

## Client

| Piece | Workstream | Status | Notes |
|---|---|---|---|
| ClientKernel, Store, NetClient, Router, Layers | K | 🟩 | |
| UI kit (Theme, Create, Anim, Button, Panel, Icon, Widgets, Toasts, MonsterIcon) | K | 🟩 | |
| Visuals: MonsterModel, EggModel | K | 🟩 | procedural placeholders |
| Visuals: MonsterAnimator | C1 | 🟩 | one shared RenderStepped; idle/walk/happy/eat/attack/hurt/sleep + egg `wobble`; distance pause > 250 studs; rainbow/prismatic hue cycling |
| Controllers: World, Weather, Interaction | C1 | 🟩 | not yet in Manifest; need Workspace.World (server `World` system) |
| Controllers: Hud, Notifications, Hatchery | C2 | ⬜ | |
| Screens: EggShop, Incubators, Monsters, MonsterDetail, Ranch, WelcomeBack, Codex | C2 | ⬜ | |
| Controllers: Tutorial, Broadcasts, TradeRequests | C3 | ⬜ | |
| Screens: Expeditions, Breeding, Trade, Boss, HallOfFame, Quests, Store, Settings | C3 | ⬜ | |

## Launch checklist

- [ ] Real `gamePassId` / `productId` values in `Config/Monetization.luau`
- [ ] AdService flow verified in a live server (see `Kernel/Adapters.luau`)
- [ ] `Config.Quests.GroupId` set; codes reviewed
- [ ] Studio API access enabled and DataStore name final (`MonsterRanch_Profiles_v1`)
- [ ] Sound ids in `Config/Sounds.luau`; art swapped in `Visuals/*` and `UI/Theme.Images`
- [ ] Analytics funnel checked in the Creator Dashboard
