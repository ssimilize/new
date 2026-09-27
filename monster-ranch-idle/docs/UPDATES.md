# Updates

Content and system changes shipped after launch, newest first. Each update lists what
players get and where it lives in the code.

## 3.11 · Seasons & secrets

### Dig Site & Fossils

**For players**
- From Ranch Level 16 a roped-off sand pit with a tool rack sits in the north strip of every ranch,
  east of the Fishing Pond. Its "Dig" prompt opens the Dig Site.
- A dig is a 5 × 5 field of covered tiles and 5 taps. Each empty tile tells you how close the
  nearest buried find is (Hot!, Warm, Cool, Cold). Every dig hides 1 find, or 2 (40%).
- 6 free digs a UTC day, then one Shovel each. Expedition Bounties now pay 2 Shovels; the
  Travelling Merchant can sell them too.
- Finds: fossil pieces (6 fossils × skull, ribs, legs, tail; a piece you already have becomes
  5 Amber), Amber (3-8), rare relic decor (Ancient Urn, Stone Tablet) and the rare Amber Egg (never
  sold; hatches the Stone, Sprout and Gloom lines with better odds than the shop eggs).
- All four pieces complete a fossil and give its skeleton display to place on the ranch (it adds
  to decor and tourist Appeal like any decor).
- The Codex has a Fossils tab: every fossil's pieces and milestones at 2 / 4 / 6 fossils
  (20 / 40 / 100 gems). New weekly goal: Finish 10 digs.

**In the code**
- `Config/DigSite`, `Logic/DigSite` (seeded layout, distance hints), `Systems/DigSite` (actions
  `DigSite.Start`, `DigSite.Tap`; API `AddShovels`, `FossilsComplete`; publishes `FossilFound` and
  `DigFinished`), screen `Screens/DigSite`, Codex tab `Parts/FossilLog`.
- The layout is seeded by (userId, dig number, a private per-player secret), never stored or sent;
  the open dig's dug tiles live in `profile.DigSite.open`, so reopening resumes it (no reroll).
- World: `Config.World.DigSite` (built in `World/Build.luau`, Decor keep-out `{ 62, -47, 12, 7 }`).
- Rewards kind `shovel`; `amber` and `shovel` icons drawn in code (`Components/Icon`).
- Amber Egg (`Config/Eggs`, order 23, pool `amber` on the 9 common Stone/Sprout/Gloom lines);
  decor `ancient_urn`, `stone_tablet`, `fossil_<id>` (DecorArt `fossil_skeleton` posed per fossil).
- Tests: `DigSite.spec`, `DigSiteClient.spec`.

## 3.10 · Ranch life

### Ranch Tourists

**For players**
- From Ranch Level 11, tourists visit your ranch: one about every 10 minutes while you play.
  Each one walks in through your gate, stops to look around, shows its stars and leaves.
- Every tourist pays a few minutes of your ranch income: 40 seconds of income per star (so 5
  stars pay 200 seconds). While you are away, up to 6 tourists still come, and the Welcome Back
  summary tells you ("6 tourists visited while you were away").
- Your ranch's **Appeal** (0-100, 1-5 stars) comes from five things: how much decor you placed,
  how many kinds of decor, your pens (how many and how full), the rarest monsters in your pens and
  your Codex. A tip names what would help most ("More lights would be nice", "Fill your pens").
- The new **Guestbook** shows your stars, a bar for each part of your Appeal, the tip, the next
  tourist's countdown and the last 20 reviews. Open it at the little stand beside your gate or
  with the "Guestbook" button on the Decorate screen.
- Friends visiting your ranch in the Visiting Showcase see your Appeal stars.
- New weekly goal: "Welcome 15 tourists".

**In the code**
- `Config/Tourists`: cadence (`Interval` 600 s, `AwayMax` 6, `BookSize` 20, `SecondsPerStar` 40),
  Appeal weights (decor 25, variety 20, pens 20, rarity 20, codex 15), `DecorFull` 40,
  `VarietyFull` 8, `RarityTop` 3, `CodexFull` 60, `StarSteps` 20/40/60/80, category names, tips,
  review lines, visitor names and the walk's plot-local spots.
- `Logic/Tourists`: `Appeal(facts)`, `Stars`, `Tip`, `Offset`/`Slot`/`NextAt` (slots of the unix
  clock offset by `Rng.seed("tourists", userId)`), `Review` (seeded by user and slot), `Pay`,
  `Push`, `StarText`.
- `Systems/Tourists` (unlock `tourists` 11): profile `{ slot, count, book }`, session
  `{ score, stars, parts, tip, nextAt, unlocked }`, global `walk` (each player's last visit for the
  clients to draw). A 5 s tick pays due slots; a join pays the missed ones (max 6) with a
  WelcomeItem. Publishes `TouristVisited (player, { stars })`. Public `Tourists:Appeal(player)`,
  `Tourists:Stars(player)`. No actions.
- Visits: the snapshot carries `stars` (`Logic/Visits.Build(..., stars)`, sanitized 0-5); the
  Visits bar and `Visuals/RanchShowcase` gate show them.
- Client: `Controllers/Tourists` (stand + prompt, walking tourist built from Parts, no avatar
  load) and `Screens/Guestbook`; Decorate's header has a "Guestbook" button.
- `Config.Decor.Layout.keepOut` keeps decor off the stand at plot-local (68, 16).
- Weekly goal `tourists_15` (family `tourists`, unlock `tourists`).

### Kitchen & Pantry

**For players**
- From Ranch Level 9 a **Kitchen** stands on your plot, in the gap south of the pens between
  the statue row and the Feed Garden. Walk up to its door and press **Cook**. The Pantry is also
  one tap away from a monster's Feed popup (the new **Pantry** button).
- **Cooking.** 8 recipes turn your food into dishes. Dishes cook for 5 to 60 minutes on the
  server clock, so they finish while you are away. The Welcome Back screen tells you, and the
  Kitchen collects them into the Pantry when you open it. You have 2 cooking slots, and a 3rd
  from Ranch Level 30. The Pantry holds up to 99 of each dish.

  | Dish | Ingredients | Time | Effect |
  |---|---|---|---|
  | Berry Pie | 5 sweet, 3 savory | 5 min | counts as 3 sweet growth meals |
  | Pepper Stew | 5 spicy, 3 savory | 10 min | +20% Job Board output for 2 h |
  | Lime Tart | 5 sour, 3 sweet | 10 min | fills Mood to the max |
  | Root Roast | 6 savory, 2 spicy | 15 min | counts as 3 savory growth meals |
  | Fish Supper | 2 fish, 3 savory | 20 min | +5% loot on its next expedition |
  | Sushi Roll | 3 fish, 2 sour | 30 min | +20% Job Board output for 2 h |
  | Golden Honeycake | 2 golden, 5 sweet | 45 min | +1 Bond heart |
  | Golden Feast | 3 golden, 3 of each food | 60 min | +1 Bond heart, makes 2 |

- **Serving.** Tap Serve on a Pantry dish and pick the monster; only monsters that can use the
  dish are offered (growth meals for Babies and Teens, job boosts for Teens and Adults, no Mood
  dish for a monster already at full Mood, and so on).
- **Fish** come from the Fishing Pond. Until you have some, the fish recipes say "Needs fish from
  the Fishing Pond".
- **Golden seeds.** Each Feed Garden harvest has a 5% chance to drop a Golden seed once the
  Kitchen is open. Plant it in a garden plot (the garden's Plant menu or the Pantry's
  "Plant a seed") and 30 minutes later it gives 2 Golden Honeyfruit for the golden recipes.
- New weekly goal: "Cook 10 dishes".

**In the code**
- `Config/Kitchen` (recipes, effects, slots, cap, golden seed numbers), `Logic/Kitchen`
  (slots, costs, boost windows, `GoldenSeed(userId, n)`, `ServeProblem`), `Systems/Kitchen`
  (actions `Kitchen.Cook`, `Kitchen.Collect`, `Kitchen.Serve`, `Kitchen.PlantGolden`; save
  section `profile.Kitchen`; session `slotCount`, `fish`, `fishing`), `Screens/Kitchen` and
  `Screens/Parts/DishIcon` (dishes drawn from Frames, no images).
- Bus: `DishCooked (player, { dish, count })` per collected slot (Weekly counts `count`,
  `Config.Quests.CountField`); `WelcomeItem` kind `kitchen`.
- Hooks added to existing systems (small, each with its own test in `Kitchen.spec`):
  `Jobs:RegisterOutputBoost` and `Logic/Jobs.BoostedSeconds` (extra work time inside a boost
  window; a scout hour's egg chance scales), `Expeditions` loot modifiers now also receive the
  squad ids, `Ranch:RegisterCrop` / `RegisterHarvestHook` / `PlantCrop` (the golden crop and
  the seed roll), `Monsters:AddMeals`, `Bond:AddHeart`.
- Fishing is an optional dependency (`FishCount`, `SpendFish`); without it fish count as 0.
- World: `Config.World.KitchenOffset` / `KitchenSize`, built from Parts in `World/Build.luau`;
  a Decor keep-out zone; the "Cook" prompt in `Controllers/Interaction`.
- Unlocks: `kitchen` 9, `kitchen_slot_3` 30.

### Gene Lab

**For players**
- From Ranch Level 21 the Gene Lab opens from Monster Detail (the Gene Lab button on the genes
  line) and from the Breeding Barn's header. No new HUD button.
- **Tune:** pick an Adult and a stat. The weaker gene of that stat's pair (the first when both
  are equal) gains +1 on a success. Cost: 20 × (gene + 1) Stardust, spent whatever happens.
  Odds: 90% for genes 0–4, 60% for 5–6, 35% for 7. The Lab stops at 8 (9 and 10 only come from
  breeding surges). 5 tunes per UTC day. The screen shows the odds, the cost and the tunes left
  before every tune, and the result with a pulse or a shake.
- **Gene lock:** 5 Star Shards lock one stat on one Adult. Its next baby gets its better gene
  of that stat for certain (surges still apply). One lock per monster; locking another stat
  replaces it with no refund (the confirm says so).
- The breeding planner counts locks in every chance and marks a locked stat "Locked".
- New weekly goal: "Tune 5 genes in the Gene Lab" (family `genelab`; every tune counts,
  success or not).

**In the code**
- `Config/GeneLab`, `Logic/GeneLab` (Weaker, Cost, Chance, Seed, Roll, TunesLeft),
  `Systems/GeneLab` (Profile v1 `{ day, tunes, attempts }`; actions `GeneLab.Tune`,
  `GeneLab.Lock`; Bus `GeneTuned { stat, success }`), `Screens/GeneLab`.
- Rolls are seeded by ("genelab", userId, monsterId, attempt) with the saved attempt counter,
  so a rejoin never rerolls. Busy monsters (expedition, breeding, job, trade) are refused
  through `Monsters:Available`.
- `Logic/Genetics` Inherit, Range, Preview, Odds and GradeOdds take optional `lockA, lockB`
  (the parents' `geneLock`); without them nothing changes, and Inherit draws the same random
  numbers either way, so a lock never moves another roll. `Logic/Breeding` Roll and Outcomes
  pass the records' locks.
- The lock lives on the monster record (`geneLock`). `Breeding.Claim` clears both parents'
  locks after the baby is made; a cancelled pod (or a claim refused for a full ranch) keeps
  them. `Monsters:Insert` clears it, so a traded or Market-listed monster arrives unlocked
  (a listing taken back or a rolled-back trade also comes back unlocked).
- Tests: `GeneLab.spec`, `GeneLabClient.spec`; `GeneticsClient.spec` reads the gene line
  through its new row.

### Fishing Pond

**For players**
- From Ranch Level 13 every ranch has a pond in the strip behind the pens, with a little dock.
  Walk onto the dock and use the **Fish** prompt to open the Fishing Pond. There is no HUD button.
- You get 10 free casts a day (UTC). After that each cast uses 1 Bait. Every Expedition Bounty
  now also pays 3 Bait.
- Fishing is a hold-and-release minigame. A fish swims up and down a bar:
  - Hold **Hold to reel** (or Space, or pad A) and the green zone rises. Let go and it sinks.
  - While the zone covers the fish, the catch meter fills. When it doesn't, the meter drains.
  - Fill the meter to land the fish. If the meter empties, or 20 seconds pass, the fish gets away.
  - Rarer fish move faster and further, and they are harder to hold.
- There are 16 fish in 4 rarities (Common, Uncommon, Rare, Legendary), and each has a weight range.
  Sell fish from your bucket for coins, or cook them in the Kitchen.
- Choose an Adult as your **fishing buddy**. Its Luck (stat and gene) raises your chance of a rare
  fish and of the extras a catch can bring: the **Old Boot** and **Sunken Chest** decor (never
  sold) and sometimes a Pearl egg. The screen shows your buddy and the chances.
- The Codex has a new **Fish Log** tab. It shows every fish you have caught, how many, and the
  heaviest of each. Milestones at 4, 8 and 16 kinds pay 10, 25 and 60 gems.
- New weekly board: **Biggest Catch** (the heaviest fish this week; its winner gets the title
  Master Angler). New weekly goal: "Catch 20 fish".

**In the code**
- `Config.Fishing`: 16 fish (`Fish`, `ById`, `Ids`), 4 `Rarities` (weight, value in seconds of
  ranch income, move speed/range/pause, meter fill/drain), and the minigame numbers (Duration 20 s,
  Step 0.05, zone, lift/gravity, FishRange, MaxInputs, Grace/Late seconds). Also `FreeCasts`,
  `BuddyShares`, `Decor` extras and `Egg`/`EggChance` (the Pearl egg, Coral Reef's region egg). Unlock key `fishing` (Level 13).
- `Logic/Fishing`: `Course(seed, bonus)` rolls the fish (rarity weights, with every rarity above
  Common ×(1 + bonus)), its seeded weight and its path. `Advance`/`Simulate` replay
  `{ t, down }` moves in fixed steps; the client and the server share them. Also `BuddyBonus`
  (Loot.LuckBonus with the buddy's Luck counted 5 times), `ExtraChance` (min(cap, chance ×
  (1 + bonus)), the Bounties formula), `Extras`, `SpendOrder` and `Species`.
- `Systems/Fishing`: `profile.Fishing` (day/casts, bait, fish, log, buddy, week/weekBest/weekFish,
  total, best). Actions `Fishing.Start`, `Finish`, `Sell` and `SetBuddy`. It uses the Surf/Racing
  anti-cheat: an in-memory open run, one-shot run ids, a replay, and the grace and late
  wall-clock checks. Publishes `FishCaught (player, { fish, rarity, weight })`.
  - Kitchen contract: `Fishing:FishCount(player)` and `Fishing:SpendFish(player, n)` (cheapest
    first; it returns false and changes nothing when you are short).
  - Also `AddBait`, `SpeciesCaught`, `WeekBest` and `Bonus`.
- `Rewards` has a new kind `bait` (it goes to `Fishing:AddBait`). `Config.Bounties.Reward` gets
  `{ kind = "bait", amount = 3 }`. Ranch Orders are unchanged.
- Codex: `Config.Codex.FishSteps`/`Gems.fish`, `Logic/Codex.FishMilestones()`/`FishById()`
  (ids `fish_<n>`, kept out of `Milestones()`). `Codex.Claim` checks them with
  `Fishing:SpeciesCaught`. `CodexClaimed` now has the kind `fish`.
- World: `Config.World.Pond` sets out the `FishingPond` model in `World/Build` (water, bed, rim,
  dock). `Controllers/Interaction` adds the "Fish" prompt on the dock. Its Decor keep-out is in
  `Config.Decor.Layout.keepOut`. The decor `old_boot` and `sunken_chest` are in `Config.Decor`
  and `DecorArt`.
- Board `fishing` (`Config.Leaderboards`, format weight, kg × 100) and the weekly goal
  `fish_20` (family `fishing`).
- Client: `Screens/Fishing`, plus `Parts/FishIcon` (a fish drawn from Frames with a UIGradient)
  and `Parts/FishLog` (the Codex tab, `Codex` opens with `{ tab = "fishlog" }`).
- Tests: `Fishing.spec` and `FishingClient.spec`.

## 3.9 · Family and fortune

### Buyer reputation

**For players**
- Every Ranch Orders buyer now remembers you. Filling one of their orders earns them
  reputation: Easy 1, Medium 2, Hard 4, Goods 2 points.
- Each buyer has 4 levels, at 5, 15, 35 and 70 points. Their perks apply to their own orders:
  - Level 1: +10% coins on their monster orders.
  - Level 2: their Hard orders carry an egg 40% of the time (was 25%), plus a one-time
    thank-you gift of 20 gems and 20 food.
  - Level 3: +25% coins instead of +10%, and they can post a 4th "favourite buyer" order. Only
    one favourite order a day, from your highest-reputation buyer at level 3 or higher.
  - Level 4: a one-time decor piece in their style. Rosa's Scarecrow, Pip's Stove, Milo's Bread
    Oven, Wren's Anchor, Ada's Medicine Cabinet, Juno's Display Case, Tam's Lookout Sign and
    Hale's Telescope. These pieces are never sold.
- A toast tells you when a buyer reaches a new level.
- On the Orders tab, each card shows its buyer's level. The new **Buyers** button (top right)
  shows all 8 buyers with their level, a bar to the next level and the next perk.

**In the code**
- `Config.Orders`: `BuyerIds` (rosa, pip, milo, wren, ada, juno, tam, hale, in `Buyers` order),
  `BuyerById[id] = { id, name, index, decor }`, and `Rep` (`Points`, `Levels`, `CoinBonus` by level,
  `EggLevel`/`EggChance`, `FavLevel`, `Gifts`, `Perks`).
- `Logic/Orders`:
  - Every drawn order stores `buyer`. It is the same buyer the 3.8 seed pick gave, so today's
    orders don't change, and orders saved without an id still read it from the seed (`BuyerId`).
  - `Make`/`Draw` take the reputation. A Hard order's egg compares the same roll with the
    buyer's chance at draw time, so the draw's RNG sequence is unchanged.
  - New: `RepPoints`, `RepLevel`, `RepProgress`, `CoinBonus`, `EggChanceAt`, `Favourite` (most
    points at level 3+, ties by id), `FavSeed` (`Rng.seed("orders_fav", userId, day)`),
    `DrawFavourite`, `GiftsBetween`, `GiftItems`. `Pay`/`Coins` take the buyer's level.
- `Systems/Orders`:
  - Profile v2 adds `rep`, `gifts` (highest level whose gift was paid) and `favDay`, via a
    Migrate from v1.
  - A fill pays the coin bonus of the buyer's level before the fill, then adds the points.
  - A new level sends `ctx:Notify` ("{name} is now a level {n} buyer!") and pays any unpaid
    gift once through `Rewards:Grant` (source "orders_rep"). The food flavour comes from its own
    seed.
  - The favourite order is `list[PerDay + 1]`. It is posted at the day's draw, or as soon as a
    buyer reaches level 3 that day, at most once a day. It can be filled but not rerolled.
  - `Orders.Fill` accepts index `PerDay + 1`. `OrderFilled` now carries `buyer`.
- `Config.Decor` / `DecorArt`: 8 reward-only pieces (`price = nil`, `reward = "orders_rep"`), each
  with its own part model in the style of the 3.8 arena cups.
- UI (`Screens/Jobs`): a "Buyers" header button on the Orders tab toggles the Buyers panel (4 x 2
  buyer cards). Order cards add a "Level n" chip, a "Favourite" chip, and the coin bonus on the
  coins line. The confirm dialog's price includes the bonus.
- Tests: `OrdersRep.spec`, `OrdersRepClient.spec`.

### Pedigree & breeding planner

**For players**
- **Family tree:** tap the "Genes X/100 · Gen N" line on a monster's page to see it, its two
  parents and its four grandparents. Each shows an icon, the name, a border in its rarity colour
  and its five gene grades (HP · ATK · DEF · SPD · Luck). Ancestors from before this update read
  "Unknown"; a hatched monster's parents read "Hatched".
- Market listings and the trade log name a bred monster's parents ("Parents: A × B").
- **Breeding planner:** the Breeding Barn now shows, for each stat, the baby's exact chance of
  grade B or better (or of your target's grade) instead of the old "+lo–hi%" range. Tap a stat to
  see its full S / A / B / C / D spread. Tapping "Genes" still explains surges.
- **Breeding target:** the "Set a target" chip picks a stat and a grade (C, B, A or S). The card
  then shows "Chance with this pair: X%", the stat is outlined, and choosing a parent lists the
  best candidates for the target first. A baby that meets the target gets a celebration toast.
- **Grade milestones:** the first time you breed a baby with grade A in a stat you get 10 Ribbons,
  and again the first time with grade S in it: up to 10 awards (100 Ribbons), target or not.
  A first high grade that is already an S pays both.

**In the code**
- Monster records: `ped = { a, b, aa?, ab?, ba?, bb? }` on bred babies only, snapshots
  `{ line, form, rarity, variant?, name?, gen, grades }` (`grades` = "BACDS" in
  `Config.Genetics.Stats` order); no ids, never deeper than grandparents. `Logic/Pedigree`
  (`Snap`, `Build`, `Copy`, `Name`, `ParentNames`). `MonsterGen.New` keeps `spec.ped` (no draws),
  `Monsters:Insert` deep-copies it (Trade and Market). No save migration.
- `Logic/Genetics`: `Odds(a, b, stat)` (exact convolution of Inherit: pick 1/2, surge +2 / +1 /
  +0, capped, a 10 never surges), `GradeOdds`, `AtLeast(odds, grade)`, `GradeMin`, `Grades`.
  The planner never reads a pod's seed.
- Breeding: `Profile.Version` 2 (Migrate adds `target = false`, `milestones = {}`);
  `Breeding.SetTarget { stat?, grade? }` (no stat clears; grades `Config.Breeding.TargetGrades`);
  Claim builds `ped`, pays milestones via `Rewards:Grant` source `"breeding_target"`
  (`MilestoneGrades`, `MilestoneRibbons`), returns `targetMet` and Notifies on a hit.
  No new `ctx.Rng` draws.
- `Listing.ItemView.parents` and the trade log summary's `parents` carry names only.
- Client: `Screens/Parts/FamilyTree` in a MonsterDetail InsetPopup; Breeding screen planner row,
  target picker dialog and pick `sortBy`.
- Tests: `Pedigree.spec` (incl. a 200k-roll Monte-Carlo check), `PedigreeClient.spec`.

### Expedition Bounties

**For players**
- **Bounties** (Ranch Level 6): every week up to 3 wanted monsters hide in stages you have already
  cleared, like "Grumbletooth the Fierce". Find them on the new **Bounties** tab of the Expeditions
  screen.
  - Each wanted poster shows the monster, its region and stage, and the reward. **Hunt** takes you
    to that stage and starts the fight.
  - The bounty leads its wave: 50% stronger than the enemies around it, a little bigger, and
    wrapped in a red-gold sparkle.
  - Bounties sit in different regions when you can reach several, on one of the last 10 stages you
    cleared there, and never on a boss stage.
  - A stage with a bounty has a red "!" marker on the stage map.
- **The reward**, once per bounty: 30 minutes of coins + 20 gems, plus a chance at the region's
  first egg (a Meadow egg in the Whispering Meadow). The chance is 25%, raised by your squad's
  loot bonus (Lucky Paw, Treasure Nose, Luck and the rest), up to 50%.
  - Lose the fight and nothing changes: try again. A defeated bounty's stage is a normal replay.
- New bounties arrive every Saturday at 15:00 UTC with the weekly leaderboards.
  - No stage cleared yet? The tab says so, and your first clear that week brings bounties.
  - A rebirth keeps the week's bounties. One whose stage you haven't cleared again waits for you
    to get back there, or ends with the week.
- **Bounty Hunter**, a new weekly leaderboard: bounties defeated this week (title: *Bounty Hunter*).
- A new weekly goal: "Defeat 3 bounties".

**In the code**
- `Config.Bounties`: `Unlock` ("bounties", Ranch Level 6 in `Config.Unlocks`, named "Bounties"),
  `Count` 3, `Window` 10, `StatMult` 1.5, `Aura` "bounty", `Reward`, `EggChance` 0.25,
  `EggChanceMax` 0.5, `Source` "bounty", and the `Names` × `Titles` the wanted names are made of.
- `Logic/Bounties`: `Draw` (seeded by `Rng.seed("bounty", userId, week)`; eligible regions,
  distinct regions first, a region repeats only when fewer than 3 are eligible), `Stages`, `Find`,
  `Monster`, `Inject`, `Egg`, `EggChance`, `RollEgg` (from the bounty's own seed), `Rewards`.
- `Systems/Expeditions`:
  - Save section Version 2 adds `bounty = { week, list = { { region, stage, name, line, seed, done } }, count }`;
    `Migrate` gives older saves an empty one.
  - The draw is lazy (join, every Expeditions action, LevelUp, a first clear and a 30 s sweep) and
    stays fixed for the week once it isn't empty.
  - `Expeditions.Fight` puts the bounty in the front slot of its stage's wave. A win marks it done
    and pays through `Rewards:Grant` (source "bounty", silent: the battle viewer shows it with the
    fight's rewards). It also returns `bounty = name` and publishes the new `BountyDefeated`
    topic `{ region, stage }`.
  - Public: `Expeditions:Bounties(player)`, `Expeditions:BountyCount(player)`.
- `Logic/BattleSim`: records may carry `bounty = true` (passed on to the unit views);
  `BattleSim.EnemyRecord` builds a regular wave enemy. `Logic/BattleStage` and
  `Visuals/BattleArena` draw a bounty `Config.BattleStage.scale.bounty` (1.35) times bigger in its
  row spot; the 2D viewer uses a 100 px icon.
- `Config.Vfx.Mastery.bounty`: the aura, drawn through the bounty's `look.aura`.
- `Config.Leaderboards`: the weekly board "bounties", valued by `Expeditions:BountyCount`.
  `Config.Weekly`: the goal `bounty_3` (family "bounties").
- UI: a third **Bounties** mode tab on `Screens/Expeditions` (`Open({ tab = "bounties" })`),
  poster cards `Bounty1..3` with a `Hunt` button, the reset countdown, the empty and locked states,
  and a `Bounty` marker on stage map nodes.

## 3.8 · Reasons to come back

### Weekly goals

**For players**
- **Weekly goals** (Ranch Level 5): every week you get 5 goals, like "Hatch 15 eggs", "Collect
  coin jars 40 times" or "Run 8 races". They're sized to finish in about 5 to 7 days of casual play.
  - The goals come from the features you have unlocked, one per area, so you never get two egg
    goals or two Arena goals in one week.
  - A new set arrives every Saturday at 15:00 UTC, with the weekly leaderboards.
- **The weekly chest** has three steps, each claimable as soon as you reach it:
  - 1 goal: 20 minutes of coins + 15 gems.
  - 3 goals: 1 hour of coins + 40 gems + 10 random food.
  - 5 goals: 2 hours of coins + 100 gems + a Crystal egg (a Royal egg from Ranch Level 25).
  - Forgot to claim? Any step you reached is paid automatically when the week ends, and Welcome
    Back says "Your weekly chest paid out".
- The Quests screen has a new **Weekly** tab (goals, chest and the reset countdown), and the HUD's
  Quests badge counts chest steps ready to claim.

**In the code**
- `Config.Weekly`: `Unlock` ("weekly", Ranch Level 5 in `Config.Unlocks`), `GoalCount`, `RoyalLevel`,
  the `Pool` (21 goals `{ id, family, text, topic, target, filter?, unlock? }`, counted from existing
  bus topics) and the three-step `Chest`.
- `Logic/Weekly`: `Pick` (seeded by `Rng.seed("weekly", userId, week)`, unlock-filtered, one goal per
  family), `Done`, `Reached`, `Claimed`, `Unclaimed`, `ChestReward` (the Royal swap).
- `Logic/Objectives`: moved from `Systems/Quests/Objectives` (which now re-exports it) so Quests and
  Weekly share `Matches`, `Amount` and `Target`.
- `Systems/Weekly`:
  - Save section `{ week, goals = { { id, progress } }, claimed = { bool, bool, bool } }`.
  - Action `Weekly.Claim { step }`; rewards through `Rewards:Grant` with source "weekly".
  - The week is `Config.Leaderboards.Week`. The draw happens once, the first time the player is
    unlocked in that week, and then stays fixed. Rollover is lazy (join, goal topics, LevelUp and
    a 30 s sweep): unclaimed reached steps are paid and a `WelcomeItem` (kind "weekly") is published.
- UI: a Weekly tab in `Screens/Quests`; `Hud` adds claimable chest steps to the Quests badge;
  Welcome Back shows the "weekly" line with a gem icon.
- Tests: `Weekly.spec`, `WeeklyClient.spec`.

### Ranch Orders

**For players**
- **Ranch Orders** (Ranch Level 10): buyers post 3 orders every day (UTC) on the Job Board's new
  **Orders** tab (the HUD's Jobs button).
- **Monster orders** ask for a Teen or Adult with good genes:
  - **Easy**: one stat at grade C or better. **Medium**: one stat at grade B or better.
  - **Hard** (Ranch Level 20+): one stat at grade A, or two stats at grade B, or a gene total of
    60 or more (of 100).
  - Pay: 3 times the monster's sell price in coins, plus 5 / 10 / 25 gems and 2 / 5 / 10 Ribbons.
    A Hard order may also carry an egg (1 in 4): a Crystal Egg, or from Ranch Level 25 sometimes a
    Royal Egg. The card shows it.
  - "Choose monster" lists the Teens and Adults that meet it, not busy or locked, cheapest first.
    A confirm names the monster, which leaves the ranch for good. Your last monster can't go.
- **Goods orders** ask for 150–400 food of one flavour (more at higher levels) and pay 10–20
  gems and 5–10 Treats. At most one a day.
- **Reroll:** once a day, replace one unfilled order for free.
- Rejoining never changes the day's orders. Welcome Back mentions new orders.

**In the code**
- `Config.Orders` (difficulties, pay, egg chance and weights, goods amounts, buyers) and
  `Logic/Orders`:
  - `Draw(userId, day, level)`: the day's orders from `Rng.seed("orders", userId, day)`; each
    order rolls everything from its own seed (goods chance 20%, at most one goods order).
    Difficulty weights: Easy 60 / Medium 40 below Lv 20; Easy 35 / Medium 40 / Hard 25 from 20.
  - A reroll draws from `Rng.seed("orders", userId, day, "reroll", n)`. It can't draw goods while
    another order of the day is goods.
  - Goods pay comes from `Rng.seed(order.seed, "pay")`. Coins are `CoinMult × Formulas.SellPrice`,
    read before the monster leaves.
- `Systems/Orders` (save `profile.Orders = { day, list, rerolls }`):
  - `Orders.Fill { index, id? }` and `Orders.Reroll { index }`.
  - The list is drawn on join, on the minute timer, on any action and on reaching Lv 10.
  - Monsters leave through `Monsters:Remove(player, id, "order")`. Publishes `OrderFilled`.
- `Screens/Jobs` has "Jobs" / "Orders" tabs (params `{ tab }`). The picker uses Monsters pick
  mode with `sortBy = -SellPrice`. The HUD side button keeps its Name "Jobs".
- Tests: `Orders.spec`, `OrdersClient.spec`.

### Events calendar

Everyone has it (no unlock); it reads the dates already in the configs, so it needs no launch date.

**For players**
- **The calendar** (📅 under the Build hammer, top right) shows what's on now, what's next and
  when it starts:
  - **Now:** what's running, with an "Ends in" countdown (the seasonal event, the Ranch Pass
    season, the arena season, a live Stampede or Egg Hunt round).
  - **This week:** everything that starts before the Saturday reset.
  - **Coming up:** the next 30 days, plus the next seasonal event, titan invasion, region
    opening, Ranch Pass season, raid and Club Wars date however far away.
  - Each row has an icon, its date, a live countdown and a one-line blurb; **Go** opens its
    screen (Arena, Quests, Expeditions, Boss, Raids, Clubs, Leaderboards).
- **HUD chips:** up to two countdowns ("Titan  3:12:04") for anything starting in the next 24 hours,
  under the calendar button. Tapping one opens the calendar. They hide while a screen is open and
  never show the Stampede (it has its own card) or back-to-back Egg Hunt rounds.
- **Reminder:** players who turned reminders on can get a nudge 30 minutes before a titan
  invasion, a seasonal event or a region opening (within the usual 2 a day). Off until the owner
  fills its template id (`Config.Reminders.Templates.event`).

**In the code**
- `Logic/Calendar`: `Entries(now, horizon)`, `Now`, `Soon`, `Sections`, `NextBig`. Sources:
  `Config.Events` windows and reruns (respecting `Flags.ActiveEvent`), `Quests.Seasons`,
  `Titan.Schedule`, region and raid `opensAt`, `Clubs.War.startsAt`, `Logic/Arena` seasons,
  `Leaderboards.WeekEndsAt`, the next Stampede and `Logic/EggHunt.Round` during Spring Bloom.
- `Logic/Titan.NextStampede` / `HoldsStampede`: the Stampede slot, skipping periods a titan
  holds. The Boss system now schedules with it, so the calendar and the server agree.
- Screen `Events`; HUD `Events` button (y 172) and `EventChips`; reminder kind `event`
  (`Config.Reminders.Event`: 30 min lead, 14-day horizon under the MemoryStore expiry).
- Tests: `Calendar.spec`, `CalendarClient.spec`.

### Arena seasons

Season 1 runs from Saturday 3 October to Saturday 28 November 2026, 15:00 UTC. Seasons are 8
arena weeks long, back to back.

**For players**
- **Seasons:** the Champions Arena now runs in 8-week seasons on top of its weekly rewards,
  which are unchanged.
- **Soft reset:** when a new season starts, every rating moves halfway back to 1,000 (a 1,600
  Champion starts the next season at 1,300). It happens the first time your record is used in
  the new season, whether you play or someone fights your defense team.
- **Fresh matchmaking:** you only meet players who have fought or set a defense this season.
- **Featured lines:** each season features 3 species lines, the same on every server. Featured
  monsters fight at +10% stats, on both sides of the fight.
- **Season rewards:** your best tier of the season pays once, the first time you join or use the
  arena after the season ends (Welcome Back mentions it):

  | Best tier | Reward |
  |---|---|
  | Bronze | nothing |
  | Silver | title "Arena Silver" + 100 gems |
  | Gold | title "Arena Gold" + 200 gems + Gold Arena Cup |
  | Crystal | title "Arena Crystal" + 400 gems + Crystal Arena Cup |
  | Champion | title "Arena Champion" + 800 gems + Champion Arena Cup + Champion's Crown Aura |

  - Titles and the aura are Mastery cosmetics, worn at once if you wear none of that kind.
  - The cups are decor that is never sold.
- **Season tab** in the Arena screen shows:
  - the season and an ends-in countdown (before season 1: "Season 1 starts in ...");
  - the featured lines;
  - your season best;
  - the reward track;
  - the season top 10 and your rank.

**In the code**
- **Config and rules:**
  - `Config/Arena.Season`, `SeasonRewards` and `SeasonItems`. The season items are merged into
    `Config/Mastery.Rewards`.
  - Aura Vfx: `Config/Vfx.Mastery.championsCrown`.
  - Cups: `Config/Decor` (`price = nil`, `reward = "arena"`), built by the `cup` model in `Config/DecorArt`.
  - The Store skips decor with no price.
  - `Logic/Arena`: `SeasonAt`, `SeasonStartsAt`, `SeasonEndsAt`, `Featured`, `FeaturedSet`,
    `SoftReset` and `Reseason`. `Normalize(fighter, featured?)` sets `statMult`, and
    `Fight(attack, defense, seed, season?)` passes the season's featured set.
- **The Arena system:**
  - Profile v2 adds `seasonOf`, `seasonBest` and `seasonPaid`.
  - Records carry `season`.
  - `Arena:SeasonRating(player)`.
  - Mastery is an optional dependency, looked up when a reward is paid. Without it the gems and
    cups still pay.
  - A record from an older season takes one soft reset per season it missed.
- **The ratings index:** the adapter keeps one index per season
  (`Services.Arena.IndexName(season)`: `MonsterRanch_ArenaRatings_s<N>`; season 0 keeps
  `_v1`). `Index` and `Near` take the season as a last argument.
- **Leaderboards:**
  - Boards have a `period` ("week" or "season").
  - The new "arena" board is a season board: `Key("arena", n)` = `arena_s<N>`, and its value is
    the current season rating.
  - It has no weekly champion or title.
  - `Config.Leaderboards.Weekly` lists the weekly boards for the Leaderboards screen, the hub
    board and nameplates.
- **Tests:** `ArenaSeasons.spec`, `ArenaSeasonsClient.spec`.

## 3.7 · Ranch Jobs + Luck

Like 3.6, no launch date of its own: the Job Board and Luck work as soon as the update is published.

**For players**
- **The Job Board** (Ranch Level 6): Teens and Adults resting in the barn can take a job. Each
  of the five stats has one:
  - **Herder** (HP): while you're online, your pen monsters' Mood drops more slowly. A strong
    herder stops the drop, so they keep their coin bonus of up to +10%.
  - **Miner** (ATK): digs up coins, about 25–60% of what that monster would earn in a pen.
    ATK-strong species and ATK genes earn more.
  - **Guard** (DEF): every pen's coin jar holds longer, from about +7 minutes for a weak guard
    to +55 for a great one (all guards together at most +90).
  - **Forager** (SPD): gathers food in the flavour you pick, about 1 to 9 an hour.
  - **Scout** (Luck): a chance each hour to find an egg (Meadow, Grove, Crystal or Royal, from
    the ones you've unlocked), about one egg per 8 hours for a top scout.
- **Slots:** 2 at Ranch Level 6, 3 at 20, 4 at 35 and 5 at 50.
- **How it pays:** workers keep working online and offline, storing up to 8 hours of work.
  - Collect all pays everything; recalling a worker pays what it has stored.
  - The HUD's Jobs button shows how many workers are full, and Welcome Back mentions them.
- **Picking a worker:** the Job Board lists your free barn monsters best at that job's stat
  first. Rarity, level, stars, traits and genes all help.
- **Luck counts:**
  - In battles, Luck adds crit chance on top of the base 5%: about +0.8% at Luck 13 and +5.6%
    for a maxed Mythic, at most +8%. The Arena gives every fighter the same Luck.
  - On expeditions, the squad's Luck adds up to +15% loot.
- **A fifth gene:** Luck has a gene pair now, so gene totals are out of 100.
  - Monsters from 3.6 keep their four genes exactly as they were and gain a Luck pair.
  - Monster Detail grades Luck, and the Breeding Barn shows all five stats.

**In the code**
- `Config.Jobs` (the jobs, slots, rates and caps) and `Logic/Jobs`:
  - `Power` = stat ÷ `RefBase`; rates run on √power; the miner uses `CoinRate × MinerShare × ATK affinity`.
  - `Collect` pays with a `carry` for fractions. Scout eggs are rolled per whole hour from
    `Rng.seed("scout", slot.seed, hour)`, so they can't be rerolled.
- `Systems/Jobs`:
  - Save section `slots` (always 5) and session `slotCount`.
  - Actions `Jobs.Assign`, `Jobs.Recall`, `Jobs.Collect` and `Jobs.SetFlavor`; busy tag `"job"`; bus topic `JobsCollected`.
  - Guards through `Ranch:RegisterJarBonus("jobs")`; herders through the new
    `Monsters:RegisterMoodDecayModifier("jobs")` (pen monsters only; Mood can now be fractional).
  - Unlocks `jobs` (6) and `jobs_slot_3/4/5` (20, 35, 50).
- Luck:
  - `BattleSim.LuckCrit` (`LuckCritK`, `LuckCritScale`, `LuckCritMax`).
  - `Loot.LuckBonus` (`LuckLootK`, `LuckLootScale`, `LuckLootMax`), added in `Expeditions:LootBonus`.
- Genetics:
  - `Config.Genetics.Stats` gains `luck` (appended, so seeded rolls keep their order).
  - `Genetics.Fill(genes, rng)` keeps valid pairs and rolls missing ones. `MonsterGen.New` and
    `Monsters:Insert` use it.
  - The Monsters save is version 3: the migration fills the Luck pair from `Rng.seed(seed, "fill")`,
    so it is not a copy of the HP pair.
- UI:
  - New `Screens/Jobs` and a HUD Jobs button (left stack, full-storage badge).
  - Monsters pick mode takes a `sortBy`.
  - Breeding shows parent grades 3 + 2 and the gene preview as a 3-column grid.
  - A "Working" busy label.
- Specs: `Jobs.spec` (rules, the board on the server, Luck, the v3 migration) and
  `JobsClient.spec` (picker order, collect, flavour, recall, the HUD badge, locked slots, Spanish).
  The genetics specs cover five genes.

## 3.6 · Genetics

No launch date of its own: genes switch on the moment the update is published, and every
monster already on a ranch gets its genes the first time its owner joins.

**For players**
- **Stat genes.** Every monster carries two genes each for **HP, ATK, DEF and SPD**, one
  from each parent. Each gene is worth 0–10 points and every point adds **+1%** to its stat,
  so a perfect pair is +20%. Luck has no gene.
- **Grades:** each stat's pair is graded **D** (0–4), **C** (5–9), **B** (10–13), **A**
  (14–17) or **S** (18–20).
- **Where genes come from:** hatched and reward monsters roll each gene at 0–5 (mostly C,
  a lucky B). A and S only come from breeding.
- **Breeding:** for each stat the baby gets one of parent A's two genes and one of parent
  B's, at random, so a strong line has to be bred for. Every gene a baby inherits has an 8%
  chance to **surge** +1 and a 1% chance to surge +2 (up to 10). Genes never drop.
- **Your monsters keep their power:** monsters from before this update get genes too
  (rolled once, the same every time), and genes only ever add to stats.
- **Only stats:** genes never change how a monster looks, its size, its coin income, its
  sell price or the breeding fee.
- **Where you see them:**
  - **Monster Detail:** a grade beside HP, ATK, DEF and SPD (tap it for the pair, e.g.
    "ATK genes: 7 + 8 = +15%") and a "Genes 41/80 · Gen 6" line (tap it for how genes work).
  - **Breeding Barn:** both parents' grades, the baby's bonus range for each stat before
    surges ("ATK +6–11%"), and the number of genes that surged when you claim the baby.
  - **Monsters:** a new **Genes** sort.
  - **Market:** listings show the monster's gene total. Genes travel with traded and sold
    monsters.

**In the code**
- `Config.Genetics`: the gene stats, `MaxGene`, `PctPerPoint`, `HatchRange`, `SurgeChance`,
  `BigSurgeChance` and the grade table.
- `Logic/Genetics`: `Roll`, `Seeded`, `Inherit` (one gene of each parent's pair, then
  surges), `Valid`, `Copy`, `Pair`, `Points`, `Bonus`, `Total`, `Grade`, `Range`, `Preview`.
  A record without genes (enemies, raid bosses) counts as all zero.
- Monster records have `genes = { hp = { a, b }, atk = …, def = …, spd = … }`.
  - `Formulas.Stats` multiplies HP, ATK, DEF and SPD by `1 + Genetics.Bonus`. `CoinRate`,
    `Value`, `SellPrice` and `Appearance` don't read genes.
  - `MonsterGen.New` rolls genes last, or copies `spec.genes`, so every earlier roll is
    unchanged.
  - `Breeding.Roll` inherits them last and sets `spec.surges`. `Breeding.Outcomes` has
    `genes = Genetics.Preview(...)`, and `Breeding.Claim` returns `surges`.
- The Monsters save is version 2. `Migrate` gives every pre-genetics record
  `Genetics.Seeded(Rng.seed("genes", id, born))`, and `PlayerAdded` repeats that for a
  save whose migration failed. `Monsters:Insert` keeps genes, and gives a record escrowed
  before genetics a fresh roll.
- `genes` is one of Trade's `VALUE_FIELDS`, and Market's `ItemView` carries `genes` (false
  for an egg).
- UI: `UI/Components/GeneGrades` (grade colours, a badge, a four-stat row). Changed:
  MonsterDetail (stat rows 22 px to make room for the gene line), Breeding (parent cards,
  preview row, claim dialog 480 × 420), the Monsters sort and the Market item line.
- Specs:
  - `Genetics.spec`: rules, inheritance and surge rates, stats and nothing else, earlier
    rolls unchanged, server breeding, the v2 migration twice, Insert and the Market view.
  - `GeneticsClient.spec`: Monster Detail with a column-fit check, Spanish, the Breeding
    Barn with a forced surge, and the Genes sort.
## Glow-up · The premium pass

Not a dated content drop: presentation, feel and new ways to play across the whole game, built
from the Glow-Up plan (37 items). Everything is live as soon as it is published; the Deep Reef
keeps its own opening date in `Config/Regions`.

**For players**
- **Sound everywhere:** licensed music for the ranch by day and night, the hub, battles, the
  Stampede, raids, racing and every event; ambience (birds by day, crickets at night, wind, rain,
  the fountain, the plaza crowd); UI clicks; hatch, evolve, level-up and reward stings; and a
  voice for every monster family, pitched per monster.
- **Rewards you can feel:** coins, gems and items fly to their counters, celebrations scale with
  the size of the win (confetti, a coin shower, a camera kick for the huge ones), and every toast
  and reward card shares one queue above popups.
- **Your monsters, alive:**
  - Tap your 3D monsters (they were not tappable), and see their hats, scarves and Golden,
    Rainbow and Shadow looks on the 3D models.
  - Every monster sleeps, eats, cheers, attacks, flinches, faints, sits and does tricks, blended.
  - Personalities: Gluttons hang around the food, Night Owls stay up, Show-offs pose when you walk
    past, Cheerful monsters start chases; pen-mates nap in a pile at night, run to the fence to
    greet you, shake off rain, shiver in snow and shelter from storms. Mood bubbles show how they feel.
  - Care for them: Pet, Brush and Play gestures raise Bond hearts (1 to 10) that never decay;
    tricks at 3, 6 and 9 hearts, a nameplate at 7, a small coin bonus, best friends at your gate.
  - Take one for a walk (three with VIP): it trots beside you in the hub, on the Sky Islands and
    on every ranch; mounts now run in step with your speed.
- **Big moments:**
  - Eggs hatch on your incubator: the rarer the monster, the longer the wobble; Mythic hatches
    light up the sky; NEW! and SHINY! stamps; Hatch All plays a montage, rarest last.
  - Watch your monsters evolve in their pen inside a swirl of their element.
  - The Stampede is live: every 30 minutes the sky darkens, thunder rolls and a giant charges into
    the new arena east of the Market Square. Everyone's squads gather round it, Cheer throws bolts in
    your lead monster's element, and the loot bursts out of the fallen giant.
  - Expeditions send postcards: a diorama of your squad in the region, kept in an album per region
    (favourites stay), and one a day can go to a friend.
- **New ways to play:**
  - Battles play out in 3D: arena, expedition and raid fights run on a stage themed to the region
    (or the Arena or a raid) with your team and the enemies as real monsters. Attacks lunge,
    elements fly as bolts, hits flash and float damage, and the camera cuts in for big hits and the
    finishing blow. Tap for 2x speed or Skip; older phones and full raids keep the 2D view.
  - Titan invasions: on set Saturdays a titan invades every server at once. Each server fights its
    own copy at the Stampede arena, but everyone's damage drains one shared HP bar that shows how
    many servers and players are fighting. Join from the banner (even mid-fight) and Cheer; when it
    falls, everyone who dealt damage gets a guaranteed Titan Egg. No Stampede runs meanwhile.
  - Live races: up to six riders (ghosts fill the empty lanes) on a new track west of plot 6, with
    a 3-2-1-GO countdown, laps, checkpoint arches, hurdles, boost pads and a podium. Racing gear
    (saddles, trails and banners) is earned from races and shows on your mount; the classic race
    is still there.
  - The Deep Reef (opens Sat 1 Jul 2028): dive from the Dive Dock by the Market Square into a
    glowing underwater world of coral, kelp, sunken ruins and fish. Swim anywhere, ride monsters
    that swim (faster, with their own paddle), meet three new Tide lines (Finnip, Glowray and
    Shellkin), find Reef Eggs and face the Kelp Warden and the Lantern Tide.
- **A ranch to show off:**
  - Build your ranch: a Decorate mode on your own plot (grid, rotate, move, undo, save) with 60+
    pieces placed anywhere, not just in pens: fences, paths, lamps that light at night, water,
    plants, seats, arches, statues and toys your monsters go and play on; seasonal sets for every
    event and a free starter set for everyone.
  - Real 3D eggs (18 painted designs, ornaments, three crack stages).
  - Pens that grow: fences from wood to crystal, a hay nest, trough, pond, hut and shade tree as
    you upgrade, themes with real materials and signature props, element habitats, and a Feed
    Garden you can see growing.
  - A living world: clouds that follow the weather, sun rays, a golden hour, lamps and windows that
    light at dusk, swaying trees and windmills, butterflies, fireflies, birds and fish.
  - Photo mode: a free camera, 7 filters, frames, stickers, depth of field and a Pose button.
  - Titanic monsters: a rare size roll makes a monster far bigger, with a deeper voice, its own
    aura and a celebration when it hatches (the odds are in the Egg Shop). Event monsters are
    numbered limited editions (#37/500) and keep their number when traded or sold.
- **Collect and come back:**
  - The Codex pays: element, egg, region and collection milestones give gems, titles, badges and
    the Codex Crown aura; walk the new Codex Museum; the Hall of Fame Plaza shows everyone's best
    statue.
  - A daily login calendar with milestones at 7, 14, 21 and 28 days, a weekly Streak Shield and
    the Golden Streak Scarf; optional reminders for ready eggs, returning expeditions and the Stampede.
  - Past the level cap, Ranch XP builds endless Ranch Mastery; every species line earns Mastery
    tiers and an aura; Star Shards buy trait rerolls (odds shown), auras, flourishes, plinths and
    small perks; a seasonal Mythic Ladder and a weekly Mastery leaderboard.
- **Visit each other:** liking a ranch pays you both once a day (not yet for brand-new players); a
  crown floats over the server's most-liked ranch of the day; visit a friend's ranch on their
  server or as a snapshot in the Visiting Showcase; last week's most-liked ranch stands on the
  Ranch of the Week stage.
- **Friends and VIP:** an emote and trick wheel, gifts to Roblox friends (eggs, food, decor,
  accessories, a Ranch Pass), invites, the group reward, Premium perks; VIP Ranchers get a daily
  crate, a gold name, a chat tag and the VIP Balcony.
- **New look:** portraits for every monster, a full icon set, and textured panels and buttons.
- **Smooth on every phone:** graphics pick High, Medium or Low from how your device runs (or
  choose in Settings), faraway ranches draw less, and effects stay inside a particle budget.

**In the code**
- Audio: `client/Audio` (+ `Voices`), `Controllers/Soundscape`, `Config/Sounds` (ids, variations,
  scatter beds, duck/duckHold), `Logic/Audio`; Sound Check screen in Studio.
- Feel: `Controllers/Celebrate`, `UI/Components/Toasts`, the Feedback layer, `Logic/Celebration`,
  `Controllers/Stampede`, Hud counter hold/release.
- 3D monsters: `Hit` tap box, accessories on bones (`MeshMonster.Slot/Attach/Follow`),
  `Visuals/MonsterLooks` (EditableImage recolours, LRU of 8), clip tables per form
  (`Visuals/MeshMonsterClips`, `tools/blender/clips.py`), `Visuals/PenBrain` + `Logic/PenLife`,
  `Systems/Bond` + `Controllers/Care`, `Systems/Companions` + `Controllers/Companions`/`Mounts`.
- Cinematics: `Controllers/CameraDirector`, `Controllers/Cinematics`, `Logic/Cinematic`.
- World: `Visuals/EggModel` + `EggAssets`, `Visuals/PenDress` + `Controllers/Pens` (`PenSpot` /
  `Habitat` attributes), `Controllers/Sky`/`Lamplight`/`SceneryMotion`/`Critters`,
  `Controllers/PhotoMode` + `Logic/PhotoRig`.
- Systems: `Codex` (+ museum and plaza controllers), `LoginStreak`, `Reminders` (its Roblox services in
  `Kernel/RemindersAdapter`), `Mastery`, `Community`, `Gifts`, `Postcards`, VIP crate in `Monetization`;
  `Adapters.Roblox` gains `Badges.Award`.
- Titanic and editions: `Logic/Titanic` (the size roll, last in `MonsterGen`), `Systems/Editions` +
  `Logic/Editions`, `Controllers/EditionPlates`, `UI/Screens/Parts/ShowpieceChips`; the
  `Services.Editions` counter (`MonsterRanch_Editions_v1`).
- Visits: `Systems/Visits` + `Logic/Visits`, `Controllers/Visits`, `Visuals/RanchShowcase`; the
  `Services.Ranches` adapter (`MonsterRanch_Ranches_v1` snapshots, friends located through
  `TeleportService`).
- Battle stage: `UI/Screens/Parts/Battle` (picks 3D or 2D), `BattleStage`, `BattleResult`,
  `Visuals/BattleArena` (Workspace.BattleStage, far outside the map; pooled models and effects),
  `Logic/BattleStage` + `Config/BattleStage`; `CameraDirector` stage shots (cuts, no letterbox).
- Build your ranch: `Systems/Decor` + `Logic/DecorLayout` (server-checked layouts), `Config/Decor`
  (+ `DecorArt` part recipes), `Controllers/Decor`, `Visuals/DecorModel`, `UI/Screens/Decorate`.
- Titans: `Systems/Titan` + `Logic/Titan` + `Config/Titan`, `Controllers/TitanInvasion`; the
  `Services.Titan` adapter (a MemoryStore hash map entry per invasion, reported off the scheduler
  thread); Boss skips periods that overlap an invasion.
- Live racing: `Systems/LiveRace` + `Logic/LiveRace` + `Config/LiveRace` (positions checked on the
  server against the track), `Systems/RaceGear`, `Controllers/LiveRace`, `Visuals/RaceTrack`.
- Deep Reef: `Config/DeepReef`, `Logic/Swim`, `Controllers/DeepReef` (dive, swim, the local light),
  `Visuals/ReefBuild` + `ReefLife`; the Reef region, egg and Tide lines in their configs.
- Stampede: `Controllers/StampedeArena` + `Logic/StampedeArena` (arena, giant, rings, bolts, fountain,
  storm), `global.Boss.squads`, `Config.Boss.Arena`.
- UI art: `UI/Art/Sheet`, `Portraits`, `Icons` (generated by `tools/ui`), 9-slice textures in `Theme`.
- Quality: `Visuals/Quality`, `Controllers/Quality`, `Logic/Quality`, `Logic/ParticleBudget`,
  the Settings Graphics row, the Studio `PerfOverlay`.
- Owner steps before publishing: GO_LIVE §5 (reminder templates and the Open Cloud secret),
  Codex badge ids. The 22 UI sheets, every sound id and the new egg textures are already uploaded.

## 3.2 · Frostbite Glacier + Level 70

Launch Sat 11 Mar 2028. Everything is dated in config: Frostbite Glacier and the Frost
Leviathan open, and the Ranch Level cap rises, on 11 Mar; Season 8 starts on 4 Mar. So this
update can be published any time before 4 Mar.

**For players**
- **Frostbite Glacier** (region 7, Ranch Level 55) opens on 11 Mar 2028. It was built in 3.0
  and was waiting for its date.
- **Ranch Level 70** (from 11 Mar 2028): the cap rises from 60 to 70. Ranches already at 60
  start earning toward 61 right away.
  - **Incubator 4** at Ranch Level 62. With the Extra Incubator pass you can have 5 incubators.
  - **Pen 6** at Ranch Level 66 (10B coins) completes a 3 × 2 grid of pens. The incubator pad
    moved to the back of the ranch and the barn moved back a little.
  - **Squad size 5** at Ranch Level 70, for stage fights, expeditions, caravans and the
    Stampede. The Expeditions screen shows locked squad slots with the level that opens them.
- **Raid 3: the Frost Leviathan** (from 11 Mar 2028, Ranch Level 60), a 4-player raid under the
  glacier.
  - **The fight:** it regrows its HP every turn and its Aurowl heals it, so the team that beats
    the Umbral Wyrm runs out of time. Bring Void and Sprout monsters.
  - **The reward:** wins pay the **Leviathan Egg**, the only way to hatch
    **Floelet → Rimecoil → Frost Leviathan** (Tide/Light).
  - **Before it opens:** raid cards show the opening date or the level needed, and a lobby
    shows the level a player needs to join.
- **Controller support:** play with a gamepad.
  - The D-pad or stick moves a gold cursor, A presses, B goes back, LB/RB switch tabs and Y
    opens your monsters.
  - Racing jumps with A (or D-pad ↑) and boosts with RT; Surf steers with the D-pad or the stick.
  - A small key guide shows in the corner while a controller is in use. Touch or the mouse
    puts everything back.
- **Español and Português (Brasil):** the whole game in Spanish and Brazilian Portuguese,
  including menus, messages, and the names of eggs, items, places and quests.
  - It follows your Roblox language, or pick one under **Settings → Language**.
  - Monster names stay the same in every language.
- **Ranch Pass Season 8, "Frostbite"** (4 Mar – 15 Apr 2028): Glacier Eggs through the tiers,
  Leviathan Eggs on the premium track, and a Legendary Pengling at the top.
- **Code:** `FROSTBITE` gives a Glacier Egg and 50 gems. It expires on 1 Apr 2028.
- **New achievements:** beat the Frost Leviathan, and clear the Frostbite Glacier.
- Error toasts that used to show a code ("TooFast", "BadRequest") now say what happened.

**In the code**
- **Level 70:**
  - `Config.Unlocks.LevelCaps` (dated `{ level, from }` steps) and `MaxLevelAt(now)`.
    Progression and the HUD's "MAX" read the cap in force; `MaxLevel` (70) is the all-time
    ceiling.
  - New unlocks `incubator_4` (62), `pen_6` (66) and `squad_5` (70).
  - `Economy.Pens.max = 6` and `Economy.Incubators.maxSlots = 5`. The Eggs save is version 2
    with always 5 slots; `Migrate` adds an empty 5th slot to old saves.
  - `Regions.SquadSize = { base, steps = { { unlock, size } } }`. `BattleSim.MaxAllies = 5`,
    so replays have ally keys `a1..a5`. Raids still pass `maxAllies = 8`, and Arena teams
    stay at 3.
  - `Api.luau` takes the squad and pen limits from config.
  - `Config.World`: pen 6, the moved pad and barn, and size keys that Build and the World
    controller share. `LevelSeventy.spec` checks that no plot footprints overlap.
- **Raids:**
  - Raids take an optional `opensAt` and a per-raid `unlock` (`Config.Raids.IsOpen`,
    `UnlockFor`). `Raids.Open` checks the date and the host's level, and `Raids.Join` checks
    the joiner's.
  - New unlock `raid_leviathan` (60). The `floelet` line uses the `slug` body, `drain` and
    `regen`, with `raid = true` and its own `leviathan` pool. The Leviathan Egg has odds
    `{ 0, 0, 35, 40, 20, 5 }`.
  - Tuned with BattleSim over 40 seeds: eight maxed Mythics that beat the Wyrm lose 40/40;
    eight maxed Void/Sprout Mythics win 40/40.
- **Localization** (`docs/LOCALIZATION.md`):
  - `Shared/Locale` holds the Spanish and Portuguese catalogues. They are keyed by the English
    text, with `{n}` templates, and pieces are translated inside templates and lists.
  - The `Localize` controller translates every text object in the PlayerGui and the
    Workspace. It shrinks longer translations to fit, and it turns off Roblox's own
    AutoLocalize.
  - `profile.Settings.language` is `"auto" | "en" | "es" | "pt"`, set with the new
    `Settings.SetLanguage`. The Settings screen has a Language row first.
  - `StoreKit.errorText` maps kernel error codes to words.
- **Controller:**
  - The `Gamepad` controller keeps the cursor inside the open screen or dialog. It is
    level-triggered, so a screen already open when the pad is picked up is scoped too.
  - Dialogs, InsetPopup, the hatch reveal and the evolution popup register with `UI/Focus`, so
    B runs their own close.
  - `Widgets.Tabs` gained `Step`, plus `Widgets.FindTabs`. A screen root with a
    `GamepadLegend` attribute (Racing, Surf) hides the cursor during a run. The world prompts
    set `GamepadKeyCode`.
  - `Router:Root(name)` is new.
- **Test harness:**
  - RobloxMock emulates pad input, ContextActionService and `Player.LocaleId`.
  - ClientHarness takes `localeId` and has `UseGamepad`, `Press`, `Stick` and `Selected`.
  - `t.LocaleHarvest` finds the text the game can show. With `LOCALE_REPORT=<file>`, the
    Locale specs write what is still missing.
- **Tests:**
  - `LevelSeventy.spec` (12) and `LevelSeventyClient.spec` (4).
  - `FrostLeviathan.spec` (10) and `FrostLeviathanClient.spec` (2).
  - `Locale.spec` (16): matching rules, catalogue integrity, and every Config text and server
    message translated.
  - `LocaleClient.spec` (7): switching language in place; a walk as a new and a veteran player
    that finds every shown text translated; fit on a 568×320 phone in both languages.
  - `GamepadClient.spec` (10).
  - RobloxMock's unset enum properties now default to the item with the lowest value. They
    used to take whichever item came first, which changed from run to run.
- **Snapshots:** `docs/snapshots/3.2-raids.png` and `3.2-spanish.png`. The snapshot tool gains
  `SNAPSHOT_LOCALE`.

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
