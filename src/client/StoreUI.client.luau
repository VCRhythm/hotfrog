-- StarterPlayer/StarterPlayerScripts/Client/StoreUI (LocalScript)
-- Store + gift UI (../../docs/roblox-port/08-frog-skins-and-store.md "Store UI";
-- ../../docs/roblox-port/09-gifts-and-ads.md gift button). Pure client: it reads
-- the authoritative profile (ProfileChanged) and sends intents the server
-- validates -- SelectSkin / BuyWithFlys / ClaimGift / Game Pass prompts. The
-- server owns ownership, currency, and the gift cooldown; this is just glass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Catalog = require(ReplicatedStorage.Shared.SkinCatalog)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ProfileChanged = remotes:WaitForChild("ProfileChanged") :: RemoteEvent
local SelectSkin = remotes:WaitForChild("SelectSkin") :: RemoteEvent
local BuyWithFlys = remotes:WaitForChild("BuyWithFlys") :: RemoteFunction
local ClaimGift = remotes:WaitForChild("ClaimGift") :: RemoteFunction
local GiftStatus = remotes:WaitForChild("GiftStatus") :: RemoteEvent

-- ordered skin ids (Catalog is keyed by numeric id; tolerate gaps)
local ids: { number } = {}
for id in pairs(Catalog) do
	table.insert(ids, id)
end
table.sort(ids)

-- latest authoritative profile snapshot + the skin currently shown in the panel
local profile: any = nil
local cursor = 1

-- ---------------------------------------------------------------------------
-- Small GUI builders
-- ---------------------------------------------------------------------------
local DARK = Color3.fromRGB(28, 30, 38)
local ACCENT = Color3.fromRGB(96, 170, 255)

local gui = Instance.new("ScreenGui")
gui.Name = "StoreGui"
gui.ResetOnSpawn = false

local function corner(parent: Instance)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = parent
end

local function button(name: string, text: string, size: UDim2, pos: UDim2, parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = DARK
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.AutoButtonColor = true
	b.Text = text
	b.Parent = parent
	corner(b)
	return b
end

local function label(name: string, text: string, size: UDim2, pos: UDim2, parent: Instance): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamMedium
	l.TextScaled = true
	l.Text = text
	l.Parent = parent
	return l
end

-- ---------------------------------------------------------------------------
-- Bottom bar: Flys balance, Shop toggle, Gift button
-- ---------------------------------------------------------------------------
local flysLabel = label("Flys", "Flys: 0", UDim2.fromOffset(160, 36), UDim2.new(1, -172, 0, 12), gui)
flysLabel.TextXAlignment = Enum.TextXAlignment.Right

local shopToggle = button("Shop", "Shop", UDim2.fromOffset(120, 44), UDim2.new(1, -132, 1, -56), gui)
local giftButton = button("Gift", "Gift", UDim2.fromOffset(150, 44), UDim2.new(0, 12, 1, -56), gui)
giftButton.BackgroundColor3 = ACCENT

-- ---------------------------------------------------------------------------
-- Store panel (hidden until Shop is tapped) -- the CycleFrog analog
-- ---------------------------------------------------------------------------
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(360, 260)
panel.Position = UDim2.new(0.5, -180, 0.5, -130)
panel.BackgroundColor3 = DARK
panel.BackgroundTransparency = 0.05
panel.Visible = false
panel.Parent = gui
corner(panel)

local nameLabel = label("SkinName", "", UDim2.fromOffset(240, 48), UDim2.fromOffset(60, 20), panel)
local statusLabel = label("Status", "", UDim2.fromOffset(320, 30), UDim2.fromOffset(20, 120), panel)
statusLabel.TextColor3 = Color3.fromRGB(180, 188, 200)

local prevButton = button("Prev", "<", UDim2.fromOffset(44, 48), UDim2.fromOffset(12, 20), panel)
local nextButton = button("Next", ">", UDim2.fromOffset(44, 48), UDim2.new(1, -56, 0, 20), panel)
local actionButton = button("Action", "", UDim2.fromOffset(220, 48), UDim2.new(0.5, -110, 1, -64), panel)
actionButton.BackgroundColor3 = ACCENT
local closeButton = button("Close", "X", UDim2.fromOffset(36, 36), UDim2.new(1, -44, 0, 8), panel)
closeButton.BackgroundColor3 = DARK

-- ---------------------------------------------------------------------------
-- Panel state: derive the current skin's button/status from the profile
-- ---------------------------------------------------------------------------
local function currentId(): number?
	return ids[cursor]
end

local function refreshPanel()
	local id = currentId()
	local entry = id and Catalog[id]
	if not entry then
		return
	end
	nameLabel.Text = entry.name

	local owned = profile and profile.owned and id and profile.owned[id]
	local selected = profile and id and profile.selected == id

	if selected then
		statusLabel.Text = "Selected"
		actionButton.Text = "Selected"
		actionButton.Active = false
		actionButton.BackgroundColor3 = DARK
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
	elseif entry.gamePassId and entry.gamePassId > 0 then
		statusLabel.Text = "Premium"
		actionButton.Text = "Buy"
		actionButton.Active = true
		actionButton.BackgroundColor3 = ACCENT
	else
		statusLabel.Text = "Locked"
		actionButton.Text = "—"
		actionButton.Active = false
		actionButton.BackgroundColor3 = DARK
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

local function cycle(delta: number)
	cursor = (cursor - 1 + delta) % #ids + 1
	refreshPanel()
end

prevButton.Activated:Connect(function()
	cycle(-1)
end)
nextButton.Activated:Connect(function()
	cycle(1)
end)
actionButton.Activated:Connect(onAction)
shopToggle.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		refreshPanel()
	end
end)
closeButton.Activated:Connect(function()
	panel.Visible = false
end)

ProfileChanged.OnClientEvent:Connect(function(p)
	profile = p
	flysLabel.Text = "Flys: " .. tostring((p and p.flys) or 0)
	if panel.Visible then
		refreshPanel()
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
