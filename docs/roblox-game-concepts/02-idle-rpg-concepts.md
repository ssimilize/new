# Part 2 — Idle RPG Concepts (Main Focus)

Six idle RPG concepts, each built on the findings in [Part 1](01-research.md). All of them follow the same rules:

- **GUI-first, not GUI-only** — the depth lives in panels, but there is a small shared 3D hub so players see each other.
- **True offline progress** (calculated on rejoin, capped).
- **2–3 prestige layers.**
- **Co-op social hook** that works even when players are mostly idle.
- **Monetization = speed, convenience, cosmetics.** Randomized paid items always show odds.

Each concept ends with a scorecard (1–5, higher = better) so they can be compared. A comparison table and a recommendation are at the end, followed by a full design sheet for the top pick.

---

## Concept 1 — **Guildhall Idle** *(idle RPG + town builder)*

> *"Run the adventurers' guild. Heroes quest while you're away — you build the town that makes them stronger."*

**Inspiration:** Evil Hunter Tycoon's planning layer + AFK Arena's hero collection + Roblox tycoon bases.

**Core loop**
1. Heroes (auto-battling) clear quest zones and bring back gold, materials and loot.
2. You spend materials on **town buildings** (Blacksmith, Tavern, Mage Tower, Farm…) that buff heroes or unlock new classes.
3. Better heroes → harder zones → rarer materials → better buildings.

**Progression layers**
- Hero levels & gear (minute-to-minute)
- Buildings & town layout (hour-to-hour) — *the planning layer: adjacency bonuses, e.g. Forge next to Mine = +10% ore*
- **Renown (prestige 1):** retire your guild, keep a Renown currency for permanent perks
- **Kingdom Charter (prestige 2):** unlock a new region with new rules (e.g. desert: water is a resource)

**Social hook:** Your town is a physical plot in a shared server (like a tycoon). Other players can walk through it. **Server World Boss** every 30 minutes — every online player's heroes contribute damage, everyone gets loot scaled by contribution. Guilds (real player guilds) pool resources for a Guild Monument.

**Monetization:** VIP pass (+1 hero slot, 12 h offline cap), Auto-Sell pass, 2× Gold pass, building skins, rewarded ad → "2× offline haul".

**Why it works on Roblox:** It's a tycoon (proven) wearing an RPG skin (best-retaining genre). The town is a visible social object. Planning layer = week-4 retention.

**Risks:** Two systems (heroes + town) is more UI to build; must be very clear on mobile.

| Fun ceiling | Roblox fit | Viral hook | Scope (5 = small) | Retention | 
|---|---|---|---|---|
| 5 | 5 | 3 | 2 | 5 |

---

## Concept 2 — **Realm of Skills** *(Melvor / RuneScape-style skilling idle)*

> *"Pick a skill, let it run. Chop, mine, smith, cook, fight — every skill feeds another."*

**Inspiration:** Melvor Idle, RuneScape, Idle Clans — a **pure GUI-heavy** design, the most "GUI game" of the set.

**Core loop**
1. Choose one active skill (Woodcutting, Mining, Fishing, Smithing, Cooking, Alchemy, Combat…). It ticks automatically.
2. Output of one skill is input to another (logs → Firemaking, ore → Smithing → gear → Combat → drops → Alchemy).
3. Each skill has **Mastery** per action (e.g. Oak Tree mastery 99) that unlocks passive bonuses.

**Progression layers**
- Skill level 1–99 (and 120 "elite" levels later)
- Per-item mastery
- **Pets** — rare drops per skill that give a permanent bonus
- Dungeons & slayer tasks for combat endgame
- **Legacy mode (prestige):** optional restart with a modifier (e.g. "Ironman — no trading") for a cosmetic badge and a bonus

**Social hook:** A **Player Market** (server-authoritative order book) — everything gathered can be sold to other players, which gives every skill real value. **Skilling spots in the 3D hub** — stand next to friends at the same "Mining Rock" for a +5% co-op XP bonus. Weekly **Skill Cup** leaderboard (most XP in Fishing this week).

**Monetization:** Extra bank tabs, 2nd action queue ("do two skills at once") pass, 12 h offline cap pass, cosmetic outfits & pets, XP boost products (limited, non-PvP).

**Why it works on Roblox:** Deep, proven design with an older audience (18+ is the growing, higher-spending segment). Almost no competition on Roblox for a polished Melvor-like. Content is **data-driven** — easy to add a new skill each month.

**Risks:** Weakest first-60-seconds — Melvor's opening is slow. Must front-load rewards (first level-up in 10 s, first pet teaser early). Younger players may bounce. Market economy needs anti-dupe discipline.

| Fun ceiling | Roblox fit | Viral hook | Scope | Retention |
|---|---|---|---|---|
| 5 | 3 | 2 | 3 | 5 |

---

## Concept 3 — **Endless Tower Idle** *(idle auto-battler + roguelite floors)*

> *"Your team climbs the tower on its own. Every 10 floors, pick a blessing. How high can you go?"*

**Inspiration:** Shiba Story Go's roguelite floors, AFK Arena's idle stages, Tower of Hell's "how high?" competition.

**Core loop**
1. A team of up to 5 heroes auto-fights floor after floor.
2. Every 10 floors, choose 1 of 3 **Blessings** (roguelite build choices: "Fire attacks chain", "Healers overheal into shields").
3. When the team stalls, you **Ascend**: reset to floor 1, keep Soul Shards for permanent upgrades, blessings reset → new build next run.

**Progression layers**
- Hero levels / stars
- Permanent Soul upgrades (prestige 1)
- **Tower Seasons** (prestige 2, time-based): every 4 weeks a new tower with a new rule set and a season leaderboard
- Active skills you can tap for burst (optional active play for players who want it)

**Social hook:** **Co-op climb** — link up with up to 3 friends; your teams fight side by side and blessings are chosen by vote. Server-wide **"Highest Floor" board** in the hub, with the top player's team displayed as statues.

**Monetization:** Extra blessing reroll (product), Season Pass (cosmetic + convenience track, earnable free track), hero skins, auto-ascend pass, rewarded ad → "revive once".

**Why it works on Roblox:** One-sentence pitch, built-in leaderboard competition, build variety (week-4 retention), seasons = natural LiveOps cadence.

**Risks:** Combat balance across hundreds of floors; need big-number handling early.

| Fun ceiling | Roblox fit | Viral hook | Scope | Retention |
|---|---|---|---|---|
| 4 | 5 | 4 | 3 | 4 |

---

## Concept 4 — **Monster Ranch Idle** *(Grow-a-Garden × creature RPG)*

> *"Hatch monsters, raise them on your ranch, send them on expeditions while you sleep."*

**Inspiration:** Grow a Garden's real-time growth, Pokémon/Digimon raising, Adopt Me's trading.

**Core loop**
1. Buy/earn **eggs** → incubate on your ranch (real-time, continues offline).
2. Monsters grow through stages (baby → teen → adult) depending on food and care → different evolutions.
3. Send adults on **Expeditions** (1 min – 8 h, idle battles) for gold, food, and new eggs.
4. **Breed** two monsters → offspring inherit traits (mutations are rare and tradeable).

**Progression layers**
- Ranch expansion (more pens, better incubators)
- Monster stats, traits and evolutions
- **Bloodlines (prestige):** retire a legendary monster to the Hall of Fame for a permanent ranch-wide buff
- Weather/season events that spawn special mutations (Grow a Garden's best trick)

**Social hook:** Your ranch is visible in the server; **trading** of monsters with rare mutations; friends can visit and "pet" your monsters for a small happiness buff (daily co-play reason). Server-wide **Wild Boss** that ranch teams fight together.

**Monetization:** Incubator speed-up is **not** sold (avoid timer-skip backlash). Sell: extra pens pass, auto-feed pass, cosmetic ranch decor, egg-luck boosts (with shown odds), rewarded ad → "free food crate".

**Why it works on Roblox:** Combines the two biggest idle patterns on the platform (growth timers + collectible trading) with RPG battles. Very easy to explain to kids; deep enough for teens via breeding.

**Risks:** Trading economies need careful dupe protection and scam-safe trade UI. Crowded "pet" space — the breeding/evolution twist must be front and center.

| Fun ceiling | Roblox fit | Viral hook | Scope | Retention |
|---|---|---|---|---|
| 4 | 5 | 5 | 2 | 5 |

---

## Concept 5 — **Idle Cultivator** *(training-stat idle RPG, original "anime-style" IP)*

> *"Meditate, train, break through. Grow from a weak disciple into a sky-splitting immortal."*

**Inspiration:** Cultivation (xianxia) novels, *Cultivation Incremental* and *Immortality* on Roblox, anime training games. **Original IP** — avoids the copyright risk of One Piece/Naruto clones.

**Core loop**
1. Train stats (Body, Qi, Spirit) automatically; tap to "focus" for active bursts.
2. Hit a stat threshold → attempt a **Breakthrough** (a short boss fight / mini-game). Success = new realm, big multiplier.
3. Each realm unlocks techniques (skills) and new training grounds.

**Progression layers**
- Stats → Realms (Qi Condensation → Foundation → Core → Nascent Soul …)
- Techniques & artifacts (equip loadout)
- **Reincarnation (prestige 1):** keep Karma for permanent talents
- **Heavenly Tribulation (prestige 2):** ultra-rare, server-announced event with a big cosmetic reward

**Social hook:** **Sects** (guilds) with a shared sect hall; **Sparring** (friendly PvP duels with normalized stats); server-wide announcement when someone breaks through a major realm (social brag moment).

**Monetization:** Auto-breakthrough pass, extra technique slot, aura cosmetics (huge for this audience), rewarded ad → "Tribulation protection".

**Why it works on Roblox:** Anime/fighting is the fastest-growing genre in 2026; stat-training idle is a proven Roblox pattern; auras and titles are strong cosmetic sinks.

**Risks:** Theme is niche outside anime fans; realm names must be easy for kids to read.

| Fun ceiling | Roblox fit | Viral hook | Scope | Retention |
|---|---|---|---|---|
| 4 | 4 | 4 | 4 | 4 |

---

## Concept 6 — **Dungeon Deckmaster Idle** *(idle deck-builder RPG)*

> *"Build a deck, your hero plays it automatically. Tune the deck, not the reflexes."*

**Inspiration:** Slay the Spire, Hearthstone Battlegrounds, auto-chess, idle auto-battlers. Card games are naturally GUI-first.

**Core loop**
1. Your hero auto-plays your deck of skill cards against dungeon enemies.
2. Earn card packs / crafting dust from runs (idle + offline).
3. Tweak the deck between runs: synergies (Burn deck, Poison deck, Shield deck).

**Progression layers**
- Card upgrades (level + rarity)
- Heroes with passive traits that change which decks work
- **Relics** (permanent run modifiers)
- **Ascension levels** (prestige: harder dungeons, better drops)

**Social hook:** **Async PvP arena** — your deck vs. other players' decks, simulated (no pay-to-win: rank matches use normalized card levels). Deck sharing codes. Weekly "Draft Cup" with friends.

**Monetization:** Card sleeves & hero skins, extra deck slots, battle pass, dust boosts. Card packs purchasable **only with shown odds and never needed for ranked**.

**Why it works on Roblox:** Almost no quality card/deck-builder on Roblox; fits the GUI skillset perfectly; strong for older players.

**Risks:** Hardest concept to explain in a thumbnail; card balance is ongoing work; smaller audience than pets/farming.

| Fun ceiling | Roblox fit | Viral hook | Scope | Retention |
|---|---|---|---|---|
| 5 | 3 | 2 | 3 | 4 |

---

## Comparison & recommendation

| # | Concept | Fun | Roblox fit | Viral | Scope | Retention | **Total /25** |
|---|---|---|---|---|---|---|---|
| 4 | **Monster Ranch Idle** | 4 | 5 | 5 | 2 | 5 | **21** |
| 1 | **Guildhall Idle** | 5 | 5 | 3 | 2 | 5 | **20** |
| 3 | **Endless Tower Idle** | 4 | 5 | 4 | 3 | 4 | **20** |
| 5 | Idle Cultivator | 4 | 4 | 4 | 4 | 4 | 20 |
| 2 | Realm of Skills | 5 | 3 | 2 | 3 | 5 | 18 |
| 6 | Dungeon Deckmaster Idle | 5 | 3 | 2 | 3 | 4 | 17 |

**Recommendation depends on your goal:**

- **Biggest audience / best viral odds → Monster Ranch Idle.** It rides the two strongest proven idle patterns on Roblox (growth timers + collectible trading) and adds RPG depth.
- **Best "idle RPG" in the classic sense, strongest long-term retention → Guildhall Idle.** Tycoon + RPG + planning layer.
- **Smallest team / fastest to ship → Endless Tower Idle or Idle Cultivator.** Fewer systems, clear one-line pitch, seasons give LiveOps for free.
- **If you're already building a Melvor-style skilling game → Realm of Skills**, but add the social hub, market, and a much faster first minute (see notes above). Consider bolting a Guildhall-style town on top later — the two concepts combine well (skills produce materials, the town consumes them).

---

## Full design sheet — Guildhall Idle (example of taking a concept to build-ready)

> Guildhall Idle is detailed here because it is the purest "idle RPG" of the top three and combines best with an existing skilling/Melvor-style codebase. The same template applies to any concept.

### Screens (mobile-first)

| Screen | Contents | Notes |
|---|---|---|
| HUD (always) | Gold, Gems, Renown, offline-earnings badge, World Boss timer | Top bar, max 4 numbers visible |
| Heroes | Roster grid, hero detail (gear, level, skills) | Bottom tab 1 |
| Quests | Zone list, assign heroes, progress bars | Bottom tab 2 |
| Town | Build/upgrade buildings, adjacency preview | Opens the 3D plot camera; tab 3 |
| Summon / Tavern | Recruit heroes (odds button visible) | Tab 4 |
| Guild | Real player guild, monument, chat shortcuts | Tab 5 |
| Welcome Back | "You were away 6 h 12 m — collected 1.2M gold" + 2× ad button | Shown on join |

Keep the **bottom tab bar to 5 items** and every button ≥ 44 px.

### Economy formulas (starting points — tune with telemetry)

- **Upgrade cost:** `cost(n) = base × 1.12^n` (use 1.07 for cheap/frequent upgrades, 1.15 for rare ones).
- **Income per level:** linear, with **milestone multipliers** at level 25 / 50 / 100 / 200 (×2 each) — AdVenture-Capitalist style "one more milestone" pull.
- **Renown on prestige:** `renown = floor(10 × sqrt(lifetimeGold / 1e6))` — square root keeps later prestiges worthwhile but not explosive.
- **Offline earnings:** 100% rate for the first 2 h, 50% up to 8 h cap. VIP pass: 12 h cap. Rewarded ad: ×2 the haul once per return.
- **First session pacing targets:** first gold < 5 s, first hero upgrade < 30 s, 2nd hero < 2 min, first building < 5 min, first World Boss seen < 10 min, first prestige available ≈ day 2.

### Monetization plan

| Item | Type | Price (R$) | Why it's fair |
|---|---|---|---|
| VIP (12 h offline, +1 hero slot, chat tag) | Pass | 199 | Convenience |
| 2× Gold | Pass | 399 | Speed, PvE only |
| Auto-Sell Junk Loot | Pass | 99 | Convenience |
| Architect (2 build queues) | Pass | 499 | Convenience |
| Starter Pack (1 epic hero + gems) | Product, once | 49 | Great-value first purchase |
| Gem packs | Product | 25 – 1,500 | Consumable |
| Building/hero skins | Product | 50 – 400 | Cosmetic |
| Rewarded ad | Ad | — | 2× offline haul, free recruit per day |

### Technical architecture (Roblox)

- **Server-authoritative:** all currency math on the server; RemoteEvents carry intent only (`BuyUpgrade(buildingId)`), validated and rate-limited.
- **Data:** session-locked profile (ProfileStore/ProfileService pattern), schema version + migrations from day 1, `lastSeen` timestamp for offline calc.
- **Content as data:** heroes, buildings, zones, loot tables in ModuleScript config tables → new content = new rows, not new code.
- **Big numbers:** decide early whether you'll pass ~1e300; if yes, use a mantissa/exponent BigNum type in shared code.
- **Paid random items:** check `PolicyService` per player; show odds before purchase.
- **Analytics:** log funnel events (tutorial steps, first upgrade, first prestige, first purchase) to find where players bounce.

### MVP roadmap (small team, ~10–12 weeks)

| Weeks | Milestone |
|---|---|
| 1–2 | Data layer (profiles, offline calc), hero auto-battle sim, 1 zone |
| 3–4 | Mobile HUD + Heroes + Quests screens; 8 heroes, 3 zones |
| 5–6 | Town: 6 buildings, adjacency bonuses, 3D plot in shared server |
| 7 | World Boss (server co-op), leaderboards |
| 8 | Prestige 1 (Renown), welcome-back screen, rewarded ads |
| 9 | Passes & products, receipt processing, odds display |
| 10 | Tutorial polish, first-60-seconds pass, analytics funnel |
| 11–12 | Closed test with ~50 players, tune D1 / session length, launch with 4 weeks of pre-built event content |

### Launch KPIs to aim for

- First-play bounce: < 30% leave in the first minute
- D1 ≥ 20%, D7 ≥ 8% (the "strong position" bar)
- Average session ≥ 12 min; play days per user in D2–D7 ≥ 2.5
- Payer conversion 1.5–3%

### Post-launch LiveOps calendar (repeating monthly)

- **Week 1:** new zone + 2 heroes
- **Week 2:** weekend event (double drops, limited building skin)
- **Week 3:** guild competition (Guild Monument race)
- **Week 4:** new World Boss + balance patch, codes on socials
