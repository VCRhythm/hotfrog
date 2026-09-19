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
   `legacy-asset:manage`. **Upload one test image first** and confirm it
   renders in Studio: the decal → image id resolution has never run against
   the live API.
3. **Create products** and paste ids:
   - 4 Game Passes → `src/shared/SkinCatalog.luau` (`gamePassId`)
   - Fly-pack Developer Products → `FLY_PRODUCTS` in
     `src/server/SkinService.server.luau`
   - 10 badges (10…100 steps) → `src/shared/Badges.luau`
4. **Enable** "Studio Access to API Services" (DataStores) and publish.

## Known gaps

| Gap | Where | Why | What would close it |
|---|---|---|---|
| Attract mode (`Player/FrogAI.cs`) | menu | skipped as low priority | client-side idle climb on a couple of decorative steps while in `Menu` state |
| `hurt` sound (`Entities/Lava.cs` FallSplash) | audio | `GameOver` doesn't say *how* the frog died | add a death-cause argument to `GameOver` / `RunSummary` |
| Bubble `pop` sound | audio | scenery isn't grabbable in the port | grabbable scenery (`StepAndScenery.cs`) |
| Background textures (`PotBack`, `KitchenTile`, `Sky`, `Water`, `HeatBackground`, `LavaGradient`) | backdrop | Unity *materials*, not sprites — not in `/Sprites` or the manifest | export their textures from the Unity project's `Assets/Materials`, add to `tools/build_manifest.py` + `SkinAssets` |
| `US` map for Country | scenery | two-layer material cutout, no single sprite | render `USRedStates`/`USBlueStates` as two tinted decals |
| Skin thumbnails for Blue / Space / Mystery Frog | store | no thumbnail file in `Sprites/Menu` | draw them; the UI falls back to the Head sprite meanwhile |
| Music toggle saves the profile on every click | settings | no debounce | throttle `SetMusicOn` saves (e.g. 5 s) |
| "Drugged" frog effect (`Frog.cs MakeDrugged`) | cosmetics | nothing in the port triggers it | only if a step type re-introduces it |
| Per-spawner `Movements` lists | spawning | doc 11 only kept one example | re-extract from the prefab dump if procedural positions feel wrong |
| Invisible Man inherits Hot Frog's head | skins | `SkinAssets.part()` falls back to Hot Frog like the Unity prefabs | if it looks wrong in game, add a per-skin "no fallback" flag |
| Bugs-this-run counter | HUD | identified by Fly amount `== Config.BUG_FLYS` | a dedicated server signal if faucet amounts ever change |

## Deliberate deviations from Unity

| Decision | Unity | Port | Why |
|---|---|---|---|
| Level progression | never advanced past Pot (`nextLevelIndex` written, never read) | Pot → Kitchen at 200 steps, Kitchen → Country at 500 (`Config.LEVEL_THRESHOLDS`) | Kitchen/Country were built but unreachable; owner's choice |
| Multiplayer field | local split-screen, one field per controller | one **lane** per player, side by side along X (doc 13) | per-player levels and sideways travel are impossible on a shared field |
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
