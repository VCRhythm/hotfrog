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

-- `kind` defaults to "steps". Long-tail kinds (b-20261008-141644-lzg7), all read
-- from signals that already exist server-side (no new persistent counters):
--   "steps"  -- `threshold` steps in one run (leaderstats.Score)
--   "level"  -- `level` ("Kitchen"/"Country") reached, via Lanes/<UserId>.Level
--   "streak" -- `threshold` = daily login streak length (Profiles.get(p).streak)
-- Not badged for lack of a server-side signal: Perfect chains (client-only)
-- and golden bugs (BugCaughtServer carries no golden flag).
export type BadgeEntry = {
	kind: ("steps" | "level" | "streak")?,
	level: string?, -- kind = "level" only
	threshold: number, -- steps (kind "steps") or streak days (kind "streak"); 0 for "level"
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
	-- Long tail
	{ threshold = 150, id = 0, name = "150 Steps!" },
	{ threshold = 200, id = 0, name = "200 Steps!" },
	{ threshold = 300, id = 0, name = "300 Steps!" },
	{ threshold = 500, id = 0, name = "500 Steps!" },
	{ kind = "level", level = "Kitchen", threshold = 0, id = 0, name = "Out of the Pot" },
	{ kind = "level", level = "Country", threshold = 0, id = 0, name = "Country Frog" },
	{ kind = "streak", threshold = 3, id = 0, name = "3-Day Streak" },
	{ kind = "streak", threshold = 7, id = 0, name = "7-Day Streak" },
	{ kind = "streak", threshold = 30, id = 0, name = "30-Day Streak" },
}

return Badges
