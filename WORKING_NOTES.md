# Working notes

Scratch handover notes for a working copy of this addon, written 2026-09-19 so a future session can pick up
without re-deriving anything. Paths are relative to the addon root (this folder) unless they use one of the
placeholders listed under "Path notation" in section 1. Not part of the addon and referenced by no Lua -
delete it or fold it into `CHANGELOG.md` when preparing a release.

Related docs, in preference order:

- [`lua/tttbots2/movement_conflicts.md`](lua/tttbots2/movement_conflicts.md) - the movement-conflict
  register. **Authoritative**; keep it updated when touching movement.
- `CHANGELOG.md` - released, versioned changes. This session did not add an entry.
- [`lua/tttbots2/plan_summary.md`](lua/tttbots2/plan_summary.md) - older planning notes.

There is no git repository in this folder (`git status` fails), so nothing here is diffed against a base.

---

## 0. Handover index - what this session changed (2026-09-19 through 09-22)

`glua-check` at the time of writing: **127 files, 0 issues, 2 notes**. Everything below is a pointer; the
sections hold the detail, and the movement register is authoritative for anything that moves a bot.

Read this first; the detail is in the sections below and in the movement register.

**Sections added this session:** 1b (the GLua checker), 13 (the fake bot-disconnect console line), 14
(`ParanoidKiller`), 15 (RDM had no minimum time), 16 (idle stands and circling when a round goes quiet), 17 (bots
stuck more often) - plus new subsections: Fuse / Doctor / Amnesiac in 2, Fake Soda / Boom Body / Thomas /
Minethrower in 7, the sniper/hiding spot findings plus the sniper-perch work in 10 - that one added a new plan
target, `POPULAR_SNIPERSPOT`, which picks a perch overlooking a busy area - 18 (the popularity map that target
reads), 19 (the whole-tree audit, which found the deputy's missing investigate group and two broken French
locale categories), 20 (the Hitman's contract and the flick loop behind it), 21 (the C4 countdown, where the
workaround was deleted rather than fixed), 22 (dead bots making live callouts), 23 (two C4s planted in the same
spot), 24 (bots freezing at gunshots), 25 (bots deducing a killer - the loitering tracker and the searched body,
with three further options parked for later), 26 (a sniper perch now needs a weapon that can use one), 27 (the
Blocker's hand-written profile being shadowed by a generated clone, which is a load-order race that can hit any
role file), 28 (the Roider and the Shinigami swinging from out of reach, where the attack behavior's "melee
range" turned out to be a guess at 160 rather than the weapon's own trace), 29 (the Cursed - a role a bot could
not play at all, because its whole mechanic is a keypress a bot cannot send - which also turned up the Blocker
profile that 27 filed under a role's *index* and which no lookup could therefore ever find), 30 (traitors
opening fire the moment a round begins: one shared gate, two clocks, `ttt_bot_attack_delay` as the only knob),
31 (the performance sweep - the path-finder's inner loop, one visibility answer per tick per pair, the per-tick
allocations and the per-tick world scan), 32 (the Revenant, one role in two states: a hidden innocent while it
lives, a neutral killer after its revive changes its team), 33 (the Pharaoh and the Graverobber - one role duo
whose whole mechanic is an item, the first real `+use` hold a bot has ever had, and the dormant door path that
had to stay dormant because of it), 34 (the Jester and the Swapper fighting a fight they cannot win in the
post-round deathmatch, where a second target rule turned out to have none of the first one's guards), 36 (the
Mesmerist's defibrillator letting the trigger up before the weapon's own revive timer, when releasing the trigger
is what cancels the revival), 37 (a NULL attack target reaching the tick's visibility cache and throwing
"Tried to use a NULL entity!"), 38 (the deathmatch hiding node calling `Player:Visible` with a position, because a
comment above it claimed that was allowed), 39 (the whole addon asking "can I see that player" with an NPC-shaped
function that returns false for every player on a server that sets `ai_ignoreplayers`) and 40 (three per-tick
entity scans that a codebase index turned up: two folded behind their own guards or shared, and the third already
cached - where the honest answer was to leave it alone).

**New cvars**, all `ttt_bot_` prefixed and all defaulting to something safe: `throw_nades`, `use_soda`,
`place_fake_soda`, `use_boom_body`, `use_thomas`, `use_minethrower`, `rdm_delay` (30), `use_ankh` (33).

**New files:** `behaviors/fusecharge.lua`, `behaviors/placefakesoda.lua`, `behaviors/boombody.lua`,
`behaviors/thomas.lua`, `behaviors/minethrower.lua`, `behaviors/curseswap.lua` + `roles/cursed.lua` (29),
`behaviors/placeankh.lua`, `behaviors/stealankh.lua`, `behaviors/moveankh.lua`, `behaviors/breakankh.lua` +
`roles/pharaoh.lua`, `roles/graverobber.lua` (33), `behaviors/evade.lua` (34), `roles/revenant.lua` (32), and
`tools/glua-check/` (tooling, not shipped).

**Thirteen rules this session paid for, in the order they cost time:**

1. **A bot's direct call bypasses the addon's own hook.** `CORPSE.ShowSearch` sits *below* `TTTCanSearchCorpse`,
   and two roles hang their whole mechanic off that hook: the Blocker (refuses searches) and the Amnesiac (the
   search *is* the role change). Same shape as `SUPERSODA:PickupSoda` and `FAKESODA:PickupFakeSoda`, which are
   reached through a server-side `KeyPress` a bot can never send. Before concluding an addon does nothing for
   bots, find the hook it lives in and check whether we ever run it.
2. **A load-time registration into somebody else's table dies on the next reload** (section 14). Register through
   a method on the component, and re-assert at the point of use if the reader can outlive the load.
3. **One skeleton for every single-use item** (section 7): pause the inventory's auto-switch, select the weapon,
   press once, confirm it was spent (the weapon removing itself, or `Clip1` dropping), give up on a timeout.
   `defectorbomb.lua`, `boombody.lua`, `thomas.lua`, `minethrower.lua` and `placefakesoda.lua` all do this; the
   only thing that differs per item is the rule that *precedes* the press.
4. **Before building a mechanism, check whether it is already here and simply has no reader.** This session found
   six of them, each a *finished-looking* half of a feature wired to nothing: `NearUnidentified` + the
   `playersNearBodies` tracker (25), `WeaponInfo.is_sniper` (26), `GetBestSniperSpots` before section 10 wired it,
   `cantReachGoal` before section 12, `SetAutoSwitch`/`SetPreferredWeapon` before the Roider fix (2), and
   `RoleData.GetEnemies`, declared on the role API and read by nothing at all (32). A grep
   for the flag, weight or tracker costs a minute and twice saved a rewrite. The corollary: such a stub makes the
   *behaviour* look broken when the code reads perfectly - the Blocker's flags were all present and correct
   (27), and the role still behaved generically.
5. **A comment that states a number or a claim is a claim to verify against the code.** Seven turned out wrong in
   this one stretch: the Fuse's "manual detonation" (2), the popularity timer's "we're in a round" (18),
   `NearUnidentified`'s "more than 5 seconds" (25), `sh_c4timer`'s clock premise (21), the sniper spots' implicit
   "the bot is holding a rifle" (26), `GetTargetPlayer`'s "the gamemode hands it a victim" (20), and the melee
   branch's "the old logic used 160" - 60 past every melee reach in the game (28). Where a comment names a
   constant, point at the constant instead of repeating its value.
6. **A role file guarded on another addon's global is a load-order race, and the auto-registration path hides it**
   (27). `tttbots2/roles/*` are included while *this* addon loads and each returns false if its `ROLE_X` global is
   not there yet, so a role addon that loads later silently loses its profile to `GenerateRegisterForRole` - a
   *clone of the base role* with none of the hand-written flags. Two console lines now tell the two cases apart:
   `Registered role 'x' late` (ours claimed it) versus `Auto-registered role 'x' based off of 'y'` (a stand-in, so
   any custom flags are missing).
7. **A role's `ROLE_X` global is its numeric *index*, never its name - and a profile filed under the wrong one
   fails silently.** TTT2 gives every role an index (`roles.GenerateNewRoleID`) and publishes it as
   `_G["ROLE_" .. NAME] = roleData.index`, while the string a profile has to be filed under is `roleData.name`,
   which is what `Player:GetRoleStringRaw()` returns and `GetRoleFor` looks up. TTT2 also publishes the role table
   as the uppercase global (`CURSED`, `BLOCKER`), which is where to take the name from. Getting this wrong is
   invisible: `GetRole` misses, hands back the **innocent** profile, and every flag the file set is simply absent
   (29 - it is exactly what was wrong with the Blocker for a session). Note this is the trap *inside* rule 6: the
   same file that guarded on `ROLE_BLOCKER` also registered under it, and the guard is the half that works.
8. **A delay is only ever as good as the paths it is applied to.** `ttt_bot_attack_delay` read like the answer to
   "traitors open fire too early" and was applied to exactly one of the three ways a bot is handed a victim (30):
   the random roll, the plan system's attack orders and the last-player-standing rule were gated three different
   ways, two of them weakly and one not at all. Having found a gate, grep for the other producers of the same
   outcome before trusting it - and read the *fallback* branch in particular, which is where the traitor's
   default `ATTACKANY` job was hiding.
9. **A trace is the expensive primitive, and the same pair gets asked about several times in one tick.** The
   biggest win in the performance sweep (31) was not an algorithm: it was answering "can this bot see that
   player" once per tick and handing the answer to everyone who asks. The memory pass, the attack behaviour, the
   ADS check, the inventory and four morality passes were each firing their own rays at the same pair inside the
   same 5 Hz tick. When a per-tick path looks expensive, count the *traces* first - and when you do touch an
   algorithm, put an instrument on it before and after, because the path-finder's real cost was invisible until
   it was printed.
10. **A flag that exists is not a flag that works - and a doc comment is not a parameter list.** Two halves of
   one lesson, both paid for by section 33. `BotLocomotor:SetUse` had been there for two sessions with a getter,
   a field and a reader in `StartCommand`, and **nothing had ever called it**: the door block it gates had never
   run once, and on TTT2 it would not have pressed the key even if it had. Beware the mechanism that reads
   perfectly and has never executed (rule 4 seen from the other side), and when a new feature wants an old flag,
   ask what its existing readers do with it - here `DetectDoorNearby` searches a 100 unit sphere, so sharing the
   flag would have had a bot holding `+use` on an ankh flapping every door around it. The second half: GluaLint
   caught `handler` being indexed inside a function that never took it as a parameter, which the doc comment
   directly above had been promising all along - a nil-global crash on the first conversion attempt, found by the
   linter and missed by reading it back. Lint new files before believing them.
11. **A rule that runs in a second phase needs the guards of the first one, copied deliberately.** Section 34:
   the round hands out targets through `SetRandomNearbyTarget`, which checks `GetStartsFights` at least, and
   `Attack.ValidateTarget` clears them again for `GetDealsNoDamage` roles. The deathmatch producer,
   `SetDeathmatchTarget`, was written later, checked **nothing**, and handed a target to every living bot - so
   the Jester and the Swapper, which carry none of those flags, spent the post-round shooting people they could
   not damage. When a phase gets its own copy of a decision (post-round, deathmatch, respawn, mid-round team
   change), diff it against the original and carry the guards across - and then add its own, because a Jester
   *should* pick fights during the round and must not after it.
12. **An API's documented audience is part of its contract.** Section 39: `Entity:Visible` reads like the obvious
   way to ask "can A see B", and its own page says "meant to be used only with NPCs" - with `ai_ignoreplayers`
   making it return false for every player target, and `FL_NOTARGET` doing the same for one player. The addon had
   been calling it for players ever since the performance sweep centralised visibility onto it, so a server that
   sets that single cvar would have had blind bots - silently, because on default settings the two agree. When a
   refactor picks a primitive it inherits that primitive's contract: read the page before choosing, and prefer the
   implementation written for the job (here the addon's own three-point shot trace) over one that merely exists.
13. **Two scans that touch the same object are not the same question.** Section 40: `placefakesoda.lua` asks two
   separate things about soda cans. "Is there a real can to sit the decoy beside" is `ents.FindByClass("soda_*")`,
   and pointing it at the shared cached list is a straight saving. "Is anything already standing where the decoy
   would go" is *not* that query: the Fake Soda addon's own cans are `ent_ttt2_fake_soda_*`, which `soda_*` does
   not match, so the class list would have let a bot drop decoy on decoy - and the test the file actually writes is
   `string.find(class, "soda")`, deliberately broader than either pattern. Sharing one cache between two lookups is
   only safe once you have compared what each of them is asking; the wildcard is a claim about every entity of
   that kind, and the claim is usually wrong.

**The fairness line drawn this session, so it is not re-litigated by accident:** bots are not told things a
player could not know. They do not know whether a can is a Fake Soda, they do not know a corpse is a Boom Body
(unless they set it themselves), and they get no warning about a mine that is not theirs. What they are told is
the same tell a player gets - a boom body they own (the addon gives the owner marker vision), their own fuse
timer, their own mines. Traps staying effective against bots is deliberate. Two later changes sit deliberately on
the *inside* of that line and are worth re-reading before anyone "fixes" them: a bot that searches a body may use
the killer TTT2 recorded on the ragdoll - gated by TTT2's own `ttt_killer_dna_range` (550) and
`ttt_killer_dna_basetime` (100 s) decay, which is what a searching player is shown (25) - and a bot only walks to
a sniper perch if it *owns* a weapon that can use one (26).

**Deleted this session:** `lib/sh_c4timer.lua`, a client-side rewrite of a C4's networked `explode_time` written
for a countdown bug it could never fix (21). Recorded with its reason; do not rebuild it without reading that
section first.

**Current state:** `node tools/glua-check/check.js` -> **128 files, 0 issues, 2 notes** (both pre-existing and
nil-guarded: `cl_scoreboard.lua:313`, `sh_concommands.lua:182`). GluaLint over the whole tree reports **174
warning lines across the 128 files** - that count has not moved for the seven files sections 33 and 34 added, nor
for section 40's four edits, which were re-measured per file (`sh_botlib.lua` 13, its previous count, and
`drinksoda.lua`, `placefakesoda.lua` and `usehealthstation.lua` at 0 each) - so they are lint-clean, and all of
them are pre-existing style. The per-kind breakdown is in section 19, and every
section's verification line is a point-in-time record of the count when that change landed.

**Upload prep (2026-09-25), so a later session neither redoes it nor undoes it:** `.gitignore` now excludes
`.roo/` - local tooling state, and `.roo/mcp.json` holds credentials that must never be published - along with
the empty `validate_result.txt` (deleted) and `lua/tttbots2/plan_summary.md`, which this file supersedes. The
long-standing "CHANGELOG.md has no entry for any of this" gap is closed by a `v1.4.0 (unreleased)` section
covering the whole session; checking the notes against the changelog is still the fastest way to see what a
public reader will and will not learn. `.roo/` itself holds only `mcp.json`.

**Debug switches worth knowing while testing:** `ttt_bot_debug_misc` (prints the HuntTarget target claims and
`Attack.OnEnd` clears from section 20, the role-registration lines from section 27, and the chatter event names),
`ttt_bot_debug_brain` (draws the running behaviour over each bot, which is how a "frozen" bot is identified),
`ttt_bot_debug_navpopularity` (draws the popularity ranking the sniper-perch job reads), and
`ttt_bot_debug_pathfinding` (now also prints, per completed path, the frames it spanned and the CPU it cost in
total - the number to compare after any change to the search, section 31).

**Parked, with enough detail in the sections to pick up cold:** scene suspicion on sight (B), damage-log
reasoning with a witnessing gate (D) and the opt-in corpse-killer cheat (E), all in 25; registering *every* role
file under its global instead of a string literal, in 27. **Deliberately left alone, so they are not re-opened as
bugs:** no decay in the popularity map (18), `FARTHEST_SNIPERSPOT` plus `ACTIONS.ROAM`/`ACTIONS.DEFUSE` unused
(10), a bot can wander back onto its own mine (7), ally bots do not clear a Fuse's blast radius (2),
`ttt_bot_allow_leaving`'s help text still promising a replacement within 30 s when the code only does that at
`quota <= 0` (13), `GetRandomPopularNav` dead (18), and - so
they are not re-opened as bugs either - the weapon cache's map-wide walk (a `weapon_*` class query would miss m9k
and cw SWEPs), the position-based witness helpers, and `CullSoundMemory`'s per-sound trace, all in 31.

---

## 1. Tooling that works here

| Job | How |
| --- | --- |
| GLua-aware checks (syntax + hooks + API) | `node tools/glua-check/check.js` - see section 1b |
| Lint one file | `"<glualint>" <file>` - the executable from the `goz3rr.vscode-glualint` extension, or a `glualint` on `PATH` |
| Syntax-check everything (fallback, no extension needed) | write `.roo/lua_sweep.py` (body below), run `python .roo/lua_sweep.py` |
| Read a workshop addon | `"<gmad>" extract -file <gma> -out <dir>` - `fastgmad.exe`, or the `gmad` shipped with a GMod server |
| Delete temp files | `cmd /c "del /f /q .roo\name.py 2>nul & dir /b .roo"` |
| Find candidate hotspots across the tree | the editor's semantic codebase index (`codebase_search`) - **shape** questions only, like "what runs every tick and loops over all players" or "which entity scans are uncached". It cannot judge an API's contract (39 came from the wiki) and it cannot measure, so it ranks a once-per-purchase scan beside a per-tick one; text-shaped queries drown in the locale chatter files. Treat every hit as a lead and confirm it by reading the file (40) |

**Path notation.** The notes were prepared for publication, so every machine-specific root is a placeholder:
nothing here names a drive, a user profile or an install folder. Everything not in angle brackets is relative
to the addon root and works as a link on GitHub.

| Placeholder | Stands for |
| --- | --- |
| `<steam>` | the Steam install root (default `C:\Program Files (x86)\Steam` on Windows) |
| `<gmodserver>` | the root of a local workshop / `steam_cache` mirror |
| `<glualint>` | the GLuaLint executable |
| `<gmad>` | the `fastgmad.exe` / `gmad` archive extractor |
| `<reference-addons>` | any folder holding extracted reference addons |
| `%USERPROFILE%` | the Windows user profile (`$HOME` on Linux) |

Two relative roots recur and are deliberately kept, because they are what makes the notes findable: paths like
`lua/tttbots2/...` are inside this repository, and `../TTT2-master` is a **sibling** checkout of the TTT2 base -
clone TTT2 next to this repository and those links resolve.

GLuaLint notes: it lints by default (no `--lint` flag), takes **one file at a time**, exits 1 when it has
warnings, and uses its defaults because there is no `.glualint.json` here. Its defaults already know the
GMod globals, so there is no false "undefined global" noise. Useful diagnostics it gives: unused locals,
unnecessary parentheses, mixed single/double quotes, trailing whitespace, shadowed names, `GetConVar`
deprecation, and tab/space inconsistency.

**Superseded by `tools/glua-check/check.js` (section 1b)**, which parses with a real GLua grammar. Kept
as a fallback for a machine without the extension installed. The parser sweep script (luaparser; GMod's
`continue` is not valid Lua 5.1, hence the substitution):

```python
import os, re
from luaparser import ast
files = failures = 0
for dirpath, _, filenames in os.walk("lua"):
    for name in filenames:
        if not name.endswith(".lua"):
            continue
        path = os.path.join(dirpath, name)
        files += 1
        src = open(path, encoding="utf-8", errors="replace").read()
        src = re.sub(r"\bcontinue\b", "do end", src)
        try:
            ast.parse(src)
        except Exception as err:
            failures += 1
            print("FAIL", path, err)
print("files:", files, "failures:", failures)
```

Last run: **111 files, 0 failures** (the addon had 101 files before the ten new roles below).

### 1b. glua-check - the GLua Enhanced extension (added later the same day)

`node tools/glua-check/check.js` (see [`tools/glua-check/README.md`](tools/glua-check/README.md)).
It reuses two things from the installed `venner.vscode-glua-enhanced` extension:

- the **real GLua parser** (`node_modules/gluaparse`), recovered from
  `dist/extension.bundle.js.map` at run time, so no GPL source is vendored into the addon;
- `resources/wiki.json`, a GMod wiki scrape: **661 hooks, 334 globals, 133 libraries/classes** with
  every member, 130 panels and 3000+ enum members. This is what makes API checks possible offline.

Checks: syntax (GLua grammar, no `continue` hack), hook names against the wiki + TTT2 + this tree, and
`library.member` / called-global references against the wiki. TTT2 is read as a second source of
truth, which is what removes most false positives. A reference the same file nil-checks
(`if not draw.DrawAvatar then return end`) is reported as a *note*, not a failure.

Current result: **111 files, 0 issues, 2 notes** (both notes are guarded cross-addon references, see
section 5). Verified end to end by seeding `lua/_gluacheck_selftest.lua` with a bogus hook name, a
bogus `util` member and a bogus global: all three were caught, exit code 1. The snippet is in the
README.

### Environment traps

- The shell mangles escaped quotes inside `cmd /c "..."`: `if exist \"C:\path\"` reported **false
  negatives** for directories that exist. Use Python for filesystem checks or existence tests.
- `Remove-Item` and friends are unavailable; use `cmd /c "del /f /q ..."` / `rmdir /s /q`.
- The Lua files are **CRLF**. Any whitespace script must keep the `\r` out of the strip, or it rewrites
  every line of the file.
- `.roo/` is scratch space. It should contain only `mcp.json` when a session ends.

### Reference sources used

- TTT2 base: `../TTT2-master` (a sibling of this workspace - see "Path notation" above).
- Workshop addons: `<steam>\steamapps\workshop\content\4000\<id>\gmpublisher.gma`, mirrored at
  `<gmodserver>\steam_cache\content\4000\<id>\gmpublisher.gma`. The folder name is the workshop id.
- GitHub role sources were cloned to `.roo/refs/` during the session and deleted afterwards.

---

## 2. Ten roles gained support

Each is a `RoleData` file in [`lua/tttbots2/roles/`](lua/tttbots2/roles/), auto-loaded by
`TTTBots.Lib.IncludeDirectory("tttbots2/roles")` at the bottom of
[`sv_roles.lua`](lua/tttbots2/lib/sv_roles.lua), and each returns `false` when its role global is absent,
so missing addons are harmless. A hand-written role file always wins over `GenerateRegisterForRole` (that
only runs when the role was not registered).

| Role | Team | Notable decisions |
| --- | --- | --- |
| [`psychopath.lua`](lua/tttbots2/roles/psychopath.lua) | traitor | Ordinary traitor tree. Its `shopFallback = SHOP_FALLBACK_DETECTIVE` is followed automatically by `Buyables.GetBorrowedShopRole`. `isPolicingRole` mirrored as `AppearsPolice` (the disguise). |
| [`bandit.lua`](lua/tttbots2/roles/bandit.lua) | custom `TEAM_BANDIT` | The addon calls `roles.InitCustomTeam("Bandit", ...)`, so it is a team of its own - allied with other Bandits and nobody else, which is what makes it neutral. `AppearsPolice` too. Uses the `Stalk` behaviour. |
| [`gambler.lua`](lua/tttbots2/roles/gambler.lua) | traitor | `credits = 0` **and** the role blocks credit awards (`TTT2CheckCreditAward` returns false, `preventFindCredits`), so the four random items are its whole round. Nothing needed bot-side. |
| [`doctor.lua`](lua/tttbots2/roles/doctor.lua) | innocent | Loadout hands out `weapon_ttt_defibrillator`, the class `Defib` already knew. Uses the detective tree (the only one with a Defib node). `SetRevivesAnyCorpse(true)`. |
| [`roider.lua`](lua/tttbots2/roles/roider.lua) | traitor | Only the crowbar damages anyone, so `SetAutoSwitch(false)` + `SetPreferredWeapon("weapon_zm_improvised")`; no C4 (its own blast damage is zeroed). |
| [`fuse.lua`](lua/tttbots2/roles/fuse.lua) | traitor | 60 s fuse: no hiding, no sniping, no following - it has to be hunting. |
| [`mesmerist.lua`](lua/tttbots2/roles/mesmerist.lua) | traitor | Its defib revives corpses as Thralls, so `SetRevivesAnyCorpse(true)` makes `Defib` take any body, not just a teammate's. |
| [`thrall.lua`](lua/tttbots2/roles/thrall.lua) | traitor | Converted role; read live by role name, so a bot converted mid-round picks it up immediately. |
| [`beggar.lua`](lua/tttbots2/roles/beggar.lua) | custom `TEAM_BEGGAR` | The addon zeroes every point of damage it *deals*, so `SetDealsNoDamage(true)` stops it taking targets at all. Keeps `Restore` (GetWeapons) because looting a dropped shop weapon is the entire role. |
| [`collusionist.lua`](lua/tttbots2/roles/collusionist.lua) | jester | Same as the Beggar, on the jester team. `SetDealsNoDamage(true)`, no FightBack/Minge nodes. |
| [`cursed.lua`](lua/tttbots2/roles/cursed.lua) | no team (`TEAM_NONE`) | Twelve. Cannot win and cannot hurt anybody, so `SetDealsNoDamage(true)`; it leaves the role only by swapping with another player, which is `behaviors/curseswap.lua` (29). |
| [`revenant.lua`](lua/tttbots2/roles/revenant.lua) | innocent, then its own `TEAM_REVENANT` | Thirteen. A hidden innocent while it lives, a neutral killer after its death changes its team - the live team rule (`SetLovesTeammates`), a state-keyed hunt and a reveal (32). |
| [`pharaoh.lua`](lua/tttbots2/roles/pharaoh.lua) | innocent | Fourteen. Ordinary innocent (`innocent.lua`'s flags, tree and empty allied sets); all of its gameplay is the Ankh, so the four ankh nodes live in the shared groups and the profile only adds `SetRoleWeapons` - the first innocent-team role weapon in the tree (33). |
| [`graverobber.lua`](lua/tttbots2/roles/graverobber.lua) | traitor | Fifteen. `notSelectable` - the addon converts a random living traitor into it the moment a Pharaoh places its first Ankh - so the profile is `traitor.lua` with nothing added, and its one extra verb (conversion) is a shared node (33). |

Role files that were **not** touched but are worth knowing: `hidden`, `shanker` and `shinigami` carry long
"do not regress" comments, and `revolutionary`/`spy` explain borrowed-shop and bluff mechanics.

### Blocker (added later)

[`blocker.lua`](lua/tttbots2/roles/blocker.lua) - the eleventh role, from `ChrisScott9456/ttt_blocker_role`
(read from a shallow clone of the repo, not from a description). An ordinary traitor - traitor tree, traitor
shop fallback, `ROLE_TRAITOR` base - with one passive: while a Blocker is alive, that addon's own
`TTTCanSearchCorpse` hook refuses every body search but the Blocker's, and every body is identified at once
when the last Blocker dies.

The passive needed a new RoleData flag, `SetBlocksCorpseIdentify(true)`, read through the new
`TTTBots.Roles.IsCorpseIdentifyBlockedFor(ply)`. The reason is that our corpses are not read the way a
player's are: `InvestigateCorpse` calls `CORPSE.ShowSearch`/`CORPSE.SetFound` **directly**, which sits below
the hook the role installs. Without the flag a bot would identify exactly the bodies the role exists to hide,
and would re-target them forever, since they never become found. The behavior checks it in `Validate` and
again in `OnRunning` (a defibrillator can put a Blocker back into the round mid-walk), and the check exempts
the Blocker itself, exactly as the addon's hook does.

### Cursed (added later)

[`cursed.lua`](lua/tttbots2/roles/cursed.lua) - the twelfth role, from `AaronMcKenney/ttt2-role_curs`, and the
only profile in this tree with no team at all. It cannot win, it cannot hurt anybody (its own hook zeroes every
point of damage a Cursed deals), and it comes back from the dead ten seconds after each death. The one thing it
can do is hand the curse to somebody else, and both of the addon's ways of doing that are out of a bot's reach:
the tag is a **keypress** - its server handler is a plain `CURS_DATA.AttemptSwap` call, which we make instead -
and the RoleSwap Deagle is a `WEAPON_EXTRA` weapon whose refill only ever ran on a client. Section 29 has the
detail, along with the Blocker profile that section 27 filed under a role's *index* and which no lookup could
ever find.

### Revenant (added later)

[`revenant.lua`](lua/tttbots2/roles/revenant.lua) - the thirteenth role, from `TaintedEnergy/ttt2-role-reven`, and
the first one in this tree whose *state* changes without its subrole changing: `ply.revenant_state` is 1 while it
lives (a disguised innocent, hidden by the addon's own role-syncing hook) and 2 after its revive, which calls
`ply:UpdateTeam(TEAM_REVENANT)` and turns it into a neutral killer with 50% more damage. A profile can describe one
of those two; the other half is the live team rule (`SetLovesTeammates(true)` against `ply:GetTeam()`), a hunt
keyed on the state, and a reveal that tells the suspicion system what a player reads off the HUD. Section 32 has
the detail, including the two upstream bugs found on the way (the damage bonus is applied to the victim's state,
and their damage hook would error on a non-player attacker).

### Pharaoh and Graverobber (added later)

[`pharaoh.lua`](lua/tttbots2/roles/pharaoh.lua) and
[`graverobber.lua`](lua/tttbots2/roles/graverobber.lua) - the fourteenth and fifteenth roles, from
`TTT-2/ttt2-role_pha`. One addon, two roles, and they cannot be supported separately: placing the Ankh is what
converts a random living traitor into the Graverobber, so a Pharaoh that never places one leaves the other role
unborn, and a Graverobber that never converts one leaves the Pharaoh's death permanent.

Both profiles are almost entirely declarative, which is the unusual part: all four of the roles' verbs are
behaviours in the shared `PriorityNodes` groups (place, convert, carry, and shoot an enemy ankh down), so
`pharaoh.lua` is `innocent.lua` plus a role-weapon registration and `graverobber.lua` is `traitor.lua` with
nothing added at all. The one piece of framework the addon forced was a way to **hold** `+use` - a first for
this addon, recorded in the movement register as #19 and in section 33 with the two behaviours that need it.

### Fuse - re-checked against the addon's own source

[`fuse.lua`](lua/tttbots2/roles/fuse.lua) already covered this role, but it had been written from a
description rather than the code, so the source was read this time (`milkwxter/TTT2Fuse`, path
`ttt2-role_fuse/lua/terrortown/entities/roles/fuse/shared.lua`; the whole module is that one file). Three
corrections came out of it:

- The timer is `ttt2_fuse_explode_timer` (default 60, archived), armed by the loadout and **re-armed on every
  kill the Fuse makes**. It lives in a single named timer (`ttt2_fuse_timer_explode`), so it only ever tracks
  whichever Fuse the loop finds first in the traitor team.
- On expiry the role plays `litFuse.wav` at the Fuse and explodes **three seconds later**:
  `util.BlastDamage(ply, ply, pos, 300, 200)` - up to 200 damage inside 300 units, no team filter, against a
  teamkill multiplier of -16. So an ally standing next to a Fuse dies with it.
- **There is no manual detonation.** The old comment in our file claimed "the role's own ability to detonate
  itself"; the workshop blurb's "use his given ability to explode others" describes the timer blast, not
  something anyone can call. Comment corrected, and nothing tries to trigger it.

The remaining time cannot be read from the server: `STATUS:AddTimedStatus` only networks a duration to the
client, so there is no countdown to ask for. New
[`behaviors/fusecharge.lua`](lua/tttbots2/behaviors/fusecharge.lua) therefore reconstructs the deadline from
the same two events the role uses - a life beginning, and a kill - plus the convar. Being a second or two out
only changes when the bot starts running.

That reconstruction is what the behaviour is *for*: **for the last 15 seconds the bot stops trying to survive
and runs at the nearest enemy position it remembers.** It is inserted after the plant node in the role's tree,
so shooting still wins - the charge owns only the ticks where the bot has nothing to shoot at, which is the
state it used to spend wandering or hiding in. It only ever charges a *non-ally* position, because the blast
has no team filter and the role punishes teamkills hardest.

Deliberately still open: ally bots do not clear out of a Fuse's blast radius. They cannot see its timer - the
status is client-side only - so anything they did about it would be guesswork or peeking. `SetCanHide(false)`,
`SetCanSnipe(false)` and `SetIsFollower(false)` stay as the other half of the role: the three ways to spend a
fuse doing nothing.

### Doctor - the defib that chooses who comes back

[`doctor.lua`](lua/tttbots2/roles/doctor.lua) covers the workshop Doctor (id 2755172511): an innocent whose
`GiveRoleLoadout` hands it `weapon_ttt_defibrillator` and nothing else, with `isPolicingRole = true` and
`shopFallback = SHOP_NONE`, so it has no shop and nothing to buy. The tree is the detective's, since that is the
one tree that already carries a defib node.

What changed is *who* it revives. `SetRevivesAnyCorpse(true)` was doing the work of getting the bot to look at a
body at all - the behaviour's default is teammates only, and the innocent side declares no allies on purpose,
so an ally-only defib left the bot walking past every corpse in the round. But "any corpse" also means traitors,
and a revived traitor is worse than no revive. New `SetRevivesInnocentSide(true)` narrows it: the body's role is
read off the ragdoll ([`Defib.IsInnocentSide`](lua/tttbots2/behaviors/defib.lua:150)) and a traitor is left where
it lies. Fools are still let through, since raising one is a wash rather than a loss, and detectives need no
special case - they are on the innocent side, so "not a traitor" already chooses them. The Mesmerist keeps plain
`SetRevivesAnyCorpse`: whoever its own defib is used on comes back as a Thrall, so for that role every body
really is the right one.

Reading a corpse's role is a deliberate little cheat, and it is the one the corpse investigation and the
Paranoid's reveal already take: a body is unidentified to a player, so "choose to revive the innocent one" has
no other implementation.

### Amnesiac - the one thing the role does never ran

[`amnesiac.lua`](lua/tttbots2/roles/amnesiac.lua) already carried the profile (TEAM_NONE, `preventWin`, kills
-12 / teamkills -16, no shop, and its own radar hook), but the role was still useless to a bot - for exactly the
reason the Blocker was. TTT2's Amnesiac does the conversion **inside its own `TTTCanSearchCorpse` hook**
(`ply:SetRole(deadply:GetSubRole(), deadply:GetTeam())`), and our corpse investigation identifies bodies with a
direct `CORPSE.ShowSearch` call, which sits *below* that hook. An Amnesiac bot could search every body in the
round and never become anything.

[`InvestigateCorpse.OnRunning`](lua/tttbots2/behaviors/investigatecorpse.lua:167) now runs
`hook.Run("TTTCanSearchCorpse", bot, rag, false)` before identifying anything and treats a `false` return as
"the addon owns this outcome" and stops. That is how TTT2 itself calls it - only `false` blocks - and it covers
both roles that use the hook at once:

- the Amnesiac converts inside the hook and then returns `ttt2_amnesiac_confirm_player`, which is `false` when
  the server does not want the body confirmed as well;
- the Blocker refuses the search, which is now enforced by the addon that means it rather than only by our own
  `IsCorpseIdentifyBlockedFor` flag. That flag stays: `Validate` still uses it to not even walk over.

Also added: `SetCanHaveRadar(true)`, because the role's own loadout hands it `item_ttt_radar`, so the bot should
get the radar treatment every other radar-carrying role gets.

### New RoleData API used by the above

In [`sv_roledata.lua`](lua/tttbots2/lib/sv_roledata.lua):

- `SetDealsNoDamage(true)` - read by `Attack.ValidateTarget`, which clears the target and returns false.
  Needed because such a bot shooting is a way to die for nothing.
- `SetRevivesAnyCorpse(true)` - read by `Defib.RevivesAnyone`, which replaces the hard-coded `allyOnly`
  argument in `Defib.Validate` / `Defib.OnStart`. `SetRevivesInnocentSide(true)` (the Doctor) then narrows it
  to the innocent side, read by `Defib.RevivesInnocentSide` / `Defib.IsInnocentSide`.
- `SetAutoSwitch(false)` + `SetPreferredWeapon(class)` - **these were declared but read by nothing**, which
  is what made the Roider harmless. `BotInventory:HandlePreferredWeapon` now honours them from
  `BotInventory:Think`, and falls back to normal management when the weapon is not in the inventory.

`Defib.WeaponClasses` gained `weapon_ttt_mesdefi` (the Mesmerist's defib; worked the same way as the
standalone one).

---

## 3. Movement work (see the register for detail)

[`lua/tttbots2/movement_conflicts.md`](lua/tttbots2/movement_conflicts.md) was re-verified line by line and
now records 18 entries with current statuses and line numbers. Highlights:

- **#4/#6 `FIXED`** - `dontmove`, `pauseRepel`, `dontAvoid` and `holdAttack` were unowned latches that
  nothing reset per life. `BotLocomotor:ResetLifeState` now clears them, called from a `PlayerSpawn` hook
  and a `TTTBeginRound` hook (bots are not recreated between rounds, so it needs a hook). A latched
  `dontmove` made a bot mute as well as immobile, because `StartCommand` returns before setting buttons.
- **#8 `FIXED` (gunplay half)** - the ladder branch replaced every button with `IN_FORWARD`, so a bot could
  not shoot while climbing. The attack/reload block moved into `BotLocomotor:ApplyAttackButtons`, which
  both the ladder branch and the main path call. The movement half (forces ignored on ladders) is left open.
- **#9 `FIXED`** - `Follow.OnRunning` set its goal to the bot's own position; now `StopMoving()` when close.
- **#12 `FIXED`** - added `BotLocomotor:ClearGoal()` and moved the five no-argument `SetGoal()` call sites
  to it (the register used to list four; `stalk.lua` was missing).
- **#13 `VERIFIED`, not a conflict** - the cmd view angles are the *movement* frame; aiming is
  `bot:EyeAngles()` via `UpdateEyeAnglesFinal`, and `HandleOverrideLook` is first in `TickViewAngles`'
  priority tree, so a combat `LookAt` wins. Documented in the code so nobody "unifies" the two.
- **#16 `FIXED`** - the strafe twitch that came back into fights. `IsStuck` is a position test (~1.5 s of
  not moving), which is exactly what the aim-patience "plant" produces, so `TryUnstick` ran and its
  fallback flipped the strafe **every tick**, beating the plant. Fixed in three parts: the fallback now
  holds a side for a second, the stuck handling is gated on the new `IsTryingToMove` (a movement vector or
  an active force), and the plant now calls `StopMoving()` so it also drops the stale goal.
- **#17 `FIXED`** - the forwards/backwards shuffle in front of a target. The stop state cleared the forces but
  left the goal and path alive, and a live path walks a bot forward on its own; the backpedal distance was also
  a bare threshold whose force outlives its trigger by a second. The retreat now latches (100 -> 160) and every
  non-approaching state calls `StopMoving`, so a force is never the only thing holding a bot still.
- **Open, do not fix blind**: #5 (`pauseRepel` is not refcounted - a naive counter breaks because
  `MingeCrowbar` pauses every tick; it needs an owner table), #10, #11 (implicit goal precedence), #15
  (`PauseAttackCompat` has no caller) and the ladder movement half.

Combat strafing lives in `Attack.StrafeIfNecessary`: hold a direction for `STRAFE_HOLD_MIN..MAX`, never
re-roll per tick. `BotLocomotor:TryUnstick` and any future caller of `Strafe` must follow the same rule.

---

## 4. Spectator camera - investigated, fix REVERTED on request

The user reported: *"the camera gets stuck pointing at nothing / at a frozen spot after the round ends or
when the bot I'm watching disappears"*.

**Diagnosis (still valid, still unfixed):**

- [`RemoveBot`](lua/tttbots2/lib/sh_botlib.lua) kicks the first **dead** bot during a round, but **any** bot
  once `TTTBots.Match.IsRoundActive()` is false - i.e. between rounds. The difficulty cull loop above it has
  the same condition.
- Both run under `TTTBots.Lib.UpdateQuota`, on a **1 second** timer.
- Source does not re-target an observer whose target entity is deleted, so the camera stays parked on the
  removed bot's last position. TTT2 re-targets a *human* disconnecting, but a kicked bot gets nothing.
- Note `ttt_bot_quota` defaults to **0** and `UpdateQuota` returns immediately at 0, so this only bites
  when a quota is configured. The difficulty cull lives inside the same function *after* that early
  return, so it is off at the default too even though `quota_cull_difficulty` defaults to 1.

**The reverted attempt**, for the record: an `IsBotBeingSpectated()` helper (scans humans'
`GetObserverTarget()`) used to skip watched bots in `RemoveBot` and in the cull loop, plus a
`PlayerDisconnected` hook that put the viewer into `OBS_MODE_ROAMING` when a watched bot was removed.
It was written, validated, then removed at the user's request; `sh_botlib.lua` is back to 1452 lines with
no trace of it (verified by grep for `IsBotBeingSpectated|RescueSpectators|OBS_MODE_ROAMING` -> 0 hits).
If this comes back, the mechanism is still in the code and needs handling somewhere - either here or
upstream in TTT2.

---

## 5. Deliberately left alone

- The repo-wide GLuaLint findings, re-run at the end of this session over all **119 files: 177 reporting lines
  over 68 files**, every one of them pre-existing style and hygiene (unused locals, unnecessary parentheses,
  mixed quotes, trailing whitespace, shadowed names, four "double if"s, four empty `elseif`s, eight `GetConVar`
  deprecations, and scope-depth warnings in `cl_scoreboard.lua`). None are from this session's code, and the
  scoreboard ones are structural refactors rather than lint tidy-ups. What the per-kind breakdown found, and the
  two silent-failure classes the stock tools miss, are in section 19.
- `CHANGELOG.md` was not touched (its entries are numbered releases).
- The Roider still buys guns it cannot damage anyone with - a wasted credit, not a bug, and special-casing
  one addon in the shop code was judged worse.
- **Open question for the author**: [`cl_scoreboard.lua`](lua/tttbots2/client/cl_scoreboard.lua:313)
  guards the avatar-refresh timer with `if not draw.DrawAvatar then return end`, but `draw.DrawAvatar`
  does not exist anywhere in the `../TTT2-master` snapshot - TTT2 has `draw.CacheAvatar` and
  `draw.DropCacheAvatar`, which is what line 319 then calls *unguarded*. So either the installed TTT2
  is newer than the snapshot and the guard is correct, or the guard should be `draw.CacheAvatar` and
  the refresh has been silently disabled (and line 319 would error if the cache function really were
  missing). `glua-check` flags it as a note precisely because of that guard.
- `Psychopath`, `Bandit` and `Doctor` mirror `isPolicingRole` as `AppearsPolice`, so bots hold 30% of the
  suspicion they otherwise would against them and `Match.CallKOS` refuses to call KOS. That is the role's
  disguise; flipping it is one `SetAppearsPolice(true)` line per file.

---

## 7. Grenades and Super Soda

Two behaviors in [`behaviors/`](lua/tttbots2/behaviors/), wired into `PriorityNodes` in
[`sv_tree.lua`](lua/tttbots2/lib/sv_tree.lua): `ThrowGrenade` last in `FightBack` (so it only runs once
shooting is not an option) and `DrinkSoda` in `Restore`. Cvars `ttt_bot_throw_nades` and `ttt_bot_use_soda`,
both defaulting to 1.

### Grenades - [`throwgrenade.lua`](lua/tttbots2/behaviors/throwgrenade.lua)

The mechanic that decides the whole design, from TTT2's `weapon_tttbasegrenade`: `PrimaryAttack` only **pulls
the pin**, and `Think` throws the grenade the moment `IN_ATTACK` is **released**. Hold the button instead and
the 5 s `detonate_timer` runs out and it goes off in the holder's face (`BlowInFace`). So a bot's gesture is
"hold ~0.5 s (`PIN_HOLD`), release", and the behavior never holds longer than that plus a tick - the same
press-and-release a player performs, driven through the existing `StartAttack`/`StopAttack`.

It recognises a grenade by `GetPin`/`PullPin` on the weapon rather than by a class list, so a custom grenade
built on the same base gets the same treatment and a radio or C4 in slot 4 is left alone. Target rules: the
spot is `attackTarget`'s position, 250-1100 units away, and that target must be **out of sight**; a lethal
grenade also requires that no teammate stands within 250 units of the spot, and a harmless one (smoke, conf)
that the enemy is at least 450 units off. Anything not in the small harmless list is treated as lethal, which
is the safe way round.

The node sits **before** `AttackTarget` inside `FightBack`, not after it. `Attack.ValidateTarget` does not
check visibility, so an enemy that broke line of sight stays a valid attack target - the bot walks at their
last known position - and a grenade node behind it would never get a turn. It is the grenade's own `Visible`
check that keeps it out of gunfights.

The three TTT2 grenades were also added to
[`data/sv_default_buyables.lua`](lua/tttbots2/data/sv_default_buyables.lua) - `Priority = 0`, below every
weapon, each gated on a personality. Without that a bot would almost never be holding one and the behavior
would be dead code.

### Super Soda - [`drinksoda.lua`](lua/tttbots2/behaviors/drinksoda.lua)

The trap: the addon triggers its pickup from a **server-side `KeyPress` hook** (+use while looking at the
can), and a bot never sends input, so that hook can never fire for one. The only way in is the addon's own
`SUPERSODA:PickupSoda(bot, can)`, which does its own checks anyway (100 units,
`ttt_soda_limit_one_per_player`, single-use cans, `CanPickupWeapon`) and removes the can on success. So the
behavior only has to choose a can (health first while hurt, then armour and the combat buffs; cheapest trip
wins otherwise) and walk the bot within 70 units of it.

Cans are spawned by *replacing* the map's own `item_*` entities, so every can sits where the map already
considered walkable - which is why the behavior needs no reachability analysis of its own. Everything is
behind `SUPERSODA` existing, so the file is inert without the addon.

### Fake Soda - [`placefakesoda.lua`](lua/tttbots2/behaviors/placefakesoda.lua)

The decoy half of the same idea (mexikoedi/ttt2_fake_soda): `weapon_ttt2_fake_soda` is a traitor purchase
holding `ttt2_fake_soda_amount` cans (3 by default), and each can is a Super Soda look-alike that poisons
whoever drinks it - health, armour, credits, speed, damage dealt, fire rate or jump height, depending on which
of the seven it is. Two things about the weapon decide the whole design:

- **The mode is the trick.** It starts in *throw* mode and pressing reload toggles it to *place* mode. Placing
  traces 100 units along the **aim vector** and only accepts a mostly-horizontal surface
  (`HitNormal.z >= 0.5`). So the bot toggles the mode itself (calling the weapon's own `Reload`, which is the
  same toggle a player gets), stands inside that trace, actually faces the spot (aim dot >= 0.97) and presses
  attack once. `PLACE_RANGE` is 60 for that reason: the eye is about 64 units up, so a spot 60 units away is
  already ~88 units from the trace's start.
- **Where it goes is the point**, and it is the human instinct that a can is worth drinking where cans are.
  `FindSpot` tries the spot the bot just drank a real can from (recorded by the drink behaviour in
  `bot.sodaDrankPos`, good for 60 s - the addon removes the real can on pickup, so the spot is free) and then
  the space beside a real can that is still standing, trying four 48-unit offsets so the decoy lands *next to*
  that can rather than inside it. Both candidates are traced for a surface, and refused if a can is already
  within 28 units of them.

The node is the last entry in `_prior.Restore`, deliberately **after** `DrinkSoda`: drinking a real can is what
tells this behaviour where a decoy belongs. It pauses the inventory's auto-switch while the decoy is in hand
(the Jihad bomb's reason - the weapon has to stay out), waits a tick after pressing attack and confirms
`Clip1` went down, and gives up after 20 s rather than spending the round walking to a can it cannot reach.
`ttt_bot_place_fake_soda` gates it, and the buyable in
[`sv_buyables_expanded.lua`](lua/tttbots2/data/sv_buyables_expanded.lua) only lets a bot pay for the item while
the map has a can to hide it beside.

Bots are not caught by the decoys themselves: `DrinkSoda` looks for `ents.FindByClass("soda_*")` and the
addon's cans are `ent_ttt2_fake_soda_*`, so nothing marks them as a can a bot would walk to. The decoy is
therefore purely a trap for players, which is what it is for.

### Boom Body - a fake corpse, used as soon as it is bought

[`boombody.lua`](lua/tttbots2/behaviors/boombody.lua) covers TTT-2/ttt2-wep_boom_body: `weapon_ttt_boom_body`
fires **once**, and what it leaves behind is a corpse of a **random player**, created by `CORPSE.Create`
wherever that addon decides to put it. The bot cannot aim it or choose the spot. The trap is in the corpse -
`TTTCanSearchCorpse` refuses the search and detonates the body instead (160 units, 350 damage, credited to the
owner, chalk outline and scorch mark left behind) - and the weapon removes itself from the inventory when it
fires, so possession *is* the signal: the behaviour presses attack once, confirms the weapon is gone, and is
finished.

So the only real decision is when, and the answer is "while the round is young" - `SETUP_WINDOW` is 150 seconds,
because a fake corpse earns its keep while people are still searching bodies rather than shooting each other.
It sits in the traitor tree right after `PlantBomb` (the same kind of set-up job) and refuses to run with an
`attackTarget`, since firing it means holding a bundle of C4 instead of a gun for a moment.
`ttt_bot_use_boom_body` gates it, and the buyable (side purchase, `Priority = 0`, `RandomChance = 2`) only
exists while the addon does.

**The owner and its own trap:** the addon does tell the owner about their boom bodies - marker vision, plus the
chance to pick the weapon back up with a covert search - so
[`InvestigateCorpse.IsOurBoomBody`](lua/tttbots2/behaviors/investigatecorpse.lua:56) skips our *own* traps.
Walking to one and searching it would blow a bot up with its own item. Everybody else is told nothing, which is
the whole point of the item, so no bot is given `rag.isBoomBody` for a body it did not set itself.

### Thomas the Tank Engine - the aim *is* the whole decision

[`thomas.lua`](lua/tttbots2/behaviors/thomas.lua) covers adigram/ttt_adithomas (`ttt_thomas_swep`). Reading it
first mattered, because the weapon chooses nothing at all: firing it drops a train 200 units in front of the
shooter facing wherever they were looking, removes the weapon from the inventory, and that is the end of the
shooter's involvement. The train then drives straight ahead at `ttt_thomas_speed` (350 u/s) for
`ttt_thomas_explode_time` (15 s) in **MOVETYPE_NOCLIP** - through walls - killing any alive player it touches
for 1,000 damage credited to the shooter, and exploding for `ttt_thomas_explode_radius` (512 units) at the end
of it. The addon's own rails are that the shooter cannot be hit by the train, and that a Detective who touches
it stops it and survives.

So the launch is the entire integration, and it falls out of how the thing kills:

- **Aim at a remembered enemy position**, the nearest one, inside the train's reach of about 5,000 units (350
  u/s for 15 seconds). Through a wall is fine - that is what makes the item worth a credit.
- **Never at our own feet** (`MIN_FIRE_DIST` 600): the blast is 512 units and nothing stops the train but a
  detective, so a target standing next to the bot is a target the bot is inside the blast of.
- **Never down a line with a teammate on it.** The train kills *any* alive player it touches, the shooter's own
  team included, so `HasAllyOnTheLine` tests the first 1,500 units of the line and refuses if an ally is within
  200 units of it.

It declines to run while the bot has an `attackTarget` - a firefight is over long before a train arrives, and the
launch means holding a pistol model instead of a gun. That also makes the behaviour's moment: when a target's
trail goes cold and `attackTarget` is dropped, the remembered position is exactly what it fires at.
`ttt_bot_use_thomas` gates it, the buyable is a side purchase, and it is deliberately **not** a
`PrimaryWeapon` - the weapon removes itself when it fires, so a bot should never be holding it instead of a gun.

### Minethrower - throw one at somebody, or leave one in a doorway and go

[`minethrower.lua`](lua/tttbots2/behaviors/minethrower.lua) covers mexikoedi/ttt_ttt2_minethrower
(`weapon_ttt_ttt2_minethrower`), a two-shot launcher for stock HL2 hopper mines. Its two buttons differ only in
force: primary throws a mine with a **7,000 unit force** applied to its physics object, secondary drops one 30
units in front of the player with a bare nudge. Both spawn it at `EyePos + aim * 30` facing the eye angles, and
the addon's `EntityTakeDamage` hook rewrites whatever the mine kills to whoever placed it.

The part that decides the design: **a hopper mine does not check teams**, and the addon does nothing to change
that, so its own owner is exactly as valid a target as anybody else. Both branches are built around that.

- **Throw** at an enemy the bot remembers but cannot shoot at - inside `MAX_THROW_DIST` (3,000 units) and never
  closer than `MIN_THROW_DIST` (300), because the mine arms where it lands. The bot stands still, aims (aim dot
  >= 0.97 - the mine leaves along the aim vector), presses once, and confirms `Clip1` went down.
- **Place** only from a doorway the bot is standing in, not walking out of, and with no ally within 400 units of
  the spot - and then **walk 500 units away before the behaviour ends**. The place button drops the mine 30 units
  in front of the bot, so the bot has to be there while it arms and then not be: that walk-away phase is not
  polish, it is the only thing between a trapper bot and its own mine. `IsInChokepoint` is two chest-height
  traces looking for walls within 120 units on both sides.

It lives in `_prior.Restore` rather than the traitor tree because the addon sells the weapon to **both** the
detective and the traitor (`SWEP.CanBuy = { ROLE_DETECTIVE, ROLE_TRAITOR }`) and both of those trees reach that
group. The buyable mirrors it (`Roles = { "traitor", "detective" }`), `ttt_bot_use_minethrower` gates the
behaviour, and it is deliberately not a `PrimaryWeapon`: `Primary.Ammo` is "none", so once the two mines are
spent the weapon is a brick a bot must not be holding instead of a gun.

**Known limitation, left on purpose:** a bot can still wander back onto a mine it placed earlier, since nothing
in the pathing knows about hazards. Teaching bots to shoot *enemy* mines would fix that and more, but it runs
into the same fairness question as the fake soda decoy - falling for a trap is what the item is for, and only
the placer's own mine is knowledge a player would legitimately have.

---

## 9. Melee bots run their targets down

The Shanker's stalk has always sprinted while it closes, for the reason written in its own comment: at walking
pace the bot matches the speed of anybody walking away from it and can never close, which leaves the knife -
the entire role - unusable. Every other melee weapon had the same problem and no such behaviour: the Roider's
crowbar above all, since that role cannot damage anybody with anything else.

[`Attack.ShouldRunToCatch`](lua/tttbots2/behaviors/attacktarget.lua:196) is that rule, expressed once for any
weapon that only works at arm's length (melee, or short range like the arsonist's thrower), and applied where
the closing actually happens rather than in a role's behaviour:

- `Attack.Seek` — while the trail is warm (`secsSince <= 4`), so a bot that lost sight of its target still
  runs it down; and explicitly *not* on the cold branch, or it would sprint across the map on a wander goal.
- `Attack.Engage` — the melee branch's approach (`distToTarget > 160`) runs; the in-range branch stops
  sprinting, stands up and swings.
- `Attack.OnEnd` hands the sprint back with the rest of the fight state, because `SetSprint` is a latch on
  the locomotor: without that a bot keeps running while it patrols. `ResetLifeState` covers a bot that dies
  mid-chase.

---

## 10. Bots finish their walk now (wander goals + the popularity map)

Reported: on big maps bots "get lost" - they cannot find each other, or walk long routes to meet up. Both
changes are in [`behaviors/wander.lua`](lua/tttbots2/behaviors/wander.lua), which is the only behaviour that
sends a bot somewhere when it has nothing else to do.

### The deadline was the whole problem

`UpdateWanderGoal` set `timeEndFar = time + math.random(6, 24)`, and `Wander.HasExpired` ends the behaviour the
moment that passes. On a large map a route takes far longer than 24 seconds, so **no bot ever finished a
walk**: it dropped the goal a third of the way there, rolled a new one, and repeated. That is what "lost" looked
like - not a failure to path, but a failure to ever commit to a route.

- The deadline is now the destination's own walking time (`distance / 350 * 1.6 + slack`, capped at 90 s).
- `HasExpired` extends the deadline by 8 s every time the bot sets a new *closest* approach. It tracks the best
  distance so far, so a bot wedged against geometry never earns an extension; the 90 s ceiling stops one
  destination from owning the round.
- `HasExpired` is nil-safe now too - a wander with no destination returns true rather than erroring on
  `Distance(nil)`.

### Everyone gets the popularity map

[`sv_popularnavs.lua`](lua/tttbots2/lib/sv_popularnavs.lua) has always re-sorted where players actually stand
once a second, and nothing read it except the `loner`/`lovescrowds` traits. `Wander.GetPopularAreaNear` now
takes the **most popular nav area within 2500 units** (at most the top 200 ranks), and the plain random-area
fallback only happens when that finds nothing or its 50% roll fails. Bots converge because they drift towards
the same few busy places - the way a player heads for the middle of the map - not because they know where each
other are.

Deliberately not done: no shared knowledge of player positions (that is information a player does not have),
and the 20%-anywhere-on-the-navmesh pick in `GetAnyRandomNav` is untouched now that a cross-map trip can
actually be walked to its end.

Left open if big maps still strand bots: a *Regroup* behaviour that deliberately sends an idle bot to a
popular area with a long deadline, a coordinator job that sends two lonely bots to the same place, and the
path-failure half - `cantReachGoal` has no fallback waypoint, and the "path is too far" branch at
`sv_locomotor.lua:1037` falls through to a fresh path request instead of returning "pathing currently", which
can spend the shared pathfinding budget every tick.

### Sniper and hiding spots - who actually uses them, and how the sniper half now picks one

Asked whether bots use the sniper and hiding spots. The answer is "both, but only through `Wander`, and not as
firing positions". Kept because the findings are non-obvious and the numbers are easy to get wrong:

- **Where they come from.** `TTTBots.Spots.CacheAllSpots` runs once at init and collects every nav area's
  exposed and hiding spot vectors; `CacheSpecialSpots` filters that into four categories by tracing 16 rays out
  of each spot: `hiding` (<= 41% visible inside 256 units), `sniper` (>= 60% visible inside 512),
  `sniperExclusionary` (>= 5 nearby navs that cannot see it) and `bomb` (the hiding rule, its own list). Each
  category prints its size at load, so the console already reports what a map produced.
- **Who reads them.** `Wander.FindSpotFor` is the only sniper-spot consumer, and the only hiding-spot consumer
  besides `Decrowd.FindRetreatSpot` (a random hide spot with <= 1 witness, 5 tries) and `PlantBomb.FindPlantSpot`
  (the `bomb` list). `GetNearestSpotOfCategory` returns the *nearest* spot and never a good one, and it used to be
  the only accessor any behaviour used. Since the fix below, the sniper half of `FindSpotFor` goes through
  `Wander.GetSniperSpotNear` instead, so the nearest-of-category answer survives there only as the fallback.
- **The plan half is dead code.** `NEAREST_HIDINGSPOT`, `FARTHEST_HIDINGSPOT`, `NEAREST_SNIPERSPOT` and
  `FARTHEST_SNIPERSPOT` are declared in `sv_plans.lua` and wired into `PlanCoordinator`'s `targetHashTable`, but
  **no preset in `sv_planpresets.lua` asks for any of them** - those only asked for `ANY_BOMBSPOT`,
  `RAND_UNPOPULAR_AREA`, `NEAREST_ENEMY`, `RAND_POLICE` and `RAND_FRIENDLY_HUMAN`. So `CalcNearestSnipeSpot`,
  `CalcFarthestSniperSpot` and both hiding equivalents were unreachable, and `GetBestSniperSpots` - the
  sniper-intersect-`sniperExclusionary` list, cached - existed only to feed two of them. `POPULAR_SNIPERSPOT` is
  now asked for by the medium and average presets (below), and `CalcNearestSnipeSpot` survives as that
  calculator's fallback, so both are live; `FARTHEST_SNIPERSPOT` and the hiding pair are still unused.
- **The odds.** `FindSpotFor` rolls 10% per flag and then a 1-in-3 gate, and resolves the category as
  `(canHide and "hiding") or "sniper"` - hiding always beats sniping. With `canHide` defaulting **false** and
  `canSnipe` **true** in `sv_roledata.lua`, the sniper bucket is the whole traitor family plus every role that
  sets neither flag (~3.3% of wander destinations, 33% with the `sniper` or `camper` trait), and the hiding
  bucket is the roles that called `SetCanHide(true)` (~6.3%, 33% with a hider trait). Bodyguard, Roider, Fuse,
  Defector, Hidden and Swapper take neither.
- **What "using a spot" means.** Walk to `spot + 64 up`, then stand there until the close deadline (3-12 s,
  x1.5 at a spot); a spot already within 100 units is "close enough" instantly, so the bot simply stands where it
  is. Nothing makes it hold the position or scan from it - combat only takes over if it gains a target by itself.

**What was done about it, in two parts:**

- **`Wander.FindSpotFor` now takes the sniper half from the good list.** New
  [`Wander.GetSniperSpotNear()`](lua/tttbots2/behaviors/wander.lua:234) scans `GetBestSniperSpots()` for the
  nearest perch inside `SNIPER_SEEK_RADIUS` (2500, in `wander.lua`) and returns nil when there is none, in which
  case the old `GetNearestSpotOfCategory` answer is used - so a map without perches behaves exactly as it did
  before. The scan is deliberately **uncapped**: the list is not ordered by anything a bot cares about, so
  stopping early would sample an arbitrary subset rather than the nearest perches, and it already sits behind the
  same two rolls (1-in-10, then 1-in-`CHANCE_TO_HIDE_IF_TRAIT`) that gate every spot destination. The hiding
  half is untouched on purpose: a hiding spot is picked for what it hides, and the nearest one is already the
  right answer.
- **A perch target with a reason, and a caller for it.** New `POPULAR_SNIPERSPOT`
  ([`CalcPopularSniperSpot()`](lua/tttbots2/lib/sv_plancoordinator.lua:215)) takes the nearest perch to the
  busiest place on the map, walking down the popularity ranking until one resolves (at most
  `PERCH_ANCHOR_COUNT` anchors, inside `PERCH_ANCHOR_RADIUS`), and falls back to the nearest perch when the
  popularity map has nothing in it yet. It exists because the perch lists answer a question nobody asked: a spot
  passes the two spot tests with no relationship to where the round goes, so the nearest perch can be a good angle
  on a room nobody enters. Anchoring to `sv_popularnavs.lua` is the same honest input section 10 and section 16
  already use - where people *have been*, not where they are.
- **Both presets got a `DEFEND` job on it.** `Chance` 30, `MaxAssigned` 1, 20-45 s, `MinTraitors` 2 and 3, placed
  **before** the `ATTACKANY` job in [`sv_planpresets.lua`](lua/tttbots2/data/sv_planpresets.lua:1), because
  [`GetNextJob`](lua/tttbots2/lib/sv_plancoordinator.lua:51) takes the first job that passes and `ATTACKANY`
  accepts everybody. One traitor takes an angle while the rest go hunting. `FollowPlan` sits above `Patrol` in the
  traitor tree ([`sv_tree.lua:88`](lua/tttbots2/lib/sv_tree.lua:88)), so the job owns exactly the idle ticks that
  used to become a wander destination - a fight, a corpse or a restore still preempts it. The low-player-count
  preset is left alone: with 1-4 players a traitor parked on a perch is a traitor not hunting.

**Two defects were fixed with the second part, because they made that route unsafe to switch on:**

- [`ACT_RUNNING_HASH`](lua/tttbots2/behaviors/followplan.lua:167) for `DEFEND` and `ROAM` called
  `SetGoal(job.TargetObj)` with no nil check, and [`SetGoal(nil)`](lua/tttbots2/components/sv_locomotor.lua:336)
  is not an error - it clears the goal. A map with no sniper perch would therefore have parked the bot in silence
  for the job's whole duration. Both handlers now return `STATUS.FAILURE` on a nil target, and both
  [`ACT_VALIDATION_HASH`](lua/tttbots2/behaviors/followplan.lua:60) entries refuse the job too, so the bot falls
  through to the next job in the plan instead of holding one it can only stand still for.

**`FARTHEST_SNIPERSPOT` was considered and deliberately skipped**, and the reasoning is worth keeping because it
is the only one of the four spot targets still dead. It would be about ten lines, and it would be the worst of
the four: it is a straight-line maximum, so it is uncorrelated with where anybody is *and* the most likely spot
on the map to have no route to it - on a big map the winner is often across a gap that cannot be crossed. That
matters here because `DEFEND` has no path-failure recovery: the `cantReachGoal` handling section 12 describes is
a `Wander` property, so a job pointed at an unreachable far perch would spend its whole 20-45 s walking into
geometry. "Go far away" is also already covered, and better, by `RAND_UNPOPULAR_AREA`,
[`Wander.GetDistantPopularArea`](lua/tttbots2/behaviors/wander.lua:332) and
[`Decrowd.FindRetreatSpot`](lua/tttbots2/behaviors/decrowd.lua:116) - none of which need the destination to be a
sniper perch. If the goal is ever *two* traitors on two angles, the cheap version is a second `DEFEND` job on
`POPULAR_SNIPERSPOT` with a higher `MinTraitors`, not the extremum.

**Also left as they were:** both hiding targets (nothing asks for them - `CalcBombSpot` already covers the hiding
category's real job), `ACTIONS.ROAM` and `ACTIONS.DEFUSE`, and the "hold the position and re-pick it" work:
`DEFEND` still only walks to the spot and stands, so a coordinated traitor takes an angle without holding it.
That last one is the deliberate fourth option from the discussion, not an oversight - it is the change that would
want live server testing. Worth knowing while testing: a `DEFEND` job's `TargetObj` is resolved once, at
assignment, so the perch is fixed for the job's duration and a bot does not re-pick if the fight moves away.

**Verification:** `node tools/glua-check/check.js` -> 119 files, 0 issues, 2 notes (both pre-existing).
GluaLint is clean on `wander.lua` and `sv_planpresets.lua`. Everything else it reports is pre-existing and
outside the new code: `sv_plans.lua` one (unused `reason`, line 136), `sv_plancoordinator.lua` eight - the two
`closestDist` locals at 187/196, the two `farthestDist` locals, `PLANSTATES`, `conditions` and the two
parenthesis warnings in `CalcBombSpot` - and `followplan.lua` two (`:289` unnecessary parentheses, `:291` unused
`chatter`), both in the untouched `PlayerSay` hook at the end of that file. The new
[`CalcPopularSniperSpot`](lua/tttbots2/lib/sv_plancoordinator.lua:215) draws no warning: it uses both of the
values `getClosestVec` returns, which is the mistake the neighbouring calculators were left with.

---

## 11. Aim that reads as an aimbot (leads, and the traitor accuracy cheat)

Reported: traitors look like an aimlock, and a bot that is shot by somebody it cannot see "locks towards the
aim source directly as if it could see through multiple floors/walls".

### The lead look was the real problem

Two places handed a bot the *exact, live* position of somebody it had no business knowing about, and both fed
`LookAt` - which the locomotor interpolates towards over the following ticks, so the bot visibly turns onto that
point and tracks it:

- [`sv_morality.lua`](lua/tttbots2/components/sv_morality.lua:710) - the damage handler did
  `loco:LookAt(attacker:GetPos(), 1)` on any unseen hit: the shooter's exact position, through any amount of
  geometry, for a full second.
- [`Attack.Seek`](lua/tttbots2/behaviors/attacktarget.lua:53) - a bot chasing a *lead* (the gunshot that hit
  it, a footstep, a body dropping) looked straight at the recorded point and kept looking at it all the way
  there.

Both now go through the new [`Lib.GetInferredLookPos`](lua/tttbots2/lib/sh_botlib.lua:335): a lead becomes a
patch of ground (180 units across, 48 up) with its offset re-rolled about once a second, so the bot sweeps the
area the way a player peeks around looking for the shooter. **Sight bypasses it entirely** - with eyes on the
target the bot looks exactly at them - so this only changes how a bot searches for somebody it cannot see. The
path *goal* is still the exact lead, so bots still walk to the right place; they just no longer track a body
through a wall on the way.

### The accuracy cheat is no longer absolute

`Attack.CalculateInaccuracy` multiplied a traitor's spread by 0.5 while `ttt_bot_cheat_traitor_accuracy` was on
- half the wander of every other bot, which at range is a bot that does not miss a still target. It is 0.7 now:
30% tighter than everyone else, still visibly the best shooter in the round. The cvar description says that
instead of promising "double the accuracy".

Deliberately left alone: `ttt_bot_cheat_traitor_reactionspd` (half the reaction delay) and `ttt_bot_flicking`
(the 5x look-speed burst when a target is first acquired). Both are documented difficulty features that apply to
the whole fight rather than to somebody the bot cannot see, and they are the dials to reach for if traitors
still feel too sharp.

---

## 12. Reacting to being shot at, and two stalls

Reported together: bots ignore bullets passing right by them until something actually hits; bots sometimes stand
still after hearing a noise; and a revived bot should say who killed it.

### Near misses now make a fight-starting bot fight back

The whiz-by detector already existed in the `EntityFireBullets` hook in
[`sv_morality.lua`](lua/tttbots2/components/sv_morality.lua:614), with a 150 unit corridor around the bullet's
path - but it only recorded `lastGunfirePos` (so Decrowd could step out of the line), added pressure, and
glanced at the closest point on that path. A bot could be shot at all day and only ever flinch.

A round passing that close tells the bot where it came from, which is what a player gets from the crack and the
muzzle flash, so a bot that starts fights now treats it as being shot at: it takes the lead and goes looking. Two
things keep it honest, and both mirror the damage handler: identity stays behind `ttt_bot_cheat_know_shooter`
**and** the role's `GetStartsFights` - so innocents and defensive roles still only flinch and glance - and the
lead is a patch of ground (`Lib.GetInferredLookPos`) rather than the shooter's position. The reaction is on a
0.75 s cooldown because the hook runs per bullet: a burst should be one reaction, not thirty.

### "AFK after hearing a sound" was a real stall

[`InvestigateNoise.OnRunning`](lua/tttbots2/behaviors/investigatenoise.lua:71) walks to a remembered noise and
re-issued the same goal every tick from a sound entry that stays in memory for seconds. Nothing ever reported
arrival, so the bot reached the spot and then stood staring at it until the sound was culled - the symptom
exactly. It now returns SUCCESS within 120 units: it went, and there was nothing to see.

### ...and an unreachable goal used to strand the bot

`BotLocomotor.cantReachGoal` is set when a path comes back impossible, and it was **read by nothing at all**.
With section 10's destination-scaled deadlines that became up to 90 seconds of standing beside a destination the
bot can never reach. [`Wander.OnRunning`](lua/tttbots2/behaviors/wander.lua:47) now fails on it so the tree picks
somewhere else, and for the next 20 seconds keeps the new destination inside the region the bot is actually
standing in instead of rolling the dice on the far side of the map again. This is also the likely explanation
for "AFK after killing someone": the end of a fight is exactly when Wander picks its next destination.

### Revived bots say who killed them

[`BotMorality:OnRevived`](lua/tttbots2/components/sv_morality.lua:341) already re-applied the grudge, fed the
killer's position to memory and re-targeted them. It now announces it too: a `RevivedBy` chatter line naming the
killer (new category, EN and FR) plus `Match.CallKOS`, which informs every bot in the match and is capped by
`ttt_bot_kos_limit` and refused against roles that look like police. Gated on `Match.IsRoundActive()`, because
the post-round deathmatch respawns bots that died, and nobody wants "X killed me!" on every respawn.

**Bug found later (reported):** "revived innocents from special roles don't call out the killer." The chatter
line and the KOS call both sat *inside* `if TTTBots.Lib.IsPlayerAlive(attacker)`, so a bot revived after the
fight was over said nothing at all - and that is the normal case for a defibrillator, since by the time anybody
is standing over a body, whoever made it is usually dead too. Knowing who killed you does not depend on them
still being up, so the `RevivedBy` line now runs whenever the bot comes back during a round, and only the
*pursuit* stays behind the alive check (memory position, attack target, `CallKOS`) - a KOS spends one of the few
calls a bot has for the round, so spending it on somebody already dead would waste it.

---

## 8. Fixed: "Tried to use a NULL entity!" out of the barrel cache

**Report:** `behaviors/attacktarget.lua:326: Tried to use a NULL entity!` (x2), raised from the tick pcall at
`sh_tttbots2.lua:136`.

**Cause:** `Attack.TargetNextToBarrel` caches the barrel it finds **on the target player**
(`target.lastBarrel`) and serves that cache for up to three seconds without looking at it again. A barrel is
the one prop in the game that is designed to stop existing in the middle of a fight, and a removed entity is
not `nil` - it is the NULL entity, which is **truthy** in Lua. So this guard

```lua
local barrel = Attack.TargetNextToBarrel(bot, target)
if barrel and target:VisibleVec(barrel:GetPos()) then
```

passed for a destroyed barrel and threw on the first method call. It printed twice because two bots were
engaging the same target: shoot a barrel next to somebody and up to three more seconds of bots keep reaching
for it.

**Fix, in two places:**

1. `TargetNextToBarrel` re-validates what it serves - `IsValid(targetBarrel)` *and* the age check - so a
   destroyed barrel forces an immediate rescan instead of being trusted until the timer runs out. The cache
   stays, because `lib.GetClosestBarrel` is a 128-unit `ents.FindInSphere` per bot per tick and the validity
   check is O(1).
2. `Engage` guards with `IsValid(barrel)` rather than `barrel`, which is the local immunity at the use site.

**The lesson, because this will recur:** once an entity has existed, it never becomes `nil` - it becomes NULL,
which passes every truthiness test. Every *cached* entity needs an `IsValid` when it is read back, and any
guard sitting in front of an entity method call should be `IsValid`, not `if x`. A sweep of the addon for
`if <name> and <name>:...` found the remaining hits are Vectors (`knownPos` in `sv_inventory.lua`,
`gunfirePos` in `decrowd.lua`) or ConVars (`convertPharaoh` in `defectordeliver.lua`), none of which can be
NULL. The other entity caches - `sodaTarget`, `corpseTarget`, `targetStation`, `botTargetWeapon` - were
already written with `IsValid`.

---

## 13. Bots leaving the server - the console line was fake

**Report:** a pasted console excerpt with no text:

```
[BOT] deathdiva666: Off to practice. Ciao.
Player [BOT] deathdiva666 left the game (Disconnect by user: Boredom)
Player [BOT] DOOM has joined the game
```

All three lines are the intended "bot gets bored and quits" feature. Nothing here is an error:

| Line | Produced by |
| --- | --- |
| the chat line | a `DisconnectBoredom` category line - [`sh_chats.lua:83`](lua/tttbots2/locale/en/sh_chats.lua:83) holds this one under archetype `Tryhard`, which is also why this bot went first: `Tryhard` traits carry `boredomRate = 2.0` ([`sh_traits.lua:227`](lua/tttbots2/data/sh_traits.lua:227)) |
| the disconnect | [`BotPersonality:DisconnectIfDesired()`](lua/tttbots2/components/sv_personality.lua:222) fires at boredom >= 0.95 (`DISCONNECT_BOREDOM_THRESHOLD`), gated by `ttt_bot_allow_leaving`, and never while a round is active or while dead |
| the replacement | [`VoluntaryDisconnect`](lua/tttbots2/lib/sh_botlib.lua:1221) - it chats, kicks itself 1-3 s later, then asks for a new bot 3-14 s later, but **only when `ttt_bot_quota` is 0**; otherwise the quota system would double-spawn |

**What was actually wrong:** the kick reason. The old line built it as

```lua
bot:Kick(string.format("Disconnect by user: %s", reason or "UNDEFINED"))
```

The console does not invent that wording - it prints `Player X left the game (%s)` around whatever string a
kick carries. So the addon was hand-writing the engine's own voluntary-disconnect prefix and appending an
internal feature name, so the log read as though a human had typed "Boredom" into the pause menu.

**Fix:** the kick now carries `"Disconnect by user."` and nothing else, which is identical to what a client
quitting from the menu produces. The motive is not player-facing text any more; it shows up as
`"Bot quit: Boredom"` only while `ttt_bot_debug_misc` is 1, because that is developer information. The
in-character chatter line above already explains why in a way a player can read. Both strings are locals just
above the function so the two wordings cannot drift apart.

**Fixed in passing:** `VoluntaryDisconnect` used to `return true` - "disconnected successfully" - when the bot
had no chatter component, and it did that *before* setting up the kick. `DisconnectIfDesired` latches
`self.disconnecting` from that return value and never tries again, so a bot without a chatter component could
never leave and would sit at boredom 1.0 for the rest of the map. The chatter lookup now guards only the
chatter call.

**Deliberately not changed:** `ttt_bot_allow_leaving`'s help text
([`sh_cvars.lua:163`](lua/tttbots2/commands/sh_cvars.lua:163)) still promises a replacement "within 30 seconds",
while the code only does that at `quota <= 0`. The code is right (the quota system already adds and removes
bots on its own, so a second path would double-spawn); the help text is the part that lies. Left alone because
the request was scoped to the kick reason.

**Verification:** `node tools/glua-check/check.js` -> 115 files, 0 issues, 2 notes (both pre-existing). GluaLint
on `sh_botlib.lua` reports 13 warnings, all pre-existing and all outside the edited lines - the file is not
lint-clean, and was not before this change either.

---

## 14. "Invalid suspicion reason: ParanoidKiller"

**Report:**

```
[ttt2bots] Invalid suspicion reason: ParanoidKiller
  1. ChangeSuspicion - addons/tttbots2/lua/tttbots2/components/sv_morality.lua:124
  2. readCorpse - addons/tttbots2/lua/tttbots2/roles/paranoid.lua:121
  3. fn - addons/tttbots2/lua/tttbots2/roles/paranoid.lua:147
  4. unknown - lua/ulib/shared/hook.lua:115
```

**What the reason is:** the Paranoid's corpse reveal. A dead Paranoid's glowing body names its killer, and
every living bot that can see it puts suspicion on that name - `ParanoidKiller` at weight 10 (over the KOS
threshold, so the bot acts on it) and `ParanoidLurker` at 5 (a lead only, for whoever is standing over the
body). The reason strings are only ever produced by that one role, which is why no built-in reason is
affected.

**The cause, and why this is a class of bug rather than a typo.** The role registered its weights by writing
straight into the component's table, captured at load:

```lua
local SUSPICIONVALUES = TTTBots.Components.Morality.SUSPICIONVALUES  -- roles/paranoid.lua, at load
SUSPICIONVALUES.ParanoidKiller = 10
```

while the lookup goes through the live component:

```lua
local susValue = self.SUSPICIONVALUES[reason]   -- components/sv_morality.lua, at runtime
```

Those are the same table only as long as the component class survives. It does not always survive:
[`sh_botlib.lua:6`](lua/tttbots2/lib/sh_botlib.lua:6) opens its server block with `TTTBots.Components = {}`
and then re-includes every component file, and `sv_morality.lua` used to *replace* the scale outright
(`SUSPICIONVALUES = { ... }`). So any second load of the shared file - the addon mounted twice, a manual
re-include, or a reload landing between the role files and the first bot creation - builds a brand new scale
holding the built-in reasons and none of the registered ones, while the Paranoid's `Think` hook from the
previous load is still installed and still asking for `ParanoidKiller`. Every built-in reason keeps working,
which is why the addon otherwise looks healthy.

**Fix, in three parts:**

1. `sv_morality.lua` now merges into the existing scale instead of replacing it
   (`BotMorality.SUSPICIONVALUES = BotMorality.SUSPICIONVALUES or {}` plus `table.Merge`), so a re-include
   cannot drop entries a role file put there.
2. New [`BotMorality:RegisterSuspicionReason()`](lua/tttbots2/components/sv_morality.lua:119) is the
   supported way for a role file to add a weight. It resolves the table through the component it is called
   on, so the entry lands wherever `ChangeSuspicion` will look it up.
3. [`roles/paranoid.lua`](lua/tttbots2/roles/paranoid.lua:31) registers through that function and
   re-asserts its two weights inside `readCorpse`, on the exact component instance it is about to use. That
   is the part that actually closes the window: the reader can no longer outlive its own registration. It is
   two table writes a second, and only writes when a weight is missing or different.

**Rule for role files from here on:** never capture a component's lookup table into a file-local at load and
mutate that. Register through a method on the component, and if the lookup happens from a hook that outlives
load, re-assert at the point of use. `roles/paranoid.lua` was the only file doing the capture-and-mutate
thing (checked across `lua/tttbots2/roles/`); the only other class-level table writes are
`TTTBots.Components.Locomotor.commonStuckPositions`/`stuckBots`, which are set by the same file that owns
the class, so they cannot be orphaned this way.

**Verification:** `node tools/glua-check/check.js` -> 115 files, 0 issues, 2 notes (both pre-existing).
GluaLint on `roles/paranoid.lua` is clean. On `sv_morality.lua` it reports 6 warnings, all pre-existing and
none on the edited lines - the oldest is
`local susFinal = ((self:GetSuspicion(target)) + (increase))`, which is now line 146.

---

## 15. RDM had no minimum time

**Report:** "RDM by bots seem to not have a minimum time before they can act on it. Many times when the round
start they instantly proceed to kill someone."

**Cause.** [`timer.Create("TTTBots.Personality.RDM", 2.5, ...)`](lua/tttbots2/components/sv_personality.lua:547)
checked every 2.5 seconds with only two gates: the round is active, and `ttt_bot_rdm` is on. Nothing looked
at how long the round had been running. Boredom and rage, meanwhile, are carried across rounds on purpose -
they are what eventually makes a bot leave the server (section 13) - so a bot that has had a bad run arrives
at the next round already past `RDM_BOREDOM_MIN` / `RDM_RAGE_MIN` (0.7) and the first tick of the round handed
it a victim. Boredom decays at 0.0005/s, so once it is up there it stays up there, and the `rdmer` trait
doubles how fast it climbs (`boredomRate = 2.0`,
[`sh_traits.lua:227`](lua/tttbots2/data/sh_traits.lua:227)).

Two details make the symptom worse than "one bot is cranky":

- The condition is `(chanceTest and isRdmer) or boredom > min or rage > min`. Past either threshold the 20%
  roll is bypassed, so such a bot picks a victim on **every** tick until it has an `attackTarget`.
- The candidate list is [`lib.GetAllWitnessesBasic()`](lua/tttbots2/lib/sh_botlib.lua:369): anybody within
  4000 units who can see the bot. That is a victim across the map rather than someone in the room, so the bot
  sets off hunting immediately - which is what "instantly proceed to kill someone" looks like.

Grudges are not part of this: [`Match.ResetStats`](lua/tttbots2/lib/sh_match.lua:171) already clears
`bot.grudge` between rounds, so the `grudge` preference in the RDM block cannot leak across one.

**Fix.** New cvar `ttt_bot_rdm_delay` (default 30,
[`sh_cvars.lua:173`](lua/tttbots2/commands/sh_cvars.lua:173)) - the minimum age of the round *and* of the
bot's current life before RDM is considered at all:

- `rdmRoundStart` is stamped on `TTTBeginRound` and the timer returns outright until the round is old enough
  ([`sv_personality.lua:557`](lua/tttbots2/components/sv_personality.lua:557)). If the addon was reloaded
  mid-round there is no stamp, so the current time is taken as the start rather than treating a running round
  as an ancient one.
- `bot.rdmAliveSince` is set the first time the timer sees the bot alive and cleared while it is dead
  ([`sv_personality.lua:561`](lua/tttbots2/components/sv_personality.lua:561)), so a late spawn or a revive
  starts its own clock. The round clock alone would leave a bot revived five minutes in free to kill instantly.
  Field documented in [`meta_defs.lua`](lua/tttbots2/meta_defs.lua:141).

Also corrected in passing: `RDM_PCT_CHANCE = 20` was commented "10% chance".

**Deliberately not changed:** the thresholds still bypass the percentage roll, and boredom is still not reset
at round start. Both are the intended flavour of the feature ("bots will be more likely to RDM when (very)
bored"); the delay is what the report asked for. `decayN`
([`sv_personality.lua:142`](lua/tttbots2/components/sv_personality.lua:142)) is dead code - GluaLint flags it
as an unused variable - and was left alone, since it predates this change and is unrelated to it.

**Verification:** `node tools/glua-check/check.js` -> 115 files, 0 issues, 2 notes (both pre-existing).
GluaLint on `sv_personality.lua` reports only that pre-existing `decayN` warning, nothing on the edited lines.

---

## 16. Few bots left: idle stands and circling one area

**Report:** "When there's a few bots left or all the bots are pretty far from each other, they tend to just be
stuck in a idle phase or just going round and round in a specific area."

**Both symptoms are the fallback behaviour being exposed.** With players around, the nodes above Patrol keep
interrupting: targets, noises, corpses, following, the fluff interactions, decrowding, restocking. Once a round
goes quiet every bot falls through to [`_prior.Patrol`](lua/tttbots2/lib/sv_tree.lua:45) = `{Follow, Wander}`,
`Follow` has nobody to follow (`GetFollowTargets` needs someone seen in the last 8 seconds), and **everything
the bot does comes from `Wander`**. Two properties of Wander then produce exactly what was reported:

1. **Circling one area.** [`Wander.GetAnyRandomNav`](lua/tttbots2/behaviors/wander.lua:179) draws 80% of
   destinations from the bot's own navmesh *region*, and a region is a connected island of nav areas
   ([`GetNavRegions`](lua/tttbots2/lib/sh_botlib.lua:698) walks adjacent areas). On a map with several islands
   - a building, a rooftop, a wing - a quiet bot keeps re-drawing goals inside the island it is standing in.
   The popularity branch meant to counter this,
   [`GetPopularAreaNear`](lua/tttbots2/behaviors/wander.lua:257), only searches 2500 units around the bot, so
   it returns nothing precisely in the reported case: the other bots are a map away from everywhere anybody
   has been.
2. **The idle phase.** A wander ended on a clock scaled to the trip, but the *arrival* had no clock of its own:
   [`HasExpired`](lua/tttbots2/behaviors/wander.lua:141) only finished early once `timeEndClose` (3-12 s, x1.5
   at a spot) had passed, so a bot that reached its goal in a few seconds stood there for the rest of an
   allowance sized for a long walk - up to ~18 s at a spot - and the pattern repeats at every destination.
   Standing still is also what the locomotor does at a goal it has already reached, so it reads as idle rather
   than as walking.

The tree runner re-validates the running node every tick
([`IterateNode`](lua/tttbots2/lib/sv_tree.lua:145)), so a node cannot pin a bot once its own `Validate` goes
false. That rules out the behaviours that look like suspects - `Decrowd` never checks for arrival but its
gunfire/crowding test expires on its own, and `Interact` ends with its animation. The long stand was Wander's.

**Fix, both in `wander.lua`:**

- [`Wander.LostContact()`](lua/tttbots2/behaviors/wander.lua:281) - nobody seen for `LOST_CONTACT_WINDOW`
  (20 s). When that is true the destination comes from
  [`Wander.GetDistantPopularArea()`](lua/tttbots2/behaviors/wander.lua:293): one of the busiest few nav areas
  at least `RELOCATE_MIN_DIST` (1500) away, so a quiet bot walks to a place people actually gather instead of
  another patch of empty region. Several quiet bots therefore converge on the same handful of hangouts and
  find each other. This stays honest: the popularity map records where people *have been*
  (sv_popularnavs.lua), not where they are now.
- `ARRIVED_LOITER` (5 s) gives the arrival its own allowance
  ([`wander.lua:158`](lua/tttbots2/behaviors/wander.lua:158)): once the bot is inside `DIST_CLOSE_THRESH` it is
  done 5 s later, whatever the trip allowance allowed, and the counter resets if it is pushed off the goal
  again. A long walk stops also being a long stand.

**Deliberately unchanged:** the 80% in-region bias in `GetAnyRandomNav` (it keeps ordinary wandering local and
avoids long treks), and the 20-second `wanderStayClose` window after an unreachable path - that one still takes
precedence, because a destination that just failed will fail again the same way. The lost-contact branch owns
everything after it, and it is the branch the report was about.

**Verification:** `node tools/glua-check/check.js` -> 115 files, 0 issues, 2 notes (both pre-existing).
GluaLint on `wander.lua` is clean.

---

## 17. Bots getting stuck more often - the ladder fix

**Report:** "I think the fixed ladder movement [...] is messing up with how bots move because they tend to be
stuck more often now."

The suspicion was right, and an earlier change of mine had made a latent problem common. The details are in the
movement register as entry 18; the short version:

**The ladder the bot is on was being identified as "the nearest ladder".** The dismount decision has to
compare the bot's height against the top and bottom of the ladder it is holding, and it asked
`GetClosestLadder()`, which measures to a ladder's **centre** - so a short ladder across the room beats a
tall one the bot is at the top of. Measured against the wrong ladder, the bot "reached the top" halfway up,
pressed use, fell, walked back and climbed again. This was rare before the ladder work only because
`GetAllLadders` used to miss most of a map's ladders: fixing the enumeration is what made the wrong ladder a
frequent candidate. New [`BotLocomotor:GetLadderOn()`](lua/tttbots2/components/sv_locomotor.lua:1456) keeps
only ladders whose span contains the bot's height and then takes the nearest horizontally; both
`ShouldDismountLadder` (1487) and `IsNearEndOfLadder` (1516) use it.

**Verification:** `node tools/glua-check/check.js` -> 114 files, 0 issues, 2 notes (both pre-existing). GluaLint
on `sv_locomotor.lua` reports 12 warnings, all pre-existing and none in the new ladder code.

---

## 19. Whole-tree audit before testing (glua-check + GluaLint + two custom checks)

**Report:** "let's scan the whole lua files for any bugs with the linter and the extensions provided related to
Garry's mod before I go test out the mod."

**The mechanical picture:**

- `node tools/glua-check/check.js` -> **119 files, 0 syntax failures, 0 unknown hooks, 0 API failures, 2 notes**
  (both pre-existing and nil-guarded: `cl_scoreboard.lua:313`, `sh_concommands.lua:182`). Its "hooks called but
  never registered in this tree" list is 6 and every entry is expected: `KeyPress` (`hiddenstalk` simulates the
  key for other addons), `TTTCanSearchCorpse` (we run TTT2's own hook so the Blocker and the Amnesiac see it,
  section 2), and the four extension points `TTTBotsCanAttack`, `TTTBotsRoleRegistered`, `TTTBotsInitialized`
  and `TTT2ModifyDefaultTraitorCredits`.
- GluaLint across every file: **177 reporting lines over 68 files**, all of it the pre-existing style and hygiene
  category - the updated bullet is in section 5. Nothing written this session draws one, apart from the two
  `followplan.lua:289/291` warnings, which sit in the untouched `PlayerSay` hook at the end of that file.

**Two checks the stock tools do not do, and what they caught.** Both are silent-failure classes: a behaviour a
tree asks for but nothing defines, and an `include` that resolves to nothing.

1. **`roles/deputy.lua:15` queued `_bh.Investigate`, which does not exist.** The behaviour nodes are
   `InvestigateCorpse` and `InvestigateNoise`; `Investigate` is a *group* on `PriorityNodes`. Every other role
   file and all three built-in trees use `_prior.Investigate`, so this was a plain typo - and because a nil value
   in a table constructor is dropped rather than kept, it never errored. The deputy was silently the one role in
   the addon with no investigate group at all, so deputies never walked to a corpse or a noise. Fixed to
   `_prior.Investigate`. **The class is the thing to remember: a mistyped node in a tree is invisible.**
2. **The French locale registered the wrong categories, twice over.** `locale/fr/sh_chats.lua` did
   `local ATTACK = ...` and then `RegisterCategory(f("Plan.%s", ATTACKANY), ...)`, and `local IGNORE = ...` and
   then `RegisterCategory(f("Plan.%s", DEFEND), ...)` - copy-paste from the block above in both cases, which is
   exactly why GluaLint listed `ATTACK` and `IGNORE` as unused locals. The effect was that `Plan.Attack` and
   `Plan.Ignore` were never registered in French, so those two lines could never be said, silently:
   [`BotChatter:On`](lua/tttbots2/components/sv_chatter.lua:252) returns false when `GetLocalizedLine` gives nil,
   so there was no error to notice. Both keys are corrected, and the FR `Plan.Ignore` block also carried the
   *defend* sentence, so it now says something meaning "I'll do my own thing this time" to match the English. No
   preset asks for `ATTACK` or `IGNORE`, so the practical impact was nil - a latent gap, not a live fault. A
   French `Plan.Defend` line already existed and is what the new perch job uses, EN and FR both.

**Two apparent findings that are not bugs**, recorded so they are not re-investigated:

- **`include("sv_roledata.lua")` in `sv_roles.lua:13` is the only relative include in the tree**, and a naive
  path check calls it missing (`lua/sv_roledata.lua` does not exist). It is fine: GMod resolves an include
  relative to the calling file when the bare path is not found - which is also why nothing else in the tree loads
  `sv_roledata.lua`, since `sv_roles.lua` is itself included by `includeServer()`. Were that not the case,
  `TTTBots.RoleData` would be nil and every role file would fail at load, which is not what happens.
- **The four `Empty elseif statement` hits in `sv_morality.lua` (179/181/183)** are branches whose bodies are
  commented-out `Say` calls - the suspicion chatter `CallKOS` replaced. Deliberate no-ops. Worth knowing while
  reading them: the thresholds are tested high-to-low, so `sus <= InnocentThresh` is tried before
  `sus <= TrustThresh` and the last branch is unreachable - harmless only because both are empty.

**Verification:** `glua-check` 119 files / 0 issues / 2 notes; GluaLint 177 lines over 68 files with nothing in
the new code. The scratch tools were deleted at the end of the pass: `.roo/` holds only `mcp.json`.

---

## 20. The Hitman stalling on its contract, and a flick caused by two owners of `attackTarget`

**Report:** "It seems like Hitman role is having trouble killing selected targets, primarily those with a
special role. I noticed the bot constantly flicking too, looks like a conflict again with another task."

**Two symptoms, one mechanism.** [`SetAttackTarget`](lua/tttbots2/components/sv_locomotor.lua:1938) is not an
assignment: on any change it calls [`locomotor:OnNewTarget`](lua/tttbots2/components/sv_locomotor.lua:204), which
applies a **5x look-speed burst** and **re-arms `reactionDelay`**, the time the bot must wait out before firing.
So a target that is written, cleared and written again is not free - each cycle is a flick *and* a reset of
time-to-shoot. Two of our own systems owned that slot for a Hitman:

- [`Attack.OnEnd`](lua/tttbots2/behaviors/attacktarget.lua:688) cleared the target **unconditionally**, and
  [`Attack.Validate`](lua/tttbots2/behaviors/attacktarget.lua:27) *is* `ValidateTarget`, which clears on any
  failed check too. `AttackTarget` sits **third** in `FightBack`, behind `ClearBreakables` and `ThrowGrenade`,
  and when an earlier node takes over the runner calls `OnEnd` on the displaced behaviour
  ([`sv_tree.lua:190`](lua/tttbots2/lib/sv_tree.lua:190)). So any tick where the grenade or breakables node
  validated ended the fight and dropped the target.
- [`hunttarget.lua`](lua/tttbots2/behaviors/hunttarget.lua:41) wrote the target **every tick**, whenever the
  current target was not *visible*. A contract the bot is walking towards - behind cover, across the map - is
  exactly that case, so a Hitman re-armed its own acquisition continuously. Every other bot has its target set
  by events (damage, KOS) instead, which is why the symptom was Hitman-shaped.

**Fixes (five files).** The provider now fills an **empty slot only**, keeps refreshing the victim's memory
entry every tick (that is what `Attack.Seek` actually navigates from - moving it below the hold would have made
the trail go cold), and declines a victim it could never hurt. `Attack.OnEnd` clears only when the fight is
genuinely over - target gone, dead, immune, or now an ally, mirroring `ValidateTarget` plus `IsTargetAlly` - so
an interruption by the grenade or breakables node no longer throws the fight away.
[`shinigami.lua`](lua/tttbots2/roles/shinigami.lua:64) carried the same visible-based hold and got the same fix.
Temporary debug logging behind `ttt_bot_debug_misc` prints when a hunt role claims a target, declines one, or
has it cleared by `OnEnd`; **delete it once the loop is confirmed**.

**Special roles: two contract types can never be fulfilled, and that is not fixable from here.**
[`IsAllies`](lua/tttbots2/lib/sv_roles.lua:97) counts the victim's own declarations ("the mode does not
currently support one-sided alliances"), and the Hitman declares
[`alliedTeams = { TEAM_TRAITOR, TEAM_JESTER }`](lua/tttbots2/roles/hitman.lua:6) - so a contract on a **Jester or
Swapper** is refused by `SetAttackTarget` outright, and a **Swapper** is damage-immune as well. The contract
cannot be reassigned from here (it belongs to the Hitman addon), so the provider simply leaves those victims
alone rather than fighting over them all round. Stating the negative as well: `AppearsPolice` - the
Detective/Deputy/Sheriff/Psychopath/Bandit/Doctor disguise - is **not** read anywhere in the attack path, only
by suspicion and `CallKOS`, so policing-looking roles are not gated.

**The provider's premise was wrong, and three comments said otherwise.**
`Player:GetTargetPlayer()`/`SetTargetPlayer()` is TTT2's **spectating** target: documented as "the target a
Player is spectating" ([`sh_player_ext.lua:970`](../TTT2-master/gamemodes/terrortown/gamemode/shared/sh_player_ext.lua:970)),
written by the client-side HUD receiver that follows what the local player is looking at
([`cl_player_ext.lua:169`](../TTT2-master/gamemodes/terrortown/gamemode/client/cl_player_ext.lua:169)) and reset
client-side, and TTT2 **ships no Hitman role at all** (the only "hitman" matches in the snapshot are language
strings). So the contract must be published by the addon the server runs, through an API built for something
else. Corrected in `hitman.lua`, `hunttarget.lua` and `sv_roledata.lua`. **Worth confirming in game before
trusting the provider:** if that addon only calls `SetTargetPlayer` for humans, a Hitman bot never receives a
contract at all and the flicking has a different trigger - the fixes above apply either way, since the loop was
ours.

**Verification:** `glua-check` 119 files / 0 issues / 2 notes (both pre-existing); GluaLint clean on all five
touched files.

---

## 21. The C4 countdown ("53 mins" on a 45-second fuse) - workaround deleted, not fixed

**Report:** "Bomb countdown when planted by bots are acting up again, displaying 53 mins when its actually 45
seconds."

**The fuse is not the bug, and that is provable in three lines of TTT2.** A bot arms through
[`PlantBomb.ArmNearbyBomb`](lua/tttbots2/behaviors/plantbomb.lua:238) with `C4_MINIMUM_TIME or C4_FUSE`, which is
TTT2's own `C4_MINIMUM_TIME` = **45** - the bottom of its own 45..600 clamp. `ENT:Arm` then calls
[`SetDetonateTimer(time)`](../TTT2-master/gamemodes/terrortown/entities/entities/ttt_c4/shared.lua:123), which
stamps `explode_time = CurTime() + time`, and the detonation test is `etime < CurTime()` in the C4's own
[`Think`](../TTT2-master/gamemodes/terrortown/entities/entities/ttt_c4/shared.lua:312) - both sides of it on the
server's clock. Nothing in this addon writes the fuse afterwards, so a bot-planted bomb does go off 45 seconds
after it is armed, exactly as reported.

**So the wrong number is only the display**, which is a client-side subtraction in TTT2: the number on the model
draws `strtime(max(0, GetExplodeTime() - CurTime()), "%02i:%02i")`
([shared.lua:779](../TTT2-master/gamemodes/terrortown/entities/entities/ttt_c4/shared.lua:779)) and the info
panel draws `util.SimpleTime(GetExplodeTime() - CurTime(), "%02i:%02i:%02i")` - **hours, minutes, seconds** - at
[cl_init.lua:377](../TTT2-master/gamemodes/terrortown/entities/entities/ttt_c4/cl_init.lua:377). A remainder of
about 3180 seconds prints there as exactly **`00:53:00`**, which is the "53 mins" that was reported: the reading
is the client's copy of `explode_time` sitting ~52 minutes ahead of its own `CurTime()`.

**`lib/sh_c4timer.lua` was deleted rather than fixed.** It had been added for this same report, on the premise
that a client's `CurTime()` is its own clock and can be permanently offset from the server's. GMod's own
documentation - the wiki data [`tools/glua-check`](tools/glua-check/check.js:1) is built on - says the opposite:
`CurTime` "Returns the uptime of the server... **This is a synchronised value**", returning "Time synced with the
game server", with the only listed caveats being `host_timescale` and a paused server (`sv_pausable`, or all
players disconnecting). The file was therefore **inert on any healthy setup** - its tolerance check skipped the
rewrite precisely because the two clocks agree - and it could never have fixed the case in the report. It also
never caused the symptom, since it only wrote the value TTT2 would have had anyway. TTT2's readout is left alone
now; the comment left in its place is at [`sh_tttbots2.lua:74`](lua/tttbots2/sh_tttbots2.lua:74).

**What is still unknown** (and is not ours to fix, being entirely cosmetic while the fuse keeps time on the
server): whether the client's copy came from a stale network-var baseline (GMod resends entity baselines when an
entity re-enters a client's PVS, which can clobber a client's local value), from the server's clock having
shifted while the bomb was armed, or from the client rendering a bomb armed under unusual conditions. If this
report comes back, **start at the client's copy of `explode_time`, not at the arming path** - the arming path is
provable, and the previous session lost a workaround to investigating it first.

**Verification:** `glua-check` 118 files / 0 issues / 2 notes (the count drops by one with the deleted file);
GluaLint on `sh_tttbots2.lua` reports only its three pre-existing warnings (unused `PathManager`, unused `call`,
and a shadowed `i`).

---

## 22. Dead bots were making gameplay callouts

**Report:** a console paste of dead bots talking, with no other comment:

```
*DEAD* [BOT] duke of hazardous: Maffin is a traitor.
*DEAD* [BOT] Starl1n6: KOS xxxpro420xxx
*DEAD* [BOT] ihavecancer: KOS OutrageousChloe NOW!
*DEAD* [BOT] xxxpro420xxx: kos outrageouschloe
*DEAD* [BOT] Starl1n6: I found a dead body!
```

**Where the lines came from.** They are locale categories, not ad-hoc strings: `CallKOS` (which also holds
`{{player}} is a traitor.`) and `InvestigateCorpse` ("I found a dead body!"). All of them are said through
`BotChatter:On`, and **nothing on that path asked whether the bot was alive** - `CanSayEvent` is only a rate
limit, and the code that produces callouts (`BotMorality:AnnounceIfThreshold`, `InvestigateCorpse.OnStart`,
`FollowPlan`, the tree nodes generally) keeps running for a dead bot, because the behaviour tree has no alive gate
either. So a dead bot could call KOS, name a traitor, report a body, narrate a plan, or answer a life check.

**One gate, at the funnel.** [`BotChatter:On`](lua/tttbots2/components/sv_chatter.lua:200) now refuses anything
from a bot that is not up, with an allowlist for the lines that are *meant* to be said while dead: `SillyChatDead`
(the flavour category written for a spectating bot) and `ServerConnected` (said on a timer after joining), plus
the `Disconnect*` goodbyes matched by prefix, because the reason is part of the name (`"Disconnect" .. reason`)
and a bot that dies before deciding to leave should not exit silently. Everything else - KOS, traitor reveals,
body reports, weapon tells, personal-space warnings, plans, purchases, defuse and bomb callouts, life checks - is
living-only now.

**Three details that mattered:**

1. **The check is the live entity state, not `lib.IsPlayerAlive`.** That cache is rebuilt once a tick, so a bot
   revived on the same tick would still have read as dead and would have lost the `RevivedBy` line it came back
   to say (section 12). The new local `isBotUp` mirrors the cache's definition, live.
2. **The gate sits ahead of the rate limit**, so a refused line does not spend the bot's one chance to say it
   after it is up again.
3. **Dialogs are deliberately untouched.** [`sv_dialog.lua`](lua/tttbots2/lib/sv_dialog.lua:135) calls
   `chatter:Say` directly rather than `On`, and its whole point is that a dialog may be dead-only
   (`template.onlyWhenDead`, enforced by `Dialog.VerifyLifeStates`). Putting the gate in `On` is what leaves that
   alone.

**Checked while in there, and left alone.** The KOS *list* that living bots act on is not fed from this path:
`AnnounceIfThreshold` only says the line, and both `Match.CallKOS` callers already require the caller to be alive
([`sh_match.lua:386`](lua/tttbots2/lib/sh_match.lua:386) for a player's chat command, and `OnRevived` for a bot
that has just come back). So a dead bot's callout was noise in dead chat rather than something living bots could
act on - which is why the report is cosmetic and why the fix is one gate. Two adjacent things are also unchanged
and worth knowing: a dead bot can still take an attack target through `BotMorality:SetAttackIfTargetSus`, and the
behaviour tree is still run for dead bots at all. Both are harmless for a spectator, and both are a bigger change
than this report asked for.

**Verification:** `glua-check` 118 files / 0 issues / 2 notes (both pre-existing); GluaLint clean on
`sv_chatter.lua`.

---

## 23. Two C4s in the same spot

**Report:** "Bots like planting more than 1 c4 in a nearby spot, can you make it where there's a minimum distance
of how many c4 can be in a spot?"

**Why it happened.** [`FindPlantSpot`](lua/tttbots2/behaviors/plantbomb.lua:110) already disqualified any spot
within **512** units of an existing bomb - but it only ever looked at bombs *already in the world*, and 512 units
is small enough that two C4s 600 apart still read as the same corner of the map. So when two traitors had a plant
job at the same time (the average preset assigns up to 2), both bots called `FindPlantSpot` before either had
planted, both saw an empty bomb list, and both took the single best-weighted spot: the weighting is
deterministic, so they agreed exactly. The second bot then planted within `PLANT_RANGE` (80) of the first.

**Two changes, both in `behaviors/plantbomb.lua`:**

1. **Separation raised to `PlantBomb.C4_MIN_SEPARATION` (1024)** - roughly two rooms on a TTT map, and the one
   number to turn if it feels too strict or too loose. The distance is measured to the nearest bomb in the world,
   armed or not.
2. **Spots are reserved before the bomb exists.** `PlantBomb.OnStart` now claims the chosen spot and `OnEnd`
   releases it, and another bot's live claim disqualifies that spot. A claim older than `CLAIM_LIFETIME` (60 s)
   is dropped on sight, which is what cleans up after a bot that died on the way to its spot - no hook needed to
   watch for deaths. This is the half that actually fixes the report: a bomb that does not exist yet pushes
   nobody away.

**A deliberate safety valve.** If *every* candidate is inside the separation distance - a small map, or a second
C4 planted late in the round - the bot takes the roomiest spot rather than failing, so this cannot turn into "the
bot stands at the spot and never plants". Planting far apart still wins where the map allows it, and on a tight
map the two bombs still end up as far apart as that map can manage.

**Also tidied while in there:** `lib.GetAllVisible` (an eye trace per candidate) now runs only for the spots that
survived the disqualifiers, instead of for every spot on the map.

**Verification:** `glua-check` 118 files / 0 issues / 2 notes (both pre-existing); GluaLint clean on
`plantbomb.lua`.

---

## 24. Bots freezing at gunshots (and "seeing through floors")

**Report:** "Bots sometimes like to freeze when they hear gunshots across multiple floors, especially if there's
multiple gunshots. It's as if they can see through floors, can you make them more reactive as in running towards
the source of the sound earlier instead of just staring?"

**The freeze was one branch of `InvestigateNoise.OnRunning`.** It had two: the hidden one walked to the noise
(that is the branch section 12 already fixed), and the **visible** one only looked:

```lua
    local closestVisible = InvestigateNoise.FindClosestSound(bot, true)
    if closestVisible then
        loco:LookAt(closestVisible.pos + Vector(0, 0, 72))
        return STATUS.RUNNING   -- looks, never sets a goal
    end
```

So a bot that could see where the sound came from stood and stared at it. And "seeing through floors" was
literal rather than a metaphor: a gunshot's recorded position is the *shooter's*, and the visibility test is a
trace that passes through a stairwell opening, a railing or a glass/trigger brush - so a shooter one floor up
with a stairwell between them read as a source the bot could see.

**Several shots turned it into a loop.** [`Memory:CullSoundMemory`](lua/tttbots2/components/sv_memory.lua:487)
drops a sound 0.5 s after the bot can see its source within a 75° arc - and a bot staring at the noise is by
definition facing it. So the lead being stared at was deleted from memory, `Validate` (which needs at least one
interesting sound) went false, the node ended, and the next shot started the cycle again. The branch that would
have walked was also behind a random chance plus a mean-time-between, so even a bot that decided to move started
late.

**Three changes, in `behaviors/investigatenoise.lua`:**

1. **Every noise is walked to.** The visible/hidden split is gone from `OnRunning` - `FindClosestSound(bot, true)`
   existed only to feed the look-only branch - so the bot looks at the source *and* sets a goal, with the
   arrival → `SUCCESS` test from section 12 applying to both. Combat still outranks it: `InvestigateNoise` sits
   below `FightBack` in the tree, so a bot that has a target fights instead of sightseeing.
2. **The bot commits to one noise.** `bot.investigateNoiseTarget` is picked once, with the dice roll asked per
   commitment rather than per tick, so several shots cannot take turns as "the closest noise" and flip the goal
   between two positions. `Validate` honours the commitment, because otherwise the memory cull above would end
   the walk half way there. It is dropped on arrival, by `INVESTIGATE_TIMEOUT` (20 s, so an unreachable source
   cannot hold the behaviour all round), and in `OnEnd` when something else takes the bot over.
3. **A fresh gunshot skips the dice roll** (`GUNSHOT_URGENT_WINDOW`, 2 s). A shot means something is happening
   now, and weighing that up with a random chance is what let a bot stand still while a fight carried on a floor
   above it. Walk speed only, deliberately: no sprint, so bots do not charge across the map at every distant
   shot.

**Left for another day** (the fourth part of what was discussed, not taken): `Validate` still only requires the
round to be active, so a dead bot can investigate a noise. Harmless for a spectator, and one line to change.

**Verification:** `glua-check` 118 files / 0 issues / 2 notes (both pre-existing); GluaLint clean on
`investigatenoise.lua`.

---

## 25. Bots deducing a killer (part one, with the rest parked)

**Report:** "bots are a bit dumb when it comes to deducing the killer of someone when they see one walk out
wounded/full hp and a fresh corpse nearby who turns out to be a non-traitor role. What could be done to make the
bot deduce of who's the killer or not?" - with options wanted before any code, and the untaken ones kept on file.

**Two gaps were found first, and together they explain the "dumb" feeling:**

1. **A finished feature was wired to nothing.** `SUSPICIONVALUES` has carried `NearUnidentified = 2` since it
   was written - *"this player is near an unidentified body and hasn't identified it in more than 5 seconds"* -
   and `playersNearBodies` has been counting exactly those seconds, per player, with decay, in a timer that runs
   every second. **Nothing awarded the reason, and nothing read the tracker.**
2. **The only corpse rule we had said the opposite.** The `TTTBodyFound` hook gives the *finder* one of
   `IdentifiedTraitor = -3 / IdentifiedInnocent = -2 / IdentifiedTrusted = -2`, all negative: touching a body
   made a player look trustworthy, always. There was no rule anywhere that made standing over a fresh body
   suspicious at all.

**What was built (options A and C of the list below):**

- **A - the loitering tracker now reports.** When a player passes `NEAR_BODY_SECONDS` (**3**, lowered from 5 at
  the user's request: a round is busy, and a body is either dealt with quickly or walked away from, so three
  seconds catches the person who stopped to look and chose not to identify it) beside an unidentified body,
  every *alive bot that can see that body* gains the existing `NearUnidentified` on them, once per visit
  (`playersNearBodiesReported` guards the repeat, because +2 a second would pin anybody standing still at the
  10-point ceiling; the flag clears when they leave the body, so a second visit is its own offence). The witness
  requirement is deliberate - seeing the body is what makes it knowledge a bot could hold - and what the body
  *contains* plays no part, because nobody has identified it yet, so the reason is role-agnostic by construction.
  [`IsPlayerNearUnfoundCorpse`](lua/tttbots2/components/sv_morality.lua:813) now returns the corpse instead of a
  boolean, which is what lets the caller check that the observing bot can see it.
- **C - a searched body names its killer.** `InvestigateCorpse` already ran `CORPSE.ShowSearch`; it now reads
  TTT2's own recorded trace afterwards and judges the killer the way the witnessed-kill path does. TTT2 records
  `rag.killer_sample.killer` only when its forensics say a trace was left - within `ttt_killer_dna_range` (550)
  and before `ttt_killer_dna_basetime` (100 s) runs out - so **the sample itself is the gate**: a killing from
  further away, or a decayed sample, leaves nothing to read and the code does nothing. Only a search that
  *identifies* the body counts (`CORPSE.GetFound` is checked first), so a bot cannot act on a body somebody else
  already opened. The judgement mirrors the kill path - victim a traitor → `KillTraitor` (-10, good news to a
  traitor), victim police-looking → `KillTrusted` (10), otherwise a new **`CorpseKiller` (8)**, below the
  eyewitness `Kill` (9) because it is a deduction, and above the KOS threshold (7) so it acts on itself. Two
  guards worth naming: a **dead** killer is skipped (nothing to act on, and announcing a KOS against a corpse is
  the mistake section 12 already made once), and a **fool's** corpse returns early, because the Jester and the
  Swapper are *meant* to be killed and whoever obliged them is not a traitor for it.

**Parked options**, kept so they can be picked up without re-deriving them:

- **B - scene suspicion on sight (the reported scenario).** When a bot sees a living non-ally within ~600 units
  of a *fresh* corpse whose victim was not a traitor, award a `SceneSuspect` (~3) with modifiers: wounded
  (≤ 60% hp) +2, gunfire heard at that spot within a few seconds +2, moving away from the body +1, and freshness
  scaling (≤ 5 s doubles it, > 20 s skips). It needs a death stamp per corpse; the cheap route is a parallel
  `Match.CorpseTimes[rag] = CurTime()` filled from the existing `TTTOnCorpseCreated` hook, rather than changing
  the shape of `Match.Corpses` and its four consumers (`Defib`, `paranoid`, `investigatecorpse`, `botlib`). This
  is the option that acts on a body nobody has searched, and it is the largest of them.
- **D - damage-log reasoning.** `Match.DamageLogs` (filled by the `PlayerHurt` hook) already carries
  attacker/victim/damage/health/time, and `Match.WhoShotFirst` queries it. "Who hurt the victim in the last N
  seconds" would cover deaths that leave no sample at all (knife, explosion), but it reads server truth, so it
  needs a witnessing gate to stay fair: the bot heard gunfire within ~1000 units in the last ~5 s, or saw the
  victim alive moments before.
- **E - the honest cheat.** `ttt_bot_cheat_corpse_killer` (default 0): bots know any corpse's killer on sight
  with no search, from `killer_sample` or TTT2's `killerSpec`. Perfectly accurate, crosses the fairness line, and
  belongs beside `cheat_know_shooter` as an opt-in.

**Verification:** `glua-check` 118 files / 0 issues / 2 notes (both pre-existing); GluaLint clean on
`investigatecorpse.lua`, and on `sv_morality.lua` it reports the same six pre-existing warnings as always (the
`susFinal` parentheses, the three empty `elseif`s holding commented-out chatter, the "silly negation" and the
shadowed `i`), now at shifted line numbers.

---

## 26. A sniper perch now needs a weapon that can use one

**Report / question:** "For the sniper spots, how do the bots know what weapon they're holding before considering
it a sniper?" - then: "apply it to both entry points - Wander.FindSpotFor and the plan's perch job
(POPULAR_SNIPERSPOT), so a coordinated traitor with a pistol is not sent to hold an angle either."

**The answer was that they did not look at the weapon at all.** `Wander.FindSpotFor` decided on three things and
nothing else: the role flag `GetCanSnipe()` (which **defaults to true**, so it is the whole traitor family plus
most innocents, minus the eight roles that opt out), the `sniper` personality trait or a 1-in-10 dice roll, then a
1-in-3 gate - and after the rolls, pure geometry. The spot categories are visibility traces (60% visible inside
512 units, plus five or more nearby navs that cannot see back), so "sniper" described the *sightlines*, never a
weapon. A bot holding a pistol, a shotgun or a crowbar would take a perch and stand on it, and the plan route did
the same with a larger audience.

**The classifier existed and had no reader** - the same shape as `NearUnidentified`, `cantReachGoal` and the
popularity tracker before they were wired up: `WeaponInfo` has carried `is_sniper` since it was written
([`sv_inventory.lua:246`](lua/tttbots2/components/sv_inventory.lua:246), inferred from "damage > 40 and not
automatic") and nothing in the tree read it. Its siblings *are* read, which is the pattern for this:
`is_shotgun` / `is_melee` / `is_short_range` are what `Attack.ShouldApproachWith`, `ShouldRunToCatch` and
`ShouldLookAtBody` decide on.

**What was built:**

- New [`TTTBots.Lib.HoldsLongRangeWeapon(bot)`](lua/tttbots2/lib/sh_botlib.lua:253), the shared question both
  entry points now ask. It scans `inventory:GetAllWeaponInfo()` and accepts a weapon that `is_sniper`, is **not**
  `is_shotgun` / `is_melee` / `is_short_range`, and **has ammo** ((`ammo` or `clip`) > 0, the inventory's own
  test). The vetoes matter because `is_sniper` is a damage heuristic - a high-damage pump shotgun satisfies
  "damage > 40 and not automatic" as well. It is deliberately **ownership, not the weapon in hand**: a bot with a
  rifle in its bag is still a sniper while it walks around with a pistol out, and the rifle will be out by the
  time it is standing on the perch wanting to shoot. The question being asked is "could a perch ever be useful to
  this bot".
- **`Wander.FindSpotFor`** takes cover instead of a perch when the bot has nothing long-range, and if the role is
  not allowed to want cover either (`SetCanHide(false)`) it takes no spot at all and wanders normally - so the
  role flags keep meaning what they say.
- **`PlanCoordinator.CalcPopularSniperSpot`** returns nil without a long-range weapon, which fails the job on the
  spot; the DEFEND guard from section 10 turns that into "pick up the next job in the plan", so a pistol-armed
  traitor falls through to hunting rather than holding an angle.

**For tuning:** the whole check is a scan of a per-weapon cache that is refreshed once a second, so it costs
nothing at destination-picking time. If perches end up rarer than you want, the thing to loosen is the `is_sniper`
heuristic itself - it needs more than 40 damage, so a marksman-ish rifle that does 40 or less is not counted -
rather than this gate.

**Verification:** `glua-check` 118 files / 0 issues / 2 notes (both pre-existing); GluaLint clean on `wander.lua`,
and unchanged elsewhere: `sv_plancoordinator.lua` still reports its eight pre-existing warnings and `sh_botlib.lua`
its thirteen, none of them in the new function.

---

## 27. The Blocker: a role profile registered too early, and the clone that shadowed it

**Report:** "Detectives and other bots are constantly trying to identify a bot when there's a Blocker role active.
Blocker being alive means they cant identify the body until the Blocker is dead."

**The check was not the bug.** `IsCorpseIdentifyBlockedFor` reads live (it walks `Match.AlivePlayers` and asks
each player's RoleData), it is called in both `InvestigateCorpse.Validate` and `OnRunning`, and it is what stops a
bot walking to a body it cannot open. What was wrong is **which profile the Blocker role ends up with** - and that
falls out of how role files are loaded:

1. Every file in `tttbots2/roles/` guards on the role's global (`if not ROLE_BLOCKER then return false end`), and
   they are all included **while this addon loads**. GMod decides for itself which addon's files run first, so a
   role addon that loads *after* ours leaves that global nil and its file silently returns false. Missing addons
   are deliberately harmless; *late* addons are not.
2. Two seconds later `TTTBots.AutoRegisterRoles` finds the role unknown **on a bot** and calls
   `GenerateRegisterForRole`, which registers a **clone of the nearest registered ancestor** - for a traitor role,
   our traitor profile. A clone carries none of the role's own flags, so `blocksCorpseIdentify` is simply absent
   and every bot goes back to identifying exactly the bodies the role exists to hide.
3. That clone is registered under the same name, so `GetRole` stops reporting the role as unknown and the stand-in
   **shadows the real file for the rest of the session**.
4. The timer only ever looked at `TTTBots.Bots`. For a **human** Blocker nothing was registered at all, so
   `GetRoleFor(humanBlocker)` returned the innocent profile with the flag false - the same symptom, with none of
   the auto-registration chatter to explain it.

**The fixes**, in [`lib/sv_roles.lua`](lua/tttbots2/lib/sv_roles.lua:269) and `roles/blocker.lua`:

- **Our own file gets a second chance.** Before inventing a profile, the timer tries
  `include("tttbots2/roles/<role>.lua")` if such a file exists - which is precisely the file that bailed while its
  addon was still loading - and only falls back to a generated stand-in if that fails too. It prints
  *"Registered role 'x' late"* when that works, so the cause is visible instead of silent.
- **Generated profiles are marked** (`autoGeneratedRoles`), so a stand-in keeps giving way to the real file. A
  clone registered in round 1 no longer blocks the file from claiming the name back in round 2, which a plain
  "is the role unknown?" test would have missed forever.
- **Every alive player is checked, not just the bots** - a human's profile is read by bots constantly (is that role
  immune, does it look like police, does it hide the dead), so a human role that never got a profile made those
  answers wrong for everybody. This is why a human Blocker was invisible to the check.
- **The Blocker is filed under the role's *name*, taken from the addon's own role table** (`(BLOCKER and
  BLOCKER.name) or "blocker"`). **Corrected in section 29**: this was first written as `ROLE_BLOCKER`, which is
  backwards - that global is the role's numeric index, not its name - so the profile was filed under a number
  that `GetRoleFor` never asks for, `GetRole` kept handing back the innocent profile, and the flag below was
  absent exactly as before. It is the same failure this section describes, one layer further in, and it is now
  rule 7 in the index.

**The general lesson, for any future "this role's flag seems ignored" report:** a role file guarded on another
addon's global is a load-order race, and the auto-registration path turns that race into a *plausible-looking*
profile with none of the custom flags - so the symptom is a role behaving generically rather than an error. The
console now distinguishes the two: `Registered role 'x' late` (ours claimed it) versus
`Auto-registered role 'x' based off of 'y'` (a stand-in, so hand-written flags are missing). The tidier version of
the last fix would be to register *all* our role files under their globals instead of string literals; that sweep
is not done.

**Verification:** `glua-check` 118 files / 0 issues / 2 notes (both pre-existing); GluaLint clean on
`roles/blocker.lua`, and `sv_roles.lua` reports only its four pre-existing mixed-quote warnings (two in the
`GenerateRegisterForRole` print block, two in the `plyMeta:GetTeam` fallback below it).

---

## 18. The popularity map (`sv_popularnavs.lua`) - reviewed, three fixes

**Report:** "is there anything that can be optimized here? or is it good enough?"

**Verdict: good enough for the job it does**, with three defects fixed and one sharp edge recorded rather than
touched.

### What the per-second timer costs

[`timer.Create("TTTBots.Lib.PopularNavsTimer", 1, 0, ...)`](lua/tttbots2/lib/sv_popularnavs.lua:16) walks the
alive players (one `navmesh.GetNearestNavArea` query each), then rebuilds the sorted list: one two-element table
per distinct nav area ever visited, plus an O(M log M) sort where M is bounded by the map's nav count. That is
roughly two thousand small allocations and twenty thousand comparisons a second on a large map - ordinary for
GLua, far below the tick budget, and the reason the loop itself was left alone. The obvious "optimization" is to
sort an array of ids and compare through the counts table, reusing the array; it would work (Lua here is
single-threaded, so nothing can observe a half-rebuilt list), but the fresh table is an atomic swap that makes
the file easier to reason about, and that is worth more than the allocation it saves.

### The three fixes

1. **The round gate the comment only claimed.** The timer's own comment said "check if we have a navmesh and
   we're in a round" while the only filter was `IsPlayerAlive`. That matters because of when players are alive
   but not playing: [`Match.ResetStats`](lua/tttbots2/lib/sh_match.lua:148) is called with `false` on
   `TTTPrepareRound` and `true` on `TTTBeginRound`, so during prep everybody is alive and standing at the spawn
   points and every second of that window deposited the full player count onto the spawn navs - a round's worth
   of points, per round, on areas that are not hangouts. It is now
   [`if TTTBots.Match.RoundActive == false then return end`](lua/tttbots2/lib/sv_popularnavs.lua:16), an early
   return rather than a clear, so `PopularNavsSorted` keeps its last good value between rounds.
2. **`GetTopNUnpopularNavs` returned n+1 entries.** The loop ran `for i = #sorted, #sorted - n, -1`
   ([`sv_popularnavs.lua:76`](lua/tttbots2/lib/sv_popularnavs.lua:76)), which is n+1 iterations; it is
   `#sorted - n + 1` now. Invisible in behaviour, because the only preset caller reads `[1]` - visible in the
   debug overlay, which asks for three unpopular ranks and drew four.
3. **`GetPopularityPct`'s scale was inverted.** The list is sorted most-popular-first, so rank 1 is the *most*
   popular area, and `i / total` returned the smallest number for it and `1.0` for the least popular: the exact
   inverse of its own documented "1 = most, 0 = least". Now `(total - i + 1) / total`, and the doc comment also
   says the lookup is a linear scan of every area ever visited, so it is not for per-tick use.

### The sharp edge left alone: there is no decay

`PopularNavs[id]` is only ever incremented, for as long as the server sits on the map, so a score is dwell-time x
players since map load - "where anybody has ever lingered" rather than "where people hang out". One player or
bot parked in a closet for ten minutes banks ~600 points, which can outrank a genuinely busy area (two players
present a fifth of a twenty-minute session is only ~480) and stays at the top afterwards. Every consumer reads
through this map: [`Wander.GetPopularAreaNear`](lua/tttbots2/behaviors/wander.lua:296),
[`Wander.GetDistantPopularArea`](lua/tttbots2/behaviors/wander.lua:332) (what section 16's relocation uses),
[`CalcPopularArea`](lua/tttbots2/lib/sv_plancoordinator.lua:93) and the new
[`CalcPopularSniperSpot`](lua/tttbots2/lib/sv_plancoordinator.lua:215).

Left alone on purpose for now: the counter-reading is defensible - a map's hangouts are stable features, the
middle room is the middle room in every round - nothing is reported as misbehaving, and decay would retune four
consumers at once. **If the symptom appears** (bots holding a perch or gathering somewhere nobody goes), the
ten-minute fix is a leaky bucket inside the loop that already walks the table: subtract a constant per tick and
`PopularNavs[id] = nil` at zero. That keeps the counts integers (the debug overlay prints them with `"s"`, so
floats would show up there), makes the map "recently busy", and self-cleans the entries. Multiplicative decay is
the alternative and is worse here: floats, and it never fully forgets a dead spot.

### Decisions recorded rather than changed

- **Bots are counted, on purpose.** They are players in `player.GetAll()`, so they write to this map as well as
  read it, and on a bot-heavy server it is mostly a map of where the bots have been - section 16's convergence is
  partly self-reinforcing as a result. Excluding them would make it strictly "where the humans are", but it would
  also silently disable section 16's relocation and the new perch target on the all-bot local servers this addon
  is most often used on, because there would be no map to read at all. Now said out loud in the file comment.
- **`GetRandomPopularNav` is dead and was left in place.** Nothing in the tree calls it (searched: the only hits
  are its own definition), and it returns a raw nav id where every other accessor hands out `{id, count}` entries.
  Kept because `TTTBots.Lib` is the surface third-party role files use, and deleting a `Lib.` function is the one
  change here that could break somebody else's file for no gain.

**Verification:** `node tools/glua-check/check.js` -> 119 files, 0 issues, 2 notes (both pre-existing). GluaLint
on `sv_popularnavs.lua` is clean.

---

## 28. The Roider and the Shinigami swinging from out of reach - "melee range" was a guess

**Report:** "Something is wrong with the Roider and Shinigami melee attack range. They seem to have trouble getting
in melee range and attacking from a distance, as if they have ranged weapons."

**The whole bug is one number.** [`Attack.Engage`](lua/tttbots2/behaviors/attacktarget.lua:325) has a
close-quarters branch for anything that is not a gun, and it decided "in range" with
`if distToTarget > 160`, where `distToTarget` is the distance between the two players' **feet**
(`bot:GetPos():Distance(target:GetPos())`). The comment next to it said *"Melee has its own distances (the old
logic used 160)"* - which is rule 5 in the handover index: a number in a comment is a claim nobody had checked
against a weapon.

**How a melee weapon actually measures its own reach.** Every melee weapon in TTT2 traces from the *eye* and only
damages whatever that trace lands on:

- the crowbar, [`weapon_zm_improvised.lua:156`](../TTT2-master/gamemodes/terrortown/entities/weapons/weapon_zm_improvised.lua:156):
  `sdest = spos + owner:GetAimVector() * 100`, `MASK_SHOT_HULL`;
- the knife, [`weapon_ttt_knife.lua:76`](../TTT2-master/gamemodes/terrortown/entities/weapons/weapon_ttt_knife.lua:76):
  the same 100 units;
- the Shanker's knife: 80, which this tree already knew - [`KNIFE_RANGE = 75`](lua/tttbots2/behaviors/shankerstalk.lua:22)
  is documented as "the weapon's own 80, minus a little slack", and the stalk tests it as
  `bot:EyePos():Distance(stabPos)`, i.e. eye-to-torso.

So the furthest a swing lands, expressed the way `Engage` was expressing distance, is about 110-116 units (100 of
trace, plus the target's 16-unit hull, minus the eye height) and comfortably less in practice. The bot stopped at
**160** and swung there: every crowbar swing and every knife stab was thrown at air, and the victim never took a
point of damage. That is the reported "attacking from a distance, as if they have ranged weapons". The "trouble
getting in melee range" is the same fact from the other end - 160 is also the distance below which the bot stopped
closing at all, so nothing ever pulled it into reach.

**The fix**, all in [`behaviors/attacktarget.lua`](lua/tttbots2/behaviors/attacktarget.lua:183):

- **`MELEE_SWING_REACH = 75`**, measured from the eye to the point being swung at - the Shanker's own figure, and
  inside every reach above. `SHORT_RANGE_SWING_REACH = 160` keeps the old distance for *short range guns* (the
  arsonist's thrower), which are held like guns, have real reach, and were tuned against it.
- **`Attack.IsSwung(weapon)`** answers "does this have to be swung from arm's length": `is_melee or not is_gun`,
  and not `is_short_range`. Deliberately not `is_melee` alone, because `is_melee` only means "no clip"
  (`clip == -1`) and the Shinigami's knife is `weapon_ttt_shinigamiknife`, a class this tree does not own - a
  melee weapon the inventory does not classify as melee still has to close. `Attack.GetSwingReach` wraps it.
- **The test is now `bot:EyePos():Distance(aimPoint) > swingReach`**, where `aimPoint` is the body position the
  swing is aimed at (`Attack.GetPreferredBodyTarget`, resolved once at the top of `Engage` and reused by the
  aiming code below, so the bone lookup is not done twice).
- **`ShouldApproachWith` and `ShouldRunToCatch` use `IsSwung` too**, so a swung weapon the inventory does not call
  melee still forces the charge and the closing run instead of only the melee branch doing it.
- **`ShouldLookAtBody` uses `IsSwung` too**, so a swung weapon aims at the torso rather than the head whoever is
  holding it. That matters for the same reason the reach does: a melee weapon reaches by *tracing* through the point
  it is aimed at, so the aim point and the reach test now agree and a headshotter personality no longer swings a
  crowbar at head height - the rule [`shankerstalk.lua`](lua/tttbots2/behaviors/shankerstalk.lua:101) already spells
  out for its knife.

**Why both roles at once:** they differ only in how the weapon ends up in hand - the Roider through
`SetAutoSwitch(false)` + `SetPreferredWeapon`, the Shinigami by being knife-only - and the reach test they both
funnel through is the single line that was wrong. The Roider's own file comment claimed the attack behavior
"closes to crowbar range and swings"; with the old 160 it did not, and that comment is only true now.

**Left alone:** the gun thresholds (`ENGAGE_THRESHOLD` 180 / `DISENGAGE_THRESHOLD` 250) and the short range
distance. Both are correct for a weapon that has reach; only the swing case was wrong.

**Verification:** `node tools/glua-check/check.js` -> 118 files, 0 issues, 2 notes (both pre-existing); GluaLint
clean on `behaviors/attacktarget.lua`.

---

## 29. The Cursed (AaronMcKenney/ttt2-role_curs) - a keypress role, and a profile filed under the wrong key

**Request:** the roles were handed over as links (the GitHub source and the workshop page) with no instruction, and
after the shape of the problem was laid out, the answer was "full support: a profile plus a behaviour that walks
to a taggable player and calls `CURS_DATA.AttemptSwap` the way the tag key does, and fires the RoleSwap Deagle
when the target is beyond tag range".

### What the role is, from its own source

`lua/terrortown/entities/roles/cursed/shared.lua`, `lua/terrortown/autorun/shared/sh_curs_handler.lua` and
`gamemodes/terrortown/entities/weapons/weapon_ttt2_role_swap_deagle.lua` (read from the repo, the same way the
Blocker was):

- **No team and no win.** `defaultTeam = TEAM_NONE` with `unknownTeam`, `preventWin = true`, every score
  multiplier 0, `preventFindCredits` and a shop disabled outright.
- **It cannot hurt anybody.** Its `EntityTakeDamage` hook zeroes *every* point of damage a Cursed deals to a
  player - which is the same fact the Beggar and the Collusionist are described by, so the flag for it already
  existed (`SetDealsNoDamage`).
- **Death is a delay, not an ending.** `TTT2PostPlayerDeath` revives it after
  `ttt2_cursed_seconds_until_respawn` (10 s), optionally at a random player spawn.
- **It leaves the role only by swapping it away**, and the addon offers exactly two ways:
  - **Tagging**: `bind.Register("CursedSendTagRequest", … KEY_E)` on the client sends a net message; the server
    handler traces from the sender's eyes (`MASK_SHOT_HULL`) and calls `CURS_DATA.AttemptSwap(ply, tgt, dist)`
    with the traced distance. Reach is `ttt2_cursed_tag_dist` (150).
  - **The RoleSwap Deagle**: a 1-round weapon whose bullet callback calls the same `AttemptSwap` at any range,
    refilled `ttt2_role_swap_deagle_refill_time` (30 s) after a *failed* shot. `SWEP.Kind = WEAPON_EXTRA`.
- The rules both routes share live in `CURS_DATA.CanSwapRoles`: round active, both alive, the target not already
  carrying "no backsies" from a swap they just made, the role and team differing, and the detective convar
  (`ttt2_cursed_affect_det`). After a swap the old Cursed is marked `curs_last_tagged` until the *new* Cursed
  tags somebody else - the tag game the workshop page describes.

### Why a bot could play none of it

- The tag is a **keypress**: a bot can never send `TTT2CursedSendTagRequest`. But the handler's whole body is
  `CURS_DATA.AttemptSwap`, and `CURS_DATA` is an ordinary table of server functions - so the bot can make the
  same call with the same trace, which is what `behaviors/curseswap.lua` does. This is rule 1 in the index
  ("find the hook it lives in") pointing the other way: the *addon* has the server-side function and only the
  client-side wrapper is missing.
- The deagle is `WEAPON_EXTRA`, a slot this addon's inventory never equips, so it was never in a bot's hands.
- Its refill is **client-side**: the server tells the shooter's client on a failed shot and the client's timer
  sends `ttt_role_swap_deagle_refilled` back. A bot has no client, so that round trip never happens and the
  weapon would be one shot per round. That part is now run on the server for the bot, which puts it on the
  footing `ttt2_role_swap_deagle_refill_time` describes for a player.

### What was added

- [`roles/cursed.lua`](lua/tttbots2/roles/cursed.lua) - `TEAM_NONE`, `SetDealsNoDamage(true)`,
  `SetStartsFights(false)`, `SetUsesSuspicion(false)`, no hide and no perch (both are ways of *not* finding
  people, which is the opposite of this role), no C4 either way, and no allies at all (the same empty
  `SetAlliedRoles`/`SetAlliedTeams` the Amnesiac - the other `TEAM_NONE` role here - uses). Its tree is
  `CurseSwap` first, then `InvestigateNoise` (gunfire is where the people are) and `Patrol`.
- Damage immunity is answered **from the convar** rather than sampled at load: `ttt2_cursed_damage_immunity`
  ships at 0 but can be turned on, and every reader of the flag asks it live. The profile overrides the getter
  so a bot stops shooting an immune Cursed instead of being a bullet sponge against one.
- [`behaviors/curseswap.lua`](lua/tttbots2/behaviors/curseswap.lua) - picks the nearest player the addon's own
  `CanSwapRoles` accepts (asked with distance 0, i.e. "would a tag be legal at point-blank"), walks to them
  through the memory's known position only, and then:
  - **in reach and looking at them** (`GetEyeTrace(MASK_SHOT_HULL).Entity == target` and the traced distance
    inside the convar) calls `CURS_DATA.AttemptSwap(bot, target, traceDist)` - the keypress, verbatim;
  - **beyond that reach, in sight, holding a loaded deagle** pauses auto-switch, selects the weapon with
    `SelectIfNotHeld` (re-selecting deploys again, and a mid-deploy weapon cannot fire), aims at the torso and
    presses once, then watches the clip to see the round leave and starts the addon's cooldown;
  - **otherwise** sprints to the last known position, because the role's own addon gives it 1.2x speed and cheap
    stamina precisely so it can catch somebody, and a walk cannot catch a walk.
- Its two routes are logged on `debug_misc` (`tagged X`, `RoleSwap Deagle refilled`), so a test session can see
  which one fired.

### The bug this turned up: the Blocker profile was filed under a number

Section 27 "fixed" the Blocker by registering under `ROLE_BLOCKER` instead of the literal `"blocker"`. That is
backwards, and it left the Blocker exactly as broken as before:

- TTT2's `roles.SetupGlobals` does `_G["ROLE_" .. string.upper(roleData.name)] = roleData.index`, and
  `roles.GenerateNewRoleID()` returns a **number**. So `ROLE_BLOCKER` is an index.
- The string a profile must be filed under is `roleData.name`, which is what `Player:GetRoleStringRaw()` returns
  and what `GetRoleFor` looks up. TTT2 publishes the role table itself as the uppercase global (`BLOCKER`,
  `CURSED`).
- So `m_roles[<number>] = profile` was written and `GetRole("blocker")` kept missing, falling back to the
  **innocent** profile - `blocksCorpseIdentify` absent, the original symptom intact. Worse, the two console
  lines now lie about it: `tryIncludingRoleFile` asks `GetRole(roleString)` *after* including our file, sees no
  change, returns false, and the auto-registration path prints the stand-in line every session while our real
  profile sits unreachable one table-key away.
- Fixed as `(BLOCKER and BLOCKER.name) or "blocker"`, and section 27's bullet is corrected in place. This is
  rule 7 in the index now, because every role file in this tree carries the same trap and only `blocker.lua` had
  stepped in it.

### Deliberately not done

- **`ttt2_cursed_no_dmg_backsies` is not mirrored.** It zeroes damage from *whoever last tagged the current
  Cursed* - transient per-player state rather than a role trait - and it self-clears on the next swap. Bots
  shooting a Cursed in that window waste a shot at worst.
- **No special treatment of the Cursed by other bots.** With immunity off it is a normal non-ally to everyone,
  so bots may shoot it and it may shoot back at nothing; TTT2 scores it as a team of its own and gives no signal
  that killing it is pointless. If that ever reads wrong in play, the place to fix it is the profile's flags,
  not the attackers.
- **No self-immolation.** The `V` key sets the Cursed (or its corpse) alight to respawn at a world spawn, which
  is a player convenience for a bot that is already going to be revived wherever it died.

**Verification:** `node tools/glua-check/check.js` -> **120 files, 0 issues, 2 notes** (both pre-existing);
GluaLint clean on `behaviors/curseswap.lua`, `roles/cursed.lua` and `roles/blocker.lua`.

---

## 30. Traitors starting fights the moment a round begins

**Report:** "Traitor seem to instantly start killing by the time round start, same problem like the RDM before."
Scope agreed from the options: **all of it** - one shared "no unprovoked killing yet" gate on every path that hands
a bot a victim, checked against the round clock *and* the bot's own life clock, with `ttt_bot_attack_delay` as the
single knob.

### What was there

A delay per path, and one path with none:

| Path | Where | Gate before this |
| --- | --- | --- |
| Random nearby roll | [`BotMorality:SetRandomNearbyTarget`](lua/tttbots2/components/sv_morality.lua:232) | `ttt_bot_attack_delay` (15 s) against `Match.Time()` - the **round clock only** |
| Plan attack orders | [`PlanCoordinator.GetNextJob`](lua/tttbots2/lib/sv_plancoordinator.lua:68) → `FollowPlan` | `Match.PlansCanStart()`, i.e. `plans_mindelay` (12 s) - and the *fallback* job is `ATTACKANY` + `NEAREST_ENEMY`, a **live** position with no visibility check |
| Last player standing | [`BotMorality:TickIfLastAlive`](lua/tttbots2/components/sv_morality.lua:267) | **nothing** - with two players alive it handed out a target on the first tick of a round |

The round clock on its own is also exactly the hole the RDM delay had to close for itself in section 15: a bot that
spawns late or is brought back by a defibrillator is a fresh arrival at a round that may already be minutes old, so
its own life is worth zero seconds of waiting.

### The fix

[`Match.KillDelayElapsed(bot)`](lua/tttbots2/lib/sh_match.lua:113) in `lib/sh_match.lua` - **two clocks, one
knob**. The round's age is `Match.Time()`; the bot's own life is `bot.killDelayAliveSince`, stamped and cleared by
`Match.Tick` (SERVER side) and reset in `Match.ResetStats`, which is what lets it cover a round spawn, a respawn, a
revive and a role change without a hook for each. Applied to:

- the random nearby roll, replacing its bare `Match.Time() <= attack_delay` test;
- `TickIfLastAlive`, which had no gate at all - and which runs for *every* role, so an innocent killing the last
  player was equally instant;
- the plan system, where only the **attack** actions are held back (`ATTACK` and `ATTACKANY`) so a traitor still
  gathers, follows somebody and plants while the round settles. When the fallback would have been that attack
  fallback, `GetNextJob` returns no job at all, so the bot patrols instead of walking at somebody it should not
  know about yet.

**Outside the gate on purpose:** everything provoked - being hurt or shot at, seeing a teammate shot, another
bot's KOS - because a bot must always be able to shoot back, and the contract roles (Hitman, Executioner), whose
victim comes from their own addon and would break if it were delayed. That line is written into the function's own
comment so it is not re-litigated.

**Recorded, not changed:** [`Match.PlansCanStart()`](lua/tttbots2/lib/sh_match.lua:78) re-rolls
`math.random(minInt, maxInt)` on **every call**, so `plans_maxdelay` (35 s) is not really a maximum - the plan
opens just after `plans_mindelay` (12 s) with a probability that climbs fast. Harmless now that the attack orders
carry their own gate, and left alone rather than reworked.

**Tuning:** `ttt_bot_attack_delay` (default 15) is now the single knob for all of it; raising it holds traitors
back for longer, and `ttt_bot_plans_mindelay` still governs when the plan system itself may start. The RDM feature
keeps its own separate clock (`bot.rdmAliveSince`, section 15) on purpose: that one is about a bot that has had
enough of the server and has to keep working when this gate is wide open.

**Verification:** `node tools/glua-check/check.js` -> 120 files, 0 issues, 2 notes (both pre-existing). GluaLint on
the four edited files reports only pre-existing style warnings - `sh_match.lua` one double-`if` in `WhoShotFirst`,
`sv_plancoordinator.lua` its eight (unused `PLANSTATES`/`conditions`/`farthestDist`/`closestDist`, two
parentheses), `sv_morality.lua` its six (empty `elseif`s, a silly negation, a shadowed loop variable) - none on the
changed lines, and `meta_defs.lua` is clean.

---

## 31. Performance sweep - four tiers, ranked by what they cost

**Request:** "check every Lua file for any optimizations that need to be done, or perhaps anything that causes
unnecessary lag?" Scope agreed from the options: all four tiers, in the order below, verified with `glua-check` and
GluaLint as each one landed.

The shape of the tree's recurring work, for orientation: the addon ticks at **5 Hz** ([`TTTBots.Tickrate`](lua/tttbots2/sh_tttbots2.lua:18)),
so components, the behaviour trees and the memory passes cost `5 x bots` per second. The **per-frame** costs are
`StartCommand` per bot, the path-finder's coroutine, and the client-side timers.

### Tier 1 - the path-finder's inner loop (the only thing here that can be felt as a stutter)

[`Astar2`](lua/tttbots2/lib/sv_pathmanager.lua:443) kept its open set as a plain array and re-sorted it after
*every* expansion, looked a node up with an `ipairs` scan, and tested membership of the closed set with
`table.HasValue` against an array that grows to the node budget. It runs `ttt_bot_pathfinding_cpf` (default **240**)
expansions per frame, so a frame was on the order of 10^5-10^6 comparisons plus 240 sorts.

Replaced with a **binary min-heap** for the open set and **nav-area-id-keyed hash tables** for open/closed
membership; a node whose cost improves is pushed again rather than decrease-keyed, and the stale entry is skipped
when it comes up. Same cost function, same heuristic, same 600-node budget and the same coroutine chunking - only
the bookkeeping changed, so path *costs* are identical (ties may resolve differently, since a heap does not sort
like a sort).

An **instrument** was added rather than a claim: with `ttt_bot_debug_pathfinding 1`, the path coroutine now prints,
once per completed path, the number of frames it spanned and the total CPU it cost across them (`queuedPath.cpu`).
That is the number to compare before and after any future change to the search.

### Tier 2 - one visibility answer per pair per tick

[`Lib.CanSee`](lua/tttbots2/lib/sh_botlib.lua:336) fires **three** traces per call, and it was called for every
player, every third tick, per bot by [`Memory:UpdateKnownPositions`](lua/tttbots2/components/sv_memory.lua:294).
The *same pair* was then traced again in the same tick by `Memory:GetCurrentPosOf` (attack path),
`Locomotor:UpdateADS`, `Attack.Seek`, `Lib.CanShoot` (used by the attack behaviour, the inventory and the morality
component), `personalSpace`, and two per-second morality scans.

Added [`Lib.SeenThisTick(bot, target)`](lua/tttbots2/lib/sh_botlib.lua:256): one trace per pair per tick, keyed on
a new `TTTBots.TickCounter` that the main tick timer increments before any of the work, so a whole batch of
per-tick work shares one cache generation (a wall-clock bucket could split a tick in half). `Lib.CanShoot` now
goes through it, which memoises every combat caller for free, and the call sites above were routed to it directly.

Two consequences worth knowing:

- The passes now **agree** with each other within a tick. They did not before: the same pair could be "visible" to
  the memory pass and not to the attack behaviour.
- The memory pass now uses `Visible` (one trace, from the eyes) rather than `CanSee`'s three-ray generosity
  (eyes, feet, centre). That is the same question the combat paths already ask, and it is *more* consistent, but it
  is a behaviour change for a bot standing behind hard cover with only its feet showing - it will notice a little
  less eagerly. `CanSee` itself is untouched and still used by `Interact.FindOther`, which is behind a timer.

### Tier 3 - per-tick allocation churn

- [`Memory:UpdateKnownPositionFor`](lua/tttbots2/components/sv_memory.lua:246) built **two closures per call** (a
  `timeSince` and a `shouldForget` closed over the entry and the component). They are now two methods shared by
  every entry (`KnownPos`), called with a colon, with the entry carrying the component it belongs to. Same
  answers; the `shouldForget` path also reads its own `forgetTime` instead of looking the entry up by nickname
  again.
- [`Memory:GetSuspectedPositionFor`](lua/tttbots2/components/sv_memory.lua:222) built a filtered list of every
  remembered sound and **sorted** it, on the tick, from `Attack.Seek`, to take the newest one. Now a single pass
  for the maximum. `GetRecentSoundsFromPly` is left in place (documented accessor, one caller left after this).
- [`BotMorality:TickIfLastAlive`](lua/tttbots2/components/sv_morality.lua:288) allocated a fresh alive-player table
  on every tick for every bot; it now uses `Match.AlivePlayers`, which the match refreshes three times a second.
  A third of a second of staleness cannot change who the last two players are.
- `GetNonAllies` is still allocated per call, but its heaviest callers (the per-second morality scans) now build
  their list from the tick's visibility answers rather than a trace each.

### Tier 4 - world scans

- [`DrinkSoda.FindCan`](lua/tttbots2/behaviors/drinksoda.lua:89) called `ents.FindByClass("soda_*")` - a fresh list,
  every tick, for every bot, because it sits in `Validate`. It now reads a shared list refreshed at most once a
  second; a can that has just been taken is filtered by the existing `IsValid` check, so a second of staleness
  cannot send a bot to a can that is gone.
- [`BotObstacleTracker.IsBreakable`](lua/tttbots2/components/sv_obstacletracker.lua:137) called `GetKeyValues`,
  which allocates a table, for every physics prop on the map, every 1.5 s, because of a rescan that exists to catch
  props being created and destroyed. Both values it reads are spawn keyvalues that cannot change while the entity
  exists, so the result is now memoised per entity in a weak-keyed table: new props are computed once, removed
  props take their entry with them, and the periodic scan no longer allocates.

### Deliberately left alone, with the reason

- **[`GetWeapons.UpdateCache`](lua/tttbots2/behaviors/getweapons.lua:126) still walks `ents.GetAll()` every 3 s.**
  The obvious "optimisation" is `ents.FindByClass("weapon_*")`, which is an indexed lookup - but SWEP classes are
  not required to carry the `weapon_` prefix (m9k and cw ship without it), so that would quietly stop bots finding
  those weapons on the floor. A full list once per 3 s with a cheap `IsWeapon()` predicate per entity is the
  cheaper side of that trade.
- **The position-based witness helpers** (`GetAllWitnesses*`, `VisibleVec`, `CanSeeArc`) cannot use the pair memo -
  they ask "can this player see that *position*" - and their callers are per-second, not per-tick.
- **`CullSoundMemory` still traces per remembered sound per second.** It is bounded by the 5 second sound memory
  and each entry is only checked once before it expires, so the pragmatic fix is a cap on the memory if it ever
  shows up in a profile, not a cache.
- **Already reviewed and left as they are:** the debug draw path (bails on empty, compresses before sending), the
  popularity timer (section 18), the client debug timers (gated by `requestData`), `GetWeaponInfo`'s one second
  cache, and the path coroutine's per-frame chunking itself.

### How to measure any of this

`ttt_bot_debug_pathfinding 1` prints the CPU cost of every path (Tier 1). For the rest, the instruments are the
existing ones: `ttt_bot_debug_misc` for the behaviour-level logs and a plain `developer 1` profile of the server
while bots are active.

**Verification:** `node tools/glua-check/check.js` -> **120 files, 0 issues, 2 notes** (both pre-existing, both
nil-guarded). GluaLint on every edited file reports only its pre-existing warnings and nothing on the new lines:
`sv_pathmanager.lua` five (unused `LADDER_TOP_FORWARD_OFFSET`/`totalNeighbors`/`bezierQuadratic`/`lastIsLower`, one
empty `elseif`), `sh_botlib.lua` thirteen, `sv_memory.lua` three, `sv_morality.lua` six, `sh_tttbots2.lua` three;
`sv_obstacletracker.lua`, `behaviors/drinksoda.lua` and `behaviors/curseswap.lua` are clean.

---

## 32. The Revenant (TaintedEnergy/ttt2-role-reven) - one role, two states, and one of them is not the subrole

**Request:** the two links and "what they do in gameplay is listed in the steamcommunity and the source code is in
the Github"; scope agreed from the options: **full support** - the profile with the live team rule, the state 2
hunt, and the reveal.

### What the addon actually does

Read from `lua/terrortown/entities/roles/revenant/shared.lua` and
`lua/terrortown/autorun/shared/sh_reven_convars.lua`. The role has **two states**, and they are not different
subroles - they are a field on the player, `ply.revenant_state`, which is why a role profile cannot describe the
role on its own:

- **State 1 (nil or 1)** - what it spawns as. `defaultTeam = TEAM_INNOCENT`, `unknownTeam`, `preventWin = false`,
  no shop (`SHOP_DISABLED`), no credits, `disableSync`. Its own `TTT2SpecialRoleSyncing` hook reports it as
  `ROLE_INNOCENT` to itself and `ROLE_NONE` to everybody else, and a search of its corpse has `was_role` rewritten
  to an innocent by `TTTCanSearchCorpse` + `TTT2ConfirmPlayer`. So while it lives it *is* an innocent to every
  observer.
- **State 2** - what its death turns it into. `TTT2PostPlayerDeath` calls
  `ply:Revive(ttt2_reven_revival_time)` (15 s) with `REVIVAL_BLOCK_ALL`, and the revive callback sets state 2 and
  calls **`ply:UpdateTeam(TEAM_REVENANT)`** - its own team, created by `roles.InitCustomTeam`: a neutral killer on
  nobody's side, with 1 + `ttt2_reven_damage_bonus` (0.5) damage. From that moment the disguise hook no longer
  applies to it, so its team and role are public.
- The `IN_RELOAD` keypress only picks *where* it respawns (`isRevenantWorldspawn`), and `ResetRevenants` clears
  every state at round end and before the next round.

### What the profile could and could not express

- **The team change is handled entirely by `SetLovesTeammates(true)`**, with both static allied sets cleared.
  `TTTBots.Roles.IsAllies` has a branch for roles "whose team is adjusted on the fly": if either side loves
  teammates, the pair are allies exactly when `ply:GetTeam()` matches - which is **live**. So in state 1 the bot
  is allied with the innocents (the disguise holds and no bot fires at it) and in state 2 with nobody. Leaving
  `TEAM_INNOCENT` in the allied-teams table would have kept a *revived* Revenant treating innocents as friends,
  which is the whole second half of the role, and setting no allies at all would have made an innocent-side bot
  treat the disguised one as a stranger. This is the same mechanism the Bodyguard has always relied on.
- **The aggression could not be a flag.** The subrole never changes, so `GetStartsFights` (declared once) would
  either hunt while the bot is meant to be a hidden innocent or never hunt at all. It lives in the role file's own
  hunt, keyed on the state, the way `roles/shinigami.lua` drives its post-death form: on the bot tick, a state 2
  bot with no target takes the nearest player it can **see** (`Lib.SeenThisTick`) and hands the attack behaviour
  the position as well, because that behaviour navigates purely from memory and would otherwise stand still.
- **The reveal** is the other half of "the addon stops hiding it". A bot cannot read a HUD, so the suspicion
  system is told what the HUD says: a once-a-second pass over the alive state 2 Revenants gives every bot that can
  see one a KOS-weight reason (`RevenantRevealed`, 10, registered through the component the way
  `roles/paranoid.lua` registers its own). That hands out the KOS callout and the attack target through machinery
  that already exists, keeps the per-player KOS cap in play, and cannot stack because it is skipped once the
  observer is at or above its KOS threshold. Traitors are skipped - they do not use suspicion and attack
  non-allies on their own already.

### Recorded, not worked around

- **Their damage bonus is applied to the wrong player.** `ScalePlayerDamage` tests `ply.revenant_state == 2` -
  the *victim's* state, not the attacker's - so the 50% only lands when one revived Revenant shoots another.
  Nothing here mirrors the bonus, because the engine applies it: a bot's decisions do not depend on it.
- **Their hook would error on an environmental kill**: `dmginfo:GetAttacker()` is used without checking that it is
  a player, and `GetSubRole` is a player method.
- The workshop page says `minPlayers` 6; the code says 8. The code wins.

**Verification:** `node tools/glua-check/check.js` -> **121 files, 0 issues, 2 notes** (both pre-existing).
GluaLint clean on `roles/revenant.lua`.

---

## 33. The Pharaoh and the Graverobber (TTT-2/ttt2-role_pha) - an item with four verbs, and the first real `+use` hold

**Source:** a shallow clone of `TTT-2/ttt2-role_pha`, read in full - two roles, an entity and a weapon - plus the
repo's own README. The workshop blurb adds nothing the source does not already say.

**The addon's own flow, which is what the bots had to be fitted into:**

1. The Pharaoh's loadout hands it `weapon_ttt_ankh`. Both attack buttons call `SWEP:AnkhStick`, which traces 100
   units **from the eye**, demands a floor normal within 0.2 rad, a *world* hit and `plyspawn.IsSpawnPointSafe`,
   and spawns `ttt_ankh`. The weapon consumes itself on success (`ClipSize = -1`), so it is single use.
2. `PHARAOH_HANDLER:PlacedAnkh` **converts a random living traitor into the Graverobber** (preferring a vanilla
   traitor). Not optional, not requested: placing an ankh is what creates the adversary, which is why the two
   roles cannot be supported apart from each other.
3. The ankh is `CONTINUOUS_USE`: `ENT:Use` stamps a conversion clock and transfers ownership after
   `ttt_ankh_conversion_time` (6 s), and the entity's own Think cancels the whole thing the moment the activator
   stops looking at it (100 unit `MASK_SHOT` trace) or stops holding `IN_USE`. A Graverobber may take *any* ankh
   while it owns none; a Pharaoh may only take back the one that was taken from him.
4. The owner's death is not the end: `TTT2PostPlayerDeath` calls `Revive(ttt_ankh_respawn_time, ...)` at the ankh
   for 50 health and consumes it. **No input, nothing to implement** - a bot Pharaoh already came back before
   any of this.

**What a bot could not do.** Place the ankh (nothing fires a `WEAPON_EXTRA` item; the inventory never equips
one), or convert one (needs the key held for six seconds). It could die and revive correctly on its own, so
before this section a bot Pharaoh was a plain innocent with an item it never used, and a bot Graverobber was a
plain traitor.

**The one new API: holding `+use`.** movement register #19 has the full entry. In short: a bot cannot send the
key, an entity with `CONTINUOUS_USE` polls `KeyDown(IN_USE)`, and the framework had no way to say "hold this
key" - `BotLocomotor:SetUse` looked like it did, but nothing had ever called it and on TTT2 its door block calls
`Door:ToggleDoor` directly rather than pressing the key. `SetHoldUse(true)` is a real hold: `StartCommand` writes
IN_USE every tick until something clears it. The old flag was deliberately left dormant rather than reused,
because `DetectDoorNearby` searches a **sphere** of 100 units rather than what the bot is looking at - sharing
one flag would have had a converting bot opening and closing every door beside it, once a second, for six
seconds.

**The four behaviours.** All four are registered in the shared `PriorityNodes` groups (three in `Restore`, one in
`FightBack`) rather than in per-role trees, because both roles are otherwise ordinary innocent/traitor roles - a
custom tree would only be the default one plus a node, and the Graverobber is handed to a bot *mid-round* rather
than chosen at spawn:

- [`behaviors/placeankh.lua`](lua/tttbots2/behaviors/placeankh.lua) - picks a spot the weapon will accept before
  spending the single-use item, using the weapon's own three tests (flat, world, within reach) rather than
  pressing and hoping. It retries a few times, because `plyspawn.IsSpawnPointSafe` cannot be predicted from
  outside, and it is `Interruptible = false` with a hard deadline: while it holds the ankh weapon it must never
  be handed to `Attack.Engage`, because the weapon's trace ignores players and a shot "at" somebody would place
  the ankh on the floor at their feet.
- [`behaviors/stealankh.lua`](lua/tttbots2/behaviors/stealankh.lua) - walks in, holds `+use` and calls
  `Ankh:Use(bot, bot)` itself (the `station:Use(bot)` shape from `usehealthstation.lua`), so it does not depend
  on a bot's fake client dispatching the use. It mirrors the addon's own gate, including the asymmetry above,
  and gives up after the conversion window plus slack instead of standing there forever.
- [`behaviors/moveankh.lua`](lua/tttbots2/behaviors/moveankh.lua) - the owner picking its own ankh up to move it.
  It calls `ENT:UseOverride` (the release handler) directly *without* pressing the key first, because pressing is
  what sets `last_activator`, and the addon refuses a pickup from anybody who was "previously converting". It
  only moves the ankh once a living non-ally has line of sight to it, and only when a hiding spot exists to move
  it to; the budget is two moves per round with a 45 second cooldown, because while the owner carries the ankh it
  has no respawn point and no heal.
- [`behaviors/breakankh.lua`](lua/tttbots2/behaviors/breakankh.lua) - shooting a non-ally's ankh down (500 health
  by default). It sits *after* `AttackTarget` in `FightBack` and is interruptible, so a person always comes
  first; it only shoots when the owner is alive (denying the respawn and the heal) or mid-revival (which cancels
  the revive outright), and it gives up after 20 seconds. Roles flagged `SetDealsNoDamage` are skipped, since
  the addon asks `TTT2PharaohPreventDamageToAnkh` before applying any damage.

**The two profiles.** [`roles/pharaoh.lua`](lua/tttbots2/roles/pharaoh.lua) and
[`roles/graverobber.lua`](lua/tttbots2/roles/graverobber.lua), registered under the role's **name** taken from
the `PHARAOH`/`GRAVEROBBER` globals (rule 7). The Pharaoh mirrors `innocent.lua` exactly, empty allied sets
included - it is no more omniscient than any other innocent. The Graverobber mirrors `traitor.lua` and adds
nothing, which is the point: the addon handed it to a bot that was already playing a traitor and the bot should
not change how it plays.

`SetRoleWeapons({ "weapon_ttt_ankh" })` is the one non-obvious flag, and it is deliberately on the Pharaoh
only. `m_roleWeapons` is a single-slot map, so a second registration would just overwrite the first. Its only
reader is `getWeaponTell` in the morality component, which is **team-guarded**: a role weapon only gives
somebody away when its role is on another team, so this registration is deliberately not a tell for any bot on
the innocents' side - the first innocent-team role weapon the map has ever held, and that guard is what makes it
safe. Traitors do not use suspicion at all; a neutral role that does would read it as "that player is the
Pharaoh".

**Deliberate limits, all of them written down where they bite:** two relocations per round with a cooldown
(above), `Interruptible = false` on placement but a hard deadline, 20 seconds on the ankh-shooting node, and one
entity scan per tick shared by every bot (`getAnkhs` in `breakankh.lua`, the soda-can cache's shape) rather than
one per bot, since that node is in the shared `FightBack` group.

**Recorded, not worked around:**

- `PHARAOH_HANDLER.ankhs` is keyed by `ply:SteamID64()`, so two ankhs coexisting relies on bots having distinct
  non-nil ids. With `maximum = 1` Pharaoh per round it cannot bite, and nothing here depends on it.
- The chatter line for a role weapon is worded for a *traitor's* weapon (`HoldingTraitorWeapon`), so the one
  non-innocent-team bot that could notice the Pharaoh's ankh weapon would use the wrong words. Cosmetic, and
  changing the wording means a new chatter key for every role weapon - parked.
- `ttt_ankh_graverobber_pickup` ships **off**, so a bot Graverobber cannot move an ankh by default; that is the
  addon's intent, not a gap here.
- The Ankh's respawn is entirely the addon's, gated on `ttt_ankh_respawn_time` (10 s) and
  `ttt_ankh_respawn_protection_time` (4 s). Nothing in this addon touches it.

**New cvar:** `ttt_bot_use_ankh` (default 1) gates all four nodes at once. Every node double-checks the addon's
globals too, so a server without `ttt2-role_pha` pays one nil check per bot per tick and nothing else.

**Verification:** `node tools/glua-check/check.js` -> **127 files, 0 issues, 2 notes** (both pre-existing).
GluaLint clean on all six new files; the whole-tree count is unchanged at 174 warning lines.

---

## 34. The Jester and the Swapper fighting in the post-round deathmatch - a target rule with no role check

**Report:** "jester and its variant are attacking others in post round deathmatch even though they cant deal any
damage. Can you steer their behavior into hiding instead of fighting since they cant deal any damage?"

**Cause, in one line:** the deathmatch hands *every* living bot a target, and the only thing that stops a
damage-less role from acting on one is a flag the Jester and the Swapper do not carry.

- [`BotMorality:SetDeathmatchTarget`](lua/tttbots2/components/sv_morality.lua:316) - the post-round producer -
  picks a random living player, writes it into memory and calls `SetAttackTarget`, once a second per bot, with
  **no role check at all**.
- The round-time producer, `SetRandomNearbyTarget`, does check one thing: `GetStartsFights`, which
  `roles/jester.lua` sets to *true* on purpose - baiting a death is how a fool wins.
- What actually kept the Beggar, the Collusionist and the Cursed out of these fights is
  [`Attack.ValidateTarget`](lua/tttbots2/behaviors/attacktarget.lua:679), which clears the target for
  `GetDealsNoDamage` roles. The Jester and the Swapper were never given that flag, so they chased and shot.
- Withholding the target alone would not have been enough anyway: the Jester's tree is
  `FightBack, Restore, Stalk, Minge, Investigate, Patrol`, and `Stalk` and `MingeCrowbar` both walk the bot *at*
  people.

**Fix, in three pieces:**

1. **`TTTBots.Roles.IsNonCombatant(ply)`** ([`sv_roles.lua`](lua/tttbots2/lib/sv_roles.lua:138)) - one answer to
   "can this player take part in a shooting fight at all": its addon zeroes the damage it deals (the Beggar, the
   Collusionist, the Cursed), or nobody can damage it (the Swapper), or it is a fool role (`IsFoolRole`, the
   jesters' team, which is the Jester and both of those).
2. **The deathmatch rule asks it**, and clears any target the bot was holding; `SetRandomNearbyTarget` asks it
   too, but only while the deathmatch is on - during a round the Jester's fight-picking is the role, and the
   Swapper roams because roaming is how it gets killed.
3. **[`behaviors/evade.lua`](lua/tttbots2/behaviors/evade.lua)** (new) - the hiding itself. A `Survive` node at
   the head of the tree: it walks to a hiding spot that no living player can see and that is as far from whoever
   is nearest as its samples allow, re-picks when somebody sees it, and never fires.

**Why `Survive` is a new group, and where it went:** it is the first entry of the three default trees
([`sv_tree.lua`](lua/tttbots2/lib/sv_tree.lua:66)) and of the five hand-written trees belonging to the roles that
can be non-combatant - `jester`, `swapper`, `collusionist`, `beggar`, `cursed`. Being *first* is the design: a
bot running it never reaches `AttackTarget`, `Stalk` or `MingeCrowbar`, which is what makes "stop fighting" stick
even when something handed it a target a tick ago. The one footgun left behind: a role file with a custom tree
whose role is a non-combatant has to add `_prior.Survive` itself, and that is written into the register as well.

**Not verified from source, and recorded as such:** the Jester's addon is not reachable from this machine
(`TTT-2/ttt2-role_jester` does not exist, and a GitHub search for it returns nothing), so "the Jester cannot deal
damage" rests on the report plus our own recorded note on the Swapper - whose profile has said "deals no damage
to players and takes none from them" since it was written. If the Jester *can* damage after all, this fix is
still right for the Swapper and still what was asked for; it would simply be hiding one bot that could have
fought.

**Choices made on purpose:**

- No new convar. The deathmatch already has one (`ttt_bot_deathmatch`), and this is a correction to a fight the
  bot cannot win rather than a feature to switch off.
- Spot candidates are **sampled** (12 a pick) rather than scanned, and re-picks are rate-limited to one every two
  seconds, so the cost does not scale with the size of a map's hiding category.
- The other bots may still shoot these bots during the deathmatch. It is a free-for-all, and a fool being shot is
  the least surprising thing in one.
- The node is interruptible and returns SUCCESS the moment the deathmatch ends, the bot dies, or its role changes
  under it - a Beggar that loots a shop weapon is no longer a non-combatant and goes straight back to playing.

**Verification:** `node tools/glua-check/check.js` -> **128 files, 0 issues, 2 notes** (both pre-existing).
GluaLint clean on `behaviors/evade.lua`, and the whole-tree count is unchanged at 174 warning lines - every
warning reported in the touched files is on a line this section did not write.

---

## 36. The Mesmerist's defib was letting the trigger up too early - and the release is what cancels the revive

**Report:** "Mesmerist role is not reviving the dead bodies properly, as in they held the attack button a bit too
short. Perhaps add a few more ticks to it?"

**What the addon actually does** (read from its source, `ZacharyHinds/ttt2-role-mesmerist`, cloned for this):

- `weapon_ttt_mesdefi.lua`'s `SWEP:PrimaryAttack` starts a **timed** revival - `ply:Revive(reviveTime, onRevive,
  doCheck, true, true)` with `reviveTime = GetConVar("ttt2_mesdefi_revive_time"):GetFloat()`, which is **3 s by
  default and whose own settings slider goes to 30**.
- `SWEP:Think` cancels that revival outright if `not owner:KeyDown(IN_ATTACK)`, if the eye trace leaves the body,
  or if the active weapon is no longer the defib. So a released trigger does not end an attempt, it *kills* one.
- The charge is spent in `SWEP:FinishRevival`, which the revival's own `doCheck` calls when the timer completes -
  so "the charge dropped" really does mean "the attempt resolved", which is what this behaviour already watched.

**Two ways the behaviour was the thing killing its own attempt:**

1. **The hold budget was a flat six seconds** (`DEFIB_MAX_TIME`). It is now `getHoldBudget()`: the longer of six
   seconds and the weapon's own convar plus four seconds of slack. Any server with that slider above six had a
   bot guaranteed to drop the button mid-revival, which is exactly the report.
2. **`Defib.IsRevivableBody(rag)` was asked every tick, including while the trigger was down.** It is
   `lib.IsValidBody`, which means "valid *and still linked to a player*" - so anything that unlinks the corpse
   during a pending revival reads as "not revivable", the node returns FAILURE, `StopReviving` lets the button up,
   and the weapon cancels the revival the bot was in the middle of. It is now asked only *before* the hold begins.
   Whether TTT2 unlinks the corpse while a revival is pending, I did not chase: what is certain is that the check
   had exactly one way to fail, and that failure path is the cancellation itself.

Also kept, and now with its reason written down: `inventory:PauseAutoSwitch()` and `bot:SetActiveWeapon(defib)`
every tick while holding, because a weapon switch is the third cancellation path in that Think.

**Verification:** glua-check 128 files, 0 issues, 2 notes. GluaLint clean on `behaviors/defib.lua`.

---

## 37. "Tried to use a NULL entity!" once a second - a NULL attack target in the tick's visibility cache

**Report:**

```
[ttt2bots] addons/ttt2bots/lua/tttbots2/lib/sh_botlib.lua:276: Tried to use a NULL entity!
  1. unknown - addons/ttt2bots/lua/tttbots2/sh_tttbots2.lua:145
```

**Reading the trace:** `sh_botlib.lua:276` is `answer = bot:Visible(target)` inside `Lib.SeenThisTick`, and
`sh_tttbots2.lua:145` is the `ErrorNoHaltWithStack` that runs *after* the tick's `pcall` - so that frame is the
error handler, not the caller. Line 276 is simply being reached with something that is not an entity.

**Cause:** `Player:Visible(NULL)` throws exactly that message, and NULL is a value this codebase really does pass
around: `sv_morality.lua` guards `closest ~= NULL` before calling `SetAttackTarget`, so a lookup handing back NULL
rather than nil is a known shape in this tree. `plyMeta:SetAttackTarget` stored whatever it was given, so a single
NULL became `bot.attackTarget = NULL`, and every reader of the tick cache then called a method on it. Note this is
a latent bug the per-tick visibility cache (31) made *loud* rather than a new one: before the cache, the same
value went into a trace call, which fails the same way but only at the moment it is used.

**Fix, in two places, on purpose:**

- **`plyMeta:SetAttackTarget` normalises** - `if not IsValid(target) then target = nil end` before anything else,
  which covers every caller at once including one written later that forgets, and keeps the early-out comparison
  honest.
- **`Lib.SeenThisTick` refuses to call a method on a non-entity** and answers "no" instead. The setter covers the
  field; this covers a field some future code assigns directly.

**Verification:** glua-check 128 files, 0 issues, 2 notes; GluaLint reports nothing on either changed line (the two
files' other warnings are the pre-existing ones, 12 in the locomotor and 13 in the shared lib).

---

## 38. `evade.lua` threw "bad argument #1 to 'Visible' (Entity expected, got userdata)" - a comment that was wrong

**Report:**

```
[ttt2bots] addons/ttt2bots/lua/tttbots2/behaviors/evade.lua:75: bad argument #1 to 'Visible' (Entity expected, got userdata)
  1. unknown - addons/ttt2bots/lua/tttbots2/sh_tttbots2.lua:145 (x36)
```

**Mine, and precisely the mistake rule 5 exists for.** The hiding node asked whether a player could see a hiding
spot with `other:Visible(pos)` - and `Player:Visible` takes an **entity**. A nav spot is a `Vector`, so every call
threw, once a tick, for every bot running the node (36 times before anyone looked). The call was justified by a
comment I had written directly above it without checking: "`Player:Visible` takes a position as well as an entity."
The wrong comment *was* the bug's whole licence, and the runtime is what caught it - rule 5 one layer up from where
it usually bites, since this time the false claim was the reason the code existed rather than a note beside it.

**Fix:** use [`TTTBots.Lib.CanSeeArc`](lua/tttbots2/lib/sh_botlib.lua:383), the framework's existing
position-based visibility test. At a full 360 degree arc its angle check cannot fail, so what is left is
`Player:VisibleVec(pos)` - the right call for a position, and already the shape the morality component uses when it
asks whether a bot can see somebody. The probe is aimed a body's height above the spot (`+ Vector(0, 0, 24)`),
the same offset morality uses, because a trace to a nav point ends *in* the floor it stands on and reads as
blocked by everything.

**Cost, for the record:** one trace per observer per candidate spot, so a re-pick (12 samples) is at most a couple
of hundred traces, every two seconds, for the one or two bots that can be non-combatant in a deathmatch. It stops
at the first observer who can see the spot, which is the common case for a bad spot and the rare case for a good
one. Both the node's own position check and its spot check go through the same function.

**Verification:** glua-check 128 files, 0 issues, 2 notes; GluaLint clean on `behaviors/evade.lua`.

---

## 39. The addon asked "can I see that player" with an NPC function - one server cvar could blind every bot

**Found by** the `gmodwiki` MCP server, in its first four lookups. It was brought in to confirm the primitive
behind section 38's fix and, while doing that, produced the page for the function the whole visibility system was
built on.

**What the wiki says about `Entity:Visible`**, which is what [`Lib.SeenThisTick`](lua/tttbots2/lib/sh_botlib.lua:259)
used for every answer:

- "This is meant to be used only with **NPCs**";
- "If `ai_ignoreplayers` is turned on and target is a player, **returns false**";
- "If target has `FL_NOTARGET`, returns false";
- and it traces with `MASK_BLOCKLOS`-flavoured masks and a custom `CTraceFilterLOS` rather than a shot trace.

On a server with `ai_ignoreplayers 1` every visual answer a bot gets is therefore "no": no targets, no shooting, no
grenades, no stalking, none of the witnessed-combat or red-handed suspicion. One cvar, silent, total blindness -
and none of `ai_ignoreplayers`, `FL_NOTARGET` or `ai_LOS_mode` is set or read anywhere in this tree, so it was
never ours to notice.

**How it got there, which is the lesson.** Before the performance sweep (31) the addon had its own answer,
[`Lib.CanSee`](lua/tttbots2/lib/sh_botlib.lua:355): three `MASK_SHOT` traces to the target's eyes, centre and
feet. The sweep centralised the hot path onto `SeenThisTick` for a real win - four to six asks per pair per tick
became one - but it centralised onto an *existing* primitive rather than the *correct* one, and in doing so
replaced a shot-accurate test with an NPC line-of-sight test. Nothing failed loudly, because on a default server
the two agree.

**The fix.** [`Lib.CanSeeEntity(ply, target)`](lua/tttbots2/lib/sh_botlib.lua:377) is now the single answer to an
entity question: a player goes through the existing three-point `CanSee`, anything else is one trace to its centre.
`SeenThisTick` calls it (keeping the per-tick memoisation and the non-entity guard from 37), the isolation cache in
`updateIsolationCache` calls it, and the ten files that asked `X:Visible(Y)` directly were converted: morality
(red-handed, witnessed combat, corpse in view), the locomotor (nearby players, the random look target), `curseswap`,
`createsidekick`, `createdeputy`, `hiddenstalk`, `investigatecorpse`, `shankerstalk`, `stalk` and `throwgrenade`.

**Deliberately unchanged: every position question.** `Entity:VisibleVec` takes a vector, is documented as a plain
trace and carries none of those caveats, so the spot, corpse and noise checks (morality, locomotor,
`investigatenoise`, `investigatecorpse`, memory, `plantbomb`, `paranoid`, `attacktarget` and `CanSeeArc` itself)
stay on it - including section 38's fix, which is what prompted this.

**The end state is checkable:** a grep for `:Visible(` across `lua/tttbots2` returns four comment blocks and no
calls at all - the section 37 and section 38 notes, a historical note in `shinigami.lua`, and one commented-out
snippet in `createdeputy.lua` that mirrors the live line in `createsidekick.lua`.

**Cost.** The common direction (an unobstructed target) is still *one* trace, because `CanSee` returns at the eyes
and only falls through to centre and feet when they are blocked. The memoisation is untouched, so the sweep's
saving stands: this restores the accuracy the addon had before section 31 while keeping the sharing that section
introduced.

**Verification:** glua-check 128 files, 0 issues, 2 notes. GluaLint: no new warnings - the big files still report
exactly their previous counts (13 in `sh_botlib`, 6 in `sv_morality`, 12 in `sv_locomotor`) and the six warnings
across `createsidekick`, `createdeputy` and `stalk` are the pre-existing shadowing, parenthesis and double-if ones,
none of them on a line this section touched.

---

## 40. Three per-tick entity scans - two fixed, the third already cached, and the index that found them

**Provenance.** This one came from a question rather than a report: whether a newly enabled codebase index (the
editor's semantic one) is any use for finding mistakes across the tree. It is, for one narrow class of question -
"what runs every tick and loops over all players", "which entity scans are uncached" - and it is no use at all for
two others: it cannot judge an API's contract (39 came from the wiki, not the index) and it cannot measure, so it
ranks a once-per-purchase scan beside a per-tick one. It is a lead generator, and every hit below was confirmed by
reading the file it pointed at.

**What it surfaced:** three `ents.FindByClass` / `ents.FindInSphere` sites outside the lib, so the sweep became
"for each one - is it hot, and is there a cached twin already in the tree?" Two had a cached twin. One did not.

1. **The health-station scan, [`behaviors/usehealthstation.lua`](lua/tttbots2/behaviors/usehealthstation.lua)** -
   the real find. `Validate` computed `(bot.targetStation or GetNearestStation(bot) ~= nil)` **before** the
   `return hasHealthStation or (isHurt and isStationNearby)` short-circuit, so every bot on the server - healthy,
   or already carrying a station - paid for a world scan on every pass through the tree, and each call rebuilt a
   filtered table besides. **Fix:** the valid stations are cached for a second (`getValidStations`, next to
   `ValidateStation`), and `Validate` is reordered so the scan is the last thing paid for and only by a bot that
   has a use for it: carrying a station returns true first (a weapon lookup, not a scan), then a bot at full
   health returns false. The result is unchanged - an empty list gives `nil` from `GetClosest` either way, and
   `OnRunning` still re-validates the station it is walking to on every tick. **One deliberate behaviour change:**
   the cached `bot.targetStation` is now read with `IsValid` rather than for truthiness. A removed station is the
   NULL entity, which is truthy (8), so it used to start the behaviour and fail on its first tick; now the nearest
   station is looked up instead.
2. **The soda-can queries, [`behaviors/drinksoda.lua`](lua/tttbots2/behaviors/drinksoda.lua) and
   [`behaviors/placefakesoda.lua`](lua/tttbots2/behaviors/placefakesoda.lua)** - two files asking the same
   question, one with a cache and one without. `drinksoda.lua` had its own one-second `getCans()`; the decoy
   behaviour scanned `ents.FindByClass("soda_*")` directly, once to decide whether the buyable is worth buying and
   once per tick in `FindNearbyCan`. **Fix:** the cache moved into the lib as
   [`Lib.GetSodaCans`](lua/tttbots2/lib/sh_botlib.lua:105), beside the alive-player cache it copies, and both
   behaviours read it - one entity scan for the whole addon per second instead of one per bot per tick, the same
   reasoning as the ankh cache in 33. **Deliberately *not* shared: the clearance test.** `GetGroundSpot` scans a
   28-unit sphere and calls `isASoda`, a `string.find(class, "soda")` test - and the Fake Soda addon's own cans are
   `ent_ttt2_fake_soda_*` (read from `mexikoedi/ttt2_fake_soda`, cloned to `.roo/refs/fakesoda`), which a `soda_*`
   query does not match. Routing that one through the can cache would have let a bot drop decoy on decoy. It keeps
   its radius scan, with a comment saying why, so the next sweep does not "fix" it (rule 13).
3. **The barrel scan, [`Lib.GetClosestBarrel`](lua/tttbots2/lib/sh_botlib.lua:54) and
   [`Attack.TargetNextToBarrel`](lua/tttbots2/behaviors/attacktarget.lua:275)** - already handled, and the reason
   section 8 exists. Its only caller serves a three-second per-target cache that re-validates what it hands back,
   so the 128-unit sphere scan runs once per bot per target per three seconds, not per tick. **Left alone.** The
   index could not tell the difference between this and the health-station scan; reading the one caller could.

**Verification:** `node tools/glua-check/check.js` -> 128 files, 0 issues, 2 notes (unchanged). GluaLint: whole
tree **174 warning lines across 128 files**, unmoved - per file `sh_botlib.lua` 13 (its previous count, so the new
function added nothing) and `drinksoda.lua`, `placefakesoda.lua` and `usehealthstation.lua` 0 each.
