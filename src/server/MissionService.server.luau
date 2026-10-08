--!strict
-- ServerScriptService/Server/MissionService (Script)
-- Rotating daily missions (b-20261008-141702-e0za; not in Unity -- see doc 17).
-- Each UTC day (os.time() // 86400, same day index as DailyService) picks 3
-- missions from POOL with a Random seeded by the day, so every player and every
-- server gets the same set. Progress lives in the profile under that day, so a
-- new day starts from zero; finishing a mission pays its Flys straight away
-- through the one faucet (ServerStorage/AwardFlys -> SkinService) and fires
-- MissionCompleted for the client's toast.
--
-- Like BadgeService it never requires GameServer: it reads leaderstats.Score
-- (steps this run), the lane folder's RunState/Level attributes, and the
-- ServerStorage/BugCaughtServer bindable BugService fires per catch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Profiles = require(script.Parent.Profiles)

local SECONDS_PER_DAY = 86400
local PER_DAY = 3

-- stat: "score" = steps in one run (best of the day), "bugs" = bugs caught
-- today, "runs" = runs started today, "level" = reached `level` in a run.
type Mission = { id: string, text: string, stat: string, target: number, reward: number, level: string? }
local POOL: { Mission } = {
	{ id = "steps30", text = "Climb 30 steps in one run", stat = "score", target = 30, reward = 30 },
	{ id = "steps75", text = "Climb 75 steps in one run", stat = "score", target = 75, reward = 60 },
	{ id = "bugs5", text = "Catch 5 bugs", stat = "bugs", target = 5, reward = 30 },
	{ id = "bugs15", text = "Catch 15 bugs", stat = "bugs", target = 15, reward = 60 },
	{ id = "runs3", text = "Play 3 runs", stat = "runs", target = 3, reward = 25 },
	{ id = "runs8", text = "Play 8 runs", stat = "runs", target = 8, reward = 50 },
	{ id = "kitchen", text = "Reach the Kitchen", stat = "level", target = 1, reward = 40, level = "Kitchen" },
	{ id = "country", text = "Reach the Country", stat = "level", target = 1, reward = 75, level = "Country" },
}

local function getOrCreate(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

local remotes = getOrCreate(ReplicatedStorage, "Folder", "Remotes")
local GetMissions = getOrCreate(remotes, "RemoteFunction", "GetMissions") :: RemoteFunction
local MissionCompleted = getOrCreate(remotes, "RemoteEvent", "MissionCompleted") :: RemoteEvent
local awardFlys = getOrCreate(ServerStorage, "BindableEvent", "AwardFlys") :: BindableEvent
local bugCaughtServer = getOrCreate(ServerStorage, "BindableEvent", "BugCaughtServer") :: BindableEvent

local cachedDay = -1
-- UTC day each player's current run started; run-score missions only count a
-- run that started today, so a run straddling midnight can't carry
-- yesterday's steps into the new day's missions.
local runDay: { [Player]: number } = {}
local cachedMissions: { Mission } = {}

-- Today's day index and its 3 missions (same for everyone that day).
local function todays(): (number, { Mission })
	local day = os.time() // SECONDS_PER_DAY
	if day ~= cachedDay then
		local rng = Random.new(day)
		local indices = {}
		for i = 1, #POOL do
			indices[i] = i
		end
		cachedMissions = {}
		for i = 1, PER_DAY do
			local j = rng:NextInteger(i, #indices)
			indices[i], indices[j] = indices[j], indices[i]
			table.insert(cachedMissions, POOL[indices[i]])
		end
		cachedDay = day
	end
	return day, cachedMissions
end

-- Applies `value` to every one of today's missions on `stat`: "add" counts up,
-- otherwise it is a level name or a score that only ever raises progress.
local function report(player: Player, stat: string, value: any)
	local p = Profiles.get(player)
	if not p then
		return
	end
	local day, missions = todays()
	if p.missionDay ~= day then
		p.missionDay = day
		p.missions = {}
	end
	for _, m in missions do
		if m.stat ~= stat then
			continue
		end
		local before = p.missions[m.id] or 0
		if before >= m.target then
			continue
		end
		local after = before
		if stat == "bugs" or stat == "runs" then
			after = before + 1
		elseif stat == "score" then
			after = math.max(before, tonumber(value) or 0)
		elseif stat == "level" and value == m.level then
			after = 1
		end
		after = math.min(after, m.target)
		if after == before then
			continue
		end
		p.missions[m.id] = after
		if after >= m.target then
			awardFlys:Fire(player, m.reward) -- SkinService grants + replicates the Flys
			MissionCompleted:FireClient(player, m.text, m.reward)
			task.spawn(Profiles.save, player)
		end
	end
end

-- Returns nil until the profile has loaded (the client retries), else today's
-- missions as { text, progress, target, reward }.
GetMissions.OnServerInvoke = function(player: Player): any
	local p = Profiles.get(player)
	if not p then
		return nil
	end
	local day, missions = todays()
	local out = {}
	for _, m in missions do
		local progress = if p.missionDay == day then p.missions[m.id] or 0 else 0
		table.insert(out, { text = m.text, progress = progress, target = m.target, reward = m.reward })
	end
	return out
end

bugCaughtServer.Event:Connect(function(player: Player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		report(player, "bugs")
	end
end)

local function watchLeaderstats(player: Player)
	local stats = player:WaitForChild("leaderstats", 30)
	local score = stats and stats:WaitForChild("Score", 10)
	if not (score and score:IsA("IntValue")) then
		return
	end
	score:GetPropertyChangedSignal("Value"):Connect(function()
		if runDay[player] == os.time() // SECONDS_PER_DAY then
			report(player, "score", score.Value)
		end
	end)
end

local function watchLane(folder: Instance)
	local userId = tonumber(folder.Name)
	local player = if userId then Players:GetPlayerByUserId(userId) else nil
	if not player then
		return
	end
	folder:GetAttributeChangedSignal("RunState"):Connect(function()
		if folder:GetAttribute("RunState") == "Playing" then
			runDay[player] = os.time() // SECONDS_PER_DAY
			report(player, "runs")
		end
	end)
	folder:GetAttributeChangedSignal("Level"):Connect(function()
		report(player, "level", folder:GetAttribute("Level"))
	end)
end

Players.PlayerAdded:Connect(watchLeaderstats)
Players.PlayerRemoving:Connect(function(player: Player)
	runDay[player] = nil
end)
for _, player in Players:GetPlayers() do
	task.spawn(watchLeaderstats, player)
end

task.spawn(function()
	local playField = workspace:WaitForChild("PlayField", 60)
	local lanes = playField and playField:WaitForChild("Lanes", 60)
	if not lanes then
		warn("MissionService: workspace.PlayField.Lanes never appeared; run/level missions disabled")
		return
	end
	lanes.ChildAdded:Connect(watchLane)
	for _, folder in lanes:GetChildren() do
		task.spawn(watchLane, folder)
	end
end)
