-- ReplicatedStorage/Shared/SkinAssets (ModuleScript)
-- name → rbxassetid map for sprite art. This is the paste-in point once art is
-- uploaded to Roblox: the pipeline is /Sprites → /tools (prep + upload_to_catbox)
-- → Ludo (reference) → generated assets → upload to Roblox → ids pasted here.
-- See ../../docs/roblox-port/08-frog-skins-and-store.md and 10-implementation-setup.md.
--
-- Keys are sprite file STEMS — identical to the /Sprites file names and the
-- {name: url} keys printed by tools/upload_to_catbox.py. Value 0 = not uploaded
-- yet (treated as "no texture"). Paste real numeric asset ids in place of 0.
--
-- Seeded with the starter frog (Hot Frog), the shared Universal eye/tongue parts,
-- the step (Rocks) sprites, and key entities (Other). Copy the Hot Frog block per
-- skin, swapping the prefix (e.g. "Blue Frog" → BlueFrog…).
--
-- NOTE (tools/build_manifest.py finding): several skins only ship a handful of
-- sprites (Hawt Frog: Accessory/HandGrab*/Thumbnail only; Space Frog: no Head/
-- Mouth/Eyes; Business Frog & Invisible Man: Arm+Body only). In the original
-- Unity prefabs (HawtFrog.prefab, SpaceFrog.prefab, BusinessFrog.prefab,
-- InvisibleMan.prefab) every part these skins DON'T override falls back to the
-- "Hot Frog" sprite folder, not a shared "Universal" one. Six skins also ship a
-- single `Arm` sprite used for both limbs instead of a LeftLimb/RightLimb pair.
-- SkinAssets.part() below follows that same chain.

local Ids: { [string]: number } = {
	-- Universal (shared across all skins: pupils, sclera, tongue)
	UniversalLeftPupil = 0,
	UniversalRightPupil = 0,
	UniversalLeftSclera = 0,
	UniversalRightSclera = 0,
	UniversalTongue = 0,

	-- Hot Frog (starter) — the rig template. Suffix after the "HotFrog" prefix is
	-- what SkinAssets.part(skinName, suffix) looks up.
	HotFrogBody = 0,
	HotFrogHead = 0,
	HotFrogMouth = 0,
	HotFrogLeftEye = 0,
	HotFrogRightEye = 0,
	HotFrogLowLeftEyelid = 0, -- blink frames (Frog.ShowEyes): Low → Lower → Closed
	HotFrogLowRightEyelid = 0,
	HotFrogLowerLeftEyelid = 0,
	HotFrogLowerRightEyelid = 0,
	HotFrogClosedLeftEyelid = 0,
	HotFrogClosedRightEyelid = 0,
	HotFrogLeftHand = 0,
	HotFrogRightHand = 0,
	HotFrogLeftHandGrab = 0,
	HotFrogRightHandGrab = 0,
	HotFrogLeftLimb = 0,
	HotFrogRightLimb = 0,

	-- Steps (Sprites/Rocks)
	WhiteRock = 0,
	SmallRock = 0,
	CrumblyRock = 0,
	WrappedRock = 0,
	Acorn = 0,
	Carrot = 0,
	Potato = 0,
	Castle = 0,
	Rocket = 0,
	Lillipad = 0,
	UpArrow = 0, -- direction-change steps (doc 05)
	LeftArrow = 0,
	RightArrow = 0,
	UpLeftArrow = 0,
	UpRightArrow = 0,

	-- Entities / scenery (Sprites/Other)
	Bug = 0,
	LavaSplash = 0,
	Sun = 0,
	Grass = 0,
	Cloud = 0,
	Speck = 0,
	Flame = 0, -- Sprites/Scenery/Flame.png: FlingingRock's "Flingee" child (doc 05/12, ActionType.SplashFlinging)

	-- ==== Auto-added by tools/write_asset_ids.py — keys from tools/asset_manifest.json not yet listed above.
	-- Re-running regenerates this block; hand-organize above the sentinel if you want a key to stay put. ====

	-- Steps (auto)
	Balloon = 0,
	CarrotStalk = 0,
	LillipadShadow = 0,
	RockShadow = 0,

	-- Entities (auto)
	Wing1 = 0,
	Wing2 = 0,
	Wing3 = 0,

	-- Scenery (auto)
	Bubble = 0,
	Chef = 0,
	Cloud2 = 0,
	Cloud3 = 0,
	Flame2 = 0,
	Fork = 0,
	Leaf = 0,
	Shelf = 0,
	SplashBackground = 0,
	Spoon = 0,
	Stars = 0,
	Water = 0,
	Window = 0,
	branch2 = 0,
	branch3 = 0,

	-- UI / Menu (auto)
	Arrow = 0,
	ArrowLeft = 0,
	ArrowRight = 0,
	BugIcon = 0,
	Circle = 0,
	FrogHeadIcon = 0,
	GearIcon = 0,
	Home = 0,
	Notes = 0,
	Present = 0,
	ReplayIcon = 0,
	TransparentPixel = 0,
	xboxControllerButtonB = 0,
	xboxControllerButtonX = 0,
	xboxControllerButtonY = 0,
	xboxControllerDPad = 0,
	xboxControllerStart = 0,

	-- Blue Frog (auto)
	BlueFrogBody = 0,
	BlueFrogClosedLeftEyelid = 0,
	BlueFrogClosedRightEyelid = 0,
	BlueFrogHead = 0,
	BlueFrogLeftEye = 0,
	BlueFrogLeftEyelid = 0,
	BlueFrogLeftHand = 0,
	BlueFrogLeftHandGrab = 0,
	BlueFrogLeftLimb = 0,
	BlueFrogLowLeftEyelid = 0,
	BlueFrogLowRightEyelid = 0,
	BlueFrogLowerLeftEyelid = 0,
	BlueFrogLowerRightEyelid = 0,
	BlueFrogMouth = 0,
	BlueFrogRightEye = 0,
	BlueFrogRightEyelid = 0,
	BlueFrogRightHand = 0,
	BlueFrogRightHandGrab = 0,
	BlueFrogRightLimb = 0,

	-- Business Frog (auto)
	BusinessFrogArm = 0,
	BusinessFrogBody = 0,
	BusinessFrogThumbnail = 0,

	-- Crossy Frog (auto)
	CrossyFrogArm = 0,
	CrossyFrogBody = 0,
	CrossyFrogClosedLeftEyelid = 0,
	CrossyFrogClosedRightEyelid = 0,
	CrossyFrogHead = 0,
	CrossyFrogLeftEye = 0,
	CrossyFrogLeftHand = 0,
	CrossyFrogLeftHandGrab = 0,
	CrossyFrogLeftSclera = 0,
	CrossyFrogLowLeftEyelid = 0,
	CrossyFrogLowRightEyelid = 0,
	CrossyFrogLowerLeftEyelid = 0,
	CrossyFrogLowerRightEyelid = 0,
	CrossyFrogMouth = 0,
	CrossyFrogRightEye = 0,
	CrossyFrogRightHand = 0,
	CrossyFrogRightHandGrab = 0,
	CrossyFrogRightSclera = 0,
	CrossyFrogThumbnail = 0,

	-- Hawt Frog (auto)
	HawtFrogAccessory = 0,
	HawtFrogLeftHandGrab = 0,
	HawtFrogLeftHandGrabBack = 0,
	HawtFrogRightHandGrab = 0,
	HawtFrogRightHandGrabBack = 0,
	HawtFrogThumbnail = 0,

	-- Hot Frog (auto)
	HotFrogThumbnail = 0,

	-- Hot Lawyer (auto)
	HotLawyerArm = 0,
	HotLawyerBody = 0,
	HotLawyerClosedLeftEyelid = 0,
	HotLawyerClosedRightEyelid = 0,
	HotLawyerHead = 0,
	HotLawyerLeftEye = 0,
	HotLawyerLeftHand = 0,
	HotLawyerLeftHandGrab = 0,
	HotLawyerLowLeftEyelid = 0,
	HotLawyerLowRightEyelid = 0,
	HotLawyerLowerLeftEyelid = 0,
	HotLawyerLowerRightEyelid = 0,
	HotLawyerMouth = 0,
	HotLawyerRightEye = 0,
	HotLawyerRightHand = 0,
	HotLawyerRightHandGrab = 0,
	HotLawyerThumbnail = 0,

	-- Invisible Man (auto)
	InvisibleManArm = 0,
	InvisibleManBody = 0,
	InvisibleManThumbnail = 0,

	-- Mystery Frog (auto)
	MysteryFrogArm = 0,
	MysteryFrogBody = 0,
	MysteryFrogClosedLeftEyelid = 0,
	MysteryFrogClosedRightEyelid = 0,
	MysteryFrogHead = 0,
	MysteryFrogLeftEye = 0,
	MysteryFrogLeftHand = 0,
	MysteryFrogLeftSclera = 0,
	MysteryFrogLowLeftEyelid = 0,
	MysteryFrogLowRightEyelid = 0,
	MysteryFrogLowerLeftEyelid = 0,
	MysteryFrogLowerRightEyelid = 0,
	MysteryFrogRightEye = 0,
	MysteryFrogRightHand = 0,
	MysteryFrogRightSclera = 0,

	-- Space Frog (auto)
	SpaceFrogAccessory = 0,
	SpaceFrogArm = 0,
	SpaceFrogBody = 0,
	SpaceFrogLeftHand = 0,
	SpaceFrogLeftHandGrab = 0,
	SpaceFrogRightHand = 0,
	SpaceFrogRightHandGrab = 0,
}

local SkinAssets = {}

-- Resolve a sprite stem to a Roblox image string, or nil if not uploaded yet.
function SkinAssets.image(stem: string): string?
	local id = Ids[stem]
	if id and id > 0 then
		return "rbxassetid://" .. id
	end
	return nil
end

-- Skin display name → art prefix, e.g. "Hot Frog" → "HotFrog".
function SkinAssets.prefix(skinName: string): string
	return (skinName:gsub("%s+", ""))
end

-- Texture for a skin's part, e.g. part("Hot Frog", "Body") → "rbxassetid://…".
-- Fallback chain for a part the skin doesn't override, as in the Unity frog
-- prefabs: the skin's own sprite → its single `Arm` sprite (for either limb) →
-- the shared Universal art (pupils/sclera/tongue) → the starter Hot Frog's art.
local FALLBACK_SKIN = "HotFrog"

function SkinAssets.part(skinName: string, suffix: string): string?
	local prefix = SkinAssets.prefix(skinName)
	local own = SkinAssets.image(prefix .. suffix)
	if own then
		return own
	end
	if suffix == "LeftLimb" or suffix == "RightLimb" then
		local arm = SkinAssets.image(prefix .. "Arm")
		if arm then
			return arm
		end
	end
	return SkinAssets.image("Universal" .. suffix) or SkinAssets.image(FALLBACK_SKIN .. suffix)
end

return SkinAssets
