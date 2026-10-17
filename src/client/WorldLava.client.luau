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
-- Color property, it never creates, moves, resizes or reparents it. The surge
-- swell below is a separate client-only part.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local Bursts = require(script.Parent.world.Bursts)
local Lanes = require(script.Parent.world.Lanes)

local TAU = math.pi * 2

local player = Players.LocalPlayer
local myLane = Lanes.waitForLocal()
local playField = workspace:FindFirstChild("PlayField")
local frogs = if playField then playField:WaitForChild("Frogs", WorldConfig.LANE_WAIT_TIMEOUT) else nil
local myFrog = if frogs then frogs:WaitForChild("Frog_" .. player.UserId, WorldConfig.LANE_WAIT_TIMEOUT) else nil
local stepsFolder = if playField then playField:WaitForChild("Steps", WorldConfig.LANE_WAIT_TIMEOUT) else nil
local lava = if playField then playField:WaitForChild("Lava", WorldConfig.LANE_WAIT_TIMEOUT) else nil
local levelState = player:WaitForChild("LevelState", WorldConfig.LANE_WAIT_TIMEOUT)
if not (myLane and myFrog and myFrog:IsA("Model") and stepsFolder and lava and lava:IsA("BasePart") and levelState) then
	warn("[WorldLava] lane, frog, lava or LevelState never appeared; lava dressing is disabled")
	return
end
local rightLimb = myFrog:WaitForChild("RightLimb", WorldConfig.LANE_WAIT_TIMEOUT)
local leftLimb = myFrog:WaitForChild("LeftLimb", WorldConfig.LANE_WAIT_TIMEOUT)
local body = myFrog.PrimaryPart
if not (body and rightLimb and rightLimb:IsA("BasePart") and leftLimb and leftLimb:IsA("BasePart")) then
	warn("[WorldLava] frog rig incomplete; lava dressing is disabled")
	return
end
local lane: Folder = myLane
local changed = levelState:WaitForChild("Changed", WorldConfig.LANE_WAIT_TIMEOUT) :: BindableEvent

-- ---------------------------------------------------------------------------
-- Heat lift/lower (Lava.cs LiftHeat(isHot)/LowerHeat -- ADAPTED to a Color tween
-- since the original animates a separate heat-haze plane's local Z offset,
-- which has no equivalent geometry in this port's single shared Lava part).
-- Pot is this game's "boiling pot" hazard level -- heat is lifted (hot) there,
-- lowered everywhere else.
-- ---------------------------------------------------------------------------
-- Hot only in Pot AND once the tutorial is fully finished: the level flips to Pot on
-- the 3rd tree, but the lane's TutorialGrace stays true until the first real step
-- is grabbed (b-20261017-133220-hfup).
local function isHot(levelName: string): boolean
	return levelName == "Pot" and lane:GetAttribute("TutorialGrace") ~= true
end

local function setHeat(levelName: string)
	local hot = isHot(levelName)
	local color = if hot then WorldConfig.LAVA_HOT_COLOR else WorldConfig.LAVA_COOL_COLOR
	local time = if hot then WorldConfig.LAVA_HEAT_LIFT_TIME else WorldConfig.LAVA_HEAT_LOWER_TIME
	TweenService:Create(lava, TweenInfo.new(time), { Color = color }):Play()
end

-- Current level name, kept up to date off the attribute signal instead of being
-- re-read every frame.
local currentLevel = ""
local function onLevel(levelName: unknown)
	if typeof(levelName) == "string" then
		currentLevel = levelName
		setHeat(levelName)
	end
end
changed.Event:Connect(onLevel)
onLevel(levelState:GetAttribute("LevelName"))
lane:GetAttributeChangedSignal("TutorialGrace"):Connect(function()
	setHeat(currentLevel)
end)

-- ---------------------------------------------------------------------------
-- Continuous heat build-up (journey 4/8, b-20260923-154344-xac3). No Unity
-- source (LiftHeat/LowerHeat above is a binary per-level switch) --
-- ADAPTED/additive: in Pot, a 0..1 heat scalar rises as the local frog's body
-- nears the lava surface (same WorldConfig.LAVA_PROXIMITY_STUDS range
-- WorldFrogCosmetics' glance-down/tint reaction already uses -- see commit
-- 00b2165) and/or the longer it's been since its last grab (`Held` flipping
-- true on either limb, same attribute WorldFrogCosmetics reads for the hand
-- grip decal) -- standing still should feel like boiling. Published on
-- levelState (the same Folder LevelClient already exposes Background/Overlay
-- on) as attribute "PotHeat" so WorldBackdrop.client.luau -- which owns the
-- Water overlay's opacity and the backdrop's warm tint, both different
-- Instances from this file's own `lava` part -- can read it without the two
-- scripts requiring each other (server scripts never require each other per
-- CLAUDE.md; same reasoning applies client-side). The attribute is only
-- rewritten when the smoothed value moved meaningfully (POT_HEAT_EPSILON), not
-- every frame -- attribute writes aren't free, and a settled heat is the common case.
-- ---------------------------------------------------------------------------
local lastGrabTime = os.clock()
local function trackGrab(limb: BasePart)
	limb:GetAttributeChangedSignal("Held"):Connect(function()
		if limb:GetAttribute("Held") == true then
			lastGrabTime = os.clock()
		end
	end)
end
trackGrab(rightLimb)
trackGrab(leftLimb)

local potHeat = 0
local publishedHeat = -1 -- last value written to the attribute (-1 forces the first write)

local function publishHeat()
	local atEnd = potHeat == 0 or potHeat == 1
	if math.abs(potHeat - publishedHeat) >= WorldConfig.POT_HEAT_EPSILON or (atEnd and potHeat ~= publishedHeat) then
		publishedHeat = potHeat
		levelState:SetAttribute("PotHeat", potHeat)
	end
end

local function updateHeat(dt: number)
	local target = 0
	if isHot(currentLevel) then
		local proximity = 1 - math.clamp((body.Position.Y - Config.LAVA_Y) / WorldConfig.LAVA_PROXIMITY_STUDS, 0, 1)
		local idle = math.clamp((os.clock() - lastGrabTime) / WorldConfig.LAVA_HEAT_IDLE_TIME, 0, 1)
		target = math.clamp(proximity + idle, 0, 1)
	end
	potHeat += (target - potHeat) * math.clamp(dt * WorldConfig.LAVA_HEAT_LERP_RATE, 0, 1)
	if math.abs(target - potHeat) < 1e-3 then
		potHeat = target -- settle exactly, so the attribute stops changing
	end
	publishHeat()
end

-- ---------------------------------------------------------------------------
-- Splash bursts (Entities/Splash.cs: random X impulse + fixed Y impulse +
-- opposing torque, self-destructs after LAVA_SPLASH_LIFETIME; doc 12 §3
-- LavaSplash.prefab's own tuned values live in WorldConfig). Pooled and aged by
-- world/Bursts (no delayed releases).
--
-- `hurt` used to play here too (Lava.cs FallSplash: AudioManager.Instance.
-- PlayForAll(hurtSound)), off this same proxy -- removed (doc 16 §6 follow-up,
-- 2026-09-19): SfxEvents.client.luau now plays `hurt` off the GameOver remote's
-- `cause` argument instead (the real per-death signal, not a proxy), so this
-- was a duplicate. The proxy itself (step-recycled-near-the-despawn-line /
-- frog-Dead) stays -- it's still the only signal this file has for WHERE to
-- place the splash burst below, which is still purely visual.
-- ---------------------------------------------------------------------------
local splashes = Bursts.new({
	name = "LavaSplash",
	size = WorldConfig.LAVA_SPLASH_SIZE,
	material = Enum.Material.Neon,
	sprite = "LavaSplash",
	color = WorldConfig.LAVA_HOT_COLOR,
})

local function splashAt(position: Vector3, count: number)
	splashes.emit(position + Vector3.new(0, WorldConfig.LAVA_SPLASH_LIFT, 0), {
		count = count,
		x = NumberRange.new(WorldConfig.LAVA_SPLASH_MIN_X, WorldConfig.LAVA_SPLASH_MAX_X),
		y = NumberRange.new(WorldConfig.LAVA_SPLASH_Y, WorldConfig.LAVA_SPLASH_Y),
		spin = WorldConfig.LAVA_SPLASH_SPIN,
		jitterX = WorldConfig.LAVA_SPLASH_JITTER_X,
		lifetime = WorldConfig.LAVA_SPLASH_LIFETIME,
		fadeStart = 0.7,
	})
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
	if pos.Y > Config.DESPAWN_Y + WorldConfig.LAVA_FALL_SPLASH_MARGIN then
		return
	end
	if not Lanes.inXBand(Lanes.originOf(lane), pos.X, WorldConfig.SCENERY_BOUNDS_MARGIN) then
		return
	end
	-- burst on the lava SURFACE, not at the recycle line: Step.cs's own call is
	-- `lava.Splash(new Vector2(transform.position.x, -50f), ...)` -- the step is
	-- recycled at the bottom net (Config.DESPAWN_Y) but the splash is drawn at
	-- Unity's -50 u = Config.LAVA_Y, which is the visible bottom of the band.
	splashAt(Vector3.new(pos.X, Config.LAVA_Y, pos.Z), WorldConfig.LAVA_SPLASH_COUNT)
end)

-- The local frog sinking onto the lava (server sets Dead=true at Config.LAVA_Y).
myFrog:GetAttributeChangedSignal("Dead"):Connect(function()
	if myFrog:GetAttribute("Dead") == true then
		splashAt(Vector3.new(body.Position.X, Config.LAVA_Y, body.Position.Z), WorldConfig.LAVA_SPLASH_COUNT)
	end
end)

-- ---------------------------------------------------------------------------
-- Lava surges (Pot only, ADAPTED/additive -- no Unity source). As PotHeat rises
-- the lava surface visibly swells and pulses, and now and then throws Flame2
-- embers and a couple of splash chunks. Strictly a visual warning: the swell is
-- a client-only strip standing at most SURGE_MAX_RISE (~1 stud) above
-- Config.LAVA_Y, and neither it nor the embers touch the real Lava part or the
-- death line (the server's LAVA_Y/DEATH rule is unchanged). It sits just behind
-- the Lava part's back face, so only the part above the lava's top edge shows.
-- ---------------------------------------------------------------------------
local swell = Instance.new("Part")
swell.Name = "LavaSwell"
swell.Anchored = true
swell.CanCollide = false
swell.CanQuery = false -- must never eat a tap
swell.CanTouch = false
swell.Material = Enum.Material.Neon
swell.Color = WorldConfig.SURGE_COLOR
swell.Size = Vector3.new(WorldConfig.SURGE_WIDTH, 0.1, 0.2)
swell.Transparency = 1
swell.Parent = workspace

local embers = Bursts.new({
	name = "LavaEmber",
	size = WorldConfig.SURGE_EMBER_SIZE,
	material = Enum.Material.Neon,
	sprite = "Flame2",
	color = WorldConfig.SURGE_COLOR,
})

local surgePhase = 0
local swellShown = false
local nextBurst = WorldConfig.SURGE_BURST_INTERVAL_CALM

local function updateSurge(dt: number)
	local heat = potHeat
	if heat < WorldConfig.SURGE_MIN_HEAT then
		if swellShown then
			swell.Transparency = 1
			swellShown = false
		end
		nextBurst = WorldConfig.SURGE_BURST_INTERVAL_CALM
		return
	end
	swellShown = true

	-- the pulse quickens as it heats up
	local period = WorldConfig.SURGE_PULSE_PERIOD_CALM
		+ (WorldConfig.SURGE_PULSE_PERIOD - WorldConfig.SURGE_PULSE_PERIOD_CALM) * heat
	surgePhase = (surgePhase + dt * TAU / period) % TAU
	local wave = 0.5 + 0.5 * math.sin(surgePhase)
	local rise =
		math.min(WorldConfig.SURGE_MAX_RISE, heat * (WorldConfig.SURGE_BASE_RISE + WorldConfig.SURGE_PULSE_RISE * wave))
	local originX = Lanes.originOf(lane).X
	swell.Size = Vector3.new(WorldConfig.SURGE_WIDTH, math.max(rise, 0.05), 0.2)
	swell.CFrame = CFrame.new(originX, Config.LAVA_Y + rise / 2, Config.PLANE_Z + WorldConfig.SURGE_Z)
	swell.Color = WorldConfig.LAVA_HOT_COLOR:Lerp(WorldConfig.SURGE_COLOR, wave)
	swell.Transparency = WorldConfig.SURGE_TRANSPARENCY_CALM
		+ (WorldConfig.SURGE_TRANSPARENCY_HOT - WorldConfig.SURGE_TRANSPARENCY_CALM) * heat

	if heat >= WorldConfig.SURGE_BURST_MIN_HEAT then
		nextBurst -= dt
		if nextBurst <= 0 then
			local t = (heat - WorldConfig.SURGE_BURST_MIN_HEAT) / (1 - WorldConfig.SURGE_BURST_MIN_HEAT)
			local interval = WorldConfig.SURGE_BURST_INTERVAL_CALM
				+ (WorldConfig.SURGE_BURST_INTERVAL_HOT - WorldConfig.SURGE_BURST_INTERVAL_CALM) * t
			nextBurst = interval * (0.6 + math.random() * 0.8)
			local x = body.Position.X + (math.random() * 2 - 1) * WorldConfig.SURGE_BURST_SPREAD
			local at = Vector3.new(x, Config.LAVA_Y + rise, Config.PLANE_Z)
			embers.emit(at, {
				count = WorldConfig.SURGE_EMBER_COUNT,
				x = WorldConfig.SURGE_EMBER_VX,
				y = WorldConfig.SURGE_EMBER_VY,
				lifetime = WorldConfig.SURGE_EMBER_LIFETIME,
				jitterX = WorldConfig.LAVA_SPLASH_JITTER_X,
				fadeStart = 0.4,
			})
			splashAt(at, WorldConfig.SURGE_SPLASH_COUNT)
		end
	else
		nextBurst = WorldConfig.SURGE_BURST_INTERVAL_CALM
	end
end

-- Per-frame visuals on PreRender (not Heartbeat): the heat scalar and the swell
-- only matter in the frame they are drawn.
RunService.PreRender:Connect(function(dt: number)
	updateHeat(dt)
	updateSurge(dt)
end)
