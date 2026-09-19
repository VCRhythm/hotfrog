# hotfrog — questions the bug loop needs answered

## b-20260919-140016-dm0e  2026-09-19 14:25
note: I'm not seeing the frog sprites on load. the flies are also just placeholders, not using the actual sprites
question: In Studio, paste rbxassetid://132401989626297 (HotFrogBody) into a test Decal's Texture or an ImageLabel's Image. Does it render? If yes, the texturing code is correct and this needs an in-Studio repro (output window errors, F8 report with screenshot). If no, the 207 images must be re-uploaded as Decal and resolved to Image ids with tools/upload_to_roblox.py --resolve-only, then the ids rewritten.
context: Ids in src/shared/SkinAssets.luau are non-zero and match tools/asset_ids.json, and SpriteSkin.apply is called in createFrog and spawnBug; whether assetType=Image upload ids render from script is listed as unverified in docs/roblox-port/17-status-and-known-gaps.md.
