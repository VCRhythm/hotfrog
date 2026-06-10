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
	grab = 0, -- grabSound: limb grips a step
	crumble = 0, -- crumbleSound: step destroyed by the lava
	crumbleShort = 0, -- crumbleShortSound: step explodes / shrugs you off
	fall = 0, -- fallSound: the frog drops (death beat)
	fly = 0, -- flySound: a bug buzzes / is collected by a tame bug
	slurp = 0, -- slurpSound: tongue extends
	squish = 0, -- squishSound: tongue catches a bug
	awake = 0, -- awakeSound: frog rises
	miss = 0, -- missSound: tap hit nothing
	holdOnVoice = 0, -- holdOnVoiceSound: tutorial "Hold on!"

	-- music (AudioManager crossfades by musicIndex per level)
	music1 = 0,
	music2 = 0,
	music3 = 0,
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
