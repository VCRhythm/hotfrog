# Unity level & spawner data (extracted)

> Extracted by walking the dumped-to-JSON Unity prefabs/scenes (`prefab_dump/`, mirroring `Assets/`) with small Python scripts: `externals[m_FileID-1]` resolves cross-file `PPtr`s to asset paths, `m_FileID == 0` resolves to `objects[].path_id` within the same file, and `MonoBehaviour.m_Script` was resolved the same way to identify which `.cs` component each blob belongs to.
> All numbers below are copied verbatim from the serialized JSON (Unity 5.3 YAML→JSON). Where a value could not be resolved (missing external, absent field) it is called out explicitly rather than guessed.
> Source consulted for field semantics: `Core/Level.cs`, `Core/LevelManager.cs`, `Spawning/Spawner.cs`, `Spawning/StepSpawner.cs`, `Spawning/ScenerySpawner.cs`, `Spawning/StepAndScenerySpawner.cs`, `Spawning/BugSpawner.cs`, `Spawning/SpawnManager.cs`, `Spawning/ObjectPool.cs`.

## 1. LevelManager `levels` array

Source: `Prefabs/Managers/Level.prefab.json`, MonoBehaviour `Scripts\LevelManager.cs` (path_id `11434170`). Base array length is **4** (`Menu`, `Tutorial`, `Pot`, `Kitchen`). `currentLevelIndex = 0`, `furthestLevelIndex = 1`.

Note: the currently-checked-out `Core/Level.cs` declares an `overlay2Material` field, but **no `overlay2Material` key is present anywhere in the serialized `levels` data** (base prefab or scene overrides). Either the prefab predates that field being added to the class, or Unity never wrote a value for it — it cannot be resolved from this dump.

| # | levelName | musicIndex | hasTimedEvents | clearAllScenery | waitToLoad | backgroundMaterial | overlayMaterial | initialSpawnDirection | spawners (resolved) | levelObjects (resolved) |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | Menu | 1 | true | false | 0.0 | *(none)* | *(none)* | (0, -1) | `Prefabs/Levels/Level0/Spawners/BackGrassSpawner.prefab`, `Prefabs/Levels/Level0/Spawners/CloudSpawner.prefab`, `Prefabs/Levels/Level0/Spawners/GrassSpawner.prefab`, `Prefabs/Levels/Level0/Spawners/BackGrassSpawnerP2.prefab`, `Prefabs/Levels/Level0/Spawners/GrassSpawnerP2.prefab` | `Prefabs/Levels/Level0/Objects/Clouds.prefab` |
| 1 | Tutorial | 1 | true | false | 0.0 | *(none)* | `Materials/Water.mat` | (0, -1) | `Prefabs/Levels/Level1/Spawners/Player1TreeDownStepSpawner.prefab`, `Prefabs/Levels/Level1/Spawners/Player2TreeDownStepSpawner.prefab` | `Prefabs/Levels/Level1/Objects/Stars.prefab`, `Prefabs/Levels/Level1/Objects/SpeckManager.prefab` |
| 2 | Pot | 0 | true | true | 3.0 | `Materials/PotBack.mat` | `Materials/Water.mat` | (0, -1) | `Prefabs/Levels/Level2/Spawners/DownLeftStepSpawner.prefab`, `Prefabs/Levels/Level2/Spawners/DownRightStepSpawner.prefab`, `Prefabs/Levels/Level2/Spawners/DownStepSpawner.prefab`, `Prefabs/Levels/Level2/Spawners/FlameScenerySpawner.prefab` | *(empty)* |
| 3 | Kitchen | 1 | true | true | 0.0 | `Materials/KitchenTile.mat` | *(none)* | (0, -1) | `Prefabs/Levels/Level3/Spawners/DownRightStepSpawner.prefab`, `Prefabs/Levels/Level3/Spawners/DownLeftStepSpawner.prefab`, `Prefabs/Levels/Level3/Spawners/RightStepSpawner.prefab`, `Prefabs/Levels/Level3/Spawners/LeftStepSpawner.prefab`, `Prefabs/Levels/Level3/Spawners/DownStepSpawner.prefab`, `Prefabs/Levels/Level3/Spawners/DownScenerySpawner.prefab` | *(empty)* |

`aiPrefab` (LevelManager field, outside the `levels` array) resolves to `Prefabs/Controllers/AI.prefab`.

### Level4 "Country" — exists only as a scene override, not in the base array

`Prefabs/Levels/Level4/` and `Prefabs/Levels/Level3/` folders exist on disk, and `Climb.unity.json`'s `PrefabInstance` of `Level.prefab` carries **no** modifications to the `levels` array (only a `placeHolderStepForLevelPulling` object reference) — i.e. the Climb scene uses the base 4-level array unmodified.

`Multiplayer.unity.json`, however, contains a `PrefabInstance` (path_id `1173578586`, parent `Prefabs/Managers/Level.prefab`) whose `m_Modifications` grow the array to **5 entries** and add a 5th level at index 4:

| Field | Value |
|---|---|
| levelName | `Country` |
| musicIndex | 4 |
| hasTimedEvents | true |
| clearAllScenery | true |
| backgroundMaterial | explicitly set to none (`{fileID:0,pathID:0}`) |
| initialSpawnDirection | **(-0.5, 0)** — the only level whose initial direction is horizontal rather than straight down |
| spawners | `Prefabs/Levels/Level4/Spawners/RightStepSpawner.prefab`, `Prefabs/Levels/Level3/Spawners/DownLeftStepSpawner.prefab`, `Prefabs/Levels/Level3/Spawners/RightStepSpawner.prefab`, `Prefabs/Levels/Level3/Spawners/LeftStepSpawner.prefab`, `Prefabs/Levels/Level3/Spawners/DownStepSpawner.prefab`, `Prefabs/Levels/Level3/Spawners/DownScenerySpawner.prefab` |
| levelObjects | `Prefabs/Levels/Level4/Objects/US.prefab` |

The same Multiplayer override also patches the base 4 levels:
- `furthestLevelIndex` overridden to `2`.
- Level 0 (Menu) and level 1 (Tutorial) `backgroundMaterial` both overridden to `Materials/Sky.mat` (base prefab leaves them unset).
- Level 2 (Pot) gets a 5th spawner appended: `Prefabs/Levels/Level2/Spawners/UpScenerySpawner.prefab`.
- Level 3 (Kitchen) gets a `levelObjects` entry appended: `Prefabs/Spawns/Scenery/Chef.prefab`.
- Unrelated tweaks in the same override: `WallTop`'s local position/rotation nudged, one `MeshRenderer` disabled, a step's `isInvincible` set true, a light's culling mask changed, a step's x-position nudged to 4.2 — cosmetic/physical adjustments for the multiplayer camera split, not level-data.

**Surprising finding:** `Level4/Spawners/RightStepSpawner.prefab` has `spawnDirection = (-0.5, 0)` (i.e. it is actually a *left*-moving spawner despite its name) and its pool contains `Rocket`/`Balloon` prefabs instead of rocks — a themed, one-off spawner exclusive to the Country/Multiplayer level.

## 2. Spawner prefabs

Type enum mapping (`Spawner.Type` in `Spawning/Spawner.cs`): `0=All, 1=Bug, 2=Step, 3=Scenery`.

### 2a. Spawners actually referenced by the levels above (`Level0`–`Level4`)

| File | Script | spawnerType | spawnDirection | discreteMove | moveTime min/max | moveSpeed min/max | maxSpawnCount | spawningSpeed min/max | position | Subclass-specific fields | Pool: name / initial / canGrow | Pooled prefabs (ordered) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Level0/Spawners/BackGrassSpawner | ScenerySpawner | Scenery | (0, 1) | false | 0/0 | 0.1/0.3 | 50 | 0/0 | (0,0,0) | spawnAllOnAwake=false, minScale=1, maxScale=1, colorOptions=4 greens, `canDuplicateWhen2Player` (legacy field, not in current `ScenerySpawner.cs`) | Scenery / 20 / true | `Spawns/Scenery/BackGrass.prefab` |
| Level0/Spawners/BackGrassSpawnerP2 | ScenerySpawner | Scenery | (0, 1) | false | 0/0 | 0.1/0.3 | 50 | 0/0 | (0,0,0) | isDuplicateFor2Player=true, colorOptions=4 greens | Scenery / 20 / true | `Spawns/Scenery/BackGrassP2.prefab` |
| Level0/Spawners/CloudSpawner | ScenerySpawner | Scenery | (-1, 0) | false | 1/2 | 1/2 | -1 (infinite) | 10/20 | (61.9, 33.6, 0) | isDuplicateFor2Player=false, colorOptions=5 pastel tints | Scenery / 6 / true | `Spawns/Scenery/Cloud3.prefab` |
| Level0/Spawners/GrassSpawner | ScenerySpawner | Scenery | (0, 1) | false | 0/0 | 0.1/0.3 | 50 | 0/0 | (0,0,0) | isDuplicateFor2Player=false, colorOptions=4 greens | Scenery / 20 / true | `Spawns/Scenery/Grass.prefab` |
| Level0/Spawners/GrassSpawnerP2 | ScenerySpawner | Scenery | (0, 1) | false | 0/0 | 0.1/0.3 | 50 | 0/0 | (0,0,0) | isDuplicateFor2Player=true, colorOptions=4 greens | Scenery / 20 / true | `Spawns/Scenery/GrassP2.prefab` |
| Level1/Spawners/Player1TreeDownStepSpawner | StepAndScenerySpawner | Step | (0, -1) | true | 1/1 | 1/1 | 3 | 1/1 | (0,20,0) | spawnAllOnAwake=true, minScale=1, maxScale=1 | Steps / 3 / **false** | `FirstTree`, `SecondTree`, `LastTree` (all `Spawns/Scenery/`) |
| Level1/Spawners/Player2TreeDownStepSpawner | StepAndScenerySpawner | Step | (0, -1) | true | 1/1 | 1/1 | 3 | 1/1 | (0,20,0) | spawnAllOnAwake=true | Steps / 3 / **false** | `FirstTreePlayer2`, `SecondTreePlayer2`, `LastTreePlayer2` |
| Level2/Spawners/DownLeftStepSpawner | StepSpawner | Step | (-0.5, -1) | true | 1/2 | 0.5/1 | -1 | 0.5/0.7 | (0,20,0) | isDuplicateFor2Player=false | Steps / 15 / true | `Potato`, `Carrot`, `UpRock` |
| Level2/Spawners/DownRightStepSpawner | StepSpawner | Step | (0.5, -1) | true | 1/2 | 0.5/1 | -1 | 0.5/0.7 | (0,20,0) | isDuplicateFor2Player=false | Steps / 15 / true | `Carrot`, `Potato`, `UpRock` |
| Level2/Spawners/DownStepSpawner | StepSpawner | Step | (0, -1) | **false** | 0.5/1 | 1/2 | -1 | 0.25/0.35 | (0,20,0) | isDuplicateFor2Player=false | Steps / 15 / true | `Potato`, `Carrot`, `UpLeftRock`, `UpRightRock` |
| Level2/Spawners/FlameScenerySpawner | ScenerySpawner | Scenery | (0, 1) | false | 1/2 | 1/1 | 5 | 5/5 | (-3,60,0) | spawnAllOnAwake=true, 10-point Movements list | Scenery / 10 / true | `Spawns/Scenery/Flame.prefab` |
| Level2/Spawners/UpScenerySpawner *(only reachable via Multiplayer override)* | ScenerySpawner | Scenery | (0, 1) | false | 1/2 | 1/2 | -1 | 5/10 | (0,20,0) | spawnAllOnAwake=false | **Steps** (pool named "Steps" despite Scenery type) / 15 / true | `Spawns/Scenery/Bubble.prefab` |
| Level3/Spawners/DownLeftStepSpawner | StepSpawner | Step | (-0.5, -1) | true | 1/2 | 0.5/1 | -1 | 0.5/1.0 | (0,20,0) | isDuplicateFor2Player=false | Steps / 15 / true | `ShelfWithSpoon`, `ShelfWithFork`, `Shelf`, `UpRock` |
| Level3/Spawners/DownRightStepSpawner | StepSpawner | Step | (0.5, -1) | true | 1/2 | 0.5/1 | -1 | 0.5/1.0 | (0,20,0) | isDuplicateFor2Player=false | Steps / 15 / true | `ShelfWithSpoon`, `ShelfWithFork`, `Shelf`, `UpRock` |
| Level3/Spawners/DownScenerySpawner | ScenerySpawner | Scenery | (0, -1) | false | 1/2 | 1/1 | -1 | 10/20 | (-3,60,0) | spawnAllOnAwake=false | Scenery / 5 / true | `Spawns/Scenery/Window.prefab` |
| Level3/Spawners/DownStepSpawner | StepSpawner | Step | (0, -1) | false | 1/2 | 0.5/1 | -1 | 0.5/1.0 | (0,20,0) | isDuplicateFor2Player=false | Steps / 15 / true | `ShelfWithSpoon`, `ShelfWithFork`, `Shelf`, `UpLeftRock`, `UpRightRock` |
| Level3/Spawners/LeftStepSpawner | StepSpawner | Step | (-0.5, 0) | true | 1/2 | 0.5/1 | -1 | 0.5/1.0 | (0,20,0) | isDuplicateFor2Player=false | Steps / 15 / true | `ShelfWithSpoon`, `ShelfWithFork`, `Shelf`, `UpRock`, `UpLeftRock` |
| Level3/Spawners/RightStepSpawner | StepSpawner | Step | (0.5, 0) | true | 1/2 | 0.5/1 | -1 | 0.5/1.0 | (0,20,0) | isDuplicateFor2Player=false | Steps / 15 / true | `ShelfWithSpoon`, `ShelfWithFork`, `Shelf`, `UpRock`, `UpRightRock` |
| Level4/Spawners/RightStepSpawner *(Multiplayer-only, name is misleading)* | StepSpawner | Step | **(-0.5, 0)** | false | 1/2 | 0.5/1 | -1 | 2/3 | (0,20,0) | isDuplicateFor2Player=false | Steps / 15 / true | `Spawns/Steps/Rocket.prefab`, `Spawns/Steps/Balloon.prefab` |

All `Movements` lists (per-spawner discrete/tween target offsets) were extracted but omitted from the table for width; see `spawners_extracted.json` logic (raw values were printed during extraction and match the offsets implied by each spawner's direction, e.g. Level3 `LeftStepSpawner` moves through `(1.5,0.5,0)→(1.5,0,0)→(1.5,-0.5,0)`).

### 2b. `Prefabs/Levels/General/Spawners/*` and `Prefabs/Levels/General/Spawners.prefab.json` — legacy/orphaned, not referenced by any level above

These prefabs live directly under `Prefabs/Levels/General/Spawners/` (as the task specified checking) but **none of their GUIDs appear in `Level.prefab.json`'s `externals` list**, and their serialized fields use an **older, incompatible schema**: `spawnType` instead of `type`, `maxSpawn` instead of `maxSpawnCount`, `canSpawn`/`isSpawningTameSpawns` instead of the current `isSpawning`, and they lack `spawningSpeedMin/Max`'s current meaning, `moveTimeMin/Max`, and (for step ones) `spawnDirection` is present but the type enum field itself (`spawnType`) is absent of a resolvable current-type key. This indicates they were serialized against an earlier version of `Spawner.cs`/`BugSpawner.cs` and left behind as unused templates:

| File | Script | position | spawnDirection | pool / pooled prefabs |
|---|---|---|---|---|
| General/Spawners/BugSpawner | BugSpawner | (-45,60,1) | n/a | initial 10, canGrow=true → `Spawns/Bugs/Bug.prefab` |
| General/Spawners/DownLeftStepSpawner | StepSpawner | (0,20,0) | (-1,-1) | initial 15, canGrow=true → 11 `Spawns/Steps/*` prefabs (StillRock, CrumblyRock, UpRock, UpLeftRock, UpRightRock, Beetle, FallingRock, Castle + 3 empty slots) |
| General/Spawners/DownRightStepSpawner | StepSpawner | (0,20,0) | (1,-1) | same 11-slot Steps pool as above |
| General/Spawners/DownStepSpawner | StepSpawner | (0,20,0) | (0,-1) | same 11-slot Steps pool |
| General/Spawners/LeftStepSpawner | StepSpawner | (0,20,0) | (-1,0) | same 11-slot Steps pool |
| General/Spawners/RightStepSpawner | StepSpawner | (0,20,0) | (1,0) | same 11-slot Steps pool |
| General/Spawners/PebbleSpawner | ScenerySpawner | (-3,60,0) | n/a | initial 15, canGrow=true → `Spawns/Pebbles/SmallRock.prefab` |
| General/Spawners/ScenerySpawner | ScenerySpawner | (-3,60,0) | n/a | initial 12, canGrow=true → `Cloud1Left`, `Cloud2Left` |
| General/Spawners.prefab.json (root GO "Spawners", child GO "BugSpawner") | BugSpawner + **SpawnManager** | (0,0,0) | n/a | initial 100, canGrow=true → `Spawns/Bugs/Bug.prefab` |

Note these General/Spawners/* directional spawners use *full unit vectors* `(±1, ±1)` for diagonal/side directions, whereas the live Level2/Level3 spawners of the same names use *half-magnitude* `(±0.5, ±1)` / `(±0.5, 0)` — consistent with them being an earlier iteration of the same design, superseded by the Level2/Level3 copies.

`Prefabs/Levels/General/Spawners.prefab.json` is the one file in the whole dump that carries `SpawnManager.cs`'s own serialized data (see §4).

## 3. Structural summary of general/objects prefabs

### Background (`Prefabs/Levels/General/Background.prefab.json`)
Root has no single GameObject; it's a flat list of siblings:
- `Sky` — Transform (0,0,0); `MeshFilter`+`MeshRenderer`, material `m_FileID 3` → **unresolved** (external guid `7cfdd49d7db54643941c0f00f27f547e` has an empty `path` in the dump, i.e. the source asset could not be found — likely `Materials/Sky.mat` but not confirmable from this data).
- `Background` — Transform only, pos (0,0,4), scale (10,1,10) — presumably a parent/anchor for level-specific background quads that get `SetMaterial()`'d via `Wall.cs`.
- `Lava` — Transform (0,-1,0); `Lava.cs` (no serialized fields — script exposes nothing to the inspector); `ObjectPool.cs`: initialPoolSize 10, canGrow=false, pooled → `Spawns/Scenery/LavaSplash.prefab`.
- `Heat` — Transform (0,-1,0); `MeshFilter`+`MeshRenderer`, material → `Materials/HeatBackground.mat`.
- `Plane` — Transform (0,0,0); `MeshFilter`+`MeshRenderer`, material → `Materials/LavaGradient.mat`.

### Borders (`Prefabs/Levels/General/Borders.prefab.json`)
Flat list of trigger/physical colliders defining the playfield edges (all `BoxCollider2D`, size 1×1 scaled by the transform's local scale):
- `LeftCatch` pos (-70.8, -17, 1), scale (1, 165, 1), **isTrigger=true**
- `RightCatch` pos (70.2, -17, 1), scale (1, 165, 1), **isTrigger=true**
- `LeftRockBarrier` pos (-51, -17, 1), scale (1, 165, 1), isTrigger=false (solid)
- `RightRockBarrier` pos (51.7, -17, 1), scale (1, 165, 1), isTrigger=false (solid)
- `TopCatch` pos (0, 75, 0), scale (140, 1, 1), isTrigger=true
- `BottomCatch` pos (0, -100, 0), scale (140, 1, 1), isTrigger=true — this is the bottom "net"/kill-trigger implied by `Scenery.cs`'s `isDestroyableByBottomNet` flag.
- `Borders` — empty parent Transform at origin.

### Sun (`Prefabs/Levels/General/Sun.prefab.json`)
- `Sun` — Transform (0.4, 50.5, 1.5), scale (1.262, 1, 1); `SpriteRenderer` using sprite material `m_FileID 3` (`Standard Assets/Effects/LightFlares/Flares/Sun.flare` / `Sprites/Other/Sun.png` per Level.prefab's own externals); `Sun.cs`; `Animator` (driven by `Animation/Sun.controller`, toggling `isNight`/`isBlack` bools per `LevelManager.FillLevelEvents`).
- `Light` — directional/point light, pos (0, -11.4, 0).
- `Point light` — pos (0, -3.7, 0).

### Clouds (`Prefabs/Levels/Level0/Objects/Clouds.prefab.json`)
Menu-only decoration: a root `Clouds` GameObject (pos (-31.29, -75, 0.1); `SceneryObject.cs` with `canDestroyWhenShowingMenu=false`) parenting **14** `Cloud3`-family `SpriteRenderer` children scattered between roughly x=-94..+188, y=98..132, each with its own `Scenery.cs` (isDestroyableByBottomNet=true, speedModifier 0.3–0.5, autoMovement (-5,0) i.e. constant left drift) — a static parallax cloud layer, not spawner-driven.

### Stars (`Prefabs/Levels/Level1/Objects/Stars.prefab.json`)
Single GameObject `Stars`, pos (9.1, 15.9, 2), scale (2,1,1); `SpriteRenderer` on `Materials/Stars.mat`; `Scenery.cs` (spawnProbability 0, isDestroyableByBottomNet=true, speedModifier 0.05); `Rigidbody2D`; `Animator`; `LevelObject.cs` (canDestroyWhenShowingMenu=true). Toggled on for the Tutorial's night sequence.

### SpeckManager (`Prefabs/Levels/Level1/Objects/SpeckManager.prefab.json`)
Single GameObject `SpeckManager`: `ObjectPool.cs` (poolName "Specks", initialPoolSize 100, canGrow=false, pooled prefab resolved only as local path_id `11404784` — a MonoBehaviour/prefab inside the same file, not an external); `SpeckManager.cs` (canDestroyWhenShowingMenu=true, 8-color `colorOptions` array — white, yellow-green, green, magenta, cyan, purple, orange, red). Drives the tutorial's firefly/guidance specks (`MoveSpecks`/`ActivateSpecks` calls in `LevelManager`).

### US (`Prefabs/Levels/Level4/Objects/US.prefab.json`, Multiplayer/Country level only)
- `US` — Transform pos (171, -15, 137), scale (1, 0.871, 1); `UnitedStates.cs` (canDestroyWhenShowingMenu=true, 2 colors: blue, red); `Rigidbody2D`; `SpriteRenderer`; `Scenery.cs` (spawnProbability 1, isInvincible=false, speedModifier 0.1).
- `USRedStates` / `USBlueStates` — two child `SpriteRenderer`-only GameObjects at local origin (presumably a two-layer USA-map cutout keyed to `UnitedStates.cs`'s two colors).

## 4. Playfield dimensions (from SpawnManager, cameras, Lava, Walls, Borders)

### SpawnManager.spawnDirections (`Prefabs/Levels/General/Spawners.prefab.json`, `Scripts\SpawnManager.cs`)
```
spawnDirections = [ (0,-1), (1,0), (-1,0), (1,-1), (-1,-1) ]
pullVector = (0,0); spawnDirection = (-0,-1); stepsCanSpawn = false
```
**Surprising / possibly-a-bug finding:** these are full unit vectors, but every diagonal/side `StepSpawner.spawnDirection` actually used in Level2–Level4 is a **half-magnitude** vector, e.g. `(-0.5,-1)`, `(0.5,-1)`, `(-0.5,0)`, `(0.5,0)` (§2a). `SpawnManager.CollectLevelSpawners()` keys a dictionary (`spawnersInDirection`) by `spawner.spawnDirection` and it's initialized from exactly this `spawnDirections` array (`SetUpSpawnDirections()`), so with these literal values, a lookup for e.g. `(-0.5,-1)` would not match a pre-existing dictionary key of `(-1,-1)` and `spawnersInDirection[spawner.spawnDirection]` would need to already contain that exact key (added via `Add` for each of the 5 array entries only) — i.e. as serialized, the half-magnitude diagonal directions used by actual level spawners don't correspond to any of the 5 keys the dictionary is initialized with. This is either a real latent bug in the original project, a value the scenes overrode elsewhere (no such override was found in `Climb.unity.json` or `Multiplayer.unity.json` — grep of the whole dump for `spawnDirections` found only this one file), or a field whose true runtime values are set via code not covered by this dump.

### Cameras (`Prefabs/Managers/Cameras.prefab.json` — base prefab)
All 4 cameras are orthographic, size **50**, near/far clip 1/10:
| Camera | local position | depth |
|---|---|---|
| Background Camera | (0, 0, -2) | -2 |
| Player 1 Camera | (0, 0, -2) | -1 |
| Player 2 Camera | (62.5, 0, -2) | -1 |
| UI Camera | (0, 0, -2) | 0 |

### Cameras as placed in `Multiplayer.unity.json` (5 cameras, embedded directly in the scene — not a PrefabInstance)
| Camera | local position | depth |
|---|---|---|
| Background Camera | (31.25, 0, -200) | -2 |
| Player 1 Camera | (0, 0, -200) | -1 |
| Player 2 Camera | (62.5, 0, -200) | -1 |
| UI Camera | (0, 0, -200) | 0 |
| Frog Camera | (0, 0, -200) | 1 |
All still orthographic size 50. `Spawner.SetMovementToScreenSize()` uses `halfScreenHeight = 50` and `halfScreenWidth = 50 * (Screen.width/Screen.height)` — i.e. the ±50 vertical bound is fixed by these cameras' orthographic size, confirming the playfield's vertical half-extent is 50 units.

### Lava (`Prefabs/Managers/Level.prefab.json`)
`Lava.cs` MonoBehaviour has **no serialized/public fields** (component data is empty beyond the standard boilerplate) — `LiftHeat`/`LowerHeat` presumably act on sibling components (Animator/Renderer) fetched via `GetComponent` at runtime, not visible in this dump. Its GameObject `Lava` transform: local position **(0, 0, 10)**, scale (1,1,1). (A second, separate `Lava` GameObject also exists inside `Background.prefab.json` at local position (0,-1,0) — see §3 — carrying the actual `ObjectPool` for `LavaSplash.prefab`.)

### Walls (`Prefabs/Managers/Level.prefab.json`, `Scripts\Wall.cs`)
Six `Wall` components (`wallToTop`/`wallToLeft`/`wallToRight` are same-file `PPtr` cross-references to sibling wall Transforms), all local scale (10,10,1):
| GameObject | local position |
|---|---|
| WallCenter | (0, -1, 0) |
| WallLeft | (-9.99, -1, 0) |
| WallRight | (9.99, -1, 0) |
| WallTop | (0, 9, 0) |
| WallTopLeft | (-9.99, 9, 0) |
| WallTopRight | (9.99, 9, 0) |
There is no `WallBottom` — the bottom of the pit is the lava/kill zone, not a wall. (These positions/scale are local to whatever parent transform the Wall prefab hierarchy sits under in the scene; they are far smaller than the ±50/±70 camera and border extents, so they should not be read as absolute playfield-edge coordinates — see Borders below for that.)

### Border/kill triggers (already detailed in §3 "Borders") — these are the actual playfield-bounds source:
- Horizontal catch bounds: **x ≈ -70.8 to +70.2** (`LeftCatch`/`RightCatch`, triggers)
- Horizontal solid rock barriers (narrower, inside the catch bounds): **x ≈ -51 to +51.7**
- Vertical bounds: **top catch at y = 75**, **bottom catch/"net" at y = -100** (both 140 units wide, triggers)

## Extraction notes / caveats

- `Prefabs/Levels/General/Spawners/*.prefab.json` and `Prefabs/Levels/General/Spawners.prefab.json`'s `BugSpawner` sub-object are **not** referenced by `Level.prefab.json`'s `externals`, confirming they are unused legacy content (see §2b), while `Prefabs/Levels/General/Spawners.prefab.json`'s own `SpawnManager.cs` component **is** the live SpawnManager data (§4).
- The `Sky` material reference in `Background.prefab.json` (external guid `7cfdd49d7db54643941c0f00f27f547e`) could not be resolved to a path in this dump (empty `path` in `externals`) — flagged rather than guessed.
- `SpeckManager.prefab.json`'s pooled prefab (`pooledObjectPrefabs[0]`) resolves to a **local** `path_id` (`11404784`) inside the same file rather than an external asset — i.e. the Speck prefab is nested inside `SpeckManager.prefab` itself, not a separate `.prefab` file.
- `Level4`/"Country" only exists via the `Multiplayer.unity.json` scene's `PrefabInstance` override of `Level.prefab`; it is absent from the base `Level.prefab.json` and from `Climb.unity.json`.
- Difficulty progression, as evidenced by the data: **Menu** (level 0) has no step spawners at all (pure background decoration). **Tutorial** (level 1) uses `StepAndScenerySpawner`s with `maxSpawnCount = 3` and `spawnAllOnAwake = true` — a fixed, one-shot set of exactly 3 steps, always spawning straight down, discrete movement. **Pot** (level 2) switches to continuous/infinite (`maxSpawnCount = -1`) `StepSpawner`s with the first diagonal directions (`DownLeft`/`DownRight`, magnitude 0.5) alongside `Down`, and a separate hazard scenery spawner (Flame). **Kitchen** (level 3) keeps continuous infinite spawning and adds the first pure-horizontal directions (`Left`/`Right`), giving it the largest spawner set (6) of the base game and the widest movement-direction coverage. **Country** (level 4, Multiplayer-exclusive) reuses Kitchen's spawners wholesale and adds one themed spawner, but is unique in starting the level with a **horizontal** `initialSpawnDirection` (-0.5, 0) instead of straight down — every other level starts by falling downward, so Country changes the base traversal pattern itself rather than just adding more spawners, consistent with it being bonus/end-game content gated behind multiplayer.
