# Go live

How to publish Monster Ranch Idle and what to check on real Roblox servers. The Lune test
suite runs every system against mocks (`tests/runtime/MockAdapters.luau`). The steps below
cover what only a live server can prove: the `VERIFY` comments in `src/server/Kernel/Adapters.luau`.

## 1. Publish both places (update 3.0.1)

The game is one universe with two places built from the same source:

| Place | Build | Name it (Creator Hub) |
|---|---|---|
| Ranch (start place) | `rojo build -o build.rbxl` | `Monster Ranch Idle` |
| Trading Hub | `rojo build hub.project.json -o hub.rbxl` | `Trading Hub` |

1. Publish `build.rbxl` as the universe's start place.
2. In Creator Hub, add a second place to the same experience and publish `hub.rbxl` to it.
3. Name the places exactly as above. Travel and Return find each other by these names
   (`Config.TradingHub.PlaceNames`), so no place ids need copying into code. If you rename a
   place, update `PlaceNames` or pin the id in `Config.TradingHub.PlaceIds`.
4. Turn on **Enable Studio Access to API Services** for testing, and make sure DataStores and
   MemoryStores work in both places (same universe, so no third-party teleport setting is needed).
5. The hub place's Workspace carries the attribute `PlaceMode = "hub"` (set by
   `hub.project.json`): it builds the hub layout and hands out no ranch plots.

## 2. Live checks

Run these with at least two servers of each place (a private server plus a public one).

| Check | How | Pass |
|---|---|---|
| Travel to the hub | Ranch Level 8+, Trading Hub portal → Travel | Arrive in the hub with the same monsters and currencies |
| Back to ranch | Hub → Back to ranch | Arrive on the ranch; coins earned while away are there |
| Teleport retry | Travel while the hub place is full / restarting | Retries (up to 2) or a clear error; never a stuck screen |
| Trade Board across servers | Post an ad on hub server A, refresh on hub server B | The ad shows on B within `RefreshSeconds` (15 s), with **Meet** |
| Meet on another server | Meet the ad from B | Teleported into server A; a trade request works there |
| Ad clean-up | Poster leaves or trades | The ad disappears from every server |
| MemoryStore budget | Watch the MemoryStore quota page with 5+ hub servers | Board reads (1 per server per 15 s) stay well under quota |
| Workshop budget | 10+ players browsing the gallery | No DataStore throttling warnings; records come from the 60 s cache |
| Royalties | Buy a copy on another server, claim on the designer's | One ledger write per purchase, one per claim |
| Moderation | Add your user id to `Config.Workshop.Moderators` (or set `ModeratorGroup`), report a design 3 times | It leaves the gallery and shows under Workshop → Gallery → Review |
| Frostfall rerun | Set `Flags.ActiveEvent = "frostfall"` in a private server | Event egg, decor, Snow boost and the Tinselkit line appear |
| Market / Arena / Ads | See the `VERIFY` comments in `Adapters.luau` | Paging and quotas behave as the comments expect |

## 3. Update 3.2 (Frostbite Glacier + Level 70)

- **Publish before Sat 4 Mar 2028, 15:00 UTC**, when Ranch Pass Season 8 starts. The Glacier,
  the Frost Leviathan and the Level 70 cap switch on by themselves on 11 Mar.
- **Languages:** the game ships its own Spanish and Portuguese (`docs/LOCALIZATION.md`). In
  Creator Hub → Localization, leave automatic text capture and automatic translation **off**
  for Spanish and Portuguese, so Roblox never translates a second time. It is safe to add
  Spanish and Portuguese as supported languages for the experience's page.
- **Live checks:**

| Check | How | Pass |
|---|---|---|
| Language by locale | Join with a Roblox account set to Español, then to Português | Menus, toasts and signs are in that language; monster names stay English |
| Language setting | Settings → Language → English, then rejoin | The choice sticks across servers |
| Controller | Play with an Xbox or PlayStation pad in Studio or on console | The cursor stays in the open menu, B closes it, LB/RB change tabs, Y opens Monsters; racing and surfing work on the pad |
| Controller legend | Look at the corner hint with a pad | The Ⓐ Ⓑ Ⓨ glyphs render in the font (if not, swap them for "A" / "B" / "Y") |

## 4. After launch

- Keep `Config.Workshop.Moderators` (or the moderator group) staffed: hidden designs wait in
  the Review queue until someone restores or removes them.
- Every region and event has a date in config (`Regions.opensAt`, `Events` windows and
  `reruns`), so the quarterly region openings and event returns need no code push.

## 5. Login streak and reminders (glow-up)

The daily streak calendar needs nothing from the owner. Reminders (Roblox Experience
Notifications) stay **off** until these steps are done; with `Config.Reminders` empty the game
never prompts, plans or sends anything.

1. **Enable HTTP requests**: Creator Hub → the experience → Settings → Security → *Allow HTTP
   Requests* on (the server calls `apis.roblox.com`). MemoryStores are on by default.
2. **Create the message templates**: Creator Hub → the experience → Engagement →
   Notifications → *Create notification*. One per reminder, no parameters needed, e.g.
   - egg: "Your eggs are ready to hatch! 🥚"
   - expedition: "Your expedition squad is back with loot!"
   - stampede: "A Stampede starts in 5 minutes. Join the herd!"
   - streak: "Your daily streak ends soon. Claim today's reward!"
   Copy each notification's **asset id** into `Config.Reminders.Templates` (`egg`, `expedition`,
   `stampede`, `streak`). Leave one empty to turn that reminder off.
3. **Create an Open Cloud API key**: Creator Hub → Open Cloud → API Keys → *Create API key*,
   add the **user-notification** API system with **write** access for this experience (and
   allow the Roblox servers' IPs, e.g. `0.0.0.0/0`, since game servers call it).
4. **Store the key as a secret**: Creator Hub → the experience → Secrets → *Create secret*,
   name it (for example `notifications_key`) and paste the key. Put that name in
   `Config.Reminders.SecretName`. In Studio, `HttpService:GetSecret` reads the local secrets
   from Game Settings → Security instead; without them the feature stays off in Studio.
5. Publish. Players are asked once (after their first hatch in a later session) and can turn
   reminders on or off from the Daily streak screen.

What the game sends: at most `MaxPerDay` (2) reminders per player per UTC day, at least
`MinGapSeconds` (4 h) apart, none while the player is in the game, and none between 22:00 and
08:00 in a rough local time guessed from the player's country (`Config.Reminders.Offsets`;
countries not listed get no quiet-hours rule). Roblox also throttles notifications per user on
its side and only delivers to players who opted in.

| Check | How | Pass |
|---|---|---|
| Streak claim | Join, claim, rejoin the same UTC day on another server | Claimed once; the calendar does not open again; the HUD badge is gone |
| Streak day change | Stay in the game across 00:00 UTC | The Daily badge comes back; a claim pays the next day |
| Opt-in prompt | Second session, hatch an egg | Roblox's notification prompt shows once; never again after answering |
| Egg reminder | Opt in, start a 1 h egg, leave | One notification about 1 h later (or at 08:00 local), opening the game |
| One send across servers | Two servers running while a reminder falls due | Exactly one notification |
| Off switch | Clear `SecretName` and publish | No prompt, no Reminders button, no sends |

