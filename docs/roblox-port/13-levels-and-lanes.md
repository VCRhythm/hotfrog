# 13 — Levels & Lanes (one PlayField per player)

> Implements [07-multiplayer.md](07-multiplayer.md#option-a--per-player-fields-recommended)'s
> "Option A" for real: each player gets their own PlayField "lane" — their own
> spawn direction, spawner pools, level/run progress, and step set — laid out
> side by side in `Workspace` so everyone stays visible to everyone. Ports
> `Core/LevelManager.cs`, `Core/Level.cs`, `Spawning/SpawnManager.cs`,
> `Spawning/Spawner.cs` + subclasses, and `Entities/Step.cs`'s direction/pull
> logic, using the extracted data in
> [11-unity-level-data.md](11-unity-level-data.md) and
> [12-unity-spawn-and-audio-data.md](12-unity-spawn-and-audio-data.md).

## Why lanes, and why now

Before this change the field was global: one `spawnBias`, one `spawnCount`, one
spawn loop, one `active` step set, one scroll-on-grab tween applied to *every*
player's steps. That can't support per-player levels, per-player direction
changes, or Kitchen/Country's sideways travel. Unity itself never solved this
for networked play either — its "multiplayer" is local split-screen
(`Core/ControllerManager.cs`), and even there it duplicated spawners per player
(`Player1TreeDownStepSpawner`/`Player2TreeDownStepSpawner`, `BackGrassSpawnerP2`,
etc.) rather than sharing one field. Per-player lanes are the natural
generalization of that same idea to a real Roblox server.

## Architecture

| Module | Responsibility |
|---|---|
| `src/shared/Levels.luau` | Level **data**: name, music, background/overlay keys, initial spawn direction, step spawners (fully wired), scenery spawners + levelObjects (data only). |
| `src/shared/StepKinds.luau` | One entry per Unity step prefab: which `StepBehaviors` entry it dispatches through, its sprite stem, its `spawnProbability`, an optional part-size override, and (for `SplashFlinging` kinds) its `Flingee` sprite. |
| `src/server/Lane.luau` | The per-player class: origin, spawn direction, spawner state/timers, level index, run progress, bounds checks, weighted kind picks, spawn positions. Pure logic — no remotes, no Instances beyond its own Folder + attributes. |
| `src/server/GameServer.server.luau` | Owns the pooled step *Instances*, `StepBehaviors` dispatch (`ctx`), the frog simulation, remotes, and scoring. Drives every `Lane` through its methods each Heartbeat and on grab/release/level events. |
| `src/server/BugService.server.luau` | Per-lane bug spawn cadence and catch permission, discovered purely through `workspace.PlayField.Lanes`' attributes — never requires `Lane.luau` or `GameServer`. |
| `src/client/GameClient.client.luau` | Centres the camera on the local player's own lane origin; otherwise unchanged. |
| `src/client/LevelClient.client.luau` | Listens to `LevelChanged`, stores it as Attributes + a BindableEvent under `LocalPlayer` for a later cosmetics phase to consume. |

Steps still come from one global `template`/pool (doc 13's spec explicitly
allows this) — only *spawning, direction, and level state* are per-lane. Each
active step carries a `LaneUserId` attribute; `GrabStep` and `CatchBug` both
reject anything whose `LaneUserId` doesn't match the caller.

`workspace.PlayField.Lanes` holds one Folder per lane, named by `UserId`, with
`UserId` (number), `Origin` (Vector3), and `Level` (string) attributes — the
contract other scripts (BugService, the client) use to discover lanes without a
module dependency.

## Unity → studs scale, and lane spacing

Doc 11 §4 gives the real Unity playfield bounds from `Borders.prefab.json`:
vertical span 175 units (top catch `y=75` to bottom catch/net `y=-100`),
horizontal span ~141 units (`x=-70.8` to `x=70.2`). This port's *pre-lanes*
`Config.SPAWN_Y`/`DESPAWN_Y` (25 / -30, a 55-stud span) were tuned
independently, in studs, before lanes existed. Dividing the two spans gives
this port's own conversion factor:

```
UNITY_TO_STUDS = 55 / 175 ≈ 0.3143
```

Sanity check against Unity's *horizontal* bound: `70.5 * 0.3143 ≈ 22.2` studs —
that's `Config.LANE_HALF_WIDTH = 22`. It round-trips against the *vertical*
bounds too (`75 * 0.3143 ≈ 23.6` vs. the existing `SPAWN_Y = 25`; `-100 * 0.3143
≈ -31.4` vs. the existing `DESPAWN_Y = -30`), which is why the existing numbers
are trusted rather than copying Unity's raw units wholesale.

A lane is `2 * LANE_HALF_WIDTH` wide (44 studs) plus a 2-stud gap so neighbours
never visually clip — `Config.LANE_SPACING = 46`. Lanes are assigned slots
`0, 1, -1, 2, -2, ...` (`Lane.luau`'s `nextSlot`), so the **first** lane in a
server always lands at `origin.X = 0` — identical to the pre-lanes single-player
layout — and later players fan out symmetrically. Slots are freed and reused on
`PlayerRemoving`. Lanes only ever offset along X; Y stays shared world space, so
`Config.SPAWN_Y`/`DESPAWN_Y`/the frog's death check didn't need new fields.

`workspace.PlayField.Lava` was widened (80 → 800 studs, still centred at
`x=0`) rather than cloned per lane — the simpler of the two options doc 13
allowed, and enough to cover ~17 lanes each direction.

## Direction / arrow semantics (and the fix)

A lane's `spawnDirection` is the direction the **world/steps scroll**, not the
direction the frog appears to travel — those are opposites, exactly like the
default `(0,-1)` "down" scroll makes the frog *feel* like it's climbing up.
Grabbing a `ChangeDirection*` step sets this.

Unity's own shipped `ChangeDirectionUpLeft`/`UpRight` already follow one
consistent rule: **arrow art shows the frog's apparent travel; SpawnDirection
is the negation.** UpLeft (frog travels up-left, apparent `(-1,1)`) sets
SpawnDirection `(1,-1)`; UpRight (travel `(1,1)`) sets `(-1,-1)`. But Unity's
plain `ChangeDirectionLeft`/`Right` **don't** follow that rule — they set
SpawnDirection directly equal to their own name's sign (`Left → (-1,0)`,
`Right → (1,0)`). Under the unified convention that would make a LeftArrow
push the frog *right* (world scrolls left, frog feels the opposite) —
contradicting its own arrow art. That's an inconsistency in the original
shipped data, not a deliberate design (`Up`/`UpLeft`/`UpRight` all agree; only
`Left`/`Right` don't).

Doc 13 explicitly invited re-deriving this now that lanes make directional pull
real, so **this port applies the unified convention everywhere**:
`ChangeDirectionLeft` now sets `(1,0)` and `ChangeDirectionRight` now sets
`(-1,0)` — swapped from Unity's literal values. `Up`/`UpLeft`/`UpRight` are
unchanged. See the comment block above `Behaviors.ChangeDirectionLeft` in
`StepBehaviors.luau` for the full derivation.

Spawn position follows from the same "opposite of travel" logic (verified
against doc 11 §2a's Level3 `LeftStepSpawner`, whose Movements sit past the
*right* edge despite its leftward direction): new steps enter from the edge
opposite `spawnDirection`, diagonals from the matching top corner
(`Lane.spawnPosition`). **Update (closing the "Per-spawner `Movements` lists"
gap, doc 17):** every level's raw prefab data was re-extracted from the
Unity prefab dump (`spawners_extracted.json`) and every step spawner's own
`Movements` list is now in `Levels.luau` as `StepSpawnerDef.movements`, in
studs, offset from the lane's origin — see the "Movements-list conversion"
comment above `Levels.luau`'s `list: { Level } = {}` for the exact formula
and its derivation (it collapses to `x_stud = Movements.x *
Config.LANE_HALF_WIDTH`, `y_stud = Movements.y * 50 * Config.UNITY_TO_STUDS`,
plus a `* 2/3` on X for scenery spawners, mirroring `StepSpawner`/
`ScenerySpawner`'s own `SetMovementToScreenSize`). `Lane.spawnPosition` now
uses that list whenever it's non-empty (currently: every step spawner) and
only falls back to the procedural edge/shape placement described above for a
spawner with an empty list (none currently, kept for robustness/future
data). The procedural formula itself is unchanged.

`Levels.luau`'s own spawner `direction` fields are the **literal** Unity
values from doc 11 §2a (kept for traceability), independent of the arrow-name
fix above — `Lane.spawnersForDirection` only ever compares them by **sign**
(doc 13 item 3: Unity's own `SpawnManager` keys spawners by exact Vector2
equality against a stale full-unit-vector array the live half-magnitude
spawners never actually match — a latent bug this port deliberately doesn't
reproduce). If a direction change has no sign-matching spawner in the current
level, `Lane.changeDirection` is a no-op — the current direction stays active.

## Level flow, the tutorial's no-death rule, and soft transitions

A run starts at **Tutorial** unless `Profiles.get(player).tutorialDone` is
already `true`, in which case it starts at **Pot**. `Lane:onStepClimbed()`
(called after every successful grab) drives progression:

- **Tutorial → Pot**: on the 3rd tree step climbed, sets `tutorialDone = true`,
  saves the profile, and calls `Lane:setLevel(Pot)`.
- **Pot → Kitchen**: at `runSteps >= Config.LEVEL_THRESHOLDS.Kitchen` (50).
- **Kitchen → Country**: at `runSteps >= Config.LEVEL_THRESHOLDS.Country` (100).

`LEVEL_THRESHOLDS` and reaching Country in single-player are the project
owner's decision (doc 13) — Unity itself never advanced past Pot.

**Tutorial fall rule** (`Core/LevelManager.cs ReportFall`, `levelIndex == 1`):
Unity doesn't kill the player on a tutorial fall — it pulls the field back up
by 3 pull-widths and lets them retry. Ported as `tutorialRetry()` in
`GameServer`: on reaching `DESPAWN_Y` while `lane.levelIndex == Levels.TUTORIAL`,
it force-releases any held steps, reuses `pullLane()` with a **negative**
distance (`-PULL_DISTANCE * Config.TUTORIAL_PULL_BACK`) to undo 3 pulls' worth
of scroll, and resets the frog to the lane origin — no `GameOver` fire, no
score reset, no respawn delay.

**Soft transitions**: `Lane:setLevel()` only swaps which spawner pools are
live going forward (fresh `spawnerStates`, new `spawnDirection`) — it never
touches `lane.active`, so steps the frog is already holding or approaching
keep scrolling exactly as they were. Old-level steps simply age out through the
normal bounds check.

**Death**: still decided purely by the frog's Heartbeat bounds check (no
`ReportDeath` remote). On death outside the tutorial, `Lane:resetRun()` puts
the lane back at Pot (or Tutorial, if `tutorialDone` is still false) and
`LevelChanged` fires with `transition = "death"`.

## Remotes

`LevelChanged` (server → that player): `levelName, musicIndex, background,
overlay, transition, laneOrigin`, fired on run start (`"start"`), every soft
transition (`"soft"`), and death (`"death"`). `LevelClient.client.luau` stores
the payload as Attributes + fires a local `BindableEvent` under
`Players.LocalPlayer.LevelState` for a later cosmetics phase — it does not
render backgrounds/overlays/music itself.

## Sprite stems referenced but not yet in SkinAssets

None — every sprite stem `StepKinds.luau` references (`Potato`, `Carrot`,
`Shelf`, `Fork`, `Spoon`, `UpArrow`/`LeftArrow`/`RightArrow`/`UpLeftArrow`/
`UpRightArrow`, `Rocket`, `Balloon`, `WrappedRock`, `CrumblyRock`,
`WhiteRock`, `Flame`, `Castle`, `Acorn`) is already present in
`SkinAssets.luau` (currently all `id = 0`, i.e. untextured until art is
uploaded — no new keys were needed).

## What doc 11/12 data could not be honoured exactly

- **Discrete Movements lists — CLOSED.** Doc 11's table only kept one worked
  example (Level3 `LeftStepSpawner`); the full per-spawner `Movements` data
  was re-extracted from the prefab dump (`spawners_extracted.json`) and is
  now in `Levels.luau` (`StepSpawnerDef.movements`/`SceneryDef.movements`),
  converted to studs — see the "Movements-list conversion" comment in
  `Levels.luau` and the "Direction / arrow semantics" section above.
  `Lane.luau` consumes it: discrete spawners jump between list entries
  (random destination ≠ current, mirroring `Spawner.cs`'s `Move()`
  coroutine), continuous spawners tween between entries over `moveSpeed`
  seconds, and `spawnAllOnAwake` spawners (the Tutorial's 3 trees) spawn one
  entity per `Movements` entry at that exact position, index-matched with
  `pool` (`Spawner.cs`'s `CycleThroughMovementsAndSpawn`). One deliberate
  deviation: the converted values are, like Unity's own off-screen
  `adjustedMovements`, meant as staging points a *continuous* per-frame pull
  drags on screen — this port only pulls on a discrete per-grab tween, so
  `Lane.spawnPosition` clamps them into `Lane.isOutOfBounds`' recycle margin
  before use rather than placing steps at the literal converted offset. The
  old procedural edge/shape placement is kept as the fallback for any
  spawner whose list is empty (none currently).
- **Menu / scenery / Bug spawners**: kept as complete, typed data
  (`Levels.luau`'s `scenerySpawners`/`levelObjects`) but not spawned — per doc
  13's explicit scope, a later phase renders scenery and the Menu level.
- **Country/Multiplayer split-screen specifics** (second camera, P2 spawner
  duplicates, `US`/`UnitedStates.cs` object) are represented as data
  (`levelObjects = {"US"}`) but not rendered; Country is reachable in this
  single-player-per-lane port via `LEVEL_THRESHOLDS.Country` instead of a
  multiplayer-only scene gate.
- **CrumblyRock/Castle's shipped `actionType = None`** (doc 12's own
  "surprising findings") were preserved deliberately, not "fixed" — see the
  comments in `StepKinds.luau`.

## Known risks needing a Studio playtest

- The procedural spawn-position/bounds numbers (`LANE_HALF_WIDTH`,
  `SPAWN_Y`/`DESPAWN_Y`, the diagonal-corner spread) are derived analytically,
  not visually tuned — steps may spawn slightly off-camera or too close to the
  frog's grab range depending on the actual camera framing once art exists.
- `Lane.pickKind`'s bounded-retry weighted pick and `changeDirection`'s
  sign-matching graph (see the worked example in the "Direction / arrow
  semantics" section above) haven't been played by a human — the *logic* is
  verified by hand-tracing, not by feel.
- Multiple simultaneous lanes' Heartbeat cost (`Lane.iter()` + per-lane
  spawner/step loops) scales linearly with player count; fine for the
  expected small server sizes, unverified beyond that.
- The Tutorial's "pull the field back up by 3" retry has no Studio-verified
  feel for how visually jarring the snap-back tween is.
- The Movements-list conversion (`Levels.luau`) assumes a specific Unity
  camera aspect ratio (the one that makes `halfScreenWidth` equal the
  playfield's own border bound) to turn doc 11's raw per-axis fractions into
  studs; the real aspect ratio is unresolvable from the prefab dump. Combined
  with `Lane.spawnPosition`'s clamp into `Lane.isOutOfBounds`' margin, this
  is a best-effort reconstruction of each spawner's *shape*, not a verified
  match to how it looked in Unity — needs a playtest to see whether entry
  points read as natural or need hand-tuning.

## What was not completed

Everything in the task's required-design list (items 1–10) was implemented.
Not implemented, by explicit scope (doc 13 item 2): actual scenery/Bug spawner
rendering, the Menu level's gameplay, and per-skin cosmetic rendering of
`LevelChanged`'s background/overlay/music payload — all deferred to a later
phase, with the data already in place for it.
