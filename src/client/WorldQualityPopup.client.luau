--!strict
-- StarterPlayerScripts/Client/WorldQualityPopup (LocalScript)
-- Phase 4 world dressing, item 5: floating OK / Great / Perfect (/ Miss) popups
-- at the grabbed step (Entities/QualityText.cs + doc 12 §6 TouchQualityText*
-- prefabs' colours/sizes), driven by the existing ScoreChanged remote's
-- `quality` argument. This is purely additive next to GameClient's own score-
-- label colour flash -- it doesn't touch GameClient.
--
-- ScoreChanged carries no step reference (GameServer.server.luau's remote list
-- is off-limits for this phase), so the popup's location is recovered with the
-- same world/GrabTarget "limb extended past its rest pose" heuristic
-- WorldFrogCosmetics uses for pupils: the instant a limb snaps onto a step is
-- remembered, and a ScoreChanged within QUALITY_POPUP_MATCH_WINDOW reuses that
-- position. The match has to work in EITHER arrival order: a held limb's
-- CFrame is an unanchored BasePart replicating from the server, so it can lag
-- a frame or more behind the (reliable, immediate) ScoreChanged remote --
-- b-20260921-164534-v6fo was this exact race, landing the popup on the frog's
-- body because ScoreChanged arrived before any transition had been captured.
-- So a ScoreChanged that finds no recent captured position doesn't fall back
-- immediately -- it waits (as `pendingQuality`) for the next transition within
-- the window, and only THEN falls back to the frog's head position if the
-- window truly lapses with no grab detected at all (e.g. a miss with no limb
-- movement, or a very late remote).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local GrabTarget = require(script.Parent.world.GrabTarget)
local Pool = require(script.Parent.world.Pool)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ScoreChanged = remotes:WaitForChild("ScoreChanged") :: RemoteEvent

local playField = workspace:WaitForChild("PlayField")
local myFrog = playField:WaitForChild("Frogs"):WaitForChild("Frog_" .. player.UserId, math.huge) :: Model
local body = myFrog.PrimaryPart :: BasePart

local headInst = myFrog:FindFirstChild("Head")
local head: BasePart? = if headInst and headInst:IsA("BasePart") then headInst else nil
local rightLimbInst = myFrog:FindFirstChild("RightLimb")
local rightLimbPart: BasePart? = if rightLimbInst and rightLimbInst:IsA("BasePart") then rightLimbInst else nil
local leftLimbInst = myFrog:FindFirstChild("LeftLimb")
local leftLimbPart: BasePart? = if leftLimbInst and leftLimbInst:IsA("BasePart") then leftLimbInst else nil

type Popup = { part: BasePart, gui: BillboardGui, label: TextLabel }

local pool = Pool.new(function(): Popup
	local part = Instance.new("Part")
	part.Name = "QualityPopupAnchor"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false

	local gui = Instance.new("BillboardGui")
	gui.Name = "QualityPopup"
	gui.Size = UDim2.fromOffset(140, 50)
	gui.AlwaysOnTop = true
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = gui

	return { part = part, gui = gui, label = label }
end, function(popup: Popup)
	popup.part.Parent = nil
end)

-- ---------------------------------------------------------------------------
-- Popup spawn/animate (QualityText.cs OnEnable: Invoke("Destroy", lifetime))
-- ---------------------------------------------------------------------------
local function spawnPopup(quality: string, position: Vector3)
	local color = WorldConfig.QUALITY_POPUP_COLORS[quality]
	local text = WorldConfig.QUALITY_POPUP_TEXT[quality]
	if not color or not text then
		return
	end

	local popup = pool.acquire()
	popup.part.CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0))
	popup.part.Parent = workspace
	popup.label.Text = text
	popup.label.TextColor3 = color
	popup.label.TextTransparency = 0
	popup.label.TextStrokeTransparency = 0.4
	popup.gui.StudsOffset = Vector3.zero

	local info = TweenInfo.new(WorldConfig.QUALITY_POPUP_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local moveTween = TweenService:Create(popup.gui, info, {
		StudsOffset = Vector3.new(0, WorldConfig.QUALITY_POPUP_RISE, 0),
	})
	local fadeTween = TweenService:Create(popup.label, info, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	moveTween:Play()
	fadeTween:Play()
	fadeTween.Completed:Once(function()
		pool.release(popup)
	end)
end

-- ---------------------------------------------------------------------------
-- Grab-location heuristic (see header): watch both limbs each Heartbeat and
-- remember the position + time whenever one transitions from "at rest" to
-- "extended" -- that's the moment a grab visually lands.
-- ---------------------------------------------------------------------------
local wasExtended = { [1] = false, [2] = false }
local lastGrabPos: Vector3? = nil
local lastGrabTime = -math.huge

-- A ScoreChanged that arrived before any grab position was captured for it
-- (see header) parks its quality here until the next Heartbeat transition
-- resolves a position, or the match window lapses and it falls back.
local pendingQuality: string? = nil
local pendingQualityTime = -math.huge

local function withinWindow(since: number): boolean
	return (os.clock() - since) <= WorldConfig.QUALITY_POPUP_MATCH_WINDOW
end

local function fallbackPosition(): Vector3
	if head then
		return head.Position
	end
	return body.Position
end

RunService.Heartbeat:Connect(function()
	local right, left = rightLimbPart, leftLimbPart
	if not right or not left then
		return
	end
	local limbs: { [number]: BasePart } = { [1] = right, [2] = left }
	for index, limb in limbs do
		local pos = GrabTarget.limbHeldPosition(body, limb, index)
		local extended = pos ~= nil
		if extended and not wasExtended[index] and pos then
			lastGrabPos = pos
			lastGrabTime = os.clock()
			if pendingQuality and withinWindow(pendingQualityTime) then
				spawnPopup(pendingQuality, pos)
				pendingQuality = nil
			end
		end
		wasExtended[index] = extended
	end

	if pendingQuality and not withinWindow(pendingQualityTime) then
		spawnPopup(pendingQuality, fallbackPosition())
		pendingQuality = nil
	end
end)

-- ---------------------------------------------------------------------------
-- ScoreChanged: use a position already captured for this grab if we have one
-- (the common case -- the limb's transition is usually seen first); otherwise
-- park the quality as `pendingQuality` and let the Heartbeat loop above
-- resolve it the instant the transition lands, instead of guessing now.
-- ---------------------------------------------------------------------------
ScoreChanged.OnClientEvent:Connect(function(_score, _best, quality)
	if typeof(quality) ~= "string" then
		return
	end
	if lastGrabPos and withinWindow(lastGrabTime) then
		spawnPopup(quality, lastGrabPos)
		return
	end
	pendingQuality = quality
	pendingQualityTime = os.clock()
end)
