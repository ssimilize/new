# Part 1 — Research: What Works on Roblox (September 2026)

> Numbers below come from third-party trackers, Roblox announcements and the Roblox DevForum.
> Trackers disagree with each other (sometimes by 2×), so treat every figure as a **direction**, not a fact.
> Full source list is at the bottom of this file.

---

## 1. Who is actually playing

| Fact | Why it matters for design |
|---|---|
| **~72% of sessions are on mobile**, ~25% desktop, ~3% console | Design the UI for a phone held in portrait/landscape *first*. Big buttons, thumb-reach zones, short text. A GUI game that looks great on a monitor and cramped on a phone will fail. |
| Age split of age-checked users: **~35% under 13, ~38% 13–17, ~27% 18+** | The audience is no longer "just kids". 18+ is the fastest-growing group (reported +50% YoY) and spends ~40% more per user. Deeper systems (idle RPGs, strategy) can now find an audience. |
| Top desired features in a 2026 survey of 1,015 users: **play with friends (54%)**, world/characters (51%), rewards/progression (46%), difficulty (35%), pacing (34%) | Social is #1. A *pure* GUI game with no way to see or play with friends leaves the biggest lever on the table. |

## 2. What is winning right now

| Game | Genre | Why it works (per analysts) |
|---|---|---|
| **Grow a Garden** | Idle / cozy farming | Plant → wait → harvest → sell. Crops grow **while offline**. ~5 minutes a day is enough to feel progress. Peaked at 22.3M concurrent (Aug 2025). |
| **Steal a Brainrot** | Tycoon + steal-and-defend PvP | Idle income base + social risk (others can steal from you) + meme culture. First game over 25M concurrent (Oct 2025). |
| **+1 Speed Keyboard Escape** | Obby × incremental | A number that always goes up (+1 speed) makes you able to reach further. Dead-simple idea, constant feedback, social competition. Launched Jan 2026, ~6.2M peak concurrent by Aug 2026; won *Best Party Game* at the 2026 Innovation Awards. |
| **Pet Simulator 99** | Pet sim / idle economy | Tightly tuned economy, disciplined weekly LiveOps calendar. |
| **Adopt Me!** | Pet sim / trading | Player-driven economy with real scarcity → trading is the endgame. |
| **99 Nights in the Forest** | Co-op survival horror | Slow-burn dread, system mastery over reflexes, party-based progression. |
| **Blox Fruits, Sailor Piece, King Legacy, GPO** | Anime action RPG | Deep progression, forgiving early hours, monthly content updates. |
| **Anime Vanguards / Anime Last Stand** | Tower defense × gacha RPG | Genre blend: collect units, upgrade them, place them. Constant new units. |
| **RIVALS** | Competitive FPS | Mobile-first controls, forgiving hitboxes. |
| **Dress to Impress** | Fashion / social voting | Served an under-served audience with creative expression. |

**Trend lines analysts agree on:**

1. **Genre blending wins.** Obby + incremental, tycoon + PvP, tower defense + RPG, horror + RPG. Pure single-genre games are rarer at the top.
2. **Idle is proven at the very top of the platform** (Grow a Garden, Steal a Brainrot are both "idle" at their core).
3. **Fastest-growing categories (2026):** steal-and-defend tycoons, idle-grow sims, co-op horror, anime fighters, fashion/social.
4. **Update cadence is survival.** RPGs that ship meaningful content monthly hold players; those that slow down collapse (Shindo Life fell from top-50 to ~1–2K concurrent).
5. **Simple to understand in 5 seconds** — every breakout above can be explained in one sentence.

## 3. Retention: what "good" looks like

Two very different benchmark sets exist — know which one you are comparing against:

| Source | D1 | D7 | D30 |
|---|---|---|---|
| GameAnalytics 2026 — **median** of all Roblox games | 10.3% | 1.6% | 0.5% |
| "Healthy target" (GameAnalytics) | ~12% | ~2.9% | — |
| "Strong position" (industry rule of thumb) | 20%+ | 8%+ | — |

Genre benchmarks from BLOXG (850+ *promoted* games — so skewed upward):

| Genre | D1 | D7 | D30 |
|---|---|---|---|
| **RPG** | **35%** | **16%** | **7.8%** |
| Simulator | 32% | 14% | 6.2% |
| Tycoon | 30% | 12% | 5.1% |
| Adventure | 27% | 10% | 3.8% |
| FPS / Shooter | 26% | 11% | 4.5% |
| Social / Hangout | 24% | 13% | 6.0% |
| Horror | 22% | 8% | 2.8% |
| Obby | 18% | 6% | 1.9% |

**Takeaway:** RPGs and simulators retain best ("deep systems and guilds"). Idle RPG sits at the intersection of the two best-retaining genres — that is the strongest argument for the idle RPG focus.

### What the discovery algorithm reacts to

Roblox says it does *not* use benchmarks directly, but impressions fall when these fall:

- **Play-through rate** (people who see the thumbnail and click play)
- **First-play bounce rate** (people who leave almost immediately) ← the first 60 seconds matter enormously
- **Play days per user** and **playtime per user** (D1, D2–7, D8–28 windows)
- Retention and monetization **together**
- New signal: **7-day intentional co-play days** — how often players join *with friends on purpose*

→ Idle games are naturally good at "play days per user" (come back daily to collect). They are weak on co-play unless you design for it.

## 4. Monetization that works (and what backfires)

**Revenue stack used by top games:**

| Layer | What | Notes |
|---|---|---|
| Game passes | Permanent perks | Tiered set of **3–5 passes** (e.g. 49 / 149 / 499 / 999 R$) reportedly lifts conversion 40–60% vs. a single pass. |
| Developer products | Consumables (boosts, currency packs, rolls) | Must be idempotent on the server (ProcessReceipt). |
| Rewarded video ads | Opt-in ad → reward | Open to all ads-eligible creators since Feb 2026. ~25–40% opt-in when offered, typically 8–15% of revenue, eCPM ~$6–12. Perfect fit for idle games ("watch ad → 2× offline earnings"). |
| Creator Rewards / Premium payouts | Passive, engagement-based | Rewards time spent — idle games benefit. |

- Roblox keeps 30% → you net 70% of Robux. DevEx ≈ **$0.0038 per Robux** (2026).
- **If you have under ~200–300 concurrent, don't optimize monetization yet** — optimize retention and visibility.

**What backfires on Roblox specifically:**

- **Pay-to-skip appointment timers.** Roblox's own creator docs warn these are unpopular with Roblox players, who dislike their fun being cut off. (Grow a Garden has timers, but there is always *something else* to do while waiting — that is the difference.)
- **Hard pay-to-win in competitive modes.** Players tolerate "pay for speed/convenience" far better than "pay for power over other players".
- **Opaque gacha.** Roblox policy requires odds to be shown for paid random items, and some regions restrict them entirely (check `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted`). There is also growing regulatory/press scrutiny of manipulative design aimed at kids (e.g. a May 2026 advocacy-group complaint). Keep randomness transparent and mostly earnable.

## 5. GUI-based and idle games on Roblox — specific findings

- **GUI-only idle games are under-served.** DevForum developers note there are few good GUI idle games on Roblox — an opening, but also a warning: the format has historically struggled to break out.
- **Players expect depth, not a button simulator.** Community advice points to *Antimatter Dimensions*, *The Prestige Tree*, *Cookie Clicker* as the bar: layered prestige, automation unlocks, meaningful choices.
- **Existing Roblox examples:** *Everything Incremental*, *GUI Incremental Game* (rebirth/prestige/runes), *Grass Cutting Incremental*, *Cultivation Incremental*, *Road to Infinity*, *Aim Incremental*. They have loyal niche audiences but none reached Grow-a-Garden scale — the breakouts all had **a visible 3D world with other players in it**.
- **Mobile idle-RPG lessons** (AFK Journey, Evil Hunter Tycoon, Shiba Story Go):
  - Early pacing generous, mid-game walls are where F2P players quit → soften them.
  - **A planning layer** (town management in Evil Hunter Tycoon) is what most idle RPGs lack and what keeps players at "week four, not hour one".
  - **Build variety** (roguelite floors with different team setups) beats pure stat growth.
- **Technical realities:**
  - Roblox kicks idle players after ~20 minutes by default. Don't design around "leave the game open all night" — build **true offline progress** calculated on rejoin (server stores `lastSeen = os.time()`, computes elapsed time, clamps to a cap).
  - Luau numbers are doubles (max ≈ 1.8e308). Incrementals that go further need a big-number library; decide this on day 1.
  - Server-authoritative economy: the client should only send *intent* ("buy upgrade #3"), never amounts.

## 6. The distilled playbook

1. **Explain it in one sentence.** If the thumbnail + title don't explain it, the play-through rate dies.
2. **First 60 seconds:** number goes up in < 5 s, first upgrade in < 30 s, first "wow" unlock in < 2 min. Kill first-play bounce.
3. **GUI-first, not GUI-only.** Keep the depth in panels, but put players in a small shared 3D hub where others can see your hero/pets/base. Social is the #1 desire and a discovery signal.
4. **Offline progress is mandatory** for idle. Cap it (e.g. 8 h) so logging in daily matters; let a pass extend it.
5. **Always something to do.** Timers are fine only if there's a parallel activity while you wait.
6. **Layered prestige** (2–3 layers) is the long-term retention engine.
7. **Co-op > PvP for idle.** Server bosses, guild goals, friend boosts. Steal-and-defend is the exception that proves you *can* add PvP risk to idle — but it's high-variance.
8. **Monetize convenience, cosmetics and speed** — not exclusive power in PvP. Tier your passes. Use rewarded ads for "2× offline earnings".
9. **Ship on a weekly/monthly cadence** — events, new zones, codes. Plan a 3-month content runway before launch.
10. **Mobile-first UI.** Test on a phone every day of development.

---

## Sources

- [List of Roblox games — Wikipedia](https://en.wikipedia.org/wiki/List_of_Roblox_games)
- [Grow a Garden — Wikipedia](https://en.wikipedia.org/wiki/Grow_a_Garden)
- [Steal a Brainrot — Wikipedia](https://en.wikipedia.org/wiki/Steal_a_Brainrot)
- [Top Roblox Games May 2026 — StudioKrew](https://studiokrew.com/blog/top-roblox-games-may-2026/)
- [Top Roblox Games 2026 — StudioKrew](https://studiokrew.com/blog/top-games-on-roblox-and-analysis-2026/)
- [Roblox Charts 2026 — EJAW](https://ejaw.net/roblox-charts/)
- [Best Roblox RPGs in 2026 by Retention — RoWatcher](https://rowatcher.com/news/best-roblox-rpgs-in-2026-ranking-the-top-10-by-gameplay-and-player-retention)
- [Roblox Retention Benchmarks by Genre (2026) — BLOXG](https://bloxg.com/statistics/roblox-retention-benchmarks)
- [How the Roblox Algorithm Works in 2026 — BLOXG](https://bloxg.com/guides/roblox-algorithm)
- [2026 Roblox Benchmark Report — GameAnalytics](https://www.gameanalytics.com/reports/2026-roblox-report)
- [Discovery — Roblox Creator Hub](https://create.roblox.com/docs/discovery)
- [Roblox Discovery Algorithm 2026 — GM Market](https://gmmarket.me/community/post/how-the-roblox-discovery-algorithm-actually-works-in-2026-myths-debunked)
- [Monetization — Roblox Creator Hub](https://create.roblox.com/docs/production/monetization)
- [Retention vs Monetization — Roblox DevForum](https://devforum.roblox.com/t/retention-vs-monetization/3324118)
- [Roblox Monetization Trends 2026 — ROLearn](https://rolearn.dev/trend-reports/roblox-monetization-trends-devex-creator-rewards/)
- [Roblox Game Monetization 2026 — Generalist Programmer](https://generalistprogrammer.com/tutorials/roblox-game-monetization-complete-revenue-strategy-guide)
- [Roblox Game Pass Pricing (2026) — Generalist Programmer](https://generalistprogrammer.com/tutorials/roblox-game-pass-pricing-guide)
- [Rewarded Video ads available to all ads-eligible creators — Roblox DevForum](https://devforum.roblox.com/t/rewarded-video-ads-are-now-available-to-all-ads-eligible-creators/4063278)
- [Roblox Rewarded Video Ads in 2026 — GM Market](https://gmmarket.me/community/post/roblox-rewarded-video-ads-in-2026-who-can-enable-them-how-to-integrate-and-what)
- [Roblox Statistics 2026 — Wagner Studios](https://www.wagnerworlds.com/en/blog/roblox-statistics-2026)
- [Who actually plays Roblox in 2026 — ZehnStudio99](https://zehn-studio26.com/news/roblox-audience-2026-age-breakdown/)
- [What 1,015 Responses Reveal About Roblox Users — newgame Inc.](https://note.com/newgame_inc/n/n3dc9352cc705?hl=en)
- [Thoughts on GUI-based idle game mechanics — Roblox DevForum](https://devforum.roblox.com/t/thoughts-on-gui-based-idle-game-mechanics/1482122)
- [How to set up a UI-Only Game — Roblox DevForum](https://devforum.roblox.com/t/how-to-set-up-a-ui-only-game/1718676)
- [Remove the 20 minutes idle kick — Roblox DevForum](https://devforum.roblox.com/t/remove-the-20-minutes-idle-kick/1175805)
- [+1 Speed Keyboard Escape — why it works — The Bloxline](https://www.thebloxline.com/articles/1-speed-keyboard-escape-has-become-one-of-roblox-s-biggest-games-here-s-why-it-works)
- [+1 Speed Keyboard Escape — Roblox Wiki](https://roblox.fandom.com/wiki/SecretVerse_Studio/%2B1_Speed_Keyboard_Escape)
- [The Idle RPG Games Worth Starting in 2026 — Mobile Game Report](https://www.mobilegamereport.com/articles/best-idle-rpg-mobile-2026)
- [Grow a Garden AFK Farming Guide — GAG Data](https://www.gagdata.com/blog/afk-farming)
- [Best Roblox Tower Defense Games — BloxQuiz](https://www.bloxquiz.gg/stats/category/tower-defense)
- [Roblox Game Genres and Popularity 2026 — ExitLag](https://www.exitlag.com/blog/roblox-game-genres-and-popularity/)
- [Advocacy groups file complaint against Roblox — Fortune](https://fortune.com/2026/05/20/exclusive-advocacy-groups-file-complaint-roblox-manipulative-design/)
