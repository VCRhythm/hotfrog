# 03 — Core Mechanics: Roblox Implementation

System-by-system implementation guidance. Each section: (1) what the original
does (with the Unity source), (2) the Roblox approach, (3) an **illustrative**
Luau snippet. Snippets are scaffolding to convey the approach — they reference a
shared `Config` and the RemoteEvents defined below, and assume the
[Option A "plane-in-3D"](02-architecture-mapping.md#option-a--plane-in-3d-with-real-parts-recommended)
setup.

Conventions used in the snippets:

- The play plane is at `Z = 0`; gameplay vectors are 2D (`Vector2`), mapped to 3D
  as `Vector3.new(v.X, v.Y, 0)`.
- Distances/positions use **studs**; tune constants to taste (the Unity numbers
  are a starting ratio, not literal studs).

---

## Project/instance layout

A concrete Explorer hierarchy for the basic version:

```
ReplicatedStorage/
  Shared/
    Config           (ModuleScript)  -- tunables (gravity, spawn rate, plane Z)
    PullMath         (ModuleScript)  -- shared pull/scroll helpers
  Assets/
    StepTemplate     (Model/Part)    -- one step, tagged Kind="Step"
    FrogModel        (Model)         -- body + Head + LeftLimb + RightLimb
  Remotes/
    GrabStep         (RemoteEvent)   -- client → server: "I grabbed step at P"
    ReleaseStep      (RemoteEvent)   -- client → server: "I let go of limb i"
    ScoreChanged     (RemoteEvent)   -- server → client: new score / high score
    GameOver         (RemoteEvent)   -- server → client: run ended, then restart
ServerScriptService/
  GameServer         (Script)        -- spawning, pull authority, score, DataStore
StarterPlayer/StarterPlayerScripts/
  GameClient         (LocalScript)   -- input, limbs, frog gravity/visuals, camera
StarterGui/
  HUD                (ScreenGui)     -- ScoreLabel, HighScoreLabel
Workspace/
  PlayField/
    Lava             (Part)          -- bottom hazard, CollisionGroup "Lava"
    Steps            (Folder)        -- spawned/pooled steps live here
```

Shared config used throughout:

```lua
-- ReplicatedStorage/Shared/Config (ModuleScript)
return {
    PLANE_Z = 0,

    -- Frog gravity (ported ratios from Player/Frog.cs)
    GRAVITY            = 20,   -- base fall speed factor
    GRAVITY_MULT_START = 0.5,  -- resets to this on a successful grab (Bob)
    GRAVITY_ACCEL      = 0.02, -- added to the multiplier each step
    MAX_FALL_SPEED     = 60,   -- clamp; tune in studs/s

    -- Limbs (from Player/Controller.cs limbReturnPos / limbReturnTime)
    LIMB_REST = { Vector2.new(2.0, -4.0), Vector2.new(-2.0, -4.0) }, -- scaled
    LIMB_RETURN_TIME = 0.3,

    -- Grab quality buckets (sqr distance, from Controller.TouchStep)
    GRAB_PERFECT_SQR = 1.0,
    GRAB_GREAT_SQR   = 2.0, -- > great .. <= ok beyond

    -- Spawning (see StepSpawner / SpawnManager)
    SPAWN_INTERVAL = 0.6,   -- seconds between steps
    SPAWN_Y        = 25,    -- spawn above the top of view
    DESPAWN_Y      = -30,   -- recycle below this (lava line)
    SPAWN_X_RANGE  = 12,    -- horizontal spread

    -- Pull: how far the world scrolls per grab
    PULL_DISTANCE = 6,      -- studs the field moves down per successful grab
    PULL_TIME     = 0.25,   -- ease duration for one pull
}
```

---

## Frog & custom gravity

**Original:** `Player/Frog.cs` falls the frog's head with a hand-rolled loop
(`SteadilyLowerHead`): each step adds `gravityAcceleration (0.02)` to a multiplier
and translates down by `gravity * multiplier * dt`. A successful grab resets the
multiplier (`Bob`) and bobs the head up. Death triggers `Fall()`.

**Roblox:** drive the fall on `RunService.Heartbeat` (client for feel, but the
*authoritative* death check is server-side via the lava — see below). Do **not**
use `Workspace.Gravity`. On a successful grab, reset the multiplier and tween a
small upward "bob."

```lua
-- inside GameClient (LocalScript)
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Shared.Config)

local Frog = {}
Frog.root = frogModel.PrimaryPart        -- the frog's body part on the plane
Frog.gravityMult = Config.GRAVITY_MULT_START
Frog.isHolding = false                    -- true while any limb holds a step

function Frog:onGrab()
    -- mirrors Frog.Bob(): reset the fall curve and bob the head up a touch
    self.gravityMult = Config.GRAVITY_MULT_START
    local head = frogModel.Head
    TweenService:Create(head, TweenInfo.new(0.15, Enum.EasingStyle.Sine),
        { CFrame = head.CFrame * CFrame.new(0, 0.5, 0) }):Play()
end

RunService.Heartbeat:Connect(function(dt)
    if Frog.isHolding then return end     -- a held frog doesn't fall
    Frog.gravityMult += Config.GRAVITY_ACCEL
    local speed = math.min(Config.GRAVITY * Frog.gravityMult, Config.MAX_FALL_SPEED)
    local p = Frog.root.Position
    Frog.root.CFrame = CFrame.new(p.X, p.Y - speed * dt, Config.PLANE_Z)
end)
```

> Note: in the original, the frog largely stays put and the *world* moves (see the
> pull section). Here the frog falls when not holding; when holding, the pull
> scrolls the field instead. Pick one frame of reference and stay consistent —
> this doc keeps the frog near-centered and moves the steps.

---

## Limbs & grabbing

**Original:** `Player/Controller.cs` holds `limbs[2]`. `MoveLimbs()` snaps a held
limb to its step each frame and `SmoothDamp`s a free limb back to its rest pose
(`limbReturnPos`, `limbReturnTime = 0.3`). `Player/Limb.cs` tracks each limb's
free/held state and which input "touch" owns it.

**Roblox:** two limb parts; each has `heldStep` (or `nil`). On Heartbeat, held
limbs follow their step's position; free limbs lerp back to rest.

```lua
-- inside GameClient
local limbs = {
    { part = frogModel.RightLimb, rest = Config.LIMB_REST[1], heldStep = nil },
    { part = frogModel.LeftLimb,  rest = Config.LIMB_REST[2], heldStep = nil },
}

local function getFreeLimb()
    for _, limb in ipairs(limbs) do
        if not limb.heldStep then return limb end
    end
    return nil
end

local function anyLimbHolding()
    return limbs[1].heldStep ~= nil or limbs[2].heldStep ~= nil
end

local function v2to3(v2) return Vector3.new(v2.X, v2.Y, Config.PLANE_Z) end

RunService.Heartbeat:Connect(function(dt)
    for _, limb in ipairs(limbs) do
        if limb.heldStep and limb.heldStep.Parent then
            limb.part.CFrame = CFrame.new(limb.heldStep.Position)   -- follow step
        else
            limb.heldStep = nil
            local target = v2to3(limb.rest) + frogModel.PrimaryPart.Position
            local alpha = math.clamp(dt / Config.LIMB_RETURN_TIME, 0, 1)
            limb.part.CFrame = limb.part.CFrame:Lerp(CFrame.new(target), alpha)
        end
    end
    Frog.isHolding = anyLimbHolding()
end)
```

A limb releases when its input ends (mirrors `Controller.FreeUnusedTouches`):
clear `heldStep` and fire `ReleaseStep` so the server can update the held set.

---

## Input → grab

**Original:** `Controller.CheckTouch(worldPos, touchIndex)` raycasts the touched
point against the `Touchable` layer. On a hit, `DecipherTouch` routes by tag:
`"Step"` → `TouchStep` (assign a free limb, score grab quality), `"Bug"`/scenery
otherwise. A miss plays `missSound` and moves a free limb toward the point.

**Roblox:** unify touch + mouse via `UserInputService`. Convert the screen point
to a ray, raycast against steps (filtered by CollisionGroup/tag), and on a hit
assign a free limb + fire `GrabStep` to the server.

```lua
-- inside GameClient
local UserInputService = game:GetService("UserInputService")
local camera = workspace.CurrentCamera
local GrabStep = ReplicatedStorage.Remotes.GrabStep

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { workspace.PlayField.Steps }

local function gradeGrab(worldPoint, step)
    -- mirrors Controller.TouchStep distance bucketing
    local d2 = (Vector2.new(worldPoint.X, worldPoint.Y)
              - Vector2.new(step.Position.X, step.Position.Y)).Magnitude ^ 2
    if d2 <= Config.GRAB_PERFECT_SQR then return "Perfect"
    elseif d2 <= Config.GRAB_GREAT_SQR then return "Great"
    else return "OK" end
end

local function tryGrab(screenPos)
    local limb = getFreeLimb()
    if not limb then return end

    local unitRay = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
    local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, rayParams)

    if result and result.Instance:GetAttribute("Kind") == "Step" then
        local step = result.Instance
        limb.heldStep = step
        Frog:onGrab()
        local quality = gradeGrab(result.Position, step)
        GrabStep:FireServer(step, quality)        -- server validates + scores + pulls
    else
        -- miss: nudge a free limb toward the point, play miss feedback
        -- (Audio handled by a small client audio module; see 02 mapping)
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        tryGrab(input.Position)
    end
end)
```

> Multi-touch: `InputBegan` fires once per finger, so two fingers naturally map to
> two `tryGrab` calls → the two free limbs. This reproduces the original's
> two-limb multi-touch with no extra bookkeeping for the MVP.

---

## Steps & spawning

**Original:** `Spawning/StepSpawner.cs` (a `Spawner`) instantiates steps on a
cadence; `Spawning/ObjectPool.cs` recycles them; `Entities/Step.cs` configures
per-step behavior on enable. `SpawnManager.SpawnDirection` biases where new steps
come from.

**Roblox:** a server `Script` clones `StepTemplate` from a pool on a timer, places
it above the view with some horizontal spread, tags it, and recycles steps that
fall past the despawn line.

```lua
-- inside GameServer (Script) -- spawning + pool
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local template = ReplicatedStorage.Assets.StepTemplate
local container = workspace.PlayField.Steps

local pool, active = {}, {}

local function acquire()
    local step = table.remove(pool) or template:Clone()
    step:SetAttribute("Kind", "Step")
    step.Anchored = true                       -- kinematic; we move it ourselves
    step.Parent = container
    return step
end

local function release(step)
    step.Parent = nil
    table.insert(pool, step)
    active[step] = nil
end

task.spawn(function()
    while true do
        local step = acquire()
        local x = math.random(-Config.SPAWN_X_RANGE, Config.SPAWN_X_RANGE)
        step.CFrame = CFrame.new(x, Config.SPAWN_Y, Config.PLANE_Z)
        active[step] = true
        task.wait(Config.SPAWN_INTERVAL)
    end
end)

-- recycle steps that fall below the lava line
game:GetService("RunService").Heartbeat:Connect(function()
    for step in pairs(active) do
        if step.Position.Y < Config.DESPAWN_Y then release(step) end
    end
end)
```

> The `ActionType` variants from `Step.cs` (crumble, fall, change-direction, ...)
> are an extension point: give each step an optional `Behavior` attribute and a
> small behavior `ModuleScript` invoked on grab/release. Not needed for MVP.

---

## The pull / world-scroll mechanic

**This is the crux.** **Original:** grabbing a step calls `Step.Pull()` →
`SpawnManager.PullStep(...)`, and `SpawnManager` applies a `PullVector` to **all
active spawns** each `FixedUpdate`. Net effect: the field of steps slides relative
to the (roughly centered) frog, so grabbing = climbing.

**Roblox — two equivalent framings:**

- **(a) Move the field down, frog ~fixed (recommended).** On a validated grab, the
  server scrolls every active step down by `PULL_DISTANCE`. The frog stays
  centered; the camera is static. This matches `SpawnManager` moving all spawns,
  and keeps the camera trivial.
- **(b) Move the camera/frog up.** Leave steps in world space and translate the
  camera + frog upward. Simpler conceptually but you then chase the frog with the
  camera and steps accumulate in world space (more cleanup).

Use **(a)**. The server owns the pull so score and world state stay consistent.

```lua
-- inside GameServer -- authoritative pull, triggered by a validated grab
local TweenService = game:GetService("TweenService")
local GrabStep = ReplicatedStorage.Remotes.GrabStep

local function scrollFieldDown(distance, duration)
    for step in pairs(active) do
        local target = step.CFrame * CFrame.new(0, -distance, 0)
        TweenService:Create(step, TweenInfo.new(duration, Enum.EasingStyle.Sine),
            { CFrame = target }):Play()
    end
end

GrabStep.OnServerEvent:Connect(function(player, step, quality)
    -- validate: real step, still active, within reach of this player's frog
    if not step or not active[step] then return end
    -- (basic reach check omitted for brevity; compare step.Position to frog)

    scrollFieldDown(Config.PULL_DISTANCE, Config.PULL_TIME)
    addScore(player, 1, quality)               -- one step climbed (see scoring)
end)
```

> Faithfulness note: the original applies a continuous `PullVector` in
> `FixedUpdate` while a step is "pulled" (with `Invoke("StopPull", 1f)` ending it).
> The tween-per-grab above is a discrete approximation that's much simpler and
> reads the same. If you want the continuous feel, replace the tween with a
> `PreSimulation` loop that integrates a pull velocity while a grab is active and
> decays it — that's the literal port of `SpawnManager.PullVector`.

---

## Lava & lose condition

**Original:** `Entities/Lava.cs` is the bottom hazard; steps tagged `BottomNet`
get destroyed on contact (`Step.OnTriggerEnter2D`), and the frog falling to the
bottom ends the run (`Frog.Fall` / `EndLevel`). Restart re-rises the frog.

**Roblox:** a `Lava` part at the bottom. Authoritatively detect the frog crossing
the lava line on the server (don't trust the client), fire `GameOver`, then reset.

```lua
-- inside GameServer
local GameOver = ReplicatedStorage.Remotes.GameOver
local LAVA_Y = Config.DESPAWN_Y

local function endRun(player)
    GameOver:FireClient(player)                -- client plays fall + restart anim
    commitHighScore(player)                    -- see scoring
    resetScore(player)
    -- respawn/re-rise the frog (mirrors Frog.Rise on restart)
end

-- the server tracks each player's frog position (replicated from client, or
-- server-owned); when it crosses the lava line, end the run.
game:GetService("RunService").Heartbeat:Connect(function()
    for player, frog in pairs(activeFrogs) do
        if frog.Position.Y <= LAVA_Y then
            endRun(player)
        end
    end
end)
```

> Steps that reach the lava are simply recycled by the spawner's despawn check
> (above), which is the Roblox analog of the `BottomNet` destruction in
> `Step.OnTriggerEnter2D`.

---

## Scoring & HUD

**Original:** `Core/VariableManager.cs` tracks steps climbed (primary score) and
the persistent high score (`PlayerPrefs`); `UI/HUD.cs` shows the live counter and
fires feedback at milestones.

**Roblox:** keep score on the server, push changes to the client via
`ScoreChanged`, render with a `ScreenGui`, and persist the high score with
`DataStoreService`.

```lua
-- inside GameServer -- scoring + persistence
local DataStoreService = game:GetService("DataStoreService")
local highScores = DataStoreService:GetDataStore("HotfrogHighScores")
local ScoreChanged = ReplicatedStorage.Remotes.ScoreChanged

local sessionScore, sessionBest = {}, {}

local function addScore(player, amount, quality)
    sessionScore[player] = (sessionScore[player] or 0) + amount
    ScoreChanged:FireClient(player, sessionScore[player], sessionBest[player], quality)
end

local function resetScore(player)
    sessionScore[player] = 0
    ScoreChanged:FireClient(player, 0, sessionBest[player])
end

local function commitHighScore(player)
    local score = sessionScore[player] or 0
    if score > (sessionBest[player] or 0) then
        sessionBest[player] = score
        local key = "u_" .. player.UserId
        pcall(function()
            highScores:UpdateAsync(key, function(old)
                return math.max(old or 0, score)
            end)
        end)
    end
end

game.Players.PlayerAdded:Connect(function(player)
    local key = "u_" .. player.UserId
    local ok, best = pcall(function() return highScores:GetAsync(key) end)
    sessionBest[player] = (ok and best) or 0
    sessionScore[player] = 0
    ScoreChanged:FireClient(player, 0, sessionBest[player])
end)
```

```lua
-- inside GameClient -- HUD update
local ScoreChanged = ReplicatedStorage.Remotes.ScoreChanged
local hud = playerGui:WaitForChild("HUD")

ScoreChanged.OnClientEvent:Connect(function(score, best, quality)
    hud.ScoreLabel.Text = tostring(score)
    hud.HighScoreLabel.Text = "Best: " .. tostring(best or 0)
    -- optional: flash/sound on a new best or a "Perfect" grab (mirrors HUD.cs)
end)
```

---

Next: build it in order — see
**[04-build-roadmap.md](04-build-roadmap.md)** for milestones and how to verify
each in Roblox Studio.
