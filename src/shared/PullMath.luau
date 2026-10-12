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

-- Grade a grab by how close the tap landed to the step's grip point (its Unity pivot; the canvas centre for most kinds).
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

-- Normal-mode combo speed multiplier for a streak value (Config.STREAK_*;
-- b-20261010-192608-4bs3): 1 at no streak, STREAK_SPEED_MAX at STREAK_FULL.
function PullMath.streakSpeed(streak: number): number
	local t = math.clamp(streak / Config.STREAK_FULL, 0, 1)
	return 1 + (Config.STREAK_SPEED_MAX - 1) * t
end

-- How many Config.STREAK_SPEED_CUES thresholds `speed` has reached (0..#cues).
function PullMath.cueIndex(speed: number): number
	local n = 0
	for i, threshold in Config.STREAK_SPEED_CUES do
		if speed >= threshold - 1e-6 then
			n = i
		end
	end
	return n
end

-- Extra score a grab earns at `streak` (Config.STREAK_BONUS_*).
function PullMath.streakBonus(streak: number): number
	return math.min(math.floor(streak / Config.STREAK_BONUS_EVERY), Config.STREAK_BONUS_MAX)
end

-- Sine/Out easing of `alpha` (clamped to 0..1): DOTween's Ease.OutSine and
-- TweenService's Sine/Out. The one curve every server-played motion shares --
-- Lane's pulls and slide-ins, Frog.Bob's sway/rise, the death sink -- and the one
-- WorldScenery tweens a lane's cosmetics with off PullDelta/PullTime, so it lives
-- here rather than once per caller.
function PullMath.sineOut(alpha: number): number
	return math.sin(math.clamp(alpha, 0, 1) * (math.pi / 2))
end

-- Quad/In easing of `alpha` (clamped to 0..1): a step dropping away (Step.cs
-- Fall's DOLocalMoveY, GameServer's step motion layer).
function PullMath.quadIn(alpha: number): number
	local a = math.clamp(alpha, 0, 1)
	return a * a
end

-- Lerp alpha that closes the same share of a gap over `dt` whatever the frame
-- rate: 1 - e^(-dt / timeConstant). At 60 Hz it matches the old per-frame
-- `dt / timeConstant` to within a few percent, but a hitch (or a 240 Hz server)
-- no longer changes the shape of the ease.
function PullMath.smoothAlpha(dt: number, timeConstant: number): number
	if timeConstant <= 0 then
		return 1
	end
	return 1 - math.exp(-dt / timeConstant)
end

-- One exact step of an underdamped spring pulling `x` back to zero: angular
-- frequency `omega` (rad/s), damping ratio `zeta` (0 < zeta < 1). Closed form
-- rather than an Euler step, so the result is the same at any frame rate and
-- cannot blow up on a long tick. Returns the new displacement and velocity.
function PullMath.springStep(x: Vector3, v: Vector3, dt: number, omega: number, zeta: number): (Vector3, Vector3)
	local sigma = zeta * omega
	local damped = omega * math.sqrt(1 - zeta * zeta)
	local decay = math.exp(-sigma * dt)
	local c, s = math.cos(damped * dt), math.sin(damped * dt)
	local b = (v + x * sigma) / damped
	return (x * c + b * s) * decay, ((b * damped - x * sigma) * c - (x * damped + b * sigma) * s) * decay
end

return PullMath
