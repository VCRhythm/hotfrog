-- ReplicatedStorage/Shared/SkinCatalog (ModuleScript)
-- Data-only skin catalog (replaces Store/StoreAssets.cs + the serialized fields on
-- Player/Frog.cs). One entry per skin. See ../../docs/roblox-port/08-frog-skins-and-store.md.
--
--   name        -> matches a source art folder: /Sprites/Frogs/<name>/
--                  (and the built model under ReplicatedStorage/Assets/Skins/<name>)
--   default = true  -> owned for free (Frog.cs isUnlocked == 1)
--   flyCost         -> buyable with the soft currency (Flys)
--   gamePassId      -> premium, permanent unlock (real money). FILL IN real ids.
--
-- default / flyCost / gamePassId are best-guess starting values; reconcile against
-- the original frog prefabs' isUnlocked/canBuy. The four premium frogs match the
-- LifetimeVG goods in Store/StoreAssets.cs.

return {
	[1] = { name = "Hot Frog", default = true }, -- the namesake / starter
	[2] = { name = "Blue Frog", flyCost = 500 },
	[3] = { name = "Hawt Frog", flyCost = 1000 },
	[4] = { name = "Space Frog", flyCost = 1500 },
	[5] = { name = "Mystery Frog", flyCost = 2000 },
	[6] = { name = "Business Frog", gamePassId = 0 }, -- premium (set real Game Pass id)
	[7] = { name = "Hot Lawyer", gamePassId = 0 },
	[8] = { name = "Invisible Man", gamePassId = 0 },
	[9] = { name = "Crossy Frog", gamePassId = 0 },
}
