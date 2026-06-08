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

### Out of scope (later)

- Frog skins / customization (`UI/FrogPackages.cs`, `Store/`).
- Bugs and tongue collectible loop (`Entities/Bug.cs`, `Entities/Tongue.cs`).
- Ads and in-app purchases (`Ads/`, `Store/`).
- Local multiplayer (the original supports 2+ controllers).
- Scripted level progression / timed events
  (`Core/LevelManager.cs`, `Core/LevelEvent.cs`).
- Step `ActionType` variants beyond plain steps (crumble, fall, change-direction,
  launch, etc. — see `Entities/Step.cs`). These are noted as extension points.

> These docs are a living design reference, not a finished tutorial. Luau snippets
> are **illustrative scaffolding** meant to convey the approach — they are not a
> drop-in, complete game.
