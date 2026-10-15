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

## o-20261008-144708-cka8  done  2026-10-08 14:47
for: b-20261008-142458-vo87
kind: approval
step: Create Game Passes for Business Frog, Hot Lawyer, Invisible Man and Crossy Frog (Creator Hub -> HotFrog -> Monetization -> Passes) and put each pass id over its gamePassId = 0 in src/shared/SkinCatalog.luau (or hand the ids to the loop)
done-check: ! grep -q 'gamePassId = 0' src/shared/SkinCatalog.luau
cleared: 2026-10-08 14:50 sent back to loop as b-20261008-145031-uwm3: can you do this with roblox open cloud?

## o-20261008-144823-fg29  done  2026-10-08 14:48
for: b-20261008-143855-nuf1
kind: login
step: Give the Open Cloud API key in .env (ROBLOX_API_KEY) the badge scope: Creator Hub -> Open Cloud -> API Keys -> that key -> Add API System 'legacy-universe.badge' -> select HotFrog -> tick Read, Write and manage-and-spend-robux -> Save (keep your IP on its allowlist). Then press Run it; free creation is capped per day, so Run it again on a later day if it stops early
command: python tools/create_badges.py
done-check: ! grep -q 'id = 0' src/shared/Badges.luau
cleared: 2026-10-08 14:50 marked done on the dashboard although the done-check failed

## o-20261008-145601-9osr  done  2026-10-08 14:56
for: b-20261008-145031-uwm3
kind: login
step: Give the Open Cloud API key in .env (ROBLOX_API_KEY) the Game Passes scope: Creator Hub -> Open Cloud -> API Keys -> that key -> Add API System 'Game Passes' (game-pass read + write) -> select HotFrog -> Save. Then press Run it (prices are in PRICES at the top of tools/create_gamepasses.py: Business Frog 99, Hot Lawyer 149, Invisible Man 199, Crossy Frog 249 Robux)
command: python tools/create_gamepasses.py
done-check: ! grep -q 'gamePassId = 0' src/shared/SkinCatalog.luau
cleared: 2026-10-08 15:07 sent back to loop as b-20261008-150752-kf7u: api key has been added. use studio to add the api system and save. then I will press run it

## o-20261008-150843-4wri  done  2026-10-08 15:08
for: b-20261008-150752-kf7u
kind: approval
step: Create the 4 skin Game Passes (Business Frog 99, Hot Lawyer 149, Invisible Man 199, Crossy Frog 249 Robux; edit PRICES at the top of tools/create_gamepasses.py first if you want other prices) by pressing Run it. The key's Game Passes scope now works.
command: python tools/create_gamepasses.py
done-check: ! grep -q 'gamePassId = 0' src/shared/SkinCatalog.luau
ran: 2026-10-08 15:09 exit 0: created 'Invisible Man' -> 2021282272 / created 'Crossy Frog' -> 2021648260 / 4/4 passes have ids
cleared: 2026-10-08 15:09 Run it: exit 0, done-check passed

## o-20261013-094512-yobn  done  2026-10-13 09:45
for: b-20261013-093943-gk5k
kind: restart
step: Restart Roblox Studio with the Hot Frog place (close and reopen it): its 3D viewport draws blank white in both Edit and Play, so the loop's screen captures show no frog, backdrop or steps
no-check: whether Studio's 3D viewport draws again can only be seen in the Studio window; the shell cannot read it
evidence: marked done by the user, no check
cleared: 2026-10-13 09:50 marked done on the dashboard

## o-20261015-100456-yqw2  done  2026-10-15 10:04
for: b-20261013-163505-y6c5
kind: restart
step: Open Hot Frog in Roblox Studio
done-check: powershell.exe -NoProfile -Command "(Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue).MainWindowTitle -match 'Hot Frog'" | grep -q True
evidence: none: done-check failed (the check found nothing (it exited non-zero with no output): `powershell.exe -NoProfile -Command "(Get-Process RobloxStudioBeta -ErrorAction S...`), marked done by the user
cleared: 2026-10-15 10:05 marked done on the fleet dashboard although the done-check failed

## o-20261015-100656-nw90  open  2026-10-15 10:06
for: b-20261013-163505-y6c5
kind: restart
step: Open Hot Frog in Roblox Studio
done-check: powershell.exe -NoProfile -Command "(Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue).MainWindowTitle -match 'Hot Frog'" | grep -q True
