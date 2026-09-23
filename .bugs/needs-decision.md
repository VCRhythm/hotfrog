# hotfrog — questions the bug loop needs answered

## b-20260923-154343-9twj  2026-09-23 15:50
note: journey 1/8: pot rim landmark: climbing out over the rim should BE the Pot->Kitchen transition
question: There is no pot rim/handle art (nothing under Sprites/ matches). Pick one: (a) you draw or supply rim + handle sprites, which go through tools/ upload and SkinAssets; (b) build a placeholder rim now from plain Parts tinted to match PotBack and swap the art in later; (c) drop the landmark and have item 2's arrival scene fire on the level change instead.
context: Lane.luau onStepClimbed (~L1090) would spawn a special rim step at Config.LEVEL_THRESHOLDS.Kitchen; WorldScenery would scroll the rim into view from ~step 40.

## b-20260923-154345-78ng  2026-09-23 15:50
note: journey 8/8: ambient sound should change with height (bubbling in Pot, kitchen room sound)
question: No ambient clips exist (SoundAssets has only boilVoice, a voice line). Pick one: (a) you supply a bubbling loop and a kitchen room-tone loop, which go through tools/ upload into SoundAssets; (b) pick loops from the Roblox audio library (insert_asset/search_asset) and record their ids; (c) skip ambience.
context: A new ambient layer beside Music.client.luau, keyed on LocalPlayer.LevelState and the height stage from item 3.
