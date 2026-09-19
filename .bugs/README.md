# hotfrog — notes for bug fixers

<!-- Written by /bugloop init. This file is the fixer subagent's map of the project.
     Keep it under 60 lines and write it for a stranger. Replace every TODO. -->

TODO: one line on what the project is, the language, and how source reaches the runtime
(e.g. "Rojo syncs src/ into Studio one-way; edit files on disk only").

## Verification
- TODO: how tests run (exact command, or "Studio only, opt-in attribute X"). If nothing
  can run headless, say so; fixers must then report `verified: not run: <reason>`.
- TODO: static checks that do run headless, with the exact command per file.
- TODO: tools that can observe the running app (MCP servers, log files) and their limits.

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
