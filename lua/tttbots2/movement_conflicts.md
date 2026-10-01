# Movement Conflict Log

Created: 2026-09-13
Last re-verified: 2026-09-17, line by line against the current source (all line numbers below are from
that pass). That pass fixed #4, #6, #8 (the gunplay half), #9, #12 and #14, and settled #13.
Follow-up 2026-09-18: #16, the strafe twitch that came back into fights through the unstuck code.
Follow-up 2026-09-22: the melee reach in `Attack.Engage` - a distance, not a competing writer, so it lives in
"Already fixed elsewhere" below rather than as a numbered conflict.

A running log of places where more than one system can decide how a bot moves in the same tick.
Kept in the repo so we can pick this back up at any time without re-deriving it.

**Status legend**

| Tag | Meaning |
| --- | --- |
| `FIXED` | Resolved, verified by parser. Do not "fix" again without reading the notes. |
| `VERIFIED` | Investigated and found **not** to be a conflict. The note says why, so it stays closed. |
| `OPEN` | Known conflict, not yet addressed. |
| `MONITOR` | Smells like a conflict but may be intentional; needs a live repro before changing. |

Scoreboard: #1, #2, #3, #4, #6, #7 (superseded), #8 (gunplay half), #9, #12, #14, #16 `FIXED`; #13
`VERIFIED`; #5, #8 (movement half), #10, #11, #15 `OPEN`/`MONITOR`.

---

## The moving parts

Every movement decision ultimately funnels through `BotLocomotor:StartCommand` in
`components/sv_locomotor.lua` (1559). Anything that writes one of these fields is a competing author:

| Writer | Field written | Lifetime |
| --- | --- | --- |
| `loco:SetGoal(pos)` (336) / `ClearGoal()` (341) | `goalPos` → path manager → `nextPos` | until changed/cleared |
| `loco:SetPriorityGoal(vec, range)` (141) | `movePriorityVec` | until changed/cleared |
| `loco:SetHalt(bool)` (303) | `dontmove` | **no timeout, no owner** (reset per life, see #4) |
| `loco:SetForceForward(bool)` (324) | `forceForward` | 1 s timeout |
| `loco:SetForceBackward(bool)` (389) | `forceBackward` | 1 s timeout |
| `loco:Strafe(dir)` (315) | `strafe` | 1 s timeout |
| `loco:SetSprint(bool)` (297) | `sprint` → IN_SPEED/IN_FORWARD | until cleared |
| `loco:SetRepelForce(normal, dur)` (662) | `repelled`, `repelDir`, `repelStopTime` | timed, gated by `pauseRepel` |
| `loco:PauseRepel()` (653) / `ResumeRepel()` (658) | `pauseRepel` | **no owner, not refcounted** |
| `loco:DisableAvoid()` (440) / `EnableAvoid()` (435) | `dontAvoid` | **no owner** (reset per life) |
| `loco:SetHoldAttack(bool)` (1475) | `holdAttack` | **no owner** (reset per life) |
| `loco:PauseAttackCompat()` (1466) / `ResumeAttackCompat()` (1481) | `attackCompat` | **no owner**; nothing calls the pause (#15) |
| `loco:InterpolateMovement(factor, goal)` (1386) | `movementVec` | lerped each call |
| `loco:AvoidPlayers()` (612) | `repelled` (via `SetRepelForce`, 640) | per tick |
| `loco:AvoidDoor()` (807) / `TryUnstick()` (733) | `use`/`dontmove` (timed), `strafe`, view angles | per tick |
| `loco:SetClimbDir("up"/"down")` | `cmd:SetUpMove` | per tick |
| Ladder branch in `StartCommand` | buttons | early-returns |

### Precedence actually implemented in `StartCommand`

1. `if self.dontmove then return end` (1562) — absolute veto; everything below is skipped, including
   every button, which is why a latched `dontmove` silences a bot's gun as well as its legs
2. Jump / crouch buttons
3. Path `nextPos` movement, **or** priority goal movement
4. Repel shove (1600, only when no forced movement is active — see #3)
5. `movementVec` → `cmd:SetViewAngles` (1637 — the **movement** frame, not the aim; see #13)
6. `UpdateEyeAnglesFinal()` (267; called at 1642)
7. Strafe → side move
8. Ladder branch early-return (1649) — skips 9–12, but now applies the attack buttons itself (see #8)
9. `SetUpMove(climbDir)`
10. `forwardDir` = backpedal `-400`, else `+400` (move vec or force forward), else `0` (1698)
11. Door use
12. `ApplyAttackButtons()` (1717) — attack/reload buttons, shared with the ladder branch
13. `moveNormal` = the command's view angles' forward

---

## Conflicts

### 1. `FIXED` — `forceBackward` had no lifetime

**Where:** `components/sv_locomotor.lua` — `SetForceBackward` (389), `VerifyBackwardTimeout` (396),
`GetForceBackward` (403), `StopMoving` (411); `behaviors/attacktarget.lua` — `Attack.OnEnd`.

**Symptom:** Once a bot was told to backpedal it kept walking backwards indefinitely, long after the
fight ended, because `forceForward` had a 1 s timeout but `forceBackward` was a bare field that
nothing ever cleared.

**Fix:** `SetForceBackward` stamps `forceBackwardTimeout = self.tick + TTTBots.Tickrate`;
`VerifyBackwardTimeout` expires it and `GetForceBackward` consults it. `StopMoving` and
`Attack.OnEnd` both clear `forceForward`, `forceBackward` and `repelled`. Re-verified 2026-09-17.

---

### 2. `FIXED` — `movementVec` silently cancelled the backpedal

**Where:** `components/sv_locomotor.lua` — `StartCommand`, forward move block (1698).

**Symptom:** Both `+400` (move vector / force forward) and `-400` (backpedal) were computed from the
same expression, and `hasMoveVec` was tested **first**. Any active path or priority vector therefore
won, so a retreating bot stood still mid-fight whenever it also had a path.

**Fix:** The `forwardDir` expression tests `forceBackward` first, so an explicit backpedal wins.
Re-verified 2026-09-17: `(forceBackward and -400) or ((hasMoveVec or forceForward) and 400) or 0`.

---

### 3. `FIXED` — repel fought forced movement and pathing

**Where:** `components/sv_locomotor.lua` — `StartCommand`, repel block (1600);

**Symptom:** `local forceForward = self:GetForceForward() or self.repelled` made being shoved also
force full-forward input, and the repel `InterpolateMovement` ran unconditionally at 1.5× rate,
overwriting priority/path vectors. The two inputs reversed each other and the bot jittered.

**Fix:** Repel no longer forces forward; the shove yields while an explicit forced movement is active
and does not touch the movement vector in that case (1607–1615). Re-verified 2026-09-17.

---

### 4. `FIXED` — `dontmove` was an unowned latch that was never cleared per life

**Where:** `components/sv_locomotor.lua` — `SetHalt`/`IsHalted` (303/344), `UpdateMovement` (867),
`StartCommand` (1562), new `ResetLifeState` (1843) and its `PlayerSpawn`/`TTTBeginRound` hooks
(1859/1866); setters: `behaviors/defuse.lua` (292, 304, 312, 362), `behaviors/plantbomb.lua`
(176, 180, 191, 198, 258), `behaviors/defib.lua` (159).

**Symptom:** `dontmove` is only ever reset by the behaviour that set it. Nothing reset it at spawn, at
round start, or on revive — `StopMoving()` explicitly does not touch it. A bot that died while halted
on a C4, or whose behaviour was torn down without `OnEnd`, came back **permanently frozen**:
`StartCommand` clears the buttons and then early-returns, so the bot could neither move **nor shoot**.

**Fix:** `BotLocomotor:ResetLifeState()` clears the unowned latches (`dontmove`, `pauseRepel`,
`dontAvoid`, `holdAttack`) plus the per-life movement leftovers (repel, attack/attack2, sprint, jump,
crouch). It is called from a `PlayerSpawn` hook (respawns) and a `TTTBeginRound` hook (the round's own
spawn). Bots are not recreated between rounds, which is why this needs a hook rather than a
constructor.

---

### 5. `OPEN` — `pauseRepel` is not refcounted

**Where:** `PauseRepel` (653) / `ResumeRepel` (658); callers `behaviors/defib.lua` (261, 160),
`behaviors/usehealthstation.lua` (129, 154), `behaviors/mingecrowbar.lua` (99, 129).
-- Line 137 moved by 25 lines when the station scan cache was added above it; the calls themselves are unchanged.

**Symptom:** Three behaviours pause repel and each resumes it on end. Whoever calls `ResumeRepel()`
first un-pauses for everyone, so a bot can be shoved out of a defib or health-station interaction by an
unrelated behaviour finishing.

**Remaining work:** the "left paused forever" half is covered by the per-life reset in #4; the
early-resume half is not. **A naive counter will not work**: `mingecrowbar.lua` calls `PauseRepel()`
from its `OnRunning`, i.e. once per tick while it is active, so the count would grow without bound and
repel would never come back. The fix has to be an owned token table (`pauseRepelOwners[behaviour]`)
with the three callers passing a fixed owner string.

---

### 6. `FIXED` (as far as it can bite today) — `dontAvoid` is unowned and only Bodyguard manages it

**Where:** `components/sv_locomotor.lua` — `EnableAvoid`/`DisableAvoid` (435/440);
`behaviors/bodyguard.lua` (49 disables while far, 69 re-enables in `OnEnd`).

**Symptom:** Same latch class as #4/#5, but with a single owner. If `Bodyguard.OnEnd` never ran (bot
died, round ended, tree torn down) avoidance stayed **off** for that bot's next life, so it stopped
avoiding props and players.

**Fix:** covered by the per-life reset in #4. It is still unowned, so a second behaviour that wants to
disable avoidance would need the owner treatment described in #5.

---

### 7. `FIXED` (superseded) — avoidance no longer overwrites combat strafing

**Where:** `components/sv_locomotor.lua` — `AvoidPlayers` (612, `SetRepelForce` at 640) and combat
strafing from `behaviors/attacktarget.lua` — `Attack.StrafeIfNecessary`.

**Original symptom:** `Attack` picked a combat strafe every tick, then `Think` ran `AvoidPlayers`,
which wrote its own strafe in the same tick. Because `Strafe` applies a full 1 s timeout,
last-writer-wins meant the loser's decision persisted for up to a second, so combat strafing was
non-deterministic: sometimes the dodge direction, sometimes the crowd-avoid direction.

**What happened instead:** `AvoidPlayers` no longer writes `strafe` at all — it averages the nearby
players into a centre point and calls `SetRepelForce`, and the repel shove yields to forced movement
(fix #3). There is one writer of `strafe` per tick again.

**Still `MONITOR`:** when no forced movement is active (a planted, close-range fight sets
`SetForceForward(false)`, which self-clears), the clump repel can still steer the movement vector
mid-fight. It only moves the bot — it cannot rotate the aim, because the look goal is untouched — so
this is a cosmetic shove rather than a gunplay bug. Change it only with a live repro.

---

### 8. `FIXED` (gunplay half) / `OPEN` (movement half) — ladder movement early-returns

**Where:** `components/sv_locomotor.lua` — `StartCommand`, `if self:IsOnLadder() then ... return end`
(1649); `BotLocomotor:ApplyAttackButtons` (1529), called from the ladder branch (1658) and the main
path (1717).

**Symptom:** The ladder branch returned before the strafe/forward/force calculation, so
`forceForward`, `forceBackward`, repel shoves and priority vectors were all discarded while on a
ladder — **and** it replaced every button with `IN_FORWARD` (`+ IN_USE` to dismount), which threw away
the attack and reload buttons added further down. A bot that was shot at while standing on a ladder
therefore could not fire back at all. Its aim was never the problem (`TickViewAngles` runs before this
branch, so it faced its target) — only the trigger was.

**Fix:** the attack/reload block was extracted into `ApplyAttackButtons(cmd, timestamp)`, which the
ladder branch now calls too. The bot shoots while climbing.

**Still `OPEN`:** the ladder branch still ignores the movement forces and still drops the duck/jump
buttons set above it. That part is plausibly intentional (climbing needs `IN_FORWARD` held) and
deciding it properly needs a live test on a map with ladders, so it was left alone. If it is fixed, it
should also cancel forces and `StopAttack` at the ladder boundary so nothing accumulates for the
dismount.

---

### 9. `FIXED` — `Follow` set its goal to its own position

**Where:** `behaviors/follow.lua` — `OnRunning` (152).

**Symptom:** `local finalTarget = (distToPoint < 250 and bot:GetPos()) or bot.botFollowPoint` set the
goal to the bot's **current** position once it was close. That goal can never be "reached" in the
`GetXYDist(...) < 32` sense as the bot moves, so the locomotion set/clear path flapped between
"arrived" and "has a goal" and the bot stuttered in place.

**Fix:** within 250 units the behaviour calls `loco:StopMoving()` — the arrival signal the other
behaviours use — instead of setting a goal that tracks the bot. That also drops the stale movement
vector, so the bot no longer carries its last walk direction past the person it is following.

---

### 10. `OPEN` — `SetPriorityGoal` silently no-ops inside its range

**Where:** `components/sv_locomotor.lua` — `SetPriorityGoal` (141).

**Symptom:** When the target is within `range` (default 32), the function returns `true` **without**
setting `movePriorityVec` and without clearing it either. Callers such as
`behaviors/clearbreakables.lua` (62) cannot distinguish "arrived" from "assigned", so they keep
re-issuing it, and `StartCommand` falls through to the `HasPath` branch — meaning the path keeps
driving while the behaviour believes it is doing priority movement.

**Suggested fix:** return a distinct value (or clear the vector on arrival) so callers can tell
arrival from assignment. Not done yet: every caller's `if res then` would have to be re-read, and none
of them is gunplay.

---

### 11. `OPEN` — goal precedence is implicit in tree order

**Where:** every behaviour that writes `SetGoal`: `follow.lua`, `followmaster.lua`, `getweapons.lua`,
`wander.lua`, `bodyguard.lua`, `investigatenoise.lua`, `investigatecorpse.lua`, `stalk.lua`,
`createdeputy.lua`, `createsidekick.lua`, `defib.lua`, `plantbomb.lua`, `attacktarget.lua`.

**Symptom:** Which goal wins depends on the order of nodes in the behaviour tree plus whether the node
owns `bot.lastBehavior` (`lib/sv_tree.lua`). There is no explicit priority, so editing tree order
silently changes movement precedence, and a `Validate` that passes for a node that is *not* the active
behaviour can still influence movement on transition ticks.

**Suggested fix:** decide on an explicit priority (combat > objective > wander) and enforce it in one
place, ideally inside the locomotor, rather than by tree ordering. Untouched — it is an architecture
change, and the recent additions to `Attack.Engage` (cross-level pathing, the planted/aim-patience
gate) deliberately work *with* tree order rather than against it.

---

### 12. `FIXED` — `SetGoal()` with no argument means "stop", not "keep current"

**Where:** `components/sv_locomotor.lua` — `SetGoal` (336) and the new `ClearGoal` (341); call sites
`behaviors/defib.lua` (259), `behaviors/mingecrowbar.lua` (128), `behaviors/createdeputy.lua` (115),
`behaviors/createsidekick.lua` (132), `behaviors/stalk.lua` (126).

**Symptom:** `loco:SetGoal()` reads like "no change" but actually clears the goal. It worked, but it
was indistinguishable from a missing-argument bug, and it silently interacted with #11.

**Fix:** added `BotLocomotor:ClearGoal()` (`self.goalPos = nil`) and moved all five call sites to it.
This register used to list four call sites; `stalk.lua` was the one that had been missed.

---

### 13. `VERIFIED` (not a conflict) — aim and movement both write the view angles, on purpose

**Where:** `components/sv_locomotor.lua` — `StartCommand` step 5 (`cmd:SetViewAngles`, 1637) and
`UpdateEyeAnglesFinal` (267) with `TickViewAngles`' priority tree (1365, `HandleOverrideLook` at 1336).

**Suspicion:** The view is decided twice per tick by two systems, so a combat `LookAt` on the target
could be overridden by the movement vector's angle, showing up as bots aiming along their walk
direction mid-fight.

**Finding:** they are two different things wearing the same name.

- `cmd:SetViewAngles` writes the *command's* angles, which the engine uses as the reference frame for
  `SetForwardMove`/`SetSideMove`: "forward" means "along these angles". That is the steering, and it
  has to be the walk direction or path following stops working.
- Where the bot actually looks — and therefore where it shoots — is `bot:EyeAngles()`, which
  `UpdateEyeAnglesFinal` rotates towards `lookPos`. `HandleOverrideLook` is the **first** handler in
  `TickViewAngles`' priority tree and returns true whenever `lookGoal` is set, which a combat
  `Attack.Engage` does every tick through `loco:LookAt(aimPoint)`. So while a fight is on, the eye
  angles are the target's and the walk-look handlers below it never run.

`Attack.IsAimedAt` compares `bot:EyeAngles()` with the target and gates the trigger on it, and bots do
land shots, which is the empirical half of the same conclusion.

**Action:** documented in the code at the `cmd:SetViewAngles` call so a future reader does not "unify"
the two and break either the aim or path following.

---

### 14. `FIXED` — `bot.wasPathing` was written but never read

**Where:** was written in `behaviors/attacktarget.lua` — `OnStart` (33), `Seek` (76), and six spots in
`Engage` (270, 280, 284, 289, 298, 302). No reader anywhere in the addon.

**Symptom:** Dead state that reads as though the locomotor or combat logic consumes it, which invites
future changes to rely on a flag that has no effect. It had just been propagated into the new
cross-level branch of `Engage`, which is what made it worth clearing out.

**Fix:** all eight writes deleted.

---

### 15. `MONITOR` — `PauseAttackCompat` has no caller

**Where:** `components/sv_locomotor.lua` — `PauseAttackCompat` (1466), `ResumeAttackCompat` (1481),
`TestShouldPreventFire` (1488); `behaviors/defib.lua` (297) calls only the resume.

**Symptom:** `attackCompat` is a latch with an owner-free pause that nothing calls, while the
defibrillator resumes it as though something had. Harmless today (a nil `attackCompat` already means
"do not pause fire"), but it is the same trap as #14: API that reads as live. Either give it a real
owner or drop the pause/resume pair.

---

### 16. `FIXED` — the unstuck code read "standing still on purpose" as "wedged"

**Where:** `components/sv_locomotor.lua` — `IsStuck` (928), `TryUnstick` (733, fallback at 797), the
stuck handling in `UpdateMovement` (899–901), new `IsTryingToMove` (949);
`behaviors/attacktarget.lua` — the aim-patience branch of `Attack.Engage` (~344).

**Symptom (reported 2026-09-18):** bots weave left and right in a fight and never shoot — the same
twitch that #7 and the strafe-hold work were supposed to have ended.

**Cause:** two systems read the same stillness in opposite ways.

- `Attack.Engage` deliberately stops weaving when a bot has failed to line a shot up for `AIM_PATIENCE`
  (1.5 s) so its view angles can catch up, and it did that with `loco:Strafe(nil)` only.
- `IsStuck` is a *position* test: ten recorded samples (every third tick) within 8 units of their own
  average — about 1.5 s of not moving, the same timescale. `RecordPosition` only runs while
  `isTryingPath`, and a bot that was pathing when the fight started still has that stale goal, so it
  qualifies.
- `TryUnstick` then ran, and with nothing within 30 units of its knee-height traces (a player 200 units
  away does not show up) it fell through to `(self.tick % 20 == 0) and "left" or "right"` — a strafe
  direction that **flips every tick**.

Because `Strafe` keeps a direction alive for a second, the flip beat the plant and outlived it, so the bot
never settled: it kept weaving, kept failing `Attack.IsAimedAt`, kept calling `loco:StopAttack()`, and
never fired. The two states even start together, since 1.5 s of standing still is what both the plant and
the stuck detector wait for.

**Fix, in three parts:**

1. `TryUnstick`'s fallback holds a side for a second (`unstickStrafeDir` / `unstickStrafeUntil`) instead
   of flipping on the tick — the same rule `Attack.StrafeIfNecessary` follows.
2. The stuck handling is gated on the new `IsTryingToMove()` (a movement vector, or an active
   forward/backward force). A bot that combat told to stand still is not trying to move, so it is left
   alone; a bot walking into geometry still has a movement vector and is still rescued.
3. The plant in `Attack.Engage` now calls `loco:StopMoving()` rather than `Strafe(nil)`, so it also drops
   the stale goal the bot was pathing to. That is what makes the plant actually hold, and what keeps the
   bot out of `IsTryingToMove` while it is planted.

**Do not regress:** the unstuck fallback must stay sticky, and `IsStuck()` must stay behind the "is
anything asking us to move" gate. Any new caller of `Strafe` inside `UpdateMovement` will start the same
fight with `Attack.StrafeIfNecessary` all over again.

---

### 17. `FIXED` — bots walked forwards and backwards in front of their target

**Where:** `behaviors/attacktarget.lua` — the close-quarters state block in `Engage` (275-330) and the new
`BACKPEDAL_START` / `BACKPEDAL_STOP` constants (170); `bot.attackBackingOff` is cleared in `Attack.OnEnd`.

**Symptom (reported 2026-09-19):** in the post-round deathmatch, bots shuffle forwards and backwards before
shooting, as if the locomotor and the combat behaviour were arguing over the same bot. It is not actually
specific to deathmatch — the free-for-all just puts several bots in the same small room, so the fight distances
sit in the band where this happened.

**Cause:** two faults in the same block. The second only became visible because of the first.

1. The *stop* state cleared the forces but left the bot's **goal and path** alive. `StartCommand` derives the
   forward move from `(forceBackward and -400) or ((hasMoveVec or forceForward) and 400) or 0`, so with no force
   set a live path still walks the bot forward. Between the backpedal distance and `ENGAGE_THRESHOLD` the bot
   had nothing holding it back while its own path pushed it into the target it had just declined to close on.
2. The backpedal trigger was a bare `distToTarget < 100`, and every call refreshes the force's **one second**
   timeout (`BotLocomotor:SetForceBackward`). So the path pushed the bot in, it flipped to backing off below
   100 units, kept going backwards for up to a second after the trigger stopped firing, and then the path
   walked it in again. The only `SetForceBackward(false)` on the non-melee path sat in an `elseif` that cannot
   be reached — `not (forceStop or maintain) and not shouldApproach` is false for every distance.

**Fix:**

- `BACKPEDAL_START` (100) and `BACKPEDAL_STOP` (160) make the retreat *latching*: it begins below 100 and does
  not stop until the bot is past 160, so there is a 60 unit band with no boundary to flip on.
- Every state that is not "walk towards the target" now calls `loco:StopMoving()`, which clears the goal *and*
  the path — exactly what the planted branch has always done — so the forces are the only thing steering.
- The retreat is skipped while `loco:IsCliffed()`, so a bot with a drop behind it stands and shoots rather than
  walking off the edge; it falls through to the hold-position branch.
- `bot.attackBackingOff` is cleared in `Attack.OnEnd` alongside the other per-fight state.

**Do not regress:** a force on its own cannot hold a bot still — `StopMoving` is what kills the path vector,
which would otherwise walk it forward. Any state added to this block has to do both, and any new distance
boundary needs hysteresis rather than a single threshold. This is #16's lesson on the other axis: there the
strafe flipped left/right per tick, here the retreat flipped forwards/backwards.

---

### 18. `FIXED` — the ladder the bot is on was identified as "the nearest ladder"

**Where:** `components/sv_locomotor.lua` — new `BotLocomotor:GetLadderOn` (1456), used by `ShouldDismountLadder`
and `IsNearEndOfLadder`. `LADDER_NEARBY_DIST` is unchanged.

**Symptom (reported 2026-09-19):** bots are stuck more often than before the ladder work, mostly around
ladders.

**Cause:** deciding when to let go of a ladder means comparing the bot's height against the top and bottom of
the ladder it is holding, and the code asked `GetClosestLadder()`, which measures to a ladder's **centre**. A
tall ladder's centre is half its height away, so a *short* ladder elsewhere can be the closest by that measure
while the bot stands at the top of a tall one. Measured against the wrong ladder, `botZ >= topZ -
LADDER_THRESH_TOP` is satisfied halfway up the climb: the bot presses use, drops off, walks back and climbs
again. This was rare before the ladder fix only because `GetAllLadders` used to miss most of a map's ladders —
fixing the enumeration is what made a wrong ladder a frequent candidate.

**Fix:** `GetLadderOn` keeps only the ladders whose span contains the bot's height (`LADDER_ON_Z_SLACK` of 64
either side, for the frame after mounting or just before letting go) and then takes the nearest *horizontally*.
Both ladder decisions use it. The `LADDER_NEARBY_DIST` check survives as a sanity bound: a bot genuinely on a
ladder is a few units from it horizontally, so only a `func_useableladder` (or a navmesh that does not list the
ladder) still takes the "let go and let pathing handle it" path.

**Do not regress:** on a ladder, "nearest" is not "the one we are on". Anything that reads a ladder's geometry
to decide what to do next has to identify the ladder by overlap with the bot's position first.

---

### 19. `NEW API` — nothing could hold the `+use` key, and the flag that looked like it could is still dormant

**Where:** `components/sv_locomotor.lua` — the new `SetHoldUse`/`IsHoldingUse` pair beside `SetUse`, the IN_USE
write in `StartCommand` next to the sprint block, and the `holdUse` field declared with `crouch`/`sprint`/`jump`.

**Symptom (found while adding the Pharaoh's Ankh):** a bot cannot hold `+use`. `Player:KeyDown(IN_USE)` reads
the *command's* buttons, and an entity with `CONTINUOUS_USE` polls exactly that in its own Think - the Ankh gives
up on a six-second conversion the tick the key is not held - so a behaviour that wants to hold the key had no
way to ask for it.

**Cause, and the trap inside it:** `BotLocomotor:SetUse` already existed and looked like the answer
(`GetUsing()` reads `emulateInUse`, and `StartCommand` has a door block gated on it). Two things were wrong with
using it. Nothing in the addon had **ever called** `SetUse`, so that block has never run on any server; and on
TTT2 it does not press the key anyway, it calls `Door:ToggleDoor(bot)` directly. Waking it by sharing a flag
would have been a behaviour change hiding inside a new feature: `DetectDoorNearby` searches a **sphere** of 100
units around the bot rather than whatever it is looking at, so a bot holding `+use` on an ankh that happens to
be next to a door would start opening and closing that door, once a second, for the whole conversion.

**Fix:** a flag of its own. `SetHoldUse(true)` makes `StartCommand` write `bit.bor(cmd:GetButtons(), IN_USE)`
every tick until it is cleared - written before the movement block, so nothing later in the command build can
drop it - and `behaviors/stealankh.lua` sets it for its conversion window and clears it in `OnEnd`. `SetUse` and
its dormant door block are left exactly as they were, with the reasoning written down at the function instead of
being re-litigated the next time somebody wants a use key.

**Do not regress:** the write has to stay *before* the ladder branch (which replaces the buttons outright, and
is why a bot on a ladder only presses IN_USE for its dismount) and above `ApplyAttackButtons`, which adds to the
existing buttons rather than replacing them. If the door emulation is ever wired up it needs its own answer to
the 100 unit sphere above - do not merge the two flags.

---

## Already fixed elsewhere (do not regress)

These lived in the same family and were fixed earlier; they are the reference examples for how the
conflicts above fail:

- `BotLocomotor:ValidateGoalProx` (841) — must **not** clear `goalPos`, otherwise `FollowPath`'s
  arrival check flaps between set and clear and the bot stutters in place.
- `Attack.Seek` — the condition must not be always-true (`or targetInvalidTicks < 2`), otherwise bots
  park staring at a stale spot.
- `Attack.Engage` — must end with `loco:StartAttack()` / `StopAttack()`; omitting it makes bots stop
  shooting entirely.
- `Attack.StrafeIfNecessary` — must hold a direction for `STRAFE_HOLD_MIN`..`STRAFE_HOLD_MAX` rather
  than re-rolling every tick; the 1 s `Strafe` timeout plus a per-tick roll is what produced the
  10 Hz left/right twitch and the two-bot standoff. `BotLocomotor:TryUnstick`'s fallback was the same
  bug in a second place (see #16), and any other caller of `Strafe` has to follow the same rule.
- A bot whose weapon only works at arm's length **runs** while it closes: `Attack.ShouldRunToCatch`
  (melee or short range), applied in `Attack.Seek`'s warm trail and in `Engage`'s melee branch, with the
  sprint handed back in `Attack.OnEnd` so it cannot latch past the fight. At walking pace such a bot
  matches the speed of anybody walking away from it and never closes at all, which is what made the
  Shanker's knife useless (its own stalk behaviour has always run for the same reason) and would do the
  same to the Roider's crowbar.
- `behaviors/curseswap.lua` (29) is a third writer of `SetSprint` + `SetGoal`: the Cursed sprints to whoever it
  is about to hand its role to, exactly as a melee bot sprints into its weapon's range, and its `OnEnd` hands
  back the sprint, the goal and the paused auto-switch. `pauseAutoSwitch` is an inventory latch that survives
  death (see the Shanker's stalk), so nothing here may set it without clearing it on the way out.
- **The command never asks for sprint and a crouch at the same time.** `StartCommand` gates the `IN_SPEED`
  write on `not (IsTryingCrouch() or IsTryingJump())` (1774): the same command already carries `IN_DUCK`
  whenever the bot is crouching *or* jumping (1633), and the path follower crouches by itself under low
  geometry, so a bot being walked through a tight spot would otherwise hand the gamemode a duck and a sprint
  together. TTT2's sprint is `IN_SPEED` held with a movement key (289), so it is the sprint key that has to be
  withheld here - not the move.
- `behaviors/evade.lua` (34) is the fourth writer of `SetGoal` + `SetSprint`, and the only one that is a *tree
  head*: while the post-round deathmatch runs it holds the first slot of `PriorityNodes.Survive`, ahead of
  `FightBack`, which is what stops a bot that cannot fight from ever reaching `AttackTarget`, `Stalk` or
  `MingeCrowbar`. It hands everything back in `OnEnd` (no goal, no sprint, no attack button) and it is inert
  outside the deathmatch, or for a role that can fight. Do not move it out of the head of the tree, and remember
  it whenever a custom tree is written for a role that cannot deal damage.
- That closing stops at the **weapon's own reach**, measured from the eye to the point being swung at:
  `Attack.GetSwingReach` / `MELEE_SWING_REACH` (75), with `Attack.IsSwung` deciding what counts as a swing
  and `SHORT_RANGE_SWING_REACH` (160) kept for short range guns. It used to be 160 between the two players'
  *feet* for everything swung, and 160 is past every melee trace in the game - the crowbar and the knife
  trace 100 units from the eye, the Shanker's knife 80 - so a melee bot stopped short of its own range and
  swung at air, which cost the Roider and the Shinigami their whole round. Do not collapse this back into one
  number: the arsonist's thrower is a gun with real reach and needs the longer distance.

## Re-checking a fix

The fastest check is `node tools/glua-check/check.js` (see `tools/glua-check/README.md`): it parses every
file with a real GLua grammar, and validates hook names and GMod API references against the wiki database
that ships inside the installed "GLua Enhanced" extension. It should report `0 issue(s)`; the two API
*notes* it prints are deliberate cross-addon nil-checks, not failures.

Without that extension installed, syntax-check the whole addon with `luaparser` (GMod's `continue` keyword
is non-standard, so swap it for `do end` first — it is syntactically equivalent for this purpose):

```
py -m pip install luaparser
py -c "import glob;files=sorted(glob.glob('lua/**/*.lua',recursive=True));exec('''from luaparser import ast\nbad=[]\nfor f in files:\n    try:\n        ast.parse(open(f,encoding=\"utf-8\").read().replace(\"continue\",\"do end\"))\n    except Exception as e:\n        bad.append((f,str(e)))\nprint(\"checked\",len(files),\"files; failures:\",len(bad))\nfor x in bad: print(x)\n''')"
```

Useful debug convars while testing movement: `debug_pathfinding`, `debug_strafe`,
`debug_stuckpositions` and `debug_misc`.
