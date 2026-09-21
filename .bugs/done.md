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
