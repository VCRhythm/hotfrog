# hotfrog — bugs processed by the bug loop

## b-20260919-123127-p3vu  fixed  2026-09-19 12:45
note: GameServer:552: attempt to index nil with 'CFrame' in createFrog, called from initPlayer
cause: FrogModel.model.json sets PrimaryPart only through Rojo's Ref attributes, which the plugin can fail to resolve on sync, so the cloned frog had a nil PrimaryPart.
change: GameServer sets frogTemplate.PrimaryPart to its Body child when unresolved, before any clone.
files: src/server/GameServer.server.luau
test: none
verified: tools/luau_check.sh clean on the file and on src/; not run in Studio
review: n/a

## b-20260919-135837-n9hp  closed-by-user  2026-09-19 13:59
note: I'm not seeing the frog sprites on load. the flies are also just placeholders, not using the actual sprites
resolved: from dashboard

## b-20260919-140016-dm0e  cannot-reproduce  2026-09-19 15:00
note: I'm not seeing the frog sprites on load. the flies are also just placeholders, not using the actual sprites
cause: user ruling "use mcp to do this" (b-20260919-144352-5rbt): the Studio check was run via the Roblox_Studio MCP. The texturing pipeline is correct; assetType=Image upload ids render directly, and the live frog and bug instances carry correct Suffix/Sprite attributes with non-zero Texture ids on server and client, no console errors. The original repro likely predates the working state.
change: no code change; doc 17 step 2 now records the Image-id render check as verified.
files: docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: Studio via MCP: edit-mode Decal with rbxassetid://132401989626297 rendered (screen capture); playtest inspection of Frog_<UserId>.Body.Body and BugTemplate.Art on server and client. Play-mode screen capture came back black (MCP capture limitation), so in-play confirmation is by property inspection, not a picture.
review: n/a

## b-20260919-144352-5rbt  cannot-reproduce  2026-09-19 15:00
note: DECISION: use mcp to do this (reopens b-20260919-140016-dm0e)
cause: answer to b-20260919-140016-dm0e; see that block.
change: none
files: docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: see b-20260919-140016-dm0e
review: n/a

## b-20260919-155020-2sli  ignored  2026-09-19 15:55
note: AUTO warning (server): Infinite yield possible on 'ReplicatedStorage.Shared:WaitForChild("GameDefs")'
cause: not from this project. The stack is the local Studio plugin user_BuildingStatsEditor (another project's tool) waiting for a GameDefs module hotfrog does not have; nothing in the repo references GameDefs.
change: none
files: none
test: none
verified: grep for GameDefs across the repo returns nothing
review: n/a

## b-20260919-160006-wj5q  ignored  2026-09-19 16:05
note: AUTO error (server): StreamingMinRadius is not a valid member of Workspace "Workspace"
cause: not game code. The stack is 'AssistantCommand', a Luau probe the sprite fixer (entry ...150613-2ehi) ran through the Studio MCP with a wrong property name; the repo does not reference the property.
change: none
files: none
test: none
verified: grep for StreamingMinRadius across the repo returns nothing
review: n/a

## b-20260919-160013-geyo  ignored  2026-09-19 16:05
note: AUTO error (server): StreamingTargetRadius is not a valid member of Workspace "Workspace"
cause: same MCP probe as b-20260919-160006-wj5q ('AssistantCommand' stack), not game code.
change: none
files: none
test: none
verified: grep for StreamingTargetRadius across the repo returns nothing
review: n/a

## b-20260919-160647-fhkj  fixed  2026-09-19 16:20
note: AUTO warning (server): [Profiles] FrequencyGames (4272203669): session lock still held by studio-... after waiting -- proceeding anyway.
cause: every Studio play session mints a fresh random SESSION_ID (game.JobId is "" in Studio), so back-to-back playtests looked like foreign live servers to each other and paid the full stale-lock wait, then warned.
change: in load(), a foreign lock whose owner starts with "studio-" is taken over immediately and without the warning, gated by RunService:IsStudio() so production servers are unaffected.
files: src/server/Profiles.luau
test: none
verified: headless only: stylua --check, selene and tools/luau_check.sh pass on the file; not run in Studio (another fixer was driving Studio)
review: n/a

## b-20260919-161227-4uzb  ignored  2026-09-19 16:35
note: AUTO warning (server): DataStore request was added to queue ... Key = u_4272203669
cause: Roblox's per-key throttle notice, raised while Studio playtests were restarted back to back and Profiles load() kept retrying UpdateAsync on the same key waiting out the previous Studio session's lock. That retry loop no longer runs in Studio after b-20260919-160647-fhkj. Not verified by a repro; if it shows up in a normal single playtest, file it by hand so it gets looked at.
change: none
files: none
test: none
verified: not run: inferred from timing (16:12, during the repeated playtests, 6 minutes after the session-lock warning on the same key)
review: n/a

## b-20260919-150613-2ehi  fixed  2026-09-19 17:25
note: still no sprites (reopens b-20260919-140016-dm0e)
cause: every Decal/Texture was on Face = Front (-Z) while the camera sits on the +Z side looking -Z, so all art faced away and only the placeholder-coloured part sides showed; separately the default Roblox character auto-loaded at the origin in front of lane 0's frog.
change: sprites moved to Face = Back in the four templates and every script-side creation (tongue uses Top with a zAxis up vector); Players.CharacterAutoLoads = false plus dropping any loaded character, and createFrog sets player.ReplicationFocus because the place streams. Follow-up after review: pupil OffsetStudsU negated in WorldFrogCosmetics, since the U axis runs the other way on Back.
files: src/assets/FrogModel.model.json, src/assets/BugTemplate.model.json, src/assets/StepTemplate.model.json, src/workspace/PlayField.model.json, src/client/GameClient.client.luau, src/client/WorldBackdrop.client.luau, src/client/WorldScenery.client.luau, src/client/WorldLava.client.luau, src/client/WorldAttract.client.luau, src/client/WorldTutorialSpecks.client.luau, src/client/WorldTouchIndicator.client.luau, src/client/WorldFrogCosmetics.client.luau, src/server/GameServer.server.luau, src/server/BugService.server.luau, src/shared/SpriteSkin.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: selene src/, tools/luau_check.sh (whole src) and rojo build pass; stylua --check passes on touched files. Studio via MCP: in play, 11 frog sprites and 2 bugs camera-facing, opaque, on screen, images fetched, no character in workspace, raycasts unobstructed, no console errors; edit-mode screenshots confirm Back reads un-mirrored and the U/V offset directions; pupil offsets move toward a test target. NOT confirmed by a picture of the frog during a run (play-mode screen capture times out).
review: concern: face flip may reverse U direction for pupil tracking (WorldFrogCosmetics) -- confirmed real by the fixer and fixed in the follow-up; other review checks (camera reasoning, no Front left, no Character dependencies, ReplicationFocus lifetime, no unrelated hunks) came back clean

## b-20260919-155921-alvk  cannot-reproduce  2026-09-19 17:45
note: AUTO warning (client): Infinite yield possible on 'Workspace.PlayField:WaitForChild("Lava")'
cause: transient artefact of the sprite fixer's half-finished edit at 15:59: CharacterAutoLoads = false was in place before player.ReplicationFocus was, so under StreamingEnabled the client had no streaming focus and an empty workspace. The committed fix (cff230a) sets both together; WorldLava only waits for Lava after the local frog exists, and Lava sits about 30 studs from the frog, inside the default streaming min radius.
change: none
files: none
test: none
verified: not run: static reading of WorldLava.client.luau, PlayField.model.json, GameServer createFrog and the cff230a diff; no Studio run
review: n/a

## b-20260919-161258-upo0  fixed  2026-09-19 18:10
note: Tutorial run spawns no steps at all: RunState=Playing, level=Tutorial, workspace.PlayField.Steps stays empty, so the frog just falls with nothing to grab
cause: spawning worked; tutorialRetry's "no death" pull-back reversed a fixed 3 pull-widths of scroll on every Tutorial fall even when nothing had been pulled forward yet, dragging the one-shot spawnAllOnAwake ladder (which never respawns) past the top bound, where it was recycled within one or two retries.
change: Lane tracks netPull (studs pulled forward since the level began, reset in setLevel/new, updated in addPull); tutorialRetry caps its pull-back to that amount and skips the pull when it is zero.
files: src/server/Lane.luau, src/server/GameServer.server.luau
test: none
verified: Studio playtest via MCP: before the fix Steps stayed at 0 children across repeated retries; after it the 3-step ladder stayed in workspace.PlayField.Steps for 11+ s across several fall/retry cycles, no console errors. stylua --check, selene and tools/luau_check.sh pass on both files.
review: n/a

## b-20260919-190522-mvso  fixed  2026-09-19 19:40
note: the sprites need to be sized and have their backgrounds transparent properly. the frog should take up practically the whole screen
cause: two independent faults. (1) Every part that only hosts a sprite was opaque with a Color, so the part showed through each PNG's alpha (source art and upload pipeline are fine). (2) The frog was about 4.4x too small: FrogModel.model.json gave each sprite an arbitrary box instead of its Unity canvas (a Decal stretches and centres the whole padded canvas), Config.LIMB_REST was authored at Unity/10 instead of UNITY_TO_STUDS, and the camera sat at 60 studs (43.7-stud view) versus Unity's orthographic size 50 (31.43-stud view).
change: rebuilt FrogModel.model.json from a UnityPy dump of HotFrog.prefab (head/body/face share one 1024 px @ 8 ppu canvas = 40.229 studs, limbs 1024 px @ 12 ppu = 26.819, grab hands 256 px @ 12 ppu, arm/hand as child parts of their limb welded at runtime); rescaled LIMB_REST and PUPIL_MAX_OFFSET; camera to 43.2 studs at FOV 40; every sprite-host part Transparency = 1 (frog, StepTemplate, BugTemplate, BugService fallback, WorldAttract rungs). Out of scope and filed as three separate inbox entries (step/scenery sprite sizing, attract ladder scale, HandGrab decal swap).
files: src/assets/FrogModel.model.json, src/assets/StepTemplate.model.json, src/assets/BugTemplate.model.json, src/shared/Config.luau, src/shared/WorldConfig.luau, src/client/GameClient.client.luau, src/client/WorldAttract.client.luau, src/server/GameServer.server.luau, src/server/BugService.server.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: selene src/ clean; tools/luau_check.sh (whole src) clean; rojo build succeeded; stylua --check clean on touched files. Studio via MCP playtest: camera (0,0,43.2) FOV 40, live frog parts carry the new canvas sizes, host parts Transparency 1 with non-zero textures on Face = Back, arm/hand children welded. Play-mode screen capture came back black, so measured with WorldToViewportPoint instead: +/-15.714 studs fills 99.9% of viewport height, frog art spans 91.9% of screen height. No confirmation by picture.
review: looks-right

## b-20260919-192618-rqdz  fixed  2026-09-19 19:55
note: Nothing swaps the *HandGrab frog sprites when a limb grabs a step
cause: WorldFrogCosmetics.client.luau tracked eyelids and pupils but never read the RightHandGrab/LeftHandGrab decals (hidden on the rig) or their open-hand counterparts, so nothing toggled Transparency on grab, although GrabTarget already had the per-limb held inference.
change: added open/grab hand Decal fields to FrogState, populated in trackFrog from the FrogModel hierarchy, plus updateHandGrab(state), which uses GrabTarget.limbHeldPosition per limb each Heartbeat to swap Transparency between the open and grab decals. Doc 17 moves the gap to the closed list.
files: src/client/WorldFrogCosmetics.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check, tools/luau_check.sh and selene pass on the file. Studio via MCP playtest: fired StartRun/GrabStep for the local frog and inspected decals; RightHandGrab and LeftHandGrab flipped Transparency 1 to 0 while RightHand/LeftHand flipped 0 to 1 once the limb was on a step. No picture (play-mode capture is black).
review: n/a

## b-20260919-192609-m36c  fixed  2026-09-19 20:45
note: Step and scenery sprites are still stretched into arbitrary collider-sized parts, not their Unity sprite canvas size
cause: step/scenery parts were guessed, roughly collider-sized boxes while a Decal stretches the whole padded Unity canvas across the face, so the art was squashed; the part doubled as the grab hit area, which is why it had been kept small. Unity keeps the two separate (Controller.cs CheckTouch is a point overlap against the Collider2D).
change: StepKinds gained size (whole sprite canvas) and hitSize (doc 12 Collider2D in studs); GameServer.acquireStep publishes a HitSize attribute; GameClient resolves a tap to its point on the play plane and point-tests it against each lane step's HitSize rectangle (raycast narrowed to Bugs); StepTemplate default size and all 9 SceneryKinds sizes corrected, sprite-hosting scenery parts Transparency = 1. Review follow-up: Lane.isOutOfBounds and WorldScenery.isOutOfBounds now recycle on the part's extent instead of its centre, like Unity's border triggers. Doc 17: gap closed; new gap rows for non-centre sprite pivots, Chef/US canvases wider than LANE_SPACING, tall steps popping in at spawn, hard-coded Flingee splash size.
files: src/shared/StepKinds.luau, src/shared/SceneryKinds.luau, src/server/GameServer.server.luau, src/server/Lane.luau, src/client/GameClient.client.luau, src/client/WorldScenery.client.luau, src/assets/StepTemplate.model.json, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check on touched files, selene src/, tools/luau_check.sh (whole src) and rojo build all pass. Studio via MCP playtest: steps replicate with Size 8.046 and HitSize (8.046, 8.046), the rectangle test hits inside the collider and misses past its edge, all kinds print expected size/hitSize pairs, 3 tutorial steps still alive at 4 s after the bounds change. NOT verified: a real on-screen tap end to end, and the recycle change in a sideways-scrolling level.
review: concern: Lane.isOutOfBounds recycled by centre against a 6-stud margin, so large sprites would pop out on screen -- confirmed real by the fixer and fixed in the follow-up

## b-20260919-192618-ge28  fixed  2026-09-19 20:55
note: Menu attract-mode ladder is tuned to the old undersized frog and now looks tiny beside the corrected rig
cause: the ATTRACT_STEP_SIZE / ATTRACT_STEP_X / ATTRACT_STEP_Y_GAP / ATTRACT_ANCHOR_OFFSET constants in WorldConfig.luau were still tuned to the old rig (arbitrary sprite boxes, LIMB_REST at Unity/10), so the ladder was out of proportion once the rig grew about 3.1 to 3.5x.
change: rescaled the four constants from Config.LIMB_REST's growth and the WhiteRock canvas (7.314 square); WorldAttract now centres the 3 rungs on the anchor so the ladder fits the +/-15.7-stud view, and the X offsets are capped to clear the frog's reach while staying inside the 22-stud lane bound. Doc 17 moves the gap to the closed list.
files: src/shared/WorldConfig.luau, src/client/WorldAttract.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check, selene and tools/luau_check.sh clean on both Luau files. Studio via MCP playtest: attract frog body at (15,0,-0.2), rungs at Y -11.05/0/+11.05 (max extent 14.71 < 15.7) and X 12/18/18 (max edge 21.66 < 22), limbs snap to the rungs after two decision cycles, no console errors from the touched scripts. No picture: on-screen framing checked by geometry only (headless viewport reports 1x1), so it still wants a human look in Studio.
review: n/a

## b-20260919-200543-yixb  fixed  2026-09-19 21:25
note: Tutorial is unplayable after the camera fix: the 3 tree steps spawn above the visible frustum and the frog falls below it
cause: two stale constants in the frog's fall, both settled by the Unity source. Config.GRAVITY / MAX_FALL_SPEED were Frog.cs's Unity-unit values (20 / 60) read as studs, so the fall was about 3.2x too fast (and GRAVITY_ACCEL was 0.6/s where Unity adds 0.02 per FixedUpdate = 1.0/s); and the frog's death check used Config.DESPAWN_Y (-30, the step recycle line) while Unity's frog stops at -50 u, the bottom edge of the camera band. The filer later corrected the note: steps do descend into view; the frog leaving the band was the real fault.
change: GRAVITY / MAX_FALL_SPEED converted with UNITY_TO_STUDS (6.2857 / 18.857 studs/s), GRAVITY_ACCEL = 1.0; new Config.LAVA_Y = -50 * UNITY_TO_STUDS (-15.714) is the frog's death / Tutorial-retry line in GameServer, the splash height in WorldLava and the top face of PlayField.Lava. DESPAWN_Y still means "recycle steps". Doc 17: records the run-end deviation (Unity ends the run when both limbs are free; the port ends it at the lava) and sharpens the camera-aspect gap (Unity's X offsets derive from a portrait screen, so the port's may be about 2.5x too wide).
files: src/shared/Config.luau, src/server/GameServer.server.luau, src/client/WorldLava.client.luau, src/client/SfxEvents.client.luau, src/workspace/PlayField.model.json, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check on touched files, selene src/, tools/luau_check.sh and rojo build pass. Studio via MCP playtest: camera band +/-15.72; after StartRun the frog falls 0 to about -14.7 and resets at about 1.8 s (Tutorial retry), never leaving the band (before: ran to -30); GrabStep on the lowest tree (y=-3.1) with the frog at y=-2.3 was accepted and the lane pulled. No console errors. NOT confirmed: anything by picture, horizontal framing, and the non-Tutorial death path (LAVA_Y to GameOver to Menu).
review: looks-right

## b-20260919-211853-u7zb  ignored  2026-09-19 21:25
note: AUTO error (client:FrequencyGames): AssistantCommand:19: attempt to index nil with 'Position'
cause: not game code. 'AssistantCommand' is a Luau probe a fixer ran through the Studio MCP during its own playtest (same as the earlier StreamingMinRadius entries); the nil index is in the probe, not in src/.
change: none
files: none
test: none
verified: not run: stack names only AssistantCommand, which does not exist in the repo
review: n/a

## b-20260919-210748-vlyq  fixed  2026-09-19 21:55
note: the controls of hot frog are essential-- on kbm, one mouse key must be down at all times. right click works as well as left click to control the right hand. left click controls the left hand
cause: GameClient only listened for MouseButton1/Touch, so right click never grabbed, and an input-up freed "the most recently grabbed slot" instead of the limb that input held; GameServer kept held steps in a packed array rendered positionally against f.limbs = {RightLimb, LeftLimb}, so which hand reached a step depended on grab order and a release shuffled the other hand's step onto the freed limb.
change: GameClient treats both mouse buttons as grab inputs with a fixed hand (left button = LeftLimb slot 2, right = RightLimb slot 1; touch keeps Unity's "whichever limb is free" rule), remembers which limb each live input holds, releases exactly that limb on its own input-up and sends the limb index with GrabStep. GameServer keys f.held by limb index, isHolding() replaces #f.held == 0, and GrabStep / ReleaseStep validate the raw client value with isLimbIndex (exactly 1 or 2) before any score/pull/state change. Run-end and fall-on-both-free rules untouched. Doc 17 records the button-to-hand mapping.
files: src/client/GameClient.client.luau, src/server/GameServer.server.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check, selene src/, tools/luau_check.sh and rojo build pass after the final edit. Studio via MCP playtest: GrabStep with limb 2 then 1 put steps under LeftLimb then RightLimb, releasing limb 1 left the left hand's step in place; GrabStep with 0/0, 0, 3, "2", math.huge, 1.5 and a table, and ReleaseStep with 0/0 and "1", were all refused with score 0 and a clean console, then a valid grab worked. NOT exercised: real mouse buttons (headless Studio delivers no mouse events); a human should confirm right click grabs in a real client.
review: concern: limb index validation let NaN through (score/pull applied, then a NaN table key error) -- confirmed and fixed in the follow-up with strict 1-or-2 validation on both remotes

## b-20260919-210638-sp3q  fixed  2026-09-19 22:05
note: the frog is missing the whites of his eyes
cause: Unity's HotFrog.prefab has separate LeftSclera/RightSclera SpriteRenderers (sortingOrder 0, behind the eyes at order 1) that the rebuild of FrogModel.model.json in 7607a9d dropped, so only the eyelid-crease "Eye" decal and the black pupil texture were rigged; the white fill layer never existed.
change: added LeftSclera/RightSclera Decal children under Head (Suffix-driven, resolved through SkinAssets.part's fallback to Universal art, since Hot Frog has no skin-specific sclera) and renumbered the eye-layer ZIndex stack (Head 0 < Mouth 1 < Sclera 2 < Eye 3 < Pupil 4 < Eyelids 5) to match Unity's sorting order.
files: src/assets/FrogModel.model.json
test: none
verified: rojo build passes. Studio via MCP in Edit mode: cloned the FrogModel asset, applied SpriteSkin.apply(clone, "Hot Frog"), both sclera decals resolved to non-zero asset ids, and an edit-mode screen capture shows white sclera ovals behind the pupils and eyelid creases. Other skins not checked (same fallback code path). Not seen in a live run.
review: n/a

## b-20260921-101202-gdw4  fixed  2026-09-21 10:35
note: flies just look like white dotes instead of flies like they do in unity
cause: BugTemplate only rendered the body sprite (Bug.png, a faint crescent); Unity's Bug prefab layers a "Wings" child (Wing1.png) on top, which the port never added.
change: Added a "Wings" Decal (Sprite="Wing1", ZIndex 1 above the body) to BugTemplate.model.json and mirrored it in BugService's fallback template; Wing1 was already uploaded.
files: src/assets/BugTemplate.model.json, src/server/BugService.server.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; root cause confirmed live in Studio (bug had one Decal, no Wings); fix not seen rendering live (playtest in progress, not restarted).
review: n/a

## b-20260921-101338-hfvp  fixed  2026-09-21 10:40
note: there's a visible scroll bar to the right of the screen
cause: The multiplayer race rail (GameClient, doc 15 item 5) is a thin full-height translucent Frame on the right edge, shown even when the player is alone, so it reads as a stray scrollbar.
change: Rail starts hidden and each poll tick shows it only when another player is present.
files: src/client/GameClient.client.luau
test: none
verified: stylua, selene, luau_check pass; offending instance located live in Studio (inspect only); fix not verified live (user mid-playtest).
review: n/a

## b-20260921-100739-ldv9  fixed  2026-09-21 10:50
note: I'm running out of platforms to climb
cause: Lane.spawnPosition's clampToLane clamped Movements offsets per axis, so corner spawns landed beyond Config.MAX_GRAB_DISTANCE and were never grabbable (Tutorial's 3rd tree every run; 2 of 3 positions of Pot's DownStepSpawner and DownLeftStepSpawner).
change: After the per-axis clamp, corners still beyond MAX_GRAB_DISTANCE are pulled back onto the reach circle; in-range spawns unchanged. Doc 17 entry added.
files: src/server/Lane.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua, selene, luau_check pass; clamp math re-derived via execute_luau against real Config (35.4->30, 31.8->30). Not playtested live (user in Play mode).
review: n/a

## b-20260921-100824-3azi  fixed  2026-09-21 11:15
note: the sprite of the frogs arms should be behind objects, the gripped hands in front of objects
cause: FrogModel put the arm parts at Z +0.2 (in front of the Z=0 step plane), and the HandGrab decals lived on the limb root part, which GameServer moves onto the gripped step's position, so the grip was coplanar with the step.
change: Arm parts moved to Z -0.2 (behind steps); HandGrab decals moved onto the RightHand/LeftHand parts (Z +0.3, in front), with WorldFrogCosmetics looking them up there. Doc 17 deviation row added (Z depth instead of Unity sorting layers).
files: src/assets/FrogModel.model.json, src/client/WorldFrogCosmetics.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua, selene, luau_check, JSON parse, rojo build pass; camera/step Z assumptions confirmed live via inspect; new layering not seen live (user mid-playtest).
review: n/a

## b-20260921-110054-r51c  fixed  2026-09-21 11:20
note: this changed caused his gripped hands to now appear enormous (reopens b-20260921-100824-3azi)
cause: c8a77f0 moved the RightHandGrab/LeftHandGrab decals onto the RightHand/LeftHand parts to fix layering, but those parts are sized for the open-hand sprite's 1024 px canvas (26.819 studs); the grab sprite's own canvas is 256 px (6.705 studs, per doc 17's rig-sizing row), so the Decal stretched it 4x.
change: Grab decals now live on their own RightHandGrab/LeftHandGrab parts (new, siblings of RightHand/LeftHand under the limb root), sized to the grab sprite's 6.705-stud canvas, at the same X/Y and Z +0.3 (still in front of steps) that RightHand/LeftHand used. WorldFrogCosmetics looks the decals up on these new parts. Doc 17 row updated.
files: src/assets/FrogModel.model.json, src/client/WorldFrogCosmetics.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua, selene, luau_check, JSON parse, rojo build pass; new host parts weld the same way as RightArm/RightHand (GameServer's generic per-descendant BasePart weld-to-parent loop, unchanged); not seen live (Studio session predates this edit, no respawn triggered).
review: n/a

## b-20260921-110646-eqim  fixed  2026-09-21 11:25
note: the flies look better but their bodies are white instead of black (reopens b-20260921-101202-gdw4)
cause: Sprites/Other/Bug.png is a white alpha-only silhouette meant to be tinted; the body Art Decal kept the default white Color3.
change: Body Art Decal Color3 = black in BugTemplate.model.json and on BugService's runtime fallback decal; wings untouched (their art is already black).
files: src/assets/BugTemplate.model.json, src/server/BugService.server.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; not seen live.
review: n/a

## b-20260921-110833-b3kt  fixed  2026-09-21 11:40
note: HUD shows placeholder text 'Label' under Best, and 'Flys: 145' overlaps the Roblox player list top-right
cause: GameClient's makeLabel never set initial Text, so a label showed Roblox's default "Label" until ProfileChanged fired; StoreUI's Flys balance label was pinned to the top-right corner under the player list.
change: makeLabel takes an explicit initial text; StoreUI's Flys label moved just above the Shop button, bottom-right.
files: src/client/GameClient.client.luau, src/client/StoreUI.client.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; not seen live.
review: n/a

## b-20260921-110937-uesm  fixed  2026-09-21 11:42
note: Run-over panel shows 'Next gift in -9223372036854775808:-9223372036854775808 — open Shop'
cause: MenuClient connected to GiftStatus only after several WaitForChild calls, missing GiftService's one-shot push; giftReadyAt stayed math.huge and %d on inf printed INT64_MIN.
change: New GetGiftStatus RemoteFunction in GiftService; MenuClient invokes it after connecting. The formatter shows "open Shop" when remaining is non-finite.
files: src/server/GiftService.server.luau, src/client/MenuClient.client.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; not seen live.
review: n/a

## b-20260921-111757-1jf7  ignored  2026-09-21 12:00
note: AUTO error (server): LoadStringEnabled is not a valid member of ServerScriptService "ServerScriptService"
cause: Thrown by an agent's MCP execute_luau probe (trace: AssistantCommand, line 1), not by game code.
change: none
files: none
test: none
verified: n/a
review: n/a

## b-20260921-110140-f9ic  fixed  2026-09-21 12:05
note: I'm still running out of things to climb after 4 steps or so (reopens b-20260921-100739-ldv9)
cause: PULL_SPAWN_SPEED 25 gave each 6-stud grab only 0.24 s of spawner time (Unity keeps spawners on 1 s per grab), so supply was below consumption and the lane deadlocked once nothing was grabbable; Tutorial->Pot also left Pot with one off-screen step.
change: PULL_SPAWN_SPEED = 8 (~0.75 s spawner time per grab; orchestrator chose this over a bigger PULL_DISTANCE). tickSpawners spends the budget over PULL_TIME, loops every spawn it covers, and spreads spawns along spawnDirection (as does prefill). GameServer prefills Pot after the Tutorial switch. Doc 17 row added.
files: src/shared/Config.luau, src/server/Lane.luau, src/server/GameServer.server.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: headless sim with the real Lane/Levels/StepKinds: Tutorial/Pot/Kitchen 300/300 grabs, Country median 300 (worst 158); stylua, selene, luau_check, rojo build pass. Not play-tested yet. Caveat: new steps appear just inside the top of view rather than scrolling in.
review: looks-right

## b-20260921-110833-9dzn  fixed  2026-09-21 12:12
note: Frog falls and dies right after pressing Play before any grab; Unity gates falling on canFall (first canPull grab)
cause: The Heartbeat fall/lava-death gate checked only RunState.Playing; Unity's Player.cs also requires canFall, set on the first grab of a pullable step.
change: FrogState.canFall (false at create/StartRun/respawn, true on the first successful GrabStep) now gates gravity and lava death.
files: src/server/GameServer.server.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; checked against Player.cs; not seen live yet.
review: n/a

## b-20260921-112735-t2ly  fixed  2026-09-21 12:35
note: HUD shows 'Flys: 0' and 'Bugs: 0' under Best while the Shop balance shows 'Flys: 145'; two Flys counters disagree (reopens b-20260921-110833-b3kt)
cause: GameClient connected ProfileChanged after several yielding WaitForChild calls, missing SkinService's one-shot push; StoreUI (no yields) caught it, and it had its own duplicate Flys label.
change: GameClient connects ProfileChanged early and caches the latest profile for the HUD label; StoreUI's duplicate Flys label removed (doc 15 item 5 names the HUD label as the authoritative one).
files: src/client/GameClient.client.luau, src/client/StoreUI.client.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; not seen live.
review: n/a

## b-20260921-112735-kd7u  fixed  2026-09-21 12:35
note: HOTFROG menu title stays on screen during a run
cause: MenuClient's title label was not part of the Playing branch that hides the menu panels.
change: title hidden while Playing, shown again in showMainMenu/showEndPanel.
files: src/client/MenuClient.client.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; not seen live.
review: n/a

## b-20260921-112713-7mxu  fixed  2026-09-21 12:45
note: Pot spawns every new step at X=23.6 studs, off-screen; nothing reachable on screen after 2 grabs
cause: Step spawner Movements X was scaled by the lane half-width (22) instead of Unity's screen half-width (~8.84 studs in portrait), so Pot's points landed at x=33/55 and clampToLane dragged them to x≈23.6; per-grab budget spawns also stacked ~2.2 studs apart.
change: Config.SPAWN_VIEW_HALF_WIDTH (portrait 9:16) scales step Movements X; vertical spawners clamp X to it; Lane.clearSpot keeps SPAWN_GAP between grab boxes (drops a spawn if no clear spot within 12 studs); spawners pause for PULL_TIME after a pull. Doc 17 updated.
files: src/shared/Config.luau, src/shared/Levels.luau, src/server/Lane.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: headless sim, 10 runs x 50 grabs: Pot visible spawns 13%->44% (75% within 16:9 view), starved grabs 173->57/500, overlaps 67%->0%; Kitchen/Country similar. stylua, selene, luau_check, rojo build pass. Residual: some grabs still find no visible step; Tutorial trees now at x≈±8.8.
review: n/a

## b-20260921-114520-qvqh  fixed  2026-09-21 13:00
note: HUD still shows 'Flys: 0' after the t2ly fix (balance was 145) (reopens b-20260921-112735-t2ly)
cause: ProfileChanged is a one-shot FireClient push from Profiles.Loaded; if it fires before GameClient connects (DataStore load race, not closed by t2ly's earlier connect), the profile is lost for the session and the HUD keeps its 0 default.
change: SkinService adds a GetProfile RemoteFunction (returns Profiles.get(player)), mirroring GiftService's GetGiftStatus; GameClient pulls it once at startup unless a push already landed, keeping the ProfileChanged connection.
files: src/server/SkinService.server.luau, src/client/GameClient.client.luau
test: none
verified: stylua, selene, rojo build, luau_check pass; live in Studio via MCP: server flys=145, client FlysLabel "Flys: 145" (Bugs: 0 is the per-run catch counter, correct); no console errors.
review: n/a

## b-20260921-111337-hqcb  fixed  2026-09-21 13:15
note: the unity game gives the frog a sway and bob with each grab (answered by b-20260921-113838-9b90: "DECISION: A")
cause: User ruling "A: full port, including gravity continuing while holding". The port never ran Frog.Bob and stopped gravity while holding; Unity's SteadilyLowerHead keeps sinking while held, and each grab resets it, sways and bobs.
change: GameServer runs Frog.Bob on every accepted GrabStep (OutSine X sway to the step, Z rock punch, rise to min(5u, y+50u) when at or below -5u; Config.BOB_* in studs). Gravity keeps running while holding: a holding frog stops at LAVA_Y, and death only comes at LAVA_Y holding nothing. The canFall gate is kept. The rock rotates the whole rig about the body centre, and the reach check now measures from the lane origin. Docs 15 and 17 updated.
files: src/server/GameServer.server.luau, src/shared/Config.luau, src/server/Lane.luau, docs/roblox-port/17-status-and-known-gaps.md, docs/roblox-port/15-menus-and-input.md
test: none
verified: stylua, selene, luau_check, rojo build pass; headless Python sim of the bob and gravity loop keeps the frog within -8.0..+1.57 studs at 0.35-1.2 s grab cadence; not seen in Studio.
review: looks-right

## b-20260921-115308-opcd  fixed  2026-09-21 13:25
note: Pause panel says held steps don't fall, but the frog now sinks while holding (it just can't die)
cause: The Pause comment and status text predated fd231a1 and still described gravity freezing while the frog holds a step.
change: The Pause block comment and the isHoldingAnything() status text in openPause() now say the frog keeps sinking but can't die while holding, matching doc 15 item 4 and doc 17's Death condition row.
files: src/client/GameClient.client.luau
test: none
verified: stylua, selene, luau_check pass; not seen in Studio.
review: n/a

## b-20260921-114209-vhv6  fixed  2026-09-21 13:40
note: hands are the right size now but they are detached from the arms when grabbing (reopens b-20260921-110054-r51c)
cause: r51c placed RightHandGrab/LeftHandGrab at RightHand/LeftHand's X/Y, but Unity's sprite metadata pivots the open hands BottomCenter (alignment 7) and the grab sprites Center (alignment 0), so the grab hand rendered about 13.4 studs from the arm end.
change: RightHandGrab/LeftHandGrab CFrames moved down by half the open-hand canvas (13.4095 studs) to (±6.2857, -13.8566/-13.7595, 0.3), which is exactly each limb root's position; size and Z +0.3 kept.
files: src/assets/FrogModel.model.json
test: none
verified: rojo build passes; Studio MCP confirmed the synced FrogModel has the new CFrames; the visual check was not completed (screen_capture returned a black frame); offset derived from sprite .meta pivots and cross-checked against pixel bounds.
review: n/a

## b-20260921-113838-9b90  fixed  2026-09-21 13:15
note: DECISION: A (reopens b-20260921-111337-hqcb)
cause: User's ruling on hqcb: full Frog.Bob port, with gravity continuing while holding.
change: Applied in commit fd231a1; see the b-20260921-111337-hqcb block above.
files: src/server/GameServer.server.luau, src/shared/Config.luau, src/server/Lane.luau, docs/roblox-port/17-status-and-known-gaps.md, docs/roblox-port/15-menus-and-input.md
test: none
verified: see hqcb block.
review: looks-right

## b-20260921-142201-j4z3  fixed  2026-09-21 14:45
note: the frog grabs the carrot in the wrong place
cause: Carrot.png.meta has a non-centre sprite pivot (0.305, 0.397), so Unity's Limb.Move target (the step transform, anchored at that pivot) sits off-centre in the carrot canvas, while the port snapped held limbs to the part's geometric centre.
change: optional StepKinds gripOffset (Carrot = (pivot - 0.5) * ART_CARROT = (-3.14, -1.66) studs), stored as a GripOffset attribute in acquireStep and added to step.Position when snapping a held limb; collider, reach and decal untouched. Doc 17 updated.
files: src/shared/StepKinds.luau, src/server/GameServer.server.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check, selene, luau_check.sh, rojo build pass. Not confirmed in game: a Studio play session was live (inspect only; it still ran the pre-fix module).
review: n/a

## b-20260921-142133-wica  fixed  2026-09-21 15:00
note: make sure hit detection on steps is pretty generous (especially for carrots)
cause: GameClient.stepAt centred the HitSize tap rectangle on the carrot's canvas centre, but Unity's collider offset is relative to the off-centre sprite pivot, so the carrot hitbox sat ~3.2 studs right / 1.5 up of the visible art and taps mostly missed.
change: optional StepKinds hitOffset (Carrot = gripOffset + Collider2D.offset in studs = (-3.17, -1.48)), published as a HitOffset attribute in acquireStep and used by stepAt to recentre the tap rectangle; other kinds unchanged. Server GrabStep does no tap hit-test, so it accepts whatever the picker offers. Hitbox sizes and snap-assist tolerance not enlarged. Doc 17 updated.
files: src/shared/StepKinds.luau, src/server/GameServer.server.luau, src/client/GameClient.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check, selene, luau_check.sh, rojo build pass. Not playtested: a Studio play session was live (inspect only; console clean).
review: n/a

## b-20260921-142102-52bb  fixed  2026-09-21 15:15
note: the fall animation needs to copy from unity game where it's more dramatic
cause: killFrog froze the frog at LAVA_Y at the moment of death; Unity's Frog.cs Die() -> Fall() holds 1 s, plays the fall sound, then sinks the body well past the lava (endY = -100u). That sink was never ported.
change: FrogState.fallTween holds for Config.DEATH_FALL_DELAY (1 s), then eases to Config.DEATH_FALL_Y (-100u in studs) over DEATH_FALL_TIME (1 s, standing in for SmoothDamp); Heartbeat drives it while f.dead, cleared on respawn. RESPAWN_DELAY 1.5 -> 2.2 s so the beat fits; doc 15 updated. GameOver timing, SFX and the Tutorial retry path untouched.
files: src/server/GameServer.server.luau, src/shared/Config.luau, docs/roblox-port/15-menus-and-input.md
test: none
verified: stylua --check, selene, luau_check.sh, rojo build pass. Not playtested: a Studio play session was live (inspect only; console clean).
review: n/a

## b-20260921-152551-2lar  fixed  2026-09-21 16:00
note: shop is behind the play menu
cause: StoreUI's persistent Shop toggle set its own panel.Visible directly, never hiding MenuClient's mainPanel; StoreGui had no DisplayOrder (0 < MenuGui's 5).
change: new StoreOpened BindableEvent in MenuBridge (next to StoreClosed); the Shop toggle fires it on open and StoreClosed on close, so MenuClient hides/restores the main/end panels as the Frogs button does; StoreGui DisplayOrder = 5.
files: src/client/StoreUI.client.luau, src/client/MenuClient.client.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; Studio MCP playtest: Shop toggle hid mainPanel and showed the store, store X restored mainPanel.
review: n/a

## b-20260921-152641-ilxp  fixed  2026-09-21 16:00
note: settings is blocked by another menu over top of it
cause: the Settings and Top Scores buttons showed their panel without hiding the nearly opaque mainPanel, and their Close buttons never restored it.
change: hideMainPanels()/restoreMainPanels() helpers in MenuClient wired into Settings, Top Scores and the existing store open/close flow.
files: src/client/MenuClient.client.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; Studio MCP playtest: Settings and Top Scores each hide mainPanel on open and restore it on Close.
review: n/a

## b-20260921-154238-evo2  ignored  2026-09-21 16:10
note: AUTO error (client:FrequencyGames): Activate is not a valid member of TextButton "Players.FrequencyGames.PlayerGui.StoreGui.Shop"
cause: raised by a fixer's MCP execute_luau test snippet (trace "AssistantCommand, line 21"), not by game code; no src/ script calls :Activate().
change: none
files: none
test: none
verified: grep of src/ and bugloop/ for :Activate() finds nothing
review: n/a

## b-20260921-152631-vdj1  fixed  2026-09-21 16:20
note: gift button resets the timer but doesn't obviously do anything other than increment flys. on unity it goes to a screen where flies explode on to the screen and the player has the opportunity to eat them (for fun)
cause: GiftService.ClaimGift only incremented Flys; Unity's MenuManager.SpawnGiftFlys burst of catchable bugs was never ported (doc 09 deferred it as polish).
change: ClaimGift fires a new ServerStorage/SpawnGiftFlys BindableEvent after the flat grant; BugService bursts GIFT_FLYS (100) pooled bugs onto the claimant's lane tagged Reward=false, which play the catch feedback but pay no Flys (no double pay). Docs 09 and 17 updated (deviation: flat grant instead of catch-derived payout).
files: src/server/GiftService.server.luau, src/server/BugService.server.luau, docs/roblox-port/09-gifts-and-ads.md, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua, selene, luau_check, rojo build pass; Studio MCP playtest: two real ClaimGift calls each gave exactly +100 Flys and burst Reward=false bugs on the lane; 5 caught via CatchBug fired BugCaught feedback with Flys unchanged; no console errors.
review: n/a

## b-20260921-155051-qc3l  ignored  2026-09-21 16:20
note: AUTO error (server): OnServerInvoke is a callback member of RemoteFunction; you can only set the callback value, get is not available
cause: raised by a fixer's MCP execute_luau test snippet (trace "AssistantCommand, line 9"), not game code.
change: none
files: none
test: none
verified: trace points at an AssistantCommand, not a src/ script
review: n/a

## b-20260921-164251-ho4b  answered  2026-09-21 17:10
note: what is the green square with a circle in it?
cause: not a bug: it is the ported TouchIndicator (Player/TouchIndicator.cs), a dot drawn where you tap or click, coloured by reach (green = within grab range). Drawn by src/client/WorldTouchIndicator.client.luau for the local lane only.
change: none
files: none
test: none
verified: triage read of WorldTouchIndicator and the screenshot
review: n/a

## b-20260921-164534-v6fo  fixed  2026-09-21 17:25
note: the step feedback "perfect" "great" etc should appear right on the grabbed step
cause: WorldQualityPopup only used a grab position captured before ScoreChanged arrived; the held limb replicates a little later than the remote, so the match often missed and the popup fell back to the frog's head/body.
change: the match now also works the other way: a ScoreChanged with no captured position is parked as pendingQuality and resolved at the next limb-extend transition within QUALITY_POPUP_MATCH_WINDOW; head/body fallback only when the window lapses.
files: src/client/WorldQualityPopup.client.luau
test: none
verified: stylua, selene, luau_check pass. Not playtested (MCP not attached for this fixer).
review: n/a

## b-20260921-164409-nkkh  fixed  2026-09-21 17:50
note: when grabbing, steps should slide in to near the center of the screen. right now we're too far to the edge
cause: each grab pulled a fixed 6 studs wherever the grabbed step was, and new steps were placed after the pull settled at staging points that could already be inside the view (e.g. Pot DownRight at (-8.84, 7.86)), so steps popped in and the grabbed step stopped short of centre.
change: a grab pulls its grip point (incl. carrot GripOffset) to lane centre, clamped 2-24 studs, over distance/40 s (0.25-0.6 s), as additive eased motions in Lane.advanceMotions that replace the per-step tweens. Lane.spawnForPull spawns at grab time with Unity's 1 s spawner window per grab (PULL_SPAWN_WINDOW replaces PULL_SPAWN_SPEED), starting each step outside the camera band (Lane.entryShift) so the pull slides it in. Prefill and the Tutorial ladder slide in via GameServer.slideIn. clearSpot/isOutOfBounds use rest positions; tutorialRetry pull-back is 3×PULL_MAX_DISTANCE capped at net pull. Doc 17 "Spawner time per grab" row rewritten as an owner-ruling deviation.
files: src/server/Lane.luau, src/server/GameServer.server.luau, src/shared/Config.luau, src/shared/PullMath.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua, selene, luau_check, rojo build pass. Headless Edit-mode sim, 20 runs × 50 grabs: 0 spawns started inside the view, 0 overlaps, grip ends 0.5-1 stud from centre; about 30% of Kitchen/Country grabs still find no step ahead (strict portrait metric). Live playtest: carrot grabs pulled 8.5 and 14.7 studs with the grip ending at y=0.00; new spawns started above the view edge and slid in; no console errors. Not live-tested: Tutorial ladder slide-in and tutorialRetry.
review: looks-right (only note: eased() never applies a zero-duration motion; no caller uses one today)

## b-20260921-164429-ee9c  fixed  2026-09-21 17:50
note: steps are still just appearing on screen rather than sliding in
cause: same as b-20260921-164409-nkkh: spawns were placed at staging points inside the view after the pull had settled.
change: fixed together with b-20260921-164409-nkkh (spawn outside the camera band at grab time, carried in by the pull).
files: see b-20260921-164409-nkkh
test: none
verified: see b-20260921-164409-nkkh
review: looks-right

## b-20260921-152825-fzl6  fixed  2026-09-21 17:50
note: steps tend to just appear on screen rather than slide in
cause: decision "steps must visibly slide in" (the user re-filed it as b-20260921-164429-ee9c "steps are still just appearing on screen rather than sliding in"); applied in b-20260921-164409-nkkh.
change: see b-20260921-164409-nkkh
files: see b-20260921-164409-nkkh
test: none
verified: see b-20260921-164409-nkkh
review: looks-right

## b-20260921-164509-uork  fixed  2026-09-21 18:05
note: the rocks are supposed to be brownish but currently appear as white
cause: WhiteRock.png is a blank white silhouette meant to be tinted by Unity's SpriteRenderer.color; StepKinds had no colour field and acquireStep never set the decal's Color3.
change: optional StepKinds color (FallingRock/Castle Color3(1, 0.459, 0.395), Beetle black, from the doc 12 §1 dump); acquireStep sets the Art decal's Color3 and resets it to white for untinted kinds, so pooled parts don't keep a stale tint.
files: src/shared/StepKinds.luau, src/server/GameServer.server.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; Studio execute_luau ran the new acquireStep logic on a cloned StepTemplate: FallingRock/Castle tinted, Beetle black, SlowFallRock/StillRock white. Not seen in a live run. Fixer filed a follow-up entry (h1ym: Beetle uses the wrong sprite).
review: n/a

## b-20260921-164343-m63b  fixed  2026-09-21 18:20
note: the gift screen after a run was blocked by the main menu appearing right away
cause: MenuClient showed the main menu on every RunStateChanged("Menu"), but the server flips Dead->Menu on the RESPAWN_DELAY timer only to reset the lane, so the end/gift panel was replaced about 2 s after every death; Unity (UI/MenuManager.cs) switches screens only on a player action.
change: client-only endPanelDismissed flag; the automatic Menu transition leaves the end/gift panel up until the player presses Home, and restoreMainPanels respects the flag. Server timer unchanged.
files: src/client/MenuClient.client.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; Studio MCP playtest fired RunSummary -> Dead -> Menu and saw EndOfRun visible with MainMenu hidden; no console errors.
review: n/a

## b-20260921-172346-h1ym  fixed  2026-09-21 18:35
note: Beetle step uses WrappedRock sprite/size instead of WhiteRock per Unity dump
cause: StepKinds.Beetle used WrappedRock/ART_WRAPPED, contradicting doc 12 (Beetle.prefab = WhiteRock.png tinted black, 256px canvas); no deviation recorded in doc 17.
change: Beetle sprite -> WhiteRock, size -> ART_ROCK; hitSize (HIT_ROCK) and black tint unchanged.
files: src/shared/StepKinds.luau
test: none
verified: stylua, selene, luau_check pass; rojo build and Studio not run (classic-mode fixer running concurrently).
review: n/a

## b-20260921-164458-8liv  fixed  2026-09-21 18:55
note: I want a mode where the steps keep falling even when they aren't grabbed. call it "classic". and players have to keep up with a constantly falling rock
cause: feature request; the port only scrolls once per grab, so nothing moves while the player is idle.
change: per-run Mode (Normal default / Classic) picked by a "Mode:" main-menu button, sent as StartRun's argument, validated server-side, stored as Lane.mode + lane `Mode` attribute. Classic drifts every step continuously at Config.CLASSIC_SCROLL_SPEED (Pot 10 / Kitchen 13 / Country 16 Unity u/s, none in Tutorial) from the first grab until death; drift banks spawner time via spawnForPull and publishes PullDelta; a held step reaching lava or leaving the lane force-releases, so an idle frog dies. Doc 17: new deviation + open gaps (shared best score/leaderboard across modes; speeds untuned).
files: src/shared/Config.luau, src/server/Lane.luau, src/server/GameServer.server.luau, src/client/MenuClient.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua, selene, luau_check, rojo build pass; Studio MCP: StartRun("Classic") -> held step sank ~3.2 studs/s, reached lava, frog died, lane back to Menu; StartRun() -> Normal, idle step stationary; no console errors. Menu button not clicked or screenshotted.
review: looks-right

## b-20260921-182139-ff3p  closed-by-user  2026-09-21 18:29
note: where's the music from the unity game?
resolved: from dashboard

## b-20260921-182233-97n6  fixed  2026-09-21 18:40
note: i don't need the yellow and green squares to appear when clicking
cause: the squares are the ported Unity TouchIndicator (WorldTouchIndicator.client.luau), drawn at every click/tap and coloured by grab distance.
change: ENABLED = false flag at the top of WorldTouchIndicator; the script exits before creating the indicator or hooking input. Logic kept; flip the flag to restore. Doc 17 row added with the next doc 17 commit.
files: src/client/WorldTouchIndicator.client.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; screenshot confirmed the square is the indicator. Studio not run.
review: n/a

## b-20260921-152818-f5bf  fixed  2026-09-21 18:50
note: the frog's hand when not grabbing, is a little far off the arm (so there's a small gap)
cause: owner ruling b-20260921-182453-9s6z: "it's a hairline. let's try a" (overlap the hand toward the arm). Hand and arm met exactly edge-to-edge, which renders as a hairline seam; the weld keeps the model's authored offset at runtime.
change: RightHand/LeftHand CFrame Y moved 0.0393 studs (~1.5 source px) toward the arm in FrogModel; doc 17 deviation row "Open hand / arm seam".
files: src/assets/FrogModel.model.json, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: JSON parses; rojo build passes. Studio not run.
review: n/a

## b-20260921-182453-9s6z  fixed  2026-09-21 18:50
note: DECISION: it's a hairline. let's try a
cause: owner ruling on b-20260921-152818-f5bf; applied there.
change: see b-20260921-152818-f5bf
files: src/assets/FrogModel.model.json
test: none
verified: see b-20260921-152818-f5bf
review: n/a

## b-20260921-152537-l4vl  fixed  2026-09-21 18:50
note: the frog is holding the carrot on the very end rather than its middle
cause: owner ruling b-20260921-182516-5kv7: "a" (move the grip toward the art's middle). GRIP_CARROT used Unity's literal pivot near the blunt end.
change: GRIP_CARROT moved to the art's geometric middle (canvas ~0.27, 0.37), ~0.7 studs; HIT_OFFSET_CARROT is derived from it and follows. Doc 17 deviation row "Carrot grip point"; stale closed-gap numbers marked superseded.
files: src/shared/StepKinds.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua, selene, luau_check, rojo build pass. Studio not run.
review: n/a

## b-20260921-182516-5kv7  fixed  2026-09-21 18:50
note: DECISION: a
cause: owner ruling on b-20260921-152537-l4vl; applied there.
change: see b-20260921-152537-l4vl
files: src/shared/StepKinds.luau
test: none
verified: see b-20260921-152537-l4vl
review: n/a

## b-20260921-182325-3jtz  fixed  2026-09-21 19:05
note: classic should be the default mode and on classic the steps should slowly get faster and faster
cause: Normal was the default on the menu and in the server fallback, and Classic's speed was a flat per-level constant.
change: menu picker defaults to Classic (cycle Classic -> Normal -> Tutorial); StartRun / Lane.setMode fall back to Classic. Lane.driftElapsed ramps speed as base + base * CLASSIC_SCROLL_ACCEL_RATE (1/120 per s) * elapsed, capped at CLASSIC_SCROLL_MAX_MULT (3x); carries across levels, resets each run. Doc 17 Classic row updated.
files: src/client/MenuClient.client.luau, src/shared/Config.luau, src/server/Lane.luau, src/server/GameServer.server.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua, selene, luau_check, rojo build pass. Studio not run (a play session was live).
review: n/a

## b-20260921-182830-2c73  fixed  2026-09-21 19:05
note: I should be able to pick the tutorial as a game mode
cause: the tutorial was reachable only automatically (new profile) or via Settings > Replay Tutorial.
change: Tutorial added to the menu's mode picker; StartRun("Tutorial") and the ReplayTutorial remote share a new GameServer forceTutorial helper. New players still get the tutorial automatically. Doc 17 Tutorial row updated.
files: src/client/MenuClient.client.luau, src/server/GameServer.server.luau, src/server/Lane.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua, selene, luau_check, rojo build pass. Studio not run (a play session was live).
review: n/a

## b-20260921-183321-iide  fixed  2026-09-21 19:05
note: touch indicator is wanted: in Unity it was a circle and an X, not coloured squares (owner: "green circle and a red x")
cause: the previous fix (a496be8) wrongly disabled the indicator; the real bug was a translucent tinted backing Part rendering as a square, plus a green/yellow/red gradient Unity doesn't have.
change: re-enabled; backing Part always transparent; two states on Config.MAX_GRAB_DISTANCE: green-tinted Circle.png in reach, red "X" TextLabel (styled like WorldQualityPopup's miss X) out of reach. No X sprite exists in Unity's art; follow-up entry filed (aeap: painted X art).
files: src/client/WorldTouchIndicator.client.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; Studio MCP playtest: in-reach click shows the green circle, no square, no console errors. Red X branch not triggerable on screen (whole view within reach); code/type-check only.
review: n/a

## b-20260921-182534-oy7p  fixed  2026-09-21 19:20
note: rocks are still white on the demo (reopens b-20260921-164509-uork)
cause: the main-menu attract ladder (GameServer buildAttract) builds its own WhiteRock Part+Decal and never set Color3; the earlier fix only covered pooled steps in acquireStep.
change: buildAttract tints its rung decals with StepKinds.FallingRock.color (white fallback). No other WhiteRock art path found (flingSplash, BugService decals use other art).
files: src/server/GameServer.server.luau
test: none
verified: stylua, selene, luau_check, rojo build pass. Studio not run (play session live).
review: n/a

## b-20260921-182815-yzh1  fixed  2026-09-21 19:25
note: top scores is not displaying
cause: the Top Scores title label (260 px at x=20) ran under the Close button (x = width-100), so the header read "Top ScorClose"; the score list itself was populating (GetTopScores returned the entry) and the panel already hides/restores the menu and end panels.
change: title narrowed to 170 px and left-aligned. Settings and Store panels checked; not affected.
files: src/client/MenuClient.client.luau
test: none
verified: stylua, selene, luau_check, rojo build pass. Not checked visually in Studio. If the list itself still shows nothing, reopen with a screenshot.
review: n/a

## b-20260921-182207-9efx  cannot-reproduce  2026-09-21 19:40
note: the hand isn't gripping
cause: not reproduced: in a live Studio session, grabs on a plain step and on the carrot (new grip offset) swapped the open hand to the fist every time; a reach that missed a step correctly stays an open hand. The screenshot (open hand between two potato steps, nothing directly under the tap) matches a missed reach.
change: none
files: none
test: none
verified: Studio MCP playtest firing GrabStep; server limb position and Reaching attribute, client RightHand/RightHandGrab transparency checked after each grab and after a miss.
review: n/a

## b-20260921-152729-o03u  fixed  2026-09-21 19:55
note: the roblox leaderboard modal gets in the way of steps. I don't want to move the modal. can we make sure steps don't stop behind it?
cause: owner ruling b-20260921-182502-qgbw: "b" (client-reported PlayerList rectangle + longer pull). Each pull could stop a step anywhere, including under the list.
change: GameClient estimates the PlayerList's lane-relative rectangle (CoreGui enabled + keyboard + Tab toggle; measured 320 px wide, 42 px header + 40 px per player) and sends it over a new rate-limited ScreenObstruction remote; GameServer validates it per lane; Lane.obstructionExtra lengthens a grab pull by at most OBSTRUCTION_MAX_EXTRA_PULL (8 studs) until no step's grab box rests inside it, and Lane.clearSpot keeps new spawns out of it. Off while the lane drifts (Classic). Doc 17 deviation row.
files: src/server/GameServer.server.luau, src/client/GameClient.client.luau, src/server/Lane.luau, src/shared/Config.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua, selene, luau_check, rojo build pass; PlayerList geometry and ScreenPointToRay mapping measured in a live Play session. The longer pull itself not played (session ran old code).
review: concern (y coordinates missing the top-bar inset) -> fixer showed not-a-bug: ScreenPointToRay already works in inset-relative coordinates, same origin as the PlayerList (measured).

## b-20260921-182502-qgbw  fixed  2026-09-21 19:55
note: DECISION: b
cause: owner ruling on b-20260921-152729-o03u; applied there.
change: see b-20260921-152729-o03u
files: see b-20260921-152729-o03u
test: none
verified: see b-20260921-152729-o03u
review: see b-20260921-152729-o03u

## b-20260921-182631-0a8u  fixed  2026-09-21 20:15
note: when changing directions left or right, steps take too long to appear in that direction. there should be some that slide in from the top as scaffold steps towards the new direction
cause: on an arrow grab the port had already pulled and spawned along the old direction, and Lane.changeDirection only swapped spawners, so new-direction steps arrived only on later grabs from off-screen side staging; Unity starts the new spawners immediately.
change: on a real direction change, GameServer.scaffoldLane -> Lane.scaffold places Config.SCAFFOLD_COUNT (3) steps from the arrow's rest point toward the new heading (6.5 studs apart, +1.5 rise when purely sideways), kinds weighted from the new spawners minus arrows, each through clearSpot with up to SCAFFOLD_NUDGE, skipped if occupied, within MAX_GRAB_DISTANCE; slideIn takes an entry direction so they slide down from above. Doc 17 deviation row.
files: src/server/Lane.luau, src/server/GameServer.server.luau, src/shared/Config.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua, selene, luau_check, rojo build pass; Studio MCP: up-left arrow grab on Pot slid 2 of 3 scaffold steps in along the new line (first spot occupied), no console errors. Sideways case (Kitchen/Country) not tested live.
review: looks-right

## b-20260922-073908-mznf  fixed  2026-09-22 07:55
note: DECISION: I'm only ever seeing a circle (answers b-20260921-183648-aeap: keep the text X, but it must actually show)
cause: ruling "I'm only ever seeing a circle" -> the X never appeared because WorldTouchIndicator's in-reach test compared body-to-tap distance against Config.MAX_GRAB_DISTANCE (30 studs, the gamepad snap tolerance), which covers nearly the whole lane, while real mouse/touch grabs succeed only when the tap overlaps a step's hit box.
change: show() now uses overOwnStep(worldPos), mirroring GameClient.stepAt's point-overlap test against this lane's live steps, so the red X shows exactly when a tap misses every grabbable step; removed the unused frog/body lookup.
files: src/client/WorldTouchIndicator.client.luau
test: none
verified: stylua, selene, luau_check pass on the file; no playtest (concurrent fixers).
review: n/a

## b-20260921-183648-aeap  fixed  2026-09-22 07:55
note: TouchIndicator out-of-reach state uses a TextLabel red X glyph, not art
cause: decided via b-20260922-073908-mznf: keep the text X; the reach test was the real bug.
change: see b-20260922-073908-mznf
files: src/client/WorldTouchIndicator.client.luau
test: none
verified: see b-20260922-073908-mznf
review: n/a

## b-20260922-073925-nrd6  fixed  2026-09-22 08:00
note: clean up and pretty up this run over screen
cause: the Run Over panel's Perfect/Great/OK line was one TextWrapped+TextScaled label that wrapped mid-phrase when it didn't fit, leaving an uneven block.
change: replaced it with a row of three fixed-width labels (matches Unity's QualityCountPanel with three separate texts); title "Run over" -> "Run Over". Other panel content and buttons unchanged.
files: src/client/MenuClient.client.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; not screenshotted in Studio (no playtest).
review: n/a

## b-20260922-080448-me55  ignored  2026-09-22 08:10
note: AUTO error (server): StreamOutBehavior is not a valid member of Workspace "Workspace"
cause: raised by an MCP execute_luau probe (trace "AssistantCommand, line 3") during a fixer's playtest; no game code references StreamOutBehavior.
change: none
files: none
test: none
verified: grep of src/, bugloop/, default.project.json finds no StreamOutBehavior
review: n/a

## b-20260922-073847-hju7  unsure  2026-09-22 08:40
note: hands aren't using the grip sprite anymore when grabbing
cause: not reproduced (Sonnet static review, then Opus with ~25 live grabs all showing the grip); probable cause is instance streaming (StreamingEnabled=true, frog ModelStreamingMode=Default): the frog model can arrive before its parts or stream parts out/in, and WorldFrogCosmetics.trackFrog resolves PrimaryPart and the hand/grip decals once, so it stops tracking or toggles stale decals.
change: createFrog sets the frog model to ModelStreamingMode = Persistent before parenting, so the rig replicates whole and never streams out.
files: src/server/GameServer.server.luau
test: none
verified: stylua, selene, luau_check pass; Studio playtest after the change: frog replicates Persistent with PrimaryPart, 4 alternating grabs show the grip. Failure never observed, so fix is unproven. If it recurs, on the client check workspace.PlayField.Frogs.Frog_<id>.RightLimb:GetAttribute("Reaching") vs the decal Transparency.
review: n/a

## b-20260922-081814-xqof  fixed  2026-09-22 09:00
note: free hand lagging behind a moving body shows the grip sprite while holding nothing (held check only measures distance from rest pose)
cause: WorldFrogCosmetics inferred holding from limb-to-rest distance (GrabTarget.limbHeldPosition), so a free limb easing back to rest (LIMB_RETURN_TIME lerp) behind a moving body read as holding.
change: GameServer's frog-render Heartbeat stamps a replicated `Held` attribute on each limb part (true only while snapped to a live step's grip); updateHandGrab reads it to pick open/grip. GrabTarget still drives pupils. Likely also covers b-20260922-073847-hju7's symptom.
files: src/server/GameServer.server.luau, src/client/WorldFrogCosmetics.client.luau
test: none
verified: stylua, selene, luau_check, rojo build pass; Studio playtest on the attract demo frog: held limb Held=true with grip decal shown, free limb Held=false with open hand shown.
review: n/a

## b-20260922-101603-88g2  fixed  2026-09-22 10:45
note: the sparkles in the tutorial should appear in front of the acorns
cause: Specks orbited at the step's own Z plane (zero Z offset), so draw order against the acorn was undefined.
change: Added WorldConfig.SPECK_Z_BIAS = 0.5 and applied it to each speck's position, nudging specks toward the camera without changing their orbit.
files: src/client/WorldTutorialSpecks.client.luau, src/shared/WorldConfig.luau
test: none
verified: stylua --check, selene src/, tools/luau_check.sh on both files pass; not playtested (Studio only)
review: n/a

## b-20260922-101707-218t  fixed  2026-09-22 10:50
note: is the pot background supposed to disappear as I slide to the side?
cause: scrollBackground moved the background tiles by the full pull delta (X and Y) but only re-wrapped them on Y, so sideways pulls let them drift out of view; Unity's Wall.cs wraps both axes.
change: Added X_DRIFT_LIMIT; once the tiles drift past it, scrollBackground snaps both tiles' X back onto the lane origin, keeping the Y wrap unchanged. The Water overlay never scrolls (same as Unity's Overlay.cs), so it needed no change.
files: src/client/WorldBackdrop.client.luau
test: none
verified: stylua --check, selene, tools/luau_check.sh pass; not playtested (Studio only)
review: n/a

## b-20260922-101435-l5k9  fixed  2026-09-22 10:52
note: change game mode names: class=normal; normal=easy;
cause: refreshModeButton showed the internal mode string directly, so the label was always the Config RUN_MODES name.
change: Added a display-only modeDisplayNames map (Classic->Normal, Normal->Easy) used in the mode button label; internal mode strings, the StartRun payload and the server are unchanged.
files: src/client/MenuClient.client.luau
test: none
verified: stylua --check, selene, tools/luau_check.sh pass; not playtested (Studio only)
review: n/a

## b-20260922-101723-tmde  fixed  2026-09-22 10:52
note: when I claim my gift, the run over modal should disappear so I can focus on collecting frogs
cause: giftPromptButton.Activated claimed the gift but never hid the Run Over panel, which covered the burst of catchable flys.
change: On a successful claim, hideMainPanels() runs, then after 3 s restoreMainPanels() brings Replay/Home back (unless the player already left or restarted). This mirrors Unity MenuManager's GiftFlys -> Invoke(ShowReturnPanel, 3f).
files: src/client/MenuClient.client.luau
test: none
verified: stylua --check, selene, tools/luau_check.sh pass; not playtested (Studio only)
review: n/a

## b-20260922-101937-mcaj  fixed  2026-09-22 10:58
note: let's change to the next level at 50 steps
cause: Config.LEVEL_THRESHOLDS was set to 200/500 steps by the earlier design; the owner now wants a new level every 50 steps.
change: LEVEL_THRESHOLDS = { Kitchen = 50, Country = 100 }, read as "every 50 steps", so Country starts at 100. Doc 17's deviation row and doc 13's numbers are updated. Lane reads the table generically, so no logic change was needed.
files: src/shared/Config.luau, docs/roblox-port/17-status-and-known-gaps.md, docs/roblox-port/13-levels-and-lanes.md
test: none
verified: stylua --check, selene, tools/luau_check.sh on Config.luau pass; not playtested
review: n/a

## b-20260922-101449-30jz  fixed  2026-09-22 11:05
note: the tutorial should have the big tree sprite behind the frog from the unity game
cause: The Unity tutorial tree prefabs draw "Branch" (branch3) and "Leaves" (branch2) children behind the Acorn, but the port's StepKinds only carried the Acorn sprite, so the trunk was never ported.
change: New cosmetic client script WorldTutorialTrunk.client.luau keeps a branch3 + branch2 decal pair on every step with Sprite = "Acorn" (only the three tutorial tree kinds). They are sized to the sprites' native canvas (~40 studs) and placed at Z behind the acorn and the frog. Unity's offset for these children isn't in the prefab dumps, so they are centred on the step, as the doc 17 "sprite pivots" row covers.
files: src/client/WorldTutorialTrunk.client.luau
test: none
verified: stylua --check, selene, tools/luau_check.sh, rojo build pass; not playtested (Studio only)
review: n/a

## b-20260922-101541-w1i2  fixed  2026-09-22 11:15
note: in the tutorial, players shouldn't be able to die, they should fall back down to the start. this lasts until they grab one of the first non tutorial (acorn) steps
cause: The no-death fall guard was gated on levelIndex == TUTORIAL, which switches to Pot as soon as the 3rd tutorial tree is grabbed, so a fall before the first Pot grab killed the frog.
change: Added a per-lane tutorialGraceActive flag. It is set for runs that start in the Tutorial and cleared on the first grab of a non-tutorial-tree step, matched through a new KindName step attribute. The fall check now gates on the flag, and tutorialRetry, unchanged, returns the frog to the lane origin.
files: src/server/Lane.luau, src/server/GameServer.server.luau
test: none
verified: stylua --check, selene, tools/luau_check.sh pass; not playtested (Studio only)
review: n/a

## b-20260922-101656-fxqk  closed-by-user  2026-09-22 11:12
note: what are all these yellow things in the background?
cause: Decision (b-20260922-110322-d398): "it's fine". The yellow dots are Unity's own Water overlay (Water.mat) on Pot/Tutorial, rendered faithfully; kept as is.
change: none
files: none
test: none
verified: n/a
review: n/a

## b-20260922-110322-d398  closed-by-user  2026-09-22 11:12
note: DECISION: it's fine
cause: User ruling on b-20260922-101656-fxqk; keep the Water overlay unchanged.
change: none
files: none
test: none
verified: n/a
review: n/a

## b-20260922-145930-pu44  fixed  2026-09-22 15:14
note: Lily Pad Pop: put the Sprites/Menu icons on the menu/store buttons
cause: UIKit.button built a text-only Face/Lip/Label stack with no ImageLabel, so every menu/store button stayed text-only even though the icon ids in SkinAssets were uploaded and non-zero.
change: Added UIKit.setButtonIcon(button, stem?) and an optional iconStem arg to UIKit.button that builds an ImageLabel inside an outline-coloured round halo left of the label (the halo keeps white GearIcon and black Notes visible on matching fills), sized off a new IconSize attribute. Wired the call sites: Frogs/Shop=FrogHeadIcon, Settings=GearIcon, Top Scores=BugIcon, Replay=ReplayIcon, Home=Home, Gift=Present, music=Notes; StoreUI's Action button sets BugIcon only in its "Buy (N)" state.
files: src/client/ui/UIKit.luau, src/client/MenuClient.client.luau, src/client/StoreUI.client.luau
test: none
verified: stylua --check, selene, tools/luau_check.sh on the touched files and rojo build pass; in the live Studio session, execute_luau confirmed each button has an IconHalo>Icon child with the right rbxassetid and that setButtonIcon adds/removes it dynamically. screen_capture returned black (environment limitation), so no visual check.
review: n/a

## b-20260922-145943-ygsg  fixed  2026-09-22 15:16
note: Lily Pad Pop: panels pop in with a 0.35s Back tween instead of appearing instantly
cause: Panels were toggled with plain panel.Visible assignments in MenuClient/StoreUI/GameClient, and UIKit had no helper to drive the design system's pop-in motion.
change: Added UIKit.showPanel(frame, visible), which on show creates or reuses a UIScale, sets Scale = 0.9 and tweens it to 1 over TweenInfo.new(0.35, Back, Out); hiding just clears Visible. Replaced every direct panel.Visible assignment for mainPanel, endPanel, settingsPanel, topPanel, the Store panel (including its toggle flip) and PausePanel with the helper.
files: src/client/ui/UIKit.luau, src/client/MenuClient.client.luau, src/client/StoreUI.client.luau, src/client/GameClient.client.luau
test: none
verified: stylua --check, selene, tools/luau_check.sh on all four touched files and rojo build pass; not checked in Studio (no play session was live).
review: n/a

## b-20260922-145943-f0mc  fixed  2026-09-22 15:22
note: Lily Pad Pop: panels have no drop shadow
cause: UIKit.panel built the panel as one cream Frame, leaving nowhere for a drop to live: under ZIndexBehavior.Sibling a child always draws over its parent and every caller parents content into that Frame, so the button Lip/Face trick did not transfer.
change: UIKit.panel now returns a transparent container at the requested size and position holding a Shadow child (ZIndex 0, outline-coloured, offset down by the new UIKit.PANEL_SHADOW = 8, with a matching UIStroke) which in turn holds the cream Face offset back up by 8. Nesting Face inside Shadow makes the face draw over the drop with no ZIndex tie, while caller widgets at the default ZIndex 1 draw over the whole Shadow subtree; size, position, Visible, re-parenting and showPanel's UIScale all still apply to the container.
files: src/client/ui/UIKit.luau
test: none
verified: stylua --check, selene, tools/luau_check.sh on UIKit and rojo build pass; live in Studio all six panel callers show a transparent container with Shadow(ZIndex 0) > Face, Face matching the container's AbsolutePosition/AbsoluteSize, the shadow 10.8px lower at UIScale 1.35, caller ZIndex overrides intact and showPanel still easing 0.9 -> 1. Console clean; no screenshot (screen_capture returns black in this environment).
review: looks-right — all four caller files parent widgets onto the returned container, never into Face/Shadow, so they sort above the shadow; the only property reads on a panel are ZIndex and Visible, both on the container.

## b-20260922-162201-gcfh  fixed  2026-09-22 16:26
note: get rid of the "pot" title when playing
cause: GameClient rendered a fading level-name HUD toast (doc 15 item 5) on every LevelChanged event, which fires on every run start and respawn rather than once per level; Unity's HUD.cs never showed a level name during play at all.
change: Removed the level-name toast and its now-unused LevelChanged binding from GameClient, leaving a comment that LevelClient still publishes the name on LocalPlayer.LevelState. Doc 15 updated to match.
files: src/client/GameClient.client.luau, docs/roblox-port/15-menus-and-input.md
test: none
verified: stylua --check, selene, tools/luau_check.sh on the touched file and rojo build pass; Studio was in Edit mode, so no in-game check (the fixer did not disturb the session).
review: n/a

## b-20260922-162210-bdsb  fixed  2026-09-22 16:34
note: the music doesn't kick in until the first run is over
cause: LevelClient's LevelChanged listener had no catch-up. Lane.new fires the one-shot "start" LevelChanged during Profiles.Loaded, and when that lands before the LocalScript connects (a real race against the DataStore round trip) the event is dropped, since RemoteEvents do not buffer. Nothing else fires until the run-ending "death" transition, so LevelState's MusicIndex stayed unset and Music.client.luau, whose own catch-up only re-reads LevelState, stayed silent for the whole first run.
change: Added an apply() helper and a one-time bootstrap in LevelClient: when no Transition has been recorded yet it reads the local lane folder's Level attribute (doc 13's discovery contract, which replicates as a normal property rather than a fired event), looks it up in Levels and applies it as a synthetic "start" transition.
files: src/client/LevelClient.client.luau
test: none
verified: stylua --check, selene, tools/luau_check.sh on the touched file and rojo build pass; live in Play Solo, LevelState carries LevelName/MusicIndex/Transition="start" and MusicChannel1 is playing at volume 0.7 with a clean console. The original race could not be forced to reproduce in Play Solo (loopback replication won it both times), so the fix is verified as correct and non-regressing by observation plus the reasoning above, not by reproducing the failure.
review: n/a

## b-20260922-162231-znnk  fixed  2026-09-22 16:40
note: the demo steps should stop on the "gift" screen
cause: GameServer's death beat flips a lane from Dead to Menu on RESPAWN_DELAY alone and refreshAttract then builds the demo ladder, but MenuClient keeps the end-of-run/gift panel up until the player presses Home or Replay and never told the server, so the demo scrolled behind the open panel.
change: Added a SetEndPanelOpen client -> server RemoteEvent (the pattern the existing ScreenObstruction signal uses) fired by MenuClient whenever endPanelDismissed changes; GameServer tracks it per player and refreshAttract now also requires the panel to be closed, tearing the ladder down if it opens while already in Menu.
files: src/server/GameServer.server.luau, src/client/MenuClient.client.luau
test: none
verified: stylua --check, selene, tools/luau_check.sh and rojo build pass; live in Studio the lane held 4 attract rungs at RunState=Menu, firing SetEndPanelOpen true dropped it to 0 and false rebuilt it, console clean. A real death/respawn cycle was not driven end to end, so MenuClient's two call sites are verified by reading, not by play.
review: checked in the orchestrator — the new remote is registered in GameServer's remote list, the handler coerces to a boolean, and the per-player entry is cleared on PlayerRemoving (GameServer.server.luau:1745), so a leaver cannot leave attract suppressed.

## b-20260922-194446-knoi  fixed  2026-09-22 20:05
note: since steps should look like they're falling, can you add a random amount of mostly slow spinning to each step *until* its grabbed
cause: steps spawned and scrolled with a fixed orientation, so nothing in flight ever looked like it was tumbling.
change: `acquireStep` rolls one signed Z spin rate per spawn (Config.STEP_SPIN_MIN_DEG 2 / STEP_SPIN_MAX_DEG 40 with a cubic bias toward slow, random direction) into a server-side `spin` table that the existing Heartbeat step loop applies; cleared on grab (the tilt freezes where it was, never resumes) and on every recycle path. Because a spun step has a tilted local frame, `Falling`'s per-tick drift and `dropAway`'s tween moved from `CFrame * CFrame.new(0, -d, 0)` to world-space `CFrame + Vector3.new(0, -d, 0)`, and `GripOffset` (which is measured in the sprite's frame) is now rotated by the step's CFrame in both the limb-follow loop and the grab-time pull/rest calc.
files: src/server/GameServer.server.luau, src/shared/Config.luau, src/shared/StepBehaviors.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none (no unit suite)
verified: stylua/selene/luau_check/rojo build pass. In a live Studio session 8 steps rotated at 2.0-37.8 deg/s with mixed signs; a grabbed step's Orientation.Z held at -6.423 (delta 0.0000 over 1.5s) while the others kept turning; console clean. The GripOffset rotation was added after that session and is checked statically only -- no carrot was grabbed mid-spin to watch the hand land.
review: concern (sonnet) -- GripOffset was still applied in world axes, so a carrot grabbed mid-spin would snap the hand and the pull target off the art, and PlayerRemoving recycled steps without clearing `spin`. Both fixed in the same commit; the reviewer confirmed the spin table is otherwise cleared on grab and recycle, that attract-mode rungs are correctly unspun, and that Lane's step moves are already world-space.

## b-20260923-154345-9iwk  fixed  2026-09-23 16:05
note: journey 6/8: HUD needs a height meter with level landmarks (Pot -> rim -> Kitchen -> Country)
cause: the HUD only showed score/best, with nothing relating it to the level thresholds.
change: the race rail in GameClient gets a "self" marker (leaderstats.Score, which equals steps climbed this run) and Pot/Kitchen/Country landmark ticks at Config.LEVEL_THRESHOLDS; the rail now shows whenever the run is Playing, solo included. Doc 17 deviation row added.
files: src/client/GameClient.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check, selene src/, tools/luau_check.sh pass on GameClient; not run in Studio (concurrent fixers, no playtest)
review: n/a

## b-20260923-154344-dr8a  fixed  2026-09-23 16:10
note: journey 3/8: split Pot into 3 height stages (step mix and effects change as you climb)
cause: Lane.pickKind used StepKinds' flat level-wide weights and Pot's scenery ran one cadence, so nothing tracked runSteps within the level.
change: optional Levels heightStages (Pot only: 0-15 Carrot-heavy, 15-35 Potato, 35-50 Up*Rock/diagonal) override pickKind weights; Lane replicates the stage as the lane folder's Stage attribute, and WorldScenery scales Bubble/Flame density from it. Doc 17 deviation row added.
files: src/server/Lane.luau, src/shared/Levels.luau, src/client/WorldScenery.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check, selene src/, tools/luau_check.sh on all three, rojo build pass; not run in Studio (concurrent fixers, no playtest)
review: n/a

## b-20260923-154344-o8po  fixed  2026-09-23 16:15
note: journey 5/8: frog should react to heat and to arriving in a new level
cause: WorldFrogCosmetics only reacted to held-step tracking and the Dead attribute; nothing read lava proximity or level-ups.
change: near Pot's lava the pupils glance down and the Body decal tints warm red; on a "soft" level-up the eyes open, pupils look around slowly, then blink (other lanes infer level-ups from their Level attribute). Blink loop gets a guard so the two blinks can't collide; tuning constants in WorldConfig. Doc 17 deviation row added.
files: src/client/WorldFrogCosmetics.client.luau, src/shared/WorldConfig.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check, selene src/, tools/luau_check.sh on both files, rojo build pass; not run in Studio (concurrent fixers, no playtest)
review: n/a

## b-20260923-154345-g9ea  fixed  2026-09-23 16:35
note: journey 7/8: arriving in Kitchen is a difficulty spike; ease the first few steps
cause: Kitchen spawners drew from the full pool at once and Lane.driftSpeed read the level's CLASSIC_SCROLL_SPEED directly, so step mix and scroll speed both jumped at the threshold.
change: optional Levels introSequence (Kitchen: Shelf, Shelf, RightRock) handed out by Lane.pickKind before the weighted pick; Lane.driftBase ramps to the new level's speed over Config.CLASSIC_LEVEL_RAMP_TIME (6 s). Doc 17 deviation row added.
files: src/server/Lane.luau, src/shared/Levels.luau, src/shared/Config.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check, selene src/, tools/luau_check.sh on Levels/Config/Lane/GameServer, rojo build pass; not run in Studio (concurrent fixers, no playtest)
review: n/a

## b-20260923-154344-xac3  fixed  2026-09-23 16:40
note: journey 4/8: Pot heat should build when the lava is close or the frog stands still
cause: setHeat only tweened the lava between two fixed per-level colours; nothing tied the overlay or backdrop to lava proximity or idle time.
change: WorldLava publishes a smoothed PotHeat (lava proximity + time since last grab, Pot only) on LocalPlayer.LevelState; WorldBackdrop raises Water overlay opacity and warms the backdrop with it outside transition tweens; constants in WorldConfig. Doc 17 deviation row added.
files: src/client/WorldLava.client.luau, src/client/WorldBackdrop.client.luau, src/shared/WorldConfig.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check, selene src/, tools/luau_check.sh on all three, rojo build pass; not run in Studio (no playtest)
review: n/a

## b-20260923-154343-3h60  fixed  2026-09-23 17:00
note: journey 2/8: Pot->Kitchen arrival should be a short scene, not a silent crossfade
cause: a soft level-up only swapped level data and let clients crossfade quietly; no beat was tied to a real level-up.
change: Lane.levelUp/beginArrival holds Classic drift 1.5 s (then the fe6ae69 ramp) and bumps a replicated ArrivalCount; clients pull the camera back (GameClient), play the "new" sting and delay the music crossfade 0.8 s (Music), and fade leftover scenery (WorldScenery). Tutorial->Pot included; not on start/respawn. Doc 17 deviation row added.
files: src/server/Lane.luau, src/shared/Config.luau, src/shared/WorldConfig.luau, src/client/GameClient.client.luau, src/client/Music.client.luau, src/client/WorldScenery.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check, selene src/, tools/luau_check.sh on all six, rojo build pass; not run in Studio, so timing and feel are unconfirmed
review: looks-right

## b-20260928-173905-b7sx  fixed  2026-09-28 18:05
note: DECISION: use ludo (answers b-20260923-154345-78ng: ambient sound should change with height, bubbling in Pot, kitchen room sound)
cause: no ambient layer or clips existed (Unity has none); ruling "use ludo".
change: Ludo-generated potBubbling (90151979006382) and kitchenRoomTone (122330171841881) loops in Sounds/Ambience, uploaded via tools/ and written to SoundAssets; build_manifest.py gained collect_ambience(); Ambience.client.luau crossfades 1.5 s on LevelName, Pot volume by lane Stage, muted by SfxOn; doc 17 row.
files: src/client/Ambience.client.luau, src/shared/SoundAssets.luau, tools/build_manifest.py, Sounds/Ambience/PotBubbling.wav, Sounds/Ambience/KitchenRoomTone.wav, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check, selene src/, tools/luau_check.sh, rojo build pass; upload/moderation confirmed via upload_to_roblox --status; not run in Studio (committed on branch bugloop/ludo-assets, not the synced checkout)
review: looks-right

## b-20260928-173934-iff0  fixed  2026-09-28 18:40
note: DECISION: use ludo to match the style of the existing sprites (answers b-20260923-154343-9twj: climbing out over the pot rim should BE the Pot->Kitchen transition)
cause: the Pot->Kitchen level-up fired silently at the threshold; no rim landmark or art existed.
change: Ludo-generated PotRim sprite (Sprites/Rocks/PotRim.png, id 140153915656484 in SkinAssets); new non-spinning StepKinds.PotRim; at 50 Pot run steps spawning stops and Lane.spawnRim (from GameServer Heartbeat) lays the rim above the highest live step; grabbing it is the levelUp + arrival beat (now the 51st grab), then Kitchen spawners fill above it; doc 17 rows added/updated.
files: Sprites/Rocks/PotRim.png, src/shared/SkinAssets.luau, src/shared/StepKinds.luau, src/shared/Config.luau, src/server/Lane.luau, src/server/GameServer.server.luau, docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: stylua --check, selene src/, tools/luau_check.sh on touched files, rojo build pass; not run in Studio (committed on branch bugloop/pot-rim, not the synced checkout)
review: looks-right

## b-20260923-154343-9twj  fixed  2026-09-28 19:05
note: journey 1/8: pot rim landmark: climbing out over the rim should BE the Pot->Kitchen transition
cause: answered by the DECISION b-20260928-173934-iff0 ("use ludo to match the style of the existing sprites"); the question block had left needs-decision.md but this id was never recorded, so it stayed pending.
change: built under b-20260928-173934-iff0 (commit 94e589f): PotRim sprite + StepKinds.PotRim, Lane.spawnRim at the Pot threshold, grabbing the rim is the level-up; doc 17 rows.
files: see b-20260928-173934-iff0
test: none
verified: see b-20260928-173934-iff0 (static checks pass; not run in Studio)
review: n/a

## b-20260923-154345-78ng  fixed  2026-09-28 19:05
note: journey 8/8: ambient sound should change with height (bubbling in Pot, kitchen room sound)
cause: answered by the DECISION b-20260928-173905-b7sx ("use ludo"); the question block had left needs-decision.md but this id was never recorded, so it stayed pending.
change: built under b-20260928-173905-b7sx (commit 4ccfced): Ludo potBubbling / kitchenRoomTone loops, Ambience.client.luau crossfade by level with Pot volume by stage; doc 17 row.
files: see b-20260928-173905-b7sx
test: none
verified: see b-20260928-173905-b7sx (static checks pass; not run in Studio)
review: n/a

## b-20261001-141720-tfkt  fixed  2026-10-01 14:26
note: make sure carrots have very generous touch areas for grabbing on to
cause: The carrot tap test used only Unity's small Collider2D (~6.5x4.5 studs), so taps near but outside it missed.
change: Carrot-only StepKinds `tapSize` (13x10 studs, same centre as hitSize/hitOffset), looked up via the KindName attribute in GameClient.stepAt and WorldTouchIndicator.overOwnStep; a tap inside any real collider beats a pad-only tap, nearest centre breaks ties. hitSize (spawn spacing) and server GrabStep unchanged. Doc 17 deviation row "Carrot tap area".
files: src/shared/StepKinds.luau, src/client/GameClient.client.luau, src/client/WorldTouchIndicator.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check (touched files), selene src/, luau_check.sh on each touched file, rojo build pass
verified: no — not playtested; needs a Studio play tapping a few studs outside the carrot art (should grab) and next to a carrot beside another step (should grab the nearer real collider). Pad-edge taps may grade as weaker grab quality (PullMath.gradeGrab uses tapPos).
review: looks-right; checked: git diff of the 3 files, KindName set in GameServer.acquireStep, tier logic, bug-catch priority, server GrabStep has no tap hit-test, luau_check on all 3 files exit 0

## b-20261001-145112-o2jb  fixed  2026-10-01 14:52
note: make sure all frogs have proper thumbnails in the store
cause: StoreUI used Thumbnail, then SkinAssets.part(name,"Head"), which falls back to Hot Frog's head, so Space Frog (no Thumbnail, no Head art) showed Hot Frog's face; Blue and Mystery Frog have no Thumbnail and show their own Head.
change: StoreUI thumbnail now resolves the skin's own Thumbnail -> own Head -> own Body -> tinted placeholder, never another skin's art (Space Frog shows its own Body). Dedicated thumbnails for Blue/Space/Mystery not drawn; existing doc 17 gap row still applies.
files: src/client/StoreUI.client.luau
test: stylua --check, selene src/, luau_check.sh StoreUI.client.luau, rojo build pass
verified: no — needs the store opened in Studio, paging to Space Frog (should show its body, not Hot Frog's head)
review: n/a
owed: draw dedicated Blue/Space/Mystery Frog thumbnails, upload as <Skin>Thumbnail, then rewrite ids

## b-20261001-145037-iaa4  fixed  2026-10-01 14:56
note: DECISION: b (reopens b-20261001-141733-kb4c "when in portrait view, the steps are often only on the sides of the screen and not any down the middle")
cause: owner ruling "b" (rescale straight-down sweeps to fit the portrait view). clampToLane clamped each Unity Movements X to ±SPAWN_VIEW_HALF_WIDTH (8.84); most of Unity's sweep points lie outside it, so steps piled on x=+8.84 or in one column.
change: Lane.clampToLane takes the spawner def; for spawners with no X direction component, viewX maps the def's Movements min..max X linearly onto ±(8.84 − m), m = half the widest hitSize.X in its pool (Pot ±5.4, Kitchen/Country ±5.2, Tutorial trees ±4.8), cached per def; min==max -> x=0. Diagonal/sideways spawners unchanged. Doc 17 "Straight-down spawn X" deviation row; older clamp rows corrected.
files: src/server/Lane.luau, docs/roblox-port/17-status-and-known-gaps.md
test: Edit-mode sim (Studio MCP, real Lane module, 20 runs x 50 grabs/level, dir (0,-1), 9:16): edge share Pot 46%->0%, Kitchen 61%->0%, Country 58%->0%; |x|<3 16-32% -> 34-37%; 0/1000 grabs with no step ahead before and after; Pot ~25% fewer visible steps (clearSpot). stylua, selene, luau_check, rojo build pass.
verified: no — needs a Studio play at 9:16 through Pot, Kitchen and Country checking vertical-phase steps spread across the screen and none cut off at the edges
review: looks-right; checked: git diff Lane.luau + doc 17, both clampToLane callers pass state.def, sign-only direction test, per-def cache, hitSize guard, scenery spawners not routed, luau_check exit 0 (stale "Tutorial trees x ≈ ±8.8" in doc 17 Camera aspect row fixed by orchestrator)

## b-20261001-141733-kb4c  fixed  2026-10-01 14:57
note: when in portrait view, the steps are often only on the sides of the screen and not any down the middle
cause: answered by owner ruling b-20261001-145037-iaa4 ("b": rescale straight-down sweeps into the portrait view); see that block.
change: applied in b-20261001-145037-iaa4 (Lane.clampToLane viewX rescale).
files: src/server/Lane.luau, docs/roblox-port/17-status-and-known-gaps.md
test: see b-20261001-145037-iaa4
verified: no — needs a Studio play at 9:16 (see b-20261001-145037-iaa4)
review: looks-right; checked: see b-20261001-145037-iaa4

## b-20261001-145155-yes7  fixed  2026-10-01 15:06
note: the store should replace your current frog with big arrows on the screen, not just be a small modal (like the unity game) and going back makes that frog drop down and your frog bounce up if you haven't purchased that frog
cause: The port's store was a small centred thumbnail modal; Unity's (FrogPackages.MakeFrog / MenuManager ArrowPanel) swaps the frog on the play field with big arrows and lowers an unowned frog on Back so the owned one rises.
change: StoreUI is a full-screen overlay (big </> arrows, name/status top, Buy/Wear low centre, Back bottom centre) previewing a local-only FrogModel clone skinned via SpriteSkin.apply, parked on the real frog (hidden locally via LocalTransparencyModifier); each arrow raises the next frog from Unity's endY over 1 s; Back equips an owned frog (SelectSkin) or drops the unowned one and bounces the equipped frog back up; run start closes the store and cancels any in-flight Back animation. Doc 17 deviation row added; the thumbnail gap row dropped (thumbnails no longer read anywhere).
files: src/client/StoreUI.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check, selene src/, luau_check.sh StoreUI.client.luau, rojo build pass
verified: Studio MCP playtest (fixer): opened store, paged to unowned Hawt Frog ("Locked — 1000 Flys"), per-frame Y trace of rise (-21.8 -> 0 over ~1 s), Back drop then equipped frog bounce (overshoot 3.1, settle 0), real frog unhidden, no previews left; Back on selected frog; repair: Play 200 ms into Back drop -> RunState Playing, no clones, real frog visible; no console errors
review: concern: starting a run during Back's ~2 s animation left the preview visible and the real frog hidden (closeStore(false) returned early once storeOpen was false); checked: git diff of StoreUI + doc 17, MenuClient hookups, SkinService SelectSkin, grep LocalTransparencyModifier/Thumbnail, luau_check
re-review: looks-right; checked: StoreUI lines 137-200 and 285-435, token checks at both tween yields, closeStore(false) callers (RunStateChanged only), luau_check exit 0

## b-20261001-150712-8jsz  fixed  2026-10-01 15:14
note: make sure the frog bounces up playfully on the start screen
cause: Nothing animated the frog when the Menu run state began; it just sat in place on join and after returning from death.
change: StoreUI bounceIn() on RunStateChanged "Menu" (skipped while the store is open) hides the real frog locally and raises a local FrogModel clone of the equipped skin from Unity's endY with the store's Back/Out BOUNCE_INFO tween and the "awake" sound; run start (closeStore(false)) and opening the store cancel it via closeToken. A one-shot startup check reads the lane's RunState attribute so the bounce also plays on first join (sawRunState guards a double fire).
files: src/client/StoreUI.client.luau
test: stylua --check, selene src/, luau_check.sh StoreUI.client.luau, rojo build pass
verified: no — not run in Studio; join and watch the frog bounce on the start screen, die and return to Menu, press Play and Shop mid-bounce
review: concern: the initial join Menu event fires before StoreUI connects, so the join bounce would be missed; checked: git diff StoreUI, StoreUI preview/open/close/RunStateChanged code, GameServer initPlayer/setRunState, MenuClient handler, luau_check exit 0
re-review: looks-right; checked: git diff StoreUI startup check + handler, bounceIn dependencies all defined earlier, SetAttribute("RunState") at GameServer:173 with Menu/Playing/Dead, luau_check exit 0 (narrow race can replay the awake sound once)

## b-20261008-124136-b89y  answered  2026-10-08 12:46
note: what else is left for this game to be a fun popcorn level experience worth playing every day?
finding: The core loop is solid: grab grading and popups, dynamic steps, a level-up beat, the race rail, quick Replay, Flys and skins, and a gift. What is missing is mostly the daily-return layer. First come the ship blockers only you can do: every badge, Game Pass and Fly product id is still 0 (so badges, premium skins and Fly packs do nothing), there is no icon or thumbnails, and most fixes have never been playtested. The biggest code gaps, in order: (1) a daily or weekly leaderboard, since the only board is the all-time top 10; (2) a daily login streak, since the gift is a flat cooldown that grows to 6 h and is never streak-based; (3) Perfect-combo juice, since there is no chain counter, camera punch or haptics. After those come long-tail badges (all 10 are earned in the first 100 steps), a Fly sink once the skin set is bought, and daily missions. Full ranked list in the report.
evidence: src/shared/Badges.luau (all id=0); src/shared/SkinCatalog.luau:17-24; src/server/SkinService.server.luau:20 (empty FLY_PRODUCTS); src/server/GiftService.server.luau:15-16,69,94; src/server/Profiles.luau:51,313 (single all-time OrderedDataStore); docs/roblox-port/17-status-and-known-gaps.md
report: .bugs/reports/b-20261008-124136-b89y.md
files: none
review: holds; checked: read the report, Badges.luau ids, SkinCatalog.luau:21-24 gamePassIds, SkinService FLY_PRODUCTS, Profiles.luau OrderedDataStore + topScores, GiftService clamp/seed logic; grepped src for streak/combo/CameraShake/HapticService/daily/weekly (none); icon/playtest claims not checkable from code
followups: b-20261008-124506-tmdz, b-20261008-124506-lo4a, b-20261008-124506-kx46 (filed held in backlog)

## b-20261008-141608-z239  closed-by-user  2026-10-08 14:17
note: add a daily and weekly leaderboard that shows after every run. ideally players would see their friends highlighted and then others globally would be filled in any leftover spaces
resolved: from dashboard

## b-20261008-141620-0ch8  closed-by-user  2026-10-08 14:17
note: add a daily login streak reward with big juicy graphics
resolved: from dashboard

## b-20261008-141637-3p3w  closed-by-user  2026-10-08 14:17
note: add perfect-combo juice with a chain counter, camera punch, and haptics
resolved: from dashboard

## b-20261008-141652-rdl8  answered  2026-10-08 14:22
note: brainstorm some fly sinks once the skin set is bought
finding: The four Fly skins cost 5000 Flys in total. Bugs pay about 50-100 Flys per 60 s run (estimated; the ceiling is about 235/min) and the gift is 100 Flys on a cooldown that settles at 6 h, so the set is done after about 1-1.5 h of play, and after that a player banks about 75 Flys per run with nothing to spend them on. Build these first: (1) a Fly Jar, where you feed in Flys with no limit to earn titles shown on the race rail at 1k/2.5k/5k/10k/25k+ (no balance risk); (2) skin colourways, 3-4 tints per skin at 400/600/800, with Gold at 1500 (about 16-25k Flys of content, no new art); (3) a Second Chance continue at 150, then 300, at most twice per run, once you decide whether continued runs count on the leaderboards. Players can also catch bugs on the menu without playing, at up to about 235/min, which makes run-priced sinks cheap; capping that is your call (doc 17 rules menu bugs deliberate).
evidence: src/shared/SkinCatalog.luau, src/server/SkinService.server.luau:19-22,43-54, src/server/GiftService.server.luau:13-16,69,94, src/server/BugService.server.luau:360-372,503-537, src/shared/Config.luau:380-419, src/server/Profiles.luau:31-42
report: .bugs/reports/b-20261008-141652-rdl8.md
files: none
review: holds; checked: SkinCatalog prices sum 500+1000+1500+2000=5000, GIFT_FLYS=100 and the clamp reaching 21600 s at seed 10, BUG_FLYS=5 with golden 25 at 6%, spawn every 2 s with 12% swarms (~41 bugs/min, ~235 Flys/min), BugService spawn loop not gated on RunState (menu catching); per-run figure is an estimate
followups: b-20261008-142124-qw4r, b-20261008-142125-1ucz, b-20261008-142125-cxm0 (filed held in backlog; release the ones you want built)

## b-20261008-124506-kx46  fixed  2026-10-08 14:31
note: Add a Perfect-chain combo counter with escalating SFX pitch, a small camera punch and mobile haptics (WorldQualityPopup, GameClient, SfxEvents, Config)
cause: Nothing tracked consecutive Perfect grabs, so there was no chain counter, pitch escalation, camera punch or haptics.
change: GameClient, SfxEvents and WorldQualityPopup each count Perfects from ScoreChanged.quality, and a non-Perfect grab, GameOver or RunStateChanged resets the count. The popup reads "Perfect xN" from 2, the Perfect voice pitches 1+0.06(N-1) up to 1.5 (new optional pitch arg on SoundFX.play), the camera dollies in 2% per link (max 6%), and HapticService pulses on Touch/Gamepad1. Knobs are Config.PERFECT_CHAIN_*; doc 17 has a row.
files: src/shared/Config.luau, src/shared/SoundFX.luau, src/client/GameClient.client.luau, src/client/SfxEvents.client.luau, src/client/WorldQualityPopup.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check on touched files, selene src/ (0 warnings), tools/luau_check.sh on touched files (clean), rojo build (ok)
verified: no — the HotFrog place is not open in Studio (the Studio MCP lists only Centralia and Tactics.rbxl), so no playtest ran; static checks only
review: looks-right; checked: git diff of the 5 src files, luau_check clean, GameServer ScoreChanged/GameOver/RunStateChanged all FireClient(player) so other lanes can't bump the chain, the three scripts' reset paths agree, updateCamera stays the only CFrame writer, pitch applies only to the cloned Perfect shot, haptic motor is zeroed after each pulse

## b-20261008-124506-lo4a  fixed  2026-10-08 14:32
note: Add a daily login streak with escalating Fly rewards shown on the main menu (Profiles.luau, GiftService or a new DailyService, MenuClient)
cause: There was no daily login streak; the only free Flys came from GiftService's flat escalating-cooldown gift.
change: New DailyService with a ClaimDailyReward RemoteFunction: one claim per UTC day, a next-day claim extends profile.streak, a missed day resets it to 1, 7-day cycle 25/50/75/100/150/200/500 Flys paid via ServerStorage/AwardFlys. MenuClient claims each time the menu shows; a grant opens a full-screen popup (sunburst, day tiles, count-up, confetti, Collect), and a "Day N streak! Tomorrow: +X Flys" line sits under the main panel. Profiles gains streak/streakDay (the save merge keeps the newer claim day); doc 17 has a row.
files: src/server/DailyService.server.luau, src/server/Profiles.luau, src/server/GameServer.server.luau, src/client/MenuClient.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check on touched files, selene src/ (0 warnings), tools/luau_check.sh on the 4 Luau files (clean), rojo build (ok)
verified: no — the HotFrog place is not open in Studio (the Studio MCP lists only Centralia and Tactics.rbxl), so no playtest ran; static checks only
review: looks-right; checked: git diff of Profiles/GameServer/MenuClient, DailyService read in full, doc 17 row, luau_check clean; no yield between the streakDay check and the set (no double claim), nil profile handled with client retry, UTC day math and the client's Tomorrow calc match REWARDS, mergeForSave keeps the newer streakDay, invoke takes no args, popup only on grant and destroyed on Collect. Minor: if the profile load fails, the unsaved default can repay each session

## b-20261008-141644-lzg7  fixed  2026-10-08 14:50
note: add long-tail badges
cause: All 10 badges were single-run step thresholds of 100 or less, so nothing was left to earn after the first 100 steps.
change: Badges.luau entries take an optional kind ("steps", "level", "streak") plus level; BadgeService watches the lane Level attribute and polls Profiles.get(p).streak read-only every 20 s. New badges (id 0 until created): 150/200/300/500 Steps!, Out of the Pot (reach Kitchen), Country Frog (reach Country), 3/7/30-Day Streak. Perfect-chain and golden-bug badges were skipped: the chain is client-only and BugCaughtServer carries no golden flag.
files: src/shared/Badges.luau, src/server/BadgeService.server.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check on touched files, selene src/ (0 warnings), tools/luau_check.sh (clean), rojo build (ok)
verified: no — the HotFrog place is not open in Studio, and every badge id is 0 (skipped) until created; static checks only
review: looks-right; checked: git diff of both files, luau_check clean, kindless rows keep the old threshold path, Lane.luau:314 sets Level to level.name matching LEVEL_RANK Pot/Kitchen/Country, Kitchen 50 / Country 100 reachable and no run cap found (300/500 practicality is tuning), streak poll nil-checks the profile, lane ChildAdded plus an existing-folder scan
owed: create the 19 badges in Creator Hub and paste their ids into src/shared/Badges.luau (see .bugs/owed.md)

## b-20261008-124506-tmdz  fixed  2026-10-08 14:58
note: Add a daily (and optionally weekly) leaderboard: day-keyed OrderedDataStore in Profiles.luau plus tabs in the Top Scores panel
cause: The only board was the all-time top 10 (HotfrogGlobalBest_v1 / Profiles.topScores): no daily or weekly boards, no tabs, no way to open it from the Dead screen, no friend highlighting.
change: Profiles.recordPeriodScore runs after every run (from commitHighScore) and UpdateAsync-maxes per-period OrderedDataStores HotfrogDailyBest_v1_d<day> and HotfrogWeeklyBest_v1_w<week> (UTC day, Monday-aligned week), writing only when the run beats this session's period best. GetTopScores(period) serves daily/weekly/all with a 60 s cache per board. MenuClient's Top Scores panel has Today / Week / All-time tabs (opens on Today), a new Top Scores button on the end-of-run panel, and highlights your row and friends in the top 10 ("(you)" / "(friend)"); the board is not filled friends-first.
files: src/server/Profiles.luau, src/server/GameServer.server.luau, src/client/MenuClient.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check on touched files, selene src/ (0 warnings), tools/luau_check.sh (clean), rojo build (ok)
verified: no — the HotFrog place is not open in Studio (the Studio MCP lists only Centralia and Tactics.rbxl); static checks only
review: looks-right; checked: git diff of the 3 files and the doc 17 row, luau_check clean, the recordPeriodScore spawn sits outside the new-best branch so it runs on every death (GameServer:1372), writeMax handles a nil old value, the week formula is Monday-aligned (epoch day 4 -> week 1), periodBest resets on index change, any unknown period string falls back to "all", IsFriendsWith is pcall'd and cached. Nits: the period best is set before the write succeeds; concurrent stale-cache reads can double-fetch (as before)

## b-20261008-142458-vo87  fixed  2026-10-08 15:05
note: extend out the existing frog skin rewards so a player earns one after 2 runs, then 5 more runs, then 10 runs, etc
cause: Decision (b-20261008-143831-k4ys): "skins should be unlocked with flys and/or robux. when I was talking about the runs to unlock, I meant by setting fly prices". The catalog still had Unity's 500/1000/1500/2000 Fly prices, and the four premium skins could only be bought with Robux.
change: Every non-free skin now has a flyCost on a run ladder, assuming about 50 Flys per typical run. The run gaps are 2, 5, 10, 20, 30, 45, 60 and 80, and the prices are Blue 100, Hawt 250, Space 500, Mystery 1000, Business 1500, Hot Lawyer 2250, Invisible Man 3000, Crossy 4000. The premium skins keep gamePassId. StoreUI shows "Buy with Robux" next to the Flys buy when a skin has a real Game Pass id. Doc 17 has a row recording the prices.
files: src/shared/SkinCatalog.luau, src/client/StoreUI.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check, selene src/, tools/luau_check.sh on both files, rojo build (all pass)
verified: no — the HotFrog place is not open in Studio (only Centralia and Tactics are), so only static checks ran.
review: looks-right; checked: git diff of the 3 files, SkinService BuyWithFlys and the Game Pass grant paths, a grep for gamePassId/flyCost, StoreUI states (free/fly-only/both/owned) and button layout, the Flys/run estimate against Config and BugService, luau_check on StoreUI
owed: Create the 4 skin Game Passes and set their gamePassId in SkinCatalog.luau (o- block in owed.md)

## b-20261008-143831-k4ys  answer  2026-10-08 15:05
note: DECISION: skins should be unlocked with flys and/or robux. when I was talking about the runs to unlock, I meant by setting fly prices
cause: The user's ruling on b-20261008-142458-vo87.
change: see b-20261008-142458-vo87
files: none
test: none
verified: no — the ruling is applied and recorded under vo87
review: n/a

## b-20261008-143855-nuf1  answered  2026-10-08 15:15
note: can you do this through open cloud with the right permissions? (sent back from owed step o-20261008-143616-fzdz for b-20261008-141644-lzg7: create the 19 HotFrog badges)
finding: Yes. tools/create_badges.py creates all 19 badges through Open Cloud and writes their ids into src/shared/Badges.luau. It only spends nothing: every create sends expectedCost 0, and the run stops at the first refusal. Your current API key lacks the badge scope (the create returned 403 "Scope not authorized"), so 0 of 19 exist yet. Add "legacy-universe.badge" (Read, Write, manage-and-spend-robux) to the key, then press Run it on the owed step. Roblox caps free badge creation per day, so it may take more than one day's run.
cause: Badge creation had only a manual Creator Hub path, and the .env API key has no legacy-universe.badge scope.
change: Added tools/create_badges.py. It is resumable: it reuses badges that already exist by name (paged GET, aborting if the listing fails), creates the rest at expectedCost 0, stops on the first refusal or network error, caches ids in the gitignored tools/badge_ids.json, and writes ids into Badges.luau with LF line endings. It is documented in tools/README.md.
files: tools/create_badges.py, tools/README.md, .gitignore
test: python tools/create_badges.py --dry-run (19 would-create, 0/19 have ids); stylua/luau_check on Badges.luau (unchanged)
verified: partly — the real Open Cloud run made the paged GET (200, no badges) and the POST create (403 Scope not authorized), so no badge was created and the id write path has not run against a real id.
review: concern: there was no try/except around the requests calls, a failed listing GET was ignored, and Badges.luau was written with CRLF; checked: git diff of README/.gitignore, read create_badges.py, ran --dry-run, compared git status
re-review: concern: --dry-run still writes the gitignored cache file tools/badge_ids.json as "{}" (harmless; the three repairs are correct); checked: read create_badges.py in full, ran --dry-run with git status before and after, grep for CR in Badges.luau
owed: Add the legacy-universe.badge scope to the API key, then run python tools/create_badges.py (o- block in owed.md)

## b-20261008-145031-uwm3  answered  2026-10-08 15:35
note: can you do this with roblox open cloud? (sent back from owed step o-20261008-144708-cka8 for b-20261008-142458-vo87: create Game Passes for the 4 premium skins)
finding: Yes. tools/create_gamepasses.py creates the 4 skin Game Passes through Open Cloud (Business Frog 99, Hot Lawyer 149, Invisible Man 199, Crossy Frog 249 Robux; change PRICES at the top of the script) and writes their ids into src/shared/SkinCatalog.luau. Your API key has no Game Passes scope yet, so it got 403 "Scope not authorized" and created nothing. Add the Game Passes API system (read and write) for HotFrog to the key, then press Run it on the owed step.
cause: Game Passes could only be made by hand, and the .env API key lacks the Game Passes scope.
change: Added tools/create_gamepasses.py, modelled on create_badges.py. It lists passes first and aborts before creating anything if the listing fails, reuses passes by name, guards each create and its response parse, caches ids in the gitignored tools/gamepass_ids.json (never on --dry-run), and rewrites only those 4 rows' gamePassId with LF line endings. Documented in tools/README.md.
files: tools/create_gamepasses.py, tools/README.md, .gitignore
test: py_compile; --dry-run against the live API (403, exit 2, no files touched)
verified: partly — the real Open Cloud list call returned 403 Scope not authorized; the create path and id write have not run against a real pass
review: concern: a successful create whose JSON lacks gamePassId/id (or doesn't parse) crashed before the catalog rewrite, and --dry-run wrote the cache; checked: read create_gamepasses.py and create_badges.py, regex against SkinCatalog rows, git diff of README/.gitignore, ran --dry-run with git status and the SkinCatalog sha1 before and after
re-review: looks-right; checked: read the script in full, py_compile, --dry-run (403 abort before any create), git status diff before/after, no cache file created
owed: Add the Game Passes scope to the API key, then run python tools/create_gamepasses.py (o- block in owed.md)

## b-20261008-141702-e0za  fixed  2026-10-08 15:50
note: add rotating daily missions
cause: The game had no daily missions; it only had the daily login streak and the gift.
change: New MissionService picks 3 missions per UTC day from an 8-mission pool, seeded by the day so every player gets the same set: climb 30 / 75 in one run (30 / 60 Flys), catch 5 / 15 bugs (30 / 60), play 3 / 8 runs (25 / 50), reach Kitchen (40), reach Country (75). Progress is stored in Profiles (missionDay + missions; the save merge keeps the newer day and the higher count). A finished mission pays automatically through AwardFlys and fires MissionCompleted, and the menu shows 3 progress lines plus a 3 s toast. Run-score missions only count runs that started today. Doc 17 has a row for it.
files: src/server/MissionService.server.luau, src/server/Profiles.luau, src/server/GameServer.server.luau, src/client/MenuClient.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check, selene src/, tools/luau_check.sh per file, rojo build (all pass)
verified: no — the HotFrog place is not open in Studio (only Tactics.rbxl and Centralia are), so only static checks ran.
review: concern: a run straddling midnight UTC credited its pre-midnight steps to the new day's "climb N in one run" mission; checked: git diff of Profiles/GameServer/MenuClient/doc 17, read MissionService in full, cross-read BadgeService, BugService, the GameServer sessionScore/leaderstats code and Profiles mergeForSave, luau_check
re-review: looks-right; checked: read MissionService in full and GameServer setRunState/StartRun/leaderstats, luau_check and stylua (rc 0); noted that a lane already Playing when the service attaches gets no credit for that one run (fails safe)

## b-20261008-142124-qw4r  fixed  2026-10-08 15:20
note: Add a Fly Jar where Flys are fed in for good, unlocking tier titles (1k-100k) on the race rail and Top Scores plus tier badges (Profiles jarFlys, FeedJar remote in SkinService, GameClient rail, MenuClient)
cause: Nothing existed for this yet: no jarFlys counter, no FeedJar remote, no tier titles or jar badges, and the race rail did not name players.
change: Profiles gains jarFlys, and the save merge keeps the higher value. The new FeedJar RemoteFunction in SkinService accepts only a positive whole amount up to the balance, moves it from flys to jarFlys, saves, and sets a replicated JarTitle player attribute. Tiers live in the new shared JarTiers module: 1k Fly Snacker, 2.5k Fly Keeper, 5k Swarm Tender, 10k Jar Master, 25k Fly Baron, 50k Lord of the Flies, 100k Frog Royalty. Each tier has a matching kind="jar" badge row, id 0 until tools/create_badges.py runs, which BadgeService awards. The race rail shows names and titles. Top Scores shows titles only for players in the same server. The menu has a new Fly Jar panel with +100, +1000 and All buttons. FeedJar is added to GameServer's remote list, and doc 17 has a row.
files: src/shared/JarTiers.luau, src/shared/Badges.luau, src/server/Profiles.luau, src/server/SkinService.server.luau, src/server/BadgeService.server.luau, src/server/GameServer.server.luau, src/client/GameClient.client.luau, src/client/MenuClient.client.luau, tools/create_badges.py, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check on the touched files (clean), selene src/ (0 warnings), tools/luau_check.sh on the touched files (clean), rojo build (ok)
verified: no — the HotFrog place is not open in Studio (the Studio MCP lists only Centralia and Tactics.rbxl), so no playtest ran; static checks only
review: looks-right; checked: full diff of the 9 files plus JarTiers.luau, SkinService AwardFlys/BuyWithFlys/initPlayer, Profiles mergeForSave (flys is written as-is, so spent Flys are not resurrected; jarFlys takes the max), FeedJar rejects NaN, inf, fractions and non-positive amounts, and has no yield between the check and the deduct; badge thresholds match JarTiers; luau_check and selene clean
owed: none
note: the new jar badges are created by the existing badge-scope step o-20261008-144823-fg29

## b-20261008-150752-kf7u  answered  2026-10-08 15:24
note: api key has been added. use studio to add the api system and save. then I will press run it (sent back from owed step o-20261008-145601-9osr)
finding: The key now has the Game Passes scope. A read-only `python tools/create_gamepasses.py --dry-run` lists the experience's passes without a 403 and would create all 4. Nothing needed doing in Studio. The step is open again for you to press Run it.
evidence: tools/create_gamepasses.py --dry-run output "would create 'Business Frog' at 99 Robux ... 0/4 passes have ids"; tools/create_badges.py --dry-run also lists without a 403 (0/26 badges have ids)
files: none
test: none
verified: yes — dry-run against the live Open Cloud Game Passes list endpoint returned 200
review: n/a
owed: create the 4 Game Passes (Run it), see owed.md

## b-20261008-142125-1ucz  fixed  2026-10-08 15:35
note: Add skin colourways (3-4 tints per skin, 400-1500 Flys) via SkinCatalog Tints, Profiles ownedTints/selectedTint, SkinService BuyTint, base Color3 in WorldFrogCosmetics, swatch row in StoreUI
cause: The port had no colourways, so a player who owned every skin had nothing left to spend Flys on.
change: The new shared SkinTints module defines 4 tints bought per skin: Mint 400, Berry 600, Midnight 800 and Gold 1500 Flys. It is a separate module because SkinCatalog is looped as a numeric id map. Profiles gains ownedTints (a union on save, so no purchase is lost) and per-skin selectedTints. SkinService adds the BuyTint RemoteFunction and the SelectTint RemoteEvent, both validated on the server (skin owned, tint valid and owned, enough Flys), and sets a replicated FrogTint player attribute that follows skin switches. WorldFrogCosmetics multiplies the tint over every frog sprite except the eyes, for every lane, combined with the Pot heat tint. StoreUI shows a swatch row (Off plus the 4 tints) for owned skins. The new remotes are in GameServer's list, and doc 17 has a row.
files: src/shared/SkinTints.luau, src/server/Profiles.luau, src/server/SkinService.server.luau, src/server/GameServer.server.luau, src/client/WorldFrogCosmetics.client.luau, src/client/StoreUI.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check on the touched files (clean), selene src/ (0 warnings), tools/luau_check.sh on the touched files (clean), rojo build (ok)
verified: no — the HotFrog place is not open in Studio (the Studio MCP lists only Centralia and Tactics.rbxl), so no playtest ran; static checks only
review: looks-right; checked: git diff of the 6 files plus SkinTints.luau and SpriteSkin.luau, luau_check on the 6 files, selene, stylua; BuyTint/SelectTint validation (unknown tint, unowned skin, short Flys, no yield before the deduct), ownedTints union merge with Flys not merged upward, refreshFrogTint on SelectSkin/SelectTint/initPlayer, SpriteSkin.apply never writes Color3, heat-tween composition, eye exclusion by Suffix, respawned and late-joined frogs read the attribute; nit: a tint change during a heat tween ends that tween on the old colour
owed: none

## b-20261010-191413-h4s9  fixed  2026-10-12 13:47
note: I'm seeing two frogs on load layered on top of each other
cause: setRealHidden only set LocalTransparencyModifier on BaseParts, so the real frog's sprite Decals/Textures stayed visible under the store preview / menu bounce-in clone ("on load" is the bounce-in path, same defect).
change: setRealHidden now also sets LocalTransparencyModifier on Decal descendants (Texture included), so the real frog's art is hidden while a preview clone shows.
files: src/client/StoreUI.client.luau
test: stylua --check, tools/luau_check.sh StoreUI.client.luau (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. Look for: only one frog on join (Menu bounce-in) and in the store.
review: looks-right; checked: git diff of StoreUI, read setRealHidden/cycle/closeStore/bounceIn/openStore, WorldFrogCosmetics Transparency writes (no clash), luau_check on StoreUI exit 0. Noted: comment at StoreUI ~101 is now stale (cosmetic).
leftover: b-20261012-134552-h6nd (Studio playtest once Studio runs)

## b-20261010-191445-xv4n  fixed  2026-10-12 13:47
note: the frog "skin" is not appearing in my place when shopping in the store (it should happen automatically, not require hitting "wear")
cause: Same decal-hide defect as h4s9, and browsing to an owned skin only changed the local preview; SelectSkin was sent only on Wear/Back.
change: cycle() now fires SelectSkin as soon as the shown skin is owned and not already selected; unowned skins still only preview, Wear/Back remain as fallbacks.
files: src/client/StoreUI.client.luau
test: stylua --check, luau_check, selene src/, rojo build: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. Look for: cycling onto an owned skin flips status to "Selected" without Wear, and the real frog wears it on close.
review: looks-right; checked: git diff of StoreUI, SkinService SelectSkin handler validates p.owned[id]; repeat fires are idempotent and ordered.
leftover: b-20261012-134553-5e9t (Studio playtest once Studio runs)

## b-20261010-191925-0re3  fixed  2026-10-12 13:47
note: what does "ON" mean? should be it "OWNED"?
cause: The worn-tint swatch label read "On", which was unclear.
change: The worn tint swatch now reads "Worn"; owned-but-not-worn tints stay blank (no-tint swatch still "Off"), unowned show their price.
files: src/client/StoreUI.client.luau
test: stylua --check, luau_check, selene src/, rojo build: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. Look for: active tint swatch reads "Worn".
review: looks-right; checked: git diff of StoreUI swatch label code.
leftover: b-20261012-134553-kdv4 (Studio playtest once Studio runs)

## b-20261010-192255-ctop  fixed  2026-10-12 13:47
note: go ahead and remove the circle on a successful grab, but keep the X for a missed grab
cause: show() displayed the circle decal whenever the tap overlapped one of the player's own steps.
change: A grab tap now shows nothing; a miss still shows the red X.
files: src/client/WorldTouchIndicator.client.luau
test: stylua --check, tools/luau_check.sh WorldTouchIndicator (clean), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. Look for: tap own step = no marker; tap empty space = red X.
review: concern: the bug test raycast included Steps, so a step in front of a bug hid it and a real catch could show a stray X (shared with 4cof); checked: git diff, GameClient tryCatchBug/stepAt/rayParams, BugService attributes, stylua + luau_check.
re-review: looks-right; checked: git diff after repair, GameClient lines 405-575, bugRayParams mirrors tryCatchBug, hitBug returned on all four paths, stylua exit 0, luau_check clean.
leftover: b-20261012-134553-fwg9 (Studio playtest once Studio runs)

## b-20261010-192422-4cof  fixed  2026-10-12 13:47
note: eating a frog shouldn't resut in an X being shown
cause: The indicator only treated steps as hits, so a tap that caught a bug (fly) with the tongue counted as a miss and showed the X.
change: worldPointFor does a separate Bugs-only raycast (same filter as GameClient tryCatchBug) and flags own-lane bugs (Kind=="Bug", LaneUserId==local); show() hides both decals for that tap. Another lane's bug still shows the X (server rejects the catch).
files: src/client/WorldTouchIndicator.client.luau
test: stylua --check, luau_check, selene src/, rojo build: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. Look for: tapping a fly (even behind a step) catches it with no X.
review: concern: single raycast included Steps so a step in front of a bug hid the catch; checked: git diff, GameClient tryCatchBug/rayParams, BugService attributes.
re-review: looks-right; checked: repaired diff, Bugs-only bugRayParams, Bugs folder waited on at line 57, nil guards intact, luau_check clean.
leftover: b-20261012-134554-1830 (Studio playtest once Studio runs)

## b-20261010-191946-75rw  fixed  2026-10-12 13:47
note: hawt frog is missing his sunglasses sprites
cause: The frog rig had no Decal with Suffix="Accessory", so SpriteSkin never applied the uploaded HawtFrogAccessory art.
change: Added an Accessory Decal on the Head (Face Back, ZIndex 6, above the eyelids). SpriteSkin.apply blanks it for skins with no accessory art, so a re-skin never keeps the old accessory. Accessory added to SkinTints UNTINTED so colourways leave the gear its own colours. Doc 17's colourway row now lists the accessory as untinted.
files: src/assets/FrogModel.model.json, src/shared/SpriteSkin.luau, src/shared/SkinTints.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check, luau_check on SpriteSkin/SkinTints (clean), selene src/ (0 errors), FrogModel JSON parses, rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. Look for: sunglasses over Hawt Frog's eyes in game and store preview, untinted under a colourway; other skins show no accessory; 1024 canvas aligned to the head.
review: concern: Accessory missing from SkinTints UNTINTED, so a Flys colourway would tint the sunglasses/helmet; checked: git diff, SpriteSkin, SkinAssets.part fallback (no Universal/HotFrog accessory id), all SpriteSkin.apply call sites, JSON parse, stylua, luau_check, rojo build.
re-review: looks-right on the code (concern resolved: all three tint paths go through SkinTints.apply); it noted doc 17 line 185 still listed only scleras/eyes/pupils as untinted, which the orchestrator then updated (doc-only); checked: git diff of 3 files, grep of tint call sites, stylua, selene.
leftover: b-20261012-134554-rnd5 (Studio playtest once Studio runs)

## b-20261010-191959-j5e3  fixed  2026-10-12 13:47
note: space frog is missing his helmet sprite
cause: Same as 75rw: no Accessory decal on the rig, so SpaceFrogAccessory (the helmet) was never applied.
change: Same change as 75rw (Accessory Decal on Head, blank-when-missing in SpriteSkin, untinted in SkinTints, doc 17 row).
files: src/assets/FrogModel.model.json, src/shared/SpriteSkin.luau, src/shared/SkinTints.luau, docs/roblox-port/17-status-and-known-gaps.md
test: same as 75rw
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. Look for: helmet over Space Frog's head in game and store preview, limbs still in front.
review: concern: same tint concern as 75rw; checked: same as 75rw.
re-review: looks-right; checked: same as 75rw.
leftover: b-20261012-134554-9c8d (Studio playtest once Studio runs)

## b-20261010-191520-jsqs  fixed  2026-10-12 13:56
note: the directional arrow steps shouldn't rotate when falling
cause: GameServer.acquireStep rolled a random idle spinRate for every step except the pot rim, so ChangeDirection arrow steps tumbled as they fell and their direction became unreadable.
change: acquireStep now skips the spin roll for kinds with isArrow (all five ChangeDirection kinds set it), as it already did for the pot rim, so arrows stay level like Unity's. Doc 17's "Idle step spin" row now says arrows never spin.
files: src/server/GameServer.server.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check, tools/luau_check.sh GameServer (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. Look for: arrow steps falling at rotation 0 while ordinary steps still tumble.
review: looks-right; checked: git diff of GameServer and doc 17, isArrow set on all 5 ChangeDirection kinds in StepKinds (lines 177-245), spinRate assigned only in acquireStep and cleared on grab, Lane.trackStep resets angle 0 / spinRate nil on re-pooled parts, stylua --check.
leftover: b-20261012-135637-pscf (Studio playtest once Studio runs)

## b-20261010-192046-ptz8  fixed  2026-10-12 13:56
note: make sure the tongue is coming out of the mouth for all the frog skins
cause: expandTongue started the tongue at Head.Position, the centre of the 40-stud head part that holds the whole 1024px sprite canvas, which is well above the drawn mouth.
change: The tongue now starts at head.CFrame:PointToWorldSpace((0, -3.5, 0)) (local TONGUE_MOUTH_DROP in GameClient), where the Mouth sprites sit (y ~589-610 of 1024 across skins). Every skin shares the rig, and the offset is head-local so it follows head rotation.
files: src/client/GameClient.client.luau
test: stylua --check, tools/luau_check.sh GameClient (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. Look for: the tongue leaving from the drawn mouth on several skins.
review: looks-right; checked: git diff, expandTongue lines 490-545 (all uses of the origin), FrogModel.model.json Head size 40.229 and decal Face Back (+Y is image up), offset arithmetic (600-512)/1024*40.229 ≈ 3.46, BugService has no reach gate, gamepadTongue's Head.Position is a target pick not an origin, stylua --check.
leftover: b-20261012-135650-hhny (Studio playtest once Studio runs)

## b-20261010-191320-w7pp  fixed  2026-10-12 13:58
note: if the screen is beyond a certain width, the dark edges show?
cause: The backdrop tiles and overlay were a fixed 84 studs wide (lane width + 40), so a viewport wider than about 1.7:1, or the arrival zoom-out, let the camera see past their edges.
change: WorldBackdrop.refitWidth sizes the tiles and overlay to the camera's visible width at the backdrop plane (FOV 40, distance 43.2 x ARRIVAL_CAMERA_ZOOM + backdrop depth, viewport aspect) plus BACKDROP_EXTRA_WIDTH, re-running on ViewportSize / CurrentCamera changes. Texture repeat sizes stay at the original BASE_WIDTH (Kitchen 42, others 84), so the art tiles more times instead of stretching; the X drift limit follows the width.
files: src/client/WorldBackdrop.client.luau
test: stylua --check, tools/luau_check.sh WorldBackdrop (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only.
review: concern: tiling was tied to the new width, so Kitchen's repeat grew with the window and PotBack/LavaGradient stretched; checked: git diff, GameClient camera lines 108-200 (FOV 40 vertical, distance 43.2, arrival zoom dollies back, chainPunch only dollies in), WorldConfig/Config greps, visible-width math, tile height vs visible height, stylua + luau_check.
re-review: concern: OffsetStudsU is never set, so widening the part around its centre shifts the lane-centre art by (W/2 - 42) mod the repeat and single-image art can show a seam in view (repeat sizes now fixed, drift limit, camera swap and width math all correct); checked: git diff of the repair, greps for OffsetStudsU/V, TILE_WIDTH, BACKDROP_*, camera constants vs GameClient 115/122, stylua exit 0, luau_check exit 0.
leftover: b-20261012-135824-th24 (centre the texture offset, next tick), b-20261012-135824-ef71 (Studio playtest once Studio runs)
leftover: none — the Studio MCP cannot resize the play window, so other window sizes can never be checked from here (playtest check b-20261012-135824-ef71, no)

## b-20261010-192357-toml  fixed  2026-10-12 14:06
note: flies should be about twice as big
cause: The fly part was hard-coded at 2x2x0.4 studs in both the BugTemplate asset and BugService's fallback template (owner's request to enlarge it).
change: Both are now 4x4x0.4 studs; the Art and Wings decals scale with the part. The client tap raycasts the Bug part and the server catch has no distance check, so the catch target grows with the drawn fly. Movement ranges and swarm spacing are unchanged.
files: src/server/BugService.server.luau, src/assets/BugTemplate.model.json
test: stylua --check BugService, tools/luau_check.sh BugService (0 errors), selene src/ (0 errors), BugTemplate JSON parses, rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only.
review: looks-right; checked: git diff of both files, json.load of the template, stylua --check, grep of every bug-related file in src/ (BugService wander/edge/swarm values from Config studs, catch handler has no size check, WorldBugs only cycles wing textures, GameClient tap raycast and tongue tip at the centre, WorldTouchIndicator, Bursts) for a 2-stud assumption: none.
leftover: b-20261012-140635-e400 (Studio playtest once Studio runs)

## b-20261012-135824-th24  fixed  2026-10-12 14:06
note: Backdrop art shifts off-centre on wide windows (follow-up to w7pp's re-review concern)
cause: refitWidth widened the backdrop tile parts and overlay around their centre, but a Texture tiles from the face's corner and OffsetStudsU was never set, so the lane-centre art shifted by (W/2 - 42) mod the repeat versus the old 84-stud layout.
change: centreOffsetU(repeat) = ((TILE_WIDTH - BASE_WIDTH) / 2) % repeat is written to OffsetStudsU on both tile textures (refitWidth and setBackground, after StudsPerTileU changes, so Kitchen's 42 and the 84-stud art each use their own modulus) and on the overlay. Sign from geometry: the textures are on the Back (+Z) face seen from +Z, so U runs along +X from the -X edge.
files: src/client/WorldBackdrop.client.luau
test: stylua --check, tools/luau_check.sh WorldBackdrop (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; the OffsetStudsU sign (positive moves the art toward +U) is reasoned, not observed.
review: looks-right; checked: git diff and the whole file, stylua --check, luau_check, every StudsPerTileU / TILE_WIDTH write site (refitWidth, setBackground, initial creation, scrollBackground wrap only moves Position, setOverlay only the image), both moduli, geometry of U on the Back face; reviewer ~70% sure of the OffsetStudsU direction, which the leftover check settles.
leftover: b-20261012-140652-jfov (Studio playtest once Studio runs, including the sign)
leftover: none — the Studio MCP cannot resize the play window, so other window sizes can never be checked from here (playtest check b-20261012-140652-jfov, no)

## b-20261010-191837-a1x9  fixed  2026-10-12 14:07
note: where is the touch point to get a "perfect" on a carrot? it always seems "ok"
finding: Before this fix a Perfect needed a tap within 1 stud of the centre of the carrot's whole image canvas, which is about 3.5 studs from the carrot itself, so it almost always graded OK. Now grading measures from where the frog's hand grips the carrot (the middle of the carrot's body, lower-left of its image): tap within 1 stud of that for Perfect, about 2 studs for Great.
cause: GrabStep graded the tap against step.Position (the canvas centre), while Unity's Controller.TouchStep grades against step.position, the same pivot the hand snaps to; the carrot's grip point sits ~3.5 studs off the canvas centre, so Perfect was nearly unreachable.
change: GameServer GrabStep now grades from the grip point (step.Position + GripOffset rotated by the step's spin angle, the same formula the pull and limb snap use); kinds without a GripOffset grade as before. PullMath.gradeGrab comment and doc 17 (reach/grading row, carrot grip row) updated.
files: src/server/GameServer.server.luau, src/shared/PullMath.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check, tools/luau_check.sh on both .luau files (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only.
review: looks-right; checked: Unity Controller.cs TouchStep lines 239-251 (grades from step.position, the hand's snap pivot), git diff, rotation vs pull (~1769) and limb follow (~1598, step.CFrame built with the same angle), nil-safety (grip falls back to Vector2.zero, st guarded), tap point and grip both world space, gradeGrab has one caller, quality popup places from limbs, stylua + luau_check. It flagged doc 17 line 104 as stale, which the orchestrator updated (doc-only), and noted GRAB_GREAT_SQR is looser than Unity, filed as b-20261012-140726-qy5i.
followups: b-20261012-140726-qy5i
leftover: b-20261012-140726-nzco (Studio playtest once Studio runs)

## b-20261010-192132-5986  fixed  2026-10-12 14:19
note: the pause button doesn't seem to actually work? (answered by b-20261012-141202-0586: "DECISION: c")
cause: Owner ruling "c: remove the button". The button opened a client-only status panel by design (a multiplayer server can't pause for one player), so it read as a pause that didn't work.
change: Removed the whole Pause block from GameClient (PauseGui, the Pause button, PausePanel and its status text, Resume with its 3-2-1 countdown, isHoldingAnything, and its RunStateChanged hook). There was no keybind, remote or server handler. The stale UIKit comment, doc 15 item 4 and its open-question bullet, and doc 17's "Pause" row now say it was removed.
files: src/client/GameClient.client.luau, src/client/ui/UIKit.luau, docs/roblox-port/15-menus-and-input.md, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check, tools/luau_check.sh GameClient (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only.
review: looks-right; checked: git diff, grep of src/ for every symbol the block declared (none referenced elsewhere), shared locals still used, remaining RunStateChanged listeners, HUD/race rail/MenuClient layout (nothing positioned relative to the button), luau_check, stylua. It flagged doc 15 as stale, which the orchestrator updated (doc-only).
leftover: b-20261012-141929-q52r (Studio playtest once Studio runs)

## b-20261012-141202-0586  fixed  2026-10-12 14:19
note: DECISION: c (reopens b-20261010-192132-5986)
cause: owner ruling on b-20261010-192132-5986; applied there.
change: see b-20261010-192132-5986
files: src/client/GameClient.client.luau
test: none
verified: see b-20261010-192132-5986
review: see b-20261010-192132-5986 (reviewed and re-reviewed there)

## b-20261010-191757-89n1  fixed  2026-10-12 14:22
note: what could we do to make the inside of the pot seem more like a pot? (the clouds in the background not being visible would help) (answered by b-20261012-141140-a1h3: "DECISION: all")
cause: Owner ruling "all": hide the clouds in Pot, a darker inner-wall vignette, metal walls down both sides, and denser steam and bubbles with a stronger heat tint. The Pot had no vessel dressing, and while the lane was Pot the idle Menu still drew its clouds.
change: New PotAtmosphere.client.luau, active only while LevelName is Pot and the camera is on the local lane (not while spectating). It adds CorrodedMetal walls just outside the lane edge (±LANE_HALF_WIDTH at the camera's projection, holding through the arrival zoom), a screen-edge vignette whose side width shrinks on narrow viewports, a steam ParticleEmitter at the lava line, and a warm ColorCorrection, both scaled by PotHeat. WorldScenery skips cloud spawners and extras while a lane's Level is Pot and fades clouds already on screen. SceneryKinds gains an extra Pot Bubble spawner. All procedural, no new art. There is a new doc 17 row.
files: src/client/PotAtmosphere.client.luau, src/client/WorldScenery.client.luau, src/shared/SceneryKinds.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check, tools/luau_check.sh on all three .luau files (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only.
review: concern: the dressing stayed anchored to my lane while spectating a neighbour (walls filled their background), and the fixed 16% side vignette darkened live play on portrait viewports; checked: the new file in full, both diffs, GameClient camera/spectate/arrival zoom, LevelClient, Lane setLevel/resetRun, GameServer notifyLevelChanged, WorldLava PotHeat, Lanes.originOf, Config lane constants, Levels Pot spawners, wall projection maths at 1.0/1.35 zoom and chain-punch, Lighting conflicts (none), leaks on enter/leave, stylua, luau_check, selene.
re-review: looks-right; checked: the repaired file, the on-lane gate through arrival zoom, chain-punch and the spectate snap (no lerp, no threshold flicker), show/hide only on transitions, one ViewportSize connection at a time, the vignette clamp at portrait and 16:9, stylua, luau_check, selene.
leftover: b-20261012-142233-blru (Studio playtest once Studio runs)
leftover: none — the Studio MCP starts single-player Play only, so a second lane can never be checked from here, and the Studio MCP cannot resize the play window, so other window sizes can never be checked from here (playtest check b-20261012-142233-blru, partly)

## b-20261012-141140-a1h3  fixed  2026-10-12 14:22
note: DECISION: all (reopens b-20261010-191757-89n1)
cause: owner ruling on b-20261010-191757-89n1; applied there.
change: see b-20261010-191757-89n1
files: src/client/PotAtmosphere.client.luau
test: none
verified: see b-20261010-191757-89n1
review: see b-20261010-191757-89n1 (reviewed and re-reviewed there)

## b-20261010-191719-3rn3  fixed  2026-10-12 14:37
note: let's make the chef a real character in the background of the kitchen who moves around and does things to the level to mess with you. he can swing a knife to break steps (with a clear swing tell) (answered by b-20261012-141130-fhme: "DECISION: c, only on the kitchen")
cause: Owner ruling "c, only on the kitchen": a Kitchen-only, server-driven Chef with a telegraphed knife swing that breaks an un-held step, plus other tricks (throwing food, shoving steps sideways). The Chef was only drifting scenery. The owner named no frequency, so the loop picked 6-10 s (Config.CHEF_*); the owner can change it.
change: New server/Chef.luau, run per lane from GameServer's step Heartbeat on the Kitchen only, while Playing and alive and not in the arrival beat. Every 6-10 s the Chef picks an in-view, un-held step (never the rim or an arrow), walks to it, and does one of three actions after a ~1 s tell. Knife and Food knock the step loose via ctx.dropAway. Shove slides it 4 studs to a spot clear by clearSpot's spacing, via lane:addMotion; it is called off if the shown side is blocked at the blow. Knife and Food only happen while another un-held foothold is in view, so Normal mode can't be stranded. Grabbing the target, even in a 0.15 s grace after the blow shows, calls the action off. New WorldChef.client.luau draws the Chef, the red target ring, the knife, the potato, and the hand and arrow, for every lane, from the ChefAction/ChefPhase/ChefSeq/ChefShoveDir lane attributes and the ChefTarget step attribute. The old cosmetic Chef was removed from WorldScenery and Kitchen levelObjects. Doc 17 has a new row, plus the oversized-canvases row and motion-layer comments.
files: src/server/Chef.luau, src/client/WorldChef.client.luau, src/server/GameServer.server.luau, src/shared/Config.luau, src/server/Lane.luau, src/client/WorldScenery.client.luau, src/shared/Levels.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check, tools/luau_check.sh on every changed .luau file (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only.
review: concern (blocking): in Normal mode the Chef could cut every un-held step in view, stranding a frog holding one step (steps only spawn on a pull). Minor concerns: the blow could land off-screen; shoves ignored neighbours; late grabs were ForceReleased because of latency; client gaps (potato origin for a late viewer, per-frame target scans, an uncleared ChefShoveDir); doc 17 was missing. checked: both new files in full, the GameServer/Config/Levels/WorldScenery diffs, GameServer isHeldBy/dropAway/pooling/Heartbeat/GrabStep/killFrog/PlayerRemoving, Lane StepState/addMotion/clearSpot/spawning/arrival, the camera, SkinAssets stems, stylua, luau_check, selene.
re-review: concern (minor): a shove re-aimed at the blow could go against its telegraphed arrow (the orchestrator changed land() to call it off instead); the client can draw on a recycled step during Strike (filed b-20261012-143703-olbq); the shove test duplicates clearSpot (filed b-20261012-143704-8ian). checked: Chef.luau and WorldChef in full, foothold count vs camera view, grace vs GrabStep dropElapsed, pooling/pull during grace, shove maths vs Lane.clearSpot, Heartbeat cost, stylua, luau_check, selene. After the orchestrator's land() edit: stylua, luau_check Chef.luau, selene, rojo build pass.
followups: b-20261012-143703-olbq, b-20261012-143704-8ian
leftover: b-20261012-143704-0raj (Studio playtest once Studio runs)
leftover: none — the Studio MCP starts single-player Play only, so a second lane can never be checked from here (playtest check b-20261012-143704-0raj, partly)

## b-20261012-141130-fhme  fixed  2026-10-12 14:37
note: DECISION: c, only on the kitchen (reopens b-20261010-191719-3rn3)
cause: owner ruling on b-20261010-191719-3rn3; applied there.
change: see b-20261010-191719-3rn3
files: src/server/Chef.luau
test: none
verified: see b-20261010-191719-3rn3
review: see b-20261010-191719-3rn3 (reviewed and re-reviewed there)

## b-20261010-192344-aj8n  answered  2026-10-12 14:46
note: what's the difference between "bugs caught" and "flys earned"?
finding: "Bugs caught" is how many bugs you ate this run, and a golden bug counts as one like any other. "Flys earned" is how much Fly currency the run paid you: 5 for a normal bug, 25 for a golden one, plus the reward for any mission you complete during the run. So the two only line up (Flys = 5 x bugs) on a run with no golden bugs and no mission completed. Both are exact counts; nothing is miscounted. If the label reads as confusing, it could say "Flys earned (incl. golden bugs and missions)".
evidence: src/client/MenuClient.client.luau:387 (end-panel line); src/server/BugService.server.luau:565-582 (25 for golden, else 5, one BugCaughtServer per rewarded catch; gift flies pay nothing and don't count); src/server/GameServer.server.luau:192-213 (flysThisRun sums every AwardFlys, bugsThisRun counts catches), 1408-1417 (RunSummary), 2008-2009 (reset at StartRun); src/server/MissionService.server.luau:116 (mission reward mid-run); src/shared/Config.luau:388, 416
files: none
review: holds; checked by the orchestrator: BugService CatchBug handler, Config BUG_FLYS/GOLDEN_BUG_FLYS, GameServer AwardFlys/BugCaughtServer counters, MenuClient end-panel line

## b-20261012-140726-qy5i  fixed  2026-10-12 14:48
note: Great grab threshold is twice Unity's: Config.GRAB_GREAT_SQR is 4.0 studs^2, but Unity Controller.TouchStep grades <= 20 u^2 Great
cause: GRAB_GREAT_SQR was set to 4.0 at the initial port (77d4f08) instead of converting Unity's 20 u^2 with UNITY_TO_STUDS^2 (~0.0988 -> ~1.98 studs^2); GRAB_PERFECT_SQR (1.0 for 10 u^2) was converted correctly, and doc 03 already said 2.0. So Great reached ~2 studs from the grip instead of ~1.41. (The earlier a1x9 answer quoted "about 2 studs for Great"; it is now about 1.41 studs, as in Unity.)
change: Config.GRAB_GREAT_SQR 4.0 -> 2.0, with a comment giving Unity's 10/20 u^2 and the conversion. PullMath.gradeGrab is the only consumer. Unity-faithful, so no doc 17 row.
files: src/shared/Config.luau
test: stylua --check, tools/luau_check.sh src/shared/Config.luau (0 errors): pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.)
review: looks-right. checked: the u^2 -> studs^2 conversion, that gradeGrab's planar distance is in studs, that PullMath.gradeGrab is the only consumer, no other code or doc assumes 4.0.
leftover: b-20261012-144900-elu0 (Studio playtest once Studio runs)

## b-20261010-192237-7x8j  fixed  2026-10-12 14:48
note: the bubble popping particles should be more obvious
cause: The bubble pop burst was 8 tiny (0.2 stud) Neon balls living 0.25 s at speed 6, which is a few pixels for a quarter second at the 43-stud camera distance.
change: WorldConfig POP_BURST_* raised to 14 balls of 0.65 studs, 0.45 s, speed 13; WorldScenery popPart holds full opacity for the first 30% of life before fading, and fires a second white burst (0.6 scale, half speed, 0.7x lifetime) from the same pooled popBursts helper, whose pool cap the orchestrator raised to 96 so back-to-back pops don't churn parts. The pop sound already has an asset id. Applies to every bubble spawner, including the Pot's ExtraBubbleSpawner. No doc 17 change (the burst was already an ADAPTED particle stand-in).
files: src/shared/WorldConfig.luau, src/client/WorldScenery.client.luau
test: stylua --check, tools/luau_check.sh on both files (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass; after the cap edit stylua and luau_check WorldScenery re-run: pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.)
review: looks-right; optional: raise the popBursts pool cap above BURST_POOL_CAP 48 (applied by the orchestrator: cap = 96). checked: the WorldConfig and popPart diffs, world/Bursts pooling and fade, the pop sound id, stylua, luau_check.
leftover: b-20261012-144900-mqlm (Studio playtest once Studio runs)
leftover: none — the burst lives 0.5 s and the MCP screen capture cannot time it; how it reads is a look the user gets in normal play (playtest check b-20261012-144900-mqlm, partly)

## b-20261010-192146-ml2d  fixed  2026-10-12 15:00
note: kitchen needs equally groovy music as pot
cause: Kitchen had Unity's musicIndex 1, FrogSounds.wav: the same track as the Menu and Tutorial, quiet (RMS 0.07) and almost beatless (beat-pulse strength 0.10 by a spectral-flux autocorrelation of the Unity files), while Pot plays BrusselSprouts.wav (pulse 0.61, RMS 0.16).
change: Kitchen musicIndex 1 -> 3 (music4 = Adenine.mp3, already uploaded and unused by the base game; pulse 0.68, RMS 0.18, no silent intro, a short quiet break around 80-100 s). Comment in Levels.luau and Music.client.luau, plus a doc 17 "Kitchen music" deviation row. Opening.mp3 (music3, pulse 0.76) was passed over because it reads as a title/intro track; Two Wrongs is Country's. The owner can swap the index if Adenine isn't the right feel.
files: src/shared/Levels.luau, src/client/Music.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check and tools/luau_check.sh on both .luau files (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.)
review: looks-right. checked: the LevelChanged -> LevelClient -> Music.client path to music4 (non-zero id), every musicIndex consumer (WorldBackdrop ignores it), Pot->Kitchen crossfade and arrival-sting delay unaffected, the other tracks as alternatives, the comments and doc row.
leftover: b-20261012-150058-oxtf (Studio playtest once Studio runs)
leftover: none — the Studio MCP cannot hear audio (playtest check b-20261012-150058-oxtf, partly)

## b-20261010-192336-pgwh  fixed  2026-10-12 15:03
note: make space for a "tips" section after a run is over
cause: Feature request: the end-of-run panel had no room or content for tips (Unity has none either).
change: New Shared/Tips.luau: 13 tips, each checked against the code it cites (grab grades, the death rule, Crumble/CrumbleAfterRelease/Fall steps, arrows, bug and golden-bug Flys, Skittish bugs, the Shop, the pot rim at 50 steps and Country at 100, the Chef's tells), and Tips.pick(previous), which never repeats the last tip. MenuClient's end-of-run panel grew 404 -> 496 high with a divider, a "TIP" header and a wrapped tip label (max 18 pt) under Top Scores. A new tip is rolled only for a new RunSummary, so opening and closing Top Scores/Settings keeps it. The orchestrator reworded the level tip to name the pot rim (Kitchen starts on the rim grab once past 50 steps). Doc 17 has a "Post-run Tips section" row.
files: src/shared/Tips.luau, src/client/MenuClient.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check and tools/luau_check.sh on Tips.luau and MenuClient (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.)
review: looks-right; minor: "after 50 steps" for the Kitchen is loose, since it starts on the pot-rim grab (the orchestrator reworded that tip). checked: every tip against Config, PullMath, StepBehaviors, StepKinds, Lane (onStepClimbed, atPotTop), GameServer frog sim and grading, BugService, Chef.luau and StoreUI; the end-panel layout, UIKit scale floor and text sizing; the showEndPanel/restoreMainPanels/RunSummary tip logic; Tips.pick; stylua and luau_check.
leftover: b-20261012-150254-scgv (Studio playtest once Studio runs)
leftover: none — the Studio MCP cannot resize the play window, so other window sizes can never be checked from here (playtest check b-20261012-150254-scgv, partly)

## b-20261010-192455-bshn  fixed  2026-10-12 15:03
note: the main menu shouldn't hide the frog's face
cause: On the Menu the frog rests at the lane origin, which GameClient's camera (FOV 40, 31.43-stud vertical view) puts at screen centre, and its eyes and mouth span about +9 to -4.5 studs around it; the main menu panel was a 280x312 panel centred on screen, right over the nose and mouth.
change: New MenuClient.layoutMainPanel projects a face rectangle measured from the Hot Frog art (half-width 8.5 studs, bottom -5) through the camera's view and moves the main panel, with its streak and mission lines, to the right of the face in landscape (vertically centred) or under it in portrait. A shared clamp keeps the stack on screen, a few px above StoreUI's Gift/Shop toggles where it shares their x range (24-unit bottom margin otherwise); if it can't fit under the face, it overlaps the mouth rather than leave the screen. It reruns on ViewportSize change, deferred until UIKit's UIScale has updated. Frog and camera untouched. Doc 17 has a "Main menu layout" row.
files: src/client/MenuClient.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check and tools/luau_check.sh on MenuClient (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.) Computed layout: 1920x1080 panel x 1397-1775 (face ends 1232); 390x844 panel from y 546 (mouth ends 543); 4:3 still covers ~60 px of the face's outer edge and a tall tablet covers the nose and mouth.
review: concern (minor): the 4:3 window overlapped the face edge and the Shop toggle; a squarish portrait window pushed the hint and missions off-screen; the phone stack touched the screen bottom; no doc 17 row. checked: GameClient camera (FOV, distance, level-up pull-back, chain dolly, spectate), UIKit screenGui/UIScale and the position maths, StoreUI Gift/Shop and SpectateGui positions, the run-state and sub-panel paths, stylua, luau_check.
re-review: concern (minor): the five viewports' numbers follow from the code and there is always a gap above Gift/Shop; left over: 4:3 still covers ~60 px of the face edge (documented), the Spectate buttons can sit over the lower panel in portrait when other lanes exist (filed b-20261012-150254-k9vy; the orchestrator added it to the doc 17 row), and the panel may brush the HOTFROG title box at 4:3. checked: layoutMainPanel clamp maths against all five viewports, StoreUI lines 86-87, SpectateGui, the doc 17 row, stylua, luau_check.
followups: b-20261012-150254-k9vy
leftover: b-20261012-150254-352v (Studio playtest once Studio runs)
leftover: none — the Studio MCP cannot resize the play window, so other window sizes can never be checked from here (playtest check b-20261012-150254-352v, partly)

## b-20261012-143703-olbq  fixed  2026-10-12 15:07
note: WorldChef draws the knife/potato on a recycled step
cause: During the Strike follow-through WorldChef kept its target as long as the Part was still in the Steps folder. A pooled step re-acquired by the server (GameServer acquireStep bumps Gen, clears ChefTarget and sets LaneUserId) stays in the folder, so the chef could keep drawing on a step that was now a new spawn, or another player's lane's step.
change: WorldChef records the target's Gen (view.targetGen) when findTarget resolves it, and the Strike branch drops the target when it left the folder, its Gen changed, or its LaneUserId no longer matches the lane folder's UserId.
files: src/client/WorldChef.client.luau
test: stylua --check, tools/luau_check.sh, selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.)
review: looks-right; minor: the dropped target is only cleared locally, so view.target stays stale and is re-dropped every frame of the Strike (harmless, and clearing it would allow a mid-Strike rescan, so it was left). checked: the WorldChef diff, update(), findTarget, every view.target/targetGen write, the View type and initialiser, acquireStep and the release path in GameServer (685-715), the ChefTarget sites in Chef.luau.
leftover: b-20261012-150755-783q (Studio playtest once Studio runs)
leftover: none — the Studio MCP starts single-player Play only, so a second lane can never be checked from here (playtest check b-20261012-150755-783q, no)

## b-20261010-192533-5os7  fixed  2026-10-12 15:08
note: the demo climb should use both arms, and the player can still pause it by interacting
cause: The attract climb always grabbed with one hard-coded limb, WorldConfig.ATTRACT_LIMB (the Right arm), and ReachEmpty plus the client's menu click were built around "the other hand only", so the Left arm never climbed and a click could not interrupt the demo.
change: attractClimb picks the arm on the target rung's side (1 = Right at +X, else Left), so on the zig-zag ladder the arms alternate; the other arm lets go of its older rung and any click-reach on the grabbing arm is ended. A menu click/tap now sends the arm on the click's side reaching (the client picks the side from the click's X against the lane origin; the server allows either arm in Menu), drops that arm's demo hold and pauses the climb for the new WorldConfig.ATTRACT_PAUSE_TIME (3 s), with the ladder standing still; the climb then resumes. ATTRACT_LIMB removed; the doc 17 attract row was updated. The orchestrator reflowed the header comment.
files: src/server/GameServer.server.luau, src/shared/WorldConfig.luau, src/client/GameClient.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check and tools/luau_check.sh on the 3 .luau files (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.)
review: looks-right; nits: two over-long header comment lines (reflowed by the orchestrator); repeated clicks keep the demo paused (intended, own frog only). checked: the diff of all four files, Config.LIMB_REST limb indexing, isLimbIndex, endReach, the render loop's held/reach handling, refreshAttract and its StartRun/SetEndPanelOpen paths, ReachEmpty validation, the client ReachEmpty call, grep for ATTRACT_LIMB and "one hand" in src/ and docs/, strict typing of the new field and parameter.
leftover: b-20261012-150835-jy21 (Studio playtest once Studio runs)

## b-20261012-143704-8ian  fixed  2026-10-12 15:16
note: Chef shove landing test duplicates Lane.clearSpot's overlap maths
cause: Chef.shoveClear carried its own copy of clearSpot's step-vs-step grab-box + sweep + SPAWN_GAP overlap loop, so a later change to the spacing rule could make the two drift apart.
change: New Lane.crowdsSpot(self, p, hit, reach, shared, exclude?) holds the one overlap loop (same terms, same order). Lane.clearSpot calls it with its sweep as reach; Chef.shoveClear calls it with the shoved step's sweep and the step itself as exclude. The obstruction check stays in each caller. Pure refactor; no behaviour change.
files: src/server/Lane.luau, src/server/Chef.luau
test: stylua --check and tools/luau_check.sh on both files (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.) A pure refactor; the Chef playtest check b-20261012-143704-0raj also exercises it.
review: looks-right (orchestrator review). checked: the old and new loops term by term, Chef's hitOf against the HitSize fallback in crowdsSpot, sharedPending computed once per caller, the obstruction short-circuit order in clearSpot, the exclude of the shoved step.
leftover: b-20261012-152359-xgne (Studio playtest once Studio runs)

## b-20261012-150254-k9vy  fixed  2026-10-12 15:23
note: Main menu panel can sit under the Spectate buttons in portrait (and clip at 4:3) when other lanes exist
cause: The Spectate strip (bottom-centre, y 1,-170) shared the lower screen with the main-menu stack that layoutMainPanel puts under the face in portrait (and near the 4:3 panel's left edge), and it showed in every non-Playing state, so the end-of-run panel and the sub-panels also covered it.
change: The strip sits bottom-centre 110 units up (above the Gift/Shop toggles, below the face) and shows only while the main menu panel itself is up: MenuClient mirrors mainPanel.Visible as the player attribute MainMenuOpen (false in Dead and under sub-panels), and GameClient publishes SpectateStripShown. layoutMainPanel re-runs on that attribute and, where the panel shares the strip's columns, keeps the stack above it (bottom limit H-118s). The orchestrator added a reset: when the strip hides, or the spectated lane leaves, the camera snaps back to the player's own lane. A first revision (strip at top-centre) was dropped after review because it covered the frog's eyes in landscape. Doc 17 "Main menu layout" row updated.
files: src/client/GameClient.client.luau, src/client/MenuClient.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check and tools/luau_check.sh on both files (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.) Computed: 1280x720 strip x 472-808 vs panel from 889; 1024x768 strip right 691 vs panel 692; 390x844 stack ends 767, strip from 772.
review: concern (minor) on revision 1 (top-centre strip): it overlapped the frog's eye tops in landscape, sat under the end panel, StoreUI's SkinName label and the sub-panels, and the 120-wide label was hard to read on phones. checked: GameClient spectate/HUD code, MenuClient title, layoutMainPanel and panels, UIKit scaling, StoreUI positions, stylua.
re-review: concern (minor) on revision 2: an active spectate stayed on another lane behind a sub-panel or after death (the orchestrator fixed it); in tall portrait (768x1024) the strip lifts the stack over most of the face (filed as a followup; doc row amended); 1024x768 clears the strip by 1 px. checked: the layoutMainPanel maths for all five viewports, spectate state handling, attribute timing and load order, no layout feedback loop, the doc row, stylua.
followups: b-20261012-152031-992y
leftover: b-20261012-152052-41xk (Studio playtest once Studio runs)
leftover: none — the Studio MCP starts single-player Play only, so a second lane can never be checked from here, and the Studio MCP cannot resize the play window, so other window sizes can never be checked from here (playtest check b-20261012-152052-41xk, no)

## b-20261012-152031-992y  fixed  2026-10-12 15:29
note: Main menu stack covers most of the frog's face in tall portrait windows when the Spectate strip shows
cause: layoutMainPanel only lifted the fixed-size stack (panel + streak + mission lines, 434 units x the ScreenGui UIScale) above the bottom obstacles, so on tall portrait windows (768x1024: 555 px of stack, ~190 px of room under the face with the strip) it covered the face.
change: In portrait, when the room under the face is smaller than the stack, a shrink factor k in [min(1, 0.65/s), 1] is applied (never below an effective scale of 0.65, so phones do not shrink), and the layout maths uses the shrunk size; landscape is unchanged. UIKit.showPanel keeps one pop-in tween per frame (weak table), cancels it on hide and re-show, and eases 0.9*target -> target, where target is an optional numeric PanelScale attribute (default 1, so other panels are unchanged). New UIKit.setPanelScale(frame, k) sets the attribute, cancels a running pop-in and applies k at once if visible; layoutMainPanel uses it. Doc 17 "Main menu layout" row updated (the orchestrator corrected its 600x900 note).
files: src/client/MenuClient.client.luau, src/client/ui/UIKit.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check and tools/luau_check.sh on both files (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.) Computed: 768x1024 no strip k .56, stack 683-993 under the face bottom 675; with strip k .51 (floor), stack 591-873, over the lower mouth by ~84 px (was 318-873, the whole face); 390x844 unchanged scale, over the mouth by ~10 px without the strip; 600x900 fits without the strip.
review: concern: showPanel's uncancelled pop-in tween read PanelScale once, so when the Spectate strip appeared right after the menu showed (or on a resize mid pop-in) the tween ended at the stale scale (768x1024: 0.558 instead of 0.508, ~25 px over the strip); a quick hide/re-show left two tweens fighting. checked: UIScale pivot (UIKit.panel keeps AnchorPoint 0,0, so the top-left stays put), the other 23 showPanel callers, the layout maths for 390x844, 768x1024 both ways, 600x900 and landscape, the bottom-limit helper, re-layout triggers, the doc row, strict typing.
re-review: looks-right; minor: the 600x900 doc note was wrong (it just fits, losing its 8 px gap; corrected by the orchestrator); in the strip case the pop-in is cut short and the panel snaps to k (acceptable). checked: setPanelScale and cancelPop on show, hide, re-show and resize, the hide path's mid-tween scale reset on the next show, weak-table GC, other panels unchanged, stylua and luau-lsp on both files.
leftover: b-20261012-152921-w0wq (Studio playtest once Studio runs)
leftover: none — the Studio MCP starts single-player Play only, so a second lane can never be checked from here, and the Studio MCP cannot resize the play window, so other window sizes can never be checked from here (playtest check b-20261012-152921-w0wq, no)

## b-20261010-192608-4bs3  fixed  2026-10-12 16:24
note: on normal, have the stage "speed up" as a player goes on a streak
cause: Feature request, asked as needs-decision; the owner's ruling b-20261012-160551-8zmn: "the streak continues until a missed tap, but grows larger on great even larger on perfect. think combo bonuses and big loud effects; 2) a" (option a: everything moves faster, up to about 1.5x, and drops back when the streak breaks). Nothing tracked a streak, and the server never used missed taps.
change: Normal-only per-lane server streak: OK +1, Great +2, Perfect +3 (Config.STREAK_WEIGHTS), published as lane attributes Streak and StreakSpeed (1 -> STREAK_SPEED_MAX 1.5 at STREAK_FULL 20, ten Great grabs). It resets on a missed tap (the existing ReachEmpty intent, which the gamepad cursor grab now also sends), a tutorial fall and every run-state change; a level change keeps it. The speed divides each grab's pull time, makes Patrol/RiseAndFall run at max(height tempo, streak speed) (never above 1.5x), speeds Falling drift, and runs the Chef's Walk/WindUp/Flight clocks faster (Strike and CHEF_STRIKE_GRACE unscaled); WorldChef scales its tell clock the same way so the animations finish with the phase. Vanish keeps real time. Combo bonus: +1 score per 6 streak points per grab, max +5 (STREAK_BONUS_EVERY/MAX). Steps stay separate: a player attribute RunSteps (real steps this run) now drives the step missions, step badges and the race rail (the orchestrator moved the rail); score with the bonus drives the HUD, run summary, best score and boards. HUD: COMBO xN counter (left, under Bugs) that pops, grows to 1.45x and turns orange; SPEED UP!/MAX SPEED!! cues at 1.15/1.3/1.5x (PullMath.cueIndex); red COMBO LOST plus a camera flinch on a 6+ break; SfxEvents plays a pitched pop per streak grab from 4 up and base10 per cue. Doc 17 deviation row added.
files: src/server/GameServer.server.luau, src/server/Chef.luau, src/server/MissionService.server.luau, src/server/BadgeService.server.luau, src/shared/Config.luau, src/shared/PullMath.luau, src/shared/StepBehaviors.luau, src/client/GameClient.client.luau, src/client/SfxEvents.client.luau, src/client/WorldChef.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check and tools/luau_check.sh on the 10 changed .luau files (0 errors), selene src/ (0 errors), rojo build to the job tmp dir: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.)
review: concern: the combo bonus fed leaderstats.Score, which the 30/75-step missions and step badges read as steps; streak speed compounded with the height tempo to 2.25x and also shortened Vanish's fuse; WorldChef's tell animations ran on real-time Config durations, so faster server phases cut them off; the speed cue touched the enlarged combo counter. Minor: a tap while both limbs hold is not a miss; client-reported tapPos can always grade Perfect (filed). checked: Normal-only gating, reset sites, ReachEmpty/GrabStep per-lane validation, pull-time consumers (PullTime attribute), Chef strike grace, all onTick behaviours, score consumers, level progression by steps, HUD positions, lint and types.
re-review: concern (minor): the race rail still placed markers by leaderstats.Score against step landmarks (the orchestrator switched it to RunSteps). checked: RunSteps set/reset order, every Score reader, Classic mission/badge semantics, tempo max() with no streak, WorldChef against Chef.tick, cueIndex, lint and types.
followups: b-20261012-162429-k6wc
leftover: b-20261012-162429-pg4k (Studio playtest once Studio runs)
leftover: none — the remaining items are feel calls or code paths that read RunSteps, which v7rl confirmed counts real steps (playtest check b-20261012-162429-pg4k, partly)

## b-20261012-160551-8zmn  fixed  2026-10-12 16:24
note: DECISION: the streak continues until a missed tap, but grows larger on great even larger on perfect. think combo bonuses and big loud effects; 2) a
cause: The owner's ruling on b-20261010-192608-4bs3.
change: see b-20261010-192608-4bs3
files: see b-20261010-192608-4bs3
test: see b-20261010-192608-4bs3
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.)
review: see b-20261010-192608-4bs3
leftover: none — this is the ruling only; the change and its Studio playtest check (b-20261012-162429-pg4k) are on b-20261010-192608-4bs3

## b-20261012-162429-k6wc  fixed  2026-10-12 16:37
note: Client-reported tapPos lets a modified client always grade Perfect, which now also maxes the Normal combo streak (+3) and its score bonus (up to +5/grab) that feeds the leaderboards
cause: Grades come from a client-reported tap point the server cannot check, and since b99c6e5 the combo bonus went into sessionScore, which fed the saved best score, the global/daily/weekly boards and leaderstats. Owner's ruling b-20261012-162800-b426: "DECISION: b" (boards and best score count steps only; the combo bonus shows on the HUD and run summary but is not saved).
change: GameServer keeps sessionSteps (+1 per grab in addScore, reset with sessionScore, cleared on leave) and sets RunSteps from it. commitHighScore (profile.highScore, recordGlobalBest, recordPeriodScore), isNewBest and leaderstats.Score use steps. ScoreChanged gains steps as a 5th argument and RunSummary as a trailing one. SfxEvents' high-score and every-10 chimes count steps. The end panel keeps "Score: N" and shows "Steps: M   Best: B" when steps differ from score. Doc 17 combo row updated. Spoofed Perfects can still raise the in-run HUD score and the streak speed, but nothing saved.
files: src/server/GameServer.server.luau, src/client/SfxEvents.client.luau, src/client/MenuClient.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check and tools/luau_check.sh on the 3 changed .luau files (0 errors), selene src/ (0 errors), rojo build to the job tmp dir: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.)
review: looks-right (orchestrator review). checked: every sessionScore reset/clear site has a sessionSteps twin, addScore's only caller is GrabStep, every ScoreChanged/RunSummary consumer (GameClient and WorldQualityPopup ignore the new trailing args), RunSteps still drives missions, badges and the race rail, isNewBest against the steps-based best, the end-panel line, the doc row.
leftover: b-20261012-163727-v7rl (Studio playtest once Studio runs)

## b-20261012-162800-b426  fixed  2026-10-12 16:37
note: DECISION: b
cause: The owner's ruling on b-20261012-162429-k6wc.
change: see b-20261012-162429-k6wc
files: see b-20261012-162429-k6wc
test: see b-20261012-162429-k6wc
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.)
review: see b-20261012-162429-k6wc
leftover: none — this is the ruling only; the change and its Studio playtest check (b-20261012-163727-v7rl) are on b-20261012-162429-k6wc

## b-20261012-134552-h6nd  fixed  2026-10-12 20:26
note: Studio playtest check for b-20261010-191413-h4s9 once Studio is running (the fix was recorded unverified because the Studio MCP was not attached); see the verified: line of b-20261010-191413-h4s9 in done.md for what to look for
cause: Studio playtest check of the b-20261010-191413-h4s9 fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — one frog on join, and no leftover preview clone after the store closed
review: n/a
leftover: none

## b-20261012-134553-5e9t  fixed  2026-10-12 20:26
note: Studio playtest check for b-20261010-191445-xv4n once Studio is running (the fix was recorded unverified because the Studio MCP was not attached); see the verified: line of b-20261010-191445-xv4n in done.md for what to look for
cause: Studio playtest check of the b-20261010-191445-xv4n fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — owned skins show "Selected" with no Wear button; Back put Hawt Frog on the real frog
review: n/a
leftover: none

## b-20261012-134553-kdv4  fixed  2026-10-12 20:26
note: Studio playtest check for b-20261010-191925-0re3 once Studio is running (the fix was recorded unverified because the Studio MCP was not attached); see the verified: line of b-20261010-191925-0re3 in done.md for what to look for
cause: Studio playtest check of the b-20261010-191925-0re3 fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — the worn tint swatch reads "WORN"
review: n/a
leftover: none

## b-20261012-134553-fwg9  fixed  2026-10-12 20:26
note: Studio playtest check for b-20261010-192255-ctop once Studio is running (the fix was recorded unverified because the Studio MCP was not attached); see the verified: line of b-20261010-192255-ctop in done.md for what to look for
cause: Studio playtest check of the b-20261010-192255-ctop fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — a real click on empty space showed the red X, and the miss did not release the held step
review: n/a
leftover: none

## b-20261012-134554-1830  fixed  2026-10-12 20:26
note: Studio playtest check for b-20261010-192422-4cof once Studio is running (the fix was recorded unverified because the Studio MCP was not attached); see the verified: line of b-20261010-192422-4cof in done.md for what to look for
cause: Studio playtest check of the b-20261010-192422-4cof fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — a real click on a fly caught it (Bugs 1 -> 2), the tongue spawned at head-local (0,-3.5,0) and no miss X showed; a click on empty space did show the X
review: n/a
leftover: none

## b-20261012-134554-rnd5  fixed  2026-10-12 20:26
note: Studio playtest check for b-20261010-191946-75rw once Studio is running (the fix was recorded unverified because the Studio MCP was not attached); see the verified: line of b-20261010-191946-75rw in done.md for what to look for
cause: Studio playtest check of the b-20261010-191946-75rw fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — Hawt Frog's sunglasses show in the store preview and on the in-game frog
review: n/a
leftover: none

## b-20261012-134554-9c8d  fixed  2026-10-12 20:26
note: Studio playtest check for b-20261010-191959-j5e3 once Studio is running (the fix was recorded unverified because the Studio MCP was not attached); see the verified: line of b-20261010-191959-j5e3 in done.md for what to look for
cause: Studio playtest check of the b-20261010-191959-j5e3 fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — Space Frog's helmet is right in the store preview and on the real frog model (applied client-side with SpriteSkin.apply on the menu, since this profile does not own Space Frog): the dome covers the head with the face inside it
review: n/a
leftover: none

## b-20261012-135637-pscf  fixed  2026-10-12 20:26
note: Studio playtest check for b-20261010-191520-jsqs once Studio is running (the fix skips the idle spin for isArrow kinds): watch ChangeDirection arrow steps fall in Kitchen/Country and confirm they stay at rotation 0 while ordinary steps still tumble
cause: Studio playtest check of the b-20261010-191520-jsqs fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — a 55 s client sample across Kitchen into Country: 3 ChangeDirection arrow steps, none rotated; 21 ordinary steps tumbled while falling (e.g. Shelf -38..38 deg, BobRock -178..179 deg)
review: n/a
leftover: none

## b-20261012-135650-hhny  fixed  2026-10-12 20:26
note: Studio playtest check for b-20261010-192046-ptz8 once Studio is running (tongue origin moved 3.5 studs down the head to the drawn mouth): catch a fly with Hot Frog, Hot Lawyer, Space Frog and Hawt Frog and confirm the tongue starts at the mouth; tune TONGUE_MOUTH_DROP if a skin is off
cause: Studio playtest check of the b-20261010-192046-ptz8 fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — a magenta marker at head.CFrame*(0,-3.5,0), screenshotted on the menu, sits on the drawn mouth line for Hawt Frog, Space Frog, Invisible Man and Crossy Frog, and inside the frown's span (about 1.4 studs under its peak) for Hot Lawyer, so TONGUE_MOUTH_DROP needs no change; in-run tongues spawned at that point. Hot Frog itself was not applied (Hawt Frog and Invisible Man showed the same frog face)
review: n/a
leftover: none

## b-20261012-135824-ef71  unsure  2026-10-12 20:26
note: Studio playtest check for b-20261010-191320-w7pp once Studio is running: at an ultrawide window (~3:1) and during the arrival zoom-out the backdrop fills the width with no dark or blue bands, Kitchen tiles at its normal size, Pot/Water art is unstretched and no seam sits in view
cause: Studio playtest check of the b-20261010-191320-w7pp fix; the check could not be run from here.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: no — only the 1098x761 window was seen (backdrop filled, no bands or seams); the ultrawide case was not run
review: n/a
leftover: none — the Studio MCP cannot resize the play window, so other window sizes can never be checked from here

## b-20261012-140635-e400  fixed  2026-10-12 20:26
note: Studio playtest check for b-20261010-192357-toml once Studio is running: flies (menu and in-run, golden and swarm) draw at twice the old size, a tap on the edge of the drawn fly catches it, and wings still flutter
cause: Studio playtest check of the b-20261010-192357-toml fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — a real tap caught a fly; raycasts 1.0/1.5/1.9 studs from a fly's centre hit it and 2.1 missed (the drawn fly fills the 4-stud hit part, so its edge catches); wings showed different poses across screenshots in run and on the menu; golden and swarm flies use the same BugTemplate (BugService only recolours a golden one), so their size and hit box match. Not compared side by side with the old size
review: n/a
leftover: none

## b-20261012-140652-jfov  unsure  2026-10-12 20:26
note: Studio playtest check for b-20261012-135824-th24 once Studio is running: the OffsetStudsU sign in WorldBackdrop.centreOffsetU is reasoned, not observed. Resize the window between 16:9 and ~3:1 in Pot and Kitchen: lane-centre art must stay put and no PotBack/LavaGradient/overlay seam may show in view; if the art slides as width grows, negate the term
cause: Studio playtest check of the b-20261012-135824-th24 fix; the check could not be run from here.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: no — the resize between 16:9 and ~3:1 was not run; at 1098x761 the Pot and Kitchen art sat still with no seam in view
review: n/a
leftover: none — the Studio MCP cannot resize the play window, so other window sizes can never be checked from here

## b-20261012-140726-nzco  fixed  2026-10-12 20:26
note: Studio playtest check for b-20261010-191837-a1x9 once Studio is running: tap a carrot at the hand's grip spot (lower-left body of the carrot art) and confirm a Perfect popup; its visual centre should give Great/OK; other step kinds grade as before
cause: Studio playtest check of the b-20261010-191837-a1x9 fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — a real right-click at a carrot's grip spot gave streak +3 (Perfect), one at its visual centre +1 (OK); other kinds graded in the elu0 mix as expected
review: n/a
leftover: none

## b-20261012-141929-q52r  fixed  2026-10-12 20:26
note: Studio playtest check: no pause button shows during a run (top right), and the HUD and race rail load with no errors
cause: Studio playtest check of the b-20261010-192132-5986 fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — no pause button in any run; HUD and race rail loaded; console clean apart from the MCP's own AssistantCommand noise
review: n/a
leftover: none

## b-20261012-142233-blru  fixed  2026-10-12 20:26
note: Studio playtest check: Pot atmosphere (no clouds in Pot/Pot menu, metal walls only outside the lane, edge vignette, steam and warm tint rising with heat, extra poppable bubbles, all gone from Kitchen on and while spectating; portrait vignette narrows)
cause: Studio playtest check of the b-20261010-191757-89n1 fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: partly — Pot run: metal walls, steam, edge vignette and heat tint on; Kitchen: all off; the Pot menu shows no clouds. Not seen: spectating and the portrait vignette
review: n/a
leftover: none — the Studio MCP starts single-player Play only, so a second lane can never be checked from here, and the Studio MCP cannot resize the play window, so other window sizes can never be checked from here

## b-20261012-143704-0raj  fixed  2026-10-12 20:26
note: Studio playtest check: Kitchen Chef hazard (knife/potato/shove tells read, ~6-10 s cadence after the arrival beat, never the held step, never strands Normal mode, grab during tell calls it off, nothing on Tutorial/Pot/Country/menu/death, per-lane in multiplayer, no old drifting Chef)
cause: Studio playtest check of the b-20261010-191719-3rn3 fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: partly — Kitchen: Knife, Food and Shove every ~7 s (seq 5-9 at 0/6.9/14.1/21.8/28.7 s), the target was never the bot's held step, the tell reads (screenshot: the Chef reaching for the target), grabbing the target during WindUp called a Knife off within 0.06 s (no Strike, the step kept), and no action on the menu, on death or once the level reached Country; Easy runs at combo x169 / speed 1.5 were not stranded. Not seen: per-lane behaviour with 2 players (Pot and Tutorial were not sampled; Chef.tick resets outside Kitchen)
review: n/a
leftover: none — the Studio MCP starts single-player Play only, so a second lane can never be checked from here

## b-20261012-144900-mqlm  fixed  2026-10-12 20:26
note: Studio playtest check: tap a Pot bubble (and an ExtraBubbleSpawner bubble); the pop should throw a clearly visible tinted burst plus a smaller white one, obvious but not overbearing, with no hitch on rapid pops
cause: Studio playtest check of the b-20261010-192237-7x8j fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: partly — a real tap on a Pot bubble spawned 28 PopBurst parts (tinted and white) at +0.05 s, 14 left at +0.37 s, 0 at +0.5 s, no errors. Too short-lived for a screenshot, so how visible it reads and any hitch on rapid pops were not judged; an ExtraBubbleSpawner bubble was not tapped separately
review: n/a
leftover: none — the burst lives 0.5 s and the MCP screen capture cannot time it; how it reads is a look the user gets in normal play

## b-20261012-144900-elu0  fixed  2026-10-12 20:26
note: Studio playtest check: grab grades - Great now needs the tap within ~1.41 studs of the grip (was 2); confirm Perfect/Great/OK popups appear in sensible proportions
cause: Studio playtest check of the b-20261012-140726-qy5i fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — Classic end panel Perfect 32% / Great 35% / OK 33% with bot tap offsets {0,0.9 | 1.2,1.35 | 1.6,2.2}, matching Perfect <= 1, Great <= 1.414, OK beyond
review: n/a
leftover: none

## b-20261012-150058-oxtf  fixed  2026-10-12 20:26
note: Studio playtest check: reach the Kitchen (grab the pot rim after 50 steps); the music should crossfade from Pot's BrusselSprouts to Adenine (music4), loop cleanly, and feel as groovy as Pot
cause: Studio playtest check of the b-20261010-192146-ml2d fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: partly — in Kitchen music4 plays looped at volume 0.7 with the room tone; the crossfade, loop seam and groove could not be heard
review: n/a
leftover: none — the Studio MCP cannot hear audio

## b-20261012-150254-352v  fixed  2026-10-12 20:26
note: Studio playtest check: main menu at 16:9, 4:3, phone portrait and a tall tablet window; the frog's eyes and mouth should be visible with the panel beside (landscape) or under (portrait) the face, nothing over Gift/Shop, layout follows a window resize
cause: Studio playtest check of the b-20261010-192455-bshn fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: partly — landscape at 1098x761 and 1048x761: eyes and mouth visible, panel beside the face, nothing over Gift/Shop. 4:3, phone portrait and tablet were not run
review: n/a
leftover: none — the Studio MCP cannot resize the play window, so other window sizes can never be checked from here

## b-20261012-150254-scgv  fixed  2026-10-12 20:26
note: Studio playtest check: die and open the end-of-run panel; a TIP area under the buttons shows one wrapped tip, no overlap at phone/desktop sizes; it changes on the next death and stays put after opening/closing Top Scores or Settings
cause: Studio playtest check of the b-20261010-192336-pgwh fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: partly — at 1098x761 the TIP area sits under the buttons with one wrapped tip and no overlap, and a new tip showed on the next death; the end panel came back after Top Scores closed. Phone size was not run
review: n/a
leftover: none — the Studio MCP cannot resize the play window, so other window sizes can never be checked from here

## b-20261012-150755-783q  unsure  2026-10-12 20:26
note: Studio playtest check: in Kitchen with 2+ lanes, the Chef's knife/potato never draws on a step that was recycled to a new spawn or another lane
cause: Studio playtest check of the b-20261012-143703-olbq fix; the check could not be run from here.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: no — needs 2+ lanes in Kitchen
review: n/a
leftover: none — the Studio MCP starts single-player Play only, so a second lane can never be checked from here

## b-20261012-150835-jy21  fixed  2026-10-12 20:26
note: Studio playtest check: on the main menu the demo frog climbs hand over hand (Right/Left alternating, no double-grab, no arm stuck stretched); a click left/right of the frog sends that arm reaching and pauses the ladder ~3 s, then the climb resumes
cause: Studio playtest check of the b-20261010-192533-5os7 fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — the menu demo frog climbs hand over hand, alternating Right/Left; a click beside it sends that arm reaching and pauses the climb
review: n/a
leftover: none

## b-20261012-152052-41xk  unsure  2026-10-12 20:26
note: Studio playtest check: 2 players, main menu at 1280x720, 1024x768 and 390x844; the Spectate strip sits bottom-centre above Gift/Shop and never under the menu panel; it hides when Frogs/Settings/Top Scores opens or on death (camera back on own lane) and returns on Home
cause: Studio playtest check of the b-20261012-150254-k9vy fix; the check could not be run from here.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: no — needs 2 players and three window sizes
review: n/a
leftover: none — the Studio MCP starts single-player Play only, so a second lane can never be checked from here, and the Studio MCP cannot resize the play window, so other window sizes can never be checked from here

## b-20261012-152359-xgne  fixed  2026-10-12 20:26
note: Studio playtest check: in the Kitchen the Chef's shove still lands only on a clear spot (falls back to the other side when crowded) and step spawn spacing/nudging looks unchanged
cause: Studio playtest check of the b-20261012-143704-8ian fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — 3 Kitchen shoves: each moved the way its ChefShoveDir tell pointed, 1.2 s after landing the nearest other step was 7.1-9.0 studs away centre to centre, and the post-shove screenshot shows no step over another; spawn spacing looked as before over three Kitchen visits. The crowded-side fallback was not triggered
review: n/a
leftover: none

## b-20261012-152921-w0wq  unsure  2026-10-12 20:26
note: Studio playtest check: main menu at 768x1024 (with a 2nd lane so the Spectate strip shows, and without) - the panel+streak+missions shrink and sit under the face (strip case only touching the mouth), the pop-in ends at the shrunk size, resizing mid pop-in settles, other panels pop as before
cause: Studio playtest check of the b-20261012-152031-992y fix; the check could not be run from here.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: no — needs a 768x1024 window and a second lane
review: n/a
leftover: none — the Studio MCP starts single-player Play only, so a second lane can never be checked from here, and the Studio MCP cannot resize the play window, so other window sizes can never be checked from here

## b-20261012-162429-pg4k  fixed  2026-10-12 20:26
note: Studio playtest check: Normal combo streak - COMBO xN counter (left, under Bugs) jumps +1/+2/+3 for OK/Great/Perfect and heats up, SPEED UP!/MAX SPEED!! cues below it without overlap, pulls/sliders/arrows visibly faster (~1.5x max, not more at height), Vanish fuse unchanged, Kitchen Chef tells finish smoothly at speed with the strike grace unchanged; a free-limb tap on empty space shows COMBO LOST and resets speed; death/new run clears it; Classic shows none of it; score rises faster than steps while the race rail, the Kitchen at 50 / Country at 100, the 30/75-step missions and step badges still follow real steps
cause: Studio playtest check of the b-20261010-192608-4bs3 fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: partly — Easy: COMBO xN under Bugs rose +1/+2/+3, SPEED UP! twice then MAX SPEED!! below it, a free-limb tap on empty space showed COMBO LOST and reset streak and speed; 12 Perfect grabs reached x34 at speed 1.5 (the cap); death set streak 0 / speed 1 / label hidden and the Replay run started at 0; Kitchen at 50 and Country at 100 followed steps; Chef tells ran normally at speed 1.5. Classic: 22 Perfect grabs left streak 0, speed 1, HUD score = steps, no combo or cue. Not judged: how much faster sliders and arrows look, the Vanish fuse, missions and badges
review: n/a
leftover: none — the remaining items are feel calls or code paths that read RunSteps, which v7rl confirmed counts real steps

## b-20261012-163727-v7rl  fixed  2026-10-12 20:26
note: Studio playtest check: Normal run with a Perfect chain - HUD score climbs faster than steps, but the player-list Score and Best are real steps; on death the end panel shows Score plus 'Steps: M   Best: B', NEW BEST! only when steps beat the old best, and the saved best / global, daily and weekly boards get steps; the high-score and every-10 chimes follow steps; a Classic run shows no Steps text
cause: Studio playtest check of the b-20261012-162429-k6wc fix; no defect found.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio ece276fd, 1098x761 window), 2026-10-12
verified: yes — Easy run: HUD score 1022 against 183 steps; end panel "Score: 1022  NEW BEST!" with "Steps: 183   Best: 183" (old best 124); leaderstats Best 183; Top Scores row "1. FrequencyGames — 183"; the Classic end panel shows no Steps text. The chimes could not be heard
review: n/a
leftover: none

## b-20261012-194820-rwvq  fixed  2026-10-12 20:34
note: hot lawyer's arms are behind his head in terms of sorting layer
cause: Generic to every skin: the Body decal sat on the Body part at Z 0, in front of the arm parts (Z -0.2), so the arms and sleeves drew behind the body art (Hot Lawyer's suit makes it obvious); Unity draws the arms over the body.
change: The Body decal moved onto a new transparent child part BodyArt at Z -0.25 (welded to Body at spawn like the limb children), giving Head -0.3 < body art -0.25 < arms -0.2 < steps 0 < hands +0.3; WorldFrogCosmetics finds the body decal (heat tint) under BodyArt; doc 17's arm/hand draw-order row notes it. Recall found no earlier fix of this cause; the arms-behind-steps rule from b-20260921-100824-3azi is kept.
files: src/assets/FrogModel.model.json, src/client/WorldFrogCosmetics.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check, tools/luau_check.sh (0 errors), selene src/ (0 errors), rojo build to %TEMP% ok; Studio MCP playtest (Studio ece276fd): BodyArt at Z -0.25, unanchored with a WeldConstraint; menu screenshot with Hot Lawyer applied client-side.
verified: yes — on the menu the Hot Lawyer sleeves and hands draw over the suit (before, the lower sleeve was hidden under it) and the arms still sit over the head; in a Classic Pot run the body decal tinted to the heat colour (G 1.00 -> 0.59) as the frog sank within 8 studs of the lava, so the moved decal is still found
review: orchestrator read the diff; StoreUI anchors every clone part and pivots the whole model, so the preview keeps the body art; no other code reads the Body decal by path
leftover: none

## b-20261012-203422-vzh9  answered  2026-10-12 20:35
note: do the steps actually speed up when the combo gets higher?
finding: Yes, in Normal mode only, and most visibly early in a run. The combo multiplier (StreakSpeed, 1x rising linearly to 1.5x at streak 20, about ten Great grabs) shortens each grab's pull/scroll (pull time / speed), makes falling steps drift down faster (FALLING_DRIFT_SPEED x speed) and speeds the Chef's tells. Sliding, swinging and bobbing steps use the larger of the combo speed and the run's own height speed-up (1 + 0.004 per step, 1.4x at 100 steps, 1.5x from 125), not the product, so after about 100 steps the combo adds little to them and nothing past 125. Classic never speeds up from the combo; spawn rate and step spacing do not change with it. If you want the combo to stay felt late in a run, the choice is to multiply the two (up to 2.25x) or raise STREAK_SPEED_MAX.
cause: question; read src/server/GameServer.server.luau (laneSpeed, the grab's pullLane call), src/shared/StepBehaviors.luau (tempo, Falling onTick), src/shared/PullMath.luau (streakSpeed) and Config STREAK_* / STEP_MOTION_*.
change: none (question answered)
files: none
test: code read; the earlier Studio check pg4k saw StreakSpeed reach 1.5 in Easy runs
verified: n/a
review: n/a
leftover: none

## b-20261012-203452-bisk  fixed  2026-10-12 20:39
note: I only saw the "COMBO" wording in easy mode and not normal
cause: The menu shows internal modes one notch down (Classic reads "Normal", Normal reads "Easy"); the owner's b-20261010-192608-4bs3 "on normal" meant the menu's Normal (internal Classic), but that fix gated the whole streak to internal Normal, so only "Easy" had it.
change: GameServer drops the three mode gates (laneSpeed, the grab's streak/bonus, the ReachEmpty reset), so the combo, its speed-up, bonus, HUD cues and SFX run in both modes; the Tutorial level still never builds a streak (it ran as Classic before, so this keeps its old behaviour). The end panel's "Steps: N" line already shows whenever steps differ from score. Comments in Config, StepBehaviors, PullMath, Chef, GameClient, SfxEvents and WorldChef and the doc 17 combo row now say both modes.
files: src/server/GameServer.server.luau, src/shared/Config.luau, src/shared/StepBehaviors.luau, src/shared/PullMath.luau, src/server/Chef.luau, src/client/GameClient.client.luau, src/client/SfxEvents.client.luau, src/client/WorldChef.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: tools/luau_check.sh on the 8 .luau files (0 errors), selene src/ (0 errors), rojo build to the job tmp dir ok (stylua's diffs are the known CRLF-only ones); Studio MCP playtest (Studio ece276fd) of a Classic run with a client grab bot.
verified: yes — Classic run (Mode: NORMAL): 24 Perfect grabs showed COMBO x2 -> x71 on the HUD with SPEED UP! from the first grab and MAX SPEED!! at streak 20 (speed 1.5); a missed tap at streak 16 reset it to 0 / speed 1 and showed COMBO LOST; the end panel read "Score: 12" with "Steps: 6   Best: 183" and leaderstats Score stayed 6 (steps). The Tutorial-level exclusion was not played (it needs Replay Tutorial on the test profile).
review: orchestrator read the diff and added the Tutorial gate the fixer left out; a fixer briefly ran git stash/pop mid-run, and the tree was checked afterwards (the user's .bugs/.gitignore edit intact, stash list empty, only this fix's files changed).
leftover: none — the Tutorial gate is one level check in the grab handler, and a Tutorial streak would be cosmetic only

## b-20261012-203507-ew0q  fixed  2026-10-12 20:46
note: "some steps crumble"-- be specific as to what steps
cause: Three end-of-run tips in src/shared/Tips.luau described steps by behaviour only ("Crumbling steps", "Some steps crumble...", "Some steps drop away..."), and the last one described StepBehaviors.Fall, whose only kind (SlowFallRock) no live level spawns.
change: The tips now name each step by its look and level: "Pebbly rock clusters in the Kitchen and Country burst 1.5 seconds after you grab them." (CrumbleRock), "Potatoes in the Pot crumble the moment you let go of them." (Potato, CrumbleAfterRelease), and the Fall tip is replaced by "Violet rocks start shaking after a few seconds on screen, then drop away." (BlinkRock, Vanish: 3 s in view, 1.5 s warning). Source comments name the kinds; doc 17's tips row notes it.
files: src/shared/Tips.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check and tools/luau_check.sh on Tips.luau (pass), selene src/ (0 errors), rojo build to the job tmp dir ok; checked each claim against StepKinds (sprite, tint), Levels (pools and heightStages) and StepBehaviors.
verified: partly — text-only change checked against the code; not seen on the end panel in Studio (the tip is random per run, and the panel's wrapping was already checked for longer tips in scgv)
review: no concerns (sonnet reviewer: every tip's kind, level and timing match StepKinds/Levels/Config; no tip names an unspawned kind; CrumbleRock only appears from Kitchen stage 3 / Country stage 2, which the wording allows)
leftover: none — the three lines are at most 87 characters, within the ~90 the Tips area was laid out for

## b-20261012-203745-7jao  fixed  2026-10-12 20:47
note: raise streak speed max (reopens b-20261012-203422-vzh9)
cause: The owner's answer to vzh9's finding: the combo capped at 1.5x, the same as the height tempo, so late in a run it no longer sped moving steps up.
change: Config.STREAK_SPEED_MAX 1.5 -> 2 and STREAK_FULL 20 -> 30 (fifteen Great or ten Perfect grabs, a similar ramp per grab), cues STREAK_SPEED_CUES {1.15, 1.3, 1.5} -> {1.25, 1.5, 2}. Movers keep max(height tempo, streak), so a full combo now takes them to 2x at any height; pulls run up to twice as fast and the Chef's tells up to 2x (CHEF_STRIKE_GRACE still unscaled). Comments in Config/StepBehaviors and the doc 17 combo row updated. The value 2x is the loop's pick; the owner named no number.
files: src/shared/Config.luau, src/shared/StepBehaviors.luau, docs/roblox-port/17-status-and-known-gaps.md
test: tools/luau_check.sh on both files (0 errors), selene src/ (0 errors), rojo build to the job tmp dir ok (stylua's diff is CRLF-only); Studio MCP playtest (Studio ece276fd), Classic run with a Perfect-grab client bot.
verified: yes — 13 Perfect grabs: StreakSpeed 1.10, 1.20 ... 1.90, then 2.00 at streak 30 and held there; SPEED UP! during the climb and MAX SPEED!! at 2.00; a short pull's PullTime went from 0.227 s at 1.1x to 0.125 s at 2x. Not judged: whether 2x movers and Chef tells still read well, a feel call for the owner.
review: no concerns (sonnet reviewer: every use of STREAK_FULL / STREAK_SPEED_MAX / STREAK_SPEED_CUES is generic, cues fire once each, MAX SPEED!! keys off the cue count; feel risks only: pull time floors near 0.125 s and Chef tells run up to 2x with the Strike grace unscaled)
leftover: none — the remaining question is how 2x feels in play, which the owner judges in normal play; the knob is Config.STREAK_SPEED_MAX

## b-20261012-203957-zjix  fixed  2026-10-12 20:56
note: have the run over and all other ui modals "bounce" into view
cause: Every menu modal already went through UIKit.showPanel, but its pop was 0.9x -> 1x over 0.35 s, too small to read as a bounce; only the Daily Streak popup (0 -> 1, Back, 0.5 s) visibly bounced.
change: UIKit.showPanel now pops a panel from scale 0 to its resting scale over 0.5 s Back/Out (overshoot to about 1.10x, settling at 1x), the Daily popup's motion, so Run Over, the main menu, Settings, Top Scores and the Fly Jar all bounce in. A panel showPanel already has up is left alone on a repeat show (a weak shownPanels set), so showEndPanel rerunning when the run summary lands no longer restarts it; a panel built Visible (the main menu) still pops on its first show. setPanelScale now retargets a pop still playing instead of cancelling it and snapping, since showing the menu toggles the Spectate strip, which relays out the main panel mid-pop (reviewer's catch). The skin Store is left as is: it is the full-screen frog swap, not a panel, and its frogs already rise with a bounce.
files: src/client/ui/UIKit.luau
test: tools/luau_check.sh (0 errors), selene (0 errors), stylua clean, rojo build ok; Studio MCP playtest (Studio ece276fd) with a per-frame UIScale sampler and real clicks.
verified: yes — Settings (real click) 0.15 -> 1.096 peak -> 1.00 in 0.47 s; Close popped the main menu the same way; a no-grab run's death popped Run Over 0 -> 1.096 -> 1.00 once, with no second pop when the summary refreshed it; Top Scores from Run Over bounced, and closing it bounced Run Over back in; toggling SpectateStripShown at scale 0.29 mid-pop kept the bounce (peak 1.071, settled 1.000) instead of snapping. Fly Jar uses the same showPanel call and was not clicked. Console clean.
review: one concern, fixed (sonnet reviewer: setPanelScale cancelled a running pop and snapped it, and showing the menu triggers it through the Spectate strip in multiplayer; now retargets only a playing tween). No other concerns: no panel is hidden by a direct Visible write, nothing reads panel AbsoluteSize mid-pop.
leftover: none — the remaining call is whether 0.5 s with a 10% overshoot is the bounce the owner wants; PANEL_POP / PANEL_POP_FROM in UIKit.luau tune it

## b-20261012-205417-kzbm  fixed  2026-10-12 21:01
note: Let's just have combos get higher with perfect and good grabs, and a combo breaks if 3 seconds passes between perfect and goods
cause: Every grab added to the combo (OK +1, Great +2, Perfect +3) and it only ended on a missed tap, a fall or the run ending, so slow OK grabs kept a combo alive forever.
change: Config.STREAK_WEIGHTS OK 1 -> 0 (Great +2 and Perfect +3 kept; "good" read as the Great grade) and new Config.STREAK_TIMEOUT = 3. GameServer stamps os.clock on each streak gain (weak streakGainAt) and its Heartbeat resets a Playing lane's streak once 3 s pass with no gain; an OK grab neither grows the combo nor restarts the 3 s. GameClient draws a ComboTimer bar under the COMBO counter that drains over STREAK_TIMEOUT from each rise and hides on COMBO LOST, reset and run-state changes. The existing breaks on a missed tap and a fall are kept (the owner did not ask to drop them). Doc 17's combo row updated.
files: src/shared/Config.luau, src/server/GameServer.server.luau, src/client/GameClient.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: tools/luau_check.sh on Config, GameServer and GameClient (0 errors), selene src/ (0 errors), stylua clean, rojo build to the job tmp dir ok; Studio MCP playtest (Studio ece276fd) of Classic runs with a client grab bot sampling Streak / StreakSpeed and the frog lane's drift.
verified: yes — OK grabs left the streak at 0, and an OK mid-combo left it unchanged (9); Perfect grabs went 3/6/9, then with only an OK 1 s later the streak hit 0 2.97 s after the last Perfect, the HUD showed COMBO LOST with the bar hidden and the run still Playing; the bar was visible and drained about a third per second (185 -> 61 px over ~2 s at UI scale).
review: no concerns (sonnet reviewer: timer lifecycle correct — setRunState, fall and missed tap clear it, a stale streakGainAt is ignored at streak 0, Heartbeat and the grab handler share one thread; an OK grab restarts neither the server timeout nor the client bar. Minor, left as is: the bar starts when Streak replicates, so it can lag the server by half a round trip and show a sliver as COMBO LOST appears; comboLost's lastStreak >= 2 guard is now always true)
leftover: none — whether 3 s and OK = 0 feel right is the owner's call in play; knobs Config.STREAK_TIMEOUT / STREAK_WEIGHTS

## b-20261012-205444-huc1  fixed  2026-10-12 21:01
note: I don't want just the "grab" speed of steps to get faster on combos, but the actual movement of steps when holding a step to be faster as well, the "idle" scroll
cause: The combo speed (lane StreakSpeed) scaled pulls, moving steps and the Chef, but Classic's idle scroll (Lane.driftSpeed, the slow drift while you hang on a step) ignored it.
change: GameServer's Classic drift now runs at lane:driftSpeed(dt) * laneSpeed(lane), so a full combo makes the idle scroll up to 2x faster and it drops back to 1x when the combo breaks; the drift's own ramp still counts real time. Easy (internal Normal) has no idle scroll, so only the menu's Normal mode changes. Config comment and doc 17's combo row updated.
files: src/server/GameServer.server.luau, src/shared/Config.luau, docs/roblox-port/17-status-and-known-gaps.md
test: tools/luau_check.sh on Config, GameServer and GameClient (0 errors), selene src/ (0 errors), stylua clean, rojo build to the job tmp dir ok; Studio MCP playtest (Studio ece276fd) of Classic runs with a client grab bot sampling Streak / StreakSpeed and the frog lane's drift.
verified: yes — Classic run: drift measured 2.74 studs/s at speed 1.00, 3.02 at 1.10 and 3.40 at 1.20, so it tracks the combo speed.
review: no concerns (sonnet reviewer: timer lifecycle correct — setRunState, fall and missed tap clear it, a stale streakGainAt is ignored at streak 0, Heartbeat and the grab handler share one thread; an OK grab restarts neither the server timeout nor the client bar. Minor, left as is: the bar starts when Streak replicates, so it can lag the server by half a round trip and show a sliver as COMBO LOST appears; comboLost's lastStreak >= 2 guard is now always true)
leftover: none — Easy has no idle scroll to speed up; with kzbm's 3 s timeout the scroll falls back to 1x whenever the combo breaks, which is the request

## b-20261012-212255-idh7  fixed  2026-10-12 21:32
note: now that we've added colored skins, the blue frog shouldn't exist as a separate "frog" anymore, it should just be a color choice
cause: Blue Frog (SkinCatalog id 2, 100 Flys) was Unity's teal recolour of Hot Frog sold as its own skin. It could not simply become one of the multiply tints: Hot Frog's art is pure green (R = B = 0), so no Color3 multiply can make it blue.
change: Blue Frog is gone from SkinCatalog (id 2 left empty; every catalog loop is pairs). SkinTints gains id 5 "Blue", an art-swap colourway: it textures the frog with the old Blue Frog art instead of multiplying a colour, is offered on Hot Frog only (new `art` / `skins` / `swatch` fields, helpers offeredOn and artName), costs 100 Flys (the old first rung of the price ladder) and is the first swatch after Off. Profiles.migrateBlueFrog (on load and in the save merge) turns an owned Blue Frog into Hot Frog's Blue tint, and a worn Blue Frog into Hot Frog wearing Blue. GameServer's frog spawn, SkinService's SelectSkin/SelectTint (new reskinFrog) and StoreUI's previews and Back re-skin all texture with the art name; BuyTint/SelectTint reject a tint not offered on that skin; the swatch row hides swatches a skin isn't offered and sizes to the rest. Docs 08 and 17 updated.
files: src/shared/SkinTints.luau, src/shared/SkinCatalog.luau, src/server/Profiles.luau, src/server/SkinService.server.luau, src/server/GameServer.server.luau, src/client/StoreUI.client.luau, docs/roblox-port/08-frog-skins-and-store.md, docs/roblox-port/17-status-and-known-gaps.md
test: tools/luau_check.sh on the 6 .luau files (0 errors), selene src/ (0 errors), stylua clean (GameServer's diff CRLF-only), rojo build ok; Studio MCP playtest (Studio ece276fd) with real store clicks and remote calls.
verified: yes — the test profile, which owned Blue Frog, loaded with Blue owned on Hot Frog; the store has no Blue Frog (Hawt Frog "<" goes straight to Hot Frog; client catalog ids 1,3-9); Hawt Frog shows Off + 4 tints, Hot Frog Off + teal Blue + 4; clicking Blue turned the preview teal and retextured the server frog (Body/Head/LeftHand/Mouth/RightLimb = BlueFrog ids, FrogTint 5), which stayed teal in a run; SelectTint(1,0) reverted to Hot Frog art mid-run and (1,5) back; BuyTint(3,5) returned false and SelectTint(3,5) changed nothing; console clean. The test profile was put back on Hawt Frog with no tint. Not run: buying Blue from scratch (this profile already owned it; it goes through the existing BuyTint path) and a phone-width store.
review: no concerns (sonnet reviewer: the save merge converts a stale record's skin 2 and never writes it back, old servers keep the tint through the ownedTints union, no code assumes contiguous ids or grants skin 2, SelectSkin/SelectTint stay consistent in either order). Minor, left as is: a record with selected 2 but no owned 2 (not reachable through SelectSkin) would get Blue; a migrated Blue Frog wearer's Hot Frog tint choice becomes Blue; Hot Frog's swatch row is one swatch wider (472 px).
leftover: none — a separate inbox item b-20261012-212643-ba72 covers the other tints barely changing Hot Frog's green

## b-20261012-212643-ba72  fixed  2026-10-13 09:39
note: Colour tints (Mint/Berry/Midnight/Gold) barely change Hot Frog: they only make its green slightly darker
cause: The tints were a Color3 multiply over the original art, and Hot Frog's art is pure green, so every colour came out as a darker green. Ruling (b-20261013-055017-6y7s): "DECISION: A, but certain parts on certain skins don't tint (hot lawyer's skin, eyes across all skins, etc)".
change: 45 tint-ready `<Prefix>Tint<Suffix>.png` sprites were added and uploaded (all Approved/Green; ids written by write_asset_ids.py). In each copy the frog green is greyed and every other pixel is kept. The split is Hot Frog 16, Crossy Frog 15, Hawt Frog 2 grab hands, and the clothing of Space Frog 6, Business Frog 2, Hot Lawyer 2 (suit only) and Invisible Man 2. A frog wearing a colour tint uses this set via SkinTints.artName -> SpriteSkin.apply, and only sprites with a copy are marked `Tinted` and take the colour. These stay as drawn: sclera, pupils, mouth/tongue, accessories (sunglasses, helmet), Hot Lawyer's head, hands and eyelids, and Mystery Frog's silhouette. Off and Blue behave as before. The Blue Frog id block in SkinAssets.luau moved above the "Auto-added" sentinel, because build_manifest drops BlueFrog keys and write_asset_ids would have deleted them (ids unchanged). Docs 08 and 17 were updated.
files: src/shared/SkinAssets.luau, src/shared/SpriteSkin.luau, src/shared/SkinTints.luau, src/client/StoreUI.client.luau, src/client/WorldFrogCosmetics.client.luau, src/server/GameServer.server.luau, src/server/SkinService.server.luau, docs/roblox-port/08-frog-skins-and-store.md, docs/roblox-port/17-status-and-known-gaps.md, Sprites/Frogs/*/<Prefix>Tint*.png (45 files)
test: luau_check.sh on src/ exit 0; selene src/ 0 errors 0 warnings; rojo build OK; stylua --check passes on LF-normalised copies (CRLF-only diffs otherwise); upload 45/45 OK and --status 45 Approved/Green
verified: partly — Studio MCP playtest of Hot Frog, 2026-10-13. Server SpriteSkin.apply(frog, SkinTints.artName(1, 1, "Hot Frog")) plus FrogTint=1 replicated: on the client the 16 Tinted body/head/limb/hand/eyelid sprites were Mint (0.59,1,0.75), and Accessory, both scleras, both pupils and Mouth stayed white. Gold on Hot Lawyer tints only RightLimb, LeftLimb and Body (the suit); head, eyes, eyelids and hands stay untinted. Space Frog tints body, head and gloves; the helmet Accessory stays untinted. Blue swaps to the Blue Frog body with 0 Tinted. Off restores the Hot Frog body with 0 Tinted, and the client colours reset to white. All 21 frog textures preloaded Success, and the console was clean. Not seen: the rendered frog, because Studio's 3D viewport captured blank white this session (backdrop too, with post effects off as well); an offline multiply preview of the new PNGs shows clean mint, gold and berry bodies and a suit-only tint on Hot Lawyer.
review: looks-right (reviewer note: the eye-crescent LeftEye/RightEye and eyelid sprites are green skin around the eye and now tint; sclera and pupils do not); checked: full git diff of the 7 Luau files; key=id pairs of HEAD vs working SkinAssets compared with comm (179 -> 224, none removed or changed, 45 added are all *Tint*, 19 BlueFrog ids byte-identical); every SpriteSkin.apply/artName call site (GameServer 1271, SkinService 137, StoreUI 251/378/496, WorldFrogCosmetics applySkinTint/watchTintedArt); SkinAssets.part's only caller; HotFrogTintLeftEye.png vs HotFrogLeftEye.png viewed
leftover: the rendered look in Studio (a tinted frog on the menu and in the store) was not seen, because the 3D viewport captured blank; also note that Mystery Frog's borrowed grab hands (Hot Frog art) take the tint

## b-20261013-055017-6y7s  fixed  2026-10-13 09:39
note: DECISION: A, but certain parts on certain skins don't tint (hot lawyer's skin, eyes across all skins, etc)
cause: the user's ruling on b-20261012-212643-ba72
change: see b-20261012-212643-ba72
files: see b-20261012-212643-ba72
test: see b-20261012-212643-ba72
verified: yes — the ruling was applied in b-20261012-212643-ba72; its own partly-verified check is held by b-20261013-093943-gk5k
review: looks-right; checked: see b-20261012-212643-ba72
leftover: none — the remaining Studio look is filed as b-20261013-093943-gk5k against b-20261012-212643-ba72

## b-20261013-093943-gk5k  blocked  2026-10-13 09:45
note: Playtest check: see a colour-tinted frog render in Studio (Hot Frog Mint/Gold on the menu and in the store preview, Hot Lawyer suit-only tint, Space Frog helmet untinted); also judge Mystery Frog's borrowed grab hands
cause: Studio playtest check of the b-20261012-212643-ba72 fix; Studio's 3D viewport draws blank white (an Edit-mode capture from (0,0,40) toward the origin showed only the axis labels), so no rendered look can be captured.
change: none (verification only)
files: none
test: Studio MCP screen_capture of Hot Frog (Studio ece276fd) in Edit mode, 2026-10-13
verified: no — the 3D viewport renders blank in Edit and Play, so the tinted frog cannot be seen from here until Studio is restarted
review: n/a
owed: o-20261013-094512-yobn (restart Roblox Studio)
leftover: re-run after the restart, filed as b-20261013-094524-ql74

## b-20261013-094524-ql74  fixed  2026-10-13 09:59
note: Playtest check after the Studio restart: see a colour-tinted frog render (Hot Frog Mint/Gold on the menu and in the store preview, Hot Lawyer suit-only tint, Space Frog helmet untinted) and judge whether Mystery Frog's borrowed grab hands should take the tint
cause: Studio playtest check of the b-20261013-093943-gk5k / b-20261012-212643-ba72 tint work; no defect in the tinting itself.
change: none (verification only)
files: none
test: Studio MCP playtest of Hot Frog (Studio 2131c262, after the restart), 2026-10-13. The menu frog was re-skinned server-side with SpriteSkin.apply(SkinTints.artName(...)) plus the FrogTint attribute; the store preview was fed a profile copy with a tint owned and worn through a temporary echo remote; the real skin (Business Frog, tint 0) and profile were restored and the console stayed clean
verified: yes — Hot Frog Mint: body, head, eye crescents, arms and hands mint, eye whites, pupils and mouth as drawn. Hawt Frog Mint: frog mint, sunglasses untinted. Hot Lawyer Gold: suit gold (client Color3 1,0.84,0.31 on Body and both limbs only), head and hands untinted. Space Frog Berry: hands berry, helmet stays its own cyan. Store: Business Frog with Mint owned and worn shows the WORN swatch on Mint and a mint preview with untinted eyes. Mystery Frog judged: its borrowed Hot Frog grab hands come out bright mint on the black silhouette, which looks wrong, so it is filed as b-20261013-095859-quga
review: n/a
leftover: none — the Mystery Frog grab-hand look is filed as b-20261013-095859-quga

## b-20261013-094916-s41t  fixed  2026-10-13 10:06
note: arms are behind the frog's head and body
cause: The frog render Heartbeat snapped a held limb to its step's full position, Z included. The menu ladder rungs sit at Z -0.2, which dragged the limb there and the welded arm to -0.4, behind BodyArt (-0.25) and Head (-0.3). The other limb was easing back, so it was caught mid-way at about -0.247.
change: A held limb is now posed at CFrame.new(gripPos.X, gripPos.Y, f.pos.Z). It follows the step in X/Y and keeps the frog's own depth, which is the limb's rest Z of 0, so the arms stay at -0.2 (in front of the body and head) and the hands at +0.3. The reach branch already keeps the limb's own Z. This follows up b-20261012-194820-rwvq, whose model layering was right at rest.
files: src/server/GameServer.server.luau
test: stylua --check, selene src/ (0 errors), bash tools/luau_check.sh, rojo build (all clean)
verified: yes. Studio playtest on 2131c262. On the menu, while the demo frog climbed the rungs, RightArm and LeftArm stayed at Z -0.20 over six samples (BodyArt -0.25, Head -0.30, hands +0.30, limbs 0), and the screenshot shows Business Frog's sleeves drawn over the body. In an Easy run sampled for 6 s at Kitchen, both arms stayed at -0.20. The store preview clone never poses limbs at a step (reviewer read StoreUI), so it keeps the template's rest depths.
review: looks-right. The reviewer checked f.pos.Z = PLANE_Z = 0 = the limb rest Z, that the arm and hand are welded to the limb, the reach, return and attract branches, and that GrabTarget, grab validation and BugService don't rely on step Z.
leftover: none

## b-20261013-095024-ufca  fixed  2026-10-13 10:06
note: increase max speed by 2x
cause: The combo speed cap (Config.STREAK_SPEED_MAX) was 2, so a full streak could only double the pace. Read as "double the max": 2 -> 4. Filed from a menu-Normal end panel, and the HUD calls this cap MAX SPEED!!.
change: STREAK_SPEED_MAX 2 -> 4 at the same STREAK_FULL of 30, so the ramp is twice as steep. STREAK_SPEED_CUES {1.25, 1.5, 2} -> {1.5, 2, 3, 4}, so MAX SPEED!! shows at 4x. The pull-time clamp is applied before dividing by the multiplier, so the shortest pull is 0.0625 s. After review, StepBehaviors' oscillate scales its per-tick cap by the tempo, so Patrol and RiseAndFall keep their full sweep at 4x. Doc 17's combo row was updated.
files: src/shared/Config.luau, src/shared/StepBehaviors.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check, selene src/ (0 errors), bash tools/luau_check.sh, rojo build (all clean)
verified: yes. Studio Easy run on 2131c262 with a bot making Perfect grabs: StreakSpeed went 1.30, 1.60 ... 3.70, 4.00 over the first 10 grabs and held 4.00 to grab 40 (COMBO x117), the HUD showed MAX SPEED!!, the run reached Kitchen, and the console was clean. The Patrol behaviour, driven on the server with a test ctx at 7 s and 60 Hz, kept a ±3.00 offset at tempo 1, 2 and 4, with 4, 7 and 16 sign changes. How 4x feels was not judged.
review: concern. oscillate's fixed per-tick cap (2·A·rate·dt) would bind at 4x and shrink or lag the Patrol and RiseAndFall sweeps. The fixer scaled the cap by the tempo.
re-review: looks-right. The cap now scales with tempo, the pull clamp is applied before dividing by speed, nothing hard-codes 2, and dropping the 1.25 cue is safe.
leftover: none — read as cap 2x -> 4x; if the user meant something else (e.g. 3x), it is one Config number (STREAK_SPEED_MAX).

## b-20261013-095859-quga  fixed  2026-10-13 10:11
note: Mystery Frog's grab hands show Hot Frog's hand art (green, or mint/gold under a colour tint) on the black silhouette; the grab hand should match the silhouette like its open hands
cause: Mystery Frog has no grab-hand art, so SkinAssets.part fell back to Hot Frog's hand (its tint-ready copy when a tint is worn), which was drawn in colour on the black silhouette.
change: SpriteSkin.apply flags a silhouette skin's borrowed *Grab sprites with a Silhouette attribute and asks for the untinted hand. SkinTints.apply paints flagged sprites black (Color3 0,0,0) whatever tint is worn. SkinTints lists the silhouette skins (only Mystery Frog). WorldFrogCosmetics re-applies the tint when the attribute changes. No new art was uploaded. Doc 17's "Mystery Frog entirely (black silhouette)" note already covers this.
files: src/shared/SpriteSkin.luau, src/shared/SkinTints.luau, src/client/WorldFrogCosmetics.client.luau
test: stylua --check (touched files), selene src/ (0 errors), bash tools/luau_check.sh, rojo build (all clean)
verified: yes. Studio playtest on 2131c262. The menu frog was re-skinned server-side to Mystery Frog with Mint (FrogTint 1). On the client, RightHandGrab and LeftHandGrab had Color3 0,0,0 and Silhouette=true; the open hands and body were unchanged. The screenshot shows the black silhouette gripping the red rung with a black hand and no mint. With no tint (FrogTint 0) the grab hands were still black. Switching back to Business Frog cleared Silhouette and reset the grab hands to Color3 1,1,1. The console was clean ([BugReport] ready only), the frog was restored, and play is stopped. The store preview was not opened; the reviewer confirmed it calls SpriteSkin.apply then SkinTints.apply.
review: looks-right. The reviewer checked that switching skins clears the attribute and resets the colour, that other tinted skins are unaffected, the server frog, store preview and store real-frog paths, that the Mystery name check holds and that MysteryFrog*HandGrab ids are absent, Color3 vs ImageColor3 per class, attribute-before-tint ordering, and that there is no require cycle.
leftover: none

## b-20261013-101115-00q9  fixed  2026-10-13 10:16
note: hide mystery frog for now
cause: SkinCatalog had no way to mark a skin unavailable, so the store, buying and selecting all treated Mystery Frog as live.
change: Mystery Frog's SkinCatalog entry has hidden = true, and deleting the flag restores it. StoreUI leaves hidden skins out of its paging list. SkinService refuses BuyWithFlys and SelectSkin for them. Profiles (migrateBlueFrog, on both load paths) moves a player wearing a hidden skin to Hot Frog. Ownership and tint data are kept, so un-hiding gives it back. Mystery has no game pass, and nothing else lists skins (no gifts, missions or random rolls). Doc 17 has a deviation row.
files: src/shared/SkinCatalog.luau, src/client/StoreUI.client.luau, src/server/SkinService.server.luau, src/server/Profiles.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check (touched files), selene src/ (0 errors), bash tools/luau_check.sh, rojo build (all clean)
verified: yes. Studio playtest on 2131c262 opened the store with real clicks on FROGS and Next. Paging read Business Frog, Hot Lawyer, Invisible Man, Crossy Frog, Hot Frog, Hawt Frog, Space Frog, then wrapped to Business Frog: seven skins, no Mystery Frog. The console was clean and play is stopped. The server refusal and the load-time reset were checked by review only, because the test profile neither owns nor wears Mystery Frog, so a live call would be refused for not owning it anyway.
review: looks-right. The reviewer checked store paging (the ids array, % #ids wrap, and the fallback when the worn skin is hidden), the game-pass, receipt, BuyTint and SelectTint paths, that the Profiles reset runs before SkinService or GameServer read selected, other Catalog iterations, and strict types (luau_check clean).
leftover: none

## b-20261013-101145-cvni  fixed  2026-10-13 10:19
note: there should be a black or very dark tint available for frogs
cause: feature request; the tint list had no dark colour (Midnight is a dark blue).
change: tint id 6 "Shadow", Color3 (55,55,60), 1000 Flys, offered on every skin (not pure black so the drawn outlines still separate shapes); store swatch labels pick white or dark text by the swatch's luma so the price reads on the dark swatch; doc 08 lists the tint prices. Commit 8500e43
files: src/shared/SkinTints.luau, src/client/StoreUI.client.luau, docs/roblox-port/08-frog-skins-and-store.md
test: stylua, selene, rojo build, luau_check clean; Studio MCP playtest of Hot Frog
verified: yes — Hot Frog's store row fits 7 swatches; Hot Frog wearing Shadow on the menu is a near-black frog with the eyes left untinted (screenshot); after the label fix the "1000" price on the Shadow swatch is white and readable (Hot Lawyer store page screenshot); console clean
review: looks-right (sonnet)
re-review: looks-right — the label-colour fix, added after the Studio check found dark text on the near-black swatch: Blue and Shadow get white text, the rest dark
leftover: none — doc 17's Skin colourways row gets Shadow 1000 with the b-20261013-101101-qbb4 change

## b-20261013-101101-qbb4  fixed  2026-10-13 10:21
note: business frog's tint should color his suit and not the frog itself or at least tint the frog a different color than the suit (maybe complementary colors?)
cause: Business Frog's tint-ready copies greyed the frog green and left the navy suit as drawn, and its borrowed Hot Frog head and hands used Hot Frog's tint-ready art, so a tint coloured the frog and not the suit.
change: regenerated BusinessFrogTintBody/Arm.png with only the navy suit greyed (brightened so a multiply shows; vest, shirt, tie, outlines kept), uploaded (Arm 104979674458678, Body 102630969057264, both Green) and written by write_asset_ids.py; SkinAssets.part looks up Universal/Hot Frog parts untinted for skins in SUIT_ONLY_TINT (Business Frog), so the head, hands and eyes never carry Tinted; docs 08 and 17 updated (doc 17 also lists Shadow 1000). Commit 0f145e0
files: Sprites/Frogs/Business Frog/BusinessFrogTintBody.png, Sprites/Frogs/Business Frog/BusinessFrogTintArm.png, src/shared/SkinAssets.luau, docs/roblox-port/08-frog-skins-and-store.md, docs/roblox-port/17-status-and-known-gaps.md
test: stylua, selene, rojo build, luau_check clean; preview PNG of None/Mint/Gold/Berry/Shadow; Studio MCP playtest of Hot Frog
verified: yes — Business Frog on the menu wearing Mint, then Gold: client decals show the tint on Body and both limbs only (Tinted=true), head, hands, grab hands, eyes and eyelids Tinted=nil at 1,1,1; screenshots show gold/mint sleeves under a green frog head and hands; console clean; frog restored to untinted Business Frog
review: looks-right (sonnet) — prefix strips spaces so BusinessFrog matches, SpriteSkin clears a stale Tinted on re-skin, Hot Lawyer / Mystery silhouette / Blue art swap paths unchanged
leftover: none — the green vest panel is inside the Body sprite, so it still darkens under Berry/Shadow; documented in docs 08 and 17, and splitting it out needs new art beyond the ask (suit coloured, frog not)

## b-20261013-101813-o11q  fixed  2026-10-13 10:27
note: HUD shows "Best: 0" on the menu after joining, although the profile's highScore is 183 (leaderstats Best=183); it only corrects on the next score push
cause: the HUD Best label was set only from ScoreChanged, which the server pushes once on profile load, so a join where the client missed that push left the label at its initial "Best: 0".
change: GameClient keeps a monotonic bestShown, the max of the profile's highScore (early ProfileChanged push and GetProfile pull, as in the b-20260921-112735-t2ly Flys fix) and any ScoreChanged best, and builds the label from it. Commit c021481
files: src/client/GameClient.client.luau
test: stylua, selene, rojo build, luau_check clean; Studio MCP playtests of Hot Frog
verified: yes — three fresh Studio joins each read "Best: 183" from the first sample (t=3.5 to 5.4 s) with leaderstats Best 183; a 6-grab Classic run kept "Best: 183" at score 9; console clean. The original miss was intermittent (1 in 3), so the fix is shown by the profile path now feeding the label, not by catching a miss
review: looks-right (sonnet) — ScoreChanged's best is bestOf = profile.highScore (steps), so max mixes one quantity; highScore never decreases at runtime and the save merge takes the max
leftover: none

## b-20261013-163505-y6c5  fixed  2026-10-15 10:05
note: don't speed up the "grab pull" speed when combos increase, just the speed that steps move on screen
cause: GrabStep divided PullMath.pullTime by the combo multiplier, shortening each grab pull while the streak grew.
change: GrabStep now uses the normal distance-based pull time at every combo; moving step behaviors and Classic idle scroll still use StreakSpeed. Updated the tuning comment and port design record.
files: src/server/GameServer.server.luau, src/shared/Config.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check on touched Luau files, selene src/ (0 errors), Windows luau-lsp analyze on touched Luau files, rojo build (all pass); bash tools/luau_check.sh could not find the analyzer in WSL, so the installed Windows analyzer was run directly
verified: no — no HotFrog Studio is attached; Roblox_Studio lists Centralia (Staging) only, so a live high-streak grab was not run
review: none
owed: o-20261015-100656-nw90 (open Hot Frog in Roblox Studio; re-owed after the earlier step was marked done while its check still failed)
leftover: playtest high-streak grab timing and moving-step/Classic drift speed, filed as b-20261015-100504-gauh after HotFrog Studio opens

## b-20261013-163534-ogsq  fixed  2026-10-16 12:05
note: arm shouldn't appear in front of the steps
cause: Ruling b-20261015-100802-a17l: "the gripping hand should stay in front while the arm is behind". The menu attract ladder rungs sat at Z -0.2 (WorldConfig.ATTRACT_ANCHOR_OFFSET), the same depth as the frog's arm parts (-0.2), so the arm tied with the rung and drew over it (the screenshot is the menu). Gameplay steps were already at Z 0, behind which the arm sits.
change: ATTRACT_ANCHOR_OFFSET is now (0, 0, 0), so attract rungs sit on the gameplay plane like real steps: arm -0.2 < rung 0 < hand +0.3. Doc 17's arm/hand draw-order row states the ruling. Hand order, FrogModel and posing unchanged.
files: src/shared/WorldConfig.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check src/shared/WorldConfig.luau, selene src/ (0 errors, 0 warnings), bash tools/luau_check.sh src/shared/WorldConfig.luau, rojo build default.project.json (all pass)
verified: no — Rojo is serving Scare and Studio is not open on Hot Frog, so no menu Play check could run; depth order is from the model JSON and GameServer posing code only
review: looks-right; checked: git diff of both files, grep of ATTRACT_ANCHOR_OFFSET (one use, GameServer buildAttract; rungs CanQuery=false, attractClimb keeps rung Z), FrogModel.model.json part Z offsets (head -0.3, body art -0.25, arms -0.2, hands +0.3), GameServer held-limb pose keeps f.pos.Z = Config.PLANE_Z, the screenshot. Minor: the comment near GameServer.server.luau:1707 still says the menu rungs sit at -0.2 (stale, harmless)
owed: o-20261016-120554-lf1c (switch rojo serve to hotfrog and open Hot Frog in Studio)
leftover: Studio check of the menu ladder and a held step, filed as b-20261016-120513-ye6k (waits on the owed Rojo/Studio check)

## b-20261015-100802-a17l  answered  2026-10-16 12:05
note: DECISION: the gripping hand should stay in front while the arm is behind
cause: The user's ruling on question b-20261013-163534-ogsq.
change: see b-20261013-163534-ogsq
files: none
test: none
verified: see b-20261013-163534-ogsq
review: n/a

## b-20261016-121230-7m2r  fixed  2026-10-16 12:25
note: Rojo/Studio checks failed with several Studios and Rojo servers open: rojo-check read port 34872 (Scare) since default.project.json had no servePort, and the Studio title check's -match printed the matching title instead of True when two Studios were open
cause: The owed done-checks used bugloop's rojo-check. It probes only servePort or 34872, so with no servePort set it read Scare's server on 34872 while hotfrog's ran on 34873. Rojo's port changes from day to day, so pinning servePort is no fix. The Studio title check ran PowerShell's -match on an array of window titles. That returns the matching titles, not True, so its grep for True never passed with two or more Studios open.
change: New tools/studio_ready.sh. It lists every port a rojo process listens on (Get-NetTCPConnection filtered by process name) and asks each one's /api/rojo which project it serves. The match against this project's name from default.project.json is anchored by the MessagePack fixstr length byte, so "hotfrog-roblox-2" and "hotfrog-roblo" do not match. It then greps all Studio window titles for "Hot Frog" and prints the Rojo port; --rojo-only skips the Studio part. It exits 1 with a reason when no project name is found, no rojo serves it, or no Studio window matches. The waiting checks x9l1 and 8v9c and owed steps t6n4 and 4rse use it. The shared rojo-check fix is filed on the bugloop list as b-20261016-121400-gm51.
files: tools/studio_ready.sh
test: Live run against Rojo on 34871/34872 (Scare), 34873 (hotfrog-roblox) and 34875 (Tactics), with the Hot Frog, Tactics and Centralia Studios open: exit 0, printing 34873, in both modes. The negative patterns "hotfrog-roblo" and "hotfrog-roblox-2" do not match 34873's response.
verified: yes — the live run above against the running Rojo servers and Studio windows
review: concern — the unanchored substring match accepted a project whose name contains ours; checked: tools/studio_ready.sh, a live run
re-review: looks-right; checked: a bash -x trace (PAT is the 0xae byte then hotfrog-roblox), the bytes of 34873's response (ae before the name), behaviour with no rojo running or no PowerShell, set -u. Minor: an empty NAME would match any empty string, so a guard was added and the script re-run (exit 0, 34873)

## b-20261016-121351-x9l1  fixed  2026-10-16 12:25
note: Playtest combo at high streak: grab pulls keep the same duration while moving steps and Classic idle scroll speed up (re-filed from b-20261015-100504-gauh; check now finds Rojo on any port and Hot Frog among several Studios)
cause: Studio playtest check of the b-20261013-163505-y6c5 fix. No defect found.
change: none (verification only)
files: none
test: Studio MCP Play test of Hot Frog (placeId 114911935371092), 2026-10-16 12:25. The Edit DataModel held the current source (WorldConfig ATTRACT_ANCHOR_OFFSET (0,0,0)). A client bot fired StartRun("Classic") and GrabStep with centred taps. It logged each published pull (PullTime, PullDelta, PullLinear, StreakSpeed) against PullMath.pullTime(|delta|). A second bot climbed to Kitchen at 4x, then switched to off-centre (OK) taps so the streak ran out while the frog lived. Two AUTO warnings filed during Play (b-20261016-121810-4vvi, b-20261016-121810-5kpu) are queued separately.
verified: yes — In the Studio Play run, all 67 grab pulls took exactly the unscaled PullMath.pullTime at every streak speed from 1.0 to 4.0x. That includes pulls above the clamp: 16.45 studs took 0.411 s at 4x, where the old divide would give 0.103 s. Classic drift chunks went from 4.1 studs/s at 1.3x to 14.8 studs/s at 4x. BobRock moved 10.9–13.4 studs/s relative to the field at 4x against 0.67 at 1x; a bobbing step's speed varies with its phase, so that comparison is indicative.
review: n/a
studio: Hot Frog (placeId 114911935371092)

## b-20261016-121351-8v9c  fixed  2026-10-16 12:25
note: Studio check on the Menu attract ladder: frog arm draws behind the rung, gripping hand in front (ATTRACT_ANCHOR_OFFSET z 0); also glance at a held step in Playing (re-filed from b-20261016-120513-ye6k; check now finds Rojo on any port and Hot Frog among several Studios)
cause: Studio Play check of the b-20261013-163534-ogsq fix. No defect found.
change: none (verification only)
files: none
test: Studio MCP Play test of Hot Frog (placeId 114911935371092), 2026-10-16 12:25. The camera sits at (0,0,43.2) looking along -Z, so a larger Z draws nearer. Server part Z on the Menu: Left/RightArm -0.20, Left/RightHand(+Grab) 0.30, AttractStep 0.00. For the screenshots the client ScreenGuis were hidden briefly and then restored; the Daily Streak popup was left uncollected. A Normal run then grabbed one Carrot (Z 0.00) for the held-step view.
verified: yes — In the Studio Play run, both menu rungs show the green fingers over the red rung, with the navy arm passing behind it. In Playing, the hand closes over the held carrot and the arm runs behind both carrots.
review: n/a
studio: Hot Frog (placeId 114911935371092)

## b-20261016-121550-awo6  fixed  2026-10-16 12:25
note: update rojo version to 7.7.1
cause: The repo already pins rojo-rbx/rojo@7.7.1 in rokit.toml, and the rojo CLI and all four running servers report 7.7.1. Only the Studio Rojo plugin (%LOCALAPPDATA%/Roblox/Plugins/RojoManagedPlugin.rbxm, read from its Version StringValue) was still on 7.7.0, installed Jul 6.
change: Ran rojo plugin install with the pinned 7.7.1 CLI, and the plugin's Version value now reads 7.7.1. The old plugin is backed up outside the Plugins folder as %LOCALAPPDATA%/Roblox/RojoManagedPlugin-7.7.0.rbxm.bak. No repo file changed.
files: none (machine-local Studio plugin)
test: rojo --version prints Rojo 7.7.1. /api/rojo on 34871–34875 reports serverVersion 7.7.1. The installed plugin's Version value is 7.7.1.
verified: yes — The plugin file is now 7.7.1, and the Hot Frog Studio stayed synced (its Edit DataModel matched the source afterwards). After the user restarted the Studios (o-20261016-122443-w0p4, done 12:28), the Hot Frog Studio's PluginGuiService holds the dock widget "Rojo 7.7.1" (read through the Studio MCP at 12:40).
review: n/a
owed: o-20261016-122443-w0p4 (restart the open Studios so they load the 7.7.1 Rojo plugin)
leftover: none — the owed restart is done and the loaded plugin was read as 7.7.1

## b-20261015-100504-gauh  duplicate  2026-10-16 12:25
note: Playtest combo at high streak: grab pulls keep the same duration while moving steps and Classic idle scroll speed up
cause: Superseded by b-20261016-121351-x9l1. That item was re-filed because this one's check could never pass with several Studios open or with Rojo on another port.
change: see b-20261016-121351-x9l1
files: none
test: none
verified: see b-20261016-121351-x9l1
review: n/a

## b-20261016-120513-ye6k  duplicate  2026-10-16 12:25
note: Studio check on the Menu attract ladder: frog arm draws behind the rung, gripping hand in front (ATTRACT_ANCHOR_OFFSET z 0); also glance at a held step in Playing
cause: Superseded by b-20261016-121351-8v9c. That item was re-filed because this one's check could never pass with several Studios open or with Rojo on another port.
change: see b-20261016-121351-8v9c
files: none
test: none
verified: see b-20261016-121351-8v9c
review: n/a

## b-20261016-121230-8dsf  duplicate  2026-10-16 12:25
note: Playtest combo at high streak: grab pulls keep the same duration while moving steps and Classic idle scroll speed up (re-filed from b-20261015-100504-gauh with a check that works with several Studios open)
cause: Superseded by b-20261016-121351-x9l1. That item was re-filed because this one's check (bugloop rojo-check) could never pass with Rojo on another port.
change: see b-20261016-121351-x9l1
files: none
test: none
verified: see b-20261016-121351-x9l1
review: n/a

## b-20261016-121231-erz7  duplicate  2026-10-16 12:25
note: Studio check on the Menu attract ladder: frog arm draws behind the rung, gripping hand in front (ATTRACT_ANCHOR_OFFSET z 0); also glance at a held step in Playing (re-filed from b-20261016-120513-ye6k with a check that works with several Studios open)
cause: Superseded by b-20261016-121351-8v9c. That item was re-filed because this one's check (bugloop rojo-check) could never pass with Rojo on another port.
change: see b-20261016-121351-8v9c
files: none
test: none
verified: see b-20261016-121351-8v9c
review: n/a

## b-20261016-121810-4vvi  ignored  2026-10-16 12:28
note: AUTO warning (server): ContentId: rbxassetid://203785492 failed due to: Asset type does not match requested type
cause: Not a game asset. No file in the repo mentions 203785492, and a scan of every instance in the Hot Frog Edit DataModel (1957 instances, all texture/image/sound/mesh/animation/sky properties and attributes) found no reference to it. The warning came from the engine or an avatar load during the Studio Play run, not from game code.
change: Added "rbxassetid://203785492" to autoReport.ignore in bugloop/Config.luau so it is not filed again.
files: bugloop/Config.luau
test: grep of the repo; Studio MCP scan of the Edit DataModel; stylua, selene and luau_check on bugloop/Config.luau pass
verified: n/a (ignored)
review: n/a

## b-20261016-121810-5kpu  ignored  2026-10-16 12:28
note: AUTO warning (client:FrequencyGames): [UIBlox - Warning] - FoundationProvider not found
cause: Roblox's own UI warning. The stack is entirely CorePackages (UIBlox AppStyleProvider under ReactReconciler); no game script is involved.
change: Added "FoundationProvider not found" to autoReport.ignore in bugloop/Config.luau.
files: bugloop/Config.luau
test: stylua, selene and luau_check on bugloop/Config.luau pass
verified: n/a (ignored)
review: n/a

## b-20261016-122217-31q0  fixed  2026-10-16 12:35
note: players shouldn't be able to play when the daily streak modal is open. clicking behind the modal should just "collect" on the modal
cause: The Daily Streak overlay in src/client/MenuClient.client.luau was a full-screen TextButton with no handler, so a click behind the card did nothing. Nothing stopped requestStart() or the queued pendingStart from firing StartRun while the popup was up (popupOpen was declared after them), so a gamepad-selected Play could still start a run under it.
change: Collect's body is now close(), wired to both the Collect button and the overlay, so a click anywhere behind the card collects. The card gets an invisible Backstop TextButton under its contents, because an Active Frame does not stop the overlay button beneath it from firing (seen in Studio). popupOpen moved up; requestStart() and the pendingStart consumer return while it is set. checkDaily shows the popup unless the state is Playing (not only Menu, since Home can show the menu while the server still says Dead), so a claim that lands after a run started never covers the run.
files: src/client/MenuClient.client.luau
test: stylua --check, selene src/, bash tools/luau_check.sh src/client/MenuClient.client.luau and rojo build all pass. Studio MCP Play test of Hot Frog (placeId 114911935371092): the server's ClaimDailyReward was stubbed in the Play session only (granted, streak 3, nothing paid or saved), and the popup was reopened via Settings -> Close. Clicks on the card's empty areas left it open. A click on the part of Play showing behind the dim layer collected it and the lane stayed Menu. Collect closed it, and Play afterwards started a run (Playing).
verified: yes — the Studio Play run above, with a screenshot of the popup over the menu
review: concern — a granted popup was dropped if the claim returned while the state was still Dead after Home; fixed by skipping only during Playing. Studio then showed the reviewer's assumption that panel.Active sinks clicks was wrong; replaced with the Backstop button and re-tested.
studio: Hot Frog (placeId 114911935371092)
re-review: concern — a start queued while Dead (pendingStart) is neither fired nor cleared when Menu arrives under the popup, so it auto-starts a run at the next Dead->Menu; narrow race, filed as b-20261016-124204-f68f; the rest of the repair holds (the Playing-only guard, both start paths blocked, the Backstop under Collect at Z0, popupOpen always cleared); checked: git show 527d847, MenuClient lines 395-610 and 1000-1215, UIKit.panel and ZIndexBehavior.Sibling, a grep of src/ for StartRun/ReplayTutorial and client KeyCode/Activated bindings
followups: b-20261016-124204-f68f

## b-20261016-123559-s03q  fixed  2026-10-16 12:44
note: Gift and Shop buttons (StoreUI, DisplayOrder 5 like MenuGui) draw undimmed over the Daily Streak popup's dim overlay and may take clicks while it is up
cause: StoreGui (Gift/Shop, src/client/StoreUI.client.luau:79) and MenuGui both had DisplayOrder 5, so the Daily Streak popup, a child of MenuGui, did not reliably sit above Gift/Shop, and they drew bright over its dim overlay.
change: showDailyPopup in src/client/MenuClient.client.luau sets MenuGui's DisplayOrder to 10 while the popup is open, and close() restores it to 5. StoreGui stays at 5, so the Shop/Gift panels still draw over the menu when no popup is up. The b-20261016-122217-31q0 mechanics (overlay collect, Backstop, popupOpen guard) are unchanged.
files: src/client/MenuClient.client.luau
test: stylua --check src/client/MenuClient.client.luau, selene src/ (0 warnings), bash tools/luau_check.sh src/client/MenuClient.client.luau and rojo build all pass
verified: yes — In a Studio Play run of Hot Frog, ClaimDailyReward was stubbed on the Server in the Play session only, and the popup was reopened via Settings -> Close. MenuGui DisplayOrder read 10 against StoreGui's 5. A screen capture showed Gift/Shop dimmed under the overlay. A click on the Gift button collected the popup, restored DisplayOrder 5 and did not open the gift panel. A card click kept the popup open. Collect closed it, and Play then started a run. Shop was not clicked separately.
review: looks-right; checked: the diff; every DisplayOrder and ScreenGui in src, bugloop and default.project.json (MenuGui 5 set once at MenuClient:72, StoreUI 5, PotAtmosphere -5, WorldBackdrop flash 100, F8 reporter 1000); the close paths (one guarded close(), ResetOnSpawn false, no start while popupOpen); bash tools/luau_check.sh on MenuClient (exit 0)
studio: Hot Frog (placeId 114911935371092)

## b-20261016-124422-fbuz  answered  2026-10-16 12:46
note: brainstorm ways to "theme" this game for Halloween
finding: There are 12 Halloween ideas in .bugs/reports/b-20261016-124422-fbuz.md, each costed S/M/L and marked as a client-only cosmetic or a change that needs your call. The recommended first 3 for the days before Oct 31: (1) a mood pass of spooky lava, a night/moon palette and a colour grade, config and tints only (S, no art); (2) pumpkin, ghost and bat scenery through SceneryKinds (M), the biggest visual payoff and the longest art lead time, so start it early; (3) a Halloween music track and one stinger (M). A limited skin or tint, a Fly bonus window and catchable bats change the economy and wait on your ruling. All the ideas can share the costume's date window (b-20261016-123058-9thf) through one helper.
evidence: .bugs/README.md, CLAUDE.md, src/shared/WorldConfig.luau, SceneryKinds.luau, StepKinds.luau, Config.luau, SkinCatalog.luau, SkinTints.luau, Levels.luau, SoundAssets.luau, src/server/BugService.server.luau, src/server/DailyService.server.luau, src/client/Music.client.luau, WorldLava, WorldBugs, PotAtmosphere, tools/README.md, docs/roblox-port/17-status-and-known-gaps.md
report: .bugs/reports/b-20261016-124422-fbuz.md
files: none
review: n/a (analysis)
followups: none — you pick what to build; file a pick on the dashboard

## b-20261016-124204-f68f  fixed  2026-10-16 12:52
note: A start queued while Dead (pendingStart) survives the Daily Streak popup and auto-starts a run at the next Dead->Menu
cause: showDailyPopup left pendingStart set, so a Play/Replay queued while the lane was Dead survived the popup (the Menu handler only skips it with "pendingStart and not popupOpen") and fired StartRun at the next Dead->Menu. This was the re-review concern on b-20261016-122217-31q0.
change: showDailyPopup in src/client/MenuClient.client.luau clears pendingStart right after setting popupOpen, so the popup cancels a queued start and the player presses Play again after collecting. requestStart already returns while the popup is open, so the flag cannot be set again under it.
files: src/client/MenuClient.client.luau
test: stylua --check src/client/MenuClient.client.luau, selene src/ (0 warnings), bash tools/luau_check.sh src/client/MenuClient.client.luau and rojo build all pass
verified: yes — In a Studio Play run of Hot Frog (orchestrator), the edit was in the Edit DataModel and ClaimDailyReward was stubbed on the Server in the Play session only (granted, 8 s delay). The run: Home on the end panel (claim in flight), a client-only RunStateChanged "Dead" from the server, then a real Replay click, which queued pendingStart. The popup then opened over EndOfRun (MenuGui DisplayOrder 10), a "Menu" fired under it, an overlay click collected it, and a fake Dead->Menu followed. StartRun fired 0 times, where the old code would have started a run there (the lane's real state was Menu, so a start would have gone through). Replay then started a run (1 StartRun, state Playing). The fixer's own run was inconclusive and is not counted.
review: looks-right; checked: every pendingStart read and write (lines 399, 554-555, 603, 610, 1012), the Menu branch under the popup in both cases, close() cleanup (overlay+Backstop destroyed, popupOpen cleared, DisplayOrder 5), bash tools/luau_check.sh on MenuClient (clean)
studio: Hot Frog (placeId 114911935371092)

## b-20261016-123058-9thf  fixed  2026-10-16 12:56
note: add halloween themed costuming to the default frog skin to go live during Halloween
cause: Feature request: there was no seasonal costume, and nothing in the port gated content by date.
change: New art, Sprites/Frogs/Hot Frog/HotFrogHalloweenHat.png (a purple witch hat with an orange band), uploaded through the pipeline (--keys HotFrogHalloweenHat; Approved), with its generated id line in src/shared/SkinAssets.luau. src/shared/Config.luau adds HALLOWEEN_START (Oct 24) and HALLOWEEN_END (Nov 1), UTC and inclusive, recurring every year. src/shared/SpriteSkin.luau adds SpriteSkin.halloweenLive(), true inside the window or when workspace attribute ForceHalloween is true. In apply, a Hot Frog or Blue Frog rig with no Accessory art of its own wears the hat while it is live. Skins with their own accessory (Hawt, Space) keep it. src/server/SkinService.server.luau re-dresses every live frog when ForceHalloween changes and from one 60 s loop that notices the window opening or closing. Doc 17 has a new deviation row.
files: Sprites/Frogs/Hot Frog/HotFrogHalloweenHat.png, src/shared/SkinAssets.luau, src/shared/Config.luau, src/shared/SpriteSkin.luau, src/server/SkinService.server.luau, docs/roblox-port/17-status-and-known-gaps.md
test: bash tools/luau_check.sh on the three source files (rc 0), selene src/ (0 warnings), stylua --check on the three files (rc 0)
verified: yes — In a Studio Play run of Hot Frog (orchestrator), with ForceHalloween true the server rig dressed as Hot Frog got Head.Accessory = rbxassetid://87049410219713 (Decal, Transparency 0), and a screen capture showed the purple witch hat on the frog's head. With ForceHalloween false, the Accessory was empty again. The test player wears Business Frog (selected 6), which stayed bare under the force, as intended. Hot Frog was dressed by calling SpriteSkin.apply directly, because the test profile does not wear Hot Frog and the real DataStore must not be written. reskinFrog uses the same apply call, so the profile path was not exercised on its own.
review: looks-right; checked: the date logic (month*100+day, 1024..1101 inclusive, UTC, no year term), every SpriteSkin.apply caller (StoreUI preview, GameServer frog creation, reskinFrog) and that the world scripts never touch the Accessory decal, the Accessory fallback chain per skin, the single 60 s loop, the generated SkinAssets line, the doc 17 row; luau_check, selene and stylua on the files
studio: Hot Frog (placeId 114911935371092)
owed: o-20261016-125533-0z6s (a taste check of the hat art)

## b-20261016-125104-47tv  ignored  2026-10-16 12:59
note: AUTO error (server): MenuGui is not a valid member of PlayerGui "Players.FrequencyGames.PlayerGui"
cause: Not a game bug. The only stack frame is "AssistantCommand, line 9", a Studio MCP execute_luau probe from a fixer in the earlier tick that indexed PlayerGui.MenuGui from the Server datamodel, where the client PlayerGui is not visible. No game script was involved. bugloop/Config.luau already ignores "AssistantCommand", but the reporter matches ignore patterns against the message only, never the trace, so this probe got through. That limitation is filed on the bugloop list as b-20261016-125903-7q4h.
change: none
files: none
test: none
verified: n/a — no game code involved
review: n/a

## b-20261016-125437-ik3j  ignored  2026-10-16 12:59
note: AUTO warning (server): ContentId: rbxassetid://87049410219713 failed due to: Asset content representation is being generated
cause: Not a game bug. 87049410219713 is the witch hat (HotFrogHalloweenHat, b-20261016-123058-9thf), uploaded minutes before that Play session, and Roblox was still processing it. In a later Play run of the same session the hat loaded and rendered on Hot Frog's head (screen capture). Every new upload will show this once.
change: Added "Asset content representation is being generated" to autoReport.ignore in bugloop/Config.luau, so a freshly uploaded asset still processing is not filed.
files: bugloop/Config.luau
test: bash tools/luau_check.sh bugloop/Config.luau (rc 0)
verified: yes — the same asset rendered in the later Studio Play run recorded on b-20261016-123058-9thf
review: none
studio: Hot Frog (placeId 114911935371092)

## b-20261016-130320-ce9u  answered  2026-10-16 13:05
note: looks good. make sure its layer is in front of the frog's head (sent back from owed step o-20261016-125533-0z6s, reopens b-20261016-123058-9thf)
finding: The hat already draws in front of the whole head, so nothing changed. Its Accessory decal sits on the Head part with ZIndex 6, the highest of the head's decals: Head art 0, Mouth 1, Sclera 2, Eyes 3, Pupils 4, every eyelid including blinks 5 (src/assets/FrogModel.model.json:18-42). The store preview builds from the same FrogModel template (src/client/StoreUI.client.luau:183), so it layers the same. The Studio Play screen capture from b-20261016-123058-9thf shows the brim over the head and the tops of the eyes. The only things drawn over the hat are parts that sit nearer the camera than the head (Head z -0.3): a step the frog holds (z 0) and the hands (z 0.3). That is the same depth order as the rest of the frog and the attract ladder (b-20261016-121351-8v9c).
evidence: src/assets/FrogModel.model.json, src/client/StoreUI.client.luau, Studio screen capture recorded on b-20261016-123058-9thf
report: none
files: none
review: n/a
followups: none

## b-20261016-125004-mog8  fixed  2026-10-16 13:17
note: let's do 2, 3, 4, 8 (vampire frog but sold forever), 10 (reopens b-20261016-124422-fbuz)
cause: Feature request: the owner picked five ideas from the Halloween brainstorm b-20261016-124422-fbuz. They were 2 (night sky), 3 (Halloween scenery), 4 (pumpkin steps), 8 (a Vampire Frog skin, sold forever) and 10 (bats, built as the cosmetic version).
change: Three fixers worked on disjoint files, and the art uploads were serialized.
(2+4) src/client/WorldBackdrop.client.luau forces a violet-black sky on every level while SpriteSkin.halloweenLive() and tints the Sun pale blue-white as a moon. It re-applies on ForceHalloween and on a 60 s recheck. src/server/GameServer.server.luau acquireStep tints step kinds that have no colour of their own (Potato and WrappedRock pumpkin, CrumblyRock candy-corn yellow, WhiteRock cream). Kinds with their own tint keep it.
(3+10) There is new art, Sprites/Scenery/{JackOLantern,Ghost,Cobweb,Bat}.png. src/shared/SceneryKinds.luau adds the four kinds and halloweenSpawners. src/client/WorldScenery.client.luau appends them to every level's spawners, Menu included, while live, and fades them out when the window shuts. A tap flares a lantern or wobbles a ghost. The new src/client/WorldBatSwarm.client.luau flies a flock of 7 to 11 client-only bats across the local lane every 25 to 45 s.
(8) There are 35 new PNGs in Sprites/Frogs/Vampire Frog/: a pale grey-green recolour of Hot Frog's parts plus tint copies, with a cape, collar, medallion, widow's-peak hair, fangs and red pupils. src/shared/SkinCatalog.luau adds [10] Vampire Frog at 1000 Flys, with no Game Pass and no date window. src/client/StoreUI.client.luau pages skins by Fly price, then id, so Vampire sits between Space Frog (500) and Business Frog (1500).
All 39 images went through the pipeline (Approved), and src/shared/SkinAssets.luau carries their generated ids. Doc 17 has three new deviation rows.
files: src/client/WorldBackdrop.client.luau, src/server/GameServer.server.luau, src/shared/SceneryKinds.luau, src/client/WorldScenery.client.luau, src/client/WorldBatSwarm.client.luau, src/shared/SkinCatalog.luau, src/client/StoreUI.client.luau, src/shared/SkinAssets.luau, Sprites/Scenery/JackOLantern.png, Sprites/Scenery/Ghost.png, Sprites/Scenery/Cobweb.png, Sprites/Scenery/Bat.png, Sprites/Frogs/Vampire Frog/ (35 PNGs), docs/roblox-port/17-status-and-known-gaps.md
test: Orchestrator checks: stylua --check on the 8 touched .luau files (rc 0), selene src/ (0 warnings), bash tools/luau_check.sh on the 8 files (rc 0), and rojo build (ok). Each fixer also ran the same checks on its own files.
verified: yes — Studio Play run of Hot Frog (orchestrator), with ForceHalloween set on the server.
- Menu: per lane, Scenery_JackOLantern ×2, Ghost ×3 and Cobweb ×2 appeared with Decal textures. workspace.HalloweenBats filled with 10 Bat parts (texture rbxassetid://135982258968890) sweeping the lane. A screen capture showed the dark violet sky, the pale moon, ghosts, a cobweb, lanterns and bats.
- Vampire Frog: SpriteSkin.apply(Frog_4272203669, "Vampire Frog") set Body, Head, Mouth, Pupil and Eyelid decals to the VampireFrog* ids, and the Accessory was blank. A capture showed the pale frog with red pupils, black hair, a fang, the red-lined cape and the medallion.
- Shop > Frogs, paged with real mouse clicks: Business Frog, then Prev to Vampire Frog ("Locked — 1000 Flys", "Buy (1000)", no Robux button), then Prev to Space Frog ("Locked — 500 Flys").
- A Normal run (client grab bot, 49 grabs, Pot): new Potato steps wore Art Color3 (1, 0.55, 0.12), while Carrot, the arrows and Lillipad stayed white.
- ForceHalloween false: within 5 s no Halloween scenery was visible, HalloweenBats was empty, and the frog went back to its profile skin. A Potato acquired while live kept its orange until reacquired, as doc 17 says.
- The Output showed no game-script errors, only "Asset content representation is being generated" for the freshly uploaded art (already ignored by autoReport).
studio: Hot Frog (placeId 114911935371092)
review: Three sonnet reviews, all looks-right.
- Sky and steps: checked the git diff of both files, SpriteSkin.halloweenLive, the backdrop restore path when off (palette colour, white Texture, original Sun colour and decal), Pot heat layered on the tinted base, the flip handler on ForceHalloween plus the 60 s recheck, StepKinds' own-colour kinds, and luau_check on both files (rc 0).
- Scenery and bats: checked the SceneryKinds and WorldScenery diffs, WorldBatSwarm in full, the flip on/off path (no duplicates, fade-out releases to the pool), the local-lane-only bats, the Include-filtered tap raycast that does not swallow step taps, and luau_check on the 3 files.
- Vampire Frog: checked the SkinCatalog, StoreUI and SkinAssets diffs, every SkinCatalog consumer (pairs/keyed only, BuyWithFlys Fly-only, game-pass loops guarded), the StoreUI comparator (total order, existing order kept, hidden Mystery filtered), and the 35 SkinAssets keys (all non-zero) against Hot Frog's part list. Ran stylua, selene and luau_check.
owed: o-20261016-131548-yk5p (taste: the Halloween scenery art and bat size), o-20261016-131549-vd5d (taste: the Vampire Frog art)

## b-20261016-130741-9ms3  fixed  2026-10-16 13:20
note: Studio MCP probe errors (AssistantCommand) are still auto-filed (like b-20261016-125104-47tv) because the vendored BugReportService.luau matches autoReport.ignore only against the message. The bugloop template now also matches the stack trace (bugloop c4dabcc): run python ~/.claude/skills/bugloop/scripts/bugloop.py upgrade, run the luau check, and confirm in Studio that an execute_luau probe error is no longer filed (bugloop b-20261016-125903-7q4h)
cause: The vendored bugloop/server/BugReportService.luau predated bugloop c4dabcc. Its isIgnored matched the autoReport.ignore patterns only against the message. A probe error's message names the indexed member, and "AssistantCommand" appears only in its trace.
change: Ran bugloop.py upgrade, which replaced the unedited bugloop/server/BugReportService.luau with the current template. isIgnored now also matches each pattern (DEFAULT_IGNORE and Config's ignore list) against the trace. .bugs/installed.json records the new install. The other vendored files already matched the template.
files: bugloop/server/BugReportService.luau, .bugs/installed.json
test: bash tools/luau_check.sh bugloop/Config.luau bugloop/server/BugReportService.luau (rc 0)
verified: yes — In a Studio Play run of Hot Frog, a server execute_luau probe spawned a thread that indexed a missing PlayerGui child. LogService shows the MessageError "ProbeThatDoesNotExist2 is not a valid member of PlayerGui", whose trace is "Script 'AssistantCommand', Line 3". No "[BugReport] sent" line followed, and the inbox got no entry. Before the upgrade, the same kind of probe error was filed as b-20261016-125104-47tv.
review: looks-right (sonnet, on commit 77c514f, which covers both b-20261016-130741-9ms3 and b-20261016-131144-fgag); checked: git show 77c514f for bugloop/server/BugReportService.luau and bugloop/Config.luau, isIgnored and its call sites (trace typed string? and nil-guarded), the client BugReportClient has no ignore filter of its own (server is the single filter), "sabuiltin_Assistant" has no Lua pattern magic characters, the ^-anchored defaults are not broadened. Minor: a real error whose trace passes through an ignored name (GameDefs, AssistantCommand) would also be dropped; those names are only unrelated plugins and the MCP probe here
studio: Hot Frog (placeId 114911935371092)

## b-20261016-131144-fgag  ignored  2026-10-16 13:20
note: AUTO warning (client:FrequencyGames): [Roblox][sabuiltin_Assistant.rbxm.Assistant.Packages._Index.AssistantUI.AssistantUI.Actions.ExecuteLuauActions] The execute_luau changed camera type. Resetting from Enum.CameraType.Custom back to Enum.CameraType.Scriptable
cause: Not a game bug. The Studio MCP Assistant plugin printed this itself while the loop checked b-20261016-125004-mog8 in Studio: a client execute_luau probe had set the camera back to Custom after a screenshot, and the plugin reverts camera changes made by its probes. Neither its message nor its trace says "AssistantCommand", so the existing ignore pattern did not catch it.
change: bugloop/Config.luau ignores "sabuiltin_Assistant", the Assistant plugin's own path, so its warnings are no longer filed. Its comment says why.
files: bugloop/Config.luau
test: bash tools/luau_check.sh bugloop/Config.luau (rc 0)
verified: yes — In a Studio Play run of Hot Frog, client probes set CameraType to Scriptable and then Custom. The plugin printed the same "The execute_luau changed camera type. Resetting ..." warning, no "[BugReport] sent" line followed, and the inbox got no new entry.
review: looks-right (sonnet, on commit 77c514f, which covers both b-20261016-130741-9ms3 and b-20261016-131144-fgag); checked: git show 77c514f for bugloop/server/BugReportService.luau and bugloop/Config.luau, isIgnored and its call sites (trace typed string? and nil-guarded), the client BugReportClient has no ignore filter of its own (server is the single filter), "sabuiltin_Assistant" has no Lua pattern magic characters, the ^-anchored defaults are not broadened. Minor: a real error whose trace passes through an ignored name (GameDefs, AssistantCommand) would also be dropped; those names are only unrelated plugins and the MCP probe here
studio: Hot Frog (placeId 114911935371092)

## b-20261016-131805-8d2q  answered  2026-10-16 13:20
note: looks great (sent back from owed step o-20261016-131549-vd5d for b-20261016-125004-mog8: look at the Vampire Frog art on the frog and in Shop > Frogs)
cause: The owner's taste check of the Vampire Frog art from b-20261016-125004-mog8: they approved it.
change: none. Owed step o-20261016-131549-vd5d is closed with the user's "looks great" as its evidence.
files: .bugs/owed.md
test: none
verified: yes — the owner judged the art themselves ("looks great")
review: n/a

## b-20261016-131816-bw8k  answered  2026-10-16 13:20
note: I'll have to see these in game (sent back from owed step o-20261016-131548-yk5p for b-20261016-125004-mog8: look at the Halloween scenery art and the bat size in game)
cause: The owner wants to judge the jack-o'-lanterns, ghosts, cobwebs and bats in game before saying whether anything should change. Nothing is wrong yet, so there is nothing to fix.
change: none. The look stays theirs to do: it is re-owed as o-20261016-132035-06e5 (kind taste). That step says how to see it: live Oct 24 to Nov 1 UTC, or any time in Studio Play after running workspace:SetAttribute("ForceHalloween", true) in the server command bar. The old step o-20261016-131548-yk5p now says it was not judged yet.
files: .bugs/owed.md
test: none
verified: yes — the scenery and bats were already seen in a Studio Play run for b-20261016-125004-mog8; only the owner's taste call is left
review: n/a
owed: o-20261016-132035-06e5 (taste: the Halloween scenery and bat size in game)

## b-20261016-140421-iqp6  fixed  2026-10-16 17:38
note: Off doesn't make any sense. it should say "EQUIP" or even better, these buttons should have icons for people that don't speak english
cause: The store's tint swatches under a skin (screenshot: OFF, WORN, then prices) used the English words "Off" for the no-tint swatch and "Worn" for the worn one, so they didn't read without English.
change: In src/client/StoreUI.client.luau refreshStore, the worn swatch now shows a check mark "✓" and the no-tint swatch a "✕". Owned tints stay blank colour chips, unowned ones keep their Fly price, and the label colour still follows the swatch luminance.
files: src/client/StoreUI.client.luau
test: stylua --check (rc 0), selene src/ (0 warnings), bash tools/luau_check.sh src/client/StoreUI.client.luau (rc 0), rojo build (ok)
verified: no — the Hot Frog Studio was closed (list_roblox_studios showed only Tactics and Centralia), so nobody saw whether ✓ and ✕ render. FredokaOne probably lacks them, so they rely on Roblox's font fallback.
review: looks-right (sonnet; caveat: the glyphs depend on font fallback, about 75% sure they render); checked: git diff of StoreUI, the refreshStore swatch loop and makeSwatch, UIKit.FONT (FredokaOne), every swatch state (worn/unworn no-tint, worn/unworn owned tint, unowned priced), luminance colouring untouched, UTF-8 literals, luau_check and stylua rc 0. Noted that the "Wear"/"Buy"/"Selected"/"Locked" labels are still English, and the comment near line 143 still says "Off"
leftover: b-20261016-173812-ko2r (Studio check that the glyphs render, plus the stale comment; waits on tools/studio_ready.sh)
owed: none
note: the held check waits on o-20261016-173728-jewl (owed for b-20261016-140523-i34z: open the Hot Frog place in Studio)

## b-20261016-140523-i34z  blocked  2026-10-16 17:38
note: the potatos don't actually break on grabbing like the tips say
cause: Not found yet. By the code, the mechanic matches Unity and the tip. Potato uses StepBehaviors.CrumbleAfterRelease, which fires on ReleaseStep; Unity's Step.cs has releaseAction += Explode. Potatoes only spawn in the Pot, and the Halloween tint only colours Art.Color3. So either the release crumble fails at runtime or the owner expected a crumble on grab. Only a Play run can tell which.
change: none
files: none
test: code reading (Tips.luau, StepKinds, StepBehaviors, GameServer release path, Unity Entities/Step.cs), plus bugloop recall (no earlier potato fix)
verified: no — the Hot Frog Studio is closed (not in list_roblox_studios), so no Play run was possible
review: n/a
leftover: b-20261016-173812-0e40 (Studio Play check of releasing a potato in the Pot, then a fix or a question for the owner; waits on tools/studio_ready.sh)
owed: o-20261016-173728-jewl (open the Hot Frog place in Studio)

## b-20261016-140445-tnpd  fixed  2026-10-16 17:44
note: the hat accessory is too high and should be behind the frog's eyes (but in front of its head)
cause: The rig's Accessory decal is on the Head at ZIndex 6, above every eye layer (Sclera 2, Eyes 3, Pupils 4, eyelids 5). The hat art's brim ran across the tops of the eye bumps, so the hat sat high and drew over the eyes.
change: src/shared/SpriteSkin.luau apply drops the Accessory decal to ZIndex 1 only while it holds the Halloween hat, so the hat draws over the head art (0) and under the eyes. Every other skin gets back the template ZIndex, kept once in a BaseZIndex attribute, so Hawt Frog's and Space Frog's accessories are unchanged. The hat art (Sprites/Frogs/Hot Frog/HotFrogHalloweenHat.png) moved 50 px down, so the brim sits on top of the head between the eyes. It was re-uploaded through the pipeline (Approved, new id 79328124668745), and write_asset_ids.py wrote the id into src/shared/SkinAssets.luau. The doc 17 Halloween row is updated.
files: src/shared/SpriteSkin.luau, Sprites/Frogs/Hot Frog/HotFrogHalloweenHat.png, src/shared/SkinAssets.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check src/shared/SpriteSkin.luau (ok), selene src/ (0 warnings), bash tools/luau_check.sh src/shared/SpriteSkin.luau (rc 0), rojo build (ok), upload_to_roblox.py --status (HotFrogHalloweenHat Approved/Green). An offline PIL composite of the real Hot Frog parts in the new layer order showed the brim behind the eyes and over the head.
verified: no — the Hot Frog Studio was closed for the whole run (list_roblox_studios showed only Tactics and Centralia), so no Play run was made. The PIL composite is not a real-environment run.
review: looks-right (sonnet); checked: git diff of SpriteSkin, SkinAssets and doc 17, SpriteSkin.apply in full, the FrogModel decal list (Head, Mouth, Sclera, Eyes, Pupils, eyelids and Accessory are all on the Head part, Face Back, ZIndex 0-6), a grep of ZIndex/BaseZIndex/Accessory across src/, the restore path for ForceHalloween off and for switches to Hawt/Space or to no-accessory skins, BaseZIndex captured before any change, StoreUI previews go through the same apply, the SkinAssets diff is the one hat id line, luau_check and stylua rc 0, old vs new PNG by eye (brim about 50 px lower, darker burnt-orange band, olive-gold buckle, upper-left light)
leftover: b-20261016-174405-kgdg (Studio Play check of the hat layering, and that Hawt/Space accessories are unchanged; waits on tools/studio_ready.sh)
owed: o-20261016-174406-ubok (taste: the reworked hat), o-20261016-173728-jewl (open the Hot Frog place in Studio)
verified: yes — b-20261016-174405-kgdg's Studio Play run (2026-10-17) confirmed Accessory ZIndex 1 under the eye layers while the hat is worn and ZIndex 6 restored for Hawt/Space Frog, and the owner looked at the hat in game (o-20261016-174406-ubok) and asked only for it to sit lower (b-20261016-192055-4s1f). (Repair 2026-10-17 09:20.)
studio: Hot Frog (placeId: 114911935371092)

## b-20261016-140637-tqc4  fixed  2026-10-16 17:44
note: the shading of the witch hat looks a *little* off compared to teh shadong of the base frog. more darkness on the buckle and strap would help
cause: The hat art was flat-shaded, with a saturated orange band and a bright yellow buckle. The frog's art uses a soft gradient lit from the upper left that darkens toward the lower right, so the band and buckle read too bright next to it.
change: Sprites/Frogs/Hot Frog/HotFrogHalloweenHat.png now has a soft radial falloff lit from the upper left, up to about 22% darker. The band and buckle get extra shadow toward both ends and toward the brim, at about x0.92 and x0.85. Size and alpha are unchanged. It was re-uploaded with the same change as b-20261016-140445-tnpd (one commit, one new id 79328124668745).
files: Sprites/Frogs/Hot Frog/HotFrogHalloweenHat.png, src/shared/SkinAssets.luau
test: see b-20261016-140445-tnpd
verified: no — the Hot Frog Studio was closed, so the art was not seen in game. The reviewer compared the old and new PNGs by eye.
review: looks-right (sonnet); checked: git diff of SpriteSkin, SkinAssets and doc 17, SpriteSkin.apply in full, the FrogModel decal list (Head, Mouth, Sclera, Eyes, Pupils, eyelids and Accessory are all on the Head part, Face Back, ZIndex 0-6), a grep of ZIndex/BaseZIndex/Accessory across src/, the restore path for ForceHalloween off and for switches to Hawt/Space or to no-accessory skins, BaseZIndex captured before any change, StoreUI previews go through the same apply, the SkinAssets diff is the one hat id line, luau_check and stylua rc 0, old vs new PNG by eye (brim about 50 px lower, darker burnt-orange band, olive-gold buckle, upper-left light)
leftover: b-20261016-174405-kgdg (the same Studio check also captures the shading)
owed: o-20261016-174456-mgfb (taste: the band and buckle shading)
verified: yes — the owner looked at the reshaded hat in Studio and marked the shading step o-20261016-174456-mgfb done on the fleet dashboard (2026-10-16 19:20); asking only for the hat to sit lower (b-20261016-192055-4s1f). Added 2026-10-17 09:10 as a record repair.

## b-20261016-192055-4s1f  fixed  2026-10-17 09:10
note: lower on the head (sent back from owed step o-20261016-174406-ubok: look at the reworked witch hat on Hot Frog)
cause: The hat art's brim bottom sat at y=353 on the 1024 canvas, just touching the top of the head art at y=347, so the hat still floated on top of the head.
change: Sprites/Frogs/Hot Frog/HotFrogHalloweenHat.png moved another 50 px down (opaque bounds y 73-353 to 123-403; same size, shading and alpha), re-uploaded through the pipeline (Approved/Green), and write_asset_ids.py changed HotFrogHalloweenHat in src/shared/SkinAssets.luau from 79328124668745 to 134244929117907.
files: Sprites/Frogs/Hot Frog/HotFrogHalloweenHat.png, src/shared/SkinAssets.luau
test: stylua --check and bash tools/luau_check.sh src/shared/SkinAssets.luau rc 0, rojo build ok, upload 1 uploaded 0 failed; PIL composite before/after
verified: partly — Studio Play run (b-20261016-174405-kgdg's pass): with ForceHalloween on, Hot Frog's Accessory decal is ZIndex 1 with texture rbxassetid://134244929117907, which loaded (PreloadAsync Success, 1024x1024); a GUI rebuild of the head decals in their ZIndex order shows the brim at eye level with the eyes, sclera and lids over it. screen_capture showed no 3D in Play (white viewport), so the real 3D render was not seen.
review: looks-right (sonnet); checked: git diff of SkinAssets is the one id line with LF endings, tools/asset_ids.json has 134244929117907 Approved/Green, no src reference to the old id, PIL compare of HEAD vs working PNG (same 1024x1024, bbox shifted exactly 50 px down, pixel-identical after shift), stylua and luau_check rc 0
studio: Hot Frog (placeId: 114911935371092)
leftover: none
owed: o-20261017-091030-a91m (taste: the hat height)
verified: yes — the owner looked at the hat height and marked o-20261017-091030-a91m done on the fleet dashboard (2026-10-17 12:39)

## b-20261016-174405-kgdg  fixed  2026-10-17 09:10
note: Studio Play check of the witch hat (SpriteSkin Accessory ZIndex 1 while the hat is worn, art moved 50 px down and reshaded): Hot Frog hat under the eyes and over the head, Hawt Frog and Space Frog accessories still on top (ZIndex 6); reset ForceHalloween afterwards
cause: Check of b-20261016-140445-tnpd; no fault found.
change: none (the art moved again under b-20261016-192055-4s1f before this check ran)
files: none
test: Studio Play run
verified: partly — Studio Play run: Hot Frog Head decals were Head 0, Mouth 1, Accessory 1 (hat 134244929117907, loaded), Sclera 2, Eyes 3, Pupils 4, eyelids 5, BaseZIndex 6; switching on the server to Hawt Frog gave Accessory ZIndex 6 (texture 92072401896151, sunglasses on top), Space Frog ZIndex 6 (97689558432795, helmet on top), and back to Hot Frog ZIndex 1 with the hat restored. Layering judged from a GUI rebuild of the decals because screen_capture showed no 3D in Play. ForceHalloween was already true and was left true.
verified: yes — with the owner's own look in game: after b-20261016-140445-tnpd they viewed the hat on the frog in Studio (owed step o-20261016-174406-ubok, 2026-10-16 19:20) and asked only for it to sit lower (b-20261016-192055-4s1f), so the under-the-eyes layering was seen in 3D; this Play run confirms the same ZIndex layering and the Hawt/Space restore. (Repair 2026-10-17 09:20.)
review: n/a
studio: Hot Frog (placeId: 114911935371092)
leftover: none
owed: none
note: the new hat height is owed on b-20261016-192055-4s1f (o-20261017-091030-a91m)

## b-20261016-173812-ko2r  fixed  2026-10-17 09:13
note: Studio check for the store tint swatches: the worn swatch shows ✓ and the no-tint swatch ✕ (StoreUI refreshStore); if either glyph draws as a box or tofu in FredokaOne, replace it with a drawn shape or a glyph that renders; also fix the stale "Off" comment at StoreUI ~line 143
cause: FredokaOne has no tick or cross glyph, so Studio fell back to other fonts: "✓" drew as a tiny hairline and "✕" drew nothing; the heavy "✔"/"✖" are emoji glyphs in a fixed dark grey that ignores TextColor3 and would vanish on the near-black Shadow swatch (as in b-20261013-101145-cvni).
change: src/client/StoreUI.client.luau makeSwatch gives each swatch a drawn Tick and Cross (two rounded 4 px Frame bars each, under its Face at ZIndex 4, in the swatch's luminance-based label colour); refreshStore shows the Tick on the worn swatch and the Cross on the no-tint swatch when another tint is worn, with no text on owned swatches. The stale "Off" comment and the swatch-label comment now describe the marks.
files: src/client/StoreUI.client.luau
test: stylua --check (ok), selene src/ (0 warnings), bash tools/luau_check.sh src/client/StoreUI.client.luau (rc 0), rojo build (ok)
verified: yes — Studio Play run: Shop > Frogs on an owned skin showed a bold dark tick on the plain swatch with prices 400/600/800/1500/1000 intact; after wearing Teal, a bold dark cross on the plain swatch and a white tick on teal; worn tint set back to none afterwards.
review: looks-right (sonnet); checked: git diff of StoreUI, makeSwatch and refreshStore in full, UIKit.button, every swatch state sets both Visible flags each refresh (no stale marks), marks created once per swatch (no leak), ink colour from the same luminance test (white on Shadow), layering Face 2 / Label 3 / marks 4, geometry fits the 72x47 face, luau_check and stylua rc 0
studio: Hot Frog (placeId: 114911935371092)
leftover: none
owed: none

## b-20261016-192312-l1g5  fixed  2026-10-17 09:18
note: potatoes should shake when grabbed and explode after 1 second with big particle effect
cause: Potatoes used Unity's StepBehaviors.CrumbleAfterRelease, which only explodes on release; there was no break-on-grab behaviour, shake or blast. The owner's note answers b-20261016-173812-0e40's question (grab-crumble wanted).
change: New StepBehaviors.ExplodeAfterGrab, used by StepKinds.Potato: the first grab sets Unsteady and the server jitters the step (±Config.EXPLODE_SHAKE 0.25 studs); Config.EXPLODE_FUSE (1 s) after the grab ctx.blast() fires the new StepExploded RemoteEvent (GameServer remote list) to all clients with the step position, then ctx.explode() recycles the potato and knocks the holder off even while held; early release does not stop the fuse. Effects.client.luau draws a big pooled burst (28 tan chunks plus a 28-ball orange flash ring, WorldConfig.EXPLODE_*) on StepExploded. Potato tip, a Levels comment and a doc 17 deviation row updated; CrumbleAfterRelease stays but no kind uses it.
files: src/shared/StepBehaviors.luau, src/shared/StepKinds.luau, src/shared/Config.luau, src/shared/WorldConfig.luau, src/shared/Tips.luau, src/shared/Levels.luau, src/client/Effects.client.luau, src/server/GameServer.server.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check on all 8 .luau files (ok), selene src/ (0 warnings), bash tools/luau_check.sh on each (rc 0), rojo build (ok)
verified: yes — two Studio Play runs. First run: Unsteady 0.05 s after grab, step left Steps 1.05 s after grab while held, ForceRelease reached the client, tap-and-release still exploded; it also found the client blast never fired (Exploded attribute set in the same frame as Parent = nil), fixed by the StepExploded remote. Second run (after the fix): StepExploded reached the client 1.00 s after Unsteady with the potato's position, PotatoBlast parts 0 -> 56 -> cleaned up within ~0.9 s, tap-and-release also blasted, about 100 carrot/rock recycles and the death cleanups fired no StepExploded, no Effects/GameServer errors. Not observed: a run ending inside the 1 s fuse (no way to force it); the fuse is gated by ctx.stillValid() per the reviews. screen_capture shows no 3D in Play, so the burst was counted, not seen.
review: concern (sonnet): the client blast fired on any removal of a lit ExplodeAfterGrab step (run end, lane cleanup), not only on ctx.explode; checked: git diff of StepBehaviors/StepKinds/Config/WorldConfig/Levels/Effects, GameServer ctxOf/releaseStep/acquireStep/advanceStep/shownPosition, Effects watch/unwatch, stale-timer safety via stillValid generations, offset composition with STEP_OFFSET_MAX
re-review: looks-right (sonnet, twice: after the Exploded attribute repair and after the StepExploded remote repair); checked: diffs of StepBehaviors, Effects, GameServer, StepKinds, Config, WorldConfig, doc 17; remote created with ensureRemote in the top list and fetched with WaitForChild; blast gated by stillValid and only in the fuse; grep shows no Exploded attribute left; Ctx type and its single builder ctxOf provide blast; luau_check and stylua rc 0 on the three files
studio: Hot Frog (placeId: 114911935371092)
leftover: none
owed: none

## b-20261016-173812-0e40  fixed  2026-10-17 09:18
note: Studio Play check: in the Pot, grab a Potato step, then let go. Does it crumble? If not, fix the cause; if it does, ask the owner whether they want grab-crumble or a rewording of the tip
cause: The owner answered the question before the check ran (b-20261016-192312-l1g5: shake on grab, explode 1 s later), so potatoes now break on grab instead of Unity's crumble-on-release.
change: see b-20261016-192312-l1g5 (same commit)
files: src/shared/StepBehaviors.luau, src/shared/StepKinds.luau, src/shared/Config.luau, src/shared/WorldConfig.luau, src/shared/Tips.luau, src/shared/Levels.luau, src/client/Effects.client.luau, src/server/GameServer.server.luau, docs/roblox-port/17-status-and-known-gaps.md
test: see b-20261016-192312-l1g5
verified: yes — Studio Play run: grabbing a Potato in the Pot shakes it and it explodes 1.0 s later (held or released), with the client blast; details on b-20261016-192312-l1g5
review: see b-20261016-192312-l1g5
studio: Hot Frog (placeId: 114911935371092)
leftover: none
owed: none

## b-20261016-192144-g2e2  fixed  2026-10-17 09:30
note: Let's get rid of the jack o' lanterns and instead throw pumpkins into the mix as "steps"
cause: The jack-o'-lantern art existed only as floating Halloween scenery (SceneryKinds JackOLantern + HalloweenLanternSpawner); there was no pumpkin step kind, and the Halloween "pumpkin steps" were only an orange tint on Potato and WrappedRock.
change: New StepKinds.Pumpkin, a plain solid step (behavior "None") drawn with the existing JackOLantern sprite on Potato's canvas and grab box, in no spawner pool; while SpriteSkin.halloweenLive(), Lane.pickKind swaps Config.HALLOWEEN_PUMPKIN_CHANCE (0.25) of its weighted picks for a Pumpkin when the pick is not an arrow or a hazard, on Pot, Kitchen and Country (never in the Tutorial, whose tree grabs drive its no-death grace; intro sequences untouched). The JackOLantern scenery kind and its spawner are gone (ghosts, cobwebs, bats stay), and the orange Halloween tint on Potato/WrappedRock is dropped from GameServer HALLOWEEN_TINTS so there is one pumpkin look; candy-corn tints stay. Doc 17 Halloween rows updated.
files: src/shared/StepKinds.luau, src/server/Lane.luau, src/shared/Config.luau, src/server/GameServer.server.luau, src/shared/SceneryKinds.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check on the 5 .luau files (ok), selene src/ (0 warnings), bash tools/luau_check.sh (rc 0), rojo build (ok)
verified: yes — Studio Play run with ForceHalloween: a client grab bot climbed Pot into Kitchen (pull ~160 studs, score 35) grabbing 11 Pumpkins without shake, explode or death; pumpkins spawned in Pot and Kitchen with the JackOLantern decal (rbxassetid://100352976265966) at white colour, Behavior None, Unsteady false; no JackOLantern instances in the client workspace while ghosts were present; with ForceHalloween turned off, a fresh run of 46 grabs and 73 new step spawns had no Pumpkin; console showed only Roblox core UIBlox warnings. Not observed: the Tutorial guard at runtime (the test profile has the Tutorial done; the guard is one condition, checked by reading); screen_capture shows no 3D in Play, so the pumpkin art was checked by decal id, not seen.
review: concern (sonnet): the swap also caught Tutorial tree picks (no isArrow/hazard flag), which would drop the tree art and end the Tutorial grace on a pumpkin grab; checked: git diff of all 6 files, SpriteSkin.halloweenLive server-safe and live per pick, StepKinds consumers keyed on KindName (GameClient, WorldTouchIndicator, Chef), Behavior None valid, no leftover JackOLantern scenery or spawner references in src/, JackOLantern id non-zero, hazard ring unaffected, stylua/selene/luau_check clean
re-review: looks-right (orchestrator): the repair adds `self.levelIndex ~= Levels.TUTORIAL` to the swap condition and its comment; stylua, selene, luau_check rc 0 on Lane.luau
studio: Hot Frog (placeId: 114911935371092)
leftover: none
owed: none

## b-20261017-123801-td2q  fixed  2026-10-17 12:52
note: respawn should reload back to the main men[u]
cause: The avatar is the frog and GameServer loads no Roblox character, so Roblox's Esc -> Reset Character did nothing and left the player in the run. Read as the Reset button from the note ("respawn"); the screenshot does not show which control was pressed.
change: MenuClient sets StarterGui ResetButtonCallback (pcall retry) to a BindableEvent: while Playing it fires the new ReturnToMenu remote, otherwise it acts like Home (dismisses the end panel, shows the main menu). GameServer's Playing-only ReturnToMenu handler releases held steps, banks the score like a death, clears the lane, resets the run and frog, and sets RunState Menu, skipping the death beat and end panel.
files: src/server/GameServer.server.luau, src/client/MenuClient.client.luau
test: stylua --check, selene src/ (0 warnings), bash tools/luau_check.sh on both (rc 0), rojo build (ok)
verified: yes — Studio Play run: ReturnToMenu fired mid-run took RunState Playing -> Menu with MenuGui/MainMenu visible; the real Esc -> R -> Enter (Reset Character) mid-run did the same; after a death with the EndOfRun panel up, Esc -> Reset showed Title + MainMenu and hid EndOfRun; console showed only Roblox core UIBlox warnings.
review: looks-right (sonnet); checked: git diff of both files, setRunState, commitHighScore/resetScore, killFrog, forceTutorial and StartRun, clearLaneSteps/releaseStep, ctxOf stillValid, MenuClient 405-630, Profiles.recordPeriodScore, GameOver/RunStateChanged listeners; notes (non-blocking): Reset in Menu with Settings open shows MainMenu over it like Home does; Play within 1 s of an abort hits the existing StartRun cooldown like Replay
studio: Hot Frog (placeId: 114911935371092)
leftover: none
owed: none

## b-20261017-123916-esfu  fixed  2026-10-17 12:52
note: when a player in the tutorial has grabbed the first acorn the sparkles are supposed to move to the next acorn to show players how to play
cause: WorldTutorialSpecks aimed at the step nearest the frog's body; right after a grab that is the held acorn, so the sparkles stayed on it.
change: Each lane's specks keep a `grabbed` set of steps an extended limb has held (cleared on RunState change, pruned when a pooled step leaves the lane), and GrabTarget.nearestStep takes an optional `exclude` set, so the sparkles go to the next ungrabbed acorn and never back; once every step is grabbed they fly off (Unity's send-away), before any grab they still sit on the frog fallback. WorldFrogCosmetics' nearestStep call is unchanged.
files: src/client/WorldTutorialSpecks.client.luau, src/client/world/GrabTarget.luau
test: stylua --check on both (ok), selene src/ (0 warnings), bash tools/luau_check.sh on both plus WorldFrogCosmetics (rc 0), rojo build (ok)
verified: yes — Studio Play run (StartRun "Tutorial"): sparkle centroid 1.2 studs from acorn 1 before any grab; 0.5 from acorn 2 after grabbing acorn 1; 0.5 from acorn 3 after grabbing acorn 2 and releasing acorn 1 (no flip back); after grabbing acorn 3 the level went to Pot and the specks were torn down; console showed only Roblox core UIBlox warnings. screen_capture shows no 3D in Play, so positions were measured, not seen.
review: concern (sonnet): after releasing acorn 1 and holding acorn 2, the nearest-to-body pick could flip back to the released acorn; checked: GrabTarget.luau, the diff, WorldTutorialSpecks 90-160, Entities/SpeckManager.cs, Core/LevelManager.cs MoveGuidanceOnTouch, Levels Tutorial block, stylua/selene/luau_check rc 0
re-review: concern (sonnet): the `grabbed` set keyed by pooled step parts was never pruned, so a recycled part could stay excluded; checked: the diff, GrabTarget, WorldConfig, GameServer pool and RunState code, stylua/selene/luau_check rc 0 — repaired by the orchestrator (prune entries whose Parent or LaneUserId changed each poll), stylua/selene/luau_check rc 0, then the Studio run above
studio: Hot Frog (placeId: 114911935371092)
leftover: none
owed: none

## b-20261017-123841-69yo  fixed  2026-10-17 13:00
note: redo the tutorial tree so it's higher fidelity and the acorns look like they're hanging off it. it should be in front of the frog
cause: The tree was two 256 px black silhouettes (branch3/branch2) stretched over a ~40-stud canvas (~6 px/stud, hence blurry), drawn as an overlapping pair centred on each acorn at Z -2/-1.5, so it sat behind the acorns and the frog and nothing connected it to the acorns.
change: A new flat-cartoon oak drawn with PIL as three 1024 px tiles (Sprites/Scenery/TutorialTreeTop/Mid/Trunk.png, ~43 px/stud, uploaded through the pipeline) around the acorns' rest points, each branch ending in a twig that runs under its acorn; WorldTutorialTrunk.client.luau now draws one tree per lane (4 transparent 24x24 tile parts named TutorialTree, Trunk tile repeated below) placed each Heartbeat at the mean of (acorn position - rest point), and destroys it when the lane's acorns are gone. It sits at Z -0.225: in front of the frog's head and body art, behind its arms, hands and the acorns, so grab targets stay visible (the reading of "in front of the frog"). Step positions, sizes and grab boxes unchanged; doc 17 got a deviation row.
files: src/client/WorldTutorialTrunk.client.luau, src/shared/SkinAssets.luau, Sprites/Scenery/TutorialTreeTop.png, Sprites/Scenery/TutorialTreeMid.png, Sprites/Scenery/TutorialTreeTrunk.png, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check (ok), selene src/ (0 warnings), bash tools/luau_check.sh (rc 0), rojo build (ok); upload: TutorialTreeTop 89761876303726 and TutorialTreeMid 75319101709073 Approved, TutorialTreeTrunk 120304099926155 Reviewing (Green); PIL preview C:/Users/Tristan/.claude/jobs/516adbeb/tmp/preview.png checked
verified: partly — Studio Play run (StartRun "Tutorial"): 4 TutorialTree tiles at Z -0.225 with the Top/Mid/Trunk decals (Face Back, camera at +Z), acorn offsets from the Mid tile exactly (±4.82, -3.14/15.71/25.0) at rest and within 0.6 studs through three grabs and pulls, no old branch parts, tiles destroyed once the acorns were recycled in Pot; frog Head -0.3, BodyArt -0.25, arms -0.2, hands +0.3 confirm the layering. Not seen: the art itself, since Roblox was still generating the three new images ("Asset content representation is being generated") and screen_capture shows no 3D in Play; held by the owed look.
review: looks-right (sonnet); checked: diffs of the script, SkinAssets and doc 17, old script, Levels/Lane Tutorial placement (rest points match after clamp and view rescale), GameServer pooling/slideIn/teardown, FrogModel.model.json Z values, other client Z layers, branch2/3 grep, stylua/selene/luau_check clean; notes: a held acorn's recoil nudges the whole tree by 1/n; ACORN_AT must follow any change to the Tutorial movements (commented)
studio: Hot Frog (placeId: 114911935371092)
leftover: the acorns still idle-spin (owner ruling b-20260922-194446); the twigs read as attached anyway
owed: Play the Tutorial in Studio and look at the new oak (taste)
owed: o-20261017-130041-mozs
leftover: none — the unseen art is covered: the owner played the Tutorial with the new oak and marked o-20261017-130041-mozs done 2026-10-17 13:33

## b-20261017-133204-k24p  fixed  2026-10-17 13:52
note: the sparkle needs to go back to the first acorn if the player falls during the tutorial
cause: A Tutorial fall is a retry (GameServer tutorialRetry), not a run end, so RunState never changed and WorldTutorialSpecks kept its `grabbed` set; the sparkles stayed on acorns 2/3 or flew off instead of returning to acorn 1.
change: tutorialRetry bumps a `TutorialRetries` counter attribute on the lane folder; WorldTutorialSpecks clears the lane's `grabbed` set when it changes, so the next poll targets the nearest acorn again (acorn 1 after the retreat pull).
files: src/server/GameServer.server.luau, src/client/WorldTutorialSpecks.client.luau
test: stylua --check (ok), selene src/ (0 warnings), bash tools/luau_check.sh on both (rc 0), rojo build (ok)
verified: yes — Studio Play run (StartRun "Tutorial"): sparkles 0.0 studs from acorn 1 at start, 0.2 from acorn 2 after grabbing acorn 1; after releasing into a fall, TutorialRetries=1 with RunState still Playing and the sparkles 0.1 from acorn 1 (21.0 from acorn 2).
review: looks-right (sonnet); checked: both diffs, tutorialRetry and its pullLane retreat, WorldTutorialSpecks grabbed/prune/poll flow, GrabTarget.limbHeldPosition; note (non-blocking): a limb still easing back in the first poll after the retry could in theory re-mark a step, which the next retry or a grab corrects
studio: Hot Frog (placeId: 114911935371092)
leftover: none
owed: none

## b-20261017-133220-hfup  fixed  2026-10-17 13:52
note: the fire and steam shouldn't appear until the player has fully finished the tutorial
cause: The Level flips to Pot when the 3rd tree is climbed, and WorldLava/PotAtmosphere keyed the hot lava and steam off Level alone, but the player is still in Tutorial grace (falls retry) until the first real Pot step is grabbed. No exact recall match; related earlier fix b-20261010-191757-89n1.
change: Lane replicates `TutorialGrace` (= tutorialGraceActive) on the lane folder, set in Lane.new and resetRun and cleared in onStepClimbed. WorldLava's new isHot() needs Pot and no grace for the heat colour, PotHeat, surge and embers, and re-runs setHeat when grace clears; PotAtmosphere enables the steam emitter only without grace. Cosmetic only; the lava death line is unchanged. Doc 17 got a deviation row.
files: src/server/Lane.luau, src/client/WorldLava.client.luau, src/client/PotAtmosphere.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check (ok), selene src/ (0 warnings), bash tools/luau_check.sh on the three scripts (rc 0), rojo build (ok)
verified: yes — Studio Play run (StartRun "Tutorial", climbed the 3 trees): with Level=Pot and TutorialGrace=true, PotSteam Enabled=false, lava colour (0.549, 0.157, 0.078) cool, LavaSwell transparency 1, unchanged 3 s later; after grabbing a Pumpkin, TutorialGrace=false, steam Enabled=true, lava (0.733, 0.235, 0.094) then (1, 0.353, 0.118), swell transparency 0.72 then 0.30.
review: concern (sonnet): PotAtmosphere was unchanged, so the steam still showed during grace (the fixer's edit had silently missed); checked: the diff, Lane grace code, WorldLava heat/surge/embers, PotAtmosphere, LevelClient attributes
re-review: looks-right (sonnet); checked: PotAtmosphere line 190 now gates steam.Enabled on TutorialGrace each PreRender, the rest of the diff unchanged, stylua/selene/luau_check rc 0
studio: Hot Frog (placeId: 114911935371092)
leftover: none
owed: none

## b-20261017-133312-vqnu  fixed  2026-10-17 13:52
note: if a player clicks at a spot with a fly *and* a step, the frog should both eat the fly *and* grab the step
cause: GameClient tryGrab returned as soon as tryCatchBug hit a fly, so a tap over a fly and a step only ate the fly and never grabbed.
change: tryGrab catches the fly and carries on to the step hit-test; with a step it grabs as usual, and with no step a catch alone returns nil without the miss sound or empty reach (as before). The Menu-screen path is unchanged.
files: src/client/GameClient.client.luau
test: stylua --check (ok), selene src/ (0 warnings), bash tools/luau_check.sh (rc 0), rojo build (ok)
verified: yes — Studio Play run (Normal run, a fly pinned server-side 1 stud in front of an UpLeftRock): one real left click (user_mouse_input) on the rock put CatchBug and GrabStep(limb 2) on the server in the same frame, BugCaught came back to the client (count 1), the left limb sat 0.0 studs from the rock and the fly respawned (Gen bumped). The fly-only no-miss-X branch was not clicked; it is the pre-existing behaviour, kept by the `caught` check (review).
review: looks-right (sonnet); checked: the diff, tryCatchBug raycast include list (Bugs only), stepAt HitSize test, InputBegan/heldByInput flow, Menu path, gamepadTongue, server CatchBug/GrabStep handlers
studio: Hot Frog (placeId: 114911935371092)
leftover: none
owed: none

## b-20261019-032005-wkiu  fixed  2026-10-20 20:13
note: Feature: Once a Play check passes in the owner's Studio, the loop accepts (or re-owes with the current `tools/studio_ready.sh` check) every older "open Studio" or "switch rojo serve" step whose done-check is the retired window-title match (lesson from the reading brief 2026-10-18)
cause: Five owed steps (o-20261015-100456-yqw2, o-20261015-100656-nw90, o-20261016-120238-gmyn, o-20261016-120554-lf1c, o-20261016-120554-5vc2) were closed by the user over a failing `MainWindowTitle -match 'Hot Frog'` done-check and stayed in every loop report as "closed on a failing check", though Studio Play checks have passed in Hot Frog since (2026-10-17 13:52, b-20261017-133312-vqnu).
change: Accepted all five with `bugloop.py owe <o-id> --accept` (reason cites the 2026-10-17 Play pass and `tools/studio_ready.sh`), and added the rule to .bugs/README.md (Verification): owed Studio/Rojo steps use `bash tools/studio_ready.sh` as the done-check, and stale title-match steps are accepted or re-owed after the next passing Play check. The `pending` warning half is the skill script's, filed on the bugloop list as b-20261020-201213-yd36.
files: .bugs/README.md, .bugs/owed.md
test: none
verified: yes — `bugloop.py owe --accept` reported each of the five accepted ("the loop report no longer lists it"); `grep -c '^accepted:' .bugs/owed.md` shows the lines on the blocks.
review: n/a
enforced-by: none in this repo; the `pending` warning on title-match done-checks is b-20261020-201213-yd36 on the bugloop list
followups: b-20261020-201213-yd36

## b-20261020-200915-5ju4  fixed  2026-10-20 20:51
note: Feature: endless outdoor area and space area (design: .bugs/attachments/b-20261020-200915-5ju4-1.md) — outdoor area after the kitchen window with trees and cars, then an endless low-gravity Space level.
cause: Ruling b-20261020-201705-zwi7: "1, but let's give it a new background; 2 space at a step threshold, 250; 3) yes; 4) generate with ludo. try to match my sprite style as closely as possible". Country was the last, endless level with no trees, cars or background of its own, and there was no Space level or low gravity.
change: Country is now the outdoor area with grabbable TreeTrunk steps, CarRight/CarLeft steps that drive on fixed rows, wrap, and force-release the frog's limb on them after 1.2 s (never a direct death), and a new CountryBack backdrop. A new endless Space level starts at 250 steps (Config.LEVEL_THRESHOLDS) with Asteroid steps, a SpaceBack backdrop, and gravity easing to 20% over 8 steps (Config.SPACE_GRAVITY_SCALE / SPACE_GRAVITY_TRANSITION_STEPS, Lane:gravityScale). HUD landmark, badge rank, a "Space Frog" badge entry (id 0, like every other badge until tools/create_badges.py runs), tips and docs 05/13/17 updated. Six sprites made with Ludo AI, uploaded with the asset pipeline (all Approved/Green), ids written by tools/write_asset_ids.py.
files: src/shared/Config.luau, src/server/Lane.luau, src/server/GameServer.server.luau, src/shared/StepBehaviors.luau, src/shared/StepKinds.luau, src/shared/Levels.luau, src/shared/SkinAssets.luau, src/client/WorldBackdrop.client.luau, src/client/GameClient.client.luau, src/client/Music.client.luau, src/client/WorldFrogCosmetics.client.luau, src/server/BadgeService.server.luau, src/shared/Badges.luau, src/shared/Tips.luau, docs/roblox-port/05-step-behaviors.md, docs/roblox-port/13-levels-and-lanes.md, docs/roblox-port/17-status-and-known-gaps.md, Sprites/Rocks/TreeTrunk.png, Sprites/Rocks/CarRight.png, Sprites/Rocks/CarLeft.png, Sprites/Rocks/Asteroid.png, Sprites/Other/CountryBack.png, Sprites/Other/SpaceBack.png
test: stylua --check pass on all 14 .luau; tools/luau_check.sh clean on each; selene src/ 0 errors 0 warnings; rojo build pass; Lane.gravityScale in the Server datamodel 1.00/0.80/0.60/0.20/0.20 at 0/2/4/8/20 steps into Space, 1 in Country.
verified: partly — Studio Play with a client bot on the real remotes (Normal mode): Pot -> Kitchen at 53, Country at 100, Space at 250 with 0 deaths; TreeTrunk, CarLeft, CarRight and Asteroid grabbed; a held CarRight was force-released after 1.23 s and the run stayed Playing; CarRight moved ~2.5 studs/s; in Space the frog fell 9.9 studs in 3 s against ~38 at normal gravity, then died in the lava and the run went Dead -> Menu; console had no script errors. Not seen: CountryBack in game (the October Halloween overlay and Daily Streak popup covered it), and 4 players at 60 FPS.
review: looks-right; checked: git diff of Config, Lane, GameServer, StepBehaviors, StepKinds, Levels, SkinAssets; read ctxOf, forceReleaseStep, releaseStep, the Heartbeat step loop and frog fall code; grepped src/ for Country, Kitchen, LEVEL_THRESHOLDS, CLASSIC_SCROLL_SPEED, LEVEL_RANK, MissionService. Noted for play: a knock-off with the other hand empty lets the frog fall (it can still reach the lava); a held car drags the limb up to ~4 studs sideways during the hold; Space has no scenery spawners or patterns and may look sparse.
studio: Hot Frog (placeId 114911935371092); the fixer started Play and stopped it.
owed: o-20261020-205042-fnwn (taste: look over the new art and car/Space feel)
leftover: b-20261020-205042-kryx (Studio check that CountryBack/SpaceBack render, once October's Halloween theme is off); 4-player / 60 FPS: none — the Studio MCP cannot start a multiplayer session or measure frame rate from this host.

## b-20261020-201705-zwi7  answered  2026-10-20 20:51
note: DECISION: 1, but let's give it a new background; 2 space at a step threshold, 250; 3) yes; 4) generate with ludo. try to match my sprite style as closely as possible
cause: The owner's ruling on b-20261020-200915-5ju4.
change: see b-20261020-200915-5ju4
files: none
test: none
verified: see b-20261020-200915-5ju4
review: n/a

## b-20261020-205151-b1ob  answered  2026-10-20 20:53
note: show me (sent back from owed step o-20261020-205042-fnwn: look over the new Ludo art and car/Space feel, for b-20261020-200915-5ju4)
cause: The owner wanted to see the new art before judging it.
change: Sent the six new sprites (Sprites/Rocks/TreeTrunk.png, CarRight.png, CarLeft.png, Asteroid.png, Sprites/Other/CountryBack.png, SpaceBack.png) to the owner's session, and filed the taste review as question b-20261020-205326-jmsu with the six images attached, so it shows on the dashboard with the pictures.
files: none
test: none
verified: yes — SendUserFile delivered all six images; bugloop.py ask filed b-20261020-205326-jmsu with the attachments.
review: n/a
followups: b-20261020-205326-jmsu

## b-20261020-205326-jmsu  fixed  2026-10-20 21:15
note: Here is the new Ludo art for the outdoor Country and Space (b-20261020-200915-5ju4): TreeTrunk, CarRight, CarLeft, Asteroid steps and the CountryBack/SpaceBack backdrops. Do they fit your sprite style?
cause: Ruling b-20261020-205449-vnng: "this works. use the trees from tutorial too" — the Ludo art is accepted as is, and Country should also use the Tutorial's tree art.
change: Added an OakTree step kind in src/shared/StepKinds.luau (static climbable trunk, behaviour None, weight 0.4) reusing the uploaded TutorialTreeMid sprite at 12 studs with a ~2.2-stud trunk hit box, appended to OUTDOOR_KINDS in src/shared/Levels.luau so it spawns in Country's four pools beside TreeTrunk (not Space or earlier levels); noted in doc 17's Country row. Read "the trees from tutorial" as the oak as a climbable step; the Tutorial's acorn-and-tile oak (WorldTutorialTrunk) is anchored to its three acorns and is unchanged.
files: src/shared/StepKinds.luau, src/shared/Levels.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check pass; selene src/ 0 warnings; tools/luau_check.sh clean on StepKinds.luau and Levels.luau; rojo build pass; Edit-datamodel canary found OakTree in both scripts' .Source.
verified: partly — Studio Play: an OakTree step spawned in Country with the right texture (rbxassetid 75319101709073, Sprite=TutorialTreeMid, 12x12x1) and a screenshot shows the oak trunk with a leaf twig; Country was reached by lowering Config.LEVEL_THRESHOLDS in the Server datamodel at runtime only (bot kept dying in Pot); the oak was not grabbed or climbed.
review: looks-right; checked: git diff of the three files; read TreeTrunk, Tutorial tree kinds and OakTree in StepKinds, OUTDOOR_KINDS/withOutdoor/withDynamic and the Space pools in Levels, SkinAssets Ids; confirmed withOutdoor feeds only Country's four pools and TutorialTreeMid's id resolves; measured TutorialTreeMid.png trunk column (~440-590 of 1024 px, near centre). Cosmetic risk noted: the 12-stud leafy sprite overhangs its 2.2-stud hit box.
studio: Hot Frog (placeId 114911935371092); the fixer started Play and stopped it; runtime threshold edits were in memory only.
leftover: b-20261020-211557-qfs4 (grab and climb an OakTree in Country Play)

## b-20261020-205449-vnng  answered  2026-10-20 21:15
note: DECISION: this works. use the trees from tutorial too
cause: The owner's ruling on b-20261020-205326-jmsu.
change: see b-20261020-205326-jmsu
files: none
test: none
verified: see b-20261020-205326-jmsu
review: n/a

## b-20261020-211557-qfs4  fixed  2026-10-20 21:36
note: Studio Play check for b-20261020-205326-jmsu: grab and climb an OakTree in Country, try a grab on the leaves, check the leaves don't overlap other steps.
cause: Verification only. The OakTree step works as built: the server accepts a trunk grab, pulls the step, and the run carries on.
change: none (verification only)
files: none
test: none
verified: partly. A bot reached Country naturally at ~100 score. It grabbed an OakTree at its trunk, the server pulled the step from (15.4, 17.4) to (2.9, -2.1) lane-relative, and RunState stayed Playing for ~40 more grabs with the score rising. A GrabStep fired at Position + 4 studs X (on the leaves) was also accepted: GameServer uses the tap point only for grab quality (PullMath.gradeGrab), so the trunk-only hit box is a client-side hit test, as for every step kind. Leaf overlap was not judged: screen_capture stayed zoomed on the frog and showed only trunk edges with a few twigs. Runtime threshold edits from execute_luau did not reach the live Lane modules, so none were made or saved.
review: n/a
studio: Hot Frog (placeId 114911935371092); canary found "OakTree" in StepKinds .Source; the checker started Play and stopped it; console clean apart from CorePackages UIBlox warnings.
leftover: b-20261020-213634-p1sp (full-lane leaf-overlap look, after the txe8 skip-ahead tool lands)

## b-20261020-213335-g57k  fixed  2026-10-20 21:42
note: remove the detailing from the ghosts and jack o lanterns to more closely match the "blurred" look of carrots, potatoes, etc
cause: Sprites/Scenery/Ghost.png and JackOLantern.png (port-made in 7e3db63) were flat vector art with thick dark outlines, hard cel shapes and crisp faces, while Carrot.png and Potato.png are soft airbrushed paintings with no outlines.
change: Redrew both 512 px sprites procedurally in PIL on the same footprints (the pumpkin keeps Potato's canvas area for the Pumpkin step): heavily blurred layered shapes, soft shading and highlight, no outlines, no halo; the ghost keeps a soft blurred face and scalloped hem, the jack-o'-lantern a blurred glowing face. Uploaded both through tools/upload_to_roblox.py (changed hash, so new ids) and ran tools/write_asset_ids.py: Ghost 99143787431972, JackOLantern 135228146455303 in src/shared/SkinAssets.luau. tools/write_asset_ids.py now writes LF (newline="\n"); on Windows it wrote CRLF, which fails stylua --check (stylua.toml line_endings Unix).
files: Sprites/Scenery/Ghost.png, Sprites/Scenery/JackOLantern.png, src/shared/SkinAssets.luau, tools/write_asset_ids.py
test: stylua --check SkinAssets.luau pass; selene src/ clean; tools/luau_check.sh SkinAssets.luau clean; rojo build pass.
verified: partly — a comparison sheet (carrot, potato, old/new ghost, old/new pumpkin) was checked and sent to the owner; the Edit-datamodel canary found both new ids in SkinAssets .Source. Not seen in Play (another fixer held Studio Play) and moderation of the new images was not confirmed.
review: looks-right; checked: git show 0516a4c; SkinAssets diff is only the two ids and they match tools/asset_ids.json (both moderation Approved, automated Green); committed SkinAssets.luau has no CR; read rewrite_file in tools/write_asset_ids.py (newline="
" covers both generated files, line-ending-only differences still count as unchanged); PIL on old vs new PNGs: 512x512 RGBA, pumpkin opaque bbox (62,87)-(450,429) -> (70,90)-(446,433), ghost ~6% shorter; cosmetic note: the ghost's body sides keep a fairly crisp edge.
studio: Hot Frog (placeId 114911935371092); Edit-datamodel canary only; this check started no Play (Studio was in Edit), so none to stop: Play stopped.
leftover: b-20261020-214145-hx6a (render check in Play with ForceHalloween)
