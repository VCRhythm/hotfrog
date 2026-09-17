-- ServerScriptService/Server/BugService (Script)
-- The bug collectible loop (../../docs/roblox-port/06-bugs-and-tongue.md; ports
-- Entities/Bug.cs + Spawning/BugSpawner.cs): bugs drift in from an edge, idle for
-- a lifespan, then leave -- unless a player taps one, in which case the server
-- validates the catch, awards Flys through the shared AwardFlys faucet (Bug.cs
-- CollectFly -> the Fly currency), and tells the catcher for tongue/squish
-- feedback. Bugs are pooled with the same Gen guard as steps so the delayed
-- leave timer can't act on a recycled part.

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
	part.Color = Color3.fromRGB(60, 60, 60)
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Front
	decal:SetAttribute("Sprite", "Bug") -- Sprites/Other/Bug.png via SkinAssets
	decal.Parent = part
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
local function spawnBug(origin: Vector3?)
	local bug = (table.remove(pool) or template:Clone()) :: BasePart
	bug:SetAttribute("Kind", "Bug")
	bug:SetAttribute("Gen", ((bug:GetAttribute("Gen") :: number?) or 0) + 1)
	bug.Anchored = true
	SpriteSkin.apply(bug) -- no-op until ids land in SkinAssets
	local gen = bug:GetAttribute("Gen")

	local dest: Vector3
	if origin then
		bug.CFrame = CFrame.new(origin)
		local wanderX = math.random(-Config.BUG_NEAR_WANDER_X, Config.BUG_NEAR_WANDER_X)
		local wanderY = math.random(-Config.BUG_NEAR_WANDER_Y, Config.BUG_NEAR_WANDER_Y)
		dest = Vector3.new(
			math.clamp(origin.X + wanderX, -Config.BUG_X_RANGE, Config.BUG_X_RANGE),
			math.clamp(origin.Y + wanderY, -Config.BUG_Y_RANGE, Config.BUG_Y_RANGE),
			Config.PLANE_Z
		)
	else
		-- enter from a side edge, drift to a random on-screen point with the
		-- original's overshoot feel (Bug.SetUpDestination / MoveTo: DOMove + Ease.OutBack)
		local side = if math.random() > 0.5 then 1 else -1
		bug.CFrame = CFrame.new(
			side * (Config.BUG_X_RANGE + 6),
			math.random(-Config.BUG_Y_RANGE, Config.BUG_Y_RANGE),
			Config.PLANE_Z
		)
		dest = Vector3.new(
			math.random(-Config.BUG_X_RANGE, Config.BUG_X_RANGE),
			math.random(-Config.BUG_Y_RANGE, Config.BUG_Y_RANGE),
			Config.PLANE_Z
		)
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
		local exitX = (if math.random() > 0.5 then 1 else -1) * (Config.BUG_X_RANGE + 10)
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

task.spawn(function()
	while true do
		spawnBug()
		task.wait(Config.BUG_INTERVAL)
	end
end)

spawnBugAt.Event:Connect(function(position: Vector3)
	spawnBug(position)
end)

-- ---------------------------------------------------------------------------
-- Catching. No reach gate on purpose: the tongue spans the whole screen in the
-- original (Controller.TouchBug works on anything tappable). Validation is
-- "a real, still-active bug" -- the server owns the bug set, so a stale tap on
-- an already-departed bug simply doesn't score.
-- ---------------------------------------------------------------------------
CatchBug.OnServerEvent:Connect(function(player, bug)
	if typeof(bug) ~= "Instance" or not bug:IsA("BasePart") or not active[bug] then
		return
	end
	local position = bug.Position
	releaseBug(bug)
	awardFlys:Fire(player, Config.BUG_FLYS)
	BugCaught:FireClient(player, position) -- feedback hook (squish sound / flash)
end)
