--!strict
-- ServerScriptService/Server/BadgeService (Script)
-- Ports Core/VariableManager.cs's CheckForAchievement (Social.ReportProgress
-- "10!".."100!" every 10 steps up to 100) onto Roblox's BadgeService.
--
-- Divergence from Unity, by design (doc 16): Unity only runs this check when
-- SaveStats() is committing a NEW ALL-TIME HIGH SCORE (`if HighScore <
-- stepsClimbed`) -- i.e. the milestone has to beat every earlier run, not
-- just this one. Roblox badges are conventionally "did this at least once,
-- ever" one-time unlocks, and gating one behind "was THIS run better than
-- your all-time best" would make most players who've already climbed past a
-- threshold once unable to ever earn that badge on a lesser run again. This
-- service instead watches the live PER-RUN leaderstats.Score IntValue
-- (GameServer.server.luau's `sessionScore`, mirrored there on every grab) and
-- awards on the first-ever crossing of each threshold, in ANY run.
--
-- No DataStore here: BadgeService itself is the durable "has this badge"
-- store (UserHasBadgeAsync); everything this module tracks in memory is
-- purely to avoid redundant Open Cloud calls within one live session.
--
-- Deliberately never requires GameServer/Lane/Profiles -- it only ever reads
-- the player's own `leaderstats` Instance tree, the same pattern BugService
-- uses for `workspace.PlayField.Lanes` (doc 13 item 7), so load order between
-- this script and GameServer is moot.

local Players = game:GetService("Players")
local BadgeServiceApi = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Badges = require(ReplicatedStorage.Shared.Badges)

-- Sorted ascending once, so "which thresholds did this jump cross" is a
-- simple linear scan per score change.
local sorted: { Badges.BadgeEntry } = {}
for _, entry in Badges do
	table.insert(sorted, entry)
end
table.sort(sorted, function(a, b)
	return a.threshold < b.threshold
end)

-- player -> { [threshold]: true }, already awarded (or confirmed
-- already-owned) THIS SESSION -- purely to skip redundant
-- UserHasBadgeAsync/AwardBadge calls; actual badge ownership persists in
-- BadgeService regardless of what's cached here.
local sessionAwarded: { [Player]: { [number]: boolean } } = {}
local lastScore: { [Player]: number } = {}

local function tryAward(player: Player, threshold: number, badgeId: number)
	if badgeId == 0 then
		return -- FILL IN: not configured in Badges.luau yet -- silently skipped
	end

	local awarded = sessionAwarded[player]
	if not awarded then
		awarded = {}
		sessionAwarded[player] = awarded
	end
	if awarded[threshold] then
		return
	end
	awarded[threshold] = true -- set BEFORE the async call so a rapid re-trigger can't double-fire it

	task.spawn(function()
		local hasOk, hasBadge = pcall(function()
			return BadgeServiceApi:UserHasBadgeAsync(player.UserId, badgeId)
		end)
		if not hasOk then
			warn(
				("BadgeService: UserHasBadgeAsync failed for %s / badge %d: %s"):format(
					player.Name,
					badgeId,
					tostring(hasBadge)
				)
			)
			return
		end
		if hasBadge then
			return
		end

		local awardOk, err = pcall(function()
			BadgeServiceApi:AwardBadge(player.UserId, badgeId)
		end)
		if not awardOk then
			warn(("BadgeService: AwardBadge failed for %s / badge %d: %s"):format(player.Name, badgeId, tostring(err)))
		end
	end)
end

local function checkThresholds(player: Player, newScore: number)
	local previous = lastScore[player] or 0
	lastScore[player] = newScore
	if newScore <= previous then
		return -- a run reset (or any non-increase) never crosses a NEW threshold
	end
	for _, entry in sorted do
		if previous < entry.threshold and newScore >= entry.threshold then
			tryAward(player, entry.threshold, entry.id)
		end
	end
end

local function watchScore(player: Player, score: IntValue)
	checkThresholds(player, score.Value) -- catch up if it's already non-zero (script started late)
	score:GetPropertyChangedSignal("Value"):Connect(function()
		checkThresholds(player, score.Value)
	end)
end

local function watchLeaderstats(player: Player)
	-- GameServer.server.luau's `ensureLeaderstats` creates this; wait rather
	-- than require it, so load order between the two scripts is moot.
	local stats = player:WaitForChild("leaderstats", 30)
	if not stats then
		warn(("BadgeService: %s never got leaderstats (is GameServer running?)"):format(player.Name))
		return
	end
	local score = stats:WaitForChild("Score", 10)
	if not (score and score:IsA("IntValue")) then
		warn(("BadgeService: %s's leaderstats has no Score IntValue"):format(player.Name))
		return
	end
	watchScore(player, score)
end

Players.PlayerAdded:Connect(watchLeaderstats)
for _, player in Players:GetPlayers() do
	task.spawn(watchLeaderstats, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	sessionAwarded[player] = nil
	lastScore[player] = nil
end)
