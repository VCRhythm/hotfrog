# Port status, known gaps and deviations

_As of 2026-09-19. Update this file whenever a gap closes or a new one is found._

## Status

Every system of the original Unity game now has Luau behind it (docs 01–16).
The whole tree passes `selene`, `stylua`, `rojo build` and `luau-lsp` strict
analysis (the CI suite in `.github/workflows/ci.yml`).

**Nothing has been run in Roblox Studio yet.** Spawn density, lane spacing,
difficulty, UI scaling and how the game feels are all unverified. Each phase
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
   `SkinAssets` / `SoundAssets`, then spot-check one image in Studio: whether an
   `assetType=Image` upload id renders directly is still unverified.
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
| Invisible Man inherits Hot Frog's head | skins | `SkinAssets.part()` falls back to Hot Frog like the Unity prefabs | if it looks wrong in game, add a per-skin "no fallback" flag |
| `HeatBackground` / `LavaGradient` materials | backdrop | wired in `WorldBackdrop` but no level references them (same as Unity) | nothing, unless a level is retuned to use them |
| Lava height maps (`Lava_01_H1/H2.tga`) | backdrop | custom Unity shader inputs, no Roblox equivalent | n/a — `LavaGradient` uses the flat `Lava_01` texture |
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
| Gamepad snap-assist | n/a | nearest step is grabbed but the **cursor** position is graded | keeps Perfect meaningful |
