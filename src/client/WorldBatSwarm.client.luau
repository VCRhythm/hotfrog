--!strict
-- StarterPlayerScripts/Client/WorldBatSwarm (LocalScript)
-- Halloween bat swarm (b-20261016-125004-mog8, idea 10, the cosmetic version;
-- port-only, doc 17): while SpriteSkin.halloweenLive, every FLOCK_INTERVAL seconds a
-- flock of bats flaps fast across the LOCAL lane from one side to the other, then is
-- destroyed. Pure decoration: the bats are client-made, anchored, CanQuery=false
-- parts (never catchable, no Flys, no remote), drawn just behind the step plane so
-- they never cover a step or the frog. The Bat kind's sprite/size/z live in
-- Shared/SceneryKinds.luau. Cosmetic only: never touches a server-owned part.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SceneryKinds = require(ReplicatedStorage.Shared.SceneryKinds)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local Lanes = require(script.Parent.world.Lanes)

local BAT = SceneryKinds.defs.Bat
local FLOCK_INTERVAL_MIN = 25 -- seconds between flocks
local FLOCK_INTERVAL_MAX = 45
local FIRST_FLOCK_DELAY = 4 -- seconds after the window opens (or ForceHalloween flips on)
local FLOCK_SIZE_MIN = 7
local FLOCK_SIZE_MAX = 11
local SPEED_MIN = 20 -- studs/s across the lane
local SPEED_MAX = 28
local EDGE = Config.LANE_HALF_WIDTH + 12 -- enter/leave this far from the lane centre (off screen)
local SPREAD_X = 9 -- the flock trails its leader by up to this many studs
local SPREAD_Y = 3.5 -- +/- vertical scatter inside the flock
local FLAP_PERIOD = 0.2 -- seconds per wing beat (squashes the sprite's height)
local BOB = 0.6 -- studs of per-bat bob
local BOB_PERIOD = 0.7

type Bat = {
	part: BasePart,
	offset: Vector2, -- position inside the flock
	speedScale: number,
	scale: number,
	phase: number,
}

type Flock = {
	bats: { Bat },
	dir: number, -- +1 flies to the right, -1 to the left
	baseY: number, -- height above the lane origin at launch
	climb: number, -- studs/s of vertical drift (a slight diagonal sweep)
	speed: number,
	age: number,
}

local folder = Instance.new("Folder")
folder.Name = "HalloweenBats"
folder.Parent = workspace

local localUserId = tostring(Players.LocalPlayer.UserId)
local localLane: Folder? = nil
local flock: Flock? = nil
local live = SpriteSkin.halloweenLive()
local nextFlock = if live then os.clock() + FIRST_FLOCK_DELAY else math.huge

local function makeBat(): BasePart
	local part = Instance.new("Part")
	part.Name = "Bat"
	part.Size = BAT.size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = BAT.colors[1] or Color3.new(0, 0, 0)
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
	decal:SetAttribute("Sprite", BAT.sprite)
	decal.Parent = part
	SpriteSkin.apply(part)
	-- the part is the sprite's whole canvas: hide the box once the art resolved
	part.Transparency = if decal.Texture ~= "" then 1 else 0
	return part
end

local function launch()
	local bats: { Bat } = {}
	for _ = 1, math.random(FLOCK_SIZE_MIN, FLOCK_SIZE_MAX) do
		local part = makeBat()
		part.Parent = folder
		table.insert(bats, {
			part = part,
			offset = Vector2.new(math.random() * SPREAD_X, (math.random() * 2 - 1) * SPREAD_Y),
			speedScale = 0.9 + math.random() * 0.2,
			scale = 0.7 + math.random() * 0.4,
			phase = math.random() * math.pi * 2,
		})
	end
	flock = {
		bats = bats,
		dir = if math.random() < 0.5 then 1 else -1,
		baseY = -4 + math.random() * 14,
		climb = (math.random() * 2 - 1) * 3,
		speed = SPEED_MIN + math.random() * (SPEED_MAX - SPEED_MIN),
		age = 0,
	}
end

local function clearFlock()
	local current = flock
	if current then
		for _, bat in current.bats do
			bat.part:Destroy()
		end
	end
	flock = nil
end

-- Advance the flock one frame; false once every bat has left the far edge.
local function stepFlock(current: Flock, origin: Vector3, dt: number): boolean
	current.age += dt
	local t = current.age
	local anyIn = false
	for _, bat in current.bats do
		local travel = t * current.speed * bat.speedScale - bat.offset.X
		if travel < 2 * EDGE then
			anyIn = true
		end
		local x = origin.X + current.dir * (travel - EDGE)
		local y = origin.Y
			+ current.baseY
			+ current.climb * t
			+ bat.offset.Y
			+ math.sin(bat.phase + t * math.pi * 2 / BOB_PERIOD) * BOB
		local flap = 0.35 + 0.65 * math.abs(math.cos(bat.phase + t * math.pi / FLAP_PERIOD))
		local part = bat.part
		part.Size = Vector3.new(BAT.size.X * bat.scale, BAT.size.Y * bat.scale * flap, BAT.size.Z)
		part.CFrame = CFrame.new(x, y, origin.Z + BAT.z) * CFrame.Angles(0, 0, math.rad(current.dir * -8))
	end
	return anyIn
end

-- Window flips (the ForceHalloween test attribute, or the date rolling over).
local function recheck()
	local now = SpriteSkin.halloweenLive()
	if now == live then
		return
	end
	live = now
	nextFlock = if live then os.clock() + FIRST_FLOCK_DELAY else math.huge
end
workspace:GetAttributeChangedSignal("ForceHalloween"):Connect(recheck)
task.spawn(function()
	while true do
		task.wait(60)
		recheck()
	end
end)

RunService.PreRender:Connect(function(dt: number)
	local lane = localLane
	if not lane then
		return
	end
	if not flock and live and os.clock() >= nextFlock then
		launch()
		nextFlock = os.clock() + FLOCK_INTERVAL_MIN + math.random() * (FLOCK_INTERVAL_MAX - FLOCK_INTERVAL_MIN)
	end
	-- a flock already in the air finishes its pass even if the window just shut
	local current = flock
	if current and not stepFlock(current, Lanes.originOf(lane), dt) then
		clearFlock()
	end
end)

-- Last: Lanes.observe waits for workspace.PlayField.Lanes to replicate.
Lanes.observe(function(lane: Folder)
	if lane.Name == localUserId then
		localLane = lane
	end
end, function(lane: Folder)
	if lane == localLane then
		localLane = nil
		clearFlock()
	end
end)
