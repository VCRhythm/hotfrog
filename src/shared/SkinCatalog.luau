-- ReplicatedStorage/Shared/SkinCatalog (ModuleScript)
-- Data-only skin catalog (replaces Store/StoreAssets.cs + the serialized fields on
-- Player/Frog.cs). One entry per skin; `name` maps to a model under
-- ReplicatedStorage/Assets/Skins/<name>. See ../08-frog-skins-and-store.md.
--
--   default = true  -> owned for free (Frog.cs isUnlocked == 1)
--   flyCost         -> buyable with the soft currency (Flys)
--   gamePassId      -> premium, permanent unlock (real money). FILL IN real ids.

return {
	[1] = { name = "Classic Frog", default = true },
	[2] = { name = "Speckled", flyCost = 500 },
	[3] = { name = "Invisible Man", gamePassId = 0 }, -- set a real Game Pass id
	[4] = { name = "Business Frog", gamePassId = 0 },
	[5] = { name = "Hot Lawyer", gamePassId = 0 },
	[6] = { name = "Crossy Frog", gamePassId = 0 },
	-- ...add the rest of the roster
}
