# glua-check

GLua-aware static checks for this addon, built on the **GLua Enhanced**
(`venner.vscode-glua-enhanced`) extension that is already installed in this editor.

```powershell
node tools/glua-check/check.js
```

Exit codes: `0` clean, `1` findings, `2` the extension or its parser could not be found.

## Why this exists

`glualint` only looks at one file at a time and knows nothing about the Garry's Mod API; the old
Python sweep used `luaparser`, which cannot parse real GLua (it needs every `continue` rewritten to
`do end` before it will accept a file). The GLua Enhanced extension ships two things that close both
gaps, and neither of them requires the editor to be running:

| Source | What is taken from it |
| --- | --- |
| `dist/extension.bundle.js.map` -> `node_modules/gluaparse` | A real GLua parser: `continue`, `!=`, `&&`, `\|\|`, `!` and `//` all parse natively |
| `resources/wiki.json` | A GMod wiki scrape: 661 hooks, 334 globals, 133 libraries/classes with their members, 130 panels, 3000+ enum members |

Neither file is copied into this repository - the parser is extracted into the OS temp directory at
run time and cached there, so there is no third-party (GPL-3.0) source vendored into the addon.

`../TTT2-master` is read as a second source of truth: any hook, library member or global that TTT2
uses is treated as existing, which removes almost all of the false positives a wiki-only check would
produce (TTT2 adds dozens of members to GMod's libraries).

## What it checks

1. **Syntax** - every `lua/**/*.lua` parses under the GLua grammar.
2. **Hooks** - every `hook.Add` / `Remove` / `Run` / `Call` name is a real hook (wiki), a TTT2 hook,
   or a hook registered somewhere in this tree. Names that are called but registered nowhere are
   listed as notes: those are extension points for other addons.
3. **API** - `library.member` references and called globals that do not exist in the wiki database,
   e.g. a typo like `util.TraceLnie(...)` or `IsValdi(...)`.

A reference that the same file nil-checks first is reported as a *note* rather than a failure:

```lua
if not draw.DrawAvatar then return end -- deliberate feature detection for the TTT2 addon
```

That distinction matters: it is exactly how this addon integrates with TTT2's avatar cache and with
the Navmesh Optimizer addon, and neither reference can be resolved statically.

## Self-test

To confirm the checks still work, paste the block below into `lua/_gluacheck_selftest.lua`, run the
script (it should report 1 unknown hook and 2 API failures, exit code 1) and delete the file again:

```lua
util.TraceLnie(Vector(0, 0, 0))  -- bogus member of a real library -> API failure
hook.Run("PlayerSpawns")         -- typo of PlayerSpawn           -> unknown hook name
IsValdi(NULL)                    -- typo of IsValid               -> API failure

if not draw.DrawAvatr then return end -- feature detection -> API note, not a failure
draw.DrawAvatr()
```

## Limitations

- Members reached through a variable (`local lib = util; lib.TraceLine()`) are not checked.
- Methods on entities and panels (`ent:GetObserv…`) are not checked yet; only named libraries and
  classes are. Adding them needs an allowlist for the methods TTT2 and role addons bolt onto
  `Player` / `Entity`, otherwise the noise is not worth it.
- Enums are treated by naming convention (`ROLE_`, `TEAM_`, `STATUS_`, `SHOP_`, ... plus everything
  in `wiki.ENUMS`), and hook names must be string literals to be checked.
- `wiki.json` is a scrape, so it lags new GMod functions; a genuinely new engine function would be
  reported until the extension updates. That is the opposite failure mode to shipping a stale
  hard-coded list, but it is still a failure mode.
