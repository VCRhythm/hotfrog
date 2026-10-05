--!strict
-- StarterPlayerScripts/Client/world/Pool (ModuleScript)
-- Tiny generic pool: acquire() reuses a parked item or makes a fresh one via
-- `factory`; release() parks it (after an optional `reset`). Cosmetic-only
-- client pooling helper (ObjectPool.cs's pattern, generalized) shared by the
-- world-dressing scripts (scenery, quality popups, touch indicator, specks) so
-- none of them allocate a new Instance per spawn once warmed up.
--
-- Hygiene (world-dressing modernisation pass):
--   * release() is idempotent -- parking an item that is already parked is a
--     no-op, so a stale release can never put one item in the list twice (which
--     would later hand the SAME part to two owners).
--   * releaseAfter() is the safe form of `task.delay(t, function() release(x) end)`:
--     every acquire() bumps the item's generation, and the delayed release only
--     fires if the generation it captured still matches. A part that was
--     recycled and re-acquired in the meantime is left alone instead of being
--     yanked back out from under its new owner.
--   * optional `cap` (parked items kept) with an optional `dispose` for the
--     overflow, so a one-off spike of spawns doesn't leave hundreds of parts
--     parked forever.

export type Pool<T> = {
	acquire: () -> T,
	release: (item: T) -> (),
	releaseAfter: (item: T, seconds: number) -> (),
	count: () -> number, -- parked (idle) items
}

export type Options<T> = {
	cap: number?, -- max parked items kept; nil = unlimited
	dispose: ((T) -> ())?, -- called for an item released past the cap (default: dropped)
}

local Pool = {}

function Pool.new<T>(factory: () -> T, reset: ((T) -> ())?, options: Options<T>?): Pool<T>
	local parked: { T } = {}
	local parkedSet: { [any]: boolean } = {}
	local generation: { [any]: number } = {}
	local cap = if options then options.cap else nil
	local dispose = if options then options.dispose else nil
	local self = {} :: Pool<T>

	function self.acquire(): T
		local item = table.remove(parked)
		if item ~= nil then
			parkedSet[item] = nil
			generation[item] = (generation[item] or 0) + 1
			return item
		end
		local created = factory()
		generation[created] = 1
		return created
	end

	function self.release(item: T)
		if parkedSet[item] then
			return -- already parked: double release
		end
		if reset then
			reset(item)
		end
		if cap and #parked >= cap then
			generation[item] = nil
			if dispose then
				dispose(item)
			end
			return
		end
		parkedSet[item] = true
		table.insert(parked, item)
	end

	function self.releaseAfter(item: T, seconds: number)
		local token = generation[item]
		task.delay(seconds, function()
			if generation[item] == token and not parkedSet[item] then
				self.release(item)
			end
		end)
	end

	function self.count(): number
		return #parked
	end

	return self
end

return Pool
