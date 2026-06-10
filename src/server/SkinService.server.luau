-- ServerScriptService/Server/SkinService (Script)
-- Server-authoritative skins (../../docs/roblox-port/08-frog-skins-and-store.md):
--   * ownership, Fly soft currency, and selection — stored on the shared Profile
--     (replaces UI/FrogPackages.cs + PlayerPrefs "FrogPackages")
--   * monetization: Game Passes for premium skins (Store/StoreAssets LifetimeVG)
--     and Developer Products for Fly packs (the "1000 Flys" consumable)
-- Persistence lives in Profiles; this script owns the skin/currency *rules* and
-- the client-facing remotes. The client only sends intents.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local Catalog = require(ReplicatedStorage.Shared.SkinCatalog)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local Profiles = require(script.Parent.Profiles)

-- Developer Product id -> Flys granted. FILL IN real product ids.
local FLY_PRODUCTS: { [number]: number } = {
	-- [123456] = 1000,
}

-- ---------------------------------------------------------------------------
-- Remotes (shared "Remotes" folder; create it if another service hasn't yet)
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

local SelectSkin = ensure("SelectSkin", "RemoteEvent") :: RemoteEvent
local BuyWithFlys = ensure("BuyWithFlys", "RemoteFunction") :: RemoteFunction
local ProfileChanged = ensure("ProfileChanged", "RemoteEvent") :: RemoteEvent

local function push(player: Player)
	local p = Profiles.get(player)
	if p then
		ProfileChanged:FireClient(player, p)
	end
end

-- ---------------------------------------------------------------------------
-- Flys faucet: a server-only BindableEvent in ServerStorage so other server
-- scripts (bug catch ../06, gift/ad faucets ../09) award through one path:
--   game.ServerStorage.AwardFlys:Fire(player, amount)
-- ---------------------------------------------------------------------------
local awardFlysBindable = ServerStorage:FindFirstChild("AwardFlys") :: BindableEvent?
if not awardFlysBindable then
	awardFlysBindable = Instance.new("BindableEvent")
	awardFlysBindable.Name = "AwardFlys"
	awardFlysBindable.Parent = ServerStorage
end
awardFlysBindable.Event:Connect(function(player: Player, amount: number)
	local p = Profiles.get(player)
	if p then
		p.flys += amount
		push(player)
	end
end)

local function grantGamePassSkins(player: Player)
	local p = Profiles.get(player)
	if not p then
		return
	end
	for id, entry in pairs(Catalog) do
		if entry.gamePassId and entry.gamePassId > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, entry.gamePassId)
			end)
			if ok and owns then
				p.owned[id] = true
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Intents from the client (server validates everything)
-- ---------------------------------------------------------------------------
SelectSkin.OnServerEvent:Connect(function(player, id)
	local p = Profiles.get(player)
	if p and p.owned[id] then
		p.selected = id
		push(player)
		-- retexture the live server-owned frog (GameServer names it Frog_<userId>);
		-- the new look replicates to every client
		local entry = Catalog[id]
		local playField = workspace:FindFirstChild("PlayField")
		local frogsFolder = playField and playField:FindFirstChild("Frogs")
		local frogModel = frogsFolder and frogsFolder:FindFirstChild("Frog_" .. player.UserId)
		if entry and frogModel then
			SpriteSkin.apply(frogModel, entry.name)
		end
	end
end)

BuyWithFlys.OnServerInvoke = function(player, id)
	local p, entry = Profiles.get(player), Catalog[id]
	if not (p and entry and entry.flyCost) then
		return false
	end
	if p.owned[id] then
		return true
	end
	if p.flys < entry.flyCost then
		return false
	end
	p.flys -= entry.flyCost
	p.owned[id] = true
	push(player)
	Profiles.save(player)
	return true
end

-- ---------------------------------------------------------------------------
-- Monetization
-- ---------------------------------------------------------------------------
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then
		return
	end
	local p = Profiles.get(player)
	if not p then
		return
	end
	for id, entry in pairs(Catalog) do
		if entry.gamePassId == passId then
			p.owned[id] = true
			push(player)
			Profiles.save(player)
		end
	end
end)

-- Consumables (Fly packs). ProcessReceipt may fire more than once -> idempotent.
MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local p = player and Profiles.get(player)
	if not (player and p) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retry when they're back
	end
	local grant = FLY_PRODUCTS[receipt.ProductId]
	if not grant then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not p.applied[receipt.PurchaseId] then
		p.applied[receipt.PurchaseId] = true
		p.flys += grant
		push(player)
		Profiles.save(player) -- persist before acknowledging
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ---------------------------------------------------------------------------
-- Per-player init: grant Game Pass skins + send the initial profile
-- ---------------------------------------------------------------------------
local function initPlayer(player: Player)
	grantGamePassSkins(player)
	push(player)
end

Profiles.Loaded:Connect(initPlayer)
for _, player in Players:GetPlayers() do
	if Profiles.get(player) then
		initPlayer(player) -- profile already loaded before this connect
	end
end
