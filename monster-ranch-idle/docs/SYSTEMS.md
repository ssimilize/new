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
| Eggs | S3 | 🟩 | `Eggs.spec`, `RanchLogic.spec` | starter egg, 4 slots (unlocks + Extra Incubator pass), speed providers (cap 0.75, fixed at placement), Starlit pity / Royal lucky meter (`Logic/EggRoll`), Hatch Rush ad, offline-ready eggs → WelcomeItem; `Room()` for trade/shop caps |
| Shop | S3 | 🟩 | `Shop.spec`, `RanchLogic.spec` | deterministic global restock (`Logic/Restock`), per-player allowance per window, unlocks, event eggs, paid-random gate (Monetization → Policy fallback), storage cap, food, decor, themes, daily free egg ad |
| Ranch | S3 | 🟩 | `Ranch.spec`, `RanchLogic.spec` | pens + jars (`Logic/Jar`, settle-on-change, offline at saved rates), modifiers/jar bonuses, passes (doubleCoins, vip, bigBarn, autoCollect), assign/busy auto-removal + return, upgrades, decor mood aura, themes, garden (rain ×2) |
| WelcomeBack | S3 | 🟩 | `WelcomeBack.spec` | buffers join WelcomeItems, ≥ 5 min away summary, claim ×1 / ×2 (ad); holds Auto-Collect until claimed |
| Expeditions | S4 | 🟩 | `Expeditions.spec`, `BattleSim.spec` | stage fights (`Logic/BattleSim`), timed runs + offline finish (`Logic/Loot`), caravans; optional Monetization (explorer, stageRetry ad), Weather (night) |
| Boss | S4 | 🟩 | `Boss.spec` | Stampede schedule, cheer (≤ `Boss.MaxTapsPerSecond`), rewards; needs Expeditions; optional Weather (bossDamage) |
| Breeding | S5 | 🟩 | `Breeding.spec` | pods (+pass), daily limits, seeded roll via `Logic/Breeding`, offline WelcomeItem, hybrid discovery → `Bred` |
| Weather | S5 | 🟩 | `Weather.spec` | clock-aligned rolls + day/night (`Logic/WeatherRoll`), pen mutations, totems (queued behind running weather), heatwave egg speed, tutorial guarantee |
| Social | S5 | 🟩 | `Social.spec` | friend boost (`friends` rate modifier), pets/likes, server + global broadcasts (MessagingService) |
| Trade | S5 | 🟩 | `Trade.spec` | request → offer → ready → confirm countdown; atomic swap with capacity/egg caps, rollback, private log |
| Plots | S5 | 🟩 | `Plots.spec` | 6 public plots, lowest free on PlayerReady, throttled rebuilds (≤ 1 / 2 s) |
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
| Controllers: Hud, Notifications, Hatchery | C2 | 🟩 | lint/selene/rojo clean; not in Manifest yet. `Hud:GetTarget(name)`, `Hud:Flash(name)`, bus `Hud.Flash`; Notifications auto-opens WelcomeBack; `Hatchery:IsShowing()` |
| Screens: EggShop, Incubators, Monsters, MonsterDetail, Ranch, WelcomeBack, Codex | C2 | 🟩 | lint/selene/rojo clean; not in Manifest yet. Monsters pick mode per §5 (returnTo opens before `onPick`; cancel returns without it). New C2 components: `StoreKit`, `Tiles`, `InsetPopup`, `StatBar`, `ViewportMonster` |
| Controllers: Tutorial, Broadcasts, TradeRequests | C3 | 🟩 | lint/selene/rojo clean; not in Manifest yet. Broadcasts also shows the `Boss.Result` popup and maps `Settings.lowGraphics` → `Anim.enabled` |
| Screens: Expeditions, Breeding, Trade, Boss, HallOfFame, Quests, Store, Settings | C3 | 🟩 | helpers in `UI/Screens/Parts/` (Util, Dialog, BattleReplay); needs C2 `Monsters` pick mode; lazy `Logic/BattleSim` + `Logic/Breeding` with local fallbacks |

## Launch checklist

- [ ] Real `gamePassId` / `productId` values in `Config/Monetization.luau`
- [ ] AdService flow verified in a live server (see `Kernel/Adapters.luau`)
- [ ] `Config.Quests.GroupId` set; codes reviewed
- [ ] Studio API access enabled and DataStore name final (`MonsterRanch_Profiles_v1`)
- [ ] Sound ids in `Config/Sounds.luau`; art swapped in `Visuals/*` and `UI/Theme.Images`
- [ ] Analytics funnel checked in the Creator Dashboard
