# hotfrog — questions the bug loop needs answered

## b-20261001-141733-kb4c  2026-10-01 14:26
note: when in portrait view, the steps are often only on the sides of the screen and not any down the middle
question: Unity's straight-down spawner sweeps (Pot -0.5/1.5/2.5, Kitchen/Country 0/1.5/2.0 screen half-widths) put most vertical-phase steps off the side of a portrait screen; the port's clampToLane pins them to the right edge (46-58% of visible steps), the rest stack in one column. Pick: (a) drop off-view spawns like Unity (edge stack gone, but sim showed 20-50% of grabs with no step ahead in Kitchen/Country); (b) keep spawn count but rescale each straight-down spawner's X range to fit inside the portrait view (min..max X onto ±8.84 minus a margin — say if you want a margin and how big); or (c) something else.
context: src/server/Lane.luau clampToLane (~line 405) and the vertical spawner X mapping from Config.SPAWN_VIEW_HALF_WIDTH; fixer measured all options with a headless Edit-mode sim and kept no change.
