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
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local SoundFX = require(ReplicatedStorage.Shared.SoundFX)
local ClientSettings = require(script.Parent.ui.ClientSettings)
local UIKit = require(script.Parent.ui.UIKit)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local GrabStep = remotes:WaitForChild("GrabStep") :: RemoteEvent
local ReleaseStep = remotes:WaitForChild("ReleaseStep") :: RemoteEvent
local ScoreChanged = remotes:WaitForChild("ScoreChanged") :: RemoteEvent
local ForceRelease = remotes:WaitForChild("ForceRelease") :: RemoteEvent
local CatchBug = remotes:WaitForChild("CatchBug") :: RemoteEvent
local RunStateChanged = remotes:WaitForChild("RunStateChanged") :: RemoteEvent
local LevelChanged = remotes:WaitForChild("LevelChanged") :: RemoteEvent
local ProfileChanged = remotes:WaitForChild("ProfileChanged") :: RemoteEvent
local BugCaught = remotes:WaitForChild("BugCaught") :: RemoteEvent

-- doc 15 (menus-and-input) item 7: this player's current run state (kept in
-- sync purely for the camera/gamepad logic below -- MenuClient owns the actual
-- Menu/Dead UI) and the last-input-type bridge other LocalScripts read for
-- gamepad glyph hints (same cross-LocalScript Folder+Attribute pattern
-- LevelClient.client.luau uses for LevelState).
local runState = "Menu"
RunStateChanged.OnClientEvent:Connect(function(state: string)
	runState = state
end)

local inputState = Instance.new("Folder")
inputState.Name = "InputState"
inputState:SetAttribute("Gamepad", false)
inputState.Parent = player

-- ---------------------------------------------------------------------------
-- My lane (doc 13 item 6): one PlayField "lane" per player, offset along X.
-- Lane.luau (server) creates `Lanes/<UserId>` with `Origin`/`Level` attributes
-- before this player's frog exists, so waiting on the lane folder first is safe
-- and gives us the origin the camera should centre on.
-- ---------------------------------------------------------------------------
local playField = workspace:WaitForChild("PlayField")
local myLane = playField:WaitForChild("Lanes"):WaitForChild(tostring(player.UserId), math.huge) :: Folder

local function laneOrigin(): Vector3
	local origin = myLane:GetAttribute("Origin")
	return if typeof(origin) == "Vector3" then origin else Vector3.new(0, 0, 0)
end

-- ---------------------------------------------------------------------------
-- Camera: scriptable, looking down +Z at the plane (approx orthographic),
-- centred on this player's own lane origin -- NOT world (0,0,0) -- so raycasts
-- from screen taps land on this lane's steps/bugs regardless of which slot it
-- was assigned. Re-centred if the lane's origin ever changes (it doesn't today,
-- but Lane.luau's attribute is the single source of truth either way).
-- ---------------------------------------------------------------------------
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
camera.FieldOfView = 40 -- far + narrow FOV fakes an orthographic look

-- Framing: every Unity camera is orthographic size 50 (doc 11 §4), i.e. a fixed
-- 100-Unity-unit vertical view = 100 * Config.UNITY_TO_STUDS ~= 31.43 studs.
-- Roblox's FieldOfView is vertical, so the distance that shows exactly that much
-- is (31.43 / 2) / tan(40/2 deg) ~= 43.2 studs. (It used to be 60, which showed
-- ~1.4x too much world and left the frog far smaller on screen than Unity's.)
local CAMERA_DISTANCE = 43.2

-- ---------------------------------------------------------------------------
-- Spectate (doc 15 item 6): while not Playing, left/right buttons walk the
-- camera through every OCCUPIED lane's Origin (read straight from
-- workspace.PlayField.Lanes -- the same attribute contract doc 13 set up for
-- BugService), snapping back to this player's own lane the moment a run
-- starts. GameClient owns the camera, so this lives here rather than in
-- MenuClient.
-- ---------------------------------------------------------------------------
local lanesFolder = playField:WaitForChild("Lanes")
local spectateIndex = 0 -- 0 = my own lane; 1.. = an index into otherLanes()

local function otherLanes(): { Folder }
	local list: { Folder } = {}
	for _, child in lanesFolder:GetChildren() do
		if child:IsA("Folder") and child ~= myLane then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

local function spectateOrigin(): Vector3
	if spectateIndex == 0 then
		return laneOrigin()
	end
	local list = otherLanes()
	local lane = list[spectateIndex]
	if lane then
		local origin = lane:GetAttribute("Origin")
		if typeof(origin) == "Vector3" then
			return origin
		end
	end
	return laneOrigin()
end

local function updateCamera()
	camera.CFrame = CFrame.lookAt(spectateOrigin() + Vector3.new(0, 0, CAMERA_DISTANCE), spectateOrigin())
end
updateCamera()
myLane:GetAttributeChangedSignal("Origin"):Connect(updateCamera)

RunStateChanged.OnClientEvent:Connect(function(state: string)
	if state == "Playing" and spectateIndex ~= 0 then
		spectateIndex = 0 -- snap back to my own lane the moment a run starts
		updateCamera()
	end
end)

-- Bottom-center, well clear of MenuClient's centred title/panels and
-- StoreUI's own bottom bar (Shop/Gift sit at 1,-56 from the bottom).
local spectateGui = UIKit.screenGui("SpectateGui")
local spectateLeft =
	UIKit.button("SpectateLeft", "<", UDim2.fromOffset(40, 40), UDim2.new(0.5, -140, 1, -170), spectateGui)
local spectateRight =
	UIKit.button("SpectateRight", ">", UDim2.fromOffset(40, 40), UDim2.new(0.5, 100, 1, -170), spectateGui)
local spectateLabel =
	UIKit.label("SpectateLabel", "", UDim2.fromOffset(160, 40), UDim2.new(0.5, -80, 1, -170), spectateGui)
spectateLabel.TextXAlignment = Enum.TextXAlignment.Center

local function refreshSpectateVisibility()
	local visible = runState ~= "Playing" and #otherLanes() > 0
	spectateLeft.Visible = visible
	spectateRight.Visible = visible
	spectateLabel.Visible = visible
	spectateLabel.Text = if spectateIndex == 0 then "My Lane" else ("Watching Player " .. spectateIndex)
end

local function cycleSpectate(delta: number)
	local count = #otherLanes()
	if count == 0 then
		spectateIndex = 0
	else
		spectateIndex = (spectateIndex + delta) % (count + 1)
	end
	updateCamera()
	refreshSpectateVisibility()
end

spectateLeft.Activated:Connect(function()
	cycleSpectate(-1)
end)
spectateRight.Activated:Connect(function()
	cycleSpectate(1)
end)
RunStateChanged.OnClientEvent:Connect(refreshSpectateVisibility)
lanesFolder.ChildAdded:Connect(refreshSpectateVisibility)
lanesFolder.ChildRemoved:Connect(refreshSpectateVisibility)
refreshSpectateVisibility()
spectateGui.Parent = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------
-- My server-owned frog (for the tongue origin and the Dead gate)
-- ---------------------------------------------------------------------------
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
	ClientSettings.playIfEnabled(SoundFX, "slurp") -- Tongue.cs Expand

	local tongue = Instance.new("Part")
	tongue.Name = "Tongue"
	tongue.Anchored = true
	tongue.CanCollide = false
	tongue.CanQuery = false -- must not eat subsequent taps
	tongue.Color = Color3.fromRGB(214, 86, 110)
	tongue.Material = Enum.Material.SmoothPlastic
	tongue.Size = Vector3.new(0.6, 0.6, 0.1)
	-- up = world +Z keeps the stretched part's Top face pointing at the camera
	-- (which sits at +Z), so the tongue sprite is never edge-on to it.
	tongue.CFrame = CFrame.lookAt(from, targetPos, Vector3.zAxis)
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal:SetAttribute("Sprite", "UniversalTongue") -- Sprites/Frogs/Universal art
	decal.Parent = tongue
	SpriteSkin.apply(tongue)
	tongue.Parent = workspace

	-- grow toward the target (part scales from its centre, so walk the midpoint out)
	local grow = TweenService:Create(tongue, TweenInfo.new(Config.TONGUE_EXPAND_TIME), {
		Size = Vector3.new(0.6, 0.6, length),
		CFrame = CFrame.lookAt(from, targetPos, Vector3.zAxis) * CFrame.new(0, 0, -length / 2),
	})
	grow.Completed:Once(function()
		local shrink = TweenService:Create(tongue, TweenInfo.new(Config.TONGUE_RETRACT_TIME), {
			Size = Vector3.new(0.6, 0.6, 0.1),
			CFrame = CFrame.lookAt(from, targetPos, Vector3.zAxis),
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
		ClientSettings.playIfEnabled(SoundFX, "miss") -- Controller.CheckTouch miss feedback
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
		ClientSettings.playIfEnabled(SoundFX, "grab") -- Step.cs PlayGrabSound
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
-- Gamepad input (doc 15 item 7): a virtual cursor moved by the left thumbstick
-- / arrow keys, snap-assist grabs (the nearest reachable step to the cursor is
-- grabbed; the cursor's own position is the tap point, so PullMath.gradeGrab
-- still rewards accuracy), and B/Y for the tongue toward the nearest bug. Mouse/touch above
-- is completely untouched. Limbs are already auto-assigned (getFreeSlot), so
-- per doc 15 "one grab button + one release per limb is fine" collapses to one
-- grab action + one release action rather than four separate limb buttons.
-- ---------------------------------------------------------------------------
local GAMEPAD_TYPES = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
}

UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
	inputState:SetAttribute("Gamepad", GAMEPAD_TYPES[inputType] == true)
end)
inputState:SetAttribute("Gamepad", GAMEPAD_TYPES[UserInputService:GetLastInputType()] == true)

local cursorGui = UIKit.screenGui("GamepadCursor")
local cursorMark = Instance.new("Frame")
cursorMark.Name = "Cursor"
cursorMark.Size = UDim2.fromOffset(22, 22)
cursorMark.AnchorPoint = Vector2.new(0.5, 0.5)
cursorMark.BackgroundColor3 = UIKit.ACCENT
cursorMark.BackgroundTransparency = 0.25
cursorMark.Visible = false
UIKit.corner(cursorMark, 11)
cursorMark.Parent = cursorGui
cursorGui.Parent = player:WaitForChild("PlayerGui")

local cursorWorld = Vector2.new(0, 0) -- offset from the lane origin, studs
local CURSOR_SPEED = 20 -- studs/sec
local moveAxis = Vector2.new(0, 0) -- from Thumbstick1
local heldArrowKeys: { [Enum.KeyCode]: boolean } = {}

local function clampCursor(v: Vector2): Vector2
	return Vector2.new(
		math.clamp(v.X, -Config.LANE_HALF_WIDTH, Config.LANE_HALF_WIDTH),
		math.clamp(v.Y, Config.DESPAWN_Y, Config.SPAWN_Y)
	)
end

local function keyAxis(): Vector2
	local x = (if heldArrowKeys[Enum.KeyCode.Right] then 1 else 0) - (if heldArrowKeys[Enum.KeyCode.Left] then 1 else 0)
	local y = (if heldArrowKeys[Enum.KeyCode.Up] then 1 else 0) - (if heldArrowKeys[Enum.KeyCode.Down] then 1 else 0)
	return Vector2.new(x, y)
end

UserInputService.InputChanged:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		moveAxis = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

local ARROW_KEYS = {
	[Enum.KeyCode.Left] = true,
	[Enum.KeyCode.Right] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true,
}

-- Nearest of THIS lane's own live steps to `worldPos`, within grab reach --
-- the snap-assist target (doc 15 item 7).
local function nearestOwnStep(worldPos: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, inst in playField.Steps:GetChildren() do
		if
			inst:IsA("BasePart")
			and inst:GetAttribute("Kind") == "Step"
			and inst:GetAttribute("LaneUserId") == player.UserId
		then
			local d = (inst.Position - worldPos).Magnitude
			if d < bestDist then
				bestDist, best = d, inst
			end
		end
	end
	if best and bestDist <= Config.MAX_GRAB_DISTANCE then
		return best
	end
	return nil
end

local function gamepadGrab()
	if frogIsDead() or runState ~= "Playing" then
		return
	end
	local slot = getFreeSlot()
	if not slot then
		return
	end
	local worldPos = laneOrigin() + Vector3.new(cursorWorld.X, cursorWorld.Y, 0)
	local step = nearestOwnStep(worldPos)
	if not step then
		return
	end
	slot.heldStep = step -- optimistic; the server corrects via ForceRelease
	ClientSettings.playIfEnabled(SoundFX, "grab")
	GrabStep:FireServer(step, worldPos) -- snap-assist picks the step; the cursor's accuracy still grades the grab
end

local function gamepadRelease()
	for i = #slots, 1, -1 do
		if slots[i].heldStep then
			releaseSlot(i)
			break
		end
	end
end

local function gamepadTongue()
	if frogIsDead() or runState ~= "Playing" then
		return
	end
	local headInstance = myFrog:FindFirstChild("Head")
	local origin = if headInstance and headInstance:IsA("BasePart") then headInstance.Position else laneOrigin()
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, inst in playField.Bugs:GetChildren() do
		if
			inst:IsA("BasePart")
			and inst:GetAttribute("Kind") == "Bug"
			and inst:GetAttribute("LaneUserId") == player.UserId
		then
			local d = (inst.Position - origin).Magnitude
			if d < bestDist then
				bestDist, best = d, inst
			end
		end
	end
	if best then
		CatchBug:FireServer(best)
		expandTongue(best.Position)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if ARROW_KEYS[input.KeyCode] then
		heldArrowKeys[input.KeyCode] = true
	end
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonA then
		gamepadGrab()
	elseif input.KeyCode == Enum.KeyCode.ButtonL2 or input.KeyCode == Enum.KeyCode.ButtonX then
		gamepadRelease()
	elseif input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.ButtonY then
		gamepadTongue()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if ARROW_KEYS[input.KeyCode] then
		heldArrowKeys[input.KeyCode] = nil
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if runState ~= "Playing" then
		cursorMark.Visible = false
		return
	end
	local axis = if moveAxis.Magnitude > 0.15 then moveAxis else keyAxis()
	if axis.Magnitude > 0 then
		cursorWorld = clampCursor(cursorWorld + axis * CURSOR_SPEED * dt)
	end
	if inputState:GetAttribute("Gamepad") ~= true then
		cursorMark.Visible = false
		return
	end
	local worldPos = laneOrigin() + Vector3.new(cursorWorld.X, cursorWorld.Y, 0)
	local screenPoint, onScreen = camera:WorldToViewportPoint(worldPos)
	cursorMark.Position = UDim2.fromOffset(screenPoint.X, screenPoint.Y)
	cursorMark.Visible = onScreen
end)

-- ---------------------------------------------------------------------------
-- HUD (built in code so the script is self-contained; or wire to StarterGui).
-- doc 15 item 5: score/best (existing) + Flys/bugs-this-run/level-name toast.
-- ---------------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
local hud = UIKit.screenGui("HUD")

local function makeLabel(name: string, posY: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.fromOffset(220, 32)
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
local bestLabel = makeLabel("HighScoreLabel", 48)
local flysLabel = makeLabel("FlysLabel", 84)
local bugsLabel = makeLabel("BugsLabel", 120)
flysLabel.TextColor3 = UIKit.SUBTEXT
bugsLabel.TextColor3 = UIKit.SUBTEXT

-- Level-name toast (doc 15 item 5): fades in/out on LevelChanged. GameClient
-- listens independently of LevelClient.client.luau (both are valid
-- OnClientEvent listeners on the same RemoteEvent) purely for this cosmetic.
local toast = UIKit.label("LevelToast", "", UDim2.fromOffset(300, 44), UDim2.new(0.5, -150, 0, 16), hud)
toast.TextColor3 = UIKit.ACCENT
toast.Font = Enum.Font.GothamBlack
toast.BackgroundTransparency = 1
toast.TextTransparency = 1

local toastToken = 0
LevelChanged.OnClientEvent:Connect(function(levelName: string)
	toastToken += 1
	local myToken = toastToken
	toast.Text = levelName
	toast.TextTransparency = 0
	task.delay(1.6, function()
		if toastToken ~= myToken then
			return -- a newer level toast has already started
		end
		local tween = TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1 })
		tween:Play()
	end)
end)

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

ProfileChanged.OnClientEvent:Connect(function(profile: any)
	flysLabel.Text = "Flys: " .. tostring((profile and profile.flys) or 0)
end)

-- Bugs caught THIS RUN: BugCaught only fires on a confirmed catch (BugService
-- validates before firing it), so counting its events client-side is exact,
-- unlike the server's own end-of-run amount-based heuristic (doc 15 item 1).
local bugsThisRun = 0
local function refreshBugsLabel()
	bugsLabel.Text = "Bugs: " .. tostring(bugsThisRun)
end
refreshBugsLabel()
BugCaught.OnClientEvent:Connect(function()
	bugsThisRun += 1
	refreshBugsLabel()
end)
RunStateChanged.OnClientEvent:Connect(function(state: string)
	if state == "Playing" then
		bugsThisRun = 0
		refreshBugsLabel()
	end
end)

-- Death/respawn is entirely server-driven; the GameOver remote is feedback-only
-- (Effects.client.luau plays the fall sound).

-- ---------------------------------------------------------------------------
-- Pause (doc 15 item 4): deliberately client-only, no server round-trip. A
-- multiplayer server can't pause for one player without affecting everyone
-- else's fairness, and the frog already only falls while holding zero steps
-- -- so there's nothing server-side TO pause. This is an honest status panel
-- instead of a real pause: holding a step means gravity is already frozen
-- (nothing more to do); holding nothing means the run keeps falling behind
-- the panel, and it says so rather than pretending otherwise. Resume's 3-2-1
-- is purely a visual beat before hiding the panel -- it doesn't stop or
-- resume anything server-side.
-- ---------------------------------------------------------------------------
local pauseGui = UIKit.screenGui("PauseGui")
local pauseButton = UIKit.button("Pause", "II", UDim2.fromOffset(44, 44), UDim2.new(1, -56, 0, 12), pauseGui)
pauseButton.Visible = false

local pausePanel = UIKit.panel("PausePanel", UDim2.fromOffset(260, 170), UDim2.new(0.5, -130, 0.5, -85), pauseGui)
pausePanel.Visible = false
pausePanel.ZIndex = 5
local pauseStatus = UIKit.label("Status", "", UDim2.fromOffset(220, 80), UDim2.fromOffset(20, 16), pausePanel)
pauseStatus.TextWrapped = true
local resumeButton = UIKit.button("Resume", "Resume", UDim2.fromOffset(220, 44), UDim2.fromOffset(20, 106), pausePanel)

local function isHoldingAnything(): boolean
	for _, slot in slots do
		if slot.heldStep then
			return true
		end
	end
	return false
end

local function openPause()
	if runState ~= "Playing" then
		return
	end
	pauseStatus.Text = if isHoldingAnything()
		then "Held steps don't fall -- you're genuinely paused."
		else "You're not holding a step, so the run keeps going!"
	resumeButton.Text = "Resume"
	resumeButton.Active = true
	pausePanel.Visible = true
end

local function closePauseWithCountdown()
	resumeButton.Active = false
	task.spawn(function()
		for _, text in { "3", "2", "1", "Go!" } do
			resumeButton.Text = text
			task.wait(0.3)
		end
		pausePanel.Visible = false
		resumeButton.Active = true
	end)
end

pauseButton.Activated:Connect(openPause)
resumeButton.Activated:Connect(closePauseWithCountdown)
RunStateChanged.OnClientEvent:Connect(function(state: string)
	pauseButton.Visible = state == "Playing"
	if state ~= "Playing" then
		pausePanel.Visible = false
	end
end)
pauseGui.Parent = playerGui

-- ---------------------------------------------------------------------------
-- Race rail (doc 15 item 5): a vertical strip on the right edge showing every
-- OTHER player's current run score as a marker between 0 and the highest
-- score anyone (including me) has reached this session -- so you can tell
-- who's ahead even when their lane has scrolled off-screen. Reads
-- leaderstats.Score directly (doc 07 already keeps that live and public);
-- no new remote needed.
-- ---------------------------------------------------------------------------
local railGui = UIKit.screenGui("RaceRail")
local rail = Instance.new("Frame")
rail.Name = "Rail"
rail.Size = UDim2.new(0, 6, 1, -160)
rail.Position = UDim2.new(1, -18, 0, 80)
rail.BackgroundColor3 = UIKit.SUBTEXT
rail.BackgroundTransparency = 0.7
rail.Parent = railGui
UIKit.corner(rail, 3)
railGui.Parent = playerGui

local railMarkers: { [Player]: Frame } = {}
local function markerFor(otherPlayer: Player): Frame
	local existing = railMarkers[otherPlayer]
	if existing then
		return existing
	end
	local marker = Instance.new("Frame")
	marker.Name = "Marker_" .. otherPlayer.UserId
	marker.Size = UDim2.fromOffset(14, 14)
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.BackgroundColor3 = UIKit.ACCENT
	marker.Parent = rail
	UIKit.corner(marker, 7)
	railMarkers[otherPlayer] = marker
	return marker
end

Players.PlayerRemoving:Connect(function(otherPlayer)
	local marker = railMarkers[otherPlayer]
	if marker then
		marker:Destroy()
		railMarkers[otherPlayer] = nil
	end
end)

task.spawn(function()
	while true do
		local maxScore = 1
		for _, otherPlayer in Players:GetPlayers() do
			local stats = otherPlayer:FindFirstChild("leaderstats")
			local score = stats and stats:FindFirstChild("Score")
			if score and score:IsA("IntValue") then
				maxScore = math.max(maxScore, score.Value)
			end
		end
		for _, otherPlayer in Players:GetPlayers() do
			if otherPlayer ~= player then
				local stats = otherPlayer:FindFirstChild("leaderstats")
				local score = stats and stats:FindFirstChild("Score")
				local value = if score and score:IsA("IntValue") then score.Value else 0
				local marker = markerFor(otherPlayer)
				local alpha = math.clamp(value / maxScore, 0, 1)
				marker.Position = UDim2.fromScale(0.5, 1 - alpha)
			end
		end
		task.wait(0.5)
	end
end)
