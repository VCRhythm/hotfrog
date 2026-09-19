--!strict
-- StarterPlayerScripts/Client/WorldTouchIndicator (LocalScript)
-- Phase 4 world dressing, item 6: the coloured dot at the local player's tap
-- point (Player/TouchIndicator.cs: Show/SetPosition/Hide + SetColor). Runs its
-- own read-only input listener (mirrors GameClient's raycast against
-- Steps/Bugs) rather than touching GameClient.client.luau -- multiple
-- UserInputService connections are fine side by side, and this one never fires
-- a remote or otherwise affects gameplay.
--
-- ADAPTED colour rule: Unity ships three mutually-exclusive SetColorBy* helpers
-- (distance / time-held / Y) and Controller.cs (outside this phase's read list)
-- decides which is live at runtime. This port uses distance from the local
-- frog, scaled against the existing Config.MAX_GRAB_DISTANCE reach check, so
-- "red" means "probably out of reach" -- the closest in spirit to all three.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)

local player = Players.LocalPlayer
local playField = workspace:WaitForChild("PlayField")
local myFrog = playField:WaitForChild("Frogs"):WaitForChild("Frog_" .. player.UserId, math.huge) :: Model
local body = myFrog.PrimaryPart :: BasePart

local camera = workspace.CurrentCamera :: Camera

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { playField:WaitForChild("Steps"), playField:WaitForChild("Bugs") }

-- Flat quad, faded out at rest (TouchIndicator.prefab: SpriteRenderer alpha=0).
local dot = Instance.new("Part")
dot.Name = "TouchIndicator"
dot.Size = Vector3.new(1.4, 1.4, 0.1)
dot.Anchored = true
dot.CanCollide = false
dot.CanQuery = false
dot.Material = Enum.Material.SmoothPlastic
dot.Transparency = 1
dot.Color = WorldConfig.TOUCH_INDICATOR_GREEN

local decal = Instance.new("Decal")
decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
decal:SetAttribute("Sprite", "Circle")
decal.Transparency = 1
decal.Parent = dot
SpriteSkin.apply(dot)
dot.Parent = workspace

local fadeTween: Tween? = nil

local function cancelFade()
	if fadeTween then
		fadeTween:Cancel()
		fadeTween = nil
	end
end

local function colorForDistance(dist: number): Color3
	local greenMax = Config.MAX_GRAB_DISTANCE * WorldConfig.TOUCH_INDICATOR_GREEN_FRACTION
	local yellowMax = Config.MAX_GRAB_DISTANCE * WorldConfig.TOUCH_INDICATOR_YELLOW_FRACTION
	if dist <= greenMax then
		return WorldConfig.TOUCH_INDICATOR_GREEN
	elseif dist <= yellowMax then
		return WorldConfig.TOUCH_INDICATOR_YELLOW
	else
		return WorldConfig.TOUCH_INDICATOR_RED
	end
end

local function show(worldPos: Vector3)
	cancelFade()
	dot.CFrame = CFrame.new(worldPos.X, worldPos.Y, Config.PLANE_Z + 0.6)
	local dist = (Vector2.new(worldPos.X, worldPos.Y) - Vector2.new(body.Position.X, body.Position.Y)).Magnitude
	local color = colorForDistance(dist)
	dot.Color = color
	decal.Color3 = color
	dot.Transparency = 0.35
	decal.Transparency = 0
end

local function hide()
	local info = TweenInfo.new(WorldConfig.TOUCH_INDICATOR_FADE_TIME)
	local tween = TweenService:Create(dot, info, { Transparency = 1 })
	fadeTween = tween
	TweenService:Create(decal, info, { Transparency = 1 }):Play()
	tween:Play()
end

-- Resolve a screen tap to a world point on the play plane: prefer a real
-- raycast hit against Steps/Bugs (matches what was actually tapped), else fall
-- back to intersecting the ray with the play plane itself so the dot still
-- tracks a miss.
local function worldPointFor(screenX: number, screenY: number): Vector3?
	local unitRay = camera:ScreenPointToRay(screenX, screenY)
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 300, rayParams)
	if result then
		return result.Position
	end
	local dz = Config.PLANE_Z - unitRay.Origin.Z
	if math.abs(unitRay.Direction.Z) < 1e-4 then
		return nil
	end
	local t = dz / unitRay.Direction.Z
	if t <= 0 then
		return nil
	end
	return unitRay.Origin + unitRay.Direction * t
end

local activeInputType: Enum.UserInputType? = nil

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local pos = worldPointFor(input.Position.X, input.Position.Y)
	if pos then
		activeInputType = input.UserInputType
		show(pos)
	end
end)

-- Follow the finger while a touch is held (mouse taps don't drag in this game's
-- input model, so only Touch needs live tracking here).
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch or activeInputType ~= Enum.UserInputType.Touch then
		return
	end
	local pos = worldPointFor(input.Position.X, input.Position.Y)
	if pos then
		show(pos)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == activeInputType then
		activeInputType = nil
		hide()
	end
end)
