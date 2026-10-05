--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Effects (LocalScript)
-- Cosmetic feedback layer, kept out of GameClient so the core loop stays lean:
--   * one-shot sounds on the existing remotes (squish / fall / crumble)
--   * pebble debris off Unsteady steps (Entities/Pebble.cs Explode + Step.cs
--     ShowCrumbles: emit crumbles every second while a step is unsteady)
-- Pebbles are client-local parts, so they never fight the server-owned step
-- CFrames that the scroll/drop tweens are writing.
--
-- Phase 4 world dressing (item 4): pebbles are pooled (world/Bursts -> Pool)
-- instead of one-shot Instance.new()+Debris per burst, and their impulse
-- matches Pebble.cs Explode (xForce/yForce spread + an opposing torque tied to
-- the X force's sign), tinted to the step's own colour exactly as before.
--
-- Event-driven (modernisation pass): the old loop polled `steps:GetChildren()`
-- every PEBBLE_INTERVAL forever. Now each step in the Steps folder gets one
-- `Unsteady` attribute-changed connection (made on ChildAdded, dropped on
-- ChildRemoved -- GameServer pools steps by reparenting them to nil, so the
-- same part comes back many times), and only the steps currently unsteady are
-- visited by the per-frame emitter below.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SoundFX = require(ReplicatedStorage.Shared.SoundFX)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local Bursts = require(script.Parent.world.Bursts)

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
local playField = workspace:WaitForChild("PlayField", WorldConfig.LANE_WAIT_TIMEOUT)
local steps = if playField then playField:WaitForChild("Steps", WorldConfig.LANE_WAIT_TIMEOUT) else nil
if not steps then
	warn("[Effects] PlayField.Steps never appeared; pebble debris is disabled")
	return
end

local pebbles = Bursts.new({
	name = "Pebble",
	size = Vector3.new(0.3, 0.3, 0.3),
})

-- Entities/Pebble.cs Explode: xForce=Random(-5,5), yForce=Random(1,5), an
-- opposing torque (rotForce = 2 * sign(xForce), applied by Bursts), tinted to the
-- step's colour.
local function emitPebbles(origin: Vector3, color: Color3)
	pebbles.emit(origin + Vector3.new(0, -WorldConfig.PEBBLE_DROP_Y, 0), {
		count = WorldConfig.PEBBLES_PER_BURST,
		x = NumberRange.new(WorldConfig.PEBBLE_MIN_X_FORCE, WorldConfig.PEBBLE_MAX_X_FORCE),
		y = NumberRange.new(WorldConfig.PEBBLE_MIN_Y_FORCE, WorldConfig.PEBBLE_MAX_Y_FORCE),
		spin = WorldConfig.PEBBLE_ROT_FORCE,
		jitterX = WorldConfig.PEBBLE_JITTER_X,
		color = color,
		lifetime = WorldConfig.PEBBLE_LIFETIME,
		fadeStart = 1, -- Pebble.cs never fades them: they just vanish
	})
end

-- step -> os.clock() of its next burst, for steps that are Unsteady right now.
local unsteady: { [BasePart]: number } = {}
-- step -> its Unsteady attribute connection while it is in the Steps folder.
local watchers: { [Instance]: RBXScriptConnection } = {}

local function syncUnsteady(step: BasePart)
	if step:GetAttribute("Unsteady") == true then
		if unsteady[step] == nil then
			unsteady[step] = os.clock() -- first burst on the next frame
		end
	else
		unsteady[step] = nil
	end
end

local function watchStep(child: Instance)
	if not child:IsA("BasePart") or watchers[child] then
		return
	end
	watchers[child] = child:GetAttributeChangedSignal("Unsteady"):Connect(function()
		syncUnsteady(child)
	end)
	syncUnsteady(child)
end

local function unwatchStep(child: Instance)
	local conn = watchers[child]
	if conn then
		conn:Disconnect()
		watchers[child] = nil
	end
	if child:IsA("BasePart") then
		unsteady[child] = nil
	end
end

steps.ChildAdded:Connect(watchStep)
steps.ChildRemoved:Connect(unwatchStep)
for _, child in steps:GetChildren() do
	watchStep(child)
end

-- Per-frame visual: visit only the (usually zero) currently-unsteady steps.
RunService.PreRender:Connect(function()
	if next(unsteady) == nil then
		return
	end
	local now = os.clock()
	for step, due in unsteady do
		if now >= due then
			unsteady[step] = now + WorldConfig.PEBBLE_INTERVAL
			emitPebbles(step.Position, step.Color)
		end
	end
end)
