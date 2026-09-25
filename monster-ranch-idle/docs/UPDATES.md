# Updates

Content and system changes shipped after launch, newest first. Each update lists what
players get and where it lives in the code.

## 1.5 · Showtime

**For players**
- **Accessories** (Wardrobe at Ranch Level 3): 39 hats, glasses, scarves, capes, wings and more in four slots (head, face, neck, back), drawn on your monster everywhere it appears.
  - Open the Wardrobe with the new **Style** button on any monster, or from the Showtime screen.
  - Buy them with gems or with **Contest Ribbons**, the new currency.
  - Accessories stay yours: when a monster is sold, traded, listed, retired or left behind in a rebirth, whatever it wore goes back to your storage.
  - The Starter Pack now includes the Sprout Cap.
- **Monster Contests** (Ranch Level 7), at the new Showtime Stage in the Market Square:
  - A themed show every 10 minutes, with the same theme on every server. There are 10 themes, such as Royal Ball, Spooky Night, Beach Day, Space Explorers and Superheroes.
  - **Entry (90 s):** enter one monster and dress it to fit the theme. You can switch or withdraw until the runway starts, and that is when outfits lock in.
  - **Runway:** each entry walks the stage for 8 seconds while everyone else rates it 1–5 stars.
  - **Results:** score = 70% votes + 30% the theme judge, who rewards accessories that fit the theme. On a quiet server the judge decides alone.
  - **Prizes:** 1st 30 Ribbons + 15 gems, 2nd 20 + 10, 3rd 12 + 5, everyone else who entered 5. Every runway walk you rate gives 1 Ribbon (up to 5 a show).
- **Ranch Pass Season 3, "Showtime"** (15 May – 26 Jun 2027): accessories on both tracks, including the pass-only Rainbow Wings and Starlight Crown.
- **New achievements:** win a contest, enter 10, vote on 25 walks, and collect 10 accessories.
- **Code:** `SHOWTIME` gives a Party Hat and 25 Ribbons. It expires on 26 Jun 2027.

**In the code**
- **Accessories:**
  - `Config/Accessories` and the `Accessories` system.
  - `Monster.acc` is worn items, set only through `Monsters:SetAccessory`. `Monsters:Remove` strips it into the `MonsterRemoved` detail, and `Monsters:Insert` clears it.
  - `Appearance.Of` carries `acc`, and `Visuals/MonsterModel` draws placeholder shapes for every accessory.
  - The `ribbons` Currency key and Rewards kind, and the `accessory` Rewards kind.
- **Contests:**
  - `Config/Contests` (the schedule on the unix clock, themes, judge, prizes) and the `Contests` system.
  - Per-server state in `global.Contests`; votes are kept in server memory only.
- **Client:**
  - New Wardrobe and Contests (Showtime) screens, and a Showtime controller that stands the walking monster on the stage.
  - A Showtime Stage hub building, and a Style button on the monster screen.
  - A Ribbon icon.
- **Ranch Pass:** Season 3 is added to `Config.Quests.Seasons`.
- **Tests:**
  - `Showtime.spec`
  - `ShowtimeClient.spec`: buying and wearing through the Wardrobe; every accessory built on every body shape against the Roblox API database; a two-player show that enters, walks, votes and reaches the podium.

## 1.4 · Rebirth + Spring Bloom

**For players**
- **Ranch Rebirth** (Ranch Level 40, always optional). Visit the new Star Altar in the Market Square, or tap ★ Rebirth in the Hall of Fame.
  - **Needs** 50M coins in hand for the first star (×3 for each star after that).
  - **Resets:** coins, pens and every ranch upgrade, the garden and region progress. Placed decor goes back to storage.
  - **Keeps:** Ranch Level, Codex, Hall of Fame, gems and other currencies, eggs, decor and themes, passes, and your Heirlooms: 3 monsters you choose, +1 per Rebirth Star.
  - **Your other monsters become Stardust** at 50% of their Hall of Fame value (more for higher stars).
  - **Gains:** a Rebirth Star (coins ×1.5 with one, ×2 with two, and so on), a new biome pen theme per star (Starfield Meadow, Crystal Tundra, Aurora Isle, Sunset Mesa, Nebula Drift), the Celestial Egg from the first star, and from 3 stars a 3rd visible trait on every monster.
  - The confirmation shows exactly what you keep, what you lose and the Stardust you get.
- **Stardust skill tree:** three branches of three skills.
  - Ranch: Golden Touch (coins), Deep Pockets (jar time), Head Start (coins after each rebirth).
  - Hatchery: Warm Hands (hatch speed), Twin Nests (+1 breed a day), Star Sifter (more Stardust from rebirths).
  - Adventure: Trailblazer (expedition loot), War Paint (Stampede damage), Family Vault (more Heirlooms).
  - Deeper skills need the one above them, and some need Rebirth Stars.
- **Celestial Egg** (6M coins, needs a Rebirth Star): Rare or better, hatching three new lines:
  - Cometkit → Meteorlynx → Supernova
  - Moonmoth → Eclipsewing → Nebula Moth
  - Orbiton → Asterock → Planetitan
- **Spring Bloom event** (3–24 Apr 2027), with **Petals** as its token:
  - **Pollen Storm:** daytime event weather that gives the new **Blossom** mutation (×3) and makes gardens grow 1.5× faster.
  - **Egg hunt:** 4 painted eggs hide around the Market Square every 20 minutes. Each one pays 10 Petals, finding all 4 pays 20 more, and you can find up to 40 a day.
  - **Bloom Egg** (400 Petals, always Blossom): Budling → Petalhop → Bloomhare, Pollenpuff → Buzzbloom → Pollen Monarch, and Tulipup → Dewfox → Rainbloom Fox.
  - **Decor:** Tulip Patch and Bloom Arch, plus the Blossom Glade pen theme.
- **Ranch Pass Season 2, "Spring Stars"** (3 Apr – 15 May 2027): Stardust, spring decor, a Celestial Egg, and a Legendary Budling at the top of the premium track.
- **New achievements:** rebirth your ranch, find 20 hidden eggs, and get the Blossom mutation.

**In the code**
- **Rebirth** (`Systems/Rebirth`, `Config/Rebirth`):
  - The whole rebirth runs in one handler with no yields, so it happens completely or not at all.
  - Owners expose reset hooks: `Ranch:ResetForRebirth`, `Expeditions:ResetForRebirth` and `Shop:GrantTheme`.
  - The skill tree and the stars feed the existing provider hooks, plus a new `Ranch:RegisterRateMultiplier`.
  - `Monsters:AddVisibleTrait` adds the 3rd trait.
  - `Shop.BuyEgg` honours an egg's new `rebirths` field.
  - Pen themes can be `rebirth` rewards: never sold, and hidden from the Store.
- **Spring Bloom:**
  - A new `Config/Events` entry, plus `pollenstorm` weather (the new `dayOnly` flag in `WeatherRoll`), the `blossom` mutation, the `bloom` egg and three `springbloom` lines.
  - `EggHunt` system with `Config/EggHunt` and `Logic/EggHunt`. Rounds are on the unix clock, so every server hides the same eggs, and the server checks how close the player's character is.
- **Ranch Pass seasons:** `Config.Quests.Seasons`, with `Config.Quests.PassAt(now)` on the server and in the Quests and Store screens.
- **Client:**
  - A new Rebirth screen, and a Star Altar building in the hub.
  - The Hall of Fame links to it.
  - A new `EggHunt` controller draws this round's eggs.
  - The Weather controller has a pollen particle layer.
- **Tests:** `Rebirth.spec`, `SpringBloom.spec` and `RebirthClient.spec` (the rebirth and a hunt pick-up, played through the real client).

## 1.3 · Market Day

**For players**
- **Market** (Ranch Level 10). Open it from the Market stall next to the Trading Plaza, or with the Market button on the HUD. Settings is now the ⚙ next to your level bar.
- **Sell:** list a monster or a stored egg for coins. It leaves your ranch while it is listed. Listings last 48 hours, and you can have 8 at a time.
- **Buy:** buy from any player on any server. The seller gets the price minus an 8% market tax, delivered to a mailbox you collect from anywhere. Unsold or cancelled items come back the same way.
- **Club trading post:** list to your club only, at a lower 4% tax.
- **Price history:** a 30-day chart for every item, and a suggested price when you sell.

**In the code**
- **Built by three parallel workstreams** against a contract fixed first (ARCHITECTURE §8):
  - M1: the `Market` server system
  - M2: `Logic/PriceHistory` and the `PriceHistory` system
  - M3: the Market screen, the `PriceChart` component and the HUD changes
- **An adversarial review found edge cases, now fixed:**
  - players leaving while a request waits on the market
  - writes that land but report failure
  - retried mail paying twice
  - crashes between the market write and the profile save
  - club posts used to move coins without tax
- **How the fixes work:**
  - Every cross-server step now saves an intent task first (`ctx:SaveNow`, new).
  - A write whose outcome is unknown is settled by a fresh read.
  - The mailbox is two-phase and deduplicated (`MailPeek` / `MailAck` replace `MailTake`).
  - Club sales pay a 4% tax and stay out of public price history.
- **Tests:** `Market.spec` (with a "Failure safety" group that simulates crashes and lost replies), `PriceHistory.spec` and `MarketClient.spec`.

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
