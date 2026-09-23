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
local TweenService = game:GetService("TweenService")

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

-- One eased displacement of this lane's steps (see "Motions" below). `only` nil
-- = a pull: every step in `active` on each frame it runs, including steps spawned
-- after it started. `only` set = a slide-in of just those steps.
export type Motion = {
	delta: Vector3,
	duration: number,
	elapsed: number,
	only: { [BasePart]: boolean }?,
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
	self.spawnDirection = newDirection
	self.activeSpawners = matches
	return changed
end

-- ---------------------------------------------------------------------------
-- Height-stage lookup (b-20260923-154344-dr8a, journey 3/8): the stage from
-- `self.level.heightStages` (Levels.luau, currently only Pot) whose
-- `maxRunSteps` bound isn't yet passed, plus its 1-based index -- nil, nil for
-- a level with no heightStages (every level but Pot) or an empty runSteps-less
-- lane. Used by both Lane.pickKind (weight overrides) and
-- Lane.updateStageAttribute (the replicated `Stage` attribute WorldScenery
-- reads for its Bubble/Flame density).
-- ---------------------------------------------------------------------------
local function currentHeightStage(self: Lane): (Levels.HeightStage?, number?)
	local stages = self.level.heightStages
	if not stages then
		return nil, nil
	end
	for i, stage in stages do
		if self.runSteps < stage.maxRunSteps then
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

-- ---------------------------------------------------------------------------
-- Weighted kind pick (Spawning/Spawner.cs SetUpSpawnProbabilities + CreateSpawn):
-- normalize spawnProbability over the spawner's own pool, roll, then gate on the
-- picked kind's behavior canSpawn (StepSpawner.CreateSpawn's canBeSpawned retry
-- loop). Bounded retries instead of Unity's unbounded recursion, with a final
-- deterministic fallback so a pathological all-gated pool can't spawn nothing.
--
-- Height-stage weight overrides (b-20260923-154344-dr8a): when the lane's
-- level has heightStages (Pot only), the current stage's `weights[kindName]`
-- replaces StepKinds[kindName].spawnProbability for any pool kind it lists;
-- kinds it doesn't list keep their normal StepKinds weight. A level with no
-- heightStages picks exactly as before.
-- ---------------------------------------------------------------------------
function Lane.pickKind(self: Lane, state: SpawnerState): string?
	local pool = state.def.pool
	if #pool == 0 then
		return nil
	end

	local function canSpawnKind(kindName: string): boolean
		local kind = StepKinds[kindName]
		local behavior = kind and StepBehaviors[kind.behavior]
		return not behavior or not behavior.canSpawn or behavior.canSpawn(self.spawnDirection, state.spawnCount)
	end

	-- Level-entry intro sequence (b-20260923-154345-g9ea): hand out
	-- self.level.introSequence in order, one kind per call, ahead of the normal
	-- weighted pick -- but only when THIS spawner's own pool carries that kind
	-- (and it still passes the usual canSpawn gate), so a level's other spawners
	-- (idle at level entry, or grabbed into later) can't be forced into a kind
	-- they never carry; they just leave the cursor for the spawner that does.
	local intro = self.level.introSequence
	if intro and self.introIndex <= #intro then
		local kindName = intro[self.introIndex]
		if table.find(pool, kindName) and canSpawnKind(kindName) then
			self.introIndex += 1
			return kindName
		end
	end

	local stage = currentHeightStage(self)

	local function weightOf(kindName: string): number
		if stage and stage.weights[kindName] then
			return stage.weights[kindName] :: number
		end
		local kind = StepKinds[kindName]
		return (kind and kind.spawnProbability) or 0
	end

	local total = 0
	for _, kindName in pool do
		total += weightOf(kindName)
	end

	if total > 0 then
		local attempts = #pool * 2
		for _ = 1, attempts do
			local r = math.random() * total
			local chosen: string = pool[#pool]
			for _, kindName in pool do
				r -= weightOf(kindName)
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
-- Unity's Move() runs on its own clock, fully independent of spawning
-- (Activate() L86-97 starts Move() and StartSpawning as two separate coroutines);
-- tickSpawners mirrors that by advancing it on the Heartbeat `dt`, and
-- spawnForPull also sweeps it through each pull's spawner window.
--
-- `Lane.spawnPosition` clamps the result into Lane.isOutOfBounds' recycle margin
-- (BOUNDS_MARGIN) before adding it to the lane's origin: the converted Movements
-- offsets (Levels.luau) are deliberately off-screen "staging" positions, matching
-- Unity's own adjustedMovements, but Unity drags those onscreen with a continuous
-- per-frame PullVector (Spawning/SpawnManager.cs Pull/PullStep) while this port's
-- steps only move on a discrete per-grab pull (Lane.addPull) -- an unclamped
-- literal offset would be recycled before ever being pulled in.
-- ---------------------------------------------------------------------------
local BOUNDS_MARGIN = 6 -- also used by Lane.isOutOfBounds below -- keep in sync

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
local DEFAULT_SIZE = Vector3.new(6, 6, 1)

-- ---------------------------------------------------------------------------
-- Motions. Every pull (and every slide-in) is an eased displacement played on
-- the server's own clock (advanceMotions, from GameServer's Heartbeat) rather
-- than a TweenService tween per step. They add up: a grab that lands mid-pull
-- keeps the rest of the previous pull instead of cancelling it, and a step
-- spawned during a pull rides whatever is left of it. Easing is Sine/Out, the
-- curve WorldScenery tweens the lane's cosmetics with off PullDelta/PullTime.
-- ---------------------------------------------------------------------------
local function eased(m: Motion, elapsed: number): number
	if m.duration <= 0 then
		return 1
	end
	return TweenService:GetValue(
		math.clamp(elapsed / m.duration, 0, 1),
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.Out
	)
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

-- Where `step` comes to rest once every motion playing on it has finished.
function Lane.restPosition(self: Lane, step: BasePart): Vector3
	local pos = step.Position
	for _, m in self.motions do
		local only = m.only
		if not only or only[step] then
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

-- Advance every motion by `dt`, moving the lane's steps by each one's eased increment.
function Lane.advanceMotions(self: Lane, dt: number)
	for i = #self.motions, 1, -1 do
		local m = self.motions[i]
		local before = eased(m, m.elapsed)
		m.elapsed += dt
		local inc = m.delta * (eased(m, m.elapsed) - before)
		if inc.Magnitude > 0 then
			local only = m.only
			if only then
				for step in only do
					if self.active[step] then
						step.CFrame += inc
					end
				end
			else
				for step in self.active do
					step.CFrame += inc
				end
			end
		end
		if m.elapsed >= m.duration then
			table.remove(self.motions, i)
		end
	end
end

-- How far back along `travel` (studs) a step of `size` must start, relative to
-- `pos`, so its whole extent is outside the camera band (Config.VIEW_HALF_HEIGHT)
-- on the side it enters from. Motion along `travel` then carries it into view:
-- it slides in rather than popping up (owner's ruling, b-20260921-164429-ee9c).
-- Any vertical component decides it (steps entering from the top); pure sideways
-- travel uses the same half-extent as an assumed half-width, since the server
-- can't see the client's aspect ratio.
local ENTRY_MARGIN = 0.5 -- studs past the band edge, so rounding never leaves a sliver on screen

function Lane.entryShift(self: Lane, pos: Vector3, size: Vector3, travel: Vector3): number
	local rel = pos - self.origin
	local h = Config.VIEW_HALF_HEIGHT
	if math.abs(travel.Y) > 1e-4 then
		local clear = h + size.Y / 2 + ENTRY_MARGIN
		local need = if travel.Y < 0 then clear - rel.Y else rel.Y + clear
		return math.max(0, need / math.abs(travel.Y))
	elseif math.abs(travel.X) > 1e-4 then
		local clear = h + size.X / 2 + ENTRY_MARGIN
		local need = if travel.X < 0 then clear - rel.X else rel.X + clear
		return math.max(0, need / math.abs(travel.X))
	end
	return 0
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
function Lane.clearSpot(self: Lane, pos: Vector3, kindName: string, travel: Vector3): Vector3?
	local kind = StepKinds[kindName]
	local size = if kind then kind.size else DEFAULT_SIZE
	local hit = if kind and kind.hitSize then kind.hitSize else Vector2.new(size.X, size.Y)
	local hitOffset = if kind and kind.hitOffset then kind.hitOffset else Vector2.zero
	local avoidObstruction = self.obstruction ~= nil and not self:drifts()
	local shift = 0
	while shift <= NUDGE_MAX do
		local p = pos - travel * shift
		if outOfBounds(self, p, size) then
			return nil
		end
		local clear = not (avoidObstruction and self:obstructs(p, hit, hitOffset))
		for step in self.active do
			if not clear then
				break
			end
			local other = (step:GetAttribute("HitSize") :: Vector2?) or Vector2.new(step.Size.X, step.Size.Y)
			local d = self:restPosition(step) - p
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

-- Start a pull of `distance` studs along this lane's spawn direction, played
-- over `duration` s by advanceMotions. Returns the displacement (nil when the
-- lane has no direction). Also tracks net forward scroll since this level began
-- (floored at 0) so a later negative "undo" pull -- GameServer.tutorialRetry's
-- Tutorial "no death" rule -- can be capped against it and never overshoot past
-- the level's start (doc 17 gap: an uncapped retry pull-back permanently
-- scrolled the Tutorial's one-shot ladder, which never respawns, off the top of
-- the field before it was ever climbed).
function Lane.addPull(self: Lane, distance: number, duration: number): Vector3?
	local dir3 = Vector3.new(self.spawnDirection.X, self.spawnDirection.Y, 0)
	if dir3.Magnitude < 1e-4 then
		return nil
	end
	local delta = dir3.Unit * distance
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

-- Classic mode: scroll every live step `speed * dt` studs along the spawn
-- direction right now (Unity's steps move under SpawnManager.PullVector every
-- frame; here it never stops). The distance accumulates until
-- Config.CLASSIC_CHUNK_TIME has passed, then is returned as one chunk (studs,
-- seconds) for GameServer to spend on spawner time and replicate; nil otherwise.
function Lane.drift(self: Lane, dt: number, speed: number): (number?, number?)
	local dir3 = Vector3.new(self.spawnDirection.X, self.spawnDirection.Y, 0)
	if speed <= 0 or dt <= 0 or dir3.Magnitude < 1e-4 then
		return nil, nil
	end
	local distance = speed * dt
	local inc = dir3.Unit * distance
	for step in self.active do
		step.CFrame += inc
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
	local dir3 = Vector3.new(self.spawnDirection.X, self.spawnDirection.Y, 0)
	if not self.obstruction or self:drifts() or distance <= 0 or dir3.Magnitude < 1e-4 then
		return 0
	end
	local travel = dir3.Unit
	type Box = { rest: Vector3, hit: Vector2, offset: Vector2 }
	local boxes: { Box } = {}
	for step in self.active do
		table.insert(boxes, {
			rest = self:restPosition(step),
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
-- overlap the camera band. `spawnFn` gets the position to create the part at
-- NOW; GameServer owns the pooled Instances.
-- ---------------------------------------------------------------------------
local SPAWN_SLICE = 1 / 30 -- spawner-seconds per slice of a pull's window

function Lane.spawnForPull(
	self: Lane,
	distance: number,
	spawnFn: (state: SpawnerState, kindName: string, worldPos: Vector3) -> (),
	windowOverride: number?
)
	local dir3 = Vector3.new(self.spawnDirection.X, self.spawnDirection.Y, 0)
	if distance <= 0 or dir3.Magnitude < 1e-4 then
		return
	end
	local travel = dir3.Unit
	local pending = self:sharedPending()
	-- a grab earns Unity's fixed window; Classic drift passes its own per-stud share
	local window = windowOverride or Config.PULL_SPAWN_WINDOW
	if window <= 0 then
		return
	end
	local left = window
	while left > 1e-6 do
		local slice = math.min(SPAWN_SLICE, left)
		left -= slice
		for _, state in self.activeSpawners do
			local def = state.def
			if def.spawnAllOnAwake then
				continue
			end
			if #def.movements > 0 then
				updateMovement(state, slice)
			end
			state.timer -= slice
			while state.timer <= 0 do
				if def.maxSpawnCount < 0 or state.spawnCount < def.maxSpawnCount then
					local kindName = self:pickKind(state)
					if kindName then
						-- (left - timer) spawner-seconds of the window remain after
						-- this spawn (timer <= 0 is the overshoot into this slice)
						local carry = (left - state.timer) / window * distance
						local rest = self:spawnPosition(state) + travel * carry
						local kind = StepKinds[kindName]
						local size = if kind then kind.size else DEFAULT_SIZE
						rest -= travel * self:entryShift(rest - pending, size, travel)
						local pos = self:clearSpot(rest, kindName, travel)
						if pos then
							spawnFn(state, kindName, pos - pending)
							state.spawnCount += 1
						end
					end
				end
				-- += (not =) keeps the overshoot, so a big window yields every spawn it covers
				state.timer += math.max(
					0.05,
					def.spawningSpeedMin + math.random() * math.max(0, def.spawningSpeedMax - def.spawningSpeedMin)
				)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Per-tick upkeep (Spawning/Spawner.cs Move() + StepAndScenerySpawner
-- spawnAllOnAwake). Continuous spawning only happens on pulls (spawnForPull);
-- here the Movements cycles advance on the Heartbeat clock (Unity's Move() is its
-- own coroutine, Spawner.cs Activate() L86-97) and a spawnAllOnAwake spawner
-- (the Tutorial ladder) fires its one batch. `spawnFn` gets the position to
-- create the part at now (GameServer slides that batch in, see slideIn there).
-- ---------------------------------------------------------------------------
function Lane.tickSpawners(
	self: Lane,
	dt: number,
	spawnFn: (state: SpawnerState, kindName: string, worldPos: Vector3) -> ()
)
	for _, state in self.activeSpawners do
		local def = state.def
		if not def.spawnAllOnAwake and #def.movements > 0 then
			updateMovement(state, dt)
		end
		if def.spawnAllOnAwake and not state.awoken then
			state.awoken = true
			local pending = self:sharedPending()
			for i, kindName in def.pool do
				if def.maxSpawnCount < 0 or state.spawnCount < def.maxSpawnCount then
					spawnFn(state, kindName, self:spawnPosition(state, i) - pending)
					state.spawnCount += 1
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
-- batch in from off-screen). No-op when the lane already has steps, e.g. a
-- respawn after a death.
function Lane.prefill(self: Lane, spawnFn: (state: SpawnerState, kindName: string, worldPos: Vector3) -> ())
	local count = 0
	for _ in self.active do
		count += 1
	end
	local dir3 = Vector3.new(self.spawnDirection.X, self.spawnDirection.Y, 0)
	if count >= Config.PREFILL_MIN_STEPS or dir3.Magnitude < 1e-4 then
		return
	end

	local pending = self:sharedPending()
	local rows = Config.PREFILL_DEPTH // Config.PREFILL_ROW_STEP
	local rowTime = Config.PULL_SPAWN_WINDOW -- each row is one grab's window
	for row = rows, 1, -1 do
		local travelled = dir3.Unit * ((row - 1) * Config.PREFILL_ROW_STEP)
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
					-- direction instead of stacking (same rule as spawnForPull)
					local carried = travelled + dir3.Unit * (-state.timer / rowTime * Config.PREFILL_ROW_STEP)
					local pos = self:clearSpot(self:spawnPosition(state) + carried, kindName, dir3.Unit)
					if pos then
						spawnFn(state, kindName, pos - pending)
						state.spawnCount += 1
					end
					local interval = def.spawningSpeedMin
						+ math.random() * math.max(0, def.spawningSpeedMax - def.spawningSpeedMin)
					interval = math.max(interval, 0.05) -- never loop forever on a 0-interval def
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
-- the new direction's own weighted picks (Lane.pickKind), minus further arrows.
-- Each spot goes through Lane.clearSpot (spacing, lane bounds, the PlayerList
-- keep-out) and must be within Config.MAX_GRAB_DISTANCE of the origin
-- (GameServer's GrabStep reach check). A rung whose spot is already taken is
-- skipped (the live steps there are that rung); the chain ends at the first rung
-- beyond reach. `spawnFn` gets the position to create the
-- part at now (rest less the lane's running pulls, like prefill); GameServer
-- then slides the batch down in from above the view.
function Lane.scaffold(self: Lane, anchor: Vector3, spawnFn: (kindName: string, worldPos: Vector3) -> ())
	local dir3 = Vector3.new(self.spawnDirection.X, self.spawnDirection.Y, 0)
	if dir3.Magnitude < 1e-4 then
		return
	end
	local travel = dir3.Unit
	local heading = -travel
	local rise = if math.abs(travel.Y) < 1e-4 then Vector3.new(0, Config.SCAFFOLD_RISE, 0) else Vector3.zero

	local spawners: { SpawnerState } = {}
	for _, state in self.activeSpawners do
		if not state.def.spawnAllOnAwake and #state.def.pool > 0 then
			table.insert(spawners, state)
		end
	end
	if #spawners == 0 then
		return
	end

	local function isArrow(kindName: string): boolean
		local kind = StepKinds[kindName]
		return kind ~= nil and string.sub(kind.behavior, 1, #"ChangeDirection") == "ChangeDirection"
	end
	local function pickPlain(state: SpawnerState): string?
		for _ = 1, 8 do
			local kindName = self:pickKind(state)
			if kindName and not isArrow(kindName) then
				return kindName
			end
		end
		for _, kindName in state.def.pool do
			if not isArrow(kindName) then
				return kindName
			end
		end
		return nil
	end

	local pending = self:sharedPending()
	local reach = Config.MAX_GRAB_DISTANCE
	for i = 1, Config.SCAFFOLD_COUNT do
		local kindName = pickPlain(spawners[math.random(1, #spawners)])
		if not kindName then
			return
		end
		local want = anchor + heading * (Config.SCAFFOLD_SPACING * i) + rise * i
		local wantRel = want - self.origin
		if Vector2.new(wantRel.X, wantRel.Y).Magnitude > reach then
			return -- every further rung is further out still
		end
		-- a crowded spot moves a little further along the heading (clearSpot shifts
		-- against its travel argument, scaled here so its NUDGE_MAX search spans
		-- only SCAFFOLD_NUDGE studs); nil means it is already taken by live steps
		-- (which then serve as this rung) or would leave the lane, so skip the rung
		local pos = self:clearSpot(want, kindName, travel * (Config.SCAFFOLD_NUDGE / NUDGE_MAX))
		if pos then
			local rel = pos - self.origin
			if Vector2.new(rel.X, rel.Y).Magnitude <= reach then
				spawnFn(kindName, pos - pending)
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
function Lane.isOutOfBounds(self: Lane, step: BasePart): boolean
	return outOfBounds(self, step.Position, step.Size) and outOfBounds(self, self:restPosition(step), step.Size)
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
-- Pot -> Kitchen -> Country at LEVEL_THRESHOLDS. Called by GameServer once per
-- successful grab (after it has already bumped the session score), with the
-- grabbed step's kind name so it can also track tutorialGraceActive
-- (b-20260922-101541-w1i2).
-- ---------------------------------------------------------------------------
function Lane.onStepClimbed(self: Lane, kindName: string?)
	self.runSteps += 1
	-- covers a height-stage change WITHIN the current level (e.g. Pot's 15/35
	-- runSteps stage bounds); a level transition below also calls setLevel,
	-- which sets this same attribute again for the new level.
	self:updateStageAttribute()

	if self.tutorialGraceActive and not (kindName and TUTORIAL_TREE_KINDS[kindName]) then
		self.tutorialGraceActive = false
	end

	if self.levelIndex == Levels.TUTORIAL then
		self.tutorialStepsClimbed += 1
		if self.tutorialStepsClimbed >= 3 then
			local profile = Profiles.get(self.player)
			if profile then
				profile.tutorialDone = true
				Profiles.save(self.player)
			end
			self:levelUp(Levels.POT)
		end
	elseif self.levelIndex == Levels.POT and self.runSteps >= Config.LEVEL_THRESHOLDS.Kitchen then
		self:levelUp(Levels.KITCHEN)
	elseif self.levelIndex == Levels.KITCHEN and self.runSteps >= Config.LEVEL_THRESHOLDS.Country then
		self:levelUp(Levels.COUNTRY)
	end
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
-- place it's triggered, so it can be repointed (e.g. to grabbing a pot-rim
-- step, b-20260923-154343-9twj) by moving this single call. Holds Classic
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

-- A new run: back to Pot, or Tutorial if this profile never finished it
-- (doc 13 item 5). Soft -- doesn't touch `self.active` either.
function Lane.resetRun(self: Lane, tutorialDone: boolean)
	self.runSteps = 0
	self.tutorialStepsClimbed = 0
	self.tutorialGraceActive = not tutorialDone
	table.clear(self.motions) -- the lane was just emptied (GameServer.clearLaneSteps)
	self.driftDistance = 0
	self.driftTime = 0
	self.driftElapsed = 0
	self.driftBase = 0
	self.driftHold = 0
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
	folder:SetAttribute("Mode", Config.RUN_MODES.Normal)
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
		tutorialStepsClimbed = 0,
		tutorialGraceActive = not tutorialDone,
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
