--!strict
-- StarterPlayer/StarterPlayerScripts/Client/ui/UIKit (ModuleScript)
-- Small shared GUI-builder + responsiveness helpers for the Phase 5 menu/HUD
-- work (docs/roblox-port/15-menus-and-input.md). Everything here is built in
-- code -- this project's rule is no hand-built Studio UI (Rojo-managed) -- and
-- every visual reads fine with every asset id still 0 (colour/text
-- placeholders only, no image dependency).
--
-- Used by MenuClient, StoreUI, and GameClient's HUD/gamepad bits so the four
-- scripts share one look instead of four slightly-different ones.
--
-- Look: "Lily Pad Pop" from the HotFrog design system -- cream panels and
-- white/lime buttons with a 3px deep-green outline, a hard 5px lip under
-- every button that it sinks onto when pressed, and Fredoka One throughout.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local UIKit = {}

-- Palette (design-system token names in comments). Every text colour here
-- holds 4.5:1 on the fill it is paired with.
UIKit.DARK = Color3.fromRGB(255, 255, 255) -- button: secondary button fill
UIKit.PANEL = Color3.fromRGB(255, 250, 240) -- panel
UIKit.ACCENT = Color3.fromRGB(63, 213, 82) -- accent: the one primary action per screen
UIKit.ACCENT_LIP = Color3.fromRGB(28, 138, 44) -- accent-lip
UIKit.GOOD = Color3.fromRGB(255, 216, 74) -- good: reward ready / celebration
UIKit.WARN = Color3.fromRGB(255, 159, 46) -- warn: waiting / attention
UIKit.TEXT = Color3.fromRGB(14, 59, 24) -- ink: text on panels and on every button fill
UIKit.SUBTEXT = Color3.fromRGB(74, 106, 80) -- ink-muted
UIKit.OUTLINE = Color3.fromRGB(14, 59, 24) -- outline: every UIStroke
UIKit.TITLE = Color3.fromRGB(63, 213, 82) -- title: the HOTFROG wordmark (always stroked)
-- Text drawn straight over the 3D world (HUD) is white/near-white with an
-- OUTLINE stroke instead of ink, since the world behind it can be any colour.
UIKit.HUD_TEXT = Color3.new(1, 1, 1)
UIKit.HUD_SUBTEXT = Color3.fromRGB(216, 245, 220)

UIKit.FONT = Font.fromEnum(Enum.Font.FredokaOne)
UIKit.STROKE = 3 -- stroke-pop
UIKit.LIP = 5 -- space-lip
local BUTTON_RADIUS = 16 -- radius-pop-button
local PANEL_RADIUS = 24 -- radius-pop-panel

local PRESS_DOWN = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_UP = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

function UIKit.corner(parent: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

-- Border outline on a Frame-like object.
function UIKit.outline(parent: GuiObject, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = UIKit.OUTLINE
	s.Thickness = thickness or UIKit.STROKE
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

-- Outline around the glyphs of a TextLabel/TextButton (titles, HUD text over
-- the world). A Contextual stroke fades with the label's TextTransparency.
function UIKit.textStroke(label: GuiObject, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Color = UIKit.OUTLINE
	s.Thickness = thickness or UIKit.STROKE
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = label
	return s
end

-- The lip is the fill's own darker shade: accent-lip under the accent, the
-- outline under white, and a darkened fill under anything else.
local function lipColor(fill: Color3): Color3
	if fill == UIKit.ACCENT then
		return UIKit.ACCENT_LIP
	elseif fill == UIKit.DARK then
		return UIKit.OUTLINE
	end
	return fill:Lerp(UIKit.OUTLINE, 0.45)
end

-- Returns the TextButton callers already expect: they keep setting Text,
-- TextColor3, BackgroundColor3 and Active on it. The button itself is an
-- invisible hit box; what shows is a "Face" frame (fill + outline + label)
-- sitting on a "Lip" frame. Children always draw over their parent under
-- Sibling ZIndexBehavior, so the button's own text/background can't be used
-- -- the properties are mirrored onto the face instead.
function UIKit.button(name: string, text: string, size: UDim2, pos: UDim2, parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = UIKit.DARK
	b.BackgroundTransparency = 1
	b.TextColor3 = UIKit.TEXT
	b.TextTransparency = 1
	b.AutoButtonColor = false
	b.Text = text
	b.Selectable = true -- doc 15 item 7: gamepad/GuiService.SelectedObject navigation

	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.Size = UDim2.new(1, 0, 1, -UIKit.LIP)
	lip.Position = UDim2.fromOffset(0, UIKit.LIP)
	lip.ZIndex = 1
	lip.Parent = b
	UIKit.corner(lip, BUTTON_RADIUS)
	UIKit.outline(lip)

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.Size = UDim2.new(1, 0, 1, -UIKit.LIP)
	face.ZIndex = 2
	face.Parent = b
	UIKit.corner(face, BUTTON_RADIUS)
	UIKit.outline(face)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = UIKit.FONT
	label.TextScaled = true
	label.ZIndex = 3
	label.Parent = face
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = label
	-- Fixed-looking type: TextScaled only shrinks long labels; the cap keeps
	-- neighbouring buttons of one height at one size.
	local sizeCap = Instance.new("UITextSizeConstraint")
	sizeCap.MaxTextSize = math.max(12, math.floor((size.Y.Offset - UIKit.LIP) * 0.5))
	sizeCap.MinTextSize = 8
	sizeCap.Parent = label

	local function syncFill()
		face.BackgroundColor3 = b.BackgroundColor3
		lip.BackgroundColor3 = lipColor(b.BackgroundColor3)
	end
	local function syncText()
		label.Text = string.upper(b.Text)
	end
	local function syncTextColor()
		label.TextColor3 = b.TextColor3
	end
	syncFill()
	syncText()
	syncTextColor()
	b:GetPropertyChangedSignal("BackgroundColor3"):Connect(syncFill)
	b:GetPropertyChangedSignal("Text"):Connect(syncText)
	b:GetPropertyChangedSignal("TextColor3"):Connect(syncTextColor)

	-- Press: the face sinks onto its lip, then springs back.
	local down = false
	local function press(isDown: boolean)
		if down == isDown or (isDown and not b.Active) then
			return
		end
		down = isDown
		local target = if isDown then UDim2.fromOffset(0, UIKit.LIP) else UDim2.new()
		TweenService:Create(face, if isDown then PRESS_DOWN else PRESS_UP, { Position = target }):Play()
	end
	b.MouseButton1Down:Connect(function()
		press(true)
	end)
	b.MouseButton1Up:Connect(function()
		press(false)
	end)
	b.MouseLeave:Connect(function()
		press(false)
	end)

	b.Parent = parent
	return b
end

function UIKit.label(name: string, text: string, size: UDim2, pos: UDim2, parent: Instance): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.TextColor3 = UIKit.TEXT
	l.FontFace = UIKit.FONT
	l.TextScaled = true
	l.Text = text
	l.Parent = parent
	return l
end

function UIKit.panel(name: string, size: UDim2, pos: UDim2, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = UIKit.PANEL
	f.Parent = parent
	UIKit.corner(f, PANEL_RADIUS)
	UIKit.outline(f)
	return f
end

-- A coloured placeholder box for art that isn't uploaded yet (every asset id
-- is 0 during this phase) -- a tinted rectangle reads fine as "a thing is
-- here" without needing any image. `stem` is used only to pick a stable tint.
function UIKit.placeholderThumb(size: UDim2, pos: UDim2, parent: Instance, seed: number): Frame
	local hue = (seed * 0.161803398875) % 1 -- golden-ratio spread so adjacent ids look distinct
	local f = Instance.new("Frame")
	f.Name = "Placeholder"
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = Color3.fromHSV(hue, 0.35, 0.55)
	f.Parent = parent
	UIKit.corner(f, 10)
	return f
end

-- ScreenGui + a UIScale that keeps UI readable across phone portrait and
-- desktop landscape: scale is derived from the viewport's short side against
-- a baseline where the layout was designed to look right (this port's panels
-- assume ~600 UI-space studs across the short side).
local BASELINE_SHORT_SIDE = 600
local MIN_SCALE, MAX_SCALE = 0.55, 1.35

function UIKit.screenGui(name: string): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false -- respect the topbar/notch inset automatically
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- UIKit.button's Lip/Face layering relies on it

	local scale = Instance.new("UIScale")
	scale.Parent = gui

	local function update()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local size = camera.ViewportSize
		local shortSide = math.min(size.X, size.Y)
		if shortSide <= 0 then
			return
		end
		scale.Scale = math.clamp(shortSide / BASELINE_SHORT_SIDE, MIN_SCALE, MAX_SCALE)
	end

	local function hookCamera(camera: Camera?)
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
	end
	hookCamera(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		hookCamera(workspace.CurrentCamera)
		update()
	end)
	update()

	return gui
end

-- Extra top padding equal to the engine's own topbar/safe-area inset, for a
-- panel that sits flush against the top edge (phone notches, the Roblox
-- topbar). `GuiService:GetGuiInset()` returns the same inset ScreenGuis with
-- IgnoreGuiInset=false already avoid, so this is only for content that wants
-- additional breathing room above that line.
function UIKit.safeAreaTopPadding(frame: GuiObject, extra: number?)
	local inset = GuiService:GetGuiInset()
	local pad = frame:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, inset.Y + (extra or 0))
	pad.Parent = frame
end

-- Keep a panel's aspect ratio sane at extreme window shapes (ultra-wide
-- desktop, very tall phone) instead of stretching to fill.
function UIKit.constrainAspect(frame: GuiObject, ratio: number, dominant: Enum.DominantAxis?)
	local c = Instance.new("UIAspectRatioConstraint")
	c.AspectRatio = ratio
	c.DominantAxis = dominant or Enum.DominantAxis.Width
	c.Parent = frame
end

return UIKit
