--!strict
-- ServerScriptService/GameServer (Script)
-- Authoritative side of the Hotfrog loop:
--   * spawns & pools steps (Spawning/StepSpawner.cs + ObjectPool.cs), now per
--     Lane (doc 13: one PlayField "lane" per player -- see server/Lane.luau)
--   * owns the pull / world-scroll along each lane's own spawn direction
--     (Spawning/SpawnManager.cs PullStep/PullVector)
--   * owns every frog: position, gravity, limbs, death, respawn (Player/Frog.cs)
--   * tracks score and persists the high score (Core/VariableManager.cs)
--   * drives level flow per lane (Tutorial -> Pot -> Kitchen -> Country -> Space)
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

local Config = require(ReplicatedStorage.Shared.Config)
local PullMath = require(ReplicatedStorage.Shared.PullMath)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local SkinCatalog = require(ReplicatedStorage.Shared.SkinCatalog)
local SkinTints = require(ReplicatedStorage.Shared.SkinTints)
local StepBehaviors = require(ReplicatedStorage.Shared.StepBehaviors)
local StepKinds = require(ReplicatedStorage.Shared.StepKinds)
local Levels = require(ReplicatedStorage.Shared.Levels)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local Profiles = require(script.Parent.Profiles)
local Lane = require(script.Parent.Lane)
local Chef = require(script.Parent.Chef)

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
local ScoreChanged = ensureRemote("ScoreChanged") -- server -> client: score (incl. combo bonus)/best (steps)/quality/grabQuality/steps (real steps this run)
local GameOver = ensureRemote("GameOver") -- server -> client: run ended, restart (score, cause)
local ForceRelease = ensureRemote("ForceRelease") -- server -> client: drop this step (Step.cs ForceRelease)
local StepExploded = ensureRemote("StepExploded") -- server -> all clients: a Potato's fuse blew it up (world position Vector3, optional burst style string: nil = potato chunks, "Pebble" = rock spray); Effects.client.luau draws the blast (StepBehaviors.ExplodeAfterGrab, doc 17)
local LevelChanged = ensureRemote("LevelChanged") -- server -> client: this lane's level/transition changed
local ScreenObstruction = ensureRemote("ScreenObstruction") -- client -> server: rough lane-relative world rectangle of the open Roblox PlayerList (minX, minY, maxX, maxY studs), or no args when closed; rate-limited and validated, grab pulls are lengthened to keep steps out of it (doc 17)

-- Phase 5 (docs/roblox-port/15-menus-and-input.md): the Menu -> Playing -> Dead
-- -> Menu run-state machine + its remotes. Everything below is additive on top
-- of the existing loop; it never changes GrabStep/ScoreChanged/GameOver/
-- LevelChanged's own contracts, only gates when they fire.
local StartRun = ensureRemote("StartRun") -- client -> server: begin a run from Menu (rate-limited, Menu-only) (mode: "Normal" | "Classic" | "Tutorial", optional, default Classic; "Tutorial" forces the Tutorial level via the same reset ReplayTutorial uses, then the run itself is Classic; anything else/missing also falls back to Classic; the lane's Mode attribute mirrors the resulting Classic/Normal scroll mode)
local RunStateChanged = ensureRemote("RunStateChanged") -- server -> client: this player's Menu/Playing/Dead state
local RunSummary = ensureRemote("RunSummary") -- server -> client: end-of-run stats for the end-of-run panel (score, newBest, isNewBest, quality, bugs, flys, cause, steps; newBest/isNewBest are steps-based)
local SetMusicOn = ensureRemote("SetMusicOn") -- client -> server: settings toggle (writes profile.musicOn)
local ReplayTutorial = ensureRemote("ReplayTutorial") -- client -> server: settings action (Menu-only)
local GetTopScores = ensureRemoteFunction("GetTopScores") -- client -> server: (period: "all" | "daily" | "weekly", optional, default "all"; anything else = "all") -> cached global top-10 { userId, name, score } for that board
ensureRemoteFunction("ClaimDailyReward") -- client -> server: claim today's daily login streak reward; returns nil until the profile loads, else { granted, streak, reward, rewards } (DailyService owns it)
ensureRemoteFunction("GetMissions") -- client -> server: today's 3 daily missions; nil until the profile loads, else { { text, progress, target, reward } } (MissionService owns it)
ensureRemote("MissionCompleted") -- server -> client: a daily mission just finished and paid its Flys (text, reward) (MissionService owns it)
ensureRemoteFunction("FeedJar") -- client -> server: (amount: positive whole Flys <= balance) move Flys into the Fly Jar for good; returns true when fed, new totals arrive via ProfileChanged, the tier title on the player's JarTitle attribute (SkinService owns it)
ensureRemoteFunction("BuyTint") -- client -> server: (skinId, tintId) buy a SkinTints colourway for an owned skin with Flys; returns true when owned, new totals via ProfileChanged (SkinService owns it)
ensureRemote("SelectTint") -- client -> server: (skinId, tintId; 0 = none) wear an owned tint on an owned skin; the worn tint of the selected skin replicates as the player's FrogTint attribute (SkinService owns it)
local ReturnToMenu = ensureRemote("ReturnToMenu") -- client -> server: Roblox's Reset Character button (MenuClient hooks ResetButtonCallback; there is no Roblox character to reset) -- abandon the current run, banking its score, and go straight back to the main menu (Playing-only)
local SetEndPanelOpen = ensureRemote("SetEndPanelOpen") -- client -> server: true while MenuClient's end-of-run/gift panel is still up (b-20260922-162231): the server flips Dead -> Menu on its own RESPAWN_DELAY timer, well before the player dismisses that panel (Home/Replay), so attract mode must wait on this rather than on RunState alone

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

-- b-20260922-162231: true while the player's end-of-run/gift panel is still on
-- screen (MenuClient's endPanelDismissed == false), reported via SetEndPanelOpen.
-- Menu-run-state alone isn't enough to gate attract: the Dead -> Menu flip above
-- is the server's own timer, not the player dismissing that panel.
local endPanelOpen: { [Player]: boolean } = {}

-- Attract mode (below the frog section): builds/tears down a Menu lane's
-- decorative ladder. Forward-declared so setRunState can drive it.
local refreshAttract: (player: Player) -> ()

-- Combo streak (b-20261010-192608-4bs3, ruling 8zmn; both run modes since
-- b-20261012-203452-bisk): lives on the lane folder as `Streak` (points) and
-- `StreakSpeed` (the multiplier) so the HUD and cosmetics can read it.
local function setStreak(lane: Lane.Lane, streak: number)
	lane.folder:SetAttribute("Streak", streak)
	lane.folder:SetAttribute("StreakSpeed", PullMath.streakSpeed(streak))
end

local function streakOf(lane: Lane.Lane): number
	local v = lane.folder:GetAttribute("Streak")
	return if typeof(v) == "number" then v else 0
end

-- The lane's current combo speed multiplier (1 with no streak).
local function laneSpeed(lane: Lane.Lane): number
	local v = lane.folder:GetAttribute("StreakSpeed")
	return if typeof(v) == "number" then v else 1
end

-- os.clock() of each lane's last streak gain: the streak breaks once
-- Config.STREAK_TIMEOUT passes without one (b-20261012-205417-kzbm).
local streakGainAt: { [Lane.Lane]: number } = setmetatable({}, { __mode = "k" }) :: any

local function streakWeight(quality: string): number
	if quality == "Perfect" then
		return Config.STREAK_WEIGHTS.Perfect
	elseif quality == "Great" then
		return Config.STREAK_WEIGHTS.Great
	end
	return Config.STREAK_WEIGHTS.OK
end

local function setRunState(player: Player, state: string)
	runState[player] = state
	local lane = Lane.get(player)
	if lane then
		setStreak(lane, 0) -- any run-state change (start, death, menu) breaks the streak
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
	-- Frog.cs Die -> Fall(): once dead, the body keeps sinking (a held-still beat,
	-- then an eased drop to Config.DEATH_FALL_Y) instead of freezing at LAVA_Y.
	-- Set by killFrog, driven in the Heartbeat loop below, cleared on respawn.
	fallTween: BobTween?,
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
	splash.Size = Config.SPLASH_PART_SIZE
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
	-- Splash.cs Invoke("Destroy", 3f). The Parent guard covers a Flingee that
	-- clearFling already destroyed (its step was recycled or grabbed again).
	task.delay(Config.SPLASH_LIFETIME, function()
		if splash.Parent then
			splash:Destroy()
		end
		if flingees[step] == splash then
			flingees[step] = nil
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Step motion layer. A step is an anchored, pooled part, and this section is
-- the ONLY thing that writes its CFrame: once when it is acquired (or re-placed
-- by slideIn), then at most once per Heartbeat, batched through
-- workspace:BulkMoveTo. Everything that moves a step edits its Lane.StepState
-- instead, and the write composes
--     CFrame.new(base + offset + recoil - sag) * rotation(angle)
--   * base   -- the logical position. Lane.advanceMotions (pulls, slide-ins,
--               the Kitchen Chef's shove -- server/Chef.luau),
--               Lane.drift, StepBehaviors.Falling and a drop-away move it; spawn
--               spacing, the recycle bound and pull aim read it (Lane.restPosition).
--   * offset -- a moving behaviour's sweep (StepBehaviors Patrol / RiseAndFall).
--   * recoil -- a damped spring kicked along the pull on every grab.
--   * sag    -- a held step hangs a little lower, and eases back on release.
--   * angle  -- the idle spin, below.
-- Four writers used to add to the CFrame in turn each tick, and a drop-away was
-- a TweenService tween to a fixed target on top: it fought any pull or drift
-- that ran meanwhile, and kept playing on the part after it was pooled and
-- handed out again. A drop is now just more base travel, so it adds to a pull
-- and ends with the state when the step is released.
--
-- The visual terms are IN the replicated CFrame on purpose: the client
-- hit-tests it, and the frog Heartbeat further down snaps a held limb to
-- `step.CFrame * GripOffset`, so a recoiling or patrolling step carries its taps
-- and its hand with it. That Heartbeat is connected after this section's, so it
-- reads this tick's CFrames. Translation is always world-space (`+ Vector3`),
-- never the step's own frame: a step that spun before it was grabbed has a
-- tilted frame and must still fall, sag and scroll straight.
--
-- Idle spin (owner's request b-20260922-194446, doc 17 -- Unity's steps never
-- rotate): a step that has not been grabbed yet slowly tumbles, so the field
-- reads as falling debris. One signed rate (rad/s about Z) is rolled per spawn,
-- biased toward slow (Config.STEP_SPIN_*), and dropped for good on the grab, so
-- a held step's grip point -- and the limb snapped to it -- never drifts. A
-- pooled part re-rolls when it is acquired again. Kinds with StepKinds
-- `spin = false` (the shelves) never get a rate and stay level. Nothing else depends on a
-- step's orientation: every hit test and reach check is taken from its position
-- in world space.
-- ---------------------------------------------------------------------------
type StepState = Lane.StepState

-- Per-spawn options for acquireStep. `params` reaches the step's behaviour as
-- ctx.params (and its `sweep`); it is stored on the StepState, not on the part.
-- nil = the kind's own defaults (StepKinds `params`). A Lane.SpawnRequest is a
-- StepOpts: spawnStep below passes the lane's request straight through.
type StepOpts = {
	params: StepBehaviors.Params?,
	upstream: number?, -- Lane.SpawnRequest.upstream -> StepState.upstream (the recycle bound's allowance)
}

local function rollSpin(): number
	local t = math.random() ^ Config.STEP_SPIN_BIAS
	local deg = Config.STEP_SPIN_MIN_DEG + (Config.STEP_SPIN_MAX_DEG - Config.STEP_SPIN_MIN_DEG) * t
	return math.rad(deg) * (if math.random() < 0.5 then -1 else 1)
end

-- Grab recoil: an underdamped spring (PullMath.springStep) on StepState.recoil,
-- kicked with RECOIL_KICK studs/s along the pull. An impulse v0 peaks at
-- (v0 / omega) * e^(-zeta / root * atan(root / zeta)), root = sqrt(1 - zeta^2),
-- so the kick is solved from Config.STEP_RECOIL_DISTANCE, the peak in studs.
local RECOIL_OMEGA = 2 * math.pi * Config.STEP_RECOIL_FREQUENCY
local RECOIL_ZETA = math.clamp(Config.STEP_RECOIL_DAMPING, 0.05, 0.95) -- springStep needs it underdamped
local RECOIL_ROOT = math.sqrt(1 - RECOIL_ZETA * RECOIL_ZETA)
local RECOIL_KICK = Config.STEP_RECOIL_DISTANCE
	* RECOIL_OMEGA
	/ math.exp(-RECOIL_ZETA / RECOIL_ROOT * math.atan2(RECOIL_ROOT, RECOIL_ZETA))
local RECOIL_REST = 1e-3 -- studs; below this (and the matching speed) the spring is parked at exactly zero
local SAG_REST = 1e-3

local function kickRecoil(lane: Lane.Lane, st: StepState)
	if RECOIL_KICK <= 0 or RECOIL_OMEGA <= 0 then
		return
	end
	local dir = lane.spawnDirection
	-- a lane with no direction (never the case for a live level) dips straight down
	local along = if dir.Magnitude < 1e-4 then Vector3.new(0, -1, 0) else Vector3.new(dir.X, dir.Y, 0).Unit
	st.recoilVelocity += along * RECOIL_KICK
end

local function isHeldBy(f: FrogState?, step: BasePart): boolean
	if f then
		for i = 1, Config.MAX_HELD_STEPS do
			if f.held[i] == step then
				return true
			end
		end
	end
	return false
end

-- Advance one step's own dynamics by `dt`: spin, drop-away, recoil, sag.
-- (Motions, drift and the behaviour's onTick have already moved it this tick.)
local function advanceStep(st: StepState, dt: number, held: boolean)
	local rate = st.spinRate
	if rate then
		st.angle += rate * dt -- ungrabbed: keep tumbling
	end

	-- ctx.dropAway (Step.cs Fall: DOLocalMoveY(-100), here Quad/In over
	-- DROP_TIME): played as increments of base travel, so a pull or drift that
	-- runs meanwhile simply adds to it. The recycle bound ends it long before
	-- the full DROP_DISTANCE.
	local elapsed = st.dropElapsed
	if elapsed then
		local dropTime = math.max(Config.DROP_TIME, 1e-3)
		local before = PullMath.quadIn(elapsed / dropTime)
		elapsed += dt
		local after = PullMath.quadIn(elapsed / dropTime)
		st.base -= Vector3.new(0, Config.DROP_DISTANCE * (after - before), 0)
		st.dropElapsed = if after >= 1 then nil else elapsed
	end

	if st.recoil ~= Vector3.zero or st.recoilVelocity ~= Vector3.zero then
		local x, v = PullMath.springStep(st.recoil, st.recoilVelocity, dt, RECOIL_OMEGA, RECOIL_ZETA)
		if x.Magnitude < RECOIL_REST and v.Magnitude < RECOIL_REST * RECOIL_OMEGA then
			x, v = Vector3.zero, Vector3.zero -- settled: stop integrating (and stop re-writing the part)
		end
		st.recoil, st.recoilVelocity = x, v
	end

	local target = if held then Config.STEP_SAG_DISTANCE else 0
	if st.sag ~= target then
		local sag = st.sag + (target - st.sag) * PullMath.smoothAlpha(dt, Config.STEP_SAG_TIME)
		st.sag = if math.abs(target - sag) < SAG_REST then target else sag
	end
end

-- Depth bias (owner's report b-20261021-094526-pbfk, z fighting between
-- steps). Every step sits on the play plane (Z 0), so two overlapping step
-- decals were coplanar and flickered. Each acquire gets the next of
-- Z_BIAS_SLOTS evenly spaced, fixed Z nudges inside +-Z_BIAS_RANGE, so
-- neighbouring steps differ and a step keeps the same depth for its whole life.
-- Kept far inside the draw-order ruling b-20261015-100802-a17l (hand +0.3, arm
-- -0.2): a step never reaches either. It is part of the replicated CFrame only;
-- base, hit tests, reach and grip maths are all XY, so nothing reads it.
local Z_BIAS_SLOTS = 16
local Z_BIAS_RANGE = 0.05 -- studs; max |bias|
local zBiasCounter = 0

local function nextZBias(): number
	zBiasCounter = (zBiasCounter + 7) % Z_BIAS_SLOTS -- 7 is coprime to 16: visits every slot, neighbours far apart
	return ((zBiasCounter + 0.5) / Z_BIAS_SLOTS * 2 - 1) * Z_BIAS_RANGE
end

local function shownPosition(st: StepState): Vector3
	return st.base + st.offset + st.recoil - Vector3.new(0, st.sag, -st.zBias)
end

-- Write `step`'s CFrame from its state right now. Only for a step being placed
-- outside the per-tick batch: a fresh acquire, or slideIn moving a new batch
-- off-screen before anyone has seen it.
local function placeStep(step: BasePart, st: StepState)
	local pos = shownPosition(st)
	st.shownPosition = pos
	st.shownAngle = st.angle
	step.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, st.angle)
end

-- This tick's writes, for one workspace:BulkMoveTo at the end of the step
-- Heartbeat. A step whose composed position and angle did not change (a grabbed
-- step on a still Normal-mode lane) is left out, so it costs no write and no
-- replication. Hoisted: cleared and refilled every tick rather than reallocated.
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function queueStep(step: BasePart, st: StepState)
	local pos = shownPosition(st)
	if pos ~= st.shownPosition or st.angle ~= st.shownAngle then
		st.shownPosition = pos
		st.shownAngle = st.angle
		table.insert(moveParts, step)
		table.insert(moveCFrames, CFrame.new(pos) * CFrame.Angles(0, 0, st.angle))
	end
end

-- forward-declared: releaseStep and ctxOf reference each other
local releaseStep: (lane: Lane.Lane, step: BasePart) -> ()
-- forward-declared: ctxOf's setSpawnBias scaffolds a direction change (defined with slideIn below)
local scaffoldLane: (lane: Lane.Lane, anchorStep: BasePart) -> ()
-- forward-declared: ctxOf's requestExtraPull (defined with the pull section below)
local pullLane: (lane: Lane.Lane, distance: number, duration: number) -> ()

-- Extra pulls a behaviour asked for from inside onTick are held until the step
-- loop is over: a pull spawns steps, and adding to lane.states while the
-- Heartbeat is iterating it is undefined.
local ticking = false
local deferredPulls: { { lane: Lane.Lane, distance: number } } = {}

-- The behaviour context for one live step (StepBehaviors.Ctx): built the first
-- time a hook needs it and kept on the StepState until the step is released, so
-- a ticking step no longer costs a table and a dozen closures per frame. The
-- StepState table is the step's generation -- a pooled part's next life gets a
-- new one -- so `lane.states[step] == st` is "still the same live step". Every
-- entry that acts on the part checks it, so a delayed call that outlived its
-- step can't hit the part's next life even if the behaviour forgot stillValid().
local function ctxOf(lane: Lane.Lane, step: BasePart, st: StepState): StepBehaviors.Ctx
	local existing = st.ctx
	if existing then
		return existing
	end
	local function stillValid(): boolean
		return lane.states[step] == st
	end
	local ctx: StepBehaviors.Ctx = {
		step = step,
		player = lane.player, -- only the owning lane's player can ever grab or hold its steps
		origin = lane.origin,
		state = st.scratch,
		params = st.params,
		stillValid = stillValid,
		isHeld = function()
			return stillValid() and isHeldBy(frogs[lane.player], step)
		end,
		makeUnsteady = function()
			if stillValid() then
				step:SetAttribute("Unsteady", true) -- clients may shake/emit pebbles off this
			end
		end,
		explode = function()
			if stillValid() then
				releaseStep(lane, step) -- knocks the holder off too; effects (pebbles/sound) are client polish, doc 05
			end
		end,
		blast = function(style: string?)
			if stillValid() then
				-- a remote, not an attribute: the step leaves the replicated tree
				-- this same frame, so an attribute change on it never arrives
				StepExploded:FireAllClients(step.Position, style)
			end
		end,
		dropAway = function()
			if not stillValid() then
				return
			end
			forceReleaseStep(lane, step)
			if not st.dropElapsed then
				st.dropElapsed = 0 -- advanceStep plays it; the bounds check recycles it past DESPAWN_Y
			end
		end,
		forceRelease = function()
			if stillValid() then
				forceReleaseStep(lane, step)
			end
		end,
		getSpawnBias = function()
			return lane.spawnDirection
		end,
		setSpawnBias = function(bias: Vector2)
			if stillValid() and lane:changeDirection(bias) then
				scaffoldLane(lane, step)
			end
		end,
		getStreakSpeed = function()
			return laneSpeed(lane)
		end,
		getRunSteps = function()
			return lane.runSteps
		end,
		getBase = function()
			return st.base
		end,
		moveBase = function(delta: Vector3)
			if delta == delta then -- not NaN
				st.base += delta
			end
		end,
		setOffset = function(offset: Vector3)
			if offset ~= offset then
				return -- NaN
			end
			local length = offset.Magnitude
			st.offset = if length > Config.STEP_OFFSET_MAX then offset * (Config.STEP_OFFSET_MAX / length) else offset
		end,
		requestExtraPull = function(distance: number)
			if not stillValid() or distance ~= distance or distance <= 0 then
				return
			end
			local capped = math.min(distance, Config.PULL_MAX_DISTANCE)
			if ticking then
				table.insert(deferredPulls, { lane = lane, distance = capped })
			else
				pullLane(lane, capped, PullMath.pullTime(capped))
			end
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
	st.ctx = ctx
	return ctx
end

releaseStep = function(lane: Lane.Lane, step: BasePart)
	local st = lane.states[step]
	if not st then
		return -- idempotent: behaviors and the bounds check can both recycle
	end
	local onDestroy = st.behavior.onDestroy
	if onDestroy then
		onDestroy(ctxOf(lane, step, st))
	end
	forceReleaseStep(lane, step)
	-- Drops the StepState -- spin, offset, any drop-away in flight, the cached
	-- ctx -- and takes the step out of any slide-in still playing (Lane motions),
	-- so the pooled part carries nothing into its next life.
	lane:untrackStep(step)
	step.Parent = nil
	step:SetAttribute("LaneUserId", nil)
	table.insert(pool, step)
end

-- Halloween step tints (b-20261016-125004-mog8, idea 4; port-only, doc 17):
-- while SpriteSkin.halloweenLive, kinds with no tint of their own (the moving /
-- timed kinds keep theirs as a gameplay signal) wear a candy-corn colour on the
-- step Decal. Colour only: no gameplay change. Keyed by sprite stem. The orange
-- "pumpkin" tint on Potato and WrappedRock is gone: the real pumpkin is now its
-- own step, StepKinds.Pumpkin (b-20261016-192144-g2e2, Lane.pickKind).
local HALLOWEEN_TINTS: { [string]: Color3 } = {
	CrumblyRock = Color3.new(1, 0.9, 0.5), -- candy-corn yellow
	WhiteRock = Color3.new(1, 0.97, 0.88), -- candy-corn white tip
}

-- The tint a kind wears this Halloween, or nil (not live, kind already tinted, or
-- no entry for its sprite).
local function halloweenTint(kind: StepKinds.Kind?, live: boolean): Color3?
	if not live or not kind or kind.color then
		return nil
	end
	return HALLOWEEN_TINTS[kind.sprite]
end

-- Take a step out of the pool for `lane`, dressed as `kindName`, at `worldPos`
-- (its base). `opts.params` are this spawn's own parameters for the kind's
-- behaviour (e.g. a Patrol's amplitude/period -- see each StepBehaviors entry),
-- defaulting to the kind's own (StepKinds `params`); they live on the step's
-- StepState, reach the behaviour as ctx.params, and are never re-read from
-- attributes.
local function acquireStep(lane: Lane.Lane, kindName: string, worldPos: Vector3, opts: StepOpts?): BasePart
	local kind = StepKinds[kindName]
	local step = (table.remove(pool) or template:Clone()) :: BasePart
	step:SetAttribute("Kind", "Step")
	-- replicated spawn generation; the server's own "same life?" test is the StepState (ctxOf)
	step:SetAttribute("Gen", ((step:GetAttribute("Gen") :: number?) or 0) + 1)
	step:SetAttribute("Unsteady", false)
	step:SetAttribute("Shrugged", false)
	step:SetAttribute("ChefTarget", nil) -- pooling: the Kitchen Chef's mark (server/Chef.luau) never outlives a life
	step:SetAttribute("LaneUserId", lane.userId)
	step.Anchored = true -- we move it ourselves (kinematic)
	clearFling(step) -- pooling safety: a recycled step must not inherit a live Flingee

	step:SetAttribute("Behavior", if kind then kind.behavior else "None")
	step:SetAttribute("KindName", kindName) -- Lane.onStepClimbed reads this back to track tutorial grace
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
	-- Unity tints several kinds' shared blank sprites (WhiteRock.png etc.) per
	-- prefab via SpriteRenderer.color (StepKinds `color`, doc 12 §1). This part
	-- is pooled and reused across kinds, so untinted kinds must explicitly reset
	-- to white or a previous kind's tint would leak onto them
	-- (b-20260921-164509-uork).
	local art = step:FindFirstChild("Art")
	if art and art:IsA("Decal") then
		art.Color3 = if kind and kind.color
			then kind.color
			else (halloweenTint(kind, SpriteSkin.halloweenLive()) or Color3.new(1, 1, 1))
	end

	-- A fresh StepState: no spin angle, offset, recoil, sag or drop-away from
	-- the part's previous life, and an empty scratch table for the behaviour.
	local st = lane:trackStep(step, worldPos)
	local behavior = behaviorOf(step)
	local params: StepBehaviors.Params? = opts and opts.params
	if not params and kind then
		params = kind.params
	end
	st.behavior = behavior
	if params then
		st.params = params
	end
	local upstream = opts and opts.upstream
	if upstream and upstream == upstream and upstream > 0 then
		st.upstream = upstream -- staged upstream on purpose: Lane.isOutOfBounds allows it that far past
	end
	if behavior.sweep then
		st.sweep = behavior.sweep(params) -- reserved by Lane.clearSpot for every later spawn
	end
	st.zBias = nextZBias()
	-- the pot's rim and the direction arrows stay level (the arrow is the info);
	-- so does any kind with `spin = false` (shelves, b-20261021-094844-4kya).
	-- st.angle is 0 in a fresh StepState, so a re-acquired pooled shelf is level.
	if kindName ~= Lane.POT_RIM_KIND and not (kind and (kind.isArrow or kind.spin == false)) then
		st.spinRate = rollSpin()
	end
	if behavior.onSpawn then
		behavior.onSpawn(ctxOf(lane, step, st)) -- after the attributes above: it may read HitSize
	end
	placeStep(step, st) -- before it is parented, so it never renders where its last life ended
	step.Parent = container
	return step
end

-- The spawn callback every Lane spawn path takes (Lane.SpawnFn): create the
-- step a lane asked for (Lane.SpawnRequest), its per-spawn params included.
local function spawnStep(lane: Lane.Lane, request: Lane.SpawnRequest): BasePart
	return acquireStep(lane, request.kindName, request.position, request)
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
-- per-lane -- doc 13 item 4) by `distance` studs over `duration` s. The motion
-- itself is played by Lane.advanceMotions from the Heartbeat below; pulls add
-- up rather than cancelling each other. A positive pull also runs the lane's
-- spawners for the time it earned (Lane.spawnForPull): the new steps are created
-- off-screen and ride this pull in, so they visibly slide in rather than pop up
-- (owner's ruling, b-20260921-164429-ee9c). A negative `distance` undoes
-- previous pulls (used by the Tutorial's no-death fall rule below).
-- ---------------------------------------------------------------------------
-- Replicate a scroll so clients can move lane-local cosmetics (scenery, walls) in step.
-- `PullDelta` / `PullTime` / `PullCount` are the original contract, read by
-- several client scripts, and stay exactly as they were. Two attributes ride
-- along for world/PullScroller, both written BEFORE the PullCount bump:
--   * `PullLinear` -- true for a Classic drift chunk, which the steps themselves
--     travelled at constant speed; a grab's pull is eased (Lane.addMotion).
--   * `PullTotal`  -- the sum of every delta published since the lane's pulls
--     last started over (Lane.resetRun zeroes it and bumps `PullEpoch`). Two
--     pulls published in one server frame -- a drift chunk and a grab, the
--     Tutorial pull-back and another -- can reach a client as ONE change showing
--     only the second delta; the total lets the scroller see what it missed.
local function publishPull(lane: Lane.Lane, delta: Vector3, duration: number, linear: boolean?)
	local total = lane.folder:GetAttribute("PullTotal")
	lane.folder:SetAttribute("PullDelta", delta)
	lane.folder:SetAttribute("PullTime", duration)
	lane.folder:SetAttribute("PullLinear", linear == true)
	lane.folder:SetAttribute("PullTotal", (if typeof(total) == "Vector3" then total else Vector3.zero) + delta)
	lane.folder:SetAttribute("PullCount", ((lane.folder:GetAttribute("PullCount") :: number?) or 0) + 1)
end

pullLane = function(lane: Lane.Lane, distance: number, duration: number)
	local delta = lane:addPull(distance, duration)
	if not delta then
		return
	end
	publishPull(lane, delta, duration)
	if distance > 0 then
		lane:spawnForPull(distance, spawnStep)
	end
end

-- Slide a batch of freshly created steps (a prefill screenful, the Tutorial
-- ladder) in from off-screen instead of popping them into view: move the whole
-- batch back along the lane's travel direction until every one of them is
-- outside the camera band (Lane.entryShift), then play that shift back over
-- Config.SLIDE_IN_TIME. Where they come to rest is unchanged. `from` overrides
-- the travel direction (the direction-change scaffold always drops in from the top).
-- `steps` is only read here (the Heartbeat passes its reused batch table).
local function slideIn(lane: Lane.Lane, steps: { BasePart }, from: Vector2?)
	local dir = from or lane.spawnDirection
	if #steps == 0 or dir.Magnitude < 1e-4 then
		return
	end
	local u = Vector3.new(dir.X, dir.Y, 0).Unit
	local shift = 0
	for _, step in steps do
		shift = math.max(shift, lane:entryShift(lane:basePosition(step), step.Size, u))
	end
	if shift <= 0 then
		return
	end
	local set: { [BasePart]: boolean } = {}
	for _, step in steps do
		local st = lane.states[step]
		if st then
			st.base -= u * shift
			-- written now, not left to the next Heartbeat's batch: this can run from
			-- a remote handler, and the part must not replicate at its rest point first
			placeStep(step, st)
			set[step] = true
		end
	end
	lane:addMotion(u * shift, Config.SLIDE_IN_TIME, set)
end

-- Prefill `lane` (Lane.prefill) and slide the batch in.
local function prefillLane(lane: Lane.Lane)
	local batch: { BasePart } = {}
	lane:prefill(function(_lane, request)
		table.insert(batch, spawnStep(lane, request))
	end)
	slideIn(lane, batch)
end

-- A grabbed ChangeDirection* step turned the lane (Lane.changeDirection): lay a
-- short scaffold toward the new heading from where that step will rest
-- (Lane.scaffold) and drop it in from above the view (owner's request
-- b-20260921-182631-0a8u, doc 17).
scaffoldLane = function(lane: Lane.Lane, anchorStep: BasePart)
	local batch: { BasePart } = {}
	lane:scaffold(lane:restPosition(anchorStep), function(_lane, request)
		table.insert(batch, spawnStep(lane, request))
	end)
	slideIn(lane, batch, Vector2.new(0, -1))
end

-- Starvation guard (b-20261020-220122-w9qy, doc 17). Without Classic drift the
-- field only moves, and the spawners only run, on a grab -- so a grab that
-- leaves nothing else to grab soft-locks the run for good: a small pull's
-- spawns all rest off-screen (and some are refused at the lane's edge under a
-- 45-degree arrow scroll), and with no further grab nothing ever brings them
-- in. True while `f` has a step to grab next: one it isn't holding, not
-- dropping away, resting in the camera band and within reach of the origin.
local function hasFoothold(lane: Lane.Lane, f: FrogState): boolean
	local shared = lane:sharedPending()
	for step, st in lane.states do
		if not st.dropElapsed and not isHeldBy(f, step) then
			-- judged at the grip point (a tall step's hand lands off-centre)
			local grip = step:GetAttribute("GripOffset") :: Vector2?
			local rel = lane:restPosition(step, shared) - lane.origin
			if grip then
				rel += Vector3.new(grip.X, grip.Y, 0)
			end
			if
				math.abs(rel.Y) <= Config.VIEW_HALF_HEIGHT
				and Vector2.new(rel.X, rel.Y).Magnitude <= Config.MAX_GRAB_DISTANCE
			then
				return true
			end
		end
	end
	return false
end

-- The Heartbeat's per-lane spawn batch (the Tutorial ladder's one-shot batch,
-- the pot's rim) and the callback that fills it, hoisted so an ordinary tick --
-- where neither spawns anything -- allocates nothing. Cleared per lane, and only
-- filled by the two Lane calls right after that.
local spawnBatch: { BasePart } = {}

local function spawnIntoBatch(lane: Lane.Lane, request: Lane.SpawnRequest)
	table.insert(spawnBatch, spawnStep(lane, request))
end

-- The Kitchen Chef's hooks (server/Chef.luau, owner's ruling
-- b-20261012-141130-fhme): Knife and Food knock the step loose the way any
-- behaviour does (ctx.dropAway -> the drop-away, then the bounds check pools
-- it); Shove slides just that step sideways as a lane motion.
local function chefIsHeld(lane: Lane.Lane, step: BasePart): boolean
	return isHeldBy(frogs[lane.player], step)
end

local function chefStrike(lane: Lane.Lane, step: BasePart, st: StepState, action: Chef.Action, shoveDir: number)
	if action == "Shove" then
		lane:addMotion(
			Vector3.new(shoveDir * Config.CHEF_SHOVE_DISTANCE, 0, 0),
			Config.CHEF_SHOVE_TIME,
			{ [step] = true }
		)
	else
		ctxOf(lane, step, st).dropAway()
	end
end

-- Per-lane motion/spawn tick + per-tick behavior hook (Falling's constant drift,
-- a Patrol's sweep, doc 05) + each step's own dynamics (advanceStep) + recycle
-- steps that leave the lane's bounds on any side (doc 13 item 4 -- Borders:
-- Left/Right/Top/Bottom catch, not just the lava line), then ONE batched write
-- of every step that moved (the step motion layer above).
--
-- Connected before the frog Heartbeat further down, which snaps held limbs to
-- the CFrames written here -- keep it that way.
RunService.Heartbeat:Connect(function(frameDt: number)
	-- A hitch (or a paused server resuming) would otherwise play as one giant
	-- step: a pull finishing instantly, a drift chunk teleporting the field.
	local dt = math.min(frameDt, Config.MAX_TICK_DT)
	-- Reset here as well as after each lane's loop: if anything in that loop
	-- errored last frame the flag was left set, and every extra pull asked for
	-- from an onGrab would be deferred to a flush this callback never reached.
	ticking = false
	table.clear(moveParts)
	table.clear(moveCFrames)
	for _, lane in Lane.iter() do
		lane:advanceMotions(dt)
		if runState[lane.player] ~= RunState.Playing then
			Chef.reset(lane)
			continue -- Menu/Dead: idle lane, no spawning (doc 15 item 1) -- and no steps to move
		end
		-- Combo timeout (b-20261012-205417-kzbm): no Perfect or Great grab for
		-- Config.STREAK_TIMEOUT seconds breaks the streak (the HUD shows COMBO LOST).
		if streakOf(lane) > 0 and os.clock() - (streakGainAt[lane] or 0) > Config.STREAK_TIMEOUT then
			setStreak(lane, 0)
		end

		table.clear(spawnBatch)
		lane:tickSpawners(dt, spawnIntoBatch)
		lane:spawnRim(spawnIntoBatch) -- the pot's rim, once the Pot is climbed
		slideIn(lane, spawnBatch) -- the Tutorial ladder's one-shot batch, the pot's rim

		-- Classic mode (Config.CLASSIC_SCROLL_SPEED, doc 17): the world keeps
		-- scrolling whether or not anything is held, once the first grab has armed
		-- the frog (Player.cs canFall, same gate as gravity). Each settled chunk
		-- earns spawner time per stud -- its spawns start off-screen and the drift
		-- carries them in, like a grab's -- and is replicated for the cosmetics.
		local f = frogs[lane.player]
		if f and f.canFall and not f.dead then
			-- The combo speeds the idle scroll too (b-20261012-205444-huc1).
			local chunk, chunkTime = lane:drift(dt, lane:driftSpeed(dt) * laneSpeed(lane))
			if chunk and chunkTime then
				publishPull(lane, lane.travel * chunk, chunkTime, true) -- linear: the steps drifted at constant speed
				lane:spawnForPull(chunk, spawnStep, chunk * Config.CLASSIC_SPAWN_PER_STUD)
			end
			-- A held step carried down into the lava (or off the lane's side) is
			-- let go, so the frog has to keep climbing or fall in after it.
			if lane.mode == Config.RUN_MODES.Classic then
				for i = 1, Config.MAX_HELD_STEPS do
					local held = f.held[i]
					if held then
						local grip = (held:GetAttribute("GripOffset") :: Vector2?) or Vector2.zero
						local gx = held.Position.X + grip.X - lane.origin.X
						local gy = held.Position.Y + grip.Y - lane.origin.Y
						if gy < Config.LAVA_Y or math.abs(gx) > Config.LANE_HALF_WIDTH then
							forceReleaseStep(lane, held)
						end
					end
				end
			end
		end

		-- What the lane's pulls still owe every step: once per lane, not once per
		-- step inside the bounds check.
		local pending = lane:sharedPending()
		local speed = laneSpeed(lane) -- combo streak speed-up (1 with no streak)
		ticking = true
		for step, st in lane.states do
			local onTick = st.behavior.onTick
			if onTick then
				-- Isolated: one step's behaviour erroring must not abort the whole
				-- Heartbeat (every lane's steps after it would freeze, unwritten). The
				-- step keeps its place as a plain foothold -- its hooks are dropped so
				-- it can't error again next frame -- and the error is reported once.
				-- (the cast: onTick returns nothing, so its typed pcall has no error slot)
				local ok, err = pcall(onTick :: (...any) -> ...any, ctxOf(lane, step, st), dt)
				if not ok then
					local kindName = tostring(step:GetAttribute("KindName"))
					warn(("[GameServer] %s onTick failed: %s"):format(kindName, tostring(err)))
					st.behavior = StepBehaviors.None
				end
				if lane.states[step] ~= st then
					continue -- the behaviour recycled its own step
				end
			end
			advanceStep(st, dt, isHeldBy(f, step))
			if lane:isOutOfBounds(step, pending) then
				releaseStep(lane, step)
			else
				queueStep(step, st)
			end
		end
		ticking = false

		-- The Kitchen Chef (server/Chef.luau): only once the frog is armed and alive.
		Chef.tick(lane, dt, f ~= nil and f.canFall and not f.dead, chefIsHeld, chefStrike, speed)
	end

	if #moveParts > 0 then
		-- FireCFrameChanged: nothing on the server listens for a step's
		-- Position/Orientation changing, so skip those per-part signals.
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end

	if #deferredPulls > 0 then
		for _, request in deferredPulls do
			if Lane.get(request.lane.player) == request.lane then
				pullLane(request.lane, request.distance, PullMath.pullTime(request.distance))
			end
		end
		table.clear(deferredPulls)
	end
end)

-- ---------------------------------------------------------------------------
-- Scoring (Core/VariableManager.cs). The high score lives on the shared Profile
-- (Profiles); sessionScore is the current run, banked into profile.highScore on
-- death. No DataStore here -- Profiles owns persistence.
-- sessionScore includes the Normal-mode combo bonus (HUD / run summary only);
-- sessionSteps is the real step count and is what best score, the leaderboards
-- and leaderstats use (owner ruling b426 on b-20261012-162429-k6wc).
-- ---------------------------------------------------------------------------
local sessionScore: { [Player]: number } = {}
local sessionSteps: { [Player]: number } = {}
-- true for a run the Studio-only StudioSkipTo (below) jumped ahead: its score is
-- not banked, so a skip never writes a best or a leaderboard entry.
local skippedRun: { [Player]: boolean } = {}

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

-- leaderstats: Score (current run, in steps -- no combo bonus) + Best (steps) in the built-in player list (doc 07)
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
		score.Value = sessionSteps[player] or 0
	end
	local best = stats:FindFirstChild("Best")
	if best and best:IsA("IntValue") then
		best.Value = bestOf(player)
	end
end

local function pushScore(player: Player, quality: string?)
	updateLeaderstats(player)
	ScoreChanged:FireClient(
		player,
		sessionScore[player] or 0,
		bestOf(player),
		quality,
		grabQuality[player],
		sessionSteps[player] or 0
	)
end

-- Only called for a grab: `amount` is 1 step plus any combo bonus; the step
-- count advances by exactly 1.
local function addScore(player: Player, amount: number, quality: string?)
	sessionScore[player] = (sessionScore[player] or 0) + amount
	sessionSteps[player] = (sessionSteps[player] or 0) + 1
	player:SetAttribute("RunSteps", sessionSteps[player]) -- real steps for missions/badges
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
	if skippedRun[player] then
		return
	end
	local p = Profiles.get(player)
	local score = sessionSteps[player] or 0 -- steps, not the bonus-inclusive sessionScore
	if p and score > p.highScore then
		p.highScore = score
		Profiles.save(player)
		Profiles.recordGlobalBest(player, score) -- mirror into the global top-N (doc 07)
	end
	-- Daily/weekly boards take every run, not just all-time bests; Profiles
	-- only writes when this beats the player's best for the current period.
	task.spawn(Profiles.recordPeriodScore, player, score)
end

local function resetScore(player: Player)
	sessionScore[player] = 0
	sessionSteps[player] = 0
	skippedRun[player] = nil
	player:SetAttribute("RunSteps", 0)
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
	if profile and entry then
		-- the worn colourway may swap the art (Hot Frog's Blue) or, for a colour
		-- tint, dress the frog in its tint-ready art (artName returns both values)
		local wornTint = profile.selectedTints[tostring(profile.selected)] or 0
		if wornTint ~= 0 and not profile.ownedTints[SkinTints.key(profile.selected, wornTint)] then
			wornTint = 0
		end
		SpriteSkin.apply(model, SkinTints.artName(profile.selected, wornTint, entry.name))
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
	-- Instance streaming is on, and a Default-mode model replicates as an empty
	-- shell whose parts stream in (and can stream out) on their own. Client
	-- scripts (WorldFrogCosmetics, GameClient) resolve the frog's parts and
	-- decals once when the model appears, so a missing PrimaryPart at that
	-- moment, or a part streamed out and back in as a new instance, leaves them
	-- driving stale decals -- the hands stop switching to the grip sprite.
	-- Persistent sends the whole rig atomically and never streams it out.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
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
-- ATTRACT_DECISION_TIME seconds (FrogAI's fixed 1s nextDecisionTime) the arm
-- on the rung's side grabs the rung above (so the arms alternate) and the
-- ladder is pulled down one rung gap -- the same "frog lifts, world scrolls" a
-- real grab does (pullLane) -- with the rung that leaves the bottom recycled
-- to the top. The other arm lets go of its older rung. A menu click/tap sends
-- the arm on that side reaching to it (ReachEmpty) and pauses the climb for
-- WorldConfig.ATTRACT_PAUSE_TIME. FrogAI raycasts a random on-screen step;
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
	pausedUntil: number, -- os.clock(); the player's menu click holds the demo until then
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
		-- WhiteRock.png is a blank white silhouette Unity tints per-prefab
		-- (StepKinds `color`, doc 12 §1); acquireStep does this for pooled steps
		-- but these decorative rungs bypass it, so they rendered untinted white
		-- (b-20260921-182534-oy7p, reopening b-20260921-164509-uork). Reuse
		-- FallingRock's tint -- the WhiteRock kind WorldConfig.ATTRACT_STEP_SIZE
		-- is itself sized after -- rather than hard-coding a new colour.
		local rockKind = StepKinds.FallingRock
		decal.Color3 = if rockKind and rockKind.color then rockKind.color else Color3.new(1, 1, 1)
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
	return { rungs = rungs, held = {}, origin = origin, lastDecision = os.clock(), pausedUntil = 0 }
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
	if runState[player] == RunState.Menu and lane and frogs[player] and not endPanelOpen[player] then
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
local function attractClimb(a: AttractState, f: FrogState)
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
	-- Hand-over-hand: the arm on the rung's side takes it (limb 1 = Right, +X;
	-- the ladder zig-zags, so the arms alternate) and the other arm lets go of
	-- its older rung, which is about to scroll off, so no arm is left stretched
	-- to a recycled rung and no rung is held twice.
	local limb = if target.Position.X >= a.origin.X then 1 else 2
	a.held[3 - limb] = nil
	a.held[limb] = target
	endReach(f, limb) -- drop any click-reach in flight on this arm
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
	-- Frog.cs Fall(): hold at the current (lava-line) height for
	-- DEATH_FALL_DELAY, then ease down to DEATH_FALL_Y -- the dramatic
	-- continued sink, driven in the Heartbeat loop below.
	f.fallTween = {
		from = f.pos.Y,
		to = Config.DEATH_FALL_Y,
		started = os.clock() + Config.DEATH_FALL_DELAY,
		duration = Config.DEATH_FALL_TIME,
	}
	-- drop anything still held (e.g. a step dragged out of bounds with us)
	for i = 1, Config.MAX_HELD_STEPS do
		local step = f.held[i]
		if step then
			forceReleaseStep(lane, step)
		end
	end

	local score = sessionScore[player] or 0
	local steps = sessionSteps[player] or 0
	local q = grabQuality[player]
	local qualitySnapshot = {
		Perfect = if q then q.Perfect else 0,
		Great = if q then q.Great else 0,
		OK = if q then q.OK else 0,
	}
	local oldBest = bestOf(player)
	commitHighScore(player) -- reads sessionSteps[player] itself; must run before resetScore clears it
	local newBest = bestOf(player)
	local isNewBest = steps > oldBest

	local bugs = bugsThisRun[player] or 0
	local flys = flysThisRun[player] or 0
	bugsThisRun[player] = 0
	flysThisRun[player] = 0

	resetScore(player)
	-- DEATH_CAUSE_LAVA on both: Effects.client.luau's fall-sound hook ignores the
	-- extra argument (unchanged), SfxEvents.client.luau's new `hurt` cue reads it.
	GameOver:FireClient(player, DEATH_CAUSE_LAVA)
	RunSummary:FireClient(player, score, newBest, isNewBest, qualitySnapshot, bugs, flys, DEATH_CAUSE_LAVA, steps)

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
		f.fallTween = nil
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
-- Gated on lane.tutorialGraceActive (Lane.luau), not lane.levelIndex ==
-- Levels.TUTORIAL: the level already flips to Pot on the 3rd tree climbed
-- (Lane.onStepClimbed), before the player has grabbed any real Pot step, so a
-- pure levelIndex check let a fall kill the frog in that gap
-- (b-20260922-101541-w1i2). tutorialGraceActive instead stays true across that
-- transition and only clears on the first successful grab of a non-tutorial-
-- tree step.
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
	setStreak(lane, 0) -- a fall breaks the combo
	local retreat = -math.min(Config.PULL_MAX_DISTANCE * Config.TUTORIAL_PULL_BACK, lane.netPull)
	if retreat < 0 then
		pullLane(lane, retreat, 0.6)
	end
	lane.folder:SetAttribute("TutorialRetries", ((lane.folder:GetAttribute("TutorialRetries") :: number?) or 0) + 1) -- WorldTutorialSpecks restarts at acorn 1
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

-- DOTween Ease.OutSine (PullMath.sineOut, the curve Lane's pulls share) from
-- `tw.from` to `tw.to`; second result is "finished".
local function bobTweenValue(tw: BobTween, now: number): (number, boolean)
	if tw.duration <= 0 then
		return tw.to, true
	end
	local a = (now - tw.started) / tw.duration
	return tw.from + (tw.to - tw.from) * PullMath.sineOut(a), a >= 1
end

-- DOPunchRotation(strength, 1 s, vibrato 1, elasticity 1): DOTween splits it
-- into 2 segments (Config.BOB_ROCK_OUT_FRACTION = 1/3 of the duration, then the
-- other 2/3): out to the punch, back to 0.
-- nil once it's over (the trailing DORotate(zero) is then a no-op).
local function rockAngle(r: { angle: number, started: number }, now: number): number?
	local t = (now - r.started) / Config.BOB_ROCK_TIME
	if t >= 1 then
		return nil
	end
	local out = Config.BOB_ROCK_OUT_FRACTION
	if t < out then
		local u = t / out
		return r.angle * (1 - (1 - u) * (1 - u))
	end
	local u = (t - out) / (1 - out)
	return r.angle * (1 - (1 - (1 - u) * (1 - u)))
end

-- Connected after the step Heartbeat above on purpose: the limb loop below
-- snaps a held hand to its step's CFrame, which that Heartbeat has just written.
RunService.Heartbeat:Connect(function(frameDt: number)
	local dt = math.min(frameDt, Config.MAX_TICK_DT) -- a hitch must not drop the frog a screen in one tick
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
		if f.dead then
			-- Frog.cs Fall(): keep sinking after death instead of freezing at
			-- LAVA_Y -- held still for DEATH_FALL_DELAY, then eased down to
			-- DEATH_FALL_Y, well below the camera, while the summary beat plays.
			local tw = f.fallTween
			if tw then
				local y, done = bobTweenValue(tw, os.clock())
				f.pos = Vector3.new(f.pos.X, y, Config.PLANE_Z)
				if done then
					f.fallTween = nil
				end
			end
		elseif runState[plr] == RunState.Playing and f.canFall then
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
				-- Space's low gravity (Lane.gravityScale): 1 on every other level
				local speed = math.min(Config.GRAVITY * f.gravityMult, Config.MAX_FALL_SPEED) * lane:gravityScale()
				y -= speed * dt
				if holding then
					y = math.max(y, Config.LAVA_Y) -- SteadilyLowerHead: `while HeadPosition.y > -50`
				end
			end
			f.pos = Vector3.new(x, y, Config.PLANE_Z)
			if not holding and f.pos.Y <= Config.LAVA_Y then
				if lane.tutorialGraceActive then
					tutorialRetry(lane, f)
				else
					killFrog(plr, f, lane)
				end
			end
		end

		-- Attract mode decision (FrogAI.cs Update): the demo hand hops up the ladder
		local a = attract[plr]
		if a and os.clock() >= a.pausedUntil and os.clock() - a.lastDecision >= WorldConfig.ATTRACT_DECISION_TIME then
			a.lastDecision = os.clock()
			attractClimb(a, f)
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
			local isHeld = false
			if step and step.Parent then
				isHeld = true
				-- Unity snaps the held hand to the step's transform.position
				-- (Player/Limb.cs Move), which a non-centre sprite pivot
				-- (Shared/StepKinds `gripOffset`) puts off the canvas centre.
				-- through the step's own rotation: a step keeps whatever spin
				-- tilt it had when it was grabbed (STEP_SPIN_*), and the offset
				-- is measured in the sprite's frame, not the world's.
				local grip = step:GetAttribute("GripOffset") :: Vector2?
				local gripPos = if grip then step.CFrame * Vector3.new(grip.X, grip.Y, 0) else step.Position
				-- X/Y follow the (scrolling) step; Z stays at the frog's own depth.
				-- A step's Z (the menu ladder rungs sit at -0.2) would otherwise drag
				-- the limb, and the arm part welded to it, behind the body art
				-- (-0.25) and head (-0.3).
				limbPart.CFrame = CFrame.new(gripPos.X, gripPos.Y, f.pos.Z)
			elseif reach and os.clock() - reach.started < Config.LIMB_REACH_TIME then
				-- DOTween's default ease (OutQuad), as Limb.Move uses
				local t = (os.clock() - reach.started) / Config.LIMB_REACH_TIME
				limbPart.CFrame = reach.from:Lerp(reach.to, 1 - (1 - t) * (1 - t))
			else
				local target = bodyCF * f.limbOffsets[i]
				-- Exponential, so the ease has the same shape at any frame rate
				-- (the old `dt / LIMB_RETURN_TIME` closed a different share of the
				-- gap per second at 30 Hz than at 60); same feel at 60 Hz.
				local alpha = PullMath.smoothAlpha(dt, Config.LIMB_RETURN_TIME)
				limbPart.CFrame = limbPart.CFrame:Lerp(target, alpha)
				-- the empty hand stays open (Reaching) until it's home again
				if reach and (limbPart.Position - target.Position).Magnitude < 0.5 then
					endReach(f, i)
				end
			end
			-- `Held` tells WorldFrogCosmetics which hand sprite to show. Not
			-- inferred client-side from limb position: a free limb easing back
			-- toward rest (above, the LIMB_RETURN_TIME lerp) legitimately lags
			-- behind a moving body and can sit far from its rest pose for a
			-- frame or two, which a distance check misreads as "holding"
			-- (b-20260922-081814-xqof). This is the one true source.
			if limbPart:GetAttribute("Held") ~= isHeld then
				limbPart:SetAttribute("Held", isHeld)
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
	local st = lane.states[step]
	if not st then
		return -- active steps always have one (Lane.trackStep); keeps the type checker honest
	end
	if runState[player] ~= RunState.Playing then
		return -- doc 15 item 1: no grabs outside an active run (Menu/Dead lanes are idle/empty anyway)
	end
	local f = frogs[player]
	if not f or f.dead then
		ForceRelease:FireClient(player, step)
		return
	end
	-- A step that is dropping away (ctx.dropAway: Fall, Vanish) has already
	-- shaken its holder off and is on its way to the recycle line; it stays
	-- active, and within reach, for the first part of the drop. It can't be
	-- caught again -- that would score a climb and aim a pull at a falling step.
	if st.dropElapsed then
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
	-- Measured to the grip point (a tall step's GripOffset), where the hand lands.
	local reachGrip = (step:GetAttribute("GripOffset") :: Vector2?) or Vector2.zero
	local reachPos = step.Position + CFrame.Angles(0, 0, st.angle) * Vector3.new(reachGrip.X, reachGrip.Y, 0)
	local reach = (Vector2.new(reachPos.X, reachPos.Y) - Vector2.new(lane.origin.X, lane.origin.Y)).Magnitude
	if reach > Config.MAX_GRAB_DISTANCE then
		ForceRelease:FireClient(player, step)
		return
	end
	-- grade quality server-side from the reported tap point (doc 07): garbage
	-- input can at worst claim "Perfect", which only flashes the HUD
	-- Unity measures from step.position, which for a carrot is its off-centre
	-- sprite pivot -- the very point the limb grips -- so grade from the grip
	-- point (canvas centre + GripOffset, rotated with the step), not the centre.
	local grip = (step:GetAttribute("GripOffset") :: Vector2?) or Vector2.zero
	local gripNow = step.Position + CFrame.Angles(0, 0, st.angle) * Vector3.new(grip.X, grip.Y, 0)
	local quality = if typeof(tapPos) == "Vector3" then PullMath.gradeGrab(tapPos, gripNow) else "OK"

	bob(f, lane, step) -- before the pull, so it reads the step's pre-pull X (Limb.CloseHand order)
	-- Pull the grabbed point (the carrot's GripOffset when it has one) to near
	-- the centre of the screen, measured where the step will REST once any pull
	-- still playing finishes (owner's ruling, b-20260921-164409-nkkh;
	-- PullMath.pullDistance). Unity reaches the same place with a per-frame force
	-- scaled by the step's distance from the target line (SpawnManager.PullVector).
	-- rotated with the step, as the limb-follow loop does, so a step grabbed
	-- mid-spin pulls its actual grip point to the target line. The rest point is
	-- the step's BASE (Lane.restPosition): recoil, sag or a patrol's sweep must
	-- not change how far the field scrolls.
	local gripRest = lane:restPosition(step) + CFrame.Angles(0, 0, st.angle) * Vector3.new(grip.X, grip.Y, 0)
	local distance =
		PullMath.pullDistance(Vector2.new(gripRest.X - lane.origin.X, gripRest.Y - lane.origin.Y), lane.spawnDirection)
	-- ...then a little further while any step would come to rest under the
	-- client's open Roblox PlayerList (owner's decision b-20260921-182502-qgbw,
	-- Lane.obstructionExtra; never shorter, not while the lane drifts).
	distance += lane:obstructionExtra(distance)
	-- Combo (b-20261010-192608-4bs3, both modes per bisk): a Perfect or Great
	-- grab grows the streak and restarts its timeout; an OK grab neither grows
	-- nor restarts it (kzbm). The streak speeds the moving field and grants the
	-- bonus score, but the grab pull keeps its normal duration. The Tutorial
	-- level never builds one, as before.
	local bonus = 0
	if lane.levelIndex ~= Levels.TUTORIAL then
		local weight = streakWeight(quality)
		if weight > 0 then
			setStreak(lane, streakOf(lane) + weight)
			streakGainAt[lane] = os.clock()
		end
		bonus = PullMath.streakBonus(streakOf(lane))
	end
	pullLane(lane, distance, PullMath.pullTime(distance))
	addScore(player, 1 + bonus, quality)

	local wasTutorial = lane.levelIndex == Levels.TUTORIAL
	local wasPot = lane.levelIndex == Levels.POT
	local kindName = step:GetAttribute("KindName") :: string?
	lane:onStepClimbed(kindName) -- level-threshold / tutorial progress; fires LevelChanged("soft") itself (doc 13 item 5)
	if wasTutorial and lane.levelIndex ~= Levels.TUTORIAL then
		-- Tutorial -> Pot: the tree ladder never respawns and Pot's spawners start
		-- cold at their off-screen staging point, so prefill Pot's first screenful
		-- the same way StartRun does (no-op if the lane somehow has steps already)
		prefillLane(lane)
	elseif wasPot and lane.levelIndex ~= Levels.POT then
		-- Pot -> Kitchen on the rim (Lane.spawnRim): nothing spawned above it, and
		-- this grab's pull spent its spawner window on the Pot, so give Kitchen's
		-- spawners that window along the same pull
		lane:spawnForPull(distance, spawnStep)
	end

	-- Player.cs TouchStep: the first grab of a (pullable) step arms falling --
	-- every step the port spawns is pullable, so any successful grab qualifies.
	f.canFall = true

	-- step behaviors (doc 05): track the holding limb, then dispatch onGrab
	endReach(f, limb)
	f.held[limb] = step
	st.spinRate = nil -- grabbed: the tumble stops here and never resumes for this step
	kickRecoil(lane, st) -- the step dips along the pull and springs back; the limb rides it
	local onGrab = st.behavior.onGrab
	if onGrab and lane.states[step] == st then
		onGrab(ctxOf(lane, step, st))
	end
	-- nothing left to grab after this one (hasFoothold): lay the direction-change
	-- scaffold from it, so the run can go on (b-20261020-220122-w9qy)
	if not lane:drifts() and not f.dead and lane.states[step] == st and not hasFoothold(lane, f) then
		scaffoldLane(lane, step)
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
	local st = lane.states[step]
	local onRelease = st and st.behavior.onRelease
	if st and onRelease then
		onRelease(ctxOf(lane, step, st))
	end
end)

-- The client's open Roblox PlayerList, as a lane-relative world rectangle
-- (owner's decision b-20260921-182502-qgbw, doc 17). The server can't see the
-- screen, so it trusts only the shape: four finite numbers, min < max, no bigger
-- than the lane's own view, clamped to it, and only ever stored on the sender's
-- own lane (the rectangle is lane-relative, so it can't name another lane). A
-- lie can at worst lengthen the sender's own pulls by OBSTRUCTION_MAX_EXTRA_PULL.
-- No arguments clears it. Updates faster than OBSTRUCTION_MIN_INTERVAL are
-- dropped (GameClient sends only on change, at most every PLAYERLIST_POLL s).
local lastObstruction: { [Player]: number } = {}

local function finite(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) < 1e6
end

ScreenObstruction.OnServerEvent:Connect(function(player, minX, minY, maxX, maxY)
	local now = os.clock()
	if now - (lastObstruction[player] or -math.huge) < Config.OBSTRUCTION_MIN_INTERVAL then
		return
	end
	lastObstruction[player] = now
	local lane = Lane.get(player)
	if not lane then
		return
	end
	if minX == nil and minY == nil and maxX == nil and maxY == nil then
		lane:setObstruction(nil)
		return
	end
	if not (finite(minX) and finite(minY) and finite(maxX) and finite(maxY)) then
		return
	end
	local x0, y0, x1, y1 = minX :: number, minY :: number, maxX :: number, maxY :: number
	local hw, hh = Config.LANE_HALF_WIDTH, Config.VIEW_HALF_HEIGHT
	if x0 >= x1 or y0 >= y1 or x1 - x0 > 2 * hw or y1 - y0 > 2 * hh then
		return
	end
	x0, x1 = math.clamp(x0, -hw, hw), math.clamp(x1, -hw, hw)
	y0, y1 = math.clamp(y0, -hh, hh), math.clamp(y1, -hh, hh)
	lane:setObstruction(if x1 > x0 and y1 > y0 then Rect.new(x0, y0, x1, y1) else nil)
end)

-- b-20260922-162231: MenuClient reports its end-of-run/gift panel's open/closed
-- state so attract mode can wait for it instead of just the Menu RunState flip
-- (the death-beat timer flips Dead -> Menu before the player dismisses that
-- panel). Boolean only; no validation needed beyond that.
SetEndPanelOpen.OnServerEvent:Connect(function(player, open)
	endPanelOpen[player] = open == true
	refreshAttract(player)
end)

-- A tap that hit no step or bug (Controller.CheckTouch's miss branch): the free
-- limb shoots out to the tap point (Limb.Move) and the Heartbeat eases it back.
-- Purely visual, so validation only keeps it sane: a live frog mid-run (or on
-- the start screen, pausing the attract climb), a free limb,
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
	if state ~= RunState.Playing and state ~= RunState.Menu then
		return
	end
	if f.held[limb] then
		return
	end
	if state == RunState.Playing then
		-- a tap that grabbed nothing (the client only sends this for a free limb
		-- and an empty tap point) breaks the combo (ruling 8zmn)
		local lane = Lane.get(player)
		if lane and streakOf(lane) > 0 then
			setStreak(lane, 0)
		end
	end
	if state == RunState.Menu then
		-- The player's click pauses the attract climb: that arm lets go of its
		-- demo rung to reach for the click (the other arm keeps its rung, the
		-- ladder stands still), and the climb resumes after ATTRACT_PAUSE_TIME.
		local a = attract[player]
		if a then
			a.held[limb] = nil
			a.pausedUntil = os.clock() + WorldConfig.ATTRACT_PAUSE_TIME
		end
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

-- Force this player's next run to start at the Tutorial level, whatever their
-- profile's tutorialDone already says (doc 15 item 3 / the Settings "Replay
-- Tutorial" action, b-20260921-182830-2c73: also reused by the menu's mode
-- picker so picking "Tutorial" there doesn't duplicate this). Only meaningful
-- from Menu -- callers gate that themselves.
local function forceTutorial(player: Player, lane: Lane.Lane)
	local p = Profiles.get(player)
	if not p then
		return
	end
	p.tutorialDone = false
	Profiles.save(player)
	lane:resetRun(false) -- back to Tutorial; fires LevelChanged for the client's level-name toast
end

-- The frog back at its lane's origin, alive and not yet armed (Player.cs canFall).
local function parkFrog(f: FrogState, origin: Vector3)
	f.pos = origin
	f.gravityMult = Config.GRAVITY_MULT_START
	cancelBob(f)
	f.dead = false
	f.canFall = false
	f.model:SetAttribute("Dead", false)
end

-- Start a run on a Menu lane in `mode` (Lane.setMode): park the frog, prefill the
-- lane and go Playing. StartRun, and the Studio-only skip below.
local function beginRun(player: Player, lane: Lane.Lane, f: FrogState, mode: string)
	parkFrog(f, lane.origin)
	flysThisRun[player] = 0
	bugsThisRun[player] = 0
	lane:setMode(mode)
	prefillLane(lane)
	setRunState(player, RunState.Playing)
end

-- doc 15 item 1: begin a run from the main menu. Only valid from Menu (a
-- client stuck mid-Playing or mid-death-beat can't re-trigger it), and
-- rate-limited the same way grabs are so a bot can't hammer it.
local START_RUN_COOLDOWN = 1.0
StartRun.OnServerEvent:Connect(function(player, mode)
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

	-- Run mode (doc 17 "Classic mode" / b-20260921-182325-3jtz, b-20260921-182830-2c73):
	-- Classic is the default -- only a literal "Normal" opts out. "Tutorial" is
	-- the menu's third pick (b-20260921-182830-2c73): it's not a scroll mode at
	-- all, it forces this run to (re)start at the Tutorial level the same way
	-- Settings' "Replay Tutorial" does, then plays out as an ordinary Classic
	-- run (Tutorial itself never drifts either way -- no CLASSIC_SCROLL_SPEED
	-- entry for it).
	local modeStr = if typeof(mode) == "string" then mode else Config.RUN_MODES.Classic
	if modeStr == "Tutorial" then
		forceTutorial(player, lane)
		modeStr = Config.RUN_MODES.Classic
	end
	beginRun(player, lane, f, modeStr)
end)

-- Reset Character / "respawn" (b-20261017-123801-td2q): the avatar is the frog,
-- so Roblox's Reset button has no character to act on. MenuClient routes it
-- here while Playing: bank the run like a death does, but skip the death beat
-- and end-of-run panel and return the lane/frog to the Menu state directly.
ReturnToMenu.OnServerEvent:Connect(function(player)
	if runState[player] ~= RunState.Playing then
		return
	end
	local lane = Lane.get(player)
	local f = frogs[player]
	if not lane or not f or f.dead then
		return
	end
	for i = 1, Config.MAX_HELD_STEPS do
		local step = f.held[i]
		if step then
			forceReleaseStep(lane, step)
		end
	end
	commitHighScore(player)
	flysThisRun[player] = 0
	bugsThisRun[player] = 0
	resetScore(player)
	clearLaneSteps(lane)
	local profile = Profiles.get(player)
	lane:resetRun(profile ~= nil and profile.tutorialDone == true)
	f.pos = lane.origin
	f.gravityMult = Config.GRAVITY_MULT_START
	cancelBob(f)
	f.fallTween = nil
	f.dead = false
	f.canFall = false
	f.model:SetAttribute("Dead", false)
	setRunState(player, RunState.Menu)
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
	local lane = Lane.get(player)
	if lane then
		forceTutorial(player, lane)
	end
end)

-- ---------------------------------------------------------------------------
-- Studio-only level skip (b-20261020-213324-txe8): lets a playtest jump a lane
-- to just before the end of a level instead of climbing there. A BindableFunction
-- in ServerStorage, so the MCP's execute_luau (which gets its own copies of
-- required modules, never this script's Lane registry) reaches the live lane:
--   game.ServerStorage.StudioSkipTo:Invoke("Kitchen", 3)  -- 3 grabs from Country
--   ...:Invoke(levelName, stepsBefore?, mode?, player?) -> summary string
-- levelName: Tutorial (stepsBefore = trees left) | Pot (steps before the rim is
-- laid; grab the rim to leave) | Kitchen | Country | Space (endless: lands at its
-- start). From Menu it starts a run in `mode` (default Normal); mid-run it keeps
-- the mode. The lane is emptied and refilled at the target level, the frog parked
-- unarmed at the origin, the score set to the steps that point implies (never
-- banked: skippedRun). Never created outside Studio.
-- ---------------------------------------------------------------------------
if RunService:IsStudio() then
	local T = Config.LEVEL_THRESHOLDS
	-- name -> level index, the run step the level begins at, and the run step
	-- its exit fires at (nil: Tutorial counts trees, Space never ends)
	local SKIP: { [string]: { index: number, start: number, exit: number? } } = {
		Tutorial = { index = Levels.TUTORIAL, start = 0 },
		Pot = { index = Levels.POT, start = 0, exit = T.Kitchen },
		Kitchen = { index = Levels.KITCHEN, start = T.Kitchen, exit = T.Country },
		Country = { index = Levels.COUNTRY, start = T.Country, exit = T.Space },
		Space = { index = Levels.SPACE, start = T.Space },
	}

	local function skipTo(levelName: any, stepsBefore: any, mode: any, who: any): string
		local target = if typeof(levelName) == "string" then SKIP[levelName] else nil
		if not target then
			return "unknown level " .. tostring(levelName) .. " (Tutorial|Pot|Kitchen|Country|Space)"
		end
		local player: Player? = if typeof(who) == "Instance" and who:IsA("Player") then who else Players:GetPlayers()[1]
		if not player then
			return "no player"
		end
		local lane = Lane.get(player)
		local f = frogs[player]
		local state = runState[player]
		if not lane or not f then
			return "player has no lane yet"
		end
		if state ~= RunState.Playing and state ~= RunState.Menu then
			return "run state is " .. tostring(state) .. "; retry once it is Menu"
		end
		local before = math.max(0, math.floor(if typeof(stepsBefore) == "number" then stepsBefore else 3))

		local runSteps, trees = target.start, 0
		if target.exit then
			runSteps = math.clamp(target.exit - before, target.start, target.exit)
		elseif target.index == Levels.TUTORIAL then
			trees = Config.TUTORIAL_STEPS - math.clamp(before, 1, Config.TUTORIAL_STEPS)
		end

		for i = 1, Config.MAX_HELD_STEPS do
			local step = f.held[i]
			if step then
				forceReleaseStep(lane, step)
			end
		end
		clearLaneSteps(lane)
		Chef.reset(lane)
		parkFrog(f, lane.origin)
		lane:skipTo(target.index, runSteps, target.start, trees)

		sessionScore[player] = runSteps
		sessionSteps[player] = runSteps
		skippedRun[player] = true
		player:SetAttribute("RunSteps", runSteps)
		pushScore(player)

		if state == RunState.Menu then
			beginRun(player, lane, f, if mode == Config.RUN_MODES.Classic then mode else Config.RUN_MODES.Normal)
		else
			setStreak(lane, 0)
			prefillLane(lane)
		end
		return ("%s: %s at runSteps %d (level from %d, exit %s), mode %s"):format(
			player.Name,
			lane.level.name,
			lane.runSteps,
			lane.levelStartSteps,
			if target.exit then tostring(target.exit) else "none",
			lane.mode
		)
	end

	local skipFn = ServerStorage:FindFirstChild("StudioSkipTo")
	if not skipFn then
		skipFn = Instance.new("BindableFunction")
		skipFn.Name = "StudioSkipTo"
		skipFn.Parent = ServerStorage
	end
	(skipFn :: BindableFunction).OnInvoke = skipTo

	-- Studio-only: place one step of a named kind in a player's lane, through
	-- acquireStep (so GripOffset / HitOffset / LaneUserId / Gen are set as for a
	-- natural spawn), with its grip point 5 studs above and 3 beside the lane
	-- origin: well inside MAX_GRAB_DISTANCE. Rare or level-bound kinds (Castle,
	-- Rocket) can then be grabbed on demand (b-20261020-235314-k0ex):
	--   game.ServerStorage.StudioSpawnKind:Invoke("Castle", player?)
	--     -> { name, kind, position, grip } (grip: world position of the grip point)
	local function spawnKind(kindName: any, who: any): any
		if typeof(kindName) ~= "string" or not StepKinds[kindName] then
			return "unknown step kind " .. tostring(kindName)
		end
		local player: Player? = if typeof(who) == "Instance" and who:IsA("Player") then who else Players:GetPlayers()[1]
		local lane = if player then Lane.get(player) else nil
		if not player or not lane then
			return "player has no lane yet"
		end
		local grip = StepKinds[kindName].gripOffset or Vector2.zero
		local want = lane.origin + Vector3.new(3, 5, 0)
		local step = acquireStep(lane, kindName, want - Vector3.new(grip.X, grip.Y, 0))
		local st = lane.states[step]
		local angle = if st then st.angle else 0
		local gripWorld = step.Position + CFrame.Angles(0, 0, angle) * Vector3.new(grip.X, grip.Y, 0)
		return { name = step.Name, kind = kindName, position = step.Position, grip = gripWorld }
	end

	local spawnFn = ServerStorage:FindFirstChild("StudioSpawnKind")
	if not spawnFn then
		spawnFn = Instance.new("BindableFunction")
		spawnFn.Name = "StudioSpawnKind"
		spawnFn.Parent = ServerStorage
	end
	(spawnFn :: BindableFunction).OnInvoke = spawnKind
end

-- Global top-scores boards (doc 15 item 5; daily/weekly per doc 17):
-- Profiles.topScores(10, period) + name resolution are both DataStore-ish
-- calls, so cache each board's assembled list for 60s rather than hitting
-- them on every panel open. A board's cache also drops when its UTC day/week
-- rolls over. Names are cached forever (a UserId's name essentially never
-- changes mid-session) and resolved in a pcall so one bad lookup can't fail
-- the whole board.
local TOP_SCORES_TTL = 60
type TopRow = { userId: number, score: number, name: string }
type TopCache = { list: { TopRow }, at: number, periodKey: number }
local topScoresCache: { [string]: TopCache } = {}
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

GetTopScores.OnServerInvoke = function(_player: Player, period: any)
	local board: Profiles.Period = if period == "daily" then "daily" elseif period == "weekly" then "weekly" else "all"
	local day, week = Profiles.periodKeys()
	local periodKey = if board == "daily" then day elseif board == "weekly" then week else 0
	local now = os.clock()
	local cached = topScoresCache[board]
	if not cached or cached.periodKey ~= periodKey or (now - cached.at) > TOP_SCORES_TTL then
		local raw = Profiles.topScores(10, board)
		local list: { TopRow } = {}
		for _, entry in raw do
			table.insert(list, { userId = entry.userId, score = entry.score, name = resolveName(entry.userId) })
		end
		local fresh: TopCache = { list = list, at = now, periodKey = periodKey }
		topScoresCache[board] = fresh
		return fresh.list
	end
	return cached.list
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
	sessionSteps[player] = 0
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
		lane:destroy() -- drops every StepState with the lane
	end
	sessionScore[player] = nil
	sessionSteps[player] = nil
	skippedRun[player] = nil
	grabQuality[player] = nil
	grabTimes[player] = nil
	lastObstruction[player] = nil
	endPanelOpen[player] = nil
	runState[player] = nil
	lastStartRun[player] = nil
	flysThisRun[player] = nil
	bugsThisRun[player] = nil
	lastMusicSave[player] = nil
end)
