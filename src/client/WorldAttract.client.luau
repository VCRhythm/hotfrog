--!strict
-- StarterPlayerScripts/Client/WorldAttract (LocalScript)
-- "Attract mode" (doc 17's known gap): Player/FrogAI.cs is a Controller
-- subclass that runs instead of a human on the main menu. Its Update() calls
-- MoveLimbs() every frame and, every `nextDecisionTime` seconds (initialized
-- to 1f and NEVER reassigned despite the name -- a literal fixed 1s cadence,
-- not a random one), raycasts a random on-screen point and grabs whatever
-- step is under it (Controller.cs CheckTouch/TouchStep -> Limb.SetStep).
-- Controller.cs's own MoveLimbs then either snaps a held limb straight to its
-- step's transform, or SmoothDamps a free limb back to `limbReturnPos`.
--
-- This script owns no real gameplay steps (GameServer/Lane are off-limits, and
-- a Menu-state lane spawns none anyway -- doc 15), so the random-raycast part
-- doesn't port literally. Instead: a small fixed decorative ladder
-- (WorldConfig.ATTRACT_STEP_COUNT rungs) is built beside the parked real frog,
-- and a LOCAL, purely cosmetic clone of the frog rig -- never the server-owned
-- model at workspace.PlayField.Frogs.Frog_<userId> that WorldFrogCosmetics.
-- client.luau already owns -- alternates grabbing its rungs in a fixed
-- up-then-wrap loop on that same 1s cadence. Rendering mirrors MoveLimbs'
-- snap-to-step / ease-to-rest shape exactly (same shape GameServer.server.
-- luau's own frog-render Heartbeat uses for the real frog, doc 15): a held
-- limb snaps to CFrame.new(rung.Position); a free limb Lerps toward
-- body.CFrame * Config.LIMB_REST[i] over Config.LIMB_RETURN_TIME.
--
-- Simplified vs. FrogAI.cs: no raycast/miss branch (the ladder is fixed, so
-- every decision is a "hit"), no screen-space randomness, and the frog's body
-- never moves (FrogAI's own body doesn't either -- only MoveLimbs' limbs do).
--
-- Scope: LOCAL PLAYER ONLY. Unlike WorldScenery/WorldFrogCosmetics (every
-- lane -- other players' menus are genuinely visible), this is a menu-only
-- vignette nobody else needs rendered. Built the instant this player's own
-- lane's RunState attribute (doc 13) reads "Menu"; torn down the instant it
-- doesn't. Not pooled (world/Pool.luau) -- unlike scenery's per-frame spawn
-- churn, this is one ladder + one frog toggled occasionally across a whole
-- session, cheap enough to Destroy/rebuild plainly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local SkinCatalog = require(ReplicatedStorage.Shared.SkinCatalog)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)

local player = Players.LocalPlayer
local playField = workspace:WaitForChild("PlayField")
local lanesFolder = playField:WaitForChild("Lanes")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ProfileChanged = remotes:WaitForChild("ProfileChanged") :: RemoteEvent

-- Lane.luau (server) creates Lanes/<UserId> with Origin/Level/RunState
-- attributes (doc 13) before the player can see anything -- the same
-- WaitForChild GameClient.client.luau already relies on for its own camera
-- target.
local myLane = lanesFolder:WaitForChild(tostring(player.UserId), math.huge) :: Folder

local frogTemplate = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("FrogModel") :: Model

type Attract = {
	model: Model,
	body: BasePart,
	limbs: { BasePart }, -- [1]=Right [2]=Left, Config.LIMB_REST's own ordering
	limbOffsets: { CFrame }, -- rest poses relative to the body (Config.LIMB_REST)
	held: { BasePart? }, -- per-limb: the rung it's currently grabbing, or nil (free)
	rungs: { BasePart },
	nextRung: number, -- 1-based index of the rung the next decision grabs
	limbTurn: number, -- 1 or 2: which limb the next decision moves
	lastDecisionTime: number, -- os.clock()
}

-- ---------------------------------------------------------------------------
-- Current skin (doc 08): ProfileChanged carries `selected`, the SkinCatalog
-- id; SpriteSkin.apply needs the catalog NAME. Re-applied live if the player
-- changes skin from the Menu store while the vignette is up. Defaults to the
-- starter frog until the first ProfileChanged lands (same default the rig
-- itself ships with).
-- ---------------------------------------------------------------------------
local currentSkinName = SkinCatalog[1].name

local function applyCurrentSkin(model: Model)
	SpriteSkin.apply(model, currentSkinName)
end

local attract: Attract? = nil

local function build(origin: Vector3): Attract
	-- The real parked frog (GameServer/WorldFrogCosmetics, untouched by this
	-- file) sits AT the lane origin -- shift this whole vignette a few studs
	-- to the side so it never renders a second frog on top of the first (see
	-- WorldConfig.ATTRACT_ANCHOR_OFFSET).
	local anchor = origin + WorldConfig.ATTRACT_ANCHOR_OFFSET

	local rungs: { BasePart } = {}
	for i = 1, WorldConfig.ATTRACT_STEP_COUNT do
		local part = Instance.new("Part")
		part.Name = "AttractStep"
		part.Size = WorldConfig.ATTRACT_STEP_SIZE
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false -- decorative only, must never eat taps (same rule WorldScenery follows)
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = 1 -- host for the Decal only (see BugService/StepTemplate)
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
		decal:SetAttribute("Sprite", "WhiteRock") -- doc 13: already a SkinAssets stem, flat placeholder until art is uploaded
		decal.Parent = part
		SpriteSkin.apply(part)

		-- Zig-zag ladder, same shape as Lane.luau's own Tutorial ladder
		-- (Config.TUTORIAL_STEP_X alternating sign / Config.TUTORIAL_STEP_GAP
		-- rise per rung), independently scaled down for this decorative one.
		local sign = if i % 2 == 1 then 1 else -1
		local position = anchor + Vector3.new(sign * WorldConfig.ATTRACT_STEP_X, i * WorldConfig.ATTRACT_STEP_Y_GAP, 0)
		part.CFrame = CFrame.new(position)
		part.Parent = workspace
		table.insert(rungs, part)
	end

	local model = frogTemplate:Clone()
	model.Name = "AttractFrog_" .. player.UserId
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			-- Same rule as GameServer.createFrog: the arm/hand sprite parts hang
			-- off their limb part (off-centre Unity sprite pivots) and ride along
			-- welded, since only the limb itself is ever posed.
			local host = descendant.Parent
			if host and host:IsA("BasePart") then
				descendant.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = host
				weld.Part1 = descendant
				weld.Parent = descendant
			else
				descendant.Anchored = true
			end
		end
	end
	applyCurrentSkin(model)

	local body = model.PrimaryPart :: BasePart
	local headInstance = model:FindFirstChild("Head")
	local head = if headInstance and headInstance:IsA("BasePart") then headInstance else nil
	local right = model:FindFirstChild("RightLimb") :: BasePart
	local left = model:FindFirstChild("LeftLimb") :: BasePart
	-- Captured before the body is moved, same as GameServer.server.luau's own
	-- createFrog -- the template's authored CFrames already encode Head's
	-- offset from Body.
	local headOffset = if head then body.CFrame:ToObjectSpace(head.CFrame) else CFrame.identity

	body.CFrame = CFrame.new(anchor)
	if head then
		head.CFrame = body.CFrame * headOffset
	end

	local limbOffsets = {
		CFrame.new(Config.LIMB_REST[1].X, Config.LIMB_REST[1].Y, 0),
		CFrame.new(Config.LIMB_REST[2].X, Config.LIMB_REST[2].Y, 0),
	}
	right.CFrame = body.CFrame * limbOffsets[1]
	left.CFrame = body.CFrame * limbOffsets[2]
	model.Parent = workspace

	return {
		model = model,
		body = body,
		limbs = { right, left },
		limbOffsets = limbOffsets,
		held = {},
		rungs = rungs,
		nextRung = 1,
		limbTurn = 1,
		lastDecisionTime = os.clock(),
	}
end

local function teardown()
	local a = attract
	if not a then
		return
	end
	attract = nil
	a.model:Destroy()
	for _, part in a.rungs do
		part:Destroy()
	end
end

ProfileChanged.OnClientEvent:Connect(function(profile: any)
	local id = profile and profile.selected
	local entry = id and SkinCatalog[id]
	if entry then
		currentSkinName = entry.name
		if attract then
			applyCurrentSkin(attract.model)
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Lifecycle: build the instant the lane is idle-and-unowned-by-a-run (doc 15's
-- "Menu"), tear down the instant it changes to "Playing" or "Dead".
-- ---------------------------------------------------------------------------
local function refreshRunState()
	local isMenu = myLane:GetAttribute("RunState") == "Menu"
	if isMenu and not attract then
		local originAttr = myLane:GetAttribute("Origin")
		local origin: Vector3 = if typeof(originAttr) == "Vector3" then originAttr else Vector3.zero
		attract = build(origin)
	elseif not isMenu and attract then
		teardown()
	end
end

refreshRunState()
myLane:GetAttributeChangedSignal("RunState"):Connect(refreshRunState)

-- ---------------------------------------------------------------------------
-- Decision (FrogAI.cs Update, ATTRACT_DECISION_TIME cadence) + render
-- (Controller.cs MoveLimbs, ADAPTED to CFrames like GameServer's own frog
-- rendering). Cheap: at most 2 limb CFrame writes and one decision branch per
-- frame, only while this player's own lane is idle in Menu.
-- ---------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt: number)
	local a = attract
	if not a then
		return
	end

	local now = os.clock()
	if now - a.lastDecisionTime >= WorldConfig.ATTRACT_DECISION_TIME then
		a.lastDecisionTime = now
		local limbIndex = a.limbTurn
		a.held[limbIndex] = a.rungs[a.nextRung]
		a.nextRung = (a.nextRung % #a.rungs) + 1
		a.limbTurn = if a.limbTurn == 1 then 2 else 1
	end

	local bodyCF = a.body.CFrame -- fixed -- FrogAI's own body never moves either, only its limbs
	for i, limbPart in a.limbs do
		local held = a.held[i]
		if held then
			limbPart.CFrame = CFrame.new(held.Position) -- Controller.cs MoveLimbs: snap straight to the held step's transform
		else
			local target = bodyCF * a.limbOffsets[i]
			local alpha = math.clamp(dt / Config.LIMB_RETURN_TIME, 0, 1)
			limbPart.CFrame = limbPart.CFrame:Lerp(target, alpha) -- same ease-to-rest shape GameServer's frog-render Heartbeat uses
		end
	end
end)
