--!strict
-- StarterPlayerScripts/Client/WorldBugs (LocalScript)
-- Cosmetic bug dressing: wing flutter and a golden-bug glow pulse. Unity's
-- Bug prefab animates its wing sprite in the Animator (Entities/Bug.cs only
-- moves/leaves); here the server's bug Part carries a static `Wings` decal, so
-- each client cycles that decal through Wing1/Wing2/Wing3 locally.
--
-- Reads replicated state only and never moves or reparents a server part:
-- BugService owns the pooled parts under workspace.PlayField.Bugs, and the only
-- thing written here is a Decal's Texture/Color3 (a local override of a
-- server-set value; the server only rewrites those at spawn, and a changed
-- value replicates over ours). Every lane's bugs flutter, not just the local one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SkinAssets = require(ReplicatedStorage.Shared.SkinAssets)

local FLUTTER_HZ = 12
local FRAMES = { "Wing1", "Wing2", "Wing3" }
local GLOW_HZ = 2.5 -- golden pulse rate
local GLOW_BRIGHT = Color3.fromRGB(255, 244, 170)

local bugsFolder = workspace:WaitForChild("PlayField"):WaitForChild("Bugs")

type Tracked = {
	wings: Decal?,
	art: Decal?,
	phase: number, -- random frame/glow offset so a group doesn't flap in unison
	frame: number,
}

local tracked: { [BasePart]: Tracked } = {}
local frameImages: { string? } = {}
for i, stem in FRAMES do
	frameImages[i] = SkinAssets.image(stem)
end

local function track(inst: Instance)
	if not inst:IsA("BasePart") or tracked[inst] then
		return
	end
	local wings: Decal? = nil
	local art: Decal? = nil
	for _, child in inst:GetChildren() do
		if child:IsA("Decal") then
			local stem = child:GetAttribute("Sprite")
			if typeof(stem) == "string" then
				if string.sub(stem, 1, 4) == "Wing" then
					wings = child
				elseif stem == "Bug" then
					art = child
				end
			end
		end
	end
	tracked[inst] = { wings = wings, art = art, phase = math.random() * 10, frame = 0 }
end

bugsFolder.ChildAdded:Connect(track)
bugsFolder.ChildRemoved:Connect(function(inst: Instance)
	if inst:IsA("BasePart") then
		tracked[inst] = nil -- pooled parts re-enter through ChildAdded, which re-tracks them
	end
end)
for _, child in bugsFolder:GetChildren() do
	track(child)
end

RunService.PreRender:Connect(function()
	local now = os.clock()
	for bug, t in tracked do
		local wings = t.wings
		if wings then
			local frame = (math.floor(now * FLUTTER_HZ + t.phase) % #FRAMES) + 1
			if frame ~= t.frame then
				t.frame = frame
				local image = frameImages[frame]
				if image then
					wings.Texture = image -- nil id (not uploaded) leaves the authored placeholder
				end
			end
		end
		local art = t.art
		if art and bug:GetAttribute("Golden") == true then
			-- soft pulse between the server's gold tint and a brighter highlight
			local k = 0.5 + 0.5 * math.sin(now * GLOW_HZ * math.pi * 2 + t.phase)
			art.Color3 = (Config.GOLDEN_BUG_COLOR :: Color3):Lerp(GLOW_BRIGHT, k)
		end
	end
end)
