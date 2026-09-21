# hotfrog — notes for bug fixers

<!-- Written by /bugloop init. This file is the fixer subagent's map of the project.
     Keep it under 60 lines and write it for a stranger. Replace every TODO. -->

TODO: one line on what the project is, the language, and how source reaches the runtime
(e.g. "Rojo syncs src/ into Studio one-way; edit files on disk only").

## Verification
- TODO: how tests run (exact command, or "Studio only, opt-in attribute X"). If nothing
  can run headless, say so; fixers must then report `verified: not run: <reason>`.
- TODO: static checks that do run headless, with the exact command per file.
- Live game: the `Roblox_Studio` MCP (registered in `.mcp.json`): `get_studio_state`,
  `start_stop_play`, `get_console_output`, `execute_luau`, `inspect_instance`,
  `search_game_tree`, `script_read`, `screen_capture` (use it for anything visual, such as
  whether a sprite actually renders). `rojo serve` is always already running; never start
  your own. Sequence: check state, start play, wait 5 to 10 s, read console or run Luau,
  capture the screen if the bug is visual, then stop play. Never edit files while a
  playtest runs; stop first, then edit. If a play session is already live, the user is
  playing: inspect only and do not start or stop it. If the MCP is not attached, report
  `verified: not run: Studio only`; never claim a pass.
- Headless Luau in the published place: `python tools/luau_exec.py --script "..."` (Open
  Cloud; needs `.env`). Good for asset metadata checks, not for rendering.

## Entry points
- TODO: server entry, client entry, shared config, remotes/messages.

## Area -> files
- TODO: 5 to 14 lines, most common bug areas first, verified paths only.

## Tests to extend
TODO: where tests live, the module shape, and "match the nearest existing test".

## Automatic entries
Entries whose note starts with `AUTO error` / `AUTO warning` were filed by the capture
module from runtime output, not by a person. `context.auto.message` and
`context.auto.trace` hold the full text and stack; `context.log` is the output around it.
Fix errors. A test that deliberately triggers a warning silences only that call in the
test (scoped silence); never add a global mute or a runner-wide ignore pattern.

## Design rulings
TODO: where design decisions are recorded (docs folder, memory). A bug report that
contradicts a ruling is a `needs-decision`, not a fix.
