-- ReplicatedStorage/Shared/SoundFX (ModuleScript)
-- Tiny one-shot sound player over SoundAssets (the AudioManager.cs Play* analog).
-- SoundFX.play("grab") clones a cached template so rapid triggers overlap instead
-- of cutting each other off. Silent no-op while a clip's id is still 0 in
-- SoundAssets -- safe to call before audio is uploaded.
--
-- PlayForAll semantics note: in Unity, AudioManager.PlayForAll plays through
-- ONE shared AudioSource (Camera.main's), so it's audible to whichever local
-- player(s) that build is rendering for -- effectively "every player this
-- client can see". The Roblox port has no such shared listener: SoundFX.play()
-- always plays for THIS client only (the LocalScript that calls it), because
-- every trigger here comes from a client-scoped signal (a RemoteEvent fired to
-- one player, or a client-local Attribute/state change). There is no
-- play-for-the-whole-server equivalent, nor does the game need one -- every
-- caller in this port already wants "just me".
--
-- No pitch randomization anywhere in the original C# (grepped for `.pitch` /
-- `Random...Pitch` across the whole Unity project -- no hits), so there's
-- nothing to port there; every clip always plays at pitch 1.
--
-- Hardening (doc 16 "SoundFX hardening"):
--   * Per-stem concurrent-clone cap, so a runaway trigger (e.g. mashing taps)
--     can't spawn unbounded Sound instances -- extra calls are dropped rather
--     than queued, matching a one-shot SFX's "fire and forget" feel.
--   * Respects the optional `SfxOn` player Attribute the same way Music.client.luau
--     respects `MusicOn`: nil = on (may not exist yet), explicit false = muted.

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local SoundAssets = require(script.Parent.SoundAssets)

local SoundFX = {}

local MAX_CONCURRENT_PER_STEM = 8

local templates: { [string]: Sound } = {}
local activeCounts: { [string]: number } = {}

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

local function sfxWanted(): boolean
	local player = Players.LocalPlayer
	return player == nil or player:GetAttribute("SfxOn") ~= false -- nil = on (doc contract)
end

function SoundFX.play(stem: string)
	if not sfxWanted() then
		return
	end
	local template = templateFor(stem)
	if not template then
		return -- id not pasted into SoundAssets yet
	end
	local count = activeCounts[stem] or 0
	if count >= MAX_CONCURRENT_PER_STEM then
		return -- too many of this stem already playing -- drop, don't queue
	end
	activeCounts[stem] = count + 1

	local shot = template:Clone()
	shot.Parent = SoundService
	-- One release path for every way a clone stops existing (normal end via
	-- Destroy(), or the Debris safety net below), so the count can never be
	-- double-decremented.
	shot.Destroying:Once(function()
		activeCounts[stem] = math.max((activeCounts[stem] or 1) - 1, 0)
	end)
	shot.Ended:Once(function()
		shot:Destroy()
	end)
	Debris:AddItem(shot, 15) -- safety net if Ended never fires (bad asset id)
	shot:Play()
end

return SoundFX
