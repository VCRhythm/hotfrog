# 04 — Build Roadmap

Build the port in this order. Each milestone is independently testable in Roblox
Studio (press **Play** / **F5** and observe). Keep early milestones client-only
for speed, then move authority to the server where noted. Each step links back to
the relevant section of [03-core-mechanics.md](03-core-mechanics.md).

> Tip: in Studio, use **Test → Play** for solo testing and the **Output** window
> for `print`/`warn`. Toggle **Test → Clients and Servers** when you start moving
> logic server-side so you can see both contexts.

## Milestone 1 — Static scene

**Goal:** the playfield exists and the camera frames it.

- Create `Workspace/PlayField` with a `Lava` part at the bottom and an empty
  `Steps` folder. Add one anchored `StepTemplate` and a `FrogModel` placeholder on
  the `Z = 0` plane.
- Set `CurrentCamera.CameraType = Scriptable` and point it at the plane
  ([Option A](02-architecture-mapping.md#option-a--plane-in-3d-with-real-parts-recommended)).
- Add `ReplicatedStorage/Shared/Config`.

**Verify:** press Play — you see the frog, one step, and the lava, framed flat
with no perspective drift that breaks readability.

## Milestone 2 — Custom gravity + lava death + restart

**Goal:** the frog falls and dies in lava, then the run resets.

- Implement the
  [frog gravity loop](03-core-mechanics.md#frog--custom-gravity) (Heartbeat).
- Implement the [lava lose check + restart](03-core-mechanics.md#lava--lose-condition)
  (can be client-only for now; move to server in M8).

**Verify:** press Play — the frog accelerates downward, touches the lava, the run
ends and resets (frog returns to start). The fall should *accelerate*, not be
linear (confirms the multiplier curve from `Frog.cs`).

## Milestone 3 — Tap-to-grab, one limb (no pull yet)

**Goal:** clicking/tapping the step makes a limb grab and the frog hangs.

- Implement [input → grab](03-core-mechanics.md#input--grab) for a single free
  limb and the held-limb follow in
  [limbs](03-core-mechanics.md#limbs--grabbing).
- While a limb holds a step, `Frog.isHolding = true` so gravity pauses.

**Verify:** press Play — tap the step before the frog falls past it; a limb snaps
to it and the frog stops falling. Tap empty space → nothing grabs (a "miss").

## Milestone 4 — Two limbs + free/return

**Goal:** two independent limbs; releasing one lets it return to rest.

- Add the second limb; implement `getFreeLimb`, release on input-end, and the
  smooth return-to-rest in [limbs](03-core-mechanics.md#limbs--grabbing).

**Verify:** with two fingers (or two quick clicks on two steps placed by hand),
both limbs grab independently. Release one → it eases back to its rest pose while
the other keeps holding.

## Milestone 5 — Step spawner + pool

**Goal:** steps appear above continuously and recycle below.

- Implement the [spawner + pool](03-core-mechanics.md#steps--spawning). For now
  steps can be stationary after spawn (the pull comes next).

**Verify:** press Play — new steps appear above on a cadence. Temporarily lower
`DESPAWN_Y` above the spawn area to confirm recycling fires (watch the `Steps`
folder count stay bounded in the Explorer).

## Milestone 6 — Pull / world-scroll (the crux)

**Goal:** grabbing scrolls the field down so the frog climbs while centered.

- Implement [the pull](03-core-mechanics.md#the-pull--world-scroll-mechanic),
  framing **(a)** (move the field down). At this point introduce the
  `GrabStep` RemoteEvent and let the **server** drive the scroll, even if the rest
  is still client-side.

**Verify:** press Play — grab a step and the whole field of steps slides down by
`PULL_DISTANCE` while the frog stays roughly centered. Chain grabs (release one
hand, grab a higher step with the other) to keep climbing indefinitely. This is
the "is it Hotfrog?" checkpoint — it should *feel* like climbing.

## Milestone 7 — Scoring + HUD + high score

**Goal:** score counts steps climbed, shows on screen, and persists.

- Implement [scoring & HUD](03-core-mechanics.md#scoring--hud) with `ScoreChanged`
  and `DataStoreService`. Increment score on each validated grab in the server's
  `GrabStep` handler.

**Verify:** press Play — score increments per grab and the HUD updates live. End a
run, start again, and the "Best" value reflects your previous high score.
(DataStore requires **Game Settings → Security → Enable Studio Access to API
Services** to persist in Studio.)

## Milestone 8 — Move authority to the server

**Goal:** spawning, pull, score, and death are server-authoritative.

- If you prototyped M2–M7 client-side, finish the
  [client/server split](02-architecture-mapping.md#decision-2-client--server-split):
  server owns spawning (already), pull, score, high score, and the lava death
  check; client sends grab events and renders.
- Replace any client-reported score with server-side increments validated against
  real grabs.

**Verify:** with **Clients and Servers** test mode, confirm steps/score live on
the server and replicate to the client, and that editing client state can't change
the score.

## Milestone 9 — Thin polish (optional but cheap)

- **Grab quality:** surface `Perfect/Great/OK/Miss` from
  [`gradeGrab`](03-core-mechanics.md#input--grab) as a flash + sound (mirrors
  `HUD.cs` milestone feedback).
- **Audio:** a small client audio module wrapping `Sound` instances for
  grab/miss/fall/crumble (mirrors `Audio/AudioManager.cs`).
- **Continuous pull feel:** if the discrete tween feels steppy, replace it with a
  `PreSimulation` integrated pull velocity (the literal port of
  `SpawnManager.PullVector`) — see the note in
  [the pull section](03-core-mechanics.md#the-pull--world-scroll-mechanic).

**Verify:** grabs feel responsive, quality feedback reads clearly, audio fires on
the right events.

---

## Later / out of scope

Deferred from the basic version — each maps to an existing Unity system that can be
layered on once the core loop is solid:

- **Step behaviors** — the `ActionType` variants (crumble, fall, change-direction,
  launch, beetle, castle, spawn-fly, ...) in `Entities/Step.cs`. Add a per-step
  `Behavior` attribute + behavior `ModuleScript` invoked on grab/release.
- **Bugs & tongue** — the collectible loop (`Entities/Bug.cs`,
  `Entities/Tongue.cs`, `Spawning/BugSpawner.cs`).
- **Frog skins / store** — `UI/FrogPackages.cs`, `Store/`, `Ads/` → Roblox
  MarketplaceService / cosmetics.
- **Scripted levels** — timed and step-count events
  (`Core/LevelManager.cs`, `Core/LevelEvent.cs`, `Core/Level.cs`).
- **Local multiplayer** — the original supports 2+ controllers
  (`Core/ControllerManager.cs`); Roblox would do this as multiple players or
  split-screen-style local inputs.

When you pick one of these up, start a new doc (e.g. `05-step-behaviors.md`) and
follow the same pattern: restate the Unity behavior, map it, snippet it, add
milestones.
