# Unity step, spawn, frog & audio data (extracted)

> Extracted by loading the dumped prefab/scene JSON (`prefab_dump\Prefabs\...`) with a small Python script that resolves `PPtr` fields (`m_FileID`/`m_PathID`) against each file's `externals` list and its own `objects` table, and cross-referencing serialized field names against the current C# in `Entities/`, `Spawning/`, and `Audio/`. All numbers below are copied verbatim from the JSON (no rounding beyond what's already in the source floats).
> Where a serialized field name does not exist on the current (modernized) script, or an old field appears alongside/instead of the current one, this is called out explicitly — it reflects a real discrepancy between the Unity 5.3 project's field names at the time of last save and the ported C#, not a transcription error.
> "not in current C#" below means: present in the JSON `data` for that MonoBehaviour, but no matching field exists in the script file listed in this task's read list.

## Step ActionType enum (from `Entities/Step.cs`)

| Int | Name |
|---|---|
| 0 | None |
| 1 | Crumble |
| 2 | CrumbleAfterRelease |
| 3 | Fall |
| 4 | ChangeDirectionUp |
| 5 | ChangeDirectionLeft |
| 6 | ChangeDirectionRight |
| 7 | ChangeDirectionUpRight |
| 8 | ChangeDirectionUpLeft |
| 9 | Launch |
| 10 | SlideOff |
| 11 | MakeFunky |
| 12 | MakeTarget |
| 13 | Move |
| 14 | RiseAndFall |
| 15 | Beetle |
| 16 | Castle |
| 17 | PullByLocation |
| 18 | Falling |
| 19 | SplashFlinging |
| 20 | StepFlinging |
| 21 | SpawnFly |
| 22 | Helper |

**Enum values actually used by shipped prefabs:** 0, 2, 3, 4, 5, 6, 7, 8, 15, 18, 19, 21, 22 (see tables below; none out of range).
**Enum values with a `case` in `Step.AssignInteractionAction()` but never used by any dumped prefab:** 1 (Crumble), 9 (Launch)\*, 10 (SlideOff)\*, 11 (MakeFunky)\*, 12 (MakeTarget)\*, 13 (Move)\*, 14 (RiseAndFall)\*, 16 (Castle), 17 (PullByLocation), 20 (StepFlinging).
\* 9–14 also have no `case` at all in the current `AssignInteractionAction()` switch — they're dead in both directions.

A field-naming pattern seen across almost every Step/Scenery/Bug/Splash MonoBehaviour: many prefabs serialize a field called **`useAlternate`** (bool) and/or **`isInvincible`** (bool) that do **not exist** in the current `Spawn.cs`/`RigidbodySpawn.cs`/`Step.cs`. Some prefabs have `isDestroyableByBottomNet` only, some have `isInvincible` only, and a few (e.g. `UpLeftRock`, `UpRightRock`, `UpRock`) have *both* simultaneously. This looks like leftover serialized data from an earlier field name/rename in the original Unity project (`isInvincible` → `isDestroyableByBottomNet`?) that Unity kept for objects not re-saved since. Treat `isDestroyableByBottomNet` as authoritative where present; `isInvincible`/`useAlternate` values are reported below for completeness but have no current-code equivalent.

---

## 1. Steps (`Prefabs\Spawns\Steps\*`)

All Step root GameObjects: tag `Step`, `m_Layer=8`, root `localScale=(1,1,1)` in every prefab (no exceptions found). Rigidbody2D `m_Mass=1`, `m_LinearDrag=2`, `m_AngularDrag=0.800000011920929`, `m_GravityScale=0`, `m_IsKinematic=false` in every prefab except where noted; `m_Constraints=4` = FreezeRotation (matches `hasRotationFrozen` read from `rb2D.freezeRotation` in `Step.Awake`), `m_Constraints=0` = free rotation.

| Prefab | actionType (int→name) | spawnProbability | canPull | isDestroyableByBottomNet / isInvincible (raw) | Rigidbody2D (constraints / interpolate / collisionDetection) | Collider | Root localPos | Sprite(s) |
|---|---|---|---|---|---|---|---|---|
| Balloon | 0 → None | 1.0 | 1 | isInvincible=0 (no `isDestroyableByBottomNet` field) | constraints=4, interp=0, colDet=0 | BoxCollider2D size=(40,40) offset=(0,25) | (0,0,0) | `Sprites\Rocks\Balloon.png` |
| Beetle | 15 → Beetle | 0.5 | 1 | isDestroyableByBottomNet=1 | constraints=0, interp=1, colDet=1 | CircleCollider2D r=11 offset=(0.9,0) | (0,0,0) | `Sprites\Rocks\WhiteRock.png` tinted black (color r0 g0 b0 a1) |
| Carrot | 0 → None | 0.5 | 1 | isDestroyableByBottomNet=1 | constraints=0, interp=1, colDet=1 | BoxCollider2D size=(20.819,14.195) offset=(-0.091,0.547) | (-46.9,0,0) | see children |
| Castle | 0 → None (enum value 16 "Castle" unused by this prefab) | 0.5 | 1 | isDestroyableByBottomNet=1 | constraints=0, interp=1, colDet=1 | CircleCollider2D r=13 offset=(0,-7) | (0,0,0) | `Sprites\Rocks\Castle.png` tinted (1, 0.459, 0.395, 1) |
| CrumblyRock | **0 → None** (name suggests Crumble=1; flagged, see below) | 0.5 | 1 | isDestroyableByBottomNet=1 | constraints=0, interp=1, colDet=1 | CircleCollider2D r=11 offset=(0.9,0) | (0,0,0) | `Sprites\Rocks\CrumblyRock.png` |
| FallingRock | 18 → Falling | 0.5 | 1 | isDestroyableByBottomNet=1 | constraints=0, interp=1, colDet=1 | CircleCollider2D r=11 offset=(0.9,0) | (0,0,0) | `Sprites\Rocks\WhiteRock.png` tinted (1,0.459,0.395,1) |
| FlingingRock | 19 → SplashFlinging | 0.5 | 1 | isDestroyableByBottomNet=1 | constraints=4, interp=1, colDet=1 | CircleCollider2D r=11 offset=(0.9,0) | (0,0,0) | `Sprites\Rocks\WrappedRock.png`; child "Flingee" = `Sprites\Scenery\Flame.png` |
| FlyRock | 21 → SpawnFly | 0.5 | 1 | isDestroyableByBottomNet=1 | constraints=4, interp=1, colDet=1 | CircleCollider2D r=11 offset=(0.9,0) | (0,0,0) | `Sprites\Rocks\WrappedRock.png`; child "Bug" = `Sprites\Other\Bug.png` |
| LeftRock | 5 → ChangeDirectionLeft | 0.1 | 1 | isInvincible=0 | constraints=4, interp=1, colDet=1 | CircleCollider2D r=11 offset=(0.9,0) | (0,0,0) | `Sprites\Rocks\LeftArrow.png` |
| Potato | 2 → CrumbleAfterRelease | 0.5 | 1 | isDestroyableByBottomNet=1 | constraints=4, interp=1, colDet=1 | CircleCollider2D r=8 offset=(-0.04,1.45) | (0,0,0) | `Sprites\Rocks\Potato.png` |
| RightRock | 6 → ChangeDirectionRight | 0.1 | 1 | isInvincible=0 | constraints=4, interp=1, colDet=1 | CircleCollider2D r=11 offset=(0.9,0) | (0,0,0) | `Sprites\Rocks\RightArrow.png` |
| Rocket | 0 → None | 1.0 | 1 | isInvincible=0 (has `autoMovementMin/Max` fields — see note) | constraints=4, interp=0, colDet=0 | BoxCollider2D size=(20.748,24.920) offset=(-0.749,65.805) | (0,-30,0) | `Sprites\Rocks\Rocket.png`; child "Flames" = `Sprites\Scenery\Flame2.png` |
| Shelf | 0 → None | 0.5 | 1 | isInvincible=0 | constraints=4, interp=1, colDet=1 | BoxCollider2D size=(23,10) offset=(-0.168,2) | (-240.1,-9.1,28.02) | `Sprites\Other\Shelf.png` |
| ShelfWithFork | 19 → SplashFlinging | 0.5 | 1 | isInvincible=0 | constraints=4, interp=1, colDet=1 | BoxCollider2D size=(23,10) offset=(-0.168,2) | (-22,8.885,0) | `Sprites\Other\Shelf.png`; child "Flingee" = `Sprites\Other\Fork.png` |
| ShelfWithSpoon | 19 → SplashFlinging | 0.5 | 1 | isInvincible=0 | constraints=4, interp=1, colDet=1 | BoxCollider2D size=(23,10) offset=(-0.168,2) | (-62.6,8.9,28.0) | `Sprites\Other\Shelf.png`; child "Flingee" = `Sprites\Other\Spoon.png` |
| SlowFallRock | 3 → Fall | 0.5 | 1 | isDestroyableByBottomNet=1 | constraints=**0** (not frozen — can tumble while falling), interp=1, colDet=1 | CircleCollider2D r=11 offset=(0.9,0) | (0,0,0) | `Sprites\Rocks\WhiteRock.png` |
| StillRock | 0 → None | 0.5 | 1 | isDestroyableByBottomNet=1 | constraints=0, interp=1, colDet=1 | CircleCollider2D r=11 offset=(0.9,0) | (0,0,0) | `Sprites\Rocks\WrappedRock.png` |
| UpLeftRock | 8 → ChangeDirectionUpLeft | 0.1 | 1 | isDestroyableByBottomNet=1 **and** isInvincible=0 (both present) | constraints=4, interp=1, colDet=1 | CircleCollider2D r=11 offset=(0.9,0) | (0,0,0) | `Sprites\Rocks\UpLeftArrow.png` |
| UpRightRock | 7 → ChangeDirectionUpRight | 0.1 | 1 | isDestroyableByBottomNet=1 **and** isInvincible=0 | constraints=4, interp=1, colDet=1 | CircleCollider2D r=11 offset=(0.9,0) | (0,0,0) | `Sprites\Rocks\UpRightArrow.png` |
| UpRock | 4 → ChangeDirectionUp | 0.1 | 1 | isDestroyableByBottomNet=1 **and** isInvincible=0 | constraints=4, interp=1, colDet=1 | CircleCollider2D r=11 offset=(0.9,0) | (0,0,0) | `Sprites\Rocks\UpArrow.png` |

All 20 prefabs also carry `hasMaxY=0`, `maxY=0` (unused clamp), `speedModifierMin=1.0`, `speedModifierMax=1.0` except where noted, and `wasGrabbedControllerID=[]`/`canPull=1` at rest. `grabClip` is unset (null PPtr) on every Step prefab; `AudioSource.m_audioClip` is also null on every one (clip is chosen at play-time via `AudioManager`, not per-prefab).

**Balloon and Rocket also serialize `autoMovementMin`/`autoMovementMax`** (both `(0,0)` in both prefabs) — these fields belong to `Scenery.cs` in the current codebase, not `Step.cs`. This means the old Unity `Step` script (or a shared ancestor) used to carry auto-movement fields that have since been removed/moved to `Scenery`.

### Children of note

- **CrumblyRock / Beetle / Castle / FallingRock / FlingingRock / FlyRock / LeftRock / Potato / RightRock / SlowFallRock / StillRock / UpLeftRock / UpRightRock / UpRock**: each has a child GameObject `Shadow` (`localPos=(2,-1,0)`, `localScale=(1,1,1)`) with a `KeepPositionFromParent.cs` (no serialized fields) and a `SpriteRenderer` — sprite is `Sprites\Rocks\RockShadow.png` on most, but **null** on Carrot, Castle, Potato, Shelf, ShelfWithFork, ShelfWithSpoon (shadow sprite not assigned on these).
- **Carrot**: children `Shadow` (sprite none), `Meat` (`Sprites\Rocks\Carrot.png`), `Stalks` (`Sprites\Rocks\CarrotStalk.png`, plus `RotateTowards.cs`: `rotateSpeed=0.001`, `direction=(0,0,-110)`, `checkParent=0`).
- **FlingingRock → "Flingee"**: `Rigidbody2D` mass=1, drag=0, angularDrag=0.05, gravityScale=1, **isKinematic=true**, constraints=0; `Splash.cs`: `minXForce=-15`, `maxXForce=15`, `yForce=60`, `rotMod=2`. Matches the `ActionType.SplashFlinging` grab logic (`splash.rb2D.isKinematic=false` on grab).
- **ShelfWithFork → "Flingee"="Fork"**: localPos (-0.74, 8.38, 0), `BoxCollider2D` size=(25,5); `Splash.cs`: minXForce=-1, maxXForce=1, yForce=0, rotMod=100; `Rigidbody2D` mass=0.1, isKinematic=true.
- **ShelfWithSpoon → "Flingee"="Spoon"**: localPos (-0.3, 7.89, 0), `BoxCollider2D` size=(25,4); same `Splash.cs` values as Fork (minXForce=-1, maxXForce=1, yForce=0, rotMod=100); `Rigidbody2D` mass=0.1, isKinematic=true.
- **FlyRock → "Bug"**: localPos (0, 13.3, 0), tag `Bug`, `CircleCollider2D` r=8 offset=(-0.5,-2) isTrigger=true, `Rigidbody2D` mass=1 drag=0 angularDrag=0.05 gravityScale=0 isKinematic=true constraints=4, `Animator`→`Animation\Bug.controller`, **`Bug.cs`** (not Step.cs) with its own `ActionType` enum (`None=0, StartGame=1`) — here `actionType=0`→None. Child `Wings` = `Sprites\Other\Wing1.png`.

**Notable/surprising findings for Steps:** `CrumblyRock.prefab` has `actionType=0` (None), not `Crumble` (1) — the "crumbling" behavior implied by its name and filename is not wired up in the shipped data. `Castle.prefab` similarly has `actionType=0`, leaving the dedicated `ActionType.Castle` (16) enum value completely unused anywhere in the dump. `ActionType.Crumble` (1) itself — despite having real grab/explode logic in `Step.AssignInteractionAction()` — is not used by any Step prefab in this project at all.

---

## 2. Bugs (`Prefabs\Spawns\Bugs\*`)

Bug's own `ActionType` enum (from `Entities/Bug.cs`) is **`None=0, StartGame=1`** — distinct from `Step.ActionType`; do not confuse the two.

| Prefab | Root localPos | actionType (Bug enum) | spawnProbability | Collider | Rigidbody2D | Sprite | Children |
|---|---|---|---|---|---|---|---|
| Bug | (52.347, 114.350, 0) | 0 → None | 0.0 | CircleCollider2D r=8 offset=(-0.5,-2) isTrigger=true | mass=1, drag=0, angularDrag=0.05, gravityScale=0, isKinematic=true, constraints=4 | `Sprites\Other\Bug.png` | `Wings` (`Sprites\Other\Wing1.png`) |
| StartBug | (52.347, 114.350, 0) | 1 → StartGame | 0.0 | CircleCollider2D r=11 offset=(0,-7) isTrigger=true | mass=1, drag=0, angularDrag=0.05, gravityScale=0, isKinematic=true, constraints=4 | `Sprites\Other\Bug.png` | `Wings` (`Sprites\Other\Wing1.png`); `StartButton` → `Text` (RectTransform + TextMeshProUGUI, text="Play!", font `Fonts\Bangers SDF.asset`, fontSize=10, Animator `Animation\StartButton.controller`) |

`StartBug` also has `isDestroyableByBottomNet=1`, `useAlternate=0`, `isInvincible=1` (fields not present on plain `Bug.prefab`). Both share `Animator`→`Animation\Bug.controller` on the root.

---

## 3. Scenery (`Prefabs\Spawns\Scenery\*`)

| Prefab | Script | spawnProbability | isDestroyableByBottomNet / isInvincible | hasMaxY / maxY | speedModifierMin/Max | autoMovementMin/Max | hasMaterial | Rigidbody2D | Collider | Sprite | Root localPos/Scale |
|---|---|---|---|---|---|---|---|---|---|---|---|
| BackGrass | Scenery.cs | 0.0 | isDestroyableByBottomNet=0 | 0 / -47.0 | 1.0/1.0 | (0,0)/(0,0) | 1 | mass=1,drag=1,angDrag=0.05,grav=0,kinematic=true,constraints=0 | — | `Sprites\Other\Grass.png` | (0,0,0), scale (1,2,1) |
| BackGrassP2 | Scenery.cs | 0.0 | isDestroyableByBottomNet=0, useAlternate=1 | 0 / -47.0 | 1.0/1.0 | (0,0)/(0,0) | 1 | same as BackGrass | — | `Sprites\Other\Grass.png` | (0,0,0), scale (1,2,1) |
| Bubble | **MovingScenery.cs** | 1.0 | isDestroyableByBottomNet=1, isInvincible=0 | n/a (MovingScenery has no hasMaxY) | minSpeedMod=1.5, maxSpeedMod=4.0 | n/a | n/a | mass=1,drag=0,angDrag=0.05,grav=0,kinematic=false,constraints=0 | CircleCollider2D r=11 isTrigger=true | `Sprites\Other\Bubble.png` | (205,-191,0) |
| Chef | **MovingScenery.cs** + `LevelObject.cs` | 1.0 | isInvincible=0 | — | minSpeedMod=1.5, maxSpeedMod=4.0 | — | — | mass=1,drag=0,angDrag=0.05,grav=0,kinematic=false,constraints=0 | none | `Sprites\Other\Chef.png` | (0,-168,0) |
| Cloud1Left | Scenery.cs | 0.5 | isDestroyableByBottomNet=1 | 0/0 | 0.1/0.3 | (-8,0)/(-20,0) | 1 | mass=2,drag=1,angDrag=0,grav=0,kinematic=false,constraints=4 | BoxCollider2D size=(10,5) | `Sprites\Other\Cloud.png` | (0,0,0) |
| Cloud2Left | Scenery.cs | 0.5 | (fields not present on this save) | — | 0.1/0.3 | (-8,0)/(-20,0) | 1 | mass=2,drag=1,angDrag=0,grav=0,kinematic=false,constraints=4 | BoxCollider2D size=(10,5) | `Sprites\Other\Cloud2.png` | (0,0,0) |
| Cloud3 | Scenery.cs | 1.0 | isDestroyableByBottomNet=1 | 0/0 | 0.3/0.5 | (-5,0)/(-5,0) | 0 | mass=2,drag=1,angDrag=0,grav=0,kinematic=false,constraints=4 | none | `Sprites\Other\Cloud3.png` | (-58.1,34.3,1) |
| Flame | Scenery.cs | 0.0 | isDestroyableByBottomNet=1 | 0/0 | 1.0/1.0 | (0,0)/(0,0) | 0 | mass=1,drag=0,angDrag=0.05,grav=0,kinematic=false,constraints=0 | BoxCollider2D size=(10,25) offset=(0,16) isTrigger=true | `Sprites\Scenery\Flame.png` | (-19,-42.2,0); child "Point light" (Light) |
| Grass | Scenery.cs | 0.0 | isDestroyableByBottomNet=0 | 0/-60 | 1.0/1.0 | (0,0)/(0,0) | 1 | mass=1,drag=1,angDrag=0.05,grav=0,kinematic=true,constraints=0 | — | `Sprites\Other\Grass.png` | (0,0,0) |
| GrassP2 | Scenery.cs | 0.0 | isDestroyableByBottomNet=0, useAlternate=1 | 0/-60 | 1.0/1.0 | (0,0)/(0,0) | 1 | same as Grass | — | `Sprites\Other\Grass.png` | (0,0,0) |
| LavaSplash | **Splash.cs** | 1.0 | isInvincible=0 | — | — | — | — | mass=1,drag=0,angDrag=0.2,grav=1,kinematic=false,constraints=0 | — | `Sprites\Other\LavaSplash.png` | (0,0,0) |
| Window | Scenery.cs | 0.5 | isInvincible=0 | 0/0 | 0.5/0.5 | (0,0)/(0,0) | 0 | mass=1,drag=2,angDrag=0.8,grav=0,kinematic=false,constraints=4 | — | `Sprites\Other\Window.png` | (59.1,-5.6,0) |

`LavaSplash.prefab` (`Splash.cs`): `minXForce=-15`, `maxXForce=15`, `yForce=20`, `rotMod=2` — same shape as the `Splash.cs` defaults but with a lower `yForce` (20 vs. the class default of 60) and drag differs from FlingingRock's Flingee (angularDrag=0.2 vs 0.05, gravityScale=1 vs 1 — matches).

**All grass/cloud/window Scenery prefabs use plain `Scenery.cs`, not the `Grass.cs` subclass** (which adds `minWaveTime`/`maxWaveTime` and triggers `Animator.SetTrigger("Wave")`). No dumped prefab references `Grass.cs` at all — the wave-shaped animation in-game must be driven entirely by the `Grass.controller` Animator Controller's own timeline/clip, not by the C# `Grass` script. This is worth confirming against the Animator Controller if the Roblox port is expected to replicate the wave cadence from `Grass.cs`.

### Tree prefabs (`StepAndScenery.cs` root + Step-tagged child)

`FirstTree`, `FirstTreePlayer2`, `LastTree`, `LastTreePlayer2`, `SecondTree`, `SecondTreePlayer2` all share this shape:

- Root: `StepAndScenery.cs` (`spawnProbability=1.0`, `isInvincible` varies 0/1, `useAlternate` 0 on "player1" variants / 1 on "Player2" variants), `Animator`→`Animation\Tree.controller`, `AudioSource` clip=`Audio\Leaves.wav` volume=1.0 playOnAwake=true (FirstTree variants only — LastTree/SecondTree have no AudioSource in the dump).
- Child **"Acorn"** / **"2xAcorn"** (tag `Step`): `Step.cs` with **`actionType=22 → Helper`** in every tree variant; `BoxCollider2D` size=(25.6,25.6); `Rigidbody2D` mass=2, drag=1, angularDrag=0.05, constraints=4 (FirstTree) or constraints=4 + collisionDetection=1 (LastTree/SecondTree); sprite `Sprites\Rocks\Acorn.png`; `hasMaxY` varies (0 on FirstTree at maxY=35, 1 on LastTree at maxY=140, 0 on SecondTree at maxY=90).
- Child **"Branch"**: `Scenery.cs`, sprite `Sprites\Other\branch3.png`, `hasMaxY=1` with `maxY` = -8 (FirstTree), 102 (LastTree), 48 (SecondTree); `Rigidbody2D` mass=2; child **"Leaves"**: sprite `Sprites\Other\branch2.png`, no script.
- `SecondTree`/`SecondTreePlayer2` mirror the whole hierarchy horizontally: root and Acorn `localScale.x = -1`.

All six tree prefabs use `actionType=22 → Helper` for their Acorn Step component — this is the only place `ActionType.Helper` is used in the dump.

---

## 4. Pebbles & Speck

| Prefab | Script | Fields | Rigidbody2D | Collider | Sprite | Root localPos/Scale |
|---|---|---|---|---|---|---|
| `Pebbles\SmallRock.prefab` | `Pebble.cs` | `minSpeed=50.0`, `maxSpeed=50.0`, `spawnProbability=0.0` | mass=0.1, drag=0, angularDrag=0.05, gravityScale=0, isKinematic=false, constraints=0 | CircleCollider2D r=2.5 offset=(0.3,0) | `Sprites\Rocks\SmallRock.png` | (-15.755, 33.498, 0), scale (0.5,0.5,1) |
| `Speck.prefab` | `Speck.cs` (source not in this task's read list — field meaning inferred from name only) | `targetRadius=1.0`, `speed=0.4`, `rotateAngle=1.0`, `rotateAxis=(0,0,1)` | none (no Rigidbody2D component on this prefab) | none | `Sprites\Other\Speck.png` tinted (0.655, 1.0, 0.0, 1.0) | (81.7, 179.8, 0) |

`Pebble.Explode()` (C#) applies `xForce=Random(-5,5)`, `yForce=Random(1,5)` as an impulse and destroys after 3s — these runtime-random values aren't in the prefab; `minSpeed`/`maxSpeed` above only govern the constant downward `FixedUpdate` force (`speedVector = (0, -Random(minSpeed,maxSpeed))`), which for SmallRock is a fixed 50 (min==max, no randomness in practice).

---

## 5. AudioManager (`Prefabs\Managers\AudioManager.prefab.json`)

The `[HideInInspector]` named fields (`slurpSound`, `grabSound`, etc.) all serialize as **null PPtr `(0,0)`** — they are *not* assigned directly in the prefab. They're populated at runtime by `AudioManager.SetUpSounds()`, which linear-searches the `soundClips[]` array by `AudioClip.name` (`ReturnClip(name)`). The table below reproduces that name-matching resolution against the `soundClips` array actually serialized in the prefab (23 entries) and the `musicClips` array (4 entries), all resolved to their asset paths via `externals`.

| Named field (`AudioManager.cs`) | Looked up by name | Resolved asset |
|---|---|---|
| blinkSound | "Blink" | `Audio\Blink.wav` |
| slurpSound | "Slurp" | `Audio\Slurp.wav` |
| selectSound | "Select" | `Audio\Select.wav` |
| squishSound | "Squish" | `Audio\Squish.wav` |
| grabSound | "Grab" | `Audio\Grab.wav` |
| hurtSound | "Hurt" | `Audio\Hurt.wav` |
| missSound | "Miss" | `Audio\Miss.wav` |
| awakeSound | "Awake" | `Audio\Awake.wav` |
| fallSound | "Fall" | `Audio\Fall.wav` |
| flySound | "Flys" | `Audio\Flys.wav` |
| newSound | "New" | `Audio\New.wav` |
| highScoreSound | "HighScore" | `Audio\HighScore.wav` |
| base10Sound | "Base10" | `Audio\Base10.wav` |
| crumbleSound | "Crumble" | `Audio\Crumble.wav` |
| crumbleShortSound | "CrumbleShort" | `Audio\CrumbleShort.wav` |
| boilVoiceSound | "BoilAFrogVO" | `Audio\BoilAFrogVO.wav` |
| perfectVoiceSound | "PerfectVO" | `Audio\PerfectVO.wav` |
| okVoiceSound | "OKVO" | `Audio\OKVO.wav` |
| greatVoiceSound | "GreatVO" | `Audio\GreatVO.wav` |
| splashSound | "Splash" | `Audio\Splash.wav` |
| holdOnVoiceSound | "HoldOnVO" | `Audio\HoldOnVO.wav` |
| **leafSound** | "LeafSound" | **unresolved** — no clip named "LeafSound" exists in the serialized `soundClips` array; `ReturnClip` would return `null` at runtime for this field. |

`soundClips[]` also contains **`Audio\HotFrogVO.wav`** and **`Audio\Pop.wav`**, neither of which is looked up by name in `SetUpSounds()` (no matching `[HideInInspector]` field calls `ReturnClip("HotFrogVO")` or `ReturnClip("Pop")`). `Pop.wav` is instead wired directly as `Bubble.prefab`'s `Spawn.grabClip`; `HotFrogVO.wav` is wired directly as `HotFrog.prefab`'s `Frog.audioIntroduction`. Both are present in the array but effectively unused by the by-name lookup path.

`musicClips[]` (indexed 0–3, selected via `AudioPlayer.PlayMusicClip(clipIndex)` / `AudioManager.StartMusic(newIndex)`):

| Index | Asset |
|---|---|
| 0 | `Audio\Music\BrusselSprouts.wav` |
| 1 | `Audio\Music\FrogSounds.wav` |
| 2 | `Audio\Music\Opening.mp3` |
| 3 | `Audio\Music\Adenine.mp3` |

### AudioPlayer / channel setup

The `AudioManager` root has two children, `Channel1` and `Channel2`, each carrying one `AudioSource` (`volume=1.0`, `loop=false`, `playOnAwake=false`, `clip=null` at rest — set at runtime by `AudioPlayer.SetChannelToPlay`). `AudioPlayer.cs` itself has **no serialized public/`[SerializeField]` fields** (`channelCount`, `musicOnAwakeLoop=true`, `musicOnAwakeVolume=0.7`, `fadeAmount=0.01` are all private, unattributed — so nothing beyond `m_Enabled` appears in the MonoBehaviour JSON). Those numeric defaults (channelCount=2, musicOnAwakeVolume=0.7, fadeAmount=0.01/frame) come only from the C# source, not the prefab.

### Audio files on disk not referenced by AudioManager's arrays

From `Assets\Audio\` (excluding `.meta` files), files **not** present in either `soundClips[]` or `musicClips[]`:

`Awake-old1.wav`, `BusinessVO.wav`, `EvenHotterVO.wav`, `ExpensiveVO.wav`, `ExploreVO.wav`, `FryingPanVO.wav`, `GoodVO.wav`, `HomageVO.wav`, `Leaves.wav`\*, `MegaManDeath.wav`, `MegaManDeath2.wav`, `NoSelect.wav`, `NothingVO.wav`, `SeeHimVO.wav`, `VeryHotVO.wav`, `Music\Two Wrongs.wav`.

\* `Leaves.wav` is referenced directly (not via AudioManager) as the `AudioSource.m_audioClip` on `FirstTree.prefab`/`FirstTreePlayer2.prefab`.

---

## 6. UI: TouchIndicator, TouchQualityText*, Guidance*

| Prefab | Key fields |
|---|---|
| `TouchIndicator.prefab` | `TouchIndicator.cs`: `touchIndex=-1`. `SpriteRenderer`: `Sprites\Other\Circle.png`, color alpha=**0** (invisible at rest). No Transform offset. |
| `TouchQualityTextGreat.prefab` | Text "GREAT!"; `m_fontColor=(0.382, 0.744, 1.0, 1.0)` (blue); `m_fontSize=5`; `QualityText.cs`: `index=1, lifetime=0.5, canMove=0`; `Animator`→`Animation\TextMeshPro.controller`; root at origin. |
| `TouchQualityTextOK.prefab` | Text "OK"; `m_fontColor=(1,1,1,1)` (white); `m_fontSize=5`; `QualityText.cs`: `index=1, lifetime=0.5, canMove=0` (same `index` as Great — worth double-checking against the live game, since `QualityText.index` looks like it should distinguish quality tiers); `Animator`→`Animation\TextMeshPro.controller`. |
| `TouchQualityTextPerfect.prefab` | Text "PERFECT!"; `m_fontColor=(0.0, 1.0, 0.423, 1.0)` (green); `m_fontSize=5`; `QualityText.cs`: `index=2, lifetime=0.5, canMove=0`; `Animator`→`Animation\TextMeshPro.controller`. |
| `TouchQualityTextMiss.prefab` | Text "X"; `m_fontColor=(1.0, 0.0, 0.0, 0.392)` (translucent red); `m_fontSize=5`; localPos=(-16.7, 32.5, 0) (only one offset from origin); `QualityText.cs`: `index=3, lifetime=1.0, canMove=1`; own dedicated `Animator`→`Animation\TouchQualityTextMiss.controller` (the other three share `TextMeshPro.controller`). |
| `Guidance.prefab` | Root localPos=(38.9,0,0); `Animator`→`Animation\Image.controller`; `KeepInDirection.cs`: `direction=(0,1)`. Children: `Image` (`Sprites\Other\Circle.png`, localScale=(1.094,1.094,1), alpha=1), `PressIcon` at (5,-13,0) containing `Impact` (`Sprites\Other\PressImpactIcon.png`, alpha=0, hidden) and `Finger` (`Sprites\Other\PressIcon.png`, alpha=1). |
| `GuidanceInverse.prefab` | Identical to `Guidance.prefab` except `PressIcon` localPos=(-5,-13,0) with `localScale=(-1,1,1)` (horizontally mirrored) — used for the mirrored-direction guidance variant. |

---

## 7. Frog & Controller tuning (`HotFrog.prefab.json`, `LocalPlayer1.prefab.json`)

> `Frog.cs`, `Limb.cs`, `Player.cs`, `JoystickInput.cs`, `Tongue.cs` were **not** in this task's provided read list, so field *values* below are taken directly from the JSON but field *meaning* is inferred from the name only (not verified against source).

### Frog.cs (root `HotFrog` GameObject, tag `Player`)

- `audioIntroduction` → `Audio\HotFrogVO.wav`
- `id = 1`, `frogName = "Hot Frog"`, `useHotFrogNormalMap = 0`, `isUnlocked = 1`, `canBuy = 0`
- `Animator` → `Animation\BusinessFrog.controller` (HotFrog reuses the "BusinessFrog" animator controller — shared across frog skins)
- `spriteLoads[]`: 29 entries, each `{spriteName, referencePath ("Hot Frog" or "Universal"), material PPtr, renderer PPtr, isHold}`. Parts: Head, Tongue, LeftEyelid, RightEyelid, LeftSclera, RightSclera, LeftEye, RightEye, LeftPupil, RightPupil, Mouth, Body, Accessory, RightLimb, RightHandGrab, RightHand, LeftLimb, LeftHandGrab, LeftHand, LowRightEyelid, LowLeftEyelid, LowerRightEyelid, LowerLeftEyelid, ClosedRightEyelid, ClosedLeftEyelid, RightHandGrabBack, LeftHandGrabBack, Thumbnail. The last 8 (`isHold=1`) have no live `renderer` PPtr (`(0,0)`) — they're held-state sprite/material swaps, not currently-rendered parts, and their `Sprite`/`Material` PPtrs are listed as separate top-level fields (e.g. `LowRightEyelidSprite`, `LowRightEyelidMaterial`, all resolving into `Sprites\Frogs\Hot Frog\...`).

### Limb.cs (identical values on both `RightLimb` and `LeftLimb`)

| Field | Value |
|---|---|
| yVelocityStart | 1.0 |
| yAscendAcceleration | 5.0 |
| yDescendAcceleration | -3.0 |
| ascendLimit | 20.0 |
| ascendTerminalVelocity | 40.0 |
| descendLimit | -30.0 |
| descendTerminalVelocity | -40.0 |

### HotFrog part hierarchy (local positions / scales)

```
HotFrog (root, scale 1,1,1)
├─ Head (0,0,0)
│  ├─ Tongue        (0, -13.85, 0)   scale (1, 0, 1)   ← Tongue.cs, zero Y-scale at rest
│  ├─ LeftEyelid     (-0.3, 0.2, 0)  sprite=none (hidden by default)
│  ├─ RightEyelid    (0.1, 0.2, 0)   sprite=none
│  ├─ LeftSclera     (0,0,0)
│  ├─ RightSclera    (0,0,0)
│  ├─ LeftEye        (0,0,0)
│  ├─ RightEye       (0,0,0)
│  ├─ LeftPupil      (0,0,0)
│  ├─ RightPupil     (0,0,0)
│  ├─ Mouth          (0,0,0)
│  ├─ Body           (0,0,0)          alpha=0.983
│  ├─ Accessory      (0,0,0)          sprite=none
│  ├─ RightPupilPosition (16, 19, 0)  marker transform, no renderer
│  └─ LeftPupilPosition  (-16, 19, 0) marker transform, no renderer
├─ RightLimb (20, -44.1, -5)          Limb.cs (see table); + TrailRenderer
│  ├─ RightHandGrab (0.1, 0, 0)       alpha=0.983
│  └─ RightHand     (0,0,0)           alpha=0.983
└─ LeftLimb (-20, -43.6, -5)          Limb.cs (identical values)
   ├─ LeftHandGrab   (1.3, 0, 0)      alpha=0.983
   └─ LeftHand       (0,0,0)          alpha=0.983
```

### Controller / Player (`LocalPlayer1.prefab.json`)

| Script | Fields |
|---|---|
| `VariableManager.cs` | `currentFrogID = 0` |
| `Player.cs` | `spawnManager = null` (scene reference, not resolvable from prefab), `touchCheckRadius = 7.0`, `canFall = 0` |
| `ObjectPool.cs` ("QualityText" pool) | `poolName = "QualityText"`, `initialPoolSize = 12`, `poolSize = 0`, `canGrow = 0`, `pooledObjectPrefabs` = [`TouchQualityTextOK.prefab`, `TouchQualityTextGreat.prefab`, `TouchQualityTextPerfect.prefab`, `TouchQualityTextMiss.prefab`] |
| `JoystickInput.cs` | `minX = -30.0`, `maxX = 90.0`, `minY = -55.0`, `maxY = 35.0`, `speed = (30.0, 30.0)`, `hasCursors = 0`, `cursorPrefab` → `Prefabs\UI\Cursor.prefab` |
| `TouchInput.cs` / `MouseInput.cs` | no serialized fields |

HUD hierarchy under `LocalPlayer1 → HUD`: `Canvas` + `CanvasScaler` (`m_UiScaleMode=1` [ScaleWithScreenSize], `m_ReferenceResolution=(768,1024)`) + `GraphicRaycaster` + `HUD.cs` (`canChangeFlyCount=1`), containing:
- **FlyPanel**: `Button` (`OnClick`→`SpendFlys`), transparent hit `Image` (alpha=0), `CanvasGroup`, `Animator`→`Animation\FlyPanel.controller`; children `FlyCount` (TextMeshProUGUI "Win a frog!", fontSize=100, `Animator`→`Animation\FlashingText.controller`), `FlyIcon` (`Image` sprite=`Sprites\Menu\BugIcon.png`), `ToGoText` (TextMeshProUGUI "\n", fontSize=60, bold fontStyle=16).
- **StepPanel**: `CanvasGroup`; children `StepCount` (TextMeshProUGUI, auto-size min18/max72 base200, `Animator`→`Animation\StepCount.controller`), `HighScore` (inactive by default, text "TOP: 1", fontSize=70).
- **ReadyPanel**: `CanvasGroup`; child `Snooze` (TextMeshProUGUI, auto-size base24, `m_pageToDisplay=1`, no Animator).

---

## Summary of unresolved / notable items

- `leafSound` in `AudioManager` has no matching clip name in `soundClips[]` — resolves to `null` at runtime.
- `HotFrogVO.wav` and `Pop.wav` sit in `soundClips[]` but aren't reached by any `[HideInInspector]` name lookup (used directly elsewhere instead).
- `Speck.cs` source wasn't in the provided read list; its fields (`targetRadius`, `speed`, `rotateAngle`, `rotateAxis`) are reported as-is with names only.
- `Player.spawnManager` on `LocalPlayer1` is a null/unresolved scene reference (expected — it's set at runtime or wired in the scene, not the prefab).
- Several prefabs (`Cloud2Left`, several Steps) omit `isDestroyableByBottomNet`/`isInvincible` entirely rather than serializing `0`, consistent with per-object stale-field behavior rather than a meaningful "false" value.
