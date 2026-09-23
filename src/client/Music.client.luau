--!strict
-- StarterPlayer/StarterPlayerScripts/Music (LocalScript)
-- Ports Audio/AudioPlayer.cs's two-channel crossfading music system (doc 12 §5
-- "AudioPlayer / channel setup"): SoundService gets two looped Sound instances
-- ("MusicChannel1"/"MusicChannel2"); LevelChanged (relayed by
-- LevelClient.client.luau's `Players.LocalPlayer.LevelState.Changed`
-- BindableEvent, doc 13 item 6 -- read-only, this script never touches
-- LevelClient itself) picks the track by musicIndex, using the SAME
-- musicClips[] order as the original AudioManager prefab (doc 12 §5):
--
--   musicIndex   Unity asset                      SoundAssets stem
--   0            Audio/Music/BrusselSprouts.wav   music1
--   1            Audio/Music/FrogSounds.wav       music2
--   2            Audio/Music/Opening.mp3          music3
--   3            Audio/Music/Adenine.mp3          music4
--   4            Audio/Music/Two Wrongs.wav       music5  (Multiplayer.unity override)
--
-- (Per Levels.luau / doc 11 §1: Menu=1, Tutorial=1, Pot=0, Kitchen=1, so in
-- practice the base game only ever plays music2 and music1.)
--
-- Country's musicIndex is 4: the base AudioManager prefab only has 4 clips, but
-- Multiplayer.unity (the only scene that has the Country level) overrides
-- musicClips[] with a fifth entry, Audio/Music/Two Wrongs.wav -> music5. An
-- index with no mapped stem just fades the current track out to silence (see
-- `playIndex` below).
--
-- Respects the `MusicOn` player Attribute (server sets it; per this phase's
-- contract it may not exist yet -- nil means ON, mirroring `SfxOn` in
-- SoundFX.luau) and reacts live if it changes.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SoundAssets = require(ReplicatedStorage.Shared.SoundAssets)
local SoundFX = require(ReplicatedStorage.Shared.SoundFX)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local player = Players.LocalPlayer

-- musicClips[] index -> SoundAssets stem (table above, verbatim order).
local MUSIC_STEMS: { [number]: string } = {
	[0] = "music1",
	[1] = "music2",
	[2] = "music3",
	[3] = "music4",
	[4] = "music5",
}

-- AudioPlayer.cs: musicOnAwakeVolume = .7f, fadeAmount = .01f applied once per
-- Update() frame (~100 frames to fully fade at a steady 60fps).
local TARGET_VOLUME = 0.7
local FADE_SECONDS = 100 / 60

local function newChannel(name: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService
	return sound
end

local channelA = newChannel("MusicChannel1")
local channelB = newChannel("MusicChannel2")

-- `active` is whichever channel currently holds the "now playing" (or
-- faded-out-and-paused) track; `idle` is the other, free to receive the next
-- crossfade target. Mirrors AudioPlayer's channelIndex / GetNewChannelIndex.
local active = channelA
local idle = channelB

local activeStem: string? = nil -- stem currently loaded on `active` (nil = channel is empty)
local activeTween: Tween? = nil

local function stopActiveTween()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
end

local function musicWanted(): boolean
	return player:GetAttribute("MusicOn") ~= false -- nil = on (doc contract)
end

-- Fades `sound`'s volume to `target` over FADE_SECONDS, then calls `onDone` (if
-- given) only if the fade actually completed (not cancelled mid-flight).
local function fadeTo(sound: Sound, target: number, onDone: (() -> ())?)
	if sound == active then
		stopActiveTween()
	end
	local tween = TweenService:Create(sound, TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Linear), { Volume = target })
	if sound == active then
		activeTween = tween
	end
	if onDone then
		tween.Completed:Once(function(playbackState: Enum.PlaybackState)
			if playbackState == Enum.PlaybackState.Completed then
				onDone()
			end
		end)
	end
	tween:Play()
end

-- Loads and plays `stem` on `active` with no fade -- AudioPlayer.PlayMusicClip
-- takes this branch whenever the target channel has no clip / isn't already
-- playing (cold start, or resuming after a full fade-out). `nil` just clears it.
local function playCold(stem: string?)
	stopActiveTween()
	active:Stop()
	active.Volume = 0
	if not stem then
		activeStem = nil
		return
	end
	local id = SoundAssets.id(stem)
	if not id then
		activeStem = nil -- id still 0 -- silent no-op (doc contract)
		return
	end
	active.SoundId = id
	active.TimePosition = 0
	active.Volume = if musicWanted() then TARGET_VOLUME else 0
	active:Play()
	activeStem = stem
end

-- Crossfades from whatever's on `active` to `stem` on `idle`, then swaps roles
-- (AudioPlayer.PlayMusicClip's isCrossFading branch).
local function crossfadeTo(stem: string)
	local id = SoundAssets.id(stem)
	if not id then
		return -- id still 0 -- leave whatever's already playing alone
	end
	idle.SoundId = id
	idle.TimePosition = 0
	idle.Volume = 0
	idle:Play()

	local outgoing = active
	active, idle = idle, outgoing -- `idle` (now `active`) owns future fade-target bookkeeping
	activeStem = stem

	fadeTo(active, if musicWanted() then TARGET_VOLUME else 0)
	fadeTo(outgoing, 0, function()
		outgoing:Stop()
	end)
end

-- Fades the current track fully out and pauses it (AudioPlayer.FadeOutMusic ->
-- Pause-at-zero-volume), WITHOUT discarding the clip, so a later fade-in on the
-- same stem resumes rather than restarts.
local function fadeOutCurrent(onDone: (() -> ())?)
	if not activeStem or active.Volume == 0 then
		if onDone then
			onDone()
		end
		return
	end
	fadeTo(active, 0, function()
		active:Pause()
		if onDone then
			onDone()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- LevelChanged handling (doc 13 item 6, relayed by LevelClient's LevelState).
-- ---------------------------------------------------------------------------
-- Bumped on every playIndex call, so a "soft" crossfade still waiting out the
-- arrival sting (below) is dropped if a newer transition (e.g. "death") lands.
local playGeneration = 0

local function playIndex(musicIndex: number, transition: string)
	playGeneration += 1
	local stem = MUSIC_STEMS[musicIndex]

	if transition == "death" then
		-- Unity: LevelManager.EndLevel -> FadeOutMusic happens immediately; THEN,
		-- once the new level actually finishes setting up, PlayLevel ->
		-- StartMusic(true, newIndex) happens separately. The port's
		-- LevelChanged("death") already carries the new level's musicIndex in the
		-- SAME event (Lane.resetRun sets the level BEFORE notifying -- see
		-- src/server/Lane.luau), so replicate the two sequential Unity calls as a
		-- genuine fade-out-then-fade-in rather than an immediate crossfade (that's
		-- what distinguishes "death" from "soft" here).
		fadeOutCurrent(function()
			if not stem then
				return
			end
			if activeStem == stem then
				-- same track resumes rather than restarting (AudioPlayer: "Triggered
				-- clip is already playing" short-circuit)
				active.Volume = if musicWanted() then TARGET_VOLUME else 0
				active:Resume()
			else
				playCold(stem)
			end
		end)
		return
	end

	if not stem then
		-- musicIndex has no mapped stem (see the Country/index-4 note up top) --
		-- fade to silence rather than erroring.
		fadeOutCurrent()
		return
	end

	if activeStem == stem and active.IsPlaying then
		return -- no overlapping duplicate tracks when LevelChanged repeats an index
	end

	local function switch()
		if not activeStem or active.Volume == 0 then
			playCold(stem)
		else
			crossfadeTo(stem)
		end
	end

	if transition == "soft" then
		-- Level-up arrival (journey 2/8, b-20260923-154343-3h60): the sting
		-- (ArrivalCount listener at the bottom of this file) plays first; the
		-- new level's track crossfades in once it has had its moment.
		local generation = playGeneration
		task.delay(WorldConfig.ARRIVAL_STING_LEAD, function()
			if generation == playGeneration then
				switch()
			end
		end)
	else
		switch()
	end
end

local levelState = player:WaitForChild("LevelState", math.huge) :: Folder
local changed = levelState:WaitForChild("Changed") :: BindableEvent

changed.Event:Connect(
	function(
		_levelName: string,
		musicIndex: number,
		_background: string?,
		_overlay: string?,
		transition: string,
		_laneOrigin: Vector3
	)
		playIndex(musicIndex, transition)
	end
)

-- Catch up if LevelChanged already fired before this script connected --
-- LocalScripts under StarterPlayerScripts start in parallel with no ordering
-- guarantee, and LevelClient.client.luau may have already set the attributes.
do
	local musicIndex = levelState:GetAttribute("MusicIndex")
	local transition = levelState:GetAttribute("Transition")
	if typeof(musicIndex) == "number" and typeof(transition) == "string" then
		playIndex(musicIndex, transition)
	end
end

-- ---------------------------------------------------------------------------
-- MusicOn toggle (contract: server sets this Attribute; nil = on). Reacts live
-- rather than only being read at the next LevelChanged.
-- ---------------------------------------------------------------------------
player:GetAttributeChangedSignal("MusicOn"):Connect(function()
	if musicWanted() then
		if activeStem then
			active:Resume()
			fadeTo(active, TARGET_VOLUME)
		end
	else
		fadeOutCurrent()
	end
end)

-- ---------------------------------------------------------------------------
-- Level-up arrival sting (journey 2/8, b-20260923-154343-3h60): the local
-- lane's `ArrivalCount` attribute bumps only on a real level-up
-- (Lane.beginArrival, server), never on run start or respawn. SoundFX, so it
-- follows the SFX toggle and is a silent no-op while the clip id is 0.
-- ---------------------------------------------------------------------------
local myLane =
	workspace:WaitForChild("PlayField"):WaitForChild("Lanes"):WaitForChild(tostring(player.UserId), math.huge)
myLane:GetAttributeChangedSignal("ArrivalCount"):Connect(function()
	SoundFX.play(WorldConfig.ARRIVAL_STING)
end)
