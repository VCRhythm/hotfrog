-- ReplicatedStorage/Shared/StepBehaviors (ModuleScript)
-- Step behavior registry (../../docs/roblox-port/05-step-behaviors.md; ports the
-- ActionType hooks composed in Entities/Step.cs AssignInteractionAction).
--
-- Each behavior exposes optional hooks the server dispatches:
--   onGrab(ctx)    -- a limb grabbed the step (Step.Grab)
--   onRelease(ctx) -- the holder let go (Step.Release)
--   onDestroy(ctx) -- the step is being recycled (Step.Destroy)
--   canSpawn(bias) -- may this variant spawn given the current spawn bias?
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
}

export type Behavior = {
	sprite: string?,
	onGrab: ((ctx: Ctx) -> ())?,
	onRelease: ((ctx: Ctx) -> ())?,
	onDestroy: ((ctx: Ctx) -> ())?,
	canSpawn: ((bias: Vector2) -> boolean)?,
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

-- Direction-change steps: grabbing biases where new steps spawn from
-- (ActionType.ChangeDirection* -> SpawnManager.SpawnDirection). canSpawn keeps a
-- redundant arrow from spawning when the bias already points that way.
Behaviors.ChangeDirectionLeft = {
	sprite = "LeftArrow",
	canSpawn = function(bias)
		return bias.X >= 0
	end,
	onGrab = function(ctx)
		ctx.setSpawnBias(Vector2.new(-1, -1))
	end,
}

Behaviors.ChangeDirectionRight = {
	sprite = "RightArrow",
	canSpawn = function(bias)
		return bias.X <= 0
	end,
	onGrab = function(ctx)
		ctx.setSpawnBias(Vector2.new(1, -1))
	end,
}

Behaviors.ChangeDirectionUp = {
	sprite = "UpArrow",
	canSpawn = function(bias)
		return bias.X ~= 0
	end,
	onGrab = function(ctx)
		ctx.setSpawnBias(Vector2.new(0, -1))
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

return Behaviors
