--!strict
-- StarterPlayerScripts/Client/WorldTutorialTrunk (LocalScript)
-- Draws the Tutorial's oak tree, the one the three "Acorn" steps
-- (StepKinds TutorialFirstTree/SecondTree/LastTree) hang from.
--
-- Unity draws each tree prefab's own "Branch" (Sprites/Other/branch3.png) and
-- "Leaves" (branch2.png) behind its Acorn (doc 12 "Tree prefabs"). The port
-- used to stretch those 256px silhouettes over the 40-stud canvas, one blurry
-- overlapping pair centred on each acorn, behind the frog
-- (b-20260922-101449-30jz). The owner asked for a crisp tree, with the acorns
-- hanging off it, in front of the frog (b-20261017-123841-69yo, doc 17
-- "Tutorial tree"). It is now one tree drawn for this port: a 24 x 72 stud oak
-- in three 1024px tiles (Sprites/Scenery/TutorialTree{Top,Mid,Trunk}.png,
-- 42.7 px/stud). The Trunk tile is seamless with Mid and with itself, so it
-- repeats down past the view while the batch slides in from above
-- (GameServer slideIn, ~23 studs).
--
-- The art is drawn around the acorns' rest points (ACORN_AT: Levels'
-- Tutorial Movements after Lane.clampToLane, relative to the lane origin).
-- Each acorn's twig runs down to the acorn's centre, so the acorn hides the
-- twig's end whatever the acorn's idle spin angle (GameServer rollSpin) or its
-- grab recoil/sag. The tree follows its lane's live acorns: the origin is the
-- average of (acorn position - its ACORN_AT). It never moves a step.
--
-- Depth: Z = PLANE_Z - 0.225, between the frog's BodyArt (-0.25, head -0.3)
-- and its arms (-0.2). Acorns (0) and hands (+0.3) are further forward. So the
-- tree covers the frog's head and body, and the frog seems to hug the trunk,
-- but the arms, hands and acorns are never behind it. The trunk is ~3.6 studs
-- wide, narrower than the gap between the frog's eyes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)

local stepsFolder = workspace:WaitForChild("PlayField"):WaitForChild("Steps")

-- The art was drawn for acorns at y = -3.1429 / 15.7143 / 25 (Unity's Movements
-- Y); b-20261022-140925-k146 lowered the Tutorial acorns for phones, so the whole
-- tree is squashed vertically about the first acorn by ART_V_SCALE (x unchanged)
-- to keep every twig under its acorn. Levels' Tutorial Y = -0.2 / 0.58 / 0.96
-- of the half view (-3.14 / 9.11 / 15.09 studs) is what ART_V_SCALE is fitted to.
local ART_V_SCALE = 0.65
local ART_BASE_Y = -3.1429
local function squash(y: number): number
	return ART_BASE_Y + (y - ART_BASE_Y) * ART_V_SCALE
end

local TILE_SIZE = Vector3.new(24, 24 * ART_V_SCALE, 0.2) -- 1024px tile; Z thickness as the frog's art parts
local TREE_Z = Config.PLANE_Z - 0.225

-- Where the tree art puts each acorn, relative to the tree origin (= the lane
-- origin at rest). The tiles were drawn around these points (then squashed): if
-- Levels' Tutorial Movements change, update ART_V_SCALE / these to match.
local ACORN_AT: { [string]: Vector2 } = {
	TutorialFirstTree = Vector2.new(4.8163, squash(-3.1429)),
	TutorialSecondTree = Vector2.new(-4.8163, squash(15.7143)),
	TutorialLastTree = Vector2.new(4.8163, squash(25.0)),
}

-- Tile sprite and centre Y relative to the tree origin (tiles abut at 24 studs
-- before the squash, 24 * ART_V_SCALE after).
local TILES: { { sprite: string, y: number } } = {
	{ sprite = "TutorialTreeTop", y = squash(26) },
	{ sprite = "TutorialTreeMid", y = squash(2) },
	{ sprite = "TutorialTreeTrunk", y = squash(-22) },
	{ sprite = "TutorialTreeTrunk", y = squash(-46) },
}

local acorns: { [BasePart]: Vector2 } = {} -- live acorn step -> its ACORN_AT
local trees: { [number]: { BasePart } } = {} -- LaneUserId -> tile parts

local function createTree(): { BasePart }
	local parts: { BasePart } = {}
	for _, tile in TILES do
		local part = Instance.new("Part")
		part.Name = "TutorialTree"
		part.Size = TILE_SIZE
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		-- The part is the tile's whole canvas; never show it as a box over the
		-- frog's face (an unuploaded id just leaves the tree invisible).
		part.Transparency = 1
		local decal = Instance.new("Decal")
		decal.Name = "Art"
		decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
		decal:SetAttribute("Sprite", tile.sprite)
		decal.Parent = part
		SpriteSkin.apply(part)
		part.Parent = workspace
		table.insert(parts, part)
	end
	return parts
end

local function onStepAdded(child: Instance)
	if not child:IsA("BasePart") then
		return
	end
	local at = ACORN_AT[child:GetAttribute("KindName") :: string? or ""]
	if at then
		acorns[child] = at
	end
end

for _, child in stepsFolder:GetChildren() do
	onStepAdded(child)
end
stepsFolder.ChildAdded:Connect(onStepAdded)
stepsFolder.ChildRemoved:Connect(function(child)
	acorns[child :: BasePart] = nil
end)

local sums: { [number]: Vector2 } = {}
local counts: { [number]: number } = {}

-- Steps ride the lane's pull tween, so the tree follows them every frame.
RunService.Heartbeat:Connect(function()
	table.clear(sums)
	table.clear(counts)
	for step, at in acorns do
		local lane = (step:GetAttribute("LaneUserId") :: number?) or 0
		local pos = step.Position
		sums[lane] = (sums[lane] or Vector2.zero) + Vector2.new(pos.X, pos.Y) - at
		counts[lane] = (counts[lane] or 0) + 1
	end
	for lane, parts in trees do
		if not sums[lane] then
			for _, part in parts do
				part:Destroy()
			end
			trees[lane] = nil
		end
	end
	for lane, sum in sums do
		local origin = sum / counts[lane]
		local parts = trees[lane]
		if not parts then
			parts = createTree()
			trees[lane] = parts
		end
		for i, tile in TILES do
			parts[i].Position = Vector3.new(origin.X, origin.Y + tile.y, TREE_Z)
		end
	end
end)
