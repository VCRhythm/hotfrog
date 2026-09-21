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
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local Profiles = require(script.Parent.Profiles)
local Lane = require(script.Parent.Lane)

-- The player's avatar is the frog model, not a Roblox character: the default
-- character spawns at the origin, standing in front of lane 0's frog art plane
-- and hiding its sprites. Nothing in this port reads Player.Character. The flag
-- alone isn't enough -- a player can already have joined (and auto-loaded)
-- before this script runs, e.g. Studio's play-solo -- so drop any character that
-- appears anyway.
Players.CharacterAutoLoads = false

local function dropCharacter(character: Model)
	character:Destroy()
end

local function disownCharacter(player: Player)
	player.CharacterAdded:Connect(dropCharacter)
	local character = player.Character
	if character then
		dropCharacter(character)
	end
end

Players.PlayerAdded:Connect(disownCharacter)
for _, player in Players:GetPlayers() do
	disownCharacter(player)
end

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

local GrabStep = ensureRemote("GrabStep") -- client -> server: tapped a step (step, tap world point, limb index 1=Right 2=Left)
local ReleaseStep = ensureRemote("ReleaseStep") -- client -> server: released a limb (limb index, step)
local ReachEmpty = ensureRemote("ReachEmpty") -- client -> server: tapped empty space (tap world point, limb index 1=Right 2=Left)
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
-- mechanism: the frog sinks onto the lava surface at Config.LAVA_Y (see the
-- fall loop's own comment). So there is only
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

-- Attract mode (below the frog section): builds/tears down a Menu lane's
-- decorative ladder. Forward-declared so setRunState can drive it.
local refreshAttract: (player: Player) -> ()

local function setRunState(player: Player, state: string)
	runState[player] = state
	local lane = Lane.get(player)
	if lane then
		lane.folder:SetAttribute("RunState", state) -- every client dresses an idle lane as the Menu level
	end
	RunStateChanged:FireClient(player, state)
	refreshAttract(player)
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
	-- Player.cs `canFall`: stays false from spawn/respawn until the first grab of
	-- a pullable step (Player.TouchStep's `canPull` check -- every step the port
	-- spawns is pullable, so in practice this just means "has grabbed once this
	-- run"). Gates both gravity accrual and the lava check below so the frog
	-- doesn't sink and die before the player has touched a step.
	canFall: boolean,
	-- The step each LIMB holds, keyed the same way `limbs` is (1=Right, 2=Left),
	-- or nil for a free limb. Keyed by limb rather than packed in grab order so
	-- the hand the player grabbed with is the hand that reaches the step (the
	-- client's mouse buttons each drive a fixed limb) and so releasing one limb
	-- never shuffles the other limb's step onto it.
	held: { [number]: BasePart },
	-- A free limb's in-flight reach toward an empty tap (ReachEmpty), keyed like
	-- `held`. Once `REACH_TIME` has elapsed it's dropped and the limb eases home.
	reach: { [number]: { from: CFrame, to: CFrame, started: number } },
	-- Frog.Bob state (Frog.cs:254-285, see `bob` below): the step whose grab
	-- started the bob (Unity's BobStep -- releasing it kills the rise), the
	-- in-flight X sway and Y rise tweens, and the Z rock punch.
	bobStep: BasePart?,
	bobX: BobTween?,
	bobY: BobTween?,
	rock: { angle: number, started: number }?,
}
type BobTween = { from: number, to: number, started: number, duration: number }
local frogs: { [Player]: FrogState } = {}

-- Frog.CancelBob / the kill-and-reset paths: drop every in-flight bob tween.
local function cancelBob(f: FrogState)
	f.bobStep = nil
	f.bobX = nil
	f.bobY = nil
	f.rock = nil
end

-- Frog.StopBob: releasing the step that started the bob kills its Y rise
-- (the X sway and rock play out, as Unity only kills the "Y" tween).
local function stopBob(f: FrogState, step: BasePart)
	if f.bobStep == step then
		f.bobStep = nil
		f.bobY = nil
	end
end

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
	for i = 1, Config.MAX_HELD_STEPS do
		if f.held[i] == step then
			f.held[i] = nil
			stopBob(f, step)
			ForceRelease:FireClient(lane.player, step)
			return
		end
	end
end

-- A limb index off a remote is only ever 1 (Right) or 2 (Left), the frog's two
-- limbs (Config.MAX_HELD_STEPS). Compared against the RAW client value: NaN
-- (a client can send 0/0) survives range checks like `< 1` / `> 2` and only
-- blows up later as a table key -- `f.held[0/0] = step` raises -- so nothing
-- unvalidated may reach `f.held` at all.
local function isLimbIndex(value: any): boolean
	return value == 1 or value == 2
end

-- Unity's Controller.HasStep: is either limb on a step? (A frog holding
-- nothing falls -- on keyboard+mouse that means at least one mouse button has
-- to stay down.)
local function isHolding(f: FrogState): boolean
	for i = 1, Config.MAX_HELD_STEPS do
		if f.held[i] then
			return true
		end
	end
	return false
end

-- Drop a limb's empty-tap reach (it grabbed a step, or eased back home). The
-- `Reaching` attribute tells WorldFrogCosmetics to keep that hand open while
-- it's extended, since its held-inference would otherwise close it.
local function endReach(f: FrogState, limb: number)
	if f.reach[limb] then
		f.reach[limb] = nil
		f.limbs[limb]:SetAttribute("Reaching", nil)
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
	decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
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
	-- The part is the sprite's whole Unity canvas (a Decal stretches the full
	-- image across it); `HitSize` carries the smaller Unity Collider2D, which is
	-- what GameClient tap-tests -- see the header of Shared/StepKinds.
	step.Size = if kind and kind.size then kind.size else DEFAULT_STEP_SIZE
	step:SetAttribute("HitSize", if kind then kind.hitSize else nil)
	step:SetAttribute("HitOffset", if kind then kind.hitOffset else nil)
	step:SetAttribute("GripOffset", if kind then kind.gripOffset else nil)
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
			descendant.CanCollide = false
			descendant.CanQuery = false -- frogs must not eat taps
			-- The arm/hand sprites are the only frog art whose Unity canvas pivot
			-- isn't centred (the arm hangs below its limb, the open hand sits
			-- above it), so FrogModel.model.json authors them as CHILD parts of
			-- the limb. Weld those to the limb instead of anchoring them: the
			-- Heartbeat loop below only ever poses the limb part itself, and an
			-- anchored root drags its welded parts along with no physics.
			local host = descendant.Parent
			if host and host:IsA("BasePart") then
				descendant.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = host
				weld.Part1 = descendant
				weld.Parent = descendant
			else
				descendant.Anchored = true -- kinematic, like the steps
			end
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
		canFall = false,
		held = {},
		reach = {},
	}
	body.CFrame = CFrame.new(lane.origin)
	frogs[player] = state
	model.Parent = frogContainer
	-- This place has instance streaming on, and streaming normally centres on the
	-- character's root part -- which no longer exists (CharacterAutoLoads is off
	-- above), leaving the client with an empty workspace. Focus it on this
	-- player's own frog body, which is always inside their lane.
	player.ReplicationFocus = body
end

-- ---------------------------------------------------------------------------
-- Attract mode (Player/FrogAI.cs): while a lane sits in Menu, its REAL frog
-- climbs a small decorative ladder on a loop -- every WorldConfig.
-- ATTRACT_DECISION_TIME seconds (FrogAI's fixed 1s nextDecisionTime) the demo
-- hand (WorldConfig.ATTRACT_LIMB) grabs the rung above and the ladder is pulled
-- down one rung gap -- the same "frog lifts, world scrolls" a real grab does
-- (pullLane) -- with the rung that leaves the bottom recycled to the top. The
-- other hand is left free: the player's menu clicks send it reaching to the
-- click (ReachEmpty). FrogAI raycasts a random on-screen step;
-- a Menu lane spawns no steps (doc 15), so the rungs are a fixed ladder
-- instead. Server-owned so there is exactly one frog per lane (this used to be
-- a second, client-local clone beside the parked frog) and other players on
-- the start screen see each other's frogs doing it too.
--
-- The rungs are NOT gameplay steps: not in lane.active, no LaneUserId, and
-- CanQuery off, so they can never be grabbed or eat a tap. Their holds live in
-- `attract[player].held`, never in f.held, so isHolding/gravity/grab
-- validation are untouched; only the frog render loop below reads them.
-- ---------------------------------------------------------------------------
type AttractState = {
	rungs: { BasePart },
	held: { [number]: BasePart }, -- keyed like FrogState.held (1=Right, 2=Left)
	origin: Vector3, -- the lane origin the ladder is laid out around
	lastDecision: number, -- os.clock()
}
local attract: { [Player]: AttractState } = {}

local attractFolder = playField:FindFirstChild("Attract")
if not attractFolder then
	attractFolder = Instance.new("Folder")
	attractFolder.Name = "Attract"
	attractFolder.Parent = playField
end

local function buildAttract(origin: Vector3): AttractState
	local rungs: { BasePart } = {}
	for i = 1, WorldConfig.ATTRACT_STEP_COUNT do
		local part = Instance.new("Part")
		part.Name = "AttractStep"
		part.Size = WorldConfig.ATTRACT_STEP_SIZE
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false -- decorative only, must never eat taps
		part.CanTouch = false
		part.Transparency = 1 -- host for the Decal only (see StepTemplate)
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
		decal:SetAttribute("Sprite", "WhiteRock")
		decal.Parent = part
		SpriteSkin.apply(part)
		-- Zig-zag ladder (Lane.luau's Tutorial ladder shape) about the frog's
		-- own Y: rung 2 level with the body, 1 below, 3 above, 4 off-screen.
		local sign = if i % 2 == 1 then 1 else -1
		local rise = (i - 2) * WorldConfig.ATTRACT_STEP_Y_GAP
		part.CFrame = CFrame.new(
			origin + WorldConfig.ATTRACT_ANCHOR_OFFSET + Vector3.new(sign * WorldConfig.ATTRACT_STEP_X, rise, 0)
		)
		part.Parent = attractFolder
		table.insert(rungs, part)
	end
	return { rungs = rungs, held = {}, origin = origin, lastDecision = os.clock() }
end

local function teardownAttract(player: Player)
	local a = attract[player]
	if not a then
		return
	end
	attract[player] = nil
	for _, part in a.rungs do
		part:Destroy()
	end
end

refreshAttract = function(player: Player)
	local lane = Lane.get(player)
	if runState[player] == RunState.Menu and lane and frogs[player] then
		if not attract[player] then
			attract[player] = buildAttract(lane.origin)
		end
	else
		teardownAttract(player) -- limbs then ease home in the render loop
	end
end

-- One attract "climb" (FrogAI's CheckTouch -> grab -> pull): recycle any rung
-- the last pull dropped off the bottom to the top of the ladder, grab the rung
-- one gap above the body with the demo hand, and pull the whole ladder down a
-- gap so that rung lands level with the body. The held hand follows its rung
-- down in the render loop, which reads as the frog lifting itself up.
local function attractClimb(a: AttractState)
	local gap = WorldConfig.ATTRACT_STEP_Y_GAP
	local top: BasePart? = nil
	for _, rung in a.rungs do
		if not top or rung.Position.Y > top.Position.Y then
			top = rung
		end
	end
	for _, rung in a.rungs do
		if top and rung.Position.Y < a.origin.Y - 1.5 * gap then
			local x = a.origin.X - (top.Position.X - a.origin.X) -- keep the zig-zag alternating
			rung.CFrame = CFrame.new(x, top.Position.Y + gap, rung.Position.Z)
			top = rung
		end
	end
	local want = a.origin.Y + gap
	local target = a.rungs[1]
	for _, rung in a.rungs do
		if math.abs(rung.Position.Y - want) < math.abs(target.Position.Y - want) then
			target = rung
		end
	end
	a.held[WorldConfig.ATTRACT_LIMB] = target
	local info = TweenInfo.new(Config.PULL_TIME, Enum.EasingStyle.Sine)
	for _, rung in a.rungs do
		TweenService:Create(rung, info, { CFrame = rung.CFrame * CFrame.new(0, -gap, 0) }):Play()
	end
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
	cancelBob(f) -- Frog.Fall: CancelBob()
	-- drop anything still held (e.g. a step dragged out of bounds with us)
	for i = 1, Config.MAX_HELD_STEPS do
		local step = f.held[i]
		if step then
			forceReleaseStep(lane, step)
		end
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
		cancelBob(f)
		f.dead = false
		f.canFall = false
		f.model:SetAttribute("Dead", false)
		setRunState(player, RunState.Menu) -- doc 15 item 1: back to the main menu, not another fall
	end)
end

-- Tutorial "no death" rule (Core/LevelManager.cs ReportFall, levelIndex==1, doc
-- 13 item 5): pull the field back up by TUTORIAL_PULL_BACK pulls' worth of
-- distance and let the frog retry from its lane's origin -- no GameOver, no
-- score reset, no respawn delay.
--
-- Capped at lane.netPull (studs actually pulled forward since this level
-- began, doc 17 gap): an uncapped retreat undoes scroll that never happened on
-- a fall before any grab, dragging the Tutorial's one-shot spawnAllOnAwake
-- ladder -- which never respawns -- past the top bound, where the ordinary
-- out-of-bounds check permanently recycles it. Capping means a fall with no
-- prior grabs this level is a pure no-op pull, leaving the still-unclimbed
-- ladder exactly where it was.
local function tutorialRetry(lane: Lane.Lane, f: FrogState)
	for i = 1, Config.MAX_HELD_STEPS do
		local step = f.held[i]
		if step then
			forceReleaseStep(lane, step)
		end
	end
	local retreat = -math.min(Config.PULL_DISTANCE * Config.TUTORIAL_PULL_BACK, lane.netPull)
	if retreat < 0 then
		pullLane(lane, retreat, 0.6)
	end
	f.pos = lane.origin
	f.gravityMult = Config.GRAVITY_MULT_START
	cancelBob(f)
end

-- The fall loop (Frog.cs SteadilyLowerHead) + lava check (per-lane via
-- Config.LAVA_Y -- lanes only offset along X, so Y bounds stay shared) +
-- rendering: limbs snap to their held step or ease back to rest, exactly as
-- the client used to do locally.
--
-- Config.LAVA_Y (-15.714 studs = Unity's -50 units) is where Frog.cs stops
-- lowering the head and where Step.cs draws the lava splash -- i.e. the lava
-- surface, which is also the bottom edge of the camera band. This check used
-- Config.DESPAWN_Y (-30), the *step* recycle line half a screen lower, so the
-- frog sank out of sight and kept falling for ~a third of each fall before the
-- run ended (b-20260919-200543-yixb).
--
-- Like SteadilyLowerHead, the frog keeps sinking while it holds a step; Unity
-- only stops lowering once the head reaches -50 u, so a holding frog rests on
-- LAVA_Y instead of dying there. Death is reaching LAVA_Y with nothing held
-- (doc 17 "Death condition"). While a Frog.Bob rise tween runs it owns Y, as
-- DOMoveY overrides Unity's per-frame Translate. The multiplier keeps growing
-- through it, as in Unity.

-- DOTween Ease.OutSine from `tw.from` to `tw.to`; second result is "finished".
local function bobTweenValue(tw: BobTween, now: number): (number, boolean)
	if tw.duration <= 0 then
		return tw.to, true
	end
	local a = math.clamp((now - tw.started) / tw.duration, 0, 1)
	return tw.from + (tw.to - tw.from) * math.sin(a * math.pi / 2), a >= 1
end

-- DOPunchRotation(strength, 1 s, vibrato 1, elasticity 1): DOTween splits it
-- into 2 segments (1/3 and 2/3 of the duration): out to the punch, back to 0.
-- nil once it's over (the trailing DORotate(zero) is then a no-op).
local function rockAngle(r: { angle: number, started: number }, now: number): number?
	local t = (now - r.started) / Config.BOB_ROCK_TIME
	if t >= 1 then
		return nil
	end
	if t < 1 / 3 then
		local u = t * 3
		return r.angle * (1 - (1 - u) * (1 - u))
	end
	local u = (t - 1 / 3) * 1.5
	return r.angle * (1 - (1 - (1 - u) * (1 - u)))
end

RunService.Heartbeat:Connect(function(dt: number)
	for plr, f in pairs(frogs) do
		local lane = Lane.get(plr)
		if not lane then
			continue
		end

		-- doc 15 item 1: gravity/death only apply while actually Playing -- in
		-- Menu/Dead the frog is parked at rest (no gravity ever accumulates for
		-- it, so it just sits at whatever f.pos it was left at; the rendering
		-- below still runs every tick so limbs ease back to rest normally). Also
		-- gated on f.canFall (Player.cs `canFall`): a fresh/respawned frog sits at
		-- its spawn step until the first grab, exactly like Unity, instead of
		-- immediately sinking toward the lava with nothing held.
		if not f.dead and runState[plr] == RunState.Playing and f.canFall then
			local now = os.clock()
			local holding = isHolding(f)
			f.gravityMult += Config.GRAVITY_ACCEL * dt
			local x, y = f.pos.X, f.pos.Y
			local bobX = f.bobX
			if bobX then
				local v, done = bobTweenValue(bobX, now)
				x = v
				if done then
					f.bobX = nil
				end
			end
			local bobY = f.bobY
			if bobY then
				local v, done = bobTweenValue(bobY, now)
				y = v
				if done then
					f.bobY = nil
				end
			elseif not holding or y > Config.LAVA_Y then
				local speed = math.min(Config.GRAVITY * f.gravityMult, Config.MAX_FALL_SPEED)
				y -= speed * dt
				if holding then
					y = math.max(y, Config.LAVA_Y) -- SteadilyLowerHead: `while HeadPosition.y > -50`
				end
			end
			f.pos = Vector3.new(x, y, Config.PLANE_Z)
			if not holding and f.pos.Y <= Config.LAVA_Y then
				if lane.levelIndex == Levels.TUTORIAL then
					tutorialRetry(lane, f)
				else
					killFrog(plr, f, lane)
				end
			end
		end

		-- Attract mode decision (FrogAI.cs Update): the demo hand hops up the ladder
		local a = attract[plr]
		if a and os.clock() - a.lastDecision >= WorldConfig.ATTRACT_DECISION_TIME then
			a.lastDecision = os.clock()
			attractClimb(a)
		end

		-- Frog.Bob's rock rotates the whole rig, rest limbs included, so
		-- world/GrabTarget's `body.CFrame * LIMB_REST` still matches the rest pose.
		local bodyCF = CFrame.new(f.pos)
		local rock = f.rock
		if rock then
			local angle = rockAngle(rock, os.clock())
			if angle then
				bodyCF *= CFrame.Angles(0, 0, math.rad(angle))
			else
				f.rock = nil
			end
		end
		f.body.CFrame = bodyCF
		local head = f.head
		if head then
			head.CFrame = bodyCF * f.headOffset
		end
		for i, limbPart in f.limbs do
			local step = f.held[i] or (a and a.held[i])
			local reach = f.reach[i]
			if step and step.Parent then
				-- Unity snaps the held hand to the step's transform.position
				-- (Player/Limb.cs Move), which a non-centre sprite pivot
				-- (Shared/StepKinds `gripOffset`) puts off the canvas centre.
				local grip = step:GetAttribute("GripOffset") :: Vector2?
				local gripPos = if grip then step.Position + Vector3.new(grip.X, grip.Y, 0) else step.Position
				limbPart.CFrame = CFrame.new(gripPos) -- follow the (scrolling) step
			elseif reach and os.clock() - reach.started < Config.LIMB_REACH_TIME then
				-- DOTween's default ease (OutQuad), as Limb.Move uses
				local t = (os.clock() - reach.started) / Config.LIMB_REACH_TIME
				limbPart.CFrame = reach.from:Lerp(reach.to, 1 - (1 - t) * (1 - t))
			else
				local target = bodyCF * f.limbOffsets[i]
				local alpha = math.clamp(dt / Config.LIMB_RETURN_TIME, 0, 1)
				limbPart.CFrame = limbPart.CFrame:Lerp(target, alpha)
				-- the empty hand stays open (Reaching) until it's home again
				if reach and (limbPart.Position - target.Position).Magnitude < 0.5 then
					endReach(f, i)
				end
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

-- Frog.Bob (Frog.cs:254-279), run on every successful grab: reset the fall
-- curve, sway the frog to the step's X with a rock punch, and -- only if it has
-- sunk to BOB_TRIGGER_Y or lower and isn't already rising -- lift it back up.
-- Unity's HeadPosition is local to the frog root, which sits at the lane origin.
local function bob(f: FrogState, lane: Lane.Lane, step: BasePart)
	local now = os.clock()
	f.gravityMult = Config.GRAVITY_MULT_START
	f.bobStep = step
	local xDest = step.Position.X
	local dx = xDest - f.pos.X
	f.rock = { angle = Config.BOB_ROCK_DEG_PER_STUD * -dx, started = now }
	f.bobX = { from = f.pos.X, to = xDest, started = now, duration = math.abs(dx) * Config.BOB_X_TIME_PER_STUD }
	local headY = f.pos.Y - lane.origin.Y
	if headY <= Config.BOB_TRIGGER_Y and not f.bobY then
		local yDest = math.min(Config.BOB_TOP_Y, headY + Config.BOB_RISE)
		f.bobY = {
			from = f.pos.Y,
			to = lane.origin.Y + yDest,
			started = now,
			duration = math.abs(yDest - headY) * Config.BOB_Y_TIME_PER_STUD,
		}
	end
end

GrabStep.OnServerEvent:Connect(function(player, step, tapPos, limbIndex)
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
	if not f or f.dead then
		ForceRelease:FireClient(player, step)
		return
	end
	-- Which limb grabbed: the client owns that choice (a mouse button drives a
	-- fixed hand, a finger takes whichever hand is free), but it's validated
	-- here -- a bad index, or a limb already on a step, is refused rather than
	-- overwriting the other hand's hold.
	if not isLimbIndex(limbIndex) or f.held[limbIndex] then
		ForceRelease:FireClient(player, step)
		return
	end
	local limb: number = limbIndex
	-- reject a step someone already holds, or grabs faster than humanly possible;
	-- ForceRelease corrects the client that optimistically snapped a limb on
	for _, held in pairs(f.held) do
		if held == step then
			ForceRelease:FireClient(player, step)
			return
		end
	end
	if not grabAllowed(player) then
		ForceRelease:FireClient(player, step)
		return
	end
	-- reach check against the SERVER's lane origin (no client trust left here).
	-- Not f.pos: Frog.Bob sways the frog to each grabbed step's X, and it sinks
	-- while holding, so it can drift far from the origin. Unity has no reach
	-- limit at all, and Lane.luau keeps every spawn within MAX_GRAB_DISTANCE of
	-- the origin, so that is the anchor this sanity bound is measured from.
	local reach = (Vector2.new(step.Position.X, step.Position.Y) - Vector2.new(lane.origin.X, lane.origin.Y)).Magnitude
	if reach > Config.MAX_GRAB_DISTANCE then
		ForceRelease:FireClient(player, step)
		return
	end
	-- grade quality server-side from the reported tap point (doc 07): garbage
	-- input can at worst claim "Perfect", which only flashes the HUD
	local quality = if typeof(tapPos) == "Vector3" then PullMath.gradeGrab(tapPos, step.Position) else "OK"

	bob(f, lane, step) -- before the pull, so it reads the step's pre-pull X (Limb.CloseHand order)
	pullLane(lane, Config.PULL_DISTANCE, Config.PULL_TIME)
	addScore(player, 1, quality)

	local wasTutorial = lane.levelIndex == Levels.TUTORIAL
	lane:onStepClimbed() -- level-threshold / tutorial progress; fires LevelChanged("soft") itself (doc 13 item 5)
	if wasTutorial and lane.levelIndex ~= Levels.TUTORIAL then
		-- Tutorial -> Pot: the tree ladder never respawns and Pot's spawners start
		-- cold at their off-screen staging point, so prefill Pot's first screenful
		-- the same way StartRun does (no-op if the lane somehow has steps already)
		lane:prefill(function(_state, kindName, worldPos)
			acquireStep(lane, kindName, worldPos)
		end)
	end

	-- Player.cs TouchStep: the first grab of a (pullable) step arms falling --
	-- every step the port spawns is pullable, so any successful grab qualifies.
	f.canFall = true

	-- step behaviors (doc 05): track the holding limb, then dispatch onGrab
	endReach(f, limb)
	f.held[limb] = step
	local b = behaviorOf(step)
	if b.onGrab then
		b.onGrab(makeCtx(lane, step, player))
	end
end)

ReleaseStep.OnServerEvent:Connect(function(player, limbIndex, step)
	-- only the recorded holder may release; ForceRelease already dropped it from
	-- f.held, so the client's echo after a forced drop lands here as a no-op
	if typeof(step) ~= "Instance" or not step:IsA("BasePart") or not isLimbIndex(limbIndex) then
		return
	end
	local lane = Lane.get(player)
	local f = frogs[player]
	if not lane or not f then
		return
	end
	local held = false
	for i = 1, Config.MAX_HELD_STEPS do
		if f.held[i] == step then
			f.held[i] = nil
			stopBob(f, step) -- Limb.OpenHand -> Frog.StopBob
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

-- A tap that hit no step or bug (Controller.CheckTouch's miss branch): the free
-- limb shoots out to the tap point (Limb.Move) and the Heartbeat eases it back.
-- Purely visual, so validation only keeps it sane: a live frog mid-run (or on
-- the start screen, with the hand the attract demo isn't using), a free limb,
-- a finite point, and no further than a grab could reach.
ReachEmpty.OnServerEvent:Connect(function(player, tapPos, limbIndex)
	if typeof(tapPos) ~= "Vector3" or not isLimbIndex(limbIndex) then
		return
	end
	if tapPos.X ~= tapPos.X or tapPos.Y ~= tapPos.Y or tapPos.Magnitude == math.huge then
		return -- NaN / inf
	end
	local f = frogs[player]
	if not f or f.dead then
		return
	end
	local limb: number = limbIndex
	local state = runState[player]
	if not (state == RunState.Playing or (state == RunState.Menu and limb ~= WorldConfig.ATTRACT_LIMB)) then
		return
	end
	if f.held[limb] then
		return
	end
	local offset = Vector2.new(tapPos.X - f.pos.X, tapPos.Y - f.pos.Y)
	if offset.Magnitude > Config.MAX_GRAB_DISTANCE then
		offset = offset.Unit * Config.MAX_GRAB_DISTANCE
	end
	local limbPart = f.limbs[limb]
	f.reach[limb] = {
		from = limbPart.CFrame,
		to = CFrame.new(f.pos.X + offset.X, f.pos.Y + offset.Y, limbPart.Position.Z),
		started = os.clock(),
	}
	limbPart:SetAttribute("Reaching", true)
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
	cancelBob(f)
	f.dead = false
	f.canFall = false
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
		for i = 1, Config.MAX_HELD_STEPS do
			f.held[i] = nil -- no ForceRelease: the holder is leaving
		end
		frogs[player] = nil
		f.model:Destroy()
	end
	teardownAttract(player)
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
