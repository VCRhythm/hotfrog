--!strict
-- StarterPlayer/StarterPlayerScripts/Ambience (LocalScript)
-- Ambient loop under the music (journey 8/8, b-20260923-154345-78ng). OWNER'S
-- FEATURE, not a Unity port: the original has no ambience. The loops are
-- generated with the Ludo AI CLI (Sounds/Ambience/, uploaded by the tools/
-- asset pipeline like every other clip):
--
--   level     SoundAssets stem
--   Pot       potBubbling      (louder at the bottom height stage, near the lava)
--   Kitchen   kitchenRoomTone
--   other     silence
--
-- Built like Music.client.luau: looped Sounds under SoundService, keyed on the
-- local player's level from LevelClient's `Players.LocalPlayer.LevelState`,
-- crossfaded by tweening each Sound's Volume. Pot's volume follows the local
-- lane folder's replicated `Stage` attribute (Lane.updateStageAttribute, 1 =
-- bottom stage). Ambience is a sound effect bed, so it follows the SFX toggle
-- (`SfxOn`, nil = on, as in SoundFX.luau), not `MusicOn`. A stem whose id is
-- still 0 gets no Sound at all (silent no-op, doc contract).

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SoundAssets = require(ReplicatedStorage.Shared.SoundAssets)

local player = Players.LocalPlayer

local STEMS: { [string]: string } = {
	Pot = "potBubbling",
	Kitchen = "kitchenRoomTone",
}
local POT_STAGE_VOLUME = { 0.5, 0.35, 0.25 } -- by Pot height stage; stage 1 is nearest the lava
local KITCHEN_VOLUME = 0.25
local FADE_SECONDS = 1.5

local sounds: { [string]: Sound } = {}
local tweens: { [Sound]: Tween } = {}

for levelName, stem in STEMS do
	local id = SoundAssets.id(stem)
	if id then
		local sound = Instance.new("Sound")
		sound.Name = "Ambience_" .. stem
		sound.SoundId = id
		sound.Looped = true
		sound.Volume = 0
		sound.Parent = SoundService
		sounds[levelName] = sound
	end
end

local levelState = player:WaitForChild("LevelState", math.huge) :: Folder
local myLane =
	workspace:WaitForChild("PlayField"):WaitForChild("Lanes"):WaitForChild(tostring(player.UserId), math.huge)

local function targetVolume(levelName: string): number
	if player:GetAttribute("SfxOn") == false then
		return 0
	end
	if levelName == "Pot" then
		local stage = myLane:GetAttribute("Stage")
		return (typeof(stage) == "number" and POT_STAGE_VOLUME[stage]) or POT_STAGE_VOLUME[1]
	end
	return KITCHEN_VOLUME
end

-- Fades every loop toward its target: the current level's loop up (starting it
-- if stopped), every other loop down to 0 and then stopped.
local function refresh()
	local current = levelState:GetAttribute("LevelName")
	for levelName, sound in sounds do
		local target = if levelName == current then targetVolume(levelName) else 0
		local previous = tweens[sound]
		if previous then
			previous:Cancel()
		end
		if target > 0 and not sound.IsPlaying then
			sound:Play()
		end
		local tween = TweenService:Create(sound, TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Linear), {
			Volume = target,
		})
		tweens[sound] = tween
		if target == 0 then
			tween.Completed:Once(function(playbackState: Enum.PlaybackState)
				if playbackState == Enum.PlaybackState.Completed then
					sound:Stop()
				end
			end)
		end
		tween:Play()
	end
end

levelState:GetAttributeChangedSignal("LevelName"):Connect(refresh)
myLane:GetAttributeChangedSignal("Stage"):Connect(refresh)
player:GetAttributeChangedSignal("SfxOn"):Connect(refresh)
refresh() -- catch up if LevelClient already set LevelName before this script ran
