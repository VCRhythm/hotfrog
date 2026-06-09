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
-- Falls back to the shared Universal art (pupils/sclera/tongue) when a skin
-- doesn't override that part.
function SkinAssets.part(skinName: string, suffix: string): string?
	return SkinAssets.image(SkinAssets.prefix(skinName) .. suffix) or SkinAssets.image("Universal" .. suffix)
end

return SkinAssets
