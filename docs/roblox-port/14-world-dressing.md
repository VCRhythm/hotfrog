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
| `src/client/WorldScenery.client.luau` | Item 1: per-lane scenery spawners (Menu grass/clouds, Tutorial stars, Pot flames/bubbles, Kitchen/Country windows) + `levelObjects` one-offs (Chef, US). Parallax-scrolls with each lane's `PullDelta` × the kind's `speedModifier`; `moving` kinds (Bubble/Chef) drift on their own. Runs for **every** lane (cheap, flat pooled parts, no physics). |
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

- **Background materials** (`PotBack`, `KitchenTile`, `Sky.mat`, `Water.mat`,
  `HeatBackground.mat`, `LavaGradient.mat`) — these are Unity *materials*, not
  sprites, and were never part of the sprite pipeline `SkinAssets` covers.
  `WorldBackdrop.client.luau` uses a small local flat-colour table keyed by the
  same `background`/`overlay` strings `Levels.luau` already carries instead.
- **US** (`UnitedStates.cs`'s two-colour map cutout) has no single sprite stem
  either — rendered as a flat placeholder part using the 2-colour scheme from
  doc 11 §3 instead of a texture.

Every other stem this phase references (`Grass`, `Cloud3`, `Flame`, `Bubble`,
`Window`, `Stars`, `Chef`, `Circle`, `Sun`, `Speck`, `LavaSplash`,
`UniversalLeftPupil`/`RightPupil`) was already present in `SkinAssets.luau`
(all `id = 0` — untextured, flat-colour placeholders render instead, and real
art appears automatically once ids are pasted in, same as every other system).

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

## Tool results

`stylua`, `selene src/` (0 errors/warnings/parse errors), and `luau-lsp
analyze` (exit 0, no type errors) all clean against every file this phase
touched.
