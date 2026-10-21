# 18 - Step kinds by level (audit)

Entry `b-20261020-215825-bmrz`. Read at commit `6645c92` (`src/shared/Levels.luau`, `src/shared/StepKinds.luau` and `src/server/Lane.luau` had no uncommitted changes when read; another fixer may change Levels/Lane later, so re-check the Country tables). Facts from code only; suggestions are marked as such.

## How a pick works

- Each level has step spawners with a `pool` (list of StepKinds names). `Lane.pickKind` does one weighted draw over the pool of the spawner active for the lane's current scroll direction (by sign): Down, DownLeft, DownRight, Left, Right, plus a themed Rocket spawner that scrolls left.
- Weight = the current height stage's `weights[kind]` if listed, else `StepKinds[kind].spawnProbability`. Shares below are weight / pool total, before gating.
- Gates: an arrow whose `canSpawn` says the bias already points that way is skipped (`UpRock` never on a straight-down scroll; `LeftRock`/`RightRock` only when not already horizontal). Kinds flagged `hazard` (Crumble, Blink, cars) are capped at 2 of the last 6 spawns.
- `withDynamic` adds Lillipad, BobRock, SpringRock, BlinkRock, CrumbleRock to a pool (weight comes from the stage). `withOutdoor` = withDynamic + TreeTrunk, OakTree, CarRight, CarLeft.
- Patterns (`patternChance` per stage) replace one spawn with a formation. Members with no `kind` are plain picks (no arrows, no hazards). Named members: FlyRock (BugChain), Lillipad (PadLadder), SpringRock (SpringStreak), Castle (CastleKeep).
- Thresholds: Kitchen 50, Country 100, Space 250 run steps. Stage counts are steps since level entry (Kitchen, Country, Space) or whole-run (Pot).
- StepKinds default weights: arrows 0.1; Shelf kinds, Potato, Carrot 0.5; Rocket, Balloon 1.0; Asteroid 1.5; TreeTrunk, OakTree 0.4; cars 0.2; Lillipad 0.15, BobRock 0.15, SpringRock/BlinkRock/CrumbleRock 0.1.

## 1. Per level

### Tutorial (3 kinds)
One spawner (`TreeDownStepSpawner`, 3 spawns, all at once): TutorialFirstTree, TutorialSecondTree, TutorialLastTree, weight 1.0 each. All three use the same `Acorn` sprite and a plain hold. No stages, patterns, arrows or Halloween swap.

### Pot (7 kinds incl. scripted PotRim; 3 stages by run step: 0-15 / 15-35 / 35+)
Pools: DownLeft `Potato, Carrot, UpRock, Lillipad`; DownRight `Carrot, Potato, UpRock, Lillipad`; Down `Potato, Carrot, UpLeftRock, UpRightRock, Lillipad`. PotRim is in no pool; `Lane.spawnRim` lays it at run step 50 and grabbing it is the level-up.

| Stage | Carrot | Potato | Arrows | Lillipad | Down pool share | DownLeft/Right pool share |
|---|---|---|---|---|---|---|
| 1 (<15) | 3 | 0.4 | 0.2 each | 0 | Carrot 79%, Potato 11%, 2 arrows 5% each | Carrot 83%, Potato 11%, UpRock 6% |
| 2 (15-35) | 1 | 1.5 | 0.5 each | 0 | Carrot 29%, Potato 43%, arrows 14% each | Carrot 33%, Potato 50%, UpRock 17% |
| 3 (35+) | 0.5 | 0.7 | 1.6 each | 0.5 | Carrot 10%, Potato 14%, arrows 33% each, Lillipad 10% | Carrot 15%, Potato 21%, UpRock 49%, Lillipad 15% |

Stage 3 also has `patternChance` 0.08 (ZigZag only). No events. No `hazard` kinds (Potato explodes after grab but is not flagged).

### Kitchen (14 kinds incl. FlyRock via pattern; 4 stages since entry: 0-12 / 12-26 / 26-38 / 38+)
Pools: DownRight and DownLeft `ShelfWithSpoon, ShelfWithFork, Shelf, UpRock`+dynamic; Right adds `UpRightRock`; Left adds `UpLeftRock`; Down `ShelfWithSpoon, ShelfWithFork, Shelf, UpLeftRock, UpRightRock, LeftRock, RightRock`+dynamic. Scripted intro: `Shelf, Shelf, RightRock` (ahead of the weighted pick; RightRock only from the Down spawner). Event: SpringStreak (3%, from step 30, cooldown 25). Shelves and arrows keep default weights in every stage.

Down pool shares (shelves = the three shelf kinds together, a third each; arrows = the four together):

| Stage | Shelves | Arrows | Lily | Bob | Spring | Blink | Crumble | Patterns (chance) |
|---|---|---|---|---|---|---|---|---|
| 1 | 79% | 21% | 0 | 0 | 0 | 0 | 0 | none |
| 2 | 59% | 16% | 14% | 12% | 0 | 0 | 0 | ZigZag, Staircase, Cluster (0.10) |
| 3 | 49% | 13% | 11% | 10% | 7% | 0 | 10% | + BugChain (0.15) |
| 4 | 43% | 11% | 11% | 10% | 6% | 9% | 10% | + PadLadder (0.20) |

Stage weights Lily/Bob/Spring/Blink/Crumble: 1: 0/0/0/0/0; 2: .35/.3/0/0/0; 3: .35/.3/.2/0/.3; 4: .4/.35/.2/.3/.35. Sideways pools have one arrow, so at stage 4 shelves are ~46% and dynamics ~48%.

### Country (18 kinds incl. Castle and FlyRock; 4 stages since entry: 0-10 / 10-30 / 30-60 / 60+)
Pools: Down `UpLeftRock, UpRightRock, LeftRock, RightRock`+outdoor; DownLeft `UpRock, UpLeftRock, UpRightRock`+outdoor; Right `UpRock, UpRightRock, RightRock`+outdoor; Left `UpRock, UpLeftRock, LeftRock`+outdoor. Themed `Level4RightStepSpawner` (scrolls left, no patterns): `Rocket`, `Balloon`, 50/50. Shelves were removed (b-20261020-213556-k25y). Every stage weights the 5 arrows 0.25 and TreeTrunk/OakTree 0.6. Events: CastleKeep (4%, from step 5, cooldown 20; Castle is in no pool), SpringStreak (3%, from step 25).

| Stage | Lily | Bob | Spring | Blink | Crumble | CarR / CarL | Patterns (chance) |
|---|---|---|---|---|---|---|---|
| 1 | .35 | .30 | .15 | 0 | 0 | 0 / 0 | ZigZag, Staircase, Cluster (0.10) |
| 2 | .40 | .35 | .25 | .20 | .30 | .15 / .15 | + BugChain (0.18) |
| 3 | .45 | .40 | .25 | .35 | .40 | .20 / .20 | + PadLadder (0.22) |
| 4 | .50 | .45 | .30 | .45 | .45 | .25 / .25 | same (0.25) |

Down-pool shares (4 arrows together, 2 trees together): stage 1: trees 40%, arrows 33%, Lily 12, Bob 10, Spring 5. Stage 2: trees 30, arrows 25, Lily 10, Bob 9, Spring 6, Blink 5, Crumble 8, cars 8. Stage 3: trees 27, arrows 22, Lily 10, Bob 9, Spring 6, Blink 8, Crumble 9, cars 9. Stage 4: trees 25, arrows 21, Lily 10, Bob 9, Spring 6, Blink 9, Crumble 9, cars 10. Sideways pools have 3 arrows, so trees and movers get a larger share.

### Space (13 kinds incl. FlyRock; 2 stages since entry: 0-12 / 12+)
Pools: Down `Asteroid, UpLeftRock, UpRightRock, LeftRock, RightRock`+dynamic; DownLeft `Asteroid, UpRock`+dynamic; Right adds UpRightRock; Left adds UpLeftRock. Themed `RocketSpawner` (scrolls left, no patterns): `Rocket` only. Intro: `Asteroid, Asteroid`. Arrows default 0.1, Asteroid 1.5. Event: SpringStreak (3%, from step 25).

| Stage | Asteroid | Arrows (4) | Lily | Bob | Spring | Blink | Crumble | Patterns |
|---|---|---|---|---|---|---|---|---|
| 1 (<12) | 59% | 16% | 14% | 12% | 0 | 0 | 0 | none |
| 2 (12+) | 37% | 10% | 12% | 11% | 7% | 11% | 11% | ZigZag, Staircase, Cluster, BugChain, PadLadder (0.25) |

### Halloween substitution (every level except Tutorial)
When `SpriteSkin.halloweenLive()` (Oct 24 to Nov 1 UTC, or workspace attribute `ForceHalloween`), after the weighted draw `Lane.pickKind` turns 25% (`Config.HALLOWEEN_PUMPKIN_CHANCE`) of picks into `Pumpkin` (plain step, JackOLantern art on Potato's canvas), unless the pick is an arrow or a `hazard`. The intro sequence returns before the swap. Non-hazard movers (Lillipad, BobRock, SpringRock), trees, Rocket and Balloon can all be swapped; pattern members with an explicit kind (FlyRock, Castle, SpringRock) do not go through `pickKind`.

### Scenery-only (SceneryKinds.luau, not steps)
Menu: BackGrass, Cloud3, Grass. Tutorial: Stars. Pot: Flame, Bubble (client extras FlameBack, extra Bubble). Kitchen: Window (the Chef hazard is a server script, not a step). Country: Window, US object (client extras: Leaf, clouds). Space: no scenery spawners in Levels. Halloween adds Ghost and Cobweb everywhere.

## 2. Per kind

| Kind | Used by | Notes |
|---|---|---|
| TutorialFirstTree / SecondTree / LastTree | Tutorial | identical Acorn art |
| Potato, Carrot | Pot | fits |
| PotRim | Pot (scripted, step 50) | weight 0, in no pool |
| UpRock, UpLeftRock, UpRightRock | Pot, Kitchen, Country, Space | rock-art arrows in every level |
| LeftRock, RightRock | Kitchen (Down pool), Country, Space (Down pool) | no Unity pool; port addition |
| Shelf, ShelfWithFork, ShelfWithSpoon | Kitchen | fits; none outdoors or in Space |
| Lillipad | Pot (stage 3), Kitchen, Country, Space, PadLadder | pond art in a pot, kitchen, sky and space |
| BobRock, SpringRock | Kitchen, Country, Space | tinted WhiteRock (sky, lime) |
| BlinkRock, CrumbleRock | Kitchen (late), Country, Space | violet SmallRock / CrumblyRock art; hazards |
| Rocket | Country, Space | fits both |
| Balloon | Country | fits |
| TreeTrunk, OakTree | Country | fits |
| CarRight, CarLeft | Country | fits; hazards, weight 0 in stage 1 |
| Asteroid | Space | the only Space-themed foothold |
| Castle | Country event (CastleKeep) | salmon-tinted castle, in no pool |
| FlyRock | BugChain in Kitchen (stage 3+), Country (stage 2+), Space (stage 2+) | wrapped-rock art |
| Pumpkin | non-Tutorial levels during Halloween | weight 0, in no pool |
| StillRock, CrumblyRock, SlowFallRock, FallingRock, FlingingRock, Beetle | **no level (dead)** | legacy Unity `General/Spawners` data, per the StepKinds comment |

Dead: 6 of 35 kinds. In no pool but live by other routes: PotRim, Castle, Pumpkin, FlyRock.

Look clashes (from the art each kind names): Shelf/Fork/Spoon appear only in the Kitchen, so no utensils outdoors. In the Kitchen the arrows and BobRock, SpringRock, BlinkRock, CrumbleRock are all rock art on a shelf level. Lillipad (pond plant) is in the Pot, Kitchen, Country sky and Space. Space has one themed foothold (Asteroid), next to Lillipad, tinted white rocks and rock arrows. No rock or utensil kind appears in a level where Unity had none, except the arrows (all levels).

## 3. Observations

- Distinct kinds: Tutorial 3, Pot 7, Kitchen 14, Country 18, Space 13 (counting scripted and pattern kinds, not Pumpkin).
- Tutorial's three kinds share one sprite: one look.
- Pot has two non-arrow footholds (Potato, Carrot); at stage 3 arrows are ~65% of the Down pool and ~49% (UpRock) of the sideways pools. Lillipad is in the Pot pools but weighs 0 in stages 1-2.
- Kitchen stage 1 and Space stage 1 are mostly static: all five dynamic kinds weigh 0 in Kitchen stage 1.
- Country has no shelf or plain rock; plain footholds are the two trees only (24-40% of the Down pool), arrows 21-33%, and cars, BlinkRock and CrumbleRock are hazards under the 2-of-6 cap. Stage 1 has no Blink, Crumble or cars.
- Rocket/Balloon (Country) and Rocket (Space) come from a left-scrolling spawner only; Country starts scrolling left, but Space starts scrolling straight down, so rockets show only after a turn to the left.
- Pumpkin and PotRim have spawnProbability 0 by design; Asteroid carries 1.5 to stand in for three shelves. LeftRock/RightRock appear in no Unity pool.
- Suggestions (not changes): a Space-specific mover art in place of Lillipad and the tinted rocks; non-rock looks for the Kitchen's dynamic kinds; themed arrow art per level; either use the six dead kinds somewhere or remove them; if Country still starves after the in-flight fix, add a plain outdoor foothold (for example a boulder) beside the trees.

The design that follows from this audit is in [19-level-theming.md](19-level-theming.md).
