# 01 — Game Overview: What We're Porting

This page describes Hotfrog's core loop and the non-obvious mechanics that give it
its feel. Everything here is tied to the original Unity source so you can verify
behavior before re-implementing it in Roblox.

## The core loop

```
        hang (frog falling under custom gravity)
                      │
            player taps/clicks a step
                      │
        a free limb reaches out and grabs it
                      │
   grabbing PULLS the field of steps downward
   → the frog effectively climbs while staying centered
                      │
        release / run out of reachable steps
                      │
            frog falls; if it hits LAVA → run ends
                      │
                 score = steps climbed
```

In one sentence: **you don't move the frog, you grab steps to pull the world past
the frog, climbing as high as you can before falling into the lava.**

## Mechanics that define the feel

These are the parts that are easy to get wrong. Each is the thing to replicate
faithfully.

### 1. Custom gravity (not engine gravity)

The frog falls under a hand-rolled gravity loop, not Unity's physics gravity.

- Source: `Player/Frog.cs` → `SteadilyLowerHead()` and `Fall()`.
- `gravity = 20`, starting `gravityMultiplier = 0.5`, accelerating by
  `gravityAcceleration = 0.02` each step (so the fall *accelerates* — a held frog
  resets the multiplier in `Bob()`).
- The head bobs up on a successful grab (`Frog.Bob()`), giving the climb its
  springy feel.

**Why it matters:** the acceleration curve and the per-grab reset are the "game
feel." Use a scripted fall in Roblox (Heartbeat-driven), *not* `Workspace.Gravity`
on the frog. See [03-core-mechanics.md](03-core-mechanics.md#frog--custom-gravity).

### 2. The pull / world-scroll mechanic (the crux)

When the frog grabs a step, the step is "pulled," and the spawner applies that
pull to **every active step** — so the whole field of steps slides relative to the
frog. The frog stays roughly centered while the world scrolls past it.

- Source: `Entities/Step.cs` → `Pull()` calls `SpawnManager.Instance.PullStep(...)`.
- Source: `Spawning/SpawnManager.cs` → maintains a `PullVector` and applies it to
  all active spawns each `FixedUpdate`.

**Why it matters:** this is *the* mechanic. Reproduce it before any polish. There
are two equivalent ways to stage it in Roblox (move the steps vs. move the
camera/frog) — see
[03-core-mechanics.md](03-core-mechanics.md#the-pull--world-scroll-mechanic).

### 3. Two independent limbs, multi-input

The frog has two limbs (hands) that grab independently, each tracking its own
input "touch." Free limbs smooth-return to a rest pose.

- Source: `Player/Controller.cs` → `limbs[2]`, `MoveLimbs()`, `GetFreeLimb()`,
  `FreeUnusedTouches()`.
- Source: `Player/Limb.cs` → per-limb free/held state.
- Rest positions in `Controller.cs`: `limbReturnPos = {(20,-40), (-20,-40)}`,
  `limbReturnTime = 0.3`.

**Why it matters:** two-handed grabbing lets the player chain grabs (release one
hand, grab with the other) to keep climbing. The original supports multi-touch;
the MVP only needs the two-limb model on a single player.

### 4. Grab quality (perfect / great / ok / miss)

A grab is scored by how close the tap was to the step's center.

- Source: `Player/Controller.cs` → `TouchStep()` computes
  `distance = (worldPos - step.position).sqrMagnitude` and buckets it
  (`> 20` ok, `> 10` great, else perfect), accumulating into `grabStats`
  (a `Vector4i`: perfect/great/ok/miss).
- A tap that hits nothing counts as a **miss** and plays `missSound`
  (`Controller.CheckTouch()`).

**Why it matters:** light polish, but cheap to add and it informs feedback (sound,
combo). Included in scope as a thin layer over the grab.

### 5. Steps with behaviors (extension point — not MVP)

Steps can be more than plain platforms. `Entities/Step.cs` defines an `ActionType`
enum with ~20 variants: `Crumble`, `CrumbleAfterRelease`, `Fall`,
`ChangeDirectionUp/Left/Right/...`, `Launch`, `Beetle`, `Castle`, `SpawnFly`, etc.
Each wires up `grabAction` / `releaseAction` callbacks.

**For the basic version, only `None` (plain step) is required.** Document the
callback hook so these can be layered in later — they map cleanly onto a
per-step "behavior module" in Roblox.

## Minimum viable feature set (checklist)

The basic port is "done" when all of these are true:

- [ ] Frog falls under a custom, accelerating gravity curve.
- [ ] Tapping/clicking a step makes a free limb grab it.
- [ ] Two limbs grab independently; free limbs return to rest.
- [ ] Grabbing pulls the field of steps so the frog climbs (world-scroll).
- [ ] Steps spawn continuously above and are recycled (pooled) below.
- [ ] Falling into the lava ends the run and restarts it.
- [ ] Score = steps climbed, shown on a HUD, with a persistent high score.
- [ ] (Thin polish) grab quality is computed and drives feedback.

Each item maps to a milestone in [04-build-roadmap.md](04-build-roadmap.md) and an
implementation section in [03-core-mechanics.md](03-core-mechanics.md).
