-- ReplicatedStorage/Shared/SoundFX (ModuleScript)
-- Tiny one-shot sound player over SoundAssets (the AudioManager.cs Play* analog).
-- SoundFX.play("grab") clones a cached template so rapid triggers overlap instead
-- of cutting each other off. Silent no-op while a clip's id is still 0 in
-- SoundAssets -- safe to call before audio is uploaded.

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local SoundAssets = require(script.Parent.SoundAssets)

local SoundFX = {}

local templates: { [string]: Sound } = {}

local function templateFor(stem: string): Sound?
	local cached = templates[stem]
	if cached then
		return cached
	end
	local id = SoundAssets.id(stem)
	if not id then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = stem
	sound.SoundId = id
	sound.Volume = 0.5
	sound.Parent = SoundService
	templates[stem] = sound
	return sound
end

function SoundFX.play(stem: string)
	local template = templateFor(stem)
	if not template then
		return -- id not pasted into SoundAssets yet
	end
	local shot = template:Clone()
	shot.Parent = SoundService
	shot.Ended:Once(function()
		shot:Destroy()
	end)
	Debris:AddItem(shot, 15) -- safety net if Ended never fires (bad asset id)
	shot:Play()
end

return SoundFX
