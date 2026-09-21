-- ServerScriptService/Server/BugService (Script)
-- The bug collectible loop (../../docs/roblox-port/06-bugs-and-tongue.md; ports
-- Entities/Bug.cs + Spawning/BugSpawner.cs): bugs drift in from an edge, idle for
-- a lifespan, then leave -- unless a player taps one, in which case the server
-- validates the catch, awards Flys through the shared AwardFlys faucet (Bug.cs
-- CollectFly -> the Fly currency), and tells the catcher for tongue/squish
-- feedback. Bugs are pooled with the same Gen guard as steps so the delayed
-- leave timer can't act on a recycled part.
--
-- Per-lane (doc 13 item 7): each occupied lane runs its own spawn cadence and
-- picks positions relative to that lane's origin, and a bug is tagged with its
-- lane's UserId so only that lane's player can catch it. Lanes are discovered
-- through `workspace.PlayField.Lanes`' child Folders and their `UserId`/`Origin`
-- attributes (Lane.luau sets these) -- this script deliberately never requires
-- server/Lane.luau or GameServer, so load order between them is moot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

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
-- Pool + lifecycle
-- ---------------------------------------------------------------------------
local pool: { BasePart } = {}
local active: { [BasePart]: boolean } = {}
local currentTween: { [BasePart]: Tween } = {}

local function releaseBug(bug: BasePart)
	if not active[bug] then
		return -- idempotent: catch and the leave timer can race
	end
	local tween = currentTween[bug]
	if tween then
		tween:Cancel() -- a live tween must not keep writing to a pooled part
		currentTween[bug] = nil
	end
	active[bug] = nil
	bug.Parent = nil
	table.insert(pool, bug)
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
	local bug = (table.remove(pool) or template:Clone()) :: BasePart
	bug:SetAttribute("Kind", "Bug")
	bug:SetAttribute("Gen", ((bug:GetAttribute("Gen") :: number?) or 0) + 1)
	bug:SetAttribute("LaneUserId", laneUserId)
	bug:SetAttribute("Reward", reward ~= false)
	bug.Anchored = true
	SpriteSkin.apply(bug) -- no-op until ids land in SkinAssets
	local gen = bug:GetAttribute("Gen")

	local minX, maxX = laneOrigin.X - Config.BUG_X_RANGE, laneOrigin.X + Config.BUG_X_RANGE

	local dest: Vector3
	if origin and wideBurst then
		bug.CFrame = CFrame.new(origin)
		dest =
			Vector3.new(math.random(minX, maxX), math.random(-Config.BUG_Y_RANGE, Config.BUG_Y_RANGE), Config.PLANE_Z)
	elseif origin then
		bug.CFrame = CFrame.new(origin)
		local wanderX = math.random(-Config.BUG_NEAR_WANDER_X, Config.BUG_NEAR_WANDER_X)
		local wanderY = math.random(-Config.BUG_NEAR_WANDER_Y, Config.BUG_NEAR_WANDER_Y)
		dest = Vector3.new(
			math.clamp(origin.X + wanderX, minX, maxX),
			math.clamp(origin.Y + wanderY, -Config.BUG_Y_RANGE, Config.BUG_Y_RANGE),
			Config.PLANE_Z
		)
	else
		-- enter from a side edge, drift to a random on-screen point with the
		-- original's overshoot feel (Bug.SetUpDestination / MoveTo: DOMove + Ease.OutBack)
		local side = if math.random() > 0.5 then 1 else -1
		bug.CFrame = CFrame.new(
			laneOrigin.X + side * (Config.BUG_X_RANGE + 6),
			math.random(-Config.BUG_Y_RANGE, Config.BUG_Y_RANGE),
			Config.PLANE_Z
		)
		dest =
			Vector3.new(math.random(minX, maxX), math.random(-Config.BUG_Y_RANGE, Config.BUG_Y_RANGE), Config.PLANE_Z)
	end
	bug.Parent = container
	active[bug] = true

	local enter = TweenService:Create(
		bug,
		TweenInfo.new(Config.BUG_ENTER_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(dest) }
	)
	currentTween[bug] = enter
	enter:Play()

	-- after its lifespan, leave unless caught (Bug.Leave)
	task.delay(Config.BUG_ENTER_TIME + Config.BUG_LIFESPAN, function()
		if not (active[bug] and bug:GetAttribute("Gen") == gen) then
			return
		end
		local exitX = laneOrigin.X + (if math.random() > 0.5 then 1 else -1) * (Config.BUG_X_RANGE + 10)
		local leave = TweenService:Create(
			bug,
			TweenInfo.new(Config.BUG_LEAVE_TIME),
			{ CFrame = CFrame.new(exitX, bug.Position.Y, Config.PLANE_Z) }
		)
		currentTween[bug] = leave
		leave.Completed:Once(function()
			if active[bug] and bug:GetAttribute("Gen") == gen then
				releaseBug(bug)
			end
		end)
		leave:Play()
	end)
end

-- ---------------------------------------------------------------------------
-- Per-lane discovery + spawn cadence (doc 13 item 7). Lane.luau creates one
-- Folder per lane under `workspace.PlayField.Lanes` carrying `UserId`/`Origin`
-- attributes; this script only ever reads those, never server/Lane.luau or
-- GameServer directly, so load order between the three is moot.
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
				spawnBug(origin, userId)
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
	if typeof(bug) ~= "Instance" or not bug:IsA("BasePart") or not active[bug] then
		return
	end
	if bug:GetAttribute("LaneUserId") ~= player.UserId then
		return
	end
	local reward = bug:GetAttribute("Reward") ~= false -- false only for gift flies (see spawnBug)
	local position = bug.Position
	releaseBug(bug)
	if reward then
		awardFlys:Fire(player, Config.BUG_FLYS)
		bugCaughtServer:Fire(player) -- GameServer's exact bugsThisRun counter (doc 17 gap)
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
