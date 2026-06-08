-- ServerScriptService/SkinService (Script)
-- Server-authoritative skins (../08-frog-skins-and-store.md):
--   * ownership, Fly soft currency, and selection, persisted per player
--     (replaces UI/FrogPackages.cs + PlayerPrefs "FrogPackages")
--   * monetization: Game Passes for premium skins (Store/StoreAssets LifetimeVG)
--     and Developer Products for Fly packs (the "1000 Flys" consumable)
-- Ownership/currency live only on the server; the client just sends intents.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Catalog = require(ReplicatedStorage.Shared.SkinCatalog)

local store = DataStoreService:GetDataStore("HotfrogProfiles")
local profiles = {} -- [Player] = { owned = {[id]=true}, selected = id, flys = n, applied = {} }

-- Developer Product id -> Flys granted. FILL IN real product ids.
local FLY_PRODUCTS = {
	-- [123456] = 1000,
}

-- ---------------------------------------------------------------------------
-- Remotes (shared "Remotes" folder; create it if GameServer hasn't yet)
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

-- ---------------------------------------------------------------------------
-- Profile helpers
-- ---------------------------------------------------------------------------
local function defaultProfile()
	local owned = {}
	for id, entry in pairs(Catalog) do
		if entry.default then
			owned[id] = true
		end
	end
	return { owned = owned, selected = 1, flys = 0, applied = {} }
end

local function push(player: Player)
	ProfileChanged:FireClient(player, profiles[player])
end

local function save(player: Player)
	local p = profiles[player]
	if p then
		pcall(function()
			store:SetAsync("u_" .. player.UserId, p)
		end)
	end
end

-- Other server scripts (the bug-catch handler in ../06, the gift/ad faucets in
-- ../09) award Flys through this one path. It's published as a server-only
-- BindableEvent in ServerStorage so those scripts can do:
--   game.ServerStorage.AwardFlys:Fire(player, amount)
-- (ServerStorage, not ReplicatedStorage, so clients can't fire it.)
local function awardFlys(player: Player, amount: number)
	local p = profiles[player]
	if p then
		p.flys += amount
		push(player)
	end
end

local ServerStorage = game:GetService("ServerStorage")
local awardFlysBindable = ServerStorage:FindFirstChild("AwardFlys") :: BindableEvent?
if not awardFlysBindable then
	awardFlysBindable = Instance.new("BindableEvent")
	awardFlysBindable.Name = "AwardFlys"
	awardFlysBindable.Parent = ServerStorage
end
awardFlysBindable.Event:Connect(awardFlys)

local function grantGamePassSkins(player: Player)
	local p = profiles[player]
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
	local p = profiles[player]
	if p and p.owned[id] then
		p.selected = id
		push(player)
	end
end)

BuyWithFlys.OnServerInvoke = function(player, id)
	local p, entry = profiles[player], Catalog[id]
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
	save(player)
	return true
end

-- ---------------------------------------------------------------------------
-- Monetization
-- ---------------------------------------------------------------------------
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then
		return
	end
	local p = profiles[player]
	if not p then
		return
	end
	for id, entry in pairs(Catalog) do
		if entry.gamePassId == passId then
			p.owned[id] = true
			push(player)
			save(player)
		end
	end
end)

-- Consumables (Fly packs). ProcessReceipt may fire more than once -> idempotent.
MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player or not profiles[player] then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retry when they're back
	end
	local grant = FLY_PRODUCTS[receipt.ProductId]
	if not grant then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local p = profiles[player]
	if not p.applied[receipt.PurchaseId] then
		p.applied[receipt.PurchaseId] = true
		p.flys += grant
		push(player)
		save(player) -- persist before acknowledging
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	local ok, saved = pcall(function()
		return store:GetAsync("u_" .. player.UserId)
	end)
	local profile = (ok and saved) or defaultProfile()
	profile.owned = profile.owned or {}
	profile.applied = profile.applied or {}
	-- reconcile any newly-added default skins (mirrors FrogPackages.LoadPackages)
	for id, entry in pairs(Catalog) do
		if entry.default then
			profile.owned[id] = true
		end
	end
	profiles[player] = profile
	grantGamePassSkins(player)
	task.defer(push, player)
end)

Players.PlayerRemoving:Connect(function(player)
	save(player)
	profiles[player] = nil
end)
