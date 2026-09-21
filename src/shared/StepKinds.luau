--!strict
-- ReplicatedStorage/Shared/StepKinds (ModuleScript)
-- One entry per Unity step prefab (`Prefabs/Spawns/Steps/*`, doc 12 §1): which
-- Shared/StepBehaviors entry it dispatches through, its own sprite stem, its
-- Spawner.cs spawnProbability (normalized PER SPAWNER POOL by Lane.pickKind, not
-- globally -- see Spawning/Spawner.cs SetUpSpawnProbabilities/CreateSpawn), and
-- the two sizes every step needs:
--
--   `size`    -- the step PART, i.e. the sprite's whole Unity canvas. A Roblox
--                Decal always stretches the full image across the face it sits
--                on, so a part that isn't the canvas squashes the art (the same
--                rule FrogModel.model.json was rebuilt under). Derived exactly
--                like the frog rig: texture pixels / the .meta's
--                `spritePixelsToUnits` * Config.UNITY_TO_STUDS, times the
--                prefab's localScale -- which is (1,1,1) on every Step prefab
--                (doc 12 §1), so no step needs the last factor.
--   `hitSize`  -- the Unity Collider2D (doc 12 §1) in studs: what the frog can
--                actually grab. Unity's tap test is
--                `Physics2D.Raycast(worldPos, Vector2.zero)` -- a point overlap
--                against the COLLIDER (Player/Controller.cs CheckTouch), never
--                the padded canvas -- so GameClient hit-tests this rectangle
--                and the padding around it is a miss, exactly as in Unity.
--                Circle colliders become their bounding square (2r).
--   `gripOffset` -- where GameServer snaps a held limb, relative to the part's
--                (= canvas) centre. Unity moves the limb to the step
--                GameObject's `transform.position` (Player/Limb.cs `Move`),
--                which for a centred sprite pivot (alignment 0/Center) *is*
--                the canvas centre, so this is nil for most kinds. A kind
--                whose sprite uses a non-centre pivot (alignment 9/Custom)
--                needs `(pivot - 0.5) * canvasSize` here or the hand lands
--                wherever the padding put the canvas centre instead of on the
--                art (doc 17 "Sprite pivots / non-centre alignment").
--   `hitOffset` -- where GameClient centres the `hitSize` tap-test rectangle,
--                relative to the part's canvas centre. Unity's Collider2D
--                itself carries an `offset` field (doc 12 §1), always
--                relative to the prefab's `transform.position` -- the same
--                off-canvas-centre point `gripOffset` targets on a non-centre
--                pivot -- so `hitOffset = gripOffset + offset * UNITY_TO_STUDS`.
--                nil (collider centred on the canvas) for every kind whose
--                collider offset is (0,0) and whose sprite pivot is centred.
--
-- This table + Shared/Levels' per-spawner `pool` lists REPLACE the old global
-- Config.BEHAVIOR_WEIGHTS roll (doc 13 item 2): a step's behavior is a function
-- of which level/spawner/kind spawned it, not one flat game-wide table anymore.

export type Kind = {
	behavior: string, -- key into Shared/StepBehaviors
	sprite: string, -- SkinAssets sprite stem for the step's own art
	spawnProbability: number, -- Spawner.cs spawnProbability (doc 12 §1), normalized per spawner pool
	size: Vector3, -- the step part = the sprite's whole Unity canvas, in studs (see header)
	hitSize: Vector2, -- the Unity Collider2D in studs: the grabbable rectangle (see header)
	flingeeSprite: string?, -- SplashFlinging's "Flingee" child sprite (doc 12 §1 "Children of note")
	gripOffset: Vector2?, -- held-limb snap point offset from canvas centre, non-centre pivots only (see header)
	hitOffset: Vector2?, -- hitSize tap-test rectangle centre offset from canvas centre (see header)
}

-- Sprite canvases: <png pixels> / <.meta spritePixelsToUnits> * Config.UNITY_TO_STUDS.
local ART_ROCK = Vector3.new(7.314, 7.314, 1) -- 256px @ 11 -- WhiteRock, CrumblyRock, every *Arrow
local ART_WRAPPED = Vector3.new(6.437, 6.437, 1) -- WrappedRock 2048px @ 100
local ART_POTATO = Vector3.new(6.437, 6.437, 1) -- 512px @ 25
local ART_CARROT = Vector3.new(16.091, 16.091, 1) -- 512px @ 10 -- a small carrot on a very padded canvas
local ART_SHELF = Vector3.new(8.046, 8.046, 1) -- 1024px @ 40
local ART_ACORN = Vector3.new(8.046, 8.046, 1) -- 256px @ 10
local ART_CASTLE = Vector3.new(8.046, 32.183, 1) -- 256x1024px @ 10
local ART_ROCKET = Vector3.new(32.183, 32.183, 1) -- 1024px @ 10
local ART_BALLOON = Vector3.new(32.183, 32.183, 1) -- 2048px @ 20

-- Colliders: doc 12 §1's Collider column * Config.UNITY_TO_STUDS (circles -> 2r).
local HIT_ROCK = Vector2.new(6.914, 6.914) -- CircleCollider2D r=11
local HIT_POTATO = Vector2.new(5.029, 5.029) -- CircleCollider2D r=8
local HIT_CASTLE = Vector2.new(8.171, 8.171) -- CircleCollider2D r=13
local HIT_CARROT = Vector2.new(6.543, 4.461) -- BoxCollider2D size=(20.819,14.195)
local HIT_SHELF = Vector2.new(7.229, 3.143) -- BoxCollider2D size=(23,10)
local HIT_ROCKET = Vector2.new(6.521, 7.832) -- BoxCollider2D size=(20.748,24.920)
local HIT_BALLOON = Vector2.new(12.571, 12.571) -- BoxCollider2D size=(40,40)
local HIT_ACORN = Vector2.new(8.046, 8.046) -- BoxCollider2D size=(25.6,25.6), the trees' "Acorn" child

-- Grip offsets: (pivot - 0.5) * canvasSize, from the sprite's .meta (see header).
-- Carrot.png.meta: alignment 9 (Custom), spritePivot=(0.30466288, 0.3970804) --
-- the art sits low-left of its padded canvas, so Unity's transform.position
-- (where Limb.Move snaps the held hand) is that far from our canvas-centred part.
local GRIP_CARROT = Vector2.new(-3.1433, -1.6561)

-- Hit offsets: gripOffset + (Collider2D.offset * UNITY_TO_STUDS), from doc 12 §1.
-- Carrot's BoxCollider2D carries offset=(-0.091,0.547) *on top of* the pivot
-- shift above (doc 12 §1's Collider column is relative to transform.position,
-- not the canvas) -- left uncorrected, GameClient's tap-test rectangle sat
-- centred on the canvas, i.e. ~3.2 studs right and ~1.5 studs up of the actual
-- (small, low-left) carrot art, so a tap ON the visible carrot mostly missed
-- the hit box entirely (b-20260921-142133-wica).
local HIT_OFFSET_CARROT = GRIP_CARROT + Vector2.new(-0.091, 0.547) * (55 / 175) -- Config.UNITY_TO_STUDS

local StepKinds: { [string]: Kind } = {
	-- Pot (Level2) pools (doc 11 §2a)
	Potato = {
		behavior = "CrumbleAfterRelease",
		sprite = "Potato",
		spawnProbability = 0.5,
		size = ART_POTATO,
		hitSize = HIT_POTATO,
	},
	Carrot = {
		behavior = "None",
		sprite = "Carrot",
		spawnProbability = 0.5,
		size = ART_CARROT,
		hitSize = HIT_CARROT,
		gripOffset = GRIP_CARROT,
		hitOffset = HIT_OFFSET_CARROT,
	},
	UpRock = {
		behavior = "ChangeDirectionUp",
		sprite = "UpArrow",
		spawnProbability = 0.1,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
	},
	UpLeftRock = {
		behavior = "ChangeDirectionUpLeft",
		sprite = "UpLeftArrow",
		spawnProbability = 0.1,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
	},
	UpRightRock = {
		behavior = "ChangeDirectionUpRight",
		sprite = "UpRightArrow",
		spawnProbability = 0.1,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
	},

	-- Kitchen (Level3) pools add these (doc 11 §2a)
	Shelf = { behavior = "None", sprite = "Shelf", spawnProbability = 0.5, size = ART_SHELF, hitSize = HIT_SHELF },
	ShelfWithFork = {
		behavior = "SplashFlinging",
		sprite = "Shelf",
		spawnProbability = 0.5,
		size = ART_SHELF,
		hitSize = HIT_SHELF,
		flingeeSprite = "Fork",
	},
	ShelfWithSpoon = {
		behavior = "SplashFlinging",
		sprite = "Shelf",
		spawnProbability = 0.5,
		size = ART_SHELF,
		hitSize = HIT_SHELF,
		flingeeSprite = "Spoon",
	},
	LeftRock = {
		behavior = "ChangeDirectionLeft",
		sprite = "LeftArrow",
		spawnProbability = 0.1,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
	},
	RightRock = {
		behavior = "ChangeDirectionRight",
		sprite = "RightArrow",
		spawnProbability = 0.1,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
	},

	-- Country (Level4, Multiplayer-exclusive) themed pool (doc 11 §2a)
	Rocket = {
		behavior = "None",
		sprite = "Rocket",
		spawnProbability = 1.0,
		size = ART_ROCKET,
		hitSize = HIT_ROCKET,
	},
	Balloon = {
		behavior = "None",
		sprite = "Balloon",
		spawnProbability = 1.0,
		size = ART_BALLOON,
		hitSize = HIT_BALLOON,
	},

	-- Legacy `General/Spawners/*` pool (doc 11 §2b) -- not referenced by any live
	-- level's spawners, but kept as data in case a future level wants them.
	StillRock = {
		behavior = "None",
		sprite = "WrappedRock",
		spawnProbability = 0.5,
		size = ART_WRAPPED,
		hitSize = HIT_ROCK,
	},
	-- CrumblyRock.prefab ships with actionType=0 (None), not Crumble (doc 12's own
	-- "Notable/surprising findings" section) -- Unity never actually spawns a
	-- crumbling CrumblyRock. Preserved here: behavior stays "None" on purpose.
	CrumblyRock = {
		behavior = "None",
		sprite = "CrumblyRock",
		spawnProbability = 0.5,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
	},
	SlowFallRock = {
		behavior = "Fall",
		sprite = "WhiteRock",
		spawnProbability = 0.5,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
	},
	FallingRock = {
		behavior = "Falling",
		sprite = "WhiteRock",
		spawnProbability = 0.5,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
	},
	FlingingRock = {
		behavior = "SplashFlinging",
		sprite = "WrappedRock",
		spawnProbability = 0.5,
		size = ART_WRAPPED,
		hitSize = HIT_ROCK,
		flingeeSprite = "Flame",
	},
	FlyRock = {
		behavior = "SpawnFly",
		sprite = "WrappedRock",
		spawnProbability = 0.5,
		size = ART_WRAPPED,
		hitSize = HIT_ROCK,
	},
	Beetle = {
		behavior = "Beetle",
		sprite = "WrappedRock",
		spawnProbability = 0.5,
		size = ART_WRAPPED,
		hitSize = HIT_ROCK,
	},
	-- Castle.prefab also ships actionType=0 (None) -- ActionType.Castle (16) is
	-- unused by any shipped prefab (doc 12); preserved as-is.
	Castle = { behavior = "None", sprite = "Castle", spawnProbability = 0.5, size = ART_CASTLE, hitSize = HIT_CASTLE },

	-- Tutorial (Level1) tree steps (doc 11/12): the "Acorn" child Step component
	-- on every FirstTree/SecondTree/LastTree prefab ships actionType=22 (Helper),
	-- which has no case in Step.AssignInteractionAction() (dead code in Unity
	-- too) -- ported as a plain step (behavior "None") with the tree's own sprite.
	-- One lane per player (doc 13) means the P1/P2 spawner duplication Unity used
	-- for split-screen is unnecessary here -- every lane gets its own 3 trees.
	TutorialFirstTree = {
		behavior = "None",
		sprite = "Acorn",
		spawnProbability = 1.0,
		size = ART_ACORN,
		hitSize = HIT_ACORN,
	},
	TutorialSecondTree = {
		behavior = "None",
		sprite = "Acorn",
		spawnProbability = 1.0,
		size = ART_ACORN,
		hitSize = HIT_ACORN,
	},
	TutorialLastTree = {
		behavior = "None",
		sprite = "Acorn",
		spawnProbability = 1.0,
		size = ART_ACORN,
		hitSize = HIT_ACORN,
	},
}

return StepKinds
