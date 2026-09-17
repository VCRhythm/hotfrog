--!strict
-- StarterPlayer/StarterPlayerScripts/LevelClient (LocalScript)
-- Thin client-side hook for the LevelChanged remote (doc 13 item 6). This is
-- intentionally NOT the cosmetics themselves -- a later phase renders
-- background/overlay materials, music, and transition effects from this data.
-- For now it just tracks the local player's current level and exposes it in a
-- way other LocalScripts can read without requiring this one (LocalScripts
-- can't require each other): a small Folder of Attributes + a BindableEvent,
-- parented under the LocalPlayer so it's easy to find and inherently
-- per-player/local (never replicated).
--
-- Fields exposed on `Players.LocalPlayer.LevelState`:
--   LevelName (string), MusicIndex (number), Background (string?),
--   Overlay (string?), Transition (string: "start" | "soft" | "death"),
--   LaneOrigin (Vector3)
-- plus a `Changed` BindableEvent firing with the same 6 values, for scripts
-- that want to react rather than poll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local LevelChanged = remotes:WaitForChild("LevelChanged") :: RemoteEvent

local state = Instance.new("Folder")
state.Name = "LevelState"

local changed = Instance.new("BindableEvent")
changed.Name = "Changed"
changed.Parent = state

state.Parent = player

LevelChanged.OnClientEvent:Connect(
	function(
		levelName: string,
		musicIndex: number,
		background: string?,
		overlay: string?,
		transition: string,
		laneOrigin: Vector3
	)
		state:SetAttribute("LevelName", levelName)
		state:SetAttribute("MusicIndex", musicIndex)
		state:SetAttribute("Background", background)
		state:SetAttribute("Overlay", overlay)
		state:SetAttribute("Transition", transition)
		state:SetAttribute("LaneOrigin", laneOrigin)
		changed:Fire(levelName, musicIndex, background, overlay, transition, laneOrigin)
	end
)
