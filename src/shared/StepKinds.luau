--!strict
-- ReplicatedStorage/Shared/StepKinds (ModuleScript)
-- One entry per Unity step prefab (`Prefabs/Spawns/Steps/*`, doc 12 §1): which
-- Shared/StepBehaviors entry it dispatches through, its own sprite stem, its
-- Spawner.cs spawnProbability (normalized PER SPAWNER POOL by Lane.pickKind, not
-- globally -- see Spawning/Spawner.cs SetUpSpawnProbabilities/CreateSpawn), and
-- an optional Size override for the step part (StepTemplate's own Size is the
-- default for anything not listed here).
--
-- This table + Shared/Levels' per-spawner `pool` lists REPLACE the old global
-- Config.BEHAVIOR_WEIGHTS roll (doc 13 item 2): a step's behavior is a function
-- of which level/spawner/kind spawned it, not one flat game-wide table anymore.

export type Kind = {
	behavior: string, -- key into Shared/StepBehaviors
	sprite: string, -- SkinAssets sprite stem for the step's own art
	spawnProbability: number, -- Spawner.cs spawnProbability (doc 12 §1), normalized per spawner pool
	size: Vector3?, -- override StepTemplate's default Size; nil keeps the template's
	flingeeSprite: string?, -- SplashFlinging's "Flingee" child sprite (doc 12 §1 "Children of note")
}

local SHELF_SIZE = Vector3.new(6, 2.6, 1) -- BoxCollider2D size=(23,10), doc 12 -- wider/flatter than a rock
local ROCKET_SIZE = Vector3.new(5, 6, 1) -- BoxCollider2D size=(20.7,24.9), doc 12
local BALLOON_SIZE = Vector3.new(5, 5, 1) -- BoxCollider2D size=(40,40), doc 12

local StepKinds: { [string]: Kind } = {
	-- Pot (Level2) pools (doc 11 §2a)
	Potato = { behavior = "CrumbleAfterRelease", sprite = "Potato", spawnProbability = 0.5 },
	Carrot = { behavior = "None", sprite = "Carrot", spawnProbability = 0.5 },
	UpRock = { behavior = "ChangeDirectionUp", sprite = "UpArrow", spawnProbability = 0.1 },
	UpLeftRock = { behavior = "ChangeDirectionUpLeft", sprite = "UpLeftArrow", spawnProbability = 0.1 },
	UpRightRock = { behavior = "ChangeDirectionUpRight", sprite = "UpRightArrow", spawnProbability = 0.1 },

	-- Kitchen (Level3) pools add these (doc 11 §2a)
	Shelf = { behavior = "None", sprite = "Shelf", spawnProbability = 0.5, size = SHELF_SIZE },
	ShelfWithFork = {
		behavior = "SplashFlinging",
		sprite = "Shelf",
		spawnProbability = 0.5,
		size = SHELF_SIZE,
		flingeeSprite = "Fork",
	},
	ShelfWithSpoon = {
		behavior = "SplashFlinging",
		sprite = "Shelf",
		spawnProbability = 0.5,
		size = SHELF_SIZE,
		flingeeSprite = "Spoon",
	},
	LeftRock = { behavior = "ChangeDirectionLeft", sprite = "LeftArrow", spawnProbability = 0.1 },
	RightRock = { behavior = "ChangeDirectionRight", sprite = "RightArrow", spawnProbability = 0.1 },

	-- Country (Level4, Multiplayer-exclusive) themed pool (doc 11 §2a)
	Rocket = { behavior = "None", sprite = "Rocket", spawnProbability = 1.0, size = ROCKET_SIZE },
	Balloon = { behavior = "None", sprite = "Balloon", spawnProbability = 1.0, size = BALLOON_SIZE },

	-- Legacy `General/Spawners/*` pool (doc 11 §2b) -- not referenced by any live
	-- level's spawners, but kept as data in case a future level wants them.
	StillRock = { behavior = "None", sprite = "WrappedRock", spawnProbability = 0.5 },
	-- CrumblyRock.prefab ships with actionType=0 (None), not Crumble (doc 12's own
	-- "Notable/surprising findings" section) -- Unity never actually spawns a
	-- crumbling CrumblyRock. Preserved here: behavior stays "None" on purpose.
	CrumblyRock = { behavior = "None", sprite = "CrumblyRock", spawnProbability = 0.5 },
	SlowFallRock = { behavior = "Fall", sprite = "WhiteRock", spawnProbability = 0.5 },
	FallingRock = { behavior = "Falling", sprite = "WhiteRock", spawnProbability = 0.5 },
	FlingingRock = {
		behavior = "SplashFlinging",
		sprite = "WrappedRock",
		spawnProbability = 0.5,
		flingeeSprite = "Flame",
	},
	FlyRock = { behavior = "SpawnFly", sprite = "WrappedRock", spawnProbability = 0.5 },
	Beetle = { behavior = "Beetle", sprite = "WrappedRock", spawnProbability = 0.5 },
	-- Castle.prefab also ships actionType=0 (None) -- ActionType.Castle (16) is
	-- unused by any shipped prefab (doc 12); preserved as-is.
	Castle = { behavior = "None", sprite = "Castle", spawnProbability = 0.5 },

	-- Tutorial (Level1) tree steps (doc 11/12): the "Acorn" child Step component
	-- on every FirstTree/SecondTree/LastTree prefab ships actionType=22 (Helper),
	-- which has no case in Step.AssignInteractionAction() (dead code in Unity
	-- too) -- ported as a plain step (behavior "None") with the tree's own sprite.
	-- One lane per player (doc 13) means the P1/P2 spawner duplication Unity used
	-- for split-screen is unnecessary here -- every lane gets its own 3 trees.
	TutorialFirstTree = { behavior = "None", sprite = "Acorn", spawnProbability = 1.0 },
	TutorialSecondTree = { behavior = "None", sprite = "Acorn", spawnProbability = 1.0 },
	TutorialLastTree = { behavior = "None", sprite = "Acorn", spawnProbability = 1.0 },
}

return StepKinds
