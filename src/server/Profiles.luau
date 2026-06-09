-- ServerScriptService/Server/Profiles (ModuleScript)
-- The single per-player profile: one DataStore, one cache, one schema shared by
-- every server system (skins, Fly currency, gifts, high score). This is the
-- "consolidate all per-player state behind one profile" the docs call for
-- (see ../../docs/roblox-port/08-frog-skins-and-store.md and 09-gifts-and-ads.md).
--
-- Other server scripts: require this, read/write `Profiles.get(player)`, call
-- `Profiles.save(player)` after meaningful changes, and react to `Profiles.Loaded`.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.SkinCatalog)

export type Profile = {
	highScore: number,
	flys: number,
	owned: { [number]: boolean },
	selected: number,
	applied: { [string]: boolean }, -- processed Developer Product receipt ids
	giftSeed: number,
	lastGift: number,
}

local store = DataStoreService:GetDataStore("HotfrogProfiles_v1")
local cache: { [Player]: Profile } = {}
local loadedEvent = Instance.new("BindableEvent")

local Profiles = {}
Profiles.Loaded = loadedEvent.Event -- fires (player, profile) once a profile is ready

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
	}
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

function Profiles.get(player: Player): Profile?
	return cache[player]
end

function Profiles.save(player: Player)
	local p = cache[player]
	if not p then
		return
	end
	pcall(function()
		store:SetAsync(keyFor(player), p)
	end)
end

local function load(player: Player)
	local ok, data = pcall(function()
		return store:GetAsync(keyFor(player))
	end)
	local p = defaultProfile()
	if ok then
		reconcile(p, data)
	end
	-- always (re)grant default skins, in case the roster gained new free ones
	for id, entry in pairs(Catalog) do
		if entry.default then
			p.owned[id] = true
		end
	end
	cache[player] = p
	loadedEvent:Fire(player, p)
end

Players.PlayerAdded:Connect(load)
for _, player in Players:GetPlayers() do
	task.spawn(load, player) -- in case this module loads after players joined
end

Players.PlayerRemoving:Connect(function(player)
	Profiles.save(player)
	cache[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(120) -- periodic autosave
		for player in cache do
			Profiles.save(player)
		end
	end
end)

game:BindToClose(function()
	for player in cache do
		Profiles.save(player)
	end
end)

return Profiles
