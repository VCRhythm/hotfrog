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

	local states: { SpawnerState } = {}
	for _, def in level.stepSpawners do
		table.insert(states, { def = def, spawnCount = 0, timer = 0, awoken = false })
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
-- Spawn position (doc 13 item 4): new steps enter from the edge the lane's
-- steps travel AWAY from -- i.e. the side opposite spawnDirection (verified
-- against doc 11 §2a's Level3 LeftStepSpawner Movements, which sit past the
-- RIGHT edge for a spawner whose direction is leftward). Diagonals enter from
-- the matching top corner. Exact per-spawner Movements lists aren't in doc 11
-- (only one example was kept, "omitted from the table for width") -- positions
-- here are generated procedurally along the same edge/shape instead of copying
-- literal Unity offsets.
-- ---------------------------------------------------------------------------
function Lane.spawnPosition(self: Lane, state: SpawnerState, indexInBatch: number?): Vector3
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
		-- spawnAllOnAwake (Tutorial's 3 trees, StepAndScenerySpawner): a ladder
		-- climbing away from the frog's start, alternating sides, so the first
		-- one is an easy reach and each next one needs the previous pull
		x = (if indexInBatch % 2 == 1 then 1 else -1) * Config.TUTORIAL_STEP_X
		y = Config.TUTORIAL_FIRST_STEP_Y + (indexInBatch - 1) * Config.TUTORIAL_STEP_GAP
	end

	return self.origin + Vector3.new(x, y, 0)
end

-- A pull of `distance` studs earns the spawners that much running time
-- (Config.PULL_SPAWN_SPEED = how fast Unity's field moves during a pull).
function Lane.addPull(self: Lane, distance: number)
	if distance > 0 then
		self.spawnBudget += distance / Config.PULL_SPAWN_SPEED
	end
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
	-- continuous spawners only advance on time earned by pulling (see spawnBudget)
	local spend = math.min(dt, self.spawnBudget)
	self.spawnBudget -= spend

	for _, state in self.activeSpawners do
		local def = state.def
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
			if state.timer <= 0 then
				if def.maxSpawnCount < 0 or state.spawnCount < def.maxSpawnCount then
					local kindName = self:pickKind(state)
					if kindName then
						spawnFn(state, kindName, self:spawnPosition(state))
						state.spawnCount += 1
					end
				end
				state.timer = def.spawningSpeedMin
					+ math.random() * math.max(0, def.spawningSpeedMax - def.spawningSpeedMin)
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
		local travelled = dir3.Unit * (row * Config.PULL_DISTANCE)
		for _, state in self.activeSpawners do
			local def = state.def
			if not def.spawnAllOnAwake then
				state.timer -= rowTime
				while state.timer <= 0 and (def.maxSpawnCount < 0 or state.spawnCount < def.maxSpawnCount) do
					local kindName = self:pickKind(state)
					if not kindName then
						break
					end
					spawnFn(state, kindName, self:spawnPosition(state) + travelled)
					state.spawnCount += 1
					local interval = def.spawningSpeedMin
						+ math.random() * math.max(0, def.spawningSpeedMax - def.spawningSpeedMin)
					state.timer += math.max(interval, 0.05) -- never loop forever on a 0-interval def
				end
			end
		end
	end
end

-- Recycle bound (Borders.prefab.json Left/Right/Top/Bottom catch, doc 11 §3):
-- ANY side, not just the bottom lava line. Only X is lane-relative -- Y bounds
-- are shared world coordinates (lanes only offset along X, doc 13 item 1).
function Lane.isOutOfBounds(self: Lane, step: BasePart): boolean
	local margin = 6
	local relX = step.Position.X - self.origin.X
	if relX < -(Config.LANE_HALF_WIDTH + margin) or relX > (Config.LANE_HALF_WIDTH + margin) then
		return true
	end
	local y = step.Position.Y
	return y < Config.DESPAWN_Y or y > (Config.SPAWN_Y + margin)
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
