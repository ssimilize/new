# Monster Ranch Idle: working notes for Claude Code

An idle RPG creature ranch for Roblox, written in Luau and synced with Rojo. The game lives in
`monster-ranch-idle/`; the design document and roadmap are in
`docs/roblox-game-concepts/monster-ranch-idle.html` (§18 is the roadmap). Setting up a computer:
`monster-ranch-idle/docs/LOCAL_SETUP.md`.

## Commands (run from `monster-ranch-idle/`)

```sh
rokit install                          # rojo, lune, stylua, selene (pinned in rokit.toml)
lune run tests                         # full suite, ~2–3 minutes; no Studio needed
lune run tests ClubWars                # only specs whose file or test name matches
stylua src tests                       # format (tabs, 140 columns, LF)
rojo serve                             # live-sync into Studio (Rojo plugin)
```

Before every commit, all of these must be clean (CI runs the same list):

```sh
stylua --check src tests
lune run tests/lint
selene src tests
rojo build -o build.rbxl
rojo build hub.project.json -o hub.rbxl
lune run tests
```

## How the code fits together

- `src/server/Kernel`: lifecycle, saves, validated networking, state replication, bus. Systems touch Roblox only through `ctx.Services` (`Kernel/Adapters.luau`; tests swap in `tests/runtime/MockAdapters.luau`).
- `src/server/Systems/<Name>/init.luau`: one system per folder, plugged in by `src/server/Manifest.luau`. Each file starts with a header describing its save section, session/global state, actions, bus topics and public API. Keep that header accurate.
- `src/shared/Kernel/Api.luau`: the contract. Every action (schema + rate), event, state root and bus topic is declared here first; the kernel rejects anything else.
- `src/shared/Config/*`: all content and tuning as data. Dates are Saturdays 15:00 UTC; regions (`opensAt`), events (`startsAt/endsAt`, `reruns`) and Ranch Pass seasons are date-gated, so updates can ship before their launch day.
- `src/shared/Logic/*`: pure rules shared by server and client (unit-tested).
- `src/client`: client kernel, UI kit (`UI/Theme`, `UI/Create`, `UI/Components`), screens (`UI/Screens`, listed in `src/client/Manifest.luau`), controllers, placeholder visuals.
- `tests/specs/*.spec.luau`: `TestKernel` boots real systems on mocks; `ClientHarness` runs the real client in a reflection-checked Roblox mock. `Client.spec` clicks every button on every screen and checks a 568×320 phone fit.
- `tools/snapshot`: renders a picture of the game without Studio (see its README).

## Building an update (the pattern every update so far followed)

1. Config (content, numbers, dates) → Logic (pure rules) → System (server) → `Api.luau` → both Manifests → Screen / controller.
2. Specs: a server spec (`tests/specs/<Update>.spec.luau`) for rules, failures and exploits, and a client spec that plays the feature through the UI.
3. Text: every new player-facing string is one literal or one `string.format`, added in English, Spanish and Portuguese to `src/shared/Locale/es.luau` and `pt.luau` (`monster-ranch-idle/docs/LOCALIZATION.md`). `LOCALE_REPORT=missing.txt lune run tests Locale` lists anything still untranslated; `Locale.spec` and `LocaleClient.spec` fail on it.
4. Docs: `monster-ranch-idle/docs/UPDATES.md` (players + code), `ARCHITECTURE.md` (new adapters / contracts), `SYSTEMS.md` rows, and the roadmap card tag in the design doc (`built` when merged, `shipped` when live).
5. A snapshot of the new screen in `monster-ranch-idle/docs/snapshots/`.
6. One branch and one pull request per update; merge once CI is green.

## Test-harness gotchas

- Actions are rate-limited: call `h:Advance(2)` between repeated calls or you get `TooFast`.
- `h:Call` / `h:Client(p)` read the test mirror; once a `ClientHarness` is attached, read client-visible state with `c:Store(path)` and change it with `c:Request(...)`.
- `h:LastEvent(p, name)` returns `{ name, payload }`.
- `expect` has no `.never`; write `expect(a ~= b).toBe(true)`.
- Cross-server features share stores through `MockAdapters.network()` passed to several `TestKernel.new({ network = net })`.
- Hub-place tests use `TestKernel.new({ placeMode = "hub" })`.
- A client in another language: `ClientHarness.new(h, p, { localeId = "es-mx" })` (or `"pt-br"`). Text you look up with `c:Button` / `c:HasText` is then the translation.
- Gamepad: `c:UseGamepad(true)`, `c:Press(Enum.KeyCode.ButtonB)`, `c:Stick(x, y)`, `c:Selected()`.

## Where things stand

- Merged on `main`: launch through 3.0 (Year Two), 3.0.1 (go-live, Frostfall returns) and 3.1 (Club Wars + Lunar Lanterns).
- 3.2 (Frostbite Glacier + Level 70: Ranch Level 70, raid 3, controller support, Spanish and Portuguese) is on branch `update-3.2-frostbite-glacier` for its pull request. It must be published before Season 8 starts (Sat 4 Mar 2028).
- Next on the roadmap: **3.3 · Spring Bloom + Design Weeks** (Sat 1 Apr 2028): themed Workshop weeks with community votes, player-designed pen themes, and Spring Bloom's return with a new egg-hunt layout.
- Manual go-live steps (publishing both places, live checks, moderators): `monster-ranch-idle/docs/GO_LIVE.md`.
