# hotfrog — questions the bug loop needs answered

## b-20261020-205326-jmsu  2026-10-20 20:53
note: Here is the new Ludo art for the outdoor Country and Space (b-20261020-200915-5ju4): TreeTrunk, CarRight, CarLeft and Asteroid steps, and the CountryBack and SpaceBack backdrops. Do they fit your sprite style? Reply 'good', or name the pieces to redo and how (also any change to car speed, the 1.2 s knock-off, or Space's 20% gravity).
question: Here is the new Ludo art for the outdoor Country and Space (b-20261020-200915-5ju4): TreeTrunk, CarRight, CarLeft and Asteroid steps, and the CountryBack and SpaceBack backdrops. Do they fit your sprite style? Reply 'good', or name the pieces to redo and how (also any change to car speed, the 1.2 s knock-off, or Space's 20% gravity).
context: good: record the art accepted on b-20261020-200915-5ju4, no change. Redo: regenerate the named sprites with Ludo in the requested direction, re-run build_manifest/upload_to_roblox --keys/write_asset_ids, Studio-check them. Tuning: Config.luau (cars in StepKinds/StepBehaviors, SPACE_GRAVITY_SCALE). Files are the committed Sprites from 3423ecd.
