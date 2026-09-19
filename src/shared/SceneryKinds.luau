--!strict
-- ReplicatedStorage/Shared/SceneryKinds (ModuleScript)
-- Visual + cadence data for the client-only scenery layer (Phase 4 world
-- dressing). Shared/Levels.luau's `SceneryDef` is deliberately minimal (doc 13:
-- "kept as data only" -- just name/kind/direction/pool), so the per-spawner
-- cadence fields doc 11 §2a DID extract (maxSpawnCount, spawnAllOnAwake,
-- spawningSpeedMin/Max, colorOptions, minScale/maxScale) live here instead,
-- keyed by the SAME spawner `name` string Levels.luau already uses. This file
-- is additive only -- Levels.luau itself is untouched.
--
-- Analogous to Shared/StepKinds.luau but for Spawning/ScenerySpawner.cs +
-- Entities/Scenery.cs / MovingScenery.cs (doc 11 §2a, doc 12 §3).

export type SceneryKind = {
	sprite: string?, -- SkinAssets stem (nil = no direct 1:1 sprite; flat color only)
	size: Vector3,
	colors: { Color3 }, -- Scenery prefab's own colorOptions (doc 11 §2a); size 1 if none
	-- Parallax: scrolls with the lane's PullDelta * speedModifier (Entities/Scenery.cs
	-- `speed => base.speed * speedModifier`). Ignored for `moving` kinds.
	speedModifier: number,
	-- Constant per-frame drift regardless of pulls (Entities/Scenery.cs autoMovementMin/Max,
	-- e.g. Cloud3's constant (-5,0) leftward drift) -- studs/s, already scaled.
	autoMove: Vector2,
	-- MovingScenery.cs kinds (Bubble/Chef): ignore pulls entirely, drift by their
	-- own constant direction*speed every frame instead (doc 12 §3).
	moving: boolean,
	moveDirection: Vector2,
	moveSpeed: number,
	-- MovingScenery.cs's IGrabable.Grab, but only for prefabs Player/Controller.cs's
	-- CheckTouch actually routes a tap to -- the "GrabableScenery" tag, which the
	-- prefab dump (Prefabs/Spawns/Scenery/*.prefab.json) shows ONLY Bubble wears
	-- (Chef also carries MovingScenery.cs, for its own-drift, but is tagged
	-- "Untagged" and has a null grabClip, so Controller.cs never reaches its
	-- Grab). A tap pops a `poppable` item: SoundFX "pop" (MovingScenery.cs Grab's
	-- grabClip, Audio/Pop.wav), a short particle burst (Grab's particles.Play()),
	-- and recycles it (Grab's Destroy(0, 0, 1f)) -- doc 14 "Bubble pop".
	poppable: boolean,
}

local function kind(def: {
	sprite: string?,
	size: Vector3,
	colors: { Color3 }?,
	speedModifier: number?,
	autoMove: Vector2?,
	moving: boolean?,
	moveDirection: Vector2?,
	moveSpeed: number?,
	poppable: boolean?,
}): SceneryKind
	return {
		sprite = def.sprite,
		size = def.size,
		colors = def.colors or {},
		speedModifier = def.speedModifier or 1.0,
		autoMove = def.autoMove or Vector2.zero,
		moving = def.moving == true,
		moveDirection = def.moveDirection or Vector2.zero,
		moveSpeed = def.moveSpeed or 0,
		poppable = def.poppable == true,
	}
end

-- doc 11 §2a "4 greens" / "5 pastel tints" colorOptions, reproduced as flat
-- placeholder Color3s (art fills the actual sprites in once ids are uploaded --
-- SpriteSkin.apply always wins over a flat Color when a sprite id exists).
local GREENS = {
	Color3.fromRGB(58, 110, 48),
	Color3.fromRGB(70, 130, 58),
	Color3.fromRGB(86, 150, 70),
	Color3.fromRGB(100, 168, 84),
}
local CLOUD_TINTS = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(240, 245, 255),
	Color3.fromRGB(230, 240, 255),
	Color3.fromRGB(255, 240, 240),
	Color3.fromRGB(240, 255, 240),
}

local SceneryKinds: { [string]: SceneryKind } = {
	-- Menu (Level0, doc 11 §2a) -- not reachable yet (doc 13: Menu isn't played),
	-- kept complete for when it is.
	BackGrass = kind({ sprite = "Grass", size = Vector3.new(5, 2.4, 0.2), colors = GREENS, speedModifier = 1.0 }),
	Grass = kind({ sprite = "Grass", size = Vector3.new(4, 3, 0.2), colors = GREENS, speedModifier = 1.0 }),
	-- P2 duplicates exist in Levels.luau for parity with Unity's split-screen data
	-- but are skipped at spawn time (world/WorldScenery.client.luau) -- one lane
	-- per player already gives everyone their own copy (same reasoning as the
	-- Tutorial's tree spawners, doc 13).
	BackGrassP2 = kind({ sprite = "Grass", size = Vector3.new(5, 2.4, 0.2), colors = GREENS, speedModifier = 1.0 }),
	GrassP2 = kind({ sprite = "Grass", size = Vector3.new(4, 3, 0.2), colors = GREENS, speedModifier = 1.0 }),
	Cloud3 = kind({
		sprite = "Cloud3",
		size = Vector3.new(6, 3, 0.2),
		colors = CLOUD_TINTS,
		speedModifier = 0.4,
		autoMove = Vector2.new(-1.5, 0), -- Scenery.cs autoMovement (-5,0)/(-5,0), scaled (ADAPTED)
	}),

	-- Tutorial (Level1). Stars.prefab (doc 11 §3) has spawnProbability=0 -- it's a
	-- single toggled decoration, not a repeat-spawned kind; world/WorldScenery
	-- treats its "Stars" pseudo-spawner as a one-shot (spawnAllOnAwake-like).
	Stars = kind({
		sprite = "Stars",
		size = Vector3.new(2.2, 1.1, 0.2),
		colors = { Color3.fromRGB(235, 235, 150) },
		speedModifier = 0.05,
	}),

	-- Pot (Level2)
	Flame = kind({
		sprite = "Flame",
		size = Vector3.new(1.3, 2.8, 0.2),
		colors = { Color3.fromRGB(255, 130, 40) },
		speedModifier = 1.0,
	}),
	-- Multiplayer-only UpScenerySpawner override (doc 11): MovingScenery.cs, own
	-- constant upward drift independent of pulls. Also the only "GrabableScenery"-
	-- tagged prefab (prefab dump), so it's `poppable` -- world/WorldScenery pops
	-- it on tap (doc 14 "Bubble pop").
	Bubble = kind({
		sprite = "Bubble",
		size = Vector3.new(0.9, 0.9, 0.2),
		colors = { Color3.fromRGB(190, 225, 255) },
		moving = true,
		moveDirection = Vector2.new(0, 1),
		moveSpeed = 5,
		poppable = true,
	}),

	-- Kitchen / Country (Level3/4)
	Window = kind({
		sprite = "Window",
		size = Vector3.new(3, 4, 0.2),
		colors = { Color3.fromRGB(215, 228, 236) },
		speedModifier = 0.5,
	}),

	-- levelObjects, one-off per lane (doc 11 §3) -- not repeat-spawned; placed once
	-- when a lane enters the level and removed on leaving it.
	Chef = kind({
		sprite = "Chef",
		size = Vector3.new(2.6, 5, 0.2),
		moving = true,
		moveDirection = Vector2.new(0, 1),
		moveSpeed = 3,
	}),
	-- UnitedStates.cs's USRedStates/USBlueStates two-color cutout (doc 11 §3,
	-- doc 17 known gap "US map for Country"). `colors` here is UnitedStates.cs's
	-- own `colors` array, extracted from
	-- Prefabs/Levels/Level4/Objects/US.prefab.json (dump_prefabs.py, doc 14):
	-- [blue(0,0,1,1), red(1,0,0,1)]. The two SpriteRenderer children
	-- (USRedStates/USBlueStates) continuously swap between these two tints
	-- every 5s (UnitedStates.cs ChangeColors: DOColor(colors[i], 5f) +
	-- WaitForSeconds(5f), staggered one index apart so exactly one layer is
	-- blue and the other red at any moment) -- world/WorldScenery.client.luau
	-- reproduces this with a looping TweenService crossfade per layer. `sprite`
	-- stays nil: US is TWO separate sprite stems (USRedStates/USBlueStates, now
	-- real SkinAssets keys, doc 14), not the single stem this generic
	-- SceneryKind.sprite field can express -- WorldScenery special-cases "US"
	-- entirely, the same way it already does for Chef.
	US = kind({
		sprite = nil,
		size = Vector3.new(9, 5.5, 0.2),
		colors = { Color3.fromRGB(0, 0, 255), Color3.fromRGB(255, 0, 0) }, -- [blue, red], UnitedStates.cs `colors`
		speedModifier = 0.1,
	}),
}

-- ---------------------------------------------------------------------------
-- Spawner cadence (doc 11 §2a columns not carried into Levels.SceneryDef).
-- Keyed by the SAME `name` field Levels.luau's scenerySpawners entries use.
-- maxSpawnCount: -1 = infinite (clamped client-side to WorldConfig.SCENERY_POOL_CAP).
-- ---------------------------------------------------------------------------
export type SpawnerCadence = {
	maxSpawnCount: number,
	spawningSpeedMin: number,
	spawningSpeedMax: number,
	spawnAllOnAwake: boolean,
}

local SpawnerCadence: { [string]: SpawnerCadence } = {
	BackGrassSpawner = { maxSpawnCount = 50, spawningSpeedMin = 0.05, spawningSpeedMax = 0.1, spawnAllOnAwake = false },
	GrassSpawner = { maxSpawnCount = 50, spawningSpeedMin = 0.05, spawningSpeedMax = 0.1, spawnAllOnAwake = false },
	CloudSpawner = { maxSpawnCount = 8, spawningSpeedMin = 10, spawningSpeedMax = 20, spawnAllOnAwake = false },
	Stars = { maxSpawnCount = 1, spawningSpeedMin = 0, spawningSpeedMax = 0, spawnAllOnAwake = true },
	FlameScenerySpawner = { maxSpawnCount = 5, spawningSpeedMin = 1, spawningSpeedMax = 2, spawnAllOnAwake = true },
	UpScenerySpawner = { maxSpawnCount = 14, spawningSpeedMin = 5, spawningSpeedMax = 10, spawnAllOnAwake = false },
	DownScenerySpawner = { maxSpawnCount = 5, spawningSpeedMin = 10, spawningSpeedMax = 20, spawnAllOnAwake = false },
}

local Kinds = {
	defs = SceneryKinds,
	cadence = SpawnerCadence,
}

-- P2 duplicate spawners are intentionally never ticked (see BackGrassP2/GrassP2
-- comment above) -- world/WorldScenery.client.luau checks this instead of a
-- string-suffix guess.
function Kinds.isDuplicateSpawner(spawnerName: string): boolean
	return spawnerName:sub(-2) == "P2"
end

return Kinds
