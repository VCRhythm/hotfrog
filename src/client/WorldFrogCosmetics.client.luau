--!strict
-- StarterPlayerScripts/Client/WorldFrogCosmetics (LocalScript)
-- Phase 4 world dressing, item 7: blink cycle, pupil tracking, and dead/rise
-- state for EVERY visible frog (workspace/PlayField/Frogs/Frog_<userId>,
-- server-owned models -- doc 13/GameServer.server.luau). Ports Player/Frog.cs's
-- Blink/BlinkAnimate/AwakeAnimate/ShowEyes and its pupil SmoothDamp-to-target.
--
-- Ownership rule for this phase: only LOCAL visual properties may be touched on
-- these server-owned models -- Decal/Texture Transparency and Texture
-- OffsetStudsU/V, never a part's CFrame (the server owns frog CFrames outright).
-- Pupils are therefore ported as Texture instances on Head (FrogModel.model.json,
-- added additively) nudged via OffsetStudsU/V instead of moving a separate part.
--
-- "Drugged" (Frog.cs MakeDrugged: scleras flicker random colors for 2s) is
-- skipped -- nothing in this phase's remotes signals it, and Frog.cs's own
-- trigger for it isn't wired to anything in this port's scope either.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local SoundFX = require(ReplicatedStorage.Shared.SoundFX)
local GrabTarget = require(script.Parent.world.GrabTarget)

local playField = workspace:WaitForChild("PlayField")
local frogsFolder = playField:WaitForChild("Frogs")
local stepsFolder = playField:WaitForChild("Steps")

type Eyelids = {
	LowLeft: Decal,
	LowRight: Decal,
	LowerLeft: Decal,
	LowerRight: Decal,
	ClosedLeft: Decal,
	ClosedRight: Decal,
}

type FrogState = {
	model: Model,
	userId: number,
	body: BasePart,
	head: BasePart?,
	rightLimb: BasePart?,
	leftLimb: BasePart?,
	leftPupil: Texture?,
	rightPupil: Texture?,
	eyelids: Eyelids?,
	leftHandOpen: Decal?,
	leftHandGrab: Decal?,
	rightHandOpen: Decal?,
	rightHandGrab: Decal?,
	alive: boolean, -- false once the model is torn down; stops the blink coroutine
	dead: boolean, -- mirrors the model's Dead attribute
	pupilU: number,
	pupilV: number,
	nextStepPoll: number,
	lookTarget: Vector3?,
}

local states: { [Model]: FrogState } = {}

-- ---------------------------------------------------------------------------
-- Blink (Frog.cs ShowEyes / BlinkAnimate / AwakeAnimate)
-- ---------------------------------------------------------------------------
local function showEyes(eyelids: Eyelids, mode: string)
	eyelids.LowLeft.Transparency = if mode == "Low" then 0 else 1
	eyelids.LowRight.Transparency = if mode == "Low" then 0 else 1
	eyelids.LowerLeft.Transparency = if mode == "Lower" then 0 else 1
	eyelids.LowerRight.Transparency = if mode == "Lower" then 0 else 1
	eyelids.ClosedLeft.Transparency = if mode == "Closed" then 0 else 1
	eyelids.ClosedRight.Transparency = if mode == "Closed" then 0 else 1
end

local function animateBlink(state: FrogState)
	local eyelids = state.eyelids
	if not eyelids then
		return
	end
	local frame = WorldConfig.BLINK_FRAME_TIME
	showEyes(eyelids, "Low")
	task.wait(frame)
	if not state.alive or state.dead then
		return
	end
	showEyes(eyelids, "Lower")
	task.wait(frame)
	if not state.alive or state.dead then
		return
	end
	showEyes(eyelids, "Closed")
	task.wait(frame)
	if not state.alive or state.dead then
		return
	end
	showEyes(eyelids, "Lower")
	task.wait(frame)
	if not state.alive or state.dead then
		return
	end
	showEyes(eyelids, "Low")
	task.wait(frame)
	if not state.alive or state.dead then
		return
	end
	showEyes(eyelids, "Open")
end

local function blinkLoop(state: FrogState)
	while state.alive do
		local delay = WorldConfig.BLINK_MIN_TIME
			+ math.random() * (WorldConfig.BLINK_MAX_TIME - WorldConfig.BLINK_MIN_TIME)
		task.wait(delay)
		if state.alive and not state.dead then
			animateBlink(state)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Dead / rise (Frog.cs Die/Rise, ADAPTED to decal-only cosmetics -- the server
-- owns the model's CFrame outright, so no part is moved here)
-- ---------------------------------------------------------------------------
local function onDeadChanged(state: FrogState)
	local dead = state.model:GetAttribute("Dead") == true
	state.dead = dead
	local eyelids = state.eyelids
	if not eyelids then
		return
	end
	if dead then
		showEyes(eyelids, "Closed")
	else
		SoundFX.play("awake") -- Frog.cs Rise: AudioManager.Instance.PlayIn(delay, awakeSound)
		task.spawn(function()
			-- AwakeAnimate: Lower -> Low -> Open, one BLINK_FRAME_TIME apart
			if not state.alive then
				return
			end
			showEyes(eyelids, "Lower")
			task.wait(WorldConfig.BLINK_FRAME_TIME)
			if not state.alive or state.dead then
				return
			end
			showEyes(eyelids, "Low")
			task.wait(WorldConfig.BLINK_FRAME_TIME)
			if not state.alive or state.dead then
				return
			end
			showEyes(eyelids, "Open")
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Pupil tracking (Frog.cs Update: SmoothDamp toward the nearest step or the
-- held step; ADAPTED to a Texture OffsetStudsU/V nudge, see header comment)
-- ---------------------------------------------------------------------------
local function updatePupilTarget(state: FrogState, now: number)
	local held = GrabTarget.heldPosition(state.body, state.rightLimb, state.leftLimb)
	if held then
		state.lookTarget = held
		return
	end
	if now >= state.nextStepPoll then
		state.nextStepPoll = now + WorldConfig.NEAREST_STEP_POLL_INTERVAL
		local head = state.head
		if head then
			local nearest = GrabTarget.nearestStep(stepsFolder, state.userId, head.Position)
			state.lookTarget = if nearest then nearest.Position else nil
		end
	end
end

local function updatePupils(state: FrogState, dt: number)
	local head = state.head
	local leftPupil, rightPupil = state.leftPupil, state.rightPupil
	if not head or not leftPupil or not rightPupil then
		return
	end

	local targetU, targetV = 0, 0
	local target = state.lookTarget
	if target then
		local localPoint = head.CFrame:PointToObjectSpace(target)
		local reach = 3 -- studs of local offset that maxes out the pupil travel (ADAPTED clamp)
		-- U is negated: the sprites sit on each part's Back (+Z) face, and there a
		-- POSITIVE OffsetStudsU slides the image the -X way -- away from a target
		-- on the frog's right. V needs no flip (+V slides the image up). Measured
		-- in Studio 2026-09-19 with an offset test rig, see SpriteSkin's header.
		targetU = -math.clamp(localPoint.X / reach, -1, 1) * WorldConfig.PUPIL_MAX_OFFSET
		targetV = math.clamp(localPoint.Y / reach, -1, 1) * WorldConfig.PUPIL_MAX_OFFSET
	end

	local alpha = math.clamp(dt * WorldConfig.PUPIL_LERP_RATE, 0, 1)
	state.pupilU += (targetU - state.pupilU) * alpha
	state.pupilV += (targetV - state.pupilV) * alpha

	leftPupil.OffsetStudsU = state.pupilU
	leftPupil.OffsetStudsV = state.pupilV
	rightPupil.OffsetStudsU = state.pupilU
	rightPupil.OffsetStudsV = state.pupilV
end

-- ---------------------------------------------------------------------------
-- Hand grab (Limb.cs OpenHand/CloseHand: show the closed-grip decal and hide
-- the open-hand decal while a limb holds a step, ADAPTED to per-limb held
-- inference from GrabTarget since the server doesn't replicate which limb
-- holds a step). A limb the server flags `Reaching` is extended toward an
-- empty tap, not holding anything, so its hand stays open.
-- ---------------------------------------------------------------------------
local function updateHandGrab(state: FrogState)
	if state.rightLimb and state.rightHandOpen and state.rightHandGrab then
		local held = GrabTarget.limbHeldPosition(state.body, state.rightLimb, 1) ~= nil
			and state.rightLimb:GetAttribute("Reaching") ~= true
		state.rightHandOpen.Transparency = if held then 1 else 0
		state.rightHandGrab.Transparency = if held then 0 else 1
	end
	if state.leftLimb and state.leftHandOpen and state.leftHandGrab then
		local held = GrabTarget.limbHeldPosition(state.body, state.leftLimb, 2) ~= nil
			and state.leftLimb:GetAttribute("Reaching") ~= true
		state.leftHandOpen.Transparency = if held then 1 else 0
		state.leftHandGrab.Transparency = if held then 0 else 1
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
local function findDecal(parent: Instance, name: string): Decal?
	local inst = parent:FindFirstChild(name)
	return if inst and inst:IsA("Decal") then inst else nil
end

local function findTexture(parent: Instance, name: string): Texture?
	local inst = parent:FindFirstChild(name)
	return if inst and inst:IsA("Texture") then inst else nil
end

local function trackFrog(model: Model)
	if states[model] or not model:IsA("Model") then
		return
	end
	local body = model.PrimaryPart
	if not body then
		return
	end
	local headInst = model:FindFirstChild("Head")
	local head = if headInst and headInst:IsA("BasePart") then headInst else nil
	local rightInst = model:FindFirstChild("RightLimb")
	local leftInst = model:FindFirstChild("LeftLimb")
	local rightLimbPart = if rightInst and rightInst:IsA("BasePart") then rightInst else nil
	local leftLimbPart = if leftInst and leftInst:IsA("BasePart") then leftInst else nil

	local rightHandPart = rightLimbPart and rightLimbPart:FindFirstChild("RightHand")
	local leftHandPart = leftLimbPart and leftLimbPart:FindFirstChild("LeftHand")

	local eyelids: Eyelids? = nil
	if head then
		local lowLeft, lowRight = findDecal(head, "LowLeftEyelid"), findDecal(head, "LowRightEyelid")
		local lowerLeft, lowerRight = findDecal(head, "LowerLeftEyelid"), findDecal(head, "LowerRightEyelid")
		local closedLeft, closedRight = findDecal(head, "ClosedLeftEyelid"), findDecal(head, "ClosedRightEyelid")
		if lowLeft and lowRight and lowerLeft and lowerRight and closedLeft and closedRight then
			eyelids = {
				LowLeft = lowLeft,
				LowRight = lowRight,
				LowerLeft = lowerLeft,
				LowerRight = lowerRight,
				ClosedLeft = closedLeft,
				ClosedRight = closedRight,
			}
		end
	end

	local state: FrogState = {
		model = model,
		userId = (model:GetAttribute("UserId") :: number?) or 0,
		body = body,
		head = head,
		rightLimb = rightLimbPart,
		leftLimb = leftLimbPart,
		leftPupil = if head then findTexture(head, "LeftPupil") else nil,
		rightPupil = if head then findTexture(head, "RightPupil") else nil,
		eyelids = eyelids,
		leftHandOpen = if leftHandPart and leftHandPart:IsA("BasePart")
			then findDecal(leftHandPart, "LeftHand")
			else nil,
		leftHandGrab = if leftHandPart and leftHandPart:IsA("BasePart")
			then findDecal(leftHandPart, "LeftHandGrab")
			else nil,
		rightHandOpen = if rightHandPart and rightHandPart:IsA("BasePart")
			then findDecal(rightHandPart, "RightHand")
			else nil,
		rightHandGrab = if rightHandPart and rightHandPart:IsA("BasePart")
			then findDecal(rightHandPart, "RightHandGrab")
			else nil,
		alive = true,
		dead = model:GetAttribute("Dead") == true,
		pupilU = 0,
		pupilV = 0,
		nextStepPoll = 0,
		lookTarget = nil,
	}
	states[model] = state

	if eyelids then
		if state.dead then
			showEyes(eyelids, "Closed")
		else
			task.spawn(blinkLoop, state)
		end
	end

	model:GetAttributeChangedSignal("Dead"):Connect(function()
		onDeadChanged(state)
	end)
end

local function untrackFrog(model: Model)
	local state = states[model]
	if state then
		state.alive = false
		states[model] = nil
	end
end

for _, child in frogsFolder:GetChildren() do
	if child:IsA("Model") then
		trackFrog(child)
	end
end
frogsFolder.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		trackFrog(child)
	end
end)
frogsFolder.ChildRemoved:Connect(function(child)
	if child:IsA("Model") then
		untrackFrog(child)
	end
end)

RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()
	for _, state in states do
		if not state.dead then
			updatePupilTarget(state, now)
			updateHandGrab(state)
		else
			state.lookTarget = nil
		end
		updatePupils(state, dt)
	end
end)
