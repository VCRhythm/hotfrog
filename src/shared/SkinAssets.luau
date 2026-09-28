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
	UniversalLeftPupil = 130713744298731,
	UniversalRightPupil = 76010823136467,
	UniversalLeftSclera = 110099824119498,
	UniversalRightSclera = 107082618992334,
	UniversalTongue = 78808304089952,

	-- Hot Frog (starter) — the rig template. Suffix after the "HotFrog" prefix is
	-- what SkinAssets.part(skinName, suffix) looks up.
	HotFrogBody = 132401989626297,
	HotFrogHead = 132142912361639,
	HotFrogMouth = 100940722192355,
	HotFrogLeftEye = 125755336287612,
	HotFrogRightEye = 118752971358694,
	HotFrogLowLeftEyelid = 110295333807394, -- blink frames (Frog.ShowEyes): Low → Lower → Closed
	HotFrogLowRightEyelid = 97739190468186,
	HotFrogLowerLeftEyelid = 80672903766924,
	HotFrogLowerRightEyelid = 139252693635147,
	HotFrogClosedLeftEyelid = 99021119325260,
	HotFrogClosedRightEyelid = 114561912405161,
	HotFrogLeftHand = 108926459809188,
	HotFrogRightHand = 78963429892283,
	HotFrogLeftHandGrab = 80581202569266,
	HotFrogRightHandGrab = 132850938803378,
	HotFrogLeftLimb = 95380188138574,
	HotFrogRightLimb = 78051231855006,

	-- Steps (Sprites/Rocks)
	WhiteRock = 122112831042498,
	SmallRock = 139421992156193,
	CrumblyRock = 137772958617395,
	WrappedRock = 72127089026951,
	Acorn = 134301313740006,
	Carrot = 103284618459905,
	Potato = 118771633254775,
	Castle = 74958147013807,
	Rocket = 104644377089306,
	Lillipad = 130120283285514,
	UpArrow = 119570514082046, -- direction-change steps (doc 05)
	LeftArrow = 80584283201618,
	RightArrow = 94306197146989,
	UpLeftArrow = 77306323920266,
	UpRightArrow = 84854723448118,

	-- Entities / scenery (Sprites/Other)
	Bug = 85290005442044,
	LavaSplash = 100787055357003,
	Sun = 98116303973352,
	Grass = 80567955372060,
	Cloud = 112163034837080,
	Speck = 106536633176831,
	Flame = 113699165201277, -- Sprites/Scenery/Flame.png: FlingingRock's "Flingee" child (doc 05/12, ActionType.SplashFlinging)

	-- Background materials (Assets/Materials/*.mat, doc 17 known gap "Background
	-- textures", extracted via the scratchpad's dump_materials.py -- doc 14).
	-- Sky/Water/HeatBackground turned out to be texture-less gradient/colour
	-- shaders (no image to upload), so only the three with a real texture get a
	-- slot here; WorldBackdrop.client.luau hardcodes the other three's extracted
	-- flat colours directly.
	PotBack = 137191232147219, -- Materials/PotBack.mat's _MainTex (Materials/Textures/PotBack.jpg)
	KitchenTile = 101816540430510, -- Materials/KitchenTile.mat's _MainTex (Materials/Textures/KitchenTile.png), tiles 2x2
	LavaGradient = 86027333889312, -- Materials/LavaGradient.mat's _MainTex, converted from Lava_01.tga -- no live Levels.luau key yet
	Water = 93958802404719, -- Sprites/Scenery/Water.png: Entities/Overlay.cs's overlay sprite, tinted from Materials/Water.mat's _Color (doc 14)

	-- UnitedStates.cs's "US" map cutout (doc 11 §3, doc 17 known gap "US map for
	-- Country") -- two independently-tinted layers, see SceneryKinds.luau/
	-- world/WorldScenery.client.luau's createUSPair.
	USRedStates = 135504058949005,
	USBlueStates = 95855031131100,

	-- ==== Auto-added by tools/write_asset_ids.py — keys from tools/asset_manifest.json not yet listed above.
	-- Re-running regenerates this block; hand-organize above the sentinel if you want a key to stay put. ====

	-- Steps (auto)
	Balloon = 104096570008422,
	CarrotStalk = 114500582490557,
	LillipadShadow = 71795008144326,
	PotRim = 140153915656484,
	RockShadow = 72804718225774,

	-- Entities (auto)
	Wing1 = 135317432340005,
	Wing2 = 110207314564549,
	Wing3 = 116756546674515,

	-- Scenery (auto)
	Bubble = 122475533926115,
	Chef = 100516010306829,
	Cloud2 = 91637480695249,
	Cloud3 = 88238728312627,
	Flame2 = 120601151032376,
	Fork = 72640815212719,
	Leaf = 75243070709330,
	Shelf = 120016036483391,
	SplashBackground = 103131700188383,
	Spoon = 138155159194064,
	Stars = 74987867151767,
	Window = 119230480245063,
	branch2 = 79198040649330,
	branch3 = 80825465919031,

	-- UI / Menu (auto)
	Arrow = 133415536045204,
	ArrowLeft = 94255496429324,
	ArrowRight = 103165974471418,
	BugIcon = 71450285340085,
	Circle = 78537555422405,
	FrogHeadIcon = 118803540274400,
	GearIcon = 104513151808081,
	Home = 94236932389609,
	Notes = 119734394649232,
	Present = 112794752006839,
	ReplayIcon = 139466469073938,
	TransparentPixel = 112234950768426,
	xboxControllerButtonB = 139047511847616,
	xboxControllerButtonX = 73072871946286,
	xboxControllerButtonY = 126102902327589,
	xboxControllerDPad = 89401895463506,
	xboxControllerStart = 85169091650591,

	-- Blue Frog (auto)
	BlueFrogBody = 124960144702031,
	BlueFrogClosedLeftEyelid = 102390321224988,
	BlueFrogClosedRightEyelid = 96749871384090,
	BlueFrogHead = 105090763011009,
	BlueFrogLeftEye = 72959705094232,
	BlueFrogLeftEyelid = 84555178499533,
	BlueFrogLeftHand = 118182958385713,
	BlueFrogLeftHandGrab = 137010534031965,
	BlueFrogLeftLimb = 133346209548827,
	BlueFrogLowLeftEyelid = 115265546517868,
	BlueFrogLowRightEyelid = 95766688335042,
	BlueFrogLowerLeftEyelid = 138260914522549,
	BlueFrogLowerRightEyelid = 71234280788019,
	BlueFrogMouth = 106037417321579,
	BlueFrogRightEye = 103085509166259,
	BlueFrogRightEyelid = 108906450668566,
	BlueFrogRightHand = 81522379998972,
	BlueFrogRightHandGrab = 72052974634511,
	BlueFrogRightLimb = 72027218197826,

	-- Business Frog (auto)
	BusinessFrogArm = 137904174701279,
	BusinessFrogBody = 77791361171864,
	BusinessFrogThumbnail = 136308984050605,

	-- Crossy Frog (auto)
	CrossyFrogArm = 85108755866784,
	CrossyFrogBody = 118864402567532,
	CrossyFrogClosedLeftEyelid = 120144461271669,
	CrossyFrogClosedRightEyelid = 91958360789538,
	CrossyFrogHead = 131103490444920,
	CrossyFrogLeftEye = 112115190233191,
	CrossyFrogLeftHand = 75630201135225,
	CrossyFrogLeftHandGrab = 123011594816824,
	CrossyFrogLeftSclera = 124590755010480,
	CrossyFrogLowLeftEyelid = 95343107347278,
	CrossyFrogLowRightEyelid = 77705975030777,
	CrossyFrogLowerLeftEyelid = 103572433140554,
	CrossyFrogLowerRightEyelid = 87255965006828,
	CrossyFrogMouth = 127702188313640,
	CrossyFrogRightEye = 136217468001224,
	CrossyFrogRightHand = 93648462566790,
	CrossyFrogRightHandGrab = 108408790077612,
	CrossyFrogRightSclera = 89344955586120,
	CrossyFrogThumbnail = 100054380994072,

	-- Hawt Frog (auto)
	HawtFrogAccessory = 92072401896151,
	HawtFrogLeftHandGrab = 123218688247261,
	HawtFrogLeftHandGrabBack = 129654776898074,
	HawtFrogRightHandGrab = 84973056236948,
	HawtFrogRightHandGrabBack = 82291578173941,
	HawtFrogThumbnail = 99565840579063,

	-- Hot Frog (auto)
	HotFrogThumbnail = 136773965416772,

	-- Hot Lawyer (auto)
	HotLawyerArm = 104014406121118,
	HotLawyerBody = 91595235773937,
	HotLawyerClosedLeftEyelid = 126332603367546,
	HotLawyerClosedRightEyelid = 134770367999774,
	HotLawyerHead = 90152287198785,
	HotLawyerLeftEye = 80194148060869,
	HotLawyerLeftHand = 80171639109592,
	HotLawyerLeftHandGrab = 126543281589756,
	HotLawyerLowLeftEyelid = 135602896991240,
	HotLawyerLowRightEyelid = 71195408035064,
	HotLawyerLowerLeftEyelid = 115947154107312,
	HotLawyerLowerRightEyelid = 136979691278601,
	HotLawyerMouth = 96781115623077,
	HotLawyerRightEye = 80055344536854,
	HotLawyerRightHand = 120506013836764,
	HotLawyerRightHandGrab = 106727107401265,
	HotLawyerThumbnail = 84459484873946,

	-- Invisible Man (auto)
	InvisibleManArm = 140228321446747,
	InvisibleManBody = 108823295493826,
	InvisibleManThumbnail = 110718601963675,

	-- Mystery Frog (auto)
	MysteryFrogArm = 108643786706477,
	MysteryFrogBody = 123914060104726,
	MysteryFrogClosedLeftEyelid = 74958994690061,
	MysteryFrogClosedRightEyelid = 79842144048993,
	MysteryFrogHead = 116157977875382,
	MysteryFrogLeftEye = 80710668966061,
	MysteryFrogLeftHand = 106876854715083,
	MysteryFrogLeftSclera = 83534784364571,
	MysteryFrogLowLeftEyelid = 100296973794454,
	MysteryFrogLowRightEyelid = 119412383328980,
	MysteryFrogLowerLeftEyelid = 88591943226695,
	MysteryFrogLowerRightEyelid = 81607041311838,
	MysteryFrogRightEye = 117264410952465,
	MysteryFrogRightHand = 85019163384735,
	MysteryFrogRightSclera = 106089418323740,

	-- Space Frog (auto)
	SpaceFrogAccessory = 97689558432795,
	SpaceFrogArm = 126387575532832,
	SpaceFrogBody = 93897124364621,
	SpaceFrogLeftHand = 112453832983221,
	SpaceFrogLeftHandGrab = 70458984446865,
	SpaceFrogRightHand = 136899151708265,
	SpaceFrogRightHandGrab = 107158885449955,
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
