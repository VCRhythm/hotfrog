# 06 — Bugs & Tongue (the collectible loop)

> Extension on top of the basic loop. Read
> [03-core-mechanics.md](03-core-mechanics.md) first. This reuses the spawner /
> pool pattern and adds two remotes.

Bugs are the secondary objective: flies drift across the screen, and tapping one
fires the frog's **tongue** to catch it for a bonus. Sources:

- `Entities/Bug.cs` — a `Spawn` that tweens to a random on-screen point
  (`DOMove(..., OutBack)`), waits `lifeSpan`, then `Leave()`s off-screen; tapping
  it triggers `CollectFly` (or `StartGame` for the special first bug). `MakeTame`
  makes a bug follow its owner.
- `Entities/Tongue.cs` — on `Expand(target)`, grows toward the target each
  `FixedUpdate`; when it reaches, runs `catchAction` (default: destroy the bug +
  squish sound), then retracts.
- `Spawning/BugSpawner.cs` — spawns bugs on a 2s cadence; `SpawnFlyBundle` spawns
  a burst of *tamed* bugs for a reward moment.

## Roblox shape

| Original | Roblox |
|---|---|
| `BugSpawner` cadence + pool | a server spawner like the step spawner, separate `Bugs` folder + pool |
| `Bug.SetUpDestination` / `MoveTo` (`DOMove OutBack`) | `TweenService` move to a random point, `Enum.EasingStyle.Back`, `EasingDirection.Out` |
| `Bug.Leave()` after `lifeSpan` | `task.delay` → tween off-screen, then recycle |
| tap a bug (`Controller.TouchBug` → `Bug.Grab`) | client raycast hits a `Kind == "Bug"` part → `CatchBug:FireServer(bug)` |
| `Tongue.Expand` visual | client-side tongue part that scales toward the bug, then retracts |
| `CollectFly` / score | server validates the catch, awards a bonus, destroys the bug, fires `BugCaught` |
| `MakeTame` / `SpawnFlyBundle` | optional: server marks bugs `Owner = userId`, they home to that player |

Two new remotes: `CatchBug` (client → server) and `BugCaught` (server → client,
for the catch sound / bonus popup).

## Server: bug spawner + catch

Mirrors `BugSpawner.cs` (cadence, pool) and `Bug.cs` (move → wait → leave).

```lua
-- inside GameServer (or a sibling BugServer Script)
local bugTemplate = ReplicatedStorage.Assets.BugTemplate
local bugContainer = workspace.PlayField.Bugs
local CatchBug = ensureRemote("CatchBug")
local BugCaught = ensureRemote("BugCaught")

local bugPool, bugsActive = {}, {}
local BUG_INTERVAL, BUG_LIFESPAN = 2.0, 2.0
local FIELD_X, FIELD_Y = 18, 12

local function releaseBug(bug)
	bugsActive[bug] = nil
	bug.Parent = nil
	table.insert(bugPool, bug)
end

local function spawnBug()
	local bug = table.remove(bugPool) or bugTemplate:Clone()
	bug:SetAttribute("Kind", "Bug")
	bug.Anchored = true
	bug.Parent = bugContainer
	bugsActive[bug] = true

	-- enter from an edge, drift to a random on-screen point (Bug.SetUpDestination)
	bug.CFrame = CFrame.new(-FIELD_X - 5, math.random(-FIELD_Y, FIELD_Y), 0)
	local dest = Vector3.new(math.random(-FIELD_X, FIELD_X), math.random(-FIELD_Y, FIELD_Y), 0)
	TweenService:Create(bug, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(dest),
	}):Play()

	-- after its lifespan, leave (Bug.Leave) unless already caught
	task.delay(BUG_LIFESPAN + 0.8, function()
		if bugsActive[bug] then
			local exitX = (math.random() > 0.5 and 1 or -1) * (FIELD_X + 10)
			local t = TweenService:Create(bug, TweenInfo.new(1.0), { CFrame = CFrame.new(exitX, 0, 0) })
			t.Completed:Once(function()
				if bugsActive[bug] then releaseBug(bug) end
			end)
			t:Play()
		end
	end)
end

task.spawn(function()
	while true do
		spawnBug()
		task.wait(BUG_INTERVAL)
	end
end)

CatchBug.OnServerEvent:Connect(function(player, bug)
	if typeof(bug) ~= "Instance" or not bugsActive[bug] then return end -- validate
	bugsActive[bug] = nil
	releaseBug(bug)
	addScore(player, 5, "Bug") -- bonus value; reuse the scoring from GameServer
	BugCaught:FireClient(player, bug.Position) -- client plays tongue/squish at point
end)
```

## Client: tap a bug + tongue visual

Extend the client raycast (it already branches on the `Kind` attribute) and add a
tongue that scales toward the target, mirroring `Tongue.Expand`/`FixedUpdate`.

```lua
-- in GameClient, inside tryGrab() after the raycast result:
if result and result.Instance:GetAttribute("Kind") == "Bug" then
	CatchBug:FireServer(result.Instance)
	expandTongue(result.Position) -- local visual; server is authoritative on the catch
	return
end
```

```lua
-- a minimal tongue: a thin part anchored at the frog head, scaled toward target
local head = frog:FindFirstChild("Head")
local function expandTongue(targetPos)
	local tongue = ReplicatedStorage.Assets.Tongue:Clone()
	tongue.Anchored = true
	tongue.Parent = workspace
	local from = head.Position
	local dir = targetPos - from
	local length = dir.Magnitude
	-- orient + stretch from head to target (grow), then shrink back (retract)
	local mid = from + dir * 0.5
	tongue.CFrame = CFrame.lookAt(mid, targetPos)
	local grow = TweenService:Create(tongue, TweenInfo.new(0.12), {
		Size = Vector3.new(tongue.Size.X, tongue.Size.Y, length),
	})
	grow.Completed:Once(function()
		local shrink = TweenService:Create(tongue, TweenInfo.new(0.18), {
			Size = Vector3.new(tongue.Size.X, tongue.Size.Y, 0.1),
		})
		shrink.Completed:Once(function() tongue:Destroy() end)
		shrink:Play()
	end)
	tongue.Size = Vector3.new(tongue.Size.X, tongue.Size.Y, 0.1)
	grow:Play()
end
```

> `Tongue.cs` runs `catchAction` exactly when the tongue *reaches* the target and
> defaults to destroying the bug. Here the server is authoritative on the catch
> (it validates and removes the bug), and the tongue is a client visual triggered
> at tap time — so a missed/contested bug simply won't score even though the
> tongue animates. That keeps it exploit-resistant; see
> [07-multiplayer.md](07-multiplayer.md).

## Optional: tame bugs & bundles

`Bug.MakeTame` + `BugSpawner.SpawnFlyBundle` spawn a burst of bugs that home to
the owning player (a reward flourish). Port later: tag bugs with an `Owner`
attribute and, in the bug's Heartbeat, steer toward that player's frog instead of
a fixed destination. Not needed for the core collectible loop.

## Milestones

1. Bug spawner + pool; bugs drift in, idle, and leave. *Verify: bugs appear,
   wander, and recycle (bounded `Bugs` folder count).*
2. Tap-to-catch: client fires `CatchBug`, server validates + scores, bug vanishes.
   *Verify: tapping a bug removes it and the score jumps by the bonus.*
3. Tongue visual on catch. *Verify: tongue stretches to the bug and retracts.*
4. (Optional) tame bugs / bundles as a reward beat.
