--!strict
-- ReplicatedStorage/Shared/StepBehaviors (ModuleScript)
-- Step behavior registry (../../docs/roblox-port/05-step-behaviors.md; ports the
-- ActionType hooks composed in Entities/Step.cs AssignInteractionAction).
--
-- Each behavior exposes optional hooks the server dispatches:
--   onGrab(ctx)    -- a limb grabbed the step (Step.Grab)
--   onRelease(ctx) -- the holder let go (Step.Release)
--   onDestroy(ctx) -- the step is being recycled (Step.Destroy)
--   onTick(ctx, dt) -- every server heartbeat while the step is active (Step.FixedUpdate)
--   onSpawn(ctx)   -- the step was just taken out of the pool (Step.OnEnable):
--     roll per-step state, set a starting offset
--   canSpawn(bias, spawnCount) -- may this variant spawn given the current spawn
--     bias and how many steps this spawn loop has produced so far?
--   sweep(params)  -- how far (studs, half-extent per axis) the behaviour may
--     carry the step from its base; Lane.clearSpot reserves it (see "Moving
--     steps" below)
-- A step's art is its kind's (Shared/StepKinds `sprite`), not the behaviour's.
--
-- GameServer builds ONE ctx per live step, the first time a hook needs it, and
-- reuses it for that step's whole life (it used to allocate one per dispatch,
-- i.e. per ticking step per frame). Delayed effects MUST check ctx.stillValid()
-- before acting: steps are pooled, so a task.delay can outlive the grab that
-- scheduled it and fire on a recycled/respawned part.
--
-- A step never writes its own CFrame. Its position is a logical BASE (what
-- pulls, drift and spawn spacing work on) plus a bounded visual OFFSET, composed
-- by GameServer's step motion layer once per Heartbeat; behaviours move a step
-- through ctx.moveBase / ctx.setOffset / ctx.dropAway only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

-- Per-spawn parameters (GameServer.acquireStep's `opts.params`), read by the
-- behaviour that owns the step; each behaviour documents its own keys.
export type Params = { [string]: any }

export type Ctx = {
	step: BasePart,
	player: Player?,
	origin: Vector3, -- the lane's origin (camera centre); lane-relative = world - origin
	-- Scratch table owned by the behaviour, fresh (empty) every time the part is
	-- acquired from the pool, so nothing leaks from the part's previous life.
	state: { [string]: any },
	params: Params, -- this spawn's parameters; empty when the spawner passed none. Read-only.
	stillValid: () -> boolean, -- still active AND same spawn generation
	isHeld: () -> boolean, -- is a limb of the lane's frog on this step right now?
	makeUnsteady: () -> (), -- sets the Unsteady attribute (clients may shake/emit)
	explode: () -> (), -- knock the holder off + recycle (Step.cs Explode)
	dropAway: () -> (), -- knock the holder off, then accelerate down until the lava line recycles it (Step.cs Fall)
	forceRelease: () -> (), -- make the holder's limb let go (Step.cs ForceRelease)
	getSpawnBias: () -> Vector2, -- the lane's spawn direction: the way the WORLD scrolls
	setSpawnBias: (bias: Vector2) -> (), -- SpawnManager.SpawnDirection analog
	getStreakSpeed: () -> number, -- Normal-mode combo speed multiplier (1 in Classic / no streak)
	getRunSteps: () -> number, -- steps the lane's frog has climbed this run (its height / difficulty)
	getBase: () -> Vector3, -- the step's logical world position, without any visual offset
	moveBase: (delta: Vector3) -> (), -- shift the logical position (world space); spawn spacing and pull aim follow
	-- Set the behaviour's visual offset from the base (world space, capped at
	-- Config.STEP_OFFSET_MAX). It persists until set again and is part of the
	-- replicated CFrame, so taps and a held limb follow it.
	setOffset: (offset: Vector3) -> (),
	-- Ask the lane for an extra pull of `distance` studs along its spawn
	-- direction (each request capped at Config.PULL_MAX_DISTANCE), spawner time
	-- included, exactly like a grab's own pull. Adds to whatever is playing.
	requestExtraPull: (distance: number) -> (),
	spawnBug: () -> (), -- wake BugService's spawn path near this step (Step.cs SpawnFly)
	flingSplash: () -> (), -- launch a physics "Flingee" off this step (Step.cs SplashFlinging)
	clearFling: () -> (), -- clean up any live Flingee this step owns (Step.cs destroyAction)
}

export type Behavior = {
	onGrab: ((ctx: Ctx) -> ())?,
	onRelease: ((ctx: Ctx) -> ())?,
	onDestroy: ((ctx: Ctx) -> ())?,
	onTick: ((ctx: Ctx, dt: number) -> ())?,
	onSpawn: ((ctx: Ctx) -> ())?,
	canSpawn: ((bias: Vector2, spawnCount: number) -> boolean)?,
	sweep: ((params: Params?) -> Vector2)?,
}

local Behaviors: { [string]: Behavior } = {}

-- Plain step: grab sound + pull only (ActionType.None).
Behaviors.None = {}

-- Unsteady on grab, then explodes shortly after (ActionType.Crumble).
Behaviors.Crumble = {
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
	onRelease = function(ctx)
		ctx.explode()
	end,
}

-- Unsteady on grab; drops away after a beat whether or not you hold on
-- (ActionType.Fall).
Behaviors.Fall = {
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
	canSpawn = function(bias)
		return not isHorizontal(bias)
	end,
	onGrab = function(ctx)
		ctx.setSpawnBias(Vector2.new(1, 0)) -- world scrolls right so the frog appears to head left
	end,
}

Behaviors.ChangeDirectionRight = {
	canSpawn = function(bias)
		return not isHorizontal(bias)
	end,
	onGrab = function(ctx)
		ctx.setSpawnBias(Vector2.new(-1, 0)) -- world scrolls left so the frog appears to head right
	end,
}

Behaviors.ChangeDirectionUp = {
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
	canSpawn = function(bias)
		return bias ~= Vector2.new(1, -1)
	end,
	onGrab = function(ctx)
		ctx.setSpawnBias(Vector2.new(1, -1))
	end,
}

Behaviors.ChangeDirectionUpRight = {
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
	onGrab = function(ctx)
		if ctx.step:GetAttribute("Shrugged") ~= true then
			ctx.step:SetAttribute("Shrugged", true)
			ctx.forceRelease()
		end
	end,
}

-- Constant downward drift, whether held or not (ActionType.Falling; Step.cs
-- fixedUpdate = AddForce(0,-50,Force) every physics tick). Steps here are
-- kinematic (server-moved), so this is a flat drift of the step's base per tick
-- rather than a simulated force/drag curve -- close enough for a step that's
-- about to scroll off the bottom anyway. canSpawn mirrors Step.cs: it can't
-- appear among a spawner's first few steps.
Behaviors.Falling = {
	canSpawn = function(_bias, spawnCount)
		return spawnCount > Config.FALLING_MIN_SPAWN_COUNT
	end,
	onTick = function(ctx, dt)
		-- The base, not the visual offset: this is real travel, so where the step
		-- will rest (spawn spacing, the recycle bound) has to follow it. World
		-- space, so an idly spinning step (Config.STEP_SPIN_*, doc 17) still
		-- falls straight down.
		ctx.moveBase(Vector3.new(0, -Config.FALLING_DRIFT_SPEED * dt * ctx.getStreakSpeed(), 0))
	end,
}

-- Grabbing wakes this step's bug: FlyRock's shipped behavior is a child Bug
-- GameObject that gets enabled on grab (ActionType.SpawnFly; Step.cs:
-- bug.GetComponent<Bug>().enabled = true). We don't keep a dormant child part --
-- ctx.spawnBug() asks BugService (the existing spawn/catch/Fly-award path, doc 06)
-- to drift a bug in from this step's position instead.
Behaviors.SpawnFly = {
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
-- with the same impulse shape and destroys it after Config.SPLASH_LIFETIME;
-- ctx.clearFling() on destroy guards against a step recycling mid-flight leaving
-- orphaned debris.
Behaviors.SplashFlinging = {
	onGrab = function(ctx)
		ctx.flingSplash()
	end,
	onDestroy = function(ctx)
		ctx.clearFling()
	end,
}

-- ---------------------------------------------------------------------------
-- Moving steps (PORT ADDITIONS). Unity's ActionType enum names Move, RiseAndFall
-- and Launch, but Step.cs has no code and no prefab for any of them (doc 17
-- "Unused ActionTypes"), so there is nothing to port: these are new designs on
-- the step motion layer. Shared/StepKinds names them (Lillipad, BobRock,
-- SpringRock, BlinkRock) and Shared/Levels' pools, stages, patterns and events
-- decide where those spawn.
--
-- Shared rules:
--   * The motion is a visual OFFSET about the step's base (ctx.setOffset), never
--     base travel, so where the step "is" for pull aim and the recycle bound is
--     the centre of its sweep.
--   * Spawn spacing reserves the whole sweep: `sweep(params)` is the offset's
--     half-extent per axis, GameServer stores it on the step, and Lane.clearSpot
--     widens that step's grab box by it on both sides (and takes the new step's
--     own sweep as an argument), so a patroller never slides through a neighbour
--     that spawned later.
--   * The motion freezes while the step is held, so the grip point -- and the
--     limb snapped to it -- stays put, and resumes from the same phase on release.
--   * Tempo rises with the lane's run height (Config.STEP_MOTION_RUN_SPEEDUP).
-- ---------------------------------------------------------------------------
local TAU = 2 * math.pi

local function numberParam(params: Params?, key: string, default: number): number
	local value = params and params[key]
	-- `value == value` drops NaN, which would otherwise poison the step's position
	return if type(value) == "number" and value == value then value else default
end

-- The combo streak speed-up (b-20261010-192608-4bs3) takes the LARGER of the
-- height tempo and the streak multiplier rather than multiplying them: both top
-- out at 1.5x, and a product (2.25x) would make movers unreadable.
local function tempo(ctx: Ctx): number
	local height = 1 + math.min(ctx.getRunSteps() * Config.STEP_MOTION_RUN_SPEEDUP, Config.STEP_MOTION_MAX_SPEEDUP)
	return math.max(height, ctx.getStreakSpeed())
end

-- Advance a step's sinusoid by `dt` and return its new displacement (studs).
-- `limit` (optional) clamps the result into [lo, hi]. The change per tick is
-- capped at twice the sinusoid's own peak speed: never binding in normal motion
-- (tempo tops out below 2), but it turns a clamp that suddenly applies -- the
-- lane turning from sideways to vertical travel -- into a slide, not a snap.
local function oscillate(ctx: Ctx, dt: number, lo: number?, hi: number?): number
	local s = ctx.state
	local rate = TAU / s.period
	s.phase = (s.phase + dt * rate * tempo(ctx)) % TAU
	local want = s.amplitude * math.sin(s.phase)
	if lo and hi then
		want = math.clamp(want, lo, hi)
	end
	local maxStep = 2 * math.abs(s.amplitude) * rate * dt
	s.value += math.clamp(want - s.value, -maxStep, maxStep)
	return s.value
end

local function startOscillation(ctx: Ctx, amplitude: number, period: number)
	local s = ctx.state
	s.amplitude = numberParam(ctx.params, "amplitude", amplitude)
	s.period = math.max(0.1, numberParam(ctx.params, "period", period))
	s.phase = numberParam(ctx.params, "phase", math.random() * TAU)
	-- starts mid-sweep: a spawn is created off-screen, so nobody sees it appear
	s.value = s.amplitude * math.sin(s.phase)
end

-- Patrols left and right about its base.
-- Params: `amplitude` (studs each side, default Config.PATROL_AMPLITUDE),
-- `period` (seconds per sweep, default Config.PATROL_PERIOD), `phase` (radians,
-- default random).
-- While the lane travels vertically (no X in its spawn direction) nothing ever
-- carries a step sideways, so the sweep is clamped to keep the whole grab box
-- inside Unity's portrait view (Config.SPAWN_VIEW_HALF_WIDTH), the same bound
-- Lane.spawnPosition holds vertical spawns to; a base that already sits outside
-- it (a step left over from sideways travel) only sweeps inward. Under sideways
-- travel the lane's own scroll moves it across the view and the sweep is free.
Behaviors.Patrol = {
	sweep = function(params)
		return Vector2.new(math.abs(numberParam(params, "amplitude", Config.PATROL_AMPLITUDE)), 0)
	end,
	onSpawn = function(ctx)
		startOscillation(ctx, Config.PATROL_AMPLITUDE, Config.PATROL_PERIOD)
		local hit = ctx.step:GetAttribute("HitSize")
		ctx.state.halfWidth = (if typeof(hit) == "Vector2" then hit.X else ctx.step.Size.X) / 2
		ctx.setOffset(Vector3.new(ctx.state.value, 0, 0))
	end,
	onTick = function(ctx, dt)
		if ctx.isHeld() then
			return -- frozen: the offset set last tick stays
		end
		local lo: number?, hi: number? = nil, nil
		if math.abs(ctx.getSpawnBias().X) < 1e-4 then
			local limit = math.max(0, Config.SPAWN_VIEW_HALF_WIDTH - ctx.state.halfWidth)
			local rel = ctx.getBase().X - ctx.origin.X
			lo, hi = math.min(0, -limit - rel), math.max(0, limit - rel)
		end
		ctx.setOffset(Vector3.new(oscillate(ctx, dt, lo, hi), 0, 0))
	end,
}

-- Bobs up and down about its base.
-- Params: `amplitude` (default Config.RISE_FALL_AMPLITUDE), `period` (default
-- Config.RISE_FALL_PERIOD), `phase` (radians, default random).
Behaviors.RiseAndFall = {
	sweep = function(params)
		return Vector2.new(0, math.abs(numberParam(params, "amplitude", Config.RISE_FALL_AMPLITUDE)))
	end,
	onSpawn = function(ctx)
		startOscillation(ctx, Config.RISE_FALL_AMPLITUDE, Config.RISE_FALL_PERIOD)
		ctx.setOffset(Vector3.new(0, ctx.state.value, 0))
	end,
	onTick = function(ctx, dt)
		if ctx.isHeld() then
			return
		end
		ctx.setOffset(Vector3.new(0, oscillate(ctx, dt), 0))
	end,
}

-- A springboard: grabbing it pulls the field a further stretch on top of the
-- grab's own pull (GameServer dispatches onGrab after that pull has started, and
-- pulls add up), so the frog is flung up the lane.
-- Params: `pull` (studs, default Config.LAUNCH_PULL).
Behaviors.Launch = {
	onGrab = function(ctx)
		ctx.requestExtraPull(numberParam(ctx.params, "pull", Config.LAUNCH_PULL))
	end,
}

-- A timed step: once it has spent `delay` seconds inside the camera band it
-- starts blinking -- the replicated `Unsteady` attribute, the same cue Fall and
-- Crumble raise on grab -- and `warn` seconds later it drops away whether or not
-- anyone ever touched it (ctx.dropAway knocks a holder off first). The clock
-- only runs while the step is in view, so one waiting off-screen above doesn't
-- burn its fuse before the player can see it.
-- Params: `delay` (default Config.VANISH_DELAY), `warn` (default
-- Config.VANISH_WARN_TIME).
Behaviors.Vanish = {
	onSpawn = function(ctx)
		local s = ctx.state
		s.delay = math.max(0, numberParam(ctx.params, "delay", Config.VANISH_DELAY))
		s.warn = math.max(0, numberParam(ctx.params, "warn", Config.VANISH_WARN_TIME))
		s.seen = 0
	end,
	onTick = function(ctx, dt)
		local s = ctx.state
		if s.gone then
			return
		end
		local rel = ctx.getBase() - ctx.origin
		if math.abs(rel.Y) > Config.VIEW_HALF_HEIGHT or math.abs(rel.X) > Config.LANE_HALF_WIDTH then
			return
		end
		s.seen += dt
		if s.seen >= s.delay and not s.warned then
			s.warned = true
			ctx.makeUnsteady()
		end
		if s.seen >= s.delay + s.warn then
			s.gone = true
			ctx.dropAway()
		end
	end,
}

return Behaviors
