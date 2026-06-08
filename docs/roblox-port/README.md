# Hotfrog → Roblox Port

This folder documents how to port a **basic but faithful** version of Hotfrog to
[Roblox](https://create.roblox.com/) using Luau and Roblox Studio.

Hotfrog (the original) is a Unity (C#) 2D physics game: you control a frog that
hangs from continuously-spawning **steps** (floating stones) using **two
independently grabbing limbs**. Grabbing a step "pulls" the whole field of steps
so the frog climbs upward; letting go drops the frog under a custom gravity curve.
Fall to the bottom (lava) and the run ends. Your score is the number of steps
climbed.

The "basic version" documented here is the **core gameplay loop only** — enough to
get a recognizable, playable Hotfrog running in Roblox. Cosmetic and
live-ops systems are intentionally deferred (see scope below).

## How to read this

Read in order:

1. **[01-game-overview.md](01-game-overview.md)** — what the game is and the
   non-obvious mechanics that define its feel.
2. **[02-architecture-mapping.md](02-architecture-mapping.md)** — how Unity
   concepts map to Roblox, and the key "2D-in-3D" + client/server decisions.
3. **[03-core-mechanics.md](03-core-mechanics.md)** — system-by-system Roblox
   implementation with illustrative Luau snippets.
4. **[04-build-roadmap.md](04-build-roadmap.md)** — ordered, independently
   testable milestones for building it in Studio.

Then the **[scripts/](scripts/)** folder has ready-to-paste Luau (`Config`,
`PullMath`, `GameServer`, `GameClient`) implementing the basic loop end to end.

### Extensions (beyond the basic version)

These layer on top of the core loop once it's solid:

5. **[05-step-behaviors.md](05-step-behaviors.md)** — porting the step
   `ActionType` variants (crumble, fall, change-direction, …) as behavior modules.
6. **[06-bugs-and-tongue.md](06-bugs-and-tongue.md)** — the bug + tongue
   collectible loop.
7. **[07-multiplayer.md](07-multiplayer.md)** — networked multiplayer and the
   server-authority hardening it requires.
8. **[08-frog-skins-and-store.md](08-frog-skins-and-store.md)** — frog skins,
   ownership/currency persistence, and monetization (Game Passes + products).
9. **[09-gifts-and-ads.md](09-gifts-and-ads.md)** — the free-currency faucets:
   timed gifts, and how the ad reward maps (or doesn't) to Roblox.

Throughout, each Roblox system is cross-referenced to the original Unity source
file (e.g. `Player/Frog.cs`) so contributors can trace behavior back to the
original.

## Scope

### In scope (the "basic version")

- Frog character with **custom gravity** (not engine gravity).
- **Two independent limbs** that grab and hold steps; multi-input.
- Tap/click **input → grab** resolution, with grab-quality feedback.
- Continuously **spawning steps** with pooling.
- The **pull / world-scroll** mechanic (grabbing climbs the world).
- **Lava** bottom hazard and lose condition + run restart.
- **Step-count scoring**, HUD, and persistent high score.

### Beyond the basic version

These are out of the *core loop* but now have (or will have) their own docs:

- Step `ActionType` variants beyond plain steps → **[05](05-step-behaviors.md)**.
- Bugs and tongue collectible loop → **[06](06-bugs-and-tongue.md)**.
- Networked multiplayer + authority hardening → **[07](07-multiplayer.md)**.
- Frog skins, currency & store/monetization → **[08](08-frog-skins-and-store.md)**.
- Free-currency faucets (gifts & ads) → **[09](09-gifts-and-ads.md)**.

Deliberately not covered:

- Scripted level progression / timed events
  (`Core/LevelManager.cs`, `Core/LevelEvent.cs`) — the original's authored campaign
  is out of scope for this port effort.

> These docs are a living design reference, not a finished tutorial. Luau snippets
> are **illustrative scaffolding** meant to convey the approach — they are not a
> drop-in, complete game.
