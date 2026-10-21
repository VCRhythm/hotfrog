--!strict
-- StarterPlayerScripts/Client/WorldChef (LocalScript)
-- Draws the Kitchen's Chef (owner's ruling b-20261012-141130-fhme, doc 17) for
-- every lane whose `Level` is "Kitchen": the Chef head sprite on a ChefBody
-- sprite, wandering behind the steps, and the tells and follow-through of
-- whatever server/Chef.luau has him doing. Purely cosmetic: it reads the lane
-- folder's ChefAction / ChefPhase / ChefSeq / ChefShoveDir / ChefPhaseStart /
-- ChefPhaseDuration / ChefSwingContact attributes and the target step's
-- `ChefTarget`, and never moves a server-owned part (the server breaks or
-- slides the step).
--   Knife -- ducks out to the lane's side edge, comes back in from it IN FRONT
--            of the frog and the steps, pulls the knife back (the tell), then
--            swings it horizontally in slow motion (a 2D side-scroller slash, the
--            tip on a flattened ellipse round his shoulder) so the blade crosses
--            the step at ChefSwingContact, the moment the server drops it; then
--            walks back out to the edge and returns to wandering behind
--   Food  -- winds back a potato (the tell) and lobs it onto the step
--   Shove -- walks to the step's far side, sets his fist against it with an
--            arrow showing which way (the tell), then jabs it along
-- The arm is the ChefArm sprite (sleeve, forearm, fist, knife) stretched from
-- his shoulder to the point it is reaching for, like the frog's arm.
-- A red ring pulses behind the target for the whole tell.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local Lanes = require(script.Parent.world.Lanes)

local stepsFolder = workspace:WaitForChild("PlayField"):WaitForChild("Steps")

-- Chef.png is a 2048px canvas; at this size the head (with hat) stands about
-- 10 studs wide and 15 tall, its art ending 5.27 studs below the part's centre.
local CHEF_SIZE = 20
-- Depths. Behind: in front of WorldScenery's dressing (-1), behind the steps.
-- Front (the Knife): in front of the steps (0), the gripping frog hand (+0.3),
-- the touch dot (+0.6) and the potato / arrow FX plane (+1).
local CHEF_Z = Config.PLANE_Z - 0.8
local FRONT_Z = Config.PLANE_Z + 1.5
local BODY_DZ = -0.1 -- the body just behind the head (front face -0.85 behind: still before the scenery's -0.9)
local ARM_DZ = 0.2 -- the knife arm, in front of his own body and head
local MARK_Z = Config.PLANE_Z - 0.6 -- the target ring, just behind the step
local FX_Z = Config.PLANE_Z + 1 -- potato, arrow, and the Food / Shove arm: in front of the step they hit
local MARK_COLOR = Color3.fromRGB(255, 40, 40)

-- Body: ChefBody.png is a 1024px canvas whose art (x 311-825, y 2-650) is a
-- headless coat, apron, trousers and shoes with the collar flush to the top.
-- 38 studs makes the coat ~19 studs across (two head widths: "a huge body,
-- sized correctly to his head", b-20261020-215940-pyvu) and ~24 neck to feet.
local BODY_SIZE = 38
local BODY_DX = (568 - 512) / 1024 * BODY_SIZE -- the art's centre sits right of the canvas centre
local COLLAR_Y = -4.8 -- the collar top, tucked just under the head's bottom (-5.27)
-- Where the arm sprite's sleeve meets the coat (px ~±173 from the art's centre,
-- 95 down), from the chef part's centre; X is mirrored toward what he faces.
local SHOULDER_DX = 173 / 1024 * BODY_SIZE
local SHOULDER_Y = COLLAR_Y - 95 / 1024 * BODY_SIZE

-- Arm: ChefArm.png is 256x1024 with the sleeve at the top (y 2), the fist at
-- ~66% of the visible length and the blade tip at its bottom (y 932). The part
-- is the whole canvas, stretched lengthwise between shoulder and target.
local ARM_CANVAS_W = 4 -- ~2.3 studs of visible arm
local ARM_VISIBLE = 932 / 1024 -- share of the canvas length the art covers
local FIST_FRAC = 0.66
local BLADE_FRAC = 0.875 -- the blade's middle: the part that meets the step

-- Knife swing: the tip runs on an ellipse round the shoulder, R wide and
-- R * SWING_FLAT tall (a horizontal swing seen slightly from above), angle 0
-- = straight at the step, pi = straight behind him, 3pi/2 = in front of his belly.
local SWING_FLAT = 0.32
local THETA_HOLD = 2 * math.pi - 1.0 -- walking in: knife held forward and down
local THETA_BACK = math.pi - 0.45 -- wound up: pulled back behind him, raised
local THETA_HIT = 2 * math.pi - 0.25 -- contact: rising into the horizontal, blade through the step
local THETA_END = 2 * math.pi + 0.5 -- follow-through past the step
local SWING_R_MIN, SWING_R_MAX = 7, 18
-- In front he stands with his centre this far from the lane centre, on the side
-- away from the target (a portrait view is only ~8.8 studs to a side, so most of
-- him is off the edge there and his arm reaches in).
local FRONT_X = 13
local ENTRY_X = Config.LANE_SPACING / 2 + 1 -- off the lane's side edge: where he enters / leaves from
local EXIT_FRAC = 0.4 -- of the Walk: ducking out to the edge (behind) before stepping back in (in front)

-- Idle wander box, relative to the lane origin.
local WANDER_X = 7
local WANDER_Y_MIN, WANDER_Y_MAX = -9, -2
-- The camera centres on the lane origin and a portrait view is only ~8.8 studs to a
-- side, so behind the steps (Food / Shove) the chef's centre never goes further than
-- this from it: the arm stretches the rest of the way to the target.
local CHEF_MAX_X = 4
-- An unresolved target (its ChefTarget mark not replicated yet) is looked for
-- in Steps at most this often, in frames.
local SCAN_FRAMES = 10

type View = {
	folder: Folder,
	model: Folder,
	chef: BasePart,
	body: BasePart,
	arm: BasePart,
	potato: BasePart,
	mark: BasePart,
	arrow: BasePart,
	arrowDecal: Decal,
	pos: Vector3, -- chef (head part) centre, relative to the lane origin
	goal: Vector3,
	wanderTimer: number,
	clock: number, -- seconds into the current phase (combo-scaled like the server's waits)
	phase: string?,
	seq: number,
	target: BasePart?,
	targetGen: any, -- the target's `Gen` (spawn generation) when resolved; a change means it was recycled
	side: number, -- which side of the target the chef stands (-1 left, +1 right)
	throwFrom: Vector3?, -- where the potato left his hand (nil: the WindUp wasn't seen)
	scanIn: number,
	front: boolean, -- drawn in front of the frog (the Knife), else behind the steps
	walkFrom: Vector3, -- Knife Walk: where he set off from
	stance: Vector3?, -- Knife: his spot for the swing, relative to the origin (frozen at contact)
	reach: number, -- Knife: the swing ellipse's R for that stance
}

local views: { [Folder]: View } = {}
local rng = Random.new()

local function block(model: Folder, name: string, size: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = Color3.new(1, 1, 1)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

local function sprite(model: Folder, name: string, stem: string, size: number, color: Color3?): (BasePart, Decal)
	local part = block(model, name, Vector3.new(size, size, 0.1))
	local decal = Instance.new("Decal")
	decal.Name = "Art"
	decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
	decal:SetAttribute("Sprite", stem)
	if color then
		decal.Color3 = color
	end
	decal.Parent = part
	SpriteSkin.apply(part)
	-- the part is the sprite's whole canvas: hide the box once the art resolved
	part.Transparency = if decal.Texture ~= "" then 1 else 0
	return part, decal
end

local function setShown(part: BasePart, view: View, shown: boolean)
	local parent = if shown then view.model else nil
	if part.Parent ~= parent then
		part.Parent = parent
	end
end

-- The ChefArm sprite from `shoulder` with the point `frac` along its visible
-- length (1 = the blade tip, FIST_FRAC = the fist) on `at`: the canvas is
-- stretched lengthwise like the frog's arm, its sleeve (top edge) at the shoulder.
local function placeArm(part: BasePart, shoulder: Vector3, at: Vector3, frac: number)
	local d = at - shoulder
	local dist = math.max(d.Magnitude, 0.3)
	local dir = if d.Magnitude > 1e-3 then d.Unit else Vector3.new(0, -1, 0)
	local length = dist / frac / ARM_VISIBLE
	part.Size = Vector3.new(ARM_CANVAS_W, length, 0.1)
	-- the part's +Y (the image's top, the sleeve) points back at the shoulder
	part.CFrame = CFrame.new(shoulder + dir * (length / 2))
		* CFrame.Angles(0, 0, math.atan2(-dir.Y, -dir.X) - math.pi / 2)
end

-- The swing ellipse's offset from the shoulder at angle `theta`, facing `f`.
local function swingOffset(theta: number, r: number, f: number): Vector3
	return Vector3.new(f * r * math.cos(theta), r * SWING_FLAT * math.sin(theta), 0)
end

local function onLaneAdded(folder: Folder)
	if views[folder] then
		return
	end
	local model = Instance.new("Folder")
	model.Name = "Chef_" .. folder.Name
	model.Parent = workspace
	local body = sprite(model, "ChefBody", "ChefBody", BODY_SIZE)
	local chef = sprite(model, "Chef", "Chef", CHEF_SIZE)
	local arm = sprite(model, "ChefArm", "ChefArm", 1)
	local mark = sprite(model, "ChefMark", "Circle", 6, MARK_COLOR)
	local arrow, arrowDecal = sprite(model, "ChefArrow", "ArrowRight", 4, MARK_COLOR)
	local potato = sprite(model, "ChefPotato", "Potato", 3)
	views[folder] = {
		folder = folder,
		model = model,
		chef = chef,
		body = body,
		arm = arm,
		potato = potato,
		mark = mark,
		arrow = arrow,
		arrowDecal = arrowDecal,
		pos = Vector3.new(0, -6, 0),
		goal = Vector3.new(0, -6, 0),
		wanderTimer = 0,
		clock = 0,
		phase = nil,
		seq = 0,
		target = nil,
		targetGen = nil,
		side = 1,
		throwFrom = nil,
		scanIn = 0,
		front = false,
		walkFrom = Vector3.new(0, -6, 0),
		stance = nil,
		reach = SWING_R_MIN,
	}
end

local function onLaneRemoved(folder: Folder)
	local view = views[folder]
	if view then
		views[folder] = nil
		view.model:Destroy()
	end
end

Lanes.observe(onLaneAdded, onLaneRemoved)

local function findTarget(userId: any): BasePart?
	for _, child in stepsFolder:GetChildren() do
		if
			child:IsA("BasePart")
			and child:GetAttribute("ChefTarget") == true
			and child:GetAttribute("LaneUserId") == userId
		then
			return child
		end
	end
	return nil
end

local function hideAll(view: View)
	for _, part in { view.chef, view.body, view.arm, view.potato, view.mark, view.arrow } do
		setShown(part, view, false)
	end
end

-- Swing progress 0..1 on the server's clock (Chef.luau's contract: the Swing runs
-- in real time from ChefPhaseStart for ChefPhaseDuration), so the blade meets the
-- step on the same instant the server drops it. Falls back to the local clock.
local function swingProgress(view: View): number
	local start = view.folder:GetAttribute("ChefPhaseStart")
	local duration = view.folder:GetAttribute("ChefPhaseDuration")
	if typeof(start) == "number" and typeof(duration) == "number" and duration > 0 then
		return math.clamp((workspace:GetServerTimeNow() - start) / duration, 0, 1)
	end
	return math.clamp(view.clock / Config.CHEF_SWING_TIME, 0, 1)
end

local function easeInOut(a: number): number
	return a * a * (3 - 2 * a)
end

-- The tip's angle `u` (0..1) into the swing, `contact` being where it crosses
-- the step: speeding up into the blow, slowing through the follow-through.
local function swingTheta(u: number, contact: number): number
	contact = math.clamp(contact, 1e-3, 1)
	if u < contact then
		local a = u / contact
		return THETA_BACK + (THETA_HIT - THETA_BACK) * a ^ 1.6
	end
	local b = math.clamp((u - contact) / math.max(1 - contact, 1e-3), 0, 1)
	return THETA_HIT + (THETA_END - THETA_HIT) * (1 - (1 - b) * (1 - b))
end

-- Knife: where he stands for the swing (head centre, relative to the origin) and
-- the ellipse R that puts the blade's middle on the step at THETA_HIT.
local function knifeStance(stepRel: Vector3, side: number): (Vector3, number)
	local f = -side -- facing: toward the step
	local hit = swingOffset(THETA_HIT, 1, f) * BLADE_FRAC -- per unit R
	local wantShoulderX = side * (FRONT_X - SHOULDER_DX)
	local r = math.clamp((stepRel.X - wantShoulderX) / hit.X, SWING_R_MIN, SWING_R_MAX)
	local shoulder = stepRel - hit * r
	return Vector3.new(shoulder.X - f * SHOULDER_DX, shoulder.Y - SHOULDER_Y, 0), r
end

local function update(view: View, dt: number, now: number)
	local folder = view.folder
	if folder:GetAttribute("Level") ~= "Kitchen" or folder:GetAttribute("RunState") == "Menu" then
		view.phase = nil
		view.target = nil
		view.front = false
		view.stance = nil
		if view.chef.Parent then
			hideAll(view)
		end
		return
	end
	local origin = Lanes.originOf(folder)
	local action = folder:GetAttribute("ChefAction")
	local phase = folder:GetAttribute("ChefPhase")
	local seq = folder:GetAttribute("ChefSeq")
	local newAction = false
	if typeof(seq) == "number" and seq ~= view.seq then
		view.seq = seq
		view.target = nil
		view.stance = nil
		newAction = true
	end
	if phase ~= view.phase then
		if phase == "Flight" then
			-- only a potato this client saw wound back has a real launch point
			view.throwFrom = if view.phase == "WindUp" then view.potato.Position else nil
		elseif phase == "Walk" then
			view.walkFrom = view.pos
		end
		view.phase = if typeof(phase) == "string" then phase else nil
		view.clock = 0
	else
		-- Combo streak (b-20261010-192608-4bs3): the server runs every
		-- phase but Strike and Swing faster by the lane's StreakSpeed, so the
		-- animation clock must too or the tell would be cut off part-way (Chef.tick).
		local speed = folder:GetAttribute("StreakSpeed")
		local realTime = phase == "Strike" or phase == "Swing"
		view.clock += if not realTime and typeof(speed) == "number" then dt * speed else dt
	end
	local clock = view.clock

	-- Resolve the target: on a new action, then at most every SCAN_FRAMES frames
	-- while its ChefTarget mark hasn't replicated yet. Once seen it is kept
	-- through the Strike, when the struck step may already be on its way out.
	local target = view.target
	local lost = not target or target.Parent ~= stepsFolder or target:GetAttribute("ChefTarget") ~= true
	if lost and target and phase == "Strike" then
		lost = false
		-- recycled mid-follow-through (out of the folder, or already handed to
		-- another spawn/lane via the pool): nothing left to draw on
		if
			target.Parent ~= stepsFolder
			or target:GetAttribute("Gen") ~= view.targetGen
			or target:GetAttribute("LaneUserId") ~= folder:GetAttribute("UserId")
		then
			target = nil
		end
	end
	view.scanIn -= 1
	if action and lost and (newAction or view.scanIn <= 0) then
		view.scanIn = SCAN_FRAMES
		target = findTarget(folder:GetAttribute("UserId"))
		view.target = target
		view.targetGen = if target then target:GetAttribute("Gen") else nil
		if target then
			local relX = target.Position.X - origin.X
			view.side = if relX > 0 then -1 else 1 -- stand on the lane-centre side of it
		end
	end
	if not action then
		target = nil
	end
	local stepPos = if target then Vector3.new(target.Position.X, target.Position.Y, FX_Z) else nil
	local side = view.side
	local shoveDir = (folder:GetAttribute("ChefShoveDir") :: number?) or 1

	-- Knife swing progress (server clock) and whether the blade has met the step.
	local contact = (folder:GetAttribute("ChefSwingContact") :: number?) or Config.CHEF_SWING_CONTACT
	local swingU = if action == "Knife" and phase == "Swing" then swingProgress(view) else 0
	local struck = action == "Knife" and phase == "Swing" and swingU >= contact
	-- The stance follows the step (it scrolls with the pulls) until contact, then
	-- stays put while the broken step drops away.
	if action == "Knife" and stepPos and not struck then
		view.stance, view.reach = knifeStance(stepPos - origin, side)
	end
	local stance = if action == "Knife" then view.stance else nil

	-- Where the chef wants to be.
	local before = view.pos
	local rate = 1.2
	local scripted: Vector3? = nil
	if action == "Knife" and stance then
		if phase == "Walk" then
			-- out to the side edge behind the steps, then back in from it in front
			local p = math.clamp(clock / Config.CHEF_WALK_TIME, 0, 1)
			local entry = Vector3.new(side * ENTRY_X, stance.Y, 0)
			if p < EXIT_FRAC then
				scripted = view.walkFrom:Lerp(entry, easeInOut(p / EXIT_FRAC))
			else
				view.front = true
				scripted = entry:Lerp(stance, 1 - (1 - (p - EXIT_FRAC) / (1 - EXIT_FRAC)) ^ 2)
			end
		else
			-- the tell and the swing (or a client that missed the walk): at his spot
			view.front = true
			view.goal = stance
			rate = 10
		end
	elseif action == "Knife" then
		-- target not resolved yet: head for the edge he'll come in from
		view.goal = Vector3.new(side * ENTRY_X, view.pos.Y, 0)
		rate = 6
	elseif view.front then
		-- the knife is done (or fizzled): walk back out the side he came in from
		local exitX = (if view.pos.X >= 0 then 1 else -1) * ENTRY_X
		view.goal = Vector3.new(exitX, view.pos.Y, 0)
		rate = 6
		if math.abs(view.pos.X - exitX) < 2 then
			view.front = false
			view.wanderTimer = 0
		end
	elseif target and action == "Shove" then
		side = -shoveDir -- behind the step, pushing it away from himself
		view.side = side
		view.goal = Vector3.new(
			math.clamp(target.Position.X + side * 14 - origin.X, -CHEF_MAX_X, CHEF_MAX_X),
			target.Position.Y - 3 - origin.Y,
			0
		)
		rate = 6
	elseif not action then
		view.wanderTimer -= dt
		if view.wanderTimer <= 0 then
			view.wanderTimer = rng:NextNumber(2.5, 4.5)
			view.goal = Vector3.new(rng:NextNumber(-WANDER_X, WANDER_X), rng:NextNumber(WANDER_Y_MIN, WANDER_Y_MAX), 0)
		end
	end
	view.pos = scripted or (before + (view.goal - before) * (1 - math.exp(-rate * dt)))
	local speed = (view.pos - before).Magnitude / math.max(dt, 1e-3)
	local moving = math.clamp(speed / 6, 0, 1)
	local bob = math.abs(math.sin(now * 9)) * moving * 0.6
	local chefCenter = origin + Vector3.new(view.pos.X, view.pos.Y + bob, 0)
	local lean = math.clamp((view.pos.X - before.X) / math.max(dt, 1e-3) * -0.02, -0.15, 0.15)
	local z = if view.front then FRONT_Z else CHEF_Z
	view.chef.CFrame = CFrame.new(chefCenter.X, chefCenter.Y, z) * CFrame.Angles(0, 0, lean)
	setShown(view.chef, view, true)
	-- the body hangs from the collar, rocking side to side while he walks
	local waddle = math.sin(now * 9) * moving * 0.06
	view.body.CFrame = view.chef.CFrame
		* CFrame.new(0, COLLAR_Y, BODY_DZ)
		* CFrame.Angles(0, 0, waddle)
		* CFrame.new(-BODY_DX, -BODY_SIZE / 2, 0)
	setShown(view.body, view, true)
	-- the shoulder facing the target (or the lane centre while idle)
	local facing = if action == "Knife"
		then -side
		elseif target then (if target.Position.X >= chefCenter.X then 1 else -1)
		else 1
	local shoulderAt = view.chef.CFrame * Vector3.new(facing * SHOULDER_DX, SHOULDER_Y, 0)
	local armZ = if view.front then FRONT_Z + ARM_DZ else FX_Z
	local shoulder = Vector3.new(shoulderAt.X, shoulderAt.Y, armZ)

	-- The target ring: the whole tell, gone once the blow lands.
	local telling = stepPos ~= nil and phase ~= "Strike" and not struck
	if telling and stepPos then
		local pulse = 1 + 0.15 * math.sin(now * 14)
		view.mark.Size = Vector3.new(6 * pulse, 6 * pulse, 0.1)
		view.mark.CFrame = CFrame.new(stepPos.X, stepPos.Y, MARK_Z)
	end
	setShown(view.mark, view, telling)

	local showArm, showPotato, showArrow = false, false, false
	if action == "Knife" and stance and view.front then
		showArm = true
		local r = view.reach
		local theta = THETA_HOLD + math.sin(now * 9) * moving * 0.15
		if phase == "WindUp" then
			-- pulls the knife back behind him, then holds it there trembling
			local tell = math.clamp(clock / Config.CHEF_WINDUP_TIME, 0, 1)
			theta = THETA_HOLD + (THETA_BACK - THETA_HOLD) * easeInOut(math.clamp(tell / 0.6, 0, 1))
			theta += math.sin(now * 40) * 0.05 * tell
		elseif phase == "Swing" then
			theta = swingTheta(swingU, contact)
		end
		placeArm(view.arm, shoulder, shoulder + swingOffset(theta, r, facing), 1)
	elseif action == "Food" then
		showArm, showPotato = true, true
		local hand = shoulder + Vector3.new(facing * 3.5, 3, 0)
		if phase == "WindUp" then
			-- wound back over his shoulder, wobbling
			local tell = math.clamp(clock / Config.CHEF_WINDUP_TIME, 0, 1)
			local p = hand + Vector3.new(-facing * 5 * tell, 2 * tell + math.sin(now * 30) * 0.2 * tell, 0)
			view.potato.CFrame = CFrame.new(p) * CFrame.Angles(0, 0, now * 2)
			placeArm(view.arm, shoulder, p, FIST_FRAC)
		elseif phase == "Flight" and stepPos then
			local a = math.clamp(clock / Config.CHEF_FOOD_FLIGHT_TIME, 0, 1)
			local from = view.throwFrom or (hand + Vector3.new(-facing * 5, 2, 0))
			local p = from:Lerp(stepPos, a) + Vector3.new(0, 6 * 4 * a * (1 - a), 0)
			view.potato.CFrame = CFrame.new(p) * CFrame.Angles(0, 0, -now * 12)
			placeArm(view.arm, shoulder, hand + Vector3.new(facing * 2, -1, 0), FIST_FRAC)
		elseif stepPos then -- Strike: lands on the step and goes down with it
			view.potato.CFrame = CFrame.new(stepPos + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, -now * 6)
			placeArm(view.arm, shoulder, hand, FIST_FRAC)
		else
			showPotato = false
			placeArm(view.arm, shoulder, hand, FIST_FRAC)
		end
	elseif action == "Shove" then
		showArm = true
		local halfWidth = 2
		local hitSize = target and target:GetAttribute("HitSize")
		if typeof(hitSize) == "Vector2" then
			halfWidth = hitSize.X / 2
		end
		local reach = if stepPos then stepPos + Vector3.new(side * (halfWidth + 0.8), 0, 0) else shoulder
		if phase == "WindUp" then
			-- fist set against the step, drawing back as it builds
			local tell = math.clamp(clock / Config.CHEF_WINDUP_TIME, 0, 1)
			reach += Vector3.new(side * 1.2 * tell, 0, 0)
		elseif phase == "Walk" or not stepPos then
			reach = shoulder + Vector3.new(-side * 4, -1, 0)
		end
		placeArm(view.arm, shoulder, reach, FIST_FRAC)
		if stepPos and phase == "WindUp" then
			showArrow = true
			local stem = if shoveDir > 0 then "ArrowRight" else "ArrowLeft"
			if view.arrowDecal:GetAttribute("Sprite") ~= stem then
				view.arrowDecal:SetAttribute("Sprite", stem)
				SpriteSkin.apply(view.arrow)
			end
			local nudge = math.sin(now * 12) * 0.4
			view.arrow.CFrame = CFrame.new(stepPos + Vector3.new(shoveDir * (halfWidth + 3 + nudge), 0, 0))
		end
	end
	setShown(view.arm, view, showArm)
	setShown(view.potato, view, showPotato)
	setShown(view.arrow, view, showArrow)
end

RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	for _, view in views do
		update(view, dt, now)
	end
end)
