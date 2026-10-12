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

## b-20261010-192146-ml2d  fixed  2026-10-12 15:00
note: kitchen needs equally groovy music as pot
cause: Kitchen had Unity's musicIndex 1, FrogSounds.wav: the same track as the Menu and Tutorial, quiet (RMS 0.07) and almost beatless (beat-pulse strength 0.10 by a spectral-flux autocorrelation of the Unity files), while Pot plays BrusselSprouts.wav (pulse 0.61, RMS 0.16).
change: Kitchen musicIndex 1 -> 3 (music4 = Adenine.mp3, already uploaded and unused by the base game; pulse 0.68, RMS 0.18, no silent intro, a short quiet break around 80-100 s). Comment in Levels.luau and Music.client.luau, plus a doc 17 "Kitchen music" deviation row. Opening.mp3 (music3, pulse 0.76) was passed over because it reads as a title/intro track; Two Wrongs is Country's. The owner can swap the index if Adenine isn't the right feel.
files: src/shared/Levels.luau, src/client/Music.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check and tools/luau_check.sh on both .luau files (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.)
review: looks-right. checked: the LevelChanged -> LevelClient -> Music.client path to music4 (non-zero id), every musicIndex consumer (WorldBackdrop ignores it), Pot->Kitchen crossfade and arrival-sting delay unaffected, the other tracks as alternatives, the comments and doc row.
leftover: b-20261012-150058-oxtf (Studio playtest once Studio runs)

## b-20261010-192336-pgwh  fixed  2026-10-12 15:03
note: make space for a "tips" section after a run is over
cause: Feature request: the end-of-run panel had no room or content for tips (Unity has none either).
change: New Shared/Tips.luau: 13 tips, each checked against the code it cites (grab grades, the death rule, Crumble/CrumbleAfterRelease/Fall steps, arrows, bug and golden-bug Flys, Skittish bugs, the Shop, the pot rim at 50 steps and Country at 100, the Chef's tells), and Tips.pick(previous), which never repeats the last tip. MenuClient's end-of-run panel grew 404 -> 496 high with a divider, a "TIP" header and a wrapped tip label (max 18 pt) under Top Scores. A new tip is rolled only for a new RunSummary, so opening and closing Top Scores/Settings keeps it. The orchestrator reworded the level tip to name the pot rim (Kitchen starts on the rim grab once past 50 steps). Doc 17 has a "Post-run Tips section" row.
files: src/shared/Tips.luau, src/client/MenuClient.client.luau, docs/roblox-port/17-status-and-known-gaps.md
test: stylua --check and tools/luau_check.sh on Tips.luau and MenuClient (0 errors), selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.)
review: looks-right; minor: "after 50 steps" for the Kitchen is loose, since it starts on the pot-rim grab (the orchestrator reworded that tip). checked: every tip against Config, PullMath, StepBehaviors, StepKinds, Lane (onStepClimbed, atPotTop), GameServer frog sim and grading, BugService, Chef.luau and StoreUI; the end-panel layout, UIKit scale floor and text sizing; the showEndPanel/restoreMainPanels/RunSummary tip logic; Tips.pick; stylua and luau_check.
leftover: b-20261012-150254-scgv (Studio playtest once Studio runs)

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

## b-20261012-143703-olbq  fixed  2026-10-12 15:07
note: WorldChef draws the knife/potato on a recycled step
cause: During the Strike follow-through WorldChef kept its target as long as the Part was still in the Steps folder. A pooled step re-acquired by the server (GameServer acquireStep bumps Gen, clears ChefTarget and sets LaneUserId) stays in the folder, so the chef could keep drawing on a step that was now a new spawn, or another player's lane's step.
change: WorldChef records the target's Gen (view.targetGen) when findTarget resolves it, and the Strike branch drops the target when it left the folder, its Gen changed, or its LaneUserId no longer matches the lane folder's UserId.
files: src/client/WorldChef.client.luau
test: stylua --check, tools/luau_check.sh, selene src/ (0 errors), rojo build to %TEMP%: all pass
verified: no — Studio MCP not attached and Studio not running, so no playtest was possible this tick; static checks only. (Studio is open, but only the Centralia place is attached to the MCP, not hotfrog.)
review: looks-right; minor: the dropped target is only cleared locally, so view.target stays stale and is re-dropped every frame of the Strike (harmless, and clearing it would allow a mid-Strike rescan, so it was left). checked: the WorldChef diff, update(), findTarget, every view.target/targetGen write, the View type and initialiser, acquireStep and the release path in GameServer (685-715), the ChefTarget sites in Chef.luau.
leftover: b-20261012-150755-783q (Studio playtest once Studio runs)

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
