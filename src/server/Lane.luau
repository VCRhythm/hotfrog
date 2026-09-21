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
local Levels = require(ReplicatedStorage.Shared.Levels)
local StepKinds = require(ReplicatedStorage.Shared.StepKinds)
local StepBehaviors = require(ReplicatedStorage.Shared.StepBehaviors)
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
		spawnerStates: { SpawnerState },
		activeSpawners: { SpawnerState },
		active: { [BasePart]: boolean }, -- this lane's own live steps
		-- Spawner seconds still to be spent. Unity's step spawners only run WHILE
		-- the field is being pulled (SpawnManager.PullStep activates them,
		-- ReleasePullingStep deactivates them), so spawner time is earned by pull
		-- distance (addPull), never by wall-clock time -- steps don't move between
		-- pulls, and a free-running timer would pile them up at the entry edge.
		spawnBudget: number,
		-- Seconds until the last pull's tween settles; spawning waits for it (Lane.addPull).
		pullSettle: number,
		-- Net forward scroll (studs) accumulated since this level began, floored at 0.
		-- Exists so the Tutorial "no death" retry (GameServer.tutorialRetry) can never
		-- undo more scroll than has actually happened -- see Lane.addPull below.
		netPull: number,
		runSteps: number, -- steps climbed this run, across levels (drives LEVEL_THRESHOLDS)
		tutorialStepsClimbed: number,
		-- called explicitly by whichever method changes the level, WITH the
		-- transition kind ("start" | "soft" | "death") -- never auto-fired from
		-- setLevel itself, so callers control the label (doc 13 item 6).
		notify: ((Lane, string) -> ())?,
	},
	Lane
))

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
	self.spawnDirection = level.initialSpawnDirection
	self.netPull = 0 -- fresh scroll baseline for this level (see Lane.addPull)

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
end

-- A grabbed ChangeDirection* step (StepBehaviors setSpawnBias) asks to steer the
-- lane. Per doc 13 item 3: if this level has no spawner for the requested
-- direction, keep the CURRENT direction active rather than starving the lane.
function Lane.changeDirection(self: Lane, newDirection: Vector2)
	local matches = self:spawnersForDirection(newDirection)
	if #matches == 0 then
		return
	end
	self.spawnDirection = newDirection
	self.activeSpawners = matches
end

-- ---------------------------------------------------------------------------
-- Weighted kind pick (Spawning/Spawner.cs SetUpSpawnProbabilities + CreateSpawn):
-- normalize spawnProbability over the spawner's own pool, roll, then gate on the
-- picked kind's behavior canSpawn (StepSpawner.CreateSpawn's canBeSpawned retry
-- loop). Bounded retries instead of Unity's unbounded recursion, with a final
-- deterministic fallback so a pathological all-gated pool can't spawn nothing.
-- ---------------------------------------------------------------------------
function Lane.pickKind(self: Lane, state: SpawnerState): string?
	local pool = state.def.pool
	if #pool == 0 then
		return nil
	end

	local total = 0
	for _, kindName in pool do
		local kind = StepKinds[kindName]
		total += (kind and kind.spawnProbability) or 0
	end

	local function canSpawnKind(kindName: string): boolean
		local kind = StepKinds[kindName]
		local behavior = kind and StepBehaviors[kind.behavior]
		return not behavior or not behavior.canSpawn or behavior.canSpawn(self.spawnDirection, state.spawnCount)
	end

	if total > 0 then
		local attempts = #pool * 2
		for _ = 1, attempts do
			local r = math.random() * total
			local chosen: string = pool[#pool]
			for _, kindName in pool do
				local kind = StepKinds[kindName]
				r -= (kind and kind.spawnProbability) or 0
				if r <= 0 then
					chosen = kindName
					break
				end
			end
			if canSpawnKind(chosen) then
				return chosen
			end
		end
	end

	-- everything gated out (or spawnProbability summed to 0): fall back to the
	-- first pool entry whose behavior doesn't gate at all
	for _, kindName in pool do
		if canSpawnKind(kindName) then
			return kindName
		end
	end
	return pool[1]
end

-- ---------------------------------------------------------------------------
-- Movements-list cycling (Spawning/Spawner.cs Move() coroutine, L123-147). Only
-- touches spawners whose Levels.luau `def.movements` is non-empty -- see
-- Lane.spawnPosition below for the empty-list procedural fallback this replaces.
-- Unity's Move() runs on its own clock, fully independent of spawning/spawnBudget
-- (Activate() L86-97 starts Move() and StartSpawning as two separate coroutines);
-- updateMovement mirrors that by always advancing on the full Heartbeat `dt`,
-- not the pull-earned `spend` budget tickSpawners' spawn cadence uses below.
--
-- `Lane.spawnPosition` clamps the result into Lane.isOutOfBounds' recycle margin
-- (BOUNDS_MARGIN) before adding it to the lane's origin: the converted Movements
-- offsets (Levels.luau) are deliberately off-screen "staging" positions, matching
-- Unity's own adjustedMovements, but Unity drags those onscreen with a continuous
-- per-frame PullVector (Spawning/SpawnManager.cs Pull/PullStep) while this port's
-- steps only move on a discrete per-grab tween (GameServer.pullLane) -- an
-- unclamped literal offset would be recycled before ever being pulled in.
-- ---------------------------------------------------------------------------
local BOUNDS_MARGIN = 6 -- also used by Lane.isOutOfBounds below -- keep in sync

-- Axis clamps alone let a CORNER of the box (max |X| and max |Y| at once) sit
-- farther from the frog -- always at the lane origin (GameServer never moves
-- f.pos.X, and f.pos.Y sits near 0) -- than Config.MAX_GRAB_DISTANCE, i.e. past
-- GameServer's own GrabStep reach check, so the step spawns already permanently
-- ungrabbable. E.g. Tutorial's TreeDownStepSpawner 3rd tree and Pot/Kitchen/
-- Country's DownStepSpawner/DownLeftStepSpawner both clamp to (25, ~20-25) --
-- 32-35 studs out. Pull those corners back onto the reach circle; in-range
-- spawns (the common case) are untouched.
--
-- A spawner whose travel has no X component (Down) moves its steps straight down, so X
-- never changes after the spawn: keep it inside Config.SPAWN_VIEW_HALF_WIDTH (Unity's
-- portrait view) or the step is never seen. Diagonal/sideways spawners keep the lane
-- bound, because their travel carries a step in from the side (b-20260921-112713-7mxu).
local function clampToLane(offset: Vector3, direction: Vector2): Vector3
	local halfX = if signOf(direction.X) == 0 then Config.SPAWN_VIEW_HALF_WIDTH else Config.LANE_HALF_WIDTH + 3
	local x = math.clamp(offset.X, -halfX, halfX)
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
		state.moveWaitTime = state.def.moveTimeMin
			+ math.random() * math.max(0, state.def.moveTimeMax - state.def.moveTimeMin)
		return
	end

	state.moveElapsed += dt
	if state.moveElapsed < state.moveWaitTime then
		return
	end

	-- leg finished: pick the next destination and start a new one (Spawner.cs Move(), L133-145)
	local nextIndex = pickMovementIndex(count, state.moveToIndex)
	local speed = state.def.moveSpeedMin + math.random() * math.max(0, state.def.moveSpeedMax - state.def.moveSpeedMin)
	local nextMoveTime = state.def.moveTimeMin
		+ math.random() * math.max(0, state.def.moveTimeMax - state.def.moveTimeMin)

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
function Lane.spawnPosition(self: Lane, state: SpawnerState, indexInBatch: number?): Vector3
	local movements = state.def.movements

	if indexInBatch and #movements > 0 then
		local idx = ((indexInBatch - 1) % #movements) + 1
		return self.origin + clampToLane(movements[idx], state.def.direction)
	end

	if not indexInBatch and #movements > 0 then
		return self.origin + clampToLane(currentMovementOffset(state), state.def.direction)
	end

	local dir = state.def.direction
	local ex, ey = -signOf(dir.X), -signOf(dir.Y) -- entry edge = opposite the travel direction

	local x: number, y: number
	if ex ~= 0 and ey ~= 0 then
		-- diagonal: spawn in the corresponding top/bottom corner region
		x = ex * (Config.LANE_HALF_WIDTH - math.random() * (Config.LANE_HALF_WIDTH * 0.4))
		y = if ey > 0 then Config.SPAWN_Y else Config.DESPAWN_Y
	elseif ex ~= 0 then
		-- pure horizontal: enter from the left/right edge, spread across a vertical band
		x = ex * (Config.LANE_HALF_WIDTH + 3)
		y = (math.random() * 2 - 1) * (Config.SPAWN_Y * 0.6)
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

	return self.origin + Vector3.new(x, y, 0)
end

-- Recycle test for a step of `size` centred at `pos` -- see Lane.isOutOfBounds.
local function outOfBounds(self: Lane, pos: Vector3, size: Vector3): boolean
	local halfX, halfY = size.X / 2, size.Y / 2
	local relX = pos.X - self.origin.X
	local boundX = Config.LANE_HALF_WIDTH + BOUNDS_MARGIN
	if relX + halfX < -boundX or relX - halfX > boundX then
		return true
	end
	return (pos.Y + halfY) < Config.DESPAWN_Y or (pos.Y - halfY) > (Config.SPAWN_Y + BOUNDS_MARGIN)
end

local NUDGE_STEP = 1 -- studs per try
local NUDGE_MAX = 12 -- studs; about two steps' worth of queue behind a crowded spawn

-- Where a new step of `kindName` can go without its grab box (StepKinds hitSize)
-- coming within Config.SPAWN_GAP of a live step's: `pos` itself, or the first
-- point back along the travel line (upstream, i.e. further off-screen) that is
-- clear. nil when that would leave the lane's bounds, and the spawn is skipped.
-- The port packs a grab's spawns into 6 studs of scroll where Unity's ~80 u/s
-- field spread them over ~25 (doc 17 "Spawner time per grab"), so without this
-- one spawner's consecutive steps land 2-3 studs apart and overlap
-- (b-20260921-112713-7mxu). Live positions are only valid once a pull's tween
-- has settled, which is why tickSpawners waits for `pullSettle`.
function Lane.clearSpot(self: Lane, pos: Vector3, kindName: string, travel: Vector3): Vector3?
	local kind = StepKinds[kindName]
	local size = if kind then kind.size else Vector3.new(6, 6, 1)
	local hit = if kind and kind.hitSize then kind.hitSize else Vector2.new(size.X, size.Y)
	local shift = 0
	while shift <= NUDGE_MAX do
		local p = pos - travel * shift
		if outOfBounds(self, p, size) then
			return nil
		end
		local clear = true
		for step in self.active do
			local other = (step:GetAttribute("HitSize") :: Vector2?) or Vector2.new(step.Size.X, step.Size.Y)
			local d = step.Position - p
			if
				math.abs(d.X) < (hit.X + other.X) / 2 + Config.SPAWN_GAP
				and math.abs(d.Y) < (hit.Y + other.Y) / 2 + Config.SPAWN_GAP
			then
				clear = false
				break
			end
		end
		if clear then
			return p
		end
		if travel.Magnitude < 1e-4 then
			return nil
		end
		shift += NUDGE_STEP
	end
	return nil
end

-- A pull of `distance` studs earns the spawners that much running time
-- (Config.PULL_SPAWN_SPEED = how fast Unity's field moves during a pull). Also
-- tracks net forward scroll since this level began (floored at 0) so a later
-- negative "undo" pull -- GameServer.tutorialRetry's Tutorial "no death" rule --
-- can be capped against it and never overshoot past the level's start (doc 17
-- gap: an uncapped retry pull-back permanently scrolled the Tutorial's one-shot
-- ladder, which never respawns, off the top of the field before it was ever
-- climbed).
function Lane.addPull(self: Lane, distance: number)
	if distance > 0 then
		self.spawnBudget += distance / Config.PULL_SPAWN_SPEED
		-- spawn only once this pull's tween (GameServer.pullLane) has settled,
		-- so Lane.clearSpot compares against where the steps actually rest
		self.pullSettle = Config.PULL_TIME
	end
	self.netPull = math.max(0, self.netPull + distance)
end

-- ---------------------------------------------------------------------------
-- Per-tick spawning (Spawning/Spawner.cs StartSpawning coroutine +
-- StepAndScenerySpawner spawnAllOnAwake). `spawnFn` is provided by GameServer,
-- which owns the pooled step Instances and behavior dispatch; Lane only decides
-- WHEN, WHICH KIND, and WHERE.
-- ---------------------------------------------------------------------------
function Lane.tickSpawners(
	self: Lane,
	dt: number,
	spawnFn: (state: SpawnerState, kindName: string, worldPos: Vector3) -> ()
)
	-- continuous spawners only advance on time earned by pulling (see spawnBudget).
	-- The pull that earned it has already happened in one PULL_TIME tween, so drain
	-- the budget on that same timescale rather than 1 s per s: otherwise a player
	-- grabbing faster than once per second outruns the spawners (the field moves a
	-- full PULL_DISTANCE per grab regardless) and the backlog never surfaces in time.
	-- Where each spawn lands doesn't depend on when it's spent (see `unspent` below).
	local spend = math.min(self.spawnBudget, math.max(dt, self.spawnBudget * dt / Config.PULL_TIME))
	if self.pullSettle > 0 then
		self.pullSettle -= dt
		spend = 0 -- steps are still tweening (see Lane.addPull)
	end
	self.spawnBudget -= spend
	local dir3 = Vector3.new(self.spawnDirection.X, self.spawnDirection.Y, 0)
	local travel = if dir3.Magnitude > 1e-4 then dir3.Unit else Vector3.zero

	for _, state in self.activeSpawners do
		local def = state.def
		-- Move() runs on its own clock (full dt), independent of the spend-gated spawn
		-- cadence below (Spawner.cs Activate() starts Move()/StartSpawning as two separate
		-- coroutines, L86-97) -- moot for spawnAllOnAwake defs, whose positions come
		-- straight from `def.movements[i]` (see Lane.spawnPosition), not this cycle.
		-- (Advanced by the spawner-time spent when that's more than dt, so a fast
		-- drain still sweeps the spawner along its Movements as Unity's 1 s window would.)
		if not def.spawnAllOnAwake and #def.movements > 0 then
			updateMovement(state, math.max(dt, spend))
		end
		if def.spawnAllOnAwake then
			if not state.awoken then
				state.awoken = true
				for i, kindName in def.pool do
					if def.maxSpawnCount < 0 or state.spawnCount < def.maxSpawnCount then
						spawnFn(state, kindName, self:spawnPosition(state, i))
						state.spawnCount += 1
					end
				end
			end
		elseif spend > 0 then
			state.timer -= spend
			while state.timer <= 0 do
				if def.maxSpawnCount < 0 or state.spawnCount < def.maxSpawnCount then
					local kindName = self:pickKind(state)
					if kindName then
						-- The pull that earned this budget already happened (one
						-- tween at grab time), but under Unity's continuous scroll a
						-- spawn this far into the window would still ride the rest
						-- of it: carry it along the travel direction by the budget
						-- that was still unspent at its spawn moment (this frame's
						-- remainder + the overshoot past the timer). Without this,
						-- every spawn of one grab's ~1 s window lands on the same
						-- staging point and they stack.
						local unspent = self.spawnBudget - state.timer
						local pos = self:clearSpot(
							self:spawnPosition(state) + travel * (unspent * Config.PULL_SPAWN_SPEED),
							kindName,
							travel
						)
						if pos then
							spawnFn(state, kindName, pos)
							state.spawnCount += 1
						end
					end
				end
				-- += (not =) keeps the overshoot, so a big spend yields every spawn it covers
				state.timer += math.max(
					0.05,
					def.spawningSpeedMin + math.random() * math.max(0, def.spawningSpeedMax - def.spawningSpeedMin)
				)
			end
		end
	end
end

-- Populate an empty lane as if the player had already pulled a screenful of
-- steps into view, so a run starts with something to grab (Unity gets the same
-- result from the level-start Pull in LevelManager/SpawnManager). Rows are one
-- PULL_DISTANCE apart along the travel direction, oldest (furthest in) first.
-- No-op when the lane already has steps, e.g. a respawn after a death.
function Lane.prefill(self: Lane, spawnFn: (state: SpawnerState, kindName: string, worldPos: Vector3) -> ())
	local count = 0
	for _ in self.active do
		count += 1
	end
	local dir3 = Vector3.new(self.spawnDirection.X, self.spawnDirection.Y, 0)
	if count >= Config.PREFILL_MIN_STEPS or dir3.Magnitude < 1e-4 then
		return
	end

	local rows = Config.PREFILL_DEPTH // Config.PULL_DISTANCE
	local rowTime = Config.PULL_DISTANCE / Config.PULL_SPAWN_SPEED
	for row = rows, 1, -1 do
		local travelled = dir3.Unit * ((row - 1) * Config.PULL_DISTANCE)
		for _, state in self.activeSpawners do
			local def = state.def
			if not def.spawnAllOnAwake then
				state.timer -= rowTime
				while state.timer <= 0 and (def.maxSpawnCount < 0 or state.spawnCount < def.maxSpawnCount) do
					local kindName = self:pickKind(state)
					if not kindName then
						break
					end
					-- carried the rest of its row's window too (-timer seconds of
					-- it), so a row's several spawns spread along the travel
					-- direction instead of stacking (same rule as tickSpawners)
					local carried = travelled + dir3.Unit * (-state.timer * Config.PULL_SPAWN_SPEED)
					local pos = self:clearSpot(self:spawnPosition(state) + carried, kindName, dir3.Unit)
					if pos then
						spawnFn(state, kindName, pos)
						state.spawnCount += 1
					end
					local interval = def.spawningSpeedMin
						+ math.random() * math.max(0, def.spawningSpeedMax - def.spawningSpeedMin)
					interval = math.max(interval, 0.05) -- never loop forever on a 0-interval def
					state.timer += interval
					updateMovement(state, interval) -- Move() keeps cycling between spawns, as in tickSpawners
				end
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
function Lane.isOutOfBounds(self: Lane, step: BasePart): boolean
	return outOfBounds(self, step.Position, step.Size)
end

-- ---------------------------------------------------------------------------
-- Level flow (Core/LevelManager.cs FillLevelEvents' step-count events, doc 13
-- item 5): Tutorial -> Pot on the 3rd tree climbed (marks tutorialDone), then
-- Pot -> Kitchen -> Country at LEVEL_THRESHOLDS. Called by GameServer once per
-- successful grab (after it has already bumped the session score).
-- ---------------------------------------------------------------------------
function Lane.onStepClimbed(self: Lane)
	self.runSteps += 1

	if self.levelIndex == Levels.TUTORIAL then
		self.tutorialStepsClimbed += 1
		if self.tutorialStepsClimbed >= 3 then
			local profile = Profiles.get(self.player)
			if profile then
				profile.tutorialDone = true
				Profiles.save(self.player)
			end
			self:setLevel(Levels.POT)
			if self.notify then
				self.notify(self, "soft")
			end
		end
	elseif self.levelIndex == Levels.POT and self.runSteps >= Config.LEVEL_THRESHOLDS.Kitchen then
		self:setLevel(Levels.KITCHEN)
		if self.notify then
			self.notify(self, "soft")
		end
	elseif self.levelIndex == Levels.KITCHEN and self.runSteps >= Config.LEVEL_THRESHOLDS.Country then
		self:setLevel(Levels.COUNTRY)
		if self.notify then
			self.notify(self, "soft")
		end
	end
end

-- A new run: back to Pot, or Tutorial if this profile never finished it
-- (doc 13 item 5). Soft -- doesn't touch `self.active` either.
function Lane.resetRun(self: Lane, tutorialDone: boolean)
	self.runSteps = 0
	self.tutorialStepsClimbed = 0
	self.spawnBudget = 0
	self:setLevel(if tutorialDone then Levels.POT else Levels.TUTORIAL)
	if self.notify then
		self.notify(self, "death")
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
		spawnerStates = {},
		activeSpawners = {},
		active = {},
		spawnBudget = 0,
		pullSettle = 0,
		netPull = 0,
		runSteps = 0,
		tutorialStepsClimbed = 0,
		notify = notify,
	}, Lane) :: Lane

	registry[player] = self
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
	if self.folder.Parent then
		self.folder:Destroy()
	end
end

return Lane
