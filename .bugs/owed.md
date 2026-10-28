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
accepted: 2026-10-20 20:11 cli: retired Studio window-title done-check; Studio Play checks passed in Hot Frog (placeId 114911935371092) on 2026-10-17 13:52 (b-20261017-133312-vqnu), and tools/studio_ready.sh is the current check (b-20261019-032005-wkiu)

## o-20261015-100656-nw90  done  2026-10-15 10:06
for: b-20261013-163505-y6c5
kind: restart
step: Open Hot Frog in Roblox Studio
done-check: powershell.exe -NoProfile -Command "(Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue).MainWindowTitle -match 'Hot Frog'" | grep -q True
evidence: none: done-check failed (the check found nothing (it exited non-zero with no output): `powershell.exe -NoProfile -Command "(Get-Process RobloxStudioBeta -ErrorAction S...`), marked done by the user
cleared: 2026-10-15 10:08 marked done on the dashboard although the done-check failed
accepted: 2026-10-20 20:11 cli: retired Studio window-title done-check; Studio Play checks passed in Hot Frog (placeId 114911935371092) on 2026-10-17 13:52 (b-20261017-133312-vqnu), and tools/studio_ready.sh is the current check (b-20261019-032005-wkiu)

## o-20261016-120238-gmyn  done  2026-10-16 12:02
for: b-20261013-163505-y6c5
kind: restart
step: Switch rojo serve to this project (stop the Scare server, then run rojo serve in H:\Roblox Projects\hotfrog) and open Hot Frog in Roblox Studio with the Rojo plugin connected
command: cd '/h/Roblox Projects/hotfrog' && rojo serve
done-check: python ~/.claude/skills/bugloop/scripts/bugloop.py rojo-check >/dev/null 2>&1 && powershell.exe -NoProfile -Command "(Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue).MainWindowTitle -match 'Hot Frog'" | grep -q True
evidence: none: done-check failed (the check found nothing (it exited non-zero with no output): `python ~/.claude/skills/bugloop/scripts/bugloop.py rojo-check >/dev/null 2>&1 &&...`), marked done by the user
cleared: 2026-10-16 12:05 marked done on the fleet dashboard although the done-check failed
accepted: 2026-10-20 20:11 cli: retired Studio window-title done-check; Studio Play checks passed in Hot Frog (placeId 114911935371092) on 2026-10-17 13:52 (b-20261017-133312-vqnu), and tools/studio_ready.sh is the current check (b-20261019-032005-wkiu)

## o-20261016-120554-lf1c  done  2026-10-16 12:05
for: b-20261013-163534-ogsq
kind: restart
step: Switch rojo serve to this project (stop the Scare server, then run rojo serve in H:\Roblox Projects\hotfrog) and open Hot Frog in Roblox Studio with the Rojo plugin connected
command: cd '/h/Roblox Projects/hotfrog' && rojo serve
done-check: python ~/.claude/skills/bugloop/scripts/bugloop.py rojo-check >/dev/null 2>&1 && powershell.exe -NoProfile -Command "(Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue).MainWindowTitle -match 'Hot Frog'" | grep -q True
evidence: none: done-check failed (the check found nothing (it exited non-zero with no output): `python ~/.claude/skills/bugloop/scripts/bugloop.py rojo-check >/dev/null 2>&1 &&...`), marked done by the user
cleared: 2026-10-16 12:06 marked done on the dashboard although the done-check failed
accepted: 2026-10-20 20:12 cli: retired Studio window-title done-check; Studio Play checks passed in Hot Frog (placeId 114911935371092) on 2026-10-17 13:52 (b-20261017-133312-vqnu), and tools/studio_ready.sh is the current check (b-20261019-032005-wkiu)

## o-20261016-120554-5vc2  done  2026-10-16 12:05
for: b-20261013-163505-y6c5
kind: restart
step: Open Hot Frog in Roblox Studio
done-check: powershell.exe -NoProfile -Command "(Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue).MainWindowTitle -match 'Hot Frog'" | grep -q True
evidence: none: done-check failed (the check found nothing (it exited non-zero with no output): `powershell.exe -NoProfile -Command "(Get-Process RobloxStudioBeta -ErrorAction S...`), marked done by the user
cleared: 2026-10-16 12:06 marked done on the dashboard although the done-check failed
accepted: 2026-10-20 20:12 cli: retired Studio window-title done-check; Studio Play checks passed in Hot Frog (placeId 114911935371092) on 2026-10-17 13:52 (b-20261017-133312-vqnu), and tools/studio_ready.sh is the current check (b-20261019-032005-wkiu)

## o-20261016-121231-t6n4  done  2026-10-16 12:12
for: b-20261013-163505-y6c5
kind: restart
step: Switch rojo serve to this project (stop the Scare server, then run rojo serve in H:\Roblox Projects\hotfrog) and open Hot Frog in Roblox Studio with the Rojo plugin connected
command: cd '/h/Roblox Projects/hotfrog' && rojo serve
done-check: bash '/h/Roblox Projects/hotfrog/tools/studio_ready.sh' >/dev/null 2>&1
evidence: done-check passed: exit 0, no output
cleared: 2026-10-16 12:14 marked done on the dashboard

## o-20261016-121232-4rse  done  2026-10-16 12:12
for: b-20261013-163534-ogsq
kind: restart
step: Switch rojo serve to this project (stop the Scare server, then run rojo serve in H:\Roblox Projects\hotfrog) and open Hot Frog in Roblox Studio with the Rojo plugin connected
command: cd '/h/Roblox Projects/hotfrog' && rojo serve
done-check: bash '/h/Roblox Projects/hotfrog/tools/studio_ready.sh' >/dev/null 2>&1
evidence: done-check passed: exit 0, no output
cleared: 2026-10-16 12:14 done-check passed

## o-20261016-121232-i1t8  done  2026-10-16 12:12
for: b-20261013-163505-y6c5
kind: restart
step: Open Hot Frog in Roblox Studio
done-check: powershell.exe -NoProfile -Command "(Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue).MainWindowTitle" | grep -q 'Hot Frog'
evidence: done-check passed: exit 0, no output
cleared: 2026-10-16 12:12 done-check passed

## o-20261016-122443-w0p4  done  2026-10-16 12:24
for: b-20261016-121550-awo6
kind: restart
step: Restart the open Roblox Studios (Hot Frog, Tactics, Centralia) so they load the 7.7.1 Rojo plugin, then reconnect Rojo in each
no-check: Studio does not expose which plugin version a running window loaded; only a person can see the Rojo widget's version after restarting
evidence: marked done by the user, no check
cleared: 2026-10-16 12:28 marked done on the fleet dashboard

## o-20261016-125533-0z6s  done  2026-10-16 12:55
for: b-20261016-123058-9thf
kind: taste
step: Look at the Halloween witch hat (Sprites/Frogs/Hot Frog/HotFrogHalloweenHat.png) on Hot Frog and say if the art is right, or ask for changes
no-check: whether the hat art looks right is the user's call
evidence: the user judged the art "looks good" when sending it back as b-20261016-130320-ce9u
cleared: 2026-10-16 13:03 sent back to loop as b-20261016-130320-ce9u: looks good. make sure its layer is in front of the frog's head

## o-20261016-131548-yk5p  done  2026-10-16 13:15
for: b-20261016-125004-mog8
kind: taste
step: Look at the Halloween scenery art (Sprites/Scenery/JackOLantern, Ghost, Cobweb, Bat .png) in game with ForceHalloween on, and say if the bats (3.2 studs on a 44-stud lane) read too small
no-check: whether new art looks right is the owner's call
evidence: not judged yet: the user will look in game, sent back as b-20261016-131816-bw8k; re-owed as o-20261016-132035-06e5
cleared: 2026-10-16 13:18 sent back to loop as b-20261016-131816-bw8k: I'll have to see these in game

## o-20261016-131549-vd5d  done  2026-10-16 13:15
for: b-20261016-125004-mog8
kind: taste
step: Look at the Vampire Frog art (Sprites/Frogs/Vampire Frog/, mainly VampireFrogBody, Head, Mouth, LeftPupil, LeftHand) on the frog and in Shop > Frogs
no-check: whether new art looks right is the owner's call
evidence: the user approved the Vampire Frog art ("looks great") when sending it back as b-20261016-131805-8d2q
cleared: 2026-10-16 13:18 sent back to loop as b-20261016-131805-8d2q: looks great

## o-20261016-132035-06e5  done  2026-10-16 13:20
for: b-20261016-125004-mog8
kind: taste
step: Look at the Halloween scenery (jack-o'-lanterns, ghosts, cobwebs) and bats in game, live Oct 24 to Nov 1 UTC or any time in Studio Play after running workspace:SetAttribute("ForceHalloween", true) in the server command bar, and say if any art or the bat size (3.2 studs on a 44-stud lane) should change
no-check: whether new art looks right in game is the owner's call
evidence: marked done by the user, no check
cleared: 2026-10-16 14:05 marked done on the fleet dashboard

## o-20261016-173728-jewl  done  2026-10-16 17:37
for: b-20261016-140523-i34z
kind: restart
step: Open the Hot Frog place in Roblox Studio (it is closed; only Tactics and Centralia are open), so the loop can run its held game checks
done-check: bash tools/studio_ready.sh
evidence: done-check passed: 34873
cleared: 2026-10-16 19:20 marked done on the fleet dashboard

## o-20261016-174406-ubok  done  2026-10-16 17:44
for: b-20261016-140445-tnpd
kind: taste
step: Look at the reworked witch hat on Hot Frog with ForceHalloween on (sits lower, behind the eyes, darker band and buckle) and say if it looks right
no-check: whether the hat looks right is the owner's call
evidence: none, the user sent it back to the loop as b-20261016-192055-4s1f
cleared: 2026-10-16 19:20 sent back to loop as b-20261016-192055-4s1f: lower on the head

## o-20261016-174456-mgfb  done  2026-10-16 17:44
for: b-20261016-140637-tqc4
kind: taste
step: Look at the reshaded witch hat's band and buckle next to the frog's own shading (Hot Frog, ForceHalloween on) and say if the darkness is right
no-check: whether the shading matches is the owner's call
evidence: marked done by the user, no check
cleared: 2026-10-16 19:20 marked done on the fleet dashboard

## o-20261017-091030-a91m  done  2026-10-17 09:10
for: b-20261016-192055-4s1f
kind: taste
step: Look at the witch hat on Hot Frog in Studio (workspace attribute ForceHalloween on), now another 50 px lower so the brim sits at eye level behind the eyes, and say if the height looks right
no-check: whether the hat height looks right is the owner's call
evidence: marked done by the user, no check
cleared: 2026-10-17 12:39 marked done on the fleet dashboard

## o-20261017-130041-mozs  done  2026-10-17 13:00
for: b-20261017-123841-69yo
kind: taste
step: Play the Tutorial in Studio and look at the new oak: crisp art, acorns hanging from twigs, trunk in front of the frog's face/body with arms and hands on top
no-check: only the owner can judge the look
evidence: marked done by the user, no check
cleared: 2026-10-17 13:33 marked done on the fleet dashboard

## o-20261020-205042-fnwn  done  2026-10-20 20:50
for: b-20261020-200915-5ju4
kind: taste
step: Look over the new Ludo art for style fit and car feel: Sprites/Rocks/TreeTrunk.png, CarRight.png, CarLeft.png, Asteroid.png, Sprites/Other/CountryBack.png, SpaceBack.png; in game, how a held car drags the frog for 1.2 s before knocking it off, car speed, and Space's 20% gravity. Reply on the dashboard with anything to change
no-check: style and feel are a judgement only the owner can make
evidence: none, the user sent it back to the loop as b-20261020-205151-b1ob
cleared: 2026-10-20 20:51 sent back to loop as b-20261020-205151-b1ob: show me

## o-20261020-214949-7t5n  done  2026-10-20 21:49
for: b-20261020-213524-zhza
kind: taste
step: Look at the Chef's placeholder coat and legs in Kitchen; say if they're fine or if you want a painted body sprite instead
no-check: only the owner can judge the look
evidence: none, the user sent it back to the loop as b-20261020-215940-pyvu
cleared: 2026-10-20 21:59 sent back to loop as b-20261020-215940-pyvu: the chef should have a huge body, sized correctly to his head. and currently his arm isn't viewable in a way that shows which step he's about to break

## o-20261021-092031-ss9x  done  2026-10-21 09:20
for: b-20261021-091520-sh6c
kind: restart
step: Stop Play in the Hot Frog Studio (Play has run since 08:47 and may be yours); the loop's Studio checks wait until Studio is back in Edit mode
done-check: cd "$LOCALAPPDATA/Roblox/logs" && f=$(ls -t *Studio*_last.log | head -3 | xargs grep -a -l 114911935371092 | head -1) && [ -n "$f" ] && grep -a -o "WaypointTelemetry\] \(PSMStartPlaySolo\|StopPlaySoloEnd\)" "$f" | tail -1 | grep -q StopPlaySoloEnd
evidence: done-check passed: exit 0, no output
cleared: 2026-10-21 09:40 marked done on the fleet dashboard

## o-20261021-095849-v7sv  done  2026-10-21 09:58
for: b-20261021-092032-44by
kind: restart
step: Stop Play in the Hot Frog Studio when you're finished with it; the loop's Studio work waits until Studio is back in Edit mode
done-check: cd "$LOCALAPPDATA/Roblox/logs" && f=$(ls -t *Studio*_last.log | head -3 | xargs grep -a -l 114911935371092 | head -1) && [ -n "$f" ] && grep -a -o "WaypointTelemetry\] \(PSMStartPlaySolo\|StopPlaySoloEnd\)" "$f" | tail -1 | grep -q StopPlaySoloEnd
evidence: none, the user sent it back to the loop as b-20261021-100120-anmj
cleared: 2026-10-21 10:01 sent back to loop as b-20261021-100120-anmj: you are starting studio yourself. you need to be able to end it yourself

## o-20261021-103548-zf5x  done  2026-10-21 10:35
for: b-20261021-094437-1mnh
kind: taste
step: Listen to the new Kitchen track (Sounds/Music/KitchenBounce.mp3, 64 s, plays in Kitchen) and its loop seam; say if it fits or should be regenerated
no-check: only a person can judge whether music fits and loops cleanly; the Studio MCP cannot play audio
evidence: none, the user sent it back to the loop as b-20261021-111751-ivdz
cleared: 2026-10-21 11:17 sent back to loop as b-20261021-111751-ivdz: link me

## o-20261021-112201-7cyi  done  2026-10-21 11:22
for: b-20261021-094437-1mnh
kind: taste
step: Listen to the new Kitchen track and its loop seam, then say if it fits or should be regenerated. Local file: file:///H:/Roblox%20Projects/hotfrog/Sounds/Music/KitchenBounce.mp3 (also sent to your Claude app). Roblox asset: https://create.roblox.com/dashboard/creations/store/111453159554462/configure
no-check: only a person can judge whether music fits and loops cleanly; the Studio MCP cannot play audio
evidence: none, the user sent it back to the loop as b-20261021-112652-q8b6
cleared: 2026-10-21 11:26 sent back to loop as b-20261021-112652-q8b6: link me

## o-20261021-114200-7965  done  2026-10-21 11:42
for: b-20261021-112652-q8b6
kind: taste
step: Listen to the trimmed Kitchen track (now starts at the old 0:14.87, 49 s) and its loop seam, then say if it fits. Local file: file:///H:/Roblox%20Projects/hotfrog/Sounds/Music/KitchenBounce.mp3 (also sent to your Claude app); in game it plays on the Kitchen level as asset 117737777986047
no-check: only a person can judge whether music fits and loops cleanly; the Studio MCP cannot play audio
evidence: marked done by the user, no check
cleared: 2026-10-21 11:59 marked done on the fleet dashboard

## o-20261022-120651-zei7  done  2026-10-22 12:06
for: b-20261022-115819-ktdq
kind: approval
step: Upload the launch kit to the Hot Frog experience page: Creator Hub (create.roblox.com) -> Creations -> Hot Frog -> Configure -> Icon: marketing/icon-512.png; Places -> start place -> Thumbnails: marketing/thumb-1.png .. thumb-5.png; paste title, description, genre and maturity answers from marketing/store-page.md under Settings
no-check: the experience page lives on roblox.com; nothing on this host shows what was uploaded
evidence: marked done by the user, no check
cleared: 2026-10-22 13:22 marked done on the fleet dashboard

## o-20261022-122336-c92z  done  2026-10-22 12:23
for: b-20261022-121451-wkhn
kind: restart
step: Open the Hot Frog place in Roblox Studio with rojo serve connected (Studio checks for the Hot Lawyer tongue and later fixes wait on it)
done-check: bash tools/studio_ready.sh
evidence: done-check passed: 34872
cleared: 2026-10-22 13:28 marked done on the dashboard

## o-20261022-134308-45zy  done  2026-10-22 13:43
for: b-20261022-133647-9w0z
kind: device
step: On a phone (or Studio's device emulator with touch), play a run: switch fingers between grabbed steps (no red X; an empty tap still shows it), check the HOTFROG title is readable and clear of the score column and menu panel, and that the Daily Streak dim reaches the very top edge
no-check: needs a person's real or emulated multi-touch and eyes at phone size; the Studio MCP cannot drive touch or the emulator
evidence: none, the user sent it back to the loop as b-20261022-135019-jlhg
cleared: 2026-10-22 13:50 sent back to loop as b-20261022-135019-jlhg: I want the info towards the buttom of the screen during a run (it's in the way being right in the top center). once it's all at the bottom, the combo text should be at the *top* of the stack

## o-20261022-135611-obdo  done  2026-10-22 13:56
for: b-20261022-135019-jlhg
kind: device
step: On a phone (or Studio's device emulator with touch), play a run: the score/combo stack sits at the bottom clear of the home bar with the combo on top; switching fingers between grabbed steps shows no red X (an empty tap still does); the HOTFROG title is readable; the Daily Streak dim reaches the top edge
no-check: needs a person's real or emulated multi-touch and eyes at phone size; the Studio MCP cannot drive touch or the emulator
evidence: marked done by the user, no check
cleared: 2026-10-22 14:02 marked done on the dashboard

## o-20261022-141404-k6j6  done  2026-10-22 14:14
for: b-20261022-135157-8qux
kind: device
step: On a portrait phone (or a portrait device emulator), start a run: the opening steps should sit well inside the screen, not at the edge; do it with the o-20261022-135611-obdo phone pass
no-check: only a person on a portrait phone can judge where the steps sit
evidence: marked done by the user, no check
cleared: 2026-10-22 14:54 marked done on the fleet dashboard

## o-20261022-142137-ufk7  done  2026-10-22 14:21
for: b-20261022-140440-c2tq
kind: device
step: On a phone in Normal mode, hold two steps with two fingers, let one step be knocked off or fall while its finger stays down, grab a new step with the other finger, then lift the old finger: the new step should stay held
no-check: needs two real fingers on a touch screen; the Studio MCP cannot drive multi-touch
evidence: marked done by the user, no check
cleared: 2026-10-22 14:54 marked done on the fleet dashboard

## o-20261022-144016-c0ap  done  2026-10-22 14:40
for: b-20261022-140925-k146
kind: device
step: On a portrait phone, start the Tutorial and check the second and third acorns are on screen and easy to reach, and the squashed oak looks acceptable
no-check: needs a real portrait phone and a judgement of reach and looks
evidence: marked done by the user, no check
cleared: 2026-10-22 14:54 marked done on the fleet dashboard

## o-20261022-144035-4c1q  done  2026-10-22 14:40
for: b-20261022-140225-lhat
kind: device
step: On a portrait phone in Kitchen or Country, grab a sideways or diagonal arrow and check at least one new step appears on screen toward the new direction within about a second
no-check: needs a real portrait phone; Studio MCP cannot set a phone viewport
evidence: none, the user sent it back to the loop as b-20261022-145536-i6g3
cleared: 2026-10-22 14:55 sent back to loop as b-20261022-145536-i6g3: there are still moments when going sideways that the screen is very empty of steps

## o-20261022-144409-zqd5  done  2026-10-22 14:44
for: b-20261022-143822-gemh
kind: device
step: Play a Kitchen run on a portrait phone through several Chef attacks, including after a sideways pull
no-check: the risk is a portrait viewport, which the Studio MCP cannot set, and the Chef's picks are random
evidence: marked done by the user, no check
cleared: 2026-10-22 14:54 marked done on the fleet dashboard

## o-20261022-144410-edgi  done  2026-10-22 14:44
for: b-20261022-141339-w3jk
kind: device
step: Play a Kitchen run on a portrait phone through several Chef Knife Swings
no-check: needs a portrait viewport and repeated random Chef picks
evidence: marked done by the user, no check
cleared: 2026-10-22 14:54 marked done on the fleet dashboard

## o-20261028-115520-m88v  done  2026-10-28 11:55
for: b-20261028-114837-bdu6
kind: restart
step: Start rojo serve for Hot Frog on its pinned port 34873 and connect the Studio Rojo plugin
command: cd '/h/Roblox Projects/hotfrog' && rojo serve --port 34873
done-check: python ~/.claude/skills/bugloop/scripts/bugloop.py --repo '/h/Roblox Projects/hotfrog' rojo-check >/dev/null 2>&1
evidence: done-check passed: exit 0, no output
cleared: 2026-10-28 11:55 done-check passed

## o-20261028-115753-qe7r  done  2026-10-28 11:57
for: b-20261028-114837-bdu6
kind: restart
step: Start rojo serve for Hot Frog on its pinned port 34873 and connect the Studio Rojo plugin
command: cd '/h/Roblox Projects/hotfrog' && rojo serve --port 34873
done-check: python "$USERPROFILE/.claude/skills/bugloop/scripts/bugloop.py" rojo-check >/dev/null 2>&1
evidence: none, the user sent it back to the loop as b-20261028-120418-kdg5
cleared: 2026-10-28 12:04 sent back to loop as b-20261028-120418-kdg5: you should be able to run your own server and connect, similar to how the scare repo does

## o-20261028-121545-wm5p  done  2026-10-28 12:15
for: b-20261028-120418-kdg5
kind: app-setting
step: Open the Hot Frog place in Studio (Edit mode) and bind "Rojo: Connect" (not "Rojo: Connect/Disconnect") to Ctrl+Alt+Shift+F8 under File > Customize Shortcuts; then run the command, or click Connect in the Rojo widget on localhost:34873. Hot Frog's rojo serve is already running.
command: cd '/h/Roblox Projects/hotfrog' && python tools/rojo_reconnect.py connect
done-check: python tools/rojo_reconnect.py status >/dev/null 2>&1
evidence: done-check passed: exit 0, no output
cleared: 2026-10-28 12:30 marked done on the fleet dashboard
