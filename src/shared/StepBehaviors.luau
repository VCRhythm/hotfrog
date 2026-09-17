-- ReplicatedStorage/Shared/StepBehaviors (ModuleScript)
-- Step behavior registry (../../docs/roblox-port/05-step-behaviors.md; ports the
-- ActionType hooks composed in Entities/Step.cs AssignInteractionAction).
--
-- Each behavior exposes optional hooks the server dispatches:
--   onGrab(ctx)    -- a limb grabbed the step (Step.Grab)
--   onRelease(ctx) -- the holder let go (Step.Release)
--   onDestroy(ctx) -- the step is being recycled (Step.Destroy)
--   onTick(ctx, dt) -- every server heartbeat while the step is active (Step.FixedUpdate)
--   canSpawn(bias, spawnCount) -- may this variant spawn given the current spawn
--     bias and how many steps this spawn loop has produced so far?
-- plus `sprite`, the Rocks art stem the spawner stamps on the step (SpriteSkin).
--
-- The ctx is built by GameServer per dispatch. Delayed effects MUST check
-- ctx.stillValid() before acting: steps are pooled, so a task.delay can outlive
-- the grab that scheduled it and fire on a recycled/respawned part.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

export type Ctx = {
	step: BasePart,
	player: Player?,
	stillValid: () -> boolean, -- still active AND same spawn generation
	makeUnsteady: () -> (), -- sets the Unsteady attribute (clients may shake/emit)
	explode: () -> (), -- knock the holder off + recycle (Step.cs Explode)
	dropAway: () -> (), -- tween down and let the lava line recycle it (Step.cs Fall)
	forceRelease: () -> (), -- make the holder's limb let go (Step.cs ForceRelease)
	getSpawnBias: () -> Vector2,
	setSpawnBias: (bias: Vector2) -> (), -- SpawnManager.SpawnDirection analog
	spawnBug: () -> (), -- wake BugService's spawn path near this step (Step.cs SpawnFly)
	flingSplash: () -> (), -- launch a physics "Flingee" off this step (Step.cs SplashFlinging)
	clearFling: () -> (), -- clean up any live Flingee this step owns (Step.cs destroyAction)
}

export type Behavior = {
	sprite: string?,
	onGrab: ((ctx: Ctx) -> ())?,
	onRelease: ((ctx: Ctx) -> ())?,
	onDestroy: ((ctx: Ctx) -> ())?,
	onTick: ((ctx: Ctx, dt: number) -> ())?,
	canSpawn: ((bias: Vector2, spawnCount: number) -> boolean)?,
}

local Behaviors: { [string]: Behavior } = {}

-- Plain step: grab sound + pull only (ActionType.None).
Behaviors.None = { sprite = "WhiteRock" }

-- Unsteady on grab, then explodes shortly after (ActionType.Crumble).
Behaviors.Crumble = {
	sprite = "CrumblyRock",
	onGrab = function(ctx)
		ctx.makeUnsteady()
		task.delay(Config.CRUMBLE_FUSE, function()
			if ctx.stillValid() then
				ctx.explode()
			end
		end)
	end,
}

-- Explodes the moment you let go (ActionType.CrumbleAfterRelease).
Behaviors.CrumbleAfterRelease = {
	sprite = "CrumblyRock",
	onRelease = function(ctx)
		ctx.explode()
	end,
}

-- Unsteady on grab; drops away after a beat whether or not you hold on
-- (ActionType.Fall).
Behaviors.Fall = {
	sprite = "SmallRock",
	onGrab = function(ctx)
		ctx.makeUnsteady()
		task.delay(Config.FALL_DELAY, function()
			if ctx.stillValid() then
				ctx.dropAway()
			end
		end)
	end,
}

-- Direction-change steps: grabbing sets the lane's spawn/scroll direction
-- (ActionType.ChangeDirection* -> SpawnManager.SpawnDirection, now Lane.spawnDirection,
-- doc 13). Left/Right/Up are pure horizontal/vertical; UpLeft/UpRight are diagonal
-- (Step.cs AssignInteractionAction). canSpawn keeps a redundant arrow from spawning
-- when the bias already points that way.
--
-- IMPORTANT naming/semantics fix vs. the literal Unity data (doc 13 item 4): a
-- lane's `spawnDirection` is the direction the WORLD/steps scroll, not the
-- direction the frog appears to travel -- those are opposites (exactly like the
-- default (0,-1) "down" scroll makes the frog *feel* like it's climbing up).
-- Unity's own shipped ActionType.ChangeDirectionUpLeft/UpRight already follow a
-- consistent "arrow art shows the frog's apparent travel, SpawnDirection is the
-- negation" rule: UpLeft (frog travels up-left, apparent travel (-1,1)) sets
-- SpawnDirection=(1,-1); UpRight (travel (1,1)) sets SpawnDirection=(-1,-1).
-- But Unity's plain ChangeDirectionLeft/Right DON'T follow that same rule -- they
-- set SpawnDirection directly equal to their own name's sign (Left -> (-1,0),
-- Right -> (1,0)), which under the unified "arrow = apparent travel" convention
-- would actually make a LeftArrow push the frog to the RIGHT (world scrolls left,
-- frog feels the opposite). That's an inconsistency in the original shipped data,
-- not a deliberate design -- Up/UpLeft/UpRight all agree on the convention, only
-- Left/Right don't. Per doc 13's explicit invitation to re-derive this now that
-- lanes make directional pull real, this port applies the UNIFIED convention
-- everywhere: ChangeDirectionLeft sets SpawnDirection=(1,0) (world scrolls right,
-- so the frog visibly heads left, matching its own arrow art) and
-- ChangeDirectionRight sets SpawnDirection=(-1,0) -- i.e. Left/Right are SWAPPED
-- from Unity's literal values, while Up/UpLeft/UpRight are unchanged. See
-- docs/roblox-port/13-levels-and-lanes.md for the full derivation.
local function isHorizontal(bias: Vector2): boolean
	return bias == Vector2.new(1, 0) or bias == Vector2.new(-1, 0)
end

Behaviors.ChangeDirectionLeft = {
	sprite = "LeftArrow",
	canSpawn = function(bias)
		return not isHorizontal(bias)
	end,
	onGrab = function(ctx)
		ctx.setSpawnBias(Vector2.new(1, 0)) -- world scrolls right so the frog appears to head left
	end,
}

Behaviors.ChangeDirectionRight = {
	sprite = "RightArrow",
	canSpawn = function(bias)
		return not isHorizontal(bias)
	end,
	onGrab = function(ctx)
		ctx.setSpawnBias(Vector2.new(-1, 0)) -- world scrolls left so the frog appears to head right
	end,
}

Behaviors.ChangeDirectionUp = {
	sprite = "UpArrow",
	canSpawn = function(bias)
		return bias ~= Vector2.new(0, -1)
	end,
	onGrab = function(ctx)
		ctx.setSpawnBias(Vector2.new(0, -1)) -- back to the default "climbing up" scroll
	end,
}

-- UpLeft/UpRight already matched the unified convention in Unity's own shipped
-- data (see the big comment above) -- kept as-is, X sign unchanged.
Behaviors.ChangeDirectionUpLeft = {
	sprite = "UpLeftArrow",
	canSpawn = function(bias)
		return bias ~= Vector2.new(1, -1)
	end,
	onGrab = function(ctx)
		ctx.setSpawnBias(Vector2.new(1, -1))
	end,
}

Behaviors.ChangeDirectionUpRight = {
	sprite = "UpRightArrow",
	canSpawn = function(bias)
		return bias ~= Vector2.new(-1, -1)
	end,
	onGrab = function(ctx)
		ctx.setSpawnBias(Vector2.new(-1, -1))
	end,
}

-- Can't be held on the first try -- it shrugs you off once, then behaves like a
-- plain step (ActionType.Beetle re-assigns grabAction after one ForceRelease).
Behaviors.Beetle = {
	sprite = "WrappedRock",
	onGrab = function(ctx)
		if ctx.step:GetAttribute("Shrugged") ~= true then
			ctx.step:SetAttribute("Shrugged", true)
			ctx.forceRelease()
		end
	end,
}

-- Constant downward drift, whether held or not (ActionType.Falling; Step.cs
-- fixedUpdate = AddForce(0,-50,Force) every physics tick). Steps here are
-- kinematic (server-moved), so this is a flat CFrame drift per tick rather than
-- a simulated force/drag curve -- close enough for a step that's about to scroll
-- off the bottom anyway. canSpawn mirrors Step.cs: it can't appear among a
-- spawner's first few steps.
Behaviors.Falling = {
	sprite = "WhiteRock", -- FallingRock reuses WhiteRock.png, tinted in Unity (doc 12)
	canSpawn = function(_bias, spawnCount)
		return spawnCount > Config.FALLING_MIN_SPAWN_COUNT
	end,
	onTick = function(ctx, dt)
		ctx.step.CFrame = ctx.step.CFrame * CFrame.new(0, -Config.FALLING_DRIFT_SPEED * dt, 0)
	end,
}

-- Grabbing wakes this step's bug: FlyRock's shipped behavior is a child Bug
-- GameObject that gets enabled on grab (ActionType.SpawnFly; Step.cs:
-- bug.GetComponent<Bug>().enabled = true). We don't keep a dormant child part --
-- ctx.spawnBug() asks BugService (the existing spawn/catch/Fly-award path, doc 06)
-- to drift a bug in from this step's position instead.
Behaviors.SpawnFly = {
	sprite = "WrappedRock", -- FlyRock's own step art (doc 12); the Bug art is BugService's
	onGrab = function(ctx)
		ctx.spawnBug()
	end,
}

-- Grabbing releases the child "Flingee" (ActionType.SplashFlinging; Step.cs:
-- splash.rb2D.isKinematic = false + splash.GetComponent<Splash>().enabled = true).
-- Splash.cs itself (read in full) is pure physics debris: OnEnable applies one
-- random-X + fixed-Y impulse and an opposing torque, then Invoke("Destroy", 3f) --
-- it never overrides OnTriggerEnter2D, so there is no on-touch damage/grip effect
-- to port; nothing is deferred here. ctx.flingSplash() spawns an unanchored part
-- with the same impulse shape and lets Debris clean it up; ctx.clearFling() on
-- destroy guards against a step recycling mid-flight leaving orphaned debris.
Behaviors.SplashFlinging = {
	sprite = "WrappedRock", -- FlingingRock's own step art (doc 12)
	onGrab = function(ctx)
		ctx.flingSplash()
	end,
	onDestroy = function(ctx)
		ctx.clearFling()
	end,
}

return Behaviors
