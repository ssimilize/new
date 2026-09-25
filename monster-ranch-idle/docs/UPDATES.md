# Updates

Content and system changes shipped after launch, newest first. Each update lists what
players get and where it lives in the code.

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
