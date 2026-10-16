-- ReplicatedStorage/Shared/SpriteSkin (ModuleScript)
-- Tiny builder that textures parts from SkinAssets via one attribute convention,
-- shared by the frog rig (per-skin) and static art (steps / bug / lava / scenery).
-- See ../../docs/roblox-port/08-frog-skins-and-store.md and 10-implementation-setup.md.
--
-- Set one of these attributes on a Decal/Texture/ImageLabel — or on a BasePart,
-- in which case its child Decals/Textures are textured (handy for steps whose
-- sprite is chosen at spawn time):
--   Sprite = "<stem>"   exact sprite stem, skin-agnostic — e.g. "WhiteRock",
--                        "Bug", "LavaSplash", "Sun" (resolved by SkinAssets.image)
--   Suffix = "<suffix>" per-skin frog part — e.g. "Body", "Head", "LeftHandGrab"
--                        (resolved by SkinAssets.part(skinName, suffix))
-- A part with `Suffix` needs a skinName passed to apply(); `Sprite` does not.
--
-- FACE: the camera sits at +Z looking -Z (GameClient), so a sprite is only
-- visible on a part's `Back` (+Z) face -- Roblox's `Front` is -Z, i.e. facing
-- away. Every Decal/Texture in this port is created with Face = Back. The image
-- reads un-mirrored from the camera there, but the face's U axis runs the other
-- way than on `Front`: a POSITIVE `Texture.OffsetStudsU` slides the image
-- towards -X (screen-left), while a positive `OffsetStudsV` slides it up.
-- (Measured in Studio 2026-09-19; `WorldFrogCosmetics`'s pupils negate U.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkinAssets = require(ReplicatedStorage.Shared.SkinAssets)
local SkinTints = require(ReplicatedStorage.Shared.SkinTints)
local Config = require(ReplicatedStorage.Shared.Config)

local SpriteSkin = {}

-- Halloween costume (b-20261016-123058-9thf; port-only, doc 17): the default
-- skin, in any colourway (Blue swaps its art to "Blue Frog"), wears this hat in
-- its otherwise empty Accessory slot while the Config window is open.
local HALLOWEEN_HAT = "HotFrogHalloweenHat"
local HALLOWEEN_SKINS: { [string]: boolean } = { ["Hot Frog"] = true, ["Blue Frog"] = true }

-- Is today (UTC) inside Config.HALLOWEEN_START..END, or is the test override
-- workspace attribute `ForceHalloween` set?
function SpriteSkin.halloweenLive(): boolean
	if workspace:GetAttribute("ForceHalloween") == true then
		return true
	end
	local now = DateTime.now():ToUniversalTime()
	local today = now.Month * 100 + now.Day
	local first = Config.HALLOWEEN_START.month * 100 + Config.HALLOWEEN_START.day
	local last = Config.HALLOWEEN_END.month * 100 + Config.HALLOWEEN_END.day
	return today >= first and today <= last
end

-- Paint one image-bearing instance (Decal/Texture use .Texture; ImageLabel/
-- ImageButton use .Image). Cast to any for the assignment (a property set on the
-- IsA union isn't expressible), with merged conditions so selene is happy.
local function paint(obj: Instance, image: string)
	if obj:IsA("Decal") or obj:IsA("Texture") then
		local sprite = obj :: any
		sprite.Texture = image
	elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
		local ui = obj :: any
		ui.Image = image
	end
end

local function setTexture(obj: Instance, image: string?)
	if not image then
		return -- leave the authored placeholder when the id isn't uploaded yet
	end
	if obj:IsA("BasePart") then
		-- a tagged part textures the surface decals/textures parented to it
		for _, child in obj:GetChildren() do
			paint(child, image)
		end
	else
		paint(obj, image)
	end
end

-- Texture `root` and its descendants from SkinAssets. Pass a skinName to resolve
-- per-skin `Suffix` parts (the frog rig); omit it for static art (`Sprite` only).
-- `tint` dresses the frog in its tint-ready art (SkinAssets.part) and marks each
-- `Suffix` sprite that got a tint-ready image with `Tinted = true` (cleared
-- otherwise), which is what SkinTints.apply colours. SkinTints.artName returns
-- the (skinName, tint) pair, so `SpriteSkin.apply(model, SkinTints.artName(...))`.
function SpriteSkin.apply(root: Instance, skinName: string?, tint: boolean?)
	local targets = root:GetDescendants()
	table.insert(targets, root)
	for _, obj in targets do
		local stem = obj:GetAttribute("Sprite")
		if typeof(stem) == "string" then
			setTexture(obj, SkinAssets.image(stem))
		end
		local suffix = obj:GetAttribute("Suffix")
		if typeof(suffix) == "string" and skinName then
			-- a silhouette skin (Mystery Frog) lacks its own grab hands: the borrowed Hot
			-- Frog hand is drawn untinted and painted black (SkinTints.apply)
			local silhouette = SkinTints.isSilhouetteSkin(skinName)
				and SkinAssets.image(SkinAssets.prefix(skinName) .. suffix) == nil
				and string.sub(suffix, -4) == "Grab"
			local image, tinted = SkinAssets.part(skinName, suffix, tint and not silhouette)
			obj:SetAttribute("Tinted", if tinted then true else nil)
			obj:SetAttribute("Silhouette", if silhouette then true else nil)
			if suffix == "Accessory" then
				-- skin-specific (sunglasses, helmet): blank when the skin has none, so a
				-- re-skinned rig never keeps the previous skin's accessory
				if not image and HALLOWEEN_SKINS[skinName] and SpriteSkin.halloweenLive() then
					image = SkinAssets.image(HALLOWEEN_HAT)
				end
				image = image or ""
			end
			setTexture(obj, image)
		end
	end
end

return SpriteSkin
