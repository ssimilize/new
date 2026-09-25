# Monster Ranch Idle (Roblox)

Idle RPG creature ranch: hatch monsters, raise them, send them on expeditions while you sleep, breed hybrids, catch weather mutations and trade with friends. Design: [game design document](../docs/roblox-game-concepts/monster-ranch-idle.html).

## Start here

1. [`docs/DEVELOPMENT_PLAN.md`](docs/DEVELOPMENT_PLAN.md): how the work is split so systems can be built at the same time
2. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): kernel, system contract, every public API, and the client contract
3. [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md): commands, boundaries, definition of done
4. [`docs/SYSTEMS.md`](docs/SYSTEMS.md): status board
5. [`docs/UPDATES.md`](docs/UPDATES.md): post-launch updates (1.1 Coral Depths)

## Setup

```bash
rokit install          # rojo, lune, stylua, selene
lune run tests         # all tests, no Studio needed (includes the real client in a mock Roblox runtime)
rojo serve             # then connect from the Rojo Studio plugin
```

In Studio, turn on **Game Settings → Security → Enable Studio Access to API Services** so saves work. Without it the kernel uses an in-memory store and warns in the output.

## How it fits together

- **Kernel** (`src/server/Kernel`): lifecycle, session-locked saves, validated networking, state replication, event bus.
- **Systems** (`src/server/Systems/*`): game rules, one folder each, plugged in through `src/server/Manifest.luau`.
- **Contract** (`src/shared/Kernel/Api.luau`): every client ↔ server action, event and state path.
- **Content** (`src/shared/Config/*`): species, eggs, regions, weather, prices, all as data.
- **Client** (`src/client`): client kernel, UI kit, screens and controllers, plus placeholder 3D visuals that the art team replaces later.
