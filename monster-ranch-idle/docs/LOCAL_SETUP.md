# Working on your own computer

Everything needed to build, test and keep developing Monster Ranch Idle locally, on Windows,
macOS or Linux.

## 1. Install the tools

| Tool | What for | Get it |
|---|---|---|
| Git | the code | <https://git-scm.com/downloads> |
| Rokit | installs the pinned rojo, lune, stylua and selene | see below |
| Roblox Studio | play and publish | <https://create.roblox.com> |
| Node.js 20+ and Google Chrome | only for the snapshot tool | <https://nodejs.org> |
| Claude Code | keep building with Claude | <https://claude.com/claude-code> |

Install Rokit:

```powershell
# Windows (PowerShell)
Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
```

```sh
# macOS / Linux
curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
```

Open a new terminal afterwards so `rokit` is on your PATH.

## 2. Get the code

```sh
git clone --branch main https://github.com/ssimilize/new.git monster-ranch
cd monster-ranch/monster-ranch-idle
rokit install        # answer yes when it asks to trust the tools
```

`main` has every merged update. Clone it by name: the repository's default branch is an older
one without `.gitattributes`, and starting there leaves Windows files with CRLF line endings
that `stylua --check` rejects. Line endings are pinned to LF by `.gitattributes`, so a clone of
`main` passes the formatter check on Windows too.

## 3. Check that it works

```sh
lune run tests       # the whole suite, about 2–3 minutes: "468 passed, 0 failed"
lune run tests/lint
selene src tests
stylua --check src tests
```

## 4. Play it in Studio

```sh
rojo plugin install  # once: installs the Rojo plugin into Studio
rojo serve           # the ranch place
```

Open Studio with a new Baseplate, click **Rojo → Connect**, then Play. Turn on
**Game Settings → Security → Enable Studio Access to API Services** so saving works (without it
the game runs on an in-memory store and says so in the output).

To try the Trading Hub place instead, run `rojo serve hub.project.json`. Place files:
`rojo build -o build.rbxl` (ranch) and `rojo build hub.project.json -o hub.rbxl` (hub).
Publishing both places: `GO_LIVE.md`.

## 5. Pictures without Studio (optional)

```sh
lune run tools/snapshot/scene tools/snapshot/scene.json          # add a screen name, e.g. Clubs
cd tools/snapshot && npm install && node render.mjs scene.json ranch.png
```

The renderer uses your installed Google Chrome (or the browser in `CHROMIUM_PATH`).

## 6. Keep building with Claude

Start Claude Code in the repository root (the folder that has `CLAUDE.md`):

```sh
cd monster-ranch
claude
```

`CLAUDE.md` gives it the layout, the checks to run before every commit, the harness gotchas
and where the roadmap stands, so you can say "start 3.2" and carry on. You can also run the
session from the Claude Desktop app, or run `claude remote-control` in that folder so the local
session shows up in the Claude Code app on your phone.

`.claude/settings.json` pre-approves the read-only and check commands (tests, lint, format,
build, git status/diff/log), so Claude asks less often while it works.
