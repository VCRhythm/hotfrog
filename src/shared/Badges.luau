--!strict
-- ReplicatedStorage/Shared/Badges (ModuleScript)
-- Threshold -> Roblox badge id, ported from Core/VariableManager.cs's
-- CheckForAchievement (Social.ReportProgress "10!".."100!" every 10 steps up
-- to 100). See src/server/BadgeService.server.luau for exactly when each
-- entry is awarded, and how that condition intentionally differs from
-- Unity's "only on a new all-time high score" gate.
--
-- All ids are placeholders (0); BadgeService treats 0 as "not configured yet"
-- and silently skips it -- safe to ship before the badges exist.
--
-- FILL IN: in the Creator Hub (create.roblox.com/dashboard/creations -> this
-- experience -> Engagement -> Badges -> Create a Badge), create one badge per
-- row below (the `name` field is just a suggestion for what to call it there),
-- then paste each badge's numeric id over the matching `id = 0`.

export type BadgeEntry = {
	threshold: number, -- steps climbed in a single run (leaderstats.Score)
	id: number, -- FILL IN: Creator Hub badge id (0 = not configured yet, skipped)
	name: string, -- suggested Creator Hub badge name, for reference only
}

local Badges: { BadgeEntry } = {
	{ threshold = 10, id = 0, name = "10 Steps!" },
	{ threshold = 20, id = 0, name = "20 Steps!" },
	{ threshold = 30, id = 0, name = "30 Steps!" },
	{ threshold = 40, id = 0, name = "40 Steps!" },
	{ threshold = 50, id = 0, name = "50 Steps!" },
	{ threshold = 60, id = 0, name = "60 Steps!" },
	{ threshold = 70, id = 0, name = "70 Steps!" },
	{ threshold = 80, id = 0, name = "80 Steps!" },
	{ threshold = 90, id = 0, name = "90 Steps!" },
	{ threshold = 100, id = 0, name = "100 Steps!" },
}

return Badges
