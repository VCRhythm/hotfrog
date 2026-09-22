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

local Levels = require(ReplicatedStorage.Shared.Levels)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local LevelChanged = remotes:WaitForChild("LevelChanged") :: RemoteEvent

local state = Instance.new("Folder")
state.Name = "LevelState"

local changed = Instance.new("BindableEvent")
changed.Name = "Changed"
changed.Parent = state

state.Parent = player

local function apply(
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

LevelChanged.OnClientEvent:Connect(
	function(
		levelName: string,
		musicIndex: number,
		background: string?,
		overlay: string?,
		transition: string,
		laneOrigin: Vector3
	)
		apply(levelName, musicIndex, background, overlay, transition, laneOrigin)
	end
)

-- Bootstrap from the replicated Lane folder (doc 13's discovery contract:
-- workspace.PlayField.Lanes/<UserId>, with a `Level` Attribute Lane.luau always
-- keeps current) in case the very first LevelChanged ("start", fired once at
-- Lane construction -- see Lane.new) raced this LocalScript's startup and was
-- dropped: OnClientEvent has no buffering, so a RemoteEvent fired before this
-- script connects is simply lost, and nothing else re-fires "start" later --
-- the next LevelChanged is often "death" at the end of the player's first run,
-- which is why music previously stayed silent until then. An Attribute doesn't
-- have that failure mode (GetAttribute always reflects the latest value, no
-- matter when it's read), so use it as a one-time catch-up, skipped entirely if
-- the remote already got through by the time this resolves.
do
	local lanesFolder = workspace:WaitForChild("PlayField"):WaitForChild("Lanes")
	local laneFolder = lanesFolder:WaitForChild(tostring(player.UserId), math.huge) :: Folder
	if state:GetAttribute("Transition") == nil then
		local levelName = laneFolder:GetAttribute("Level")
		if typeof(levelName) == "string" then
			for _, level in Levels.list do
				if level.name == levelName then
					local origin = laneFolder:GetAttribute("Origin")
					apply(
						level.name,
						level.musicIndex,
						level.background,
						level.overlay,
						"start",
						if typeof(origin) == "Vector3" then origin else Vector3.zero
					)
					break
				end
			end
		end
	end
end
