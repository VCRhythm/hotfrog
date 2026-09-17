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
}

-- Scenery/Bug spawners: DATA ONLY (doc 13 item 2). Not consumed by Lane.luau yet.
export type SceneryDef = {
	name: string,
	kind: string, -- "Scenery" | "Bug" (Spawner.Type, doc 11 §2)
	direction: Vector2,
	pool: { string }, -- pooled prefab names, data only (not Shared/StepKinds -- no behavior)
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
		{ name = "BackGrassSpawner", kind = "Scenery", direction = Vector2.new(0, 1), pool = { "BackGrass" } },
		{ name = "CloudSpawner", kind = "Scenery", direction = Vector2.new(-1, 0), pool = { "Cloud3" } },
		{ name = "GrassSpawner", kind = "Scenery", direction = Vector2.new(0, 1), pool = { "Grass" } },
		-- Unity's P2 duplicates (split-screen only) -- kept as data for parity,
		-- unused by the per-lane port (doc 13: one lane per player already gives
		-- everyone their own copy, so no P2-specific spawner is needed).
		{ name = "BackGrassSpawnerP2", kind = "Scenery", direction = Vector2.new(0, 1), pool = { "BackGrassP2" } },
		{ name = "GrassSpawnerP2", kind = "Scenery", direction = Vector2.new(0, 1), pool = { "GrassP2" } },
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
		},
	},
	scenerySpawners = {
		{ name = "Stars", kind = "Scenery", direction = Vector2.new(0, 0), pool = { "Stars" } },
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
		},
	},
	scenerySpawners = {
		{ name = "FlameScenerySpawner", kind = "Scenery", direction = Vector2.new(0, 1), pool = { "Flame" } },
		-- Multiplayer-only override (doc 11): Level2 gets a 5th spawner appended.
		{ name = "UpScenerySpawner", kind = "Scenery", direction = Vector2.new(0, 1), pool = { "Bubble" } },
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
		},
	},
	scenerySpawners = {
		{ name = "DownScenerySpawner", kind = "Scenery", direction = Vector2.new(0, -1), pool = { "Window" } },
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
		},
		-- Kitchen's (Level3) spawners, reused wholesale (doc 11).
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
		},
	},
	scenerySpawners = {
		{ name = "DownScenerySpawner", kind = "Scenery", direction = Vector2.new(0, -1), pool = { "Window" } },
	},
	levelObjects = { "US" },
}

Levels.list = list

return Levels
