# Monster Ranch Idle — Development Plan

This plan turns the [game design document](../../docs/roblox-game-concepts/monster-ranch-idle.html) into a codebase that several people can build **at the same time**. Every game system is a separate module with a fixed contract. A system is built and tested on its own, then **plugged into the kernel** by adding one line to a manifest.

- Architecture and contracts: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- Coding rules and definition of done: [`CONVENTIONS.md`](CONVENTIONS.md)
- System status board: [`SYSTEMS.md`](SYSTEMS.md)

---

## 1. Principles

1. **The kernel is small and stable.** It owns lifecycle, dependency checks, save data, networking, state replication, the event bus and the Roblox service adapters. Game rules never live in the kernel.
2. **Systems only talk through contracts.**
   - Client ↔ server: only through the actions, events and state paths declared in `src/shared/Kernel/Api.luau`.
   - System ↔ system: through the public methods a system exports (declared in its `Dependencies`) or through bus topics listed in `Api.Topics`.
   - Nobody reaches into another system's internals or another system's part of the save file.
3. **Content is data.** Species, eggs, regions, weather, traits, prices and unlocks are config tables in `src/shared/Config`. Designers change numbers without touching systems.
4. **Pure logic is separate from Roblox.** Anything with maths or rules (battle simulation, egg rolls, breeding, offline accrual, formulas) goes in `src/shared/Logic`. It has no Roblox dependencies and is unit-tested in Lune.
5. **Placeholder art is behind an interface.** Monsters, eggs, the world and animations are built procedurally now. The art team swaps them later by replacing the builders in `src/client/Visuals`, without changing gameplay code.

## 2. Architecture at a glance

```
            ┌──────────────────────── shared (ReplicatedStorage.Shared) ─────────────────────────┐
            │  Kernel/Api  (the contract)   Config/* (content)   Logic/* (pure rules)   Kernel/T  │
            └────────────────────────────────────────────────────────────────────────────────────┘
                    ▲                                                        ▲
┌───────────────────┴─────────────── server ──────┐    ┌─────────────────────┴──────── client ─────────────┐
│ Kernel: lifecycle · Data · Net · State · Bus    │    │ ClientKernel: lifecycle · Net · Store · Bus       │
│         Adapters (DataStore, Marketplace, …)    │◄──►│   Controllers/*  (HUD, World, Screens router …)   │
│ Manifest.luau  ──►  Systems/<Name>/init.luau    │    │   UI kit · Screens/* · Visuals (models, anims)    │
└─────────────────────────────────────────────────┘    └───────────────────────────────────────────────────┘
```

**Plugging in a system** means adding its folder name to `src/server/Manifest.luau` (server) or `src/client/Manifest.luau` (client). The kernel sorts systems by their declared dependencies, calls `Init` on all of them, then `Start`, then runs per-player hooks. A system missing from the manifest is simply not loaded, so half-built systems never break the game.

## 3. Workstreams (built in parallel)

Each workstream owns a disjoint set of folders. Workstreams depend only on the kernel, the shared contract and config, and the **public API** of the systems they list, which is fixed in `ARCHITECTURE.md`.

| # | Workstream | Owns | Depends on (public API only) |
|---|---|---|---|
| **K** | Kernel & foundation | `src/*/Kernel`, `Config`, core `Logic`, UI kit, Visuals builders, test runtime | — |
| **S1** | Economy core | `Systems/Currency`, `Systems/Progression` | Kernel |
| **S2** | Monsters | `Systems/Monsters`, `Systems/HallOfFame`, `Logic/Stats`, `Logic/Growth` | S1 |
| **S3** | Ranch & eggs | `Systems/Ranch`, `Systems/Eggs`, `Systems/Shop`, `Systems/WelcomeBack`, `Logic/EggRoll`, `Logic/Restock`, `Logic/Jar` | S1, S2 |
| **S4** | Adventure | `Systems/Expeditions`, `Systems/Boss`, `Logic/BattleSim`, `Logic/Loot` | S1, S2, S3 (Eggs) |
| **S5** | Social & world | `Systems/Breeding`, `Systems/Weather`, `Systems/Social`, `Systems/Trade`, `Systems/Plots`, `Logic/Breeding`, `Logic/Mutation` | S1, S2, S3 |
| **S6** | Live-ops & money | `Systems/Monetization`, `Systems/Quests`, `Systems/Analytics` | S1, S3 (Eggs) |
| **C1** | Client world | `Controllers/World`, `Controllers/Weather`, `Controllers/Camera`, `Visuals/*` animation and effects | Contract |
| **C2** | Client screens A | HUD, Egg Shop, Incubators and hatch reveal, Monsters (roster and detail), Ranch management, Welcome Back, Codex | Contract, UI kit |
| **C3** | Client screens B | Expeditions and battle replay, Breeding, Trade, Stampede, Hall of Fame, Quests, Store, Settings | Contract, UI kit |

Because the contract fixes every request name, payload and state path before any system is written, client teams build screens against the contract while server teams implement it. A client screen calling an action whose system isn't plugged in yet gets a clean `NotAvailable` error, not a crash.

## 4. Milestones

| Milestone | Scope | Exit criteria |
|---|---|---|
| **M0 · Foundation** (week 1) | Kernel, contract, config, UI kit, placeholder visuals, test runtime | Empty game boots; saves and loads a profile; the test runner is green |
| **M1 · Vertical slice** (weeks 1–2) | Currency, Progression, Monsters, Eggs, Shop, Ranch, WelcomeBack, HUD, Shop, Hatch, Roster | Hatch a starter, collect coins, buy an egg, grow a monster, leave and come back to offline earnings |
| **M2 · Alpha** (weeks 3–8) | Expeditions, Boss, Breeding, Weather, Plots, Social, Quests, all screens, world renderer | The whole GDD loop is playable on a phone with placeholder art |
| **M3 · Beta** (weeks 9–11) | Trade, Monetization, Analytics, balance, tutorial polish | Closed test with 100–300 players; D1 and tutorial funnel measured |
| **M4 · Launch** (week 12) | Frostfall event content, live config values, real asset IDs | Launch checklist in `SYSTEMS.md` complete |

## 5. How a system is built (every workstream)

1. Read `ARCHITECTURE.md` for the system contract and your system's public API.
2. Put pure rules in `src/shared/Logic/<Name>.luau` and unit-test them in `tests/specs/<Name>.spec.luau`.
3. Write the system in `src/server/Systems/<Name>/init.luau`. It uses only the kernel, `Config`, `Logic` and its declared dependencies.
4. Write a system test using `MockKernel`. It plugs in only your system and its dependencies, fakes players and time, and calls your actions through `kernel.Net:Invoke`.
5. Add the folder name to `Manifest.luau` to plug it in. Run `lune run tests` and the lint script.
6. Update the status row in `SYSTEMS.md`.

## 6. Toolchain

| Tool | Use |
|---|---|
| **Rojo 7** | Syncs `src/` into Studio (`rojo serve`) or builds a place file (`rojo build -o build.rbxl`) |
| **Lune** | Runs unit and system tests outside Roblox (`lune run tests`) |
| **StyLua** | Formatting (`stylua src tests`) |
| **Selene** | Linting (`selene src`) |

Versions are pinned in `rokit.toml`. See the repository README for setup.

## 7. Art and audio later

All placeholder visuals go through three builders. The art team replaces their internals without touching any gameplay code:

- `Visuals/MonsterModel.Build(appearance)` returns a `Model` with a `PrimaryPart` and named attachments.
- `Visuals/EggModel.Build(eggType)` returns a `Model`.
- `Visuals/MonsterAnimator.new(model)` exposes `:Play(state)` for `idle`, `walk`, `happy`, `eat`, `attack`, `hurt` and `sleep`. The procedural animations are replaced by authored `AnimationTrack`s later.

UI images work the same way. Components draw with shapes and gradients now, and the art team can set image IDs in `UI/Theme.luau` (`Theme.Images`) when real sprites exist. Sounds are listed in `Config/Sounds.luau` with empty IDs, so every sound call is a no-op until audio is added.
