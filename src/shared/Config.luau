--!strict
-- ReplicatedStorage/Shared/Config (ModuleScript)
-- Tunables for the basic Hotfrog loop. The numbers are ported *ratios* from the
-- Unity original (Player/Frog.cs, Player/Controller.cs, Spawning/SpawnManager.cs);
-- treat them as a starting point and tune in studs.

local Config = {
	PLANE_Z = 0, -- everything lives on this XY plane

	-- Frog gravity (Player/Frog.cs: gravity / gravityMultiplier / gravityAcceleration)
	GRAVITY = 20, -- base fall factor
	GRAVITY_MULT_START = 0.5, -- multiplier resets to this on a successful grab (Bob)
	GRAVITY_ACCEL = 0.6, -- added to the multiplier per second (scaled from per-frame 0.02)
	MAX_FALL_SPEED = 60, -- clamp, studs/s

	-- Limbs (Player/Controller.cs: limbReturnPos / limbReturnTime, scaled to studs)
	LIMB_REST = { Vector2.new(2.0, -4.0), Vector2.new(-2.0, -4.0) }, -- [1]=Right, [2]=Left
	LIMB_RETURN_TIME = 0.3,

	-- Grab quality buckets by squared distance (Player/Controller.cs: TouchStep)
	GRAB_PERFECT_SQR = 1.0,
	GRAB_GREAT_SQR = 4.0, -- <= great; beyond = ok

	-- Spawning (Spawning/StepSpawner.cs + SpawnManager.cs)
	SPAWN_INTERVAL = 0.6, -- seconds between steps
	SPAWN_Y = 25, -- spawn above the top of view
	DESPAWN_Y = -30, -- recycle / lava line
	SPAWN_X_RANGE = 12, -- horizontal spread (+/-)

	-- Pull / world-scroll (Spawning/SpawnManager.cs: PullStep / PullVector)
	PULL_DISTANCE = 6, -- studs the field scrolls down per successful grab
	PULL_TIME = 0.25, -- ease duration for one pull

	-- Reach: how far a limb can grab from the frog (sanity check on the server)
	MAX_GRAB_DISTANCE = 30,

	-- Grab anti-abuse (doc 07 hardening): cap grabs per rolling window per player.
	-- Two limbs + fast chaining is maybe ~6/s for a human; 10 leaves headroom.
	GRAB_WINDOW = 1.0, -- seconds
	GRAB_MAX_PER_WINDOW = 10,

	-- Step behaviors (Entities/Step.cs ActionType; see doc 05). Weighted roll per
	-- spawned step; entries must match names in Shared/StepBehaviors.
	BEHAVIOR_WEIGHTS = {
		None = 70,
		Crumble = 8,
		CrumbleAfterRelease = 6,
		Fall = 8,
		ChangeDirectionLeft = 3,
		ChangeDirectionRight = 3,
		Beetle = 2,
	},
	CRUMBLE_FUSE = 1.5, -- grab -> explode (Step.cs Invoke("Explode", 1.5))
	FALL_DELAY = 3.0, -- unsteady -> drop away (Step.cs Fall coroutine)
	DROP_DISTANCE = 100, -- studs a falling step drops (DOLocalMoveY(-100))
	DROP_TIME = 1.0,

	-- Bugs (Entities/Bug.cs + Spawning/BugSpawner.cs; doc 06)
	BUG_INTERVAL = 2.0, -- spawn cadence (BugSpawner.Activate: 2s)
	BUG_LIFESPAN = 2.0, -- idle time before leaving (Bug.lifeSpan)
	BUG_ENTER_TIME = 0.8, -- drift-in tween (Bug.moveTime, scaled)
	BUG_LEAVE_TIME = 1.0,
	BUG_X_RANGE = 18, -- on-screen wander extents, studs
	BUG_Y_RANGE = 12,
	BUG_FLYS = 5, -- Flys per catch (Bug.cs CollectFly -> the Fly currency)

	-- Tongue (Entities/Tongue.cs expand/retract, scaled to tween times)
	TONGUE_EXPAND_TIME = 0.12,
	TONGUE_RETRACT_TIME = 0.18,
}

return Config
