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
-- levelObject, and Country exists as a 5th level entry.

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

export type Level = {
	name: string,
	musicIndex: number,
	background: string?, -- doc 11 backgroundMaterial, as a bare material-name key
	overlay: string?, -- doc 11 overlayMaterial, as a bare material-name key
	initialSpawnDirection: Vector2,
	stepSpawners: { StepSpawnerDef },
	scenerySpawners: { SceneryDef },
	levelObjects: { string },
}

local Levels = {}

-- 1-based indices (Lua arrays), matching Core/LevelManager.cs's 0-based order
-- (Menu=0..Kitchen=3) plus the Multiplayer-only Country as a 5th entry.
Levels.MENU = 1
Levels.TUTORIAL = 2
Levels.POT = 3
Levels.KITCHEN = 4
Levels.COUNTRY = 5

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
local MOVEMENTS_X_SCALE = Config.LANE_HALF_WIDTH
local MOVEMENTS_Y_SCALE = 50 * Config.UNITY_TO_STUDS -- halfScreenHeight (doc 11 §4) in studs

-- StepSpawner.SetMovementToScreenSize (Spawning/StepSpawner.cs L34-43): no extra per-axis factor.
local function mv(pairs: { { number } }): { Vector3 }
	local out: { Vector3 } = {}
	for _, xy in pairs do
		table.insert(out, Vector3.new(xy[1] * MOVEMENTS_X_SCALE, xy[2] * MOVEMENTS_Y_SCALE, 0))
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
			movements = mv({ { 2.5, -0.2 }, { -2.5, 1.0 }, { 2.5, 2.2 } }),
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
			pool = { "Potato", "Carrot", "UpRock" },
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
			pool = { "Carrot", "Potato", "UpRock" },
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
			pool = { "Potato", "Carrot", "UpLeftRock", "UpRightRock" },
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
}

-- ---------------------------------------------------------------------------
-- Kitchen (doc 11 §1, index 3). Adds the first pure-horizontal directions.
-- Includes the Multiplayer-only Chef levelObject override (doc 11) as data.
-- ---------------------------------------------------------------------------
list[Levels.KITCHEN] = {
	name = "Kitchen",
	musicIndex = 1,
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
			pool = { "ShelfWithSpoon", "ShelfWithFork", "Shelf", "UpRock" },
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
			pool = { "ShelfWithSpoon", "ShelfWithFork", "Shelf", "UpRock" },
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
			pool = { "ShelfWithSpoon", "ShelfWithFork", "Shelf", "UpRock", "UpRightRock" },
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
			pool = { "ShelfWithSpoon", "ShelfWithFork", "Shelf", "UpRock", "UpLeftRock" },
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
			pool = { "ShelfWithSpoon", "ShelfWithFork", "Shelf", "UpLeftRock", "UpRightRock", "LeftRock", "RightRock" },
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
	levelObjects = { "Chef" },
}

-- ---------------------------------------------------------------------------
-- Country (doc 11 "Level4 Country" -- Multiplayer-scene-only, index 4 there /
-- index 5 here). Reuses Kitchen's spawners wholesale and adds one themed
-- Rocket/Balloon spawner; uniquely starts with a HORIZONTAL initial direction.
-- Owner's decision (doc 13 item 5): reachable in the single-player port too, at
-- LEVEL_THRESHOLDS.Country steps.
-- ---------------------------------------------------------------------------
list[Levels.COUNTRY] = {
	name = "Country",
	musicIndex = 4,
	background = nil, -- explicitly none (doc 11: backgroundMaterial set to {fileID:0,pathID:0})
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
			pool = { "ShelfWithSpoon", "ShelfWithFork", "Shelf", "UpRock" },
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
			pool = { "ShelfWithSpoon", "ShelfWithFork", "Shelf", "UpRock", "UpRightRock" },
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
			pool = { "ShelfWithSpoon", "ShelfWithFork", "Shelf", "UpRock", "UpLeftRock" },
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
			pool = { "ShelfWithSpoon", "ShelfWithFork", "Shelf", "UpLeftRock", "UpRightRock", "LeftRock", "RightRock" },
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
}

Levels.list = list

return Levels
