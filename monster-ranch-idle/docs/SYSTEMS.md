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
| Expeditions | S4 | ⬜ | | |
| Boss | S4 | ⬜ | | |
| Breeding | S5 | ⬜ | | |
| Weather | S5 | ⬜ | | |
| Social | S5 | ⬜ | | |
| Trade | S5 | ⬜ | | |
| Plots | S5 | ⬜ | | |
| Monetization | S6 | ⬜ | | |
| Quests | S6 | ⬜ | | |
| HallOfFame | S6 | ⬜ | | |
| World (geometry) | C1 | ⬜ | Studio | |

## Client

| Piece | Workstream | Status | Notes |
|---|---|---|---|
| ClientKernel, Store, NetClient, Router, Layers | K | 🟩 | |
| UI kit (Theme, Create, Anim, Button, Panel, Icon, Widgets, Toasts, MonsterIcon) | K | 🟩 | |
| Visuals: MonsterModel, EggModel | K | 🟩 | procedural placeholders |
| Visuals: MonsterAnimator | C1 | ⬜ | |
| Controllers: World, Weather, Interaction | C1 | ⬜ | |
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
