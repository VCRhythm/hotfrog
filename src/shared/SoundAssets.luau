-- ReplicatedStorage/Shared/SoundAssets (ModuleScript)
-- stem → rbxassetid map for audio, the paste-in point once clips are uploaded to
-- Roblox (same pattern as SkinAssets for images). Value 0 = not uploaded yet
-- (SoundFX treats it as a silent no-op).
--
-- The repo contains NO audio files -- these stems are the clip set named by the
-- original Audio/AudioManager.cs, so this map doubles as the list of sounds to
-- source or recreate.

local Ids: { [string]: number } = {
	-- one-shots (AudioManager.cs fields, minus the "Sound" suffix)
	grab = 73108433873246, -- grabSound: limb grips a step
	crumble = 110518003299500, -- crumbleSound: step destroyed by the lava
	crumbleShort = 100610021589583, -- crumbleShortSound: step explodes / shrugs you off
	fall = 75340992287340, -- fallSound: the frog drops (death beat)
	fly = 83624192055113, -- flySound: a bug buzzes / is collected by a tame bug
	slurp = 129746971606694, -- slurpSound: tongue extends
	squish = 135825820732891, -- squishSound: tongue catches a bug
	awake = 80000324613456, -- awakeSound: frog rises
	miss = 90981200443162, -- missSound: tap hit nothing
	holdOnVoice = 99276810667754, -- holdOnVoiceSound: tutorial "Hold on!"

	-- music (AudioManager crossfades by musicIndex per level)
	music1 = 77652599137287,
	music2 = 135676407745412,
	music3 = 130591680122369,

	-- ==== Auto-added by tools/write_asset_ids.py — keys from tools/asset_manifest.json not yet listed above.
	-- Re-running regenerates this block; hand-organize above the sentinel if you want a key to stay put. ====

	-- one-shots (auto)
	base10 = 138857525055183,
	blink = 120161436532837,
	boilVoice = 78513594088362,
	greatVoice = 111189315835604,
	highScore = 111151171883625,
	hotFrogVO = 87593120929445,
	hurt = 113097634312056,
	leaves = 137434649313793,
	new = 100681368854534,
	okVoice = 116142283148706,
	perfectVoice = 111376508107588,
	pop = 107730930869486,
	select = 94150736478475,
	splash = 99385317094275,

	-- music (auto)
	music4 = 116586551716598,
	music5 = 70897771387242,
}

local SoundAssets = {}

-- Resolve a clip stem to a Roblox sound id string, or nil if not uploaded yet.
function SoundAssets.id(stem: string): string?
	local id = Ids[stem]
	if id and id > 0 then
		return "rbxassetid://" .. id
	end
	return nil
end

return SoundAssets
