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
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent.ui.UIKit)
local ClientSettings = require(script.Parent.ui.ClientSettings)
local SkinAssets = require(ReplicatedStorage.Shared.SkinAssets)
local SoundFX = require(ReplicatedStorage.Shared.SoundFX)
local JarTiers = require(ReplicatedStorage.Shared.JarTiers)
local Tips = require(ReplicatedStorage.Shared.Tips)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local StartRun = remotes:WaitForChild("StartRun") :: RemoteEvent
local RunStateChanged = remotes:WaitForChild("RunStateChanged") :: RemoteEvent
local RunSummary = remotes:WaitForChild("RunSummary") :: RemoteEvent
local ReturnToMenu = remotes:WaitForChild("ReturnToMenu") :: RemoteEvent
local SetMusicOn = remotes:WaitForChild("SetMusicOn") :: RemoteEvent
local ReplayTutorial = remotes:WaitForChild("ReplayTutorial") :: RemoteEvent
local GetTopScores = remotes:WaitForChild("GetTopScores") :: RemoteFunction
local ProfileChanged = remotes:WaitForChild("ProfileChanged") :: RemoteEvent
local ClaimGift = remotes:WaitForChild("ClaimGift") :: RemoteFunction
local GiftStatus = remotes:WaitForChild("GiftStatus") :: RemoteEvent
local GetGiftStatus = remotes:WaitForChild("GetGiftStatus") :: RemoteFunction
local SetEndPanelOpen = remotes:WaitForChild("SetEndPanelOpen") :: RemoteEvent
local ClaimDailyReward = remotes:WaitForChild("ClaimDailyReward") :: RemoteFunction
local GetMissions = remotes:WaitForChild("GetMissions") :: RemoteFunction
local MissionCompleted = remotes:WaitForChild("MissionCompleted") :: RemoteEvent
local FeedJar = remotes:WaitForChild("FeedJar") :: RemoteFunction
local GetProfile = remotes:WaitForChild("GetProfile") :: RemoteFunction

-- Bridge into StoreUI's existing panel (doc 15: "reuse ... rather than
-- duplicating"). StoreUI creates this Folder; wait for it rather than racing
-- LocalScript load order.
local menuBridge = player:WaitForChild("MenuBridge", math.huge) :: Folder
local openStoreEvent = menuBridge:WaitForChild("OpenStore") :: BindableEvent
local storeClosedEvent = menuBridge:WaitForChild("StoreClosed") :: BindableEvent
-- StoreUI's own persistent bottom-right Shop toggle opens the panel without
-- going through openStoreEvent (that's only fired by our Frogs button), so it
-- needs its own signal to tell us to get out of the way too (b-20260921-152551).
local storeOpenedEvent = menuBridge:WaitForChild("StoreOpened") :: BindableEvent

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

-- b-20261022-132934-sgr2: the title used to carry safeAreaTopPadding inside a
-- 64px TextScaled box, so the top-bar inset (~58px on phones) left a ~6px text
-- area. MenuGui already sits below the inset (IgnoreGuiInset=false), so y is a fixed 8; the box scales with the screen.
local title = UIKit.label("Title", "HOTFROG", UDim2.new(0.7, 0, 0, 56), UDim2.new(0.5, 0, 0, 8), gui)
title.AnchorPoint = Vector2.new(0.5, 0)
title.TextColor3 = UIKit.TITLE
UIKit.textStroke(title)
local titleMax = Instance.new("UISizeConstraint")
titleMax.MaxSize = Vector2.new(360, 56)
titleMax.Parent = title

-- ---------------------------------------------------------------------------
-- Main menu panel (RunState.Menu)
-- ---------------------------------------------------------------------------
local mainPanel = UIKit.panel("MainMenu", UDim2.fromOffset(280, 312), UDim2.new(0.5, -140, 0.5, -156), gui)

local playButton = UIKit.button("Play", "PLAY", UDim2.fromOffset(220, 64), UDim2.fromOffset(30, 24), mainPanel)
playButton.BackgroundColor3 = UIKit.ACCENT

-- Run mode picker (doc 17 "Classic mode"): Normal scrolls only on grabs;
-- Classic keeps the world falling. Sent with StartRun (Play and Replay).
local modeButton = UIKit.button("Mode", "", UDim2.fromOffset(220, 40), UDim2.fromOffset(30, 100), mainPanel)
local frogsButton =
	UIKit.button("Frogs", "Frogs", UDim2.fromOffset(105, 48), UDim2.fromOffset(30, 152), mainPanel, "FrogHeadIcon")
local settingsButton =
	UIKit.button("Settings", "Settings", UDim2.fromOffset(105, 48), UDim2.fromOffset(145, 152), mainPanel, "GearIcon")
local topScoresButton =
	UIKit.button("TopScores", "Top Scores", UDim2.fromOffset(105, 44), UDim2.fromOffset(30, 210), mainPanel, "BugIcon")
local jarButton = UIKit.button("Jar", "Fly Jar", UDim2.fromOffset(105, 44), UDim2.fromOffset(145, 210), mainPanel)
local hintLabel = UIKit.label("Hint", "", UDim2.fromOffset(220, 30), UDim2.fromOffset(30, 262), mainPanel)
hintLabel.TextColor3 = UIKit.SUBTEXT
hintLabel.TextScaled = false
hintLabel.TextSize = 16

-- Daily streak line just under the main panel (DailyService); filled in once
-- the first ClaimDailyReward answer arrives.
local streakLine = UIKit.label("DailyStreak", "", UDim2.fromOffset(280, 28), UDim2.new(0, 0, 1, 16), mainPanel)
streakLine.TextColor3 = UIKit.GOOD
UIKit.textStroke(streakLine, 2)

-- Today's 3 daily missions under the streak line (MissionService); refreshed
-- every time the main menu shows.
local missionLines: { TextLabel } = {}
for i = 1, 3 do
	local line = UIKit.label("Mission" .. i, "", UDim2.fromOffset(280, 24), UDim2.new(0, 0, 1, 20 + i * 26), mainPanel)
	line.TextColor3 = UIKit.HUD_TEXT
	UIKit.textStroke(line, 2)
	missionLines[i] = line
end

-- b-20261010-192455-bshn: the frog rests at the lane origin, which GameClient's
-- camera (FOV 40, a fixed ~31.4-stud vertical view) centres on screen, and its
-- 40-stud head art puts the eyes ~9 studs above centre and the mouth ~4.5 below.
-- A screen-centred panel therefore hides the face, so the panel (plus the streak
-- and mission lines hanging off it) is placed clear of it: to the right of the
-- face in landscape, just under it in portrait. Face half-width and top/bottom
-- are measured from HotFrogHead/Eye/Mouth.png (Hot Frog; other skins match it).
local FACE_HALF_W, FACE_BOTTOM = 8.5, -5 -- studs from the frog origin, +y up (eyes top out ~9)
local VIEW_STUDS = 31.43 -- GameClient: 100 Unity units of vertical view
local PANEL_W, PANEL_H, PANEL_STACK_H = 280, 312, 434 -- panel, and panel + streak + mission lines
local MIN_EFFECTIVE_SCALE = 0.65 -- smallest on-screen scale (UIScale * shrink) the stack may be shrunk to
local function layoutMainPanel()
	local camera = workspace.CurrentCamera
	local guiScale = gui:FindFirstChildOfClass("UIScale")
	if not camera or not guiScale then
		return
	end
	local view = camera.ViewportSize
	if view.X <= 0 or view.Y <= 0 then
		return
	end
	local inset = GuiService:GetGuiInset().Y
	local s = guiScale.Scale
	local fit = player:GetAttribute("CameraFitZoom")
	-- GameClient backs the camera off on viewports narrower than 9:16 (portrait fit)
	local pxPerStud = view.Y / (VIEW_STUDS * (if type(fit) == "number" and fit >= 1 then fit else 1))
	local faceRight = view.X / 2 + FACE_HALF_W * pxPerStud
	local faceBottom = view.Y / 2 - FACE_BOTTOM * pxPerStud
	-- StoreUI's Gift (left, 150 wide) and Shop (right, 120 wide) toggles sit in the
	-- bottom 56 units; stay above them where the stack is over their columns, and
	-- never run off the bottom (a squarish portrait window lets the stack overlap
	-- the mouth rather than leave the screen). GameClient's Spectate strip
	-- (bottom-centre, y -110..-70 units, x +-140 around the centre) is another
	-- bottom obstacle while it is showing (b-20261012-150254-k9vy).
	local spectating = player:GetAttribute("SpectateStripShown") == true
	local function bottomLimit(left: number, w: number): number
		local overToggles = left < (12 + 150) * s - 6 or left + w > view.X - 132 * s + 6
		local limit = view.Y - (if overToggles then 60 else 24) * s
		if spectating and left < view.X / 2 + 140 * s and left + w > view.X / 2 - 140 * s then
			limit = math.min(limit, view.Y - 118 * s)
		end
		return limit
	end
	local k = 1
	local panelW, panelH, stackH = PANEL_W * s, PANEL_H * s, PANEL_STACK_H * s
	local left, top
	if view.X >= view.Y then
		-- landscape: right of the face; if the window is too narrow the panel is
		-- kept on screen and may overlap the face's outer edge instead
		left = math.max(0, math.min((faceRight + view.X - panelW) / 2, view.X - panelW - 8))
		top = (view.Y - panelH) / 2
	else
		-- portrait: no room beside the face, so tuck the stack right under it. If it
		-- doesn't fit between the face and the bottom obstacles, shrink the whole stack
		-- (b-20261012-152031-992y) down to a legible effective scale (s * k >= MIN_EFFECTIVE_SCALE;
		-- phones already at that scale keep k = 1); only past that does it overlap the mouth.
		top = faceBottom + 8
		local room = bottomLimit((view.X - panelW) / 2, panelW) - top
		if room < stackH then
			k = math.clamp(room / stackH, math.min(1, MIN_EFFECTIVE_SCALE / s), 1)
			panelW, panelH, stackH = panelW * k, panelH * k, stackH * k
		end
		left = (view.X - panelW) / 2
	end
	top = math.max(inset, math.min(top, bottomLimit(left, panelW) - stackH))
	-- UIKit.showPanel eases the frame's UIScale to this (default 1); setPanelScale
	-- also retargets a pop-in in flight and applies it to a panel already up.
	UIKit.setPanelScale(mainPanel, k)
	mainPanel.Position = UDim2.fromScale(left / view.X, (top - inset) / (view.Y - inset))
end
task.defer(layoutMainPanel)
player:GetAttributeChangedSignal("SpectateStripShown"):Connect(layoutMainPanel)
player:GetAttributeChangedSignal("CameraFitZoom"):Connect(layoutMainPanel)
-- GameClient shows its Spectate strip only while this panel is up.
mainPanel:GetPropertyChangedSignal("Visible"):Connect(function()
	player:SetAttribute("MainMenuOpen", mainPanel.Visible)
end)
player:SetAttribute("MainMenuOpen", mainPanel.Visible)
do
	local function hook(camera: Camera?)
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				task.defer(layoutMainPanel) -- after UIKit's UIScale has followed the new size
			end)
		end
	end
	hook(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		hook(workspace.CurrentCamera)
		layoutMainPanel()
	end)
end

-- ---------------------------------------------------------------------------
-- End-of-run panel (RunState.Dead)
-- ---------------------------------------------------------------------------
local endPanel = UIKit.panel("EndOfRun", UDim2.fromOffset(320, 496), UDim2.new(0.5, -160, 0.5, -248), gui)
UIKit.showPanel(endPanel, false)

UIKit.label("Title", "Run Over", UDim2.fromOffset(280, 36), UDim2.fromOffset(20, 16), endPanel)
local scoreLine = UIKit.label("Score", "", UDim2.fromOffset(280, 40), UDim2.fromOffset(20, 52), endPanel)
local bestLine = UIKit.label("Best", "", UDim2.fromOffset(280, 26), UDim2.fromOffset(20, 92), endPanel)
bestLine.TextColor3 = UIKit.SUBTEXT

-- b-20260922-073925: was one TextWrapped+TextScaled label ("Perfect 50%  Great
-- 13%  OK 38%") that wrapped mid-phrase ("OK 38%" alone on its own line,
-- unevenly split from the other two) whenever it didn't fit on one line at the
-- scaled font size. Unity keeps these as three separate TextMeshProUGUI
-- elements (MenuManager.cs: perfectCount/greatCount/okCount under
-- QualityCountPanel) rather than one sentence -- do the same here with three
-- fixed-width labels in a row so each is scaled and wrapped independently and
-- the row can never break unevenly.
local qualityRow = Instance.new("Frame")
qualityRow.Name = "Quality"
qualityRow.Size = UDim2.fromOffset(280, 30)
qualityRow.Position = UDim2.fromOffset(20, 132)
qualityRow.BackgroundTransparency = 1
qualityRow.Parent = endPanel
local qualityLayout = Instance.new("UIListLayout")
qualityLayout.FillDirection = Enum.FillDirection.Horizontal
qualityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
qualityLayout.VerticalAlignment = Enum.VerticalAlignment.Center
qualityLayout.Padding = UDim.new(0, 10)
qualityLayout.Parent = qualityRow
local perfectLabel = UIKit.label("Perfect", "", UDim2.fromOffset(90, 30), UDim2.fromOffset(0, 0), qualityRow)
perfectLabel.TextColor3 = UIKit.SUBTEXT
local greatLabel = UIKit.label("Great", "", UDim2.fromOffset(90, 30), UDim2.fromOffset(0, 0), qualityRow)
greatLabel.TextColor3 = UIKit.SUBTEXT
local okLabel = UIKit.label("OK", "", UDim2.fromOffset(90, 30), UDim2.fromOffset(0, 0), qualityRow)
okLabel.TextColor3 = UIKit.SUBTEXT

local statsLine = UIKit.label("Stats", "", UDim2.fromOffset(280, 26), UDim2.fromOffset(20, 176), endPanel)
statsLine.TextColor3 = UIKit.SUBTEXT

local replayButton =
	UIKit.button("Replay", "Replay", UDim2.fromOffset(135, 52), UDim2.fromOffset(20, 214), endPanel, "ReplayIcon")
replayButton.BackgroundColor3 = UIKit.ACCENT
local homeButton = UIKit.button("Home", "Home", UDim2.fromOffset(125, 52), UDim2.fromOffset(165, 214), endPanel, "Home")

-- Gift/Shop prompt (doc 15 item 1: the Unity ad/buy/wait branch reduces to
-- "gift ready -> claim, else show the wait + a Shop button" since ads were
-- dropped by the owner's decision, doc 09).
local giftPromptButton =
	UIKit.button("GiftPrompt", "", UDim2.fromOffset(280, 56), UDim2.fromOffset(20, 278), endPanel, "Present")
giftPromptButton.BackgroundColor3 = UIKit.WARN
-- Leaderboards after every run (b-20261008-124506-tmdz): opens the Top Scores
-- panel on its Today tab.
local endTopScoresButton =
	UIKit.button("TopScores", "Top Scores", UDim2.fromOffset(280, 44), UDim2.fromOffset(20, 344), endPanel, "BugIcon")

-- Tips area (b-20261010-192336-pgwh): one tip per run under a divider, below the
-- buttons so it never overlaps them. Port addition (doc 17); the lines live in
-- Shared/Tips.
local tipsDivider = Instance.new("Frame")
tipsDivider.Name = "TipsDivider"
tipsDivider.Size = UDim2.fromOffset(280, 3)
tipsDivider.Position = UDim2.fromOffset(20, 402)
tipsDivider.BackgroundColor3 = UIKit.SUBTEXT
tipsDivider.BackgroundTransparency = 0.6
tipsDivider.BorderSizePixel = 0
tipsDivider.Parent = endPanel
local tipsHeader = UIKit.label("TipsHeader", "TIP", UDim2.fromOffset(280, 20), UDim2.fromOffset(20, 410), endPanel)
tipsHeader.TextColor3 = UIKit.ACCENT_LIP
local tipLine = UIKit.label("Tip", "", UDim2.fromOffset(280, 52), UDim2.fromOffset(20, 432), endPanel)
tipLine.TextColor3 = UIKit.SUBTEXT
tipLine.TextWrapped = true
local tipSizeCap = Instance.new("UITextSizeConstraint")
tipSizeCap.MaxTextSize = 18
tipSizeCap.Parent = tipLine
local lastTipIndex: number? = nil
local lastTipSummary: unknown = nil -- the run summary the shown tip was picked for

-- ---------------------------------------------------------------------------
-- Settings panel
-- ---------------------------------------------------------------------------
local settingsPanel = UIKit.panel("Settings", UDim2.fromOffset(280, 260), UDim2.new(0.5, -140, 0.5, -130), gui)
UIKit.showPanel(settingsPanel, false)
settingsPanel.ZIndex = 2

UIKit.label("Title", "Settings", UDim2.fromOffset(240, 32), UDim2.fromOffset(20, 14), settingsPanel)

local musicButton =
	UIKit.button("Music", "Music: On", UDim2.fromOffset(240, 44), UDim2.fromOffset(20, 56), settingsPanel, "Notes")
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
UIKit.showPanel(topPanel, false)
topPanel.ZIndex = 2

-- b-20260921-182815: the title used to span the same width as the Close
-- button (both reaching the panel's right edge), so TextScaled rendered
-- "Top Scores" right under/behind "Close" ("Top ScorClose"). Stop the title
-- short of the button instead.
local topTitle = UIKit.label("Title", "Top Scores", UDim2.fromOffset(170, 32), UDim2.fromOffset(20, 14), topPanel)
topTitle.TextXAlignment = Enum.TextXAlignment.Left
local topCloseButton = UIKit.button("Close", "Close", UDim2.fromOffset(80, 34), UDim2.new(1, -100, 0, 10), topPanel)

-- Today / Week / All-time tabs (b-20261008-124506-tmdz). Periods are UTC;
-- see Profiles.periodKeys.
type Board = string -- "daily" | "weekly" | "all" (GetTopScores period)
local TAB_DEFS: { { board: Board, text: string } } = {
	{ board = "daily", text = "Today" },
	{ board = "weekly", text = "Week" },
	{ board = "all", text = "All-time" },
}
local tabButtons: { [string]: TextButton } = {}
for i, def in TAB_DEFS do
	tabButtons[def.board] = UIKit.button(
		"Tab" .. def.text,
		def.text,
		UDim2.fromOffset(82, 32),
		UDim2.fromOffset(20 + (i - 1) * 89, 54),
		topPanel
	)
end

local topList = Instance.new("ScrollingFrame")
topList.Name = "List"
topList.Size = UDim2.fromOffset(260, 226)
topList.Position = UDim2.fromOffset(20, 96)
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
-- Fly Jar panel (b-20261008-142124-qw4r): feed Flys in for good to unlock
-- JarTiers titles. The server (SkinService FeedJar) validates and deducts.
-- ---------------------------------------------------------------------------
local jarPanel = UIKit.panel("FlyJar", UDim2.fromOffset(300, 300), UDim2.new(0.5, -150, 0.5, -150), gui)
UIKit.showPanel(jarPanel, false)
jarPanel.ZIndex = 2

local jarTitleLabel = UIKit.label("Title", "Fly Jar", UDim2.fromOffset(170, 32), UDim2.fromOffset(20, 14), jarPanel)
jarTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
local jarCloseButton = UIKit.button("Close", "Close", UDim2.fromOffset(80, 34), UDim2.new(1, -100, 0, 10), jarPanel)
local jarTotalLine = UIKit.label("Total", "", UDim2.fromOffset(260, 30), UDim2.fromOffset(20, 56), jarPanel)
local jarRankLine = UIKit.label("Rank", "", UDim2.fromOffset(260, 24), UDim2.fromOffset(20, 90), jarPanel)
jarRankLine.TextColor3 = UIKit.ACCENT_LIP
local jarNextLine = UIKit.label("Next", "", UDim2.fromOffset(260, 24), UDim2.fromOffset(20, 118), jarPanel)
jarNextLine.TextColor3 = UIKit.SUBTEXT
local jarBalanceLine = UIKit.label("Balance", "", UDim2.fromOffset(260, 24), UDim2.fromOffset(20, 146), jarPanel)
jarBalanceLine.TextColor3 = UIKit.SUBTEXT
local jarFeedSmall =
	UIKit.button("Feed100", "+100", UDim2.fromOffset(80, 48), UDim2.fromOffset(20, 184), jarPanel, "BugIcon")
local jarFeedBig =
	UIKit.button("Feed1000", "+1000", UDim2.fromOffset(80, 48), UDim2.fromOffset(110, 184), jarPanel, "BugIcon")
local jarFeedAll = UIKit.button("FeedAll", "All", UDim2.fromOffset(80, 48), UDim2.fromOffset(200, 184), jarPanel)
jarFeedAll.BackgroundColor3 = UIKit.WARN
local jarNote = UIKit.label(
	"Note",
	"Flys fed in are gone for good.",
	UDim2.fromOffset(260, 22),
	UDim2.fromOffset(20, 246),
	jarPanel
)
jarNote.TextColor3 = UIKit.SUBTEXT

-- ---------------------------------------------------------------------------
-- Panel switching: exactly one of {mainPanel, endPanel} is visible per
-- RunState; settingsPanel/topPanel float above whichever is showing.
-- ---------------------------------------------------------------------------
local currentRunState = "Menu"
local pendingStart = false -- Replay/Play pressed before the server confirmed Menu yet
local popupOpen = false -- the daily streak popup is up (b-20261016-122217-31q0)
-- doc 15 item 1 / b-20260921-164343: the server flips Dead -> Menu on its own
-- timer (Config.RESPAWN_DELAY) purely to reset the frog/lane for the next
-- run; Unity only swaps to the main menu screen on an explicit player action
-- (Home/Replay), never on a clock. Track whether the player has actually
-- dismissed the end/gift panel so that server-driven Menu transition doesn't
-- yank the end panel away out from under them while they're still reading it.
local endPanelDismissed = true
-- b-20260922-162231: tell the server whenever that flips, so attract mode (the
-- demo climb GameServer runs once RunState flips to Menu) waits for the player
-- to actually dismiss this panel instead of starting under it -- the same
-- Dead -> Menu death-beat timer this flag already exists to survive (comment
-- above) also kicks attract off early.
local function setEndPanelDismissed(dismissed: boolean)
	endPanelDismissed = dismissed
	SetEndPanelOpen:FireServer(not dismissed)
end
local lastSummary: {
	score: number,
	best: number,
	isNewBest: boolean,
	quality: { Perfect: number, Great: number, OK: number },
	bugs: number,
	flys: number,
	steps: number,
}? =
	nil

-- The run mode Play/Replay will ask for (GameServer validates it). Classic is
-- the default (owner's request b-20260921-182325-3jtz), cycled Classic ->
-- Normal -> Tutorial -> Classic. "Tutorial" isn't a scroll mode -- picking it
-- (re)starts the run at the Tutorial level (GameServer.forceTutorial, the same
-- path Settings' "Replay Tutorial" uses, b-20260921-182830-2c73) and plays out
-- as Classic once it's done. This is a per-session choice only (not saved to
-- the profile), so it resets to Classic on a fresh join, per the owner's call
-- that a client-only variable is enough here.
local selectedMode = "Classic"
-- b-20260922-101435: internal mode strings (Config.RUN_MODES, the StartRun
-- payload, the server) stay "Classic"/"Normal"/"Tutorial" -- only the label
-- shown to the player shifts down a notch per the owner's request (Classic
-- reads as the "Normal" difficulty, Normal reads as "Easy").
local modeDisplayNames = { Classic = "Normal", Normal = "Easy" }
local function refreshModeButton()
	modeButton.Text = "Mode: " .. (modeDisplayNames[selectedMode] or selectedMode)
	modeButton.BackgroundColor3 = if selectedMode == "Classic"
		then UIKit.WARN
		elseif selectedMode == "Tutorial" then UIKit.ACCENT
		else UIKit.DARK
end
refreshModeButton()
modeButton.Activated:Connect(function()
	selectedMode = if selectedMode == "Classic"
		then "Normal"
		elseif selectedMode == "Normal" then "Tutorial"
		else "Classic"
	refreshModeButton()
end)

local function focusFirst(button: GuiButton)
	if gamepadActive() then
		GuiService.SelectedObject = button
	end
end

local checkDaily: () -> () = function() end -- assigned in the Daily streak section below
local refreshMissions: () -> () = function() end -- assigned in the Daily missions section below

local function showMainMenu()
	checkDaily()
	refreshMissions()
	title.Visible = true
	UIKit.showPanel(mainPanel, true)
	UIKit.showPanel(endPanel, false)
	focusFirst(playButton)
end

local function pulseNewBest()
	local original = scoreLine.TextColor3
	scoreLine.TextColor3 = UIKit.ACCENT_LIP
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
	-- score includes the Normal-mode combo bonus; best is steps (ruling b426), so
	-- show the run's steps next to it whenever the two differ.
	bestLine.Text = (if s.steps ~= s.score then "Steps: " .. tostring(s.steps) .. "   " else "")
		.. "Best: "
		.. tostring(s.best)
	local total = s.quality.Perfect + s.quality.Great + s.quality.OK
	perfectLabel.Text = "Perfect " .. pct(s.quality.Perfect, total)
	greatLabel.Text = "Great " .. pct(s.quality.Great, total)
	okLabel.Text = "OK " .. pct(s.quality.OK, total)
	statsLine.Text = string.format("Bugs caught: %d   Flys earned: %d", s.bugs, s.flys)
	-- showEndPanel also reruns when a sub-panel closes; only roll a new tip for a new run.
	if lastTipSummary ~= s then
		lastTipSummary = s
		tipLine.Text, lastTipIndex = Tips.pick(lastTipIndex)
	end
	if s.isNewBest then
		pulseNewBest()
	end

	title.Visible = true
	UIKit.showPanel(mainPanel, false)
	UIKit.showPanel(endPanel, true)
	focusFirst(replayButton)
end

-- Any sub-panel (store, settings, top scores) that floats above the Menu/Dead
-- state must hide whichever of {mainPanel, endPanel} is currently showing,
-- and restore it on close -- otherwise the sub-panel either shows behind it
-- (b-20260921-152551) or the main menu bleeds through underneath it
-- (b-20260921-152641).
local function hideMainPanels()
	UIKit.showPanel(mainPanel, false)
	UIKit.showPanel(endPanel, false)
end

local function restoreMainPanels()
	if currentRunState == "Dead" or not endPanelDismissed then
		showEndPanel()
	elseif currentRunState == "Menu" then
		showMainMenu()
	end
end

RunStateChanged.OnClientEvent:Connect(function(state: string)
	local previousState = currentRunState
	currentRunState = state
	if state == "Playing" then
		title.Visible = false
		UIKit.showPanel(mainPanel, false)
		UIKit.showPanel(endPanel, false)
		UIKit.showPanel(settingsPanel, false)
		UIKit.showPanel(topPanel, false)
		UIKit.showPanel(jarPanel, false)
	elseif state == "Dead" then
		setEndPanelDismissed(false)
		showEndPanel()
	elseif state == "Menu" then
		if pendingStart and not popupOpen then
			pendingStart = false
			StartRun:FireServer(selectedMode)
		elseif not (previousState == "Dead" and not endPanelDismissed) then
			showMainMenu()
		end
		-- else: b-20260921-164343: this is the server's own death-beat timer
		-- resetting the lane, not the player asking for the main menu -- leave
		-- the end/gift panel up until Home or Replay is pressed.
	end
end)

RunSummary.OnClientEvent:Connect(
	function(
		score: number,
		best: number,
		isNewBest: boolean,
		quality: { Perfect: number, Great: number, OK: number },
		bugs: number,
		flys: number,
		_cause: string?,
		steps: number?
	)
		lastSummary = {
			score = score,
			best = best,
			isNewBest = isNewBest,
			quality = quality,
			bugs = bugs,
			flys = flys,
			steps = steps or score,
		}
		if currentRunState == "Dead" then
			showEndPanel()
		end
	end
)

-- Play/Replay both want "start as soon as the server says Menu" -- if we're
-- already there, fire immediately; otherwise queue it so the click feels
-- instant even though the server is still finishing the death beat.
local function requestStart()
	-- b-20261016-122217-31q0: no run may start under the daily streak popup.
	if popupOpen then
		return
	end
	if currentRunState == "Menu" then
		StartRun:FireServer(selectedMode)
	else
		pendingStart = true
	end
end

playButton.Activated:Connect(requestStart)
replayButton.Activated:Connect(requestStart)
homeButton.Activated:Connect(function()
	pendingStart = false
	setEndPanelDismissed(true)
	showMainMenu()
end)

-- b-20261017-123801-td2q: Roblox's "Reset Character" (the frog is the avatar, so
-- there is no character to reset) lands the player on the main menu: while
-- Playing the server abandons the run (ReturnToMenu); from the end panel it acts
-- like Home.
local resetRequest = Instance.new("BindableEvent")
resetRequest.Event:Connect(function()
	pendingStart = false
	if currentRunState == "Playing" then
		ReturnToMenu:FireServer()
	elseif not popupOpen then
		setEndPanelDismissed(true)
		showMainMenu()
	end
end)
task.spawn(function()
	for _ = 1, 20 do
		if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", resetRequest) then
			return
		end
		task.wait(0.5)
	end
end)

-- ---------------------------------------------------------------------------
-- Frogs / Shop (reuse StoreUI's panel, doc 15 item 1/2)
-- ---------------------------------------------------------------------------
local function openStore()
	hideMainPanels()
	openStoreEvent:Fire()
end

frogsButton.Activated:Connect(openStore)
storeClosedEvent.Event:Connect(restoreMainPanels)
-- The Shop toggle StoreUI itself renders (bottom-right, visible outside an
-- active run) opens the same panel without going through openStore() above.
storeOpenedEvent.Event:Connect(hideMainPanels)

-- ---------------------------------------------------------------------------
-- Settings (doc 15 item 3)
-- ---------------------------------------------------------------------------
local musicOn = true

local function refreshSettingsButtons()
	musicButton.Text = "Music: " .. (if musicOn then "On" else "Off")
	sfxButton.Text = "SFX: " .. (if ClientSettings.sfxOn() then "On" else "Off")
end

local refreshJar: (profile: any) -> () = function() end -- assigned in the Fly Jar section below

ProfileChanged.OnClientEvent:Connect(function(profile: any)
	if profile and typeof(profile.musicOn) == "boolean" then
		musicOn = profile.musicOn
		refreshSettingsButtons()
	end
	refreshJar(profile)
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
	hideMainPanels()
	UIKit.showPanel(settingsPanel, true)
	focusFirst(musicButton)
end)
settingsCloseButton.Activated:Connect(function()
	UIKit.showPanel(settingsPanel, false)
	restoreMainPanels()
end)

-- ---------------------------------------------------------------------------
-- Top scores (doc 15 item 5)
-- ---------------------------------------------------------------------------
-- Friend lookups are web calls; cache per session (pcall: they can fail).
local friendCache: { [number]: boolean } = {}
local function isFriend(userId: number): boolean
	local cached = friendCache[userId]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return player:IsFriendsWith(userId)
	end)
	local friend = ok and result == true
	friendCache[userId] = friend
	return friend
end

local currentBoard: Board = "daily"
local populateGeneration = 0 -- a slow answer for a tab the player already left is dropped

local function populateTopScores(board: Board)
	currentBoard = board
	populateGeneration += 1
	local generation = populateGeneration
	for b, button in tabButtons do
		button.BackgroundColor3 = if b == board then UIKit.ACCENT else UIKit.DARK
	end
	for _, child in topList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local ok, list = pcall(function()
		return GetTopScores:InvokeServer(board)
	end)
	if generation ~= populateGeneration then
		return
	end
	if not ok or typeof(list) ~= "table" then
		UIKit.label("Error", "Couldn't load scores", UDim2.fromOffset(240, 28), UDim2.fromOffset(0, 0), topList)
		return
	end
	local rows = list :: { any }
	if #rows == 0 then
		UIKit.label("Empty", "No scores yet", UDim2.fromOffset(240, 28), UDim2.fromOffset(0, 0), topList)
		return
	end
	-- Resolve friendship before drawing so highlights don't pop in afterwards.
	local friends: { [number]: boolean } = {}
	for _, entry in rows do
		local userId = tonumber(entry.userId)
		if userId and userId ~= player.UserId then
			friends[userId] = isFriend(userId)
		end
	end
	if generation ~= populateGeneration then
		return
	end
	for i, entry in rows do
		local userId = tonumber(entry.userId) or 0
		local isSelf = userId == player.UserId
		local isFriendRow = friends[userId] == true
		local tag = if isSelf then "  (you)" elseif isFriendRow then "  (friend)" else ""
		-- Fly Jar title (replicated JarTitle attribute), for players in this server
		local inServer = Players:GetPlayerByUserId(userId)
		local jarTitle = if inServer then inServer:GetAttribute("JarTitle") else nil
		local titled = if type(jarTitle) == "string" and jarTitle ~= ""
			then string.format("%s [%s]", tostring(entry.name), jarTitle)
			else tostring(entry.name)
		local row = UIKit.label(
			"Row" .. i,
			string.format("%d. %s — %s%s", i, titled, tostring(entry.score), tag),
			UDim2.new(1, -8, 0, 28),
			UDim2.fromOffset(0, 0),
			topList
		)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = i
		if isSelf or isFriendRow then
			row.BackgroundTransparency = 0.3
			row.BackgroundColor3 = if isSelf then UIKit.ACCENT else UIKit.GOOD
			UIKit.corner(row, 6)
		end
	end
end

for _, def in TAB_DEFS do
	local board = def.board
	tabButtons[board].Activated:Connect(function()
		if board ~= currentBoard then
			populateTopScores(board)
		end
	end)
end

-- Opened from the main menu and from the end-of-run panel; always lands on Today.
local function openTopScores()
	hideMainPanels()
	UIKit.showPanel(topPanel, true)
	focusFirst(topCloseButton)
	populateTopScores("daily")
end

topScoresButton.Activated:Connect(openTopScores)
endTopScoresButton.Activated:Connect(openTopScores)
topCloseButton.Activated:Connect(function()
	populateGeneration += 1
	UIKit.showPanel(topPanel, false)
	restoreMainPanels()
end)

-- ---------------------------------------------------------------------------
-- Fly Jar (b-20261008-142124-qw4r)
-- ---------------------------------------------------------------------------
local jarBalance, jarTotal = 0, 0
local jarBusy = false

local function drawJar()
	jarTotalLine.Text = string.format("In the jar: %d Flys", jarTotal)
	local rankTitle = JarTiers.title(jarTotal)
	jarRankLine.Text = if rankTitle ~= "" then "Title: " .. rankTitle else "No title yet"
	local nextTier = JarTiers.nextTier(jarTotal)
	jarNextLine.Text = if nextTier
		then string.format(
			"Next: %s at %d (%d to go)",
			nextTier.title,
			nextTier.threshold,
			nextTier.threshold - jarTotal
		)
		else "Every title unlocked!"
	jarBalanceLine.Text = string.format("You have %d Flys", jarBalance)
	jarFeedSmall.Active = jarBalance >= 100
	jarFeedBig.Active = jarBalance >= 1000
	jarFeedAll.Active = jarBalance >= 1
	for _, b in { jarFeedSmall, jarFeedBig, jarFeedAll } do
		b.TextColor3 = if b.Active then UIKit.TEXT else UIKit.SUBTEXT
	end
end

refreshJar = function(profile: any)
	if typeof(profile) ~= "table" then
		return
	end
	jarBalance = tonumber(profile.flys) or jarBalance
	jarTotal = tonumber(profile.jarFlys) or jarTotal
	drawJar()
end

local function feed(amount: number)
	if jarBusy or amount < 1 or amount > jarBalance then
		return
	end
	jarBusy = true
	task.spawn(function()
		local ok, fed = pcall(function()
			return FeedJar:InvokeServer(amount)
		end)
		if ok and fed then
			SoundFX.play("pop")
		end
		jarBusy = false -- the new totals arrive through ProfileChanged
	end)
end

jarFeedSmall.Activated:Connect(function()
	feed(100)
end)
jarFeedBig.Activated:Connect(function()
	feed(1000)
end)
jarFeedAll.Activated:Connect(function()
	feed(jarBalance)
end)

jarButton.Activated:Connect(function()
	hideMainPanels()
	drawJar()
	UIKit.showPanel(jarPanel, true)
	focusFirst(jarCloseButton)
	task.spawn(function()
		local ok, profile = pcall(function()
			return GetProfile:InvokeServer()
		end)
		if ok then
			refreshJar(profile)
		end
	end)
end)
jarCloseButton.Activated:Connect(function()
	UIKit.showPanel(jarPanel, false)
	restoreMainPanels()
end)

-- ---------------------------------------------------------------------------
-- Gift/Shop prompt on the end-of-run panel (doc 15 item 1, 09-gifts-and-ads.md)
-- ---------------------------------------------------------------------------
local giftReadyAt = math.huge
local giftServerNowAtRecv = 0
local giftClockAtRecv = os.clock()
-- b-20260922-101723: Unity's MenuManager.GiftFlys hides the end-game panel
-- for the same reason -- the claim's catchable-fly burst (GiftService.server.luau
-- -> BugService) should be visible, not covered. It brings the panel back via
-- SpawnGiftFlys -> Invoke(ShowReturnPanel, 3f); mirror that delay here.
local GIFT_BURST_VISIBLE_SECONDS = 3

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
			local ok, claimed = pcall(function()
				return ClaimGift:InvokeServer()
			end)
			if ok and claimed then
				-- Get out of the way of the fly burst, then bring Replay/Home
				-- back -- unless the player has since left (Home) or started a
				-- new run, same guard restoreMainPanels() already uses for the
				-- Store/Settings/Top Scores sub-panels.
				hideMainPanels()
				task.wait(GIFT_BURST_VISIBLE_SECONDS)
				restoreMainPanels()
			end
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
-- Daily login streak (DailyService, b-20261008-124506-lo4a). Asked every time
-- the main menu shows (cheap; the server answers granted = false after the
-- first claim of a UTC day), so a session that crosses midnight still gets the
-- next day's reward. A grant plays the full-screen reward popup.
-- ---------------------------------------------------------------------------
type DailyResult = { granted: boolean, streak: number, reward: number, rewards: { number } }

local DAILY_RETRIES, DAILY_RETRY_WAIT = 15, 2 -- the profile may still be loading at join
local dailyBusy = false

local function cycleReward(rewards: { number }, streak: number): number
	return rewards[(math.max(streak, 1) - 1) % #rewards + 1]
end

local function refreshStreakLine(r: DailyResult)
	if r.streak <= 0 then
		streakLine.Text = ""
		return
	end
	streakLine.Text =
		string.format("Day %d streak!  Tomorrow: +%d Flys", r.streak, cycleReward(r.rewards, r.streak + 1))
end

-- Confetti: little coloured chips that tumble down past the popup.
local CONFETTI_COLORS = {
	UIKit.ACCENT,
	UIKit.GOOD,
	UIKit.WARN,
	Color3.fromRGB(255, 105, 180),
	Color3.fromRGB(90, 200, 255),
}
local function confetti(parent: GuiObject, count: number)
	for _ = 1, count do
		local chip = Instance.new("Frame")
		chip.Name = "Confetti"
		chip.AnchorPoint = Vector2.new(0.5, 0.5)
		chip.Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22))
		local x = math.random()
		chip.Position = UDim2.new(x, 0, 0, -30)
		chip.Rotation = math.random(0, 360)
		chip.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
		chip.BorderSizePixel = 0
		chip.ZIndex = 3 -- over the popup panel
		chip.Parent = parent
		local fall = 1.6 + math.random() * 1.4
		task.delay(math.random() * 0.6, function()
			local tween =
				TweenService:Create(chip, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.new(x + (math.random() - 0.5) * 0.3, 0, 1, 40),
					Rotation = chip.Rotation + math.random(-540, 540),
				})
			tween.Completed:Connect(function()
				chip:Destroy()
			end)
			tween:Play()
		end)
	end
end

local function showDailyPopup(r: DailyResult)
	if popupOpen then
		return
	end
	popupOpen = true
	-- b-20261016-124204-f68f: the popup cancels a start queued while Dead; Play again after collecting.
	pendingStart = false
	SoundFX.play("highScore")

	-- Full-screen dim layer that also swallows clicks meant for the menu below.
	-- Own ScreenGui (same UIKit scale as MenuGui, so the card scales the same) with
	-- no inset, so the dim reaches the very top and the phone notch/safe area
	-- (b-20261022-132723-mxjm).
	local dimGui = UIKit.screenGui("DailyRewardGui")
	dimGui.IgnoreGuiInset = true
	dimGui.ScreenInsets = Enum.ScreenInsets.None
	-- b-20261016-123559-s03q: above StoreGui (Gift/Shop) and MenuGui, both at 5.
	dimGui.DisplayOrder = 11
	local overlay = Instance.new("TextButton")
	overlay.Name = "DailyReward"
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Selectable = false
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.ZIndex = 20
	overlay.Parent = dimGui
	dimGui.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.4 }):Play()

	-- Spinning sunburst behind the panel. Each bar spins on its own: a
	-- GuiObject's Rotation doesn't carry over to its children.
	local burst = Instance.new("Frame")
	burst.Name = "Burst"
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromOffset(0, 0)
	burst.BackgroundTransparency = 1
	burst.Parent = overlay
	for i = 0, 5 do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Size = UDim2.fromOffset(46, 620)
		ray.Rotation = i * 30
		ray.BackgroundColor3 = UIKit.GOOD
		ray.BackgroundTransparency = 1
		ray.BorderSizePixel = 0
		ray.Parent = burst
		TweenService:Create(ray, TweenInfo.new(0.4), { BackgroundTransparency = 0.55 }):Play()
		TweenService:Create(
			ray,
			TweenInfo.new(12, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1),
			{ Rotation = ray.Rotation + 360 }
		):Play()
	end

	local panel = UIKit.panel("Panel", UDim2.fromOffset(360, 330), UDim2.new(0.5, -180, 0.5, -165), overlay)
	panel.ZIndex = 2 -- over the sunburst
	-- Only the dim area behind the card collects. An Active Frame doesn't stop
	-- the overlay button under it from firing, but a button does: an invisible
	-- one under the card's contents swallows clicks on the card itself.
	local backstop = Instance.new("TextButton")
	backstop.Name = "Backstop"
	backstop.Text = ""
	backstop.AutoButtonColor = false
	backstop.Selectable = false
	backstop.BackgroundTransparency = 1
	backstop.Size = UDim2.fromScale(1, 1)
	backstop.ZIndex = 0
	backstop.Parent = panel
	local pop = Instance.new("UIScale")
	pop.Scale = 0
	pop.Parent = panel
	TweenService:Create(pop, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local heading = UIKit.label("Title", "DAILY STREAK!", UDim2.fromOffset(320, 40), UDim2.fromOffset(20, 14), panel)
	heading.TextColor3 = UIKit.WARN
	UIKit.textStroke(heading)
	local dayLabel = UIKit.label(
		"Day",
		string.format("Day %d", r.streak),
		UDim2.fromOffset(320, 30),
		UDim2.fromOffset(20, 56),
		panel
	)
	dayLabel.TextColor3 = UIKit.SUBTEXT

	-- The 7-day cycle: done days green, today gold and bouncing, the rest white.
	local cycleLen = #r.rewards
	local todayIndex = (math.max(r.streak, 1) - 1) % cycleLen + 1
	local tileW, gap = 42, 4
	local rowX = (360 - (cycleLen * tileW + (cycleLen - 1) * gap)) // 2
	for i, amount in r.rewards do
		local tile = Instance.new("Frame")
		tile.Name = "Day" .. i
		tile.AnchorPoint = Vector2.new(0.5, 0.5)
		tile.Size = UDim2.fromOffset(tileW, 58)
		tile.Position = UDim2.fromOffset(rowX + (i - 1) * (tileW + gap) + tileW // 2, 126)
		tile.BackgroundColor3 = if i < todayIndex
			then UIKit.ACCENT
			elseif i == todayIndex then UIKit.GOOD
			else UIKit.DARK
		tile.Parent = panel
		UIKit.corner(tile, 10)
		UIKit.outline(tile, 2)
		local dayText = UIKit.label("D", "D" .. i, UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 4), tile)
		dayText.TextColor3 = UIKit.SUBTEXT
		UIKit.label("Amount", tostring(amount), UDim2.new(1, -6, 0, 24), UDim2.fromOffset(3, 28), tile)
		local tileScale = Instance.new("UIScale")
		tileScale.Scale = 0
		tileScale.Parent = tile
		task.delay(0.25 + i * 0.07, function()
			SoundFX.play("pop")
			TweenService
				:Create(tileScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
			if i == todayIndex then
				task.wait(0.35)
				TweenService:Create(
					tileScale,
					TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Scale = 1.18 }
				):Play()
			end
		end)
	end

	-- "+N" beside the fly icon, counting up from 0 and then thumping.
	local amountRow = Instance.new("Frame")
	amountRow.Name = "Amount"
	amountRow.AnchorPoint = Vector2.new(0.5, 0.5)
	amountRow.Size = UDim2.fromOffset(240, 60)
	amountRow.Position = UDim2.fromOffset(180, 200)
	amountRow.BackgroundTransparency = 1
	amountRow.Parent = panel
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromOffset(52, 52)
	icon.Position = UDim2.fromOffset(0, 4)
	icon.BackgroundTransparency = 1
	icon.Image = SkinAssets.image("BugIcon") or ""
	icon.Parent = amountRow
	local amountLabel = UIKit.label("Value", "+0", UDim2.fromOffset(180, 60), UDim2.fromOffset(60, 0), amountRow)
	amountLabel.TextColor3 = UIKit.GOOD
	amountLabel.TextXAlignment = Enum.TextXAlignment.Left
	UIKit.textStroke(amountLabel)
	local amountScale = Instance.new("UIScale")
	amountScale.Parent = amountRow
	task.spawn(function()
		task.wait(0.8)
		local start, dur = os.clock(), 0.9
		while overlay.Parent do
			local t = math.min((os.clock() - start) / dur, 1)
			amountLabel.Text = "+" .. tostring(math.floor(r.reward * (1 - (1 - t) ^ 3) + 0.5))
			if t >= 1 then
				break
			end
			task.wait()
		end
		if not overlay.Parent then
			return
		end
		SoundFX.play("pop")
		amountScale.Scale = 1.35
		TweenService
			:Create(amountScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		confetti(overlay, 40)
	end)

	local collect =
		UIKit.button("Collect", "Collect!", UDim2.fromOffset(200, 56), UDim2.fromOffset(80, 254), panel, "Present")
	collect.BackgroundColor3 = UIKit.ACCENT
	focusFirst(collect)
	confetti(overlay, 30)

	-- Collect and a click anywhere on the dim overlay do the same thing
	-- (b-20261016-122217-31q0); `closing` makes a double trigger harmless.
	local closing = false
	local function close()
		if closing then
			return
		end
		closing = true
		SoundFX.play("select")
		TweenService:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
			:Play()
		TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		task.wait(0.25)
		dimGui:Destroy()
		popupOpen = false
		if mainPanel.Visible then
			focusFirst(playButton)
		end
	end
	collect.Activated:Connect(close)
	overlay.Activated:Connect(close)
end

checkDaily = function()
	if dailyBusy then
		return
	end
	dailyBusy = true
	task.spawn(function()
		for _ = 1, DAILY_RETRIES do
			local ok, result = pcall(function()
				return ClaimDailyReward:InvokeServer()
			end)
			if ok and typeof(result) == "table" and typeof(result.streak) == "number" then
				local r = result :: DailyResult
				refreshStreakLine(r)
				-- Already paid server-side; never cover a live run with the popup.
				-- (Home can show the menu while the server still says Dead.)
				if r.granted and currentRunState ~= "Playing" then
					showDailyPopup(r)
				end
				break
			end
			task.wait(DAILY_RETRY_WAIT)
		end
		dailyBusy = false
	end)
end

-- ---------------------------------------------------------------------------
-- Daily missions (MissionService, b-20261008-141702-e0za): the list under the
-- main panel, pulled like the daily streak, plus a short toast whenever the
-- server says one finished (it has already paid the Flys).
-- ---------------------------------------------------------------------------
type MissionInfo = { text: string, progress: number, target: number, reward: number }
local missionsBusy = false

refreshMissions = function()
	if missionsBusy then
		return
	end
	missionsBusy = true
	task.spawn(function()
		for _ = 1, DAILY_RETRIES do
			local ok, result = pcall(function()
				return GetMissions:InvokeServer()
			end)
			if ok and typeof(result) == "table" then
				for i, line in missionLines do
					local m = (result :: { MissionInfo })[i]
					if not m then
						line.Text = ""
					elseif m.progress >= m.target then
						line.Text = string.format("Done: %s", m.text)
						line.TextColor3 = UIKit.GOOD
					else
						line.Text = string.format("%s  %d/%d  +%d", m.text, m.progress, m.target, m.reward)
						line.TextColor3 = UIKit.HUD_TEXT
					end
				end
				break
			end
			task.wait(DAILY_RETRY_WAIT)
		end
		missionsBusy = false
	end)
end

MissionCompleted.OnClientEvent:Connect(function(text: string, reward: number)
	SoundFX.play("pop")
	local toast = UIKit.label(
		"MissionToast",
		string.format("Mission done: %s  +%d Flys", text, reward),
		UDim2.fromOffset(420, 36),
		UDim2.new(0.5, -210, 0.2, 0),
		gui
	)
	toast.TextColor3 = UIKit.GOOD
	toast.ZIndex = 10
	local stroke = UIKit.textStroke(toast, 2)
	task.delay(3, function()
		TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		task.wait(0.5)
		toast:Destroy()
	end)
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
