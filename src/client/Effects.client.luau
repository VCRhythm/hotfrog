-- StarterPlayer/StarterPlayerScripts/Client/Effects (LocalScript)
-- Cosmetic feedback layer, kept out of GameClient so the core loop stays lean:
--   * one-shot sounds on the existing remotes (squish / fall / crumble)
--   * pebble debris off Unsteady steps (Entities/Pebble.cs Explode + Step.cs
--     ShowCrumbles: emit crumbles every second while a step is unsteady)
-- Pebbles are client-local parts, so they never fight the server-owned step
-- CFrames that the scroll/drop tweens are writing.
--
-- Phase 4 world dressing (item 4): pebbles are now pooled (world/Pool.luau)
-- instead of one-shot Instance.new()+Debris per burst, and their impulse
-- matches Pebble.cs Explode (xForce/yForce spread + an opposing torque tied to
-- the X force's sign), tinted to the step's own colour exactly as before.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundFX = require(ReplicatedStorage.Shared.SoundFX)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local Pool = require(script.Parent.world.Pool)

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
local steps = workspace:WaitForChild("PlayField"):WaitForChild("Steps")

local pebblePool = Pool.new(function(): BasePart
	local pebble = Instance.new("Part")
	pebble.Name = "Pebble"
	pebble.Size = Vector3.new(0.3, 0.3, 0.3)
	pebble.CanCollide = false
	pebble.CanQuery = false -- must not eat taps
	return pebble
end, function(pebble: BasePart)
	pebble.Anchored = true
	pebble.AssemblyLinearVelocity = Vector3.zero
	pebble.AssemblyAngularVelocity = Vector3.zero
	pebble.Parent = nil
end)

-- Entities/Pebble.cs Explode: xForce=Random(-5,5), yForce=Random(1,5), an
-- opposing torque (rotForce = 2 * sign(xForce)), tinted to the step's colour.
local function emitPebbles(origin: Vector3, color: Color3)
	for _ = 1, WorldConfig.PEBBLES_PER_BURST do
		local pebble = pebblePool.acquire()
		pebble.Color = color
		pebble.CFrame = CFrame.new(origin + Vector3.new(math.random(-15, 15) / 10, -0.5, 0))
		pebble.Anchored = false

		local xForce = WorldConfig.PEBBLE_MIN_X_FORCE
			+ math.random() * (WorldConfig.PEBBLE_MAX_X_FORCE - WorldConfig.PEBBLE_MIN_X_FORCE)
		local yForce = WorldConfig.PEBBLE_MIN_Y_FORCE
			+ math.random() * (WorldConfig.PEBBLE_MAX_Y_FORCE - WorldConfig.PEBBLE_MIN_Y_FORCE)
		local rotForce = WorldConfig.PEBBLE_ROT_FORCE * (if xForce >= 0 then 1 else -1)
		pebble.AssemblyLinearVelocity = Vector3.new(xForce, yForce, 0)
		pebble.AssemblyAngularVelocity = Vector3.new(0, 0, -rotForce)
		pebble.Parent = workspace

		task.delay(WorldConfig.PEBBLE_LIFETIME, function()
			if pebble.Parent then
				pebblePool.release(pebble)
			end
		end)
	end
end

task.spawn(function()
	while true do
		for _, step in steps:GetChildren() do
			if step:IsA("BasePart") and step:GetAttribute("Unsteady") == true then
				emitPebbles(step.Position, step.Color)
			end
		end
		task.wait(WorldConfig.PEBBLE_INTERVAL)
	end
end)
