# 14 — World dressing (client-only cosmetics)

> Phase 4: renders everything doc 13 deliberately left as data (scenery
> spawners, `levelObjects`) or deferred outright (background/overlay/Sun, lava,
> quality popups, touch indicator, frog blink/pupils, tutorial specks). Nothing
> here is gameplay-authoritative — every module is a `LocalScript`/client
> `ModuleScript`, reading server-replicated Attributes/remotes and rendering
> flat placeholder colours until real sprite/sound ids are pasted into
> `SkinAssets`/`SoundAssets`.

## Files

| File | Renders |
|---|---|
| `src/shared/WorldConfig.luau` | Tuning constants for this phase (blink timing, pupil travel, popup colours/lifetime, touch-indicator thresholds, lava/sun/overlay timings, pebble impulse, speck settings). Mirrors `Shared/Config.luau`'s style but kept separate per this phase's file ownership. |
| `src/shared/SceneryKinds.luau` | Visual data (size/colour/sprite stem/parallax `speedModifier`/`autoMove`/`moving`) and spawn **cadence** (`maxSpawnCount`/`spawningSpeedMin`/`Max`/`spawnAllOnAwake`) for every scenery prefab name `Shared/Levels.luau`'s `scenerySpawners` reference. `Levels.SceneryDef` stayed intentionally minimal (doc 13 item 2: "data only"), so the doc 11 §2a columns it didn't carry (cadence, `colorOptions`) live here instead, keyed by the same spawner `name` string — additive, `Levels.luau` itself is untouched. |
| `src/client/world/Pool.luau` | Generic acquire/release Instance pool (`ObjectPool.cs`, generalized) shared by every system below. |
| `src/client/world/GrabTarget.luau` | The "what is this frog holding" heuristic: a limb whose world position has moved more than `GRAB_EXTEND_THRESHOLD` studs from its `Config.LIMB_REST` offset is "holding" whatever it's touching. Used for pupil look targets and quality-popup placement — see "Design notes" below for why this exists. |
| `src/client/WorldScenery.client.luau` | Item 1: per-lane scenery spawners (Menu grass/clouds, Tutorial stars, Pot flames/bubbles, Kitchen/Country windows) + `levelObjects` one-offs (Chef, US). Parallax-scrolls with each lane's `PullDelta` × the kind's `speedModifier`; `moving` kinds (Bubble/Chef) drift on their own. Runs for **every** lane (cheap, flat pooled parts, no physics). Also owns its own tap-to-pop input for `poppable` kinds (Bubble only — see "Bubble pop" below, a later doc 17 gap closure). |
| `src/client/WorldBackdrop.client.luau` | Item 2: background (two wrap-around tiles), overlay (Water fade), Sun (day/night/black), and the level-transition flash/crossfade — driven by `LevelClient`'s existing `Players.LocalPlayer.LevelState`. Local lane only (see below). |
| `src/client/WorldLava.client.luau` | Item 3: lava heat lift/lower (tweens the existing `workspace.PlayField.Lava` part's colour) and splash bursts when a step or the local frog drops past `Config.DESPAWN_Y`. |
| `src/client/Effects.client.luau` *(edited)* | Item 4: pebble bursts upgraded to match `Pebble.cs Explode` (X/Y impulse spread + opposing torque, tinted to the step's colour) and pooled via `world/Pool.luau` instead of one-shot `Instance.new()` + `Debris`. |
| `src/client/WorldQualityPopup.client.luau` | Item 5: floating OK/GREAT!/PERFECT! popups at the grabbed step, driven by the existing `ScoreChanged` remote's `quality` argument. |
| `src/client/WorldTouchIndicator.client.luau` | Item 6: the coloured tap-point dot, its own read-only raycast (mirrors `GameClient`'s, never touches it). |
| `src/client/WorldFrogCosmetics.client.luau` | Item 7: blink cycle, pupil tracking, dead/rise state for every visible frog. |
| `src/client/WorldTutorialSpecks.client.luau` | Item 8: guidance specks orbiting the next tutorial step, per lane. |
| `src/assets/FrogModel.model.json` *(edited, additive)* | Adds `LeftPupil`/`RightPupil` as **Texture** (not Decal) instances under `Head`, so pupils can be nudged via `OffsetStudsU/V` — a local visual property — without ever touching a server-owned part's CFrame. |

## Design notes

**Why `GrabTarget`'s heuristic exists at all.** Neither `ScoreChanged` (quality
popups) nor any per-frog state (pupil look target) carries a step reference —
and `GameServer.server.luau`/the remote list are off-limits for this phase.
But `GameServer`'s frog-render Heartbeat already snaps a held limb's CFrame to
exactly `CFrame.new(step.Position)` every tick, and eases it back toward
`body.CFrame * Config.LIMB_REST[i]` otherwise (both already replicated,
read-only data). Comparing a limb's live position against its known rest
offset is a free, exact "is this limb holding something, and where" signal —
used by both `WorldFrogCosmetics` (pupils) and `WorldQualityPopup` (popup
placement, matched against `ScoreChanged` within `QUALITY_POPUP_MATCH_WINDOW`).

**Pupils are Textures, not a moved Part.** This phase's ownership rule allows
"Decal transparency/offsets" but never a server-owned part's CFrame. Unity's
pupils are separate moving Transforms; the nearest equivalent that stays
inside that rule is a `Texture` (not `Decal` — only `Texture` exposes
`OffsetStudsU/V`) nudged in place. `FrogModel.model.json` gained two additive
`Texture` children of `Head` for this; `SkinAssets` already had
`UniversalLeftPupil`/`RightPupil` stems.

**Scope split: every lane vs. local lane only.** `GameClient.client.luau`'s
camera (read-only) only ever centres on the local player's own lane origin —
neighbouring lanes' full-screen background/overlay/Sun would never be visible,
so duplicating them per lane is pure waste. Scenery, frog cosmetics, and
tutorial specks *are* rendered for every lane (cheap, and other players' frogs
genuinely are visible). Lava/backdrop/touch-indicator/quality-popup are local
only, matching what only the local player can see or trigger.

**Blink/pupil/quality-text/lava/background timings** are ported 1:1 from
`Frog.cs`, `QualityText.cs`, `Lava.cs`, and doc 12 §6's prefab data where a
literal value existed; anything requiring a moving part Unity represents with
its own Transform (pupils, background tiling, Sun's day/night/black bools) is
marked `ADAPTED` in-file with the reasoning, since a flat 2D-sprite scene
doesn't map 1:1 onto Roblox parts/UI.

## Sprite stems missing from `SkinAssets`

Every stem this phase references (`Grass`, `Cloud3`, `Flame`, `Bubble`,
`Window`, `Stars`, `Chef`, `Circle`, `Sun`, `Speck`, `LavaSplash`,
`UniversalLeftPupil`/`RightPupil`, plus `PotBack`/`KitchenTile`/`LavaGradient`/
`USRedStates`/`USBlueStates`/`Water` added below) is now present in
`SkinAssets.luau` (all `id = 0` — untextured, flat-colour placeholders render
instead, and real art appears automatically once ids are uploaded and pasted
in, same as every other system).

## Background materials and the US map (doc 17 known gaps, closed)

Two of doc 17's known gaps were closed after this phase shipped: the
background materials (`PotBack`/`KitchenTile`/`Sky`/`Water`/`HeatBackground`/
`LavaGradient`) and the `US` Country scenery item. Both were Unity
*materials*, not sprites — never part of the sprite pipeline `SkinAssets`
covers — so a small `dump_materials.py` script (same UnityPy setup as
`dump_prefabs.py`, run from the scratchpad against the Unity project's
`Assets/Materials/*.mat`) was written to read each material's shader, texture
reference and `_Color`/gradient properties out of their binary type trees,
instead of guessing.

**Per-material findings:**

| Material | Texture? | Colour(s) | Notes |
|---|---|---|---|
| `PotBack.mat` | yes — `Materials/Textures/PotBack.jpg`, tiling scale (1,1) | avg. pixel colour (Pillow) `RGB(197,197,195)` | `_Color`=white (no tint); fills the background tile once |
| `KitchenTile.mat` | yes — `Materials/Textures/KitchenTile.png`, tiling scale (2,2) | avg. `RGB(220,216,209)` | repeats twice across each axis — ported as a Roblox `Texture`'s `StudsPerTileU/V`, not a `Decal` (`Decal` has no tiling) |
| `Sky.mat` | no | `_Color` = `RGB(155,255,255)` | plain Standard-style shader, `_MainTex` unset — the `background = nil` fallback colour |
| `Water.mat` | no (see below) | `_Color` = `RGB(255,69,0)` | custom water/heat shader; `_MainTex` is a third-party paid asset-pack texture (`First Fantasy for Mobile`'s `Water_01.tga`) not in this project and not exportable — but `Sprites/Scenery/Water.png` (already a `SkinAssets` stem from the general sprite scan) is this same overlay's actual sprite art, so that's used as the texture once uploaded, with this `_Color` as the id=0 fallback (replacing the old guessed blue) |
| `HeatBackground.mat` | no | `_Color` = `RGB(255,0,0)` | shader resolved to `Shaders/Gradient-NoTexture-Radial-SingleColor-ToTransparent-RegularUV-AlphaBlend.shader` — confirms it's a texture-less radial gradient by design; no live `Levels.luau` `background`/`overlay` key references it yet, kept in `WorldBackdrop`'s lookup table for when one does |
| `LavaGradient.mat` | yes — `Materials/Textures/Lava_01.tga` (+ 2 height maps, not portable to a flat Decal, skipped) | avg. `RGB(199,69,3)` | shares its shader family with `Lava.mat`/`Water.mat`; its own `_MainTexTile` float is a custom shader parameter, not a standard Unity material tiling vector, so it doesn't map onto `Texture.StudsPerTileU/V` — rendered untiled. No live `Levels.luau` key references it yet either (same "kept complete" treatment as `HeatBackground`) |

`tools/build_manifest.py` gained `collect_background_materials()`: it adds
`PotBack`/`KitchenTile` directly (their real texture files, outside the repo
in the Unity project) and converts `LavaGradient`'s `Lava_01.tga` to PNG via
Pillow (cached under `tools/.asset_cache/converted_images/`, gitignored) since
the upload pipeline wants PNG, not TGA. `Sky`/`Water`/`HeatBackground` have no
texture to upload, so they're not manifest entries — their extracted colours
are hardcoded directly in `WorldBackdrop.client.luau`. The background tiles'
image-bearing child changed from `Decal` to `Texture` (to support
`KitchenTile`'s real 2x tiling); the current flat colours above are the
fallback whenever `SkinAssets.image(key)` returns nil (id still 0), exactly
like every other sprite in this port.

**US** (`UnitedStates.cs`'s two-colour map cutout): `Sprites/Scenery/
USRedStates.png`/`USBlueStates.png` turned out to already exist and be
referenced — `Prefabs/Levels/Level4/Objects/US.prefab.json`
(`dump_prefabs.py`) shows two `SpriteRenderer` children of the "US"
levelObject wearing exactly those two sprites. They'd been marked skipped in
`tools/build_manifest.py`'s `SCENERY_SKIP_REASONS` as "likely unused"; that
skip is now removed and both are ordinary `Sprites/Scenery` manifest
entries/`SkinAssets` stems. `UnitedStates.cs`'s own `colors` field (read off
the same prefab JSON) is `[blue(0,0,1,1), red(1,0,0,1)]`; its `ChangeColors`
coroutine continuously swaps each `SpriteRenderer`'s tint between these two
colours every 5 seconds (`DOColor(colors[i], 5f)` + `WaitForSeconds(5f)`),
staggered one index apart so exactly one layer is blue and the other red at
any moment. `world/WorldScenery.client.luau` reproduces this with two thin
stacked parts (`USBlueStates`/`USRedStates`, same z-offset trick
`WorldBackdrop`'s background tiles use), each looping a `TweenService`
crossfade between the two colours via `SceneryKinds.defs.US.colors`. `US`
remains a compound, hand-built one-off (like `Chef`) rather than a
`SceneryKind.sprite` entry — that field only expresses a single sprite stem,
and `US` needs two independently-tinted ones.

## Bubble pop (doc 17 known gap, closed)

A later pass (2026-09-19) closed doc 17's "Bubble pop" gap: `Entities/
MovingScenery.cs`'s `Grab` (its `IGrabable` implementation) makes a scenery
item tappable — plays its `grabClip` (`Pop.wav`, doc 12 §5 "pop"), bursts its
particle system, and self-destructs after 1s (`Destroy(0, 0, 1f)`) — purely
cosmetic, no gameplay effect (`Grab`'s `playerID` argument is unused).
`Player/Controller.cs`'s `CheckTouch` only ever routes a tap into `Grab` for
an object tagged `"GrabableScenery"`; the prefab dump
(`Prefabs/Spawns/Scenery/*.prefab.json`) shows **only `Bubble` wears that
tag** — `Chef` also carries `MovingScenery.cs` (for its own constant upward
drift, already ported as `SceneryKinds`' `moving`/`moveDirection`/`moveSpeed`
fields) but is tagged `"Untagged"` and has a null `grabClip`, so it's never
poppable in the original either.

`SceneryKinds.luau` gained a `poppable: boolean` field (default `false`),
set `true` only on `Bubble`. `world/WorldScenery.client.luau`:

- `createSceneryPart` sets `CanQuery = true` only for `poppable` kinds — every
  other kind stays `CanQuery = false`, preserving this file's existing "never
  eat a tap meant for a step/bug" guarantee (see the file's header comment).
  That guarantee doesn't depend on `CanQuery` in the first place:
  `GameClient.client.luau`'s (and `WorldTouchIndicator.client.luau`'s) own
  raycasts are `Include`-filtered to the `Steps`/`Bugs` folders only, and
  scenery parts are never parented under either, so they're structurally
  invisible to those raycasts regardless of `CanQuery`.
- A new, file-local `UserInputService.InputBegan` listener (mouse/touch,
  skipping `gameProcessed`) fires its own raycast, `Include`-filtered to
  exactly the set of currently-live `poppable` parts across every lane
  (`poppableParts`). Roblox fires every connected listener for a given input
  — there's no "consume"/stop-propagation between two separate scripts' own
  connections — so this can never suppress `GameClient.client.luau`'s own
  `InputBegan` handler; a step grab always still fires from that handler
  regardless of whether this one also pops a bubble on the same tap.
- On a hit: `SoundFX.play("pop")` (`pop` was already declared in
  `SoundAssets.luau`, `id = 0`), a short outward burst of a handful of
  pooled, tinted `Ball` parts that fade over ~0.25s (`popBurstAt` — ADAPTED
  from `MovingScenery.cs`'s Unity `ParticleSystem`; no 1:1 `ParticleEmitter`
  equivalent fit this file's existing pooled-part burst style, the same
  reasoning `WorldLava.client.luau`'s `splashAt`/`LavaSplash` burst already
  uses), then recycles the part back through the same `recycleScenery` path
  bounds-recycling already uses (`MovingScenery.cs Grab`'s `Destroy(0, 0,
  1f)`).

## Tuning constants added

All in `src/shared/WorldConfig.luau`: blink timing (`BLINK_MIN/MAX_TIME`,
`BLINK_FRAME_TIME`), pupil travel (`PUPIL_MAX_OFFSET`, `PUPIL_LERP_RATE`,
`GRAB_EXTEND_THRESHOLD`, `NEAREST_STEP_POLL_INTERVAL`), frog dead/rise fade,
quality-popup colours/text/lifetime/match-window, touch-indicator
colours/thresholds/fade, lava heat/splash timings and colours, Sun
colours/transition time, overlay fade/transparency, transition flash/crossfade
timings, scenery bounds margin/pool cap/auto-move scale, and pebble impulse
(moved out of `Effects.client.luau`'s old local constants) and speck
count/radius/colours/rotate speed.

## What needs a Studio playtest

- The background wrap-tile math (`WorldBackdrop.scrollBackground`) and the
  scenery bounds-recycle margins are derived analytically like doc 13's own
  spawn positions, not visually tuned — verify no visible pop/seam at the tile
  wrap point once art exists.
- Pupil `OffsetStudsU/V` travel range (`WorldConfig.PUPIL_MAX_OFFSET`) is a
  guess independent of real eye-art placement on the Head sprite; revisit once
  actual Hot Frog art is uploaded so the pupils land inside the drawn eyes.
- The `GrabTarget` limb-extension heuristic (quality-popup placement, pupil
  "held step" target, tutorial-speck "next step") has only been hand-traced
  against `GameServer`'s Heartbeat ordering, not observed live — verify popups
  land on the actually-grabbed step and specks track correctly through a full
  Tutorial run.
- Multi-lane scenery + frog-cosmetics cost scales with player count (bounded,
  pooled, throttled nearest-step polling) but is unverified beyond small
  server sizes, consistent with doc 13's own caveat for `Lane.iter()`.
- "Drugged" (`Frog.cs MakeDrugged`) was skipped — no signal in this port's
  scope triggers it, and it wasn't asked for explicitly.
- `KitchenTile`'s `StudsPerTileU/V` (real 2x tiling from the material's own
  scale) and `US`'s 5-second colour-swap loop are both derived/ported
  analytically, not visually tuned — verify the tile repeat looks right and
  the US blink timing/z-stacking reads cleanly once art is uploaded.

## Tool results

`stylua`, `selene src/` (0 errors/warnings/parse errors), and `luau-lsp
analyze` (exit 0, no type errors) all clean against every file this phase
touched, including the later background-materials/US-map gap closure
(`WorldBackdrop.client.luau`, `WorldScenery.client.luau`, `SceneryKinds.luau`,
`SkinAssets.luau`, `tools/build_manifest.py`).
