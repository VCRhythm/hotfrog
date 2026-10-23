--!strict
-- ReplicatedStorage/Shared/Levels (ModuleScript)
-- Level data ported from doc 11 (Core/LevelManager.cs `levels` array + doc 11 §2a
-- spawner tables): one entry per level, step spawners fully wired for Lane.luau,
-- scenery spawners and levelObjects kept as DATA ONLY (doc 13 item 2 -- a later
-- phase renders them; nothing here spawns scenery yet).
--
-- `direction` fields are the LITERAL Unity spawnDirection values from doc 11 §2a
-- (kept for traceability), but Lane.luau only ever compares them by the SIGN of
-- each component (doc 13 item 3: Unity's own SpawnManager keys spawners by exact
-- Vector2 equality against a stale full-unit-vector array that the live
-- half-magnitude diagonal/side spawners never actually match -- a latent bug we
-- deliberately do not reproduce).
--
-- Multiplayer-scene overrides (doc 11 "Level4 Country" + its patches to the base
-- 4 levels) are folded directly into this single list rather than kept as a
-- separate scene: Pot gets its extra UpScenerySpawner, Kitchen gets its Chef
-- levelObject, and Country exists as a 5th level entry. Space (a 6th) is a PORT
-- ADDITION with no Unity counterpart (b-20261020-200915-5ju4, doc 17).

local Config = require(script.Parent.Config)

export type StepSpawnerDef = {
	name: string,
	direction: Vector2, -- Unity's literal spawnDirection (doc 11 §2a); Lane matches by SIGN only
	discreteMovement: boolean,
	moveTimeMin: number,
	moveTimeMax: number,
	moveSpeedMin: number,
	moveSpeedMax: number,
	maxSpawnCount: number, -- -1 = infinite (Spawner.cs maxSpawnCount)
	spawningSpeedMin: number,
	spawningSpeedMax: number,
	spawnAllOnAwake: boolean,
	pool: { string }, -- ordered Shared/StepKinds names (Spawner.cs pooledObjectPrefabs)
	-- Spawner.cs's own `Movements` list (raw prefab data, per-spawner), converted to stud
	-- offsets from the lane's origin -- see the "Movements-list conversion" comment below for
	-- the formula. Empty for a spawner this doc's re-extraction couldn't source (none,
	-- currently -- every step spawner actually referenced by a level has one); Lane.luau falls
	-- back to its existing procedural placement when this is empty.
	movements: { Vector3 },
	-- PORT ADDITION: true keeps spawn patterns and events (below) off this spawner --
	-- Country's themed Rocket/Balloon spawner, whose 32-stud canvases leave no room.
	noPatterns: boolean?,
}

-- Scenery/Bug spawners: DATA ONLY (doc 13 item 2). Not consumed by Lane.luau yet.
export type SceneryDef = {
	name: string,
	kind: string, -- "Scenery" | "Bug" (Spawner.Type, doc 11 §2)
	direction: Vector2,
	pool: { string }, -- pooled prefab names, data only (not Shared/StepKinds -- no behavior)
	-- Same conversion as StepSpawnerDef.movements, but through ScenerySpawner's own X*(2/3)
	-- scale (see `smv` below). Data only, like the rest of this type -- nothing spawns scenery
	-- yet (doc 13 item 2).
	movements: { Vector3 },
}

-- Height-stage progression within a single level (b-20260923-154344-dr8a,
-- journey 3/8): OWNER'S FEATURE, not a Unity port -- Unity's spawner pools
-- never change composition mid-level. Optional; nil for Menu and Tutorial.
-- `maxRunSteps` is an exclusive upper bound on the lane's step count (the last
-- entry should use math.huge so every count lands in some stage);
-- Lane.currentHeightStage picks the first stage whose bound isn't yet passed.
-- WHICH count depends on the level's `stagesFromEntry` (Level, below): unset
-- (the Pot) it is Lane.runSteps, the whole run's; set (Kitchen, Country) it is
-- the steps climbed since the lane entered the level, because the run step a
-- level really begins on is not its Config.LEVEL_THRESHOLDS entry -- the Pot's
-- rim is only LAID at the threshold, and the Pot steps still below it and the
-- rim grab itself all count before Kitchen starts.
-- `weights` overrides StepKinds[kindName].spawnProbability for Lane.pickKind,
-- per stage, for whichever kind names it lists -- a pool kind with no entry
-- here falls back to its normal StepKinds weight. `sceneryDensity` multiplies
-- WorldScenery's Bubble/Flame (bubbles/steam) spawn cadence for the stage (1 =
-- unchanged); WorldScenery reads it off the lane folder's `Stage` attribute
-- (the 1-based index into this list), which Lane.luau alone sets. That client
-- re-fires a one-shot scenery batch whenever the density changes, so Kitchen
-- and Country keep it at 1 throughout.
-- `patternChance` / `patterns` (PORT ADDITION): the chance that a spawn in this
-- stage lays one of the listed patterns (picked by `weight`) instead of a single
-- step; absent = never.
export type HeightStage = {
	maxRunSteps: number,
	weights: { [string]: number },
	sceneryDensity: number,
	patternChance: number?,
	patterns: { PatternDef }?,
}

-- Spawn patterns (PORT ADDITION, doc 17): a small formation laid in place of one
-- spawn. Each member is placed relative to the spawner's current staging point:
-- `lateral` studs across the lane's travel line (the whole pattern is mirrored
-- at random) and `upstream` studs back along it, i.e. further off-screen, so
-- later members arrive later. Every member goes through the same placement as a
-- single spawn (Lane.clearSpot, the off-screen entry), and one with no clear
-- spot, or out of reach, is skipped. `kind` nil = the spawner's own weighted
-- pick, restricted to ordinary footholds (no arrows, no hazards). Offsets are
-- sized for the two columns a portrait screen has room for: 8.8 studs across
-- clears two rock grab boxes side by side, 4.75 up clears two shelves. They are
-- the pattern's NOMINAL shape, its tightest: two rocks one RISE apart do not
-- clear (6.9-stud boxes plus Config.SPAWN_GAP), nor does a mover with its
-- reserved sweep. Lane.spawnPattern measures each member's actual grab box,
-- sweep and gap as it lays it (Lane.clearSpot) and moves that member AND every
-- later one back by whatever was missing, so a pattern opens up to fit what it
-- is made of. List members outward (ascending `upstream`).
export type PatternMember = {
	lateral: number,
	upstream: number,
	kind: string?,
	-- a role name (Levels.ROLES) resolved to the lane level's kind for it
	-- (Lane.spawnPattern); wins over `kind`, which is for fixed kinds
	role: string?,
	params: { [string]: any }?, -- replaces the kind's default StepKinds params
}

export type PatternDef = {
	name: string,
	weight: number,
	members: { PatternMember },
}

-- Rare event spawns (PORT ADDITION, doc 17): once the lane has reached
-- `minRunSteps` (counted like a height stage's bound -- see `stagesFromEntry`)
-- and `cooldown` run steps have passed since this event last fired on it, each
-- GRAB fires it with probability `chance` (one roll per spawner window, scaled
-- down for a Classic drift chunk's shorter one -- Lane.rollEvent), and it lays
-- `pattern` in place of one of that window's spawns.
export type EventDef = {
	name: string,
	chance: number,
	minRunSteps: number,
	cooldown: number,
	pattern: PatternDef,
}

-- Scripted level-entry steps (b-20260923-154345-g9ea, journey 7/8): OWNER'S
-- FEATURE, like heightStages above -- Unity's spawners never script specific
-- kinds. Optional; nil for every level except Kitchen. An ordered list of
-- StepKinds names that Lane.pickKind hands out, one per call, INSTEAD of its
-- normal weighted pick, before falling back to the normal mix once the list is
-- exhausted -- e.g. Kitchen opens on a plain Shelf (no surprise) then a single
-- LeftRock/RightRock (teaches the new sideways spawners) before the random
-- pool takes over, so the level's difficulty ramps in rather than hitting all
-- at once the instant runSteps crosses LEVEL_THRESHOLDS.Kitchen. Lane.pickKind
-- only consumes an entry when the REQUESTING spawner's own pool actually
-- contains that kind (e.g. RightRock only ever spawns off Kitchen's
-- DownStepSpawner) -- it just waits for the spawner that does, so this can't
-- force a kind onto a spawner that never carries it.
export type Level = {
	name: string,
	-- which StepKinds name plays each role in this level (Levels.ROLES); nil for
	-- levels with no dynamic steps. Builds the pools (withRoles) and resolves
	-- pattern members that name a role.
	roles: { [string]: string }?,
	musicIndex: number,
	background: string?, -- doc 11 backgroundMaterial, as a bare material-name key
	overlay: string?, -- doc 11 overlayMaterial, as a bare material-name key
	initialSpawnDirection: Vector2,
	stepSpawners: { StepSpawnerDef },
	scenerySpawners: { SceneryDef },
	levelObjects: { string },
	heightStages: { HeightStage }?,
	-- true: `heightStages` bounds and `events` thresholds count steps climbed
	-- since the lane ENTERED this level (Lane.levelStartSteps), not the whole run
	stagesFromEntry: boolean?,
	introSequence: { string }?,
	events: { EventDef }?,
}

local Levels = {}

-- 1-based indices (Lua arrays), matching Core/LevelManager.cs's 0-based order
-- (Menu=0..Kitchen=3) plus the Multiplayer-only Country as a 5th entry and the
-- port's own Space as a 6th.
Levels.MENU = 1
Levels.TUTORIAL = 2
Levels.POT = 3
Levels.KITCHEN = 4
Levels.COUNTRY = 5
Levels.SPACE = 6

local list: { Level } = {}

-- ---------------------------------------------------------------------------
-- Movements-list conversion (closes doc 17's "Per-spawner `Movements` lists" gap).
--
-- Unity's raw Spawner.Movements (Spawning/Spawner.cs L26, a per-prefab List<Vector3>) are NOT
-- world positions -- Awake() -> SetMovementToScreenSize() (Spawner.cs L64, L162-166) rescales
-- each entry into `adjustedMovements` by the camera's half-extents:
--   halfScreenHeight = 50                                    (fixed: ortho camera size, doc 11 §4 "Cameras")
--   halfScreenWidth  = 50 * (Screen.width / Screen.height)   (aspect-dependent, unresolved from the dump)
-- StepSpawner (Spawning/StepSpawner.cs L34-43) applies those two factors as-is, with no extra
-- per-axis multiplier. ScenerySpawner (Spawning/ScenerySpawner.cs L24-33) additionally scales X
-- by 2/3. BugSpawner (Spawning/BugSpawner.cs L68-77) scales both axes by 1.2 -- moot here since
-- no Bug spawner appears in any level's live spawner list (doc 11 §2/§2b: Bug spawners only
-- exist in the unused "General/Spawners" legacy prefabs and the always-on global BugSpawner
-- BugService.server.luau drives directly, neither of which is level data).
--
-- The real aspect ratio can't be recovered from the dump, so this port assumes the camera was
-- framed so halfScreenWidth lands exactly on the playfield's own horizontal catch/border bound
-- in Unity units (doc 11 §3 "Borders", ~70.5) -- the SAME assumption Config.UNITY_TO_STUDS /
-- Config.LANE_HALF_WIDTH already make when deriving the lane's own half-width from that same
-- border bound (doc 13, "Unity -> studs scale, and lane spacing"). Under that assumption the
-- two Unity multipliers collapse to flat per-axis stud scales with no separate aspect term:
--   x_stud = Movements.x * LANE_HALF_WIDTH          (== 22, matches Config.LANE_HALF_WIDTH)
--   y_stud = Movements.y * (50 * UNITY_TO_STUDS)    (== ~15.714, halfScreenHeight * Config.UNITY_TO_STUDS)
-- (Scenery's extra `* 2/3` on X is folded into `smv` below.)
--
-- The values below are a faithful stud-space conversion of doc 11's raw data, but -- like
-- Unity's own off-screen `adjustedMovements`, which the level scroll continuously drags
-- onscreen (Spawning/SpawnManager.cs Pull/PullStep, every frame while pulling) -- several
-- entries land well outside the lane's *visible* play area (Config.LANE_HALF_WIDTH / SPAWN_Y /
-- DESPAWN_Y) by design: they're staging/entry points, not on-screen rest positions. This port's
-- steps only move on a discrete per-grab pull (GameServer.pullLane), not Unity's continuous
-- per-frame drag, so `Lane.spawnPosition` clamps them into `Lane.isOutOfBounds`' recycle margin
-- when actually placing a spawn instead of using these raw offsets verbatim -- see the comment
-- there.
--
-- Raw Z values (Unity render-order artifacts -- Spawner.cs's Vector3.z is carried through
-- unscaled by SetMovementToScreenSize) carry no spatial meaning in Roblox and are dropped
-- (always 0 below).
--
-- Update (b-20260921-112713-7mxu): STEP spawners now use Unity's PORTRAIT halfScreenWidth
-- (Config.SPAWN_VIEW_HALF_WIDTH, ~8.84 studs = 28 u at 9:16) instead of LANE_HALF_WIDTH. At 22
-- studs per unit, Pot's DownStepSpawner (x = -0.5, 1.5, 2.5) put 2 of its 3 points at 33 and 55
-- studs, which the lane clamp collapsed into a single off-screen column at x = 23.6. The
-- diagonal spawners' points (x = 2..3 or -1..0) only make sense at portrait width too: from
-- there a (-0.5,-1) scroll carries a step into the view from the side. Scenery (`smv`) keeps
-- the old lane-width scale: it is client cosmetics sized to fill the lane.
local MOVEMENTS_X_SCALE = Config.LANE_HALF_WIDTH
local STEP_MOVEMENTS_X_SCALE = Config.SPAWN_VIEW_HALF_WIDTH
local MOVEMENTS_Y_SCALE = 50 * Config.UNITY_TO_STUDS -- halfScreenHeight (doc 11 §4) in studs

-- StepSpawner.SetMovementToScreenSize (Spawning/StepSpawner.cs L34-43): no extra per-axis factor.
local function mv(pairs: { { number } }): { Vector3 }
	local out: { Vector3 } = {}
	for _, xy in pairs do
		table.insert(out, Vector3.new(xy[1] * STEP_MOVEMENTS_X_SCALE, xy[2] * MOVEMENTS_Y_SCALE, 0))
	end
	return out
end

-- ScenerySpawner.SetMovementToScreenSize (Spawning/ScenerySpawner.cs L24-33): X * 2/3.
local function smv(pairs: { { number } }): { Vector3 }
	local out: { Vector3 } = {}
	for _, xy in pairs do
		table.insert(out, Vector3.new(xy[1] * MOVEMENTS_X_SCALE * (2 / 3), xy[2] * MOVEMENTS_Y_SCALE, 0))
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Dynamic content (PORT ADDITIONS, doc 17 -- none of this is Unity data).
-- ---------------------------------------------------------------------------
-- The moving / timed kinds (Shared/StepKinds), appended to every Kitchen and
-- Country rock/shelf pool. A pool only makes a kind ELIGIBLE: the level's height
-- stages give each one its weight, starting at 0.
-- Role order is the order the kinds are appended to a pool.
local ROLES = { "Patrol", "Bob", "Launch", "Vanish", "Crumble" }
Levels.ROLES = ROLES

-- The default kind per role (Space); themed levels swap a role's kind below
-- (doc 19, ruling 1B on b-20261021-074242-z0a9). A themed kind inherits the
-- stage weights of the kind it replaces, and SpringStreak / PadLadder members
-- resolve through the lane level's map.
local DYNAMIC_ROLES: { [string]: string } = {
	Patrol = "Lillipad",
	Bob = "BobRock",
	Launch = "SpringRock",
	Vanish = "BlinkRock",
	Crumble = "CrumbleRock",
}

-- Kitchen: a melting IceCube (b-20261021-091537-rv4a). Its Launch role is the default
-- SpringRock again: the Toaster is no longer spawned (b-20261022-om8p).
local KITCHEN_ROLES: { [string]: string } = table.clone(DYNAMIC_ROLES)
KITCHEN_ROLES.Vanish = "IceCube"

-- Country: Launch is the default SpringRock again (the CashPile was removed,
-- b-20261023-ag53); Vanish stays BlinkRock until the Dandelion has art
-- (b-20261021-091537-rv4a).
local COUNTRY_ROLES: { [string]: string } = table.clone(DYNAMIC_ROLES)

-- Space: a UFO bobs where BobRock did (b-20261021-091537-xh0w). Lillipad stays
-- the Patrol kind; the Satellite joins beside it (SPACE_KINDS, split weight).
-- Space keeps its rock steps: no Meteor, BoostRocket or DriftAsteroid.
local SPACE_ROLES: { [string]: string } = table.clone(DYNAMIC_ROLES)
SPACE_ROLES.Bob = "UFO"

local function withRoles(roles: { [string]: string }, pool: { string }): { string }
	local out = table.clone(pool)
	for _, role in ROLES do
		table.insert(out, roles[role])
	end
	return out
end

-- Space's extra Patrol mover (a pool is eligible kinds; stages give the weight).
local SPACE_KINDS = { "Satellite" }

local function withSpace(roles: { [string]: string }, pool: { string }): { string }
	local out = withRoles(roles, pool)
	for _, kindName in SPACE_KINDS do
		table.insert(out, kindName)
	end
	return out
end

-- Country's outdoor footholds (b-20261020-200915-5ju4, owner's ruling
-- b-20261020-201705-zwi7): tree trunks and cars, appended to each Country
-- rock/shelf pool on top of the dynamic kinds. Beetle: a hazard from stage 2.
local OUTDOOR_KINDS = { "TreeTrunk", "StillRock", "SlowFallRock", "CarRight", "CarLeft", "Beetle" }

local function withOutdoor(roles: { [string]: string }, pool: { string }): { string }
	local out = withRoles(roles, pool)
	for _, kindName in OUTDOOR_KINDS do
		table.insert(out, kindName)
	end
	return out
end

-- Nominal pattern offsets (see PatternMember: Lane widens them per member).
local COLUMN = 4.4 -- half the gap between a portrait screen's two columns
local RISE = 4.75 -- one shelf-height step up

local function member(lateral: number, upstream: number, kind: string?, params: { [string]: any }?): PatternMember
	return { lateral = lateral, upstream = upstream, kind = kind, params = params }
end

-- A member that plays a role; the lane's level picks the kind.
local function roleMember(lateral: number, upstream: number, role: string, params: { [string]: any }?): PatternMember
	return { lateral = lateral, upstream = upstream, role = role, params = params }
end

local patterns: { [string]: PatternDef } = {
	-- alternating columns, climbing
	ZigZag = {
		name = "ZigZag",
		weight = 3,
		members = { member(-COLUMN, 0), member(COLUMN, RISE), member(-COLUMN, 2 * RISE), member(COLUMN, 3 * RISE) },
	},
	-- one diagonal flight across the screen
	Staircase = {
		name = "Staircase",
		weight = 2,
		members = { member(-COLUMN, 0), member(0, RISE), member(COLUMN, 2 * RISE) },
	},
	-- a tight triangle
	Cluster = {
		name = "Cluster",
		weight = 2,
		members = { member(-COLUMN, 0), member(COLUMN, 0), member(0, RISE) },
	},
	-- three FlyRocks: each grab wakes a bug (StepBehaviors.SpawnFly)
	BugChain = {
		name = "BugChain",
		weight = 1,
		members = {
			member(-COLUMN, 0, "FlyRock"),
			member(COLUMN, RISE, "FlyRock"),
			member(-COLUMN, 2 * RISE, "FlyRock"),
		},
	},
	-- two lily pads gliding in opposite directions, one above the other
	PadLadder = {
		name = "PadLadder",
		weight = 1,
		members = {
			roleMember(0, 0, "Patrol", { amplitude = 2.5, period = 3.5, phase = 0 }),
			roleMember(0, 7.25, "Patrol", { amplitude = 2.5, period = 3.5, phase = math.pi }),
		},
	},
	-- event: two springboards and somewhere ordinary to land
	SpringStreak = {
		name = "SpringStreak",
		weight = 1,
		members = { roleMember(-COLUMN, 0, "Launch"), roleMember(COLUMN, RISE, "Launch"), member(-COLUMN, 2 * RISE) },
	},
	-- event: the tall castle (StepKinds.Castle, in no pool)
	CastleKeep = {
		name = "CastleKeep",
		weight = 1,
		members = { member(0, 0, "Castle") },
	},
}
Levels.patterns = patterns

-- ---------------------------------------------------------------------------
-- Menu (doc 11 §1, index 0). Not played yet (doc 13 item 5 starts a run at
-- Tutorial/Pot) -- kept complete so a future menu phase can consume it.
-- ---------------------------------------------------------------------------
list[Levels.MENU] = {
	name = "Menu",
	musicIndex = 1,
	background = nil,
	overlay = nil,
	initialSpawnDirection = Vector2.new(0, -1),
	stepSpawners = {},
	scenerySpawners = {
		{
			name = "BackGrassSpawner",
			kind = "Scenery",
			direction = Vector2.new(0, 1),
			pool = { "BackGrass" },
			movements = smv({ { -1.0, -1.5 }, { 1.0, -1.5 } }),
		},
		{
			name = "CloudSpawner",
			kind = "Scenery",
			direction = Vector2.new(-1, 0),
			pool = { "Cloud3" },
			movements = smv({ { 4.0, 0.8 }, { 4.0, 0.5 } }),
		},
		{
			name = "GrassSpawner",
			kind = "Scenery",
			direction = Vector2.new(0, 1),
			pool = { "Grass" },
			movements = smv({ { -1.0, -1.3 }, { 1.0, -1.3 } }),
		},
		-- Unity's P2 duplicates (split-screen only) -- kept as data for parity,
		-- unused by the per-lane port (doc 13: one lane per player already gives
		-- everyone their own copy, so no P2-specific spawner is needed).
		{
			name = "BackGrassSpawnerP2",
			kind = "Scenery",
			direction = Vector2.new(0, 1),
			pool = { "BackGrassP2" },
			movements = smv({ { 1.0, -1.5 }, { 3.0, -1.5 } }),
		},
		{
			name = "GrassSpawnerP2",
			kind = "Scenery",
			direction = Vector2.new(0, 1),
			pool = { "GrassP2" },
			movements = smv({ { 1.0, -1.3 }, { 3.0, -1.3 } }),
		},
	},
	levelObjects = { "Clouds" },
}

-- ---------------------------------------------------------------------------
-- Tutorial (doc 11 §1, index 1). StepAndScenerySpawner, spawnAllOnAwake=true,
-- maxSpawnCount=3, discrete straight-down movement (doc 11 §2a). Unity duplicated
-- this per-player (Player1Tree.../Player2Tree...); one lane per player makes
-- that duplication unnecessary here -- every lane gets its own 3 trees.
-- ---------------------------------------------------------------------------
list[Levels.TUTORIAL] = {
	name = "Tutorial",
	musicIndex = 1,
	background = nil,
	overlay = "Water",
	initialSpawnDirection = Vector2.new(0, -1),
	stepSpawners = {
		{
			name = "TreeDownStepSpawner",
			direction = Vector2.new(0, -1),
			discreteMovement = true,
			moveTimeMin = 1,
			moveTimeMax = 1,
			moveSpeedMin = 1,
			moveSpeedMax = 1,
			maxSpawnCount = 3,
			spawningSpeedMin = 1,
			spawningSpeedMax = 1,
			spawnAllOnAwake = true,
			pool = { "TutorialFirstTree", "TutorialSecondTree", "TutorialLastTree" },
			-- Player1TreeDownStepSpawner's own Movements (doc 11 §2a); Player2's copy (a
			-- purely x-shifted duplicate for split-screen) is dropped -- one lane per player
			-- already gives everyone their own ladder (see the header comment above).
			-- Unity's second/third Y (1.0, 2.2) are the very top of the view and past it, so
			-- on a phone acorn 2 sat under the HUD / at the thumb's far edge
			-- (b-20261022-140925-k146); lowered to 0.58 / 0.96 (doc 17; WorldTutorialTrunk's art is squashed to match).
			movements = mv({ { 2.5, -0.2 }, { -2.5, 0.58 }, { 2.5, 0.96 } }),
		},
	},
	scenerySpawners = {
		-- "Stars" here is a `LevelObject`/`Scenery.cs` decoration (doc 11 §3 "Stars"), not an
		-- actual `Spawner`-derived prefab -- no Movements list exists for it to extract.
		{ name = "Stars", kind = "Scenery", direction = Vector2.new(0, 0), pool = { "Stars" }, movements = {} },
	},
	levelObjects = { "Stars", "SpeckManager" },
}

-- ---------------------------------------------------------------------------
-- Pot (doc 11 §1, index 2). First endless (maxSpawnCount=-1) level. Includes
-- the Multiplayer-only UpScenerySpawner override (doc 11 "same Multiplayer
-- override" note) as data.
-- ---------------------------------------------------------------------------
list[Levels.POT] = {
	name = "Pot",
	musicIndex = 0,
	background = "PotBack",
	overlay = "Water",
	initialSpawnDirection = Vector2.new(0, -1),
	stepSpawners = {
		{
			name = "DownLeftStepSpawner",
			direction = Vector2.new(-0.5, -1),
			discreteMovement = true,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 0.7,
			spawnAllOnAwake = false,
			pool = { "Potato", "Carrot", "UpRock", "Lillipad", "FlingingRock" },
			movements = mv({ { 2.0, 1.25 }, { 3.0, 1.25 }, { 3.0, 0.5 } }),
		},
		{
			name = "DownRightStepSpawner",
			direction = Vector2.new(0.5, -1),
			discreteMovement = true,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 0.7,
			spawnAllOnAwake = false,
			pool = { "Carrot", "Potato", "UpRock", "Lillipad", "FlingingRock" },
			movements = mv({ { -1.0, 0.5 }, { -1.0, 1.25 }, { 0.0, 1.25 } }),
		},
		{
			name = "DownStepSpawner",
			direction = Vector2.new(0, -1),
			discreteMovement = false,
			moveTimeMin = 0.5,
			moveTimeMax = 1,
			moveSpeedMin = 1,
			moveSpeedMax = 2,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.25,
			spawningSpeedMax = 0.35,
			spawnAllOnAwake = false,
			pool = { "Potato", "Carrot", "UpLeftRock", "UpRightRock", "Lillipad", "FlingingRock" },
			movements = mv({ { -0.5, 1.25 }, { 1.5, 1.25 }, { 2.5, 1.25 } }),
		},
	},
	scenerySpawners = {
		{
			name = "FlameScenerySpawner",
			kind = "Scenery",
			direction = Vector2.new(0, 1),
			pool = { "Flame" },
			movements = smv({
				{ -1.0, -1.0 },
				{ -0.5, -1.0 },
				{ 0.0, -1.0 },
				{ 0.5, -1.0 },
				{ 1.0, -1.0 },
				{ 1.5, -1.0 },
				{ 2.0, -1.0 },
				{ 2.5, -1.0 },
				{ 3.0, -1.0 },
				{ 3.5, -1.0 },
			}),
		},
		-- Multiplayer-only override (doc 11): Level2 gets a 5th spawner appended.
		{
			name = "UpScenerySpawner",
			kind = "Scenery",
			direction = Vector2.new(0, 1),
			pool = { "Bubble" },
			movements = smv({ { -0.5, -1.25 }, { 1.5, -1.25 }, { 2.5, -1.25 } }),
		},
	},
	levelObjects = {},
	-- Three height stages across Pot's 0-50 runSteps span (Config.LEVEL_THRESHOLDS.Kitchen),
	-- so the climb reads as progress through a place rather than one flat pool the whole
	-- level (b-20260923-154344-dr8a): mostly Carrot with heavy bubbles/steam low down,
	-- Potato (explodes 1 s after the grab) mixed in through the middle, then the Up*Rock
	-- diagonals dominating and the steam thinning near the top. Every pool kind above
	-- gets an entry so no stage silently falls back to a flat StepKinds weight.
	-- PORT ADDITION: the last stage also floats the odd Lillipad (a patrolling step,
	-- the first dynamic kind a run meets) and lays an occasional plain ZigZag; the
	-- first two stages are unchanged (Lillipad = 0, no patterns). Three stages exactly:
	-- Ambience.client.luau maps Pot's Stage attribute onto three volumes.
	heightStages = {
		{
			maxRunSteps = 15,
			weights = {
				Carrot = 3,
				Potato = 0.4,
				UpRock = 0.2,
				UpLeftRock = 0.2,
				UpRightRock = 0.2,
				Lillipad = 0,
				FlingingRock = 0,
			},
			sceneryDensity = 1.75,
		},
		{
			maxRunSteps = 35,
			weights = {
				Carrot = 1,
				Potato = 1.5,
				UpRock = 0.5,
				UpLeftRock = 0.5,
				UpRightRock = 0.5,
				Lillipad = 0,
				FlingingRock = 0.3,
			},
			sceneryDensity = 1,
		},
		{
			maxRunSteps = math.huge,
			weights = {
				Carrot = 0.5,
				Potato = 0.7,
				UpRock = 1.6,
				UpLeftRock = 1.6,
				UpRightRock = 1.6,
				Lillipad = 0.5,
				FlingingRock = 0.4,
			},
			sceneryDensity = 0.4,
			patternChance = 0.08,
			patterns = { patterns.ZigZag },
		},
	},
}

-- ---------------------------------------------------------------------------
-- Kitchen (doc 11 §1, index 3). Adds the first pure-horizontal directions.
-- Includes the Multiplayer-only Chef levelObject override (doc 11) as data.
-- ---------------------------------------------------------------------------
list[Levels.KITCHEN] = {
	name = "Kitchen",
	roles = KITCHEN_ROLES,
	-- PORT DEVIATION: Unity plays musicIndex 1 (FrogSounds, the menu track) here;
	-- 5 = music6, a Ludo-generated kitchen chiptune (owner b-20261021-094437-1mnh;
	-- Adenine, the earlier pick from b-20261010-192146-ml2d, moved to Space).
	-- doc 17 "Kitchen music".
	musicIndex = 5,
	background = "KitchenTile",
	overlay = nil,
	initialSpawnDirection = Vector2.new(0, -1),
	stepSpawners = {
		{
			name = "DownRightStepSpawner",
			direction = Vector2.new(0.5, -1),
			discreteMovement = true,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 1.0,
			spawnAllOnAwake = false,
			pool = withRoles(
				KITCHEN_ROLES,
				{ "ShelfWithSpoon", "ShelfWithFork", "Shelf", "UpRock", "CrumblyRock", "FallingRock" }
			),
			movements = mv({ { -1.0, 0.5 }, { -1.0, 1.25 }, { 0.0, 1.25 } }),
		},
		{
			name = "DownLeftStepSpawner",
			direction = Vector2.new(-0.5, -1),
			discreteMovement = true,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 1.0,
			spawnAllOnAwake = false,
			pool = withRoles(
				KITCHEN_ROLES,
				{ "ShelfWithSpoon", "ShelfWithFork", "Shelf", "UpRock", "CrumblyRock", "FallingRock" }
			),
			movements = mv({ { 2.0, 1.25 }, { 3.0, 1.25 }, { 3.0, 0.5 } }),
		},
		{
			name = "RightStepSpawner",
			direction = Vector2.new(0.5, 0),
			discreteMovement = true,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 1.0,
			spawnAllOnAwake = false,
			pool = withRoles(
				KITCHEN_ROLES,
				{ "ShelfWithSpoon", "ShelfWithFork", "Shelf", "UpRock", "UpRightRock", "CrumblyRock", "FallingRock" }
			),
			movements = mv({ { -1.5, 0.5 }, { -1.5, 0.0 }, { -1.5, -0.5 } }),
		},
		{
			name = "LeftStepSpawner",
			direction = Vector2.new(-0.5, 0),
			discreteMovement = true,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 1.0,
			spawnAllOnAwake = false,
			pool = withRoles(
				KITCHEN_ROLES,
				{ "ShelfWithSpoon", "ShelfWithFork", "Shelf", "UpRock", "UpLeftRock", "CrumblyRock", "FallingRock" }
			),
			-- doc 13's worked example: this is the spawner whose Movements sit past the
			-- RIGHT edge despite a leftward spawnDirection (see "Direction / arrow semantics").
			movements = mv({ { 1.5, 0.5 }, { 1.5, 0.0 }, { 1.5, -0.5 } }),
		},
		{
			name = "DownStepSpawner",
			direction = Vector2.new(0, -1),
			discreteMovement = false,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 1.0,
			spawnAllOnAwake = false,
			-- PORT ADDITION: LeftRock/RightRock are in no shipped Unity pool, which left the
			-- Left/Right spawners unreachable from a downward scroll; adding them here is
			-- what makes sideways travel actually happen (doc 13).
			pool = withRoles(KITCHEN_ROLES, {
				"ShelfWithSpoon",
				"ShelfWithFork",
				"Shelf",
				"UpLeftRock",
				"UpRightRock",
				"LeftRock",
				"RightRock",
				"CrumblyRock",
				"FallingRock",
			}),
			movements = mv({ { 0.0, 1.25 }, { 1.5, 1.25 }, { 2.0, 1.25 } }),
		},
	},
	scenerySpawners = {
		{
			name = "DownScenerySpawner",
			kind = "Scenery",
			direction = Vector2.new(0, -1),
			pool = { "Window" },
			movements = smv({ { -0.5, 1.25 }, { 1.5, 1.25 }, { 2.5, 1.25 } }),
		},
	},
	-- Multiplayer-only override (doc 11): Level3 gets a Chef levelObject appended.
	-- The port draws the Chef as a hazard instead (server/Chef.luau + WorldChef).
	levelObjects = {},
	-- First three DownStepSpawner spawns after arriving from Pot: a plain Shelf
	-- (matches DownStepSpawner's own first movements-list entry, (0, 1.25) --
	-- straight above the frog, no tween-in per Lane.updateMovement), a second
	-- Shelf to let that land, then one RightRock so the player meets the new
	-- sideways travel deliberately instead of stumbling into it (b-20260923-154345-g9ea).
	introSequence = { "Shelf", "Shelf", "RightRock" },
	-- PORT ADDITION: Kitchen's ~45 steps (rim grab to LEVEL_THRESHOLDS.Country) in
	-- four stages, counted from the lane's arrival (stagesFromEntry). The shelves and arrows
	-- keep their StepKinds weights throughout (not listed = unchanged), so stage 1
	-- is the Kitchen as it was; the dynamic kinds are then introduced a pair at a
	-- time -- movers first, then the springboard (SpringRock) and the crumbler, the
	-- timed IceCube last -- and patterns grow more likely. For scale, the shelf and
	-- arrow weights in a pool sum to 1.6-1.9.
	stagesFromEntry = true,
	heightStages = {
		{
			maxRunSteps = 12,
			weights = {
				Lillipad = 0,
				BobRock = 0,
				SpringRock = 0,
				IceCube = 0,
				CrumbleRock = 0,
				CrumblyRock = 0.3,
				FallingRock = 0,
			},
			sceneryDensity = 1,
		},
		{
			maxRunSteps = 26,
			weights = {
				Lillipad = 0.35,
				BobRock = 0.3,
				SpringRock = 0,
				IceCube = 0,
				CrumbleRock = 0,
				CrumblyRock = 0.3,
				FallingRock = 0,
			},
			sceneryDensity = 1,
			patternChance = 0.1,
			patterns = { patterns.ZigZag, patterns.Staircase, patterns.Cluster },
		},
		{
			maxRunSteps = 38,
			weights = {
				Lillipad = 0.35,
				BobRock = 0.3,
				SpringRock = 0.2,
				IceCube = 0,
				CrumbleRock = 0.3,
				CrumblyRock = 0.35,
				FallingRock = 0.2,
			},
			sceneryDensity = 1,
			patternChance = 0.15,
			patterns = { patterns.ZigZag, patterns.Staircase, patterns.Cluster, patterns.BugChain },
		},
		{
			maxRunSteps = math.huge,
			weights = {
				Lillipad = 0.4,
				BobRock = 0.35,
				SpringRock = 0.2,
				IceCube = 0.3,
				CrumbleRock = 0.35,
				CrumblyRock = 0.4,
				FallingRock = 0.3,
			},
			sceneryDensity = 1,
			patternChance = 0.2,
			patterns = { patterns.ZigZag, patterns.Staircase, patterns.Cluster, patterns.BugChain, patterns.PadLadder },
		},
	},
	events = {
		{
			name = "SpringStreak",
			chance = 0.03,
			minRunSteps = 30,
			cooldown = 25,
			pattern = patterns.SpringStreak,
		},
	},
}

-- ---------------------------------------------------------------------------
-- Country (doc 11 "Level4 Country" -- Multiplayer-scene-only, index 4 there /
-- index 5 here). Reuses Kitchen's spawners wholesale and adds one themed
-- Rocket/Balloon spawner; uniquely starts with a HORIZONTAL initial direction.
-- Owner's decision (doc 13 item 5): reachable in the single-player port too, at
-- LEVEL_THRESHOLDS.Country steps. PORT ADDITIONS (b-20261020-200915-5ju4, ruling
-- b-20261020-201705-zwi7, doc 17): Country is the outdoor area -- its own sky
-- backdrop, tree trunks and cars in its rock/shelf pools -- and it is no longer
-- endless: LEVEL_THRESHOLDS.Space run steps hand the lane on to Space.
-- ---------------------------------------------------------------------------
list[Levels.COUNTRY] = {
	name = "Country",
	roles = COUNTRY_ROLES,
	musicIndex = 4,
	-- PORT DEVIATION: Unity has none (doc 11: backgroundMaterial {fileID:0,pathID:0});
	-- the port paints a sky (Sprites/Other/CountryBack.png).
	background = "CountryBack",
	overlay = nil,
	initialSpawnDirection = Vector2.new(-0.5, 0),
	stepSpawners = {
		-- Level4's own themed spawner (doc 11: file is misleadingly named
		-- "RightStepSpawner" but its Unity spawnDirection is (-0.5,0) -- a
		-- *left*-moving spawner; pool is Rocket/Balloon, not rocks).
		{
			name = "Level4RightStepSpawner",
			direction = Vector2.new(-0.5, 0),
			discreteMovement = false,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 2,
			spawningSpeedMax = 3,
			spawnAllOnAwake = false,
			pool = { "Rocket", "Balloon" },
			noPatterns = true,
			movements = mv({ { 1.0, -1.25 }, { 1.5, -1.25 }, { 2.5, -1.25 } }),
		},
		-- Kitchen's (Level3) spawners, reused wholesale (doc 11) -- same Movements as their
		-- Kitchen counterparts above, since it's literally the same shipped prefab.
		{
			name = "DownLeftStepSpawner",
			direction = Vector2.new(-0.5, -1),
			discreteMovement = true,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 1.0,
			spawnAllOnAwake = false,
			pool = withOutdoor(COUNTRY_ROLES, { "UpRock", "UpLeftRock", "UpRightRock" }),
			movements = mv({ { 2.0, 1.25 }, { 3.0, 1.25 }, { 3.0, 0.5 } }),
		},
		{
			name = "RightStepSpawner",
			direction = Vector2.new(0.5, 0),
			discreteMovement = true,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 1.0,
			spawnAllOnAwake = false,
			pool = withOutdoor(COUNTRY_ROLES, { "UpRock", "UpRightRock", "RightRock" }),
			movements = mv({ { -1.5, 0.5 }, { -1.5, 0.0 }, { -1.5, -0.5 } }),
		},
		{
			name = "LeftStepSpawner",
			direction = Vector2.new(-0.5, 0),
			discreteMovement = true,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 1.0,
			spawnAllOnAwake = false,
			pool = withOutdoor(COUNTRY_ROLES, { "UpRock", "UpLeftRock", "LeftRock" }),
			movements = mv({ { 1.5, 0.5 }, { 1.5, 0.0 }, { 1.5, -0.5 } }),
		},
		{
			name = "DownStepSpawner",
			direction = Vector2.new(0, -1),
			discreteMovement = false,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 1.0,
			spawnAllOnAwake = false,
			-- PORT ADDITION: LeftRock/RightRock are in no shipped Unity pool, which left the
			-- Left/Right spawners unreachable from a downward scroll; adding them here is
			-- what makes sideways travel actually happen (doc 13).
			pool = withOutdoor(COUNTRY_ROLES, {
				"UpLeftRock",
				"UpRightRock",
				"LeftRock",
				"RightRock",
			}),
			movements = mv({ { 0.0, 1.25 }, { 1.5, 1.25 }, { 2.0, 1.25 } }),
		},
	},
	scenerySpawners = {
		{
			name = "DownScenerySpawner",
			kind = "Scenery",
			direction = Vector2.new(0, -1),
			pool = { "Window" },
			movements = smv({ { -0.5, 1.25 }, { 1.5, 1.25 }, { 2.5, 1.25 } }),
		},
	},
	levelObjects = { "US" },
	-- PORT ADDITION: Country's ~150 steps (LEVEL_THRESHOLDS.Country to .Space)
	-- ramp from "Kitchen's movers, no hazards" (a breather on arrival, no cars
	-- yet) to a mix where roughly half the rock/shelf spawns are dynamic. Tree
	-- trunks keep their StepKinds weight throughout; cars and the Beetle join
	-- after stage 1 and grow more common (each stage lists them, so the stage
	-- tables match). The Launch role is the default SpringRock. The
	-- themed Rocket/Balloon spawner is untouched. Shelves are gone from Country
	-- (b-20261020-213556-k25y): the plain footholds are the trees, and every
	-- stage weights the arrows (0.25 each) well above their 0.1 default.
	-- Counted from the lane's
	-- arrival, like Kitchen's.
	stagesFromEntry = true,
	heightStages = {
		{
			maxRunSteps = 10,
			weights = {
				Lillipad = 0.35,
				BobRock = 0.3,
				SpringRock = 0.15,
				BlinkRock = 0,
				CrumbleRock = 0,
				CarRight = 0,
				TreeTrunk = 1.2,
				StillRock = 0.4,
				SlowFallRock = 0,
				UpRock = 0.25,
				UpLeftRock = 0.25,
				UpRightRock = 0.25,
				LeftRock = 0.25,
				RightRock = 0.25,
				CarLeft = 0,
				Beetle = 0,
			},
			sceneryDensity = 1,
			patternChance = 0.1,
			patterns = { patterns.ZigZag, patterns.Staircase, patterns.Cluster },
		},
		{
			maxRunSteps = 30,
			weights = {
				Lillipad = 0.4,
				BobRock = 0.35,
				SpringRock = 0.25,
				BlinkRock = 0.2,
				CrumbleRock = 0.3,
				CarRight = 0.15,
				TreeTrunk = 1.2,
				StillRock = 0.4,
				SlowFallRock = 0,
				UpRock = 0.25,
				UpLeftRock = 0.25,
				UpRightRock = 0.25,
				LeftRock = 0.25,
				RightRock = 0.25,
				CarLeft = 0.15,
				Beetle = 0.1,
			},
			sceneryDensity = 1,
			patternChance = 0.18,
			patterns = { patterns.ZigZag, patterns.Staircase, patterns.Cluster, patterns.BugChain },
		},
		{
			maxRunSteps = 60,
			weights = {
				Lillipad = 0.45,
				BobRock = 0.4,
				SpringRock = 0.25,
				BlinkRock = 0.35,
				CrumbleRock = 0.4,
				CarRight = 0.2,
				TreeTrunk = 1.2,
				StillRock = 0.4,
				SlowFallRock = 0.2,
				UpRock = 0.25,
				UpLeftRock = 0.25,
				UpRightRock = 0.25,
				LeftRock = 0.25,
				RightRock = 0.25,
				CarLeft = 0.2,
				Beetle = 0.15,
			},
			sceneryDensity = 1,
			patternChance = 0.22,
			patterns = { patterns.ZigZag, patterns.Staircase, patterns.Cluster, patterns.BugChain, patterns.PadLadder },
		},
		{
			maxRunSteps = math.huge,
			weights = {
				Lillipad = 0.5,
				BobRock = 0.45,
				SpringRock = 0.3,
				BlinkRock = 0.45,
				CrumbleRock = 0.45,
				CarRight = 0.25,
				TreeTrunk = 1.2,
				StillRock = 0.4,
				SlowFallRock = 0.3,
				UpRock = 0.25,
				UpLeftRock = 0.25,
				UpRightRock = 0.25,
				LeftRock = 0.25,
				RightRock = 0.25,
				CarLeft = 0.25,
				Beetle = 0.15,
			},
			sceneryDensity = 1,
			patternChance = 0.25,
			patterns = { patterns.ZigZag, patterns.Staircase, patterns.Cluster, patterns.BugChain, patterns.PadLadder },
		},
	},
	events = {
		{
			name = "CastleKeep",
			chance = 0.04,
			minRunSteps = 5,
			cooldown = 20,
			pattern = patterns.CastleKeep,
		},
		{
			name = "SpringStreak",
			chance = 0.03,
			minRunSteps = 25,
			cooldown = 25,
			pattern = patterns.SpringStreak,
		},
	},
}

-- ---------------------------------------------------------------------------
-- Space (PORT ADDITION, no Unity level: b-20261020-200915-5ju4, owner's ruling
-- b-20261020-201705-zwi7, doc 17). Reached from Country at
-- LEVEL_THRESHOLDS.Space run steps; the last level, endless. Gravity eases to
-- Config.SPACE_GRAVITY_SCALE over the first SPACE_GRAVITY_TRANSITION_STEPS
-- steps after arrival (Lane.gravityScale) and stays there. Country's spawners
-- with asteroids in place of the shelves and trees/cars, the themed spawner
-- down to rockets, and a star-field backdrop; travel starts straight up.
-- ---------------------------------------------------------------------------
list[Levels.SPACE] = {
	name = "Space",
	roles = SPACE_ROLES,
	musicIndex = 3, -- music4 "Adenine", Kitchen's old track (owner b-20261021-094437-1mnh)
	background = "SpaceBack",
	overlay = nil,
	initialSpawnDirection = Vector2.new(0, -1),
	stepSpawners = {
		{
			name = "RocketSpawner",
			direction = Vector2.new(-0.5, 0),
			discreteMovement = false,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 2,
			spawningSpeedMax = 3,
			spawnAllOnAwake = false,
			pool = { "Rocket" },
			noPatterns = true,
			movements = mv({ { 1.0, -1.25 }, { 1.5, -1.25 }, { 2.5, -1.25 } }),
		},
		{
			name = "DownLeftStepSpawner",
			direction = Vector2.new(-0.5, -1),
			discreteMovement = true,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 1.0,
			spawnAllOnAwake = false,
			pool = withSpace(SPACE_ROLES, { "Asteroid", "UpRock" }),
			movements = mv({ { 2.0, 1.25 }, { 3.0, 1.25 }, { 3.0, 0.5 } }),
		},
		{
			name = "RightStepSpawner",
			direction = Vector2.new(0.5, 0),
			discreteMovement = true,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 1.0,
			spawnAllOnAwake = false,
			pool = withSpace(SPACE_ROLES, { "Asteroid", "UpRock", "UpRightRock" }),
			movements = mv({ { -1.5, 0.5 }, { -1.5, 0.0 }, { -1.5, -0.5 } }),
		},
		{
			name = "LeftStepSpawner",
			direction = Vector2.new(-0.5, 0),
			discreteMovement = true,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 1.0,
			spawnAllOnAwake = false,
			pool = withSpace(SPACE_ROLES, { "Asteroid", "UpRock", "UpLeftRock" }),
			movements = mv({ { 1.5, 0.5 }, { 1.5, 0.0 }, { 1.5, -0.5 } }),
		},
		{
			name = "DownStepSpawner",
			direction = Vector2.new(0, -1),
			discreteMovement = false,
			moveTimeMin = 1,
			moveTimeMax = 2,
			moveSpeedMin = 0.5,
			moveSpeedMax = 1,
			maxSpawnCount = -1,
			spawningSpeedMin = 0.5,
			spawningSpeedMax = 1.0,
			spawnAllOnAwake = false,
			pool = withSpace(SPACE_ROLES, { "Asteroid", "UpLeftRock", "UpRightRock", "LeftRock", "RightRock" }),
			movements = mv({ { 0.0, 1.25 }, { 1.5, 1.25 }, { 2.0, 1.25 } }),
		},
	},
	scenerySpawners = {},
	levelObjects = {},
	-- Two asteroids to land on while gravity eases off, before anything else.
	introSequence = { "Asteroid", "Asteroid" },
	-- Counted from the lane's arrival: a calm stretch (movers only) while the
	-- gravity transition plays, then Country's late-game mix.
	stagesFromEntry = true,
	heightStages = {
		{
			maxRunSteps = 12,
			weights = { Lillipad = 0.175, Satellite = 0.175, UFO = 0.3, SpringRock = 0, BlinkRock = 0, CrumbleRock = 0 },
			sceneryDensity = 1,
		},
		{
			maxRunSteps = math.huge,
			weights = {
				Lillipad = 0.25,
				Satellite = 0.25,
				UFO = 0.45,
				SpringRock = 0.3,
				BlinkRock = 0.45,
				CrumbleRock = 0.45,
			},
			sceneryDensity = 1,
			patternChance = 0.25,
			patterns = { patterns.ZigZag, patterns.Staircase, patterns.Cluster, patterns.BugChain, patterns.PadLadder },
		},
	},
	events = {
		{
			name = "SpringStreak",
			chance = 0.03,
			minRunSteps = 25,
			cooldown = 25,
			pattern = patterns.SpringStreak,
		},
	},
}

Levels.list = list

return Levels
