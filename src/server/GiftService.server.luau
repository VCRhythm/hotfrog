-- ServerScriptService/Server/GiftService (Script)
-- Free Fly faucet on an escalating cooldown (../../docs/roblox-port/09-gifts-and-ads.md;
-- ports UI/GiftManager.cs). Timing is server-authoritative via os.time(); the
-- client only renders a countdown and asks to claim. Gift state (giftSeed,
-- lastGift) lives on the shared Profile; Flys are granted through the one faucet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local Profiles = require(script.Parent.Profiles)

local GIFT_FLYS = 100 -- Flys granted per gift (the SpawnGiftFlys amount)
local SEED_MAX = 21
local MIN_WAIT, MAX_WAIT = 120, 21600 -- 2 min .. 6 h (GetGiftTime clamp)

-- ---------------------------------------------------------------------------
-- Remotes
-- ---------------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local function ensure(name: string, className: string): Instance
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = remotes
	end
	return r
end

local ClaimGift = ensure("ClaimGift", "RemoteFunction") :: RemoteFunction
local GiftStatus = ensure("GiftStatus", "RemoteEvent") :: RemoteEvent

-- Single Fly faucet (created by SkinService; get-or-create so load order is moot)
local awardFlys = ServerStorage:FindFirstChild("AwardFlys") :: BindableEvent?
if not awardFlys then
	awardFlys = Instance.new("BindableEvent")
	awardFlys.Name = "AwardFlys"
	awardFlys.Parent = ServerStorage
end

-- ---------------------------------------------------------------------------
-- Timing (ports GetGiftTime / CanShowGift / IncreaseGiftSeed)
-- ---------------------------------------------------------------------------
local function giftTime(seed: number): number
	return math.clamp(math.round(math.exp(seed)), MIN_WAIT, MAX_WAIT)
end

local function nextGiftAt(p): number
	return p.lastGift + giftTime(p.giftSeed)
end

local function pushStatus(player: Player)
	local p = Profiles.get(player)
	if p then
		GiftStatus:FireClient(player, nextGiftAt(p), os.time()) -- client derives countdown
	end
end

ClaimGift.OnServerInvoke = function(player)
	local p = Profiles.get(player)
	if not p then
		return false
	end
	if os.time() < nextGiftAt(p) then
		return false -- not ready; the server clock is the source of truth
	end
	awardFlys:Fire(player, GIFT_FLYS) -- SkinService grants + replicates the Flys
	p.lastGift = os.time()
	p.giftSeed = math.min(p.giftSeed + 1, SEED_MAX) -- next gift takes longer
	Profiles.save(player)
	pushStatus(player)
	return true
end

-- ---------------------------------------------------------------------------
-- Send the initial countdown when each profile is ready
-- ---------------------------------------------------------------------------
Profiles.Loaded:Connect(pushStatus)
for _, player in Players:GetPlayers() do
	if Profiles.get(player) then
		pushStatus(player)
	end
end
