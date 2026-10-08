-- ServerScriptService/Server/Profiles (ModuleScript)
-- The single per-player profile: one DataStore, one cache, one schema shared by
-- every server system (skins, Fly currency, gifts, high score). This is the
-- "consolidate all per-player state behind one profile" the docs call for
-- (see ../../docs/roblox-port/08-frog-skins-and-store.md and 09-gifts-and-ads.md).
--
-- Other server scripts: require this, read/write `Profiles.get(player)`, call
-- `Profiles.save(player)` after meaningful changes, and react to `Profiles.Loaded`.
--
-- Hardening notes (see docs/roblox-port/07-multiplayer.md, 09-gifts-and-ads.md):
--   * Saves merge onto whatever is currently stored (via UpdateAsync) instead of
--     blindly overwriting it, so a slow/late write can never lower highScore,
--     drop an owned skin, or lose a processed purchase receipt.
--   * A small session lock (owner = this server's JobId, stamped with os.time())
--     rides along in the same record so a player rejoining a new server before
--     the old one's save lands doesn't load stale data out from under it.
--   * DataStore calls are retried with exponential backoff; a profile that never
--     manages to load is marked non-saveable (Profiles.loadFailed) so it can't
--     later stomp the player's real data with a fresh default.
--   * In Studio with API access to DataStores disabled, the module degrades to
--     in-memory-only profiles after a single warn instead of erroring on every call.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Catalog = require(ReplicatedStorage.Shared.SkinCatalog)

export type Profile = {
	highScore: number,
	flys: number,
	owned: { [number]: boolean },
	selected: number,
	applied: { [string]: boolean }, -- processed Developer Product receipt ids
	giftSeed: number,
	lastGift: number,
	musicOn: boolean, -- Unity VariableManager.IsPlayingMusic
	tutorialDone: boolean,
	bugsCaught: number, -- lifetime stat; Unity VariableManager.BugsCaught
	streak: number, -- daily login streak length (DailyService; not in Unity)
	streakDay: number, -- UTC day index (os.time() // 86400) of the last daily claim, 0 = never
	missionDay: number, -- UTC day index the `missions` progress belongs to (MissionService; not in Unity)
	missions: { [string]: number }, -- daily mission id -> progress, clamped to its target
	jarFlys: number, -- lifetime Flys fed into the Fly Jar (SkinService FeedJar; JarTiers titles; not in Unity)
}

-- What actually lives at the DataStore key: the profile plus the session lock.
-- (Older saves from before this record wrapper existed are a bare Profile-shaped
-- table at the top level; `unwrap` below handles both.)
type StoredLock = { owner: string, at: number }
type StoredRecord = { profile: any, lock: StoredLock? }

local store = DataStoreService:GetDataStore("HotfrogProfiles_v1")
local orderedBest = DataStoreService:GetOrderedDataStore("HotfrogGlobalBest_v1")
-- Daily/weekly boards: one OrderedDataStore per period, keyed by period index
-- (see periodKeys below), fetched lazily so old periods are never touched again.
local periodStores: { [string]: OrderedDataStore } = {}
-- Best score already written to the current day/week board this session, per
-- player, so a run only costs an OrderedDataStore write when it beats it.
type PeriodBest = { day: number, dayBest: number, week: number, weekBest: number }
local periodBest: { [Player]: PeriodBest } = {}
local cache: { [Player]: Profile } = {}
local loadFailed: { [Player]: boolean } = {}
local loadedEvent = Instance.new("BindableEvent")

local Profiles = {}
Profiles.Loaded = loadedEvent.Event -- fires (player, profile) once a profile is ready

-- Identifies this server for the session lock. game.JobId is "" in Studio, so
-- fall back to a per-run GUID (only meaningful if the Studio probe below finds
-- API access actually enabled).
local STUDIO_OWNER_PREFIX = "studio-"
local SESSION_ID = if game.JobId ~= "" then game.JobId else STUDIO_OWNER_PREFIX .. HttpService:GenerateGUID(false)

local AUTOSAVE_INTERVAL = 120 -- seconds between periodic full-profile autosaves
local SAVE_ATTEMPTS, SAVE_RETRY_BASE = 3, 1 -- ~1s, 2s backoff (bounded ~3s worst case)
local LOAD_ATTEMPTS, LOAD_RETRY_BASE = 5, 1 -- ~1s,2s,4s,8s backoff (bounded ~15s worst case)
local LOCK_STALE_SECONDS = 300 -- a lock this old is an abandoned/crashed session -- steal it
local SHUTDOWN_BUDGET = 25 -- seconds; BindToClose gets ~30s from Roblox, leave headroom
local UPDATE_REQUEST_TYPE = Enum.DataStoreRequestType.UpdateAsync

-- Set once at startup: true only when we're in Studio and a DataStore call
-- actually failed, i.e. "Studio Access to API Services" is off. Live servers
-- never set this -- a real outage there goes through the retry/warn path instead.
local apiAccessDisabled = false

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

local function defaultProfile(): Profile
	local owned: { [number]: boolean } = {}
	for id, entry in pairs(Catalog) do
		if entry.default then
			owned[id] = true
		end
	end
	return {
		highScore = 0,
		flys = 0,
		owned = owned,
		selected = 1,
		applied = {},
		giftSeed = 0,
		lastGift = 0,
		musicOn = true,
		tutorialDone = false,
		bugsCaught = 0,
		streak = 0,
		streakDay = 0,
		missionDay = 0,
		missions = {},
		jarFlys = 0,
	}
end

-- Always (re)grant default skins, in case the roster gained new free ones since
-- this profile was last saved.
local function grantDefaultSkins(p: Profile)
	for id, entry in pairs(Catalog) do
		if entry.default then
			p.owned[id] = true
		end
	end
end

-- Merge a loaded DataStore table onto a fresh default (forward-compatible; numeric
-- keys come back from JSON as strings, so coerce them).
local function reconcile(p: Profile, data: any)
	if type(data) ~= "table" then
		return
	end
	p.highScore = tonumber(data.highScore) or p.highScore
	p.flys = tonumber(data.flys) or p.flys
	p.selected = tonumber(data.selected) or p.selected
	p.giftSeed = tonumber(data.giftSeed) or p.giftSeed
	p.lastGift = tonumber(data.lastGift) or p.lastGift
	p.bugsCaught = tonumber(data.bugsCaught) or p.bugsCaught
	p.streak = tonumber(data.streak) or p.streak
	p.streakDay = tonumber(data.streakDay) or p.streakDay
	p.missionDay = tonumber(data.missionDay) or p.missionDay
	p.jarFlys = tonumber(data.jarFlys) or p.jarFlys
	if type(data.missions) == "table" then
		for k, v in pairs(data.missions) do
			p.missions[tostring(k)] = tonumber(v) or 0
		end
	end
	if type(data.musicOn) == "boolean" then
		p.musicOn = data.musicOn
	end
	if type(data.tutorialDone) == "boolean" then
		p.tutorialDone = data.tutorialDone
	end
	if type(data.owned) == "table" then
		for k, v in pairs(data.owned) do
			local id = tonumber(k)
			if id and v then
				p.owned[id] = true
			end
		end
	end
	if type(data.applied) == "table" then
		for k, v in pairs(data.applied) do
			if v then
				p.applied[tostring(k)] = true
			end
		end
	end
end

-- Pull the Profile-shaped table out of a raw DataStore value, whether it's the
-- new { profile, lock } envelope or an old bare-profile save.
local function unwrapProfile(data: any): any
	if type(data) == "table" and type(data.profile) == "table" then
		return data.profile
	end
	return data
end

local function unwrapLock(data: any): StoredLock?
	if type(data) == "table" and type(data.lock) == "table" then
		return data.lock
	end
	return nil
end

-- Runs `fn` up to `attempts` times with exponential backoff (base, base*2, ...),
-- warning with `context` on final failure. Mirrors pcall's (ok, result) shape.
local function withRetry(fn: () -> any, attempts: number, base: number, context: string): (boolean, any)
	local lastResult: any = nil
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastResult = result
		if i < attempts then
			task.wait(base * (2 ^ (i - 1)))
		end
	end
	warn(("[Profiles] %s failed after %d attempt(s): %s"):format(context, attempts, tostring(lastResult)))
	return false, lastResult
end

-- One-time Studio probe: if DataStore API access is off, every real call would
-- otherwise error the same way forever. Detect it once and degrade quietly.
local function probeStudioAccess()
	if not RunService:IsStudio() then
		return
	end
	local ok, err = pcall(function()
		store:GetAsync("__hotfrog_probe__")
	end)
	if not ok then
		apiAccessDisabled = true
		warn(
			"[Profiles] Studio API access to DataStores is unavailable ('"
				.. tostring(err)
				.. "'); using in-memory, non-persisted profiles for this session. "
				.. 'Enable "Studio Access to API Services" in Game Settings to test persistence locally.'
		)
	end
end
probeStudioAccess()

-- Build the record to write for `p`, merging onto whatever `old` (the value
-- UpdateAsync just handed us) already holds so a stale/slow writer can never
-- lower highScore, bugsCaught or jarFlys, drop an owned skin, or un-apply a receipt.
local function mergeForSave(old: any, p: Profile, release: boolean): StoredRecord
	local merged: Profile = {
		highScore = p.highScore,
		flys = p.flys,
		owned = {},
		selected = p.selected,
		applied = {},
		giftSeed = p.giftSeed,
		lastGift = p.lastGift,
		musicOn = p.musicOn,
		tutorialDone = p.tutorialDone,
		bugsCaught = p.bugsCaught,
		streak = p.streak,
		streakDay = p.streakDay,
		missionDay = p.missionDay,
		missions = table.clone(p.missions),
		jarFlys = p.jarFlys,
	}
	for id in pairs(p.owned) do
		merged.owned[id] = true
	end
	for id in pairs(p.applied) do
		merged.applied[id] = true
	end

	local oldProfile = unwrapProfile(old)
	if type(oldProfile) == "table" then
		local oldHighScore = tonumber(oldProfile.highScore)
		if oldHighScore and oldHighScore > merged.highScore then
			merged.highScore = oldHighScore
		end
		local oldBugs = tonumber(oldProfile.bugsCaught)
		if oldBugs and oldBugs > merged.bugsCaught then
			merged.bugsCaught = oldBugs
		end
		-- The jar only ever fills, so a stale writer can't empty it.
		local oldJar = tonumber(oldProfile.jarFlys)
		if oldJar and oldJar > merged.jarFlys then
			merged.jarFlys = oldJar
		end
		-- A stale writer must not roll the daily streak back (that would let the
		-- same UTC day be claimed twice): keep whichever claim day is newer.
		local oldStreakDay = tonumber(oldProfile.streakDay)
		if oldStreakDay and oldStreakDay > merged.streakDay then
			merged.streakDay = oldStreakDay
			merged.streak = tonumber(oldProfile.streak) or merged.streak
		end
		-- Same for daily missions: a newer day wins outright, the same day keeps
		-- the higher progress per mission, so a reward can't be earned twice.
		local oldMissionDay = tonumber(oldProfile.missionDay) or 0
		local oldMissions = if type(oldProfile.missions) == "table" then oldProfile.missions else {}
		if oldMissionDay > merged.missionDay then
			merged.missionDay = oldMissionDay
			merged.missions = {}
		end
		if oldMissionDay == merged.missionDay then
			for k, v in pairs(oldMissions) do
				local n = tonumber(v)
				if n and n > (merged.missions[tostring(k)] or 0) then
					merged.missions[tostring(k)] = n
				end
			end
		end
		if type(oldProfile.owned) == "table" then
			for k, v in pairs(oldProfile.owned) do
				local id = tonumber(k)
				if id and v then
					merged.owned[id] = true
				end
			end
		end
		if type(oldProfile.applied) == "table" then
			for k, v in pairs(oldProfile.applied) do
				if v then
					merged.applied[tostring(k)] = true
				end
			end
		end
	end

	return {
		profile = merged,
		lock = if release then nil else { owner = SESSION_ID, at = os.time() },
	}
end

function Profiles.get(player: Player): Profile?
	return cache[player]
end

-- True once a profile failed to load after retries: gameplay proceeds on an
-- in-memory default, but that default is never persisted (see `doSave`), so it
-- can't overwrite the player's real save once the underlying issue clears up.
function Profiles.loadFailed(player: Player): boolean
	return loadFailed[player] == true
end

local function doSave(player: Player, release: boolean): boolean
	local p = cache[player]
	if not p then
		return false
	end
	if apiAccessDisabled or loadFailed[player] then
		return false
	end
	local key = keyFor(player)
	local ok = withRetry(function()
		store:UpdateAsync(key, function(old: any)
			return mergeForSave(old, p, release)
		end)
	end, SAVE_ATTEMPTS, SAVE_RETRY_BASE, "save for " .. key)
	return ok
end

function Profiles.save(player: Player)
	doSave(player, false)
end

-- Mirror a new personal best into the OrderedDataStore so a global top-N is
-- queryable (doc 07, Leaderboard & persistence). Call when highScore improves.
-- UpdateAsync + max() so a slow/late write can never lower the stored best.
function Profiles.recordGlobalBest(player: Player, best: number)
	if apiAccessDisabled then
		return
	end
	local key = keyFor(player)
	withRetry(function()
		orderedBest:UpdateAsync(key, function(old: any)
			local oldBest = tonumber(old)
			if oldBest and oldBest > best then
				return oldBest
			end
			return best
		end)
	end, SAVE_ATTEMPTS, SAVE_RETRY_BASE, "recordGlobalBest for " .. key)
end

-- Period indices for the daily/weekly boards, both UTC: day = days since the
-- Unix epoch; week = (day + 3) // 7, i.e. weeks run Monday 00:00 UTC to
-- Sunday 23:59 UTC (epoch day 0 was a Thursday, so +3 puts the boundary on
-- Monday). Not the ISO week number, just a monotonic Monday-aligned index.
function Profiles.periodKeys(): (number, number)
	local day = os.time() // 86400
	return day, (day + 3) // 7
end

local function periodStore(name: string): OrderedDataStore
	local s = periodStores[name]
	if not s then
		s = DataStoreService:GetOrderedDataStore(name)
		periodStores[name] = s
	end
	return s
end

local function dailyStore(day: number): OrderedDataStore
	return periodStore("HotfrogDailyBest_v1_d" .. day)
end

local function weeklyStore(week: number): OrderedDataStore
	return periodStore("HotfrogWeeklyBest_v1_w" .. week)
end

local function writeMax(ordered: OrderedDataStore, key: string, score: number, context: string)
	withRetry(function()
		ordered:UpdateAsync(key, function(old: any)
			local oldBest = tonumber(old)
			if oldBest and oldBest >= score then
				return nil -- cancel: nothing to raise, saves the write
			end
			return score
		end)
	end, SAVE_ATTEMPTS, SAVE_RETRY_BASE, context)
end

-- Record a finished run on the daily and weekly boards. Called for every run;
-- only writes the period(s) whose in-session best this score beats (UpdateAsync
-- + max covers a best set earlier on another server). Yields; spawn it.
function Profiles.recordPeriodScore(player: Player, score: number)
	if apiAccessDisabled or score <= 0 then
		return
	end
	local day, week = Profiles.periodKeys()
	local pb = periodBest[player]
	if not pb then
		pb = { day = day, dayBest = 0, week = week, weekBest = 0 }
		periodBest[player] = pb
	end
	if pb.day ~= day then
		pb.day, pb.dayBest = day, 0
	end
	if pb.week ~= week then
		pb.week, pb.weekBest = week, 0
	end
	local key = keyFor(player)
	if score > pb.dayBest then
		pb.dayBest = score
		writeMax(dailyStore(day), key, score, "recordPeriodScore (day) for " .. key)
	end
	if score > pb.weekBest then
		pb.weekBest = score
		writeMax(weeklyStore(week), key, score, "recordPeriodScore (week) for " .. key)
	end
end

export type TopEntry = { userId: number, score: number }
export type Period = "all" | "daily" | "weekly"

-- Global top-N for a world-leaderboard surface: all-time personal bests, or
-- the current UTC day's / week's best runs. Returns an empty list on
-- DataStore failure rather than erroring.
function Profiles.topScores(count: number, period: Period?): { TopEntry }
	local results: { TopEntry } = {}
	if apiAccessDisabled then
		return results
	end
	local ordered = orderedBest
	if period == "daily" or period == "weekly" then
		local day, week = Profiles.periodKeys()
		ordered = if period == "daily" then dailyStore(day) else weeklyStore(week)
	end
	local ok, pages = pcall(function()
		return ordered:GetSortedAsync(false, math.clamp(count, 1, 100))
	end)
	if not ok then
		return results
	end
	for _, entry in pages:GetCurrentPage() do
		local userId = tonumber(string.match(entry.key, "%d+"))
		if userId then
			table.insert(results, { userId = userId, score = tonumber(entry.value) or 0 })
		end
	end
	return results
end

local function load(player: Player)
	loadFailed[player] = nil
	player:SetAttribute("ProfileLoadFailed", false)

	if apiAccessDisabled then
		local p = defaultProfile()
		grantDefaultSkins(p)
		cache[player] = p
		loadedEvent:Fire(player, p)
		return
	end

	local key = keyFor(player)
	local data: any = nil
	local everSucceeded = false
	local lastErr: any = nil

	-- Fetch-and-check-lock loop: doubles as transient-error retry (a real
	-- outage just keeps failing every attempt) and as the "wait for the old
	-- session's release" retry (a healthy lock clears within a save or two).
	-- If the lock is still fresh after every attempt we proceed anyway rather
	-- than block the player from ever joining -- the merge-safe save below
	-- means that race can't drop highScore/owned/applied even in that case.
	--
	-- The read is an UpdateAsync so that, when the lock is free, we stamp OUR lock
	-- in the same atomic step -- a plain GetAsync would leave the record unlocked
	-- until the first save, which is exactly the window a quick rejoin lands in.
	-- Returning nil from the transform cancels the write (lock held elsewhere).
	for attempt = 1, LOAD_ATTEMPTS do
		local free = false
		local forceSteal = attempt == LOAD_ATTEMPTS
		local ok, result = pcall(function()
			local seen: any = nil
			store:UpdateAsync(key, function(old: any)
				seen = old
				local lock = unwrapLock(old)
				-- Every Studio Play session mints a fresh random SESSION_ID (game.JobId
				-- is "" in Studio), so back-to-back playtests always look like a foreign
				-- server to each other even though there's only ever one tester. A lock
				-- left by a *previous Studio session* can never be a live production
				-- server (those always own game.JobId, never "studio-" prefixed), so
				-- it's safe to take over immediately instead of paying the full
				-- stale-lock wait -- this can't weaken the lock for real servers since
				-- IsStudio() is false there.
				local staleStudioLock = RunService:IsStudio()
					and lock ~= nil
					and lock.owner ~= SESSION_ID
					and lock.owner:sub(1, #STUDIO_OWNER_PREFIX) == STUDIO_OWNER_PREFIX
				free = lock == nil
					or lock.owner == SESSION_ID
					or (os.time() - lock.at) >= LOCK_STALE_SECONDS
					or staleStudioLock
				if not free and not forceSteal then
					return nil
				end
				return { profile = unwrapProfile(old), lock = { owner = SESSION_ID, at = os.time() } }
			end)
			return seen
		end)
		if ok then
			everSucceeded = true
			data = result
			if free or forceSteal then
				break
			end
		else
			lastErr = result
		end
		if attempt < LOAD_ATTEMPTS then
			task.wait(LOAD_RETRY_BASE * (2 ^ (attempt - 1)))
		end
	end

	if not everSucceeded then
		warn(
			("[Profiles] Failed to load profile for %s (%d) after %d attempt(s): %s -- "):format(
				player.Name,
				player.UserId,
				LOAD_ATTEMPTS,
				tostring(lastErr)
			) .. "using a temporary profile that will NOT be saved, so their real data isn't overwritten."
		)
		loadFailed[player] = true
		player:SetAttribute("ProfileLoadFailed", true)
		local p = defaultProfile()
		grantDefaultSkins(p)
		cache[player] = p
		loadedEvent:Fire(player, p)
		return
	end

	local lock = unwrapLock(data)
	local wasStaleStudioLock = RunService:IsStudio()
		and lock ~= nil
		and lock.owner ~= SESSION_ID
		and lock.owner:sub(1, #STUDIO_OWNER_PREFIX) == STUDIO_OWNER_PREFIX
	if lock and lock.owner ~= SESSION_ID and (os.time() - lock.at) < LOCK_STALE_SECONDS and not wasStaleStudioLock then
		warn(
			("[Profiles] %s (%d): session lock still held by %s after waiting -- proceeding anyway."):format(
				player.Name,
				player.UserId,
				tostring(lock.owner)
			)
		)
	end

	local p = defaultProfile()
	reconcile(p, unwrapProfile(data))
	grantDefaultSkins(p)
	cache[player] = p
	loadedEvent:Fire(player, p)
end

Players.PlayerAdded:Connect(load)
for _, player in Players:GetPlayers() do
	task.spawn(load, player) -- in case this module loads after players joined
end

Players.PlayerRemoving:Connect(function(player)
	doSave(player, true) -- final save; release the session lock
	cache[player] = nil
	loadFailed[player] = nil
	periodBest[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		if not apiAccessDisabled then
			for player in cache do
				if not loadFailed[player] then
					-- Don't blow the UpdateAsync request budget: stop issuing new
					-- saves this cycle once it's exhausted, pick the rest up next tick.
					local budget = DataStoreService:GetRequestBudgetForRequestType(UPDATE_REQUEST_TYPE)
					if budget < 1 then
						break
					end
					task.spawn(Profiles.save, player)
				end
			end
		end
	end
end)

game:BindToClose(function()
	if apiAccessDisabled then
		return
	end
	local players: { Player } = {}
	for player in cache do
		table.insert(players, player)
	end
	if #players == 0 then
		return
	end
	local remaining = #players
	for _, player in players do
		task.spawn(function()
			doSave(player, true) -- release the lock so the next server doesn't wait on us
			remaining -= 1
		end)
	end
	local deadline = os.clock() + SHUTDOWN_BUDGET
	while remaining > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	if remaining > 0 then
		warn(("[Profiles] BindToClose timed out with %d profile(s) still saving"):format(remaining))
	end
end)

return Profiles
