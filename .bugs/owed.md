# Steps only you can do

## o-20261001-145250-oq0m  done  2026-10-01 14:52
for: b-20261001-145112-o2jb
step: Draw dedicated store thumbnails for Blue, Space and Mystery Frog (Sprites/Frogs/<name>/<Skin>Thumbnail.png), upload them, and rewrite the asset ids
command: python tools/build_manifest.py && python tools/upload_to_roblox.py --manifest tools/asset_manifest.json && python tools/write_asset_ids.py
cleared: 2026-10-01 15:06 marked done on the dashboard

## o-20261008-143616-fzdz  done  2026-10-08 14:36
for: b-20261008-141644-lzg7
kind: login
step: Create the 19 HotFrog badges in Creator Hub (create.roblox.com -> this experience -> Engagement -> Badges): the 10 existing '10 Steps!'..'100 Steps!' plus the new '150 Steps!', '200 Steps!', '300 Steps!', '500 Steps!', 'Out of the Pot', 'Country Frog', '3-Day Streak', '7-Day Streak', '30-Day Streak'; paste each id over its id = 0 in src/shared/Badges.luau (or hand the ids to the loop)
done-check: ! grep -q 'id = 0' src/shared/Badges.luau
cleared: 2026-10-08 14:38 sent back to loop as b-20261008-143855-nuf1: can you do this through open cloud with the right permissions?

## o-20261008-144708-cka8  open  2026-10-08 14:47
for: b-20261008-142458-vo87
kind: approval
step: Create Game Passes for Business Frog, Hot Lawyer, Invisible Man and Crossy Frog (Creator Hub -> HotFrog -> Monetization -> Passes) and put each pass id over its gamePassId = 0 in src/shared/SkinCatalog.luau (or hand the ids to the loop)
done-check: ! grep -q 'gamePassId = 0' src/shared/SkinCatalog.luau
