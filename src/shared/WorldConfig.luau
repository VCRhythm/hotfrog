--!strict
-- ReplicatedStorage/Shared/WorldConfig (ModuleScript)
-- Tuning constants for Phase 4 "world dressing" (client-only cosmetics: scenery,
-- backdrop/overlay/sun, lava, pebbles, quality popups, touch indicator, frog
-- blink/pupils, tutorial specks). Kept separate from Shared/Config per this
-- phase's file ownership -- Config.luau stays untouched.
--
-- Where a value is a straight port of a Unity field it says so; where it's an
-- adaptation (no literal Unity equivalent survives the 2D-sprite -> Roblox-part
-- translation, e.g. pupil travel in studs) it's marked ADAPTED.

local WorldConfig = {}

-- ---------------------------------------------------------------------------
-- Frog blink cycle (Player/Frog.cs Blink/BlinkAnimate/AwakeAnimate)
-- ---------------------------------------------------------------------------
WorldConfig.BLINK_MIN_TIME = 1.0 -- Frog.cs minBlinkTime
WorldConfig.BLINK_MAX_TIME = 3.0 -- Frog.cs maxBlinkTime
WorldConfig.BLINK_FRAME_TIME = 0.05 -- Frog.cs blinkAnimateCounter (WaitForSeconds(.05))

-- ADAPTED: Frog.cs moves separate LeftPupil/RightPupil Transforms with
-- SmoothDamp (clamp 3 "Unity units", smoothTime .3s). The Roblox rig has no
-- separate pupil parts (doc: only Decal-flat facial art) -- pupils are ported
-- as Texture instances on the Head so they can be nudged via OffsetStudsU/V
-- (a "local visual property", never a part CFrame). The Head part's face is now
-- the pupil sprite's own Unity canvas (1024 px / 8 px-per-unit = 128 units,
-- FrogModel.model.json), so the offset IS a literal unit->stud conversion:
-- Frog.cs pupilClamp 3 * Config.UNITY_TO_STUDS.
WorldConfig.PUPIL_MAX_OFFSET = 0.9429 -- studs of OffsetStudsU/V travel, each axis
WorldConfig.PUPIL_LERP_RATE = 10 -- higher = snappier tracking (per-second lerp factor)

-- How far a limb must sit from its Config.LIMB_REST offset to count as
-- "extended onto something" (Shared/GrabTarget heuristic -- see world/GrabTarget.luau).
WorldConfig.GRAB_EXTEND_THRESHOLD = 1.0 -- studs
WorldConfig.NEAREST_STEP_POLL_INTERVAL = 0.25 -- seconds between nearest-step rescans (per idle frog)

-- Frog dead/rise fade (ADAPTED "rise/lower" -- Frog.cs Rise/Lower move the whole
-- rig; the server already owns that CFrame, so the client-only cosmetic here is
-- a fade instead of a move).
WorldConfig.FROG_DEAD_FADE_TIME = 0.15
WorldConfig.FROG_RISE_FADE_TIME = 0.35
WorldConfig.FROG_DEAD_TRANSPARENCY = 0.55

-- ---------------------------------------------------------------------------
-- QualityText (doc 12 §6 TouchQualityText* prefabs)
-- ---------------------------------------------------------------------------
WorldConfig.QUALITY_POPUP_LIFETIME = 0.5 -- QualityText.cs lifetime
WorldConfig.QUALITY_POPUP_RISE = 2.5 -- studs it floats upward over its lifetime
WorldConfig.QUALITY_POPUP_COLORS = {
	Perfect = Color3.fromRGB(0, 255, 108), -- (0.0, 1.0, 0.423, 1.0)
	Great = Color3.fromRGB(97, 190, 255), -- (0.382, 0.744, 1.0, 1.0)
	OK = Color3.fromRGB(255, 255, 255),
	Miss = Color3.fromRGB(255, 0, 0),
}
WorldConfig.QUALITY_POPUP_TEXT = {
	Perfect = "PERFECT!",
	Great = "GREAT!",
	OK = "OK",
	Miss = "X",
}
-- how long after a grab we'll still trust a captured limb-extend position
-- (Shared/GrabTarget) as "the step that scored this quality"
WorldConfig.QUALITY_POPUP_MATCH_WINDOW = 0.5

-- ---------------------------------------------------------------------------
-- TouchIndicator (Player/TouchIndicator.cs)
-- ---------------------------------------------------------------------------
WorldConfig.TOUCH_INDICATOR_FADE_TIME = 0.5 -- TouchIndicator.cs Hide: DOFade(0, .5f)
WorldConfig.TOUCH_INDICATOR_COLOR_TIME = 1.0 -- TouchIndicator.cs SetColor animated case
WorldConfig.TOUCH_INDICATOR_GREEN = Color3.fromRGB(80, 220, 90)
WorldConfig.TOUCH_INDICATOR_YELLOW = Color3.fromRGB(240, 210, 60)
WorldConfig.TOUCH_INDICATOR_RED = Color3.fromRGB(230, 70, 70)
-- ADAPTED: Unity's TouchIndicator has three unused-together color strategies
-- (by distance / by time-held / by Y); Controller.cs (not in this phase's read
-- list) decides which is live. We use distance-from-frog, scaled against the
-- existing MAX_GRAB_DISTANCE reach check so "red" roughly means "likely too far".
WorldConfig.TOUCH_INDICATOR_GREEN_FRACTION = 0.4 -- of Config.MAX_GRAB_DISTANCE
WorldConfig.TOUCH_INDICATOR_YELLOW_FRACTION = 0.75

-- ---------------------------------------------------------------------------
-- Lava (Entities/Lava.cs LiftHeat/LowerHeat + Splash)
-- ---------------------------------------------------------------------------
WorldConfig.LAVA_HEAT_LIFT_TIME = 2.0 -- Lava.cs heatPlane.DOLocalMoveZ(0, 2f)
WorldConfig.LAVA_HEAT_LOWER_TIME = 2.0 -- Lava.cs heatPlane.DOLocalMoveZ(10f, 2f)
WorldConfig.LAVA_SPLASH_COUNT = 5 -- Lava.Splash(pos, splashCount) call sites use small counts
WorldConfig.LAVA_SPLASH_LIFETIME = 3.0 -- Entities/Splash.cs Invoke("Destroy", 3f)
WorldConfig.LAVA_SPLASH_MIN_X = -15 -- Splash.cs LavaSplash values (doc 12 §3)
WorldConfig.LAVA_SPLASH_MAX_X = 15
WorldConfig.LAVA_SPLASH_Y = 20
WorldConfig.LAVA_HOT_COLOR = Color3.fromRGB(255, 90, 30)
WorldConfig.LAVA_COOL_COLOR = Color3.fromRGB(140, 40, 20)

-- ---------------------------------------------------------------------------
-- Sun (Entities/Sun.cs + LevelManager's isNight/isBlack Animator bools)
-- ---------------------------------------------------------------------------
WorldConfig.SUN_TRANSITION_TIME = 1.5
WorldConfig.SUN_DAY_COLOR = Color3.fromRGB(255, 236, 160)
WorldConfig.SUN_NIGHT_COLOR = Color3.fromRGB(180, 190, 230)
WorldConfig.SUN_BLACK_COLOR = Color3.fromRGB(20, 20, 30)

-- ---------------------------------------------------------------------------
-- Overlay (Entities/Overlay.cs Fade/Lower/Lift)
-- ---------------------------------------------------------------------------
WorldConfig.OVERLAY_FADE_TIME = 1.0
WorldConfig.OVERLAY_LOWER_DELAY = 1.0
WorldConfig.OVERLAY_LOWER_TIME = 1.0
WorldConfig.OVERLAY_LIFT_TIME = 1.0
WorldConfig.OVERLAY_COLOR = Color3.fromRGB(80, 150, 220) -- Water.mat placeholder tint
WorldConfig.OVERLAY_TRANSPARENCY = 0.55

-- ---------------------------------------------------------------------------
-- Level transition flash (start / soft / death -- LevelChanged remote)
-- ---------------------------------------------------------------------------
WorldConfig.TRANSITION_DEATH_FLASH_TIME = 0.35
WorldConfig.TRANSITION_SOFT_CROSSFADE_TIME = 1.0
WorldConfig.TRANSITION_START_FADE_TIME = 0.6

-- ---------------------------------------------------------------------------
-- Scenery spawning + parallax (Spawning/ScenerySpawner.cs, Entities/Scenery.cs)
-- ---------------------------------------------------------------------------
WorldConfig.SCENERY_BOUNDS_MARGIN = 10 -- extra studs beyond the lane's step bounds before recycling
WorldConfig.SCENERY_POOL_CAP = 24 -- clamp for spawners whose maxSpawnCount is "-1" (infinite)
WorldConfig.SCENERY_AUTOMOVE_SCALE = 0.12 -- Unity autoMovement units -> studs/s (ADAPTED, cosmetic-only)

-- ---------------------------------------------------------------------------
-- Pebbles (Entities/Pebble.cs Explode: xForce=Random(-5,5), yForce=Random(1,5),
-- rotForce=2*sign(xForce), impulse; used by Effects.client.luau for the
-- crumble-debris burst off an Unsteady step, pooled instead of one-shot parts)
-- ---------------------------------------------------------------------------
WorldConfig.PEBBLES_PER_BURST = 5
WorldConfig.PEBBLE_LIFETIME = 1.5 -- Pebble.cs Explode: Invoke("Destroy", 3f) is 3s in Unity; kept short here (doc 05 crumble fuse is already 1.5s)
WorldConfig.PEBBLE_INTERVAL = 1.0 -- ShowCrumbles: a burst every second while Unsteady
WorldConfig.PEBBLE_MIN_X_FORCE = -5
WorldConfig.PEBBLE_MAX_X_FORCE = 5
WorldConfig.PEBBLE_MIN_Y_FORCE = 1
WorldConfig.PEBBLE_MAX_Y_FORCE = 5
WorldConfig.PEBBLE_ROT_FORCE = 2 -- Pebble.cs rotForce = 2f * Mathf.Sign(xForce)

-- ---------------------------------------------------------------------------
-- Tutorial specks (Entities/Speck.cs + SpeckManager.cs)
-- ---------------------------------------------------------------------------
WorldConfig.SPECK_COUNT = 6 -- ADAPTED down from Unity's pool of 100 -- a few is plenty for guidance
WorldConfig.SPECK_MOVE_TIME = 0.5 -- Speck.cs Move(): transform.DOMove(..., 0.5f)
WorldConfig.SPECK_RADIUS = 1.2 -- Speck.prefab targetRadius=1.0 (already stud-scale, doc 12 §4)
WorldConfig.SPECK_ROTATE_SPEED = 2.5 -- radians/sec around its target (Speck.cs rotateSpeed, simplified)
WorldConfig.SPECK_SIZE = Vector3.new(0.35, 0.35, 0.1)
WorldConfig.SPECK_COLORS = { -- SpeckManager.prefab colorOptions (doc 11 §3): 8 entries
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(170, 255, 80),
	Color3.fromRGB(80, 255, 120),
	Color3.fromRGB(255, 80, 220),
	Color3.fromRGB(80, 230, 255),
	Color3.fromRGB(170, 80, 255),
	Color3.fromRGB(255, 160, 40),
	Color3.fromRGB(255, 60, 60),
}

-- ---------------------------------------------------------------------------
-- Attract mode (Player/FrogAI.cs): while a lane's RunState == "Menu", a
-- decorative ladder + cosmetic frog climb it on a loop, beside the parked
-- real (server-owned) frog -- see WorldAttract.client.luau.
-- ---------------------------------------------------------------------------
WorldConfig.ATTRACT_STEP_COUNT = 3 -- "a few steps" (FrogAI plays on 2-3 in Unity's menu scene)
WorldConfig.ATTRACT_STEP_SIZE = Vector3.new(2.4, 1.6, 0.6) -- smaller than StepTemplate's real (4,3,1) -- reads as a toy-scale prop, never mistaken for a grabbable step
-- Offset from the lane origin: the real parked frog (GameServer/
-- WorldFrogCosmetics, untouched by this file) sits AT the origin, so this
-- whole vignette is shifted a few studs to the side to avoid rendering a
-- second frog on top of the first. z is nudged slightly off the gameplay
-- plane (Config.PLANE_Z = 0), same direction as WorldScenery's own z=-1 dressing.
WorldConfig.ATTRACT_ANCHOR_OFFSET = Vector3.new(7, 0, -0.2)
WorldConfig.ATTRACT_STEP_X = 2.2 -- zig-zag half-width per rung (same shape as Lane.luau's Tutorial ladder: Config.TUTORIAL_STEP_X, alternating sign)
WorldConfig.ATTRACT_STEP_Y_GAP = 3.2 -- vertical rise per rung (same shape as Config.TUTORIAL_STEP_GAP, independently tuned smaller for a compact decorative ladder)
WorldConfig.ATTRACT_DECISION_TIME = 1.0 -- FrogAI.cs: nextDecisionTime is initialized to 1f and never reassigned -- despite the "next" name it's a literal fixed 1s cadence, not randomized

return WorldConfig
