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

local GuiService = game:GetService("GuiService")

local UIKit = {}

UIKit.DARK = Color3.fromRGB(28, 30, 38)
UIKit.PANEL = Color3.fromRGB(40, 43, 54)
UIKit.ACCENT = Color3.fromRGB(96, 170, 255)
UIKit.GOOD = Color3.fromRGB(120, 255, 120)
UIKit.WARN = Color3.fromRGB(255, 196, 96)
UIKit.TEXT = Color3.new(1, 1, 1)
UIKit.SUBTEXT = Color3.fromRGB(180, 188, 200)

function UIKit.corner(parent: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

function UIKit.button(name: string, text: string, size: UDim2, pos: UDim2, parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = UIKit.DARK
	b.TextColor3 = UIKit.TEXT
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.AutoButtonColor = true
	b.Text = text
	b.Selectable = true -- doc 15 item 7: gamepad/GuiService.SelectedObject navigation
	b.Parent = parent
	UIKit.corner(b)
	return b
end

function UIKit.label(name: string, text: string, size: UDim2, pos: UDim2, parent: Instance): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.TextColor3 = UIKit.TEXT
	l.Font = Enum.Font.GothamMedium
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
	f.BackgroundTransparency = 0.05
	f.Parent = parent
	UIKit.corner(f, 12)
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
