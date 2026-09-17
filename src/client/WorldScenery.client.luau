--!strict
-- StarterPlayerScripts/Client/WorldScenery (LocalScript)
-- Phase 4 world dressing, item 1: the scenery layer (Spawning/ScenerySpawner.cs
-- + Entities/Scenery.cs/MovingScenery.cs, doc 11 §2a scenerySpawners + doc 12
-- §3), rendered per LANE (workspace/PlayField/Lanes/<userId>, doc 13) so every
-- lane on screen gets its own copy -- cheap, since it's flat pooled parts with
-- no physics. Consumes Shared/Levels.luau's scenerySpawners data (already
-- wired, doc 13 item 2) plus Shared/SceneryKinds.luau (this phase's additive
-- cadence/visual data, since Levels.SceneryDef intentionally stayed minimal).
--
-- Scrolls with each lane's own PullDelta (replicated by GameServer's pullLane,
-- read here off the lane folder's attributes) times the kind's own
-- speedModifier -- a parallax multiplier, same tween shape GameServer already
-- uses for steps. `moving` kinds (Bubble/Chef, MovingScenery.cs) ignore pulls
-- and drift by their own constant direction*speed instead. Flat anchored,
-- non-collide, CanQuery=false throughout -- must never eat taps or block
-- raycasts to steps/bugs (doc 12 TouchIndicator/GameClient rely on that).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Levels = require(ReplicatedStorage.Shared.Levels)
local SceneryKinds = require(ReplicatedStorage.Shared.SceneryKinds)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local Pool = require(script.Parent.world.Pool)

local playField = workspace:WaitForChild("PlayField")
local lanesFolder = playField:WaitForChild("Lanes")

local levelByName: { [string]: Levels.Level } = {}
for _, level in Levels.list do
	levelByName[level.name] = level
end

-- ---------------------------------------------------------------------------
-- Pooled scenery parts (one pool per kind name, shared across every lane --
-- a recycled Cloud3 doesn't care which lane it came from)
-- ---------------------------------------------------------------------------
local function createSceneryPart(kindName: string): BasePart
	local kind = SceneryKinds.defs[kindName]
	local part = Instance.new("Part")
	part.Name = "Scenery_" .. kindName
	part.Size = if kind then kind.size else Vector3.new(2, 2, 0.2)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = if kind and #kind.colors > 0 then kind.colors[1] else Color3.fromRGB(200, 200, 200)

	if kind and kind.sprite then
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Front
		decal:SetAttribute("Sprite", kind.sprite)
		decal.Parent = part
		SpriteSkin.apply(part)
	end

	return part
end

local pools: { [string]: Pool.Pool<BasePart> } = {}
local function poolFor(kindName: string): Pool.Pool<BasePart>
	local p = pools[kindName]
	if not p then
		p = Pool.new(function()
			return createSceneryPart(kindName)
		end, function(part: BasePart)
			part.Parent = nil
		end)
		pools[kindName] = p
	end
	return p
end

-- ---------------------------------------------------------------------------
-- Spawn position (same "opposite of travel direction" edge logic Lane.luau
-- uses for steps, doc 13 item 4 -- exact Unity Movements offsets aren't
-- recoverable, so this generates positions procedurally along the same
-- edge/shape instead). Placed slightly behind the step plane (z=-1) so scenery
-- reads as background, never overlapping the grabbable steps.
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

local function spawnPosition(origin: Vector3, direction: Vector2): Vector3
	local ex, ey = -signOf(direction.X), -signOf(direction.Y)
	local x: number, y: number
	if ex ~= 0 and ey ~= 0 then
		x = ex * (Config.LANE_HALF_WIDTH - math.random() * (Config.LANE_HALF_WIDTH * 0.4))
		y = if ey > 0 then Config.SPAWN_Y else Config.DESPAWN_Y
	elseif ex ~= 0 then
		x = ex * (Config.LANE_HALF_WIDTH + 3)
		y = (math.random() * 2 - 1) * (Config.SPAWN_Y * 0.6)
	else
		x = (math.random() * 2 - 1) * Config.SPAWN_X_RANGE
		y = if ey >= 0 then Config.SPAWN_Y else Config.DESPAWN_Y
	end
	return origin + Vector3.new(x, y, -1)
end

local function isOutOfBounds(origin: Vector3, part: BasePart): boolean
	local margin = WorldConfig.SCENERY_BOUNDS_MARGIN
	local relX = part.Position.X - origin.X
	if relX < -(Config.LANE_HALF_WIDTH + margin) or relX > (Config.LANE_HALF_WIDTH + margin) then
		return true
	end
	local y = part.Position.Y
	return y < (Config.DESPAWN_Y - margin) or y > (Config.SPAWN_Y + margin)
end

-- ---------------------------------------------------------------------------
-- Per-lane state
-- ---------------------------------------------------------------------------
type SpawnerRuntime = {
	direction: Vector2,
	pool: { string },
	cadence: SceneryKinds.SpawnerCadence,
	timer: number,
	spawnCount: number,
	awoken: boolean,
}

type LaneScenery = {
	folder: Folder,
	origin: Vector3,
	levelName: string,
	spawners: { SpawnerRuntime },
	active: { [BasePart]: string }, -- part -> kind name
	oneOffs: { [string]: BasePart? }, -- levelObjects (Chef/US), one per lane
}

local DEFAULT_CADENCE: SceneryKinds.SpawnerCadence =
	{ maxSpawnCount = 10, spawningSpeedMin = 2, spawningSpeedMax = 4, spawnAllOnAwake = false }

local function buildSpawners(levelName: string): { SpawnerRuntime }
	local level = levelByName[levelName]
	if not level then
		return {}
	end
	local list: { SpawnerRuntime } = {}
	for _, def in level.scenerySpawners do
		if def.kind == "Scenery" and not SceneryKinds.isDuplicateSpawner(def.name) then
			table.insert(list, {
				direction = def.direction,
				pool = def.pool,
				cadence = SceneryKinds.cadence[def.name] or DEFAULT_CADENCE,
				timer = 0,
				spawnCount = 0,
				awoken = false,
			})
		end
	end
	return list
end

-- levelObjects (doc 11 §3): one-off decorations placed for the duration of a
-- level, not repeat-spawned. Stars/SpeckManager are covered elsewhere (Stars
-- via its own scenerySpawner pseudo-entry above; specks by
-- WorldTutorialSpecks.client.luau) -- only Chef/US need a placement here.
local function updateLevelObjects(lane: LaneScenery)
	local wantChef = lane.levelName == "Kitchen"
	if wantChef and not lane.oneOffs.Chef then
		local part = createSceneryPart("Chef")
		part.CFrame = CFrame.new(lane.origin + Vector3.new(0, Config.DESPAWN_Y * 0.5, -1))
		part.Parent = workspace
		lane.oneOffs.Chef = part
	elseif not wantChef and lane.oneOffs.Chef then
		lane.oneOffs.Chef:Destroy()
		lane.oneOffs.Chef = nil
	end

	local wantUS = lane.levelName == "Country"
	if wantUS and not lane.oneOffs.US then
		local part = createSceneryPart("US")
		part.CFrame = CFrame.new(lane.origin + Vector3.new(Config.LANE_HALF_WIDTH * 0.5, 0, -1))
		part.Parent = workspace
		lane.oneOffs.US = part
	elseif not wantUS and lane.oneOffs.US then
		lane.oneOffs.US:Destroy()
		lane.oneOffs.US = nil
	end
end

local lanes: { [Folder]: LaneScenery } = {}

local function spawnScenery(lane: LaneScenery, kindName: string, position: Vector3)
	local kind = SceneryKinds.defs[kindName]
	local part = poolFor(kindName).acquire()
	if kind and #kind.colors > 0 then
		local color = kind.colors[math.random(1, #kind.colors)]
		part.Color = color
		local decal = part:FindFirstChildOfClass("Decal")
		if decal then
			decal.Color3 = color
		end
	end
	part.CFrame = CFrame.new(position)
	part.Parent = workspace
	lane.active[part] = kindName
end

local function recycleScenery(lane: LaneScenery, part: BasePart)
	local kindName = lane.active[part]
	lane.active[part] = nil
	if kindName then
		poolFor(kindName).release(part)
	end
end

local function onPullCount(lane: LaneScenery)
	local delta = lane.folder:GetAttribute("PullDelta")
	local pullTime = lane.folder:GetAttribute("PullTime")
	if typeof(delta) ~= "Vector3" or typeof(pullTime) ~= "number" then
		return
	end
	local info = TweenInfo.new(pullTime, Enum.EasingStyle.Sine)
	for part, kindName in lane.active do
		local kind = SceneryKinds.defs[kindName]
		if not (kind and kind.moving) then
			local speedMod = if kind then kind.speedModifier else 1
			TweenService:Create(part, info, { Position = part.Position + delta * speedMod }):Play()
		end
	end
end

local function trackLane(folder: Folder)
	if lanes[folder] then
		return
	end
	local originAttr = folder:GetAttribute("Origin")
	local origin: Vector3 = if typeof(originAttr) == "Vector3" then originAttr else Vector3.zero
	-- an idle lane (GameServer's RunState attribute: Menu/Dead) is dressed as the Menu
	-- level (LevelManager level 0: grass + clouds); a running one as its own Level
	local function effectiveLevel(): string
		if folder:GetAttribute("RunState") == "Menu" then
			return "Menu"
		end
		local levelAttr = folder:GetAttribute("Level")
		return if typeof(levelAttr) == "string" then levelAttr else "Pot"
	end
	local levelName = effectiveLevel()

	local lane: LaneScenery = {
		folder = folder,
		origin = origin,
		levelName = levelName,
		spawners = buildSpawners(levelName),
		active = {},
		oneOffs = {},
	}
	lanes[folder] = lane
	updateLevelObjects(lane)

	local function refreshLevel()
		local newName = effectiveLevel()
		if newName == lane.levelName then
			return
		end
		lane.levelName = newName
		lane.spawners = buildSpawners(newName) -- soft transition: leaves `active` untouched
		updateLevelObjects(lane)
	end
	folder:GetAttributeChangedSignal("Level"):Connect(refreshLevel)
	folder:GetAttributeChangedSignal("RunState"):Connect(refreshLevel)
	folder:GetAttributeChangedSignal("Origin"):Connect(function()
		local newOrigin = folder:GetAttribute("Origin")
		if typeof(newOrigin) == "Vector3" then
			lane.origin = newOrigin
		end
	end)
	folder:GetAttributeChangedSignal("PullCount"):Connect(function()
		onPullCount(lane)
	end)
end

local function untrackLane(folder: Folder)
	local lane = lanes[folder]
	if not lane then
		return
	end
	lanes[folder] = nil
	for part, kindName in lane.active do
		poolFor(kindName).release(part)
	end
	for _, part in lane.oneOffs do
		if part then
			part:Destroy()
		end
	end
end

for _, child in lanesFolder:GetChildren() do
	if child:IsA("Folder") then
		trackLane(child)
	end
end
lanesFolder.ChildAdded:Connect(function(child)
	if child:IsA("Folder") then
		trackLane(child)
	end
end)
lanesFolder.ChildRemoved:Connect(function(child)
	if child:IsA("Folder") then
		untrackLane(child)
	end
end)

-- ---------------------------------------------------------------------------
-- Per-frame: spawn cadence, own-drift ("moving"/autoMove), bounds recycling.
-- ---------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt: number)
	for _, lane in lanes do
		for _, spawner in lane.spawners do
			if spawner.cadence.spawnAllOnAwake then
				if not spawner.awoken then
					spawner.awoken = true
					local count = math.max(1, math.min(spawner.cadence.maxSpawnCount, #spawner.pool * 4))
					for i = 1, count do
						local kindName = spawner.pool[((i - 1) % #spawner.pool) + 1]
						spawnScenery(lane, kindName, spawnPosition(lane.origin, spawner.direction))
						spawner.spawnCount += 1
					end
				end
			else
				spawner.timer -= dt
				if spawner.timer <= 0 then
					local cap = if spawner.cadence.maxSpawnCount < 0
						then WorldConfig.SCENERY_POOL_CAP
						else spawner.cadence.maxSpawnCount
					if spawner.spawnCount < cap and #spawner.pool > 0 then
						local kindName = spawner.pool[math.random(1, #spawner.pool)]
						spawnScenery(lane, kindName, spawnPosition(lane.origin, spawner.direction))
						spawner.spawnCount += 1
					end
					local span = math.max(0, spawner.cadence.spawningSpeedMax - spawner.cadence.spawningSpeedMin)
					spawner.timer = math.max(0.05, spawner.cadence.spawningSpeedMin + math.random() * span)
				end
			end
		end

		for part, kindName in lane.active do
			local kind = SceneryKinds.defs[kindName]
			if kind then
				if kind.moving then
					if kind.moveDirection.Magnitude > 1e-4 then
						local dir = kind.moveDirection.Unit
						part.Position += Vector3.new(dir.X, dir.Y, 0) * kind.moveSpeed * dt
					end
				elseif kind.autoMove.Magnitude > 1e-4 then
					part.Position += Vector3.new(kind.autoMove.X, kind.autoMove.Y, 0) * dt
				end
			end
			if isOutOfBounds(lane.origin, part) then
				recycleScenery(lane, part)
			end
		end
	end
end)
