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
