--!strict
-- StarterPlayerScripts/Client/world/Lanes (ModuleScript)
-- Lane discovery + bounds math shared by the World* cosmetic scripts (doc 13:
-- `workspace.PlayField.Lanes/<UserId>` folders carrying `Origin` / `Level` /
-- `RunState` attributes are the discovery contract). Before this module
-- WorldScenery, WorldBackdrop and WorldLava each re-implemented the folder
-- lookup, the origin read and the out-of-bounds test. Every wait here takes
-- WorldConfig.LANE_WAIT_TIMEOUT and returns nil on timeout, so a caller must
-- handle nil; the default timeout is unbounded (see WorldConfig for why).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local Lanes = {}

-- workspace.PlayField.Lanes, or nil if the server never created it in time.
function Lanes.container(timeout: number?): Folder?
	local limit = timeout or WorldConfig.LANE_WAIT_TIMEOUT
	local playField = workspace:WaitForChild("PlayField", limit)
	local lanes = if playField then playField:WaitForChild("Lanes", limit) else nil
	if lanes and lanes:IsA("Folder") then
		return lanes
	end
	return nil
end

-- The local player's own lane folder (nil on timeout).
function Lanes.waitForLocal(timeout: number?): Folder?
	local container = Lanes.container(timeout)
	if not container then
		return nil
	end
	local lane = container:WaitForChild(tostring(Players.LocalPlayer.UserId), timeout or WorldConfig.LANE_WAIT_TIMEOUT)
	if lane and lane:IsA("Folder") then
		return lane
	end
	return nil
end

-- The lane's world-space origin (its `Origin` attribute; zero until it replicates).
function Lanes.originOf(folder: Folder): Vector3
	local origin = folder:GetAttribute("Origin")
	return if typeof(origin) == "Vector3" then origin else Vector3.zero
end

-- Call `onChanged(origin)` whenever the lane's origin is rewritten (level start /
-- relayout). Returns the connection so the caller can drop it with the lane.
function Lanes.watchOrigin(folder: Folder, onChanged: (Vector3) -> ()): RBXScriptConnection
	return folder:GetAttributeChangedSignal("Origin"):Connect(function()
		onChanged(Lanes.originOf(folder))
	end)
end

-- Run `onAdded` for every lane that exists now and every one that appears later,
-- `onRemoved` when one goes. Returns a function that stops the observation.
function Lanes.observe(onAdded: (Folder) -> (), onRemoved: ((Folder) -> ())?): () -> ()
	local container = Lanes.container()
	if not container then
		warn("[Lanes] workspace.PlayField.Lanes never appeared; lane-driven cosmetics are disabled")
		return function() end
	end
	local added = container.ChildAdded:Connect(function(child)
		if child:IsA("Folder") then
			onAdded(child)
		end
	end)
	local removed = container.ChildRemoved:Connect(function(child)
		if onRemoved and child:IsA("Folder") then
			onRemoved(child)
		end
	end)
	for _, child in container:GetChildren() do
		if child:IsA("Folder") then
			onAdded(child)
		end
	end
	return function()
		added:Disconnect()
		removed:Disconnect()
	end
end

-- Is `x` inside this lane's horizontal band, widened by `margin` studs?
function Lanes.inXBand(origin: Vector3, x: number, margin: number): boolean
	return math.abs(x - origin.X) <= Config.LANE_HALF_WIDTH + margin
end

-- Measured against the part's own EXTENT (`halfX`/`halfY`), not just its centre:
-- a scenery part is its sprite's whole Unity canvas (up to ~129 studs for the US
-- map), so a centre-only test would recycle one while most of it is still on
-- screen. Same rule as Lane.isOutOfBounds server-side, and the same one Unity
-- gets from recycling on collider/border contact rather than on centres.
function Lanes.isOutOfBounds(origin: Vector3, position: Vector3, halfX: number, halfY: number, margin: number?): boolean
	local m = margin or WorldConfig.SCENERY_BOUNDS_MARGIN
	local relX = position.X - origin.X
	local boundX = Config.LANE_HALF_WIDTH + m
	if relX + halfX < -boundX or relX - halfX > boundX then
		return true
	end
	return (position.Y + halfY) < (Config.DESPAWN_Y - m) or (position.Y - halfY) > (Config.SPAWN_Y + m)
end

return Lanes
