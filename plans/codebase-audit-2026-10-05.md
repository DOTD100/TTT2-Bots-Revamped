# Codebase audit — 2026-10-05

A full-tree review of TTT-Bots-2 (128 Lua files) for correctness and optimisation. This pass used the semantic
index, regex sweeps for the known bug classes, and targeted reads of the hot paths. `glua-check` and GluaLint
were **not** re-run here (Architect mode has no shell); their re-run is the first hand-off step, with the recorded
baselines to diff against: **128 files / 0 issues / 2 notes** and **174 lint warning lines**.

## Bottom line

No new correctness bugs were found. The two real problems are both optimisation: two position-visibility loops that
trace every player on the server from per-tick hot paths, and two entity scans that duplicate a cache that already
exists elsewhere in the tree.

---

## Findings, in priority order

### 1. `Wander.StareAtNearbyPlayers` traces every player every tick — highest value

- [`Wander.StareAtNearbyPlayers()`](lua/tttbots2/behaviors/wander.lua:105) calls
  [`Lib.GetAllVisible()`](lua/tttbots2/lib/sh_botlib.lua:928), which loops `player.GetAll()` and fires
  `ply:VisibleVec(pos)` — a trace — per player.
- It is reached from [`Wander.OnRunning()`](lua/tttbots2/behaviors/wander.lua:73) on every tick a bot is close to
  its wander goal. Wandering is the default idle state for most bots, so with a full server this is roughly
  `players × bots` traces every 200 ms — the single most frequent remaining trace loop in the addon.
- The purpose is only to make a standing bot look at the nearest player, which does not need per-tick freshness.

**Fix:** throttle it (e.g. re-check every 0.5–1 s, or every `N` ticks), storing the look target in between. The
behaviour is cosmetic, so staleness is invisible. Put the throttle on the behaviour, not the helper.

### 2. `PlantBomb.FindPlantSpot` is O(spots × players × trace)

- [`PlantBomb.FindPlantSpot()`](lua/tttbots2/behaviors/plantbomb.lua:109) loops over every bomb spot and, per
  surviving spot, calls [`Lib.GetAllVisible(spot, true, bot)`](lua/tttbots2/behaviors/plantbomb.lua:141) (a trace
  per player), `bot:VisibleVec(spot)` (another trace), and then a `player.GetAll()` distance loop at line 161.
- This runs from `Validate`, i.e. every tick for a traitor carrying C4, and again from `OnRunning`.

**Fix (two parts):**
- Cache the chosen spot and re-evaluate on an interval (a planting bot does not need to re-weight 30 spots five
  times a second).
- Replace the per-spot witness trace with a cheaper estimate, or reuse `SeenThisTick` for the bot's own
  visibility and a throttled witness count.

### 3. The ankh scan is triplicated; only one copy is cached

- [`MoveAnkh.findOwnAnkh()`](lua/tttbots2/behaviors/moveankh.lua:63) and
  [`StealAnkh.findConvertibleAnkh()`](lua/tttbots2/behaviors/stealankh.lua:103) each run
  `ents.FindByClass("ttt_ankh")` from their `Validate` (per tick), while
  [`breakankh.lua`](lua/tttbots2/behaviors/breakankh.lua:54) already keeps a per-tick cache of the same query.
- Impact is bounded by role rarity (one Pharaoh, one Graverobber), but it is exactly the shape section 40 fixed
  for the soda cans: one shared cached list instead of per-bot-per-tick scans.

**Fix:** lift the cached query into `TTTBots.Lib` (e.g. `GetAnkhs()`) and have all three behaviours read it.

### 4. `PlantBomb` scans C4s while `Match` already keeps a list

- [`PlantBomb.FindPlantSpot()`](lua/tttbots2/behaviors/plantbomb.lua:112) and
  [`PlantBomb.ArmNearbyBomb()`](lua/tttbots2/behaviors/plantbomb.lua:292) call `ents.FindByClass("ttt_c4")` directly.
- [`Match.UpdateC4List`](lua/tttbots2/lib/sh_match.lua:447) already scans once a second but only retains *armed*
  C4s in `Match.AllArmedC4s`. `FindPlantSpot` needs **all** C4s (armed or not) for its separation rule.

**Fix:** extend the 1 s cache to hold the full C4 list (armed and unarmed) and have `PlantBomb` read it.

### 5. Minor: `GetAllWitnesses` iterates `player.GetAll()`/`TTTBots.Bots`

- [`Lib.GetAllWitnesses()`](lua/tttbots2/lib/sh_botlib.lua:525) could use `Match.AlivePlayers` when `botsOnly`
  instead of re-filtering `TTTBots.Bots`. Its callers are on 1 s timers, so this is low priority, but it is the
  same class of needless re-scan.

---

## What was checked and is clean

- **`Entity:Visible` misuse** — zero live `:Visible(` calls; only four comment blocks remain (the section 39 end
  state holds).
- **NULL-entity truthiness guards** — the five `if x and x:` matches are a Vector (`sv_inventory.lua:292`,
  `decrowd.lua:38`), a `CNavArea` (`sh_botlib.lua:1406`), a ConVar (`defectordeliver.lua:27`) and a boolean
  (`drinksoda.lua:68`), not entities. Section 8's sweep still holds.
- **NULL attack targets** — `SetAttackTarget` still normalises invalid input to `nil`, and the `~= NULL` guards in
  the morality component are intact.
- **External addon cvars** — the 21 `GetConVar("ttt…")` reads are other addons' cvars, all nil-guarded or behind
  the lib's own wrappers; they are the known GluaLint style warnings, not defects.
- **Section 40 work** — the health-station and soda-can caches remain correct and the clearance radius test in
  `placefakesoda.lua` still deliberately does not use the class cache.

---

## Hand-off plan (Code mode)

1. Re-run `node tools/glua-check/check.js` and GluaLint over the whole tree; confirm 128/0/2 and 174 lines.
2. Implement finding 1 (throttle the wander stare).
3. Implement finding 2 (throttle/cache plant-spot evaluation).
4. Implement findings 3 and 4 (shared ankh cache; full C4 list shared with `Match`).
5. Optionally finding 5 (use `Match.AlivePlayers` in `GetAllWitnesses`).
6. Re-verify (glua-check + per-file GluaLint) and document as a new `WORKING_NOTES` section with a changelog entry.

## Corrections made during implementation

- **Finding 2 was retracted.** `PlantBomb.FindPlantSpot` is called once per attempt from `OnStart`, not per tick
  from `Validate`, so there was no per-tick spot evaluation to cache. Nothing changed in that path.
- **Finding 4 was narrowed.** Only `FindPlantSpot` reads the shared `Match.C4s`; `ArmNearbyBomb` keeps a fresh scan
  because it must find the bomb the bot placed on the current tick, which the one-second cache may not contain yet.
