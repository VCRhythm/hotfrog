--!strict
-- StarterPlayer/StarterPlayerScripts/GameClient (LocalScript)
-- Client side of the basic Hotfrog loop:
--   * scriptable camera framing the play plane (../02 Option A)
--   * frog custom gravity + head bob (Player/Frog.cs)
--   * two independent limbs that grab / hold / return (Player/Controller.cs, Limb.cs)
--   * input -> raycast -> grab, with grab-quality grading (Player/Controller.cs)
--   * local death detection -> ReportDeath; HUD driven by ScoreChanged
--
-- The frog is a client-local visual; steps are server-owned and replicate in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local PullMath = require(ReplicatedStorage.Shared.PullMath)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local GrabStep = remotes:WaitForChild("GrabStep") :: RemoteEvent
local ReleaseStep = remotes:WaitForChild("ReleaseStep") :: RemoteEvent
local ReportDeath = remotes:WaitForChild("ReportDeath") :: RemoteEvent
local ScoreChanged = remotes:WaitForChild("ScoreChanged") :: RemoteEvent
local GameOver = remotes:WaitForChild("GameOver") :: RemoteEvent
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
-- Spawn the local frog
-- ---------------------------------------------------------------------------
local frog = ReplicatedStorage.Assets.FrogModel:Clone()
frog.Parent = workspace
local frogRoot = frog.PrimaryPart :: BasePart
local START_CFRAME = CFrame.new(0, 0, Config.PLANE_Z)
frogRoot.CFrame = START_CFRAME
frogRoot.Anchored = true

local function v2to3(v: Vector2): Vector3
	return PullMath.v2to3(v)
end

-- ---------------------------------------------------------------------------
-- Limbs
-- ---------------------------------------------------------------------------
type Limb = { part: BasePart, rest: Vector2, heldStep: BasePart? }
local limbs: { Limb } = {
	{ part = frog:FindFirstChild("RightLimb") :: BasePart, rest = Config.LIMB_REST[1], heldStep = nil },
	{ part = frog:FindFirstChild("LeftLimb") :: BasePart, rest = Config.LIMB_REST[2], heldStep = nil },
}

local function getFreeLimb(): Limb?
	for _, limb in ipairs(limbs) do
		if not limb.heldStep then
			return limb
		end
	end
	return nil
end

local function anyLimbHolding(): boolean
	return limbs[1].heldStep ~= nil or limbs[2].heldStep ~= nil
end

local function releaseLimb(index: number)
	local step = limbs[index].heldStep
	if step then
		limbs[index].heldStep = nil
		ReleaseStep:FireServer(index, step) -- step included for step-behaviour hooks (../05)
	end
end

-- A step behavior knocked us off (Beetle, crumble, fall — Step.cs ForceRelease):
-- drop whichever limb holds that step. The ReleaseStep echo is a server no-op.
ForceRelease.OnClientEvent:Connect(function(step)
	for i, limb in ipairs(limbs) do
		if limb.heldStep == step then
			releaseLimb(i)
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Frog gravity + bob (Player/Frog.cs)
-- ---------------------------------------------------------------------------
local gravityMult = Config.GRAVITY_MULT_START
local isDead = false

local function onGrab()
	gravityMult = Config.GRAVITY_MULT_START -- reset the fall curve (Bob)
	local head = frog:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		TweenService:Create(head, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {
			CFrame = head.CFrame * CFrame.new(0, 0.5, 0),
		}):Play()
	end
end

local function respawnFrog()
	isDead = false
	gravityMult = Config.GRAVITY_MULT_START
	for i = 1, #limbs do
		limbs[i].heldStep = nil
	end
	frogRoot.CFrame = START_CFRAME
end

-- ---------------------------------------------------------------------------
-- Input -> grab (Player/Controller.cs: CheckTouch / DecipherTouch / TouchStep)
-- ---------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = {
	workspace.PlayField.Steps,
	workspace.PlayField:WaitForChild("Bugs"), -- created by BugService at startup
}

-- Tongue visual (Entities/Tongue.cs Expand/FixedUpdate): a thin part stretches
-- from the head to the tap point, then retracts. Pure local cosmetics -- the
-- server is authoritative on whether the catch actually scored (doc 06).
local function expandTongue(targetPos: Vector3)
	local head = frog:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local from = head.Position
	local length = (targetPos - from).Magnitude
	if length < 0.5 then
		return
	end

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
	if isDead then
		return
	end

	local unitRay = camera:ScreenPointToRay(screenX, screenY)
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 300, rayParams)
	if not result then
		return -- miss: add a sound/limb-nudge here to match Controller.CheckTouch
	end

	local kind = result.Instance:GetAttribute("Kind")

	-- bugs are caught with the tongue, not a limb (Controller.TouchBug)
	if kind == "Bug" then
		CatchBug:FireServer(result.Instance)
		expandTongue(result.Instance.Position)
		return
	end

	if kind == "Step" then
		local limb = getFreeLimb()
		if not limb then
			return
		end
		local step = result.Instance :: BasePart
		limb.heldStep = step
		onGrab()
		local quality = PullMath.gradeGrab(result.Position, step.Position)
		GrabStep:FireServer(step, quality, frogRoot.Position)
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
-- loop frees a limb on any relevant input-up; refine per-finger tracking later.
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		-- free the most-recently-grabbed held limb
		for i = #limbs, 1, -1 do
			if limbs[i].heldStep then
				releaseLimb(i)
				break
			end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Per-frame: limbs follow/return, frog falls, lava check
-- ---------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt: number)
	-- limbs
	for _, limb in ipairs(limbs) do
		if limb.heldStep and limb.heldStep.Parent then
			limb.part.CFrame = CFrame.new(limb.heldStep.Position) -- follow the (scrolling) step
		else
			limb.heldStep = nil
			local target = v2to3(limb.rest) + frogRoot.Position
			local alpha = math.clamp(dt / Config.LIMB_RETURN_TIME, 0, 1)
			limb.part.CFrame = limb.part.CFrame:Lerp(CFrame.new(target), alpha)
		end
	end

	-- gravity: a held frog doesn't fall; otherwise accelerate downward
	if not isDead and not anyLimbHolding() then
		gravityMult += Config.GRAVITY_ACCEL * dt
		local speed = math.min(Config.GRAVITY * gravityMult, Config.MAX_FALL_SPEED)
		local p = frogRoot.Position
		frogRoot.CFrame = CFrame.new(p.X, p.Y - speed * dt, Config.PLANE_Z)
	end

	-- lava / lose condition (Frog.Fall + Lava.cs). Client-detected here; server
	-- owns the consequences (score commit + restart) via ReportDeath.
	if not isDead and frogRoot.Position.Y <= Config.DESPAWN_Y then
		isDead = true
		ReportDeath:FireServer()
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

GameOver.OnClientEvent:Connect(function()
	-- simple restart: re-rise the frog (Frog.Rise). Add a fall anim / delay to
	-- match the original's death beat if you like.
	task.wait(0.5)
	respawnFrog()
end)
