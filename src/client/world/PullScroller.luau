--!strict
-- StarterPlayerScripts/Client/world/PullScroller (ModuleScript)
-- The ONE driver for a lane's cosmetic pull. GameServer publishes every pull
-- as lane-folder attributes (`PullDelta` / `PullTime` / `PullCount`, plus the
-- `PullLinear` / `PullTotal` / `PullEpoch` described below); the server plays a
-- grab's pull as a Sine/Out eased displacement on its own clock, and pulls
-- ADD UP rather than cancelling (Lane.addMotion / advanceMotions). This module
-- mirrors that exactly on the client: each PullCount bump queues a motion, and
-- step(dt) -- called once per frame by the consumer -- returns the eased
-- displacement that frame owes. The consumer applies it (x its own parallax
-- factor) in its single per-frame write.
--
-- It replaces the old per-part TweenService tweens in WorldScenery and the
-- instant, un-eased `Position +=` in WorldBackdrop: those could outlive a recycled
-- part (a pooled part re-acquired while its old pull tween still wrote Position
-- teleported), stacked fighting tweens on overlapping pulls, and fought the
-- per-frame autoMove drift. No Instances are created here.
--
-- Each consumer owns its own Scroller: the easing is a pure function of the
-- accumulated frame dt, so two scrollers fed the same dt agree exactly and no
-- cross-script frame-ordering contract is needed.
--
-- Lossless. Attribute changes made in one server frame can reach a client as a
-- single change, so two pulls published together (a Classic drift chunk and a
-- grab's pull, the Tutorial pull-back and another) used to show up as one
-- PullCount bump carrying only the SECOND delta, and the cosmetics stayed out of
-- step with the real steps for the rest of the run. The server therefore also
-- publishes `PullTotal`, the sum of every delta since the lane's pulls last
-- started over, and this module queues whatever part of it it has not queued
-- yet: the latest pull as published, plus one extra motion for anything missed.
-- `PullEpoch` changes whenever the server restarts that total (Lane.resetRun: a
-- death, Replay Tutorial), so the drop back to zero is a new baseline and never
-- played as a pull; motions already queued simply finish.
--
-- `PullLinear` marks a Classic drift chunk: the steps travelled it at constant
-- speed, so it is played linearly. Eased like a grab, a chunk every
-- CLASSIC_CHUNK_TIME made the scenery surge at 2 Hz beside steadily moving steps.

local Scroller = {}
Scroller.__index = Scroller

type Motion = { delta: Vector3, duration: number, elapsed: number, linear: boolean }

export type Scroller = typeof(setmetatable(
	{} :: {
		_folder: Folder,
		_motions: { Motion },
		_conns: { RBXScriptConnection },
		_seen: Vector3, -- the part of PullTotal already queued
		_epoch: number?, -- the PullEpoch `_seen` belongs to
	},
	Scroller
))

local PullScroller = {}

-- Totals are float32 sums; a difference below this is rounding, not a pull.
local EPSILON = 1e-3

-- Sine/Out, the curve Lane.eased uses server-side; linear for a drift chunk.
local function eased(motion: Motion, elapsed: number): number
	if motion.duration <= 0 then
		return 1
	end
	local alpha = math.clamp(elapsed / motion.duration, 0, 1)
	return if motion.linear then alpha else math.sin(alpha * math.pi / 2)
end

local function epochOf(folder: Folder): number?
	local epoch = folder:GetAttribute("PullEpoch")
	return if typeof(epoch) == "number" then epoch else nil
end

-- Queue whatever the lane has published that this scroller has not queued yet.
-- `counted` is true when called for a PullCount bump, which is all an older
-- server without PullTotal ever sends. Safe to call any number of times for the
-- same published state: once the total is accounted for there is nothing owed.
local function sync(self: Scroller, counted: boolean)
	local folder = self._folder
	local delta = folder:GetAttribute("PullDelta")
	local pullTime = folder:GetAttribute("PullTime")
	if typeof(delta) ~= "Vector3" or typeof(pullTime) ~= "number" then
		return
	end
	local linear = folder:GetAttribute("PullLinear") == true
	local motions = self._motions

	local total = folder:GetAttribute("PullTotal")
	if typeof(total) ~= "Vector3" then
		if counted then
			table.insert(motions, { delta = delta, duration = pullTime, elapsed = 0, linear = linear })
		end
		return
	end

	local epoch = epochOf(folder)
	if epoch ~= self._epoch then
		self._epoch = epoch
		self._seen = Vector3.zero -- the server's total started over
	end
	local owed = total - self._seen
	self._seen = total
	if owed.Magnitude < EPSILON then
		return
	end
	-- The latest pull exactly as published (the total only ever changes by a
	-- publish, so it is always part of what is owed), and anything before it
	-- that never arrived as one eased motion over the same time. The two always
	-- sum to `owed`, so the scroll stays exact whatever was merged.
	table.insert(motions, { delta = delta, duration = pullTime, elapsed = 0, linear = linear })
	local missed = owed - delta
	if missed.Magnitude >= EPSILON then
		table.insert(motions, { delta = missed, duration = pullTime, elapsed = 0, linear = false })
	end
end

function PullScroller.new(folder: Folder): Scroller
	local total = folder:GetAttribute("PullTotal")
	local self = setmetatable({
		_folder = folder,
		_motions = {} :: { Motion },
		_conns = {} :: { RBXScriptConnection },
		-- pulls published before this scroller existed are not owed
		_seen = if typeof(total) == "Vector3" then total else Vector3.zero,
		_epoch = epochOf(folder),
	}, Scroller)
	-- PullTotal is written before PullCount, so either signal finds the whole
	-- publish in place; listening to both costs one no-op call and means a
	-- change to either is enough.
	table.insert(
		self._conns,
		folder:GetAttributeChangedSignal("PullTotal"):Connect(function()
			sync(self, false)
		end)
	)
	table.insert(
		self._conns,
		folder:GetAttributeChangedSignal("PullCount"):Connect(function()
			sync(self, true)
		end)
	)
	return self
end

-- Advance every running pull by `dt` and return the displacement owed this frame
-- (Vector3.zero when idle).
function Scroller.step(self: Scroller, dt: number): Vector3
	local motions = self._motions
	local sum = Vector3.zero
	for i = #motions, 1, -1 do
		local m = motions[i]
		local before = eased(m, m.elapsed)
		m.elapsed += dt
		sum += m.delta * (eased(m, m.elapsed) - before)
		if m.elapsed >= m.duration then
			table.remove(motions, i)
		end
	end
	return sum
end

-- True while any pull is still playing.
function Scroller.isActive(self: Scroller): boolean
	return #self._motions > 0
end

function Scroller.destroy(self: Scroller)
	for _, conn in self._conns do
		conn:Disconnect()
	end
	table.clear(self._conns)
	table.clear(self._motions)
end

return PullScroller
