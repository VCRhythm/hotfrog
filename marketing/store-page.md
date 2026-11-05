# Hot Frog - Roblox experience page kit

Facts below come from the code (src/shared/Config.luau, Levels.luau, SkinCatalog.luau, src/server/Chef.luau, MenuClient).

## Title
Hot Frog

## Description (about 1000 characters)
Hot Frog is a one-more-try climbing game: you never move the frog, you grab the steps and pull the whole world past him. Press and hold on a step and a free hand reaches out and grabs it: hold the left mouse button for the left hand, the right button for the right hand, and keep at least one hand holding or the frog falls. Time your grabs for Perfect and Great grades, build a COMBO streak and the climb speeds up. Let go of everything and you drop into the lava.

Climb out of the Pot, up through the Kitchen (watch out: the Chef throws potatoes, swings a knife and shoves steps away), across the Country, and all the way to Space.

Catch bugs with your tongue to earn Flys, then spend them on new frogs: Hawt Frog, Space Frog, Vampire Frog and more, plus Hot Frog's Blue colour. Business Frog, Hot Lawyer, Invisible Man and Crossy Frog can also be bought with Robux. Daily gifts, a login streak and daily goals keep the Flys coming, and you can pour spare Flys into the Fly Jar to earn titles.

Everyone gets their own play field, so you can race friends side by side and watch the leaderboard. Pick Normal or Easy mode, or learn the ropes in the Tutorial.

## Feature bullets
- Grab steps to pull the world past you: climb as high as you can before the lava gets you
- Four-plus levels: Pot, Kitchen (with a hostile Chef), Country and Space
- Time your grabs, build a COMBO streak and the climb speeds up
- Catch bugs for Flys and unlock frog skins; Robux options for the premium frogs
- Your own lane in multiplayer, with top-score leaderboards, daily gifts and Fly Jar titles

## Controls (for the description or a how-to-play note)
Mouse: hold left button = left hand, hold right button = right hand; at least one hand must stay on a step or the frog falls. Touch: each finger held on a step uses a free hand. Gamepad: R2 or A grabs, L2 or X releases, B or Y shoots the tongue, thumbstick moves the cursor. Click/tap a bug to catch it with the tongue. There is no keyboard grab, so do not advertise keyboard play.

## Suggested genre and tags
Genre: Obstacle Course / Skill (Roblox "Adventure" is a reasonable alternative).
Tags to try: climbing, arcade, casual, endless, high score, funny, cute, multiplayer, skill, frogs.
Devices: PC, Phone, Tablet (touch and mouse input exist); Console is unverified: gamepad code exists but it has not been tested.

## Age rating / Maturity questionnaire (suggested answers, owner to confirm)
- Violence: none beyond cartoon peril. The frog falls into lava and the Chef throws food or swings a knife at steps (the target is a step, not the player). No gore or injury to characters on screen (the Chef art has a bloody-looking mouth, see Fear). Answer: none/minimal cartoon.
- Fear: the Kitchen Chef is a crudely drawn cartoon with red eyes and a bloody-looking, toothy mouth; it is the most unsettling art in the game, so answer the fear/violence questions conservatively (mild cartoon). From 24 Oct to 1 Nov each year the game adds a Halloween theme (ghosts, bats, pumpkins, cobwebs), also mild cartoon.
- Language, crime, drugs, alcohol, romance: none.
- Social: no in-game user-generated content. Chat behaviour is whatever Roblox provides by default; the game adds no custom chat (not verified further).
- Commerce: yes, optional Robux purchases (Game Passes for four skins). Flys are earned in play. The shop sells fixed skins at fixed prices; the code shows no loot boxes or random paid items, but the owner should confirm the daily gift reward is not randomised and answer the questionnaire's paid-random-item question accordingly.
- Expect "All ages" / minimal maturity; the owner makes the final answers in the Creator Hub questionnaire.

## Short social / launch post
Hot Frog is out on Roblox! Grab steps, pull the world past you and climb out of the Pot, through the Kitchen (the Chef is NOT friendly), over the Country and up to Space, before the lava gets you. Catch bugs, unlock frogs, race friends. How high can you get? [link]

## Files and where they go (Creator Hub)
1. marketing/icon-512.png -> Creator Hub -> Creations -> Hot Frog -> Configure/Settings -> Icon (512x512 PNG or JPG; Roblox crops it to a rounded square, and the frog face is centred).
2. marketing/ingame-1.png .. ingame-4.png -> Creator Hub -> Creations -> Hot Frog -> Places -> (start place) -> Thumbnails (1920x1080, up to 10). Order: ingame-1 (Kitchen, mid-grab beside the Chef), ingame-2 (Pot, lava along the bottom), ingame-3 (Kitchen, the Chef's knife), ingame-4 (fly catch with the tongue). Then gameplay-3 and gameplay-4 (Country, Space; the ingame set has no Country/Space frame yet), then optionally gameplay-1, -2, -5 and marketing/thumb-1..5.png (composed sprite-art cards), up to the 10-image limit. Remove or move down any older thumbnails so ingame-1 is first. Each is submitted for Roblox moderation after upload.
3. Title, description, genre, devices and the maturity questionnaire -> Creator Hub -> Hot Frog -> Settings (Basic Info / Access / Questionnaire).
4. Optional: add a short gameplay video as a thumbnail after recording one in Studio or the Roblox client (not produced here).

## Notes
- ingame-1..4.png are full-bleed Studio Play captures (2026-11-05, Hot Frog skin, Halloween off, bot-driven climb; raw 1806x1016 frames in marketing/captures/ingame/). Method: the Studio window set to 2221x1460 (SetWindowPos at 0,0), which gives a 16:9 1806x1016 viewport; on the client only, HUD, RaceRail, MenuGui, StoreGui, SpectateGui, DailyRewardGui and GamepadCursor disabled and SetCore("TopbarEnabled", false); Lighting.Atmosphere density 0.08 / offset 0, GlobalShadows off (it drew a dark band over the lower frame) and ExposureCompensation +0.3 (+0.6 for the Pot); the camera held at GameClient's native framing (Scriptable, FOV 40, 43.2 studs from the lane Origin, dropped 1.2 to 1.5 studs) by a RenderStep bind, because it fell back to Custom during the run. tools/make_ingame_thumbs.py scales each frame about 1.06x to 1920x1080 and adds a small title and caption in the top-left; the gameplay pixels are not redrawn. Re-run: python tools/make_ingame_thumbs.py.
- ingame-4 (fly catch) is a held frame: the tongue is the game's own tongue part (UniversalTongue sprite, same colour and mouth origin), created locally and kept stretched to a live fly so the screenshot can catch it; the real tongue lasts about 0.3 s. Quality popups ("PERFECT!") are BillboardGuis, which Studio's MCP screen_capture does not render, so there is no perfect-grab frame.
- No Country or Space ingame frame yet: during the 2026-11-05 session Studio could not fetch the CountryBack and SpaceBack textures (ContentProvider "HttpError: DnsResolve"), so those levels rendered without a backdrop. Recapture them the same way once Studio loads them, add them to SHOTS in tools/make_ingame_thumbs.py, and they replace gameplay-3/-4 in the upload order.
- gameplay-1..5.png are real Studio Play captures (2026-10-23, Hot Frog skin with no colourway, Halloween off, bot-driven climb; raw 1048x955 frames in marketing/captures/). Studio's viewport is portrait-ish, so tools/make_gameplay_thumbs.py scales each frame about 1.13x to the full 1080 px height, sets it on the right of the 16:9 canvas over a blurred, darkened copy of itself, and adds the title and a caption on the left; the gameplay pixels are not redrawn. The in-game HUD (combo, score, Best/Flys/Bugs, level track) is left as it appeared. Re-run: python tools/make_gameplay_thumbs.py.
- thumb-1..5.png are composed from the project's own sprites (tools/make_marketing.py), not captures; keep them only as optional extra cards.
- To recapture: Studio Play, server workspace:SetAttribute("ForceHalloween", false) (the place file currently saves it true) and dress the frog with SpriteSkin.apply(frog, "Hot Frog", false) plus FrogTint 0 after each StudioSkipTo, then StudioBot start and screen_capture.
- Nothing was uploaded or published.
