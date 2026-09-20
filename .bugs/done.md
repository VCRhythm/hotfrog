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
