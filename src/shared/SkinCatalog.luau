-- ReplicatedStorage/Shared/SkinCatalog (ModuleScript)
-- Data-only skin catalog (replaces Store/StoreAssets.cs + the serialized fields on
-- Player/Frog.cs). One entry per skin. See ../../docs/roblox-port/08-frog-skins-and-store.md.
--
--   name        -> matches a source art folder: /Sprites/Frogs/<name>/
--                  (and the built model under ReplicatedStorage/Assets/Skins/<name>)
--   default = true  -> owned for free (Frog.cs isUnlocked == 1)
--   flyCost         -> buyable with the soft currency (Flys)
--   hidden = true   -> not shown in the store, not buyable/selectable; data kept
--   gamePassId      -> premium, permanent unlock (real money). FILL IN real ids.
--
-- default / gamePassId are best-guess starting values; reconcile against the
-- original frog prefabs' isUnlocked/canBuy. The four premium frogs match the
-- LifetimeVG goods in Store/StoreAssets.cs and keep their Game Pass as the Robux
-- alternative (a skin may have both flyCost and gamePassId).
--
-- flyCost is a run ladder, not Unity's prices (b-20261008-142458-vo87 /
-- b-20261008-143831-k4ys; doc 17): at ~50 Flys per typical run each price is
-- the next gap of 2, 5, 10, 20, 30, 45, 60, 80 runs (cumulative 2, 7, 17, 37,
-- 67, 112, 172, 252 runs). The first rung (100 Flys, 2 runs) is Hot Frog's Blue
-- colour (SkinTints), so Hawt Frog is the first skin on the ladder.

return {
	[1] = { name = "Hot Frog", default = true }, -- the namesake / starter
	-- id 2 (Blue Frog) is gone: it is now Hot Frog's "Blue" art-swap colourway
	-- (SkinTints id 5, 100 Flys, b-20261012-212255-idh7); Profiles migrates owners.
	[3] = { name = "Hawt Frog", flyCost = 250 }, -- 5 more
	[4] = { name = "Space Frog", flyCost = 500 }, -- 10 more
	[5] = { name = "Mystery Frog", flyCost = 1000, hidden = true }, -- 20 more; hidden for now (delete `hidden` to bring it back)
	[6] = { name = "Business Frog", flyCost = 1500, gamePassId = 2019110445 }, -- 30 more; premium (set real Game Pass id)
	[7] = { name = "Hot Lawyer", flyCost = 2250, gamePassId = 2019278450 }, -- 45 more
	[8] = { name = "Invisible Man", flyCost = 3000, gamePassId = 2021282272 }, -- 60 more
	[9] = { name = "Crossy Frog", flyCost = 4000, gamePassId = 2021648260 }, -- 80 more
}
