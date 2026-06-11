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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkinAssets = require(ReplicatedStorage.Shared.SkinAssets)

local SpriteSkin = {}

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
function SpriteSkin.apply(root: Instance, skinName: string?)
	local targets = root:GetDescendants()
	table.insert(targets, root)
	for _, obj in targets do
		local stem = obj:GetAttribute("Sprite")
		if typeof(stem) == "string" then
			setTexture(obj, SkinAssets.image(stem))
		end
		local suffix = obj:GetAttribute("Suffix")
		if typeof(suffix) == "string" and skinName then
			setTexture(obj, SkinAssets.part(skinName, suffix))
		end
	end
end

return SpriteSkin
