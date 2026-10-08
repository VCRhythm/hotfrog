--!strict
-- ServerScriptService/Server/DailyService (Script)
-- Daily login streak (b-20261008-124506-lo4a; not in Unity -- see doc 17).
-- One claim per UTC calendar day; claiming the day after the last claim
-- extends the streak, any gap resets it to day 1. The reward escalates over a
-- 7-day cycle and then repeats (the streak count itself keeps growing).
--
-- The client asks (`ClaimDailyReward`) whenever it shows the main menu; the
-- server decides everything from os.time() and the profile, so asking twice
-- in a day just returns the current streak with granted = false. A pull
-- rather than a push on Profiles.Loaded, for the same load-order reason as
-- GiftService's GetGiftStatus (b-20260921-110937-uesm). Flys go through the
-- one faucet (ServerStorage/AwardFlys -> SkinService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Profiles = require(script.Parent.Profiles)

local SECONDS_PER_DAY = 86400
-- Flys for streak day 1..7; day 8 pays REWARDS[1] again, and so on.
local REWARDS = { 25, 50, 75, 100, 150, 200, 500 }

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end
local claimRemote = remotes:FindFirstChild("ClaimDailyReward")
if not claimRemote then
	claimRemote = Instance.new("RemoteFunction")
	claimRemote.Name = "ClaimDailyReward"
	claimRemote.Parent = remotes
end
local ClaimDailyReward = claimRemote :: RemoteFunction

-- Single Fly faucet (created by SkinService; get-or-create so load order is moot)
local awardFlysInstance = ServerStorage:FindFirstChild("AwardFlys")
if not awardFlysInstance then
	awardFlysInstance = Instance.new("BindableEvent")
	awardFlysInstance.Name = "AwardFlys"
	awardFlysInstance.Parent = ServerStorage
end
local awardFlys = awardFlysInstance :: BindableEvent

local function rewardFor(streak: number): number
	return REWARDS[(math.max(streak, 1) - 1) % #REWARDS + 1]
end

-- Returns nil until the profile has loaded (the client retries), else
-- { granted, streak, reward, rewards }: `reward` is what was just paid (0 when
-- already claimed today), `rewards` the cycle table for the menu's day row.
ClaimDailyReward.OnServerInvoke = function(player: Player): any
	local p = Profiles.get(player)
	if not p then
		return nil
	end
	local today = os.time() // SECONDS_PER_DAY
	if p.streakDay == today then
		return { granted = false, streak = p.streak, reward = 0, rewards = REWARDS }
	end
	-- Update the claim day before anything yields, so a second invoke in
	-- flight can't pay the same day twice.
	p.streak = if p.streakDay == today - 1 then p.streak + 1 else 1
	p.streakDay = today
	local reward = rewardFor(p.streak)
	awardFlys:Fire(player, reward) -- SkinService grants + replicates the Flys
	task.spawn(Profiles.save, player)
	return { granted = true, streak = p.streak, reward = reward, rewards = REWARDS }
end
