# 08 — Frog Skins & Store

> Extension on top of the basic loop. Builds on the persistence pattern in
> [03-core-mechanics.md](03-core-mechanics.md#scoring--hud), the currency angle of
> [06-bugs-and-tongue.md](06-bugs-and-tongue.md), and the server-authority rules in
> [07-multiplayer.md](07-multiplayer.md).

Hotfrog ships ~20 collectible frog skins. Some start unlocked, some are bought.
The original wires this through three systems:

- `Player/Frog.cs` — each frog prefab carries its identity and look: `id` (1–20),
  `frogName`, `isUnlocked` (0/1), `canBuy` (0/1), an `audioIntroduction`, and a
  list of `SpriteLoad`s that swap in that frog's sprites.
- `UI/FrogPackages.cs` — the catalog + ownership manager. It keeps a list of
  `Vector3i(id, isOpen, canBuy)` "packages," persists them to `PlayerPrefs` under
  `"FrogPackages"`, cycles through frogs (`NextFrog`/`PrevFrog` → `CycleFrog`),
  unlocks them (`OpenPackage`/`BuyFrog`), and selects the active one
  (`variableManager.currentFrogID`). `MakeFrog(id)` instantiates the chosen frog
  prefab and hands it to the `Controller` (`SetFrog`).
- `Store/PurchaseManager.cs` + `Store/StoreAssets.cs` — real-money IAP via the
  Soomla plugin. Each premium frog is a `LifetimeVG` (one-time unlock) with a
  product id like `"4_business_frog"` (the leading number is the frog `id`, parsed
  by `GetID`). There's also a soft currency, **Fly** (`FLY_CURRENCY`), and a
  consumable `"1000 Flys"` pack bought with money.

So there are two unlock paths: **pay real money** (premium frogs) or **earn/spend
Flys** (the soft-currency path, fed by caught bugs and gifts).

## Source art (in the repo)

The original frog art lives in [`/Sprites/Frogs/`](../../Sprites/Frogs) — one
folder per skin, named to match the `SkinCatalog` `name` field:

`Hot Frog`, `Blue Frog`, `Hawt Frog`, `Space Frog`, `Mystery Frog`,
`Business Frog`, `Hot Lawyer`, `Invisible Man`, `Crossy Frog`, plus a shared
[`Universal/`](../../Sprites/Frogs/Universal) set (pupils, sclera, tongue).

Each skin folder holds the full rig as separate PNGs, named by part — they line up
1:1 with the `Frog.cs` fields and the `FrogModel` rig parts:

| Sprite (per `<Name>` prefix) | Rig part / use |
|---|---|
| `…Body`, `…Head`, `…Mouth` | body, head, mouth |
| `…LeftEye` / `…RightEye`, `Universal…Pupil` / `…Sclera` | eyes (pupils/sclera shared via `Universal/`) |
| `…Low/Lower/Closed{Left,Right}Eyelid` | the blink/eyelid states (`Frog.ShowEyes`) |
| `…LeftHand` / `…RightHand`, `…HandGrab`, `…HandGrabBack` | open hand + grip variants (`Limb.cs`) |
| `…LeftLimb` / `…RightLimb` (+ `…Shadow`) | arms |
| `…Thumbnail` | store/UI thumbnail |

Non-frog art is also present: [`/Sprites/Rocks/`](../../Sprites/Rocks) (step
variants + direction arrows + `Castle`/`Rocket`/`Lillipad`),
[`/Sprites/Other/`](../../Sprites/Other) (`Bug`, `LavaSplash`, `Sun`, clouds,
grass, …), plus `Menu/` and `Scenery/`.

> **Getting them into Roblox.** The PNGs are prepped via [`/tools`](../../tools)
> (clean up + `upload_to_catbox.py` → `{name: url}`), and those catbox URLs are
> used as **reference inputs for Ludo** to generate the Roblox-bound assets — see
> the pipeline in
> [doc 10](10-implementation-setup.md#art-tooling-tools). A Roblox `Decal`/
> `ImageLabel` needs an `rbxassetid://` (an asset uploaded to Roblox), so the skin
> builder binds parts from the **generated assets' ids** (e.g. a name→assetId map),
> not from catbox URLs.

## Roblox mapping

| Original | Roblox |
|---|---|
| Source sprites in `/Sprites/Frogs/<name>/` | uploaded image assets → `Decal`/`Texture`/`ImageLabel` on the rig parts |
| Frog prefab per skin (`Frog.cs` + `SpriteLoad`) | a skin `Model` per look under `ReplicatedStorage/Assets/Skins/`, **or** one base frog with swappable textures/colors |
| `FrogPackages` catalog (`frogPackages` list, ids, `canBuy`, `isUnlocked`) | a `SkinCatalog` `ModuleScript` (data only) |
| `PlayerPrefs "FrogPackages"` ownership | per-player `DataStore` record: owned set + selected skin + Fly balance |
| `variableManager.currentFrogID` | a persisted `selectedSkin` field; applied on spawn |
| `MakeFrog(id)` / `SetFrog` | clone the selected skin model (or apply textures) when building the frog |
| Soomla `LifetimeVG` (premium frog) | **Game Pass** per premium skin (`MarketplaceService`, one-time) |
| Soomla `"1000 Flys"` consumable pack | **Developer Product** for Flys (`ProcessReceipt`, consumable) |
| `FLY_CURRENCY` (soft currency) | a persisted `Flys` balance, earned from bugs (doc 06) / gifts |
| `CycleFrog` / store UI | a `ScreenGui` store: cycle, owned/locked badge, buy/select buttons |

**Authority:** ownership, currency, and selection are **server-authoritative**
(DataStore is server-only). The client requests; the server validates and
persists. Never trust a client that says "I own skin X" or "my Fly balance is N" —
same rule as [07](07-multiplayer.md#authority--anti-exploit-required-either-way).

## Catalog (data) — replaces `StoreAssets` + serialized `Frog` fields

The real catalog lives at
[`src/shared/SkinCatalog.luau`](../../src/shared/SkinCatalog.luau) (names match the
`/Sprites/Frogs/` folders):

```lua
-- ReplicatedStorage/Shared/SkinCatalog (ModuleScript)
-- name -> /Sprites/Frogs/<name>/ ; gamePassId => premium; flyCost => soft currency;
-- default = true => owned free. The 4 premium frogs match Store/StoreAssets.cs.
return {
	[1] = { name = "Hot Frog", default = true }, -- namesake / starter
	[2] = { name = "Blue Frog", flyCost = 500 },
	[3] = { name = "Hawt Frog", flyCost = 1000 },
	[4] = { name = "Space Frog", flyCost = 1500 },
	[5] = { name = "Mystery Frog", flyCost = 2000 },
	[6] = { name = "Business Frog", gamePassId = 0 }, -- premium (set real id)
	[7] = { name = "Hot Lawyer", gamePassId = 0 },
	[8] = { name = "Invisible Man", gamePassId = 0 },
	[9] = { name = "Crossy Frog", gamePassId = 0 },
}
```

Each entry's `name` maps to the source art `/Sprites/Frogs/<name>/` and to the
built model under `ReplicatedStorage/Assets/Skins/<name>`. The `default`/`flyCost`/
`gamePassId` values are starting guesses — reconcile against the original frog
prefabs' `isUnlocked`/`canBuy`.

## Ownership, currency & selection — replaces `FrogPackages` persistence

> Implemented in [`src/server/SkinService.server.luau`](../../src/server/SkinService.server.luau).
> Ownership, Flys, and selection live on the shared profile
> ([`Profiles.luau`](../../src/server/Profiles.luau)) — SkinService owns the
> *rules* and remotes, not its own DataStore. The snippet below is the illustrative
> standalone version (it inlines the storage that Profiles now centralizes).

```lua
-- ServerScriptService/SkinService (Script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Catalog = require(ReplicatedStorage.Shared.SkinCatalog)

local store = DataStoreService:GetDataStore("HotfrogProfiles")
local profiles = {} -- [Player] = { owned = {[id]=true}, selected = id, flys = number }

-- remotes (reuse the auto-create helper pattern from GameServer)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local SelectSkin = remotes:FindFirstChild("SelectSkin") or Instance.new("RemoteEvent", remotes)
SelectSkin.Name = "SelectSkin"
local BuyWithFlys = remotes:FindFirstChild("BuyWithFlys") or Instance.new("RemoteFunction", remotes)
BuyWithFlys.Name = "BuyWithFlys"
local ProfileChanged = remotes:FindFirstChild("ProfileChanged") or Instance.new("RemoteEvent", remotes)
ProfileChanged.Name = "ProfileChanged"

local function defaultProfile()
	local owned = {}
	for id, entry in pairs(Catalog) do
		if entry.default then owned[id] = true end
	end
	return { owned = owned, selected = 1, flys = 0 }
end

local function push(player)
	ProfileChanged:FireClient(player, profiles[player])
end

local function save(player)
	local p = profiles[player]
	if p then pcall(function() store:SetAsync("u_" .. player.UserId, p) end) end
end

Players.PlayerAdded:Connect(function(player)
	local ok, saved = pcall(function() return store:GetAsync("u_" .. player.UserId) end)
	profiles[player] = (ok and saved) or defaultProfile()
	-- reconcile newly-added default skins (mirrors FrogPackages.LoadPackages)
	for id, entry in pairs(Catalog) do
		if entry.default then profiles[player].owned[id] = true end
	end
	grantGamePassSkins(player) -- see monetization below
	task.defer(push, player)
end)

Players.PlayerRemoving:Connect(function(player)
	save(player); profiles[player] = nil
end)

-- selecting: only if owned (server validates, mirrors "is package open")
SelectSkin.OnServerEvent:Connect(function(player, id)
	local p = profiles[player]
	if p and p.owned[id] then
		p.selected = id
		push(player)
		-- (re)build the frog with the new look on next spawn / immediately
	end
end)

-- soft-currency unlock (the Fly path)
BuyWithFlys.OnServerInvoke = function(player, id)
	local p, entry = profiles[player], Catalog[id]
	if not (p and entry and entry.flyCost) then return false end
	if p.owned[id] then return true end
	if p.flys < entry.flyCost then return false end
	p.flys -= entry.flyCost
	p.owned[id] = true
	push(player)
	return true
end
```

Award Flys from gameplay (extends [doc 06](06-bugs-and-tongue.md)): when a bug is
caught, add to `profiles[player].flys` and `push(player)` — Flys are the original
`FLY_CURRENCY` fed by bugs/gifts.

## Monetization (real money)

Roblox replaces Soomla with `MarketplaceService`. Two product kinds:

### Premium skins → Game Passes (permanent, one-time)

A Game Pass per premium frog (the analog of a `LifetimeVG`):

```lua
local MarketplaceService = game:GetService("MarketplaceService")

function grantGamePassSkins(player)
	local p = profiles[player]
	for id, entry in pairs(Catalog) do
		if entry.gamePassId and entry.gamePassId > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, entry.gamePassId)
			end)
			if ok and owns then p.owned[id] = true end
		end
	end
end

-- client asks to buy: MarketplaceService:PromptGamePassPurchase(player, gamePassId)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then return end
	for id, entry in pairs(Catalog) do
		if entry.gamePassId == passId then
			profiles[player].owned[id] = true
			push(player)
		end
	end
end)
```

### Fly packs → Developer Products (consumable, e.g. "1000 Flys")

Consumables must be granted in `ProcessReceipt`, which **must be idempotent** (it
can fire more than once):

```lua
local FLY_PRODUCTS = { [0 /*devProductId*/] = 1000 } -- productId -> flys granted

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player or not profiles[player] then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retry when they're back
	end
	local grant = FLY_PRODUCTS[receipt.ProductId]
	if not grant then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- idempotency: ignore a receipt key we've already applied
	local p = profiles[player]
	p.applied = p.applied or {}
	if not p.applied[receipt.PurchaseId] then
		p.applied[receipt.PurchaseId] = true
		p.flys += grant
		push(player)
		save(player) -- persist before acknowledging
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
```

## Applying the look — replaces `SpriteLoad` / `MakeFrog`

> **Superseded by the doc-07 hardening:** frogs are server-built, so the shipped
> code applies skins **server-side** — `GameServer.createFrog` reads
> `profile.selected` at creation and `SkinService` re-applies on `SelectSkin` —
> and the look replicates to everyone. The client snippet below remains valid for
> a client-built-frog architecture (the pre-hardening basic loop).

The basic [`GameClient`](../../src/client/GameClient.client.luau) clones a fixed
`Assets/FrogModel`. With skins, build the frog from the **selected** skin instead:

```lua
-- client: retexture the frog rig whenever the profile arrives / changes
local ProfileChanged = remotes:WaitForChild("ProfileChanged")
local Catalog = require(ReplicatedStorage.Shared.SkinCatalog)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)

-- Rig Decals carry a "Suffix" attribute ("Body", "Head", "LowLeftEyelid",
-- "LeftHandGrab", …); SpriteSkin resolves each to the selected skin's rbxassetid
-- via SkinAssets (and leaves the placeholder when an id isn't uploaded yet).
ProfileChanged.OnClientEvent:Connect(function(profile)
	SpriteSkin.apply(frogModel, Catalog[profile.selected].name)
end)
```

The same [`SpriteSkin`](../../src/shared/SpriteSkin.luau) util textures static art
too — a step, bug, or lava part with a `Sprite = "WhiteRock"` / `"Bug"` /
`"LavaSplash"` attribute gets textured by `SpriteSkin.apply(part)` (no skin name).
See the convention in
[doc 10](10-implementation-setup.md#texturing-parts-attribute-convention).

> Keep every skin model's child part names identical (`Head`, `LeftLimb`,
> `RightLimb`, `PrimaryPart`) so the core loop is skin-agnostic — only the
> appearance changes, exactly like the original swaps sprites but keeps the same
> `Frog` rig. The lighter alternative (one base model, swap `Texture`/`Decal`/
> `Color3` per skin) avoids per-skin models if your art is texture-based.

Each skin model's part textures come from the
[`/Sprites/Frogs/<name>/`](../../Sprites/Frogs) images (via the
[`/tools` → catbox → Ludo](10-implementation-setup.md#art-tooling-tools) pipeline)
— the per-part sprites map onto the matching rig parts (see
[Source art](#source-art-in-the-repo)). The eyelid PNGs (`Low`/`Lower`/`Closed`)
are the swap frames for `Frog.ShowEyes`-style blinking; pupils/sclera/tongue come
from `Universal/`. The part→assetId map lives in
[`src/shared/SkinAssets.luau`](../../src/shared/SkinAssets.luau) (keys are sprite
stems, matching the `upload_to_catbox.py` output) — paste the uploaded ids there, so
adding a skin is "drop a folder, run the pipeline, paste ids, add a `SkinCatalog`
row."

## Store UI — replaces `CycleFrog` + buy button

> **Implemented:** [`src/client/StoreUI.client.luau`](../../src/client/StoreUI.client.luau)
> — a Shop toggle opens a panel that cycles the roster (`<`/`>`), shows the
> Selected/Owned/locked-price status, and drives one context button; a Flys
> balance sits top-right and the gift button (doc 09) bottom-left. State comes
> entirely from `ProfileChanged`, so it can't desync from the authoritative
> profile.

A `ScreenGui` that shows one skin at a time with next/prev (the `CycleFrog`
analog), a locked/owned badge, and a context button:

- **Owned** → "Wear" → `SelectSkin:FireServer(id)`.
- **Buyable with Flys** (`flyCost`) → "Buy (N)" → `BuyWithFlys:InvokeServer(id)`
  (server checks balance; the panel just refreshes from `ProfileChanged`).
- **Premium** (`gamePassId`) → "Buy" → `MarketplaceService:PromptGamePassPurchase`.

Drive the owned/locked state and Fly balance entirely from the `ProfileChanged`
payload so the UI can't desync from the authoritative profile.

## Multiplayer note

**Resolved by the doc-07 hardening:** frogs are now built and skinned
**server-side** — `GameServer` applies the profile's skin at frog creation, and
[`SkinService`](../../src/server/SkinService.server.luau) retextures the live
`Frog_<userId>` model when the selection changes — so every player sees every
frog's skin through ordinary replication, no extra broadcast needed.

## Milestones

1. `SkinCatalog` + `SkinService` with default skins, selection, and DataStore
   persistence. *Verify: select a skin, rejoin, it's still selected.*
2. Apply the selected skin to the frog (model swap or texture swap). *Verify: the
   frog's look changes on select.*
3. Soft-currency path: earn Flys from bugs, buy a skin with `BuyWithFlys`.
   *Verify: balance drops, skin becomes owned & selectable, persists.*
4. Game Pass premium skin: prompt, grant on purchase, restore on rejoin via
   `UserOwnsGamePassAsync`. *Verify in Studio with a test pass.*
5. Developer Product Fly pack via `ProcessReceipt` (idempotent). *Verify: balance
   increases once per purchase, even if the receipt re-fires.*
6. Store UI tying it together (cycle / owned / buy / select).
7. (Multiplayer) replicate each player's skin to others.

## Still out of scope

Ads (`Ads/`), gifting/daily rewards (`UI/GiftManager.cs`), and the celebration
sequences around unlocks are separate; this doc covers the skin **catalog,
ownership, currency, monetization, and selection** that make a store work.
