--!strict
-- StarterPlayer/StarterPlayerScripts/SfxEvents (LocalScript)
-- Wires the remaining Audio/AudioManager.cs one-shots that have a genuine,
-- already-existing CLIENT-VISIBLE signal to trigger from, without touching any
-- of the files that own those signals (GameServer/GameClient/Effects/Lane are
-- off-limits this phase). See docs/roblox-port/16-audio-and-badges.md for the
-- full per-clip coverage table, including what's deliberately NOT wired here
-- and why (dead code in the original, UI-owned, or blocked on a server signal
-- that doesn't exist yet).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundFX = require(ReplicatedStorage.Shared.SoundFX)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ScoreChanged = remotes:WaitForChild("ScoreChanged") :: RemoteEvent
local GameOver = remotes:WaitForChild("GameOver") :: RemoteEvent
local BugCaught = remotes:WaitForChild("BugCaught") :: RemoteEvent

-- ---------------------------------------------------------------------------
-- Grab quality voice lines (Player.cs TrackGrabQuality: OK/Great/Perfect).
-- ScoreChanged already carries the same `quality` string GameServer computed
-- for the grab that just scored (src/server/GameServer.server.luau's
-- `addScore`), the same remote GameClient.client.luau reuses for its HUD
-- flash -- one more listener here, no new signal needed.
-- ---------------------------------------------------------------------------
local QUALITY_STEM: { [string]: string } = {
	OK = "okVoice",
	Great = "greatVoice",
	Perfect = "perfectVoice",
}

-- ---------------------------------------------------------------------------
-- base10 / highScore (UI/HUD.cs's StepsClimbed setter). `best` on ScoreChanged
-- is the profile's high score as of the START of this run (GameServer only
-- bumps it in `commitHighScore`, on death) -- exactly Unity's
-- `newHighScore = HighScore + 1` computed once per run in HUD.SetInitialStats
-- -- so "score == best + 1" is the same "just beat my previous best"
-- condition, re-derivable fresh from every event with no extra state. Falls
-- through to the every-10 case with an `elseif`, exactly like HUD.cs's
-- if/else-if (a value that's simultaneously a new best AND a multiple of ten
-- plays only the high-score cue, same as Unity).
-- ---------------------------------------------------------------------------
ScoreChanged.OnClientEvent:Connect(function(score: number, best: number, quality: string?)
	if quality then
		local stem = QUALITY_STEM[quality]
		if stem then
			SoundFX.play(stem)
		end
	end

	if best > 0 and score == best + 1 then
		SoundFX.play("highScore")
	elseif score > 0 and score % 10 == 0 then
		SoundFX.play("base10")
	end
end)

-- ---------------------------------------------------------------------------
-- splash (task-directed mapping: "splash on death/GameOver"). Unity's own
-- splashSound call sites are both level-scripted lava-reveal timers inside
-- Core/LevelManager.cs's Tutorial-end sequence (sun/lava Animator choreography
-- the port doesn't reproduce yet -- that's LevelClient/World territory, out of
-- this phase's file ownership) rather than a per-death cue; GameOver is the
-- closest already-existing "a run just ended" signal.
--
-- Lava.FallSplash's hurtSound (a lava-specific death) is deliberately NOT
-- wired here: GameOver fires uniformly for every death cause, and there is no
-- server signal today that distinguishes "died in the lava" from any other
-- fall -- see doc 16's coverage table (blocked, needs a death-cause signal).
-- ---------------------------------------------------------------------------
GameOver.OnClientEvent:Connect(function()
	SoundFX.play("splash")
end)

-- ---------------------------------------------------------------------------
-- fly (Entities/Bug.cs OnTriggerEnter2D: plays alongside Tongue's squish sound,
-- which Effects.client.luau already wires on this same BugCaught remote --
-- catching a bug fires both clips in Unity, so this just adds the second one).
-- ---------------------------------------------------------------------------
BugCaught.OnClientEvent:Connect(function()
	SoundFX.play("fly")
end)

-- ---------------------------------------------------------------------------
-- awake (Player/Frog.cs Rise: plays whenever the frog rises up -- the initial
-- spawn AND every respawn after death). GameServer.server.luau's `Dead`
-- attribute on this player's frog model already flips false -> true -> false
-- across exactly that lifecycle, and Attributes replicate to every client
-- automatically, so this needs no new server signal: play once for the frog
-- we find already alive on join (the initial Rise), then again on every later
-- false transition (a respawn's Rise).
-- ---------------------------------------------------------------------------
local playField = workspace:WaitForChild("PlayField")
local myFrog = playField:WaitForChild("Frogs"):WaitForChild("Frog_" .. player.UserId, math.huge) :: Model

if myFrog:GetAttribute("Dead") ~= true then
	SoundFX.play("awake")
end
myFrog:GetAttributeChangedSignal("Dead"):Connect(function()
	if myFrog:GetAttribute("Dead") ~= true then
		SoundFX.play("awake")
	end
end)

-- ---------------------------------------------------------------------------
-- leaves (FirstTree*.prefab: an AudioSource with playOnAwake=true directly on
-- the tree root -- not routed through AudioManager's by-name lookup at all, so
-- in Unity it plays the instant the tree object exists, not on grab). The
-- Tutorial's tree steps are the only src/shared/StepKinds.luau entries using
-- the "Acorn" sprite, so a new Step child carrying that Sprite attribute in
-- OUR OWN lane is the same "a tree just spawned" moment (LaneUserId filters
-- out other players' trees -- the Steps folder is shared by every lane).
-- ---------------------------------------------------------------------------
local steps = playField:WaitForChild("Steps")

local function onStepAdded(step: Instance)
	if
		step:IsA("BasePart")
		and step:GetAttribute("Sprite") == "Acorn"
		and step:GetAttribute("LaneUserId") == player.UserId
	then
		SoundFX.play("leaves")
	end
end

steps.ChildAdded:Connect(onStepAdded)
for _, step in steps:GetChildren() do
	onStepAdded(step)
end
