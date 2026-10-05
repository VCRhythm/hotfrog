-- ServerScriptService/Server/BugService (Script)
-- The bug collectible loop (../../docs/roblox-port/06-bugs-and-tongue.md; ports
-- Entities/Bug.cs + Spawning/BugSpawner.cs): bugs drift in from an edge, idle for
-- a lifespan (flying a Hover/FigureEight/Dart/Skittish pattern, occasionally as a
-- swarm or a golden bug), then leave -- unless a player taps one, in which case the server
-- validates the catch, awards Flys through the shared AwardFlys faucet (Bug.cs
-- CollectFly -> the Fly currency), and tells the catcher for tongue/squish
-- feedback. Bugs are pooled and moved by a single Heartbeat integrator.
--
-- Per-lane (doc 13 item 7): each occupied lane runs its own spawn cadence and
-- picks positions relative to that lane's origin, and a bug is tagged with its
-- lane's UserId so only that lane's player can catch it. Lanes are discovered
-- through `workspace.PlayField.Lanes`' child Folders and their `UserId`/`Origin`
-- attributes (Lane.luau sets these) -- this script deliberately never requires
-- server/Lane.luau or GameServer, so load order between them is moot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)

-- ---------------------------------------------------------------------------
-- Remotes
-- ---------------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local function ensure(name: string, className: string): Instance
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = remotes
	end
	return r
end

local CatchBug = ensure("CatchBug", "RemoteEvent") :: RemoteEvent -- client -> server: tapped a bug
local BugCaught = ensure("BugCaught", "RemoteEvent") :: RemoteEvent -- server -> client: catch confirmed

-- Single Fly faucet (created by SkinService; get-or-create so load order is moot)
local awardFlys = ServerStorage:FindFirstChild("AwardFlys") :: BindableEvent?
if not awardFlys then
	awardFlys = Instance.new("BindableEvent")
	awardFlys.Name = "AwardFlys"
	awardFlys.Parent = ServerStorage
end

-- SpawnFly step behavior fan-in (created by GameServer; get-or-create so load
-- order is moot, same pattern as the AwardFlys faucet above): grabbing a
-- FlyRock-style step fires this with the step's position instead of requiring a
-- Script-to-Script call (doc 05, ActionType.SpawnFly).
local spawnBugAt = ServerStorage:FindFirstChild("SpawnBugAt") :: BindableEvent?
if not spawnBugAt then
	spawnBugAt = Instance.new("BindableEvent")
	spawnBugAt.Name = "SpawnBugAt"
	spawnBugAt.Parent = ServerStorage
end

-- Confirmed-catch fan-out to GameServer (doc 17 gap: GameServer's own
-- bugsThisRun counter, for the end-of-run RunSummary, used to infer a catch
-- from the Fly award amount matching Config.BUG_FLYS -- a heuristic that would
-- silently miscount if that amount, or another faucet's amount, ever changed.
-- This reports a confirmed catch directly, with no inference. Get-or-create in
-- ServerStorage, same pattern as AwardFlys/SpawnBugAt above, so load order
-- between BugService and GameServer stays moot.
local bugCaughtServer = ServerStorage:FindFirstChild("BugCaughtServer") :: BindableEvent?
if not bugCaughtServer then
	bugCaughtServer = Instance.new("BindableEvent")
	bugCaughtServer.Name = "BugCaughtServer"
	bugCaughtServer.Parent = ServerStorage
end

-- Gift-fly burst fan-in (doc 09, b-20260921-152631: claiming a gift used to be
-- invisible besides the Flys ticking up -- Unity's GiftManager.GiftFlys ->
-- MenuManager.SpawnGiftFlys bursts a bundle of catchable flies onto the screen
-- for the player to eat, purely for the fun of it (Bug.cs is reused for both
-- normal bugs and gift flies in the original). GiftService fires this with the
-- claimant and how many to spawn; get-or-create, same pattern as the faucets
-- above, so load order between GiftService and BugService stays moot.
local spawnGiftFlys = ServerStorage:FindFirstChild("SpawnGiftFlys") :: BindableEvent?
if not spawnGiftFlys then
	spawnGiftFlys = Instance.new("BindableEvent")
	spawnGiftFlys.Name = "SpawnGiftFlys"
	spawnGiftFlys.Parent = ServerStorage
end

-- ---------------------------------------------------------------------------
-- Container + template (self-provisioned so the scene needs no extra manual
-- setup; replace Assets/BugTemplate with real art whenever you like)
-- ---------------------------------------------------------------------------
local playField = workspace:WaitForChild("PlayField")
local container = playField:FindFirstChild("Bugs")
if not container then
	container = Instance.new("Folder")
	container.Name = "Bugs"
	container.Parent = playField
end

local assets = ReplicatedStorage:FindFirstChild("Assets")
if not assets then
	assets = Instance.new("Folder")
	assets.Name = "Assets"
	assets.Parent = ReplicatedStorage
end

local template = assets:FindFirstChild("BugTemplate")
if not template then
	local part = Instance.new("Part")
	part.Name = "BugTemplate"
	part.Size = Vector3.new(2, 2, 0.4)
	part.CanCollide = false
	part.Transparency = 1 -- host for the Decal only; a coloured part reads as an opaque sprite background
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
	decal.ZIndex = 0
	decal.Color3 = Color3.new(0, 0, 0) -- Bug.png is a white silhouette (alpha-only shape), tinted black same as Unity's SpriteRenderer
	decal:SetAttribute("Sprite", "Bug") -- Sprites/Other/Bug.png via SkinAssets
	decal.Parent = part
	local wings = Instance.new("Decal")
	wings.Face = Enum.NormalId.Back
	wings.ZIndex = 1
	wings:SetAttribute("Sprite", "Wing1") -- Sprites/Other/Wing1.png via SkinAssets; Unity's Bug prefab layers this over the body (doc 12 SS2)
	wings.Parent = part
	part.Parent = assets
	template = part
end

-- ---------------------------------------------------------------------------
-- Pool + lifecycle. Unity's Bug.cs runs a DOTween per bug (MoveTo, then Leave
-- after lifeSpan) and then sits still; the port instead keeps one Heartbeat
-- integrator over every active bug (below) so flight patterns compose and
-- nothing but `states` owns a bug's lifetime. `releaseBug` is the single
-- teardown: it drops the state, so a stale catch or the integrator can never
-- act on a pooled part. No delayed callbacks remain, so no Gen guard is needed
-- for bug motion; `Gen` is still bumped per spawn so clients can tell a
-- recycled part from its previous life.
-- ---------------------------------------------------------------------------
type BugState = {
	part: BasePart,
	laneUserId: number,
	laneX: number, -- lane origin X (box centre)
	pattern: string,
	golden: boolean,
	reward: boolean,
	phase: number, -- per-bug phase offset (radians) so swarms don't wobble in lockstep
	mode: "enter" | "fly" | "leave",
	modeT: number, -- seconds in the current mode
	life: number, -- fly-mode duration
	start: Vector3,
	dest: Vector3,
	exitX: number,
	pos: Vector3,
	center: Vector3, -- pattern anchor (moves for Skittish)
	dartTimer: number,
	dartTarget: Vector3,
}

local pool: { BasePart } = {}
local states: { [BasePart]: BugState } = {}
local laneCount: { [number]: number } = {}

local function releaseBug(bug: BasePart)
	local state = states[bug]
	if not state then
		return -- idempotent: catch and the lifespan can race
	end
	states[bug] = nil
	laneCount[state.laneUserId] = math.max(0, (laneCount[state.laneUserId] or 1) - 1)
	bug.Parent = nil
	if #pool >= Config.BUG_POOL_MAX then
		bug:Destroy() -- bound the pool; a gift burst can briefly need far more parts than steady state
	else
		table.insert(pool, bug)
	end
end

local PATTERN_ORDER = { "Hover", "FigureEight", "Dart", "Skittish" }

local function pickPattern(allowed: { string }?): string
	local weights = Config.BUG_PATTERN_WEIGHTS :: { [string]: number }
	local names = allowed or PATTERN_ORDER
	local total = 0
	for _, name in names do
		total += weights[name] or 0
	end
	if total <= 0 then
		return "Hover"
	end
	local roll = math.random() * total
	for _, name in names do
		roll -= weights[name] or 0
		if roll <= 0 then
			return name
		end
	end
	return "Hover"
end

local function clampToBox(p: Vector3, laneX: number): Vector3
	return Vector3.new(
		math.clamp(p.X, laneX - Config.BUG_X_RANGE, laneX + Config.BUG_X_RANGE),
		math.clamp(p.Y, -Config.BUG_Y_RANGE, Config.BUG_Y_RANGE),
		Config.PLANE_Z
	)
end

local function randomInBox(laneX: number): Vector3
	return Vector3.new(
		laneX + (math.random() * 2 - 1) * Config.BUG_X_RANGE,
		(math.random() * 2 - 1) * Config.BUG_Y_RANGE,
		Config.PLANE_Z
	)
end

local function findArt(bug: BasePart): Decal?
	for _, child in bug:GetChildren() do
		if child:IsA("Decal") and child:GetAttribute("Sprite") == "Bug" then
			return child
		end
	end
	return nil
end

-- Common launch: stamps attributes, parks the part at `startPos` and registers
-- it with the integrator. `golden` is only ever passed for rewarded bugs.
local function launch(
	laneOrigin: Vector3,
	laneUserId: number,
	startPos: Vector3,
	dest: Vector3,
	reward: boolean,
	pattern: string,
	golden: boolean,
	phase: number
)
	local bug = (table.remove(pool) or template:Clone()) :: BasePart
	bug:SetAttribute("Kind", "Bug")
	bug:SetAttribute("Gen", ((bug:GetAttribute("Gen") :: number?) or 0) + 1)
	bug:SetAttribute("LaneUserId", laneUserId)
	bug:SetAttribute("Reward", reward)
	bug:SetAttribute("Pattern", pattern)
	bug:SetAttribute("Golden", golden)
	bug.Anchored = true
	SpriteSkin.apply(bug) -- no-op until ids land in SkinAssets
	local art = findArt(bug)
	if art then
		art.Color3 = if golden then Config.GOLDEN_BUG_COLOR else Color3.new(0, 0, 0)
	end
	bug.CFrame = CFrame.new(startPos)
	bug.Parent = container

	local exitSide = if math.random() > 0.5 then 1 else -1
	states[bug] = {
		part = bug,
		laneUserId = laneUserId,
		laneX = laneOrigin.X,
		pattern = pattern,
		golden = golden,
		reward = reward,
		phase = phase,
		mode = "enter",
		modeT = 0,
		life = if golden then Config.GOLDEN_BUG_LIFESPAN else Config.BUG_LIFESPAN,
		start = startPos,
		dest = dest,
		exitX = laneOrigin.X + exitSide * (Config.BUG_X_RANGE + Config.BUG_EDGE_EXIT_MARGIN),
		pos = startPos,
		center = dest,
		dartTimer = 0,
		dartTarget = dest,
	}
	laneCount[laneUserId] = (laneCount[laneUserId] or 0) + 1
end

-- `origin` is set for ActionType.SpawnFly (doc 05): a FlyRock-style step was
-- grabbed, so the bug starts at the step and only wanders nearby, instead of
-- entering from the screen edge and roaming the whole field like a normal spawn.
-- `laneOrigin`/`laneUserId` scope the spawn/wander bounds and catch permission
-- to one lane (doc 13 item 7). `reward` false marks a gift fly (see
-- spawnGiftFlys.Event below): still catchable for the squish/tongue feedback,
-- but CatchBug won't pay it out, since the gift already granted its Flys up
-- front -- these are Unity's SpawnGiftFlys bundle, ported as a flourish, not a
-- second currency source. `wideBurst` (only with `origin`) sends it to a
-- random point across the whole lane, like a normal edge spawn's destination,
-- instead of the small nearby wander FlyRock uses -- the "explode onto the
-- screen" look a gift burst wants.
local function spawnBug(
	laneOrigin: Vector3,
	laneUserId: number,
	origin: Vector3?,
	reward: boolean?,
	wideBurst: boolean?
)
	local rewarded = reward ~= false
	if (laneCount[laneUserId] or 0) >= Config.BUG_MAX_PER_LANE_BURST then
		return
	end
	local laneX = laneOrigin.X
	local startPos: Vector3
	local dest: Vector3
	if origin and wideBurst then
		startPos = origin
		dest = randomInBox(laneX)
	elseif origin then
		startPos = origin
		dest = clampToBox(
			origin
				+ Vector3.new(
					math.random(-Config.BUG_NEAR_WANDER_X, Config.BUG_NEAR_WANDER_X),
					math.random(-Config.BUG_NEAR_WANDER_Y, Config.BUG_NEAR_WANDER_Y),
					0
				),
			laneX
		)
	else
		-- enter from a side edge, drift to a random on-screen point with the
		-- original's overshoot feel (Bug.SetUpDestination / MoveTo: DOMove + Ease.OutBack)
		local side = if math.random() > 0.5 then 1 else -1
		startPos = Vector3.new(
			laneX + side * (Config.BUG_X_RANGE + Config.BUG_EDGE_ENTER_MARGIN),
			(math.random() * 2 - 1) * Config.BUG_Y_RANGE,
			Config.PLANE_Z
		)
		dest = randomInBox(laneX)
	end
	local golden = rewarded and math.random() < Config.GOLDEN_BUG_CHANCE
	local pattern = if golden then "Dart" else pickPattern()
	launch(laneOrigin, laneUserId, startPos, dest, rewarded, pattern, golden, math.random() * math.pi * 2)
end

-- A loose cluster entering together from one edge: members share a destination
-- centre (offset around it) and a Hover/FigureEight pattern, with evenly spaced
-- phase offsets so they weave rather than move in lockstep. Never golden.
local function spawnSwarm(laneOrigin: Vector3, laneUserId: number, count: number)
	local laneX = laneOrigin.X
	local side = if math.random() > 0.5 then 1 else -1
	local entryY = (math.random() * 2 - 1) * Config.BUG_Y_RANGE
	local centre = randomInBox(laneX)
	local pattern = pickPattern({ "Hover", "FigureEight" })
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local offset = Vector3.new(math.cos(angle), math.sin(angle), 0) * Config.BUG_SWARM_SPREAD
		local startPos = Vector3.new(
			laneX + side * (Config.BUG_X_RANGE + Config.BUG_EDGE_ENTER_MARGIN + (i - 1) * 1.5), -- trail in a loose line
			entryY + offset.Y,
			Config.PLANE_Z
		)
		launch(laneOrigin, laneUserId, startPos, clampToBox(centre + offset, laneX), true, pattern, false, angle)
	end
end

-- Timed edge spawn: respects the soft per-lane cap, occasionally a swarm.
local function spawnEdge(laneOrigin: Vector3, laneUserId: number)
	local room = Config.BUG_MAX_PER_LANE - (laneCount[laneUserId] or 0)
	if room <= 0 then
		return
	end
	if room >= Config.BUG_SWARM_MIN and math.random() < Config.BUG_SWARM_CHANCE then
		spawnSwarm(laneOrigin, laneUserId, math.min(room, math.random(Config.BUG_SWARM_MIN, Config.BUG_SWARM_MAX)))
	else
		spawnBug(laneOrigin, laneUserId)
	end
end

-- ---------------------------------------------------------------------------
-- Integrator. One Heartbeat pass over every active bug, throttled to
-- BUG_UPDATE_HZ (30 Hz: anchored-part CFrame writes replicate unsmoothed, so
-- the rate is a replication-cost vs smoothness trade; 30 keeps a Dart's zip
-- readable while halving the traffic of per-frame writes) and dt-clamped so a
-- server hitch can't teleport bugs. All moves go out in one BulkMoveTo.
-- ---------------------------------------------------------------------------
local frogsFolder = playField:WaitForChild("Frogs")
local limbCache: { [number]: { Vector3 } } = {} -- per integrator step, lazily filled

local function limbPositions(laneUserId: number): { Vector3 }
	local cached = limbCache[laneUserId]
	if cached then
		return cached
	end
	local list: { Vector3 } = {}
	local frog = frogsFolder:FindFirstChild("Frog_" .. laneUserId)
	if frog then
		for _, name in { "LeftLimb", "RightLimb" } do
			local limb = frog:FindFirstChild(name)
			if limb and limb:IsA("BasePart") then
				table.insert(list, limb.Position) -- read only; the frog is simulated elsewhere
			end
		end
	end
	limbCache[laneUserId] = list
	return list
end

local function easeOutBack(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	local u = t - 1
	return 1 + c3 * u * u * u + c1 * u * u
end

local function flyStep(s: BugState, dt: number)
	local t = s.modeT
	local ramp = math.min(1, t / Config.BUG_FLY_IN_RAMP)
	local pattern = s.pattern
	if pattern == "Dart" then
		local interval = if s.golden then Config.GOLDEN_BUG_DART_INTERVAL else Config.BUG_DART_INTERVAL
		local radius = if s.golden then Config.GOLDEN_BUG_DART_RADIUS else Config.BUG_DART_RADIUS
		local smooth = if s.golden then Config.GOLDEN_BUG_DART_SMOOTH else Config.BUG_DART_SMOOTH
		s.dartTimer -= dt
		if s.dartTimer <= 0 then
			s.dartTimer = interval * (0.8 + 0.4 * math.random())
			local jump = Vector3.new((math.random() * 2 - 1) * radius, (math.random() * 2 - 1) * radius, 0)
			s.dartTarget = clampToBox(s.pos + jump, s.laneX)
		end
		s.pos = clampToBox(s.pos:Lerp(s.dartTarget, 1 - math.exp(-smooth * dt)), s.laneX)
		return
	end
	local offset: Vector3
	if pattern == "FigureEight" then
		local a = Config.BUG_EIGHT_FREQ * t + s.phase
		offset = Vector3.new(Config.BUG_EIGHT_AMP_X * math.sin(a), Config.BUG_EIGHT_AMP_Y * math.sin(2 * a), 0)
	else
		local a = Config.BUG_HOVER_FREQ * t + s.phase
		offset = Vector3.new(Config.BUG_HOVER_AMP_X * math.sin(a), Config.BUG_HOVER_AMP_Y * math.sin(1.7 * a + 1), 0)
		if pattern == "Skittish" then
			-- drift the anchor away from any frog limb that gets close (read-only)
			for _, limbPos in limbPositions(s.laneUserId) do
				local away = Vector3.new(s.center.X - limbPos.X, s.center.Y - limbPos.Y, 0)
				local dist = away.Magnitude
				if dist < Config.BUG_SKITTISH_RADIUS then
					local dir = if dist > 0.01
						then away / dist
						else Vector3.new(math.cos(s.phase), math.sin(s.phase), 0)
					s.center = clampToBox(s.center + dir * Config.BUG_SKITTISH_SPEED * dt, s.laneX)
				end
			end
		end
	end
	s.pos = clampToBox(s.center + offset * ramp, s.laneX)
end

local acc = 0
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local doomed: { BasePart } = {}

RunService.Heartbeat:Connect(function(rawDt: number)
	acc += rawDt
	if acc < 1 / Config.BUG_UPDATE_HZ then
		return
	end
	local dt = math.min(acc, Config.BUG_DT_MAX)
	acc = 0
	table.clear(limbCache)
	table.clear(moveParts)
	table.clear(moveCFrames)
	table.clear(doomed)

	for bug, s in states do
		s.modeT += dt
		if s.mode == "enter" then
			local a = math.min(1, s.modeT / Config.BUG_ENTER_TIME)
			s.pos = s.start:Lerp(s.dest, easeOutBack(a))
			if a >= 1 then
				s.mode, s.modeT = "fly", 0
				s.pos, s.center, s.dartTarget = s.dest, s.dest, s.dest
			end
		elseif s.mode == "fly" then
			flyStep(s, dt)
			if s.modeT >= s.life then
				-- lifespan over: leave unless caught (Bug.Leave)
				s.mode, s.modeT = "leave", 0
				s.start = s.pos
			end
		else
			local a = math.min(1, s.modeT / Config.BUG_LEAVE_TIME)
			local eased = a * a -- accelerate off-screen
			s.pos = Vector3.new(s.start.X + (s.exitX - s.start.X) * eased, s.start.Y, Config.PLANE_Z)
			if a >= 1 then
				table.insert(doomed, bug)
				continue
			end
		end
		table.insert(moveParts, bug)
		table.insert(moveCFrames, CFrame.new(s.pos))
	end

	for _, bug in doomed do
		releaseBug(bug)
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)

-- ---------------------------------------------------------------------------
-- Per-lane discovery + spawn cadence (doc 13 item 7). Lane.luau creates one
-- Folder per lane under `workspace.PlayField.Lanes` carrying `UserId`/`Origin`
-- attributes; this script only ever reads those, never server/Lane.luau or
-- GameServer directly, so load order between the three is moot. Spawning is
-- deliberately NOT gated on RunState: bugs still fly and can be eaten on the
-- Menu/Dead screen (doc 17 attract mode).
-- ---------------------------------------------------------------------------
local lanesFolder = playField:WaitForChild("Lanes")
local laneLoopRunning: { [Instance]: boolean } = {}

local function laneOriginOf(laneFolder: Instance): (Vector3?, number?)
	local origin = laneFolder:GetAttribute("Origin")
	local userId = laneFolder:GetAttribute("UserId")
	if typeof(origin) == "Vector3" and typeof(userId) == "number" then
		return origin, userId
	end
	return nil, nil
end

local function onLaneAdded(laneFolder: Instance)
	if not laneFolder:IsA("Folder") then
		return
	end
	laneLoopRunning[laneFolder] = true
	task.spawn(function()
		-- the very first tick may race Lane.luau setting attributes right after
		-- Instance.new/Parent -- wait a beat for them to land
		while laneLoopRunning[laneFolder] and laneFolder.Parent do
			local origin, userId = laneOriginOf(laneFolder)
			if origin and userId then
				spawnEdge(origin, userId)
			end
			task.wait(Config.BUG_INTERVAL)
		end
	end)
end

lanesFolder.ChildAdded:Connect(onLaneAdded)
lanesFolder.ChildRemoved:Connect(function(laneFolder: Instance)
	laneLoopRunning[laneFolder] = nil
end)
for _, laneFolder in lanesFolder:GetChildren() do
	onLaneAdded(laneFolder)
end

-- ActionType.SpawnFly (doc 05): GameServer fires this with the grabbed step's
-- world position AND its lane's userId (the step's own LaneUserId attribute),
-- since the step's position alone doesn't say which lane it belongs to.
spawnBugAt.Event:Connect(function(position: Vector3, laneUserId: number)
	local laneFolder = lanesFolder:FindFirstChild(tostring(laneUserId))
	local origin = if laneFolder then select(1, laneOriginOf(laneFolder)) else nil
	spawnBug(origin or Vector3.new(0, 0, Config.PLANE_Z), laneUserId, position)
end)

-- ---------------------------------------------------------------------------
-- Catching. No reach gate on purpose: the tongue spans the whole screen in the
-- original (Controller.TouchBug works on anything tappable). Validation is
-- "a real, still-active bug FROM THIS PLAYER'S OWN LANE" (doc 13 item 7) -- the
-- server owns the bug set, so a stale tap on an already-departed bug, or
-- another lane's bug, simply doesn't score.
-- ---------------------------------------------------------------------------
CatchBug.OnServerEvent:Connect(function(player, bug)
	if typeof(bug) ~= "Instance" or not bug:IsA("BasePart") then
		return
	end
	local state = states[bug]
	if not state or state.laneUserId ~= player.UserId then
		return
	end
	local reward = state.reward -- false only for gift flies (see spawnBug)
	local flys = if state.golden then Config.GOLDEN_BUG_FLYS else Config.BUG_FLYS
	local position = bug.Position
	releaseBug(bug)
	if reward then
		awardFlys:Fire(player, flys)
		bugCaughtServer:Fire(player) -- GameServer's exact bugsThisRun counter (doc 17 gap); one count even for golden
	end
	BugCaught:FireClient(player, position) -- feedback hook (squish sound / flash) -- always, gift or not
end)

-- Gift claim (doc 09): burst `count` unrewarded, catchable flies onto the
-- claimant's own lane, staggered a frame apart so they pop in like Unity's
-- zero-delay BugSpawner burst rather than all overlapping in one frame. Works
-- in every run state -- BugService already spawns/accepts catches on idle
-- Menu/Dead lanes (see the per-lane loop above and GameClient's "Start
-- screen: bugs still fly and can be eaten") -- so eating gift flies at the
-- gift button in the main menu needs no extra plumbing.
spawnGiftFlys.Event:Connect(function(player: Player, count: number)
	local laneFolder = lanesFolder:FindFirstChild(tostring(player.UserId))
	local origin = if laneFolder then select(1, laneOriginOf(laneFolder)) else nil
	if not origin then
		return
	end
	task.spawn(function()
		for _ = 1, count do
			if not player.Parent then
				break -- claimant left mid-burst
			end
			spawnBug(origin :: Vector3, player.UserId, origin, false, true)
			task.wait()
		end
	end)
end)
