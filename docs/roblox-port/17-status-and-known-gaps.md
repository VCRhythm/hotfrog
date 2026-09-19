# Port status, known gaps and deviations

_As of 2026-09-19. Update this file whenever a gap closes or a new one is found._

## Status

Every system of the original Unity game now has Luau behind it (docs 01–16).
The whole tree passes `selene`, `stylua`, `rojo build` and `luau-lsp` strict
analysis (the CI suite in `.github/workflows/ci.yml`).

**Studio testing has only just begun.** 2026-09-19: the uploaded ids resolve and
the images load on the client (`ContentProvider:GetAssetFetchStatus` → `Success`),
and Invisible Man's fallback head is right — but nothing was actually _on screen_
until the same day's fix: every `Decal`/`Texture` was authored on the part's
`Front` face, which in Roblox is **-Z**, i.e. pointing away from the camera at
+Z, and the default Roblox character spawned at the origin in front of lane 0's
frog. Both are fixed (`Face = Back` everywhere; `Players.CharacterAutoLoads =
false` plus a `ReplicationFocus` on the frog body, since this place has instance
streaming on). The evidence for those two is computed (face normals vs. the
camera look vector, a clear raycast from the camera to every frog part), **not
photographic** — Studio MCP `screen_capture` works in Edit mode (it needs a
`capture_id`) but times out in Play mode, so no screenshot has yet confirmed the
frog's own pixels in a run.

The face flip has a horizontal consequence, checked the same day with an
edit-mode capture of a known-asymmetric sprite at ±¼-tile offsets: on `Back` the
image still reads **un-mirrored** from the camera, but the face's U axis runs the
opposite way from `Front` — a **positive `Texture.OffsetStudsU` slides the image
towards -X (screen-left)**, while a positive `OffsetStudsV` slides it up. Only
the pupils use those offsets (`WorldFrogCosmetics`), and they now negate U so the
frog looks _at_ its target; V was already right. Left\*/Right\* parts are
unaffected — nothing in `src/` rotates or negative-scales a part, and the
template's limb X signs match the Unity dump in doc 12 (`LeftLimb` at -X).
Spawn density, lane spacing,
difficulty, UI scaling and how the game feels are still unverified. Each phase
doc ends with a "needs a Studio playtest" list:

- [13-levels-and-lanes.md](13-levels-and-lanes.md#known-risks-needing-a-studio-playtest)
- [14-world-dressing.md](14-world-dressing.md#what-needs-a-studio-playtest)
- [15-menus-and-input.md](15-menus-and-input.md#what-needs-a-studio-playtest)
- [16-audio-and-badges.md](16-audio-and-badges.md)

## Steps only a human can do

1. **Playtest** — `rojo serve`, connect from Studio, play through the Tutorial,
   Pot, Kitchen (200 steps) and Country (500), with two players.
2. **Upload assets** — the `tools/` pipeline (see `tools/README.md`, doc 10).
   Needs an Open Cloud API key with Assets read/write and
   `legacy-asset:manage`. As of 2026-09-19 `tools/asset_ids.json` (gitignored)
   already holds ~100 uploaded ids (`status: resolved-direct`); the remaining
   entries — including the five background/US-map images added the same day —
   are still `id = 0`. Run `tools/write_asset_ids.py` to pull cached ids into
   `SkinAssets` / `SoundAssets`, then spot-check one image in Studio: confirmed
   2026-09-19 via MCP (`HotFrogBody`, `rbxassetid://132401989626297`, on the live
   `Frog_<UserId>`/`BugTemplate` instances during a playtest) — an
   `assetType=Image` upload id loads directly from script, on both server and
   client, no `--resolve-only` re-upload needed. Note that a non-zero `Texture`
   property is **not** proof the art is visible: these same instances were
   invisible for a day because their decals faced away from the camera (see
   Status above).
3. **Create products** and paste ids:
   - 4 Game Passes → `src/shared/SkinCatalog.luau` (`gamePassId`)
   - Fly-pack Developer Products → `FLY_PRODUCTS` in
     `src/server/SkinService.server.luau`
   - 10 badges (10…100 steps) → `src/shared/Badges.luau`
4. **Enable** "Studio Access to API Services" (DataStores) and publish.

## Known gaps

| Gap | Where | Why | What would close it |
|---|---|---|---|
| Skin thumbnails for Blue / Space / Mystery Frog | store | no thumbnail file in `Sprites/Menu` | draw them; the UI falls back to the Head sprite meanwhile |
| "Drugged" frog effect (`Frog.cs MakeDrugged`) | cosmetics | nothing in the port triggers it | only if a step type re-introduces it |
| `HeatBackground` / `LavaGradient` materials | backdrop | wired in `WorldBackdrop` but no level references them (same as Unity) | nothing, unless a level is retuned to use them |
| Lava height maps (`Lava_01_H1/H2.tga`) | backdrop | custom Unity shader inputs, no Roblox equivalent | n/a — `LavaGradient` uses the flat `Lava_01` texture |
| Step / scenery sprite sizing | `StepKinds.luau`, `Levels.luau`, step + scenery parts | the frog rig was re-derived from `HotFrog.prefab`'s real sprite canvases (below), but every step/scenery part is still an arbitrary collider-sized box that stretches a padded Unity canvas into it | dump each step/scenery prefab with UnityPy the same way (sprite `spritePixelsToUnits`, `alignment`, `localScale`) and size the parts `pixels / ppu * UNITY_TO_STUDS` |
| Attract-mode ladder scale | `WorldConfig.ATTRACT_*` | the vignette's rung size/offsets were tuned beside the old, ~4× too small frog | retune once the corrected frog is seen in Studio |
| `*HandGrab` decals | frog cosmetics | the open/closed hand sprites exist on the rig but nothing in `src/` swaps them when a limb grabs | swap `Transparency` between `<side>Hand` and `<side>HandGrab` in `WorldFrogCosmetics.client.luau` off the existing held-step inference |
| Camera aspect for `Movements` offsets | spawning | Unity scaled `Movements` by the runtime screen aspect, which the prefab dump doesn't record; the port assumes the lane's half-width is the screen edge and clamps into the recycle margin | playtest; retune `Levels.luau`'s `MOVEMENTS_*_SCALE` if spawn positions feel wrong |

### Closed on 2026-09-19

| Gap | How |
|---|---|
| Attract mode (`Player/FrogAI.cs`) | `WorldAttract.client.luau`: cosmetic frog clone climbs a 3-rung ladder while the lane is in `Menu` (doc 15) |
| `hurt` sound | `GameOver` / `RunSummary` carry a death-cause argument (`"Lava"`); `SfxEvents` plays it; the old `WorldLava` proxy sound was removed (doc 16 §6) |
| Bubble `pop` | Bubble is the only `GrabableScenery` in Unity; a client-side tap raycast against live bubbles pops it (doc 14) |
| Background textures | `PotBack.jpg`, `KitchenTile.png` (2×2 tiled), `Lava_01.tga`→PNG in the manifest and `SkinAssets`; `Sky`/`Water`/`HeatBackground` colours taken from the `.mat` files (doc 14) |
| `US` map | `USRedStates` / `USBlueStates` as two layers crossfading blue↔red every 5 s, per `UnitedStates.cs` (doc 14) |
| Music toggle save spam | `Config.MUSIC_SAVE_DEBOUNCE` (5 s); the value applies immediately, the leave/BindToClose save is unconditional |
| Per-spawner `Movements` | all step and scenery spawner lists in `Levels.luau`; `Lane.luau` mirrors `Spawner.Move()` (discrete jump vs. tween) (doc 13) |
| Bugs-this-run counter | `BugService` fires a `BugCaughtServer` bindable; the `AwardFlys` amount heuristic is gone |
| Invisible Man inherits Hot Frog's head | checked in Studio with the uploaded sprites — looks right, the Unity-style `SkinAssets.part()` fallback stays |
| Frog rig size and sprite framing | `FrogModel.model.json` rebuilt from `HotFrog.prefab`'s own sprite data (UnityPy dump): head/body/face are one shared 1024 px @ 8 ppu canvas (= 40.23 studs), limbs 1024 px @ 12 ppu (= 26.82 studs), grab hands 256 px @ 12 ppu, each part sized to the **whole** canvas because a `Decal` always stretches and centres the full image. `Config.LIMB_REST` now uses the prefab's real limb offsets × `UNITY_TO_STUDS` (it was Unity/10, i.e. ~3.1× too small) and `WorldConfig.PUPIL_MAX_OFFSET` was rescaled to the new head face |
| Camera framing | `GameClient.client.luau`: distance 43.2 studs at FOV 40 shows exactly Unity's orthographic size 50 (100 Unity units ≈ 31.43 studs) vertically; it was 60 studs, ~1.4× too much world. With the rig fix the frog now spans ≈93 % of screen height, as in Unity |
| Opaque sprite backgrounds | every part that only hosts a `Decal`/`Texture` is now `Transparency = 1` (`StepTemplate`/`BugTemplate` `.model.json`, `BugService` fallback, `WorldAttract` rungs, all `FrogModel` parts) — a coloured host part read as an opaque box behind each sprite's alpha |

## Deliberate deviations from Unity

| Decision | Unity | Port | Why |
|---|---|---|---|
| Level progression | never advanced past Pot (`nextLevelIndex` written, never read) | Pot → Kitchen at 200 steps, Kitchen → Country at 500 (`Config.LEVEL_THRESHOLDS`) | Kitchen/Country were built but unreachable; owner's choice |
| Multiplayer field | local split-screen, one field per controller | one **lane** per player, side by side along X (doc 13) | per-player levels and sideways travel are impossible on a shared field |
| Spawner `Movements` offsets | off-screen staging points dragged on screen by the continuous per-frame pull | converted to studs with a fixed aspect assumption and **clamped** into the recycle margin | the port pulls per grab, not per frame, so an off-screen spawn would be recycled before it was ever seen |
| Attract-mode frog | drives the real frog with random screen taps (`FrogAI.cs`) | a separate cosmetic clone on a fixed 3-rung ladder, 1 s cadence | the real frog is server-owned; the demo must not fight replication |
| Bubble pop particles | Unity `ParticleSystem` | pooled part burst (same style as the lava splash) | |
| Tutorial | every run | once per profile (`profile.tutorialDone`), replayable from Settings | |
| Ads | watch-ad-for-Flys branch after a run | **dropped**, no replacement | owner's choice |
| Left / Right arrow steps | `SpawnDirection` = the arrow's own sign, inconsistent with Up/UpLeft/UpRight | all arrows point the way the frog appears to travel (Left/Right swapped vs. Unity's literal values) | see `StepBehaviors.luau` |
| Sideways travel in Kitchen/Country | `LeftRock`/`RightRock` in no shipped pool, so the Left/Right spawners were unreachable | both added to the Kitchen and Country down-spawner pools (`Levels.luau`, "PORT ADDITION") | otherwise Kitchen plays like Pot with shelf art |
| Spawner direction lookup | exact-vector dictionary that never matched the half-magnitude spawners | matched by sign of each component | Unity bug not reproduced |
| Country music | `musicIndex 4` looked out of range | `music5` = `Two Wrongs.wav`, the fifth clip in `Multiplayer.unity`'s AudioManager override | |
| Badges | only checked on a new all-time best | awarded the first time any run crosses a threshold | friendlier to players who already have a high best |
| Pause | freezes the game | status panel only; gravity already stops while holding a step | a multiplayer server can't pause |
| Crumble step (`ActionType.Crumble`) | in the enum; `CrumblyRock.prefab` is actually `None` | behaviour kept, weight 0 / in no pool | no Unity prefab ever used it |
| Unused `ActionType`s (Launch, SlideOff, MakeFunky, MakeTarget, Move, RiseAndFall, Castle, Helper, PullByLocation, StepFlinging) | enum values with no code or no prefab | not ported | nothing to port |
| Scoring | +1 per step, quality tracked separately | same; Perfect/Great/OK counts sent with `ScoreChanged` and shown on the end-of-run panel | (the earlier audit's "partial" rating was wrong) |
| Frog head / body draw order | `SpriteRenderer` sorting order puts Head (−4) *behind* Body (−3) but the face sprites (+9…+13) in front of both | the whole Head part, face decals included, sits behind the Body part (Z −0.3 vs 0) | the face art (eyes ≈ +20…+29 u, mouth ≈ −14…−11 u) never overlaps the body art (−64…−36 u), so one part per layer is faithful and avoids a third plane |
| Gamepad snap-assist | n/a | nearest step is grabbed but the **cursor** position is graded | keeps Perfect meaningful |
