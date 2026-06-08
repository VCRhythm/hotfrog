--!strict
-- ReplicatedStorage/Shared/PullMath (ModuleScript)
-- Small shared helpers for plane math and the pull mechanic. Kept separate so the
-- server (authoritative scroll) and any client-side prediction agree on the math.

local Config = require(script.Parent.Config)

local PullMath = {}

-- Map a 2D gameplay vector onto the 3D play plane.
function PullMath.v2to3(v: Vector2): Vector3
	return Vector3.new(v.X, v.Y, Config.PLANE_Z)
end

-- Squared planar distance between two world positions (ignores Z).
function PullMath.planarDistSqr(a: Vector3, b: Vector3): number
	local dx, dy = a.X - b.X, a.Y - b.Y
	return dx * dx + dy * dy
end

-- Grade a grab by how close the tap landed to the step centre.
-- Mirrors Player/Controller.cs TouchStep bucketing.
function PullMath.gradeGrab(tapWorld: Vector3, stepWorld: Vector3): string
	local d2 = PullMath.planarDistSqr(tapWorld, stepWorld)
	if d2 <= Config.GRAB_PERFECT_SQR then
		return "Perfect"
	elseif d2 <= Config.GRAB_GREAT_SQR then
		return "Great"
	else
		return "OK"
	end
end

-- The original (SpawnManager.PullMultiplier) scales the pull by distance to a
-- target line: 2 * |target - position|. We expose it for anyone wanting the
-- continuous-pull feel; the reference GameServer uses a fixed PULL_DISTANCE step,
-- which reads the same and is simpler.
function PullMath.pullMultiplier(position: number, target: number): number
	return 2 * math.abs(target - position)
end

return PullMath
