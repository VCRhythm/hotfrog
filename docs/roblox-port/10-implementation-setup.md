# 10 — Implementation Setup (source, toolchain & running it)

The reference implementation of the **basic loop** lives in the repo's
[`/src`](../../src) tree (real Luau, the source of truth), and a Rojo project syncs
it straight into Roblox Studio. These are the fleshed-out versions of the
illustrative snippets in [03-core-mechanics.md](03-core-mechanics.md) plus the
skins service from [08-frog-skins-and-store.md](08-frog-skins-and-store.md).

> Still a starting point, not a shipped game: art is placeholder parts and tuning
> lives in `Config` — but the client/server split is the **hardened** one from
> [07-multiplayer.md](07-multiplayer.md): the server owns frogs (gravity, limbs,
> death, respawn, skins), steps, pull, and score; the client sends taps and draws
> cosmetics. Frogs replicate like any other server-owned model, so multiple
> players already see each other climb.

## Source layout

```
src/
  shared/    -> ReplicatedStorage.Shared      (ModuleScripts)
    Config.luau
    PullMath.luau
    SkinCatalog.luau
    SkinAssets.luau   -- name → rbxassetid map (paste uploaded ids here)
    SpriteSkin.luau   -- textures parts from SkinAssets via an attribute convention
    StepBehaviors.luau -- step ActionType registry (doc 05)
    SoundAssets.luau  -- clip stem → rbxassetid map (paste uploaded ids here)
    SoundFX.luau      -- one-shot sound player over SoundAssets
  server/    -> ServerScriptService.Server     (Scripts + a ModuleScript)
    Profiles.luau           -- single per-player profile + DataStore (persistence)
    GameServer.server.luau
    SkinService.server.luau
    GiftService.server.luau -- timed free-Fly gift (doc 09)
    BugService.server.luau  -- bug collectible loop (doc 06; self-provisions its folder/template)
  client/    -> StarterPlayer.StarterPlayerScripts.Client   (LocalScripts)
    GameClient.client.luau
    Effects.client.luau     -- sounds + pebble debris off Unsteady steps
    StoreUI.client.luau     -- skin store + gift button (docs 08/09)
```

The mapping is defined in [`default.project.json`](../../default.project.json).
Rojo creates the `Shared` / `Server` / `Client` folders and places each script;
Scripts and LocalScripts run regardless of nesting, so the wrapper folders don't
change behavior. The server auto-creates the `ReplicatedStorage/Remotes` folder and
its `RemoteEvent`s on first run, so you don't build those by hand.

**Persistence is consolidated:** [`Profiles.luau`](../../src/server/Profiles.luau)
owns one DataStore and one per-player schema (high score, Flys, owned/selected
skins, applied receipts, gift cooldown), plus an `OrderedDataStore` mirror of
personal bests for the global top-N (`Profiles.topScores`). `GameServer`, `SkinService`, and
`GiftService` all read/write `Profiles.get(player)` and react to `Profiles.Loaded`
— no service stands up its own store. Flys are granted through one path: a
server-only `ServerStorage/AwardFlys` `BindableEvent` (`SkinService` applies +
replicates; bugs/gifts just `:Fire(player, amount)`).

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
build on every push/PR, plus a Luau type-check (`luau-lsp analyze` against a
generated sourcemap). Config: [`.stylua.toml`](../../.stylua.toml),
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

## Source art

The original sprite art is in the repo under [`/Sprites`](../../Sprites): frog
skins (`Sprites/Frogs/<name>/`, one per `SkinCatalog` entry, plus a shared
`Universal/`), step variants (`Sprites/Rocks/`), and entities/scenery
(`Sprites/Other/`, `Sprites/Scenery/`, `Sprites/Menu/`). See
[doc 08](08-frog-skins-and-store.md#source-art-in-the-repo) for the part→sprite
mapping. Placeholder parts are only the gray-box fallback; the real look comes from
these via the art pipeline below.

### Art tooling (`/tools`)

[`/tools`](../../tools) holds Python sprite-prep utilities (`pip install -r
tools/requirements.txt`; see [tools/README.md](../../tools/README.md)). Typical
order:

1. **`webp_to_png.py`** — normalize any `.webp` source art to `.png`.
2. **`remove_bg.py`** — flood-fill out a solid background and tight-crop.
3. **`pixel_pass.py`** — optional: bake a consistent low-res pixel-art look.
4. **`upload_to_catbox.py`** — upload the cleaned PNGs to catbox.moe and emit a
   `{name: url}` JSON map (keys are file stems).

> **How art reaches Roblox.** The catbox URLs are **reference inputs for Ludo** —
> they're fed to the AI asset tool as references to generate the Roblox-bound
> assets. Note catbox URLs are *not* usable as Roblox textures directly: a Roblox
> `Decal`/`ImageLabel` needs an `rbxassetid://` from an asset uploaded to (and
> moderated by) Roblox. So the chain is:
> **`/Sprites` PNGs → `/tools` prep → catbox URLs → Ludo (reference) → generated
> assets → upload to Roblox → `rbxassetid` bound to the rig parts.**

### Texturing parts (attribute convention)

[`src/shared/SpriteSkin.luau`](../../src/shared/SpriteSkin.luau) textures any
`Decal`/`Texture`/`ImageLabel` from [`SkinAssets`](../../src/shared/SkinAssets.luau)
using one attribute you set on the part in your templates:

| Attribute | Use | Resolved by |
|---|---|---|
| `Sprite = "<stem>"` | skin-agnostic art — `"WhiteRock"`, `"Bug"`, `"LavaSplash"`, `"Sun"` | `SkinAssets.image(stem)` |
| `Suffix = "<suffix>"` | per-skin frog part — `"Body"`, `"Head"`, `"LeftHandGrab"` | `SkinAssets.part(skinName, suffix)` |

Put the attribute on the `Decal`/`Texture`/`ImageLabel` itself, **or on a
`BasePart`** — a tagged part textures the `Decal`s parented to it. So a step part
whose `Sprite` is stamped at spawn time just needs a blank `Decal` (Front face) on
the `StepTemplate`; the frog rig instead tags each part's `Decal` with `Suffix`.

Then call `SpriteSkin.apply(root, skinName?)`:

- **Frog rig** — `SpriteSkin.apply(frogModel, selectedSkinName)` retextures all the
  `Suffix` decals for the chosen skin (wired in [doc 08](08-frog-skins-and-store.md)).
- **Static art** — `SpriteSkin.apply(part)` (no skin name) textures `Sprite` decals.
  The reference [`GameServer`](../../src/server/GameServer.server.luau) already calls
  this on each step it spawns; do the same when you build the `Bug`
  ([doc 06](06-bugs-and-tongue.md)) and `Lava` parts (give their decal a
  `Sprite = "Bug"` / `"LavaSplash"` attribute).

It's a no-op for any part whose id is still `0` in `SkinAssets`, so it's safe to
call on placeholder templates before art is uploaded.

### Audio

The repo contains **no audio files** — unlike the sprites, the original sound set
was never committed. [`SoundAssets.luau`](../../src/shared/SoundAssets.luau) lists
the clip stems named by `Audio/AudioManager.cs` (grab, crumble, fall, slurp,
squish, miss, music…), so it doubles as the list of sounds to source or recreate;
paste uploaded ids there exactly like `SkinAssets`.
[`SoundFX.play(stem)`](../../src/shared/SoundFX.luau) is a silent no-op while an
id is `0`, and the gameplay calls are already wired (grab/miss/slurp in
`GameClient`; squish/fall/crumble + pebble debris in
[`Effects.client.luau`](../../src/client/Effects.client.luau)) — uploading clips
makes the game audible with no code changes.

## What you should see on Play

- The frog falls (accelerating) and, untouched, dies in the lava and respawns.
- Steps stream in from the top.
- Clicking/tapping a step makes a limb grab it; the field scrolls down a notch
  (you "climb"); the score ticks up.
- The HUD shows score and your persisted best (enable **Game Settings → Security →
  Enable Studio Access to API Services** for DataStore persistence).

See [04-build-roadmap.md](04-build-roadmap.md) for the milestone-by-milestone path
and per-milestone verification.
