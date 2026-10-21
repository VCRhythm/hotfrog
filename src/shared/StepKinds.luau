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
--   `tapSize`  -- OPTIONAL generous tap-only rectangle (same centre as `hitSize`,
--                i.e. `hitOffset`), used ONLY by the client tap test
--                (GameClient.stepAt, WorldTouchIndicator). Lane spawn spacing and
--                the server grab check keep using `hitSize`, so enlarging this
--                never changes layout. A tap inside `hitSize` always beats one
--                that is only inside another step's `tapSize`.
--   `color`    -- Unity's SpriteRenderer.color tint (doc 12 §1), applied to the
--                step Decal by GameServer.acquireStep. Several kinds share
--                WhiteRock.png -- a blank white silhouette by design, coloured
--                per prefab in Unity -- so this is required to tell them apart
--                (b-20260921-164509-uork); nil means untinted (white).
--   `params`   -- OPTIONAL default parameters for the kind's behaviour (each
--                StepBehaviors entry documents its keys: a Patrol's `amplitude`
--                / `period`, a Launch's `pull`, ...). A spawn that carries its
--                own (a Levels pattern member) replaces them wholesale.
--   `isArrow`  -- a ChangeDirection* step. Lane leaves these out wherever it
--                needs an ordinary foothold (the direction-change scaffold,
--                pattern members).
--   `spin`     -- false keeps the kind level: GameServer's idle spin
--                (b-20260922-194446) skips it (shelves, b-20261021-094844-4kya).
--   `hazard`   -- the step takes itself away (crumbles, drops, blinks out), so
--                it must never be the only thing on offer: Lane.pickKind caps
--                these at Config.HAZARD_MAX_RECENT of the last HAZARD_WINDOW
--                spawns and never uses one as a scaffold rung or a free pattern
--                member.
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
	tapSize: Vector2?, -- generous client-only tap rectangle around hitSize (see header)
	color: Color3?, -- Unity SpriteRenderer tint (see header); nil = untinted (white)
	params: { [string]: any }?, -- default behaviour parameters (see header)
	isArrow: boolean?, -- a ChangeDirection* step (see header)
	spin: boolean?, -- false = never idle-spins, stays level (the shelves; see header); nil = spins
	hazard: boolean?, -- removes itself; capped by Lane's fairness guard (see header)
}

-- Sprite canvases: <png pixels> / <.meta spritePixelsToUnits> * Config.UNITY_TO_STUDS.
local ART_ROCK = Vector3.new(7.314, 7.314, 1) -- 256px @ 11 -- WhiteRock, CrumblyRock, Lillipad, every *Arrow
local ART_SMALL_ROCK = Vector3.new(3.657, 3.657, 1) -- SmallRock 128px @ 11
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
-- Port additions with no Unity collider: the art's own extent on its canvas.
local HIT_LILLIPAD = Vector2.new(5.6, 5.6) -- the pad is ~196 of Lillipad.png's 256 px
local HIT_SMALL_ROCK = Vector2.new(3.657, 3.657) -- the whole 128 px canvas
local TAP_SMALL_ROCK = Vector2.new(6, 6) -- client-only: a 3.7-stud target is too small for a thumb

-- Grip offsets: (pivot - 0.5) * canvasSize, from the sprite's .meta (see header).
-- Carrot.png.meta: alignment 9 (Custom), spritePivot=(0.30466288, 0.3970804) --
-- the art sits low-left of its padded canvas, so Unity's transform.position
-- (where Limb.Move snaps the held hand) is that far from our canvas-centred part.
-- **Deliberate deviation from that Unity pivot** (owner's ruling
-- b-20260921-182516-5kv7, reopening b-20260921-152537-l4vl "the frog is
-- holding the carrot on the very end rather than its middle"): the pivot
-- above sits near the blunt end of the carrot's small, low-left art, so a
-- fist snapped exactly there reads as gripping the tip, not the carrot's
-- body. GRIP_CARROT is now targeted at the art's own geometric middle within
-- the padded canvas (~canvas-fraction (0.27, 0.37), about 0.7 studs off the
-- Unity pivot toward the canvas centre) instead of the literal pivot -- see
-- doc 17 "Deliberate deviations from Unity".
local GRIP_CARROT = Vector2.new(-3.7009, -2.0918)

-- Hit offsets: gripOffset + (Collider2D.offset * UNITY_TO_STUDS), from doc 12 §1.
-- Carrot's BoxCollider2D carries offset=(-0.091,0.547) *on top of* the pivot
-- shift above (doc 12 §1's Collider column is relative to transform.position,
-- not the canvas) -- left uncorrected, GameClient's tap-test rectangle sat
-- centred on the canvas, i.e. ~3.2 studs right and ~1.5 studs up of the actual
-- (small, low-left) carrot art, so a tap ON the visible carrot mostly missed
-- the hit box entirely (b-20260921-142133-wica).
local HIT_OFFSET_CARROT = GRIP_CARROT + Vector2.new(-0.091, 0.547) * (55 / 175) -- Config.UNITY_TO_STUDS

-- Grab at the TOP of the tall steps, not the canvas centre (b-20261020-215647-efp2;
-- a deliberate deviation, Unity's colliders sit at the art centre -- doc 17).
-- Rocket.png is upright: the yellow nose cone spans px y 80-310 of 1024 and is
-- centred at px x 500, so the point is the cone's middle, (512-210)/1024 of the
-- 32.183 canvas up, so the 7.8-stud hit box ends at the nose tip.
local GRIP_ROCKET = Vector2.new(-0.38, 9.5)
-- Castle.png (8 x 32): the battlements fill the top 60 px; the 8.17-stud hit
-- circle's box is placed flush with the canvas top (16.09 - 8.17/2).
local GRIP_CASTLE = Vector2.new(0, 12)

-- Very generous tap rectangle (owner: b-20261001-141720-tfkt): about 2x the
-- Collider2D in each axis, covering the whole visible carrot art plus margin.
-- Deliberate deviation from Unity (doc 17 "Carrot tap area").
local TAP_CARROT = Vector2.new(13, 10)

-- SpriteRenderer.color tints (doc 12 §1), applied to the step Decal by
-- GameServer.acquireStep (see `color` in the `Kind` type above). WhiteRock.png
-- is a blank white silhouette shared by several kinds -- untinted it renders
-- white regardless of the kind, which is what b-20260921-164509-uork reported.
-- Kitchen FallingRock drift (studs/s), above Config.FALLING_DRIFT_SPEED so it visibly sinks.
local FALLING_ROCK_SPEED = 24

local TINT_SALMON = Color3.new(1, 0.459, 0.395) -- FallingRock, Castle
-- Port additions (no Unity prefab): one tint per moving / timed kind, so each
-- reads at a glance against the white, salmon and black rocks above.
local TINT_SKY = Color3.new(0.45, 0.75, 1) -- BobRock
local TINT_LIME = Color3.new(0.6, 0.95, 0.3) -- SpringRock
local TINT_VIOLET = Color3.new(0.78, 0.55, 1) -- BlinkRock
-- Dead-kind revival (b-20261021-091536-8ayk, doc 19 ruling 4): one tint each.
local TINT_EMBER = Color3.new(1, 0.5, 0.12) -- FlingingRock (Pot Ember): orange coals
local TINT_GOLD = Color3.new(1, 0.88, 0.35) -- FlyRock: golden, so it differs from the plain StillRock
local TINT_PINK = Color3.new(1, 0.55, 0.78) -- SlowFallRock
local TINT_BISCUIT = Color3.new(0.88, 0.7, 0.45) -- CrumblyRock (Kitchen): toasty, so it differs from the untinted CrumbleRock

-- ExplodeAfterGrab params for the pebble-cluster rocks: the burst is grey rock chunks (Effects.client).
local PEBBLE_BURST = { burst = "Pebble" }

local StepKinds: { [string]: Kind } = {
	-- Pot (Level2) pools (doc 11 §2a)
	-- Unity: CrumbleAfterRelease; the port explodes 1 s after the grab (owner's
	-- request b-20261016-192312-l1g5, doc 17).
	Potato = {
		behavior = "ExplodeAfterGrab",
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
		tapSize = TAP_CARROT,
	},
	UpRock = {
		behavior = "ChangeDirectionUp",
		sprite = "UpArrow",
		spawnProbability = 0.1,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
		isArrow = true,
	},
	UpLeftRock = {
		behavior = "ChangeDirectionUpLeft",
		sprite = "UpLeftArrow",
		spawnProbability = 0.1,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
		isArrow = true,
	},
	UpRightRock = {
		behavior = "ChangeDirectionUpRight",
		sprite = "UpRightArrow",
		spawnProbability = 0.1,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
		isArrow = true,
	},
	-- PORT ADDITION, no Unity prefab (b-20260923-154343-9twj, ruling
	-- b-20260928-173934-iff0): the pot's rim, the Pot -> Kitchen landmark. In
	-- no spawner pool -- Lane.spawnRim places the one rim once a Pot run reaches
	-- Config.LEVEL_THRESHOLDS.Kitchen, and grabbing it IS the level-up
	-- (Lane.onStepClimbed). Art: Sprites/Rocks/PotRim.png, 722x75 px, sized to
	-- one lane's width (2 * Config.LANE_HALF_WIDTH = 44 studs, 16.41 px/stud);
	-- the grab box is the metal band between the handles, 9.5 px below the
	-- canvas centre.
	PotRim = {
		behavior = "None",
		sprite = "PotRim",
		spawnProbability = 0,
		size = Vector3.new(44, 4.571, 1),
		hitSize = Vector2.new(38.7, 3.2),
		gripOffset = Vector2.new(0, -0.579),
		hitOffset = Vector2.new(0, -0.579),
	},

	-- Kitchen (Level3) pools add these (doc 11 §2a)
	Shelf = {
		behavior = "None",
		sprite = "Shelf",
		spawnProbability = 0.5,
		size = ART_SHELF,
		hitSize = HIT_SHELF,
		spin = false,
	},
	ShelfWithFork = {
		behavior = "SplashFlinging",
		sprite = "Shelf",
		spawnProbability = 0.5,
		size = ART_SHELF,
		hitSize = HIT_SHELF,
		spin = false,
		flingeeSprite = "Fork",
	},
	ShelfWithSpoon = {
		behavior = "SplashFlinging",
		sprite = "Shelf",
		spawnProbability = 0.5,
		size = ART_SHELF,
		hitSize = HIT_SHELF,
		spin = false,
		flingeeSprite = "Spoon",
	},
	LeftRock = {
		behavior = "ChangeDirectionLeft",
		sprite = "LeftArrow",
		spawnProbability = 0.1,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
		isArrow = true,
	},
	RightRock = {
		behavior = "ChangeDirectionRight",
		sprite = "RightArrow",
		spawnProbability = 0.1,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
		isArrow = true,
	},

	-- Country (Level4, Multiplayer-exclusive) themed pool (doc 11 §2a)
	Rocket = {
		behavior = "None",
		sprite = "Rocket",
		spawnProbability = 1.0,
		size = ART_ROCKET,
		hitSize = HIT_ROCKET,
		gripOffset = GRIP_ROCKET,
		hitOffset = GRIP_ROCKET,
	},
	Balloon = {
		behavior = "None",
		sprite = "Balloon",
		spawnProbability = 1.0,
		size = ART_BALLOON,
		hitSize = HIT_BALLOON,
	},

	-- PORT ADDITIONS (b-20261020-200915-5ju4, owner's ruling
	-- b-20261020-201705-zwi7; doc 17): Country's outdoor footholds and Space's
	-- rocks. No Unity prefab or .meta, so each canvas is the port's own size
	-- for its Ludo-generated art (Sprites/Rocks/<sprite>.png) and the hit box
	-- is the art's own extent on it.
	-- A static tree trunk. TreeTrunk.png is 256x512 px; the trunk runs the
	-- canvas height but sits left of centre (a leafy twig fills the right), so
	-- the grip and hit box are shifted onto the trunk (x 38-146 px of 256).
	TreeTrunk = {
		behavior = "None",
		sprite = "TreeTrunk",
		spawnProbability = 0.4,
		size = Vector3.new(4.5, 9, 1),
		hitSize = Vector2.new(2.2, 8.4),
		gripOffset = Vector2.new(-0.63, 0),
		hitOffset = Vector2.new(-0.63, 0),
		tapSize = Vector2.new(4, 8.8),
	},
	-- The Tutorial's oak (b-20261020-205449-vnng, owner: "use the trees from
	-- tutorial too"): its Sprites/Scenery/TutorialTreeMid.png tile (1024 px, a
	-- trunk with leafy branches, already uploaded) as a static climbable trunk
	-- beside TreeTrunk. The trunk is x 430-590 px of 1024, so at 12 studs the
	-- hit box is ~2.2 studs wide and runs the canvas height.
	OakTree = {
		behavior = "None",
		sprite = "TutorialTreeMid",
		spawnProbability = 0.4,
		size = Vector3.new(12, 12, 1),
		hitSize = Vector2.new(2.2, 11.5),
		tapSize = Vector2.new(4, 11.5),
	},
	-- Cars (StepBehaviors.Drive): each drives its row at the kind's own fixed
	-- speed and knocks a frog that rides it too long off (a forced release).
	-- CarRight.png / CarLeft.png (mirrored) are 512x256 px; the body spans x
	-- 62-444 and y 9-212 px, so the hit box and grip sit ~0.38 studs above the
	-- canvas centre (off the wheels).
	CarRight = {
		behavior = "Drive",
		sprite = "CarRight",
		spawnProbability = 0.2,
		size = Vector3.new(11, 5.5, 1),
		hitSize = Vector2.new(8.2, 4.2),
		gripOffset = Vector2.new(0, 0.38),
		hitOffset = Vector2.new(0, 0.38),
		params = { speed = 2.5 },
		hazard = true,
	},
	CarLeft = {
		behavior = "Drive",
		sprite = "CarLeft",
		spawnProbability = 0.2,
		size = Vector3.new(11, 5.5, 1),
		hitSize = Vector2.new(8.2, 4.2),
		gripOffset = Vector2.new(0, 0.38),
		hitOffset = Vector2.new(0, 0.38),
		params = { speed = -3.5 },
		hazard = true,
	},
	-- Space's plain rock (Asteroid.png, 256 px, the rock canvas and collider).
	-- It alone stands in for Country's three shelf kinds (0.5 each), so it
	-- carries their summed weight and the arrows keep their share.
	Asteroid = {
		behavior = "None",
		sprite = "Asteroid",
		spawnProbability = 1.5,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
	},

	-- Legacy `General/Spawners/*` pool (doc 11 §2b). StillRock, FlingingRock and
	-- SlowFallRock are live again (b-20261021-091536-8ayk, doc 19 ruling 4, doc 17),
	-- CrumblyRock and FallingRock in Kitchen (b-20261021-091536-2ymu), Beetle in
	-- Country with its own art (b-20261021-091537-rv4a).
	-- Country plain rock (weight 0.4 per stage in Levels); untinted mossy
	-- WrappedRock, so FlyRock wears a tint to differ.
	StillRock = {
		behavior = "None",
		sprite = "WrappedRock",
		spawnProbability = 0.5,
		size = ART_WRAPPED,
		hitSize = HIT_ROCK,
	},
	-- CrumblyRock.prefab ships with actionType=0 (None), not Crumble (doc 12's own
	-- "Notable/surprising findings" section) -- Unity never actually spawns a
	-- crumbling CrumblyRock, and this kind used to stay "None" to match. The owner
	-- overrode that (b-20261021-095009-vou1: the pebble-cluster rocks should shake
	-- and turn into a spray of pebbles, like the Potato): it now runs the Potato's
	-- ExplodeAfterGrab with a pebble burst, so it is a hazard (never the only
	-- thing on offer, never swapped for a Halloween pumpkin).
	CrumblyRock = {
		behavior = "ExplodeAfterGrab",
		sprite = "CrumblyRock",
		spawnProbability = 0.5,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
		color = TINT_BISCUIT,
		params = PEBBLE_BURST,
		hazard = true,
	},
	-- Country hazard in its later stages (Levels), own pink tint.
	SlowFallRock = {
		behavior = "Fall",
		sprite = "WhiteRock",
		spawnProbability = 0.5,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
		color = TINT_PINK,
		hazard = true,
	},
	FallingRock = {
		behavior = "Falling",
		sprite = "WhiteRock",
		spawnProbability = 0.5,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
		color = TINT_SALMON,
		hazard = true,
		params = { speed = FALLING_ROCK_SPEED },
	},
	-- The Pot's Ember (PORT DEVIATION from Unity's WrappedRock prefab): orange-tinted
	-- CrumblyRock art that flings a harmless Flame on grab. Not a hazard, so the
	-- Halloween pumpkin swap may replace it.
	FlingingRock = {
		behavior = "SplashFlinging",
		sprite = "CrumblyRock",
		spawnProbability = 0.5,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
		flingeeSprite = "Flame",
		color = TINT_EMBER,
	},
	FlyRock = {
		behavior = "SpawnFly",
		sprite = "WrappedRock",
		spawnProbability = 0.5,
		size = ART_WRAPPED,
		hitSize = HIT_ROCK,
		color = TINT_GOLD,
	},
	-- Country hazard from stage 2 (Levels; b-20261021-091537-rv4a, doc 19 ruling
	-- 4). PORT DEVIATION from Unity's black-tinted WhiteRock: its own Beetle.png
	-- (256 px, a red ladybug facing right, untinted) on the rock canvas. The bug
	-- spans x 5-251, y 61-194 px (centred), so the hit box is that extent
	-- (~7.0 x 3.8 studs) rather than the rock circle. `hazard`: its first grab
	-- is always shrugged off (a forced release, like the cars), so it never
	-- stands alone and Halloween never swaps it.
	Beetle = {
		behavior = "Beetle",
		sprite = "Beetle",
		spawnProbability = 0.5,
		size = ART_ROCK,
		hitSize = Vector2.new(6.9, 3.7),
		tapSize = Vector2.new(7.3, 5.5),
		hazard = true,
	},
	-- Castle.prefab also ships actionType=0 (None) -- ActionType.Castle (16) is
	-- unused by any shipped prefab (doc 12); preserved as-is.
	Castle = {
		behavior = "None",
		sprite = "Castle",
		spawnProbability = 0.5,
		size = ART_CASTLE,
		hitSize = HIT_CASTLE,
		gripOffset = GRIP_CASTLE,
		hitOffset = GRIP_CASTLE,
		color = TINT_SALMON,
	},

	-- -----------------------------------------------------------------------
	-- PORT ADDITIONS: dynamic kinds with no Unity prefab (doc 17). Each rides a
	-- behaviour Unity's ActionType enum names but never implemented (Patrol
	-- stands in for Move), or one no shipped prefab uses (Crumble). They appear
	-- only where Shared/Levels' height stages, patterns and events name them --
	-- never in the Tutorial. `spawnProbability` is the weight in a pool whose
	-- level has no height stage listing the kind.
	-- -----------------------------------------------------------------------
	-- Glides left and right. Under straight-down travel Lane keeps the whole
	-- sweep inside the portrait view (Config.SPAWN_VIEW_HALF_WIDTH).
	Lillipad = {
		behavior = "Patrol",
		sprite = "Lillipad",
		spawnProbability = 0.15,
		size = ART_ROCK,
		hitSize = HIT_LILLIPAD,
		params = { amplitude = 2.5, period = 3.5 },
	},
	-- Bobs up and down.
	BobRock = {
		behavior = "RiseAndFall",
		sprite = "WhiteRock",
		spawnProbability = 0.15,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
		color = TINT_SKY,
		params = { amplitude = 1.5, period = 2.5 },
	},
	-- Springboard: its grab pulls the field a further `pull` studs.
	SpringRock = {
		behavior = "Launch",
		sprite = "WhiteRock",
		spawnProbability = 0.1,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
		color = TINT_LIME,
		params = { pull = 8 },
	},
	-- Timed: `delay` seconds in view, `warn` seconds of blinking, then it drops
	-- away whether or not it is held.
	BlinkRock = {
		behavior = "Vanish",
		sprite = "SmallRock",
		spawnProbability = 0.1,
		size = ART_SMALL_ROCK,
		hitSize = HIT_SMALL_ROCK,
		tapSize = TAP_SMALL_ROCK,
		color = TINT_VIOLET,
		params = { delay = 3, warn = 1.5 },
		hazard = true,
	},
	-- Themed replacements (b-20261021-091537-rv4a, doc 19 ruling 1B / section 4):
	-- each copies the behaviour, weight and params of the rock it stands in for
	-- in its level's role map (Levels), on its own Ludo art. Untinted: the art
	-- reads on its own, where a lime / violet multiply would muddy it.
	-- Kitchen's Launch kind (SpringRock elsewhere). Toaster.png is 512 px on
	-- the shelf canvas; the toaster spans x 6-506, y 78-433 px (centred), the
	-- body without the lever, knob and feet ~x 38-492, y 78-415, which is the
	-- hit box; the tap pad covers the whole visible toaster.
	Toaster = {
		behavior = "Launch",
		sprite = "Toaster",
		spawnProbability = 0.1,
		size = ART_SHELF,
		hitSize = Vector2.new(7.1, 5.3),
		tapSize = Vector2.new(8, 5.8),
		params = { pull = 8 },
	},
	-- Kitchen's Vanish kind (BlinkRock elsewhere): an ice cube that melts away.
	-- IceCube.png is 128 px and nearly fills it (x 4-124, y 4-123), so it takes
	-- BlinkRock's small-rock canvas, hit box and tap pad.
	IceCube = {
		behavior = "Vanish",
		sprite = "IceCube",
		spawnProbability = 0.1,
		size = ART_SMALL_ROCK,
		hitSize = HIT_SMALL_ROCK,
		tapSize = TAP_SMALL_ROCK,
		params = { delay = 3, warn = 1.5 },
		hazard = true,
	},
	-- Country's Launch kind (replaced the Trampoline, owner request 9uqb): a
	-- low pile of banknotes and coins. CashPile.png is 512x256 px on an 8 x 4
	-- canvas (64 px/stud); the pile spans x 4-508, y 59-196 px (centred), about
	-- 7.9 x 2.1 studs, so the hit box is that extent (a hair narrower, as the
	-- top is a narrow mound) and a taller tap pad keeps it thumb-sized.
	CashPile = {
		behavior = "Launch",
		sprite = "CashPile",
		spawnProbability = 0.1,
		size = Vector3.new(8, 4, 1),
		hitSize = Vector2.new(7.8, 2),
		tapSize = Vector2.new(8, 3.6),
		params = { pull = 8 },
	},
	-- Space's RiseAndFall kind (BobRock elsewhere): a flying saucer that bobs.
	-- UFO.png is 512x256 px on an 8 x 4 canvas (64 px/stud); the saucer spans
	-- x 6-507, y 47-209 px (centred), 7.8 x 2.5 studs, which is the hit box; the
	-- tap pad adds height to stay thumb-sized. Params and weight are BobRock's.
	UFO = {
		behavior = "RiseAndFall",
		sprite = "UFO",
		spawnProbability = 0.15,
		size = Vector3.new(8, 4, 1),
		hitSize = Vector2.new(7.8, 2.5),
		tapSize = Vector2.new(8, 3.6),
		params = { amplitude = 1.5, period = 2.5 },
	},
	-- Space's second Patrol kind, beside Lillipad (which keeps the Patrol role
	-- everywhere, z0a9). Satellite.png is 512x256 px on an 8 x 4 canvas; the
	-- satellite with its panels spans x 6-506, y 79-178 px (centred), 7.8 x 1.5
	-- studs, so the tap pad is taller than the hit box. Params are Lillipad's.
	Satellite = {
		behavior = "Patrol",
		sprite = "Satellite",
		spawnProbability = 0.15,
		size = Vector3.new(8, 4, 1),
		hitSize = Vector2.new(7.8, 1.5),
		tapSize = Vector2.new(8, 3.4),
		params = { amplitude = 2.5, period = 3.5 },
	},
	-- CrumblyRock's art, untinted. Same shake-then-pebble-burst life as
	-- CrumblyRock above (b-20261021-095009-vou1); it was StepBehaviors.Crumble
	-- (Unity's never-used 1.5 s fuse), now the Potato's Config.EXPLODE_FUSE.
	CrumbleRock = {
		behavior = "ExplodeAfterGrab",
		sprite = "CrumblyRock",
		spawnProbability = 0.1,
		size = ART_ROCK,
		hitSize = HIT_ROCK,
		params = PEBBLE_BURST,
		hazard = true,
	},

	-- PORT ADDITION (b-20261016-192144-g2e2, doc 17): the Halloween pumpkin, a
	-- plain solid step. In no spawner pool -- while SpriteSkin.halloweenLive,
	-- Lane.pickKind swaps Config.HALLOWEEN_PUMPKIN_CHANCE of its ordinary picks
	-- for it. Art: the 512 px Sprites/Scenery/JackOLantern.png on Potato's canvas
	-- and grab box (the pumpkin fills about the same share of its canvas).
	Pumpkin = {
		behavior = "None",
		sprite = "JackOLantern",
		spawnProbability = 0,
		size = ART_POTATO,
		hitSize = HIT_POTATO,
	},

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
