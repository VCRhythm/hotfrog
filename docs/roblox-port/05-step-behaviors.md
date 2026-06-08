# 05 — Step Behaviors (ActionType variants)

> Extension on top of the basic loop. Read
> [03-core-mechanics.md](03-core-mechanics.md) first — this assumes the step
> spawner, pool, and the `GrabStep` / `ReleaseStep` remotes from the
> [reference scripts](10-implementation-setup.md).

In the original, a step is not always a plain platform. `Entities/Step.cs` defines
an `ActionType` enum (~20 values) and, in `AssignInteractionAction()`, composes
three `System.Action` hooks per step:

- `grabAction` — runs when a limb grabs the step (`Step.Grab`).
- `releaseAction` — runs when the step is released (`Step.Release`).
- `destroyAction` — runs on despawn/cleanup (`Step.Destroy`).
- plus `canBeSpawned(spawnCount)` — gates whether this variant may spawn now.

The plain step (`ActionType.None`) just plays a grab sound and pulls. Everything
else *adds* behavior onto those hooks. That composition model ports cleanly.

## Roblox approach: behavior modules keyed by attribute

Give each step a `Behavior` string attribute (default `"None"`), and keep a
registry of behavior modules on the **server** (steps are server-owned). Each
module exposes optional `onGrab`, `onRelease`, `onDestroy`, and `canSpawn`
functions — the direct analog of the Unity action hooks.

```lua
-- ReplicatedStorage/Shared/StepBehaviors (ModuleScript)
-- A registry: behaviorName -> { onGrab?, onRelease?, onDestroy?, canSpawn? }
-- Each callback receives a small `ctx` the server passes in (step, player,
-- the spawner, helpers like SpawnCrumbles / setSpawnBias).
local Behaviors = {}

Behaviors.None = {} -- plain step: nothing extra

-- Crumble: on grab, get unsteady, then explode shortly after (Step.cs Crumble)
Behaviors.Crumble = {
	onGrab = function(ctx)
		ctx.makeUnsteady(ctx.step, false, 0.5) -- shake, no fall
		task.delay(1.5, function()
			ctx.explode(ctx.step) -- pebbles + short crumble sound + destroy
		end)
	end,
}

-- CrumbleAfterRelease: explodes the moment you let go (Step.cs CrumbleAfterRelease)
Behaviors.CrumbleAfterRelease = {
	onRelease = function(ctx)
		ctx.explode(ctx.step)
	end,
}

-- Fall: gets unsteady on grab, then drops away after a beat (Step.cs Fall)
Behaviors.Fall = {
	onGrab = function(ctx)
		ctx.makeUnsteady(ctx.step, true, 1.0) -- true = will fall
		task.delay(3.0, function()
			if ctx.isUnsteady(ctx.step) then
				ctx.dropAway(ctx.step) -- tween down ~100 studs then recycle
			end
		end)
	end,
}

-- ChangeDirectionRight: grabbing biases where new steps come from
-- (Step.cs ChangeDirection* -> SpawnManager.SpawnDirection)
Behaviors.ChangeDirectionRight = {
	canSpawn = function(ctx) return ctx.spawnBias.X <= 0 end, -- mirrors canBeSpawned gating
	onGrab = function(ctx) ctx.setSpawnBias(Vector2.new(1, -1)) end,
}

-- Beetle: can't actually be held -- it shrugs you off once (Step.cs Beetle)
Behaviors.Beetle = {
	onGrab = function(ctx)
		ctx.forceRelease(ctx.step) -- immediately knock the limb free
	end,
}

return Behaviors
```

## Wiring it into the server

The reference [`GameServer.server.lua`](../../src/server/GameServer.server.luau) already has
the hook points. Extend its handlers to dispatch through the registry:

```lua
local Behaviors = require(ReplicatedStorage.Shared.StepBehaviors)

local function behaviorOf(step)
	return Behaviors[step:GetAttribute("Behavior") or "None"] or Behaviors.None
end

-- build the ctx of helpers once (explode, makeUnsteady, dropAway, forceRelease,
-- setSpawnBias, isUnsteady) -- these wrap the pool + spawner you already have.

GrabStep.OnServerEvent:Connect(function(player, step, quality, frogPos)
	-- ... existing validation, scrollFieldDown, addScore ...
	local b = behaviorOf(step)
	if b.onGrab then b.onGrab(makeCtx(step, player)) end
end)

ReleaseStep.OnServerEvent:Connect(function(player, limbIndex, step)
	local b = step and behaviorOf(step)
	if b and b.onRelease then b.onRelease(makeCtx(step, player)) end
end)
```

And gate spawning on `canSpawn` (mirrors `Step.canBeSpawned`): when the spawner
picks a behavior for the next step, skip variants whose `canSpawn(ctx)` is false.

## Helpers to implement (the `ctx`)

These are the Roblox versions of the private methods in `Step.cs`:

| Unity (`Step.cs`) | Roblox helper | Notes |
|---|---|---|
| `MakeUnsteady` + `ShowCrumbles` | `makeUnsteady(step, canFall, delay)` | set an `Unsteady` attribute, start a shake tween + periodic pebble emit |
| `Explode` / `SpawnCrumbles` | `explode(step)` | emit `Pebble` parts (own small pool), sound, then `releaseStep` |
| `Fall` coroutine | `dropAway(step)` | `TweenService` the step down ~100 studs, then recycle |
| `ForceRelease` | `forceRelease(step)` | tell the owning client to drop that limb (a `ForceRelease` RemoteEvent) |
| `SpawnManager.SpawnDirection` | `setSpawnBias(v2)` / `ctx.spawnBias` | the spawner reads this to bias new step X (and optional Y) |
| `IsUnsteady` | `isUnsteady(step)` | read the `Unsteady` attribute |

`Pebble` (the crumble debris in `Entities/Pebble.cs`) becomes a tiny pooled part
that you unanchor and let fall, or tween — cosmetic, client-side is fine.

## Mapping the full enum

| `ActionType` | Port summary |
|---|---|
| `None` | plain step (basic loop) |
| `Crumble` | unsteady on grab → explode after ~1.5s |
| `CrumbleAfterRelease` | explode on release |
| `Fall` | unsteady on grab → drop away after ~3s |
| `ChangeDirectionUp/Left/Right/UpLeft/UpRight` | set spawn bias on grab; `canSpawn` gates redundant changes |
| `Launch` | on grab, fling the frog/limb (apply an impulse / scripted hop) |
| `SlideOff` | step drifts sideways while held |
| `RiseAndFall` / `Move` | scripted position tween loop while active |
| `Beetle` | rejects the grab once (force-release) |
| `Castle` | spawn-bias variant based on position (`SetSpawnDirectionBasedOnCastlePosition`) |
| `PullByLocation` | set spawn bias from the step's own X/Y on grab |
| `Falling` | continuous downward force while active; `canSpawn` only after some progress |
| `SplashFlinging` / `StepFlinging` / `SpawnFly` | enable a child object on grab (a splash, a sub-step, or a bug) |
| `Helper` / `MakeFunky` / `MakeTarget` | misc one-offs; port last |

Start with `Crumble`, `Fall`, and one `ChangeDirection` — they cover the three
hook types (grab, timed, spawn-bias) and prove the registry end to end. Add a
`Behavior` attribute to authored step variants (or have the spawner roll one
randomly with weights) and verify each in isolation following the
[roadmap](04-build-roadmap.md) milestone style.
