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
local JarTiers = require(ReplicatedStorage.Shared.JarTiers)
local SkinTints = require(ReplicatedStorage.Shared.SkinTints)
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
local GetProfile = ensure("GetProfile", "RemoteFunction") :: RemoteFunction
local FeedJar = ensure("FeedJar", "RemoteFunction") :: RemoteFunction
local BuyTint = ensure("BuyTint", "RemoteFunction") :: RemoteFunction
local SelectTint = ensure("SelectTint", "RemoteEvent") :: RemoteEvent

local function push(player: Player)
	local p = Profiles.get(player)
	if p then
		ProfileChanged:FireClient(player, p)
	end
end

-- Pull-based counterpart to the push above: Profiles.Loaded's one-shot
-- ProfileChanged push can fire (right after the DataStore load) before a
-- client LocalScript has reached its OnClientEvent connection, and is lost
-- forever since FireClient never queues (same shape as GiftService's
-- GetGiftStatus fix for b-20260921-110937-uesm). Clients that need the
-- profile at startup should invoke this instead of only trusting the push.
GetProfile.OnServerInvoke = function(player: Player)
	return Profiles.get(player)
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

-- Skin colourways (b-20261008-142125-1ucz; doc 17): the tint worn on the
-- selected skin rides on the player as the replicated `FrogTint` attribute
-- (a SkinTints id, 0 = none); WorldFrogCosmetics tints that frog for everyone.
local function refreshFrogTint(player: Player)
	local p = Profiles.get(player)
	if not p then
		return
	end
	local tint = p.selectedTints[tostring(p.selected)] or 0
	local worn = SkinTints.get(tint)
	if
		tint ~= 0
		and not (worn and SkinTints.offeredOn(worn, p.selected) and p.ownedTints[SkinTints.key(p.selected, tint)])
	then
		tint = 0
	end
	player:SetAttribute("FrogTint", tint)
end

-- Retexture the live server-owned frog (GameServer names it Frog_<userId>) with
-- the selected skin's art, the worn tint's art swap (Blue), or its tint-ready
-- art under a colour tint; the new look replicates to every client.
local function reskinFrog(player: Player)
	local p = Profiles.get(player)
	local entry = p and Catalog[p.selected]
	local playField = workspace:FindFirstChild("PlayField")
	local frogsFolder = playField and playField:FindFirstChild("Frogs")
	local frogModel = frogsFolder and frogsFolder:FindFirstChild("Frog_" .. player.UserId)
	if p and entry and frogModel then
		local tintId = player:GetAttribute("FrogTint")
		SpriteSkin.apply(frogModel, SkinTints.artName(p.selected, tintId, entry.name))
	end
end

-- ---------------------------------------------------------------------------
-- Intents from the client (server validates everything)
-- ---------------------------------------------------------------------------
SelectSkin.OnServerEvent:Connect(function(player, id)
	local p = Profiles.get(player)
	if p and p.owned[id] and not (Catalog[id] and Catalog[id].hidden) then
		p.selected = id
		refreshFrogTint(player)
		push(player)
		reskinFrog(player)
	end
end)

-- Fly Jar (b-20261008-142124-qw4r; doc 17): Flys fed in are spent for good and
-- added to the lifetime profile.jarFlys, whose tier title (JarTiers) rides on
-- the player as the replicated `JarTitle` attribute for every client to show.
local function refreshJarTitle(player: Player)
	local p = Profiles.get(player)
	if p then
		player:SetAttribute("JarTitle", JarTiers.title(p.jarFlys))
	end
end

-- amount: a positive whole number of Flys, at most the current balance.
-- Returns true once fed (the new totals arrive via ProfileChanged).
FeedJar.OnServerInvoke = function(player, amount)
	local p = Profiles.get(player)
	if not p or type(amount) ~= "number" or amount ~= amount or amount < 1 or amount % 1 ~= 0 then
		return false
	end
	if amount > p.flys then
		return false
	end
	p.flys -= amount
	p.jarFlys += amount
	refreshJarTitle(player)
	push(player)
	Profiles.save(player)
	return true
end

-- (skinId, tintId): the skin must be owned and the tint real; costs the
-- tint's flyCost once per skin. Returns true when owned (already or now).
BuyTint.OnServerInvoke = function(player, skinId, tintId)
	local p, tint = Profiles.get(player), SkinTints.get(tintId)
	if not (p and tint and type(skinId) == "number" and p.owned[skinId] and SkinTints.offeredOn(tint, skinId)) then
		return false
	end
	local key = SkinTints.key(skinId, tint.id)
	if p.ownedTints[key] then
		return true
	end
	if p.flys < tint.flyCost then
		return false
	end
	p.flys -= tint.flyCost
	p.ownedTints[key] = true
	push(player)
	Profiles.save(player)
	return true
end

-- (skinId, tintId): wear an owned tint on an owned skin; tintId 0 clears it.
SelectTint.OnServerEvent:Connect(function(player, skinId, tintId)
	local p = Profiles.get(player)
	if not (p and type(skinId) == "number" and p.owned[skinId] and type(tintId) == "number") then
		return
	end
	if tintId ~= 0 then
		local tint = SkinTints.get(tintId)
		if not (tint and SkinTints.offeredOn(tint, skinId) and p.ownedTints[SkinTints.key(skinId, tintId)]) then
			return
		end
	end
	p.selectedTints[tostring(skinId)] = tintId
	refreshFrogTint(player)
	push(player)
	reskinFrog(player) -- Blue swaps the art; a colour tint wears the tint-ready art
end)

BuyWithFlys.OnServerInvoke = function(player, id)
	local p, entry = Profiles.get(player), Catalog[id]
	if not (p and entry and entry.flyCost) or entry.hidden then
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
	refreshJarTitle(player)
	refreshFrogTint(player)
	push(player)
end

Profiles.Loaded:Connect(initPlayer)
for _, player in Players:GetPlayers() do
	if Profiles.get(player) then
		initPlayer(player) -- profile already loaded before this connect
	end
end
