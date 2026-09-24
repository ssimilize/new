# Conventions & Definition of Done

## Commands

```bash
rokit install                 # installs rojo, lune, stylua, selene (versions in rokit.toml)
lune run tests                # unit + system tests (Lune, no Studio needed)
lune run tests Economy        # only specs whose file/name matches "Economy"
lune run tests/lint           # syntax-check every .luau file (client code too)
selene src tests              # lint (std = roblox_min; use `std = "roblox"` if you generated it)
stylua src tests              # format
rojo serve                    # live-sync into Studio
rojo build -o build.rbxl      # build a place file
```

## Code style

- Luau, formatted with StyLua (tabs, 140 columns). Every file starts with a header comment saying what it owns.
- Modules return a table. Public methods use `:` (`Currency:Add(...)`). Private helpers are `local function`.
- Names: systems, controllers and screens are `PascalCase` and match their folder or file name. Config keys are `camelCase`; content ids are `snake_case` or lower-case words (`"cindlet"`, `"hay_bale"`).
- Player-facing text is plain, short and specific: "Not enough coins", "Unlocks at Ranch Level 12". No jargon, no apologies.
- Comments explain *why*, not *what*.

## Boundaries (what makes parallel work safe)

1. Only edit files your workstream owns (see `DEVELOPMENT_PLAN.md` §3). If you need a change elsewhere, write it down in your hand-off notes instead of editing.
2. Shared files you *may* append to (never edit or delete others' lines):
   - `src/shared/Kernel/Api.luau` for new actions and events under your own system prefix
   - `src/shared/Config/<YourTopic>.luau` for new keys your systems need
   - `docs/SYSTEMS.md` for your own rows
3. Never change `src/server/Kernel/*`, `src/client/Kernel/*` or `tests/runtime/*`. Ask the kernel owner instead.
4. Plug-in lines in `Manifest.luau` are added by the integrator after the tests pass.

## Definition of done (per system)

- [ ] Implements every action and public method listed for it in `ARCHITECTURE.md`.
- [ ] Pure rules live in `src/shared/Logic` with unit tests.
- [ ] A system spec (`tests/specs/<Name>.spec.luau`) boots the system with `TestKernel`, covering the happy path, each failure message, offline or rejoin behaviour where relevant, and the exploit cases (not owned, busy, locked, can't afford, too fast).
- [ ] `lune run tests`, `lune run tests/lint` and `selene src tests` are clean.
- [ ] No Roblox service calls outside `ctx.Services` (server).
- [ ] Row updated in `SYSTEMS.md`.

## Client code (can't run in Lune)

- Must pass `lune run tests/lint` and `selene`.
- Build UI only with the UI kit (Theme, Create, components) so reskinning stays a Theme change.
- Read state only through `ctx.Store`; change state only through `ctx.Net:Request`. Never assume a request succeeded: show `ctx:Toast(err, "error")` on failure.
- Disconnect Store observers and loops when a screen is destroyed. Screens are built once and reused.
- Mobile first: 44 px minimum tap targets, the key action in the bottom-centre thumb zone, text ≥ 15 px at design size.
