# Changelog

## v1.4.0 (unreleased)

A long pass over role support and over how bots move and fight. `WORKING_NOTES.md` holds the reasoning, the
verified sources and the traps behind every line below; it is not part of the addon.

### Added

- **TTT2** Role support for the Cursed, the Revenant, and the Pharaoh with its Graverobber. The last two are one
  addon's pair of roles: placing the Ankh is what turns a random traitor into the Graverobber, so they are
  supported together. All four of the Ankh's verbs work - placing it, converting it, carrying it somewhere
  safer, and shooting a non-ally's down - behind `ttt_bot_use_ankh`.
- **TTT2** Bots throw the grenades they are carrying (`ttt_bot_throw_nades`), pulling the pin and *then*
  throwing, the way the weapon is built.
- **TTT2** Bots drink Super Soda cans (`ttt_bot_use_soda`) and use a Fake Soda decoy where a can belongs
  (`ttt_bot_place_fake_soda`).
- **TTT2** Bots use the Boom Body (`ttt_bot_use_boom_body`), the Thomas the Tank Engine gun (`ttt_bot_use_thomas`)
  and the Minethrower (`ttt_bot_use_minethrower`) when they are carrying one.
- **TTT2** A new plan target, `POPULAR_SNIPERSPOT`, which sends a bot to a perch overlooking a busy area, plus a
  popularity map behind the sniper, hiding and bomb spot categories.
- **TTT2** Bots work out who killed somebody: they track a loiterer near a body and can act on the killer TTT2
  records on a ragdoll, inside that system's own DNA range and decay.

### Changed

- **TTT2** Traitors no longer open fire the instant a round begins. Every path that hands a bot a victim - the
  random nearby roll, the plan system's attack orders and the last-player-standing rule - now shares one gate,
  `ttt_bot_attack_delay`, and that gate is measured against the round clock **and** the bot's own life, so a
  bot that was revived into an old round waits too.
- Melee bots close to their weapon's real reach. The attack behaviour used a 160-unit "melee range" measured
  between two players' feet, while every melee weapon traces 100 units from the eye (80 for the Shanker's
  knife), so the Roider, the Shinigami and the Shanker kept stopping short and swinging at air.
- A bot only walks to a sniper perch if it is actually carrying a weapon that can use one.
- `ttt_bot_attack_delay` is now the single knob for "not yet", rather than one of three half-applied timers.
- Bots no longer all wander to the same place. The popularity map is sorted most-popular-first, and the wander
  picker, the loves-crowds/loner picker and the plan coordinator's "popular area" job each read it from the top -
  which is one answer for every bot on the server, so a quiet round sent the whole lobby to a single corner. They
  now choose between the busiest few, and a bot avoids a destination another bot is already walking to (the claim
  is that bot's live goal, so it expires by itself when it picks somewhere else).
- A bot announcing a KOS now actually registers one, so the rest of the team hears it and their suspicion moves -
  previously the callout was decorative and the KOS list was never read by anything. Gated by a new
  `ttt_bot_kos_chance` (50% by default): 0 makes bot callouts flavour text again, 100 makes every announcement
  real. The existing per-caller `ttt_bot_kos_limit` still applies.
- Traitors ordered to follow a human no longer all follow the same person. The job allowed the whole team to take
  it, and with one human traitor they all resolved the same name; each bot now prefers somebody another bot is not
  already following.

### Fixed

- **TTT2** The Blocker's hand-written profile was being filed under the role's numeric index instead of its
  name, so no lookup ever found it and the role behaved generically. Any role file written that way has the
  same silent failure; the rule is now written down.
- **TTT2** Bots in roles that cannot fight no longer attack during the post-round deathmatch - the Jester, the
  Swapper, and the roles whose addons zero their damage, such as the Beggar and the Collusionist. They hide from
  everybody instead of walking into a fight they cannot win.
- Bots no longer ask whether they can see somebody through `Entity:Visible`. That is an NPC function which returns
  false for every player on a server that sets `ai_ignoreplayers`, and false for anyone carrying `FL_NOTARGET` -
  either one silently blinding every bot. The answer is now the addon's own shot trace: three points on a player,
  the centre for anything else. Position checks (spots, corpses, noises) keep the vector test, which never had
  those caveats.
- The hiding behaviour used in the post-round deathmatch no longer throws once a tick: it asked whether a player
  could see a position with `Player:Visible`, which only accepts an entity.
- **TTT2** Defibrillator revives are held for as long as the weapon's own revive timer asks for, instead of a flat
  six seconds. The defibrillators cancel a revival the moment the trigger is released, so a bot letting go early
  was killing its own attempt - most visibly the Mesmerist, whose revive timer is a setting that goes up to 30.
- A `NULL` attack target no longer reaches the per-tick visibility check, which used to throw "Tried to use a NULL
  entity!" roughly once a second for as long as the bot held it.
- The health-station behaviour no longer trusts a station that has already been removed from the world: a removed
  entity is the `NULL` entity rather than `nil`, and the cached station it is holding is now checked with `IsValid`.
- **TTT2** Bots no longer make gameplay callouts while dead, and no longer plant two C4s in the same spot.
- **TTT2** Bots no longer freeze at gunshots, or "see through floors" when a shot lands below them.
- **TTT2** RDM has a minimum time (`ttt_bot_rdm_delay`), and an invalid `ParanoidKiller` suspicion reason was fixed.
- Fewer bots idle or circling one area when only a few are left, and fewer stuck on ladders or on geometry.
- The whole-tree audit fixed a deputy tree with no investigate group and two broken French locale categories.
- The bot-disconnect console line no longer claims a bot disconnected when it did not.
- The C4 countdown workaround was **deleted rather than fixed**: the "53 mins" that was reported on a
  45-second fuse was TTT2 drawing hours, minutes and seconds, not a broken timer.

### Performance

- The path-finder's A\* search uses a binary heap and id-keyed sets instead of an array sorted on every step,
  and a per-path CPU/frame report sits behind `ttt_bot_debug_pathfinding`.
- "Can this bot see that player" is answered once per tick per pair and shared, instead of the memory pass, the
  attack behaviour, the ADS check, the inventory and four morality passes each firing their own traces.
- Per-tick allocation churn and one per-tick world scan were removed.
- The health-station lookup is cached and now runs last, behind its own guards: it used to be a world scan on every
  pass through the behaviour tree for **every** bot, including one that was already carrying a station and one at
  full health, neither of which has anything to walk to a station for.
- The two soda-can lookups share one cached list. The drink behaviour and the fake-soda decoy both asked the world
  for the same set of cans, one of them up to once per bot per tick and one of them with a cache already.
- The wander stare no longer traces every player on the server every tick: it picks its look-target at most once a
  second and holds it in between.
- The three Ankh behaviours share one cached entity scan per tick instead of two of them scanning the world each.
- `GetAllWitnesses` reads the already-alive player list instead of walking the whole server and filtering.
- `PlantBomb` reads the cached C4 list for its separation rule; arming still scans fresh, because the just-placed
  bomb is not in the one-second cache yet.

## v1.3.4

Another patch to prevent bots from opening doors they are not supposed to; targeting **TTT2**

## Fixed

- **TTT2** #64: Bots were able to open doors that were unopenable but technically not locked

## v1.3.3

This is a small patch targeting **TTT2**, fixing bots able to open locked doors as well as rate-limiting door interactions.

### Changed

- **TTT2** Rate-limit door interactions between bots to prevent traffic jams

### Fixed

- **TTT2** #64: Bots able to open locked doors

## v1.3.2

Merge of PR #62 via @ZeadenBeake -- adds support for multiple TTT2 roles.

### Added

- **TTT2** Role support: Sheriff

- **TTT2** Role support: Deputy

- **TTT2** Role support: Drunk

## v1.3.1

A small patch has been released.

### Fixed

- #60: Fix bots unable to use doors in TTT2, via @ZeadenBeake

### Changed

- Updated names list to include issue submitter @ZeadenBeake (#60)

## v1.3

A major feature overhaul, focused on fixing major bugs and adding some useful QOL features.

Next up will likely be the Traitor rework, but before then will be a patch to debloat the main repo. I.e., separate TTT Bots 2 maps into another repo.

### Added

- **TTT2** Bots will show their avatars in the top-right when their corpse is revealed. ([#41](https://github.com/thebigsleepjoe/TTT-Bots-2/issues/41))
^ Note: this is a little inconsistent, but AFAIK it's the best I will do for now.

- **TTT2** Role suppport for Bodyguard ([#37](https://github.com/thebigsleepjoe/TTT-Bots-2/issues/37))

- Added concommand `ttt_bot_nav_gen` to utilize Navmesh Optimizer for quick navmesh generation.

- Added `Decrowding` behavior to main bot classes. This behavior will make bots without the `lovesCrowds` attribute (most bots) try to find less populated areas when they feel too crowded.

- New `GetWeapons` behavior to fix issues plaguing the old `FindWeapon` behavior. This makes bots seek out weapons more intelligently.

- Added @EntranceJew's (the 1st other contributor of this repo) username to Community name pool :)

- Added some name suggestions from [discussion #47](https://github.com/thebigsleepjoe/TTT-Bots-2/discussions/47) into the community name pool.

### Changed

- Dramatically increased time interval between the Interaction behavior and the crowbar minge behavior. This should prevent the bots from grouping up too much.

- Increased `CommonSense` timer interval for optimization.

- Increased follow distance target so that bots following another player don't keep bumping into them (as much)

- Improved bot movement precision by reducing the pathfinding node 'complete' threshold.

- Bot avatar system no longer needs to sync with server, reducing bandwidth usage and increasing consitency.

- Overhauled bot brain functionality to prevent potential (rare) bugs, mostly related to bots doing nothing

### Removed

- Removed concommand `ttt_bot_nav_generate`, as it was outdated.

- No more difficulty-specific bot profile pictures due to unmaintainabiltiy

- Removed old `FindWeapon` behavior due to a number of headaches it caused.

### Fixed

- Lua error caused by quota trying to kick an uninitialized bot. Oops!

- Lua error related to plymeta:GetDifficulty

- Lua error related to fetching the BotLocomotor in one of the timers

- Fixed caching issue in inventory component which prevented caching from actually working.

- Fixed bots using the crowbar when they have ammo in the mag but none in the current mag.

- Mostly mitigated the issue in [#39](https://github.com/thebigsleepjoe/TTT-Bots-2/issues/39) where traitor bots would stare through walls at their target. Bots will not look at where they think an enemy is for more than 4 seconds.

- Bots will forget about their targets once they die, to prevent other behaviors from errantly being skipped (rare bug)

- Fixed InvestigateNoise behavior not including name/description metadata

- Fixed a funny bug where bots would congregate around health stations like a campfire. This was because they mistook the healing sound for gunshots.

# Developer Notes

- Added `ttt_bot_debug_brain` concommand to render a bot's latest behavior underneath them.

- New `Get/SetLovesTeammates` in RoleData to allow the Role definitions to understand if `Player:GetTeam()` can be used to test if two players are allied. Defaults to false; specifically useful for T roles.

## v1.2.2

Very small bugfix.

### Fixed

- A rare bug when a bot leaves could cause an issue with the silly chat system.

## v1.2.1-meta

This version brings mostly nominal changes. I.e., mostly chore tasks which do not effect gameplay. This is to overcome some technical debt and drastically increase long-term maintainability using LuaLS annotations.

This means more features can be developed quicker. The next actual version will likely be a feature release.

This build will probably not be going to steam due to it having minimal gameplay changes.

### Fixed

- Cache WeaponInfo class to prevent unnecessary computation.

- Traitor aggression now properly considers the bot's current rage level.

### Developer Notes

- Added a large number of class definitions and improved commenting across the entire codebase.

- There are no longer linting errors present using LuaLS. Which is saying a lot, as there were probably a hundred or so before these changes.

- Changed `Player:GetMorality` --> `Player:BotMorality` for consistency.

- BStatus is now a public enum, and can be found by querying the TTTBots global for the STATUS field (`TTTBots.STATUS`)

- Removed deprecated Follow.GetVisibleNavs function

- Removed deprecated Follow.GetRandomVisiblePointOnNavmeshTo function. (Holy, that was a long name)

- lib.GetComp is now obsolete. Use `Player:BotCOMPONENTNAME` instead. (e.g., `Player:BotLocomotor`)

- Added hook "TTTBotJoined" which is called AFTER full bot initialization. sv_miscnetwork now depends on this hook.

## v1.2

### Features

- Bots will sometimes nod, shake their head, and look players up and down when approached.

- Bots care about personal space and will get upset if you stay too close for too long. Builds some suspicion every 5 seconds if you're too close.

- **TTT2** Survivalist support. Survivalist bots will buy same (default) store items as if they were a detective.

- Bots can purchase UMP prototype and utilize it properly.

- **TTT2** Bots can use defibs to revive their allies. [This addon](https://steamcommunity.com/sharedfiles/filedetails/?id=2115944312) is required for this to happen.

- Bots can push you away with crowbars if you get too close. Some bots will do this much more often than others.

- Bots will avoid ladders with people on them, assuming there is another reasonable route available

- Bots will back away from people that are trying to melee them

- Bots will reload outside of combat more often, and reload when they can't see their enemy.

### Changes/Rebalances

- Bots will be less likely to target the head or strafe on lower difficulties.

- Placed cvars on shared realm, so clients can see them.

- Rebalanced bot inventory management. Bots will prioritize special weapons (e.g. UMP prototype) over normal weapons.

- Overall bot accuracy rebalance:

  1. Worse accuracy when the bot is moving.
  2. Worse accuracy when their target is moving.
  3. Worse accuracy when the bot or its target is in smoke.
  4. Better accuracy when the bot is stationary.
  5. Better accuracy when shoothing stationary targets.
  6. Focus system like CSGO bots, where they will increase in shooting accuracy when shooting at the same target over time. Affected heavily by personality.

- Decreased time between quote management updates (2.5s -> 1s)

- **TTT2** Improved behavior consistency between custom roles by unifying behavior trees (i.e., clumped together common sequences into priority nodes)

- Bots won't be repelled from one another when at a health station

### Fixed

- Retrying bug that threw errors on SRCDS servers. (#34)

- Bots trying to break unbreakable obstructions. (#33)

- Bot inaccuracy not correctly scaling over distances. It was hard-capped to a lower value than it should be.

- Sending too many net msgs to syncronize bot avatars. (reported per @EntranceJew)

- Bots will place their crosshair closer to the stomach when they lose sight of their enemy.

- No longer EthicalNotify if there are no bots in the game.

- Bots with a melee will no longer slow themselves down by stafing while approaching.

- **TTT2** Jackal will start fights to prevent stalling rounds.

### Developer Notes

This is a more technical explanation of the changes in this version, and contains useful change info for developers.

- Refactored locomotor-related code to be neater and use Player:BotLocomotor instead of grabbing bot.components.locomotor every time.

- Reworked the behavior tree for modularity and consistency. You can nest priority nodes (tables sorted by numbers) inside of other priority nodes, allowing behaviors to be neatly grouped together. This improves consistency between role behaviors.

- Buyables now test for mod presence before attempting to buy a weapon. There is also the option to define if a weapon is TTT2 specific, but this is optional.

- Added easier support for setting temporary variables in the Memory component.

- Locomotor now supports +attack2 for right click actions.
