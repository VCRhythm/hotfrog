--!strict
-- StarterPlayerScripts/Client/WorldTutorialSpecks (LocalScript)
-- Phase 4 world dressing, item 8: guidance specks (Entities/Speck.cs +
-- SpeckManager.cs) orbiting the next tutorial tree step, for every lane
-- currently on the Tutorial level (doc 13: one lane per player, so this covers
-- everyone mid-tutorial, not just the local player).
--
-- "Next step" is the nearest currently-active step in that lane to its frog --
-- since a grab pulls the WHOLE lane (including its still-standing tree steps)
-- toward the frog, the nearest one is always the one to climb next, and it
-- naturally updates as steps are climbed without needing a dedicated remote
-- (world/GrabTarget.nearestStep, reused from the frog-cosmetics heuristic).
-- ADAPTED down from Unity's 100-speck pool (WorldConfig.SPECK_COUNT) -- a
-- handful reads the same as guidance and is far cheaper.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local GrabTarget = require(script.Parent.world.GrabTarget)

local playField = workspace:WaitForChild("PlayField")
local lanesFolder = playField:WaitForChild("Lanes")
local frogsFolder = playField:WaitForChild("Frogs")
local stepsFolder = playField:WaitForChild("Steps")

type SpeckInst = { part: BasePart, angle: number, center: Vector3 }
type LaneSpecks = {
	userId: number,
	specks: { SpeckInst },
	target: Vector3?,
	nextPoll: number,
}

local lanes: { [Folder]: LaneSpecks } = {}

local function createSpeckPart(): BasePart
	local part = Instance.new("Part")
	part.Name = "Speck"
	part.Size = WorldConfig.SPECK_SIZE
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = WorldConfig.SPECK_COLORS[math.random(1, #WorldConfig.SPECK_COLORS)]
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
	decal:SetAttribute("Sprite", "Speck")
	decal.Parent = part
	SpriteSkin.apply(part)
	return part
end

local function ensureSpecks(folder: Folder): LaneSpecks
	local existing = lanes[folder]
	if existing then
		return existing
	end
	local userIdAttr = folder:GetAttribute("UserId")
	local userId: number = if typeof(userIdAttr) == "number" then userIdAttr else 0

	local specks: { SpeckInst } = {}
	for i = 1, WorldConfig.SPECK_COUNT do
		local part = createSpeckPart()
		part.Parent = workspace
		table.insert(specks, {
			part = part,
			angle = (i / WorldConfig.SPECK_COUNT) * math.pi * 2,
			center = Vector3.zero,
		})
	end

	local laneSpecks: LaneSpecks = { userId = userId, specks = specks, target = nil, nextPoll = 0 }
	lanes[folder] = laneSpecks
	return laneSpecks
end

local function teardownSpecks(folder: Folder)
	local laneSpecks = lanes[folder]
	if not laneSpecks then
		return
	end
	lanes[folder] = nil
	for _, speck in laneSpecks.specks do
		speck.part:Destroy()
	end
end

local function onLevelChanged(folder: Folder)
	local levelAttr = folder:GetAttribute("Level")
	if levelAttr == "Tutorial" then
		ensureSpecks(folder)
	else
		teardownSpecks(folder)
	end
end

local function trackLane(folder: Folder)
	onLevelChanged(folder)
	folder:GetAttributeChangedSignal("Level"):Connect(function()
		onLevelChanged(folder)
	end)
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
		teardownSpecks(child)
	end
end)

RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()
	for _, laneSpecks in lanes do
		if now >= laneSpecks.nextPoll then
			laneSpecks.nextPoll = now + WorldConfig.NEAREST_STEP_POLL_INTERVAL
			local frogModel = frogsFolder:FindFirstChild("Frog_" .. laneSpecks.userId)
			local from: Vector3? = nil
			if frogModel and frogModel:IsA("Model") and frogModel.PrimaryPart then
				from = frogModel.PrimaryPart.Position
			end
			if from then
				local nearest = GrabTarget.nearestStep(stepsFolder, laneSpecks.userId, from)
				laneSpecks.target = if nearest then nearest.Position else from
			end
		end

		local target = laneSpecks.target
		if target then
			local alpha = math.clamp(dt / WorldConfig.SPECK_MOVE_TIME, 0, 1)
			for _, speck in laneSpecks.specks do
				speck.angle += WorldConfig.SPECK_ROTATE_SPEED * dt
				local offset = Vector3.new(math.cos(speck.angle), math.sin(speck.angle), 0) * WorldConfig.SPECK_RADIUS
				speck.center = speck.center:Lerp(target, alpha)
				speck.part.Position = speck.center + offset
			end
		end
	end
end)
