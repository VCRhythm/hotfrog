# Reference scripts

Ready-to-paste Luau for the **basic Hotfrog loop**. These are the fleshed-out,
runnable versions of the illustrative snippets in
[../03-core-mechanics.md](../03-core-mechanics.md). They are a faithful-but-minimal
implementation — wire them up as below, press Play, and you get a climbable,
scoring prototype.

> These are still a starting point, not a shipped game: art is placeholder parts,
> tuning constants live in `Config`, and the client/server split is the pragmatic
> MVP one (see [../02-architecture-mapping.md](../02-architecture-mapping.md#decision-2-client--server-split)).
> Hardening against exploits and true multiplayer are covered in
> [../07-multiplayer.md](../07-multiplayer.md).

## Where each file goes in Studio

These filenames use the common Rojo suffix convention. If you're pasting by hand
in Studio, create the matching instance type and copy the body in.

| File here | Studio instance | Location |
|---|---|---|
| `Config.lua` | `ModuleScript` named `Config` | `ReplicatedStorage/Shared/` |
| `PullMath.lua` | `ModuleScript` named `PullMath` | `ReplicatedStorage/Shared/` |
| `GameServer.server.lua` | `Script` named `GameServer` | `ServerScriptService/` |
| `GameClient.client.lua` | `LocalScript` named `GameClient` | `StarterPlayer/StarterPlayerScripts/` |

The server auto-creates the `ReplicatedStorage/Remotes` folder and its
`RemoteEvent`s on first run, so you don't have to make them by hand.

## One-time scene setup (Milestone 1)

In `Workspace`, create a model `PlayField` containing:

- `Lava` — a wide, flat `Part`, anchored, positioned so its top sits at
  `Config.DESPAWN_Y` on the `Z = 0` plane.
- `Steps` — an empty `Folder` (spawned steps are parented here).

In `ReplicatedStorage`, create:

- `Shared` (Folder) — holds `Config` and `PullMath`.
- `Assets` (Folder) with:
  - `StepTemplate` — a small `Part` (anchored is fine; the server sets this),
    sized like a stepping stone.
  - `FrogModel` — a `Model` with `PrimaryPart` = a body `Part`, plus child parts
    named `Head`, `LeftLimb`, `RightLimb`. (Placeholder blocks are fine.)

Then paste the four scripts into the locations in the table above and press Play.

## What you should see

- The frog falls (accelerating) and, untouched, dies in the lava and respawns.
- Steps stream in from the top.
- Clicking/tapping a step makes a limb grab it; the whole field scrolls down a
  notch (you "climb"); the score ticks up.
- The HUD shows score and your persisted best (enable **Studio Access to API
  Services** for the DataStore to persist).

See [../04-build-roadmap.md](../04-build-roadmap.md) for the milestone-by-milestone
path and per-milestone verification.
