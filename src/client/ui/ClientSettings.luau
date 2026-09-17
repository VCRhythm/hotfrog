--!strict
-- StarterPlayer/StarterPlayerScripts/Client/ui/ClientSettings (ModuleScript)
-- The SFX on/off toggle (docs/roblox-port/15-menus-and-input.md item 3). There
-- is no `profile.sfxOn` field -- Profiles.luau is off-limits for this phase --
-- and Roblox LocalScripts have no persistent client storage (no browser
-- localStorage equivalent), so this is deliberately session-only, in-memory
-- state: "client-side only" per the task, not "persisted across rejoins".
--
-- The flag is mirrored onto the LocalPlayer's `SfxOn` attribute (a client-side
-- attribute write stays local), which Shared/SoundFX checks on every play -- so
-- the toggle silences every caller, not just the ones that ask this module.

local Players = game:GetService("Players")

local ClientSettings = {}

local sfxOn = true
local changed = Instance.new("BindableEvent")
ClientSettings.Changed = changed.Event -- fires (sfxOn: boolean)

function ClientSettings.sfxOn(): boolean
	return sfxOn
end

function ClientSettings.setSfxOn(value: boolean)
	if sfxOn == value then
		return
	end
	sfxOn = value
	Players.LocalPlayer:SetAttribute("SfxOn", value)
	changed:Fire(sfxOn)
end

-- Convenience: play `stem` through the given SoundFX module only if SFX is on.
function ClientSettings.playIfEnabled(soundFX: { play: (stem: string) -> () }, stem: string)
	if sfxOn then
		soundFX.play(stem)
	end
end

return ClientSettings
