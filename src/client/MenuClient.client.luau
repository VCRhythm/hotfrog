--!strict
-- StarterPlayer/StarterPlayerScripts/Client/MenuClient (LocalScript)
-- The Menu -> Playing -> Dead run-state UI (docs/roblox-port/15-menus-and-input.md
-- item 1): main menu (Play/Frogs/Settings/Top Scores), the end-of-run panel
-- (score/best/new-best flourish/grab-quality percentages/replay/home/gift or
-- shop prompt), and Settings (music/SFX/replay tutorial). It never simulates
-- gameplay -- it only shows/hides panels off the server's RunStateChanged and
-- fires the handful of new client -> server intents (StartRun, SetMusicOn,
-- ReplayTutorial). Score/skins/gift state are read from the SAME remotes
-- GameClient/StoreUI already listen to (RemoteEvents support more than one
-- OnClientEvent listener), so nothing here can desync from them.
--
-- Store/gift UI is intentionally NOT rebuilt here: StoreUI.client.luau's panel
-- (frog carousel + gift button) is reused via a tiny local bridge
-- (`Players.LocalPlayer.MenuBridge`, a Folder of BindableEvents -- same
-- pattern LevelClient.client.luau uses for its LevelState) instead of
-- duplicating the carousel/gift logic here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent.ui.UIKit)
local ClientSettings = require(script.Parent.ui.ClientSettings)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local StartRun = remotes:WaitForChild("StartRun") :: RemoteEvent
local RunStateChanged = remotes:WaitForChild("RunStateChanged") :: RemoteEvent
local RunSummary = remotes:WaitForChild("RunSummary") :: RemoteEvent
local SetMusicOn = remotes:WaitForChild("SetMusicOn") :: RemoteEvent
local ReplayTutorial = remotes:WaitForChild("ReplayTutorial") :: RemoteEvent
local GetTopScores = remotes:WaitForChild("GetTopScores") :: RemoteFunction
local ProfileChanged = remotes:WaitForChild("ProfileChanged") :: RemoteEvent
local ClaimGift = remotes:WaitForChild("ClaimGift") :: RemoteFunction
local GiftStatus = remotes:WaitForChild("GiftStatus") :: RemoteEvent
local GetGiftStatus = remotes:WaitForChild("GetGiftStatus") :: RemoteFunction

-- Bridge into StoreUI's existing panel (doc 15: "reuse ... rather than
-- duplicating"). StoreUI creates this Folder; wait for it rather than racing
-- LocalScript load order.
local menuBridge = player:WaitForChild("MenuBridge", math.huge) :: Folder
local openStoreEvent = menuBridge:WaitForChild("OpenStore") :: BindableEvent
local storeClosedEvent = menuBridge:WaitForChild("StoreClosed") :: BindableEvent

-- doc 15 item 7: glyph/nav hints follow GameClient's InputState.Gamepad flag
-- (same cross-LocalScript Folder+Attribute pattern as LevelClient's LevelState).
local inputState = player:WaitForChild("InputState", math.huge) :: Folder
local function gamepadActive(): boolean
	return inputState:GetAttribute("Gamepad") == true
end

-- ---------------------------------------------------------------------------
-- Root GUI
-- ---------------------------------------------------------------------------
local gui = UIKit.screenGui("MenuGui")
gui.DisplayOrder = 5

local title = UIKit.label("Title", "HOTFROG", UDim2.fromOffset(320, 64), UDim2.new(0.5, -160, 0, 24), gui)
title.Font = Enum.Font.GothamBlack
title.TextColor3 = UIKit.GOOD
title.Position = UDim2.new(0.5, -160, 0, 24)
title.AnchorPoint = Vector2.new(0, 0)
UIKit.safeAreaTopPadding(title, 0)

-- ---------------------------------------------------------------------------
-- Main menu panel (RunState.Menu)
-- ---------------------------------------------------------------------------
local mainPanel = UIKit.panel("MainMenu", UDim2.fromOffset(280, 260), UDim2.new(0.5, -140, 0.5, -130), gui)

local playButton = UIKit.button("Play", "PLAY", UDim2.fromOffset(220, 64), UDim2.fromOffset(30, 24), mainPanel)
playButton.BackgroundColor3 = UIKit.ACCENT
playButton.TextSize = 28

local frogsButton = UIKit.button("Frogs", "Frogs", UDim2.fromOffset(105, 48), UDim2.fromOffset(30, 100), mainPanel)
local settingsButton =
	UIKit.button("Settings", "Settings", UDim2.fromOffset(105, 48), UDim2.fromOffset(145, 100), mainPanel)
local topScoresButton =
	UIKit.button("TopScores", "Top Scores", UDim2.fromOffset(220, 44), UDim2.fromOffset(30, 158), mainPanel)
local hintLabel = UIKit.label("Hint", "", UDim2.fromOffset(220, 30), UDim2.fromOffset(30, 210), mainPanel)
hintLabel.TextColor3 = UIKit.SUBTEXT
hintLabel.TextScaled = false
hintLabel.TextSize = 16

-- ---------------------------------------------------------------------------
-- End-of-run panel (RunState.Dead)
-- ---------------------------------------------------------------------------
local endPanel = UIKit.panel("EndOfRun", UDim2.fromOffset(320, 360), UDim2.new(0.5, -160, 0.5, -180), gui)
endPanel.Visible = false

UIKit.label("Title", "Run over", UDim2.fromOffset(280, 36), UDim2.fromOffset(20, 16), endPanel)
local scoreLine = UIKit.label("Score", "", UDim2.fromOffset(280, 40), UDim2.fromOffset(20, 52), endPanel)
scoreLine.Font = Enum.Font.GothamBlack
scoreLine.TextSize = 26
local bestLine = UIKit.label("Best", "", UDim2.fromOffset(280, 26), UDim2.fromOffset(20, 92), endPanel)
bestLine.TextColor3 = UIKit.SUBTEXT
local qualityLine = UIKit.label("Quality", "", UDim2.fromOffset(280, 50), UDim2.fromOffset(20, 122), endPanel)
qualityLine.TextColor3 = UIKit.SUBTEXT
qualityLine.TextWrapped = true
local statsLine = UIKit.label("Stats", "", UDim2.fromOffset(280, 26), UDim2.fromOffset(20, 176), endPanel)
statsLine.TextColor3 = UIKit.SUBTEXT

local replayButton = UIKit.button("Replay", "Replay", UDim2.fromOffset(135, 52), UDim2.fromOffset(20, 214), endPanel)
replayButton.BackgroundColor3 = UIKit.ACCENT
local homeButton = UIKit.button("Home", "Home", UDim2.fromOffset(125, 52), UDim2.fromOffset(165, 214), endPanel)

-- Gift/Shop prompt (doc 15 item 1: the Unity ad/buy/wait branch reduces to
-- "gift ready -> claim, else show the wait + a Shop button" since ads were
-- dropped by the owner's decision, doc 09).
local giftPromptButton = UIKit.button("GiftPrompt", "", UDim2.fromOffset(280, 56), UDim2.fromOffset(20, 278), endPanel)
giftPromptButton.BackgroundColor3 = UIKit.WARN
giftPromptButton.TextColor3 = Color3.new(0, 0, 0)

-- ---------------------------------------------------------------------------
-- Settings panel
-- ---------------------------------------------------------------------------
local settingsPanel = UIKit.panel("Settings", UDim2.fromOffset(280, 260), UDim2.new(0.5, -140, 0.5, -130), gui)
settingsPanel.Visible = false
settingsPanel.ZIndex = 2

UIKit.label("Title", "Settings", UDim2.fromOffset(240, 32), UDim2.fromOffset(20, 14), settingsPanel)

local musicButton =
	UIKit.button("Music", "Music: On", UDim2.fromOffset(240, 44), UDim2.fromOffset(20, 56), settingsPanel)
local sfxButton = UIKit.button("Sfx", "SFX: On", UDim2.fromOffset(240, 44), UDim2.fromOffset(20, 108), settingsPanel)
local replayTutorialButton = UIKit.button(
	"ReplayTutorial",
	"Replay Tutorial",
	UDim2.fromOffset(240, 44),
	UDim2.fromOffset(20, 160),
	settingsPanel
)
local settingsCloseButton =
	UIKit.button("Close", "Close", UDim2.fromOffset(240, 40), UDim2.fromOffset(20, 210), settingsPanel)

-- ---------------------------------------------------------------------------
-- Top scores panel (doc 15 item 5)
-- ---------------------------------------------------------------------------
local topPanel = UIKit.panel("TopScores", UDim2.fromOffset(300, 340), UDim2.new(0.5, -150, 0.5, -170), gui)
topPanel.Visible = false
topPanel.ZIndex = 2

UIKit.label("Title", "Top Scores", UDim2.fromOffset(260, 32), UDim2.fromOffset(20, 14), topPanel)
local topCloseButton = UIKit.button("Close", "Close", UDim2.fromOffset(80, 34), UDim2.new(1, -100, 0, 10), topPanel)

local topList = Instance.new("ScrollingFrame")
topList.Name = "List"
topList.Size = UDim2.fromOffset(260, 260)
topList.Position = UDim2.fromOffset(20, 56)
topList.BackgroundTransparency = 1
topList.BorderSizePixel = 0
topList.CanvasSize = UDim2.fromOffset(0, 0)
topList.AutomaticCanvasSize = Enum.AutomaticSize.Y
topList.ScrollBarThickness = 6
topList.Parent = topPanel

local topListLayout = Instance.new("UIListLayout")
topListLayout.SortOrder = Enum.SortOrder.LayoutOrder
topListLayout.Padding = UDim.new(0, 4)
topListLayout.Parent = topList

-- ---------------------------------------------------------------------------
-- Panel switching: exactly one of {mainPanel, endPanel} is visible per
-- RunState; settingsPanel/topPanel float above whichever is showing.
-- ---------------------------------------------------------------------------
local currentRunState = "Menu"
local pendingStart = false -- Replay/Play pressed before the server confirmed Menu yet
local lastSummary: {
	score: number,
	best: number,
	isNewBest: boolean,
	quality: { Perfect: number, Great: number, OK: number },
	bugs: number,
	flys: number,
}? =
	nil

local function focusFirst(button: GuiButton)
	if gamepadActive() then
		GuiService.SelectedObject = button
	end
end

local function showMainMenu()
	title.Visible = true
	mainPanel.Visible = true
	endPanel.Visible = false
	focusFirst(playButton)
end

local function pulseNewBest()
	local original = scoreLine.TextColor3
	scoreLine.TextColor3 = UIKit.GOOD
	local tween = TweenService:Create(scoreLine, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { TextColor3 = original })
	tween:Play()
end

local function pct(part: number, total: number): string
	if total <= 0 then
		return "--"
	end
	return string.format("%d%%", math.floor(part / total * 100 + 0.5))
end

-- doc 15 item 5: HUD.SetGrabStats analog -- Perfect/Great/OK as percentages.
local function showEndPanel()
	local s = lastSummary
	if not s then
		return
	end
	scoreLine.Text = "Score: " .. tostring(s.score) .. (if s.isNewBest then "  NEW BEST!" else "")
	bestLine.Text = "Best: " .. tostring(s.best)
	local total = s.quality.Perfect + s.quality.Great + s.quality.OK
	qualityLine.Text = string.format(
		"Perfect %s  Great %s  OK %s",
		pct(s.quality.Perfect, total),
		pct(s.quality.Great, total),
		pct(s.quality.OK, total)
	)
	statsLine.Text = string.format("Bugs caught: %d   Flys earned: %d", s.bugs, s.flys)
	if s.isNewBest then
		pulseNewBest()
	end

	title.Visible = true
	mainPanel.Visible = false
	endPanel.Visible = true
	focusFirst(replayButton)
end

RunStateChanged.OnClientEvent:Connect(function(state: string)
	currentRunState = state
	if state == "Playing" then
		title.Visible = false
		mainPanel.Visible = false
		endPanel.Visible = false
		settingsPanel.Visible = false
		topPanel.Visible = false
	elseif state == "Dead" then
		showEndPanel()
	elseif state == "Menu" then
		if pendingStart then
			pendingStart = false
			StartRun:FireServer()
		else
			showMainMenu()
		end
	end
end)

RunSummary.OnClientEvent:Connect(
	function(
		score: number,
		best: number,
		isNewBest: boolean,
		quality: { Perfect: number, Great: number, OK: number },
		bugs: number,
		flys: number
	)
		lastSummary = { score = score, best = best, isNewBest = isNewBest, quality = quality, bugs = bugs, flys = flys }
		if currentRunState == "Dead" then
			showEndPanel()
		end
	end
)

-- Play/Replay both want "start as soon as the server says Menu" -- if we're
-- already there, fire immediately; otherwise queue it so the click feels
-- instant even though the server is still finishing the death beat.
local function requestStart()
	if currentRunState == "Menu" then
		StartRun:FireServer()
	else
		pendingStart = true
	end
end

playButton.Activated:Connect(requestStart)
replayButton.Activated:Connect(requestStart)
homeButton.Activated:Connect(function()
	pendingStart = false
	showMainMenu()
end)

-- ---------------------------------------------------------------------------
-- Frogs / Shop (reuse StoreUI's panel, doc 15 item 1/2)
-- ---------------------------------------------------------------------------
local function openStore()
	mainPanel.Visible = false
	endPanel.Visible = false
	openStoreEvent:Fire()
end

frogsButton.Activated:Connect(openStore)
storeClosedEvent.Event:Connect(function()
	if currentRunState == "Menu" then
		showMainMenu()
	elseif currentRunState == "Dead" then
		showEndPanel()
	end
end)

-- ---------------------------------------------------------------------------
-- Settings (doc 15 item 3)
-- ---------------------------------------------------------------------------
local musicOn = true

local function refreshSettingsButtons()
	musicButton.Text = "Music: " .. (if musicOn then "On" else "Off")
	sfxButton.Text = "SFX: " .. (if ClientSettings.sfxOn() then "On" else "Off")
end

ProfileChanged.OnClientEvent:Connect(function(profile: any)
	if profile and typeof(profile.musicOn) == "boolean" then
		musicOn = profile.musicOn
		refreshSettingsButtons()
	end
end)

musicButton.Activated:Connect(function()
	musicOn = not musicOn
	SetMusicOn:FireServer(musicOn)
	refreshSettingsButtons()
end)

sfxButton.Activated:Connect(function()
	ClientSettings.setSfxOn(not ClientSettings.sfxOn())
	refreshSettingsButtons()
end)

replayTutorialButton.Activated:Connect(function()
	ReplayTutorial:FireServer()
	hintLabel.Text = "Tutorial will restart on your next Play"
end)

settingsButton.Activated:Connect(function()
	refreshSettingsButtons()
	settingsPanel.Visible = true
	focusFirst(musicButton)
end)
settingsCloseButton.Activated:Connect(function()
	settingsPanel.Visible = false
end)

-- ---------------------------------------------------------------------------
-- Top scores (doc 15 item 5)
-- ---------------------------------------------------------------------------
local function populateTopScores()
	for _, child in topList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local ok, list = pcall(function()
		return GetTopScores:InvokeServer()
	end)
	if not ok or typeof(list) ~= "table" then
		UIKit.label("Error", "Couldn't load scores", UDim2.fromOffset(240, 28), UDim2.fromOffset(0, 0), topList)
		return
	end
	for i, entry in list :: { any } do
		local row = UIKit.label(
			"Row" .. i,
			string.format("%d. %s — %s", i, tostring(entry.name), tostring(entry.score)),
			UDim2.new(1, 0, 0, 28),
			UDim2.fromOffset(0, 0),
			topList
		)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = i
	end
end

topScoresButton.Activated:Connect(function()
	topPanel.Visible = true
	populateTopScores()
	focusFirst(topCloseButton)
end)
topCloseButton.Activated:Connect(function()
	topPanel.Visible = false
end)

-- ---------------------------------------------------------------------------
-- Gift/Shop prompt on the end-of-run panel (doc 15 item 1, 09-gifts-and-ads.md)
-- ---------------------------------------------------------------------------
local giftReadyAt = math.huge
local giftServerNowAtRecv = 0
local giftClockAtRecv = os.clock()

GiftStatus.OnClientEvent:Connect(function(nextAt: number, now: number)
	giftReadyAt = tonumber(nextAt) or math.huge
	giftServerNowAtRecv = tonumber(now) or 0
	giftClockAtRecv = os.clock()
end)

-- Profiles.Loaded's one-shot GiftStatus push can fire before we've connected
-- above (this script waits on several other LocalScripts' bridges first), so
-- pull the current value directly rather than relying on having caught it.
task.spawn(function()
	local ok, nextAt, now = pcall(function()
		return GetGiftStatus:InvokeServer()
	end)
	if ok and nextAt then
		giftReadyAt = tonumber(nextAt) or giftReadyAt
		giftServerNowAtRecv = tonumber(now) or giftServerNowAtRecv
		giftClockAtRecv = os.clock()
	end
end)

giftPromptButton.Activated:Connect(function()
	local estServerNow = giftServerNowAtRecv + (os.clock() - giftClockAtRecv)
	if estServerNow >= giftReadyAt then
		task.spawn(function()
			ClaimGift:InvokeServer()
		end)
	else
		openStore()
	end
end)

task.spawn(function()
	while true do
		if endPanel.Visible then
			local estServerNow = giftServerNowAtRecv + (os.clock() - giftClockAtRecv)
			local remaining = giftReadyAt - estServerNow
			if remaining <= 0 then
				giftPromptButton.Text = "Claim your gift!"
				giftPromptButton.BackgroundColor3 = UIKit.GOOD
			elseif remaining == remaining and remaining < math.huge then -- finite (guards the brief pre-sync window)
				local mins = math.floor(remaining / 60)
				local secs = math.floor(remaining % 60)
				giftPromptButton.Text = string.format("Next gift in %d:%02d — open Shop", mins, secs)
				giftPromptButton.BackgroundColor3 = UIKit.WARN
			else
				giftPromptButton.Text = "open Shop"
				giftPromptButton.BackgroundColor3 = UIKit.WARN
			end
		end
		task.wait(1)
	end
end)

-- ---------------------------------------------------------------------------
-- Gamepad hint text (doc 15 item 7): show button glyph names as plain text
-- (asset ids are 0 for the real xbox glyph sprites during this phase) only
-- while the last input was a gamepad.
-- ---------------------------------------------------------------------------
local function refreshGamepadHint()
	if gamepadActive() then
		hintLabel.Text = "A: Select   B: Back   D-Pad/Stick: Navigate"
	else
		hintLabel.Text = ""
	end
end
inputState:GetAttributeChangedSignal("Gamepad"):Connect(refreshGamepadHint)
refreshGamepadHint()

gui.Parent = player:WaitForChild("PlayerGui")
showMainMenu()
