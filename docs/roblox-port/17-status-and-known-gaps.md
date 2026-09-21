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
| Sprite pivots / non-centre alignment | step + scenery parts | sizing is now correct (below), but Unity's non-centre `alignment: 9` pivots (`Grass`, `Carrot`, `Castle`, `Rocket`, `LavaSplash`, `Flame`, `branch2/3`) still render centred, so those sprites sit offset from where Unity draws them | offset each part by `(pivot - 0.5) * canvasSize` |
| Oversized canvases vs. lane spacing | `SceneryKinds.luau` | `Chef` (64 studs) and the `US` map (≈129 × 112 studs) are genuinely that big in Unity, which is wider than `Config.LANE_SPACING` (46), so in multiplayer they overhang the neighbouring lane | per-lane culling or a scenery-only lane offset; harmless single-player |
| Tall steps pop IN at spawn | `Lane.spawnPosition` / `Config.SPAWN_Y` | spawn lines are fixed at `SPAWN_Y = 25` while the camera shows ±15.7 studs, so a step whose art is taller than ~18.6 studs (`Rocket` 27.2, `Balloon` 25.6, the unused `Castle` 32.2) is already partly on screen the frame it spawns. Recycling now measures the step's extent, but raising the spawn line would delay every one of those steps' arrival, i.e. change spawn timing | spawn tall kinds at `SPAWN_Y + halfY` and retune their spawner cadence together |
| `Flingee` splash size | `GameServer.flingSplash` | the fling/splash part is a hard-coded `1.2 × 1.2 × 0.4`, so `Fork`/`Spoon`/`Flame` canvases are still squashed into it | same derivation as the steps (`Fork`/`Spoon` 512 px @ 20 = 8.046 studs) |
| Camera aspect for `Movements` offsets | spawning | Unity scaled `Movements` by the runtime screen aspect, which the prefab dump doesn't record; the port assumes the lane's half-width is the screen edge and clamps into the recycle margin. Note (2026-09-19) that `Spawner.SetMovementToScreenSize` uses `halfScreenWidth = 50 * (Screen.width / Screen.height)` — on the **portrait phone** this game shipped on that is ≈28 u, not the ≈70.5 u (landscape) the port assumed, so every X offset here may be ~2.5× too wide. Visible effect today: the Tutorial's three trees land at x = ±25 studs (the `clampToLane` limit), just inside a 16:9 window and outside a 4:3 one | playtest; retune `Levels.luau`'s `MOVEMENTS_*_SCALE` if spawn positions feel wrong |

### Closed on 2026-09-21

| Gap | How |
|---|---|
| Movements corners spawn past grab reach (b-20260921-100739-ldv9, "I'm running out of platforms to climb") | `Lane.spawnPosition`'s `clampToLane` clamped a Movements offset's X and Y independently against the lane/screen bounds, so a corner entry (max \|X\| *and* max \|Y\| at once) could still land farther from the frog than `Config.MAX_GRAB_DISTANCE` (30 studs) — permanently ungrabbable the instant it spawned, since the frog never moves off the lane's X origin. This wasn't rare: Tutorial's 3rd tree (35.4 studs out), and Pot's own default `DownStepSpawner` plus Pot/Kitchen/Country's `DownLeftStepSpawner` (2 of 3 cycled positions each, ~31.8 studs out) all hit it — i.e. the very first level's last tree, and the most common Pot spawner, both routinely handed the frog an unreachable step. `clampToLane` now clamps the per-axis box first, then pulls any corner still outside `Config.MAX_GRAB_DISTANCE` back onto that reach circle; already in-range spawns are untouched. The separate camera-aspect gap above (whether a reachable step is also *visible*) is unaffected and still open |

### Closed on 2026-09-19

| Gap | How |
|---|---|
| Frog fall speed and the lava line (b-20260919-200543-yixb) | `Config.GRAVITY` / `MAX_FALL_SPEED` were Unity's `Frog.cs` numbers (20 / 60) read as **studs** instead of Unity units — the same class of miss as the old `LIMB_REST` — so the frog fell ~3.2× too fast, and `GRAVITY_ACCEL` was 0.6/s where Unity adds `0.02` per FixedUpdate (= 1.0/s). Both now convert with `UNITY_TO_STUDS` (6.2857 studs/s, 18.857 studs/s, 1.0/s), which reproduces Unity's own 1.79 s sink from rest to the bottom of the screen. The frog's death check also used `Config.DESPAWN_Y` (−30) — that is the **step** recycle line (Borders' bottom catch at −100 u, where Unity's *dead* frog tweens to, `Frog.Fall`'s `endY`), half a screen below the view. Unity's living frog stops at **−50 u**: `SteadilyLowerHead` runs `while (HeadPosition.y > -50)` and `Step.cs` draws the lava splash at `(x, -50f)` — i.e. the lava surface, which with ortho size 50 is exactly the bottom edge of the camera band. New `Config.LAVA_Y = -50 * UNITY_TO_STUDS` (−15.714) is now the frog's death/Tutorial-retry line, the `WorldLava` splash height for both frog and step, and the top face of `PlayField.Lava` (centre −17.714 for its 4-stud thickness). The frog now stays inside the ±15.7-stud band for its whole fall |
| Attract mode (`Player/FrogAI.cs`) | `GameServer.server.luau`: the real server-owned frog climbs a 3-rung server-built ladder while the lane is in `Menu`, so each lane shows one frog and other players see it (doc 15). Replaced a client-local clone that put a second frog on screen |
| Attract-mode ladder scale (b-20260919-192618-ge28) | `WorldConfig.ATTRACT_*` rescaled off `Config.LIMB_REST`'s own growth (the frog rig fix above) instead of the pre-fix, ~4× too small frog: `ATTRACT_STEP_SIZE` now `StepKinds`' `WhiteRock` canvas (7.314²); `ATTRACT_STEP_Y_GAP` centred on the anchor (the ladder spans `±STEP_Y_GAP`, not `1..COUNT × STEP_Y_GAP`) so it still fits the camera's ±15.7-stud band; `ATTRACT_ANCHOR_OFFSET.X` is now 0 (ladder centred on the real frog) — verified in Studio (rung/anchor/limb positions), still worth a human look once art is uploaded |
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
| Opaque sprite backgrounds | every part that only hosts a `Decal`/`Texture` is now `Transparency = 1` (`StepTemplate`/`BugTemplate` `.model.json`, `BugService` fallback, attract-mode rungs, all `FrogModel` parts) — a coloured host part read as an opaque box behind each sprite's alpha |
| Step / scenery sprite sizing | every step part is now its sprite's whole Unity canvas (`pixels / spritePixelsToUnits * UNITY_TO_STUDS`, times the prefab `localScale` — `(1,1,1)` on every step) in `StepKinds.size`, and every scenery part likewise in `SceneryKinds.size` (only `BackGrass` `(1,2,1)`, `Stars` `(2,1,1)` and `US` `(1,0.8709,1)` scale). Because the canvases are heavily padded, the grab hit area is kept separate: `StepKinds.hitSize` carries the Unity `Collider2D` (doc 12 §1) in studs, `GameServer` publishes it as a `HitSize` attribute, and `GameClient` tap-tests that rectangle at the tap's point on the play plane instead of raycasting the part — which is what Unity does (`Physics2D.Raycast(worldPos, Vector2.zero)` is a point overlap against the collider, `Player/Controller.cs CheckTouch`). Its raycast is now Bugs-only so the big step parts can't swallow bug taps, and sprite-hosting scenery parts are `Transparency = 1`. `Lane.isOutOfBounds` now recycles on the step's own extent rather than its centre, matching Unity (`Spawning/Spawn.cs` recycles on `OnTriggerEnter2D` with the Borders catch colliders, i.e. on the edge), so a ~32-stud `Rocket`/`Balloon`/`Castle` can no longer vanish while part of it is still on screen; `WorldScenery`'s own `isOutOfBounds` got the same treatment for the large scenery canvases (`Chef`, `US`, `Stars`, `Cloud3`) |
| `*HandGrab` decals | `WorldFrogCosmetics.client.luau` toggles `Transparency` between `<side>Hand` and `<side>HandGrab` every Heartbeat, per limb, off `GrabTarget.limbHeldPosition` (the same held-step inference pupil tracking already used) — verified live in Studio for both limbs |

## Deliberate deviations from Unity

| Decision | Unity | Port | Why |
|---|---|---|---|
| Level progression | never advanced past Pot (`nextLevelIndex` written, never read) | Pot → Kitchen at 200 steps, Kitchen → Country at 500 (`Config.LEVEL_THRESHOLDS`) | Kitchen/Country were built but unreachable; owner's choice |
| Multiplayer field | local split-screen, one field per controller | one **lane** per player, side by side along X (doc 13) | per-player levels and sideways travel are impossible on a shared field |
| Spawner `Movements` offsets | off-screen staging points dragged on screen by the continuous per-frame pull | converted to studs with a fixed aspect assumption and **clamped** into the recycle margin | the port pulls per grab, not per frame, so an off-screen spawn would be recycled before it was ever seen |
| Spawner time per grab | spawners run a fixed 1 s per grab (`Step.cs` Pull: `Invoke("StopPull", 1f)`) while the field scrolls ~80 u/s, i.e. ~25 studs per grab | each grab earns `PULL_DISTANCE / Config.PULL_SPAWN_SPEED` = 6 / 8 = **0.75 s** of spawner time. `Lane.tickSpawners` drains that budget on the `PULL_TIME` timescale rather than 1 s per second, and it moves each spawn along the travel direction by the budget still unspent at its spawn moment, so a window's spawns spread out the way Unity's continuous scroll spreads them. `prefill` does the same within each row. Tutorial → Pot now prefills Pot's first screenful, as `StartRun` does | `PULL_SPAWN_SPEED` was 25, Unity's per-stud density. The port pulls only 6 studs per grab, so that earned only 0.24 s per grab, fewer steps than each grab consumes. Spawning runs only on pulls, so once nothing grabbable remained the lane deadlocked (b-20260921-110140-f9ic, reopening b-20260921-100739-ldv9). Budget drained at 1 s/s let faster grabbing outrun supply, and the Tutorial → Pot switch left Pot with one step at its off-screen staging point. In a headless sim (20 runs × 300 grabs × grab cadences of 1.2, 0.7 and 0.35 s), 8 kept Pot, Kitchen and Country supplied; Pot had about 21% of spawns land within 2.5 studs of another step. 6 crowds Pot (about 35%), and 10 or more starves Kitchen and Country. Caveat: spawns now surface just after each grab near the top edge of the view, sometimes a few studs inside it, instead of scrolling in from above |
| Attract-mode frog | drives the real frog with random screen taps (`FrogAI.cs`) with whichever limb is free | the real server-owned frog on a fixed 4-rung looping ladder (3 on screen), 1 s cadence, climbing with ONE hand (`WorldConfig.ATTRACT_LIMB`, right); each grab pulls the ladder down one rung gap like a real grab's `pullLane`, so the frog visibly lifts itself; the other hand reaches to the player's own menu clicks/taps (`ReachEmpty`, allowed in `Menu` for that hand only), and menu taps on a bug still eat it (Flys awarded; not counted in the next run's summary) | a fixed ladder because a Menu lane has no steps; the free hand gives the start screen something to react to the player |
| Bubble pop particles | Unity `ParticleSystem` | pooled part burst (same style as the lava splash) | |
| Death condition | `Player.cs Update`: `if (!HasStep && !frog.isDead && canFall) EndClimb()` — once you have grabbed one `canPull` step, letting go of **both** limbs ends the run instantly; the frog itself can never fall out of the world (only the head sinks, clamped at −50 u, and nothing in Unity kills on contact — `Lava.cs` has no collider) | the whole frog falls under `Config.GRAVITY` and the run ends when it reaches the lava surface (`Config.LAVA_Y`), i.e. ~1.79 s of grace to re-grab | doc 03's frame of reference: the port moves the frog and keeps Unity's fall curve, so "you let go" reads as a visible fall rather than an instant cut |
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
| Frog arm / hand draw order vs. steps (b-20260921-100824-3azi, b-20260921-110054-r51c) | `Limb.cs`'s (commented-out) sorting-layer swap moves the closed-grip hand from `FrogArms` to the `Rocks` sorting layer on grab, i.e. in front of the step; the arm/limb sprite otherwise sits behind steps | `RightArm`/`LeftArm` (the limb sprite) sit at Z −0.2 off their limb (was +0.2, i.e. wrongly in front of the Z 0 step plane). `RightHandGrab`/`LeftHandGrab` moved from being children of the root `RightLimb`/`LeftLimb` part (which tracks the held step's own Z 0, so the grip decal used to tie with the step it gripped) to their own small `RightHandGrab`/`LeftHandGrab` parts, siblings of `RightHand`/`LeftHand` under the limb root, at the same X/Y and Z +0.3 (already in front of steps, same depth the open-hand decal they swap with uses) but sized to the grab sprite's own smaller canvas (6.705 studs, the 256 px @ 12 ppu canvas from the row above) instead of `RightHand`/`LeftHand`'s larger one — an earlier pass hosted the grab decal directly on `RightHand`/`LeftHand` (correct Z, wrong canvas size), which stretched it to 4× its sprite's size | Roblox has no per-instance sorting layer for cross-part draw order, only Z depth (camera looks down −Z from +Z, so higher Z is more in front), so the swap is baked into each decal's host part instead of toggled at runtime; and a `Decal` always stretches to fill its host part, so the host must be sized to that decal's own canvas, not reuse a differently-sized neighbour's |
| Gamepad snap-assist | n/a | nearest step is grabbed but the **cursor** position is graded | keeps Perfect meaningful |
| Which limb a mouse button grabs with | `MouseInput.cs` reports two "touch indices" (0 = left button, 1 = right button) and `Controller.GetFreeLimb` gives the press **whichever limb is free**, so the same button drives either hand depending on press order | left button = the frog's **Left** limb, right button = its **Right** limb, fixed (`GameClient` sends the limb index with `GrabStep`; `GameServer` keys `f.held` by limb instead of packing it in grab order, so a release never shuffles the other hand's step onto the freed limb). Touch keeps Unity's rule — each new finger takes whichever limb is free — and each input releases only its own limb | owner's ruling (b-20260919-210748-vlyq): on keyboard+mouse the two buttons stand in for the two fingers, one must stay down at all times, and a hand-per-button has to be predictable. Both buttons were already first-class inputs in Unity; the port only handled `MouseButton1`, so right-click did nothing |
