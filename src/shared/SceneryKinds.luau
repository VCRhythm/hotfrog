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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

-- SIZES: every `size` below is the sprite's WHOLE Unity canvas, in studs --
-- `<png pixels> / <the .png.meta's spritePixelsToUnits> * Config.UNITY_TO_STUDS`,
-- times the prefab's own localScale (only BackGrass (1,2,1), Stars (2,1,1) and US
-- (1,0.8709,1) have one that isn't identity). A Roblox Decal always stretches the
-- full image across the face it sits on, so a part that isn't the canvas squashes
-- the art -- the same rule the frog rig (FrogModel.model.json) and StepKinds were
-- rebuilt under. Most of these canvases are heavily padded around the visible art,
-- which is why the numbers look large next to the old placeholders; scenery is
-- CanQuery=false, so a big part can't eat a tap.
export type SceneryKind = {
	sprite: string?, -- SkinAssets stem (nil = no direct 1:1 sprite; flat color only)
	size: Vector3, -- the sprite's whole Unity canvas in studs (see SIZES above)
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
	-- ---- Client-only dynamics (ADAPTED/additive -- Unity scenery has none of these) ----
	-- Plane the part sits on (WorldConfig.SCENERY_Z by default). Far parallax layers sit
	-- further back, near ones just behind the step plane (steps are 1 stud thick at Z 0).
	z: number,
	-- Sprite opacity 0..1 (atmospheric far layers are fainter).
	opacity: number,
	-- Per-frame motion layered ON TOP of pull + autoMove (see SceneryMotion).
	motion: SceneryMotion?,
	-- How strongly Country's gusts (world/Wind.luau) push this kind's drift and
	-- amplify its sway. 0 = unaffected.
	windSensitivity: number,
	-- What a tap on the part does (WorldScenery's generalised Bubble pop): "pop" (burst
	-- + recycle, MovingScenery.cs Grab), "wobble" (squash and damped roll), "flare"
	-- (swell + a few sparks). nil = not tappable (CanQuery stays false).
	reaction: Reaction?,
}

-- Optional per-kind motion descriptor, evaluated every frame in WorldScenery on top
-- of the pull/autoMove position. All amplitudes are studs / degrees / fractions and
-- are scaled by WorldConfig.MOTION_AMPLITUDE_SCALE; periods are seconds (scaled by
-- MOTION_SPEED_SCALE). Each part gets its own random phase so a field of them
-- doesn't move in lockstep.
export type SceneryMotion = {
	swayX: number, -- horizontal sine offset amplitude, studs
	swayY: number, -- vertical sine (bob) amplitude, studs
	swayPeriod: number,
	roll: number, -- Z-rotation sine amplitude, degrees
	rollPeriod: number,
	spin: number, -- constant Z spin, degrees/second (0 = none)
	pulse: number, -- fractional size breathing amplitude (0.05 = +/-5%)
	pulsePeriod: number,
	flicker: number, -- extra fractional size jitter from noise (flames)
}

export type Reaction = "pop" | "wobble" | "flare"

local function motion(def: {
	swayX: number?,
	swayY: number?,
	swayPeriod: number?,
	roll: number?,
	rollPeriod: number?,
	spin: number?,
	pulse: number?,
	pulsePeriod: number?,
	flicker: number?,
}): SceneryMotion
	return {
		swayX = def.swayX or 0,
		swayY = def.swayY or 0,
		swayPeriod = def.swayPeriod or 4,
		roll = def.roll or 0,
		rollPeriod = def.rollPeriod or 4,
		spin = def.spin or 0,
		pulse = def.pulse or 0,
		pulsePeriod = def.pulsePeriod or 2,
		flicker = def.flicker or 0,
	}
end

-- A sprite's whole canvas in studs (the SIZES rule above), times an optional
-- display scale for the parallax layers that reuse one sprite at several sizes.
local function canvas(pixels: number, pixelsPerUnit: number, scale: number?): number
	return pixels / pixelsPerUnit * Config.UNITY_TO_STUDS * (scale or 1)
end

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
	z: number?,
	opacity: number?,
	motion: SceneryMotion?,
	windSensitivity: number?,
	reaction: Reaction?,
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
		poppable = def.poppable == true or def.reaction == "pop",
		z = def.z or WorldConfig.SCENERY_Z,
		opacity = def.opacity or 1,
		motion = def.motion,
		windSensitivity = def.windSensitivity or 0,
		reaction = def.reaction or (if def.poppable == true then "pop" :: Reaction else nil),
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
	-- Grass.png 256px @ 10 = 25.6u; BackGrass.prefab scales it (1,2,1).
	BackGrass = kind({
		sprite = "Grass",
		size = Vector3.new(8.046, 16.091, 0.2),
		colors = GREENS,
		speedModifier = 1.0,
	}),
	Grass = kind({ sprite = "Grass", size = Vector3.new(8.046, 8.046, 0.2), colors = GREENS, speedModifier = 1.0 }),
	-- P2 duplicates exist in Levels.luau for parity with Unity's split-screen data
	-- but are skipped at spawn time (world/WorldScenery.client.luau) -- one lane
	-- per player already gives everyone their own copy (same reasoning as the
	-- Tutorial's tree spawners, doc 13).
	BackGrassP2 = kind({
		sprite = "Grass",
		size = Vector3.new(8.046, 16.091, 0.2),
		colors = GREENS,
		speedModifier = 1.0,
	}),
	GrassP2 = kind({ sprite = "Grass", size = Vector3.new(8.046, 8.046, 0.2), colors = GREENS, speedModifier = 1.0 }),
	Cloud3 = kind({
		sprite = "Cloud3",
		size = Vector3.new(32.183, 8.046, 0.2), -- 1024x256px @ 10
		colors = CLOUD_TINTS,
		speedModifier = 0.4,
		autoMove = Vector2.new(-1.5, 0), -- Scenery.cs autoMovement (-5,0)/(-5,0), scaled (ADAPTED)
		-- Dynamics: a slow bob and a hint of roll, wind-pushed, wobbles when tapped.
		motion = motion({ swayY = 0.45, swayPeriod = 7, roll = 1.2, rollPeriod = 9 }),
		windSensitivity = 0.7,
		reaction = "wobble",
	}),

	-- Parallax depth layers from the otherwise unused Cloud/Cloud2 art (client-only,
	-- merged into Menu and Country by `extraSpawners` below). Same sprite sheet
	-- convention as Cloud3 (CLOUD_TINTS); each is a different canvas scale, parallax
	-- speedModifier, plane and opacity so the sky reads as layers, not one cloud size.
	-- CloudFar: small, faint, nearly fixed, right in front of the backdrop tile (Z -5).
	CloudFar = kind({
		sprite = "Cloud",
		size = Vector3.new(canvas(1024, 50, 2.4), canvas(1024, 50, 2.4), 0.2), -- 1024px @ 50, shown at 2.4x
		colors = CLOUD_TINTS,
		speedModifier = 0.12,
		autoMove = Vector2.new(-0.5, 0),
		z = -4.6,
		opacity = 0.55,
		motion = motion({ swayY = 0.3, swayPeriod = 9 }),
		windSensitivity = 0.35,
	}),
	-- CloudNear: big, bright, scrolls almost with the steps, just behind them (steps are
	-- 1 stud thick at Z 0). Tappable: a quick squash-and-wobble.
	CloudNear = kind({
		sprite = "Cloud2",
		size = Vector3.new(canvas(1024, 50, 3.2), canvas(1024, 50, 3.2), 0.2), -- 1024px @ 50, shown at 3.2x
		colors = CLOUD_TINTS,
		speedModifier = 0.7,
		autoMove = Vector2.new(-1.8, 0),
		z = -1.5,
		opacity = 0.9,
		motion = motion({ swayY = 0.55, swayPeriod = 6, roll = 1.8, rollPeriod = 8, pulse = 0.015, pulsePeriod = 5 }),
		windSensitivity = 1,
		reaction = "wobble",
	}),
	-- Country: a leaf drifting down and sideways. Leaf.png is 16px @ 100 (a 0.05-stud
	-- speck at native size), so it is shown at 30x (~1.5 studs). It is a dark
	-- silhouette (the art is black + alpha), so it takes no colour tint.
	Leaf = kind({
		sprite = "Leaf",
		size = Vector3.new(canvas(16, 100, 30), canvas(16, 100, 30), 0.05),
		speedModifier = 0.9,
		autoMove = Vector2.new(0, -2.2), -- falls; the flutter below is on top
		z = -1.3,
		motion = motion({ swayX = 1.6, swayPeriod = 2.4, swayY = 0.4, roll = 40, rollPeriod = 2.4 }),
		windSensitivity = 1,
	}),

	-- Tutorial (Level1). Stars.prefab (doc 11 §3) has spawnProbability=0 -- it's a
	-- single toggled decoration, not a repeat-spawned kind; world/WorldScenery
	-- treats its "Stars" pseudo-spawner as a one-shot (spawnAllOnAwake-like).
	Stars = kind({
		sprite = "Stars",
		size = Vector3.new(49.512, 24.756, 0.2), -- 1024px @ 13, prefab scale (2,1,1)
		colors = { Color3.fromRGB(235, 235, 150) },
		speedModifier = 0.05,
	}),

	-- Pot (Level2)
	Flame = kind({
		sprite = "Flame",
		size = Vector3.new(5.029, 5.029, 0.2), -- 64px @ 4
		colors = { Color3.fromRGB(255, 130, 40) },
		speedModifier = 1.0,
		-- Dynamics: a quick size flicker and a lazy sway; a tap flares it.
		motion = motion({
			swayX = 0.25,
			swayPeriod = 1.9,
			roll = 3.5,
			rollPeriod = 1.3,
			pulse = 0.07,
			pulsePeriod = 0.45,
			flicker = 0.06,
		}),
		reaction = "flare",
	}),
	-- Pot: a bigger, fainter Flame2 (256px @ 10, shown at 1.3x) further back, so the
	-- pot wall has depth behind the foreground flames. Merged in by `extraSpawners`.
	FlameBack = kind({
		sprite = "Flame2",
		size = Vector3.new(canvas(256, 10, 1.3), canvas(256, 10, 1.3), 0.2),
		speedModifier = 0.45,
		z = -2.2,
		opacity = 0.5,
		motion = motion({
			swayX = 0.4,
			swayPeriod = 2.6,
			pulse = 0.09,
			pulsePeriod = 0.7,
			flicker = 0.08,
		}),
		reaction = "flare",
	}),
	-- Multiplayer-only UpScenerySpawner override (doc 11): MovingScenery.cs, own
	-- constant upward drift independent of pulls. Also the only "GrabableScenery"-
	-- tagged prefab (prefab dump), so it's `poppable` -- world/WorldScenery pops
	-- it on tap (doc 14 "Bubble pop").
	Bubble = kind({
		sprite = "Bubble",
		size = Vector3.new(8.046, 8.046, 0.2), -- 512px @ 20
		colors = { Color3.fromRGB(190, 225, 255) },
		moving = true,
		moveDirection = Vector2.new(0, 1),
		moveSpeed = 5,
		poppable = true,
		reaction = "pop",
		-- Dynamics: wobbles side to side as it rises, slight breathing.
		motion = motion({ swayX = 0.9, swayPeriod = 2.3, pulse = 0.05, pulsePeriod = 1.7 }),
	}),

	-- Kitchen / Country (Level3/4)
	Window = kind({
		sprite = "Window",
		size = Vector3.new(12.873, 12.873, 0.2), -- 2048px @ 50
		colors = { Color3.fromRGB(215, 228, 236) },
		speedModifier = 0.5,
	}),

	-- levelObjects, one-off per lane (doc 11 §3) -- not repeat-spawned; placed once
	-- when a lane enters the level and removed on leaving it.
	Chef = kind({
		sprite = "Chef",
		size = Vector3.new(64.366, 64.366, 0.2), -- 2048px @ 10
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
		size = Vector3.new(128.731, 112.112, 0.2), -- 2048px @ 5, prefab scale (1,0.8709,1)
		colors = { Color3.fromRGB(0, 0, 255), Color3.fromRGB(255, 0, 0) }, -- [blue, red], UnitedStates.cs `colors`
		speedModifier = 0.1,
	}),

	-- Halloween (b-20261016-125004-mog8, ideas 3 + 10; port-only, doc 17): mixed into
	-- every level's scenery by `halloweenSpawners` below while SpriteSkin.halloweenLive.
	-- Port-made 512px art (Sprites/Scenery), sized in studs directly. Each drifts on its
	-- own (autoMove) with a low parallax speedModifier, so it crosses the lane whichever
	-- way the level scrolls. Flat colours are only the un-uploaded fallback.
	-- A floating jack-o'-lantern bobbing in from the right; a tap flares it like a flame.
	JackOLantern = kind({
		sprite = "JackOLantern",
		size = Vector3.new(5, 5, 0.2),
		colors = { Color3.fromRGB(240, 120, 24) },
		speedModifier = 0.35,
		autoMove = Vector2.new(-1.2, 0),
		z = -1.6,
		motion = motion({ swayY = 0.5, swayPeriod = 3.2, roll = 6, rollPeriod = 3.6, pulse = 0.03, pulsePeriod = 0.6 }),
		reaction = "flare",
	}),
	-- A sheet ghost rising from the bottom edge, weaving side to side; wobbles on tap.
	Ghost = kind({
		sprite = "Ghost",
		size = Vector3.new(6, 6, 0.2),
		colors = { Color3.fromRGB(240, 242, 255) },
		speedModifier = 0.25,
		autoMove = Vector2.new(0, 1.3),
		z = -2,
		opacity = 0.8,
		motion = motion({ swayX = 1.4, swayPeriod = 4, swayY = 0.3, roll = 5, rollPeriod = 4 }),
		reaction = "wobble",
	}),
	-- A cobweb (with its spider) sinking slowly from the top edge, far back and faint.
	Cobweb = kind({
		sprite = "Cobweb",
		size = Vector3.new(8, 8, 0.2),
		colors = { Color3.fromRGB(230, 232, 240) },
		speedModifier = 0.5,
		autoMove = Vector2.new(0, -0.6),
		z = -2.6,
		opacity = 0.7,
		motion = motion({ swayX = 0.3, swayPeriod = 5, roll = 4, rollPeriod = 5 }),
	}),
	-- Idea 10's bat: never spawned by a spawner; WorldBatSwarm.client.luau reads its
	-- sprite/size/z and flies whole flocks of it across the local lane.
	Bat = kind({
		sprite = "Bat",
		size = Vector3.new(3.2, 1.6, 0.05), -- 512x256 canvas
		colors = { Color3.fromRGB(52, 34, 72) },
		z = -0.8,
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

-- ---------------------------------------------------------------------------
-- Client-side extra scenery spawners per level name (ADAPTED/additive).
-- Levels.luau is the gameplay data and stays untouched; WorldScenery merges these
-- with the level's own `scenerySpawners` (same SpawnerRuntime shape, same
-- direction-by-sign placement, see WorldScenery.spawnPosition). They exist for the
-- parallax-depth layers and Country's drifting leaves. `initialScatter` places that
-- many parts at random spots over the field when the spawner starts, so the sky is
-- not empty for the first minute. The key is the effective level name WorldScenery
-- uses ("Menu" while the lane is idle).
-- ---------------------------------------------------------------------------
export type ExtraSpawner = {
	name: string,
	direction: Vector2,
	pool: { string },
	cadence: SpawnerCadence,
	initialScatter: number,
}

local SKY_LAYERS: { ExtraSpawner } = {
	{
		name = "FarCloudSpawner",
		direction = Vector2.new(-1, 0),
		pool = { "CloudFar" },
		cadence = { maxSpawnCount = 5, spawningSpeedMin = 9, spawningSpeedMax = 16, spawnAllOnAwake = false },
		initialScatter = 3,
	},
	{
		name = "NearCloudSpawner",
		direction = Vector2.new(-1, 0),
		pool = { "CloudNear" },
		cadence = { maxSpawnCount = 3, spawningSpeedMin = 14, spawningSpeedMax = 24, spawnAllOnAwake = false },
		initialScatter = 1,
	},
}

local ExtraSpawners: { [string]: { ExtraSpawner } } = {
	Menu = SKY_LAYERS,
	Country = {
		SKY_LAYERS[1] :: ExtraSpawner,
		SKY_LAYERS[2] :: ExtraSpawner,
		{
			name = "LeafSpawner",
			direction = Vector2.new(0, -1), -- spawns along the top edge and falls
			pool = { "Leaf" },
			cadence = { maxSpawnCount = 14, spawningSpeedMin = 1.2, spawningSpeedMax = 2.6, spawnAllOnAwake = false },
			initialScatter = 5,
		},
	},
	Pot = {
		{
			name = "BackFlameSpawner",
			direction = Vector2.new(0, 1),
			pool = { "FlameBack" },
			cadence = { maxSpawnCount = 4, spawningSpeedMin = 3, spawningSpeedMax = 6, spawnAllOnAwake = false },
			initialScatter = 2,
		},
		-- b-20261010-191757-89n1 (ruling b-20261012-141140-a1h3): denser bubbles so the
		-- pot reads as boiling; the same poppable Bubble kind as the level's own spawner.
		{
			name = "ExtraBubbleSpawner",
			direction = Vector2.new(0, 1),
			pool = { "Bubble" },
			cadence = { maxSpawnCount = 8, spawningSpeedMin = 1.5, spawningSpeedMax = 3, spawnAllOnAwake = false },
			initialScatter = 4,
		},
	},
}

-- Halloween (b-20261016-125004-mog8, idea 3): appended to EVERY level's spawners
-- (Menu included) by WorldScenery while SpriteSkin.halloweenLive. Concurrent caps,
-- same as the other extra spawners. Each direction matches its kind's own drift:
-- lanterns enter from the right, ghosts from the bottom, cobwebs from the top.
local HalloweenSpawners: { ExtraSpawner } = {
	{
		name = "HalloweenLanternSpawner",
		direction = Vector2.new(-1, 0),
		pool = { "JackOLantern" },
		cadence = { maxSpawnCount = 2, spawningSpeedMin = 8, spawningSpeedMax = 14, spawnAllOnAwake = false },
		initialScatter = 1,
	},
	{
		name = "HalloweenGhostSpawner",
		direction = Vector2.new(0, 1),
		pool = { "Ghost" },
		cadence = { maxSpawnCount = 3, spawningSpeedMin = 5, spawningSpeedMax = 10, spawnAllOnAwake = false },
		initialScatter = 2,
	},
	{
		name = "HalloweenCobwebSpawner",
		direction = Vector2.new(0, -1),
		pool = { "Cobweb" },
		cadence = { maxSpawnCount = 2, spawningSpeedMin = 9, spawningSpeedMax = 16, spawnAllOnAwake = false },
		initialScatter = 1,
	},
}

local Kinds = {
	defs = SceneryKinds,
	cadence = SpawnerCadence,
	extraSpawners = ExtraSpawners,
	halloweenSpawners = HalloweenSpawners,
}

-- P2 duplicate spawners are intentionally never ticked (see BackGrassP2/GrassP2
-- comment above) -- world/WorldScenery.client.luau checks this instead of a
-- string-suffix guess.
function Kinds.isDuplicateSpawner(spawnerName: string): boolean
	return spawnerName:sub(-2) == "P2"
end

return Kinds
