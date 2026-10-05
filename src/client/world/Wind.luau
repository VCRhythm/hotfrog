--!strict
-- StarterPlayerScripts/Client/world/Wind (ModuleScript)
-- Per-lane gust value for the Country level's ambient wind (ADAPTED/additive --
-- Unity has no wind). A gust is a timer-driven pulse: a quiet gap, then an
-- ease-in/ease-out swell (sin^2 envelope) over a few seconds. step() returns the
-- smoothed 0..1 strength; WorldScenery scales leaf/cloud drift and scenery sway
-- by it. Purely a number -- no Instances, no remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local Wind = {}
Wind.__index = Wind

export type Wind = typeof(setmetatable(
	{} :: {
		_timer: number, -- seconds until the next gust starts
		_elapsed: number, -- seconds into the running gust (< 0 = none running)
		_duration: number,
		gust: number, -- smoothed 0..1 strength, what consumers read
	},
	Wind
))

local function between(min: number, max: number): number
	return min + math.random() * (max - min)
end

function Wind.new(): Wind
	return setmetatable({
		_timer = between(WorldConfig.WIND_GUST_INTERVAL_MIN, WorldConfig.WIND_GUST_INTERVAL_MAX) * 0.5,
		_elapsed = -1,
		_duration = 0,
		gust = 0,
	}, Wind)
end

function Wind.step(self: Wind, dt: number, enabled: boolean): number
	local envelope = 0
	if self._elapsed >= 0 then
		self._elapsed += dt
		if self._elapsed >= self._duration then
			self._elapsed = -1
			self._timer = between(WorldConfig.WIND_GUST_INTERVAL_MIN, WorldConfig.WIND_GUST_INTERVAL_MAX)
		else
			local s = math.sin(math.pi * self._elapsed / self._duration)
			envelope = s * s
		end
	elseif enabled then
		self._timer -= dt
		if self._timer <= 0 then
			self._elapsed = 0
			self._duration = between(WorldConfig.WIND_GUST_DURATION_MIN, WorldConfig.WIND_GUST_DURATION_MAX)
		end
	end
	local target = if enabled then envelope else 0
	-- Extra smoothing so leaving a windy level (or a gust ending abruptly because the
	-- lane was switched) eases out instead of snapping.
	self.gust += (target - self.gust) * math.clamp(dt * WorldConfig.WIND_RESPONSE_RATE, 0, 1)
	if self.gust < 1e-3 and target == 0 then
		self.gust = 0
	end
	return self.gust
end

return Wind
