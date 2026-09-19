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
