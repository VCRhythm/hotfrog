--!strict
-- ServerScriptService/Server/Lane (ModuleScript)
-- One PlayField "lane" per player (doc 13): everything that used to be a single
-- global field (Spawning/SpawnManager.cs + Core/LevelManager.cs, once one field
-- per whole game) becomes per-player state here -- spawn direction, spawner
-- pools/counts, level/run progress, and the lane's origin offset along X
-- (Config.LANE_SPACING). GameServer owns the step *instance* pool, the frog, and
-- remote handlers; it drives a lane through the methods below every Heartbeat
-- and on grab/release/level events. BugService discovers lanes independently,
-- through the `workspace.PlayField.Lanes` folder's attributes -- it never
-- requires this module (doc 13 item 7).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PullMath = require(ReplicatedStorage.Shared.PullMath)
local Levels = require(ReplicatedStorage.Shared.Levels)
local StepKinds = require(ReplicatedStorage.Shared.StepKinds)
local StepBehaviors = require(ReplicatedStorage.Shared.StepBehaviors)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local Profiles = require(script.Parent.Profiles)

export type SpawnerState = {
	def: Levels.StepSpawnerDef,
	spawnCount: number,
	timer: number, -- seconds until the next spawn attempt (continuous spawners)
	awoken: boolean, -- spawnAllOnAwake spawners fire once, then stay dormant
	-- Movements-list cycling (only meaningful when #def.movements > 0 -- see
	-- Lane.updateMovement / Lane.currentMovementOffset below). Mirrors Spawner.cs's own
	-- `transform.position`, which the Move() coroutine (Spawner.cs L123-147) advances
	-- independently of spawning itself; CreateSpawn() (L192-214) just reads whatever that
	-- position currently is when it fires.
	moveToIndex: number, -- 1-based index into def.movements `moveTo` was picked from; 0 = not yet started
	moveFrom: Vector3, -- tween start point (continuous movers only; unused when discrete)
	moveTo: Vector3, -- current leg's destination / settle point
	moveElapsed: number, -- seconds into the current leg
	moveTweenTime: number, -- this leg's tween duration (0 = discrete instant jump)
	moveWaitTime: number, -- total leg length before the next re-pick (tweenTime + nextMoveTime)
}

-- One eased displacement of this lane's steps (see "Motions" below). `only` nil
-- = a pull: every step in `active` on each frame it runs, including steps spawned
-- after it started. `only` set = a slide-in of just those steps, or the
-- Kitchen Chef's shove of one step (server/Chef.luau via GameServer).
export type Motion = {
	delta: Vector3,
	duration: number,
	elapsed: number,
	only: { [BasePart]: boolean }?,
}

-- One live step's motion state (the "step motion layer"; GameServer composes it
-- into the part's CFrame once per Heartbeat, and is the only writer of that
-- CFrame). A step part is pooled and its CFrame used to be its only state, with
-- four writers adding to it each tick; anything that wobbles would then have
-- leaked into spawn spacing and pull aim, which read the part's Position. So the
-- state is split:
--   * `base` is where the step logically IS. Motions (pulls, slide-ins), Classic
--     drift, Falling and a drop-away move it, and everything in this module that
--     asks "where is / where will this step rest" reads it.
--   * `offset`, `recoil` and `sag` are bounded visual displacement on top, and
--     `angle` the idle spin. They are in the replicated CFrame (so taps and a
--     held limb follow them) but never in `base`.
-- Created by Lane.trackStep when GameServer.acquireStep takes a part out of the
-- pool, dropped by Lane.untrackStep when it goes back. The table itself is the
-- step's generation: a pooled part's next life gets a new one.
export type StepState = {
	base: Vector3,
	angle: number, -- Z rotation, radians (idle spin, frozen on grab)
	spinRate: number?, -- rad/s while it still tumbles; nil once grabbed (and for the pot's rim)
	zBias: number, -- this step's fixed depth nudge off the play plane (GameServer.nextZBias): overlapping step decals sort the same way every frame
	offset: Vector3, -- the behaviour's visual offset (StepBehaviors ctx.setOffset)
	-- How far `offset` may carry the step from `base`, per axis (the behaviour's
	-- `sweep`); clearSpot keeps other steps' grab boxes out of that whole extent.
	sweep: Vector2,
	recoil: Vector3, -- grab-recoil spring displacement and velocity (GameServer)
	recoilVelocity: Vector3,
	sag: number, -- studs the step currently hangs below its base under a held limb
	dropElapsed: number?, -- seconds into a drop-away (ctx.dropAway); nil when not dropping
	-- Studs this step was deliberately staged upstream of an ordinary spawn (a
	-- pattern member behind the ones before it, SpawnRequest.upstream); 0 for
	-- every other step. Lane.isOutOfBounds allows it that much past the bounds.
	upstream: number,
	behavior: StepBehaviors.Behavior, -- resolved once at acquire, not re-read from the attribute each tick
	params: StepBehaviors.Params, -- this spawn's parameters (acquireStep opts.params)
	scratch: { [string]: any }, -- the behaviour's own per-step state (ctx.state)
	ctx: StepBehaviors.Ctx?, -- built on first use, reused until the step is released
	shownPosition: Vector3, -- what the part's CFrame was last written from,
	shownAngle: number, -- so an unchanged step costs no write (or replication)
}

local NO_PARAMS: StepBehaviors.Params = table.freeze({})

local Lane = {}
Lane.__index = Lane

export type Lane = typeof(setmetatable(
	{} :: {
		player: Player,
		userId: number,
		slot: number,
		origin: Vector3,
		folder: Folder,
		levelIndex: number,
		level: Levels.Level,
		spawnDirection: Vector2,
		-- spawnDirection as a unit Vector3 on the play plane (zero when the lane
		-- has no direction): the way this lane's steps travel. Kept in step with
		-- spawnDirection by setTravel, its only writer.
		travel: Vector3,
		spawnerStates: { SpawnerState },
		activeSpawners: { SpawnerState },
		active: { [BasePart]: boolean }, -- this lane's own live steps
		-- Each live step's motion state (StepState above), same keys as `active`
		-- (Lane.trackStep / Lane.untrackStep keep the two in step).
		states: { [BasePart]: StepState },
		-- Pulls and slide-ins still playing (Lane.addMotion / advanceMotions).
		motions: { Motion },
		-- Net forward scroll (studs) accumulated since this level began, floored at 0.
		-- Exists so the Tutorial "no death" retry (GameServer.tutorialRetry) can never
		-- undo more scroll than has actually happened -- see Lane.addPull below.
		netPull: number,
		-- Run mode (Config.RUN_MODES), chosen per run with StartRun and mirrored
		-- as the folder's `Mode` attribute. "Classic" adds a constant scroll
		-- (Lane.drift) on top of the per-grab pulls.
		mode: string,
		-- Classic drift scrolled since the last settled chunk (studs, seconds).
		driftDistance: number,
		driftTime: number,
		-- Seconds of actual Classic drift (Lane.driftSpeed) since this run's
		-- ramp last reset (Lane.setMode / Lane.resetRun) -- feeds the Classic
		-- speed ramp (Config.CLASSIC_SCROLL_ACCEL_RATE). Carries across this
		-- run's level transitions; never advances outside Classic mode or on a
		-- level with no CLASSIC_SCROLL_SPEED entry (e.g. Tutorial).
		driftElapsed: number,
		-- Lane.driftSpeed's own chasing base speed (studs/s, b-20260923-154345-g9ea):
		-- ramps toward Config.CLASSIC_SCROLL_SPEED[level] at CLASSIC_LEVEL_RAMP_TIME
		-- instead of snapping to it, so a level transition's base-speed jump (e.g.
		-- Pot -> Kitchen) blends in. 0 = not yet drifting this run (driftSpeed then
		-- snaps straight to the current level's base with no ramp). Reset by
		-- Lane.setMode / Lane.resetRun; NOT reset by Lane.setLevel, so it keeps
		-- ramping across a level transition instead of restarting at 0.
		driftBase: number,
		-- Seconds of Classic drift still held off after a level-up (Lane.beginArrival,
		-- b-20260923-154343-3h60): Lane.driftSpeed returns 0 and freezes both
		-- ramps until it runs out, then driftBase's CLASSIC_LEVEL_RAMP_TIME blend
		-- starts. Counts down only while drift would otherwise run (frog armed and
		-- alive). Reset by Lane.setMode / Lane.resetRun.
		driftHold: number,
		-- 1-based cursor into `self.level.introSequence` (Levels.luau); nil-safe --
		-- levels without introSequence never read it. Reset to 1 by Lane.setLevel.
		introIndex: number,
		-- The client's Roblox PlayerList rectangle (lane-relative studs, validated
		-- by GameServer's ScreenObstruction handler), nil while the list is closed
		-- or unknown. Grab pulls and spawns keep step grab boxes out of it while
		-- the lane isn't drifting (Lane.obstructionExtra / Lane.clearSpot).
		obstruction: Rect?,
		runSteps: number, -- steps climbed this run, across levels (drives LEVEL_THRESHOLDS)
		-- runSteps when this lane entered its current level (Lane.setLevel): what a
		-- level flagged `stagesFromEntry` (Levels.luau) counts its height stages and
		-- event thresholds from, since the step a level really begins on varies.
		levelStartSteps: number,
		-- Fairness guard (Lane.pickKind): a ring of this lane's last
		-- Config.HAZARD_WINDOW spawned steps -- true = a StepKinds `hazard` kind --
		-- with its write cursor and how many of them are true.
		recentHazards: { boolean },
		recentCursor: number,
		hazardCount: number,
		-- Levels EventDef name -> runSteps when it last fired on this lane (its cooldown).
		eventLast: { [string]: number },
		tutorialStepsClimbed: number,
		-- Tutorial "no death" protection (GameServer.tutorialRetry), true for a run
		-- that started in the Tutorial and hasn't yet grabbed a real (non-tree) step.
		-- Stays true across the Tutorial -> Pot soft transition (onStepClimbed, on the
		-- 3rd tree) so a fall between that transition and the first Pot grab still
		-- retries instead of killing (b-20260922-101541-w1i2) -- false from the start
		-- for a run that skips the Tutorial (tutorialDone already true).
		tutorialGraceActive: boolean,
		-- called explicitly by whichever method changes the level, WITH the
		-- transition kind ("start" | "soft" | "death") -- never auto-fired from
		-- setLevel itself, so callers control the label (doc 13 item 6).
		notify: ((Lane, string) -> ())?,
	},
	Lane
))

-- One step a lane wants created: the single shape every spawn path -- spawner,
-- pattern, event, prefill, the Tutorial batch, scaffold, the pot's rim -- hands
-- to GameServer, which owns the pooled Instances (acquireStep). `position` is
-- where to create the part NOW: its rest point less whatever the lane's running
-- pulls still owe it.
export type SpawnRequest = {
	kindName: string,
	position: Vector3,
	params: StepBehaviors.Params?, -- the behaviour's parameters for this spawn (StepKinds default or a pattern member's)
	spawner: SpawnerState?, -- the spawner it came from; nil for the scaffold and the rim
	source: string, -- "spawner" | "pattern" | "event" | "prefill" | "awake" | "scaffold" | "rim"
	upstream: number?, -- studs it is staged past an ordinary spawn's spot (StepState.upstream); nil = 0
}
export type SpawnFn = (lane: Lane, request: SpawnRequest) -> ()

-- ---------------------------------------------------------------------------
-- Registry + slot allocation. Slots are reused (doc 13 item 1): the first lane
-- ever created always lands on slot 0 (origin X=0), matching the pre-lanes
-- single-player layout exactly, and later lanes alternate outward
-- (1, -1, 2, -2, ...) so the field stays centered as players come and go.
-- ---------------------------------------------------------------------------
local registry: { [Player]: Lane } = {}
local freeSlots: { number } = {}
local slotCounter = 0

local function nextSlot(): number
	if #freeSlots > 0 then
		return table.remove(freeSlots) :: number
	end
	local n = slotCounter
	slotCounter += 1
	if n == 0 then
		return 0
	elseif n % 2 == 1 then
		return (n + 1) // 2
	else
		return -(n // 2)
	end
end

local function releaseSlot(slot: number)
	table.insert(freeSlots, slot)
end

function Lane.get(player: Player): Lane?
	return registry[player]
end

-- Iterate every live lane: `for player, lane in Lane.iter() do ... end`.
function Lane.iter(): { [Player]: Lane }
	return registry
end

-- ---------------------------------------------------------------------------
-- Direction matching (doc 13 item 3): match by SIGN of each component instead
-- of Unity's exact-Vector2-equality dictionary lookup, which the doc 11 §4
-- extraction shows never actually matches the half-magnitude diagonal/side
-- spawners shipped in Level2-4 against the registered full-unit-vector keys --
-- a latent Unity bug this port deliberately does not reproduce.
-- ---------------------------------------------------------------------------
local function signOf(n: number): number
	if n > 1e-4 then
		return 1
	elseif n < -1e-4 then
		return -1
	else
		return 0
	end
end

local function directionKey(v: Vector2): string
	return signOf(v.X) .. "," .. signOf(v.Y)
end

-- The one place a lane's direction is set: keeps `travel` (the unit Vector3
-- every pull, drift and spawn moves along) in step with `spawnDirection`.
local function setTravel(self: Lane, direction: Vector2)
	self.spawnDirection = direction
	self.travel = if direction.Magnitude < 1e-4 then Vector3.zero else Vector3.new(direction.X, direction.Y, 0).Unit
end

function Lane.spawnersForDirection(self: Lane, dir: Vector2): { SpawnerState }
	local key = directionKey(dir)
	local out: { SpawnerState } = {}
	for _, state in self.spawnerStates do
		if directionKey(state.def.direction) == key then
			table.insert(out, state)
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Level / spawner-set management (Core/LevelManager.cs SetUpSpawners +
-- Spawning/SpawnManager.cs SetUpLevel). Soft transition (doc 13 item 5): this
-- only swaps which spawner pools are live going forward -- it never touches
-- `self.active`, so steps the frog is already holding or approaching keep
-- scrolling exactly as they were.
-- ---------------------------------------------------------------------------
function Lane.setLevel(self: Lane, levelIndex: number)
	self.levelIndex = levelIndex
	local level = Levels.list[levelIndex]
	self.level = level
	setTravel(self, level.initialSpawnDirection)
	self.eventLast = {} -- event cooldowns are per level
	self.levelStartSteps = self.runSteps -- the level's own step count starts here (stageSteps)
	self.netPull = 0 -- fresh scroll baseline for this level (see Lane.addPull)
	self.introIndex = 1 -- fresh cursor into the new level's introSequence, if any

	local states: { SpawnerState } = {}
	for _, def in level.stepSpawners do
		table.insert(states, {
			def = def,
			spawnCount = 0,
			timer = 0,
			awoken = false,
			moveToIndex = 0,
			moveFrom = Vector3.zero,
			moveTo = Vector3.zero,
			moveElapsed = 0,
			moveTweenTime = 0,
			moveWaitTime = 0,
		})
	end
	self.spawnerStates = states
	self.activeSpawners = self:spawnersForDirection(self.spawnDirection)
	if #self.activeSpawners == 0 and #states > 0 then
		warn(("[Lane] %s: level %q's initialSpawnDirection matches no spawner"):format(self.player.Name, level.name))
	end

	self.folder:SetAttribute("Level", level.name)
	self:updateStageAttribute()
end

-- A grabbed ChangeDirection* step (StepBehaviors setSpawnBias) asks to steer the
-- lane. Per doc 13 item 3: if this level has no spawner for the requested
-- direction, keep the CURRENT direction active rather than starving the lane.
-- Returns true when the direction actually changed (GameServer then scaffolds).
function Lane.changeDirection(self: Lane, newDirection: Vector2): boolean
	local matches = self:spawnersForDirection(newDirection)
	if #matches == 0 then
		return false
	end
	local changed = directionKey(newDirection) ~= directionKey(self.spawnDirection)
	setTravel(self, newDirection)
	self.activeSpawners = matches
	return changed
end

-- ---------------------------------------------------------------------------
-- Height-stage lookup (b-20260923-154344-dr8a, journey 3/8): the stage from
-- `self.level.heightStages` (Levels.luau: Pot, Kitchen, Country, Space) whose
-- `maxRunSteps` bound isn't yet passed, plus its 1-based index -- nil, nil for
-- a level with no heightStages (Menu, Tutorial). The bounds are in stageSteps:
-- the whole run's steps for the Pot, steps since the lane entered the level for
-- Kitchen, Country and Space (Levels `stagesFromEntry`). Used by both Lane.pickKind
-- (weight overrides) and Lane.updateStageAttribute (the replicated `Stage`
-- attribute WorldScenery reads for its Bubble/Flame density).
-- ---------------------------------------------------------------------------

-- The step count this lane's level measures its height stages and event
-- thresholds in. A level flagged `stagesFromEntry` counts from where the lane
-- entered it: Kitchen does not begin at LEVEL_THRESHOLDS.Kitchen but a few steps
-- later -- the rim is laid there, and the Pot steps still below it plus the rim
-- grab itself all count -- so bounds written as "threshold + n" cut its first
-- stage short by however many that was. Every other level counts the whole run.
local function stageSteps(self: Lane): number
	return if self.level.stagesFromEntry then self.runSteps - self.levelStartSteps else self.runSteps
end

local function currentHeightStage(self: Lane): (Levels.HeightStage?, number?)
	local stages = self.level.heightStages
	if not stages then
		return nil, nil
	end
	local steps = stageSteps(self)
	for i, stage in stages do
		if steps < stage.maxRunSteps then
			return stage, i
		end
	end
	return stages[#stages], #stages
end

-- Sets (or clears) the lane folder's `Stage` attribute to the current height
-- stage's 1-based index -- nil on a level with no heightStages. Called
-- whenever the level or runSteps changes (Lane.setLevel, Lane.onStepClimbed);
-- WorldScenery.client.luau reads it off the replicated attribute to scale its
-- Bubble/Flame spawn cadence, and never computes stage/runSteps itself.
function Lane.updateStageAttribute(self: Lane)
	local _, index = currentHeightStage(self)
	self.folder:SetAttribute("Stage", index)
end

-- The pot's rim kind (StepKinds.PotRim), and whether this lane has climbed the
-- Pot up to it: Pot stops spawning there and the rim is laid (Lane.spawnRim).
local POT_RIM_KIND = "PotRim"
Lane.POT_RIM_KIND = POT_RIM_KIND

function Lane.atPotTop(self: Lane): boolean
	return self.levelIndex == Levels.POT and self.runSteps >= Config.LEVEL_THRESHOLDS.Kitchen
end

-- ---------------------------------------------------------------------------
-- Weighted kind pick (Spawning/Spawner.cs SetUpSpawnProbabilities + CreateSpawn):
-- normalize spawnProbability over the spawner's own pool, roll, and gate on the
-- picked kind's behavior canSpawn (StepSpawner.CreateSpawn's canBeSpawned retry
-- loop). Unity re-rolls until a kind passes; rolling once over only the kinds
-- that pass (pickWeighted) is the same distribution with no retries, and a
-- deterministic fallback means a pathological all-gated pool still spawns.
--
-- Height-stage weight overrides (b-20260923-154344-dr8a): when the lane's
-- level has heightStages, the current stage's `weights[kindName]` replaces
-- StepKinds[kindName].spawnProbability for any pool kind it lists; kinds it
-- doesn't list keep their normal StepKinds weight.
--
-- Fairness guard (PORT ADDITION, doc 17). StepKinds flags the kinds that take
-- themselves away (crumble, timed, falling) as `hazard`. The lane remembers its
-- last Config.HAZARD_WINDOW spawned steps (noteSpawn), and while
-- HAZARD_MAX_RECENT of them were hazards the pick is made over the safe kinds
-- only, so hazards can never crowd out everything else on screen. A `plain`
-- pick (scaffold rungs, free pattern members) is always safe and also leaves
-- out the direction arrows.
-- ---------------------------------------------------------------------------

-- What one pick is choosing under. A single table reused by every pick (nothing
-- here yields), so picking allocates no closures or tables.
type PickQuery = {
	direction: Vector2, -- the lane's spawn direction, for canSpawn
	spawnCount: number, -- the spawner's count so far, for canSpawn
	weights: { [string]: number }?, -- the current height stage's overrides
	plain: boolean, -- no arrows
	safe: boolean, -- no hazards
}
local query: PickQuery = { direction = Vector2.zero, spawnCount = 0, weights = nil, plain = false, safe = false }

local function kindWeight(kindName: string, q: PickQuery): number
	local weights = q.weights
	local override = weights and weights[kindName]
	if override then
		return override
	end
	local kind = StepKinds[kindName]
	return if kind then kind.spawnProbability else 0
end

-- The query's static filters: arrows out of a plain pick, hazards out of a safe one.
local function suits(kindName: string, q: PickQuery): boolean
	local kind = StepKinds[kindName]
	if not kind then
		return true
	end
	return not (q.plain and kind.isArrow) and not (q.safe and kind.hazard)
end

-- ...plus the kind's own behaviour gate (Step.cs canBeSpawned).
local function admits(kindName: string, q: PickQuery): boolean
	if not suits(kindName, q) then
		return false
	end
	local kind = StepKinds[kindName]
	local behavior = kind and StepBehaviors[kind.behavior]
	local canSpawn = behavior and behavior.canSpawn
	return not canSpawn or canSpawn(q.direction, q.spawnCount)
end

-- One weighted draw from `pool` in a single pass: each admitted entry replaces
-- the running choice with probability weight / (total so far), which leaves
-- every entry chosen with probability weight / total. nil when nothing admitted
-- has a positive weight.
local function pickWeighted<T>(
	pool: { string },
	weightOf: (kindName: string, arg: T) -> number,
	gate: (kindName: string, arg: T) -> boolean,
	arg: T
): string?
	local total = 0
	local chosen: string? = nil
	for _, kindName in pool do
		if gate(kindName, arg) then
			local weight = weightOf(kindName, arg)
			if weight > 0 then
				total += weight
				if math.random() * total < weight then
					chosen = kindName
				end
			end
		end
	end
	return chosen
end

-- Record a spawned step in the fairness guard's ring.
local function noteSpawn(self: Lane, kindName: string)
	local kind = StepKinds[kindName]
	local hazard = kind ~= nil and kind.hazard == true
	local i = self.recentCursor % Config.HAZARD_WINDOW + 1
	if self.recentHazards[i] then
		self.hazardCount -= 1
	end
	self.recentHazards[i] = hazard
	if hazard then
		self.hazardCount += 1
	end
	self.recentCursor = i
end

local function resetRecent(self: Lane)
	table.clear(self.recentHazards)
	self.recentCursor = 0
	self.hazardCount = 0
end

-- Is the level's scripted intro (Levels introSequence) still being handed out?
-- Only while a spawner that can hand out its next kind is running: pickKind
-- leaves the cursor alone for any other, so a lane that turned away mid-intro
-- (Kitchen's RightRock only comes off its DownStepSpawner) would otherwise stay
-- "pending" -- and keep patterns and events off -- for as long as it travels
-- that way. The cursor itself is kept; the intro resumes if the lane turns back.
local function introPending(self: Lane): boolean
	local intro = self.level.introSequence
	if not intro or self.introIndex > #intro then
		return false
	end
	local kindName = intro[self.introIndex]
	for _, state in self.activeSpawners do
		if table.find(state.def.pool, kindName) then
			return true
		end
	end
	return false
end

local PUMPKIN_KIND = "Pumpkin" -- StepKinds.Pumpkin, the Halloween step

-- `plain` = an ordinary foothold: never an arrow, never a hazard.
function Lane.pickKind(self: Lane, state: SpawnerState, plain: boolean?): string?
	local pool = state.def.pool
	if #pool == 0 or self:atPotTop() then
		return nil -- nothing spawns above the pot's rim (Lane.spawnRim)
	end

	local stage = currentHeightStage(self)
	local q = query
	q.direction = self.spawnDirection
	q.spawnCount = state.spawnCount
	q.weights = if stage then stage.weights else nil
	q.plain = plain == true
	q.safe = q.plain or self.hazardCount >= Config.HAZARD_MAX_RECENT

	-- Level-entry intro sequence (b-20260923-154345-g9ea): hand out
	-- self.level.introSequence in order, one kind per call, ahead of the normal
	-- weighted pick -- but only when THIS spawner's own pool carries that kind
	-- (and it still passes the gates), so a level's other spawners (idle at
	-- level entry, or grabbed into later) can't be forced into a kind they never
	-- carry; they just leave the cursor for the spawner that does.
	local intro = self.level.introSequence
	if intro and self.introIndex <= #intro then
		local kindName = intro[self.introIndex]
		if table.find(pool, kindName) and admits(kindName, q) then
			self.introIndex += 1
			return kindName
		end
	end

	local chosen = pickWeighted(pool, kindWeight, admits, q)
	if chosen then
		-- Halloween pumpkins (b-20261016-192144-g2e2; port-only, doc 17): while
		-- the window is live, a share of the ordinary picks (never an arrow, whose
		-- direction is the information, nor a hazard, nor a mover: Patrol,
		-- RiseAndFall, Launch -- b-20261021-091520-sh6c) become the plain Pumpkin --
		-- never in the Tutorial, whose tree grabs drive its no-death grace.
		local kind = StepKinds[chosen]
		if
			kind
			and self.levelIndex ~= Levels.TUTORIAL
			and not kind.isArrow
			and not kind.hazard
			and not Config.HALLOWEEN_KEEP_BEHAVIORS[kind.behavior]
			and math.random() < Config.HALLOWEEN_PUMPKIN_CHANCE
			and SpriteSkin.halloweenLive()
		then
			return PUMPKIN_KIND
		end
		return chosen
	end
	-- Nothing admitted carries weight. First anything admitted at all (a pool
	-- whose weights sum to 0), then anything that suits the query even though its
	-- behaviour gates it; a plain pick with neither spawns nothing, any other
	-- falls back to the pool's first entry rather than starve the lane.
	for _, kindName in pool do
		if admits(kindName, q) then
			return kindName
		end
	end
	for _, kindName in pool do
		if suits(kindName, q) then
			return kindName
		end
	end
	return if q.plain then nil else pool[1]
end

-- ---------------------------------------------------------------------------
-- Movements-list cycling (Spawning/Spawner.cs Move() coroutine, L123-147). Only
-- touches spawners whose Levels.luau `def.movements` is non-empty -- see
-- Lane.spawnPosition below for the empty-list procedural fallback this replaces.
-- Unity's Move() runs on its own clock, fully independent of spawning
-- (Activate() L86-97 starts Move() and StartSpawning as two separate coroutines);
-- tickSpawners mirrors that by advancing it on the Heartbeat `dt`, and
-- spawnForPull also sweeps it through each pull's spawner window.
--
-- `Lane.spawnPosition` clamps the result into Lane.isOutOfBounds' recycle margin
-- (Config.BOUNDS_MARGIN) before adding it to the lane's origin: the converted Movements
-- offsets (Levels.luau) are deliberately off-screen "staging" positions, matching
-- Unity's own adjustedMovements, but Unity drags those onscreen with a continuous
-- per-frame PullVector (Spawning/SpawnManager.cs Pull/PullStep) while this port's
-- steps only move on a discrete per-grab pull (Lane.addPull) -- an unclamped
-- literal offset would be recycled before ever being pulled in.
-- ---------------------------------------------------------------------------
-- Axis clamps alone let a CORNER of the box (max |X| and max |Y| at once) sit
-- farther from the lane origin (GameServer's GrabStep measures reach from the
-- origin, not the swaying frog) than Config.MAX_GRAB_DISTANCE, i.e. past
-- GameServer's own GrabStep reach check, so the step spawns already permanently
-- ungrabbable. E.g. Tutorial's TreeDownStepSpawner 3rd tree and Pot/Kitchen/
-- Country's DownStepSpawner/DownLeftStepSpawner both clamp to (25, ~20-25) --
-- 32-35 studs out. Pull those corners back onto the reach circle; in-range
-- spawns (the common case) are untouched.
--
-- A spawner whose travel has no X component (Down) moves its steps straight down, so X
-- never changes after the spawn: it must land inside Config.SPAWN_VIEW_HALF_WIDTH (Unity's
-- portrait view) or the step is never seen. Unity's sweeps put most of their points past
-- that edge (Unity just spawns those off-screen), and a plain clamp stacked them all on
-- the right edge. Owner's ruling b-20261001-145037-iaa4 (doc 17): rescale the spawner's
-- whole sweep instead -- its min..max X maps linearly onto the view less a margin of half
-- the widest grab box (StepKinds hitSize.X) in its pool, so every step sits fully on a
-- portrait screen and the sweep (and its tweens) spreads steps across the middle. A
-- sweep with no X range (min == max) is centred.
--
-- A diagonal/sideways spawner's travel carries a step in from the side, so its X is
-- clamped to the portrait view's edge (b-20260921-112713-7mxu; b-20261022-145536-i6g3).
-- Unity stages those points 1-3 half-widths out because its per-frame pull drags them
-- in continuously. The port pulls once per grab, and a sideways grab only pulls by the
-- grabbed step's own X, at most ~8.84 on a phone. From the lane edge (25), or even
-- Kitchen's 1.5 half-widths (13.3), new steps came to rest past a phone's edge after
-- every grab, so the screen stayed nearly empty. Lane.entryShift still starts each one
-- outside the portrait view, so it slides in.
type ViewSweep = { lo: number, hi: number, half: number }
local viewSweeps: { [Levels.StepSpawnerDef]: ViewSweep } = {}

local function viewSweepOf(def: Levels.StepSpawnerDef): ViewSweep
	local sweep = viewSweeps[def]
	if not sweep then
		local lo, hi = math.huge, -math.huge
		for _, m in def.movements do
			lo = math.min(lo, m.X)
			hi = math.max(hi, m.X)
		end
		local widest = 0
		for _, kindName in def.pool do
			local kind = StepKinds[kindName]
			if kind and kind.hitSize then
				widest = math.max(widest, kind.hitSize.X)
			end
		end
		sweep = { lo = lo, hi = hi, half = math.max(0, Config.SPAWN_VIEW_HALF_WIDTH - widest / 2) }
		viewSweeps[def] = sweep
	end
	return sweep
end

local function viewX(x: number, def: Levels.StepSpawnerDef): number
	local sweep = viewSweepOf(def)
	if sweep.hi - sweep.lo < 1e-4 then
		return 0
	end
	return -sweep.half + (x - sweep.lo) / (sweep.hi - sweep.lo) * 2 * sweep.half
end

local function clampToLane(offset: Vector3, def: Levels.StepSpawnerDef): Vector3
	local edge = Config.SPAWN_VIEW_HALF_WIDTH
	local x = if signOf(def.direction.X) == 0 then viewX(offset.X, def) else math.clamp(offset.X, -edge, edge)
	local y = math.clamp(offset.Y, Config.DESPAWN_Y, Config.SPAWN_Y)
	local planar = Vector2.new(x, y)
	if planar.Magnitude > Config.MAX_GRAB_DISTANCE then
		planar = planar.Unit * Config.MAX_GRAB_DISTANCE
	end
	return Vector3.new(planar.X, planar.Y, 0)
end

-- Spawner.cs Move(), L128-131: `do { destination = movements[rand] } while (destination ==
-- transform.position && movements.Count > 1)`. Compared by INDEX here (not value) -- strictly
-- safer than Unity's value compare (guaranteed to terminate even if two entries happen to
-- share a value) while producing the same observable "don't repeat the current one" behavior.
local function randomBetween(lo: number, hi: number): number
	return lo + math.random() * math.max(0, hi - lo)
end

local function pickMovementIndex(count: number, excludeIndex: number): number
	if count <= 1 then
		return 1
	end
	local idx: number
	repeat
		idx = math.random(1, count)
	until idx ~= excludeIndex
	return idx
end

-- Advances one spawner's Movements cycle by `dt` seconds. First call snaps straight to
-- movements[1] with no tween-in (Spawner.cs Activate() L88-93: SetPosition(adjustedMovements[0])
-- runs BEFORE Move() starts), matching Unity's own "no tween on the very first position" quirk.
local function updateMovement(state: SpawnerState, dt: number)
	local list = state.def.movements
	local count = #list
	if count == 0 then
		return
	end

	if state.moveToIndex == 0 then
		state.moveToIndex = 1
		state.moveTo = list[1]
		state.moveFrom = list[1]
		state.moveElapsed = 0
		state.moveTweenTime = 0
		state.moveWaitTime = randomBetween(state.def.moveTimeMin, state.def.moveTimeMax)
		return
	end

	state.moveElapsed += dt
	if state.moveElapsed < state.moveWaitTime then
		return
	end

	-- leg finished: pick the next destination and start a new one (Spawner.cs Move(), L133-145)
	local nextIndex = pickMovementIndex(count, state.moveToIndex)
	local speed = randomBetween(state.def.moveSpeedMin, state.def.moveSpeedMax)
	local nextMoveTime = randomBetween(state.def.moveTimeMin, state.def.moveTimeMax)

	state.moveFrom = state.moveTo
	state.moveTo = list[nextIndex]
	state.moveToIndex = nextIndex
	state.moveElapsed = 0
	if state.def.discreteMovement then
		state.moveTweenTime = 0 -- instant SetPosition (Spawner.cs L142-144)
		state.moveWaitTime = nextMoveTime
	else
		state.moveTweenTime = speed -- DOLocalMove(destination, speed) (Spawner.cs L138)
		state.moveWaitTime = speed + nextMoveTime -- WaitForSeconds(speed + nextMoveTime) (Spawner.cs L139)
	end
end

-- The spawner's current logical position (Spawner.cs's own `transform.position`, which
-- CreateSpawn() just reads whenever it fires, L206) -- linearly interpolated mid-tween for
-- continuous movers, otherwise the settle point. Falls back to the first list entry if
-- updateMovement hasn't run yet this lane's lifetime (e.g. Lane.prefill's synthetic rows).
local function currentMovementOffset(state: SpawnerState): Vector3
	local list = state.def.movements
	if #list == 0 then
		return Vector3.zero
	end
	if state.moveToIndex == 0 then
		return list[1]
	end
	if state.moveTweenTime <= 0 or state.moveElapsed >= state.moveTweenTime then
		return state.moveTo
	end
	return state.moveFrom:Lerp(state.moveTo, state.moveElapsed / state.moveTweenTime)
end

-- ---------------------------------------------------------------------------
-- Spawn position (doc 13 item 4). When `state.def.movements` is populated (every step
-- spawner as of the doc 17 Movements re-extraction), a regular spawn uses the spawner's
-- current Movements-cycle position (currentMovementOffset) and a spawnAllOnAwake batch
-- spawns one entity per Movements entry, positioned exactly there (Spawner.cs
-- CycleThroughMovementsAndSpawn, L110-117 -- SetPosition(adjustedMovements[i]) then
-- CreateSpawn(i), a strict 1:1 index match with `pool`). Otherwise (an empty list) this falls
-- back to the original procedural placement: new steps enter from the edge the lane's steps
-- travel AWAY from -- i.e. the side opposite spawnDirection -- with diagonals entering from the
-- matching top/bottom corner.
-- ---------------------------------------------------------------------------
-- stagingOffset is that point relative to the lane's origin; Lane.spawnPosition
-- is the same in world space.
local function stagingOffset(state: SpawnerState, indexInBatch: number?): Vector3
	local movements = state.def.movements

	if indexInBatch and #movements > 0 then
		local idx = ((indexInBatch - 1) % #movements) + 1
		return clampToLane(movements[idx], state.def)
	end

	if not indexInBatch and #movements > 0 then
		return clampToLane(currentMovementOffset(state), state.def)
	end

	local dir = state.def.direction
	local ex, ey = -signOf(dir.X), -signOf(dir.Y) -- entry edge = opposite the travel direction

	local x: number, y: number
	if ex ~= 0 and ey ~= 0 then
		-- diagonal: spawn in the corresponding top/bottom corner region
		x = ex * (Config.LANE_HALF_WIDTH - math.random() * (Config.LANE_HALF_WIDTH * Config.SPAWN_CORNER_BAND))
		y = if ey > 0 then Config.SPAWN_Y else Config.DESPAWN_Y
	elseif ex ~= 0 then
		-- pure horizontal: enter from the left/right edge, spread across a vertical band
		x = ex * (Config.LANE_HALF_WIDTH + Config.SPAWN_EDGE_MARGIN)
		y = (math.random() * 2 - 1) * (Config.SPAWN_Y * Config.SPAWN_SIDE_BAND)
	else
		-- pure vertical (the common case): enter from the top/bottom edge, spread across X
		x = (math.random() * 2 - 1) * Config.SPAWN_X_RANGE
		y = if ey >= 0 then Config.SPAWN_Y else Config.DESPAWN_Y
	end

	if indexInBatch then
		-- spawnAllOnAwake with an empty Movements list: a ladder climbing away from the
		-- frog's start, alternating sides, so the first one is an easy reach and each next
		-- one needs the previous pull
		x = (if indexInBatch % 2 == 1 then 1 else -1) * Config.TUTORIAL_STEP_X
		y = Config.TUTORIAL_FIRST_STEP_Y + (indexInBatch - 1) * Config.TUTORIAL_STEP_GAP
	end

	return Vector3.new(x, y, 0)
end

function Lane.spawnPosition(self: Lane, state: SpawnerState, indexInBatch: number?): Vector3
	return self.origin + stagingOffset(state, indexInBatch)
end

-- Is a step of `size` centred at `pos` wholly past the lane's catch bounds?
local function pastBounds(self: Lane, pos: Vector3, size: Vector3): boolean
	local halfX, halfY = size.X / 2, size.Y / 2
	local relX = pos.X - self.origin.X
	local boundX = Config.LANE_HALF_WIDTH + Config.BOUNDS_MARGIN
	if relX + halfX < -boundX or relX - halfX > boundX then
		return true
	end
	return (pos.Y + halfY) < Config.DESPAWN_Y or (pos.Y - halfY) > (Config.SPAWN_Y + Config.BOUNDS_MARGIN)
end

-- Recycle test for a step of `size` centred at `pos` -- see Lane.isOutOfBounds.
-- `slack` (travel * StepState.upstream) is the displacement that takes a step
-- staged upstream on purpose back to where an ordinary spawn would be: such a
-- step is only out when it is past the bounds both where it is and there. That
-- widens the bounds on the upstream side alone -- once the step has travelled
-- out the far side, moving it further along travel leaves it out.
local function outOfBounds(self: Lane, pos: Vector3, size: Vector3, slack: Vector3?): boolean
	if not pastBounds(self, pos, size) then
		return false
	end
	return slack == nil or pastBounds(self, pos + slack, size)
end

local DEFAULT_SIZE = Vector3.new(6, 6, 1)

-- ---------------------------------------------------------------------------
-- Step states. GameServer owns the pooled Instances; the lane owns where each
-- one logically is (StepState.base), because every question this module answers
-- about a step -- rest position, spacing, bounds -- is about that, not about the
-- part's replicated CFrame.
-- ---------------------------------------------------------------------------

-- Start tracking `step` (just taken from the pool) at `base`: marks it active
-- and gives it a fresh StepState, which GameServer.acquireStep then fills in
-- (spin, behaviour, params).
function Lane.trackStep(self: Lane, step: BasePart, base: Vector3): StepState
	local state: StepState = {
		base = base,
		angle = 0,
		spinRate = nil,
		zBias = 0,
		offset = Vector3.zero,
		sweep = Vector2.zero,
		recoil = Vector3.zero,
		recoilVelocity = Vector3.zero,
		sag = 0,
		dropElapsed = nil,
		upstream = 0,
		behavior = StepBehaviors.None,
		params = NO_PARAMS,
		scratch = {},
		ctx = nil,
		shownPosition = base,
		shownAngle = 0,
	}
	self.active[step] = true
	self.states[step] = state
	return state
end

-- `step` is going back to the pool: forget its state, and drop it from any
-- slide-in it was part of (forgetStep), so the part's next life inherits nothing.
function Lane.untrackStep(self: Lane, step: BasePart)
	self.active[step] = nil
	self.states[step] = nil
	self:forgetStep(step)
end

-- `step`'s logical position (StepState.base). The part's own Position only for
-- a part this lane isn't tracking, which no caller passes.
function Lane.basePosition(self: Lane, step: BasePart): Vector3
	local state = self.states[step]
	return if state then state.base else step.Position
end

-- ---------------------------------------------------------------------------
-- Motions. Every pull (and every slide-in) is an eased displacement played on
-- the server's own clock (advanceMotions, from GameServer's Heartbeat) rather
-- than a TweenService tween per step. They add up: a grab that lands mid-pull
-- keeps the rest of the previous pull instead of cancelling it, and a step
-- spawned during a pull rides whatever is left of it. Easing is Sine/Out
-- (PullMath.sineOut), the curve WorldScenery tweens the lane's cosmetics with
-- off PullDelta/PullTime. A motion moves StepState.base; the part itself is
-- written once per tick by GameServer.
-- ---------------------------------------------------------------------------
local function eased(m: Motion, elapsed: number): number
	if m.duration <= 0 then
		return 1
	end
	return PullMath.sineOut(elapsed / m.duration)
end

local function remaining(m: Motion): Vector3
	return m.delta * (1 - eased(m, m.elapsed))
end

function Lane.addMotion(self: Lane, delta: Vector3, duration: number, only: { [BasePart]: boolean }?): Motion
	local m: Motion = { delta = delta, duration = duration, elapsed = 0, only = only }
	table.insert(self.motions, m)
	return m
end

-- What the lane's running pulls still owe every step, including one spawned now.
function Lane.sharedPending(self: Lane): Vector3
	local sum = Vector3.zero
	for _, m in self.motions do
		if not m.only then
			sum += remaining(m)
		end
	end
	return sum
end

-- Where `step`'s base comes to rest once every motion playing on it has
-- finished. A caller asking about many steps at once passes `shared`, the
-- lane's sharedPending() computed once, and only the step's own slide-ins are
-- then walked here.
function Lane.restPosition(self: Lane, step: BasePart, shared: Vector3?): Vector3
	local pos = self:basePosition(step)
	if shared then
		pos += shared
	end
	for _, m in self.motions do
		local only = m.only
		if only then
			if only[step] then
				pos += remaining(m)
			end
		elseif not shared then
			pos += remaining(m)
		end
	end
	return pos
end

-- A pooled step is leaving this lane: drop it from any slide-in it was part of,
-- so a re-acquired part doesn't inherit the old slide.
function Lane.forgetStep(self: Lane, step: BasePart)
	for _, m in self.motions do
		local only = m.only
		if only then
			only[step] = nil
		end
	end
end

-- Advance every motion by `dt`, moving the lane's step bases by each one's eased
-- increment. Pulls are summed first, so a lane with several playing still walks
-- its steps once.
function Lane.advanceMotions(self: Lane, dt: number)
	local shared = Vector3.zero
	for i = #self.motions, 1, -1 do
		local m = self.motions[i]
		local before = eased(m, m.elapsed)
		m.elapsed += dt
		local inc = m.delta * (eased(m, m.elapsed) - before)
		local only = m.only
		if only then
			for step in only do
				local state = self.states[step]
				if state then
					state.base += inc
				end
			end
		else
			shared += inc
		end
		if m.elapsed >= m.duration then
			table.remove(self.motions, i)
		end
	end
	if shared ~= Vector3.zero then
		for _, state in self.states do
			state.base += shared
		end
	end
end

-- How far back along `travel` (studs) a step of `size` must start, relative to
-- `pos`, so its whole extent is outside the camera band (Config.VIEW_HALF_HEIGHT)
-- on the side it enters from. Motion along `travel` then carries it into view:
-- it slides in rather than popping up (owner's ruling, b-20260921-164429-ee9c).
-- Any vertical component decides it (steps entering from the top). Pure sideways
-- travel uses the portrait view's half-width (Config.SPAWN_VIEW_HALF_WIDTH), the
-- narrowest view the camera shows. The server can't see the client's aspect ratio,
-- and a sideways grab pulls only a few studs, so a step started outside a wider
-- band came to rest past a phone's edge (b-20261022-145536-i6g3). A wider view
-- sees it appear near its sides instead. Config.ENTRY_MARGIN is the slack past
-- the band edge.
function Lane.entryShift(self: Lane, pos: Vector3, size: Vector3, travel: Vector3): number
	local rel = pos - self.origin
	local h = Config.VIEW_HALF_HEIGHT
	if math.abs(travel.Y) > 1e-4 then
		local clear = h + size.Y / 2 + Config.ENTRY_MARGIN
		local need = if travel.Y < 0 then clear - rel.Y else rel.Y + clear
		return math.max(0, need / math.abs(travel.Y))
	elseif math.abs(travel.X) > 1e-4 then
		local clear = Config.SPAWN_VIEW_HALF_WIDTH + size.X / 2 + Config.ENTRY_MARGIN
		local need = if travel.X < 0 then clear - rel.X else rel.X + clear
		return math.max(0, need / math.abs(travel.X))
	end
	return 0
end

-- True when a step with grab box `hit` and sweep half-extent `reach`, resting
-- at `p`, would come within Config.SPAWN_GAP of any live step (compared at REST
-- positions; `shared` = self:sharedPending(), passed in so callers compute it
-- once). `exclude` (optional) is skipped -- a step being moved. Shared by
-- clearSpot and Chef's shove landing test so the spacing can't drift apart.
function Lane.crowdsSpot(
	self: Lane,
	p: Vector3,
	hit: Vector2,
	reach: Vector2,
	shared: Vector3,
	exclude: BasePart?
): boolean
	for step, state in self.states do
		if step ~= exclude then
			local other = (step:GetAttribute("HitSize") :: Vector2?) or Vector2.new(step.Size.X, step.Size.Y)
			local d = self:restPosition(step, shared) - p
			if
				math.abs(d.X) < (hit.X + other.X) / 2 + reach.X + state.sweep.X + Config.SPAWN_GAP
				and math.abs(d.Y) < (hit.Y + other.Y) / 2 + reach.Y + state.sweep.Y + Config.SPAWN_GAP
			then
				return true
			end
		end
	end
	return false
end

-- Where a new step of `kindName` can rest without its grab box (StepKinds hitSize)
-- coming within Config.SPAWN_GAP of a live step's (compared at REST positions,
-- Lane.restPosition, so a pull still playing doesn't matter): `pos` itself, or
-- the first point back along the travel line (upstream, i.e. further off-screen)
-- that is clear. nil when that would leave the lane's bounds, and the spawn is
-- skipped. Without this one spawner's consecutive steps can land 2-3 studs apart
-- and overlap (b-20260921-112713-7mxu).
-- Also keeps the new step's grab box out of the client's PlayerList rectangle
-- (self.obstruction) while the lane isn't drifting -- a drifting step never
-- stops under it (Lane.obstructionExtra, doc 17).
--
-- Moving steps (StepBehaviors.Patrol / RiseAndFall) are spaced by the centre of
-- their sweep plus its whole extent, never by wherever they happen to be right
-- now: a live step's reserved half-extent is its StepState.sweep, and the new
-- step's own is the optional `sweep` argument (its behaviour's `sweep(params)`;
-- omitted = a step that stays put). Both widen the gap on their axis, so a
-- patroller can't slide into a neighbour whichever of the two spawned first.
-- The PlayerList keep-out tests the base only -- a sweep may graze it.
--
-- `slack` (optional) is the bounds allowance of a step staged upstream on
-- purpose (outOfBounds above): a pattern member behind the ones before it.
function Lane.clearSpot(
	self: Lane,
	pos: Vector3,
	kindName: string,
	travel: Vector3,
	sweep: Vector2?,
	slack: Vector3?
): Vector3?
	local kind = StepKinds[kindName]
	local size = if kind then kind.size else DEFAULT_SIZE
	local hit = if kind and kind.hitSize then kind.hitSize else Vector2.new(size.X, size.Y)
	local hitOffset = if kind and kind.hitOffset then kind.hitOffset else Vector2.zero
	local reach = sweep or Vector2.zero
	local avoidObstruction = self.obstruction ~= nil and not self:drifts()
	local shared = self:sharedPending() -- once, not per step per try
	local shift = 0
	while shift <= Config.SPAWN_NUDGE_MAX do
		local p = pos - travel * shift
		if outOfBounds(self, p, size, slack) then
			return nil
		end
		local clear = not (avoidObstruction and self:obstructs(p, hit, hitOffset))
			and not self:crowdsSpot(p, hit, reach, shared)
		if clear then
			return p
		end
		if travel.Magnitude < 1e-4 then
			return nil
		end
		shift += Config.SPAWN_NUDGE_STEP
	end
	return nil
end

-- Start a pull of `distance` studs along this lane's spawn direction, played
-- over `duration` s by advanceMotions. Returns the displacement (nil when the
-- lane has no direction). Also tracks net forward scroll since this level began
-- (floored at 0) so a later negative "undo" pull -- GameServer.tutorialRetry's
-- Tutorial "no death" rule -- can be capped against it and never overshoot past
-- the level's start (doc 17 gap: an uncapped retry pull-back permanently
-- scrolled the Tutorial's one-shot ladder, which never respawns, off the top of
-- the field before it was ever climbed).
function Lane.addPull(self: Lane, distance: number, duration: number): Vector3?
	if self.travel == Vector3.zero then
		return nil
	end
	local delta = self.travel * distance
	self:addMotion(delta, duration)
	self.netPull = math.max(0, self.netPull + distance)
	return delta
end

-- Set the run mode (StartRun). Classic is the default (owner's request
-- b-20260921-182325-3jtz): only a literal "Normal" opts out, anything else
-- (missing/garbage/an old client) falls back to Classic.
function Lane.setMode(self: Lane, mode: string)
	self.mode = if mode == Config.RUN_MODES.Normal then Config.RUN_MODES.Normal else Config.RUN_MODES.Classic
	self.driftDistance = 0
	self.driftTime = 0
	self.driftElapsed = 0
	self.driftBase = 0
	self.driftHold = 0
	self.folder:SetAttribute("Mode", self.mode)
end

-- Classic mode's scroll speed for the current level right now (studs/s), 0
-- when this lane isn't Classic or the level doesn't drift at all
-- (Config.CLASSIC_SCROLL_SPEED has no entry for it, e.g. Tutorial). Ramps
-- gently the longer this run's drift has run (Config.CLASSIC_SCROLL_ACCEL_RATE,
-- self.driftElapsed), capped at CLASSIC_SCROLL_MAX_MULT times the level's base.
-- `dt` advances the ramp clock; callers only invoke this once per tick they
-- actually mean to drift (GameServer's Heartbeat, gated on the frog being
-- armed and alive), so the ramp only runs while drift itself runs.
--
-- self.driftBase chases the level's own CLASSIC_SCROLL_SPEED at
-- CLASSIC_LEVEL_RAMP_TIME instead of snapping to it (b-20260923-154345-g9ea):
-- without this, a level transition's base-speed jump (e.g. Pot ~3.14 ->
-- Kitchen ~4.09 studs/s) landed instantly the moment runSteps crossed
-- LEVEL_THRESHOLDS. The first-ever drift of a run (driftBase == 0) still
-- snaps straight to the base -- there's nothing to ramp from yet.
function Lane.driftSpeed(self: Lane, dt: number): number
	if self.mode ~= Config.RUN_MODES.Classic then
		return 0
	end
	local target = Config.CLASSIC_SCROLL_SPEED[self.level.name]
	if not target or target <= 0 then
		self.driftBase = 0
		return 0
	end
	if self.driftHold > 0 then
		self.driftHold = math.max(0, self.driftHold - dt)
		return 0 -- level-up breather: hold first, then ramp (Lane.beginArrival)
	end

	if self.driftBase <= 0 then
		self.driftBase = target
	elseif self.driftBase ~= target then
		local maxStep = (math.abs(target - self.driftBase) / Config.CLASSIC_LEVEL_RAMP_TIME) * dt
		if math.abs(target - self.driftBase) <= maxStep then
			self.driftBase = target
		else
			self.driftBase += if target > self.driftBase then maxStep else -maxStep
		end
	end

	self.driftElapsed += dt
	local speed = self.driftBase + self.driftBase * Config.CLASSIC_SCROLL_ACCEL_RATE * self.driftElapsed
	return math.min(speed, self.driftBase * Config.CLASSIC_SCROLL_MAX_MULT)
end

-- Classic mode: scroll every live step's base `speed * dt` studs along the spawn
-- direction right now (Unity's steps move under SpawnManager.PullVector every
-- frame; here it never stops). The distance accumulates until
-- Config.CLASSIC_CHUNK_TIME has passed, then is returned as one chunk (studs,
-- seconds) for GameServer to spend on spawner time and replicate; nil otherwise.
function Lane.drift(self: Lane, dt: number, speed: number): (number?, number?)
	if speed <= 0 or dt <= 0 or self.travel == Vector3.zero then
		return nil, nil
	end
	local distance = speed * dt
	local inc = self.travel * distance
	for _, state in self.states do
		state.base += inc
	end
	self.netPull += distance
	self.driftDistance += distance
	self.driftTime += dt
	if self.driftTime < Config.CLASSIC_CHUNK_TIME then
		return nil, nil
	end
	local chunk, chunkTime = self.driftDistance, self.driftTime
	self.driftDistance = 0
	self.driftTime = 0
	return chunk, chunkTime
end

-- ---------------------------------------------------------------------------
-- Roblox PlayerList keep-out (owner's decision b-20260921-182502-qgbw, doc 17).
-- The client reports the list's rough rectangle (self.obstruction, lane-relative
-- studs); a grab's pull is lengthened until no step's grab box rests inside it.
-- Only while the lane is NOT drifting: under Classic drift every step keeps
-- moving, so none can stop under the list, and a longer pull there would only
-- cost the player height against the lava.
-- ---------------------------------------------------------------------------

-- True when this lane's steps scroll on their own (Classic on a level with a
-- CLASSIC_SCROLL_SPEED entry).
function Lane.drifts(self: Lane): boolean
	if self.mode ~= Config.RUN_MODES.Classic then
		return false
	end
	local base = Config.CLASSIC_SCROLL_SPEED[self.level.name]
	return base ~= nil and base > 0
end

-- Record (or clear, nil) the client's PlayerList rectangle. GameServer validates it.
function Lane.setObstruction(self: Lane, rect: Rect?)
	self.obstruction = rect
end

-- Does a grab box of `hit` studs, centred `hitOffset` from a step at world
-- position `pos`, overlap the obstruction rectangle (padded by OBSTRUCTION_PAD)?
function Lane.obstructs(self: Lane, pos: Vector3, hit: Vector2, hitOffset: Vector2): boolean
	local r = self.obstruction
	if not r then
		return false
	end
	local pad = Config.OBSTRUCTION_PAD
	local cx = pos.X - self.origin.X + hitOffset.X
	local cy = pos.Y - self.origin.Y + hitOffset.Y
	local hx, hy = hit.X / 2, hit.Y / 2
	return cx + hx > r.Min.X - pad and cx - hx < r.Max.X + pad and cy + hy > r.Min.Y - pad and cy - hy < r.Max.Y + pad
end

-- How much LONGER (studs, >= 0) a grab pull of `distance` should be so that no
-- live step's grab box ends up resting inside the obstruction: the smallest
-- extension in [0, OBSTRUCTION_MAX_EXTRA_PULL] that leaves none inside, or, when
-- none within the cap does, the one leaving the fewest (ties: the shortest).
-- Call before the pull is added (restPosition then still excludes it).
function Lane.obstructionExtra(self: Lane, distance: number): number
	local travel = self.travel
	if not self.obstruction or self:drifts() or distance <= 0 or travel == Vector3.zero then
		return 0
	end
	type Box = { rest: Vector3, hit: Vector2, offset: Vector2 }
	local boxes: { Box } = {}
	local shared = self:sharedPending()
	for step in self.active do
		table.insert(boxes, {
			rest = self:restPosition(step, shared),
			hit = (step:GetAttribute("HitSize") :: Vector2?) or Vector2.new(step.Size.X, step.Size.Y),
			offset = (step:GetAttribute("HitOffset") :: Vector2?) or Vector2.zero,
		})
	end
	local bestExtra, bestCount = 0, math.huge
	local extra = 0
	while extra <= Config.OBSTRUCTION_MAX_EXTRA_PULL + 1e-6 do
		local shift = travel * (distance + extra)
		local count = 0
		for _, b in boxes do
			if self:obstructs(b.rest + shift, b.hit, b.offset) then
				count += 1
			end
		end
		if count < bestCount then
			bestExtra, bestCount = extra, count
			if count == 0 then
				break
			end
		end
		extra += Config.OBSTRUCTION_SEARCH_STEP
	end
	return bestExtra
end

-- ---------------------------------------------------------------------------
-- Laying one step. Every spawn path below ends here: fit the staging point to
-- the kind (fitStaging), find it a clear rest spot (placeStep -> Lane.clearSpot,
-- with the kind's own sweep reserved), and hand GameServer one SpawnRequest
-- (emit).
-- ---------------------------------------------------------------------------

-- How far `kindName`'s behaviour may carry it from its base, per axis, given
-- `params` (StepBehaviors `sweep`); zero for a step that stays put.
local function sweepOf(kindName: string, params: StepBehaviors.Params?): Vector2
	local kind = StepKinds[kindName]
	local behavior = kind and StepBehaviors[kind.behavior]
	local sweep = behavior and behavior.sweep
	return if sweep then sweep(params) else Vector2.zero
end

-- Where the hand lands on a `kindName` step resting at angle 0: its StepKinds
-- `gripOffset` (zero for every kind without one), so reach is judged where the
-- frog actually grabs, same as GameServer's GrabStep.
local function gripOf(kindName: string): Vector3
	local kind = StepKinds[kindName]
	local grip = if kind then kind.gripOffset else nil
	return if grip then Vector3.new(grip.X, grip.Y, 0) else Vector3.zero
end

local function planarDistance(self: Lane, pos: Vector3): number
	return Vector2.new(pos.X - self.origin.X, pos.Y - self.origin.Y).Magnitude
end

-- The fairness guard's reach rule: a step resting at `pos` can be grabbed
-- anywhere in its sweep (GameServer's GrabStep measures from the lane origin).
local function withinReach(self: Lane, pos: Vector3, sweep: Vector2, kindName: string): boolean
	return planarDistance(self, pos + gripOf(kindName)) + math.max(sweep.X, sweep.Y) <= Config.MAX_GRAB_DISTANCE
end

-- Fit a lane-relative staging `offset` to the kind about to spawn there.
--   * A spawner that travels straight down never moves a step sideways, so the
--     grab box AND the whole sweep must sit inside the portrait view
--     (Config.SPAWN_VIEW_HALF_WIDTH) from the start.
--   * The step must be within reach of the lane origin at either end of its sweep.
-- A no-op for a pool kind that stays put: clampToLane has already held it to
-- the same bounds using the pool's widest grab box.
local function fitStaging(offset: Vector3, def: Levels.StepSpawnerDef, kindName: string, sweep: Vector2): Vector3
	local x, y = offset.X, offset.Y
	if signOf(def.direction.X) == 0 then
		local kind = StepKinds[kindName]
		local hitX = if kind then kind.hitSize.X else DEFAULT_SIZE.X
		local limit = math.max(0, Config.SPAWN_VIEW_HALF_WIDTH - hitX / 2 - sweep.X)
		x = math.clamp(x, -limit, limit)
	end
	local reach = Config.MAX_GRAB_DISTANCE - math.max(sweep.X, sweep.Y)
	-- clamp the grip point, not the centre (a tall step's hand lands off-centre)
	local grip = gripOf(kindName)
	local planar = Vector2.new(x + grip.X, y + grip.Y)
	if planar.Magnitude > reach then
		planar = planar.Unit * reach
	end
	return Vector3.new(planar.X - grip.X, planar.Y - grip.Y, 0)
end

-- Find where a `kindName` step meant to rest at `rest` can actually go, and
-- return the position to create it at NOW (rest less `pending`, what the lane's
-- running pulls still owe), or nil when there is no clear spot. Also returns how
-- far back along the travel line (studs) the step ended up from `rest`: the
-- entry shift plus clearSpot's nudge.
--   `entry`  -- first push it back along the travel line until it starts outside
--               the camera band (Lane.entryShift), sweep included, so it slides in.
--   `strict` -- refuse a spot the nudging has pushed out of reach (new content:
--               moving kinds, pattern and event members).
--   `slack`  -- studs this step is staged upstream ON PURPOSE (a pattern member
--               behind the ones before it); 0 for anything else.
-- The reach rule is there so a step can be grabbed when the frog gets to it, and
-- a step staged upstream is only got to after the scroll has brought it down:
-- the pulls of the members before it for `slack`, the lane's own scroll for the
-- entry shift (which only exists to start the step off-screen -- for the tall
-- Castle that alone is past reach). So reach is tested that far along travel
-- from the spot found, and the bounds likewise (clearSpot's `slack`). The nudge
-- gets no such credit: crowding must not push a step out of reach.
local function placeStep(
	self: Lane,
	kindName: string,
	rest: Vector3,
	sweep: Vector2,
	pending: Vector3,
	entry: boolean,
	strict: boolean,
	slack: number
): (Vector3?, number)
	local travel = self.travel
	local wanted = rest
	local credit = slack
	if entry then
		local kind = StepKinds[kindName]
		local size = (if kind then kind.size else DEFAULT_SIZE) + Vector3.new(2 * sweep.X, 2 * sweep.Y, 0)
		local shift = self:entryShift(rest - pending, size, travel)
		rest -= travel * shift
		credit += shift
	end
	local pos = self:clearSpot(rest, kindName, travel, sweep, if slack > 0 then travel * slack else nil)
	if not pos or (strict and not withinReach(self, pos + travel * credit, sweep, kindName)) then
		return nil, 0
	end
	return pos - pending, (wanted - pos):Dot(travel)
end

-- Hand GameServer one step to create, and account for it. `upstream` is the
-- step's StepState.upstream (nil = an ordinary spawn).
local function emit(
	self: Lane,
	spawnFn: SpawnFn,
	kindName: string,
	params: StepBehaviors.Params?,
	position: Vector3,
	spawner: SpawnerState?,
	source: string,
	upstream: number?
)
	spawnFn(self, {
		kindName = kindName,
		position = position,
		params = params,
		spawner = spawner,
		source = source,
		upstream = upstream,
	})
	if spawner then
		spawner.spawnCount += 1
	end
	noteSpawn(self, kindName)
end

-- One ordinary spawn from `state`: a weighted kind (Lane.pickKind) at the
-- spawner's `staging` offset, carried `carry` along the travel line. Returns
-- how many steps it laid (0 = no clear spot), or nil when the spawner has
-- nothing to offer right now (empty pool, the pot's top).
local function spawnSingle(
	self: Lane,
	state: SpawnerState,
	staging: Vector3,
	carry: Vector3,
	pending: Vector3,
	spawnFn: SpawnFn,
	entry: boolean,
	source: string
): number?
	local kindName = self:pickKind(state)
	if not kindName then
		return nil
	end
	local kind = StepKinds[kindName]
	local params = if kind then kind.params else nil
	local sweep = sweepOf(kindName, params)
	local rest = self.origin + fitStaging(staging, state.def, kindName, sweep) + carry
	local position = placeStep(self, kindName, rest, sweep, pending, entry, sweep ~= Vector2.zero, 0)
	if not position then
		return 0
	end
	emit(self, spawnFn, kindName, params, position, state, source)
	return 1
end

-- ---------------------------------------------------------------------------
-- Spawn patterns and events (PORT ADDITIONS, doc 17; data in Levels.luau). A
-- pattern is laid in place of one spawn: each member sits `lateral` studs across
-- the travel line (the whole pattern mirrored at random) and `upstream` studs
-- back along it from the spawner's staging point, and goes through exactly the
-- placement a single spawn does -- fitStaging, the off-screen entry, clearSpot
-- with its sweep -- plus the reach rule. A member with no clear spot is skipped.
--
-- Upstream members. Only a member's spot in the ANCHOR ROW is fitted to the
-- lane (fitStaging: the portrait view, reach); its `upstream` is added after
-- that, because fitting the offset as a whole squeezed every member past reach
-- onto the reach circle, on top of one another. A member behind the first one
-- laid (the lead) is not within reach when it spawns and is not meant to be: it
-- is reached once the members before it have been climbed, so its reach and
-- bounds are judged where it will be by then -- its own spot brought down by
-- its distance behind the lead (placeStep's `slack`, StepState.upstream for the
-- recycle bound). A member more than Config.PATTERN_MAX_UPSTREAM behind the
-- lead is left out, with every member after it.
--
-- Spacing. Levels' offsets are the pattern's nominal shape, sized for its
-- smallest members. Whatever a member is moved back by on top of that -- the
-- off-screen entry, or clearSpot's nudge because its actual grab box and sweep
-- (plus SPAWN_GAP) did not clear the member before it -- is carried on to every
-- later member (`push`), so the pattern opens up to fit what it is made of and
-- keeps its order and shape instead of each member being nudged on its own.
--
-- Fairness: a member with no `kind` is a plain pick (no arrow, no hazard). A
-- member that NAMES a hazard kind keeps it only while the pattern has laid
-- fewer than Config.PATTERN_MAX_HAZARDS, is not that pattern's every member,
-- and the lane's recent-spawn cap (Lane.pickKind) has room; otherwise it
-- becomes a plain pick too.
-- ---------------------------------------------------------------------------
local function spawnPattern(
	self: Lane,
	state: SpawnerState,
	pattern: Levels.PatternDef,
	staging: Vector3,
	carry: Vector3,
	pending: Vector3,
	spawnFn: SpawnFn,
	source: string
): number
	local def = state.def
	local travel = self.travel
	local across = Vector3.new(-travel.Y, travel.X, 0) * (if math.random() < 0.5 then 1 else -1)

	-- Under straight-down travel the pattern's width has to fit the portrait
	-- view, so centre it far enough in that its outer members aren't all clamped
	-- onto one edge.
	local anchor = staging
	if signOf(def.direction.X) == 0 then
		local widest = 0
		for _, member in pattern.members do
			widest = math.max(widest, math.abs(member.lateral))
		end
		local limit = math.max(0, viewSweepOf(def).half - widest)
		anchor = Vector3.new(math.clamp(staging.X, -limit, limit), staging.Y, 0)
	end

	local laid, hazards = 0, 0
	local hazardRoom = math.min(Config.PATTERN_MAX_HAZARDS, #pattern.members - 1)
	local push = 0 -- studs the members laid so far were moved back, owed to every later one
	local lead: number? = nil -- how far upstream of the anchor row the first laid member sits
	for _, member in pattern.members do
		local upstream = member.upstream + push
		local slack = if lead then math.max(0, upstream - lead) else 0
		if slack > Config.PATTERN_MAX_UPSTREAM then
			break -- members are listed outward, so every later one is further still
		end
		local kindName = if member.role and self.level.roles then self.level.roles[member.role] else member.kind
		local named = if kindName then StepKinds[kindName] else nil
		local isHazard = named ~= nil and named.hazard == true
		if isHazard and (hazards >= hazardRoom or self.hazardCount >= Config.HAZARD_MAX_RECENT) then
			kindName, isHazard = nil, false
		end
		if not kindName then
			kindName = self:pickKind(state, true)
		end
		if kindName then
			local kind = StepKinds[kindName]
			local params = if (member.kind == kindName or member.role) and member.params
				then member.params
				elseif kind then kind.params
				else nil
			local sweep = sweepOf(kindName, params)
			local row = fitStaging(anchor + across * member.lateral, def, kindName, sweep)
			local rest = self.origin + row + carry - travel * upstream
			local position, moved = placeStep(self, kindName, rest, sweep, pending, true, true, slack)
			if position then
				push += moved
				lead = lead or upstream + moved
				emit(self, spawnFn, kindName, params, position, state, source, slack + moved)
				laid += 1
				if isHazard then
					hazards += 1
				end
			end
		end
	end
	return laid
end

-- A level event (Levels EventDef) due on this lane, rolled now: past its
-- `minRunSteps` (in stageSteps), off cooldown, and its `chance` came up. nil =
-- none. Rolled ONCE per spawner window (Lane.spawnForPull), not per spawner
-- firing: a window fires several spawns, which made a 3-4 % event all but
-- certain within a few grabs of its cooldown ending. `share` is the window as a
-- fraction of one grab's (a Classic drift chunk earns a small one), so `chance`
-- means "per grab's worth of spawning" however the window was earned.
local function rollEvent(self: Lane, share: number): Levels.EventDef?
	local events = self.level.events
	if not events then
		return nil
	end
	local steps = stageSteps(self)
	for _, event in events do
		local last = self.eventLast[event.name]
		if
			steps >= event.minRunSteps
			and (not last or self.runSteps - last >= event.cooldown)
			and math.random() < event.chance * share
		then
			return event
		end
	end
	return nil
end

-- The current height stage's pattern roll: one of its `patterns` by weight, at
-- its `patternChance`. nil = an ordinary spawn.
local function rollPattern(self: Lane): Levels.PatternDef?
	local stage = currentHeightStage(self)
	local patterns = stage and stage.patterns
	local chance = stage and stage.patternChance
	if not patterns or not chance or math.random() >= chance then
		return nil
	end
	local total = 0
	local chosen: Levels.PatternDef? = nil
	for _, pattern in patterns do
		if pattern.weight > 0 then
			total += pattern.weight
			if math.random() * total < pattern.weight then
				chosen = pattern
			end
		end
	end
	return chosen
end

-- One firing of a running spawner: `event` (the event this spawner window
-- rolled, if any -- Lane.spawnForPull), else a pattern, else (or when neither
-- found room for a single member) one ordinary step. Patterns and events never
-- appear in the Tutorial, on a spawner flagged `noPatterns`, or while the
-- level's scripted intro is still being handed out. Returns how many steps were
-- laid, and whether they were the event's (the caller then stops offering it;
-- one that found no room is offered to the window's next firing).
local function spawnFromSpawner(
	self: Lane,
	state: SpawnerState,
	staging: Vector3,
	carry: Vector3,
	pending: Vector3,
	spawnFn: SpawnFn,
	event: Levels.EventDef?
): (number, boolean)
	if
		self.levelIndex ~= Levels.TUTORIAL
		and not state.def.noPatterns
		and not introPending(self)
		and not self:atPotTop()
	then
		if event then
			local laid = spawnPattern(self, state, event.pattern, staging, carry, pending, spawnFn, "event")
			if laid > 0 then
				self.eventLast[event.name] = self.runSteps
				return laid, true
			end
		end
		local pattern = rollPattern(self)
		if pattern then
			local laid = spawnPattern(self, state, pattern, staging, carry, pending, spawnFn, "pattern")
			if laid > 0 then
				return laid, false
			end
		end
	end
	return spawnSingle(self, state, staging, carry, pending, spawnFn, true, "spawner") or 0, false
end

-- Seconds until `def`'s next spawn (Spawner.cs StartSpawning's Random.Range
-- wait), floored so a 0-interval def can't loop forever. A firing that laid
-- several steps (a pattern) waits a share longer per extra step.
local function rollInterval(def: Levels.StepSpawnerDef, laid: number): number
	local interval = math.max(Config.SPAWN_MIN_INTERVAL, randomBetween(def.spawningSpeedMin, def.spawningSpeedMax))
	return interval * (1 + math.max(0, laid - 1) * Config.PATTERN_INTERVAL_COST)
end

local function underSpawnCap(state: SpawnerState): boolean
	return state.def.maxSpawnCount < 0 or state.spawnCount < state.def.maxSpawnCount
end

-- ---------------------------------------------------------------------------
-- Pull-driven spawning (Spawning/Spawner.cs StartSpawning, run only while the
-- field is being pulled: SpawnManager.PullStep activates the step spawners and
-- ReleasePullingStep stops them). Each grab earns Config.PULL_SPAWN_WINDOW
-- spawner-seconds (Unity's fixed 1 s, Step.cs Invoke("StopPull", 1f)), spent
-- right away in small slices so each spawner's Movements cycle still sweeps along
-- as Unity's window would. Under Unity's scroll a spawn made partway through the
-- window rides the rest of the pull, so each spawn's REST position is carried
-- along the travel direction by the matching share of `distance`; the part is then created back by
-- whatever the lane's running pulls still owe (sharedPending) -- i.e. at the
-- spawner's staging point or further out -- and the pull carries it in.
-- Lane.entryShift pushes a spawn further back when even that start would
-- overlap the camera band. `spawnFn` gets a SpawnRequest whose position is where
-- to create the part NOW; GameServer owns the pooled Instances.
-- ---------------------------------------------------------------------------
function Lane.spawnForPull(self: Lane, distance: number, spawnFn: SpawnFn, windowOverride: number?)
	local travel = self.travel
	if distance <= 0 or travel == Vector3.zero then
		return
	end
	local pending = self:sharedPending()
	-- a grab earns Unity's fixed window; Classic drift passes its own per-stud share
	local window = windowOverride or Config.PULL_SPAWN_WINDOW
	if window <= 0 then
		return
	end
	-- this window's one event roll (rollEvent), laid by its first firing with room
	local event = rollEvent(self, window / Config.PULL_SPAWN_WINDOW)
	local left = window
	while left > 1e-6 do
		local slice = math.min(Config.SPAWN_SLICE, left)
		left -= slice
		for _, state in self.activeSpawners do
			local def = state.def
			if def.spawnAllOnAwake then
				continue
			end
			updateMovement(state, slice)
			state.timer -= slice
			while state.timer <= 0 do
				local laid = 0
				if underSpawnCap(state) then
					-- (left - timer) spawner-seconds of the window remain after
					-- this spawn (timer <= 0 is the overshoot into this slice)
					local carry = travel * ((left - state.timer) / window * distance)
					local fired: boolean
					laid, fired = spawnFromSpawner(self, state, stagingOffset(state), carry, pending, spawnFn, event)
					if fired then
						event = nil
					end
				end
				-- += (not =) keeps the overshoot, so a big window yields every spawn it covers
				state.timer += rollInterval(def, laid)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Per-tick upkeep (Spawning/Spawner.cs Move() + StepAndScenerySpawner
-- spawnAllOnAwake). Continuous spawning only happens on pulls (spawnForPull);
-- here the Movements cycles advance on the Heartbeat clock (Unity's Move() is its
-- own coroutine, Spawner.cs Activate() L86-97) and a spawnAllOnAwake spawner
-- (the Tutorial ladder) fires its one batch, each entry exactly at its own
-- Movements point. `spawnFn` gets the position to create the part at now
-- (GameServer slides that batch in, see slideIn there).
-- ---------------------------------------------------------------------------
function Lane.tickSpawners(self: Lane, dt: number, spawnFn: SpawnFn)
	for _, state in self.activeSpawners do
		local def = state.def
		if not def.spawnAllOnAwake then
			updateMovement(state, dt)
		elseif not state.awoken then
			state.awoken = true
			local pending = self:sharedPending()
			for i, kindName in def.pool do
				if underSpawnCap(state) then
					local kind = StepKinds[kindName]
					local params = if kind then kind.params else nil
					emit(self, spawnFn, kindName, params, self:spawnPosition(state, i) - pending, state, "awake")
				end
			end
		end
	end
end

-- Populate an empty lane as if the player had already pulled a screenful of
-- steps into view, so a run starts with something to grab (Unity gets the same
-- result from the level-start Pull in LevelManager/SpawnManager). Rows are one
-- PREFILL_ROW_STEP apart along the travel direction, oldest (furthest in) first.
-- `spawnFn` gets the position to create the part at now: the rest position less
-- whatever the lane's running pulls still owe (GameServer then slides the whole
-- batch in from off-screen). Single steps only -- no patterns or events. No-op
-- when the lane already has steps, e.g. a respawn after a death.
function Lane.prefill(self: Lane, spawnFn: SpawnFn)
	local count = 0
	for _ in self.active do
		count += 1
	end
	local travel = self.travel
	if count >= Config.PREFILL_MIN_STEPS or travel == Vector3.zero then
		return
	end

	local pending = self:sharedPending()
	local rows = Config.PREFILL_DEPTH // Config.PREFILL_ROW_STEP
	local rowTime = Config.PULL_SPAWN_WINDOW -- each row is one grab's window
	for row = rows, 1, -1 do
		local travelled = travel * ((row - 1) * Config.PREFILL_ROW_STEP)
		for _, state in self.activeSpawners do
			local def = state.def
			if not def.spawnAllOnAwake then
				state.timer -= rowTime
				while state.timer <= 0 and underSpawnCap(state) do
					-- carried the rest of its row's window too (-timer seconds of
					-- it), so a row's several spawns spread along the travel
					-- direction instead of stacking (same rule as spawnForPull)
					local carry = travelled + travel * (-state.timer / rowTime * Config.PREFILL_ROW_STEP)
					local laid =
						spawnSingle(self, state, stagingOffset(state), carry, pending, spawnFn, false, "prefill")
					if not laid then
						break
					end
					local interval = rollInterval(def, laid)
					state.timer += interval
					updateMovement(state, interval) -- Move() keeps cycling between spawns, as in spawnForPull
				end
			end
		end
	end
end

-- Direction-change scaffold (owner's request b-20260921-182631-0a8u, doc 17).
-- Unity sets SpawnDirection BEFORE the arrow's own pull and its spawners fire on
-- Activate, under a continuous per-frame scroll, so the new direction fills in
-- almost at once; here the arrow's grab has already pulled (and spawned) along
-- the OLD direction, and the new direction's spawners only run on later grabs,
-- starting at their off-screen side staging points. So a direction change lays
-- Config.SCAFFOLD_COUNT ordinary steps from `anchor` (the grabbed arrow's rest
-- point) toward the frog's new heading (-spawnDirection), SCAFFOLD_SPACING apart,
-- rising SCAFFOLD_RISE per step when that heading is purely sideways. Kinds are
-- the new direction's own weighted PLAIN picks (Lane.pickKind: no further
-- arrows, no hazards).
-- Each spot goes through Lane.clearSpot (spacing incl. the kind's sweep, lane
-- bounds, the PlayerList keep-out) and must be within Config.MAX_GRAB_DISTANCE
-- of the origin (GameServer's GrabStep reach check).
--   * Straight up (the Up arrow): a rung whose spot is already taken is skipped
--     (the live steps there are that rung); the chain ends at the first rung
--     beyond reach.
--   * A heading with any sideways part (Left/Right/UpLeft/UpRight): the line
--     leaves a portrait phone's view (Config.SPAWN_VIEW_HALF_WIDTH) after one
--     rung, so each rung is laid at the clear spot inside that view nearest its
--     point on the line, the line bent straight up where it meets the view edge
--     (scaffoldSpotInView). Rungs laid off-screen left the new direction looking
--     empty on a phone (b-20261022-140225-lhat).
-- `spawnFn` gets the position to create the part at now (rest less the lane's
-- running pulls, like prefill); GameServer then slides the batch down in from
-- above the view.

-- How far (studs) a `kindName` step's centre may rest from the lane centre and
-- still have its whole grab box, sweep included, inside the portrait view:
-- sideways, and vertically inside Config.VIEW_HALF_HEIGHT. Same bound
-- fitStaging holds a straight-down spawn to.
local function viewBox(kindName: string, sweep: Vector2): Vector2
	local kind = StepKinds[kindName]
	local hit = if kind and kind.hitSize then kind.hitSize else Vector2.new(DEFAULT_SIZE.X, DEFAULT_SIZE.Y)
	return Vector2.new(
		math.max(0, Config.SPAWN_VIEW_HALF_WIDTH - hit.X / 2 - sweep.X),
		math.max(0, Config.VIEW_HALF_HEIGHT - hit.Y / 2 - sweep.Y)
	)
end

-- The rest spot for a sideways / diagonal scaffold rung meant for `want`: the
-- clear (Lane.clearSpot, no nudge) and reachable point inside the portrait view
-- (viewBox, judged at the grip point) nearest `want` once `want` is bent onto
-- the view -- the part of the line past the heading-side edge turned straight
-- up the edge, so a ladder that runs out of width climbs instead. Searched on a
-- SCAFFOLD_GRID grid over the heading half of the view (centre column
-- included); nil when every point is crowded.
local function scaffoldSpotInView(self: Lane, want: Vector3, side: number, kindName: string, sweep: Vector2): Vector3?
	local box = viewBox(kindName, sweep)
	local grip = gripOf(kindName)
	local rel = want + grip - self.origin -- the grip point, lane-relative
	local excess = math.abs(rel.X) - box.X
	if excess > 0 then
		rel = Vector3.new(math.sign(rel.X) * box.X, rel.Y + excess, 0)
	end
	local ideal = Vector2.new(rel.X, math.clamp(rel.Y, -box.Y, box.Y))
	local spots: { Vector2 } = {}
	local grid = Config.SCAFFOLD_GRID
	for gx = 0, math.floor(box.X / grid) do
		for gy = -math.floor(box.Y / grid), math.floor(box.Y / grid) do
			table.insert(spots, Vector2.new(side * gx * grid, gy * grid))
		end
	end
	table.sort(spots, function(a, b)
		return (a - ideal).Magnitude < (b - ideal).Magnitude
	end)
	for _, spot in spots do
		local pos = self.origin + Vector3.new(spot.X, spot.Y, want.Z) - grip
		local clear = self:clearSpot(pos, kindName, Vector3.zero, sweep)
		if clear and withinReach(self, clear, sweep, kindName) then
			return clear
		end
	end
	return nil
end

function Lane.scaffold(self: Lane, anchor: Vector3, spawnFn: SpawnFn)
	local travel = self.travel
	if travel == Vector3.zero or self:atPotTop() then
		return -- nothing spawns above the pot's rim (Lane.spawnRim)
	end
	local heading = -travel
	local rise = if math.abs(travel.Y) < 1e-4 then Vector3.new(0, Config.SCAFFOLD_RISE, 0) else Vector3.zero
	local side = signOf(heading.X) -- 0: straight up

	local spawners: { SpawnerState } = {}
	for _, state in self.activeSpawners do
		if not state.def.spawnAllOnAwake and #state.def.pool > 0 then
			table.insert(spawners, state)
		end
	end
	if #spawners == 0 then
		return
	end

	local pending = self:sharedPending()
	-- a crowded spot moves a little further along the heading (clearSpot shifts
	-- against its travel argument, scaled here so its SPAWN_NUDGE_MAX search spans
	-- only SCAFFOLD_NUDGE studs)
	local nudge = travel * (Config.SCAFFOLD_NUDGE / Config.SPAWN_NUDGE_MAX)
	for i = 1, Config.SCAFFOLD_COUNT do
		local want = anchor + heading * (Config.SCAFFOLD_SPACING * i) + rise * i
		if side == 0 then
			local kindName = self:pickKind(spawners[math.random(1, #spawners)], true)
			if not kindName then
				return
			end
			local kind = StepKinds[kindName]
			local params = if kind then kind.params else nil
			local sweep = sweepOf(kindName, params)
			if planarDistance(self, want + gripOf(kindName)) > Config.MAX_GRAB_DISTANCE then
				return -- every further rung is further out still
			end
			-- nil means the spot is already taken by live steps (which then serve
			-- as this rung) or would leave the lane, so skip the rung
			local pos = self:clearSpot(want, kindName, nudge, sweep)
			if pos and withinReach(self, pos, sweep, kindName) then
				emit(self, spawnFn, kindName, params, pos - pending, nil, "scaffold")
			end
		else
			-- the view's heading half is narrow, and a mover's sweep (a Lillipad's
			-- patrol) reserves most of it: a kind with no spot there is re-picked,
			-- up to SCAFFOLD_PICKS kinds per rung, leaving the intro cursor as it was
			for _ = 1, Config.SCAFFOLD_PICKS do
				local introIndex = self.introIndex
				local kindName = self:pickKind(spawners[math.random(1, #spawners)], true)
				if not kindName then
					return
				end
				local kind = StepKinds[kindName]
				local params = if kind then kind.params else nil
				local sweep = sweepOf(kindName, params)
				local pos = scaffoldSpotInView(self, want, side, kindName, sweep)
				if pos then
					emit(self, spawnFn, kindName, params, pos - pending, nil, "scaffold")
					break
				end
				self.introIndex = introIndex
			end
		end
	end
end

-- Recycle bound (Borders.prefab.json Left/Right/Top/Bottom catch, doc 11 §3):
-- ANY side, not just the bottom lava line. Only X is lane-relative -- Y bounds
-- are shared world coordinates (lanes only offset along X, doc 13 item 1).
--
-- Measured against the step's own EXTENT, not just its centre: a step part is
-- its sprite's whole Unity canvas (StepKinds.size), which for Rocket/Balloon/
-- Castle is ~32 studs, so a centre-only test recycles them while a good chunk of
-- the art is still on screen -- the fixed BOUNDS_MARGIN was tuned when every step
-- was a ~6-stud box. Unity has the same property for free: Spawning/Spawn.cs
-- recycles on `OnTriggerEnter2D` against the Borders.prefab catch colliders, i.e.
-- when the step's own collider EDGE reaches the border, never its centre. This
-- only ever keeps a step alive longer (by at most its half-extent) and changes no
-- spawn cadence; the extra life is spent entirely outside the view, and an
-- off-screen step stays untappable because GameClient resolves a tap to a point
-- on the play plane inside the camera frustum before testing any step.
--
-- A step mid-motion is only recycled when BOTH where it is now and where it will
-- rest are out: a spawn starts off-screen, past the top catch line, and must
-- survive until the pull carries it in.
--
-- Both tests are on the step's BASE: its visual offset (recoil, sag, a patrol's
-- sweep) is small and bounded and must not decide whether it lives. `shared` is
-- the lane's sharedPending(), which GameServer computes once per lane per tick
-- for this check instead of once per step.
--
-- A step staged upstream on purpose (StepState.upstream: a pattern member behind
-- the ones before it, a rim laid above a tall stack) sits past the entry-side
-- bound from the moment it spawns, with no pull owed to it. It is allowed that
-- far past on that side (outOfBounds' `slack`), or it would be recycled on the
-- very next tick.
function Lane.isOutOfBounds(self: Lane, step: BasePart, shared: Vector3?): boolean
	local size = step.Size
	local state = self.states[step]
	local slack = if state and state.upstream > 0 then self.travel * state.upstream else nil
	return outOfBounds(self, self:basePosition(step), size, slack)
		and outOfBounds(self, self:restPosition(step, shared), size, slack)
end

-- ---------------------------------------------------------------------------
-- The pot rim (journey 1/8, b-20260923-154343-9twj; owner's ruling
-- b-20260928-173934-iff0 -- PORT ADDITION, Unity has no rim, doc 17). Once a
-- Pot run reaches Config.LEVEL_THRESHOLDS.Kitchen steps the Pot stops spawning
-- (Lane.pickKind / Lane.scaffold) and one StepKinds.PotRim step is laid across
-- the lane just above the highest step left, so the steps already on screen
-- lead up to it; grabbing it -- climbing out over the rim -- is the Pot ->
-- Kitchen level-up (Lane.onStepClimbed). The rim is an ordinary replicated
-- step, so every lane's rim renders for every player.
-- ---------------------------------------------------------------------------
-- Called every Heartbeat while the run plays: lays the rim once the Pot is
-- climbed (no-op otherwise, or while this lane's rim is still live -- one that
-- fell away unclimbed is laid again). Rests centred on the lane, its grab box
-- SPAWN_GAP above every live step's (at rest, Lane.restPosition), even when that
-- is past the recycle line (see `upstream` below); `spawnFn` gets the position to create it at now (rest less the
-- running pulls) and GameServer slides it in like a prefill batch.
function Lane.spawnRim(self: Lane, spawnFn: SpawnFn)
	if not self:atPotTop() then
		return
	end
	local top = -math.huge
	local shared = self:sharedPending()
	for step in self.active do
		if step:GetAttribute("KindName") == POT_RIM_KIND then
			return
		end
		local hit = (step:GetAttribute("HitSize") :: Vector2?) or Vector2.new(step.Size.X, step.Size.Y)
		local offset = (step:GetAttribute("HitOffset") :: Vector2?) or Vector2.zero
		top = math.max(top, self:restPosition(step, shared).Y + offset.Y + hit.Y / 2)
	end
	local kind = StepKinds[POT_RIM_KIND]
	local hitOffsetY = if kind.hitOffset then kind.hitOffset.Y else 0
	local y = math.max(top + Config.SPAWN_GAP + kind.hitSize.Y / 2 - hitOffsetY, self.origin.Y)
	-- Above the recycle line (pattern members rest up there, StepState.upstream)
	-- the rim is a step staged upstream too: by however far the lane's scroll
	-- must carry it to bring it down to the line. A lane with no downward travel
	-- can't bring it down at all, so there it stays capped at the line.
	local cap = Config.SPAWN_Y + Config.BOUNDS_MARGIN
	local fall = -self.travel.Y
	local upstream = 0
	if y > cap then
		if fall > 1e-4 then
			upstream = (y - cap) / fall
		else
			y = cap
		end
	end
	-- Under diagonal travel every pull that brings the rim down also carries it
	-- sideways, so one laid centred arrives off to the side -- seen in Studio
	-- (2026-10-05) resting at x = 40, past Config.MAX_GRAB_DISTANCE, with the Pot
	-- no longer spawning anything to climb toward it. Lay it back along the travel
	-- line instead, so it is centred when it reaches the lane origin's height;
	-- capped so the rim's near end still starts inside the lane.
	local x = self.origin.X
	if fall > 1e-4 then
		local lean = self.travel.X / fall * (y - self.origin.Y)
		local maxLean = Config.LANE_HALF_WIDTH + kind.size.X / 2 - Config.BOUNDS_MARGIN
		x -= math.clamp(lean, -maxLean, maxLean)
	end
	spawnFn(self, {
		kindName = POT_RIM_KIND,
		position = Vector3.new(x, y, self.origin.Z) - shared,
		params = kind.params,
		spawner = nil,
		source = "rim",
		upstream = upstream,
	})
end

-- The three Tutorial tree kinds (StepKinds, Levels.luau's Tutorial pool): grabbing
-- one of these never ends the fall-protection grace period below; grabbing
-- anything else (the first real Pot step) does.
local TUTORIAL_TREE_KINDS = {
	TutorialFirstTree = true,
	TutorialSecondTree = true,
	TutorialLastTree = true,
}

-- ---------------------------------------------------------------------------
-- Level flow (Core/LevelManager.cs FillLevelEvents' step-count events, doc 13
-- item 5): Tutorial -> Pot on the 3rd tree climbed (marks tutorialDone), then
-- Pot -> Kitchen on grabbing the pot's rim (laid at LEVEL_THRESHOLDS.Kitchen,
-- Lane.spawnRim), Kitchen -> Country -> Space at LEVEL_THRESHOLDS. Called by GameServer once per
-- successful grab (after it has already bumped the session score), with the
-- grabbed step's kind name so it can also track tutorialGraceActive
-- (b-20260922-101541-w1i2).
-- ---------------------------------------------------------------------------
function Lane.onStepClimbed(self: Lane, kindName: string?)
	self.runSteps += 1
	local levelBefore = self.levelIndex

	if self.tutorialGraceActive and not (kindName and TUTORIAL_TREE_KINDS[kindName]) then
		self.tutorialGraceActive = false
		self.folder:SetAttribute("TutorialGrace", false) -- Pot fire/steam can show now
	end

	if self.levelIndex == Levels.TUTORIAL then
		self.tutorialStepsClimbed += 1
		if self.tutorialStepsClimbed >= Config.TUTORIAL_STEPS then
			local profile = Profiles.get(self.player)
			if profile then
				profile.tutorialDone = true
				Profiles.save(self.player)
			end
			self:levelUp(Levels.POT)
		end
	elseif self.levelIndex == Levels.POT and kindName == POT_RIM_KIND then
		self:levelUp(Levels.KITCHEN)
	elseif self.levelIndex == Levels.KITCHEN and self.runSteps >= Config.LEVEL_THRESHOLDS.Country then
		self:levelUp(Levels.COUNTRY)
	elseif self.levelIndex == Levels.COUNTRY and self.runSteps >= Config.LEVEL_THRESHOLDS.Space then
		self:levelUp(Levels.SPACE)
	end

	-- A height-stage change WITHIN the level (e.g. Pot's 15/35 runSteps stage
	-- bounds). A level transition above already set the attribute (setLevel).
	if self.levelIndex == levelBefore then
		self:updateStageAttribute()
	end
end

-- The frog's gravity multiplier for this lane right now (b-20261020-200915-5ju4):
-- 1 everywhere but Space, where it eases linearly from 1 to
-- Config.SPACE_GRAVITY_SCALE over the first SPACE_GRAVITY_TRANSITION_STEPS steps
-- climbed since the lane arrived, then stays there. GameServer scales the frog's
-- fall speed by it.
function Lane.gravityScale(self: Lane): number
	if self.levelIndex ~= Levels.SPACE then
		return 1
	end
	local span = math.max(1, Config.SPACE_GRAVITY_TRANSITION_STEPS)
	local t = math.clamp((self.runSteps - self.levelStartSteps) / span, 0, 1)
	return 1 + (Config.SPACE_GRAVITY_SCALE - 1) * t
end

-- A real mid-run level-up (never run start or respawn -- those go through
-- Lane.new / Lane.resetRun): switch level, play the arrival beat, then tell
-- the client ("soft").
function Lane.levelUp(self: Lane, levelIndex: number)
	self:setLevel(levelIndex)
	self:beginArrival()
	if self.notify then
		self.notify(self, "soft")
	end
end

-- The level-up ARRIVAL beat (journey 2/8, b-20260923-154343-3h60) -- the one
-- place it's triggered; for Pot -> Kitchen that is now the grab of the pot's
-- rim (Lane.spawnRim, b-20260923-154343-9twj). Holds Classic
-- drift for Config.CLASSIC_ARRIVAL_HOLD_TIME (Lane.driftSpeed) and bumps the
-- lane folder's replicated `ArrivalCount` attribute, which every client-side
-- piece of the beat keys off: GameClient's camera pull-back and Music's sting
-- (local lane only), WorldScenery's fade of the previous level's scenery
-- (every lane).
function Lane.beginArrival(self: Lane)
	self.driftHold = Config.CLASSIC_ARRIVAL_HOLD_TIME
	local count = self.folder:GetAttribute("ArrivalCount")
	self.folder:SetAttribute("ArrivalCount", (if typeof(count) == "number" then count else 0) + 1)
end

-- The scroll a lane's run has built up, started over: its fairness ring, its
-- running motions (the caller just emptied the lane, GameServer.clearLaneSteps),
-- the replicated pull total and the Classic drift.
local function restartScroll(self: Lane)
	resetRecent(self)
	table.clear(self.motions)
	-- PullEpoch is bumped FIRST: it tells a client's PullScroller that the total
	-- (GameServer.publishPull) restarted, so the drop to zero is not read as a pull back.
	local epoch = self.folder:GetAttribute("PullEpoch")
	self.folder:SetAttribute("PullEpoch", (if typeof(epoch) == "number" then epoch else 0) + 1)
	self.folder:SetAttribute("PullTotal", Vector3.zero)
	self.driftDistance = 0
	self.driftTime = 0
	self.driftElapsed = 0
	self.driftBase = 0
	self.driftHold = 0
end

-- A new run: back to Pot, or Tutorial if this profile never finished it
-- (doc 13 item 5). Soft -- doesn't touch `self.active` either.
function Lane.resetRun(self: Lane, tutorialDone: boolean)
	self.runSteps = 0
	self.tutorialStepsClimbed = 0
	self.tutorialGraceActive = not tutorialDone
	self.folder:SetAttribute("TutorialGrace", not tutorialDone)
	restartScroll(self)
	self:setLevel(if tutorialDone then Levels.POT else Levels.TUTORIAL)
	if self.notify then
		self.notify(self, "death")
	end
end

-- Studio-only level skip (GameServer's ServerStorage/StudioSkipTo,
-- b-20261020-213324-txe8): put this lane in `levelIndex` as if the run had
-- climbed there -- `runSteps` steps this run, the level entered at
-- `levelStartSteps` (what height stages, Space's gravity ease and the level-up
-- thresholds in onStepClimbed count from) and `treesClimbed` Tutorial trees --
-- with fresh spawners, so the next real grabs play the real transition. The
-- caller has emptied the lane and prefills it after. A lane landed partway
-- through its level skips that level's introSequence. Fires notify("start"),
-- which snaps the client's backdrop and music to the level.
function Lane.skipTo(self: Lane, levelIndex: number, runSteps: number, levelStartSteps: number, treesClimbed: number)
	restartScroll(self)
	self.runSteps = levelStartSteps
	self:setLevel(levelIndex) -- levelStartSteps = runSteps, Level/Stage attributes
	self.runSteps = runSteps
	local intro = self.level.introSequence
	if intro and runSteps > levelStartSteps then
		self.introIndex = #intro + 1
	end
	self.tutorialStepsClimbed = treesClimbed
	self.tutorialGraceActive = levelIndex == Levels.TUTORIAL
	self.folder:SetAttribute("TutorialGrace", self.tutorialGraceActive)
	self:updateStageAttribute()
	if self.notify then
		self.notify(self, "start")
	end
end

-- ---------------------------------------------------------------------------
-- Construction / teardown
-- ---------------------------------------------------------------------------

-- `notify(lane, transition)` is called once at the end of construction (with
-- "start") and again on every later transition ("soft" from onStepClimbed,
-- "death" from resetRun) -- GameServer uses it to fire the LevelChanged remote
-- without Lane needing to know about remotes at all.
function Lane.new(player: Player, tutorialDone: boolean, notify: ((Lane, string) -> ())?): Lane
	local playField = workspace:WaitForChild("PlayField")
	local lanesFolder = playField:WaitForChild("Lanes")

	local slot = nextSlot()
	local origin = Vector3.new(slot * Config.LANE_SPACING, 0, Config.PLANE_Z)

	local folder = Instance.new("Folder")
	folder.Name = tostring(player.UserId)
	folder:SetAttribute("UserId", player.UserId)
	folder:SetAttribute("Origin", origin)
	folder:SetAttribute("Mode", Config.RUN_MODES.Normal)
	folder:SetAttribute("PullTotal", Vector3.zero) -- GameServer.publishPull; restarted by Lane.resetRun
	folder:SetAttribute("PullEpoch", 0)
	folder.Parent = lanesFolder

	local self = setmetatable({
		player = player,
		userId = player.UserId,
		slot = slot,
		origin = origin,
		folder = folder,
		levelIndex = Levels.TUTORIAL,
		level = Levels.list[Levels.TUTORIAL],
		spawnDirection = Vector2.new(0, -1),
		travel = Vector3.new(0, -1, 0),
		spawnerStates = {},
		activeSpawners = {},
		active = {},
		states = {},
		motions = {},
		netPull = 0,
		mode = Config.RUN_MODES.Normal,
		driftDistance = 0,
		driftTime = 0,
		driftElapsed = 0,
		driftBase = 0,
		driftHold = 0,
		introIndex = 1,
		obstruction = nil,
		runSteps = 0,
		levelStartSteps = 0,
		recentHazards = {},
		recentCursor = 0,
		hazardCount = 0,
		eventLast = {},
		tutorialStepsClimbed = 0,
		tutorialGraceActive = not tutorialDone,
		notify = notify,
	}, Lane) :: Lane

	registry[player] = self
	folder:SetAttribute("TutorialGrace", not tutorialDone) -- clients hold Pot fire/steam until it clears
	self:setLevel(if tutorialDone then Levels.POT else Levels.TUTORIAL)
	if self.notify then
		self.notify(self, "start")
	end

	return self
end

function Lane.destroy(self: Lane)
	registry[self.player] = nil
	releaseSlot(self.slot)
	table.clear(self.active)
	table.clear(self.states)
	if self.folder.Parent then
		self.folder:Destroy()
	end
end

return Lane
