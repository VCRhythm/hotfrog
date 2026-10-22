# hotfrog — questions the bug loop needs answered

## b-20261021-093703-adx9  2026-10-22 14:03
note: Asset id cache drift: tools/asset_ids.json holds re-uploaded music1/music5 ids that differ from src/shared/SoundAssets.luau (the wu4e upload run re-uploaded them on a cache mismatch, and the file was put back to its committed ids). Next write_asset_ids run will swap them; decide which ids to keep and find why the cache mismatched.
question: Keep the committed music ids in src/shared/SoundAssets.luau (music1 = 77652599137287, music5 = 70897771387242), or switch to the website re-uploads cached in tools/asset_ids.json (music1 = 89807132444823, music5 = 105962262612155, both Approved/Green, uploaded 2026-10-21)? If you keep the committed ids, the cache entries must be set back to them before the next python tools/write_asset_ids.py run; tools/ belongs to the upload session, so the loop will not change either file until you choose.
context: write_asset_ids.py rewrites the Ids table in src/shared/SoundAssets.luau from tools/asset_ids.json (gitignored), so whichever ids the cache holds win on the next run.
