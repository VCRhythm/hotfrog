--!strict
-- ReplicatedStorage/Shared/Config (ModuleScript)
-- Tunables for the basic Hotfrog loop. The numbers are ported *ratios* from the
-- Unity original (Player/Frog.cs, Player/Controller.cs, Spawning/SpawnManager.cs);
-- treat them as a starting point and tune in studs.

-- Unity unit -> stud factor. Declared up here (and re-exported as
-- Config.UNITY_TO_STUDS below, where its derivation is documented) so the
-- Unity-unit constants declared before it in the table can convert with it.
local UNITY_TO_STUDS = 55 / 175

local Config = {
	PLANE_Z = 0, -- everything lives on this XY plane

	-- Frog gravity (Player/Frog.cs: gravity / gravityMultiplier / gravityAcceleration).
	-- Unity's `gravity`/fall speeds are Unity units per second, so -- exactly like
	-- LIMB_REST below -- they only make sense here multiplied by UNITY_TO_STUDS.
	-- They used to be the raw Unity numbers read as studs (20 / 60), i.e. ~3.2x too
	-- fast: the frog cleared the camera's whole 31.4-stud band in ~1.5 s and sank
	-- out of sight before the player could reach the first step.
	-- `gravityAcceleration` is a unitless multiplier, so it doesn't scale -- but it
	-- is added once per FixedUpdate (50 Hz), i.e. +1.0 per second, not 0.6.
	GRAVITY = 20 * UNITY_TO_STUDS, -- Frog.cs gravity = 20 u/s -> 6.2857 studs/s
	GRAVITY_MULT_START = 0.5, -- multiplier resets to this on a successful grab (Bob)
	GRAVITY_ACCEL = 1.0, -- Frog.cs gravityAcceleration 0.02 per FixedUpdate * 50 Hz
	MAX_FALL_SPEED = 60 * UNITY_TO_STUDS, -- clamp, studs/s (no Unity equivalent; never binds above LAVA_Y)

	-- Limbs (Player/Controller.cs: limbReturnPos / limbReturnTime, scaled to studs).
	-- The rest offsets are HotFrog.prefab's own RightLimb/LeftLimb local positions
	-- ((20, -44.1) / (-20, -43.6) Unity units -- Controller.cs' limbReturnPos
	-- (+/-20, -40) is the same pose rounded), times UNITY_TO_STUDS below. They used
	-- to be Unity/10, which made the frog rig ~3x smaller than the world it climbs.
	LIMB_REST = { Vector2.new(6.2857, -13.8566), Vector2.new(-6.2857, -13.7595) }, -- [1]=Right, [2]=Left
	LIMB_RETURN_TIME = 0.3,

	-- Grab quality buckets by squared distance (Player/Controller.cs: TouchStep)
	GRAB_PERFECT_SQR = 1.0,
	GRAB_GREAT_SQR = 4.0, -- <= great; beyond = ok

	-- Spawning (Spawning/StepSpawner.cs + SpawnManager.cs)
	SPAWN_INTERVAL = 0.6, -- seconds between steps
	SPAWN_Y = 25, -- spawn above the top of view
	DESPAWN_Y = -30, -- recycle line for steps/scenery (Borders' bottom catch, y=-100 u)
	SPAWN_X_RANGE = 12, -- horizontal spread (+/-)

	-- The lava SURFACE, and with it the lowest the frog can ever go. Unity puts
	-- both at y = -50 units: Frog.cs SteadilyLowerHead only lowers the head
	-- `while (HeadPosition.y > -50)`, and Step.cs draws the lava splash at
	-- `new Vector2(transform.position.x, -50f)` when a step reaches the bottom
	-- net. -50 u is also exactly the bottom of the ortho-size-50 camera, so in
	-- Unity a sinking frog stops at the bottom edge of the screen, on the lava.
	-- The port's frog death check used DESPAWN_Y (-30) instead -- that's the
	-- *step* recycle line (Borders at -100 u), a whole half-screen BELOW the
	-- view, so the frog spent the last third of every fall invisible.
	LAVA_Y = -50 * UNITY_TO_STUDS, -- = -15.714 studs, the bottom of the camera band

	-- Pull / world-scroll (Spawning/SpawnManager.cs: PullStep / PullVector)
	PULL_DISTANCE = 6, -- studs the field scrolls down per successful grab
	PULL_TIME = 0.25, -- ease duration for one pull

	-- Reach: how far a limb can grab from the frog (sanity check on the server)
	MAX_GRAB_DISTANCE = 30,

	-- Lanes (doc 13: one PlayField "lane" per player; Core/LevelManager.cs +
	-- Spawning/SpawnManager.cs, made per-player instead of global).
	--
	-- Unity -> studs scale factor: doc 11 §4 gives the playfield's real bounds
	-- from Borders.prefab.json -- top/bottom "catch" triggers at y=75/y=-100
	-- (a 175-unit vertical span) and left/right catch at x=-70.8/+70.2 (a
	-- ~141-unit horizontal span). This port's *existing* SPAWN_Y/DESPAWN_Y
	-- (25/-30, a 55-stud vertical span) was tuned independently before lanes
	-- existed; dividing the two spans gives the port's own Unity-unit -> stud
	-- factor: 55 / 175 = 0.3142857... Sanity check against the horizontal
	-- bound: 70.5 (average of 70.8/70.2) * that factor = ~22.2 studs, which is
	-- what LANE_HALF_WIDTH below uses (rounded). The vertical check round-trips
	-- too: 75 * factor = ~23.6 (close to the existing SPAWN_Y=25) and
	-- -100 * factor = ~-31.4 (close to the existing DESPAWN_Y=-30) -- i.e. the
	-- port's already-tuned vertical numbers were, coincidentally or not,
	-- already close to this same factor, which is why it's trusted here rather
	-- than copying Unity's raw units.
	UNITY_TO_STUDS = UNITY_TO_STUDS, -- = 55 / 175, declared at the top of this file
	LANE_HALF_WIDTH = 22, -- one lane's horizontal catch bound (+/-), studs
	-- adjacent lanes sit edge to edge with a small 2-stud gap so a bug/step
	-- drifting to a lane's edge doesn't visually clip into its neighbour.
	LANE_SPACING = 2 * 22 + 2, -- = 46

	-- A run's total steps-climbed thresholds for soft level transitions
	-- (owner's decision, doc 13 -- Unity itself never advances past Pot).
	LEVEL_THRESHOLDS = { Kitchen = 200, Country = 500 },

	-- Step spawners only run while the field is being pulled (SpawnManager.PullStep
	-- / ReleasePullingStep), so a lane earns spawner time from pull distance:
	-- seconds = studs pulled / PULL_SPAWN_SPEED. Unity's PullVector is
	-- 2 * |target - step.y| (~80 units/s for a mid-field grab) * UNITY_TO_STUDS.
	PULL_SPAWN_SPEED = 25, -- studs of pull per spawner-second
	PREFILL_DEPTH = 24, -- studs of already-pulled field a fresh lane starts with
	PREFILL_MIN_STEPS = 4, -- a lane with at least this many live steps isn't prefilled
	TUTORIAL_FIRST_STEP_Y = 5, -- Tutorial's three tree steps: a ladder up from the frog
	TUTORIAL_STEP_GAP = 7,
	TUTORIAL_STEP_X = 5,

	-- Tutorial "fall" rule (Core/LevelManager.cs ReportFall, levelIndex == 1):
	-- no death -- the field pulls back up by this many PULL_DISTANCE steps and
	-- the player retries from the same 3 tree steps.
	TUTORIAL_PULL_BACK = 3,

	-- Grab anti-abuse (doc 07 hardening): cap grabs per rolling window per player.
	-- Two limbs + fast chaining is maybe ~6/s for a human; 10 leaves headroom.
	GRAB_WINDOW = 1.0, -- seconds
	GRAB_MAX_PER_WINDOW = 10,
	MAX_HELD_STEPS = 2, -- a frog has two limbs (server-enforced)
	RESPAWN_DELAY = 1.5, -- death beat before the frog re-rises (Frog.cs Fall/Rise)

	-- Step behaviors (Entities/Step.cs ActionType; see doc 05). Per-spawner
	-- weighted picks now live in Shared/StepKinds + Shared/Levels + Lane.luau
	-- (Spawner.cs SetUpSpawnProbabilities/CreateSpawn, per doc 13) -- there is no
	-- more global weight table; a step's behavior is entirely a function of
	-- which level/spawner/kind produced it.
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

	-- Settings persistence (doc 17 gap: SetMusicOn used to save the profile on
	-- every toggle click). The Attribute/in-memory value still applies
	-- instantly; only the DataStore write is throttled to at most once per this
	-- many seconds (see GameServer.server.luau's SetMusicOn handler).
	MUSIC_SAVE_DEBOUNCE = 5,
}

return Config
