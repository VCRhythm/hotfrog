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
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local SoundFX = require(ReplicatedStorage.Shared.SoundFX)
local Levels = require(ReplicatedStorage.Shared.Levels)
local GrabTarget = require(script.Parent.world.GrabTarget)

local player = Players.LocalPlayer
local playField = workspace:WaitForChild("PlayField")
local frogsFolder = playField:WaitForChild("Frogs")
local stepsFolder = playField:WaitForChild("Steps")
local lanesFolder = playField:WaitForChild("Lanes")

-- Levels.luau's `list` indices are already in progression order (Tutorial <
-- Pot < Kitchen < Country) -- used below to tell a real level-up (index goes
-- up) apart from a death reset (index goes back down) when all we have for
-- another lane is its current Level attribute, not the transition string.
local levelIndexByName: { [string]: number } = {}
for index, level in Levels.list do
	levelIndexByName[level.name] = index
end

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
	bodyDecal: Decal?,
	alive: boolean, -- false once the model is torn down; stops the blink coroutine
	dead: boolean, -- mirrors the model's Dead attribute
	isLocal: boolean, -- this is Players.LocalPlayer's own frog
	blinking: boolean, -- guards animateBlink against overlapping callers
	pupilU: number,
	pupilV: number,
	nextStepPoll: number,
	lookTarget: Vector3?,
	lookDown: boolean, -- overrides lookTarget: glancing down at nearby Pot lava
	nearLava: boolean,
	heatTinted: boolean, -- current state of the Body decal's heat tween
	laneFolder: Folder?, -- workspace.PlayField.Lanes/<UserId>, resolved lazily
	laneLevelIndex: number?, -- last seen Levels.list index for this lane (remote soft-transition heuristic)
	reacting: boolean, -- true while the level-up look-around plays
	reactU: number,
	reactV: number,
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

-- `blinking` guards against two callers overlapping (the ambient loop below
-- and the level-up reaction's closing blink) and fighting over the same
-- eyelid decals.
local function animateBlink(state: FrogState)
	local eyelids = state.eyelids
	if not eyelids or state.blinking then
		return
	end
	state.blinking = true
	local frame = WorldConfig.BLINK_FRAME_TIME
	local stages = { "Low", "Lower", "Closed", "Lower", "Low", "Open" }
	for i, mode in stages do
		showEyes(eyelids, mode)
		if i < #stages then
			task.wait(frame)
			if not state.alive or state.dead then
				break
			end
		end
	end
	state.blinking = false
end

local function blinkLoop(state: FrogState)
	while state.alive do
		local delay = WorldConfig.BLINK_MIN_TIME
			+ math.random() * (WorldConfig.BLINK_MAX_TIME - WorldConfig.BLINK_MIN_TIME)
		task.wait(delay)
		-- `reacting` pauses the ambient loop so it doesn't clobber the level-up
		-- reaction's own wide-eyes-then-blink beat (see playLevelUpReaction).
		if state.alive and not state.dead and not state.reacting then
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
-- held step; ADAPTED to a Texture OffsetStudsU/V nudge, see header comment).
-- Priority: an actually-held step wins, then (Pot only) a glance down at
-- nearby lava (state.nearLava, set by updateLevelTracking below), then idle
-- nearest-step tracking.
-- ---------------------------------------------------------------------------
local function updatePupilTarget(state: FrogState, now: number)
	local held = GrabTarget.heldPosition(state.body, state.rightLimb, state.leftLimb)
	if held then
		state.lookTarget = held
		state.lookDown = false
		return
	end
	if state.nearLava then
		state.lookTarget = nil
		state.lookDown = true
		return
	end
	state.lookDown = false
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
	local lerpRate = WorldConfig.PUPIL_LERP_RATE
	if state.reacting then
		-- Level-up look-around (playLevelUpReaction) drives the pupils directly,
		-- at its own slower rate -- a deliberate "look around", not a snap-track.
		targetU, targetV = state.reactU, state.reactV
		lerpRate = WorldConfig.LEVEL_UP_LOOK_LERP_RATE
	elseif state.lookDown then
		targetV = -WorldConfig.PUPIL_MAX_OFFSET * WorldConfig.LAVA_GLANCE_V_FRACTION
	else
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
	end

	local alpha = math.clamp(dt * lerpRate, 0, 1)
	state.pupilU += (targetU - state.pupilU) * alpha
	state.pupilV += (targetV - state.pupilV) * alpha

	leftPupil.OffsetStudsU = state.pupilU
	leftPupil.OffsetStudsV = state.pupilV
	rightPupil.OffsetStudsU = state.pupilU
	rightPupil.OffsetStudsV = state.pupilV
end

-- ---------------------------------------------------------------------------
-- Heat (Pot lava proximity) and level-up reactions -- journey 5/8,
-- b-20260923-154344-o8po. Neither has a Unity source (Frog.cs has no lava- or
-- level-up-driven reaction), so both are ADAPTED/additive; see WorldConfig's
-- header comment for the two blocks of tuning constants.
-- ---------------------------------------------------------------------------

-- Resolves (and caches) this frog's workspace.PlayField.Lanes/<UserId> folder
-- -- the doc 13 discovery contract -- which may not exist yet the instant a
-- frog model replicates in.
local function laneFolderFor(state: FrogState): Folder?
	if state.laneFolder then
		return state.laneFolder
	end
	local found = lanesFolder:FindFirstChild(tostring(state.userId))
	if found and found:IsA("Folder") then
		state.laneFolder = found
	end
	return state.laneFolder
end

local function setHeatTint(state: FrogState, hot: boolean)
	local decal = state.bodyDecal
	if not decal or state.heatTinted == hot then
		return
	end
	state.heatTinted = hot
	local color = if hot then WorldConfig.FROG_HEAT_TINT_COLOR else Color3.new(1, 1, 1)
	TweenService:Create(decal, TweenInfo.new(WorldConfig.FROG_HEAT_TINT_TIME), { Color3 = color }):Play()
end

-- Level-up "wide eyes, slow look around, then blink". ADAPTED: no "wide"
-- eyelid art exists, so wide eyes is approximated by forcing lids Open and
-- pausing the ambient blink loop (see blinkLoop's `reacting` check) for the
-- duration; the look-around is a scripted left/right/center pupil sweep at
-- LEVEL_UP_LOOK_LERP_RATE, driven through updatePupils' `reacting` branch.
local function playLevelUpReaction(state: FrogState)
	if not state.alive or state.dead or state.reacting then
		return
	end
	state.reacting = true
	if state.eyelids then
		showEyes(state.eyelids, "Open")
	end
	local looks = { WorldConfig.PUPIL_MAX_OFFSET, -WorldConfig.PUPIL_MAX_OFFSET, 0 }
	for _, u in looks do
		if not state.alive or state.dead then
			state.reacting = false
			return
		end
		state.reactU, state.reactV = u, 0
		task.wait(WorldConfig.LEVEL_UP_LOOK_SEGMENT_TIME)
	end
	state.reacting = false
	if state.alive and not state.dead then
		animateBlink(state)
	end
end

-- Per-frame per-frog bookkeeping: resolves the lane folder, updates the Pot
-- heat tint/glance, and -- for every OTHER lane (never the local player's
-- own; that one gets the real transition off LevelState.Changed below) --
-- detects a real level-up from the lane's Level attribute alone. `Level`
-- changes on every transition ("start"/"soft"/"death"), but only "soft" ever
-- moves to a HIGHER Levels.list index (Tutorial->Pot->Kitchen->Country);
-- "start" has no prior value to compare against and "death" always resets
-- back to Pot or Tutorial, so "index went up from a known prior value" is an
-- exact stand-in for "soft" without needing the transition string itself.
local function updateLevelTracking(state: FrogState)
	local folder = laneFolderFor(state)
	local levelName: string? = nil
	if folder then
		local name = folder:GetAttribute("Level")
		if typeof(name) == "string" then
			levelName = name
			if not state.isLocal then
				local newIndex = levelIndexByName[name]
				local prevIndex = state.laneLevelIndex
				if newIndex and prevIndex and newIndex > prevIndex then
					task.spawn(playLevelUpReaction, state)
				end
				if newIndex then
					state.laneLevelIndex = newIndex
				end
			end
		end
	end

	local anchor = state.head or state.body
	local nearLava = levelName == "Pot" and (anchor.Position.Y - Config.LAVA_Y) <= WorldConfig.LAVA_PROXIMITY_STUDS
	state.nearLava = nearLava
	setHeatTint(state, nearLava)
end

-- ---------------------------------------------------------------------------
-- Hand grab (Limb.cs OpenHand/CloseHand: show the closed-grip decal and hide
-- the open-hand decal while a limb holds a step). The server stamps a `Held`
-- attribute on each limb (GameServer's frog-render Heartbeat) since a
-- position-based guess (comparing the limb to its rest pose) misfires when a
-- free limb is still easing back toward rest and legitimately lags behind a
-- moving body (b-20260922-081814-xqof) -- `Held` is the real state, not an
-- inference.
-- ---------------------------------------------------------------------------
local function updateHandGrab(state: FrogState)
	if state.rightLimb and state.rightHandOpen and state.rightHandGrab then
		local held = state.rightLimb:GetAttribute("Held") == true
		state.rightHandOpen.Transparency = if held then 1 else 0
		state.rightHandGrab.Transparency = if held then 0 else 1
	end
	if state.leftLimb and state.leftHandOpen and state.leftHandGrab then
		local held = state.leftLimb:GetAttribute("Held") == true
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
	-- The grab decal has its own small host part (sized to its own, smaller
	-- canvas -- doc 17 "Frog rig size and sprite framing") rather than sharing
	-- RightHand/LeftHand's part, which is sized for the open-hand sprite's
	-- larger canvas and would stretch the grab art up to that size.
	local rightGrabPart = rightLimbPart and rightLimbPart:FindFirstChild("RightHandGrab")
	local leftGrabPart = leftLimbPart and leftLimbPart:FindFirstChild("LeftHandGrab")

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
		leftHandGrab = if leftGrabPart and leftGrabPart:IsA("BasePart")
			then findDecal(leftGrabPart, "LeftHandGrab")
			else nil,
		rightHandOpen = if rightHandPart and rightHandPart:IsA("BasePart")
			then findDecal(rightHandPart, "RightHand")
			else nil,
		rightHandGrab = if rightGrabPart and rightGrabPart:IsA("BasePart")
			then findDecal(rightGrabPart, "RightHandGrab")
			else nil,
		bodyDecal = findDecal(body, "Body"),
		alive = true,
		dead = model:GetAttribute("Dead") == true,
		isLocal = (model:GetAttribute("UserId") :: number?) == player.UserId,
		blinking = false,
		pupilU = 0,
		pupilV = 0,
		nextStepPoll = 0,
		lookTarget = nil,
		lookDown = false,
		nearLava = false,
		heatTinted = false,
		laneFolder = nil,
		laneLevelIndex = nil,
		reacting = false,
		reactU = 0,
		reactV = 0,
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

	-- The local player's own frog gets the real "soft" transition straight off
	-- LevelState (LevelClient.client.luau), instead of the Level-attribute
	-- heuristic updateLevelTracking uses for every other lane (see its header
	-- comment). Backgrounded (not WaitForChild(math.huge) at file scope) so a
	-- slow-to-appear LevelState never delays tracking any other frog.
	if state.isLocal then
		task.spawn(function()
			local levelState = player:WaitForChild("LevelState", 30)
			local changed = levelState and levelState:WaitForChild("Changed", 30)
			if changed and changed:IsA("BindableEvent") then
				changed.Event:Connect(function(_, _, _, _, transition)
					if transition == "soft" then
						task.spawn(playLevelUpReaction, state)
					end
				end)
			end
		end)
	end
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
			updateLevelTracking(state)
			updatePupilTarget(state, now)
			updateHandGrab(state)
		else
			state.lookTarget = nil
			state.lookDown = false
			state.nearLava = false
			setHeatTint(state, false)
		end
		updatePupils(state, dt)
	end
end)
