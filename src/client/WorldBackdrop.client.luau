--!strict
-- StarterPlayerScripts/Client/WorldBackdrop (LocalScript)
-- Phase 4 world dressing, item 2: per-level background (Entities/Wall.cs
-- wrap-around tiling scroll), overlay (Entities/Overlay.cs fade), Sun
-- (Entities/Sun.cs + LevelManager's day/night/black states), and the level
-- transition flash -- driven entirely by LevelClient.client.luau's already-
-- exposed `Players.LocalPlayer.LevelState` Attributes/BindableEvent (doc 13
-- item 6), which itself just mirrors the LevelChanged remote.
--
-- Scoped to the LOCAL PLAYER's own lane only (unlike WorldScenery): GameClient's
-- camera (read-only, doc 13 item 6) only ever centres on `myLane`'s origin, so a
-- background/overlay/sun rendered for a neighbouring lane would never be on
-- screen anyway -- duplicating it per lane would be pure waste.
--
-- ADAPTED (background wrap): Wall.cs's real wrap logic juggles three neighbour
-- Transform references across both local axes, a 2D-on-a-3D-plane quirk of the
-- original Unity scene graph that doesn't translate 1:1. This ports the
-- OBSERVABLE behaviour -- a tiled backdrop that scrolls with pulls and wraps
-- seamlessly -- with two tall tiles wrapping along Y (the dominant scroll axis
-- for every level except Country's initial horizontal pull), sized wide enough
-- that X drift never exposes an edge.
--
-- ADAPTED (Sun states): LevelManager's Animator isNight/isBlack bools aren't
-- part of the LevelChanged payload (doc 13's remote list is off-limits for this
-- phase). Night is inferred from the Tutorial level (doc 11 §3: Stars toggle on
-- for the Tutorial's night sequence); black is a brief pulse on a "death"
-- transition, giving all three states an observable trigger.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)

local player = Players.LocalPlayer
local playField = workspace:WaitForChild("PlayField")
local myLane = playField:WaitForChild("Lanes"):WaitForChild(tostring(player.UserId), math.huge) :: Folder

local levelState = player:WaitForChild("LevelState", math.huge) :: Folder
local changed = levelState:WaitForChild("Changed") :: BindableEvent

local function laneOrigin(): Vector3
	local origin = myLane:GetAttribute("Origin")
	return if typeof(origin) == "Vector3" then origin else Vector3.new(0, 0, 0)
end

-- ---------------------------------------------------------------------------
-- Background: two wide tiles wrapping along Y (see header ADAPTED note).
-- ---------------------------------------------------------------------------
local BACKGROUND_COLORS: { [string]: Color3 } = {
	PotBack = Color3.fromRGB(94, 42, 30),
	KitchenTile = Color3.fromRGB(214, 206, 188),
}
local DEFAULT_BACKGROUND_COLOR = Color3.fromRGB(38, 42, 58) -- Sky.mat placeholder

local TILE_HEIGHT = (Config.SPAWN_Y - Config.DESPAWN_Y) + WorldConfig.SCENERY_BOUNDS_MARGIN
local TILE_WIDTH = Config.LANE_HALF_WIDTH * 2 + 40

local function makeBackgroundTile(index: number): BasePart
	local tile = Instance.new("Part")
	tile.Name = "BackgroundTile" .. index
	tile.Size = Vector3.new(TILE_WIDTH, TILE_HEIGHT, 0.2)
	tile.Anchored = true
	tile.CanCollide = false
	tile.CanQuery = false
	tile.Material = Enum.Material.SmoothPlastic
	tile.Color = DEFAULT_BACKGROUND_COLOR
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Front
	decal.Parent = tile
	tile.Parent = workspace
	return tile
end

local bgTiles = { makeBackgroundTile(1), makeBackgroundTile(2) }
local function layoutBackgroundTiles()
	local origin = laneOrigin()
	bgTiles[1].CFrame = CFrame.new(origin.X, origin.Y, Config.PLANE_Z - 5)
	bgTiles[2].CFrame = CFrame.new(origin.X, origin.Y + TILE_HEIGHT, Config.PLANE_Z - 5)
end
layoutBackgroundTiles()

local function setBackground(key: string?)
	local color = if key then (BACKGROUND_COLORS[key] or DEFAULT_BACKGROUND_COLOR) else DEFAULT_BACKGROUND_COLOR
	for _, tile in bgTiles do
		TweenService:Create(tile, TweenInfo.new(WorldConfig.TRANSITION_SOFT_CROSSFADE_TIME), { Color = color }):Play()
	end
end

local function scrollBackground(delta: Vector3)
	local origin = laneOrigin()
	for _, tile in bgTiles do
		tile.Position += delta
	end
	-- wrap: whichever tile has scrolled fully past a bound gets relocated just
	-- beyond the other tile, so the pair always tiles the visible span.
	table.sort(bgTiles, function(a, b)
		return a.Position.Y < b.Position.Y
	end)
	local lower, upper = bgTiles[1], bgTiles[2]
	if upper.Position.Y - origin.Y < Config.SPAWN_Y + TILE_HEIGHT * 0.5 then
		if lower.Position.Y - origin.Y < Config.DESPAWN_Y - TILE_HEIGHT * 0.5 then
			lower.Position = Vector3.new(upper.Position.X, upper.Position.Y + TILE_HEIGHT, upper.Position.Z)
		end
	elseif lower.Position.Y - origin.Y > Config.DESPAWN_Y + TILE_HEIGHT * 0.5 then
		upper.Position = Vector3.new(lower.Position.X, lower.Position.Y - TILE_HEIGHT, lower.Position.Z)
	end
end

-- ---------------------------------------------------------------------------
-- Overlay (Entities/Overlay.cs Fade) -- one layer; overlay2 has no data in this
-- port either (doc 11 §1 note: overlay2Material is never serialized by any
-- level), so there's nothing to render for it.
-- ---------------------------------------------------------------------------
local overlay = Instance.new("Part")
overlay.Name = "LevelOverlay"
overlay.Size = Vector3.new(TILE_WIDTH, TILE_HEIGHT, 0.2)
overlay.Anchored = true
overlay.CanCollide = false
overlay.CanQuery = false
overlay.Material = Enum.Material.SmoothPlastic
overlay.Color = WorldConfig.OVERLAY_COLOR
overlay.Transparency = 1
overlay.Parent = workspace

local function layoutOverlay()
	local origin = laneOrigin()
	overlay.CFrame = CFrame.new(origin.X, origin.Y, Config.PLANE_Z - 3)
end
layoutOverlay()

local function setOverlay(key: string?)
	local target = if key then WorldConfig.OVERLAY_TRANSPARENCY else 1
	TweenService:Create(overlay, TweenInfo.new(WorldConfig.OVERLAY_FADE_TIME), { Transparency = target }):Play()
end

-- ---------------------------------------------------------------------------
-- Sun (Entities/Sun.cs + LevelManager day/night/black -- see header ADAPTED note)
-- ---------------------------------------------------------------------------
local sun = Instance.new("Part")
sun.Name = "Sun"
sun.Shape = Enum.PartType.Ball
sun.Size = Vector3.new(4, 4, 4)
sun.Anchored = true
sun.CanCollide = false
sun.CanQuery = false
sun.Material = Enum.Material.Neon
sun.Color = WorldConfig.SUN_DAY_COLOR
local sunDecal = Instance.new("Decal")
sunDecal.Face = Enum.NormalId.Front
sunDecal:SetAttribute("Sprite", "Sun")
sunDecal.Parent = sun
SpriteSkin.apply(sun)
sun.Parent = workspace

local function layoutSun()
	local origin = laneOrigin()
	sun.CFrame = CFrame.new(origin.X - Config.LANE_HALF_WIDTH * 0.5, Config.SPAWN_Y + 8, Config.PLANE_Z - 4)
end
layoutSun()

local currentSunColor = WorldConfig.SUN_DAY_COLOR
local function setSun(levelName: string)
	currentSunColor = if levelName == "Tutorial" then WorldConfig.SUN_NIGHT_COLOR else WorldConfig.SUN_DAY_COLOR
	TweenService:Create(sun, TweenInfo.new(WorldConfig.SUN_TRANSITION_TIME), { Color = currentSunColor }):Play()
end

local function pulseSunBlack()
	local dark = TweenService:Create(sun, TweenInfo.new(WorldConfig.TRANSITION_DEATH_FLASH_TIME), {
		Color = WorldConfig.SUN_BLACK_COLOR,
	})
	dark.Completed:Once(function()
		TweenService:Create(sun, TweenInfo.new(WorldConfig.SUN_TRANSITION_TIME), { Color = currentSunColor }):Play()
	end)
	dark:Play()
end

-- ---------------------------------------------------------------------------
-- Level transition flash (LevelChanged: "start" | "soft" | "death")
-- ---------------------------------------------------------------------------
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "TransitionFlash"
flashGui.IgnoreGuiInset = true
flashGui.DisplayOrder = 100

local flashFrame = Instance.new("Frame")
flashFrame.Name = "Flash"
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BackgroundColor3 = Color3.new(0, 0, 0)
flashFrame.BackgroundTransparency = 1
flashFrame.BorderSizePixel = 0
flashFrame.Parent = flashGui
flashGui.Parent = player:WaitForChild("PlayerGui")

local function flash(inTime: number, holdTime: number, outTime: number)
	local fadeIn = TweenService:Create(flashFrame, TweenInfo.new(inTime), { BackgroundTransparency = 0 })
	fadeIn.Completed:Once(function()
		task.delay(holdTime, function()
			TweenService:Create(flashFrame, TweenInfo.new(outTime), { BackgroundTransparency = 1 }):Play()
		end)
	end)
	fadeIn:Play()
end

-- ---------------------------------------------------------------------------
-- Drive everything off LevelClient's already-exposed state
-- ---------------------------------------------------------------------------
local function applyLevel(levelName: string, background: string?, overlayKey: string?, transition: string)
	setBackground(background)
	setOverlay(overlayKey)
	setSun(levelName)

	if transition == "death" then
		pulseSunBlack()
		flash(WorldConfig.TRANSITION_DEATH_FLASH_TIME, 0.05, WorldConfig.TRANSITION_DEATH_FLASH_TIME)
	elseif transition == "start" then
		flashFrame.BackgroundTransparency = 0
		TweenService
			:Create(flashFrame, TweenInfo.new(WorldConfig.TRANSITION_START_FADE_TIME), { BackgroundTransparency = 1 })
			:Play()
	end
	-- "soft": setBackground/setOverlay/setSun above already cross-fade (Color3 /
	-- Transparency tweens) instead of popping -- no flash needed.
end

changed.Event:Connect(function(levelName, _musicIndex, background, overlayKey, transition, newOrigin)
	if typeof(newOrigin) == "Vector3" then
		layoutBackgroundTiles()
		layoutOverlay()
		layoutSun()
	end
	applyLevel(levelName, background, overlayKey, transition)
end)

myLane:GetAttributeChangedSignal("PullCount"):Connect(function()
	local delta = myLane:GetAttribute("PullDelta")
	if typeof(delta) == "Vector3" then
		scrollBackground(delta * 0.6) -- background sits further back: slower parallax than scenery
	end
end)

-- Prime from whatever LevelClient already captured before this script started
-- (Attributes persist even if we missed the BindableEvent's first fire).
do
	local levelName = levelState:GetAttribute("LevelName")
	local background = levelState:GetAttribute("Background")
	local overlayKey = levelState:GetAttribute("Overlay")
	if typeof(levelName) == "string" then
		setBackground(if typeof(background) == "string" then background else nil)
		setOverlay(if typeof(overlayKey) == "string" then overlayKey else nil)
		setSun(levelName)
	end
end
