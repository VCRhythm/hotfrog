--!strict
-- StarterPlayerScripts/Client/world/GrabTarget (ModuleScript)
-- Client-only heuristic for "what is this frog currently holding". The server
-- never replicates WHICH step a limb holds (that state stays server-side, doc
-- 07) -- but GameServer.server.luau's frog-render Heartbeat snaps a held limb's
-- CFrame to exactly `CFrame.new(step.Position)` every tick while it's held, and
-- eases it back toward `body.CFrame * Config.LIMB_REST[i]` otherwise. Comparing
-- a limb's current world position against that known rest offset is a cheap,
-- read-only way to detect "this limb is extended onto something" from already-
-- replicated data, without a new remote.
--
-- Used by world/FrogCosmetics (pupil look target, every visible frog) and
-- world/QualityPopup (floating text placement, local frog only).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local GrabTarget = {}

-- The world position a limb is extended to, or nil if it looks "at rest".
-- `limbIndex` is 1=Right, 2=Left (Config.LIMB_REST's own ordering).
function GrabTarget.limbHeldPosition(body: BasePart, limb: BasePart, limbIndex: number): Vector3?
	local rest = Config.LIMB_REST[limbIndex]
	if not rest then
		return nil
	end
	local restWorld = (body.CFrame * CFrame.new(rest.X, rest.Y, 0)).Position
	if (limb.Position - restWorld).Magnitude > WorldConfig.GRAB_EXTEND_THRESHOLD then
		return limb.Position
	end
	return nil
end

-- Either limb's held position (Right checked first), or nil if neither is
-- extended past its rest pose.
function GrabTarget.heldPosition(body: BasePart, rightLimb: BasePart?, leftLimb: BasePart?): Vector3?
	if rightLimb then
		local p = GrabTarget.limbHeldPosition(body, rightLimb, 1)
		if p then
			return p
		end
	end
	if leftLimb then
		local p = GrabTarget.limbHeldPosition(body, leftLimb, 2)
		if p then
			return p
		end
	end
	return nil
end

-- Nearest active step belonging to `laneUserId`, scanning `steps`'s children.
-- Callers throttle this (WorldConfig.NEAREST_STEP_POLL_INTERVAL) -- it's an
-- O(n) scan over one lane's live steps, not a per-frame hot-loop op.
function GrabTarget.nearestStep(steps: Instance, laneUserId: number, from: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, child in steps:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("LaneUserId") == laneUserId then
			local d = (child.Position - from).Magnitude
			if d < bestDist then
				bestDist = d
				best = child
			end
		end
	end
	return best
end

return GrabTarget
