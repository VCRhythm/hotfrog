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
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local SkinAssets = require(ReplicatedStorage.Shared.SkinAssets)
local Lanes = require(script.Parent.world.Lanes)
local PullScroller = require(script.Parent.world.PullScroller)

local player = Players.LocalPlayer
local lane = Lanes.waitForLocal()
local levelStateInstance = player:WaitForChild("LevelState", WorldConfig.LANE_WAIT_TIMEOUT)
if not (lane and levelStateInstance) then
	warn("[WorldBackdrop] lane or LevelState never appeared; backdrop is disabled")
	return
end
local myLane: Folder = lane
local levelState = levelStateInstance
local changed = levelState:WaitForChild("Changed", WorldConfig.LANE_WAIT_TIMEOUT) :: BindableEvent

-- Journey 4/8 (b-20260923-154344-xac3): tracked so the heat-modulation
-- PreRender update below (see its own header comment, near the bottom of this file)
-- knows what level/keys it's blending from and never fights the crossfade
-- tweens setBackground/setOverlay/setSun below kick off on every transition.
local currentLevelName: string? = nil
local currentBackgroundKey: string? = nil
local currentOverlayKey: string? = nil
local transitioning = false
local function gateTransition(duration: number)
	transitioning = true
	task.delay(duration, function()
		transitioning = false
	end)
end

local function laneOrigin(): Vector3
	return Lanes.originOf(myLane)
end

-- ---------------------------------------------------------------------------
-- Background: two wide tiles wrapping along Y (see header ADAPTED note).
--
-- Colours/textures below are extracted straight from the Unity project's
-- Assets/Materials/*.mat (dump_materials.py against the scratchpad's UnityPy
-- venv, doc 14 "Background materials" section — not guessed):
--   PotBack.mat / KitchenTile.mat -- real textures (Materials/Textures/
--     PotBack.jpg, KitchenTile.png), plain Sprites-Diffuse-style shader,
--     _Color=white (no tint). `PotBack`/`KitchenTile` below are the average
--     pixel colour of each texture (Pillow), used only while the id is still
--     0 -- SkinAssets.image() below wins once art is uploaded.
--   Sky.mat -- texture-less (_MainTex unset), _Color=(0.609,1,1,1): the
--     DEFAULT_BACKGROUND_COLOR fallback for `background = nil` levels.
--   LavaGradient.mat -- also a real texture (Materials/Textures/Lava_01.tga,
--     converted to PNG by build_manifest.py) but not referenced by any
--     Levels.luau `background` key yet -- kept here so it lights up the
--     moment a level does (same "kept complete" pattern SceneryKinds.luau
--     already uses for the unreachable Menu level).
-- ---------------------------------------------------------------------------
local BACKGROUND_COLORS: { [string]: Color3 } = {
	PotBack = Color3.fromRGB(197, 197, 195),
	KitchenTile = Color3.fromRGB(220, 216, 209),
	LavaGradient = Color3.fromRGB(199, 69, 3),
}
local DEFAULT_BACKGROUND_COLOR = Color3.fromRGB(155, 255, 255) -- Sky.mat's own _Color

local TILE_HEIGHT = (Config.SPAWN_Y - Config.DESPAWN_Y) + WorldConfig.SCENERY_BOUNDS_MARGIN
-- Mutable: widened by refitWidth() below when the viewport is wider than the lane
-- (b-20261010-191320-w7pp: ultrawide windows saw past a fixed-width backdrop).
local BASE_WIDTH = Config.LANE_HALF_WIDTH * 2 + WorldConfig.BACKDROP_EXTRA_WIDTH -- original tile width: art repeat size
local TILE_WIDTH = BASE_WIDTH
local visibleWidth = Config.LANE_HALF_WIDTH * 2
-- GameClient's CAMERA_DISTANCE and FieldOfView (camera is Scriptable, FOV 40).
local BACKDROP_CAMERA_DISTANCE = 43.2
local BACKDROP_CAMERA_FOV = 40

-- StudsPerTileU/V for the Texture instance below, derived from each
-- material's _MainTex tiling `scale` (dump_materials.py's tex_env dump):
-- PotBack.mat scale=(1,1) -> one full image spans the whole tile; KitchenTile.mat
-- scale=(2,2) -> the pattern repeats twice across each axis. LavaGradient.mat's
-- only tiling knob (`_MainTexTile`) is a custom shader float, not a portable
-- Material tiling vector, so it renders untiled (fills once) like PotBack.
local function tilingFor(key: string?): (number, number)
	if key == "KitchenTile" then
		return BASE_WIDTH / 2, TILE_HEIGHT / 2
	end
	-- Single-image art keeps its original 84 x TILE_HEIGHT stud size and simply
	-- repeats horizontally across a wider tile (no stretching).
	return BASE_WIDTH, TILE_HEIGHT
end

-- A Texture tiles from its face's corner, so widening a part about its centre moves
-- the corner by (width - BASE_WIDTH) / 2. On the Back (+Z) face U runs along +X (seen
-- from the camera at +Z) and the corner is the -X edge, so the art would shift by that
-- amount relative to the old BASE_WIDTH layout. Shifting the texture by the same
-- amount along +U (mod the repeat) keeps the lane-centre art where it always was.
local function centreOffsetU(studsPerTileU: number): number
	return ((TILE_WIDTH - BASE_WIDTH) / 2) % studsPerTileU
end

local function makeBackgroundTile(index: number): BasePart
	local tile = Instance.new("Part")
	tile.Name = "BackgroundTile" .. index
	tile.Size = Vector3.new(TILE_WIDTH, TILE_HEIGHT, WorldConfig.BACKDROP_TILE_THICKNESS)
	tile.Anchored = true
	tile.CanCollide = false
	tile.CanQuery = false
	tile.Material = Enum.Material.SmoothPlastic
	tile.Color = DEFAULT_BACKGROUND_COLOR
	-- Texture (not Decal): only Texture exposes StudsPerTileU/V, needed for
	-- KitchenTile's real 2x2 tiling (see BACKGROUND_TILING above). Left with an
	-- empty .Texture until setBackground() resolves an id -- the part's own
	-- Color (tweened below) shows through as the flat-colour fallback, same
	-- convention SpriteSkin.apply/id=0 use everywhere else in this port.
	local texture = Instance.new("Texture")
	texture.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
	texture.StudsPerTileU = BASE_WIDTH
	texture.StudsPerTileV = TILE_HEIGHT
	texture.Parent = tile
	tile.Parent = workspace
	return tile
end

local bgTiles = { makeBackgroundTile(1), makeBackgroundTile(2) }
local function layoutBackgroundTiles()
	local origin = laneOrigin()
	bgTiles[1].CFrame = CFrame.new(origin.X, origin.Y, Config.PLANE_Z + WorldConfig.BACKDROP_DEPTH)
	bgTiles[2].CFrame = CFrame.new(origin.X, origin.Y + TILE_HEIGHT, Config.PLANE_Z + WorldConfig.BACKDROP_DEPTH)
end
layoutBackgroundTiles()

local function setBackground(key: string?)
	local color = if key then (BACKGROUND_COLORS[key] or DEFAULT_BACKGROUND_COLOR) else DEFAULT_BACKGROUND_COLOR
	local image = if key then SkinAssets.image(key) else nil -- nil until the id is uploaded (SkinAssets convention)
	for _, tile in bgTiles do
		TweenService:Create(tile, TweenInfo.new(WorldConfig.TRANSITION_SOFT_CROSSFADE_TIME), { Color = color }):Play()
		local texture = tile:FindFirstChildOfClass("Texture") :: Texture
		texture.StudsPerTileU, texture.StudsPerTileV = tilingFor(key)
		texture.OffsetStudsU = centreOffsetU(texture.StudsPerTileU)
		texture.Texture = image or "" -- "" leaves the tweened flat Color visible (fallback)
	end
end

-- X has no neighbour grid like Wall.cs's wallToLeft/wallToRight (only one
-- column of tiles, stacked along Y) -- so instead of relocating a tile past its
-- neighbour, X is simply re-zeroed back onto the origin once it's drifted
-- through half of the tile's spare width (TILE_WIDTH's own margin beyond the
-- lane, see its definition above), well before a drifted edge could reach the
-- camera. Matches Wall.cs's own snap-back-on-bound shape without needing a
-- second axis of tiles.
local function xDriftLimit(): number
	return (TILE_WIDTH - visibleWidth) / 2
end

local function scrollBackground(delta: Vector3)
	if delta.X == 0 and delta.Y == 0 then
		return
	end
	local origin = laneOrigin()
	for _, tile in bgTiles do
		tile.Position += delta
	end
	if math.abs(bgTiles[1].Position.X - origin.X) > xDriftLimit() then
		for _, tile in bgTiles do
			tile.Position = Vector3.new(origin.X, tile.Position.Y, tile.Position.Z)
		end
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
--
-- Water.mat is the only overlay key any level actually sets (Tutorial/Pot,
-- "overlay = Water" in Levels.luau). Its own _MainTex is a third-party paid
-- asset-pack texture (First Fantasy for Mobile's Water_01.tga) that isn't in
-- this project and can't be exported -- but Sprites/Scenery/Water.png (already
-- a SkinAssets stem, doc 14) is this same overlay's actual sprite art, so
-- that's used as the Texture below once uploaded. OVERLAY_COLORS.Water is
-- Water.mat's own extracted _Color (dump_materials.py) -- an orange/red
-- "boiling" tint -- replacing WorldConfig.OVERLAY_COLOR's guessed blue as the
-- flat-colour fallback while the id is still 0.
-- ---------------------------------------------------------------------------
local OVERLAY_COLORS: { [string]: Color3 } = {
	Water = Color3.fromRGB(255, 69, 0),
}

local overlay = Instance.new("Part")
overlay.Name = "LevelOverlay"
overlay.Size = Vector3.new(TILE_WIDTH, TILE_HEIGHT, WorldConfig.BACKDROP_TILE_THICKNESS)
overlay.Anchored = true
overlay.CanCollide = false
overlay.CanQuery = false
overlay.Material = Enum.Material.SmoothPlastic
overlay.Color = WorldConfig.OVERLAY_COLOR
overlay.Transparency = 1
local overlayTexture = Instance.new("Texture")
overlayTexture.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
overlayTexture.StudsPerTileU = BASE_WIDTH
overlayTexture.StudsPerTileV = TILE_HEIGHT
overlayTexture.Parent = overlay
overlay.Parent = workspace

local function layoutOverlay()
	local origin = laneOrigin()
	overlay.CFrame = CFrame.new(origin.X, origin.Y, Config.PLANE_Z + WorldConfig.OVERLAY_DEPTH)
end
layoutOverlay()

-- Widen tiles + overlay so the camera's visible width at the backdrop's depth
-- (plus the arrival zoom-out and the drift spare) is always covered.
local function refitWidth()
	local camera = workspace.CurrentCamera
	if not camera or camera.ViewportSize.Y <= 0 then
		return
	end
	local viewport = camera.ViewportSize
	local distance = BACKDROP_CAMERA_DISTANCE * WorldConfig.ARRIVAL_CAMERA_ZOOM + math.abs(WorldConfig.BACKDROP_DEPTH)
	visibleWidth = math.max(
		Config.LANE_HALF_WIDTH * 2,
		2 * distance * math.tan(math.rad(BACKDROP_CAMERA_FOV / 2)) * (viewport.X / viewport.Y)
	)
	TILE_WIDTH = math.max(
		Config.LANE_HALF_WIDTH * 2 + WorldConfig.BACKDROP_EXTRA_WIDTH,
		visibleWidth + WorldConfig.BACKDROP_EXTRA_WIDTH
	)
	for _, tile in bgTiles do
		tile.Size = Vector3.new(TILE_WIDTH, TILE_HEIGHT, WorldConfig.BACKDROP_TILE_THICKNESS)
		local texture = tile:FindFirstChildOfClass("Texture") :: Texture
		texture.StudsPerTileU, texture.StudsPerTileV = tilingFor(currentBackgroundKey)
		texture.OffsetStudsU = centreOffsetU(texture.StudsPerTileU)
	end
	overlay.Size = Vector3.new(TILE_WIDTH, TILE_HEIGHT, WorldConfig.BACKDROP_TILE_THICKNESS)
	overlayTexture.StudsPerTileU = BASE_WIDTH
	overlayTexture.OffsetStudsU = centreOffsetU(BASE_WIDTH)
end
refitWidth()
do
	local viewportConn: RBXScriptConnection? = nil
	local function watchCamera()
		if viewportConn then
			viewportConn:Disconnect()
			viewportConn = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refitWidth)
		end
	end
	watchCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watchCamera()
		refitWidth()
	end)
end

local function setOverlay(key: string?)
	local target = if key then WorldConfig.OVERLAY_TRANSPARENCY else 1
	local color = if key then (OVERLAY_COLORS[key] or WorldConfig.OVERLAY_COLOR) else WorldConfig.OVERLAY_COLOR
	TweenService:Create(overlay, TweenInfo.new(WorldConfig.OVERLAY_FADE_TIME), { Transparency = target, Color = color })
		:Play()
	overlayTexture.Texture = (key and SkinAssets.image(key)) or ""
end

-- ---------------------------------------------------------------------------
-- Sun (Entities/Sun.cs + LevelManager day/night/black -- see header ADAPTED note)
-- ---------------------------------------------------------------------------
local sun = Instance.new("Part")
sun.Name = "Sun"
sun.Shape = Enum.PartType.Ball
sun.Size = Vector3.one * WorldConfig.SUN_SIZE
sun.Anchored = true
sun.CanCollide = false
sun.CanQuery = false
sun.Material = Enum.Material.Neon
sun.Color = WorldConfig.SUN_DAY_COLOR
local sunDecal = Instance.new("Decal")
sunDecal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
sunDecal:SetAttribute("Sprite", "Sun")
sunDecal.Parent = sun
SpriteSkin.apply(sun)
sun.Parent = workspace

local function layoutSun()
	local origin = laneOrigin()
	sun.CFrame = CFrame.new(
		origin.X + Config.LANE_HALF_WIDTH * WorldConfig.SUN_X_FRACTION,
		Config.SPAWN_Y + WorldConfig.SUN_Y_ABOVE_SPAWN,
		Config.PLANE_Z + WorldConfig.SUN_DEPTH
	)
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
	currentLevelName = levelName
	currentBackgroundKey = background
	currentOverlayKey = overlayKey
	gateTransition(
		math.max(
			WorldConfig.TRANSITION_SOFT_CROSSFADE_TIME,
			WorldConfig.OVERLAY_FADE_TIME,
			WorldConfig.SUN_TRANSITION_TIME
		)
	)

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

-- The same eased, additive pull the scenery uses (world/PullScroller: Sine/Out over
-- PullTime, matching the server's own pull), integrated once per frame -- the
-- backdrop used to step by the whole PullDelta the instant a grab landed while the
-- scenery eased in. It sits further back, hence the slower parallax.
local pullScroller = PullScroller.new(myLane)
RunService.PreRender:Connect(function(dt: number)
	scrollBackground(pullScroller:step(dt) * WorldConfig.BACKDROP_PARALLAX)
end)

-- ---------------------------------------------------------------------------
-- Pot heat build-up (journey 4/8, b-20260923-154344-xac3): reads the 0..1
-- scalar WorldLava.client.luau publishes on this same levelState folder
-- (proximity to the lava and/or time since the local frog's last grab --
-- "standing still should feel like boiling") and layers it onto the Water
-- overlay's opacity and the backdrop tiles' warm tint. Applied as a direct
-- per-frame property write, kept separate from setBackground/setOverlay's
-- own TweenService tweens above, and only once `transitioning` is clear (see
-- gateTransition) so the two never fight over the same Transparency/Color
-- properties -- heat itself is already smoothed (WorldConfig.
-- LAVA_HEAT_LERP_RATE), so no tween is needed here. Kitchen (and everywhere
-- else) gets none of this: levelName ~= "Pot" holds heat's own target at 0 in
-- WorldLava, and this gate stops applying it the instant the level changes,
-- so arriving in Kitchen reads as immediate relief rather than a lingering
-- flush.
-- ---------------------------------------------------------------------------
RunService.PreRender:Connect(function()
	if transitioning or currentLevelName ~= "Pot" then
		return
	end
	local heat = levelState:GetAttribute("PotHeat")
	if typeof(heat) ~= "number" or heat <= 0 then
		return
	end

	if currentOverlayKey then
		local baseTransparency = WorldConfig.OVERLAY_TRANSPARENCY
		overlay.Transparency = baseTransparency
			+ (WorldConfig.LAVA_HEAT_OVERLAY_TRANSPARENCY_MIN - baseTransparency) * heat
	end

	local baseColor = if currentBackgroundKey
		then (BACKGROUND_COLORS[currentBackgroundKey] or DEFAULT_BACKGROUND_COLOR)
		else DEFAULT_BACKGROUND_COLOR
	local warmColor =
		baseColor:Lerp(WorldConfig.LAVA_HEAT_BACKDROP_COLOR, heat * WorldConfig.LAVA_HEAT_BACKDROP_MAX_MIX)
	for _, tile in bgTiles do
		tile.Color = warmColor
	end
end)

-- Prime from whatever LevelClient already captured before this script started
-- (Attributes persist even if we missed the BindableEvent's first fire).
do
	local levelName = levelState:GetAttribute("LevelName")
	local background = levelState:GetAttribute("Background")
	local overlayKey = levelState:GetAttribute("Overlay")
	if typeof(levelName) == "string" then
		currentLevelName = levelName
		currentBackgroundKey = if typeof(background) == "string" then background else nil
		currentOverlayKey = if typeof(overlayKey) == "string" then overlayKey else nil
		gateTransition(
			math.max(
				WorldConfig.TRANSITION_SOFT_CROSSFADE_TIME,
				WorldConfig.OVERLAY_FADE_TIME,
				WorldConfig.SUN_TRANSITION_TIME
			)
		)
		setBackground(currentBackgroundKey)
		setOverlay(currentOverlayKey)
		setSun(levelName)
	end
end
