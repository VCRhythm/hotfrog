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
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)

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

-- ---------------------------------------------------------------------------
-- Step pool + spawning (shared field; one field for the basic version)
-- ---------------------------------------------------------------------------
local template = ReplicatedStorage.Assets.StepTemplate
local container = workspace.PlayField.Steps

local pool: { BasePart } = {}
local active: { [BasePart]: boolean } = {}

local function acquireStep(): BasePart
	local step = table.remove(pool) or template:Clone()
	step:SetAttribute("Kind", "Step")
	step.Anchored = true -- we move it ourselves (kinematic)
	SpriteSkin.apply(step) -- texture from its `Sprite` attribute (no-op until ids are set)
	step.Parent = container
	active[step] = true
	return step
end

local function releaseStep(step: BasePart)
	active[step] = nil
	step.Parent = nil
	table.insert(pool, step)
end

-- spawn loop
task.spawn(function()
	while true do
		local step = acquireStep()
		local x = math.random(-Config.SPAWN_X_RANGE, Config.SPAWN_X_RANGE)
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
-- Scoring + persistence (Core/VariableManager.cs)
-- ---------------------------------------------------------------------------
local highScores = DataStoreService:GetDataStore("HotfrogHighScores")
local sessionScore: { [Player]: number } = {}
local sessionBest: { [Player]: number } = {}

local function pushScore(player: Player, quality: string?)
	ScoreChanged:FireClient(player, sessionScore[player] or 0, sessionBest[player] or 0, quality)
end

local function addScore(player: Player, amount: number, quality: string?)
	sessionScore[player] = (sessionScore[player] or 0) + amount
	pushScore(player, quality)
end

local function commitHighScore(player: Player)
	local score = sessionScore[player] or 0
	if score > (sessionBest[player] or 0) then
		sessionBest[player] = score
		local key = "u_" .. player.UserId
		pcall(function()
			highScores:UpdateAsync(key, function(old)
				return math.max(old or 0, score)
			end)
		end)
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
end)

ReleaseStep.OnServerEvent:Connect(function(_player, _limbIndex)
	-- The basic loop has nothing authoritative to do on release; the hook exists
	-- so step behaviours (../05-step-behaviors.md) can react to release later.
end)

ReportDeath.OnServerEvent:Connect(function(player)
	commitHighScore(player)
	resetScore(player)
	GameOver:FireClient(player)
end)

-- ---------------------------------------------------------------------------
-- Player lifecycle
-- ---------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player: Player)
	local ok, best = pcall(function()
		return highScores:GetAsync("u_" .. player.UserId)
	end)
	sessionBest[player] = (ok and best) or 0
	sessionScore[player] = 0
	-- give the client a moment to load before the first HUD push
	task.defer(pushScore, player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	commitHighScore(player)
	sessionScore[player] = nil
	sessionBest[player] = nil
end)
