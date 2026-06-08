# 02 — Architecture: Unity → Roblox

This page covers the two decisions that shape everything else — how to represent a
2D game in Roblox's 3D world, and how to split logic across client and server —
followed by a concept-to-concept mapping table.

## Decision 1: 2D-in-3D

Hotfrog is a 2D game (orthographic camera, `Rigidbody2D`, `SpriteRenderer`).
Roblox is fundamentally 3D. Two viable approaches:

### Option A — Plane-in-3D with real parts (recommended)

Build the game on a fixed **XY plane** in 3D space (pick a constant Z, e.g.
`Z = 0`) using real `BasePart`s, and lock everything to that plane.

- **Camera:** a scripted `Camera` (`CameraType.Scriptable`) looking down the +Z
  axis at the plane. Roblox has no true orthographic camera, but a far camera with
  a narrow field of view approximates one well enough; alternatively accept a
  slight perspective — it reads fine for this art style.
- **Keep parts on the plane:** anchor steps and drive them kinematically
  (set `CFrame`/`Position` each frame), or, if you want real physics, constrain
  motion to the plane with a `PrismaticConstraint`/`AlignPosition` pinning Z, or a
  `PlaneConstraint`-style setup. For the MVP, **kinematic movement is simpler and
  matches the original**, which already drives most motion explicitly (the
  `SpawnManager` pull, the frog's custom gravity) rather than leaving it to the
  physics solver.
- **Art:** textured `Part`s, `Decal`s, or `ImageLabel`s on `SurfaceGui` for the
  sprite look.

**Why recommended:** the original already moves objects under script control
(custom gravity, scripted pull). Real parts + kinematic motion preserve that
control while letting you use raycasts/touch and Roblox tooling naturally.

### Option B — Pure GUI (2D)

Render the whole game in a `ScreenGui` with `ImageLabel`s and do all physics in
script with raw vectors.

- **Pro:** truly 2D, pixel-exact, no camera fiddling.
- **Con:** you re-implement *all* collision/raycasting math yourself, you lose
  Roblox physics/constraints entirely, and it's harder to later add 3D flourish.

**Use Option A unless** you specifically want a flat, GUI-only build. The rest of
these docs assume **Option A**.

## Decision 2: Client / server split

Unity (single-player, local) has no client/server boundary. Roblox always does.
Even for a basically single-player game, decide what is authoritative.

For the basic version, a pragmatic split:

| Concern | Where | Notes |
|---|---|---|
| Input capture (taps/clicks) | **Client** | `UserInputService`; resolve the world point and which step was hit. |
| Limb visuals & frog animation | **Client** | Cosmetic; smooth locally for responsiveness. |
| Camera | **Client** | Each player frames their own view. |
| Step spawning | **Server** (authoritative) | The server owns the field of steps and the pull, then replicates. |
| The pull / world-scroll | **Server** drives, replicates to clients | Or run client-predicted + server-validated; see below. |
| Score & game-over | **Server** | Score is the thing players would cheat; keep it authoritative. |
| High-score persistence | **Server** | `DataStoreService` is server-only. |

**MVP shortcut:** It is fine to **prototype almost everything on the client** (one
`LocalScript` driving frog, steps, pull, score) to get the feel right fast, then
move spawning/score/persistence to the server once the loop is fun. The roadmap
([04-build-roadmap.md](04-build-roadmap.md)) calls out where to draw the line.

**Authority / exploits (basic awareness):** because score gates a leaderboard,
never let the client send "my score is N." Instead the client sends *grab events*
("grabbed step X at world point P"), and the server validates and increments the
count. Don't `RemoteEvent`-trust a client-reported score.

## Concept mapping (Unity / Hotfrog → Roblox)

| Unity / Hotfrog | Roblox equivalent |
|---|---|
| MonoBehaviour singletons (`LevelManager`, `SpawnManager`, `ControllerManager`) | Server `Script`s + `ModuleScript`s (ModuleScript-as-singleton pattern) |
| `MonoBehaviour.Update()` | `RunService.Heartbeat` (after physics) / `RunService.RenderStepped` (client visuals only) |
| `MonoBehaviour.FixedUpdate()` | `RunService.PreSimulation` (`Stepped`) — fixed-ish physics step |
| `Rigidbody2D` + `AddForce` | `BasePart` + `VectorForce`/`LinearVelocity`/`AlignPosition` — or kinematic `CFrame` updates (recommended for MVP) |
| Unity 2D gravity | scripted fall loop on Heartbeat (do **not** rely on `Workspace.Gravity`) |
| `SpriteRenderer` + orthographic camera | textured `Part`/`Decal`/`ImageLabel`; `Camera` set to `Scriptable` |
| `Physics2D.Raycast` on "Touchable" layer | `workspace:Raycast()` with a `RaycastParams` filter, or `Mouse.Target`; gate by CollisionGroup |
| Unity layers (`Touchable`, `BottomNet`, `Frogs`, `Rocks`) | **CollisionGroups** (physics) + **`CollectionService` tags** / **attributes** (logical typing) |
| Unity tags (`"Step"`, `"Bug"`, `"BottomNet"`) | `CollectionService` tags or an `Attribute` like `Kind = "Step"` |
| `ObjectPool` / `PooledObject` | a pool `ModuleScript` recycling parts (same idea) — see `Spawning/ObjectPool.cs` |
| DOTween (`DOMove`, `DOPunchRotation`, ...) | `TweenService:Create(...)` with `TweenInfo` + easing |
| `AudioManager` / `AudioClip` | `Sound` instances under `SoundService` / parts; a small audio `ModuleScript` |
| `PlayerPrefs` (high score, settings) | `DataStoreService` (server-only) for persistence; attributes for session state |
| Input abstraction (`IUserInput`, `TouchInput`, `MouseInput`) | `UserInputService` (`TouchTap`, `InputBegan`) + `ContextActionService`; one code path handles touch & mouse |
| `HUD.cs` (`TextMeshPro` counters) | `ScreenGui` + `TextLabel`s in `StarterGui` |
| Scene `0 → 1` load (`Core/LoadGame.cs`, `Preload`) | place loads directly; use a loading `ScreenGui` + preload via `ContentProvider:PreloadAsync` if needed |
| Coroutines (`IEnumerator` + `yield`) | `task.spawn` / `task.wait` / `task.defer`, or event-driven Heartbeat loops |

## Suggested top-level structure

A minimal, idiomatic Roblox layout (detailed hierarchy in
[03-core-mechanics.md](03-core-mechanics.md#projectinstance-layout)):

```
ReplicatedStorage/
  Shared/            (ModuleScripts: Config, types, pull math)
  Assets/            (StepTemplate, FrogModel templates)
  Remotes/           (RemoteEvents: GrabStep, ReleaseStep, ScoreChanged, GameOver)
ServerScriptService/
  GameServer         (spawning, pull authority, score, persistence)
StarterPlayer/
  StarterPlayerScripts/
    GameClient       (input, limbs, frog visuals, camera, HUD wiring)
StarterGui/
  HUD                (ScreenGui: score, high score)
Workspace/
  PlayField          (plane, lava part, step container)
```
