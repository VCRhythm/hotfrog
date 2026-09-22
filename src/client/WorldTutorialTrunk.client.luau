--!strict
-- StarterPlayerScripts/Client/WorldTutorialTrunk (LocalScript)
-- Renders the big tree trunk + leaves Unity's TutorialFirstTree/SecondTree/
-- LastTree prefabs draw behind their "Acorn" Step child (doc 12 "Tree
-- prefabs" section): child "Branch" (Scenery.cs, Sprites/Other/branch3.png)
-- and Branch's own child "Leaves" (Sprites/Other/branch2.png, no script).
-- StepKinds.luau only carries the Acorn's own sprite/hitbox (the tree's
-- grabbable part), so this purely cosmetic trunk was never ported
-- (b-20260922-101449-30jz).
--
-- Doc 12's prefab dump gives every tree child's sprite but not Branch/
-- Leaves' own localPosition -- only Scenery.cs's hasMaxY/maxY scroll-despawn
-- threshold (a world-Y recycle bound, not a placement offset), which isn't
-- recoverable as an X/Y offset from the Acorn. So, same as every other
-- non-centre-pivot sprite this port already renders canvas-centred (doc 17
-- "Sprite pivots / non-centre alignment" lists Grass/Castle/Rocket/
-- LavaSplash/Flame/branch2/branch3 together), Branch and Leaves are centred
-- on the Acorn step's own position instead of an unrecoverable Unity offset.
--
-- Purely cosmetic, client-only, same shape as this file's sibling
-- WorldTutorialSpecks.client.luau: watches workspace.PlayField.Steps for
-- steps whose replicated `Sprite` attribute is "Acorn" -- the only
-- StepKinds entries that use it are the three Tutorial tree kinds
-- (TutorialFirstTree/SecondTree/LastTree) -- and keeps a pair of Decal parts
-- glued to that step's position every frame, well behind the shared Z 0
-- gameplay plane (Config.PLANE_Z) so both the acorn and the frog draw in
-- front of it (doc 17: camera at +Z looks down -Z, higher Z = more in
-- front, same direction WorldScenery's z=-1 dressing and WorldBackdrop's
-- PLANE_Z-3/4/5 layers already use).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)

local playField = workspace:WaitForChild("PlayField")
local stepsFolder = playField:WaitForChild("Steps")

-- Sprite canvas: 256px @ spritePixelsToUnits=2 (branch2.png.meta and
-- branch3.png.meta both agree) * Config.UNITY_TO_STUDS -- the same
-- "size = the sprite's whole Unity canvas" rule StepKinds/SceneryKinds use
-- everywhere else (128 * 55/175 studs).
local TRUNK_SIZE = Vector3.new(40.229, 40.229, 0.6)

-- Behind the shared Z 0 gameplay plane both the Acorn step and the frog sit
-- on (Config.PLANE_Z). Leaves sits slightly in front of Branch (foliage in
-- front of bark) but both stay well behind the acorn/frog.
local BRANCH_Z = Config.PLANE_Z - 2
local LEAVES_Z = Config.PLANE_Z - 1.5

type TrunkCosmetic = { branch: BasePart, leaves: BasePart }
local tracked: { [BasePart]: TrunkCosmetic } = {}

local function createPart(name: string, sprite: string): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = TRUNK_SIZE
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.SmoothPlastic
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
	decal:SetAttribute("Sprite", sprite)
	decal.Parent = part
	SpriteSkin.apply(part)
	-- Same rule as WorldScenery.createSceneryPart: the part is the sprite's
	-- whole (padded) canvas, so it must not show as a box behind the art.
	-- Only hide it once the sprite actually resolved (SkinAssets id 0 leaves
	-- Texture empty), keeping a visible placeholder for un-uploaded art.
	part.Transparency = if decal.Texture ~= "" then 1 else 0
	part.Parent = workspace
	return part
end

local function onStepAdded(step: BasePart)
	if tracked[step] or step:GetAttribute("Sprite") ~= "Acorn" then
		return
	end
	local branch = createPart("TutorialTreeBranch", "branch3")
	local leaves = createPart("TutorialTreeLeaves", "branch2")
	local pos = step.Position
	branch.Position = Vector3.new(pos.X, pos.Y, BRANCH_Z)
	leaves.Position = Vector3.new(pos.X, pos.Y, LEAVES_Z)
	tracked[step] = { branch = branch, leaves = leaves }
end

local function onStepRemoved(step: BasePart)
	local cosmetic = tracked[step]
	if not cosmetic then
		return
	end
	tracked[step] = nil
	cosmetic.branch:Destroy()
	cosmetic.leaves:Destroy()
end

for _, child in stepsFolder:GetChildren() do
	if child:IsA("BasePart") then
		onStepAdded(child)
	end
end
stepsFolder.ChildAdded:Connect(function(child)
	if child:IsA("BasePart") then
		onStepAdded(child)
	end
end)
stepsFolder.ChildRemoved:Connect(function(child)
	if child:IsA("BasePart") then
		onStepRemoved(child :: BasePart)
	end
end)

-- Steps ride the lane's own pull tween (GameServer.pullLane), so the trunk
-- has to chase the step's replicated Position every frame rather than snap
-- once at creation -- same technique WorldTutorialSpecks uses to follow its
-- target step.
RunService.Heartbeat:Connect(function()
	for step, cosmetic in tracked do
		local pos = step.Position
		cosmetic.branch.Position = Vector3.new(pos.X, pos.Y, BRANCH_Z)
		cosmetic.leaves.Position = Vector3.new(pos.X, pos.Y, LEAVES_Z)
	end
end)
