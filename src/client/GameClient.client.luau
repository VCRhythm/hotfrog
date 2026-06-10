--!strict
-- StarterPlayer/StarterPlayerScripts/GameClient (LocalScript)
-- Client side of the Hotfrog loop -- intents and cosmetics only (doc 07):
--   * scriptable camera framing the play plane (../02 Option A)
--   * input -> raycast -> grab/catch intents (Player/Controller.cs)
--   * optimistic limb slots for input gating, corrected by ForceRelease
--   * tongue visual (Entities/Tongue.cs) + HUD
--
-- The frog itself is SERVER-owned: GameServer builds Frog_<userId> in
-- workspace/PlayField/Frogs and drives gravity, limbs, death, and respawn, so it
-- simply replicates in like the steps do. The client never moves it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local SoundFX = require(ReplicatedStorage.Shared.SoundFX)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local GrabStep = remotes:WaitForChild("GrabStep") :: RemoteEvent
local ReleaseStep = remotes:WaitForChild("ReleaseStep") :: RemoteEvent
local ScoreChanged = remotes:WaitForChild("ScoreChanged") :: RemoteEvent
local ForceRelease = remotes:WaitForChild("ForceRelease") :: RemoteEvent
local CatchBug = remotes:WaitForChild("CatchBug") :: RemoteEvent

-- ---------------------------------------------------------------------------
-- Camera: scriptable, looking down +Z at the plane (approx orthographic)
-- ---------------------------------------------------------------------------
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
camera.FieldOfView = 40 -- far + narrow FOV fakes an orthographic look
camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, 60), Vector3.new(0, 0, 0))

-- ---------------------------------------------------------------------------
-- My server-owned frog (for the tongue origin and the Dead gate)
-- ---------------------------------------------------------------------------
local playField = workspace:WaitForChild("PlayField")
local myFrog = playField:WaitForChild("Frogs"):WaitForChild("Frog_" .. player.UserId, math.huge) :: Model

local function frogIsDead(): boolean
	return myFrog:GetAttribute("Dead") == true
end

-- ---------------------------------------------------------------------------
-- Limb slots: an optimistic mirror of what we hold, used only to gate input
-- (two limbs). The server is the truth; ForceRelease corrects us.
-- ---------------------------------------------------------------------------
type Slot = { heldStep: BasePart? }
local slots: { Slot } = { { heldStep = nil }, { heldStep = nil } }

local function getFreeSlot(): Slot?
	for _, slot in ipairs(slots) do
		if not slot.heldStep then
			return slot
		end
	end
	return nil
end

local function releaseSlot(index: number)
	local step = slots[index].heldStep
	if step then
		slots[index].heldStep = nil
		ReleaseStep:FireServer(index, step) -- step included for step-behaviour hooks (../05)
	end
end

-- The server rejected/ended a grab (already held, rate limit, behavior knock-off,
-- death): drop whichever slot mirrors that step. The ReleaseStep echo is a
-- server-side no-op because heldBy was already cleared.
ForceRelease.OnClientEvent:Connect(function(step)
	for i, slot in ipairs(slots) do
		if slot.heldStep == step then
			releaseSlot(i)
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Input -> intents (Player/Controller.cs: CheckTouch / DecipherTouch / TouchStep)
-- ---------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = {
	playField:WaitForChild("Steps"),
	playField:WaitForChild("Bugs"), -- created by BugService at startup
}

-- Tongue visual (Entities/Tongue.cs Expand/FixedUpdate): a thin part stretches
-- from the head to the tap point, then retracts. Pure local cosmetics -- the
-- server is authoritative on whether the catch actually scored (doc 06).
local function expandTongue(targetPos: Vector3)
	local head = myFrog:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local from = head.Position
	local length = (targetPos - from).Magnitude
	if length < 0.5 then
		return
	end
	SoundFX.play("slurp") -- Tongue.cs Expand

	local tongue = Instance.new("Part")
	tongue.Name = "Tongue"
	tongue.Anchored = true
	tongue.CanCollide = false
	tongue.CanQuery = false -- must not eat subsequent taps
	tongue.Color = Color3.fromRGB(214, 86, 110)
	tongue.Material = Enum.Material.SmoothPlastic
	tongue.Size = Vector3.new(0.6, 0.6, 0.1)
	tongue.CFrame = CFrame.lookAt(from, targetPos)
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Front
	decal:SetAttribute("Sprite", "UniversalTongue") -- Sprites/Frogs/Universal art
	decal.Parent = tongue
	SpriteSkin.apply(tongue)
	tongue.Parent = workspace

	-- grow toward the target (part scales from its centre, so walk the midpoint out)
	local grow = TweenService:Create(tongue, TweenInfo.new(Config.TONGUE_EXPAND_TIME), {
		Size = Vector3.new(0.6, 0.6, length),
		CFrame = CFrame.lookAt(from, targetPos) * CFrame.new(0, 0, -length / 2),
	})
	grow.Completed:Once(function()
		local shrink = TweenService:Create(tongue, TweenInfo.new(Config.TONGUE_RETRACT_TIME), {
			Size = Vector3.new(0.6, 0.6, 0.1),
			CFrame = CFrame.lookAt(from, targetPos),
		})
		shrink.Completed:Once(function()
			tongue:Destroy()
		end)
		shrink:Play()
	end)
	grow:Play()
end

local function tryGrab(screenX: number, screenY: number)
	if frogIsDead() then
		return
	end

	local unitRay = camera:ScreenPointToRay(screenX, screenY)
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 300, rayParams)
	if not result then
		SoundFX.play("miss") -- Controller.CheckTouch miss feedback
		return
	end

	local kind = result.Instance:GetAttribute("Kind")

	-- bugs are caught with the tongue, not a limb (Controller.TouchBug)
	if kind == "Bug" then
		CatchBug:FireServer(result.Instance)
		expandTongue(result.Instance.Position)
		return
	end

	if kind == "Step" then
		local slot = getFreeSlot()
		if not slot then
			return
		end
		local step = result.Instance :: BasePart
		slot.heldStep = step -- optimistic; the server corrects via ForceRelease
		SoundFX.play("grab") -- Step.cs PlayGrabSound
		GrabStep:FireServer(step, result.Position) -- server grades quality from the tap point
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		tryGrab(input.Position.X, input.Position.Y)
	end
end)

-- release a limb when its input lifts (Controller.FreeUnusedTouches). The basic
-- loop frees a slot on any relevant input-up; refine per-finger tracking later.
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		-- free the most-recently-grabbed held slot
		for i = #slots, 1, -1 do
			if slots[i].heldStep then
				releaseSlot(i)
				break
			end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- HUD (built in code so the script is self-contained; or wire to StarterGui)
-- ---------------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
local hud = Instance.new("ScreenGui")
hud.Name = "HUD"
hud.ResetOnSpawn = false

local function makeLabel(name: string, posY: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.fromOffset(220, 36)
	label.Position = UDim2.fromOffset(12, posY)
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = hud
	return label
end

local scoreLabel = makeLabel("ScoreLabel", 12)
local bestLabel = makeLabel("HighScoreLabel", 52)
hud.Parent = playerGui

ScoreChanged.OnClientEvent:Connect(function(score, best, quality)
	scoreLabel.Text = tostring(score)
	bestLabel.Text = "Best: " .. tostring(best or 0)
	if quality == "Perfect" then
		-- cheap feedback hook (flash/sound). See ../03 scoring section.
		scoreLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
		task.delay(0.15, function()
			scoreLabel.TextColor3 = Color3.new(1, 1, 1)
		end)
	end
end)

-- Death/respawn is entirely server-driven; the GameOver remote is feedback-only
-- (Effects.client.luau plays the fall sound).
