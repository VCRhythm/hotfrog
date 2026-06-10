-- StarterPlayer/StarterPlayerScripts/Client/Effects (LocalScript)
-- Cosmetic feedback layer, kept out of GameClient so the core loop stays lean:
--   * one-shot sounds on the existing remotes (squish / fall / crumble)
--   * pebble debris off Unsteady steps (Entities/Pebble.cs + Step.cs ShowCrumbles:
--     emit crumbles every second while a step is unsteady)
-- Pebbles are client-local parts, so they never fight the server-owned step
-- CFrames that the scroll/drop tweens are writing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local SoundFX = require(ReplicatedStorage.Shared.SoundFX)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local BugCaught = remotes:WaitForChild("BugCaught") :: RemoteEvent
local GameOver = remotes:WaitForChild("GameOver") :: RemoteEvent
local ForceRelease = remotes:WaitForChild("ForceRelease") :: RemoteEvent

-- ---------------------------------------------------------------------------
-- Sounds (clip stems from SoundAssets; silent until ids are pasted in)
-- ---------------------------------------------------------------------------
BugCaught.OnClientEvent:Connect(function()
	SoundFX.play("squish") -- Tongue.cs DefaultCatchAction
end)

GameOver.OnClientEvent:Connect(function()
	SoundFX.play("fall") -- Frog.cs PlayFallSound
end)

ForceRelease.OnClientEvent:Connect(function()
	SoundFX.play("crumbleShort") -- knocked off: Step.cs PlayShortCrumbleSound
end)

-- ---------------------------------------------------------------------------
-- Pebbles off unsteady steps (ShowCrumbles: a burst every second while unsteady)
-- ---------------------------------------------------------------------------
local PEBBLES_PER_BURST = 4
local PEBBLE_LIFETIME = 1.5
local PEBBLE_INTERVAL = 1.0

local steps = workspace:WaitForChild("PlayField"):WaitForChild("Steps")

local function emitPebbles(origin: Vector3, color: Color3)
	for _ = 1, PEBBLES_PER_BURST do
		local pebble = Instance.new("Part")
		pebble.Name = "Pebble"
		pebble.Size = Vector3.new(0.3, 0.3, 0.3)
		pebble.Color = color -- Pebble.cs Explode tints debris to the step's colour
		pebble.CanCollide = false
		pebble.CanQuery = false -- must not eat taps
		pebble.CFrame = CFrame.new(origin + Vector3.new(math.random(-15, 15) / 10, -0.5, 0))
		pebble.AssemblyLinearVelocity = Vector3.new(math.random(-8, 8), math.random(2, 6), 0)
		pebble.Parent = workspace
		Debris:AddItem(pebble, PEBBLE_LIFETIME)
	end
end

task.spawn(function()
	while true do
		for _, step in steps:GetChildren() do
			if step:IsA("BasePart") and step:GetAttribute("Unsteady") == true then
				emitPebbles(step.Position, step.Color)
			end
		end
		task.wait(PEBBLE_INTERVAL)
	end
end)
