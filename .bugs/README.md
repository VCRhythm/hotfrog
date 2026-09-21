# hotfrog — notes for bug fixers

Roblox (Luau, `--!strict`) port of HotFrog, a Unity 2D physics climber. Rojo syncs `src/` into
Studio one-way (`rojo serve` is always already running; never start your own); edit files on disk
only. Root-level `Core/ Player/ Entities/ Spawning/ Input/ ...` are the **read-only Unity C#
original**: Luau files cite the C# file they port — read it for "how should this behave".
`CLAUDE.md` has the full architecture map; read it first.

## Verification
- No unit-test suite. Headless static checks (all must pass on touched files):
  `stylua --check <files>`, `selene src/`, `bash tools/luau_check.sh <file>`,
  `rojo build default.project.json --output build.rbxl`.
- Live game: the `Roblox_Studio` MCP: `get_studio_state`, `start_stop_play`,
  `get_console_output`, `execute_luau`, `inspect_instance`, `search_game_tree`, `screen_capture`
  (use it for anything visual). Sequence: check state, start play, wait 5 to 10 s, read console
  or run Luau, capture if visual, stop play. Never edit files while a playtest runs. If a play
  session is already live, the user is playing: inspect only, do not start/stop it. If the MCP is
  not attached, report `verified: not run: Studio only`; never claim a pass.
- Headless Luau in the published place: `python tools/luau_exec.py --script "..."`.

## Entry points
- Server: `src/server/GameServer.server.luau` (frog sim, steps, grab validation, pull, score;
  remote list at the top). Per-lane logic: `src/server/Lane.luau`.
- Client: `src/client/GameClient.client.luau` (input, snap-assist grab picking, camera, HUD),
  `MenuClient` (run-state UI), `World*.client.luau` cosmetics (must not move server parts).
- Shared config: `src/shared/Config.luau` (tuning), `Levels.luau`, `StepKinds.luau`,
  `StepBehaviors.luau`, `PullMath.luau`, `WorldConfig.luau`.

## Area -> files
- Grabbing / reach / hit detection: `GameClient` (nearest step to cursor), `GameServer` (GrabStep
  validation), `Config.luau` reach constants, `src/client/world/GrabTarget.luau`.
- Step kinds, sizes, sprites: `src/shared/StepKinds.luau`, `src/assets/StepTemplate.model.json`.
- Frog rig, limbs, fall/death: `GameServer` + `src/assets/FrogModel.model.json`,
  `WorldFrogCosmetics.client.luau`; Unity: `Player/Frog.cs`, `Player/Limb.cs`.
- Level flow/spawning: `Lane.luau`, `Levels.luau`; Unity `Spawning/`.
- Art binding: `src/shared/SpriteSkin.luau`, `SkinAssets.luau` (Ids table generated; don't hand-edit ids).
- Sound: `SoundFX.luau`, `SoundAssets.luau`, `SfxEvents.client.luau`.
- Bugs (flies): `src/server/BugService.server.luau`.
- Persistence: `src/server/Profiles.luau`.

## Tests to extend
None exist; verify with the static checks plus an MCP playtest.

## Automatic entries
Entries whose note starts with `AUTO error` / `AUTO warning` were filed by the capture
module from runtime output, not by a person. `context.auto.message` and
`context.auto.trace` hold the full text and stack; `context.log` is the output around it.
Fix errors. Never add a global mute.

## Design rulings
`docs/roblox-port/17-status-and-known-gaps.md` lists every deliberate deviation from Unity;
also docs 11–13 (prefab dumps = source of truth for values). A report that contradicts a
recorded deviation is `needs-decision`, not a fix. Update doc 17 when you add a deviation.
The working tree may carry the user's uncommitted edits (PullMath, SkinAssets, SkinCatalog,
WorldConfig) — build on them, never revert them.
