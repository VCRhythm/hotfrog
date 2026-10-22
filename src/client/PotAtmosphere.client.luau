--!strict
-- StarterPlayerScripts/Client/PotAtmosphere (LocalScript)
-- Owner's ruling b-20261012-141140-a1h3 (note b-20261010-191757-89n1: "make the inside of
-- the pot seem more like a pot"): Pot-only dressing, client-only cosmetics, local lane only.
--   * cloud scenery hidden in the Pot -- see WorldScenery's `skyHidden`, not here
--   * dark inner-wall vignette framing the screen (ScreenGui, edges only)
--   * corroded-metal walls down both sides of the lane, hugging LANE_HALF_WIDTH
--   * steam rising off the lava and a warm colour grade, both strengthened by the
--     0..1 PotHeat scalar WorldLava publishes (denser bubbles: SceneryKinds' Pot extras)
-- No art exists for walls/steam, so it is procedural (built-in Material + the built-in
-- smoke particle texture). Everything switches off when LevelState.LevelName ~= "Pot".

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local Lanes = require(script.Parent.world.Lanes)

local player = Players.LocalPlayer
local lane = Lanes.waitForLocal()
local levelState = player:WaitForChild("LevelState", WorldConfig.LANE_WAIT_TIMEOUT)
if not (lane and levelState) then
	warn("[PotAtmosphere] lane or LevelState never appeared; Pot atmosphere is disabled")
	return
end
local myLane: Folder = lane

local WALL_Z = -3 -- behind the play plane (steps/frog at 0) and in front of the backdrop (-5)
local CAMERA_DISTANCE = 43.2 -- GameClient's camera distance (duplicated: GameClient is not ours to edit)
-- Inner edge pushed out so its PROJECTED position lands on LANE_HALF_WIDTH: the walls
-- never show inside the playable width.
local WALL_INNER_X = Config.LANE_HALF_WIDTH * (CAMERA_DISTANCE - WALL_Z) / CAMERA_DISTANCE
local WALL_WIDTH = 90 -- wider than any viewport shows
local WALL_HEIGHT = 400
local WALL_COLOR = Color3.fromRGB(58, 48, 44)

local STEAM_BASE_RATE = 6
local STEAM_HEAT_RATE = 16 -- extra particles/s at full PotHeat
local GRADE_TINT = Color3.fromRGB(255, 226, 205) -- warm grade; deepens with heat
local GRADE_HEAT_TINT = Color3.fromRGB(255, 190, 150)

local folder = Instance.new("Folder")
folder.Name = "PotAtmosphere"

local walls: { BasePart } = {}
for _, side in { -1, 1 } do
	local wall = Instance.new("Part")
	wall.Name = if side < 0 then "PotWallLeft" else "PotWallRight"
	wall.Size = Vector3.new(WALL_WIDTH, WALL_HEIGHT, 1)
	wall.Anchored = true
	wall.CanCollide = false
	wall.CanQuery = false
	wall.CanTouch = false
	wall.CastShadow = false
	wall.Material = Enum.Material.CorrodedMetal
	wall.Color = WALL_COLOR
	wall:SetAttribute("Side", side)
	wall.Parent = folder
	table.insert(walls, wall)
end

local steamPart = Instance.new("Part")
steamPart.Name = "PotSteam"
steamPart.Size = Vector3.new(Config.LANE_HALF_WIDTH * 2, 1, 1)
steamPart.Transparency = 1
steamPart.Anchored = true
steamPart.CanCollide = false
steamPart.CanQuery = false
steamPart.CanTouch = false
steamPart.CastShadow = false
local steam = Instance.new("ParticleEmitter")
steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
steam.EmissionDirection = Enum.NormalId.Top
steam.Lifetime = NumberRange.new(4, 6)
steam.Speed = NumberRange.new(5, 8)
steam.SpreadAngle = Vector2.new(12, 12)
steam.Rate = STEAM_BASE_RATE
steam.Rotation = NumberRange.new(0, 360)
steam.RotSpeed = NumberRange.new(-15, 15)
steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
steam.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.2, 0.7),
	NumberSequenceKeypoint.new(1, 1),
})
steam.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235))
steam.LightEmission = 0
steam.LightInfluence = 0
steam.Parent = steamPart
steamPart.Parent = folder

-- Edge vignette: dark at the screen edges, fully clear toward the middle.
local gui = Instance.new("ScreenGui")
gui.Name = "PotVignette"
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None -- cover the notch/topbar too (phones)
gui.DisplayOrder = -5
gui.ResetOnSpawn = false
local function vignetteEdge(anchor: Vector2, size: UDim2, rotation: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = anchor
	frame.Position = UDim2.fromScale(anchor.X, anchor.Y)
	frame.Size = size
	frame.BackgroundColor3 = Color3.fromRGB(10, 6, 4)
	frame.BorderSizePixel = 0
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
	frame.Parent = gui
	return frame
end
local sideFrames = {
	vignetteEdge(Vector2.new(0, 0), UDim2.fromScale(0.16, 1), 0), -- left, dark at the edge
	vignetteEdge(Vector2.new(1, 0), UDim2.fromScale(0.16, 1), 180), -- right
}
vignetteEdge(Vector2.new(0, 0), UDim2.fromScale(1, 0.12), 90) -- top
gui.Parent = player:WaitForChild("PlayerGui")

-- Narrow (portrait) viewports show little beyond the lane, so the side bands shrink
-- with aspect instead of darkening live play (0.16 at 16:9 and wider).
local function refitVignette()
	local camera = workspace.CurrentCamera
	if not camera or camera.ViewportSize.Y <= 0 then
		return
	end
	local aspect = camera.ViewportSize.X / camera.ViewportSize.Y
	local width = math.clamp(0.16 * (16 / 9) / aspect, 0.06, 0.16)
	for _, frame in sideFrames do
		frame.Size = UDim2.fromScale(width, 1)
	end
end
do
	local conn: RBXScriptConnection? = nil
	local function watchCamera()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			conn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refitVignette)
		end
		refitVignette()
	end
	watchCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
end

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "PotHeatGrade"
grade.Enabled = false
grade.Parent = Lighting

local active = false
local function setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	folder.Parent = if on then workspace else nil
	gui.Enabled = on
	grade.Enabled = on
end
gui.Enabled = false

RunService.PreRender:Connect(function()
	local origin = Lanes.originOf(myLane)
	-- Spectating (GameClient centres the camera on another lane while not Playing):
	-- the dressing belongs to this lane only, so it is off whenever the camera is elsewhere.
	local camera = workspace.CurrentCamera
	local onMyLane = camera ~= nil and math.abs(camera.CFrame.Position.X - origin.X) < 8
	setActive(onMyLane and levelState:GetAttribute("LevelName") == "Pot")
	if not active then
		return
	end
	for _, wall in walls do
		local side = wall:GetAttribute("Side") :: number
		wall.CFrame =
			CFrame.new(origin.X + side * (WALL_INNER_X + WALL_WIDTH / 2), origin.Y, Config.PLANE_Z + WALL_Z - 0.5)
	end
	steamPart.CFrame = CFrame.new(origin.X, origin.Y + Config.LAVA_Y, Config.PLANE_Z - 1)
	local heat = levelState:GetAttribute("PotHeat")
	heat = if typeof(heat) == "number" then math.clamp(heat, 0, 1) else 0
	steam.Enabled = myLane:GetAttribute("TutorialGrace") ~= true -- not until the tutorial is fully done
	steam.Rate = STEAM_BASE_RATE + STEAM_HEAT_RATE * heat
	grade.TintColor = GRADE_TINT:Lerp(GRADE_HEAT_TINT, heat)
end)
