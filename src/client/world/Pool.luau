--!strict
-- StarterPlayerScripts/Client/world/Pool (ModuleScript)
-- Tiny generic pool: acquire() reuses a parked item or makes a fresh one via
-- `factory`; release() parks it (after an optional `reset`). Cosmetic-only
-- client pooling helper (ObjectPool.cs's pattern, generalized) shared by the
-- world-dressing scripts (scenery, quality popups, touch indicator, specks) so
-- none of them allocate a new Instance per spawn once warmed up.

export type Pool<T> = {
	acquire: () -> T,
	release: (item: T) -> (),
	count: () -> number, -- parked (idle) items
}

local Pool = {}

function Pool.new<T>(factory: () -> T, reset: ((T) -> ())?): Pool<T>
	local parked: { T } = {}
	local self = {} :: Pool<T>

	function self.acquire(): T
		local item = table.remove(parked)
		if item ~= nil then
			return item
		end
		return factory()
	end

	function self.release(item: T)
		if reset then
			reset(item)
		end
		table.insert(parked, item)
	end

	function self.count(): number
		return #parked
	end

	return self
end

return Pool
