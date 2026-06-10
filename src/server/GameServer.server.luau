--!strict
-- ServerScriptService/GameServer (Script)
-- Authoritative side of the Hotfrog loop:
--   * spawns & pools steps (Spawning/StepSpawner.cs + ObjectPool.cs)
--   * owns the pull / world-scroll (Spawning/SpawnManager.cs)
--   * owns every frog: position, gravity, limbs, death, respawn (Player/Frog.cs)
--   * tracks score and persists the high score (Core/VariableManager.cs)
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

local Config = require(ReplicatedStorage.Shared.Config)
local PullMath = require(ReplicatedStorage.Shared.PullMath)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local SkinCatalog = require(ReplicatedStorage.Shared.SkinCatalog)
local StepBehaviors = require(ReplicatedStorage.Shared.StepBehaviors)
local Profiles = require(script.Parent.Profiles)

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

local GrabStep = ensureRemote("GrabStep") -- client -> server: tapped a step (step, tap world point)
local ReleaseStep = ensureRemote("ReleaseStep") -- client -> server: released a limb
local ScoreChanged = ensureRemote("ScoreChanged") -- server -> client: score/best
local GameOver = ensureRemote("GameOver") -- server -> client: run ended, restart
local ForceRelease = ensureRemote("ForceRelease") -- server -> client: drop this step (Step.cs ForceRelease)

-- ---------------------------------------------------------------------------
-- Step pool + spawning (shared field; one field for the basic version).
-- Each spawn rolls a weighted behavior (Shared/StepBehaviors, doc 05) and bumps a
-- Gen attribute so delayed behavior effects can tell a recycled part apart.
-- ---------------------------------------------------------------------------
local template = ReplicatedStorage.Assets.StepTemplate
local container = workspace.PlayField.Steps

local pool: { BasePart } = {}
local active: { [BasePart]: boolean } = {}
local heldBy: { [BasePart]: Player } = {} -- who currently holds each step
local spawnBias = Vector2.new(0, -1) -- SpawnManager.SpawnDirection analog

-- Server-authoritative frog state (doc 07): the server owns position, gravity,
-- held steps, and death. The model lives in workspace, so replication renders it
-- on every client.
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

local function removeHeld(player: Player, step: BasePart)
	local f = frogs[player]
	if not f then
		return
	end
	for i = #f.held, 1, -1 do
		if f.held[i] == step then
			table.remove(f.held, i)
		end
	end
end

local function behaviorOf(step: BasePart): StepBehaviors.Behavior
	local name = step:GetAttribute("Behavior")
	return (typeof(name) == "string" and StepBehaviors[name]) or StepBehaviors.None
end

-- Knock the holder's limb off this step (Step.cs ForceRelease).
local function forceReleaseStep(step: BasePart)
	local holder = heldBy[step]
	if holder then
		heldBy[step] = nil
		removeHeld(holder, step)
		ForceRelease:FireClient(holder, step)
	end
end

-- forward-declared: releaseStep and makeCtx reference each other
local makeCtx: (step: BasePart, player: Player?) -> StepBehaviors.Ctx

local function releaseStep(step: BasePart)
	if not active[step] then
		return -- idempotent: behaviors and the lava check can both recycle
	end
	local b = behaviorOf(step)
	if b.onDestroy then
		b.onDestroy(makeCtx(step, heldBy[step]))
	end
	forceReleaseStep(step)
	active[step] = nil
	step.Parent = nil
	table.insert(pool, step)
end

makeCtx = function(step: BasePart, player: Player?): StepBehaviors.Ctx
	local gen = step:GetAttribute("Gen")
	local function stillValid(): boolean
		return active[step] == true and step:GetAttribute("Gen") == gen
	end
	return {
		step = step,
		player = player,
		stillValid = stillValid,
		makeUnsteady = function()
			step:SetAttribute("Unsteady", true) -- clients may shake/emit pebbles off this
		end,
		explode = function()
			forceReleaseStep(step)
			releaseStep(step) -- effects (pebbles/sound) are client polish, doc 05
		end,
		dropAway = function()
			forceReleaseStep(step)
			local info = TweenInfo.new(Config.DROP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(step, info, { CFrame = step.CFrame * CFrame.new(0, -Config.DROP_DISTANCE, 0) }):Play()
			-- the lava-line check below recycles it once it falls past DESPAWN_Y
		end,
		forceRelease = function()
			forceReleaseStep(step)
		end,
		getSpawnBias = function()
			return spawnBias
		end,
		setSpawnBias = function(bias: Vector2)
			spawnBias = bias
		end,
	}
end

-- Weighted behavior roll, gated by canSpawn (Step.cs canBeSpawned).
local behaviorWeights: { [string]: number } = Config.BEHAVIOR_WEIGHTS

local function rollBehavior(): string
	local total = 0
	for _, weight in behaviorWeights do
		total += weight
	end
	local r = math.random() * total
	for name, weight in behaviorWeights do
		r -= weight
		if r <= 0 then
			local b = StepBehaviors[name]
			if b and (not b.canSpawn or b.canSpawn(spawnBias)) then
				return name
			end
			return "None" -- gated out: fall back to a plain step
		end
	end
	return "None"
end

local function acquireStep(): BasePart
	local step = table.remove(pool) or template:Clone()
	step:SetAttribute("Kind", "Step")
	step:SetAttribute("Gen", ((step:GetAttribute("Gen") :: number?) or 0) + 1)
	step:SetAttribute("Unsteady", false)
	step:SetAttribute("Shrugged", false)
	step.Anchored = true -- we move it ourselves (kinematic)

	local name = rollBehavior()
	step:SetAttribute("Behavior", name)
	local sprite = StepBehaviors[name] and StepBehaviors[name].sprite
	if sprite then
		step:SetAttribute("Sprite", sprite) -- behavior-specific art (CrumblyRock, arrows, …)
	end
	SpriteSkin.apply(step) -- texture from its `Sprite` attribute (no-op until ids are set)

	step.Parent = container
	active[step] = true
	return step
end

-- spawn loop; spawn X follows the current bias (direction-change steps shift it)
task.spawn(function()
	while true do
		local step = acquireStep()
		local x
		if spawnBias.X > 0 then
			x = math.random(0, Config.SPAWN_X_RANGE)
		elseif spawnBias.X < 0 then
			x = math.random(-Config.SPAWN_X_RANGE, 0)
		else
			x = math.random(-Config.SPAWN_X_RANGE, Config.SPAWN_X_RANGE)
		end
		step.CFrame = CFrame.new(x, Config.SPAWN_Y, Config.PLANE_Z)
		task.wait(Config.SPAWN_INTERVAL)
	end
end)

-- recycle steps that drop past the lava line (analog of Step.OnTriggerEnter2D)
RunService.Heartbeat:Connect(function()
	for step in pairs(active) do
		if step.Position.Y < Config.DESPAWN_Y then
			releaseStep(step)
		end
	end
end)

-- ---------------------------------------------------------------------------
-- The pull / world-scroll: on a validated grab, slide the whole field down.
-- (SpawnManager applies PullVector to every active spawn; here it's one tween
-- per step per grab -- discrete but reads the same.)
-- ---------------------------------------------------------------------------
local function scrollFieldDown(distance: number, duration: number)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine)
	for step in pairs(active) do
		TweenService:Create(step, info, { CFrame = step.CFrame * CFrame.new(0, -distance, 0) }):Play()
	end
end

-- ---------------------------------------------------------------------------
-- Scoring (Core/VariableManager.cs). The high score lives on the shared Profile
-- (Profiles); sessionScore is the current run, banked into profile.highScore on
-- death. No DataStore here -- Profiles owns persistence.
-- ---------------------------------------------------------------------------
local sessionScore: { [Player]: number } = {}

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
	ScoreChanged:FireClient(player, sessionScore[player] or 0, bestOf(player), quality)
end

local function addScore(player: Player, amount: number, quality: string?)
	sessionScore[player] = (sessionScore[player] or 0) + amount
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
	pushScore(player)
end

-- ---------------------------------------------------------------------------
-- Frogs (Player/Frog.cs, server-authoritative). One model per player, named
-- Frog_<userId>, skinned from the profile so the look replicates to everyone.
-- ---------------------------------------------------------------------------
local frogContainer = workspace.PlayField:FindFirstChild("Frogs")
if not frogContainer then
	frogContainer = Instance.new("Folder")
	frogContainer.Name = "Frogs"
	frogContainer.Parent = workspace.PlayField
end

local frogTemplate = ReplicatedStorage.Assets.FrogModel
local FROG_START = Vector3.new(0, 0, Config.PLANE_Z)

local function createFrog(player: Player)
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
		pos = FROG_START,
		gravityMult = Config.GRAVITY_MULT_START,
		dead = false,
		held = {},
	}
	body.CFrame = CFrame.new(FROG_START)
	frogs[player] = state
	model.Parent = frogContainer
end

local function killFrog(player: Player, f: FrogState)
	f.dead = true
	f.model:SetAttribute("Dead", true)
	-- drop anything still held (e.g. a step dragged under the lava line with us)
	for i = #f.held, 1, -1 do
		forceReleaseStep(f.held[i])
	end
	commitHighScore(player)
	resetScore(player)
	GameOver:FireClient(player)
	task.delay(Config.RESPAWN_DELAY, function()
		if frogs[player] ~= f then
			return -- player left (or was rebuilt) during the death beat
		end
		f.pos = FROG_START
		f.gravityMult = Config.GRAVITY_MULT_START
		f.dead = false
		f.model:SetAttribute("Dead", false)
	end)
end

-- The fall loop (Frog.cs SteadilyLowerHead) + lava check (Lava.cs) + rendering:
-- limbs snap to their held step or ease back to rest, exactly as the client
-- used to do locally.
RunService.Heartbeat:Connect(function(dt: number)
	for plr, f in pairs(frogs) do
		if not f.dead then
			if #f.held == 0 then
				f.gravityMult += Config.GRAVITY_ACCEL * dt
				local speed = math.min(Config.GRAVITY * f.gravityMult, Config.MAX_FALL_SPEED)
				f.pos = Vector3.new(f.pos.X, f.pos.Y - speed * dt, Config.PLANE_Z)
			end
			if f.pos.Y <= Config.DESPAWN_Y then
				killFrog(plr, f)
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
	-- validate: a real, still-active step, from a live frog with a limb to spare
	if typeof(step) ~= "Instance" or not step:IsA("BasePart") or not active[step] then
		return
	end
	local f = frogs[player]
	if not f or f.dead or #f.held >= Config.MAX_HELD_STEPS then
		ForceRelease:FireClient(player, step)
		return
	end
	-- reject a step someone already holds, or grabs faster than humanly possible;
	-- ForceRelease corrects the client that optimistically snapped a limb on
	if heldBy[step] or not grabAllowed(player) then
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
	scrollFieldDown(Config.PULL_DISTANCE, Config.PULL_TIME)
	addScore(player, 1, quality)

	-- step behaviors (doc 05): track the holder, then dispatch onGrab
	heldBy[step] = player
	table.insert(f.held, step)
	local b = behaviorOf(step)
	if b.onGrab then
		b.onGrab(makeCtx(step, player))
	end
end)

ReleaseStep.OnServerEvent:Connect(function(player, _limbIndex, step)
	-- only the recorded holder may release; ForceRelease already cleared heldBy,
	-- so the client's echo after a forced drop lands here as a no-op
	if typeof(step) ~= "Instance" or not step:IsA("BasePart") then
		return
	end
	if heldBy[step] ~= player then
		return
	end
	heldBy[step] = nil
	removeHeld(player, step)
	local b = behaviorOf(step)
	if b.onRelease and active[step] then
		b.onRelease(makeCtx(step, player))
	end
end)

-- ---------------------------------------------------------------------------
-- Player lifecycle. Profiles owns persistence; once a profile is ready we set
-- up the run state, the leaderstats board, and the server-owned frog. Death is
-- decided entirely by the server's lava check in the frog Heartbeat (no
-- ReportDeath remote -- the client has no say in when it died).
-- ---------------------------------------------------------------------------
local function initPlayer(player: Player)
	ensureLeaderstats(player)
	sessionScore[player] = 0
	createFrog(player)
	pushScore(player)
end

Profiles.Loaded:Connect(initPlayer)
for _, player in Players:GetPlayers() do
	if Profiles.get(player) then
		initPlayer(player)
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	local f = frogs[player]
	if f then
		for i = #f.held, 1, -1 do
			local step = f.held[i]
			heldBy[step] = nil -- no ForceRelease: the holder is leaving
			table.remove(f.held, i)
		end
		frogs[player] = nil
		f.model:Destroy()
	end
	sessionScore[player] = nil
	grabTimes[player] = nil
end)
