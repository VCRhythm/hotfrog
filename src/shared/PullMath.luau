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
-- target line: 2 * |target - position|, a per-frame force. Kept for reference;
-- the port uses pullDistance below, which turns the same idea into a destination.
function PullMath.pullMultiplier(position: number, target: number): number
	return 2 * math.abs(target - position)
end

-- How far one grab scrolls the field (studs along `travel`, the lane's spawn
-- direction): far enough that the grabbed point `rel` (lane-relative, at rest)
-- ends on the point of its travel line nearest Config.PULL_TARGET, the camera
-- centre. For a straight-down scroll that is simply "the step's height above the
-- centre". Clamped to [PULL_MIN_DISTANCE, PULL_MAX_DISTANCE] (see Config).
function PullMath.pullDistance(rel: Vector2, travel: Vector2): number
	if travel.Magnitude < 1e-4 then
		return 0
	end
	local d = -(rel - Config.PULL_TARGET):Dot(travel.Unit)
	return math.clamp(d, Config.PULL_MIN_DISTANCE, Config.PULL_MAX_DISTANCE)
end

-- Tween duration for a pull of `distance` studs (Config.PULL_SPEED, clamped).
function PullMath.pullTime(distance: number): number
	return math.clamp(math.abs(distance) / Config.PULL_SPEED, Config.PULL_TIME, Config.PULL_TIME_MAX)
end

return PullMath
