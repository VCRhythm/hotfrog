# 15 — Menus, HUD, Run Flow, Gamepad Input

> Phase 5. Builds on the per-player lanes in
> [13-levels-and-lanes.md](13-levels-and-lanes.md), the multiplayer hardening in
> [07-multiplayer.md](07-multiplayer.md), the store in
> [08-frog-skins-and-store.md](08-frog-skins-and-store.md), and the gift faucet in
> [09-gifts-and-ads.md](09-gifts-and-ads.md). Ports `UI/MenuManager.cs`,
> `UI/HUD.cs`, `UI/FrogPackages.cs`, `Core/ControllerManager.cs`, and the
> gamepad-relevant bits of `Player/Controller.cs`/`Input/*.cs`.

## Why a run-state machine

Before this phase a frog started falling the instant a profile loaded and
auto-respawned forever after death — there was no menu, no "you can watch
before you play," and no end-of-run summary. This phase adds a small
per-player state machine, owned entirely by `GameServer.server.luau`:

```
Menu --StartRun--> Playing --death--> Dead --RESPAWN_DELAY--> Menu
```

`Menu`/`Dead` both mean **idle**: the frog is parked at the lane origin with no
gravity, the lane spawns nothing beyond what was already there (and death
clears even that — see below), and grabs are rejected. Only `Playing` runs
gravity, spawning, and grab validation. The distinction between `Menu` and
`Dead` is purely which client panel is showing (main menu vs. end-of-run) —
the server treats them almost identically, which is why `Dead` auto-advances
to `Menu` on a timer instead of needing another client action.

## Remotes (all new; nothing existing changed shape)

| Remote | Direction | Purpose / validation |
|---|---|---|
| `StartRun` (RemoteEvent) | client → server | Begin a run. Rejected unless `runState == Menu`; 1s cooldown per player (same rolling-window spirit as `GrabStep`'s rate limit). On success: parks/un-deads the frog, zeroes this run's Flys/bugs counters, calls `Lane:prefill` (moved here from join-time — see below), sets `Playing`. |
| `RunStateChanged` (RemoteEvent) | server → client | Fires on every state change with the new state string. The single source of truth `GameClient`/`MenuClient`/`StoreUI` all listen to independently. |
| `RunSummary` (RemoteEvent) | server → client | Fired once, right before `Dead`: `score, newBest, isNewBest, {Perfect,Great,OK}, bugsThisRun, flysThisRun`. Never trusts the client — every field is server-computed. |
| `SetMusicOn` (RemoteEvent) | client → server | Validates a boolean, writes `profile.musicOn`, saves, and sets the `MusicOn` player Attribute — the whole contract the client music system (another agent's work) consumes. This script never plays anything. |
| `ReplayTutorial` (RemoteEvent) | client → server | Only from `Menu`. Sets `profile.tutorialDone = false`, saves, and calls `Lane:resetRun(false)` to put the lane back at Tutorial immediately. |
| `GetTopScores` (RemoteFunction) | client → server | Returns a cached (60s TTL) top-10 list `{userId, score, name}`, built from `Profiles.topScores(10)` + `Players:GetNameFromUserIdAsync` (pcall'd, name cached forever). |

`GrabStep` gained one line (`runState ~= Playing → reject`); `GameOver`,
`ScoreChanged`, `LevelChanged`, `ForceRelease` are all **unchanged** —
`Effects.client.luau`'s `GameOver` listener still just plays the fall sound.

## Death → summary → Menu, precisely

`killFrog` now: snapshots `score`/`grabQuality` before `resetScore` clears
them → `commitHighScore` (unchanged) → fires `RunSummary` → **immediately**
recycles every one of the lane's live steps (`clearLaneSteps`, new — reuses
`releaseStep` so behavior `onDestroy` hooks still run) so the idle lane is
actually empty, not just frozen mid-scroll → `Lane:resetRun` (unchanged,
still fires `LevelChanged("death")`) → `setRunState(Dead)` → after
`Config.RESPAWN_DELAY`, parks the frog and `setRunState(Menu)`. `StartRun`
does the `Lane:prefill` that used to happen at join/death time — a fresh
`Menu` lane is genuinely empty until the player presses Play.

## Bugs-caught / Flys-earned this run

`BugService`/`SkinService`/`GiftService` are off-limits this phase, so their
counts are derived **additively**, never by editing those scripts:

- **Client HUD** (`GameClient`): counts real `BugCaught` events (server only
  fires this on a confirmed catch), so it's exact.
- **Server `RunSummary`**: `GameServer` adds its own listener to the *same*
  `ServerStorage/AwardFlys` BindableEvent `SkinService` already fires on every
  bug catch, gift claim, and IAP grant (BindableEvents support multiple
  listeners). A catch is identified by amount `== Config.BUG_FLYS` (5); gifts
  grant a very different 100, so the heuristic doesn't collide in practice —
  documented as a heuristic, not a security-sensitive value.

## UI modules

| File | Owns |
|---|---|
| `src/client/ui/UIKit.luau` (new, ModuleScript) | Shared button/label/panel/placeholder-thumbnail builders, `screenGui()` (adds a viewport-driven `UIScale` for phone-portrait/desktop-landscape), `safeAreaTopPadding`, `constrainAspect`. |
| `src/client/ui/ClientSettings.luau` (new, ModuleScript) | The SFX on/off flag. Session-only, in-memory — Roblox LocalScripts have no persistent client storage and `Profiles.luau` is off-limits, so "client-side only" means exactly that, not "survives rejoin." |
| `src/client/MenuClient.client.luau` (new) | Main menu, end-of-run panel, Settings, Top Scores — everything driven by `RunStateChanged`/`RunSummary`. |
| `src/client/StoreUI.client.luau` (edited) | Unchanged store/gift *logic*; added a thumbnail box (Thumbnail → `SkinAssets.part`'s Head/Arm/Universal fallback chain → tinted placeholder), a `MenuBridge` (`OpenStore`/`StoreClosed` BindableEvents under `LocalPlayer`, same pattern as `LevelClient`'s `LevelState`) so `MenuClient` opens/closes this panel instead of duplicating the carousel, and `RunStateChanged`-gated visibility for its own Shop/Gift bottom bar. |
| `src/client/GameClient.client.luau` (edited) | HUD extras (Flys, bugs-this-run, level-name toast), the race rail, spectate camera, and all gamepad input — GameClient already owned the camera/HUD, so this phase's additions stay there rather than a fifth script. |

## Item-by-item

1. **Run flow / main menu** — done as above. `MenuClient` switches between
   `mainPanel` (Menu) and `endPanel` (Dead) off `RunStateChanged`; `Playing`
   hides both. Replay/Play use a `pendingStart` flag: clicking while still
   `Dead` (the ~1.5s `RESPAWN_DELAY` beat) queues `StartRun` for the moment
   `Menu` actually arrives, so it feels instant without ever trusting the
   client's idea of state.
2. **Frog select carousel** — `StoreUI`'s existing cycle/owned/locked/buy/
   select logic is untouched (doc 08); only a thumbnail box was added, with
   the exact fallback chain the task asked for (Thumbnail → Head via
   `SkinAssets.part` → tinted placeholder). No `SkinService` remote changed.
3. **Settings** — Music via the `MusicOn`/`SetMusicOn` contract above (real
   persistence, server-validated). SFX via `ClientSettings` (session-only, by
   design). "Replay tutorial" via the new `ReplayTutorial` remote.
4. **Pause** — deliberately **client-only, no remote** (`GameClient`, since it
   already owns the Playing-time HUD). A multiplayer server can't pause for
   one player without affecting everyone else's fairness, and the frog
   already only falls while holding zero steps, so there's nothing
   server-side *to* pause. The Pause button (visible only while `Playing`)
   opens an honest status panel instead of a real pause: holding a step means
   gravity is already frozen (says so); holding nothing means the run keeps
   falling behind the panel (says that too, matching the task's "if not
   holding, the run continues"). Resume's 3-2-1 is a purely cosmetic beat
   before hiding the panel.
5. **HUD** — score/best (existing) + Flys (`ProfileChanged`) + bugs-this-run
   (`BugCaught` count, exact) + a fading level-name toast (`LevelChanged`,
   listened to independently of `LevelClient.client.luau`). The **race rail**
   is a thin vertical strip on the right edge; every other `Player`'s
   `leaderstats.Score` is polled every 0.5s and mapped to a marker between 0
   and the highest score anyone has this session. The **top-scores board** is
   `MenuClient`'s Top Scores panel, fed by `GetTopScores`.
6. **Spectate** — `GameClient` (camera owner) adds `<`/`>` buttons, visible
   only while `runState ~= Playing`, cycling through `workspace.PlayField.Lanes`
   origins (excluding the player's own, doc 13's existing attribute contract —
   no new state needed). Snaps back to the player's own lane the instant
   `RunStateChanged` reports `Playing`.
7. **Gamepad + keyboard** — see the mapping table below. Mouse/touch
   (`tryGrab`, `InputBegan`/`InputEnded`) are **byte-for-byte unchanged** —
   every gamepad addition is new, parallel `Connect`s, never a rewrite of the
   existing handlers. `UserInputService.LastInputTypeChanged` drives an
   `InputState` Folder + `Gamepad` Attribute under `LocalPlayer` (same
   cross-LocalScript pattern `LevelClient` uses for `LevelState`), which both
   `GameClient` (cursor/glyph visibility) and `MenuClient` (hint text) read.
   Menu buttons are all `Selectable = true`; `GuiService.SelectedObject` is
   set to a sensible default whenever a panel opens while gamepad is the last
   input type, and engine default spatial navigation handles the rest.
8. **Attract mode (FrogAI)** — **skipped**, as explicitly allowed (low
   priority, "otherwise skip and say so"). The parked Menu frog just sits at
   the lane origin.

## Input mapping table

| Action | Mouse/Touch (unchanged) | Keyboard | Gamepad |
|---|---|---|---|
| Move aim | — (direct screen tap) | Arrow keys move a virtual cursor | Left thumbstick moves the virtual cursor |
| Grab (auto-assigned limb) | Tap a step | — (no keyboard grab button; arrow keys are aim-only) | `ButtonR2` or `ButtonA` — grabs the nearest own-lane step within `Config.MAX_GRAB_DISTANCE` of the cursor, reporting the step's own position as the tap point (snap-assist → always grades "Perfect") |
| Release | Input lifts | — | `ButtonL2` or `ButtonX` — releases the most-recently-grabbed limb |
| Tongue / catch bug | Tap a bug | — | `ButtonB` or `ButtonY` — targets the nearest own-lane bug automatically (no cursor precision needed) |
| Menu navigate/confirm | Click/tap | — | D-pad/stick via `GuiService.SelectedObject` default engine navigation; `ButtonA` activates |

Per the task's explicit allowance, limbs are already auto-assigned
(`getFreeSlot`), so this collapses Unity's separate left/right trigger-to-limb
mapping into one grab action + one release action rather than four buttons.

## Tool results

`stylua` (all new/edited files) and `selene src/` are clean (0 warnings).
`luau-lsp analyze` against the generated sourcemap is clean for every file
this phase touched or created (`GameServer.server.luau`, `Lane.luau`
untouched, `GameClient.client.luau`, `StoreUI.client.luau`,
`MenuClient.client.luau`, `src/client/ui/*.luau`). The only remaining
`luau-lsp` findings are in `WorldLava.client.luau`/`WorldScenery.client.luau`/
`WorldTouchIndicator.client.luau` — a different agent's concurrent,
in-progress work outside this phase's file ownership; left untouched.

## What needs a Studio playtest

- **Panel layout at extreme aspect ratios.** `UIKit.screenGui`'s `UIScale` is
  a single scalar derived from the viewport's short side; it hasn't been
  visually verified against a very tall phone or an ultrawide monitor, only
  reasoned about analytically.
- **The `pendingStart` queue's feel.** Clicking Replay/Play during the ~1.5s
  `Dead` beat should feel instant (it just waits for the server's own
  `Menu` transition), but the actual perceived latency depends on
  `Config.RESPAWN_DELAY` and hasn't been played.
- **Gamepad snap-assist range.** The virtual cursor's `CURSOR_SPEED` (20
  studs/s) and the "nearest step within `MAX_GRAB_DISTANCE`" grab target were
  chosen analytically to match the existing reach check, not tuned by feel
  with an actual controller.
- **Race rail readability with many players.** The strip maps every other
  player's score into one 0..max range; with a wide score spread (a
  brand-new player next to a long-run veteran) most markers may cluster near
  the bottom. Untested beyond 1-2 simulated players.
- **Pause panel wording/feel.** The "run keeps going" warning when not
  holding a step is correct but has an odd edge case: a player could die
  while reading the panel. That's intentional per the task's framing, but
  hasn't been played to see if it feels fair or just surprising.
- **The bugs-caught heuristic on `RunSummary`** (`amount == Config.BUG_FLYS`)
  is correct against the current `BugService`/`GiftService` amounts (5 vs.
  100) but would silently miscount if either amount is retuned later without
  updating this comment — flagged in the code, not otherwise enforced.

## What wasn't built

- **Attract mode (item 8)** — skipped per the task's explicit low-priority/
  time-box language. The parked Menu/Dead frog is static at the lane origin
  rather than idly climbing a couple of decorative steps.
