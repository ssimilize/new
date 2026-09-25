# Updates

Content and system changes shipped after launch, newest first. Each update lists what
players get and where it lives in the code.

## 1.2 · Clubs + Lunar Lanterns

**For players**
- **Clubs** (Ranch Level 8, 50K coins to start one):
  - Up to 30 members across every server. Join with a 6-letter code, or tap Join on an open club of someone on your server.
  - Roles: the owner promotes, demotes or hands over the club; officers can remove members and change settings.
  - Each club picks a name, a tag, a colour and an emblem, and its tag shows above members' heads.
  - Open the Club Plaza in the Market Square, or tap the Clubs button on the HUD.
- **Weekly club goals:** three goals each week, drawn from hatching, stage clears, Stampedes, expedition hours, breeding, petting and feeding. Targets grow with the club. Every member claims each finished goal once: 30 gems, then a Grove Egg with 20 Treats, then a Crystal Egg.
- **Weekly club boss:** everyone gets 3 attacks a day. Damage grows with the square root of squad power, so newer players still count. When it falls, everyone who attacked claims a Stampede Egg and 50 gems.
- **Lunar Lanterns event** (6–27 Feb 2027):
  - **Lantern Coins:** earned by playing (daily login, Stampedes, expeditions, first stage clears, hatches), up to 300 a day.
  - **Lantern Egg** (400 coins, always Glow): hatches the Lantern Dragon line (Lanternling → Lanternwyrm → Lantern Dragon), Mochibun and Wickit.
  - **Lantern Night:** night-only event weather that gives the new **Glow** mutation (×3).
  - **Decor:** Paper Lantern and Moon Gate, plus the Lantern Garden pen theme.
- **Nameplates:** club tags and leaderboard champion titles now appear together above players.

**In the code**
- **Events:**
  - `Config/Events` is the event calendar. `Flags.ActiveEvent` now overrides it: an id forces that event, `false` turns events off.
  - Everything reads the running event through `Config.Events.ActiveId(now)`. On the client that goes through `StoreKit.activeEvent()`.
  - The `Events` system publishes `global.Events` and pays tokens for play, with a daily cap.
- **Clubs:**
  - The `Clubs` system keeps records in their own DataStore through `Services.Clubs`, which uses atomic Update. The rules are pure functions in `Systems/Clubs/Record.luau`.
  - Contributions are batched and written every 60 s, and each write is announced over Messaging (`Clubs`) so other servers re-read that club.
  - Players see `session.Clubs` (their club view) and `global.Clubs.here` (club tags of players on this server).
- **Client:**
  - A new Clubs screen, a Club Plaza building, and a Clubs button on the HUD's right stack.
  - A new Nameplates controller draws both club tags and champion titles. The Leaderboards controller now only draws the board.
  - `WeatherRoll` skips weather marked `event` unless that event is running.
- **Tests:**
  - `Clubs.spec`: record rules, and two servers sharing one club store.
  - `LunarLanterns.spec`
  - Client tests: the UI during the event, and a two-player club flow.
  - Mock servers can now share a network (`MockAdapters.network()`) for cross-server tests.

## 1.1 · Coral Depths

**For players**
- **Coral Depths:** Coral Coast now has stages 21–30, a deeper band that unlocks at Ranch Level 22 once stage 20 is cleared. It is about as tough as early Ember Peaks.
- **New bosses:** Old Snapjaw (stage 25) and The Abyssal Lantern (stage 30). The first clear of each gives Pearl Eggs.
- **Pearl Egg:** drops from Depths expeditions and hatches only the three new lines:
  - **Shellsnap** (Tide) → Clawcrest → Tidecrusher (sour diet) or Pearlguard (sweet diet)
  - **Jellow** (Spark) → Glimmerjel → Voltmedusa
  - **Anglit** (Tide + Spark) → Lanternfin → Abyssangler
- **Pearl mutation:** Soaked + Starstruck combine into Pearl (×5).
- **Beach decor set:**
  - Decor: Sandcastle, Beach Umbrella, Shell Pile, Tide Pool
  - Pen theme: Beach Boardwalk
- **New achievements:**
  - Clear the Coral Depths
  - Hatch 5 Pearl Eggs
  - Get the Pearl mutation
- **Code:** `CORALDEPTHS` gives a Pearl Egg and 50 gems. It expires on 6 Feb 2027.

**In the code**
- `Config/Regions`: a region can have its own `stages` count and an optional `depths` band. The band has its own unlock, levels, rarity, enemy lines, colours and global index. Read these through `Regions.Stages`, `Regions.Band`, `Regions.MaxStages` and `Regions.GlobalIndex`. A boss can also have `firstClear` rewards.
- `Logic/BattleSim` scales enemies and builds waves from the stage's band.
- `Systems/Expeditions` rejects stages past the region's count, and stages in a locked band.
- The API bound for stages is now `Regions.MaxStages`.
- The Expeditions screen has Coast / Depths map pages.
- `Config/Species` marks new lines with `added = "1.1"`. `Config/Eggs` has the `pearl` egg, `Config/Mutations` the `pearl` combo, and `Config/Decor` the beach set.
- Decor now has a `shape` field, which the World controller uses to draw it.
- The Leaderboards "Highest stage" board uses `Regions.GlobalIndex`, so clearing Depths stage 30 counts as stage 60.
- Tests: `CoralDepths.spec`, and the client test "switches the Expeditions map to the Coral Depths".
