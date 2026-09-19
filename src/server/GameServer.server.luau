--!strict
-- ServerScriptService/GameServer (Script)
-- Authoritative side of the Hotfrog loop:
--   * spawns & pools steps (Spawning/StepSpawner.cs + ObjectPool.cs), now per
--     Lane (doc 13: one PlayField "lane" per player -- see server/Lane.luau)
--   * owns the pull / world-scroll along each lane's own spawn direction
--     (Spawning/SpawnManager.cs PullStep/PullVector)
--   * owns every frog: position, gravity, limbs, death, respawn (Player/Frog.cs)
--   * tracks score and persists the high score (Core/VariableManager.cs)
--   * drives level flow per lane (Tutorial -> Pot -> Kitchen -> Country)
--
-- Hardened per ../07-multiplayer.md: the client sends intents (taps); the server
-- owns all state. Frog models live in workspace and replicate to every client,
-- which also gives multiplayer frog visibility and server-side skins for free.
-- The frog's motion is autonomous (gravity + grab events -- the client never
-- steers it), so replication latency doesn't hurt feel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local PullMath = require(ReplicatedStorage.Shared.PullMath)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local SkinCatalog = require(ReplicatedStorage.Shared.SkinCatalog)
local StepBehaviors = require(ReplicatedStorage.Shared.StepBehaviors)
local StepKinds = require(ReplicatedStorage.Shared.StepKinds)
local Levels = require(ReplicatedStorage.Shared.Levels)
local Profiles = require(script.Parent.Profiles)
local Lane = require(script.Parent.Lane)

-- ---------------------------------------------------------------------------
-- Remotes (auto-created so you don't have to build them by hand)
-- ---------------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local function ensureRemote(name: string): RemoteEvent
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end
	return r :: RemoteEvent
end

local function ensureRemoteFunction(name: string): RemoteFunction
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = remotes
	end
	return r :: RemoteFunction
end

local GrabStep = ensureRemote("GrabStep") -- client -> server: tapped a step (step, tap world point)
local ReleaseStep = ensureRemote("ReleaseStep") -- client -> server: released a limb
local ScoreChanged = ensureRemote("ScoreChanged") -- server -> client: score/best/quality/grabQuality
local GameOver = ensureRemote("GameOver") -- server -> client: run ended, restart (score, cause)
local ForceRelease = ensureRemote("ForceRelease") -- server -> client: drop this step (Step.cs ForceRelease)
local LevelChanged = ensureRemote("LevelChanged") -- server -> client: this lane's level/transition changed

-- Phase 5 (docs/roblox-port/15-menus-and-input.md): the Menu -> Playing -> Dead
-- -> Menu run-state machine + its remotes. Everything below is additive on top
-- of the existing loop; it never changes GrabStep/ScoreChanged/GameOver/
-- LevelChanged's own contracts, only gates when they fire.
local StartRun = ensureRemote("StartRun") -- client -> server: begin a run from Menu (rate-limited, Menu-only)
local RunStateChanged = ensureRemote("RunStateChanged") -- server -> client: this player's Menu/Playing/Dead state
local RunSummary = ensureRemote("RunSummary") -- server -> client: end-of-run stats for the end-of-run panel (score, newBest, isNewBest, quality, bugs, flys, cause)
local SetMusicOn = ensureRemote("SetMusicOn") -- client -> server: settings toggle (writes profile.musicOn)
local ReplayTutorial = ensureRemote("ReplayTutorial") -- client -> server: settings action (Menu-only)
local GetTopScores = ensureRemoteFunction("GetTopScores") -- client -> server: cached global top-10 (name, score)

local function ensureBindable(name: string): BindableEvent
	local b = ServerStorage:FindFirstChild(name)
	if not b then
		b = Instance.new("BindableEvent")
		b.Name = name
		b.Parent = ServerStorage
	end
	return b :: BindableEvent
end

-- Cross-script spawn request (ActionType.SpawnFly step behavior, doc 05): fired
-- when a FlyRock-style step is grabbed, asking BugService to drift a bug in from
-- the step's position. `lane's userId` rides along so BugService can tag the bug
-- to the right lane (doc 13 item 7). Same BindableEvent-in-ServerStorage pattern
-- as the AwardFlys faucet (SkinService/BugService/GiftService) -- get-or-create
-- so load order between GameServer and BugService is moot.
local spawnBugAt = ensureBindable("SpawnBugAt")

-- Confirmed-catch fan-in from BugService (doc 17 gap: the bugs-this-run counter
-- below used to be inferred from the Fly award amount, see the note further
-- down). Same get-or-create-in-ServerStorage pattern as SpawnBugAt/AwardFlys --
-- BugService fires this directly, with no inference, right alongside its own
-- AwardFlys/BugCaught calls (src/server/BugService.server.luau).
local bugCaughtServer = ensureBindable("BugCaughtServer")

-- Death cause (doc 17 gap: `GameOver`/`RunSummary` never said *how* the frog
-- died, so `hurt` -- Entities/Lava.cs FallSplash's hurtSound, a lava-specific
-- death cue -- couldn't be wired). The fall loop below has exactly one death
-- mechanism: the frog's head drops past Config.DESPAWN_Y, this port's stand-in
-- for Unity's lava line (see the fall loop's own comment). So there is only
-- ever one cause today, but it's still threaded through as an explicit
-- argument (not hardcoded at each call site) so a future second cause (e.g. a
-- border/out-of-bounds kill) only needs a new value here, not a new remote.
local DEATH_CAUSE_LAVA = "Lava"

-- ---------------------------------------------------------------------------
-- Run state (doc 15): Menu -> Playing -> Dead -> Menu, per player. In Menu the
-- lane is idle (createFrog still parks a frog at the origin, but the frog
-- Heartbeat loop below skips gravity/death and the lane Heartbeat loop skips
-- spawning while state ~= Playing) so the client can show a main menu instead
-- of an already-falling frog. `setRunState` is the only place that changes it,
-- so RunStateChanged always mirrors `runState` exactly.
-- ---------------------------------------------------------------------------
local RunState = { Menu = "Menu", Playing = "Playing", Dead = "Dead" }
local runState: { [Player]: string } = {}
local lastStartRun: { [Player]: number } = {} -- StartRun rate limit (os.clock())

local function setRunState(player: Player, state: string)
	runState[player] = state
	local lane = Lane.get(player)
	if lane then
		lane.folder:SetAttribute("RunState", state) -- every client dresses an idle lane as the Menu level
	end
	RunStateChanged:FireClient(player, state)
end

-- Per-RUN faucet totals for the end-of-run summary (doc 15 item 1/5). Listens
-- to the same ServerStorage/AwardFlys BindableEvent SkinService already
-- creates and fires on every bug catch (BugService) / gift claim
-- (GiftService) / IAP grant -- purely additive, never touches those scripts.
-- Every source is genuine Fly currency, so summing every amount here is
-- correct regardless of which faucet it came from -- unlike bugsThisRun below,
-- this was never a heuristic.
local flysThisRun: { [Player]: number } = {}
local awardFlysBindable = ensureBindable("AwardFlys")
awardFlysBindable.Event:Connect(function(player: Player, amount: number)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(amount) ~= "number" then
		return
	end
	flysThisRun[player] = (flysThisRun[player] or 0) + amount
end)

-- doc 17 gap: this counter used to be inferred from the AwardFlys amount
-- matching Config.BUG_FLYS (5) -- correct only as long as no other faucet
-- (GiftService's 100, a Developer Product grant, ...) ever happened to reuse
-- that exact number. BugService now fires BugCaughtServer directly on every
-- confirmed catch (see its CatchBug handler), so this is an exact count, not
-- an inference.
local bugsThisRun: { [Player]: number } = {}
bugCaughtServer.Event:Connect(function(player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	bugsThisRun[player] = (bugsThisRun[player] or 0) + 1
end)

-- ---------------------------------------------------------------------------
-- PlayField containers. `Lanes` holds one Folder per lane (Lane.luau creates
-- them); `Steps`/`Frogs`/`Bugs` stay global (doc 13: the step instance pool may
-- stay global -- only spawning/direction/level state is per-lane).
-- ---------------------------------------------------------------------------
local playField = workspace.PlayField
if not playField:FindFirstChild("Lanes") then
	local lanes = Instance.new("Folder")
	lanes.Name = "Lanes"
	lanes.Parent = playField
end

-- ---------------------------------------------------------------------------
-- Step pool + spawning. Each lane decides WHEN/WHICH KIND/WHERE (Lane.luau);
-- this script owns the actual pooled Instances and Step behavior dispatch
-- (Shared/StepBehaviors, doc 05), same as before lanes existed.
-- ---------------------------------------------------------------------------
local template = ReplicatedStorage.Assets.StepTemplate :: BasePart
local DEFAULT_STEP_SIZE = template.Size
local container = playField.Steps :: Folder

local pool: { BasePart } = {}

-- Server-authoritative frog state (doc 07): the server owns position, gravity,
-- held steps, and death. The model lives in workspace, so replication renders it
-- on every client. Forward-declared (type + table) because forceReleaseStep,
-- below, needs to look up a lane's single frog.
type FrogState = {
	model: Model,
	body: BasePart,
	head: BasePart?,
	headOffset: CFrame,
	limbs: { BasePart },
	limbOffsets: { CFrame }, -- rest poses relative to the body
	pos: Vector3,
	gravityMult: number,
	dead: boolean,
	held: { BasePart }, -- steps this player holds (max Config.MAX_HELD_STEPS)
}
local frogs: { [Player]: FrogState } = {}

local function behaviorOf(step: BasePart): StepBehaviors.Behavior
	local name = step:GetAttribute("Behavior")
	return (typeof(name) == "string" and StepBehaviors[name]) or StepBehaviors.None
end

-- Knock this step's holder's limb off (Step.cs ForceRelease). Only the owning
-- lane's single player can ever hold a lane's step, so a small linear scan of
-- its (at most 2) held steps replaces the old global heldBy map.
local function forceReleaseStep(lane: Lane.Lane, step: BasePart)
	local f = frogs[lane.player]
	if not f then
		return
	end
	for i = #f.held, 1, -1 do
		if f.held[i] == step then
			table.remove(f.held, i)
			ForceRelease:FireClient(lane.player, step)
			return
		end
	end
end

-- Destroy this step's live "Flingee", if it has one (ActionType.SplashFlinging
-- destroyAction). Guards against a step recycling mid-flight leaving orphaned
-- debris, and against a repeat grab stacking Splashes.
local flingees: { [BasePart]: BasePart } = {}
local function clearFling(step: BasePart)
	local existing = flingees[step]
	if existing then
		existing:Destroy()
		flingees[step] = nil
	end
end

-- Spawn + launch a "Flingee" off this step (ActionType.SplashFlinging grabAction;
-- Splash.cs OnEnable: random X impulse + fixed Y impulse + opposing torque, then
-- self-destructs after SPLASH_LIFETIME). It's a plain unanchored part; its sprite
-- comes from the spawning kind's `flingeeSprite` (Shared/StepKinds), stamped on
-- the step as a `FlingeeSprite` attribute at spawn time -- Fork/Spoon/Flame per
-- doc 12, instead of always "Flame".
local function flingSplash(step: BasePart)
	clearFling(step) -- a repeat grab shouldn't stack Splashes
	local splash = Instance.new("Part")
	splash.Name = "Flingee"
	splash.Size = Vector3.new(1.2, 1.2, 0.4)
	splash.CanCollide = false
	splash.CanQuery = false -- must not eat taps
	splash.Anchored = false
	splash.CFrame = step.CFrame
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Front
	local flingeeSprite = step:GetAttribute("FlingeeSprite")
	decal:SetAttribute("Sprite", if typeof(flingeeSprite) == "string" then flingeeSprite else "Flame")
	decal.Parent = splash
	SpriteSkin.apply(splash)
	splash.Parent = workspace

	local xForce = Config.SPLASH_MIN_X_FORCE + math.random() * (Config.SPLASH_MAX_X_FORCE - Config.SPLASH_MIN_X_FORCE)
	splash.AssemblyLinearVelocity = Vector3.new(xForce, Config.SPLASH_Y_FORCE, 0)
	local rotForce = Config.SPLASH_ROT_MOD * (if xForce >= 0 then 1 else -1)
	splash.AssemblyAngularVelocity = Vector3.new(0, 0, -rotForce)

	flingees[step] = splash
	Debris:AddItem(splash, Config.SPLASH_LIFETIME)
end

-- forward-declared: releaseStep and makeCtx reference each other
local makeCtx: (lane: Lane.Lane, step: BasePart, player: Player?) -> StepBehaviors.Ctx

local function releaseStep(lane: Lane.Lane, step: BasePart)
	if not lane.active[step] then
		return -- idempotent: behaviors and the bounds check can both recycle
	end
	local b = behaviorOf(step)
	if b.onDestroy then
		b.onDestroy(makeCtx(lane, step, lane.player))
	end
	forceReleaseStep(lane, step)
	lane.active[step] = nil
	step.Parent = nil
	step:SetAttribute("LaneUserId", nil)
	table.insert(pool, step)
end

makeCtx = function(lane: Lane.Lane, step: BasePart, player: Player?): StepBehaviors.Ctx
	local gen = step:GetAttribute("Gen")
	local function stillValid(): boolean
		return lane.active[step] == true and step:GetAttribute("Gen") == gen
	end
	return {
		step = step,
		player = player,
		stillValid = stillValid,
		makeUnsteady = function()
			step:SetAttribute("Unsteady", true) -- clients may shake/emit pebbles off this
		end,
		explode = function()
			forceReleaseStep(lane, step)
			releaseStep(lane, step) -- effects (pebbles/sound) are client polish, doc 05
		end,
		dropAway = function()
			forceReleaseStep(lane, step)
			local info = TweenInfo.new(Config.DROP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(step, info, { CFrame = step.CFrame * CFrame.new(0, -Config.DROP_DISTANCE, 0) }):Play()
			-- the bounds check below recycles it once it falls past DESPAWN_Y
		end,
		forceRelease = function()
			forceReleaseStep(lane, step)
		end,
		getSpawnBias = function()
			return lane.spawnDirection
		end,
		setSpawnBias = function(bias: Vector2)
			lane:changeDirection(bias)
		end,
		spawnBug = function()
			spawnBugAt:Fire(step.Position, lane.userId) -- BugService owns the actual drift/idle/catch loop (doc 06)
		end,
		flingSplash = function()
			flingSplash(step)
		end,
		clearFling = function()
			clearFling(step)
		end,
	}
end

local function acquireStep(lane: Lane.Lane, kindName: string, worldPos: Vector3): BasePart
	local kind = StepKinds[kindName]
	local step = (table.remove(pool) or template:Clone()) :: BasePart
	step:SetAttribute("Kind", "Step")
	step:SetAttribute("Gen", ((step:GetAttribute("Gen") :: number?) or 0) + 1)
	step:SetAttribute("Unsteady", false)
	step:SetAttribute("Shrugged", false)
	step:SetAttribute("LaneUserId", lane.userId)
	step.Anchored = true -- we move it ourselves (kinematic)
	clearFling(step) -- pooling safety: a recycled step must not inherit a live Flingee

	step:SetAttribute("Behavior", if kind then kind.behavior else "None")
	step:SetAttribute("Sprite", if kind then kind.sprite else nil)
	step:SetAttribute("FlingeeSprite", if kind then kind.flingeeSprite else nil)
	step.Size = if kind and kind.size then kind.size else DEFAULT_STEP_SIZE
	SpriteSkin.apply(step) -- texture from its `Sprite` attribute (no-op until ids are set)

	step.CFrame = CFrame.new(worldPos)
	step.Parent = container
	lane.active[step] = true
	return step
end

-- Recycle every one of this lane's live steps immediately (doc 15 item 1):
-- called on death so the lane goes back to a clean, empty, idle Menu instead
-- of leftover run steps sitting frozen while runState ~= Playing gates the
-- bounds-check loop below from ever recycling them on its own. Any step still
-- held was already force-released by the caller (killFrog), so this never
-- needs to touch f.held itself.
local function clearLaneSteps(lane: Lane.Lane)
	local steps: { BasePart } = {}
	for step in pairs(lane.active) do
		table.insert(steps, step)
	end
	for _, step in steps do
		releaseStep(lane, step)
	end
end

-- ---------------------------------------------------------------------------
-- The pull / world-scroll: on a validated grab, slide this lane's steps along
-- ITS OWN spawn direction (Spawning/SpawnManager.cs PullStep/PullVector, now
-- per-lane -- doc 13 item 4). A negative `distance` undoes previous pulls (used
-- by the Tutorial's no-death fall rule below).
-- ---------------------------------------------------------------------------
local function pullLane(lane: Lane.Lane, distance: number, duration: number)
	local dir = lane.spawnDirection
	local dir3 = Vector3.new(dir.X, dir.Y, 0)
	if dir3.Magnitude < 1e-4 then
		return
	end
	lane:addPull(distance) -- spawners only run on time earned by pulling (Lane.spawnBudget)
	local delta = dir3.Unit * distance
	-- replicate the pull so clients can scroll lane-local cosmetics (scenery, walls) in step
	lane.folder:SetAttribute("PullDelta", delta)
	lane.folder:SetAttribute("PullTime", duration)
	lane.folder:SetAttribute("PullCount", ((lane.folder:GetAttribute("PullCount") :: number?) or 0) + 1)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine)
	for step in pairs(lane.active) do
		TweenService:Create(step, info, { CFrame = step.CFrame * CFrame.new(delta.X, delta.Y, 0) }):Play()
	end
end

-- Per-lane spawn tick + per-tick behavior hook (Falling's constant drift,
-- doc 05) + recycle steps that leave the lane's bounds on any side (doc 13
-- item 4 -- Borders: Left/Right/Top/Bottom catch, not just the lava line).
RunService.Heartbeat:Connect(function(dt: number)
	for _, lane in Lane.iter() do
		if runState[lane.player] ~= RunState.Playing then
			continue -- Menu/Dead: idle lane, no spawning (doc 15 item 1)
		end
		lane:tickSpawners(dt, function(_state, kindName, worldPos)
			acquireStep(lane, kindName, worldPos)
		end)

		for step in pairs(lane.active) do
			local b = behaviorOf(step)
			if b.onTick then
				b.onTick(makeCtx(lane, step, lane.player), dt)
			end
			if lane:isOutOfBounds(step) then
				releaseStep(lane, step)
			end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Scoring (Core/VariableManager.cs). The high score lives on the shared Profile
-- (Profiles); sessionScore is the current run, banked into profile.highScore on
-- death. No DataStore here -- Profiles owns persistence.
-- ---------------------------------------------------------------------------
local sessionScore: { [Player]: number } = {}

-- Per-run grab-quality counts (Player/Player.cs grabStats Vector4i / TrackGrabQuality).
-- Unity's score is a flat +1 per step climbed -- quality only feeds these separate
-- Perfect/Great/OK counters, e.g. for an end-of-run stats panel (doc 08/09).
type GrabQuality = { Perfect: number, Great: number, OK: number }
local grabQuality: { [Player]: GrabQuality } = {}

local function resetGrabQuality(player: Player)
	grabQuality[player] = { Perfect = 0, Great = 0, OK = 0 }
end

local function bestOf(player: Player): number
	local p = Profiles.get(player)
	return if p then p.highScore else 0
end

-- leaderstats: Score (current run) + Best in the built-in player list (doc 07)
local function ensureLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local score = Instance.new("IntValue")
	score.Name = "Score"
	score.Parent = stats
	local best = Instance.new("IntValue")
	best.Name = "Best"
	best.Parent = stats
	stats.Parent = player
end

local function updateLeaderstats(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	local score = stats:FindFirstChild("Score")
	if score and score:IsA("IntValue") then
		score.Value = sessionScore[player] or 0
	end
	local best = stats:FindFirstChild("Best")
	if best and best:IsA("IntValue") then
		best.Value = bestOf(player)
	end
end

local function pushScore(player: Player, quality: string?)
	updateLeaderstats(player)
	ScoreChanged:FireClient(player, sessionScore[player] or 0, bestOf(player), quality, grabQuality[player])
end

local function addScore(player: Player, amount: number, quality: string?)
	sessionScore[player] = (sessionScore[player] or 0) + amount
	local q = grabQuality[player]
	if q then
		if quality == "Perfect" then
			q.Perfect += 1
		elseif quality == "Great" then
			q.Great += 1
		elseif quality == "OK" then
			q.OK += 1
		end
	end
	pushScore(player, quality)
end

local function commitHighScore(player: Player)
	local p = Profiles.get(player)
	local score = sessionScore[player] or 0
	if p and score > p.highScore then
		p.highScore = score
		Profiles.save(player)
		Profiles.recordGlobalBest(player, score) -- mirror into the global top-N (doc 07)
	end
end

local function resetScore(player: Player)
	sessionScore[player] = 0
	resetGrabQuality(player)
	pushScore(player)
end

-- ---------------------------------------------------------------------------
-- LevelChanged notification (doc 13 item 6): fired on run start and every
-- transition. Lane.luau calls this through the `notify` callback so Lane never
-- needs to know about remotes.
-- ---------------------------------------------------------------------------
local function notifyLevelChanged(lane: Lane.Lane, transition: string)
	local level = lane.level
	LevelChanged:FireClient(
		lane.player,
		level.name,
		level.musicIndex,
		level.background,
		level.overlay,
		transition,
		lane.origin
	)
end

-- ---------------------------------------------------------------------------
-- Frogs (Player/Frog.cs, server-authoritative). One model per player, named
-- Frog_<userId>, skinned from the profile so the look replicates to everyone.
-- Spawns at its lane's origin (doc 13 item 1).
-- ---------------------------------------------------------------------------
local frogContainer = playField:FindFirstChild("Frogs")
if not frogContainer then
	frogContainer = Instance.new("Folder")
	frogContainer.Name = "Frogs"
	frogContainer.Parent = playField
end

local frogTemplate = ReplicatedStorage.Assets.FrogModel

-- FrogModel.model.json wires PrimaryPart -> Body via Rojo's attribute-based
-- Ref convention (Rojo_Id / Rojo_Target_PrimaryPart), which the Rojo Studio
-- plugin resolves on sync. That resolution can lose the race against the
-- model's own children being created (rojo-rbx/rojo#928), leaving
-- PrimaryPart nil on first sync and crashing createFrog below when it reads
-- body.CFrame. Guard it here so a clone always has a PrimaryPart regardless
-- of whether the plugin's Ref-attribute pass won that race.
if not frogTemplate.PrimaryPart then
	local frogBody = frogTemplate:FindFirstChild("Body")
	if frogBody and frogBody:IsA("BasePart") then
		frogTemplate.PrimaryPart = frogBody
	end
end

local function createFrog(player: Player, lane: Lane.Lane)
	if frogs[player] then
		return
	end
	local model = frogTemplate:Clone() :: Model
	model.Name = "Frog_" .. player.UserId
	model:SetAttribute("UserId", player.UserId)
	model:SetAttribute("Dead", false)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true -- kinematic, like the steps
			descendant.CanCollide = false
			descendant.CanQuery = false -- frogs must not eat taps
		end
	end

	local body = model.PrimaryPart :: BasePart
	local headInstance = model:FindFirstChild("Head")
	local head = if headInstance and headInstance:IsA("BasePart") then headInstance else nil
	local right = model:FindFirstChild("RightLimb") :: BasePart
	local left = model:FindFirstChild("LeftLimb") :: BasePart

	-- skin from the profile (server-side: replicates to everyone -- doc 08)
	local profile = Profiles.get(player)
	local entry = profile and SkinCatalog[profile.selected]
	if entry then
		SpriteSkin.apply(model, entry.name)
	end

	local state: FrogState = {
		model = model,
		body = body,
		head = head,
		headOffset = if head then body.CFrame:ToObjectSpace(head.CFrame) else CFrame.identity,
		limbs = { right, left },
		limbOffsets = {
			CFrame.new(Config.LIMB_REST[1].X, Config.LIMB_REST[1].Y, 0),
			CFrame.new(Config.LIMB_REST[2].X, Config.LIMB_REST[2].Y, 0),
		},
		pos = lane.origin,
		gravityMult = Config.GRAVITY_MULT_START,
		dead = false,
		held = {},
	}
	body.CFrame = CFrame.new(lane.origin)
	frogs[player] = state
	model.Parent = frogContainer
end

-- doc 15 item 1: death now ends the run rather than auto-respawning into
-- another fall. It banks the score/best as before, but instead of
-- immediately re-priming the lane for another fall it reports a RunSummary
-- (score/best/isNewBest/grab-quality counts/bugs+flys this run) and, after the
-- same death beat the auto-respawn used to wait out, returns the player to
-- Menu -- the client shows the end-of-run panel for that beat instead of a
-- falling frog.
local function killFrog(player: Player, f: FrogState, lane: Lane.Lane)
	f.dead = true
	f.model:SetAttribute("Dead", true)
	-- drop anything still held (e.g. a step dragged out of bounds with us)
	for i = #f.held, 1, -1 do
		forceReleaseStep(lane, f.held[i])
	end

	local score = sessionScore[player] or 0
	local q = grabQuality[player]
	local qualitySnapshot = {
		Perfect = if q then q.Perfect else 0,
		Great = if q then q.Great else 0,
		OK = if q then q.OK else 0,
	}
	local oldBest = bestOf(player)
	commitHighScore(player) -- reads sessionScore[player] itself; must run before resetScore clears it
	local newBest = bestOf(player)
	local isNewBest = score > oldBest

	local bugs = bugsThisRun[player] or 0
	local flys = flysThisRun[player] or 0
	bugsThisRun[player] = 0
	flysThisRun[player] = 0

	resetScore(player)
	-- DEATH_CAUSE_LAVA on both: Effects.client.luau's fall-sound hook ignores the
	-- extra argument (unchanged), SfxEvents.client.luau's new `hurt` cue reads it.
	GameOver:FireClient(player, DEATH_CAUSE_LAVA)
	RunSummary:FireClient(player, score, newBest, isNewBest, qualitySnapshot, bugs, flys, DEATH_CAUSE_LAVA)

	clearLaneSteps(lane) -- leave the lane empty/idle for the Menu, not littered with the just-ended run's steps
	local profile = Profiles.get(player)
	lane:resetRun(profile ~= nil and profile.tutorialDone == true) -- fires LevelChanged("death") itself

	setRunState(player, RunState.Dead)

	task.delay(Config.RESPAWN_DELAY, function()
		if frogs[player] ~= f then
			return -- player left (or was rebuilt) during the death beat
		end
		f.pos = lane.origin
		f.gravityMult = Config.GRAVITY_MULT_START
		f.dead = false
		f.model:SetAttribute("Dead", false)
		setRunState(player, RunState.Menu) -- doc 15 item 1: back to the main menu, not another fall
	end)
end

-- Tutorial "no death" rule (Core/LevelManager.cs ReportFall, levelIndex==1, doc
-- 13 item 5): pull the field back up by TUTORIAL_PULL_BACK pulls' worth of
-- distance and let the frog retry from its lane's origin -- no GameOver, no
-- score reset, no respawn delay.
local function tutorialRetry(lane: Lane.Lane, f: FrogState)
	for i = #f.held, 1, -1 do
		forceReleaseStep(lane, f.held[i])
	end
	pullLane(lane, -Config.PULL_DISTANCE * Config.TUTORIAL_PULL_BACK, 0.6)
	f.pos = lane.origin
	f.gravityMult = Config.GRAVITY_MULT_START
end

-- The fall loop (Frog.cs SteadilyLowerHead) + bounds check (Lava.cs, per-lane
-- via Config.DESPAWN_Y -- lanes only offset along X, so Y bounds stay shared)
-- + rendering: limbs snap to their held step or ease back to rest, exactly as
-- the client used to do locally.
RunService.Heartbeat:Connect(function(dt: number)
	for plr, f in pairs(frogs) do
		local lane = Lane.get(plr)
		if not lane then
			continue
		end

		-- doc 15 item 1: gravity/death only apply while actually Playing -- in
		-- Menu/Dead the frog is parked at rest (no gravity ever accumulates for
		-- it, so it just sits at whatever f.pos it was left at; the rendering
		-- below still runs every tick so limbs ease back to rest normally).
		if not f.dead and runState[plr] == RunState.Playing then
			if #f.held == 0 then
				f.gravityMult += Config.GRAVITY_ACCEL * dt
				local speed = math.min(Config.GRAVITY * f.gravityMult, Config.MAX_FALL_SPEED)
				f.pos = Vector3.new(f.pos.X, f.pos.Y - speed * dt, Config.PLANE_Z)
			end
			if f.pos.Y <= Config.DESPAWN_Y then
				if lane.levelIndex == Levels.TUTORIAL then
					tutorialRetry(lane, f)
				else
					killFrog(plr, f, lane)
				end
			end
		end

		local bodyCF = CFrame.new(f.pos)
		f.body.CFrame = bodyCF
		local head = f.head
		if head then
			head.CFrame = bodyCF * f.headOffset
		end
		for i, limbPart in f.limbs do
			local step = f.held[i]
			if step and step.Parent then
				limbPart.CFrame = CFrame.new(step.Position) -- follow the (scrolling) step
			else
				local target = bodyCF * f.limbOffsets[i]
				local alpha = math.clamp(dt / Config.LIMB_RETURN_TIME, 0, 1)
				limbPart.CFrame = limbPart.CFrame:Lerp(target, alpha)
			end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Remote handlers
-- ---------------------------------------------------------------------------

-- Per-player grab rate limit (doc 07): a bot could fire GrabStep far faster than
-- a human to climb instantly. Keep recent grab timestamps in a rolling window.
local grabTimes: { [Player]: { number } } = {}

local function grabAllowed(player: Player): boolean
	local now = os.clock()
	local times = grabTimes[player]
	if not times then
		times = {}
		grabTimes[player] = times
	end
	-- drop timestamps older than the window
	local cutoff = now - Config.GRAB_WINDOW
	local kept = 0
	for i = 1, #times do
		if times[i] >= cutoff then
			kept += 1
			times[kept] = times[i]
		end
	end
	for i = #times, kept + 1, -1 do
		times[i] = nil
	end
	if kept >= Config.GRAB_MAX_PER_WINDOW then
		return false
	end
	times[kept + 1] = now
	return true
end

GrabStep.OnServerEvent:Connect(function(player, step, tapPos)
	-- validate: a real, still-active step FROM THIS PLAYER'S OWN LANE, from a
	-- live frog with a limb to spare (doc 13 item 1: GrabStep must reject steps
	-- from another lane)
	if typeof(step) ~= "Instance" or not step:IsA("BasePart") then
		return
	end
	local lane = Lane.get(player)
	if not lane or step:GetAttribute("LaneUserId") ~= lane.userId or not lane.active[step] then
		return
	end
	if runState[player] ~= RunState.Playing then
		return -- doc 15 item 1: no grabs outside an active run (Menu/Dead lanes are idle/empty anyway)
	end
	local f = frogs[player]
	if not f or f.dead or #f.held >= Config.MAX_HELD_STEPS then
		ForceRelease:FireClient(player, step)
		return
	end
	-- reject a step someone already holds, or grabs faster than humanly possible;
	-- ForceRelease corrects the client that optimistically snapped a limb on
	for _, held in f.held do
		if held == step then
			ForceRelease:FireClient(player, step)
			return
		end
	end
	if not grabAllowed(player) then
		ForceRelease:FireClient(player, step)
		return
	end
	-- reach check against the SERVER's frog position (no client trust left here)
	local reach = (Vector2.new(step.Position.X, step.Position.Y) - Vector2.new(f.pos.X, f.pos.Y)).Magnitude
	if reach > Config.MAX_GRAB_DISTANCE then
		ForceRelease:FireClient(player, step)
		return
	end
	-- grade quality server-side from the reported tap point (doc 07): garbage
	-- input can at worst claim "Perfect", which only flashes the HUD
	local quality = if typeof(tapPos) == "Vector3" then PullMath.gradeGrab(tapPos, step.Position) else "OK"

	f.gravityMult = Config.GRAVITY_MULT_START -- reset the fall curve (Frog.Bob)
	pullLane(lane, Config.PULL_DISTANCE, Config.PULL_TIME)
	addScore(player, 1, quality)

	lane:onStepClimbed() -- level-threshold / tutorial progress; fires LevelChanged("soft") itself (doc 13 item 5)

	-- step behaviors (doc 05): track the holder, then dispatch onGrab
	table.insert(f.held, step)
	local b = behaviorOf(step)
	if b.onGrab then
		b.onGrab(makeCtx(lane, step, player))
	end
end)

ReleaseStep.OnServerEvent:Connect(function(player, _limbIndex, step)
	-- only the recorded holder may release; ForceRelease already dropped it from
	-- f.held, so the client's echo after a forced drop lands here as a no-op
	if typeof(step) ~= "Instance" or not step:IsA("BasePart") then
		return
	end
	local lane = Lane.get(player)
	local f = frogs[player]
	if not lane or not f then
		return
	end
	local held = false
	for i = #f.held, 1, -1 do
		if f.held[i] == step then
			table.remove(f.held, i)
			held = true
			break
		end
	end
	if not held then
		return
	end
	local b = behaviorOf(step)
	if b.onRelease and lane.active[step] then
		b.onRelease(makeCtx(lane, step, player))
	end
end)

-- doc 15 item 1: begin a run from the main menu. Only valid from Menu (a
-- client stuck mid-Playing or mid-death-beat can't re-trigger it), and
-- rate-limited the same way grabs are so a bot can't hammer it.
local START_RUN_COOLDOWN = 1.0
StartRun.OnServerEvent:Connect(function(player)
	if runState[player] ~= RunState.Menu then
		return
	end
	local now = os.clock()
	if now < (lastStartRun[player] or 0) + START_RUN_COOLDOWN then
		return
	end
	lastStartRun[player] = now

	local lane = Lane.get(player)
	local f = frogs[player]
	if not lane or not f then
		return
	end
	f.pos = lane.origin
	f.gravityMult = Config.GRAVITY_MULT_START
	f.dead = false
	f.model:SetAttribute("Dead", false)
	flysThisRun[player] = 0
	bugsThisRun[player] = 0
	lane:prefill(function(_state, kindName, worldPos)
		acquireStep(lane, kindName, worldPos)
	end)
	setRunState(player, RunState.Playing)
end)

-- Settings (doc 15 item 3): music on/off is the whole MusicOn attribute
-- contract another agent's client music system reads -- this script never
-- plays anything, it only validates, persists, and republishes the attribute.
--
-- doc 17 gap: a settings toggle used to call Profiles.save on every single
-- click, which is a DataStore write a player mashing the toggle could spam.
-- The Attribute (what Music.client.luau actually reacts to) and the in-memory
-- profile field both still apply IMMEDIATELY on every call -- only the
-- DataStore write itself is throttled to at most once per
-- Config.MUSIC_SAVE_DEBOUNCE seconds. This can never lose the final value:
-- Profiles.save's skip here only skips a save that's about to be superseded by
-- a newer one anyway, and Profiles.luau already does its own unconditional
-- final save on PlayerRemoving/BindToClose (see Profiles.luau's doSave(...,
-- true) calls) reading whatever `p.musicOn` holds at that moment, plus its own
-- 120s periodic autosave in between -- so the debounce below only ever skips a
-- write, never the value.
local lastMusicSave: { [Player]: number } = {}
SetMusicOn.OnServerEvent:Connect(function(player, value)
	if typeof(value) ~= "boolean" then
		return
	end
	local p = Profiles.get(player)
	if not p then
		return
	end
	p.musicOn = value
	player:SetAttribute("MusicOn", value) -- applied immediately, independent of the save debounce below

	local now = os.clock()
	local last = lastMusicSave[player]
	if last and (now - last) < Config.MUSIC_SAVE_DEBOUNCE then
		return -- too soon since the last write; the in-memory value above is already correct
	end
	lastMusicSave[player] = now
	Profiles.save(player)
end)

-- "Replay tutorial" settings action (doc 15 item 3): only from Menu, so it
-- can't clobber a run in progress. Reuses Lane:resetRun's existing Tutorial
-- setup rather than duplicating it.
ReplayTutorial.OnServerEvent:Connect(function(player)
	if runState[player] ~= RunState.Menu then
		return
	end
	local p = Profiles.get(player)
	if not p then
		return
	end
	p.tutorialDone = false
	Profiles.save(player)
	local lane = Lane.get(player)
	if lane then
		lane:resetRun(false) -- back to Tutorial; fires LevelChanged for the client's level-name toast
	end
end)

-- Global top-scores board (doc 15 item 5): Profiles.topScores(10) + name
-- resolution are both DataStore-ish calls, so cache the assembled list for 60s
-- rather than hitting them on every panel open. Names are cached forever
-- (a UserId's name essentially never changes mid-session) and resolved in a
-- pcall so one bad lookup can't fail the whole board.
local TOP_SCORES_TTL = 60
local topScoresCache: { { userId: number, score: number, name: string } }? = nil
local topScoresCachedAt = 0
local nameCache: { [number]: string } = {}

local function resolveName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok and typeof(name) == "string" then name else ("Player" .. userId)
	nameCache[userId] = resolved
	return resolved
end

GetTopScores.OnServerInvoke = function(_player: Player)
	local now = os.clock()
	if not topScoresCache or (now - topScoresCachedAt) > TOP_SCORES_TTL then
		local raw = Profiles.topScores(10)
		local list: { { userId: number, score: number, name: string } } = {}
		for _, entry in raw do
			table.insert(list, { userId = entry.userId, score = entry.score, name = resolveName(entry.userId) })
		end
		topScoresCache = list
		topScoresCachedAt = now
	end
	return topScoresCache
end

-- ---------------------------------------------------------------------------
-- Player lifecycle. Profiles owns persistence; once a profile is ready we
-- create this player's Lane (doc 13), set up the run state, the leaderstats
-- board, and the server-owned frog. Death is decided entirely by the server's
-- bounds check in the frog Heartbeat (no ReportDeath remote -- the client has
-- no say in when it died).
-- ---------------------------------------------------------------------------
local function initPlayer(player: Player)
	ensureLeaderstats(player)
	sessionScore[player] = 0
	resetGrabQuality(player)
	flysThisRun[player] = 0
	bugsThisRun[player] = 0

	local profile = Profiles.get(player)
	local tutorialDone = profile ~= nil and profile.tutorialDone == true
	local lane = Lane.new(player, tutorialDone, notifyLevelChanged) -- fires LevelChanged("start") itself
	-- doc 15 item 1: no prefill here -- a fresh join starts in Menu with an
	-- idle, empty lane; StartRun does the prefill once the player presses Play.
	createFrog(player, lane)
	pushScore(player)
	setRunState(player, RunState.Menu)

	-- MusicOn attribute contract (doc 15): the whole handshake for another
	-- agent's client music system -- this script never plays anything, only
	-- mirrors profile.musicOn onto the Player attribute.
	if profile then
		player:SetAttribute("MusicOn", profile.musicOn == true)
	end
end

Profiles.Loaded:Connect(initPlayer)
for _, player in Players:GetPlayers() do
	if Profiles.get(player) then
		initPlayer(player)
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	local f = frogs[player]
	local lane = Lane.get(player)
	if f then
		for i = #f.held, 1, -1 do
			table.remove(f.held, i) -- no ForceRelease: the holder is leaving
		end
		frogs[player] = nil
		f.model:Destroy()
	end
	if lane then
		for step in pairs(lane.active) do
			step.Parent = nil
			step:SetAttribute("LaneUserId", nil)
			table.insert(pool, step)
		end
		lane:destroy()
	end
	sessionScore[player] = nil
	grabQuality[player] = nil
	grabTimes[player] = nil
	runState[player] = nil
	lastStartRun[player] = nil
	flysThisRun[player] = nil
	bugsThisRun[player] = nil
	lastMusicSave[player] = nil
end)
