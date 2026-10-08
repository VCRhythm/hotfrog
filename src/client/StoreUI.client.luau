-- StarterPlayer/StarterPlayerScripts/Client/StoreUI (LocalScript)
-- Store + gift UI (../../docs/roblox-port/08-frog-skins-and-store.md "Store UI";
-- ../../docs/roblox-port/09-gifts-and-ads.md gift button). Pure client: it reads
-- the authoritative profile (ProfileChanged) and sends intents the server
-- validates -- SelectSkin / BuyWithFlys / ClaimGift / Game Pass prompts. The
-- server owns ownership, currency, and the gift cooldown; this is just glass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Catalog = require(ReplicatedStorage.Shared.SkinCatalog)
local Config = require(ReplicatedStorage.Shared.Config)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local SkinTints = require(ReplicatedStorage.Shared.SkinTints)
local SoundFX = require(ReplicatedStorage.Shared.SoundFX)
local UIKit = require(script.Parent.ui.UIKit)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ProfileChanged = remotes:WaitForChild("ProfileChanged") :: RemoteEvent
local SelectSkin = remotes:WaitForChild("SelectSkin") :: RemoteEvent
local BuyWithFlys = remotes:WaitForChild("BuyWithFlys") :: RemoteFunction
local BuyTint = remotes:WaitForChild("BuyTint") :: RemoteFunction
local SelectTint = remotes:WaitForChild("SelectTint") :: RemoteEvent
local ClaimGift = remotes:WaitForChild("ClaimGift") :: RemoteFunction
local GiftStatus = remotes:WaitForChild("GiftStatus") :: RemoteEvent
local RunStateChanged = remotes:WaitForChild("RunStateChanged") :: RemoteEvent

-- doc 15 (menus-and-input): a tiny bridge so MenuClient can open/close THIS
-- script's existing store panel instead of duplicating the frog carousel --
-- same cross-LocalScript Folder+BindableEvent pattern LevelClient.client.luau
-- uses for LevelState. LocalScripts can't `require` each other, so this is the
-- one place StoreUI and MenuClient actually talk.
local menuBridge = Instance.new("Folder")
menuBridge.Name = "MenuBridge"
local openStoreEvent = Instance.new("BindableEvent")
openStoreEvent.Name = "OpenStore"
openStoreEvent.Parent = menuBridge
local storeClosedEvent = Instance.new("BindableEvent")
storeClosedEvent.Name = "StoreClosed"
storeClosedEvent.Parent = menuBridge
-- The bottom-right Shop toggle below opens this same panel without going
-- through MenuClient's openStore() (that only fires OpenStore), so it needs
-- its own signal telling MenuClient to get its own panel out of the way too
-- (b-20260921-152551: shop rendered behind the main menu).
local storeOpenedEvent = Instance.new("BindableEvent")
storeOpenedEvent.Name = "StoreOpened"
storeOpenedEvent.Parent = menuBridge
menuBridge.Parent = player

-- ordered skin ids (Catalog is keyed by numeric id; tolerate gaps)
local ids: { number } = {}
for id in pairs(Catalog) do
	table.insert(ids, id)
end
table.sort(ids)

-- latest authoritative profile snapshot + the skin currently shown in the store
local profile: any = nil
local cursor = 1

-- ---------------------------------------------------------------------------
-- Small GUI builders
-- ---------------------------------------------------------------------------
local DARK = UIKit.DARK
local ACCENT = UIKit.ACCENT
local button = UIKit.button
local label = UIKit.label

-- doc 15: UIKit.screenGui adds the UIScale that keeps this readable on both
-- phone portrait and desktop landscape (item 6's "UI must work on phone
-- portrait and desktop landscape" requirement).
local gui = UIKit.screenGui("StoreGui")
gui.DisplayOrder = 5 -- match MenuGui so this panel isn't painted underneath it

-- ---------------------------------------------------------------------------
-- Bottom bar: Shop toggle, Gift button
-- ---------------------------------------------------------------------------
-- No separate Flys balance here (b-20260921-112735-t2ly): GameClient's HUD
-- FlysLabel is already on screen in every run state (Menu/Playing/Dead), a
-- strict superset of this bar's Menu/Dead-only visibility, so a second Flys
-- counter here only risked disagreeing with it.
local shopToggle = button("Shop", "Shop", UDim2.fromOffset(120, 44), UDim2.new(1, -132, 1, -56), gui, "FrogHeadIcon")
local giftButton = button("Gift", "Gift", UDim2.fromOffset(150, 44), UDim2.new(0, 12, 1, -56), gui, "Present")
giftButton.BackgroundColor3 = ACCENT

-- ---------------------------------------------------------------------------
-- Store screen (hidden until Shop/Frogs is tapped) -- the FrogPackages
-- CycleFrog + MenuManager ArrowPanel analog (b-20261001-145155-yes7). Unity
-- has no store modal: ShowFrogs leaves the play field up, swaps the frog
-- itself for each candidate (MakeFrog: a fresh frog rises from below,
-- Frog.Rise), and shows big left/right arrows, the frog's name and a Buy
-- button. Back (ShowMainMenu -> MakeSureFrogIsPurchased) keeps an owned frog,
-- or lowers an unowned one off screen and raises an owned frog in its place.
--
-- The real frog is server-owned (doc 13), so the preview is a LOCAL clone of
-- the FrogModel template parked on the real frog's body, which is hidden for
-- this viewer only (LocalTransparencyModifier, which also hides its decals).
-- Other players keep seeing the equipped skin until a real SelectSkin.
-- ---------------------------------------------------------------------------
local store = Instance.new("Frame")
store.Name = "Store"
store.Size = UDim2.fromScale(1, 1)
store.BackgroundTransparency = 1
store.Visible = false
store.Parent = gui

local nameLabel = label("SkinName", "", UDim2.fromOffset(360, 56), UDim2.new(0.5, -180, 0, 96), store)
nameLabel.TextColor3 = UIKit.HUD_TEXT
UIKit.textStroke(nameLabel)
local statusLabel = label("Status", "", UDim2.fromOffset(360, 30), UDim2.new(0.5, -180, 0, 154), store)
statusLabel.TextColor3 = UIKit.HUD_SUBTEXT
UIKit.textStroke(statusLabel)

local prevButton = button("Prev", "<", UDim2.fromOffset(96, 140), UDim2.new(0, 16, 0.5, -70), store)
local nextButton = button("Next", ">", UDim2.fromOffset(96, 140), UDim2.new(1, -112, 0.5, -70), store)
local actionButton = button("Action", "", UDim2.fromOffset(240, 56), UDim2.new(0.5, -120, 1, -128), store)
actionButton.BackgroundColor3 = ACCENT
-- Robux alternative for a skin that has BOTH a flyCost and a real gamePassId
-- (b-20261008-142458-vo87: every skin is on the Fly ladder, premium ones keep
-- their Game Pass); the Action button stays the Flys buy.
local robuxButton = button("Robux", "Buy with Robux", UDim2.fromOffset(200, 40), UDim2.new(0.5, -100, 1, -176), store)
robuxButton.BackgroundColor3 = ACCENT
robuxButton.Visible = false
-- bottom centre, between Gift and Shop: the top-left corner is the HUD's score
local backButton = button("Back", "Back", UDim2.fromOffset(120, 48), UDim2.new(0.5, -60, 1, -60), store, "Home")
backButton.BackgroundColor3 = DARK

-- Colourway swatches for the shown skin (b-20261008-142125-1ucz; doc 17):
-- only for an owned skin, so they sit where the Robux button would be. "Off"
-- clears the tint; an unowned swatch shows its Flys price and buys (then
-- wears) it; an owned one wears it. The server validates all of it.
local SWATCH_W, SWATCH_GAP = 72, 8
local swatchRow = Instance.new("Frame")
swatchRow.Name = "Tints"
swatchRow.BackgroundTransparency = 1
swatchRow.Size = UDim2.fromOffset((#SkinTints.list + 1) * (SWATCH_W + SWATCH_GAP) - SWATCH_GAP, 52)
swatchRow.Position = UDim2.new(0.5, -swatchRow.Size.X.Offset / 2, 1, -192)
swatchRow.Visible = false
swatchRow.Parent = store
local swatchLayout = Instance.new("UIListLayout")
swatchLayout.FillDirection = Enum.FillDirection.Horizontal
swatchLayout.Padding = UDim.new(0, SWATCH_GAP)
swatchLayout.SortOrder = Enum.SortOrder.LayoutOrder
swatchLayout.Parent = swatchRow
local swatches: { [number]: TextButton } = {}
local function makeSwatch(tintId: number, color: Color3)
	local b = button("Tint" .. tintId, "", UDim2.fromOffset(SWATCH_W, 52), UDim2.new(), swatchRow)
	b.LayoutOrder = tintId
	b.BackgroundColor3 = color
	swatches[tintId] = b
end
makeSwatch(0, SkinTints.NONE)
for _, tint in SkinTints.list do
	makeSwatch(tint.id, tint.color)
end

-- ---------------------------------------------------------------------------
-- Preview frog (local clone; see the header above)
-- ---------------------------------------------------------------------------
local frogTemplate = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("FrogModel") :: Model
local frogsFolder = workspace:WaitForChild("PlayField"):WaitForChild("Frogs")
local DROP = -100 * Config.UNITY_TO_STUDS -- Frog.cs endY: where a lowered frog sits
local MOVE_TIME = 1 -- Frog.cs Rise / Lower: DOMoveY(..., 1f)
local RISE_INFO = TweenInfo.new(MOVE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LOWER_INFO = TweenInfo.new(MOVE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BOUNCE_INFO = TweenInfo.new(MOVE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

type Preview = { model: Model, y: NumberValue }
local previews: { Preview } = {}
local current: Preview? = nil -- the candidate frog on screen while the store is open
local storeOpen = false
local closeToken = 0 -- bumped on every open/close so a stale Back animation stops

local function realFrog(): Model?
	local m = frogsFolder:FindFirstChild("Frog_" .. player.UserId)
	return if m and m:IsA("Model") then m else nil
end

local function setRealHidden(hidden: boolean)
	local m = realFrog()
	if not m then
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

-- The tint worn on skin `id` per the latest profile (white when none/unowned).
local function wornTint(id: number?): Color3
	local tints = profile and profile.selectedTints
	local tintId = if tints and id then tints[tostring(id)] else nil
	if tintId and tintId ~= 0 and profile.ownedTints and profile.ownedTints[SkinTints.key(id :: number, tintId)] then
		return SkinTints.color(tintId)
	end
	return SkinTints.NONE
end

local function skinIdByName(skinName: string): number?
	for id, entry in pairs(Catalog) do
		if entry.name == skinName then
			return id
		end
	end
	return nil
end

local function makePreview(skinName: string, y: number): Preview
	local model = frogTemplate:Clone()
	model.PrimaryPart = model:FindFirstChild("Body") :: BasePart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	SpriteSkin.apply(model, skinName)
	SkinTints.apply(model, wornTint(skinIdByName(skinName)))
	local value = Instance.new("NumberValue")
	value.Value = y
	local preview: Preview = { model = model, y = value }
	table.insert(previews, preview)
	model.Parent = workspace.CurrentCamera
	return preview
end

local function destroyPreview(preview: Preview?)
	if not preview then
		return
	end
	local i = table.find(previews, preview)
	if i then
		table.remove(previews, i)
	end
	preview.model:Destroy()
	preview.y:Destroy()
end

local function clearPreviews()
	for i = #previews, 1, -1 do
		destroyPreview(previews[i])
	end
	current = nil
end

local function tweenY(preview: Preview, y: number, info: TweenInfo): Tween
	local tween = TweenService:Create(preview.y, info, { Value = y })
	tween:Play()
	return tween
end

-- Park every preview on the real frog's body (offset by its rise/lower y).
RunService.RenderStepped:Connect(function()
	if #previews == 0 then
		return
	end
	local m = realFrog()
	local body = m and m.PrimaryPart
	if not body then
		return
	end
	for _, preview in previews do
		preview.model:PivotTo(CFrame.new(body.Position + Vector3.new(0, preview.y.Value, 0)))
	end
end)

-- ---------------------------------------------------------------------------
-- Store state: derive the current skin's button/status from the profile
-- ---------------------------------------------------------------------------
local function currentId(): number?
	return ids[cursor]
end

local function refreshStore()
	local id = currentId()
	local entry = id and Catalog[id]
	if not entry then
		return
	end
	nameLabel.Text = entry.name

	local owned = profile and profile.owned and id and profile.owned[id]
	local selected = profile and id and profile.selected == id

	-- Flys-price icon (b-20260922-145930): only the "Buy (N)" state is a Flys
	-- price, so the icon set on Action here is a fresh call each refresh
	-- rather than a fixed stem the button was created with.
	local flysIcon: string? = nil
	actionButton.Visible = true
	robuxButton.Visible = not owned and entry.flyCost ~= nil and (entry.gamePassId or 0) > 0
	if selected then
		statusLabel.Text = "Selected"
		actionButton.Visible = false
	elseif owned then
		statusLabel.Text = "Owned"
		actionButton.Text = "Wear"
		actionButton.Active = true
		actionButton.BackgroundColor3 = ACCENT
	elseif entry.flyCost then
		statusLabel.Text = "Locked — " .. entry.flyCost .. " Flys"
		actionButton.Text = "Buy (" .. entry.flyCost .. ")"
		actionButton.Active = true
		actionButton.BackgroundColor3 = ACCENT
		flysIcon = "BugIcon"
	elseif entry.gamePassId and entry.gamePassId > 0 then
		statusLabel.Text = "Premium"
		actionButton.Text = "Buy"
		actionButton.Active = true
		actionButton.BackgroundColor3 = ACCENT
	else
		statusLabel.Text = "Locked"
		actionButton.Visible = false
	end
	UIKit.setButtonIcon(actionButton, flysIcon)

	swatchRow.Visible = owned == true
	if owned and id then
		local tints = profile.selectedTints
		local worn = (tints and tints[tostring(id)]) or 0
		local ownedTints = profile.ownedTints or {}
		for tintId, swatch in swatches do
			local tint = SkinTints.get(tintId)
			local has = tintId == 0 or ownedTints[SkinTints.key(id, tintId)] == true
			if has and worn == tintId then
				swatch.Text = "On"
			elseif has then
				swatch.Text = if tintId == 0 then "Off" else ""
			else
				swatch.Text = tostring(tint and tint.flyCost or "")
			end
		end
	end
	if current then
		SkinTints.apply(current.model, wornTint(id))
	end
end

local function onSwatch(tintId: number)
	local id = currentId()
	if not (id and profile and profile.owned and profile.owned[id]) then
		return
	end
	local ownedTints = profile.ownedTints or {}
	if tintId == 0 or ownedTints[SkinTints.key(id, tintId)] then
		SelectTint:FireServer(id, tintId)
	else
		task.spawn(function()
			-- server checks skin ownership + balance; wear it once bought
			if BuyTint:InvokeServer(id, tintId) then
				SelectTint:FireServer(id, tintId)
			end
		end)
	end
end

local function onAction()
	local id = currentId()
	local entry = id and Catalog[id]
	if not (id and entry and profile) then
		return
	end
	if profile.owned and profile.owned[id] then
		if profile.selected ~= id then
			SelectSkin:FireServer(id) -- server validates ownership
		end
	elseif entry.flyCost then
		task.spawn(function()
			BuyWithFlys:InvokeServer(id) -- server checks balance; ProfileChanged refreshes us
		end)
	elseif entry.gamePassId and entry.gamePassId > 0 then
		MarketplaceService:PromptGamePassPurchase(player, entry.gamePassId)
	end
end

local function equippedName(): string?
	local entry = profile and Catalog[profile.selected]
	return entry and entry.name
end

local function openStore()
	if storeOpen then
		return
	end
	storeOpen = true
	closeToken += 1
	clearPreviews()
	if profile and profile.selected then
		cursor = table.find(ids, profile.selected) or cursor
	end
	-- Unity ShowFrogs keeps the frog already on screen: the stand-in starts
	-- in place, wearing the candidate (= the equipped skin) skin.
	local entry = Catalog[ids[cursor]]
	if entry then
		current = makePreview(entry.name, 0)
	end
	setRealHidden(true)
	store.Visible = true
	refreshStore()
end

-- Unity MakeFrog: the old frog is destroyed and the new one rises from below.
local function cycle(delta: number)
	cursor = (cursor - 1 + delta) % #ids + 1
	destroyPreview(current)
	current = nil
	local entry = Catalog[ids[cursor]]
	if entry then
		local preview = makePreview(entry.name, DROP)
		current = preview
		tweenY(preview, 0, RISE_INFO)
		SoundFX.play("awake") -- Frog.cs Rise: awakeSound
	end
	refreshStore()
end

-- Back. An owned candidate stays (Unity's MakeFrog already equips any owned
-- frog it shows); an unowned one is lowered off screen and the equipped frog
-- bounces back up (MakeSureFrogIsPurchased -> LowerAndOpen...). `animate`
-- is false when a run starts underneath the store: just restore at once.
local function closeStore(animate: boolean)
	if not storeOpen then
		if not animate then
			-- a run started during Back's drop/bounce: cancel it, restore at once
			closeToken += 1
			clearPreviews()
			setRealHidden(false)
		end
		return
	end
	storeOpen = false
	store.Visible = false
	closeToken += 1
	local token = closeToken

	local id = currentId()
	local owned = profile and profile.owned and id and profile.owned[id]
	if owned or not animate then
		if owned and profile.selected ~= id then
			SelectSkin:FireServer(id)
			-- the server re-skins the real frog for everyone; paint it locally
			-- now so it doesn't flash the old skin while that replicates
			local m = realFrog()
			local entry = Catalog[id]
			if m and entry then
				SpriteSkin.apply(m, entry.name)
			end
		end
		clearPreviews()
		setRealHidden(false)
		return
	end

	local leaving = current
	current = nil
	task.spawn(function()
		if leaving then
			tweenY(leaving, DROP, LOWER_INFO).Completed:Wait()
			destroyPreview(leaving)
		end
		local name = equippedName()
		if token ~= closeToken then
			return
		end
		if name then
			local returning = makePreview(name, DROP)
			SoundFX.play("awake")
			tweenY(returning, 0, BOUNCE_INFO).Completed:Wait()
			if token ~= closeToken then
				return
			end
			destroyPreview(returning)
		end
		setRealHidden(false)
	end)
end

-- b-20261001-150712-8jsz: when the start screen shows (join, or back to Menu
-- after a death) the equipped frog bounces up into place, like Back's bounce.
-- Same local stand-in as the store; a run start / store open cancels it via
-- closeToken (closeStore(false) restores at once).
local function bounceIn()
	if storeOpen then
		return
	end
	closeToken += 1
	local token = closeToken
	clearPreviews()
	task.spawn(function()
		local waited = 0
		while (not realFrog() or not equippedName()) and waited < 5 do
			waited += task.wait()
			if token ~= closeToken then
				return
			end
		end
		local name = equippedName()
		if not name or not realFrog() then
			return
		end
		setRealHidden(true)
		local preview = makePreview(name, DROP)
		SoundFX.play("awake")
		tweenY(preview, 0, BOUNCE_INFO).Completed:Wait()
		if token ~= closeToken then
			return
		end
		destroyPreview(preview)
		setRealHidden(false)
	end)
end

prevButton.Activated:Connect(function()
	cycle(-1)
end)
nextButton.Activated:Connect(function()
	cycle(1)
end)
actionButton.Activated:Connect(onAction)
for tintId, swatch in swatches do
	swatch.Activated:Connect(function()
		onSwatch(tintId)
	end)
end
robuxButton.Activated:Connect(function()
	local entry = Catalog[currentId() or 0]
	if entry and entry.gamePassId and entry.gamePassId > 0 then
		MarketplaceService:PromptGamePassPurchase(player, entry.gamePassId)
	end
end)
shopToggle.Activated:Connect(function()
	if storeOpen then
		closeStore(true)
		storeClosedEvent:Fire()
	else
		openStore()
		storeOpenedEvent:Fire()
	end
end)
backButton.Activated:Connect(function()
	closeStore(true)
	storeClosedEvent:Fire() -- doc 15: lets MenuClient bring its own panel back
end)

openStoreEvent.Event:Connect(openStore)

ProfileChanged.OnClientEvent:Connect(function(p)
	profile = p
	if storeOpen then
		refreshStore()
	end
end)

-- doc 15 item 1: this bottom bar (Shop toggle + Gift button) is the main
-- menu's "Gift"/"Shop/Flys" entries reused as-is, so it only makes sense
-- outside an active run. Hidden during Playing; the store itself is
-- force-closed too so a run can't be interrupted by a lingering store.
local sawRunState = false -- the initial server fire can predate this connection
RunStateChanged.OnClientEvent:Connect(function(state: string)
	sawRunState = true
	local outOfRun = state ~= "Playing"
	shopToggle.Visible = outOfRun
	giftButton.Visible = outOfRun
	if not outOfRun then
		closeStore(false)
	elseif state == "Menu" then
		bounceIn()
	end
end)

-- Join: the server's first "Menu" fire may have landed before we connected, so
-- read the lane's RunState attribute once (unless the event already arrived).
task.spawn(function()
	local lane = workspace:WaitForChild("PlayField"):WaitForChild("Lanes"):WaitForChild(tostring(player.UserId), 30)
	if lane and not sawRunState and lane:GetAttribute("RunState") == "Menu" then
		bounceIn()
	end
end)

-- ---------------------------------------------------------------------------
-- Gift button + countdown (doc 09). Server is the clock; we estimate it locally
-- between GiftStatus updates so the timer ticks smoothly.
-- ---------------------------------------------------------------------------
local readyAt = math.huge
local serverNowAtRecv = 0
local clockAtRecv = os.clock()

GiftStatus.OnClientEvent:Connect(function(nextAt, now)
	readyAt = tonumber(nextAt) or math.huge
	serverNowAtRecv = tonumber(now) or 0
	clockAtRecv = os.clock()
end)

giftButton.Activated:Connect(function()
	task.spawn(function()
		local ok = ClaimGift:InvokeServer()
		if not ok then
			return -- not ready yet; the countdown will catch up on the next GiftStatus
		end
	end)
end)

task.spawn(function()
	while true do
		local estServerNow = serverNowAtRecv + (os.clock() - clockAtRecv)
		local remaining = readyAt - estServerNow
		if remaining <= 0 then
			giftButton.Text = "Gift!"
			giftButton.BackgroundColor3 = ACCENT
		else
			local mins = math.floor(remaining / 60)
			local secs = math.floor(remaining % 60)
			giftButton.Text = string.format("Gift %d:%02d", mins, secs)
			giftButton.BackgroundColor3 = DARK
		end
		task.wait(1)
	end
end)

gui.Parent = player:WaitForChild("PlayerGui")
