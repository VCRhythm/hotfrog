--!strict
-- StarterPlayerScripts/Client/WorldChef (LocalScript)
-- Draws the Kitchen's Chef (owner's ruling b-20261012-141130-fhme, doc 17) for
-- every lane whose `Level` is "Kitchen": the Chef sprite wandering behind the
-- steps, and the tells and follow-through of whatever server/Chef.luau has him
-- doing. Purely cosmetic: it reads the lane folder's ChefAction / ChefPhase /
-- ChefSeq / ChefShoveDir attributes and the target step's `ChefTarget`, and
-- never moves a server-owned part (the server breaks or slides the step).
--   Knife -- walks up beside the step, raises a shaking knife over it (the
--            tell), then chops down through it
--   Food  -- winds back a potato (the tell) and lobs it onto the step
--   Shove -- walks to the step's far side, sets his hand against it with an
--            arrow showing which way (the tell), then jabs it along
-- A red ring pulses behind the target for the whole tell.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local Lanes = require(script.Parent.world.Lanes)

local stepsFolder = workspace:WaitForChild("PlayField"):WaitForChild("Steps")

-- Chef.png is a 2048px canvas with the chef in its upper three quarters; at
-- this size he stands about 10 studs wide and 15 tall, a background figure
-- rather than SceneryKinds' 64-stud drifting giant.
local CHEF_SIZE = 20
local CHEF_Z = Config.PLANE_Z - 0.8 -- in front of WorldScenery's dressing (-1), behind the steps
local MARK_Z = Config.PLANE_Z - 0.6 -- the target ring, just behind the step
local FX_Z = Config.PLANE_Z + 1 -- knife, potato, hand: in front of the step they hit
local SHOULDER = Vector3.new(8, -5, 0) -- from the chef part's centre (X mirrored by side): the coat's edge
local ARM_WIDTH = 2.2
-- The camera centres on the lane origin and a portrait view is only ~8.8 studs to a
-- side, so the chef's centre never goes further than this from it: the arm stretches
-- the rest of the way to the target.
local CHEF_MAX_X = 4
-- Body: Chef.png is a head and hat only (its art ends at about 2.6 studs below the
-- part's centre), so a coat and legs hang from there, posed from the chef part's own
-- CFrame so they follow every step, lean and bob of the head.
local NECK_Y = -2.6
-- Sized to the head (about 10 studs wide, 12 tall with the hat): shoulders two head
-- widths, neck to feet about 2.3 head heights.
local TORSO_SIZE = Vector3.new(18, 14, 0.3)
local LEG_SIZE = Vector3.new(6, 13, 0.3)
local LEG_X = 4.5
local COAT = Color3.fromRGB(245, 245, 245)
local TROUSERS = Color3.fromRGB(70, 75, 90)
local SKIN = Color3.fromRGB(240, 128, 120)
local MARK_COLOR = Color3.fromRGB(255, 40, 40)

-- Idle wander box, relative to the lane origin.
local WANDER_X = 7
local WANDER_Y_MIN, WANDER_Y_MAX = -9, -2
-- An unresolved target (its ChefTarget mark not replicated yet) is looked for
-- in Steps at most this often, in frames.
local SCAN_FRAMES = 10

type View = {
	folder: Folder,
	model: Folder,
	chef: BasePart,
	torso: BasePart,
	legL: BasePart,
	legR: BasePart,
	arm: BasePart,
	blade: BasePart,
	handle: BasePart,
	hand: BasePart,
	potato: BasePart,
	mark: BasePart,
	arrow: BasePart,
	arrowDecal: Decal,
	pos: Vector3, -- chef centre, relative to the lane origin
	goal: Vector3,
	wanderTimer: number,
	clock: number, -- seconds into the current phase
	phase: string?,
	seq: number,
	target: BasePart?,
	targetGen: any, -- the target's `Gen` (spawn generation) when resolved; a change means it was recycled
	side: number, -- which side of the target the chef stands (-1 left, +1 right)
	throwFrom: Vector3?, -- where the potato left his hand (nil: the WindUp wasn't seen)
	scanIn: number, -- frames until the next Steps scan for an unresolved target
}

local views: { [Folder]: View } = {}
local rng = Random.new()

local function block(model: Folder, name: string, size: Vector3, color: Color3, shape: Enum.PartType?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.Color = color
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
	local part = block(model, name, Vector3.new(size, size, 0.1), Color3.new(1, 1, 1))
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

-- A bar from `a` to `b` (an arm, on the FX plane).
local function span(part: BasePart, a: Vector3, b: Vector3)
	local d = b - a
	local length = math.max(d.Magnitude, 0.1)
	part.Size = Vector3.new(ARM_WIDTH, length, 0.2)
	part.CFrame = CFrame.new((a + b) / 2) * CFrame.Angles(0, 0, math.atan2(d.Y, d.X) - math.pi / 2)
end

-- The knife held at `grip`, blade pointing along `angle` (0 = straight up).
local function placeKnife(view: View, grip: Vector3, angle: number)
	local frame = CFrame.new(grip) * CFrame.Angles(0, 0, angle)
	view.blade.CFrame = frame * CFrame.new(0, 2.6, 0)
	view.handle.CFrame = frame * CFrame.new(0, -0.1, 0)
end

local function onLaneAdded(folder: Folder)
	if views[folder] then
		return
	end
	local model = Instance.new("Folder")
	model.Name = "Chef_" .. folder.Name
	model.Parent = workspace
	local torso = block(model, "ChefTorso", TORSO_SIZE, COAT)
	local legL = block(model, "ChefLegL", LEG_SIZE, TROUSERS)
	local legR = block(model, "ChefLegR", LEG_SIZE, TROUSERS)
	local chef = sprite(model, "Chef", "Chef", CHEF_SIZE)
	local mark = sprite(model, "ChefMark", "Circle", 6, MARK_COLOR)
	local arrow, arrowDecal = sprite(model, "ChefArrow", "ArrowRight", 4, MARK_COLOR)
	local potato = sprite(model, "ChefPotato", "Potato", 3)
	views[folder] = {
		folder = folder,
		model = model,
		chef = chef,
		torso = torso,
		legL = legL,
		legR = legR,
		arm = block(model, "ChefArm", Vector3.new(ARM_WIDTH, 1, 0.2), SKIN),
		blade = block(model, "ChefKnifeBlade", Vector3.new(0.9, 4.2, 0.2), Color3.fromRGB(205, 210, 220)),
		handle = block(model, "ChefKnifeHandle", Vector3.new(0.6, 1.6, 0.3), Color3.fromRGB(90, 60, 40)),
		hand = block(model, "ChefHand", Vector3.new(1.6, 1.6, 1.6), SKIN, Enum.PartType.Ball),
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
	for _, part in
		{
			view.chef,
			view.torso,
			view.legL,
			view.legR,
			view.arm,
			view.blade,
			view.handle,
			view.hand,
			view.potato,
			view.mark,
			view.arrow,
		}
	do
		setShown(part, view, false)
	end
end

local function update(view: View, dt: number, now: number)
	local folder = view.folder
	if folder:GetAttribute("Level") ~= "Kitchen" or folder:GetAttribute("RunState") == "Menu" then
		view.phase = nil
		view.target = nil
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
		newAction = true
	end
	if phase ~= view.phase then
		if phase == "Flight" then
			-- only a potato this client saw wound back has a real launch point
			view.throwFrom = if view.phase == "WindUp" then view.potato.Position else nil
		end
		view.phase = if typeof(phase) == "string" then phase else nil
		view.clock = 0
	else
		-- Combo streak (b-20261010-192608-4bs3): the server runs every
		-- phase but Strike faster by the lane's StreakSpeed, so the animation clock
		-- must too or the tell would be cut off part-way (Chef.tick).
		local speed = folder:GetAttribute("StreakSpeed")
		view.clock += if phase ~= "Strike" and typeof(speed) == "number" then dt * speed else dt
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

	-- Where the chef wants to be.
	local chasing = false
	if target and action == "Knife" then
		view.goal = Vector3.new(
			math.clamp(target.Position.X + side * 11 - origin.X, -CHEF_MAX_X, CHEF_MAX_X),
			target.Position.Y - 6 - origin.Y,
			0
		)
		chasing = true
	elseif target and action == "Shove" then
		side = -shoveDir -- behind the step, pushing it away from himself
		view.side = side
		view.goal = Vector3.new(
			math.clamp(target.Position.X + side * 14 - origin.X, -CHEF_MAX_X, CHEF_MAX_X),
			target.Position.Y - 3 - origin.Y,
			0
		)
		chasing = true
	elseif not action then
		view.wanderTimer -= dt
		if view.wanderTimer <= 0 then
			view.wanderTimer = rng:NextNumber(2.5, 4.5)
			view.goal = Vector3.new(rng:NextNumber(-WANDER_X, WANDER_X), rng:NextNumber(WANDER_Y_MIN, WANDER_Y_MAX), 0)
		end
	end
	local before = view.pos
	local rate = if chasing then 6 else 1.2
	view.pos = before + (view.goal - before) * (1 - math.exp(-rate * dt))
	local speed = (view.pos - before).Magnitude / math.max(dt, 1e-3)
	local bob = math.abs(math.sin(now * 9)) * math.clamp(speed / 6, 0, 1) * 0.6
	local chefCenter = origin + Vector3.new(view.pos.X, view.pos.Y + bob, 0)
	local lean = math.clamp((view.pos.X - before.X) / math.max(dt, 1e-3) * -0.02, -0.15, 0.15)
	view.chef.CFrame = CFrame.new(chefCenter.X, chefCenter.Y, CHEF_Z) * CFrame.Angles(0, 0, lean)
	setShown(view.chef, view, true)
	-- the body: coat under the neck, legs stepping while he moves
	local body = view.chef.CFrame
	-- 0.2 back: its front face (-0.85) sits between the head art (-0.75) and the
	-- scenery's front (-0.9), so it neither z-fights the head nor hides behind scenery
	view.torso.CFrame = body * CFrame.new(0, NECK_Y - TORSO_SIZE.Y / 2 + 0.4, -0.2)
	local hipY = NECK_Y - TORSO_SIZE.Y + 0.4
	local stride = math.sin(now * 9) * math.clamp(speed / 6, 0, 1) * 0.3
	view.legL.CFrame = body
		* CFrame.new(-LEG_X, hipY, -0.05)
		* CFrame.Angles(0, 0, stride)
		* CFrame.new(0, -LEG_SIZE.Y / 2, 0)
	view.legR.CFrame = body
		* CFrame.new(LEG_X, hipY, -0.05)
		* CFrame.Angles(0, 0, -stride)
		* CFrame.new(0, -LEG_SIZE.Y / 2, 0)
	setShown(view.torso, view, true)
	setShown(view.legL, view, true)
	setShown(view.legR, view, true)
	-- the shoulder facing the target (or the lane centre while idle)
	local facing = if target then (if target.Position.X >= chefCenter.X then 1 else -1) else 1
	local shoulder = Vector3.new(chefCenter.X + SHOULDER.X * facing, chefCenter.Y + SHOULDER.Y, FX_Z)

	-- The target ring: the whole tell, gone once the blow lands.
	local telling = stepPos ~= nil and phase ~= "Strike"
	if telling and stepPos then
		local pulse = 1 + 0.15 * math.sin(now * 14)
		view.mark.Size = Vector3.new(6 * pulse, 6 * pulse, 0.1)
		view.mark.CFrame = CFrame.new(stepPos.X, stepPos.Y, MARK_Z)
	end
	setShown(view.mark, view, telling)

	local showArm, showKnife, showHand, showPotato, showArrow = false, false, false, false, false
	if action == "Knife" then
		showArm, showKnife = true, true
		local tell = math.clamp(clock / Config.CHEF_WINDUP_TIME, 0, 1)
		if phase == "Walk" and stepPos then
			-- already reaching toward the step he has picked
			local toStep = stepPos - shoulder
			placeKnife(view, shoulder + toStep.Unit * math.min(toStep.Magnitude, 5) + Vector3.new(0, 2, 0), 0)
		elseif phase == "Walk" or not stepPos then
			placeKnife(view, shoulder + Vector3.new(facing * 1.5, 2, 0), 0)
		elseif phase == "WindUp" then
			-- raised high over the step, shaking harder as the chop nears
			local shake = math.sin(now * 45) * 0.25 * tell
			local grip = stepPos + Vector3.new(side * 1.5 + shake, 4 + 1.5 * tell, 0)
			placeKnife(view, grip, -side * (0.3 + 0.5 * tell)) -- blade cocked back toward him
		else -- Strike: chop down across the step, then hold
			local a = math.clamp(clock / 0.12, 0, 1)
			local grip = stepPos + Vector3.new(side * 1.5, 5.5 - 5 * a, 0)
			placeKnife(view, grip, side * (-0.8 + 2.4 * a))
		end
		span(view.arm, shoulder, view.handle.Position)
	elseif action == "Food" then
		showArm, showPotato = true, true
		local hand = shoulder + Vector3.new(facing * 1.5, 1.5, 0)
		if phase == "WindUp" then
			-- wound back behind his head, wobbling
			local tell = math.clamp(clock / Config.CHEF_WINDUP_TIME, 0, 1)
			local p = hand + Vector3.new(-facing * 2 * tell, 2.5 * tell + math.sin(now * 30) * 0.2 * tell, 0)
			view.potato.CFrame = CFrame.new(p) * CFrame.Angles(0, 0, now * 2)
			span(view.arm, shoulder, p)
		elseif phase == "Flight" and stepPos then
			local a = math.clamp(clock / Config.CHEF_FOOD_FLIGHT_TIME, 0, 1)
			local from = view.throwFrom or (hand + Vector3.new(-facing * 2, 2.5, 0))
			local p = from:Lerp(stepPos, a) + Vector3.new(0, 6 * 4 * a * (1 - a), 0)
			view.potato.CFrame = CFrame.new(p) * CFrame.Angles(0, 0, -now * 12)
			span(view.arm, shoulder, hand + Vector3.new(facing * 1.5, -0.5, 0))
		elseif stepPos then -- Strike: lands on the step and goes down with it
			view.potato.CFrame = CFrame.new(stepPos + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, -now * 6)
			span(view.arm, shoulder, hand)
		else
			showPotato = false
			span(view.arm, shoulder, hand)
		end
	elseif action == "Shove" then
		showArm, showHand = true, true
		local halfWidth = 2
		local hitSize = target and target:GetAttribute("HitSize")
		if typeof(hitSize) == "Vector2" then
			halfWidth = hitSize.X / 2
		end
		local reach = if stepPos then stepPos + Vector3.new(side * (halfWidth + 0.8), 0, 0) else shoulder
		if phase == "WindUp" then
			-- hand set against the step, drawing back as it builds
			local tell = math.clamp(clock / Config.CHEF_WINDUP_TIME, 0, 1)
			reach += Vector3.new(side * 1.2 * tell, 0, 0)
		elseif phase == "Walk" then
			reach = shoulder + Vector3.new(-side * 1.5, 0, 0)
		end
		view.hand.CFrame = CFrame.new(reach)
		span(view.arm, shoulder, reach)
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
	setShown(view.blade, view, showKnife)
	setShown(view.handle, view, showKnife)
	setShown(view.hand, view, showHand)
	setShown(view.potato, view, showPotato)
	setShown(view.arrow, view, showArrow)
end

RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	for _, view in views do
		update(view, dt, now)
	end
end)
