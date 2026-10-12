--!strict
-- StarterPlayerScripts/Client/WorldScenery (LocalScript)
-- Phase 4 world dressing, item 1: the scenery layer (Spawning/ScenerySpawner.cs
-- + Entities/Scenery.cs/MovingScenery.cs, doc 11 §2a scenerySpawners + doc 12
-- §3), rendered per LANE (workspace/PlayField/Lanes/<userId>, doc 13) so every
-- lane on screen gets its own copy -- cheap, since it's flat pooled parts with
-- no physics. Consumes Shared/Levels.luau's scenerySpawners data (already
-- wired, doc 13 item 2) plus Shared/SceneryKinds.luau (this phase's additive
-- cadence/visual data, since Levels.SceneryDef intentionally stayed minimal) and
-- its client-only `extraSpawners` (parallax cloud layers, Country leaves, Pot
-- back-flames), merged with the level's own spawners.
--
-- ONE WRITER PER PART. Every active part's position is owned by the per-frame
-- loop below (RunService.PreRender): it integrates
--     anchor += lane pull (world/PullScroller, eased, x kind.speedModifier)
--             + autoMove drift (+ Country wind gust, world/Wind)
-- and then writes CFrame = anchor + the kind's `motion` offset (sway/bob/roll/
-- spin) and Size = base x pulse/reaction scale. There are no per-pull Tweens any
-- more: those were never cancelled, so a part recycled by the bounds check and
-- re-acquired from the (LIFO) pool could still be dragged by its old pull tween
-- (a respawned part teleporting), overlapping pulls stacked fighting tweens, and
-- the autoMove `Position +=` fought them (Cloud3 jitter).
--
-- `moving` kinds (Bubble/Chef, MovingScenery.cs) ignore pulls and drift by their
-- own constant direction*speed instead. Parts are anchored, non-colliding and
-- CanQuery=false EXCEPT kinds with a `reaction` (tappable: Bubble pop, cloud
-- wobble, flame flare) -- see "Tap reactions" at the bottom for why CanQuery=true
-- there is still safe for step/bug taps.
--
-- Cosmetic only: never touches a server-owned part (steps, bugs, frogs); reads
-- replicated lane attributes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Levels = require(ReplicatedStorage.Shared.Levels)
local SceneryKinds = require(ReplicatedStorage.Shared.SceneryKinds)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local SoundFX = require(ReplicatedStorage.Shared.SoundFX)
local Bursts = require(script.Parent.world.Bursts)
local Lanes = require(script.Parent.world.Lanes)
local Pool = require(script.Parent.world.Pool)
local PullScroller = require(script.Parent.world.PullScroller)
local Wind = require(script.Parent.world.Wind)

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
	-- CanQuery stays false for every kind EXCEPT those with a `reaction` -- those
	-- need to be raycast-hittable by this file's own tap input below. Safe: the
	-- "must never eat taps meant for steps/bugs" guarantee comes from GameClient's
	-- (and WorldTouchIndicator's) raycasts being Include-filtered to the Steps/Bugs
	-- folders only (scenery parts live directly under workspace, never inside either),
	-- so CanQuery here is invisible to them regardless of its own value.
	part.CanQuery = kind ~= nil and kind.reaction ~= nil
	part.Material = Enum.Material.SmoothPlastic
	part.Color = if kind and #kind.colors > 0 then kind.colors[1] else Color3.fromRGB(200, 200, 200)

	if kind and kind.sprite then
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
		decal:SetAttribute("Sprite", kind.sprite)
		decal.Parent = part
		SpriteSkin.apply(part)
		-- SceneryKinds.size is the sprite's whole (usually heavily padded) Unity
		-- canvas, because a Decal stretches the full image across the face -- so
		-- the host part must not be a visible box behind it. Only hide it once the
		-- sprite actually resolved (SkinAssets id 0 leaves Texture empty), keeping
		-- the flat placeholder colour as the fallback for un-uploaded art.
		part.Transparency = if decal.Texture ~= "" then 1 else 0
	end

	return part
end

-- ---------------------------------------------------------------------------
-- "US" levelObject (Country, doc 11 §3 / doc 17 known gap "US map for
-- Country"): UnitedStates.cs's two-color map cutout -- two SpriteRenderers
-- (USBlueStates/USRedStates), continuously swapping between the script's own
-- `colors` array (SceneryKinds.defs.US.colors, extracted doc 14) every 5s
-- (UnitedStates.cs ChangeColors), staggered one index apart. SceneryKinds
-- carries the colors/size but not this compound two-sprite/animated-tint
-- shape, so it's built directly here -- same as Chef.
-- ---------------------------------------------------------------------------
local function makeUSColorTweens(part: BasePart, decal: Decal, color: Color3): (Tween, Tween)
	return TweenService:Create(part, TweenInfo.new(WorldConfig.US_SWAP_PERIOD), { Color = color }),
		TweenService:Create(decal, TweenInfo.new(WorldConfig.US_SWAP_PERIOD), { Color3 = color })
end

-- Loops forever: tween to colors[startIndex], and the instant that finishes,
-- start tweening to the next one -- mirrors UnitedStates.cs's coroutine (the
-- next DOColor call happens exactly when WaitForSeconds(5f) elapses, the same
-- duration as the tween itself, so there's no pause between swaps).
local function loopUSColor(part: BasePart, decal: Decal, colors: { Color3 }, startIndex: number)
	local index = startIndex
	local function step()
		local color = colors[((index - 1) % #colors) + 1]
		index += 1
		local partTween, decalTween = makeUSColorTweens(part, decal, color)
		-- Only chain on a genuine completion of a part that is still in the world: a
		-- Destroy()ed layer (level left) cancels its tween, and without this check the
		-- loop would re-arm itself on a dead part forever.
		decalTween.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed and part.Parent then
				step()
			end
		end)
		partTween:Play()
		decalTween:Play()
	end
	step()
end

local function makeUSLayer(spriteStem: string): (BasePart, Decal)
	local kind = SceneryKinds.defs.US
	local part = Instance.new("Part")
	part.Name = "Scenery_" .. spriteStem
	part.Size = if kind then kind.size else Vector3.new(9, 5.5, 0.2)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.SmoothPlastic
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
	decal:SetAttribute("Sprite", spriteStem)
	decal.Parent = part
	SpriteSkin.apply(part)
	-- Same rule as createSceneryPart: the part is the sprite's whole canvas, so it
	-- must not show as a box behind the cutout. The tinting below still works --
	-- loopUSColor tweens the Decal's Color3, and the part's Color only matters in
	-- the un-uploaded fallback where the box is left visible.
	part.Transparency = if decal.Texture ~= "" then 1 else 0
	return part, decal
end

-- Two thin stacked parts (tiny Z offset, same trick as WorldBackdrop's
-- background tiles) instead of one part with two overlapping Decals on the
-- same face -- Roblox doesn't guarantee draw order for that. Both sprites are
-- cutout shapes covering different pixel regions of the same map, so the
-- z-order between them barely matters.
local function createUSPair(position: Vector3): { BasePart }
	local kind = SceneryKinds.defs.US
	local colors = if kind and #kind.colors > 0
		then kind.colors
		else { Color3.fromRGB(0, 0, 255), Color3.fromRGB(255, 0, 0) }

	local bluePart, blueDecal = makeUSLayer("USBlueStates")
	bluePart.CFrame = CFrame.new(position + Vector3.new(0, 0, -0.05))
	bluePart.Parent = workspace

	local redPart, redDecal = makeUSLayer("USRedStates")
	redPart.CFrame = CFrame.new(position)
	redPart.Parent = workspace

	loopUSColor(bluePart, blueDecal, colors, 1) -- UnitedStates.cs colorIndices[0] = 0 -> colors[0] = blue
	loopUSColor(redPart, redDecal, colors, 2) -- colorIndices[1] = numOfBlinks * 1 -> colors[1] = red

	return { bluePart, redPart }
end

local pools: { [string]: Pool.Pool<BasePart> } = {}
local function poolFor(kindName: string): Pool.Pool<BasePart>
	local p = pools[kindName]
	if not p then
		p = Pool.new(function()
			return createSceneryPart(kindName)
		end, function(part: BasePart)
			part.Parent = nil
		end, {
			cap = WorldConfig.SCENERY_PARK_CAP,
			dispose = function(part: BasePart)
				part:Destroy()
			end,
		})
		pools[kindName] = p
	end
	return p
end

-- ---------------------------------------------------------------------------
-- Spawn position (same "opposite of travel direction" edge logic Lane.luau
-- uses for steps, doc 13 item 4 -- exact Unity Movements offsets aren't
-- recoverable, so this generates positions procedurally along the same
-- edge/shape instead). Placed slightly behind the step plane (SCENERY_Z) so
-- scenery reads as background, never overlapping the grabbable steps.
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
		x = ex
			* (
				Config.LANE_HALF_WIDTH
				- math.random() * (Config.LANE_HALF_WIDTH * WorldConfig.SPAWN_EDGE_INSET_FRACTION)
			)
		y = if ey > 0 then Config.SPAWN_Y else Config.DESPAWN_Y
	elseif ex ~= 0 then
		x = ex * (Config.LANE_HALF_WIDTH + WorldConfig.SPAWN_SIDE_OUTSET)
		y = (math.random() * 2 - 1) * (Config.SPAWN_Y * WorldConfig.SPAWN_SIDE_Y_FRACTION)
	else
		x = (math.random() * 2 - 1) * Config.SPAWN_X_RANGE
		y = if ey >= 0 then Config.SPAWN_Y else Config.DESPAWN_Y
	end
	return origin + Vector3.new(x, y, 0)
end

-- A random spot over the visible field (initial scatter of the extra spawners).
local function scatterPosition(origin: Vector3): Vector3
	local x = (math.random() * 2 - 1) * Config.SPAWN_X_RANGE
	local lo = Config.DESPAWN_Y * (1 - WorldConfig.SCATTER_Y_MIN_FRACTION)
	local hi = Config.SPAWN_Y * WorldConfig.SCATTER_Y_MAX_FRACTION
	return origin + Vector3.new(x, lo + math.random() * (hi - lo), 0)
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
	-- Height-stage density (b-20260923-154344-dr8a) this spawner's current live
	-- population was last built with, spawnAllOnAwake spawners only (Flame) --
	-- nil until its one-shot batch has fired once. Lets a later Stage-attribute
	-- change (Pot's bubbles/steam thinning as the lane climbs) replace an
	-- already-fired batch instead of it being stuck at whatever density was live
	-- on the lane's first tick.
	lastDensity: number?,
	-- Client-only extra spawners (SceneryKinds.extraSpawners): maxSpawnCount caps the
	-- CONCURRENT live parts of the pool instead of the total ever spawned (Unity's
	-- Spawner.spawnCount never goes down; a sky that stopped producing clouds after
	-- the first eight would defeat the point), and `pendingScatter` parts are dropped
	-- over the field on the first tick so it isn't empty.
	concurrent: boolean,
	pendingScatter: number,
}

-- Everything the per-frame loop needs about one live part. One table per live part,
-- reused across the part's life; no per-frame allocation.
type PartState = {
	part: BasePart,
	kindName: string,
	kind: SceneryKinds.SceneryKind,
	lane: LaneScenery,
	anchor: Vector3, -- the integrated pull/drift position (what bounds are tested against)
	age: number, -- seconds alive: drives the motion phases
	phase: number, -- random per-part phase offset, radians
	seed: number, -- random per-part noise offset (flicker)
	spinAngle: number, -- accumulated constant spin, degrees
	scaled: boolean, -- Size currently differs from kind.size
	reaction: SceneryKinds.Reaction?, -- running tap reaction (wobble/flare)
	reactAge: number,
	lastReact: number, -- os.clock() of the last reaction (cooldown)
}

type LaneScenery = {
	folder: Folder,
	origin: Vector3,
	levelName: string,
	skyHidden: boolean,
	spawners: { SpawnerRuntime },
	active: { [BasePart]: PartState },
	oneOffs: { [string]: { BasePart }? }, -- levelObjects (US), one-or-more parts per lane (US is two stacked decal layers, doc 14)
	-- Multiplies this lane's scenery spawn cadence (b-20260923-154344-dr8a):
	-- Levels.list[..].heightStages[Stage attribute].sceneryDensity, read off the
	-- lane folder (Lane.luau owns `Stage`); 1 on a level with no heightStages
	-- (every level but Pot), so nothing else changes behaviour.
	stageDensity: number,
	scroller: PullScroller.Scroller, -- the eased lane pull (world/PullScroller)
	wind: Wind.Wind, -- Country gusts (world/Wind)
	connections: { RBXScriptConnection },
}

local DEFAULT_CADENCE: SceneryKinds.SpawnerCadence =
	{ maxSpawnCount = 10, spawningSpeedMin = 2, spawningSpeedMax = 4, spawnAllOnAwake = false }

-- Cloud kinds (Cloud3 / CloudFar / CloudNear): hidden while the lane is in the Pot
-- (b-20261010-191757-89n1, owner's ruling b-20261012-141140-a1h3), idle Menu included.
local function isCloudPool(pool: { string }): boolean
	for _, kindName in pool do
		if kindName:sub(1, 5) == "Cloud" then
			return true
		end
	end
	return false
end

local function buildSpawners(levelName: string, skyHidden: boolean): { SpawnerRuntime }
	local list: { SpawnerRuntime } = {}
	local level = levelByName[levelName]
	if level then
		for _, def in level.scenerySpawners do
			if
				def.kind == "Scenery"
				and not SceneryKinds.isDuplicateSpawner(def.name)
				and not (skyHidden and isCloudPool(def.pool))
			then
				table.insert(list, {
					direction = def.direction,
					pool = def.pool,
					cadence = SceneryKinds.cadence[def.name] or DEFAULT_CADENCE,
					timer = 0,
					spawnCount = 0,
					awoken = false,
					lastDensity = nil,
					concurrent = false,
					pendingScatter = 0,
				})
			end
		end
	end
	local extras = SceneryKinds.extraSpawners[levelName]
	if extras then
		for _, extra in extras do
			if skyHidden and isCloudPool(extra.pool) then
				continue
			end
			table.insert(list, {
				direction = extra.direction,
				pool = extra.pool,
				cadence = extra.cadence,
				timer = extra.cadence.spawningSpeedMin,
				spawnCount = 0,
				awoken = false,
				lastDensity = nil,
				concurrent = true,
				pendingScatter = extra.initialScatter,
			})
		end
	end
	return list
end

-- Height-stage scenery density (b-20260923-154344-dr8a): the 1-based `Stage`
-- attribute Lane.luau sets, resolved against that level's own heightStages
-- list (currently only Pot's). 1 (unchanged) for any level without one, or
-- before the attribute has replicated yet.
local function densityForStage(levelName: string, stageAttr: unknown): number
	local level = levelByName[levelName]
	local stages = level and level.heightStages
	if not stages or #stages == 0 then
		return 1
	end
	local index = if typeof(stageAttr) == "number" then math.floor(stageAttr) else 1
	local stage = stages[math.clamp(index, 1, #stages)]
	return if stage then stage.sceneryDensity else 1
end

-- levelObjects (doc 11 §3): one-off decorations placed for the duration of a
-- level, not repeat-spawned. Stars/SpeckManager are covered elsewhere (Stars
-- via its own scenerySpawner pseudo-entry above; specks by
-- WorldTutorialSpecks.client.luau) -- only US needs a placement here. The
-- Kitchen Chef is a hazard now (server/Chef.luau, drawn by WorldChef.client.luau).
local function updateLevelObjects(lane: LaneScenery)
	local wantUS = lane.levelName == "Country"
	if wantUS and not lane.oneOffs.US then
		local position = lane.origin + Vector3.new(Config.LANE_HALF_WIDTH * 0.5, 0, WorldConfig.SCENERY_Z)
		lane.oneOffs.US = createUSPair(position)
	elseif not wantUS and lane.oneOffs.US then
		for _, part in lane.oneOffs.US do
			part:Destroy()
		end
		lane.oneOffs.US = nil
	end
end

local lanes: { [Folder]: LaneScenery } = {}

-- Every currently-live part whose kind has a `reaction`, across every lane -- the
-- tap input at the bottom Include-filters its raycast to exactly this set (see
-- "Tap reactions"), so a tap can only ever land on a live reactive part. The
-- filter list is cached and only rebuilt when this set changed (`filterDirty`).
local reactiveStates: { [BasePart]: PartState } = {}
local filterDirty = true

local function setReactive(state: PartState, on: boolean)
	local was = reactiveStates[state.part] ~= nil
	if on and not was then
		reactiveStates[state.part] = state
		filterDirty = true
	elseif not on and was then
		reactiveStates[state.part] = nil
		filterDirty = true
	end
end

local function spawnScenery(lane: LaneScenery, kindName: string, position: Vector3)
	local kind = SceneryKinds.defs[kindName]
	if not kind then
		return
	end
	local part = poolFor(kindName).acquire()
	part.Size = kind.size
	local decal = part:FindFirstChildOfClass("Decal")
	if #kind.colors > 0 then
		local color = kind.colors[math.random(1, #kind.colors)]
		part.Color = color
		if decal then
			decal.Color3 = color
		end
	end
	if decal then
		-- undo a previous arrival fade (fadeOutLeftovers) on a reused part
		decal.Transparency = 1 - kind.opacity
		part.Transparency = if decal.Texture ~= "" then 1 else 1 - kind.opacity
	else
		part.Transparency = 1 - kind.opacity
	end
	local anchor = Vector3.new(position.X, position.Y, lane.origin.Z + kind.z)
	part.CFrame = CFrame.new(anchor)
	part.Parent = workspace
	local state: PartState = {
		part = part,
		kindName = kindName,
		kind = kind,
		lane = lane,
		anchor = anchor,
		age = 0,
		phase = math.random() * math.pi * 2,
		seed = math.random() * 100,
		spinAngle = 0,
		scaled = false,
		reaction = nil,
		reactAge = 0,
		lastReact = -math.huge,
	}
	lane.active[part] = state
	if kind.reaction then
		setReactive(state, true)
	end
end

local function recycleScenery(lane: LaneScenery, part: BasePart)
	local state = lane.active[part]
	lane.active[part] = nil
	if state then
		setReactive(state, false)
		poolFor(state.kindName).release(part)
	end
end

-- Level-up arrival (journey 2/8, b-20260923-154343-3h60): fade out and recycle
-- every live part whose kind the lane's CURRENT level no longer spawns (Pot's
-- Flame/Bubble on arriving in Kitchen), instead of leaving it to drift off.
-- Dropped from `active`/the reactive set at once, so it stops moving, can't be
-- tapped and isn't recycled twice; the delayed release is generation-guarded
-- (Pool.releaseAfter), so it can never free a part that has been re-acquired.
local function fadeOutLeftovers(lane: LaneScenery)
	local keep: { [string]: boolean } = {}
	for _, spawner in lane.spawners do
		for _, kindName in spawner.pool do
			keep[kindName] = true
		end
	end
	local info = TweenInfo.new(WorldConfig.ARRIVAL_SCENERY_FADE_TIME)
	for part, state in lane.active do
		if not keep[state.kindName] then
			lane.active[part] = nil
			setReactive(state, false)
			local decal = part:FindFirstChildOfClass("Decal")
			if decal then
				TweenService:Create(decal, info, { Transparency = 1 }):Play()
			end
			if part.Transparency < 1 then
				TweenService:Create(part, info, { Transparency = 1 }):Play()
			end
			poolFor(state.kindName).releaseAfter(part, WorldConfig.ARRIVAL_SCENERY_FADE_TIME)
		end
	end
end

local function trackLane(folder: Folder)
	if lanes[folder] then
		return
	end
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
	local function skyHidden(): boolean
		return folder:GetAttribute("Level") == "Pot"
	end

	local lane: LaneScenery = {
		folder = folder,
		origin = Lanes.originOf(folder),
		levelName = levelName,
		skyHidden = skyHidden(),
		spawners = buildSpawners(levelName, skyHidden()),
		active = {},
		oneOffs = {},
		stageDensity = densityForStage(levelName, folder:GetAttribute("Stage")),
		scroller = PullScroller.new(folder),
		wind = Wind.new(),
		connections = {},
	}
	lanes[folder] = lane
	updateLevelObjects(lane)

	local function refreshLevel()
		local newName = effectiveLevel()
		local hidden = skyHidden()
		if newName == lane.levelName and hidden == lane.skyHidden then
			return
		end
		local clouds = hidden and not lane.skyHidden
		lane.levelName = newName
		lane.skyHidden = hidden
		lane.spawners = buildSpawners(newName, hidden) -- soft transition: leaves `active` untouched
		lane.stageDensity = densityForStage(newName, folder:GetAttribute("Stage"))
		updateLevelObjects(lane)
		if clouds then
			fadeOutLeftovers(lane) -- clouds already on screen when the Pot began
		end
	end
	local conns = lane.connections
	table.insert(conns, folder:GetAttributeChangedSignal("Level"):Connect(refreshLevel))
	table.insert(conns, folder:GetAttributeChangedSignal("RunState"):Connect(refreshLevel))
	-- Only on a real level-up (Lane.beginArrival), never on run start/respawn.
	table.insert(
		conns,
		folder:GetAttributeChangedSignal("ArrivalCount"):Connect(function()
			refreshLevel() -- no-op if the Level attribute already landed
			fadeOutLeftovers(lane)
		end)
	)
	table.insert(
		conns,
		Lanes.watchOrigin(folder, function(origin)
			lane.origin = origin
		end)
	)
	table.insert(
		conns,
		folder:GetAttributeChangedSignal("Stage"):Connect(function()
			lane.stageDensity = densityForStage(lane.levelName, folder:GetAttribute("Stage"))
		end)
	)
end

local function untrackLane(folder: Folder)
	local lane = lanes[folder]
	if not lane then
		return
	end
	lanes[folder] = nil
	for _, conn in lane.connections do
		conn:Disconnect()
	end
	lane.scroller:destroy()
	for part, state in lane.active do
		setReactive(state, false)
		poolFor(state.kindName).release(part)
	end
	table.clear(lane.active)
	for _, parts in lane.oneOffs do
		if parts then
			for _, part in parts do
				part:Destroy()
			end
		end
	end
end

Lanes.observe(trackLane, untrackLane)

-- ---------------------------------------------------------------------------
-- Per-frame: spawn cadence, pull + drift + wind integration, motion
-- descriptors, tap-reaction animation, bounds recycling. PreRender (not
-- Heartbeat): these are purely visual writes, so they should land in the frame
-- they are drawn.
-- ---------------------------------------------------------------------------
local TAU = math.pi * 2

local function liveCount(lane: LaneScenery, pool: { string }): number
	local n = 0
	for _, state in lane.active do
		if table.find(pool, state.kindName) then
			n += 1
		end
	end
	return n
end

local function tickSpawner(lane: LaneScenery, spawner: SpawnerRuntime, dt: number)
	local cadence = spawner.cadence
	if spawner.pendingScatter > 0 then
		local missing = spawner.pendingScatter - liveCount(lane, spawner.pool)
		spawner.pendingScatter = 0
		for _ = 1, missing do
			spawnScenery(lane, spawner.pool[math.random(1, #spawner.pool)], scatterPosition(lane.origin))
		end
	end
	if cadence.spawnAllOnAwake then
		-- b-20260923-154344-dr8a: a density change (Pot's Stage attribute)
		-- after the one-shot batch already fired replaces it instead of
		-- leaving the batch stuck at whatever density was live at first tick.
		if not spawner.awoken or spawner.lastDensity ~= lane.stageDensity then
			if spawner.awoken then
				for part, state in lane.active do
					if table.find(spawner.pool, state.kindName) then
						recycleScenery(lane, part)
					end
				end
				spawner.spawnCount = 0
			end
			spawner.awoken = true
			spawner.lastDensity = lane.stageDensity
			local density = math.max(0.05, lane.stageDensity)
			local count = math.max(
				1,
				math.min(
					cadence.maxSpawnCount,
					math.floor(#spawner.pool * WorldConfig.AWAKE_BATCH_PER_POOL_ENTRY * density)
				)
			)
			for i = 1, count do
				local kindName = spawner.pool[((i - 1) % #spawner.pool) + 1]
				spawnScenery(lane, kindName, spawnPosition(lane.origin, spawner.direction))
				spawner.spawnCount += 1
			end
		end
		return
	end

	spawner.timer -= dt
	if spawner.timer > 0 then
		return
	end
	local cap = if cadence.maxSpawnCount < 0 then WorldConfig.SCENERY_POOL_CAP else cadence.maxSpawnCount
	local count = if spawner.concurrent then liveCount(lane, spawner.pool) else spawner.spawnCount
	if count < cap and #spawner.pool > 0 then
		local kindName = spawner.pool[math.random(1, #spawner.pool)]
		spawnScenery(lane, kindName, spawnPosition(lane.origin, spawner.direction))
		spawner.spawnCount += 1
	end
	local span = math.max(0, cadence.spawningSpeedMax - cadence.spawningSpeedMin)
	local interval = math.max(WorldConfig.SPAWNER_MIN_INTERVAL, cadence.spawningSpeedMin + math.random() * span)
	-- b-20260923-154344-dr8a: higher stage density -> shorter interval
	-- -> denser continuous scenery (Pot's Bubble spawner); 1 elsewhere.
	spawner.timer = interval / math.max(WorldConfig.SPAWNER_MIN_INTERVAL, lane.stageDensity)
end

-- Advance one live part: integrate pull/drift into its anchor, evaluate its motion
-- descriptor and any running tap reaction, then write CFrame/Size once. Returns
-- false when the part has left the lane's bounds (caller recycles it).
local function updatePart(state: PartState, pull: Vector3, gust: number, dt: number): boolean
	local kind = state.kind
	local part = state.part
	local anchor = state.anchor
	local moved = false

	if kind.moving then
		local dir = kind.moveDirection
		if dir.Magnitude > 1e-4 then
			local unit = dir.Unit
			anchor += Vector3.new(unit.X, unit.Y, 0) * kind.moveSpeed * dt
			moved = true
		end
	else
		if pull.X ~= 0 or pull.Y ~= 0 then
			anchor += Vector3.new(pull.X, pull.Y, 0) * kind.speedModifier
			moved = true
		end
		local driftX, driftY = kind.autoMove.X, kind.autoMove.Y
		if gust > 0 and kind.windSensitivity > 0 then
			local push = WorldConfig.WIND_STRENGTH * gust * kind.windSensitivity
			driftX += WorldConfig.WIND_DIRECTION.X * push
			driftY += WorldConfig.WIND_DIRECTION.Y * push
		end
		if driftX ~= 0 or driftY ~= 0 then
			anchor += Vector3.new(driftX, driftY, 0) * dt
			moved = true
		end
	end
	state.anchor = anchor
	state.age += dt

	local offsetX, offsetY, rollDeg = 0, 0, 0
	local scaleX, scaleY = 1, 1
	local motion = kind.motion
	local animated = false
	if motion then
		animated = true
		local ampScale = WorldConfig.MOTION_AMPLITUDE_SCALE
			* (1 + gust * WorldConfig.WIND_SWAY_BOOST * kind.windSensitivity)
		local rate = TAU * WorldConfig.MOTION_SPEED_SCALE
		local swayPhase = state.phase + state.age * rate / motion.swayPeriod
		offsetX = math.sin(swayPhase) * motion.swayX * ampScale
		-- a different frequency on Y so the path is a lissajous, not a diagonal line
		offsetY = math.cos(swayPhase * 1.3) * motion.swayY * ampScale
		if motion.roll ~= 0 then
			rollDeg = math.sin(state.phase + state.age * rate / motion.rollPeriod + 1.0) * motion.roll * ampScale
		end
		if motion.spin ~= 0 then
			state.spinAngle += motion.spin * dt
			rollDeg += state.spinAngle
		end
		if motion.pulse ~= 0 or motion.flicker ~= 0 then
			local pulsePhase = state.phase + state.age * rate / motion.pulsePeriod
			local s = 1
				+ math.sin(pulsePhase) * motion.pulse * WorldConfig.MOTION_AMPLITUDE_SCALE
				+ math.noise(state.age * 7, state.seed) * motion.flicker * WorldConfig.MOTION_AMPLITUDE_SCALE
			scaleX, scaleY = s, s
		end
	end

	local reaction = state.reaction
	if reaction then
		animated = true
		state.reactAge += dt
		if reaction == "wobble" then
			local u = state.reactAge / WorldConfig.WOBBLE_DURATION
			if u >= 1 then
				state.reaction = nil
			else
				local wave = math.sin(u * WorldConfig.WOBBLE_FREQUENCY * TAU) * (1 - u)
				rollDeg += wave * WorldConfig.WOBBLE_ROLL_DEGREES
				scaleX *= 1 + wave * WorldConfig.WOBBLE_SQUASH
				scaleY *= 1 - wave * WorldConfig.WOBBLE_SQUASH
			end
		elseif reaction == "flare" then
			local u = state.reactAge / WorldConfig.FLARE_DURATION
			if u >= 1 then
				state.reaction = nil
			else
				local swell = 1 + math.sin(u * math.pi) * WorldConfig.FLARE_SCALE
				scaleX *= swell
				scaleY *= swell
			end
		end
	end

	if moved or animated then
		part.CFrame = CFrame.new(anchor.X + offsetX, anchor.Y + offsetY, anchor.Z)
			* CFrame.Angles(0, 0, math.rad(rollDeg))
		local scaled = scaleX ~= 1 or scaleY ~= 1
		if scaled or state.scaled then
			local size = kind.size
			part.Size = Vector3.new(size.X * scaleX, size.Y * scaleY, size.Z)
			state.scaled = scaled
		end
	end

	return not Lanes.isOutOfBounds(state.lane.origin, anchor, kind.size.X / 2, kind.size.Y / 2)
end

RunService.PreRender:Connect(function(dt: number)
	for _, lane in lanes do
		for _, spawner in lane.spawners do
			tickSpawner(lane, spawner, dt)
		end

		local pull = lane.scroller:step(dt)
		local gust = lane.wind:step(dt, WorldConfig.WIND_LEVELS[lane.levelName] == true)
		for part, state in lane.active do
			if not updatePart(state, pull, gust, dt) then
				recycleScenery(lane, part)
			end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Tap reactions (generalises the Bubble pop: Entities/MovingScenery.cs Grab,
-- gated by Player/Controller.cs's CheckTouch to its "GrabableScenery" tag -- see
-- SceneryKinds.luau's `poppable`/`reaction` doc comments for why only Bubble is
-- a real Unity pop). Purely cosmetic, no gameplay effect (Grab's `playerID`
-- argument goes unused in the original too): its own input -> raycast ->
-- reaction pipeline, entirely separate from (and never touching)
-- GameClient.client.luau's grab input.
--   pop    -- SoundFX "pop", a particle burst, recycle (the original behaviour)
--   wobble -- damped squash + roll (clouds)
--   flare  -- the flame swells and throws a few sparks
--
-- Coexistence with step grabs: this connects its own UserInputService.
-- InputBegan listener -- the SAME signal GameClient.client.luau already listens
-- on. Roblox fires every connected listener for a given input (no "consume"
-- between scripts), so a step grab always still fires from GameClient's own
-- handler no matter what this one does. This handler's raycast is Include-
-- filtered to exactly `reactiveStates` (live reactive parts, CanQuery=true),
-- which can never overlap GameClient's / WorldTouchIndicator's Include filters
-- (the Steps/Bugs folders): a scenery part is never parented under either, so a
-- tap on a step or a bug is never swallowed by a cloud that happens to be behind.
-- Only the nearest reactive part under the tap reacts.
-- ---------------------------------------------------------------------------
-- ADAPTED: MovingScenery.cs's particle burst is a Unity ParticleSystem; this
-- port has no 1:1 ParticleEmitter equivalent wired through the pooled-part
-- style the rest of the world dressing already uses, so it's a handful of
-- tinted, pooled Balls flying outward and fading (world/Bursts), same shape as
-- the lava splash.
local popBursts = Bursts.new({
	name = "PopBurst",
	size = WorldConfig.POP_BURST_SIZE,
	material = Enum.Material.Neon,
	shape = Enum.PartType.Ball,
	-- A pop now fires a tinted and a white burst (~28 parts), so keep enough
	-- parked for back-to-back pops without churning Instances.
	cap = 96,
})
local flareSparks = Bursts.new({
	name = "FlareSpark",
	size = WorldConfig.FLARE_SPARK_SIZE,
	material = Enum.Material.Neon,
	shape = Enum.PartType.Ball,
	color = WorldConfig.FLARE_SPARK_COLOR,
})

local function popPart(state: PartState)
	local part = state.part
	if not reactiveStates[part] then
		return -- already popped by another input this frame
	end
	SoundFX.play("pop") -- MovingScenery.cs Grab: AudioManager.Instance.PlayForAll(grabClip) (Pop.wav)
	popBursts.emit(part.Position, {
		count = WorldConfig.POP_BURST_COUNT,
		radialSpeed = WorldConfig.POP_BURST_SPEED,
		lifetime = WorldConfig.POP_BURST_LIFETIME,
		color = part.Color,
		fadeStart = 0.3,
	})
	-- white flash ring on top of the tinted droplets so the pop reads on any bubble colour
	popBursts.emit(part.Position, {
		count = WorldConfig.POP_BURST_COUNT,
		radialSpeed = WorldConfig.POP_BURST_SPEED * 0.5,
		lifetime = WorldConfig.POP_BURST_LIFETIME * 0.7,
		color = Color3.new(1, 1, 1),
		fadeStart = 0.2,
		scale = 0.6,
	})
	recycleScenery(state.lane, part) -- MovingScenery.cs Grab: Destroy(0, 0, 1f)
end

local function reactTo(state: PartState)
	local reaction = state.kind.reaction
	if reaction == "pop" then
		popPart(state)
		return
	end
	local now = os.clock()
	if reaction == nil or state.reaction ~= nil or now - state.lastReact < WorldConfig.REACTION_COOLDOWN then
		return
	end
	state.reaction = reaction :: SceneryKinds.Reaction -- narrowed by the nil check above; Luau widens the literal union to string
	state.reactAge = 0
	state.lastReact = now
	if reaction == "flare" then
		local speed = WorldConfig.FLARE_SPARK_SPEED
		flareSparks.emit(state.part.Position, {
			count = WorldConfig.FLARE_SPARK_COUNT,
			x = NumberRange.new(-speed, speed),
			y = NumberRange.new(speed * 0.4, speed),
			lifetime = WorldConfig.FLARE_SPARK_LIFETIME,
			fadeStart = 0.3,
		})
	end
end

local tapRayParams = RaycastParams.new()
tapRayParams.FilterType = Enum.RaycastFilterType.Include

-- Rebuilt only when the reactive set changed since the last tap, not per tap.
local function refreshFilter()
	if not filterDirty then
		return
	end
	filterDirty = false
	local filter: { Instance } = {}
	for part in reactiveStates do
		table.insert(filter, part)
	end
	tapRayParams.FilterDescendantsInstances = filter
end

local function tryReact(screenX: number, screenY: number)
	local camera = workspace.CurrentCamera
	if not camera or next(reactiveStates) == nil then
		return
	end
	refreshFilter()
	local unitRay = camera:ScreenPointToRay(screenX, screenY)
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * WorldConfig.TAP_RAY_LENGTH, tapRayParams)
	if result and result.Instance:IsA("BasePart") then
		local state = reactiveStates[result.Instance]
		if state then
			reactTo(state)
		end
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		tryReact(input.Position.X, input.Position.Y)
	end
end)
