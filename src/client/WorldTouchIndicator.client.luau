--!strict
-- StarterPlayerScripts/Client/WorldTouchIndicator (LocalScript)
-- Phase 4 world dressing, item 6: the tap-point feedback at the local player's
-- click/touch (Player/TouchIndicator.cs: Show/SetPosition/Hide + SetColor).
-- Runs its own read-only input listener (mirrors GameClient's raycast against
-- Steps/Bugs) rather than touching GameClient.client.luau -- multiple
-- UserInputService connections are fine side by side, and this one never fires
-- a remote or otherwise affects gameplay.
--
-- ADAPTED: Unity's TouchIndicator.prefab is a single Sprites/Other/Circle.png
-- recolored green/yellow/red by whichever of three mutually-exclusive
-- SetColorBy* strategies Controller.cs (outside this phase's read list) has
-- live at runtime. The owner's wanted feedback (b-20260921-183321-iide,
-- reopening b-20260921-182233-97n6) is simpler and binary: a green circle
-- when the tap is within grab reach, a red X when it isn't -- no yellow
-- middle state. There's no dedicated X sprite under Sprites/ (TouchIndicator
-- only ever used Circle.png; checked docs/roblox-port/12 sec.6 and the Sprites
-- tree), so the X reuses the "X" glyph/red styling doc 12 records for
-- TouchQualityTextMiss.prefab, rendered as a TextLabel the same way
-- WorldQualityPopup.client.luau already renders its quality-popup glyphs --
-- avoids inventing new art up front.
--
-- FIXED (b-20260922-073908-mznf, reopening b-20260921-183648-aeap): "reach"
-- was a distance check from the frog's body against Config.MAX_GRAB_DISTANCE
-- (30 studs) -- but that constant is only GameClient's gamepad snap-assist
-- tolerance (cursor-to-step, not frog-to-tap), and 30 studs covers nearly the
-- whole lane (LANE_HALF_WIDTH=22, SPAWN_Y..DESPAWN_Y=25..-30), so it was
-- effectively always true and the X never showed. Mouse/touch grabs have no
-- distance limit at all: GameClient.tryGrab succeeds/fails purely on whether
-- the tap point-overlaps a live step's HitSize/HitOffset collider (stepAt).
-- "In reach" here now mirrors that same overlap test instead of a distance.
--
-- Previous bug: a translucent, tinted backing Part was left visible behind the
-- circle decal, so in-reach/near-reach taps showed as a green/yellow square
-- (b-20260921-182233-97n6) instead of just the circle. Fixed by keeping the
-- anchor Part fully transparent at all times -- only the Decal/TextLabel ever
-- carry color or opacity.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)

local player = Players.LocalPlayer
local playField = workspace:WaitForChild("PlayField")
local stepsFolder = playField:WaitForChild("Steps")

local camera = workspace.CurrentCamera :: Camera

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { stepsFolder, playField:WaitForChild("Bugs") }

-- Anchor part: always fully transparent (see header) -- it only carries
-- position, never a visible fill.
local dot = Instance.new("Part")
dot.Name = "TouchIndicator"
dot.Size = Vector3.new(1.4, 1.4, 0.1)
dot.Anchored = true
dot.CanCollide = false
dot.CanQuery = false
dot.Material = Enum.Material.SmoothPlastic
dot.Transparency = 1

-- In-reach state: the circle decal (Sprites/Other/Circle.png), tinted green.
local decal = Instance.new("Decal")
decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
decal:SetAttribute("Sprite", "Circle")
decal.Color3 = WorldConfig.TOUCH_INDICATOR_GREEN
decal.Transparency = 1
decal.Parent = dot
SpriteSkin.apply(dot)

-- Out-of-reach state: a red "X" glyph (no dedicated sprite exists -- see
-- header), styled like WorldQualityPopup's quality-popup text.
local missGui = Instance.new("BillboardGui")
missGui.Name = "MissIndicator"
missGui.Size = UDim2.fromOffset(60, 60)
missGui.AlwaysOnTop = true
missGui.Parent = dot

local missLabel = Instance.new("TextLabel")
missLabel.Name = "Label"
missLabel.BackgroundTransparency = 1
missLabel.Size = UDim2.fromScale(1, 1)
missLabel.Font = Enum.Font.GothamBlack
missLabel.TextScaled = true
missLabel.Text = "X"
missLabel.TextColor3 = WorldConfig.TOUCH_INDICATOR_RED
missLabel.TextTransparency = 1
missLabel.TextStrokeTransparency = 1
missLabel.Parent = missGui

dot.Parent = workspace

local decalFadeTween: Tween? = nil
local labelFadeTween: Tween? = nil

local function cancelFade()
	if decalFadeTween then
		decalFadeTween:Cancel()
		decalFadeTween = nil
	end
	if labelFadeTween then
		labelFadeTween:Cancel()
		labelFadeTween = nil
	end
end

-- Mirrors GameClient.stepAt's point-overlap test (this lane's own live steps,
-- boxed by their Unity HitSize/HitOffset collider, not the sprite canvas) --
-- the actual pass/fail condition for a mouse/touch grab. See header.
local function overOwnStep(worldPos: Vector3): boolean
	for _, inst in stepsFolder:GetChildren() do
		if
			inst:IsA("BasePart")
			and inst:GetAttribute("Kind") == "Step"
			and inst:GetAttribute("LaneUserId") == player.UserId
		then
			local hit = inst:GetAttribute("HitSize")
			local offset = inst:GetAttribute("HitOffset")
			local cx, cy = inst.Position.X, inst.Position.Y
			if typeof(offset) == "Vector2" then
				cx, cy = cx + offset.X, cy + offset.Y
			end
			local halfX, halfY
			if typeof(hit) == "Vector2" then
				halfX, halfY = hit.X / 2, hit.Y / 2
			else
				halfX, halfY = inst.Size.X / 2, inst.Size.Y / 2 -- no collider data: the part itself
			end
			if math.abs(worldPos.X - cx) <= halfX and math.abs(worldPos.Y - cy) <= halfY then
				return true
			end
		end
	end
	return false
end

local function show(worldPos: Vector3)
	cancelFade()
	dot.CFrame = CFrame.new(worldPos.X, worldPos.Y, Config.PLANE_Z + 0.6)
	local inReach = overOwnStep(worldPos)
	if inReach then
		decal.Transparency = 0
		missLabel.TextTransparency = 1
		missLabel.TextStrokeTransparency = 1
	else
		decal.Transparency = 1
		missLabel.TextTransparency = 0
		missLabel.TextStrokeTransparency = 0.4
	end
end

local function hide()
	local info = TweenInfo.new(WorldConfig.TOUCH_INDICATOR_FADE_TIME)
	local decalTween = TweenService:Create(decal, info, { Transparency = 1 })
	local labelTween = TweenService:Create(missLabel, info, { TextTransparency = 1, TextStrokeTransparency = 1 })
	decalFadeTween = decalTween
	labelFadeTween = labelTween
	decalTween:Play()
	labelTween:Play()
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
