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
	MAX_HELD_STEPS = 2, -- a frog has two limbs (server-enforced)
	RESPAWN_DELAY = 1.5, -- death beat before the frog re-rises (Frog.cs Fall/Rise)

	-- Step behaviors (Entities/Step.cs ActionType; see doc 05). Weighted roll per
	-- spawned step; entries must match names in Shared/StepBehaviors.
	--
	-- The "Pot" level (doc 11 §1, index 2) is the game's first *endless*
	-- (maxSpawnCount = -1) set of StepSpawners, so its pools are the default mix
	-- here. Weight = 20 * (sum of that prefab's spawnProbability, doc 12 §1,
	-- across every Level2 StepSpawner pool it appears in, doc 11 §2a):
	--   DownLeftStepSpawner  = Potato, Carrot, UpRock
	--   DownRightStepSpawner = Carrot, Potato, UpRock
	--   DownStepSpawner      = Potato, Carrot, UpLeftRock, UpRightRock
	-- Carrot/Potato (spawnProbability 0.5) are in all 3 pools -> 1.5*20 = 30;
	-- UpRock (0.1) is in 2 of 3 -> 0.2*20 = 4; UpLeftRock/UpRightRock (0.1) are
	-- each in 1 of 3 -> 0.1*20 = 2.
	BEHAVIOR_WEIGHTS = {
		None = 30, -- Carrot (actionType None)
		CrumbleAfterRelease = 30, -- Potato
		ChangeDirectionUp = 4, -- UpRock
		ChangeDirectionUpLeft = 2, -- UpLeftRock
		ChangeDirectionUpRight = 2, -- UpRightRock

		-- Not referenced by any Level2 pool (doc 11 §2a), so there's no Unity
		-- spawnProbability to derive a weight from -- small placeholders kept for
		-- endless-mode variety, as far as the docs allow.
		Fall = 8, -- SlowFallRock (Level0/Level1/legacy pools only)
		Beetle = 2, -- Beetle (legacy General/Spawners pools only)
		ChangeDirectionLeft = 3, -- LeftRock -- not found in ANY live spawner pool (doc 11)
		ChangeDirectionRight = 3, -- RightRock -- same
		Falling = 2, -- FallingRock; canSpawn also gates on spawnCount (Step.cs)
		SpawnFly = 2, -- FlyRock
		SplashFlinging = 2, -- FlingingRock

		-- CrumblyRock.prefab ships with actionType=0 (None), not Crumble (doc 12) --
		-- Unity never actually spawns a step with this behavior. The grab/explode
		-- logic is real ported code, kept for completeness, but weighted 0 so
		-- rollBehavior never rolls it.
		Crumble = 0,
	},
	CRUMBLE_FUSE = 1.5, -- grab -> explode (Step.cs Invoke("Explode", 1.5))
	FALL_DELAY = 3.0, -- unsteady -> drop away (Step.cs Fall coroutine)
	DROP_DISTANCE = 100, -- studs a falling step drops (DOLocalMoveY(-100))
	DROP_TIME = 1.0,
	FALLING_MIN_SPAWN_COUNT = 5, -- ActionType.Falling canBeSpawned: spawnCount > 5
	FALLING_DRIFT_SPEED = 15, -- studs/s downward drift (Step.cs AddForce(0,-50,Force), flattened -- no drag/accel)

	-- Splash (Entities/Splash.cs; ActionType.SplashFlinging's "Flingee" child).
	-- Values are FlingingRock's own Splash.cs fields (doc 12), reused directly as
	-- Roblox impulse velocities (studs/s) -- a rough analog, not physically exact.
	SPLASH_MIN_X_FORCE = -15,
	SPLASH_MAX_X_FORCE = 15,
	SPLASH_Y_FORCE = 60,
	SPLASH_ROT_MOD = 2, -- initial angular velocity magnitude, opposing the X force's sign
	SPLASH_LIFETIME = 3.0, -- Splash.cs Invoke("Destroy", 3f)

	-- Bugs (Entities/Bug.cs + Spawning/BugSpawner.cs; doc 06)
	BUG_INTERVAL = 2.0, -- spawn cadence (BugSpawner.Activate: 2s)
	BUG_LIFESPAN = 2.0, -- idle time before leaving (Bug.lifeSpan)
	BUG_ENTER_TIME = 0.8, -- drift-in tween (Bug.moveTime, scaled)
	BUG_LEAVE_TIME = 1.0,
	BUG_X_RANGE = 18, -- on-screen wander extents, studs
	BUG_Y_RANGE = 12,
	BUG_FLYS = 5, -- Flys per catch (Bug.cs CollectFly -> the Fly currency)
	BUG_NEAR_WANDER_X = 6, -- ActionType.SpawnFly (doc 05): drift near the step instead of the full field, studs
	BUG_NEAR_WANDER_Y = 4,

	-- Tongue (Entities/Tongue.cs expand/retract, scaled to tween times)
	TONGUE_EXPAND_TIME = 0.12,
	TONGUE_RETRACT_TIME = 0.18,
}

return Config
