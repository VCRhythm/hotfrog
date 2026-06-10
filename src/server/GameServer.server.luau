--!strict
-- ServerScriptService/GameServer (Script)
-- Authoritative side of the basic Hotfrog loop:
--   * spawns & pools steps (Spawning/StepSpawner.cs + ObjectPool.cs)
--   * owns the pull / world-scroll (Spawning/SpawnManager.cs)
--   * tracks score and persists the high score (Core/VariableManager.cs)
--
-- The frog itself is client-driven for responsiveness; the client reports grabs
-- (GrabStep) and its own death (ReportDeath). That client trust is the pragmatic
-- MVP choice -- see ../07-multiplayer.md for hardening.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
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

local GrabStep = ensureRemote("GrabStep") -- client -> server: grabbed a step
local ReleaseStep = ensureRemote("ReleaseStep") -- client -> server: released a limb
local ReportDeath = ensureRemote("ReportDeath") -- client -> server: frog hit lava
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

local function behaviorOf(step: BasePart): StepBehaviors.Behavior
	local name = step:GetAttribute("Behavior")
	return (typeof(name) == "string" and StepBehaviors[name]) or StepBehaviors.None
end

-- Knock the holder's limb off this step (Step.cs ForceRelease).
local function forceReleaseStep(step: BasePart)
	local holder = heldBy[step]
	if holder then
		heldBy[step] = nil
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
-- Remote handlers
-- ---------------------------------------------------------------------------
GrabStep.OnServerEvent:Connect(function(player, step, quality, frogPos)
	-- validate: a real, still-active step
	if typeof(step) ~= "Instance" or not step:IsA("BasePart") or not active[step] then
		return
	end
	-- basic reach sanity check (don't trust arbitrary grabs)
	if typeof(frogPos) == "Vector3" then
		local d2 = (Vector2.new(step.Position.X, step.Position.Y) - Vector2.new(frogPos.X, frogPos.Y)).Magnitude
		if d2 > Config.MAX_GRAB_DISTANCE then
			return
		end
	end
	if typeof(quality) ~= "string" then
		quality = "OK"
	end

	scrollFieldDown(Config.PULL_DISTANCE, Config.PULL_TIME)
	addScore(player, 1, quality)

	-- step behaviors (doc 05): track the holder, then dispatch onGrab
	heldBy[step] = player
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
	local b = behaviorOf(step)
	if b.onRelease and active[step] then
		b.onRelease(makeCtx(step, player))
	end
end)

ReportDeath.OnServerEvent:Connect(function(player)
	commitHighScore(player)
	resetScore(player)
	GameOver:FireClient(player)
end)

-- ---------------------------------------------------------------------------
-- Player lifecycle (scoring side). Profiles owns persistence; here we reset the
-- run and push the initial HUD once the profile is ready. The high score is
-- banked on death (commitHighScore in ReportDeath), not on leave.
-- ---------------------------------------------------------------------------
local function initScore(player: Player)
	ensureLeaderstats(player)
	sessionScore[player] = 0
	pushScore(player)
end

Profiles.Loaded:Connect(initScore)
for _, player in Players:GetPlayers() do
	if Profiles.get(player) then
		initScore(player)
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	sessionScore[player] = nil
end)
