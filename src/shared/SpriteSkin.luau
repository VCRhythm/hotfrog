-- ReplicatedStorage/Shared/SpriteSkin (ModuleScript)
-- Tiny builder that textures parts from SkinAssets via one attribute convention,
-- shared by the frog rig (per-skin) and static art (steps / bug / lava / scenery).
-- See ../../docs/roblox-port/08-frog-skins-and-store.md and 10-implementation-setup.md.
--
-- Set one of these attributes on a Decal/Texture/ImageLabel in your templates:
--   Sprite = "<stem>"   exact sprite stem, skin-agnostic — e.g. "WhiteRock",
--                        "Bug", "LavaSplash", "Sun" (resolved by SkinAssets.image)
--   Suffix = "<suffix>" per-skin frog part — e.g. "Body", "Head", "LeftHandGrab"
--                        (resolved by SkinAssets.part(skinName, suffix))
-- A part with `Suffix` needs a skinName passed to apply(); `Sprite` does not.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkinAssets = require(ReplicatedStorage.Shared.SkinAssets)

local SpriteSkin = {}

local function setTexture(obj: Instance, image: string?)
	if not image then
		return -- leave the authored placeholder when the id isn't uploaded yet
	end
	-- separate branches so each :IsA() narrows obj to the concrete class
	if obj:IsA("Decal") then
		obj.Texture = image
	elseif obj:IsA("Texture") then
		obj.Texture = image
	elseif obj:IsA("ImageLabel") then
		obj.Image = image
	elseif obj:IsA("ImageButton") then
		obj.Image = image
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
