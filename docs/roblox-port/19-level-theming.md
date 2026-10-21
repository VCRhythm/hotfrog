# 19 - Level theming and step rosters (design)

Entry `b-20261021-074242-z0a9` (reopens the audit `b-20261020-215825-bmrz`, doc [18](18-step-kinds-by-level.md)). **A proposal: no code changed.** Read at commit `393a9d9` (`src/shared/Levels.luau`, `StepKinds.luau`, `StepBehaviors.luau`, `SkinAssets.luau` clean); the Country pools are the ones after `b-20261020-213556-k25y` (no shelves, arrows 0.25, trees 0.6), which is what doc 18 already records. Everything here is a port addition on top of doc 17's deviations; nothing below touches a Unity value from docs 11 and 12.

## Principles

1. **Re-skin, don't drop.** Every level keeps each mechanic it has today: the arrows (they steer the scroll), the hazards (Crumble, Vanish, cars, Potato), the movers (Patrol, RiseAndFall, Launch), FlyRock's BugChain (the Flys faucet) and the events. What changes is which *kind* plays each role, so the look fits the level.
2. **Roles, not kind names.** A level's roster is five roles: plain foothold, mover, hazard/crumble, arrow, special/event. Today the movers and hazards are one global set (`Levels.DYNAMIC_KINDS`: Lillipad, BobRock, SpringRock, BlinkRock, CrumbleRock) appended to every pool by `withDynamic`; the proposal gives each level its own kind per role.
3. **Same difficulty curve.** Each role keeps today's stage weights (doc 18 tables); a themed kind inherits the weights of the kind it replaces. New weights are given only for kinds that are new to a level.
4. **One look, one behaviour, within a level.** A sprite that appears twice in a level must differ by tint and never hide a different behaviour. Moving and timed kinds keep their gameplay tint as an accent where the art allows (doc 17 "Halloween night sky and pumpkin steps": tints signal gameplay).
5. **Halloween stays as it is.** `Lane.pickKind` swaps 25% (`Config.HALLOWEEN_PUMPKIN_CHANCE`) of ordinary picks that are not arrows and not `hazard` for `Pumpkin`. Every new non-hazard kind below is swappable; every new hazard is not. `GameServer`'s `HALLOWEEN_TINTS` is keyed by sprite (`CrumblyRock`, `WhiteRock`) and only touches untinted kinds, so new sprites get no Halloween tint unless added there.

## 1. Art on hand

All stems below have a non-zero id in `src/shared/SkinAssets.luau` (uploaded).

| Stem | Look | Steps using it today | Free to use for |
|---|---|---|---|
| `WhiteRock` | blank white rock silhouette, made to be tinted | BobRock (sky), SpringRock (lime), SlowFallRock, FallingRock (salmon), Beetle (black) | fallback mover art anywhere |
| `SmallRock` | small white silhouette | BlinkRock (violet) | reads as a space pebble |
| `CrumblyRock` | cluster of dark red and black pebbles (reads as coals or rubble) | CrumbleRock, CrumblyRock | Pot ember (tinted), stove coals |
| `WrappedRock` | brown boulder with green bands (reads as a mossy rock) | FlyRock, StillRock, FlingingRock | Country plain rock |
| `UpArrow` `UpLeftArrow` `UpRightArrow` `LeftArrow` `RightArrow` | white rock with a black arrow; a tint recolours the rock, the arrow stays black | the five arrow kinds | per-level arrow tint |
| `Shelf` (+ `Fork`, `Spoon` flingees) | wooden wall shelf | Shelf, ShelfWithFork, ShelfWithSpoon | Kitchen movers |
| `Lillipad` | green leafy pad | Lillipad | Pot (as a floating cabbage leaf) |
| `Balloon`, `Rocket`, `Castle`, `Asteroid` | themed props | Balloon, Rocket, Castle, Asteroid | smaller re-sized copies as movers |
| `Carrot`, `Potato`, `Acorn`, `TutorialTreeMid`, `TreeTrunk`, `CarLeft`, `CarRight`, `PotRim`, `JackOLantern` | themed | their own kinds | keep |

Scenery art is not proposed as steps: `Cloud`/`Cloud2`/`Cloud3` are Country and Menu sky layers (CloudNear is a tappable layer right behind the steps), `Leaf` is a 16 px silhouette, `Bubble` and `Flame`/`Flame2` are Pot scenery. A step that looks like scenery makes the player tap the wrong thing. `Flame` stays usable as a flingee (it already is FlingingRock's).

## 2. Per level

Weights are stage weights as in doc 18 (stages and bounds unchanged). "Existing" means the kind can be built from uploaded art; "new art" names a sprite that does not exist yet.

### Tutorial: "the frog's home oak at dawn"

| Role | Today | Proposed | Weight |
|---|---|---|---|
| Plain | TutorialFirstTree / SecondTree / LastTree (`Acorn`) | unchanged | 1.0 each, scripted 3 spawns |
| Mover, hazard, arrow, special | none | none | - |

No change. The Tutorial teaches the grab only and must stay static. The oak already rhymes with Country (`OakTree` reuses `TutorialTreeMid`). No Pumpkin swap here today, and none proposed.

### Pot: "a simmering soup pot: vegetables in the broth, fire below, climb to the rim"

| Role | Today | Proposed (existing art) | New-art option | Weight by stage 1 / 2 / 3 |
|---|---|---|---|---|
| Plain | Carrot | Carrot | - | 3 / 1 / 0.5 |
| Plain, flings | none | **Ember** (revived FlingingRock: `SplashFlinging`, `CrumblyRock` art tinted orange, `Flame` flingee) | - | 0 / 0.3 / 0.4 (new) |
| Hazard | Potato (`ExplodeAfterGrab`) | Potato | - | 0.4 / 1.5 / 0.7 |
| Mover (Patrol) | Lillipad | Lillipad, recast as a floating cabbage leaf (art unchanged) | `CabbageLeaf` | 0 / 0 / 0.5 |
| Arrows | UpRock, UpLeftRock, UpRightRock (white) | same kinds, **broth-amber arrow tint** | Pot arrow set (3) | 0.2 / 0.5 / 1.6 each |
| Special | PotRim (scripted at run step 50) | unchanged | - | - |

Changes: Pot gets a third non-arrow foothold (doc 18: only Carrot and Potato today), from a dead kind. Ember's flame is harmless debris (`SplashFlinging` has no damage), so it is not a `hazard` and Halloween can swap it. Ember is tinted, so it never shares a look with the untinted `CrumbleRock` coals of later levels. Pot keeps no Crumble, Vanish or Launch kind, as today.

### Kitchen: "up the kitchen wall past the stove: shelves, cutlery, the Chef on patrol"

| Role | Today | Proposed (existing art) | New-art option | Weight (stages 1 / 2 / 3 / 4) |
|---|---|---|---|---|
| Plain | Shelf, ShelfWithFork, ShelfWithSpoon | unchanged (Fork/Spoon fling cutlery) | - | 0.5 each |
| Mover (Patrol) | Lillipad | **SlidingShelf** (`Shelf`, Patrol, warm tint) | `Plate` | 0 / .35 / .35 / .4 |
| Mover (RiseAndFall) | BobRock (sky `WhiteRock`) | **LiftShelf** (`Shelf`, RiseAndFall, sky tint) | `FryingPan` on a hook | 0 / .3 / .3 / .35 |
| Mover (Launch) | SpringRock (lime `WhiteRock`) | SpringRock (unchanged) | `Toaster` | 0 / 0 / .2 / .2 |
| Hazard (Vanish) | BlinkRock (violet `SmallRock`) | BlinkRock (unchanged) | `IceCube` (melts) | 0 / 0 / 0 / .3 |
| Hazard (Crumble) | CrumbleRock (`CrumblyRock`) | CrumbleRock, read as stove coals | - | 0 / 0 / .3 / .35 |
| Arrows | five rock arrows (white) | same kinds, **tile-colour tint** picked against `KitchenTile` | Kitchen arrow set (5) | 0.1 each (default) |
| Special | FlyRock (BugChain), SpringStreak, Chef, intro `Shelf, Shelf, RightRock` | unchanged; SpringStreak and PadLadder use this level's Launch and Patrol kinds | - | as today |

Changes: Lillipad and BobRock leave the Kitchen; the pond pad and the sky rock become moving shelves, which is the doc 18 clash ("rock art on a shelf level") fixed with existing art. Launch and Vanish stay rock-art until the Toaster and IceCube exist.

### Country: "the countryside: trees, mossy rocks, road traffic, balloons on the wind, a castle on the way up"

| Role | Today | Proposed (existing art) | New-art option | Weight (stages 1 / 2 / 3 / 4) |
|---|---|---|---|---|
| Plain | TreeTrunk, OakTree | TreeTrunk, OakTree, **StillRock** (revived, `WrappedRock` mossy rock, `None`) | - | trees 0.6 each; StillRock 0.4 (new) |
| Mover (Patrol) | Lillipad | **DriftBalloon** (`Balloon` on a ~12-stud canvas, Patrol; rides Country's wind theme) | `Bird` | .35 / .4 / .45 / .5 |
| Mover (RiseAndFall) | BobRock | BobRock (unchanged) | `Butterfly` | .3 / .35 / .4 / .45 |
| Mover (Launch) | SpringRock | SpringRock (unchanged) | `Trampoline` | .15 / .25 / .25 / .3 |
| Hazard (Vanish) | BlinkRock | BlinkRock (unchanged) | `Dandelion` (puffs away) | 0 / .2 / .35 / .45 |
| Hazard (Crumble) | CrumbleRock | CrumbleRock, read as rubble | - | 0 / .3 / .4 / .45 |
| Hazard (other) | CarRight, CarLeft | unchanged | **Beetle** (revived; shrugs you off once; flag `hazard`) | cars 0 / .15 / .2 / .25 each; Beetle 0 / .1 / .15 / .15 (new art only) |
| Arrows | five rock arrows at 0.25 | same, **fence-post brown tint** | signpost arrow set (5) | 0.25 each |
| Special | Rocket/Balloon spawner, CastleKeep, SpringStreak, BugChain, PadLadder | unchanged; PadLadder becomes two DriftBalloons | - | as today |

Changes: a third plain foothold (doc 18: "Country has no plain rock"). In the Down pool at stage 1 the plain share goes from 40% to 47% and arrows from 33% to 29% (total weight 3.0 to 3.4). StillRock and FlyRock share `WrappedRock`; FlyRock only appears inside a BugChain, so the cost is that a lone mossy rock never wakes a bug. If that reads badly, tint FlyRock (decision 4). The Beetle needs real beetle art: a black-tinted `WhiteRock` that throws you off reads as a bug in the game, not a beetle.

### Space: "a low-gravity asteroid belt above the clouds"

| Role | Today | Proposed (existing art) | New-art option | Weight (stages 1 / 2) |
|---|---|---|---|---|
| Plain | Asteroid (intro `Asteroid, Asteroid`) | unchanged | - | 1.5 |
| Mover (Patrol) | Lillipad | **DriftAsteroid** (`Asteroid`, Patrol, pale-blue tint) | `Satellite` | .35 / .5 |
| Mover (RiseAndFall) | BobRock | BobRock (unchanged) | `UFO` | .3 / .45 |
| Mover (Launch) | SpringRock | **BoostRocket** (`Rocket` on a ~14-stud canvas, Launch, `pull` 8) | - | 0 / .3 |
| Hazard (Vanish) | BlinkRock (violet pebble) | unchanged (fits as a space pebble) | - | 0 / .45 |
| Hazard (Crumble) | CrumbleRock | **Meteor** (`Asteroid`, Crumble, salmon tint `TINT_SALMON`) | - | 0 / .45 |
| Arrows | four rock arrows (Down); UpRock, plus one diagonal on Left/Right | same, **pale-cyan tint** | beacon arrow set (5) | 0.1 each |
| Special | RocketSpawner (left scroll only), BugChain, PadLadder, SpringStreak | unchanged; PadLadder becomes DriftAsteroids, SpringStreak BoostRockets | - | as today |

Changes: Space goes from one themed foothold (Asteroid) to four (Asteroid, DriftAsteroid, Meteor, BoostRocket); Lillipad and CrumbleRock leave. Three asteroid looks need clearly different tints (none, pale blue, salmon). BoostRocket shares art with the plain themed Rocket at a third of the size; the hit box scales to about 2.8 x 3.4 studs, so it needs a `tapSize` (about 5 x 6) and a scaled `gripOffset`. Rockets still show only after a left turn (doc 18); whether to also seed them in the Down pool is decision 5.

## 3. Dead kinds

| Kind | Behaviour | Proposal |
|---|---|---|
| StillRock | `None`, `WrappedRock` | **use**: Country plain rock |
| FlingingRock | `SplashFlinging`, `Flame` flingee | **use**: Pot "Ember" (art changed to tinted `CrumblyRock`; or keep the kind and add `Ember` beside it) |
| Beetle | `Beetle` (one forced release), black `WhiteRock` | **use with new art**: Country hazard; stays dead without art |
| CrumblyRock | `None` twin of CrumbleRock (Unity-faithful: the prefab ships `actionType` 0) | **retire** |
| SlowFallRock | `Fall` (unsteady, drops away) | **retire**: Vanish and Crumble already cover "drops away" |
| FallingRock | `Falling` (constant drift down), salmon | **retire**: a slow drift is lost inside the pull; Space low gravity makes it odd |

"Retire" means deleting the `StepKinds` entry and recording it in doc 17; the `Fall` and `Falling` behaviours can stay in `StepBehaviors` as unused data (doc 17 "Unused `ActionType`s" already lists others like them).

## 4. New art list (for a later step; nothing generated now)

Made with the `ludo` skill, matched to the existing step style, saved as `Sprites/Rocks/<Stem>.png`, then `python tools/build_manifest.py`, `python tools/upload_to_roblox.py --manifest tools/asset_manifest.json`, `python tools/write_asset_ids.py`. Sizes follow the port-addition rule in `StepKinds` (TreeTrunk, cars): the canvas is the port's own size and the hit box is the art's extent.

| Stem | Level | Behaviour | PNG | Canvas (studs) | Hit box (studs) |
|---|---|---|---|---|---|
| `CabbageLeaf` (optional) | Pot | Patrol | 256 | 7.314 (`ART_ROCK`) | 5.6 (as Lillipad) |
| `Toaster` | Kitchen | Launch | 512 | 8.046 (`ART_SHELF`) | ~6 x 4 |
| `IceCube` | Kitchen | Vanish | 128 | 3.657 (`ART_SMALL_ROCK`) | 3.657, tap 6 |
| `FryingPan` (optional) | Kitchen | RiseAndFall | 512 x 256 | 8 x 4 | ~7 x 2.5 |
| `Plate` (optional) | Kitchen | Patrol | 512 x 256 | 8 x 4 | ~7 x 2.5 |
| `Trampoline` | Country | Launch | 512 x 256 | 8 x 4 | ~7 x 2.5 |
| `Dandelion` | Country | Vanish | 128 | 3.657 | 3.657, tap 6 |
| `Butterfly` | Country | RiseAndFall | 256 | 7.314 | ~5 |
| `Bird` (optional) | Country | Patrol | 256 | 7.314 | ~5 |
| `Beetle` | Country | Beetle | 256 | 7.314 | 6.914 (`HIT_ROCK`) |
| `Satellite` | Space | Patrol | 512 x 256 | 8 x 4 | ~7 x 3 |
| `UFO` | Space | RiseAndFall | 512 x 256 | 8 x 4 | ~7 x 3 |
| Arrow sets (decision 3 B) | Pot 3, Kitchen 5, Country 5, Space 5 | ChangeDirection* | 256 | 7.314 | 6.914 |

## 5. Implementation sketch

Shared groundwork (one fixer, first):

- `src/shared/Levels.luau`: replace the global `DYNAMIC_KINDS` / `withDynamic` with a per-level role map, e.g. `roles = { Patrol = "SlidingShelf", Bob = "LiftShelf", Launch = "SpringRock", Vanish = "BlinkRock", Crumble = "CrumbleRock" }`, used to build each pool and to key the stage weights. `PadLadder` and `SpringStreak` members name a role instead of `Lillipad` / `SpringRock`. Add an optional `arrowTint: Color3?` per level.
- `src/server/Lane.luau`: resolve a pattern member's role to the lane level's kind where `spawnPattern` reads `member.kind` (members with no kind still take a plain `pickKind`).
- `src/server/GameServer.server.luau` (`acquireStep` tint, where `kind.color or halloweenTint(...)` is chosen): use the level's `arrowTint` for `isArrow` kinds.
- `src/shared/Tips.luau`: the tips that describe looks ("Pebbly rock clusters", "Violet rocks") must name the per-level look.
- Docs: doc 17 rows "Dynamic steps", "Country outdoor area and Space", "Crumble step", "Halloween night sky and pumpkin steps"; doc 18 tables.

Per level (independent after the groundwork; each touches `StepKinds.luau` for its new kinds and its own block of `Levels.luau`):

| Level | Files | Work |
|---|---|---|
| Tutorial | none | - |
| Pot | `StepKinds.luau` (Ember, or rework FlingingRock), `Levels.luau` Pot pools and stages, `arrowTint` | add Ember to the three pools; Lillipad stays |
| Kitchen | `StepKinds.luau` (SlidingShelf, LiftShelf; later Toaster, IceCube), `Levels.luau` Kitchen roles, `arrowTint` | role map; intro unchanged |
| Country | `StepKinds.luau` (StillRock tweak, DriftBalloon; later Beetle with `hazard = true`, Trampoline, Dandelion, Butterfly), `Levels.luau` Country pools, stages (StillRock 0.4), roles, `arrowTint` | `withOutdoor` gains StillRock |
| Space | `StepKinds.luau` (DriftAsteroid, Meteor, BoostRocket with `tapSize` and scaled grip), `Levels.luau` Space roles, `arrowTint` | role map |
| Dead kinds | `StepKinds.luau` (delete CrumblyRock, SlowFallRock, FallingRock), `GameServer` `HALLOWEEN_TINTS` (`CrumblyRock` key stays: CrumbleRock uses it), doc 17 | after decision 4 |
| New art | `Sprites/Rocks/*.png`, then the `tools/` pipeline; `SkinAssets.luau` ids are written by `write_asset_ids.py` | per decision 1 |

Each step is checked with the static checks and a `StudioSpawnKind` / `StudioSkipTo` playtest per level (`.bugs/README.md`).

## Decisions for the owner

1. **Is new art in scope?** A: existing art only (tints, re-sized props, moving shelves, revived kinds). B: A now, then the new-art batch in section 4, most visible first (Toaster, IceCube, Trampoline, Satellite, UFO). C: new art for everything, no interim. *Recommended: B.*
2. **Lillipad's fate.** A: keep it in every level as today. B: keep it only in Pot (as a cabbage leaf) and give the other levels their own Patrol kind (SlidingShelf, DriftBalloon, DriftAsteroid). C: retire it everywhere. *Recommended: B.*
3. **Arrow look.** A: one `arrowTint` per level on the existing arrow art. B: themed arrow sprites (18 new). C: leave them white. *Recommended: A, with Country signposts as the first B set if art is approved.*
4. **Dead kinds.** A: use StillRock and FlingingRock (Ember) now, Beetle when its art exists, delete CrumblyRock, SlowFallRock and FallingRock. B: use the three, keep the other three as data. C: leave all six. Also: tint FlyRock so it differs from Country's StillRock? *Recommended: A, and tint FlyRock only if playtests show confusion.*
5. **Space roster and rockets.** A: DriftAsteroid, Meteor, BoostRocket now (existing art). B: wait for Satellite and UFO. Separately: also put `Rocket` in Space's Down pool at a low weight (about 0.2) so rockets appear without a left turn, which needs a spacing check of its 32-stud canvas in a patterned pool. *Recommended: A; keep rockets left-scroll-only until a playtest.*
6. **Halloween and movers.** The 25% Pumpkin swap turns movers (Patrol, RiseAndFall, Launch kinds) into static pumpkins. A: keep as today. B: skip movers in the swap too, so it only replaces plain footholds. *Recommended: B (one more check in `Lane.pickKind`).*
