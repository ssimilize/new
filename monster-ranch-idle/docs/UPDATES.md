# Updates

Content and system changes shipped after launch, newest first. Each update lists what
players get and where it lives in the code.

## 3.1 · Club Wars + Lunar Lanterns

Launch Sat 5 Feb 2028. Everything is dated in config (Club Wars start, the event rerun and
Season 7 on 22 Jan), so this update can be published any time before 22 Jan.

**For players**
- **Club Wars** (from 5 Feb 2028): every club is on a weekly ladder across all servers.
  - **Scoring:** members earn war points for their club by winning raids (25), from Racing Cup
    points (×5) and by finishing Stampedes (5, +10 in the top 3), up to 150 per member per day.
  - **Leagues:** at the end of the week (Saturday 15:00 UTC) the club's points put it in Bronze,
    Silver (600), Gold (1,500) or Diamond (3,000). The top 3 clubs on the ladder are Champions.
  - **Rewards:** every member who scored claims the club's reward during the next week (gems,
    ribbons, a Crystal Egg in Gold, Royal Eggs in Diamond and for Champions).
  - A **Club Wars** tab shows your league, progress to the next one, how to score, the top 10
    ladder and last week's result with a Claim button.
- **Club banners:** owners and officers can hang a Workshop design they own as the club
  banner. It shows in the club header and on club tags around the hub.
- **Lunar Lanterns returns** (5 Feb – 26 Feb 2028): Lantern Coins, the Lantern Egg, Lantern Night
  and its Glow mutation come back. Lanternwyrms raised on sweet food now grow into the new
  **Moonlit Dragon** (spicy food still makes the Lantern Dragon).
- **Ranch Pass Season 7, "Club Wars"** (22 Jan – 4 Mar 2028): Lantern Eggs, ribbons, and a
  Legendary Tinselkit.
- **Code:** `CLUBWARS` gives 150 Lantern Coins and 50 gems. It expires on 26 Feb 2028.
- **New achievements:** claim a Club Wars reward, and reach the Gold league.

**In the code**
- **Clubs:**
  - `Config.Clubs.War` (sources, leagues, champion, daily cap, ladder) and `Config.Clubs.League`.
  - War points collect in the same pending buffer as goal progress and are written with the
    club's atomic sync. `Record.rollWeek` keeps `lastWar` and each member's share.
  - `Services.Clubs.IndexWar` / `TopWar` hold the weekly ladder (one OrderedDataStore per
    week). Servers read the top 10 every 5 minutes into `global.Clubs.ladder`.
  - New actions `Clubs.ClaimWar` and `Clubs.SetBanner`, and the `ClubWarClaimed` topic.
  - `RaceFinished` now carries `cup`. `Workshop:Copy(player, designId)` is new.
- **Events:** a Lunar Lanterns rerun window. The Lantern Dragon line gains a second adult.
- **Tests:** `ClubWars.spec` (5): leagues, scoring across servers with the daily cap and the
  ladder, league / Champion claims, banners, and the Lunar Lanterns rerun with Season 7 and
  the code. `YearTwoClient.spec` gains the Club Wars tab and the banner picker.
- **Snapshots:** `docs/snapshots/3.1-club-wars.png`. The snapshot tool gains `SNAPSHOT_START`.

## 3.0.1 · Go live + Frostfall returns

Launch Sat 18 Dec 2027: the Trading Hub goes live, the Workshop gets moderation, and
Frostfall comes back for its second winter.

**For players**
- **Frostfall returns** (18 Dec 2027 – 15 Jan 2028): Snowflakes, the Frostfall Egg, the winter
  decor and pen theme, and the Snow boost come back. The egg now also hatches a fourth winter
  line: **Tinselkit → Garlandfox → Yuletail** (Spark/Light). Snowflakes left from last winter
  still count.
- **Code:** `FROSTFALL27` gives 150 Snowflakes. It expires on 15 Jan 2028.
- **Trading Hub:** travel and return now retry a failed teleport up to twice instead of
  leaving you stuck.
- **Workshop:** designs hidden by reports are reviewed by moderators, who restore them or
  remove them for good. Royalties are collected in one go however many designs you have.

**For the team**
- **Publishing:** see `docs/GO_LIVE.md`. Build the hub place from `hub.project.json` (it sets
  the Workspace attribute `PlaceMode = "hub"`) and name the places "Monster Ranch Idle" and
  "Trading Hub". No place ids need copying into code. CI now builds both place files.
- **Moderators:** add user ids to `Config.Workshop.Moderators` or set
  `Config.Workshop.ModeratorGroup` (group id and minimum rank).

**In the code**
- **Events:** `reruns` windows per event; `Events.Windows`, and `Events.Active` / `Next`
  return the event with the running window's dates. Nothing else changes, so every item tagged
  with the event comes back.
- **Trading Hub:** `Services.Places.List` (AssetService) resolves `Config.TradingHub.PlaceNames`,
  with `PlaceIds` as optional pins and a "not the hub" fallback for the ranch. The Teleport
  adapter retries `TeleportInitFailed` (Flooded / Failure) twice.
- **Workshop:**
  - Design records and the Top / New lists are cached per server (`CacheSeconds` 60,
    `ListCacheSeconds` 30); purchases still read fresh.
  - Royalties go to a per-designer ledger (`Services.Designs.Owe` / `Collect`).
  - A design hidden by reports joins a moderation feed (`Flag` / `Flagged` / `Unflag`).
    New actions `Workshop.ModQueue` and `Workshop.Moderate`, and a Review view in the gallery
    for moderators. `Services.Players.RankInGroup` checks the moderator group.
- **Tests:** `GoLive.spec` (8): the rerun window, the rerun shop and code, the hub project file,
  places by name (outage, fallback, pinned id), the design cache, the royalty ledger, the
  moderation queue, and moderators by group rank. `YearTwoClient.spec` gains the Review queue
  through the UI.

## 3.0 · Year Two

The four "Year 2" items from the roadmap, in one update (launch Sat 11 Dec 2027).

**For players**
- **A new region every quarter:**
  - **Mirage Dunes** (Ranch Level 50) opens with the update. It has 20 stages of Ember/Stone enemies, the Riddling Sphinx and Sunken Pharaoh bosses, and a **Dune Egg** for three new lines: Sandskip → Dunehopper → Sirocco / Oasis Hare, Cactling → Pricklord → Saguardian, and Scarabit → Sunscarab → Pharaoh Beetle.
  - **Frostbite Glacier** (Ranch Level 55) is already in the game and opens on **11 Mar 2028**; until then its tab shows the date. It has Tide/Light enemies, the Glacier Egg, and three lines: Pengling, Yetikit and Aurowl.
  - Region tabs now use short names so seven regions fit on a phone.
- **Monster Racing** at the new **Racetrack** (Ranch Level 16):
  - Race one of your Adults 600 m against three ghosts on the day's track; everyone gets the same track each day.
  - Faster species run faster, but timing wins races: **Jump** hurdles (a stumble costs 1 s), **Boost** with stamina, and avoid mud.
  - Your first 10 races each day pay Contest Ribbons and coins by place, plus **Racing Cup** points for the new weekly leaderboard (title: *Speed Demon*).
- **Trading Hub**, a separate place for traders from every server (Ranch Level 8, same as trading):
  - Travel there from the Trading Hub portal just outside the Market Square. Your monsters come with you.
  - Post an ad on the **Trade Board**: up to 4 monsters or eggs, what you want (Legendary+, Mythic, Shiny, Mutated, Light, Void…) and a preset note (never free text).
  - The board shows ads from every hub server. **Meet** sends a trade request when the poster is on your server, or takes you to their server. Trades still run through the usual trade window.
  - "Back to ranch" takes you home.
- **Accessory Workshop** (Ranch Level 12), a new building west of the plaza and a Workshop button in the Wardrobe:
  - Design an accessory from any catalogue shape (its slot comes with it) in two of 16 colours, and give it a name (checked by the text filter).
  - Publishing costs 40 Contest Ribbons, 3 designs a week. You get the first copy.
  - Browse the **Gallery** (Top, New, Mine): like designs and buy copies for 15 ribbons. The designer earns 5 ribbons for every copy someone else buys; collect royalties in the Gallery.
  - Players can report designs; 3 reports hide one from the gallery until moderators look at it.
  - Worn designs show up on your monsters everywhere, and Contest judges count them like any accessory.
- **Ranch Pass Season 6, "Year Two"** (11 Dec 2027 – 22 Jan 2028): Dune Eggs, ribbons for the Workshop, and a Legendary Sandskip.
- **New achievements:** clear the Mirage Dunes, win 10 races, publish a design, and post a Trade Board ad.
- **Code:** `YEARTWO` gives a Dune Egg and 50 gems. It expires on 1 Jan 2028.

**In the code**
- **Regions:** `Regions.opensAt`, `Regions.IsOpen` and `Regions.NextOpening`. Expeditions refuses a region before its date and the screen shows the date. `Format.date` formats it.
- **Racing:** `Config/Racing`, `Logic/Racing` (track from the day's seed, fixed-step simulation shared by client and server; the server replays the `{ t, a }` moves) and the `Racing` system. The Leaderboards `racing` board reads `Racing:CupPoints`.
- **Trading Hub:**
  - `Config/TradingHub`, which holds the place ids (`VERIFY`: fill in when publishing) and decides the mode.
  - The `TradingHub` system; the new `Services.Teleport` and `Services.HubBoard` (a MemoryStore sorted map) adapters.
  - On the hub place, `Plots` hands out no plots and `World/Build` builds the hub layout (`Build.world(Config, "hub")`).
- **Workshop:**
  - `Config/Workshop` and the `Workshop` system, with `Services.Designs` (design records, a likes index and a recent feed).
  - A worn design is encoded in `Monster.acc` (`Config.Accessories.Encode/Decode/Resolve`), so every client draws it from the monster record.
  - `Accessories:Return` / `RegisterReturn` hand designs back to Workshop storage.
- **Content:** 6 lines, 2 eggs, Season 6, the code and 4 achievements.
- **World:** the Racetrack, Trading Hub portal and Workshop buildings.
- **Tests:**
  - `YearTwo.spec` (9): regions by date and level, the race rules and replay, paid races and the Cup, the hub trip and no plots, ads shared across hub servers with Meet here or there, posting only from the hub, board outages and expiry, publishing and wearing a design, and copies and royalties across servers with likes and reports.
  - `YearTwoClient.spec` (5): a race through the UI, posting an ad and starting a trade from it, the board preview from the ranch, designing and wearing an accessory, and region tabs with dates.
- **Snapshots:** `docs/snapshots/3.0-*.png`. The snapshot tool gains `SNAPSHOT_PLACE=hub`.

## 2.1 · Arena & Raids

**For players**
- **Champions Arena** (Ranch Level 20), just outside the Market Square:
  - **Fair fights:** every arena monster fights as a Lv 50, 3★ Epic of its species, with no traits, mutations, Legacy or upgrades. Species, element, skill and team order decide the fight, not spending.
  - **Defense:** set a team of three Adults, and players on any server can challenge it.
  - **Attacks:** up to 5 a day, against opponents near your rating. Bots fill in when few players are near. A win pays some coins.
  - **Ratings and tiers:** Elo ratings for both sides, with tiers Bronze, Silver, Gold, Crystal and Champion. Your best tier each week pays a reward once the week ends (Saturday 15:00 UTC).
- **Raid Portal** (Ranch Level 30): 4-player raids on your server.
  - Open a lobby with up to two Adults, and friends join with theirs. The host starts the raid, and everyone watches the battle.
  - **Stormcrag Titan:** needs a full team of Legendaries or better.
  - **Umbral Wyrm:** needs a full team of maxed Mythics.
  - **Rewards:** wins pay a **Raid Egg**, the only way to hatch the three raid lines (Titanling → Thundercrag → Stormcrag Colossus, Wyrmlet → Ashwyrm → Umbral Wyrm, and Tempestray → Squallwing → Maelstrom Ray), for your first 3 raid wins each day.
- **Harvest Moon event** (2–30 Oct 2027), with **Moon Candy** as its token:
  - Blood Moon is 3× as likely.
  - **Harvest Egg:** Pumpkit → Gourdling → Jack o' Lord, Scarecrowl → Strawhoot → Harvest Warden, and Batterfly → Duskflutter → Nightreaper.
  - **Decor:** the Jack-o'-Lantern and Haunted Tree, plus the Haunted Hollow pen theme.
- **Ranch Pass Season 5, "Harvest Moon"** (2 Oct – 13 Nov 2027): spooky accessories, Raid Eggs, and a Legendary Pumpkit.
- **New achievements:** win 10 arena battles, beat a raid boss, and beat the Umbral Wyrm.
- **Code:** `ARENAANDRAIDS` gives a Raid Egg and 50 gems. It expires on 30 Oct 2027.

**In the code**
- **Arena:** the `Arena` system (`Config/Arena`, `Logic/Arena`), plus `Services.Arena`, a DataStore record per player with an OrderedDataStore rating index. The mock shares it through `MockAdapters.network()`.
- **Raids:** the `Raids` system (`Config/Raids`). Raid lines are marked `raid = true`, and the `raid` egg pool is used only by the Raid Egg.
- **BattleSim:** records take `look` and `hpMult`, and `opts.maxAllies` lifts the ally cap. Raid bosses were tuned by simulation.
- **Content:** Harvest Moon adds entries to `Config/Events`, `Species`, `Eggs` and `Decor`, and Season 5 is added.
- **Client:** Arena and Raids screens, and the Champions Arena and Raid Portal buildings (outside the plaza, clear of the plot paths).
- **Tests:**
  - `ArenaRaids.spec` (9): normalization, Elo, two servers sharing the arena, bots, limits, weekly tier, arena outage, a 4-player raid win, a weak-team loss, the daily cap, leaving and expiry, the Raid Egg, and Harvest Moon.
  - `ArenaRaidsClient.spec` (2): defense and an arena fight through the UI; a two-player raid where both players watch.
- **Snapshots:** `docs/snapshots/2.1-*.png`.

## 2.0 · Light & Void

**For players**
- **Light and Void**, a third group of elements: a pair where each beats the other (×1.5 both ways) and neither has a weakness against the other six. There are seven new lines:
  - Light: Lumipup → Beamhound → Sunfang or Dawnmane · Halobee → Glintwing → Seraphly · Dawnling → Aurelle → Daybreak Seraph
  - Void: Nullkit → Voidlynx → Eventide Lynx · Hollowisp → Riftshade → Abyss Warden · Gravitoad → Singulatoad → Event Horizon
  - Both: Eclipsa → Penumbra → Total Eclipse
- **Sky Islands** (Ranch Level 45):
  - Five floating islands high above the map, joined by cloud bridges. Fly up from the launch pad in the Market Square.
  - **Wind crystals:** 13 of them, each collectable once an hour (up to 60 a day). Each pays coins, Treats, Stardust or a Sky Egg.
  - **Sky Gate:** opens the new **Sky Islands** expedition region, stages 1–20 (global stages 81–100), with two bosses. The Sunlit Warden guards stage 10, and Umbra, the Hungry Star, stage 20 (first clear: 2 Sky Eggs).
  - **Sky Egg:** from Sky Islands expeditions and crystals. It hatches the Light and Void lines.
- **Riding** (Ranch Level 16): tap **Ride** on any Adult to travel on it, and everyone sees your mount. Riding speed comes from the species' speed and rarity (20–40 studs/s, against 16 walking). **Get off** is on the HUD.
- **Summer Splash event** (3 Jul – 14 Aug 2027), with **Seashells** as its token:
  - Heatwave is 3× as likely.
  - **Beach Day:** daytime event weather that gives the new **Sunkissed** mutation (×3). **Soaked + Sunkissed = Tropical** (×5).
  - **Surf Shack** in the Market Square: a 45-second, three-lane surfing run. Catch seashells, dodge rocks, and earn up to 40 Seashells a run.
  - **Splash Egg** (400 Seashells, always Sunkissed): Surfotter → Wavebreaker → Tidal Champion, Coconutty → Palmguard → Island King, and Sunnyray → Glareray → Solar Manta.
  - **Decor:** Beach Ball and Tiki Torch, plus the Tropical Lagoon pen theme.
- **Ranch Pass Season 4, "Summer Splash"** (26 Jun – 7 Aug 2027): beachwear accessories, Sky, Celestial and Royal Eggs, and a Legendary Surfotter.
- **New achievements:** your first wind crystal, 50 crystals, clearing the Sky Islands, riding a monster, and 10 surf runs.
- **Code:** `LIGHTANDVOID` gives a Sky Egg and 50 gems. It expires on 14 Aug 2027.

**In the code**
- **Content:**
  - `Config/Elements` gains the Light/Void pair.
  - New entries in `Config/Species`, `Config/Eggs` (`sky`, `splash`), `Config/Regions` (`sky`), `Config/Mutations` (`sunkissed`, the `tropical` combo), `Config/Weather` (`beachday`, the new `dayOnly` rule, `EventBoosts.summersplash`), `Config/Events` and `Config/Decor`.
- **World:** `Config.World.Sky` holds the island layout. `World/Build` builds the islands, bridges, pads and gate, and the Surf Shack joins the hub buildings.
- **New systems:**
  - `SkyIslands` (`Config/SkyIslands`)
  - `Riding` (`Config/Riding`)
  - `Surf` (`Config/Surf`, `Logic/Surf`): the course comes from a server seed, and the server replays the lane changes, so a client can't report a made-up score.
- **Client:**
  - `SkyIslands` and `Riding` controllers, and a Surf screen.
  - A Ride button on the monster screen.
  - `MonsterModel` adds Light/Void touches and a `scale` option for mounts.
  - A Beach Day weather look.
- **Tests:**
  - `LightAndVoid.spec` (11)
  - `LightAndVoidClient.spec` (3): fly up, collect a crystal and open the gate; ride and get off; surf a whole run through the UI.
- **Snapshots:** `docs/snapshots/2.0-*.png`, from `tools/snapshot`.

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
