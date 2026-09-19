--!strict
-- StarterPlayerScripts/Client/WorldLava (LocalScript)
-- Phase 4 world dressing, item 3: lava heat animation (Entities/Lava.cs
-- LiftHeat/LowerHeat) and splash bursts (Lava.cs Splash / Entities/Splash.cs)
-- when a step or the local frog drops past the bottom. Scoped to the local
-- player's own lane (same reasoning as WorldBackdrop -- the camera only ever
-- looks at `myLane`).
--
-- Detection is entirely local/cheap: GameServer.server.luau recycles a step by
-- setting its Parent to nil (pooling, never Destroy), so `Steps.ChildRemoved`
-- fires for every recycle; a step whose last known position was at/below the
-- despawn line AND inside this lane's X band is treated as "fell into the
-- lava" (cheap proxy -- crumble/explode recycles happen at the frog's height,
-- almost never down at DESPAWN_Y, so they don't false-trigger). The frog's own
-- fall is read straight off its `Dead` attribute flipping true.
--
-- workspace.PlayField.Lava already exists (src/workspace/PlayField.model.json,
-- outside this phase's ownership) -- this script only tweens its existing
-- Color property, it never creates or reparents it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local Pool = require(script.Parent.world.Pool)

local player = Players.LocalPlayer
local playField = workspace:WaitForChild("PlayField")
local myLane = playField:WaitForChild("Lanes"):WaitForChild(tostring(player.UserId), math.huge) :: Folder
local myFrog = playField:WaitForChild("Frogs"):WaitForChild("Frog_" .. player.UserId, math.huge) :: Model
local body = myFrog.PrimaryPart :: BasePart
local stepsFolder = playField:WaitForChild("Steps")
local lava = playField:WaitForChild("Lava") :: BasePart

local levelState = player:WaitForChild("LevelState", math.huge) :: Folder
local changed = levelState:WaitForChild("Changed") :: BindableEvent

local function laneOrigin(): Vector3
	local origin = myLane:GetAttribute("Origin")
	return if typeof(origin) == "Vector3" then origin else Vector3.new(0, 0, 0)
end

-- ---------------------------------------------------------------------------
-- Heat lift/lower (Lava.cs LiftHeat(isHot)/LowerHeat -- ADAPTED to a Color tween
-- since the original animates a separate heat-haze plane's local Z offset,
-- which has no equivalent geometry in this port's single shared Lava part).
-- Pot is this game's "boiling pot" hazard level -- heat is lifted (hot) there,
-- lowered everywhere else.
-- ---------------------------------------------------------------------------
local function setHeat(levelName: string)
	local hot = levelName == "Pot"
	local color = if hot then WorldConfig.LAVA_HOT_COLOR else WorldConfig.LAVA_COOL_COLOR
	local time = if hot then WorldConfig.LAVA_HEAT_LIFT_TIME else WorldConfig.LAVA_HEAT_LOWER_TIME
	TweenService:Create(lava, TweenInfo.new(time), { Color = color }):Play()
end

changed.Event:Connect(function(levelName)
	if typeof(levelName) == "string" then
		setHeat(levelName)
	end
end)
do
	local levelName = levelState:GetAttribute("LevelName")
	if typeof(levelName) == "string" then
		setHeat(levelName)
	end
end

-- ---------------------------------------------------------------------------
-- Splash bursts (Entities/Splash.cs: random X impulse + fixed Y impulse +
-- opposing torque, self-destructs after LAVA_SPLASH_LIFETIME; doc 12 §3
-- LavaSplash.prefab's own tuned values live in WorldConfig)
-- ---------------------------------------------------------------------------
local splashPool = Pool.new(function(): BasePart
	local part = Instance.new("Part")
	part.Name = "LavaSplash"
	part.Size = Vector3.new(0.6, 0.6, 0.3)
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = WorldConfig.LAVA_HOT_COLOR
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Front
	decal:SetAttribute("Sprite", "LavaSplash")
	decal.Parent = part
	SpriteSkin.apply(part)
	return part
end, function(part: BasePart)
	part.Anchored = true
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.Parent = nil
end)

-- `hurt` used to play here too (Lava.cs FallSplash: AudioManager.Instance.
-- PlayForAll(hurtSound)), off this same proxy -- removed (doc 16 §6 follow-up,
-- 2026-09-19): SfxEvents.client.luau now plays `hurt` off the GameOver remote's
-- `cause` argument instead (the real per-death signal, not a proxy), so this
-- was a duplicate. The proxy itself (step-recycled-near-the-despawn-line /
-- frog-Dead) stays -- it's still the only signal this file has for WHERE to
-- place the splash burst below, which is still purely visual.
local function splashAt(position: Vector3)
	for _ = 1, WorldConfig.LAVA_SPLASH_COUNT do
		local part = splashPool.acquire()
		part.CFrame = CFrame.new(position + Vector3.new((math.random(-10, 10)) / 10, 0.2, 0))
		part.Anchored = false
		local xForce = WorldConfig.LAVA_SPLASH_MIN_X
			+ math.random() * (WorldConfig.LAVA_SPLASH_MAX_X - WorldConfig.LAVA_SPLASH_MIN_X)
		part.AssemblyLinearVelocity = Vector3.new(xForce, WorldConfig.LAVA_SPLASH_Y, 0)
		part.AssemblyAngularVelocity = Vector3.new(0, 0, if xForce >= 0 then -4 else 4)
		part.Parent = workspace
		task.delay(WorldConfig.LAVA_SPLASH_LIFETIME, function()
			if part.Parent then
				splashPool.release(part)
			end
		end)
	end
end

-- Steps: recycled parts are Parent=nil, never Destroy()'d (GameServer's pool) --
-- ChildRemoved fires for every one; filter to "was near the bottom, in my
-- lane's X band" so crumble/explode/knock-off recycles (which happen up at the
-- frog's height) don't false-trigger a splash.
stepsFolder.ChildRemoved:Connect(function(child)
	if not child:IsA("BasePart") then
		return
	end
	local pos: Vector3 = child.Position
	if pos.Y > Config.DESPAWN_Y + 3 then
		return
	end
	local origin = laneOrigin()
	if math.abs(pos.X - origin.X) > Config.LANE_HALF_WIDTH + WorldConfig.SCENERY_BOUNDS_MARGIN then
		return
	end
	splashAt(Vector3.new(pos.X, Config.DESPAWN_Y, pos.Z))
end)

-- The local frog dropping past the bottom (server sets Dead=true at that point).
myFrog:GetAttributeChangedSignal("Dead"):Connect(function()
	if myFrog:GetAttribute("Dead") == true then
		splashAt(Vector3.new(body.Position.X, Config.DESPAWN_Y, body.Position.Z))
	end
end)
