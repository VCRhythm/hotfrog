# 10 — Implementation Setup (source, toolchain & running it)

The reference implementation of the **basic loop** lives in the repo's
[`/src`](../../src) tree (real Luau, the source of truth), and a Rojo project syncs
it straight into Roblox Studio. These are the fleshed-out versions of the
illustrative snippets in [03-core-mechanics.md](03-core-mechanics.md) plus the
skins service from [08-frog-skins-and-store.md](08-frog-skins-and-store.md).

> Still a starting point, not a shipped game: art is placeholder parts, tuning
> lives in `Config`, and the client/server split is the pragmatic MVP one (see
> [02-architecture-mapping.md](02-architecture-mapping.md#decision-2-client--server-split)).
> Hardening and true multiplayer are in [07-multiplayer.md](07-multiplayer.md).

## Source layout

```
src/
  shared/    -> ReplicatedStorage.Shared      (ModuleScripts)
    Config.luau
    PullMath.luau
    SkinCatalog.luau
  server/    -> ServerScriptService.Server     (Scripts)
    GameServer.server.luau
    SkinService.server.luau
  client/    -> StarterPlayer.StarterPlayerScripts.Client   (LocalScript)
    GameClient.client.luau
```

The mapping is defined in [`default.project.json`](../../default.project.json).
Rojo creates the `Shared` / `Server` / `Client` folders and places each script;
Scripts and LocalScripts run regardless of nesting, so the wrapper folders don't
change behavior. The server auto-creates the `ReplicatedStorage/Remotes` folder and
its `RemoteEvent`s on first run, so you don't build those by hand.

## Toolchain

Tools are pinned in [`rokit.toml`](../../rokit.toml): **rojo** (sync/build),
**stylua** (format), **selene** (lint), **luau-lsp** (type-check). Install
[Rokit](https://github.com/rojo-rbx/rokit), then from the repo root:

```sh
rokit install     # installs the pinned tool versions
rojo serve        # then connect the Rojo plugin in Studio and click "Sync In"
```

(No toolchain manager? `cargo install rojo` / a prebuilt binary also works, then
just `rojo serve`. The same `[tools]` table works as `aftman.toml` for Aftman.)

### Local checks (what CI runs)

```sh
stylua --check src/                # formatting
selene generate-roblox-std         # one-time, writes roblox.yml
selene src/                        # lint
rojo build default.project.json --output build.rbxl   # parse + build
```

[`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) runs format + lint +
build on every push/PR, plus an advisory Luau type-check (`luau-lsp analyze`
against a generated sourcemap). Config: [`.stylua.toml`](../../.stylua.toml),
[`selene.toml`](../../selene.toml), [`.luaurc`](../../.luaurc).

## One-time scene setup in Studio (Milestone 1)

Rojo syncs the code; you still build the world it expects. In `Workspace`, create
a model `PlayField` containing:

- `Lava` — a wide, flat anchored `Part`, top at `Config.DESPAWN_Y` on the `Z = 0`
  plane.
- `Steps` — an empty `Folder` (spawned steps are parented here).

In `ReplicatedStorage`, create:

- `Assets` (Folder) with:
  - `StepTemplate` — a small `Part` sized like a stepping stone.
  - `FrogModel` — a `Model` whose `PrimaryPart` is a body `Part`, plus child parts
    named `Head`, `LeftLimb`, `RightLimb`. (Placeholder blocks are fine.)
  - `Skins/` (Folder) — one model per skin named to match `SkinCatalog` entries
    (optional until you wire up [doc 08](08-frog-skins-and-store.md)).

`Shared` (with the modules) is synced by Rojo — don't create it by hand.

## What you should see on Play

- The frog falls (accelerating) and, untouched, dies in the lava and respawns.
- Steps stream in from the top.
- Clicking/tapping a step makes a limb grab it; the field scrolls down a notch
  (you "climb"); the score ticks up.
- The HUD shows score and your persisted best (enable **Game Settings → Security →
  Enable Studio Access to API Services** for DataStore persistence).

See [04-build-roadmap.md](04-build-roadmap.md) for the milestone-by-milestone path
and per-milestone verification.
