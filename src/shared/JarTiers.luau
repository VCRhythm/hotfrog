--!strict
-- ReplicatedStorage/Shared/JarTiers (ModuleScript)
-- Fly Jar titles (b-20261008-142124-qw4r; not in Unity -- see doc 17). Flys fed
-- into the jar are gone for good (SkinService's FeedJar remote moves them from
-- profile.flys into the lifetime profile.jarFlys); the jar total unlocks the
-- tier titles below. SkinService mirrors the current title onto the player as
-- the `JarTitle` attribute so every client can show it (race rail, Top Scores).
-- Each tier also has a "jar" row in Badges.luau with the same threshold.

export type Tier = { threshold: number, title: string }

-- Ascending by threshold.
local TIERS: { Tier } = {
	{ threshold = 1000, title = "Fly Snacker" },
	{ threshold = 2500, title = "Fly Keeper" },
	{ threshold = 5000, title = "Swarm Tender" },
	{ threshold = 10000, title = "Jar Master" },
	{ threshold = 25000, title = "Fly Baron" },
	{ threshold = 50000, title = "Lord of the Flies" },
	{ threshold = 100000, title = "Frog Royalty" },
}

local JarTiers = {}
JarTiers.TIERS = TIERS

-- The highest tier reached with `jarFlys` fed in, or nil below the first.
function JarTiers.current(jarFlys: number): Tier?
	local found: Tier? = nil
	for _, tier in TIERS do
		if jarFlys >= tier.threshold then
			found = tier
		end
	end
	return found
end

-- The next tier still to reach, or nil once the top one is unlocked.
function JarTiers.nextTier(jarFlys: number): Tier?
	for _, tier in TIERS do
		if jarFlys < tier.threshold then
			return tier
		end
	end
	return nil
end

-- Title string for `jarFlys` ("" below the first tier).
function JarTiers.title(jarFlys: number): string
	local tier = JarTiers.current(jarFlys)
	return if tier then tier.title else ""
end

return JarTiers
