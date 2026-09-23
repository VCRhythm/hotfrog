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
	MAX_FALL_SPEED = 60 * UNITY_TO_STUDS, -- clamp, studs/s (no Unity equivalent; binds only after ~2.5 s without a grab)

	-- Frog.Bob (Player/Frog.cs:254-279), run on every grab. The head (the port's
	-- f.pos, relative to the lane origin = Unity's frog root) sways to the grabbed
	-- step's X over |dx| * 0.06 s/u, gets a Z "rock" punch of -0.1 deg per unit of
	-- that sway over 1 s, and -- only if it has sunk to -5 u or lower -- rises to
	-- min(5 u, y + 50 u) over |dy| * 0.05 s/u. Both moves are Ease.OutSine.
	BOB_TRIGGER_Y = -5 * UNITY_TO_STUDS, -- the rise only fires at or below this
	BOB_TOP_Y = 5 * UNITY_TO_STUDS, -- the rise never goes above this
	BOB_RISE = 50 * UNITY_TO_STUDS, -- ...or more than this far up
	BOB_X_TIME_PER_STUD = 0.06 / UNITY_TO_STUDS, -- seconds per stud of sway
	BOB_Y_TIME_PER_STUD = 0.05 / UNITY_TO_STUDS, -- seconds per stud of rise
	BOB_ROCK_DEG_PER_STUD = -0.1 / UNITY_TO_STUDS, -- punch angle per stud of (head X - step X)
	BOB_ROCK_TIME = 1.0, -- DOPunchRotation duration

	-- Limbs (Player/Controller.cs: limbReturnPos / limbReturnTime, scaled to studs).
	-- The rest offsets are HotFrog.prefab's own RightLimb/LeftLimb local positions
	-- ((20, -44.1) / (-20, -43.6) Unity units -- Controller.cs' limbReturnPos
	-- (+/-20, -40) is the same pose rounded), times UNITY_TO_STUDS below. They used
	-- to be Unity/10, which made the frog rig ~3x smaller than the world it climbs.
	LIMB_REST = { Vector2.new(6.2857, -13.8566), Vector2.new(-6.2857, -13.7595) }, -- [1]=Right, [2]=Left
	LIMB_RETURN_TIME = 0.3,
	-- A tap that hits nothing sends a free limb out to the tap point (Controller.cs
	-- CheckTouch miss -> Limb.Move: DOMove over 0.1 s) before it eases back to rest.
	LIMB_REACH_TIME = 0.1,

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

	-- Death fall (Player/Frog.cs Die -> Fall() coroutine), the dramatic beat that
	-- used to be missing entirely: the port froze the frog at LAVA_Y the instant
	-- it died. Unity instead holds still for a beat, plays the fall/splash sound,
	-- then keeps sinking the whole body well past the lava line -- off the bottom
	-- of the camera -- before the run summary beat ends.
	DEATH_FALL_DELAY = 1, -- Fall(): `yield return new WaitForSeconds(1f)` before PlayFallSound
	DEATH_FALL_TIME = 1, -- eased duration standing in for Fall()'s SmoothDamp(smoothTime .3s) sink
	DEATH_FALL_Y = -100 * UNITY_TO_STUDS, -- Fall()'s `endY`: how far the body sinks past LAVA_Y

	-- Pull / world-scroll (Spawning/SpawnManager.cs: PullStep / PullVector).
	-- Unity scales each pull by how far the grabbed step is from a target line
	-- (PullMultiplier = 2 * |target - step.y|), so grabbing a high step scrolls the
	-- field further. The port pulls once per grab (a tween), so it turns that rule
	-- into a destination: a grab slides the field along the lane's spawn direction
	-- until the grabbed step's grip point sits at the point of its travel line
	-- nearest PULL_TARGET, the camera centre (owner's ruling, b-20260921-164409-nkkh;
	-- PullMath.pullDistance). The distance is clamped to [PULL_MIN_DISTANCE,
	-- PULL_MAX_DISTANCE] so a step already at/below the centre still scrolls the
	-- field a little (as Unity's never-zero multiplier does) and earns spawner time.
	PULL_TARGET = Vector2.new(0, 0), -- lane-relative; the camera looks at the lane origin
	PULL_MIN_DISTANCE = 2,
	PULL_MAX_DISTANCE = 24,
	-- One pull's duration: distance / PULL_SPEED, clamped to [PULL_TIME, PULL_TIME_MAX]
	-- (Sine out), so a long pull reads as a slide rather than a jump.
	PULL_SPEED = 40, -- studs/s
	PULL_TIME = 0.25, -- shortest pull (also the attract ladder's rung pull)
	PULL_TIME_MAX = 0.6,
	-- Half the camera's vertical view (ortho size 50 u, GameClient CAMERA_DISTANCE).
	-- New steps are placed so they START outside this band and are carried in by
	-- the pull (Lane.entryShift), so they slide in instead of popping into view.
	-- Side entries (pure horizontal travel) use the same half-extent as an assumed
	-- half-width: the server cannot see the client's aspect ratio.
	VIEW_HALF_HEIGHT = 50 * UNITY_TO_STUDS, -- = 15.714 studs
	SLIDE_IN_TIME = 0.6, -- a prefilled screenful / the Tutorial ladder scrolls in over this

	-- Roblox PlayerList keep-out (owner's decision b-20260921-182502-qgbw, doc 17):
	-- while the core PlayerList is (probably) open, GameClient sends its rough
	-- lane-relative world rectangle (ScreenObstruction remote) and a non-drifting
	-- lane's grab pull is lengthened, never shortened, by up to
	-- OBSTRUCTION_MAX_EXTRA_PULL studs (about one ordinary pull) until no step's
	-- grab box rests inside it; new spawns are nudged out of it too (Lane.clearSpot).
	-- Pixel sizes were measured off the live CoreGui PlayerList (2026-09-21):
	-- 320 px wide, 4 px from the right/top edges under the top bar, a ~42 px
	-- header, ~40 px per player row, ~8 px footer, capped at ~436 px (it scrolls).
	OBSTRUCTION_MAX_EXTRA_PULL = 8,
	OBSTRUCTION_PAD = 0.25, -- studs of slack around the rectangle
	OBSTRUCTION_SEARCH_STEP = 0.25, -- studs per candidate extension tried
	OBSTRUCTION_MIN_INTERVAL = 0.2, -- server: seconds between accepted updates per player
	PLAYERLIST_WIDTH_PX = 340, -- 320 px list + its 4 px edge margin + slack
	PLAYERLIST_HEADER_PX = 4 + 42 + 8, -- top margin + header + footer
	PLAYERLIST_ROW_PX = 40,
	PLAYERLIST_MAX_HEIGHT_PX = 440,
	PLAYERLIST_POLL = 0.5, -- client: seconds between checks (and the send throttle)

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
	-- Unity's visible half-width on the portrait phone it shipped on: the camera
	-- is ortho size 50 and Spawner.cs SetMovementToScreenSize uses
	-- halfScreenWidth = 50 * (Screen.width / Screen.height), which at 9:16 is
	-- ~28 u. Step spawner `Movements` x values are fractions of this width
	-- (Levels.luau), and a spawn that only travels vertically is kept inside it
	-- (Lane.spawnPosition), so a portrait player sees every step and a wider
	-- window sees them all near the middle.
	SPAWN_VIEW_HALF_WIDTH = 50 * (9 / 16) * UNITY_TO_STUDS, -- ~8.84 studs
	-- Two steps' grab boxes (StepKinds hitSize) never spawn closer than this
	-- gap; a crowded spawn is moved back along its travel line (Lane.clearSpot).
	SPAWN_GAP = 1.5,

	-- A run's total steps-climbed thresholds for soft level transitions
	-- (owner's decision, doc 13 -- Unity itself never advances past Pot).
	-- Changed to a new level every 50 steps 2026-09-22 (b-20260922-101937-mcaj,
	-- owner's decision; was Kitchen 200, Country 500).
	LEVEL_THRESHOLDS = { Kitchen = 50, Country = 100 },

	-- Step spawners only run while the field is being pulled (SpawnManager.PullStep
	-- / ReleasePullingStep), and Unity runs them for a fixed 1 s per grab
	-- (Entities/Step.cs Pull: Invoke("StopPull", 1f)) whatever the pull's length.
	-- The port does the same: each grab earns PULL_SPAWN_WINDOW spawner-seconds,
	-- spent at once when the grab lands (Lane.spawnForPull), with the window's
	-- spawns spread along that grab's pull and placed upstream so the pull itself
	-- carries them in. This replaces a per-stud rate (8 studs per spawner-second),
	-- which suited the old fixed 6-stud pull; with target-seeking pulls a grab
	-- consumes about one step whatever its length, and so does a fixed window. In
	-- a headless sim (20 runs x 50 grabs, 0.7 s cadence), grabs with no
	-- portrait-visible step ahead: Pot 168 -> 103, Kitchen 375 -> 303, Country
	-- 423 -> 257 of 1000, with no spawn overlaps (doc 17 "Spawner time per grab").
	PULL_SPAWN_WINDOW = 1, -- spawner-seconds earned per grab
	PREFILL_DEPTH = 24, -- studs of already-pulled field a fresh lane starts with
	PREFILL_ROW_STEP = 6, -- prefill simulates that depth as grabs pulling this many studs each
	PREFILL_MIN_STEPS = 4, -- a lane with at least this many live steps isn't prefilled
	-- Direction-change scaffold (owner's request b-20260921-182631-0a8u, doc 17):
	-- grabbing a ChangeDirection* step also drops this many steps in from the top
	-- of the view, laid out from the grabbed step toward the frog's new heading,
	-- one SCAFFOLD_SPACING apart (plus SCAFFOLD_RISE upward per step when the new
	-- heading is purely sideways), so the new direction has something to grab
	-- before its own spawners catch up. Lane.scaffold.
	SCAFFOLD_COUNT = 3,
	SCAFFOLD_SPACING = 6.5,
	SCAFFOLD_RISE = 1.5,
	SCAFFOLD_NUDGE = 3, -- studs a crowded rung may move along the heading before it is skipped
	TUTORIAL_FIRST_STEP_Y = 5, -- Tutorial's three tree steps: a ladder up from the frog
	TUTORIAL_STEP_GAP = 7,
	TUTORIAL_STEP_X = 5,

	-- Tutorial "fall" rule (Core/LevelManager.cs ReportFall, levelIndex == 1):
	-- no death -- the field pulls back up by up to this many PULL_MAX_DISTANCE
	-- pulls (capped at the lane's net pull, so in practice all of it) and the
	-- player retries from the same 3 tree steps.
	TUTORIAL_PULL_BACK = 3,

	-- "Classic" run mode (owner's request b-20260921-164458-8liv; doc 17): the
	-- world keeps scrolling along the lane's spawn direction whether or not the
	-- frog holds anything, on top of the normal per-grab pull, so the player has
	-- to keep climbing or be carried into the lava. "Normal" only scrolls on
	-- grabs. Chosen per run on the main menu (StartRun payload); Classic is the
	-- default (owner's request b-20260921-182325-3jtz) -- only an explicit
	-- "Normal" selection opts out, anything else (missing/garbage) also falls
	-- back to Classic (Lane.setMode).
	RUN_MODES = { Normal = "Normal", Classic = "Classic" },
	-- Constant scroll speed per level, in Unity units/s converted to studs.
	-- Unity never scrolls on its own (Rigidbody2D drag = 2 stops the steps once a
	-- grab's 1 s pull ends), so there is no original number; the scale comes from
	-- Unity's own pull: SpawnManager.PullStep's force is 2 * |target - y| with a
	-- 40 u target line, i.e. 80 for a step at the centre, and with drag 2 that
	-- settles at 80 / 2 = 40 u/s. Classic drifts at a quarter of that on Pot and
	-- speeds up per level. Levels not listed (Menu, Tutorial) don't drift: the
	-- Tutorial ladder is one-shot and its retry rule pulls the field back.
	CLASSIC_SCROLL_SPEED = {
		Pot = 10 * UNITY_TO_STUDS, -- ~3.14 studs/s
		Kitchen = 13 * UNITY_TO_STUDS, -- ~4.09 studs/s
		Country = 16 * UNITY_TO_STUDS, -- ~5.03 studs/s
	} :: { [string]: number },
	-- Drift spends spawner time per stud scrolled (the port's old per-stud rate,
	-- 8 studs per spawner-second, see PULL_SPAWN_WINDOW above), settled in chunks
	-- of this many seconds; each chunk is also replicated as one PullDelta so the
	-- lane's cosmetics scroll with it.
	CLASSIC_SPAWN_PER_STUD = 1 / 8,
	CLASSIC_CHUNK_TIME = 0.5,
	-- Classic ramp (owner's request b-20260921-182325-3jtz: "the steps should
	-- slowly get faster and faster"): once a Classic run's drift has started
	-- (Lane.driftElapsed, seconds since the run's first grab armed the frog),
	-- the scroll speed grows by this fraction of the CURRENT level's own base
	-- CLASSIC_SCROLL_SPEED per second, so the ramp scales with each level
	-- instead of one flat number. At 1/120 a run reaches ~2x its level's base
	-- speed after about 2 minutes of continuous drifting; it keeps climbing
	-- gently after that, hard-capped at CLASSIC_SCROLL_MAX_MULT times the base
	-- so a long run can never run away. Gentle by design -- there is no Unity
	-- equivalent (Unity never scrolls on its own, see CLASSIC_SCROLL_SPEED
	-- above). The ramp carries across a run's level transitions (Pot -> Kitchen
	-- -> Country) but resets on every new run (Lane.resetRun); Tutorial never
	-- drifts at all (no entry in CLASSIC_SCROLL_SPEED), so the ramp is inert
	-- there regardless of mode.
	CLASSIC_SCROLL_ACCEL_RATE = 1 / 120, -- fraction of the level's base speed added per second
	CLASSIC_SCROLL_MAX_MULT = 3, -- hard cap, as a multiple of the level's base speed
	-- Level-transition speed ramp (b-20260923-154345-g9ea): CLASSIC_SCROLL_SPEED
	-- steps up per level (Pot ~3.14 -> Kitchen ~4.09, a ~30% jump), which used to
	-- land instantly the moment runSteps crossed LEVEL_THRESHOLDS -- on top of
	-- Kitchen's new sideways spawners, that read as a difficulty spike. Lane.driftBase
	-- now chases each level's CLASSIC_SCROLL_SPEED at a rate of (this many seconds to
	-- cross the whole gap) instead of snapping, so the speed blends in; the slower
	-- CLASSIC_SCROLL_ACCEL_RATE ramp above still runs on top of it exactly as before.
	CLASSIC_LEVEL_RAMP_TIME = 6, -- seconds to blend from one level's base speed to the next

	-- Grab anti-abuse (doc 07 hardening): cap grabs per rolling window per player.
	-- Two limbs + fast chaining is maybe ~6/s for a human; 10 leaves headroom.
	GRAB_WINDOW = 1.0, -- seconds
	GRAB_MAX_PER_WINDOW = 10,
	MAX_HELD_STEPS = 2, -- a frog has two limbs (server-enforced)
	-- Death beat before the frog re-rises (Frog.cs Fall/Rise). Widened from 1.5 so
	-- it comfortably contains DEATH_FALL_DELAY + DEATH_FALL_TIME above -- the
	-- dramatic sink now has to finish playing out before the frog resets.
	RESPAWN_DELAY = 2.2,

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

	-- Idle step spin (owner's request, doc 17 -- Unity's steps never rotate).
	-- Every step rolls one signed rate on spawn and keeps it until it is grabbed;
	-- direction is a coin flip. The roll is `min + (max-min) * random()^BIAS`, so
	-- BIAS > 1 crowds the draw toward the slow end: most steps barely turn and the
	-- occasional one tumbles. Degrees per second.
	STEP_SPIN_MIN_DEG = 2,
	STEP_SPIN_MAX_DEG = 40,
	STEP_SPIN_BIAS = 3,

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
